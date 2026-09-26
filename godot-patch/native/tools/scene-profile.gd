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
		"castShadow": shadow, "meshSurfaces": surfaces, "topParents": top.slice(0, 15),
		"camera": [cam.global_position, cam.far] if cam != null else null,
	}))


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
