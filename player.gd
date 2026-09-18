extends CharacterBody3D

const CharacterStep := preload("res://addons/character_step/character_step.gd")


enum MovementState {
	IDLE,
	WALKING,
	RUNNING,
	AIRBORNE
}


# ─────────────────────────────
# 节点
# ─────────────────────────────

@onready var head: Node3D = $Head                                      # 左右视角
@onready var camera: Camera3D = $Head/Camera3D                        # 上下视角
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var interaction_ray: RayCast3D = $Head/Camera3D/InteractionRay  # 视线交互检测
@onready var interaction_prompt: Control = $UI/InteractionPrompt     # 交互提示容器
@onready var interaction_label: Label = $UI/InteractionPrompt/Label # 交互提示文字


# ─────────────────────────────
# 移动参数
# ─────────────────────────────
@export_group("Movement")

@export var walk_speed: float = 3.0          # 走路速度
@export var run_speed: float = 6.0           # 奔跑速度
@export var jump_velocity: float = 4.5       # 跳跃力度
@export var acceleration: float = 15.0       # 起步加速度
@export var deceleration: float = 20.0       # 停止减速度
@export var max_step_up: float = 0.55        # 可走上的最大台阶高度
@export var max_step_down: float = 0.55      # 可走下的最大台阶高度


# ─────────────────────────────
# 视角参数
# ─────────────────────────────

@export_group("Camera")

@export var mouse_sensitivity: float = 0.001 # 鼠标灵敏度
@export var max_look_angle: float = 89.0     # 最大抬头 / 低头角度
@export var step_camera_smooth: float = 16.0 # 上台阶后相机回落速度，越大越快


# ─────────────────────────────
# 交互参数
# ─────────────────────────────

@export_group("Interaction")

@export var interaction_text: String = "E 交互"  # 默认交互提示


# ─────────────────────────────
# 运行状态
# ─────────────────────────────

var current_state: MovementState = MovementState.IDLE

var move_direction: Vector3 = Vector3.ZERO   # 当前移动方向
var wants_to_run: bool = false               # 是否按住 Shift
var was_on_floor: bool = false               # move_and_slide 前是否在地面
var current_interactable: Node = null        # 当前正在看的可交互对象
var _head_rest_y: float = 0.0                # Head 的默认局部高度
var _step_camera_offset_y: float = 0.0       # 台阶瞬移时的相机高度补偿



# ═════════════════════════════
# 生命周期
# ═════════════════════════════

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)  # 锁定鼠标
	interaction_ray.add_exception(self)              # 射线不要打到自己的碰撞体
	interaction_prompt.hide()                        # 开局隐藏交互提示
	_head_rest_y = head.position.y                   # 记下眼睛默认高度
	floor_snap_length = maxf(floor_snap_length, 0.2)


func _physics_process(delta: float) -> void:
	was_on_floor = is_on_floor()
	read_movement_input()                            # 读取移动输入
	apply_vertical_motion(delta)                     # 跳跃 / 重力
	apply_horizontal_motion(delta)                   # 水平移动

	var y_before := global_position.y
	var stepped_up := try_step_up()                  # 上台阶：在撞墙之前抬脚
	move_and_slide()                                 # 执行移动和碰撞
	var stepped_down := false
	if not stepped_up:
		stepped_down = try_step_down()               # 下台阶：离地后再贴地
	if stepped_up or stepped_down:
		finish_step()
		absorb_step_height(global_position.y - y_before)
	elif velocity.y <= 0.0:
		apply_floor_snap()

	tick_step_camera(delta)
	update_movement_state()                          # 更新移动状态
	update_interaction()                             # 更新交互目标


func _unhandled_input(event: InputEvent) -> void:
	handle_mouse_look(event)                         # 鼠标视角
	handle_mouse_capture(event)                      # 鼠标释放 / 捕获

	if event.is_action_pressed("interact"):
		try_interact()                                # E 键交互



# ═════════════════════════════
# 视角
# ═════════════════════════════

func handle_mouse_look(event: InputEvent) -> void:
	if not event is InputEventMouseMotion:
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	head.rotate_y(-event.relative.x * mouse_sensitivity)       # 左右看
	camera.rotate_x(-event.relative.y * mouse_sensitivity)     # 上下看

	camera.rotation.x = clamp(
		camera.rotation.x,
		deg_to_rad(-max_look_angle),
		deg_to_rad(max_look_angle)
	)


func handle_mouse_capture(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)          # ESC 释放鼠标
		return

	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
		and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)         # 左键重新捕获鼠标



# ═════════════════════════════
# 移动
# ═════════════════════════════

func read_movement_input() -> void:
	var input_2d := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)

	var direction: Vector3 = (
		head.global_transform.basis
		* Vector3(input_2d.x, 0.0, input_2d.y)
	)

	direction.y = 0.0

	move_direction = direction.normalized()                    # 转成水平 3D 方向
	wants_to_run = Input.is_action_pressed("run")              # Shift 状态


func apply_vertical_motion(delta: float) -> void:
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity                          # Space 跳跃
	else:
		velocity += get_gravity() * delta                       # 空中应用重力


