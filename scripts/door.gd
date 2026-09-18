extends Interactable

# 门交互脚本（挂在门碰撞体上）：按 E 在开 / 关之间切换。
# 开与关复用父节点 AnimationPlayer 的同一条 open 动画，关门是它的反向播放。

const OPEN_ANIMATION := &"open"
const CLOSED_PROMPT := "E 关门"

@onready var animation_player: AnimationPlayer = get_parent().get_node("AnimationPlayer")

var is_open: bool = false
var is_animating: bool = false
var target_open: bool = false


func _ready() -> void:
	animation_player.animation_finished.connect(_on_animation_finished)


func interact() -> void:
	if is_animating:
		return

	is_animating = true
	target_open = not is_open

	if target_open:
		animation_player.play(OPEN_ANIMATION)
	else:
		animation_player.play_backwards(OPEN_ANIMATION)


func get_interaction_text() -> String:
	return CLOSED_PROMPT if is_open else interaction_text


# is_open 描述动画真正播完后的姿态，所以状态在这里提交，而不是在 interact() 里。
func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name != OPEN_ANIMATION:
		return

	is_open = target_open
	is_animating = false
