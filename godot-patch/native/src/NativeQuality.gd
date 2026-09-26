## ADAPTIVE QUALITY: the game holds its frame rate by trading detail, one step at a time.
##
## Measured on an iPhone 15 Pro Max (build 115, /client-diag): the full HD world ran at 23 fps
## average, 9 at worst, with 10,390 draw calls a frame. A phone's speed also changes with heat,
## battery saving and what is on screen, so no fixed setting is right. This watches the frame rate
## once the world is up and, when it stays under TARGET_LOW, steps down a ladder; when it has run
## at the cap for a while it steps back up. The HD art and the Full HD user interface are untouched.
##
##   level 0  3D at Full HD, 2x MSAA, sun shadows in 2 cascades to 160 m, full object distances
##   level 1  3D at 90%, shadows to 130 m, object distances 85%
##   level 2  3D at 80%, one shadow cascade to 100 m, object distances 70%
##   level 3  Medium tier, 3D at 70%, shadows to 80 m, object distances 60%
##   level 4  Low tier (build 113's settings, which ran smoothly on this phone), distances 50%
##
## The desktop HD tier drew the sun's shadows in 4 cascades to 620 m (every shadow caster drawn up
## to 4 more times) with SSAO; no level uses that on the phone. The terrain's streaming distance is
## fixed for the session (Main.gd, ChikFeat.native_view_distance): changing it under 32-voxel
## blocks leaves holes. Far detail is trimmed per object instead: every mesh gets a draw distance
## by its size (a 2 m bush stops drawing sooner than a 20 m castle), which the GPU culls for free.
##
## The level is reported by NativeVitals, so the settings each phone settles on are visible.
extends Node

const TARGET_LOW := 45.0     # step down when a window averages below this
const TARGET_HIGH := 54.0    # step up after UP_AFTER seconds at or above this (a 60 Hz phone averages ~57)
const WINDOW := 5.0
const UP_AFTER := 20.0
const START_LEVEL := 1
const MAX_LEVEL := 4

var level := -1
var _fps: Array[float] = []
var _t := 0.0
var _good_for := 0.0
var _cooldown := 0.0
var _applied_tier := -1
var _pinned := false


func _ready() -> void:
	if not ChikFeat.native():
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	var mn = get_tree().get_first_node_in_group("world_main")
	if mn == null or not mn.has_method("set_quality_tier"):
		return
	if level < 0:
		# the world is up: start one step below the top, on phones that get the HD world
		level = START_LEVEL if ChikFeat.native_hd() else 4
		if OS.get_environment("CHIK_QUALITY_LEVEL") != "":  # tests: hold one level
			level = clampi(int(OS.get_environment("CHIK_QUALITY_LEVEL")), 0, MAX_LEVEL)
			_pinned = true
		_build_scenery(mn)
		_apply(mn)
		_cooldown = 8.0  # let loading hitches pass before judging
		return
	# the player changed the quality button: follow it as the new ceiling
	if mn.gfx_tier() != _applied_tier:
		level = maxi(level, _level_for_tier(mn.gfx_tier()))
		_apply(mn)
	if _pinned:
		return
	# no judging while the world is still loading: voxel models are meshed one per frame after entering
	var vm := get_node_or_null("/root/NativeVoxelMesh")
	if vm != null and not (vm.get("_queue") as Array).is_empty():
		_cooldown = maxf(_cooldown, 10.0)
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	_t += delta
	if _t < 1.0:
		return
	_t = 0.0
	_fps.append(Engine.get_frames_per_second())
	if _fps.size() > int(WINDOW):
		_fps.pop_front()
	if _fps.size() < int(WINDOW) or _cooldown > 0.0:
		return
	var avg := 0.0
	for v in _fps:
		avg += v
	avg /= _fps.size()
	if avg < TARGET_LOW and level < MAX_LEVEL:
		level += 1
		_step(mn, "down", avg)
	elif avg >= TARGET_HIGH and level > 0 and level > _level_for_tier(_user_tier(mn)):
		_good_for += 1.0
		if _good_for >= UP_AFTER:
			level -= 1
			_step(mn, "up", avg)
	else:
		_good_for = 0.0


func _step(mn: Node, dir: String, avg: float) -> void:
	print("[native] quality %s to level %d (%.0f fps)" % [dir, level, avg])
	_apply(mn)
	_fps.clear()
	_good_for = 0.0
	_cooldown = 6.0


