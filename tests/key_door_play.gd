extends Node

## 真实游玩流程驱动（把正式关卡当游戏玩一遍并回报事实，不是断言 rig）。
##
## 覆盖流程：面向锁着的门（无钥匙）→ 外部真实按 E → 门不动 →
## 面向 Basement Key → 外部真实按 E → 钥匙消失且进库存 →
## 再面向门 → 外部真实按 E → 一次 E 解锁并向屋内打开 → 驱动再按 E 关 / 开 → 移动回归。
##
## 三个关键交互（打不开、拾取、解锁）由 MCP game_manage(input_key) 从外部注入真实按键，
## 本脚本只负责站位、瞄准和读状态；D1/D2 连续开关因为只有时序需求才用
## Input.parse_input_event 注入（与 MCP input_key 内部同一条路径）。
##
## 为什么需要它：编辑器 @tool 层拿不到 autoload（见 lock_runtime_suite.gd 顶部说明），
## 而 Player / 交互射线 / 提示 UI / 真实门板动画只有在运行中的游戏里才存在。
## 本脚本不碰任何游戏逻辑：只读状态、只用 project.godot 里已有的输入动作。
##
## 门向屋内打开后碰撞体会跟着门板转走，站在原地会脱靶，所以每次按 E 前都重新搜索一个
## "脚下有地、射线又真的打中目标"的站位，而不是假设门还在原来的位置。
##
## 文件名刻意不带 test_ 前缀：test_run 只发现 McpTestSuite 子类。

const KEY_NAME := "Basement Key"
const DOOR_PATH := "Abandoned_House/Casa/Puerta"
const DOOR_BODY_PATH := "Abandoned_House/Casa/Puerta/Collision_Puerta"
const KEY_PATH := "BasementKey"
const STAND_DISTANCES := [1.5, 2.1]
const SETTLE_FRAMES := 6
const DOOR_ANIM_WAIT := 1.4      # 真实 open 动画 0.8s，留足余量
const WALK_HOLD_SEC := 0.6
const E_KEYCODE := KEY_E

var _checks: int = 0
var _failures: Array[String] = []
var _lines: Array[String] = []
var _stand_dirs: Array[Vector3] = [
	Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)
]

var _scene: Node3D
var _player: CharacterBody3D
var _door: Node
var _puerta: Node3D
var _key: Node
var _ray: RayCast3D
var _label: Label
var _prompt: Control


## 站到一个目标正面并回报当前提示 —— 调用方随后从外部注入真实 E 键。
func stage_face(target_name: String, expected_prompt: String) -> String:
	_resolve()
	var target: Node = _door if target_name == "door" else _key
	if _player == null or target == null:
		_failures.append("%s 或 player 节点缺失" % target_name)
		return report()

	var hit: String = await _face(target)
	_line("%s：射线命中=%s 玩家提示=%s door.get_interaction_text=%s 库存=%s"
		% [target_name, hit, _prompt_text(), _door_text(), _inventory()])
	_check(hit == String(target.name), "%s 必须被 InteractionRay 打中（实际命中 %s）" % [target_name, hit])
	_check(_prompt_text() == expected_prompt, "%s 的提示应为「%s」，实际「%s」" % [target_name, expected_prompt, _prompt_text()])
	if target_name == "door":
		_check(_bool("is_locked"), "%s 面向门时锁状态应与预期一致" % target_name)
	return report()


## 外部真实按 E 之后回来收结果。
func stage_verify(step: String) -> String:
	match step:
		"no_key":
			await _frames(20)
			_snapshot("A2 无钥匙 + 外部真实 E 之后")
			_check(_bool("is_locked"), "A2 无钥匙不得解锁")
			_check(not _bool("is_open"), "A2 无钥匙不得开门")
		"pickup":
			await _frames(30)
			var key_alive := _key != null and is_instance_valid(_key)
			_line("B2 外部真实 E 拾取后：钥匙还在场景里=%s 库存=%s" % [str(key_alive), _inventory()])
			_check(not key_alive, "B2 钥匙应已 queue_free")
			_check(_count_key() >= 1, "B2 库存里应有 Basement Key")
		"unlock":
			await _verify_unlock_then_cycle()
	return report()


