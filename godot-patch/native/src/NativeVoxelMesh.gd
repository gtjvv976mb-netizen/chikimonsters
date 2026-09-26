## VOXEL MODELS AS REAL MESHES: the same pixels at a fraction of the triangles.
##
## Every building, tree, gather node and prop in the world is a voxel model the game draws as a
## MultiMesh of cubes: 12 triangles for every voxel, including the faces pressed against another
## cube that nobody can see. Measured on the phone's HD world (tools/scene-profile.gd): 34 million
## triangles a frame, 6.5 M of them trees and 3.8 M the town wall. Mobile games draw well under a
## million.
##
## This turns each such model, once, into one mesh of only its visible faces, with neighbouring
## faces of the same colour merged (Voxel Tools' greedy cubes mesher, the one the terrain already
## uses). It looks identical: same cubes, same colours, same material, same place. The MultiMesh
## node stays where it was, so game code that moves, turns, hides or swaps it keeps working; it
## only gets a one-instance MultiMesh holding the new mesh. A model it cannot reproduce exactly
## (non-cube or rotated instances, a mismatch in bounds) is left as the game made it.
##
## Models convert one per frame while the world loads, and a model shared by many instances (every
## tree of a kind) converts once.
extends Node

const MIN_CUBES := 400        # smaller models are cheap already, and some are read back by the game

var _done := {}      # original MultiMesh -> converted MultiMesh, or null when left alone
var _queue: Array[MultiMesh] = []
var _users := {}     # original MultiMesh -> the instances using it
var _world: Node = null
var tris_before := 0
var tris_after := 0
var converted := 0


func _ready() -> void:
	if not ChikFeat.native():
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_added)


func _on_added(n: Node) -> void:
	if n is MultiMeshInstance3D:
		_watch.call_deferred(n)


func _watch(mmi: MultiMeshInstance3D) -> void:
	if not is_instance_valid(mmi) or not mmi.is_inside_tree():
		return
	var mm := mmi.multimesh
	if mm == null:
		return
	if _done.has(mm):
		if _done[mm] != null:
			mmi.multimesh = _done[mm]
		return
	if not _candidate(mm):
		return
	if not _users.has(mm):
		_users[mm] = []
		_queue.append(mm)
	_users[mm].append(mmi)


func _process(_d: float) -> void:
	if _world == null or not is_instance_valid(_world):
		_world = get_tree().get_first_node_in_group("world_main")
		if _world != null:
			# models built before this autoload saw them
			for n in _world.find_children("*", "MultiMeshInstance3D", true, false):
				_watch(n)
	# the game swaps some models back (a gather node regrowing): put the converted one back in
	if Engine.get_process_frames() % 30 == 0 and _world != null:
		for n in _world.find_children("*", "MultiMeshInstance3D", true, false):
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			if mm != null and _done.get(mm) != null:
				(n as MultiMeshInstance3D).multimesh = _done[mm]
	if _queue.is_empty():
		return
	var mm: MultiMesh = _queue.pop_front()
	var out := convert_multimesh(mm)
	_done[mm] = out
	if out != null:
		converted += 1
		for mmi in _users.get(mm, []):
			if is_instance_valid(mmi) and mmi.multimesh == mm:
				mmi.multimesh = out
		if _queue.is_empty():
			print("[native] voxel models meshed: %d, triangles %d -> %d" % [converted, tris_before, tris_after])
	_users.erase(mm)


static func _candidate(mm: MultiMesh) -> bool:
	if mm.instance_count < MIN_CUBES or not mm.use_colors or mm.use_custom_data:
		return false
	if mm.transform_format != MultiMesh.TRANSFORM_3D or mm.visible_instance_count >= 0:
		return false
	var box := mm.mesh as BoxMesh
	return box != null and is_equal_approx(box.size.x, box.size.y) and is_equal_approx(box.size.x, box.size.z)


