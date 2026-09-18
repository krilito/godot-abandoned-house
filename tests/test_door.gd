@tool
extends McpTestSuite

## Casa/Puerta 的门动画数据 + door.gd 开关状态机回归测试（编辑器层）。
## door.gd 不是 @tool 脚本，场景里的 Collision_Puerta 在编辑器中只是 placeholder，
## 所以状态机用 door.gd 的真实实例 + 场景里的真实 open 动画搭一套等价 rig 来跑。
## 锁相关只覆盖不需要查库存的分支，其余锁用例在真实运行的游戏里跑（见 lock_runtime_suite.gd）。

const CLOSE_ROTATION := Vector3(PI, 0.0, 0.0)      # Puerta 关闭时的真实欧拉角
const OPEN_ROTATION := Vector3(PI, PI / 2.0, 0.0)  # 绕 Y 轴 +90°：实测门板落在屋内一侧
const ANIM_LENGTH := 0.8
const OPEN_ANIMATION := "open"
const CLOSED_PROMPT := "E 关门"
const DOOR_SCRIPT := "res://scripts/door.gd"

var _mesh: Node3D
var _door: Node
var _anim: AnimationPlayer
var _floor: MeshInstance3D

var _rig_host: Node3D
var _rig_player: AnimationPlayer
var _rig_door: Node


func suite_name() -> String:
	return "door"


func setup() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var house: Node = (load("res://abandoned_house.tscn") as PackedScene).instantiate()
	track(house)
	tree.root.add_child(house)
	_mesh = house.get_node("Casa/Puerta")
	_door = _mesh.get_node("Collision_Puerta")
	_anim = _mesh.get_node("AnimationPlayer")
	_floor = house.get_node("Colision/Piso_001")
	_build_rig(tree)


# ─────────────────────────────
# 场景接线与动画数据
# ─────────────────────────────

func test_door_wiring() -> void:
	assert_true(_anim is AnimationPlayer, "Puerta 下必须有 AnimationPlayer")
	assert_ne(_mesh.get_child_count(), 0, "Collision_Puerta 应是 Puerta 的子节点")
	assert_eq(_door.get_parent(), _mesh, "门碰撞体必须保持父子关系（随门旋转）")
	assert_true(_door.get_script() != null, "Collision_Puerta 应挂有 door.gd")


func test_saved_animation_data() -> void:
	var anim: Animation = _anim.get_animation(OPEN_ANIMATION)
	assert_ne(anim, null, "open 动画必须存在于场景中")
	assert_true(is_equal_approx(anim.length, ANIM_LENGTH), "动画时长应为 0.8s")
	assert_eq(anim.loop_mode, Animation.LOOP_NONE, "不得循环播放")
	assert_eq(anim.get_track_count(), 1, "只允许一条动画轨道")
	assert_eq(str(anim.track_get_path(0)), ".:rotation", "轨道只修改 Puerta 自身旋转")
	assert_eq(anim.track_get_key_count(0), 2, "两个关键帧")
	assert_true(anim.track_get_key_value(0, 0).is_equal_approx(CLOSE_ROTATION), "首帧=当前关闭姿态")
	assert_true(anim.track_get_key_value(0, 1).is_equal_approx(OPEN_ROTATION), "末帧=Y 轴 +90°")
	assert_true(is_equal_approx(anim.track_get_key_time(0, 1), ANIM_LENGTH), "末帧在 0.8s")


func test_scene_starts_closed_without_autoplay() -> void:
	assert_true(_anim.autoplay.is_empty(), "AnimationPlayer 不得设置 autoplay")
	assert_true(_mesh.rotation.is_equal_approx(CLOSE_ROTATION), "初始旋转应为关闭姿态")


func test_scene_prompt_starts_as_open_hint() -> void:
	assert_eq(_door.get("interaction_text"), "E 打开门", "场景里的关闭态提示不得被改动")