func _user_tier(mn: Node) -> int:
	var pf = get_tree().get_first_node_in_group("profile")
	if pf != null and "d" in pf:
		return int(pf.d.get("gfx_tier_native", 2))
	return 2


func _level_for_tier(t: int) -> int:
	return 0 if t >= 2 else (3 if t == 1 else 4)


func _apply(mn: Node) -> void:
	var tier := 2 if level <= 2 else (1 if level == 3 else 0)
	if mn.gfx_tier() != tier:
		mn.set_quality_tier(tier)  # resets scale, shadows, fog for that tier
	_applied_tier = tier
	var vp := get_viewport()
	var ws := DisplayServer.window_get_size()
	var fhd := clampf(1080.0 / float(maxi(1, mini(ws.x, ws.y))), 0.5, 1.0)
	var sun = mn.get("_sun")
	vp.scaling_3d_scale = fhd * [1.0, 0.9, 0.8, 0.7, 0.6][clampi(level, 0, 4)] if level < 4 else vp.scaling_3d_scale
	vp.msaa_3d = Viewport.MSAA_2X if level == 0 else Viewport.MSAA_DISABLED
	if sun is DirectionalLight3D and level <= 3:
		var d := sun as DirectionalLight3D
		d.directional_shadow_max_distance = [160.0, 130.0, 100.0, 80.0][level]
		d.directional_shadow_mode = (DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if level <= 1
			else DirectionalLight3D.SHADOW_ORTHOGONAL)
		vp.positional_shadow_atlas_size = 2048 if level <= 1 else 1024
	var env = mn.get("_env")
	if env is Environment:
		(env as Environment).ssao_enabled = false  # the Mobile renderer has none; keep the tier from asking
		if ChikFeat.native_hd():
			# the fog closes where the terrain stops streaming, so the world has no hard edge
			var vd := float(ChikFeat.native_view_distance())
			(env as Environment).fog_depth_begin = vd * 0.55
			(env as Environment).fog_depth_end = vd * 1.02
	_set_ranges([1.0, 0.85, 0.7, 0.6, 0.5][clampi(level, 0, 4)])
	_look(mn, vp)


## OBJECT DRAW DISTANCES. Each mesh in the world stops drawing past a distance that follows its size,
## the way mobile games cull: at 60x its size (a 2 m bush at 120 m, where it is a few pixels tall),
## never under 70 m, never past the streamed terrain; anything 40 m or larger always draws. A range
## the game set itself is kept. New meshes (players, drops, buildings) get theirs as they appear.
const RANGE_PER_METRE := 60.0
var _range_scale := 1.0
var _world: Node3D = null


func _set_ranges(scale: float) -> void:
	_range_scale = scale
	var mn := get_tree().get_first_node_in_group("world_main") as Node3D
	if mn == null:
		return
	if _world != mn:
		_world = mn
		get_tree().node_added.connect(func(n: Node):
			if n is GeometryInstance3D and is_instance_valid(_world) and _world.is_ancestor_of(n):
				_range.call_deferred(n))
	for n in mn.find_children("*", "GeometryInstance3D", true, false):
		_range(n)


func _range(g: GeometryInstance3D) -> void:
	if not is_instance_valid(g) or not g.is_inside_tree():
		return
	if g.has_meta("chik_range_own"):
		return
	if not g.has_meta("chik_range"):
		if g.visibility_range_end > 0.0:
			g.set_meta("chik_range_own", true)  # the game chose this one
			return
		var size := (g.global_transform.basis * g.get_aabb().size).abs()
		var longest := maxf(size.x, maxf(size.y, size.z))
		if longest >= 40.0 or longest <= 0.0 or g.name == "GrassField":
			g.set_meta("chik_range_own", true)
			return
		g.set_meta("chik_range", clampf(longest * RANGE_PER_METRE, 70.0, float(ChikFeat.native_view_distance()) * 1.1))
	g.visibility_range_end = float(g.get_meta("chik_range")) * _range_scale
	g.visibility_range_end_margin = 4.0


