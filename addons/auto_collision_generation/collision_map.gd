@tool
extends EditorPlugin

const FacePicker := preload("res://addons/auto_collision_generation/collision_face_picker.gd")

var panel: Control
var info_dialog: AcceptDialog
var pick_button: Button
var click_gen_button: Button
var sel_label: Label
var angle_spin: SpinBox
var picker = FacePicker.new()
var click_gen_on := false
var _hover_mesh: MeshInstance3D
var _hover_overlay: Material
var _click_highlight: StandardMaterial3D


func _enter_tree():
	_purge_stale_docks()
	picker.setup(self)

	panel = Control.new()
	panel.name = "AutoCollisionGenDock"
	panel.custom_minimum_size = Vector2(0, 112)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	var row1 := HBoxContainer.new()
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	row1.add_theme_constant_override("separation", 10)
	col.add_child(row1)

	row1.add_child(_make_button("选中：三角网格", _on_generate_selected.bind("trimesh")))
	row1.add_child(_make_button("选中：简化凸包", _on_generate_selected.bind("simplified")))
	row1.add_child(_make_button("选中：凸包", _on_generate_selected.bind("convex")))
	click_gen_button = Button.new()
	click_gen_button.text = "点击物体生成"
	click_gen_button.toggle_mode = true
	click_gen_button.toggled.connect(_on_click_gen_toggled)
	row1.add_child(click_gen_button)
	sel_label = Label.new()
	sel_label.text = "当前: （未选）"
	row1.add_child(sel_label)
	get_editor_interface().get_selection().selection_changed.connect(_update_sel_label)

	var row_pick := HBoxContainer.new()
	row_pick.alignment = BoxContainer.ALIGNMENT_CENTER
	row_pick.add_theme_constant_override("separation", 10)
	col.add_child(row_pick)

	pick_button = Button.new()
	pick_button.text = "点选碰撞面"
	pick_button.toggle_mode = true
	pick_button.toggled.connect(_on_pick_toggled)
	row_pick.add_child(pick_button)
	row_pick.add_child(_make_button("扩展相连面", _on_grow_pressed))
	row_pick.add_child(_make_button("清除选区", _on_clear_pick_pressed))
	row_pick.add_child(_make_button("裁剪选中面", _on_cut_faces_pressed))

	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 10)
	col.add_child(row2)

	var angle_label := Label.new()
	angle_label.text = "扩展角度"
	row2.add_child(angle_label)
	angle_spin = SpinBox.new()
	angle_spin.min_value = 5
	angle_spin.max_value = 90
	angle_spin.value = 40
	angle_spin.suffix = "°"
	row2.add_child(angle_spin)
	row2.add_child(_make_button("放置裁剪盒", _on_place_cut_box_pressed))
	row2.add_child(_make_button("按盒子裁剪", _on_cut_pressed))

	add_control_to_bottom_panel(panel, "Auto Collision")
	panel.visibility_changed.connect(_on_panel_visibility_changed)

	info_dialog = AcceptDialog.new()
	info_dialog.title = "Auto Collision Generator"
	get_editor_interface().get_base_control().add_child(info_dialog)


func _exit_tree():
	picker.cleanup()
	_clear_hover_highlight()
	click_gen_on = false
	var sel := get_editor_interface().get_selection()
	if sel.selection_changed.is_connected(_update_sel_label):
		sel.selection_changed.disconnect(_update_sel_label)
	if is_instance_valid(panel):
		remove_control_from_bottom_panel(panel)
		panel.queue_free()
		panel = null
	if is_instance_valid(info_dialog):
		info_dialog.queue_free()
		info_dialog = null
	_purge_stale_docks()


func _purge_stale_docks() -> void:
	var base := get_editor_interface().get_base_control()
	if base == null:
		return
	var docks: Array[Control] = []
	_find_our_docks(base, docks)
	for dock in docks:
		if dock == panel:
			continue
		remove_control_from_bottom_panel(dock)
		if is_instance_valid(dock):
			var parent := dock.get_parent()
			if parent:
				parent.remove_child(dock)
			dock.queue_free()