func _verify_unlock_then_cycle() -> void:
	await _frames(20)
	_snapshot("C2 一次真实 E 之后")
	_check(not _bool("is_locked"), "C2 一次 E 就必须完成解锁，不能要玩家按两次")
	await _wait(DOOR_ANIM_WAIT)
	_snapshot("C3 动画播完（应已解锁 + 已打开）")
	_check(not _bool("is_locked"), "C3 一次 E 必须完成解锁")
	_check(_bool("is_open"), "C3 一次 E 必须完成开门")
	_check(_count_key() >= 1, "C3 consume=false：钥匙必须还在库存")
	_check(_rot_y() > 0.1, "C3 门板必须真的转过（当前 rotation.y=%s）" % _rot_y())

	await _face(_door)
	await _press_e()
	await _wait(DOOR_ANIM_WAIT)
	_snapshot("D1 第二次 E（关门）")
	_check(not _bool("is_open"), "D1 第二次 E 应关门")

	await _face(_door)
	await _press_e()
	await _wait(DOOR_ANIM_WAIT)
	_snapshot("D2 第三次 E（重新开门）")
	_check(_bool("is_open"), "D2 第三次 E 应重新开门")
	_check(_count_key() >= 1, "D2 反复开关不得消耗钥匙")
	_check(not _bool("is_locked"), "D2 不会重新上锁")

	await _walk_regression()


# ─────────────────────────────
# 回归
# ─────────────────────────────

func _walk_regression() -> void:
	var before: Vector3 = _player.global_position
	Input.action_press("move_forward")
	await _wait(WALK_HOLD_SEC)
	Input.action_release("move_forward")
	await _frames(10)
	var after: Vector3 = _player.global_position
	_line("E1 移动回归：按 W %ss 前=%s 后=%s 位移=%s"
		% [WALK_HOLD_SEC, str(before), str(after), "%.2f" % after.distance_to(before)])
	_check(after.distance_to(before) > 0.3, "E1 玩家必须能前进")
	_check(absf(after.y - before.y) < 3.0, "E1 玩家不得掉出世界")


# ─────────────────────────────
# 输入（仅用于 D1/D2 连续开关）
# ─────────────────────────────

func _press_e() -> void:
	_key_event(true)
	await _frames(3)
	_key_event(false)