func test_scene_door_is_configured_with_basement_key_lock() -> void:
	assert_eq(_door.get("is_locked"), true, "Casa/Puerta 开局必须是锁住的")
	assert_eq(_door.get("required_key"), "Basement Key", "解锁钥匙名必须与 key.gd 的 key_name 一致")
	assert_eq(_door.get("consume_key_on_unlock"), false, "当前设计：Basement Key 是普通钥匙，不消耗")


# ─────────────────────────────
# 锁（不触达 Inventory 的部分）
# ─────────────────────────────

## PlayerInventory 是 autoload，在编辑器 @tool 层只是 placeholder，调用它的方法会直接报错，
## 所以这里只能测“解锁流程在碰到 Inventory 之前就 fail closed”的那条分支。
## 需要真正查库存的用例（无钥匙 / 有钥匙 / 消耗型）在 tests/lock_runtime_suite.gd 里跑真实运行。
func test_locked_door_without_required_key_fails_closed() -> void:
	_rig_door.is_locked = true
	_rig_door.required_key = ""

	_rig_door.interact()

	assert_true(_rig_door.is_locked, "required_key 为空时不得解锁")
	assert_false(_rig_door.is_animating, "required_key 为空时不得进入动画")
	assert_false(_rig_door.is_open, "required_key 为空时不得开门")
	assert_false(_rig_door.target_open, "required_key 为空时目标状态不得被翻转")
	assert_false(_rig_player.is_playing(), "required_key 为空时不得播放动画")
	assert_eq(_rig_door.get_interaction_text(), "门锁住了", "配置缺失时应提示门锁着，而不是提示开门")


func test_unlocked_rig_door_has_no_lock_behaviour() -> void:
	assert_false(_rig_door.is_locked, "rig 门默认必须是无锁门")
	assert_eq(_rig_door.required_key, "", "无锁门不该配钥匙")
	assert_eq(_rig_door.get_interaction_text(), "E 打开门", "无锁门提示不受锁系统影响")
	_rig_door.interact()
	assert_true(_rig_door.is_animating, "无锁门必须直接进入开门动画")
	_finish_rig_animation()
	assert_true(_rig_door.is_open, "无锁门应能照常打开")


# ─────────────────────────────
# 开门方向
# ─────────────────────────────

## OPEN_ROTATION 这个常量本身不能自证方向，所以这里用引擎自己的变换矩阵算出
## 门板中心在关门 / 开门两个姿态下的世界位置，再和地板（屋内地面）的中心比符号。
func test_open_pose_swings_into_house() -> void:
	var leaf := _leaf_local_center()
	var hinge := _mesh.global_position
	var closed_center: Vector3 = _mesh.global_transform * leaf

	_anim.play(OPEN_ANIMATION)
	_anim.advance(ANIM_LENGTH + 0.2)
	assert_true(_mesh.rotation.is_equal_approx(OPEN_ROTATION), "open 播完应停在 OPEN_ROTATION")
	var opened_center: Vector3 = _mesh.global_transform * leaf

	var floor_box := _global_aabb(_floor)
	var inward := signf(floor_box.get_center().z - hinge.z)
	assert_ne(inward, 0.0, "地板中心与门铰链 z 相同，无法判定屋内外")
	var closed_radius := closed_center.distance_to(hinge)
	var opened_radius := opened_center.distance_to(hinge)
	assert_true(
		absf(opened_radius - closed_radius) < 0.001,
		"门板只能绕铰链旋转，不得飞离或改变大小（铰链距离 %s -> %s）" % [closed_radius, opened_radius]
	)
	assert_gt(
		(opened_center.z - closed_center.z) * inward,
		0.0,
		"门板必须朝屋内摆动（屋内方向 z 符号 %s，门板 z: %s -> %s）"
		% [inward, closed_center.z, opened_center.z]
	)


# ─────────────────────────────
# door.gd 状态循环
# ─────────────────────────────