func _find_our_docks(node: Node, out: Array[Control]) -> void:
	if node is Button:
		var text := (node as Button).text
		if text == "Generate Collision" or text == "选中：三角网格" or text == "点击物体生成" or text == "点选碰撞面" or text == "裁剪碰撞" or text == "按盒子裁剪":
			var dock := _dock_root_from_button(node as Button)
			if dock and not out.has(dock):
				out.append(dock)
	for child in node.get_children():
		_find_our_docks(child, out)


func _dock_root_from_button(button: Button) -> Control:
	var hbox := button.get_parent()
	if hbox == null:
		return null
	var mid := hbox.get_parent()
	if mid == null:
		return hbox as Control
	if mid is VBoxContainer:
		var dock := mid.get_parent()
		if dock is Control:
			return dock as Control
	if mid is Control:
		return mid as Control
	return null


func _handles(_object: Object) -> bool:
	if not is_instance_valid(panel) or not panel.visible:
		return false
	return picker.enabled or click_gen_on


func _on_panel_visibility_changed() -> void:
	if panel == null or not is_instance_valid(panel):
		return
	if panel.visible:
		return
	_stop_pick_mode()
	_stop_click_gen()


func _stop_pick_mode() -> void:
	if is_instance_valid(pick_button) and pick_button.button_pressed:
		pick_button.set_pressed_no_signal(false)
	picker.set_enabled(false)
	if is_instance_valid(pick_button):
		pick_button.text = "点选碰撞面"
	if is_instance_valid(info_dialog) and info_dialog.visible:
		info_dialog.hide()
	update_overlays()


func _stop_click_gen() -> void:
	click_gen_on = false
	if is_instance_valid(click_gen_button) and click_gen_button.button_pressed:
		click_gen_button.set_pressed_no_signal(false)
	if is_instance_valid(click_gen_button):
		click_gen_button.text = "点击物体生成"
	_clear_hover_highlight()
	update_overlays()


func _on_click_gen_toggled(on: bool) -> void:
	if not on:
		_stop_click_gen()
		return
	if picker.enabled:
		_stop_pick_mode()
	click_gen_on = true
	click_gen_button.text = "点击生成中（再点关闭）"
	var sel: Array = get_editor_interface().get_selection().get_selected_nodes()
	if sel.size() > 0:
		get_editor_interface().edit_node(sel[0])
	update_overlays()


func _update_sel_label() -> void:
	if not is_instance_valid(sel_label):
		return
	var sel: Array = get_editor_interface().get_selection().get_selected_nodes()
	if sel.is_empty():
		sel_label.text = "当前: （未选）"
		return
	sel_label.text = "当前: %s" % str(sel[0].name)


func _clear_hover_highlight() -> void:
	if is_instance_valid(_hover_mesh):
		_hover_mesh.material_overlay = _hover_overlay
	_hover_mesh = null
	_hover_overlay = null


func _set_hover_mesh(mi: MeshInstance3D) -> void:
	if mi == _hover_mesh:
		return
	_clear_hover_highlight()
	if mi == null:
		return
	_hover_mesh = mi
	_hover_overlay = mi.material_overlay
	if _click_highlight == null:
		_click_highlight = StandardMaterial3D.new()
		_click_highlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_click_highlight.albedo_color = Color(0.2, 1.0, 0.45, 0.45)
		_click_highlight.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_click_highlight.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_overlay = _click_highlight


func _handle_click_gen(camera: Camera3D, event: InputEvent) -> int:
	if camera == null:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseMotion:
		var mi := _pick_mesh_under_cursor(camera, (event as InputEventMouseMotion).position)
		_set_hover_mesh(mi)
		update_overlays()
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		var mi := _pick_mesh_under_cursor(camera, mb.position)
		if mi == null:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		_set_hover_mesh(mi)
		get_editor_interface().get_selection().clear()
		get_editor_interface().get_selection().add_node(mi)
		_on_generate_selected("trimesh")
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _pick_mesh_under_cursor(camera: Camera3D, mouse: Vector2) -> MeshInstance3D:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return null
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var small: Array[MeshInstance3D] = []
	var large: Array[MeshInstance3D] = []
	for mi in _collect_meshes(root):
		var mesh_i := mi as MeshInstance3D
		if mesh_i.mesh == null:
			continue
		var world_aabb: AABB = mesh_i.global_transform * mesh_i.get_aabb()
		if not world_aabb.intersects_segment(from, from + dir * 400.0) and not world_aabb.has_point(from):
			continue
		if mesh_i.get_aabb().get_volume() < 80.0:
			small.append(mesh_i)
		else:
			large.append(mesh_i)
	var best := _closest_mesh_in(from, dir, small)
	if best != null:
		return best
	return _closest_mesh_in(from, dir, large)


