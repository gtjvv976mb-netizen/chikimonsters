## SCENE PROFILE for the native build (test only, never shipped): what the frame is made of.
##
## Enters the world like ui-audit.gd, lets it settle, then reports as "[profile]" JSON:
##   - draw calls, objects and primitives in the frame;
##   - every visible GeometryInstance3D by kind, by size (AABB longest side) and by distance from
##     the camera, and how many cast shadows;
##   - the same draw-call count again with shadows off, and with small far objects hidden,
##     so each fix's share is measured instead of guessed.
extends Node

const SETTLE := 60.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().create_timer(6.0).timeout
	var title := _find_title(get_tree().root)
	if title != null:
		title.call("_enter")
	await get_tree().create_timer(SETTLE).timeout
	_report("base")
	var sun = get_tree().get_first_node_in_group("world_main").get("_sun")
	if sun is Light3D:
		sun.shadow_enabled = false
		await _frames(30)
		_report("no_shadows")
		sun.shadow_enabled = true
	var hidden := _hide_small_far()
	await _frames(30)
	_report("small_far_hidden_%d" % hidden)
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _find_title(n: Node) -> Node:
	var s: Script = n.get_script()
	if s != null and s.resource_path.ends_with("Title.gd") and n.has_method("_enter"):
		return n
	for c in n.get_children():
		var f := _find_title(c)
		if f != null:
			return f
	return null


func _report(tag: String) -> void:
	var cam := get_viewport().get_camera_3d()
	var by_kind := {}
	var by_size := {"<1": 0, "1-3": 0, "3-8": 0, "8-20": 0, "20+": 0}
	var by_dist := {"<40": 0, "40-100": 0, "100-200": 0, "200-400": 0, "400+": 0}
	var shadow := 0
	var surfaces := 0
	var owners := {}
	var tris := {}
	var shadow_tris := {}
	for g in _geoms(get_tree().root):
		var gi := g as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var k := gi.get_class()
		if gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
			k += "(%d)" % (gi as MultiMeshInstance3D).multimesh.visible_instance_count
		by_kind[k] = int(by_kind.get(k, 0)) + 1
		var aabb := gi.global_transform * gi.get_aabb()
		var s := aabb.get_longest_axis_size()
		by_size["<1" if s < 1 else ("1-3" if s < 3 else ("3-8" if s < 8 else ("8-20" if s < 20 else "20+")))] += 1
		if cam != null:
			var d := cam.global_position.distance_to(aabb.get_center())
			by_dist["<40" if d < 40 else ("40-100" if d < 100 else ("100-200" if d < 200 else ("200-400" if d < 400 else "400+")))] += 1
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow += 1
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
			surfaces += (gi as MeshInstance3D).mesh.get_surface_count()
		var p := gi.get_parent()
		var pn := str(p.name).rstrip("0123456789_@") if p != null else "?"
		owners[pn] = int(owners.get(pn, 0)) + 1
		# triangles this one draws (after its own draw distance), grouped by what the world built it under
		var tri := _tris(gi)
		if cam != null and gi.visibility_range_end > 0.0 and cam.global_position.distance_to(aabb.get_center()) > gi.visibility_range_end:
			tri = 0
		var top := _top(gi)
		tris[top] = int(tris.get(top, 0)) + tri
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow_tris[top] = int(shadow_tris.get(top, 0)) + tri
	var top := []
	for o in owners:
		top.append([owners[o], o])
	top.sort()
	top.reverse()
	print("[profile] ", JSON.stringify({
		"tag": tag,
		"drawCalls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"visibleGeoms": by_kind, "bySize": by_size, "byDist": by_dist,
		"castShadow": shadow, "tris": _sorted(tris), "shadowTris": _sorted(shadow_tris), "meshSurfaces": surfaces, "topParents": top.slice(0, 15),
		"camera": [cam.global_position, cam.far] if cam != null else null,
	}))
	var dir := OS.get_environment("CHIK_AUDIT_DIR")
	if dir != "":
		get_viewport().get_texture().get_image().save_png(dir.path_join("%s.png" % tag))


func _geoms(n: Node, out: Array = []) -> Array:
	if n is GeometryInstance3D:
		out.append(n)
	for c in n.get_children():
		_geoms(c, out)
	return out


func _hide_small_far() -> int:
	var cam := get_viewport().get_camera_3d()
	var n := 0
	for g in _geoms(get_tree().root):
		var gi := g as GeometryInstance3D
		if not gi.is_visible_in_tree() or cam == null:
			continue
		var aabb := gi.global_transform * gi.get_aabb()
		var s := aabb.get_longest_axis_size()
		var d := cam.global_position.distance_to(aabb.get_center())
		if (s < 3.0 and d > 60.0) or (s < 8.0 and d > 140.0) or (s < 20.0 and d > 260.0):
			gi.visible = false
			n += 1
	return n


func _sorted(d: Dictionary) -> Array:
	var a := []
	for k in d:
		a.append([d[k], k])
	a.sort()
	a.reverse()
	return a.slice(0, 14)


func _mesh_tris(m: Mesh) -> int:
	if m == null:
		return 0
	var t := 0
	for s in m.get_surface_count():
		if m is ArrayMesh:
			var n := (m as ArrayMesh).surface_get_array_index_len(s)
			t += (n if n > 0 else (m as ArrayMesh).surface_get_array_len(s)) / 3
		else:
			var arr := m.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			t += (idx.size() if idx != null and idx.size() > 0 else arr[Mesh.ARRAY_VERTEX].size()) / 3
	return t


func _tris(g: GeometryInstance3D) -> int:
	if g is MultiMeshInstance3D:
		var mm := (g as MultiMeshInstance3D).multimesh
		if mm == null:
			return 0
		var n := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		return _mesh_tris(mm.mesh) * n
	if g is MeshInstance3D:
		return _mesh_tris((g as MeshInstance3D).mesh)
	return 2


## the name of the world-level node this geometry was built under, and its script
func _top(g: Node) -> String:
	var mn := get_tree().get_first_node_in_group("world_main")
	var n := g
	while n.get_parent() != null and n.get_parent() != mn and n.get_parent() != get_tree().root:
		n = n.get_parent()
	var sc: Script = n.get_script()
	return "%s%s" % [str(n.name).rstrip("0123456789_@"), (" (" + sc.resource_path.get_file() + ")") if sc != null else ""]
