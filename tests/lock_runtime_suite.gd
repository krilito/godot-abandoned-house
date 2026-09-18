extends Node

## 钥匙锁系统的运行时测试套件 —— 必须在真实运行的游戏里执行。
## 原因：PlayerInventory 是 autoload，编辑器 @tool 层拿到的只是 placeholder，
## 任何调用它的方法都会 "Attempt to call a method on a placeholder instance"。
## 调起方式（MCP）：editor_manage(op="game_eval") 里 load 本脚本、add_child 后 await run_all(true)。
##
## 文件名刻意不带 test_ 前缀：test_run 只发现 McpTestSuite 子类，带前缀会被报成套件错误。
## 这里给 rig 造一条同样叫 open 的旋转动画，测的是 door.gd 的锁状态机；
## 真实门板动画与开门方向由 tests/test_door.gd（编辑器层）负责。

const DOOR_SCRIPT := "res://scripts/door.gd"
const KEY := "Basement Key"
const OPEN_ANIMATION := &"open"
const ANIM_SECONDS := 0.1        # rig 动画时长，只要能在 SETTLE 内播完即可
const SETTLE_SECONDS := 0.22     # > ANIM_SECONDS，留出门板真正播完动画的余量
const MAX_KEY_CLEARANCE := 64    # 清库存的上限，宁可退出也别把游戏卡死
const RIG_OFFSET := Vector3(0.0, -1000.0, 0.0)  # 把 rig 丢到玩家够不到的地方

var _checks: int = 0
var _passes: Array[String] = []
var _failures: Array[String] = []
var _rigs: Array[Node] = []


func run_all(verbose: bool = false) -> String:
	await _run_cases()
	_teardown()
	var detail: String = (" :: " + ", ".join(_passes)) if verbose else ""
	if _failures.is_empty():
		return "PASS %d/%d%s" % [_checks, _checks, detail]
	return "FAIL %d/%d -> %s%s" % [_failures.size(), _checks, " | ".join(_failures), detail]


func _run_cases() -> void:
	await _case_l1_locked_without_key()
	await _case_l2_permanent_key()
	await _case_l3_consumable_key()
	await _case_l4_consumes_only_once()
	await _case_l5_unlocked_door_unaffected()
	await _case_l6_locked_without_required_key()


func _teardown() -> void:
	_clear_key()
	for rig in _rigs:
		if is_instance_valid(rig):
			rig.free()
	_rigs.clear()


# ─────────────────────────────
# 用例
# ─────────────────────────────

## L1：锁着 + 库存为空 —— 按 E 之后门必须原地不动，状态位一个都不能被改脏。
func _case_l1_locked_without_key() -> void:
	_clear_key()
	var door := _make_door(true, KEY, false)

	_check(door.get_interaction_text() == "需要 Basement Key", "L1缺钥匙提示")
	for _i in 3:
		door.interact()
	_check(door.is_locked, "L1仍然锁着")
	_check(not door.is_animating, "L1不进入动画")
	_check(not door.is_open, "L1不开门")
	_check(not door.target_open, "L1target_open未翻转")
	_check(_rig_rotation_y(door) == 0.0, "L1门板没有转动")
	_check(PlayerInventory.get_item_count(KEY) == 0, "L1库存仍为空")
	await _settle()
	_check(not door.is_open and not door.is_animating, "L1静置后仍未打开")


## L2：正式配置（consume=false）—— 一次 E 同时完成解锁 + 开门，钥匙留在身上。
func _case_l2_permanent_key() -> void:
	_clear_key()
	PlayerInventory.add_item(KEY, 1)
	var door := _make_door(true, KEY, false)

	_check(door.get_interaction_text() == "E 解锁并打开", "L2有钥匙提示")
	door.interact()
	await _settle()
	_check(not door.is_locked, "L2已解锁")
	_check(door.is_open, "L2一次E完成解锁+开门")
	_check(PlayerInventory.get_item_count(KEY) == 1, "L2钥匙未被消耗")
	_check(_rig_rotation_y(door) > 0.0, "L2门板真的转过去了")
	_check(door.get_interaction_text() == "E 关门", "L2打开后提示关门")

	door.interact()
	await _settle()
	_check(not door.is_open, "L2第二次E关门")
	door.interact()
	await _settle()
	_check(door.is_open, "L2第三次E重新打开")
	_check(PlayerInventory.get_item_count(KEY) == 1, "L2反复开关不消耗钥匙")
	_check(not door.is_locked, "L2解锁后不再回到锁住")