## GRASS AND CLOUDS. The phone build never made them (Main skips both on phones). The grass is one
## MultiMesh of small wind-blown tufts over the island's grass surfaces; its density follows the
## quality level, so it never costs the frame rate the ladder is protecting.
##
## The game builds its grass as ONE MultiMesh over the whole island (103,719 tufts, 0.9 M triangles),
## so every tuft is drawn every frame wherever the camera looks. Here it is cut into GRASS_TILE-metre
## tiles that each stop drawing past GRASS_RANGE: only the grass around the player is drawn, which
## is where a 1.6 m tuft is more than a pixel or two, and the density can stay high.
const GRASS_SHARE := [1.0, 0.9, 0.75, 0.6, 0.45]
const GRASS_RANGE := [150.0, 130.0, 115.0, 100.0, 80.0]
const GRASS_TILE := 48.0
var _grass_tiles: Array[MultiMeshInstance3D] = []


func _build_scenery(mn: Node) -> void:
	if mn.get_node_or_null("GrassField") == null and mn.has_method("_build_grass"):
		mn.call("_build_grass")
	_tile_grass(mn)
	if mn.get_node_or_null("Clouds") == null and mn.has_method("_build_clouds"):
		mn.call("_build_clouds")


## THE LOOK: a little glow on bright light, richer colour, sun-lit fog and debanding, on the
## upper levels; grass at every level; clouds while there is headroom. set_quality_tier resets
## these, so they are applied after it every time.
func _look(mn: Node, vp: Viewport) -> void:
	var grass := mn.get_node_or_null("GrassField") as MultiMeshInstance3D
	if grass != null and grass.multimesh != null:
		grass.visible = true
		var lv := clampi(level, 0, 4)
		if _grass_tiles.is_empty():
			grass.multimesh.visible_instance_count = int(grass.multimesh.instance_count * GRASS_SHARE[lv])
		else:
			grass.multimesh.visible_instance_count = 0  # the tiles draw it (the tier code may reset this)
			for t in _grass_tiles:
				t.multimesh.visible_instance_count = int(t.multimesh.instance_count * GRASS_SHARE[lv])
				t.visibility_range_end = GRASS_RANGE[lv]
	var clouds := mn.get_node_or_null("Clouds") as Node3D
	if clouds != null:
		clouds.visible = level <= 2
	vp.use_debanding = level <= 2
	var env = mn.get("_env")
	if env is Environment:
		var e := env as Environment
		e.adjustment_enabled = true
		e.adjustment_saturation = 1.16
		e.adjustment_contrast = 1.06
		e.adjustment_brightness = 1.02
		e.fog_sun_scatter = 0.25
		e.glow_enabled = level <= 2
		if e.glow_enabled:
			e.glow_intensity = 0.4
			e.glow_strength = 0.9
			e.glow_bloom = 0.04
			e.glow_hdr_threshold = 1.1
			e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT


func _tile_grass(mn: Node) -> void:
	var g := mn.get_node_or_null("GrassField") as MultiMeshInstance3D
	if g == null or g.multimesh == null or not _grass_tiles.is_empty():
		return
	var mm := g.multimesh
	var stride := 12 + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)
	var n := mm.instance_count
	var buf := mm.buffer
	if n == 0 or mm.transform_format != MultiMesh.TRANSFORM_3D or buf.size() != n * stride:
		return
	var bins := {}
	for i in n:
		var o := i * stride
		var k := Vector2i(floori(buf[o + 3] / GRASS_TILE), floori(buf[o + 11] / GRASS_TILE))
		if not bins.has(k):
			bins[k] = PackedInt32Array()
		bins[k].append(i)
	for k in bins:
		var ids: PackedInt32Array = bins[k]
		var data := PackedFloat32Array()
		data.resize(ids.size() * stride)
		var w := 0
		for i in ids:
			for j in stride:
				data[w + j] = buf[i * stride + j]
			w += stride
		var part := MultiMesh.new()
		part.transform_format = MultiMesh.TRANSFORM_3D
		part.use_colors = mm.use_colors
		part.use_custom_data = mm.use_custom_data
		part.mesh = mm.mesh
		part.instance_count = ids.size()
		part.buffer = data
		var t := MultiMeshInstance3D.new()
		t.name = "GrassTile"
		t.multimesh = part
		t.material_override = g.material_override
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.visibility_range_end = GRASS_RANGE[0]
		t.visibility_range_end_margin = 8.0
		g.add_child(t)
		_grass_tiles.append(t)
	mm.visible_instance_count = 0
	print("[native] grass: %d tufts in %d tiles of %d m" % [n, _grass_tiles.size(), int(GRASS_TILE)])
