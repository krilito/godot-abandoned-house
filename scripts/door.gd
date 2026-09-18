extends Interactable

# 门交互脚本（挂在门碰撞体上）：按 E 播放父节点 AnimationPlayer 的 open 动画，只播一次。


@onready var animation_player: AnimationPlayer = get_parent().get_node("AnimationPlayer")

var is_open: bool = false
var is_animating: bool = false


func _ready() -> void:
	animation_player.animation_finished.connect(_on_animation_finished)


func interact() -> void:
	if is_open or is_animating:
		return
	is_animating = true
	animation_player.play("open")


func _on_animation_finished(_anim_name: StringName) -> void:
	is_animating = false
	is_open = true
