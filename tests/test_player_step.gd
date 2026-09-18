@tool
extends McpTestSuite

## Scenario: walking stairs teleports the body up/down each tread.
## The first-person camera must absorb that delta, then settle, or the view jitters.

func suite_name() -> String:
	return "player_step"


func _make_player() -> Node:
	var script: GDScript = load("res://player.gd") as GDScript
	var player: Node = script.new()
	track(player)
	var head := Node3D.new()
	head.name = "Head"
	player.add_child(head)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0.0, 0.62, 0.0)
	head.add_child(camera)
	player.set("head", head)
	player.set("camera", camera)
	return player


func _camera_y(player: Node) -> float:
	var head: Node3D = player.get_node("Head")
	var camera: Node3D = player.get_node("Head/Camera3D")
	return player.position.y + head.position.y + camera.position.y


func test_step_up_absorbs_height_so_camera_does_not_pop() -> void:
	var player := _make_player()
	var cam_before: float = _camera_y(player)
	player.position.y += 0.3
	player.call("absorb_step_height", 0.3)
	var cam_after: float = _camera_y(player)
	assert_true(
		is_equal_approx(cam_after, cam_before),
		"step-up popped camera y from %s to %s" % [cam_before, cam_after]
	)
	var head: Node3D = player.get_node("Head")
	assert_true(
		is_equal_approx(head.position.y, -0.3),
		"head should offset by -0.3, got %s" % head.position.y
	)


func test_step_camera_settles_back_toward_rest() -> void:
	var player := _make_player()
	var head: Node3D = player.get_node("Head")
	player.call("absorb_step_height", 0.3)
	var offset_start: float = head.position.y
	assert_true(offset_start < -0.2, "expected a downward head offset, got %s" % offset_start)
	for _i in 24:
		player.call("tick_step_camera", 0.05)
	assert_true(
		absf(head.position.y) < absf(offset_start),
		"head offset did not decay (%s -> %s)" % [offset_start, head.position.y]
	)
	assert_true(
		absf(head.position.y) < 0.04,
		"head offset did not settle, still %s" % head.position.y
	)


func test_finish_step_clears_vertical_velocity() -> void:
	var player := _make_player()
	player.set("velocity", Vector3(0.0, -3.5, 0.0))
	player.call("finish_step")
	var velocity: Vector3 = player.get("velocity")
	assert_eq(velocity.y, 0.0, "step finish must zero vertical velocity")