func test_case1_first_interact_opens() -> void:
	assert_false(_rig_door.is_open, "初始必须关闭")
	assert_false(_rig_door.is_animating, "初始不得处于动画中")

	_rig_door.interact()

	assert_true(_rig_door.is_animating, "interact() 后应进入动画中")
	assert_false(_rig_door.is_open, "动画刚开始不得提前把 is_open 置真")
	assert_true(_rig_player.is_playing(), "open 应处于播放中")
	assert_eq(str(_rig_player.current_animation), OPEN_ANIMATION, "应播放 open 动画")

	_rig_player.advance(ANIM_LENGTH * 0.4)
	assert_gt(_rig_player.get_current_animation_position(), 0.0, "开门必须正向播放")
	assert_gt(_rig_host.rotation.y, CLOSE_ROTATION.y, "开门中途门应已离开关闭姿态")

	_finish_rig_animation()

	assert_true(_rig_door.is_open, "动画播完后 is_open 应为 true")
	assert_false(_rig_door.is_animating, "动画播完后 is_animating 应为 false")
	assert_true(_rig_host.rotation.is_equal_approx(OPEN_ROTATION), "门应停在开启姿态")


func test_case2_second_interact_closes() -> void:
	_open_rig()
	assert_true(_rig_door.is_open, "前置条件：门应已打开")

	_rig_door.interact()

	assert_true(_rig_door.is_animating, "关门应进入动画中")
	assert_true(_rig_door.is_open, "关门动画期间 is_open 仍是 true")
	assert_eq(str(_rig_player.current_animation), OPEN_ANIMATION, "关门必须复用同一条 open 动画")
	assert_true(_rig_player.is_playing(), "关门动画应在播放")

	# speed_scale 在 Godot 4.7 里不反映播放方向，所以用"播放位置倒退"来证明 play_backwards 生效。
	var position_before := _rig_player.get_current_animation_position()
	_rig_player.advance(ANIM_LENGTH * 0.4)
	assert_true(
		_rig_player.get_current_animation_position() < position_before,
		"关门必须用 play_backwards 反向播放（播放位置应从 %s 倒退）" % position_before
	)
	assert_true(
		_rig_host.rotation.y > CLOSE_ROTATION.y and _rig_host.rotation.y < OPEN_ROTATION.y,
		"关门中途门应处于半开姿态，当前 rotation.y = %s" % _rig_host.rotation.y
	)

	_finish_rig_animation()

	assert_false(_rig_door.is_open, "关门动画结束后 is_open 应为 false")
	assert_false(_rig_door.is_animating, "关门动画结束后 is_animating 应为 false")
	assert_true(_rig_host.rotation.is_equal_approx(CLOSE_ROTATION), "门应回到关闭姿态")


func test_case3_third_interact_reopens() -> void:
	_open_rig()
	_rig_door.interact()
	_finish_rig_animation()
	assert_false(_rig_door.is_open, "两次交互后应回到关闭")

	_rig_door.interact()
	var position_before := _rig_player.get_current_animation_position()
	_rig_player.advance(ANIM_LENGTH * 0.4)
	assert_gt(
		_rig_player.get_current_animation_position(),
		position_before,
		"第三次交互必须重新正向开门"
	)
	_finish_rig_animation()

	assert_true(_rig_door.is_open, "门必须能反复切换，而不是只跑一个周期")
	assert_true(_rig_host.rotation.is_equal_approx(OPEN_ROTATION), "重新开启的姿态应一致")


func test_case4_spam_during_opening_is_ignored() -> void:
	_rig_door.interact()
	_rig_player.advance(ANIM_LENGTH * 0.2)
	assert_true(_rig_player.is_playing(), "开门动画应仍在进行")
	var position_before := _rig_player.get_current_animation_position()
	var rotation_before: Vector3 = _rig_host.rotation

	for _i in 3:
		_rig_door.interact()

	assert_eq(
		_rig_player.get_current_animation_position(),
		position_before,
		"动画中重复按 E 不得重启或倒回播放位置"
	)
	assert_true(_rig_host.rotation.is_equal_approx(rotation_before), "动画中重复按 E 不得让门抽搐")
	assert_true(_rig_door.target_open, "目标状态应仍是开")

	_rig_player.advance(ANIM_LENGTH * 0.2)
	assert_gt(
		_rig_player.get_current_animation_position(),
		position_before,
		"动画中重复按 E 不得翻转播放方向"
	)

	_finish_rig_animation()
	assert_true(_rig_door.is_open, "一次完整开门后应处于打开状态")


