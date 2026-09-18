@tool
extends RefCounted

var plugin: EditorPlugin
var enabled: bool = false
var target: CollisionShape3D
var hover_tri: int = -1
var selected: Dictionary = {}

var _hover_mi: MeshInstance3D
var _select_mi: MeshInstance3D
var _line_mi: MeshInstance3D
var _adj: Dictionary = {}
var _adj_for_shape: ConcavePolygonShape3D
var _last_mouse := Vector2(-1, -1)


func setup(p: EditorPlugin) -> void:
	plugin = p


func set_enabled(v: bool) -> void:
	enabled = v
	if not enabled:
		hover_tri = -1
		selected.clear()
		_clear_previews()
	else:
		_retarget_from_selection()
		_ensure_previews()
		_rebuild_previews()
	if plugin:
		plugin.update_overlays()


func clear_selection() -> void:
	selected.clear()
	hover_tri = -1
	_rebuild_previews()
	if plugin:
		plugin.update_overlays()


func selected_count() -> int:
	return selected.size()


func _retarget_from_selection() -> void:
	if plugin == null:
		return
	var nodes: Array = plugin.get_editor_interface().get_selection().get_selected_nodes()
	var shapes: Array[CollisionShape3D] = []
	for node in nodes:
		_gather_concave(node, shapes)
	if shapes.is_empty():
		return
	if target != shapes[0]:
		target = shapes[0]
		_adj.clear()
		_adj_for_shape = null


func _gather_concave(node: Node, out: Array[CollisionShape3D]) -> void:
	if node is CollisionShape3D:
		var cs := node as CollisionShape3D
		if cs.shape is ConcavePolygonShape3D and not out.has(cs):
			out.append(cs)
	if node is StaticBody3D:
		for child in node.get_children():
			_gather_concave(child, out)
	elif node is MeshInstance3D:
		for child in node.get_children():
			_gather_concave(child, out)


func handle_3d_input(camera: Camera3D, event: InputEvent) -> int:
	if not enabled or camera == null:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	_retarget_from_selection()
	if target == null or not is_instance_valid(target) or target.shape == null:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.position.distance_squared_to(_last_mouse) < 1.0:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		_last_mouse = mm.position
		var tri := _pick_triangle(camera, mm.position)
		if tri != hover_tri:
			hover_tri = tri
			_rebuild_hover()
			plugin.update_overlays()
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		var tri := _pick_triangle(camera, mb.position)
		if tri < 0:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		hover_tri = tri
		if mb.ctrl_pressed:
			selected.erase(tri)
		else:
			selected[tri] = true
		_rebuild_previews()
		plugin.update_overlays()
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func grow_connected(max_angle_deg: float) -> int:
	_retarget_from_selection()
	if target == null or selected.is_empty():
		return 0
	_ensure_adjacency()
	var cos_lim := cos(deg_to_rad(max_angle_deg))
	var shape := target.shape as ConcavePolygonShape3D
	var faces := shape.get_faces()
	var queue: Array[int] = []
	for k in selected.keys():
		queue.append(int(k))
	var added := 0
	var i := 0
	while i < queue.size():
		var tri: int = queue[i]
		i += 1
		var n0 := _tri_normal(faces, tri)
		if not _adj.has(tri):
			continue
		for nb in _adj[tri]:
			var nbi: int = int(nb)
			if selected.has(nbi):
				continue
			var n1 := _tri_normal(faces, nbi)
			if n0.dot(n1) < cos_lim:
				continue
			selected[nbi] = true
			queue.append(nbi)
			added += 1
	_rebuild_previews()
	if plugin:
		plugin.update_overlays()
	return added


func cut_selected(undo: EditorUndoRedoManager) -> int:
	_retarget_from_selection()
	if target == null or selected.is_empty():
		return 0
	var old_shape := target.shape as ConcavePolygonShape3D
	var faces := old_shape.get_faces()
	var kept := PackedVector3Array()
	var tri_count := int(faces.size() / 3)
	var removed := 0
	for t in tri_count:
		var i := t * 3
		if selected.has(t):
			removed += 1
			continue
		kept.append(faces[i])
		kept.append(faces[i + 1])
		kept.append(faces[i + 2])
	if removed == 0:
		return 0
	var new_shape := old_shape.duplicate() as ConcavePolygonShape3D
	new_shape.set_faces(kept)
	undo.create_action("Cut Selected Collision Faces")
	undo.add_do_property(target, "shape", new_shape)
	undo.add_undo_property(target, "shape", old_shape)
	undo.add_do_reference(new_shape)
	undo.commit_action()
	selected.clear()
	hover_tri = -1
	_adj.clear()
	_adj_for_shape = null
	_rebuild_previews()
	if plugin:
		plugin.update_overlays()
	return removed


func draw_overlay(overlay: Control) -> void:
	if not enabled:
		return
	var text := "碰撞点选  左键选面  Ctrl+左键取消  |  悬停: %s  已选: %d 面" % [
		str(hover_tri) if hover_tri >= 0 else "无",
		selected.size()
	]
	overlay.draw_string(
		overlay.get_theme_default_font(),
		Vector2(16, 28),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		Color(1, 0.85, 0.3)
	)


func cleanup() -> void:
	enabled = false
	selected.clear()
	hover_tri = -1
	_clear_previews()