func apply_horizontal_motion(delta: float) -> void:
	var target_speed: float = walk_speed

	if wants_to_run:
		target_speed = run_speed

	var target_velocity: Vector3 = move_direction * target_speed

	if move_direction != Vector3.ZERO:
		velocity.x = move_toward(
			velocity.x,
			target_velocity.x,
			acceleration * delta
		)

		velocity.z = move_toward(
			velocity.z,
			target_velocity.z,
			acceleration * delta
		)

	else:
		velocity.x = move_toward(
			velocity.x,
			0.0,
			deceleration * delta
		)

		velocity.z = move_toward(
			velocity.z,
			0.0,
			deceleration * delta
		)


func _capsule_radius() -> float:
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule == null:
		return 0.4
	return capsule.radius


func _origin_from_feet() -> float:
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule == null:
		return 1.0
	return collision_shape.position.y + capsule.height * 0.5


func _horizontal_velocity() -> Vector3:
	return Vector3(velocity.x, 0.0, velocity.z)


func _should_step_up(direction: Vector3) -> bool:
	if direction.is_zero_approx():
		return false

	var start := global_position - Vector3(0.0, _origin_from_feet(), 0.0)
	var radius := _capsule_radius()
	var width := radius * 0.5
	var full_width := width + radius
	var space := get_world_3d().direct_space_state
	var exclude: Array = [get_rid()]

	var center := CharacterStep.snapped_intersect_ray(space, start, direction, full_width, false, exclude)
	var left := CharacterStep.snapped_intersect_ray(
		space,
		start + direction.rotated(Vector3.UP, deg_to_rad(90.0)).normalized() * width,
		direction,
		full_width,
		false,
		exclude
	)
	var right := CharacterStep.snapped_intersect_ray(
		space,
		start + direction.rotated(Vector3.UP, deg_to_rad(-90.0)).normalized() * width,
		direction,
		full_width,
		false,
		exclude
	)

	if center.has("normal"):
		return center.normal.angle_to(Vector3.UP) > floor_max_angle
	if left.has("normal"):
		return left.normal.angle_to(Vector3.UP) > floor_max_angle
	if right.has("normal"):
		return right.normal.angle_to(Vector3.UP) > floor_max_angle
	if center.has("error") and left.has("error") and right.has("error"):
		return get_floor_normal().angle_to(Vector3.UP) <= floor_max_angle
	return false


func absorb_step_height(delta_y: float) -> void:
	if absf(delta_y) < 0.001:
		return
	_step_camera_offset_y -= delta_y
	_apply_head_offset()


func tick_step_camera(delta: float) -> void:
	if delta > 0.0:
		var weight := 1.0 - exp(-step_camera_smooth * delta)
		_step_camera_offset_y = lerpf(_step_camera_offset_y, 0.0, weight)
	_apply_head_offset()


func finish_step() -> void:
	velocity.y = 0.0


func _apply_head_offset() -> void:
	if head == null:
		return
	head.position.y = _head_rest_y + _step_camera_offset_y


func try_step_up() -> bool:
	if move_direction.is_zero_approx():
		return false
	if velocity.y > 0.0:
		return false
	if not was_on_floor and not is_on_floor():
		return false
	if not _should_step_up(move_direction):
		return false

	var step := CharacterStep.step_up(
		get_rid(),
		global_transform,
		max_step_up,
		move_direction,
		_capsule_radius() * 0.5,
		0.12
	)
	if step.is_empty():
		return false
	if step["normal"].angle_to(Vector3.UP) > floor_max_angle:
		return false

	global_position.y = step["point"].y + _origin_from_feet()
	return true


func try_step_down() -> bool:
	if is_on_floor():
		return false
	if velocity.y > 0.0:
		return false
	if not was_on_floor:
		return false

	var ground_ok := func(_point: Vector3, normal: Vector3) -> bool:
		return normal.angle_to(Vector3.UP) <= floor_max_angle

	var step := CharacterStep.step_down(
		get_rid(),
		global_transform,
		max_step_down,
		_horizontal_velocity().normalized(),
		_capsule_radius(),
		ground_ok
	)
	if step.is_empty():
		return false

	global_position.y = step["point"].y + _origin_from_feet()
	return true


# ═════════════════════════════
# 移动状态
# ═════════════════════════════

func update_movement_state() -> void:
	if not is_on_floor():
		current_state = MovementState.AIRBORNE

	elif move_direction == Vector3.ZERO:
		current_state = MovementState.IDLE

	elif wants_to_run:
		current_state = MovementState.RUNNING

	else:
		current_state = MovementState.WALKING



# ═════════════════════════════
# 交互
# ═════════════════════════════

func update_interaction() -> void:
	current_interactable = find_interactable()                  # 更新眼前目标

	if current_interactable == null:
		interaction_prompt.hide()
		return

	if current_interactable.has_method("get_interaction_text"):
		interaction_label.text = String(current_interactable.call("get_interaction_text"))
	else:
		interaction_label.text = interaction_text
	interaction_prompt.show()


func try_interact() -> void:
	if current_interactable == null:
		return

	current_interactable.call("interact")                       # 让目标自己执行交互


func find_interactable() -> Node:
	if not interaction_ray.is_colliding():
		return null

	var node: Node = interaction_ray.get_collider() as Node

	while node != null:
		if node.has_method("interact"):
			return node                                         # 找到拥有 interact() 的节点

		node = node.get_parent()                                # 没有就继续向父节点寻找

	return null