func _key_event(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = E_KEYCODE
	event.pressed = pressed
	event.echo = false
	Input.parse_input_event(event)


# ─────────────────────────────
# 站位与视角：搜索"脚下有地 + 射线真的打中目标"的位置
# ─────────────────────────────

func _face(target: Node) -> String:
	for distance in STAND_DISTANCES:
		for dir in _stand_dirs:
			if await _try_stand_at(target, dir, distance):
				await _wait_for_player_target(target)
				_line("站到 %s 面向 %s（射线命中=%s）"
					% [str(_player.global_position), String(target.name), _target_name()])
				return _target_name()
	_line("搜遍候选站位仍打不到 %s" % String(target.name))
	return _target_name()


## RayCast3D 的命中结果要等下一个物理帧才被 player.gd 的 update_interaction() 采纳，
## 只看射线就按 E 会打在 current_interactable 还是 null 的空档上（按键被丢弃）。
## 所以以玩家自己的状态为准：等它认了这个目标、提示也显示出来，才算"面向"成功。
func _wait_for_player_target(target: Node) -> void:
	for _i in 12:
		if _player.get("current_interactable") == target and _prompt.visible:
			return
		await _frames(2)


func _try_stand_at(target: Node, dir: Vector3, distance: float) -> bool:
	if _scene == null or _player == null or _ray == null:
		return false
	var probe := _center_of(target) + dir * distance
	var floor_hit := _floor_below(probe)
	if floor_hit.is_empty():
		return false

	var feet_y: float = (floor_hit["position"] as Vector3).y
	_player.global_position = Vector3(probe.x, feet_y + _origin_offset(), probe.z)
	_player.velocity = Vector3.ZERO
	await _frames(SETTLE_FRAMES)
	_aim_at(_center_of(target))
	await _frames(3)
	return _ray.is_colliding() and _ray.get_collider() == target


func _floor_below(probe: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = _scene.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(
		probe + Vector3(0.0, 2.0, 0.0), probe - Vector3(0.0, 2.5, 0.0), 1
	)
	params.exclude = [_player.get_rid()]
	return space.intersect_ray(params)


## 碰撞体世界中心：凹面（门板）要按实际顶点算，节点原点可能落在铰链上而不是几何中心。
func _center_of(target: Node) -> Vector3:
	var shape_node := _shape_of(target)
	if shape_node == null:
		return target.global_position
	var concave := shape_node.shape as ConcavePolygonShape3D
	if concave == null:
		return shape_node.global_position
	var faces := concave.get_faces()
	if faces.is_empty():
		return shape_node.global_position
	var box := AABB(faces[0], Vector3.ZERO)
	for vertex in faces:
		box = box.expand(vertex)
	return shape_node.global_transform * box.get_center()


func _shape_of(target: Node) -> CollisionShape3D:
	for child in target.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null


func _aim_at(world_point: Vector3) -> void:
	var head: Node3D = _player.get_node("Head") as Node3D
	var camera: Camera3D = _player.get_node("Head/Camera3D") as Camera3D
	var to: Vector3 = world_point - camera.global_position
	head.rotation.y = atan2(-to.x, -to.z)
	camera.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())


func _origin_offset() -> float:
	return float(_player.call("_origin_from_feet")) + 0.05


func _resolve() -> void:
	_scene = get_tree().current_scene as Node3D
	if _scene == null:
		return
	_player = _scene.get_node_or_null("player") as CharacterBody3D
	_door = _scene.get_node_or_null(DOOR_BODY_PATH)
	_puerta = _scene.get_node_or_null(DOOR_PATH) as Node3D
	_key = _scene.get_node_or_null(KEY_PATH)
	if _player != null:
		_ray = _player.get_node("Head/Camera3D/InteractionRay") as RayCast3D
		_label = _player.get_node("UI/InteractionPrompt/Label") as Label
		_prompt = _player.get_node("UI/InteractionPrompt") as Control


# ─────────────────────────────
# 观测
# ─────────────────────────────

func _snapshot(label: String) -> void:
	_line("%s：is_locked=%s is_open=%s is_animating=%s target_open=%s 门板rotation.y=%s 玩家提示=%s 库存=%s" % [
		label,
		str(_bool("is_locked")),
		str(_bool("is_open")),
		str(_bool("is_animating")),
		str(_bool("target_open")),
		"%.4f" % _rot_y(),
		_prompt_text(),
		_inventory(),
	])


func _bool(property: String) -> bool:
	return bool(_door.get(property))


func _rot_y() -> float:
	return _puerta.rotation.y


func _door_text() -> String:
	return String(_door.call("get_interaction_text"))


func _prompt_text() -> String:
	if _prompt == null or not _prompt.visible:
		return "<提示未显示>"
	return _label.text


func _target_name() -> String:
	if _ray == null or not _ray.is_colliding():
		return "无"
	var collider := _ray.get_collider()
	return String(collider.name) if collider != null else "无"


func _count_key() -> int:
	return int(PlayerInventory.call("get_item_count", KEY_NAME))


func _inventory() -> String:
	return str(PlayerInventory.inventory)


# ─────────────────────────────
# 工具
# ─────────────────────────────

func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _line(text: String) -> void:
	_lines.append(text)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func report() -> String:
	var body := "\n".join(_lines)
	if _failures.is_empty():
		return "PASS %d/%d\n%s" % [_checks, _checks, body]
	return "FAIL %d/%d -> %s\n%s" % [_failures.size(), _checks, " | ".join(_failures), body]