func _pick_triangle(camera: Camera3D, mouse: Vector2) -> int:
	var shape := target.shape as ConcavePolygonShape3D
	if shape == null:
		return -1
	var faces := shape.get_faces()
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var xform := target.global_transform
	var best_i := -1
	var best_d := INF
	var t := 0
	var i := 0
	while i + 2 < faces.size():
		var a: Vector3 = xform * faces[i]
		var b: Vector3 = xform * faces[i + 1]
		var c: Vector3 = xform * faces[i + 2]
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir, a, b, c)
		if hit != null:
			var p: Vector3 = hit
			var d := from.distance_squared_to(p)
			if d < best_d:
				best_d = d
				best_i = t
		t += 1
		i += 3
	return best_i


func _tri_normal(faces: PackedVector3Array, tri: int) -> Vector3:
	var i := tri * 3
	var n: Vector3 = (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i])
	if n.length_squared() < 0.0000001:
		return Vector3.UP
	return n.normalized()


func _ensure_adjacency() -> void:
	var shape := target.shape as ConcavePolygonShape3D
	if shape == _adj_for_shape and not _adj.is_empty():
		return
	_adj.clear()
	_adj_for_shape = shape
	var faces := shape.get_faces()
	var edge_to_tris: Dictionary = {}
	var tri_count := int(faces.size() / 3)
	for t in tri_count:
		var i := t * 3
		var keys := [
			_edge_key(faces[i], faces[i + 1]),
			_edge_key(faces[i + 1], faces[i + 2]),
			_edge_key(faces[i + 2], faces[i])
		]
		for key in keys:
			if not edge_to_tris.has(key):
				edge_to_tris[key] = []
			edge_to_tris[key].append(t)
	for t in tri_count:
		_adj[t] = []
	for key in edge_to_tris.keys():
		var tris: Array = edge_to_tris[key]
		if tris.size() < 2:
			continue
		for a in tris:
			for b in tris:
				if a == b:
					continue
				if not _adj[a].has(b):
					_adj[a].append(b)


func _edge_key(a: Vector3, b: Vector3) -> String:
	var ka := _vert_key(a)
	var kb := _vert_key(b)
	if ka < kb:
		return ka + "|" + kb
	return kb + "|" + ka


func _vert_key(v: Vector3) -> String:
	return "%d,%d,%d" % [roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0)]


func _ensure_previews() -> void:
	if target == null or not is_instance_valid(target):
		return
	if not is_instance_valid(_hover_mi):
		_hover_mi = _make_preview("_ACP_Hover", Color(1, 1, 0.2, 0.7))
	if not is_instance_valid(_select_mi):
		_select_mi = _make_preview("_ACP_Select", Color(1, 0.35, 0.08, 0.55))
	if not is_instance_valid(_line_mi):
		_line_mi = _make_preview("_ACP_Lines", Color(1, 0.95, 0.2, 1), true)
	_reparent_preview(_hover_mi)
	_reparent_preview(_select_mi)
	_reparent_preview(_line_mi)


func _make_preview(node_name: String, color: Color, lines: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 20
	if lines:
		mat.albedo_color = color
	mi.material_override = mat
	return mi


func _reparent_preview(mi: MeshInstance3D) -> void:
	if mi.get_parent() != target:
		if mi.get_parent():
			mi.get_parent().remove_child(mi)
		target.add_child(mi)
		mi.owner = null


func _rebuild_hover() -> void:
	_ensure_previews()
	if hover_tri < 0:
		if is_instance_valid(_hover_mi):
			_hover_mi.mesh = null
		return
	var shape := target.shape as ConcavePolygonShape3D
	_hover_mi.mesh = _tris_mesh(shape.get_faces(), [hover_tri], false)


func _rebuild_previews() -> void:
	_ensure_previews()
	if target == null or not is_instance_valid(target):
		return
	var shape := target.shape as ConcavePolygonShape3D
	var faces := shape.get_faces()
	var tris: Array = selected.keys()
	_select_mi.mesh = _tris_mesh(faces, tris, false)
	_line_mi.mesh = _tris_mesh(faces, tris, true)
	_rebuild_hover()


func _tris_mesh(faces: PackedVector3Array, tris: Array, lines: bool) -> ArrayMesh:
	if tris.is_empty():
		return null
	var st := SurfaceTool.new()
	if lines:
		st.begin(Mesh.PRIMITIVE_LINES)
	else:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for item in tris:
		var t: int = int(item)
		var i := t * 3
		if i + 2 >= faces.size():
			continue
		var a: Vector3 = faces[i]
		var b: Vector3 = faces[i + 1]
		var c: Vector3 = faces[i + 2]
		var n: Vector3 = (b - a).cross(c - a)
		if n.length_squared() > 0.0000001:
			n = n.normalized() * 0.012
		else:
			n = Vector3(0, 0.012, 0)
		a += n
		b += n
		c += n
		if lines:
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(c)
			st.add_vertex(a)
		else:
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
	return st.commit()


func _clear_previews() -> void:
	for mi in [_hover_mi, _select_mi, _line_mi]:
		if is_instance_valid(mi):
			mi.queue_free()
	_hover_mi = null
	_select_mi = null
	_line_mi = null