func _closest_mesh_in(from: Vector3, dir: Vector3, meshes: Array[MeshInstance3D]) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_d := INF
	var best_vol := INF
	for mesh_i in meshes:
		var d := _ray_hit_mesh_distance(from, dir, mesh_i)
		if d < 0.0:
			continue
		var vol := mesh_i.get_aabb().get_volume()
		if d < best_d - 0.03:
			best = mesh_i
			best_d = d
			best_vol = vol
		elif absf(d - best_d) <= 0.03 and vol < best_vol:
			best = mesh_i
			best_vol = vol
	return best


func _ray_hit_mesh_distance(from: Vector3, dir: Vector3, mi: MeshInstance3D) -> float:
	if mi.mesh == null:
		return -1.0
	var local_aabb: AABB = mi.get_aabb()
	var world_aabb: AABB = mi.global_transform * local_aabb
	if not world_aabb.has_point(from) and not world_aabb.intersects_segment(from, from + dir * 400.0):
		return -1.0
	var xf := mi.global_transform
	var best := INF
	var hit_any := false
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices = arrays[Mesh.ARRAY_INDEX]
		if indices != null and indices.size() >= 3:
			var i := 0
			var idx: PackedInt32Array = indices
			while i + 2 < idx.size():
				var a: Vector3 = xf * verts[idx[i]]
				var b: Vector3 = xf * verts[idx[i + 1]]
				var c: Vector3 = xf * verts[idx[i + 2]]
				var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir, a, b, c)
				if hit != null:
					hit_any = true
					best = minf(best, from.distance_to(hit))
				i += 3
		else:
			var i := 0
			while i + 2 < verts.size():
				var a2: Vector3 = xf * verts[i]
				var b2: Vector3 = xf * verts[i + 1]
				var c2: Vector3 = xf * verts[i + 2]
				var hit2: Variant = Geometry3D.ray_intersects_triangle(from, dir, a2, b2, c2)
				if hit2 != null:
					hit_any = true
					best = minf(best, from.distance_to(hit2))
				i += 3
	if hit_any:
		return best
	return -1.0


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if click_gen_on:
		return _handle_click_gen(viewport_camera, event)
	return picker.handle_3d_input(viewport_camera, event)


func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if click_gen_on:
		var name_text := "无"
		if is_instance_valid(_hover_mesh):
			name_text = str(_hover_mesh.name)
		overlay.draw_string(
			overlay.get_theme_default_font(),
			Vector2(16, 28),
			"点击生成  指向: %s   左键=三角网格碰撞" % name_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			Color(0.5, 1, 0.7)
		)
		return
	picker.draw_overlay(overlay)


func _on_pick_toggled(on: bool) -> void:
	if not on:
		_stop_pick_mode()
		return
	picker.set_enabled(true)
	pick_button.text = "点选中（再点关闭）"
	var sel: Array = get_editor_interface().get_selection().get_selected_nodes()
	if sel.size() > 0:
		get_editor_interface().edit_node(sel[0])
	update_overlays()


func _on_grow_pressed() -> void:
	if not picker.enabled:
		pick_button.set_pressed_no_signal(true)
		_on_pick_toggled(true)
	if picker.selected_count() == 0:
		_show_info("先在视口里点一下要剪的那块碰撞面。")
		return
	var added := picker.grow_connected(float(angle_spin.value))
	_show_info("已扩展 %d 个相连面，当前共 %d 面。\n橙面+黄线就是将要删掉的碰撞。不对就「清除选区」。" % [added, picker.selected_count()])


func _on_clear_pick_pressed() -> void:
	picker.clear_selection()


func _on_cut_faces_pressed() -> void:
	if picker.selected_count() == 0:
		_show_info("没有选中的面。先点选，确认橙黄高亮后再裁。")
		return
	var removed := picker.cut_selected(get_undo_redo())
	if removed == 0:
		_show_info("没有裁掉任何面。")
		return
	_show_info("已从碰撞里删掉 %d 个三角形。Ctrl+Z 撤销，然后保存场景。" % removed)


