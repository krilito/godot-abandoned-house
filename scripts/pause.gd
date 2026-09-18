extends Control

@export var pause_action: StringName = &"pause"  # 暂停输入


func _ready() -> void:  # 初始化
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	print("Pause system ready")


func _input(event: InputEvent) -> void:  # 监听 ESC
	if event.is_action_pressed(pause_action):
		print("Pause key received")
		toggle_pause()
		get_viewport().set_input_as_handled()


func toggle_pause() -> void:  # 暂停 / 恢复
	var is_paused := not get_tree().paused

	get_tree().paused = is_paused
	visible = is_paused

	print("Paused: ", is_paused, " | UI visible: ", visible)

	Input.set_mouse_mode(
		Input.MOUSE_MODE_VISIBLE
		if is_paused
		else Input.MOUSE_MODE_CAPTURED
	)