## the model as one greedy-meshed MultiMesh instance, or null when it cannot be reproduced exactly
func convert_multimesh(mm: MultiMesh) -> MultiMesh:
	var box := mm.mesh as BoxMesh
	var n := mm.instance_count
	var buf := mm.buffer  # per instance: 12 floats of transform (rows of basis | origin), 4 of colour
	if buf.size() != n * 16:
		return null
	# all instances the same axis-aligned uniform scale
	var s := buf[0]
	if s <= 0.0:
		return null
	var e := box.size.x * s  # the cube's edge
	var centers := PackedVector3Array()
	centers.resize(n)
	for i in n:
		var o := i * 16
		if not (is_equal_approx(buf[o], s) and is_equal_approx(buf[o + 5], s) and is_equal_approx(buf[o + 10], s)):
			return null
		if absf(buf[o + 1]) + absf(buf[o + 2]) + absf(buf[o + 4]) + absf(buf[o + 6]) + absf(buf[o + 8]) + absf(buf[o + 9]) > 0.0001:
			return null
		if buf[o + 15] < 0.999:
			return null  # a see-through cube: keep the game's own drawing of it
		centers[i] = Vector3(buf[o + 3], buf[o + 7], buf[o + 11])
	# the grid: usually one cube edge apart; some models draw their cubes a little larger than the
	# grid so neighbours overlap (Gather: 3%), so the spacing is measured when the edge does not fit
	var a := e
	var cells := _lattice(centers, a)
	if cells.is_empty():
		a = _spacing(centers, e)
		if a <= 0.0:
			return null
		cells = _lattice(centers, a)
		if cells.is_empty():
			return null
	var f: Vector3 = cells[0]
	var cmin: Vector3i = cells[1]
	var idx: PackedInt32Array = cells[2]
	# mesh in chunks of CHUNK^3 cells: memory stays small whatever the model's extent
	var chunks := {}
	for i in n:
		var k := Vector3i(idx[i * 3] / CHUNK, idx[i * 3 + 1] / CHUNK, idx[i * 3 + 2] / CHUNK)
		if not chunks.has(k):
			chunks[k] = PackedInt32Array()
		chunks[k].append(i)
	var mesher := VoxelMesherCubes.new()
	mesher.color_mode = VoxelMesherCubes.COLOR_RAW
	mesher.greedy_meshing_enabled = true
	var mat: Material = box.material
	var all := []
	all.resize(Mesh.ARRAY_MAX)
	var vcount := 0
	var vb := VoxelBuffer.new()
	vb.set_channel_depth(VoxelBuffer.CHANNEL_COLOR, VoxelBuffer.DEPTH_32_BIT)
	for k in chunks:
		var base := Vector3i(k) * CHUNK
		# the mesher reads a 1-voxel border, left as air: the faces it adds where chunks meet are
		# inside the model, where nobody sees them, and cost a few triangles on the cut planes
		vb.create(CHUNK + 2, CHUNK + 2, CHUNK + 2)
		_fill(vb, chunks[k], idx, buf, base)
		var m := mesher.build_mesh(vb, [mat, mat])
		if m == null or m.get_surface_count() == 0:
			continue
		var arr := m.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var off := Vector3(base)
		for vi in verts.size():
			verts[vi] += off
		arr[Mesh.ARRAY_VERTEX] = verts
		var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if vcount > 0:
			for ii in ind.size():
				ind[ii] += vcount
		arr[Mesh.ARRAY_INDEX] = ind
		for slot in Mesh.ARRAY_MAX:
			if arr[slot] == null:
				continue
			if all[slot] == null:
				all[slot] = arr[slot]
			else:
				all[slot].append_array(arr[slot])
		vcount += verts.size()
	if vcount == 0:
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, all)
	mesh.surface_set_material(0, mat)
	var xf := Transform3D(Basis.from_scale(Vector3(a, a, a)), (Vector3(cmin) + f) * a)
	# the check: the new model covers the cubes' bounds (less their overlap, when they overlap)
	var want := mm.get_aabb()
	var got := xf * mesh.get_aabb()
	var tol := a * 0.01 + absf(e - a) * 1.8
	if (got.position - want.position).length() > tol or (got.size - want.size).length() > tol * 2.0:
		push_warning("voxel mesh bounds differ, model left as cubes: %s vs %s" % [got, want])
		return null
	var out := MultiMesh.new()
	out.transform_format = MultiMesh.TRANSFORM_3D
	out.mesh = mesh
	out.instance_count = 1
	out.set_instance_transform(0, xf)
	tris_before += n * 12
	tris_after += (all[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return out


const CHUNK := 64


## [lattice offset, lowest cell, cell index triples from the lowest] or [] when the centres are not
## on a grid of this spacing
static func _lattice(centers: PackedVector3Array, a: float) -> Array:
	var n := centers.size()
	var f := centers[0] / a - Vector3(0.5, 0.5, 0.5)
	f -= f.round()
	var raw := PackedInt32Array()
	raw.resize(n * 3)
	var cmin := Vector3i(1 << 30, 1 << 30, 1 << 30)
	for i in n:
		var q := centers[i] / a - Vector3(0.5, 0.5, 0.5) - f
		var c := Vector3i(q.round())
		if (q - Vector3(c)).length_squared() > 0.0004:
			return []
		raw[i * 3] = c.x
		raw[i * 3 + 1] = c.y
		raw[i * 3 + 2] = c.z
		cmin = cmin.min(c)
	for i in n:
		raw[i * 3] -= cmin.x
		raw[i * 3 + 1] -= cmin.y
		raw[i * 3 + 2] -= cmin.z
	return [f, cmin, raw]


## the grid spacing of cube centres: the smallest gap between neighbouring centres on any axis
static func _spacing(centers: PackedVector3Array, e: float) -> float:
	var best := INF
	for axis in 3:
		var vals := PackedFloat32Array()
		for i in mini(centers.size(), 4000):
			vals.append(centers[i][axis])
		vals.sort()
		for i in range(1, vals.size()):
			var d := vals[i] - vals[i - 1]
			if d > e * 0.5 and d < best:
				best = d
	return best if best < e * 1.01 else -1.0


## the chunk's voxels into the buffer, inside its 1-voxel border
static func _fill(vb: VoxelBuffer, ids: PackedInt32Array, idx: PackedInt32Array, buf: PackedFloat32Array, base: Vector3i) -> void:
	for i in ids:
		var x := idx[i * 3] - base.x + 1
		var y := idx[i * 3 + 1] - base.y + 1
		var z := idx[i * 3 + 2] - base.z + 1
		var o := i * 16 + 12
		vb.set_voxel(Color(buf[o], buf[o + 1], buf[o + 2], 1.0).to_rgba32(), x, y, z, VoxelBuffer.CHANNEL_COLOR)