## L3：只把 Inspector 改成 consume=true，同一把钥匙就变成一次性钥匙。
func _case_l3_consumable_key() -> void:
	_clear_key()
	PlayerInventory.add_item(KEY, 1)
	var door := _make_door(true, KEY, true)

	_check(door.get_interaction_text() == "E 解锁并打开", "L3消耗型也提示解锁")
	door.interact()
	await _settle()
	_check(not door.is_locked, "L3已解锁")
	_check(door.is_open, "L3已开门")
	_check(PlayerInventory.get_item_count(KEY) == 0, "L3扣掉1把后库存清空")


## L4：消耗只发生一次 —— 解锁之后的开关门不得再碰库存。
func _case_l4_consumes_only_once() -> void:
	_clear_key()
	PlayerInventory.add_item(KEY, 2)
	var door := _make_door(true, KEY, true)

	door.interact()
	await _settle()
	_check(PlayerInventory.get_item_count(KEY) == 1, "L4只扣1把而不是全部")
	_check(door.is_open, "L4首次开门")

	for _i in 4:
		door.interact()
		await _settle()
	_check(PlayerInventory.get_item_count(KEY) == 1, "L4后续开关未继续扣钥匙")
	_check(door.is_open, "L4四次交互后仍是打开")
	_check(not door.is_locked, "L4保持已解锁")


## L5：无锁门完全不受锁系统影响（即使库存里什么都没有）。
func _case_l5_unlocked_door_unaffected() -> void:
	_clear_key()
	var door := _make_door(false, "", false)

	_check(door.get_interaction_text() == "E 打开门", "L5无锁门提示不变")
	door.interact()
	await _settle()
	_check(door.is_open, "L5无钥匙也能开")
	door.interact()
	await _settle()
	_check(not door.is_open, "L5能正常关")
	_check(PlayerInventory.get_item_count(KEY) == 0, "L5库存未被无锁门动过")


## L6：锁着但没配钥匙 —— fail closed，不解锁、不开门、不崩，也不能自己把锁去掉。
func _case_l6_locked_without_required_key() -> void:
	_clear_key()
	PlayerInventory.add_item(KEY, 1)
	var door := _make_door(true, "", false)

	_check(door.get_interaction_text() == "门锁住了", "L6配置缺失提示")
	door.interact()
	await _settle()
	_check(door.is_locked, "L6配置缺失时绝不自动解锁")
	_check(not door.is_open, "L6配置缺失时不开门")
	_check(PlayerInventory.get_item_count(KEY) == 1, "L6有钥匙也不得被误扣")


# ─────────────────────────────
# 夹具
# ─────────────────────────────

func _make_door(locked: bool, required: String, consume: bool) -> Node:
	var rig := Node3D.new()
	rig.name = "LockRig"
	rig.position = RIG_OFFSET

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	rig.add_child(player)
	var library := AnimationLibrary.new()
	library.add_animation(OPEN_ANIMATION, _build_open_animation())
	player.add_animation_library("", library)

	var door: Node = (load(DOOR_SCRIPT) as GDScript).new()
	door.name = "Collision_Puerta"
	door.interaction_text = "E 打开门"
	door.is_locked = locked
	door.required_key = required
	door.consume_key_on_unlock = consume
	rig.add_child(door)

	add_child(rig)
	_rigs.append(rig)
	return door


func _build_open_animation() -> Animation:
	var animation := Animation.new()
	animation.length = ANIM_SECONDS
	# 与场景里真实 open 动画同构：TYPE_VALUE 轨道直接驱动 .:rotation 的欧拉角。
	# 用 TYPE_ROTATION_3D 会被要求填 Quaternion，插 Vector3 会静默丢帧、门板不动。
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(".:rotation"))
	animation.track_insert_key(track, 0.0, Vector3.ZERO)
	animation.track_insert_key(track, ANIM_SECONDS, Vector3(0.0, PI / 2.0, 0.0))
	return animation


func _rig_rotation_y(door: Node) -> float:
	return (door.get_parent() as Node3D).rotation.y


func _settle() -> void:
	await get_tree().create_timer(SETTLE_SECONDS).timeout


func _clear_key() -> void:
	for _i in MAX_KEY_CLEARANCE:
		if not PlayerInventory.remove_item(KEY, 1):
			return


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		_passes.append(label)
	else:
		_failures.append(label)
