extends Interactable

# 门交互脚本（挂在门碰撞体上）：按 E 在开 / 关之间切换。
# 开与关复用父节点 AnimationPlayer 的同一条 open 动画，关门是它的反向播放。
# 锁完全归 Door 自己管：Door 主动查 PlayerInventory，Player / Key / Inventory 都不知道有锁这回事。

const OPEN_ANIMATION := &"open"
const CLOSED_PROMPT := "E 关门"
const UNLOCK_PROMPT := "E 解锁并打开"
const NEED_KEY_PROMPT := "需要 %s"
const BROKEN_LOCK_PROMPT := "门锁住了"

@export_group("Lock")

@export var is_locked: bool = false                  # 当前这扇门是否仍然锁住
@export var required_key: String = ""                # 解锁所需的 Inventory item name
@export var consume_key_on_unlock: bool = false      # 成功解锁后是否从 Inventory 扣掉 1 个

@onready var animation_player: AnimationPlayer = get_parent().get_node("AnimationPlayer")

var is_open: bool = false
var is_animating: bool = false
var target_open: bool = false


func _ready() -> void:
	animation_player.animation_finished.connect(_on_animation_finished)


func interact() -> void:
	if is_animating:
		return

	if not _try_unlock():
		return

	is_animating = true
	target_open = not is_open

	if target_open:
		animation_player.play(OPEN_ANIMATION)
	else:
		animation_player.play_backwards(OPEN_ANIMATION)


func get_interaction_text() -> String:
	if is_locked:
		if required_key.is_empty():
			return BROKEN_LOCK_PROMPT
		if PlayerInventory.has_item(required_key):
			return UNLOCK_PROMPT
		return NEED_KEY_PROMPT % required_key

	return CLOSED_PROMPT if is_open else interaction_text


# 只有真正解锁成功才把 is_locked 置 false；remove_item 返回 false 时必须保持锁住（fail closed）。
func _try_unlock() -> bool:
	if not is_locked:
		return true

	if required_key.is_empty():
		push_warning("Locked door %s has no required_key configured" % get_path())
		return false

	if not PlayerInventory.has_item(required_key):
		return false

	if consume_key_on_unlock and not PlayerInventory.remove_item(required_key, 1):
		return false

	is_locked = false
	return true


# is_open 描述动画真正播完后的姿态，所以状态在这里提交，而不是在 interact() 里。
func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name != OPEN_ANIMATION:
		return

	is_open = target_open
	is_animating = false