func _make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	return button


func _on_generate_selected(mode: String) -> void:
	var root = get_editor_interface().get_edited_scene_root()
	if root == null:
		_show_info("先打开一个场景。")
		return

	var selected: Array = get_editor_interface().get_selection().get_selected_nodes()
	if selected.is_empty():
		_show_info("先在场景树选中一个 MeshInstance3D（例如 Piso_Sotano），再点按钮。\n和官方 Mesh 菜单一样：只对选中的那一个生成。")
		return

	var all_meshes: Array = _meshes_from_selection(selected)
	if all_meshes.is_empty():
		_show_info("选中的节点里没有网格。请点选一个 MeshInstance3D。")
		return

	var created_count := 0
	var skipped_count := 0
	var names := PackedStringArray()
	var undo := get_undo_redo()
	undo.create_action("Generate Selected Collision")

	for mesh_node in all_meshes:
		if _add_collision(mesh_node, root, undo, mode):
			created_count += 1
			names.append(str(mesh_node.name))
		else:
			skipped_count += 1

	undo.commit_action()

	var mode_name := "三角网格"
	if mode == "simplified":
		mode_name = "简化凸包"
	elif mode == "convex":
		mode_name = "凸包"

	var message := "已对选中网格生成%s碰撞。\n\n" % mode_name
	message += "✅ %d 个：%s\n" % [created_count, ", ".join(names)]
	if skipped_count > 0:
		message += "⏭️ %d 个跳过（已有 StaticBody3D）\n" % skipped_count
	_show_info(message)


func _on_place_cut_box_pressed():
	var root = get_editor_interface().get_edited_scene_root()
	if root == null:
		_show_info("先打开一个场景。")
		return
	if not (root is Node3D):
		_show_info("当前场景根不是 Node3D，无法放置 3D 裁剪盒。")
		return

	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(2, 2, 2)

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.25, 0.15, 0.35)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	box_mesh.material = mat

	var box := MeshInstance3D.new()
	box.name = "CollisionCutBox"
	box.mesh = box_mesh
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	box.add_to_group("collision_cut_box")

	var camera := get_editor_interface().get_editor_viewport_3d(0).get_camera_3d()
	if camera:
		box.global_transform.origin = camera.global_position - camera.global_transform.basis.z * 6.0
	else:
		box.position = Vector3.ZERO

	var undo := get_undo_redo()
	undo.create_action("Place Collision Cut Box")
	undo.add_do_method(root, "add_child", box)
	undo.add_do_method(self, "_set_owner_recursive", box, root)
	undo.add_do_reference(box)
	undo.add_undo_method(root, "remove_child", box)
	undo.commit_action()

	get_editor_interface().get_selection().clear()
	get_editor_interface().get_selection().add_node(box)
	_show_info("已放置 CollisionCutBox。\n把它缩放到要挖掉的楼梯井/门口，选中 Collision_Casa，再点「裁剪碰撞」。")


func _on_cut_pressed():
	var root = get_editor_interface().get_edited_scene_root()
	if root == null:
		_show_info("先打开一个场景。")
		return

	var selected: Array = get_editor_interface().get_selection().get_selected_nodes()
	var shapes: Array[CollisionShape3D] = []
	var boxes: Array[MeshInstance3D] = []
	for node in selected:
		_collect_concave_shapes(node, shapes)
		_collect_cut_boxes(node, boxes)

	if boxes.is_empty():
		_collect_cut_boxes(root, boxes)

	if shapes.is_empty():
		_show_info("请先选中要裁的碰撞：Collision_Casa 或它下面的 CollisionShape3D。")
		return
	if boxes.is_empty():
		_show_info("场景里没有裁剪盒。先点「放置裁剪盒」，对准楼梯井后再裁。")
		return

	var undo := get_undo_redo()
	undo.create_action("Cut Collision Faces")
	var total_removed := 0
	var any := false
	for shape_node in shapes:
		var result := _cut_shape(shape_node, boxes)
		if result.is_empty():
			continue
		any = true
		total_removed += int(result.removed)
		undo.add_do_property(shape_node, "shape", result.new_shape)
		undo.add_undo_property(shape_node, "shape", result.old_shape)
		undo.add_do_reference(result.new_shape)

	if not any:
		_show_info("裁剪盒没有罩住任何三角形。把盒子放大、对准青色碰撞网后再试。")
		return

	undo.commit_action()
	_show_info("裁剪完成，去掉 %d 个三角形。\nCtrl+Z 可撤销。裁完后保存场景。" % total_removed)