func test_case5_spam_during_closing_is_ignored() -> void:
	_open_rig()
	_rig_door.interact()
	_rig_player.advance(ANIM_LENGTH * 0.2)
	assert_true(_rig_player.is_playing(), "关门动画应仍在进行")
	var position_before := _rig_player.get_current_animation_position()
	var rotation_before: Vector3 = _rig_host.rotation

	for _i in 3:
		_rig_door.interact()

	assert_eq(
		_rig_player.get_current_animation_position(),
		position_before,
		"关门动画中重复按 E 不得重启或倒回播放位置"
	)
	assert_true(_rig_host.rotation.is_equal_approx(rotation_before), "关门动画中重复按 E 不得让门抽搐")
	assert_false(_rig_door.target_open, "目标状态应仍是关")

	_rig_player.advance(ANIM_LENGTH * 0.2)
	assert_true(
		_rig_player.get_current_animation_position() < position_before,
		"关门动画中重复按 E 不得翻转播放方向"
	)

	_finish_rig_animation()
	assert_false(_rig_door.is_open, "一次完整关门后应回到关闭状态")


func test_prompt_follows_completed_state() -> void:
	assert_eq(_rig_door.get_interaction_text(), "E 打开门", "关闭时应提示打开门")
	_rig_door.interact()
	assert_eq(_rig_door.get_interaction_text(), "E 打开门", "开门动画期间提示不得提前翻转")
	_finish_rig_animation()
	assert_eq(_rig_door.get_interaction_text(), CLOSED_PROMPT, "完全打开后应提示关门")
	_rig_door.interact()
	_finish_rig_animation()
	assert_eq(_rig_door.get_interaction_text(), "E 打开门", "关好后应重新提示打开门")


# ─────────────────────────────
# 夹具
# ─────────────────────────────

func _build_rig(tree: SceneTree) -> void:
	_rig_host = Node3D.new()
	_rig_host.name = "DoorRig"
	_rig_player = AnimationPlayer.new()
	_rig_player.name = "AnimationPlayer"
	_rig_host.add_child(_rig_player)

	var library := AnimationLibrary.new()
	library.add_animation(OPEN_ANIMATION, _anim.get_animation(OPEN_ANIMATION))
	_rig_player.add_animation_library("", library)

	_rig_door = (load(DOOR_SCRIPT) as GDScript).new()
	_rig_door.name = "Collision_Puerta"
	_rig_door.interaction_text = _door.get("interaction_text")
	# rig 门刻意保持无锁（door.gd 的三个 Lock 属性用默认值），这样上面的用例测的还是原始开关状态机；
	# 需要锁的用例在各自 test_ 方法里显式改 rig 的配置，setup() 会为每个用例重建 rig。
	_rig_host.add_child(_rig_door)

	track(_rig_host)
	tree.root.add_child(_rig_host)


func _open_rig() -> void:
	_rig_door.interact()
	_finish_rig_animation()


func _finish_rig_animation() -> void:
	_rig_player.advance(ANIM_LENGTH + 0.2)


func _leaf_local_center() -> Vector3:
	var concave := (_door.get_child(0) as CollisionShape3D).shape as ConcavePolygonShape3D
	var faces := concave.get_faces()
	var box := AABB(faces[0], Vector3.ZERO)
	for vertex in faces:
		box = box.expand(vertex)
	return box.get_center()


func _global_aabb(node: MeshInstance3D) -> AABB:
	var gt := node.global_transform
	var local: AABB = node.mesh.get_aabb()
	var box := AABB(gt * local.position, Vector3.ZERO)
	for i in 8:
		var corner := local.position + Vector3(
			local.size.x * float((i >> 0) & 1),
			local.size.y * float((i >> 1) & 1),
			local.size.z * float((i >> 2) & 1)
		)
		box = box.expand(gt * corner)
	return box