func _collect_concave_shapes(node: Node, out: Array[CollisionShape3D]) -> void:
	if node is CollisionShape3D:
		var cs := node as CollisionShape3D
		if cs.shape is ConcavePolygonShape3D and not out.has(cs):
			out.append(cs)
	if node is StaticBody3D or node is MeshInstance3D:
		for child in node.get_children():
			_collect_concave_shapes(child, out)
	elif node.get_child_count() > 0:
		for child in node.get_children():
			if child is StaticBody3D or child is CollisionShape3D:
				_collect_concave_shapes(child, out)


func _collect_cut_boxes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh is BoxMesh:
			if mi.name.begins_with("CollisionCutBox") or mi.is_in_group("collision_cut_box"):
				if not out.has(mi):
					out.append(mi)
	for child in node.get_children():
		_collect_cut_boxes(child, out)


func _cut_shape(shape_node: CollisionShape3D, boxes: Array[MeshInstance3D]) -> Dictionary:
	var old_shape := shape_node.shape as ConcavePolygonShape3D
	if old_shape == null:
		return {}
	var faces := old_shape.get_faces()
	if faces.size() < 3:
		return {}

	var kept := PackedVector3Array()
	var removed := 0
	var xform := shape_node.global_transform
	var i := 0
	while i + 2 < faces.size():
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var centroid := (a + b + c) / 3.0
		var world := xform * centroid
		if _inside_any_box(world, boxes):
			removed += 1
		else:
			kept.append(a)
			kept.append(b)
			kept.append(c)
		i += 3

	if removed == 0:
		return {}

	var new_shape := old_shape.duplicate() as ConcavePolygonShape3D
	new_shape.set_faces(kept)
	return {"old_shape": old_shape, "new_shape": new_shape, "removed": removed}


func _inside_any_box(world_point: Vector3, boxes: Array[MeshInstance3D]) -> bool:
	for box in boxes:
		if not is_instance_valid(box):
			continue
		var bm := box.mesh as BoxMesh
		if bm == null:
			continue
		var local: Vector3 = box.global_transform.affine_inverse() * world_point
		var half: Vector3 = bm.size * 0.5
		if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
			return true
	return false


func _show_info(message: String):
	if is_instance_valid(info_dialog):
		info_dialog.dialog_text = message
		info_dialog.popup_centered()
	print(message)


func _meshes_from_selection(selected: Array) -> Array:
	var result: Array = []
	for node in selected:
		if node is MeshInstance3D:
			if not result.has(node):
				result.append(node)
		else:
			for mesh_node in _collect_meshes(node):
				if not result.has(mesh_node):
					result.append(mesh_node)
	return result


func _collect_meshes(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D:
		var n := node.name
		if not n.begins_with("_ACP_") and not n.begins_with("CollisionCutBox"):
			result.append(node)
	for child in node.get_children():
		result += _collect_meshes(child)
	return result


func _set_owner_recursive(node: Node, owner: Node):
	node.owner = owner
	for child in node.get_children():
		_set_owner_recursive(child, owner)


func _add_collision(mesh_node, scene_root, undo: EditorUndoRedoManager, mode: String = "trimesh") -> bool:
	for child in mesh_node.get_children():
		if child is StaticBody3D:
			return false

	if mesh_node.mesh == null:
		return false

	var shape: Shape3D = null
	if mode == "simplified":
		shape = mesh_node.mesh.create_convex_shape(true, true)
	elif mode == "convex":
		shape = mesh_node.mesh.create_convex_shape(true, false)
	else:
		shape = mesh_node.mesh.create_trimesh_shape()
	if shape == null:
		return false

	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = shape

	var static_body = StaticBody3D.new()
	static_body.name = "Collision_" + mesh_node.name
	static_body.add_child(collision_shape)

	undo.add_do_method(mesh_node, "add_child", static_body)
	undo.add_do_method(self, "_set_owner_recursive", static_body, scene_root)
	undo.add_do_reference(static_body)
	undo.add_undo_method(mesh_node, "remove_child", static_body)

	return true
