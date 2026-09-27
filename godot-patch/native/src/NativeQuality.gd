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
##   level 4  Low tier (build 113's settings, which ran smoothly on this phone), 3D at 60%, one
##            shadow cascade to 64 m, object distances 50%
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
var _applied_pick := -1          # the player's pick when the settings were last applied
var _pinned := false
var _setup_world: Node = null    # the world the settings below were made for
var _up_after := UP_AFTER        # doubles each time a step up is undone soon after (no flip-flopping)
var _last_up_at := -1000.0


func _ready() -> void:
	if not ChikFeat.native():
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if n is GeometryInstance3D and is_instance_valid(_world) and _world.is_ancestor_of(n):
		_range.call_deferred(n)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	var mn = get_tree().get_first_node_in_group("world_main")
	if mn == null or not mn.has_method("set_quality_tier"):
		return
	if level < 0 or mn != _setup_world:
		# a world is up (the first one, or a new one after an account switch reloaded the scene)
		if level < 0 and OS.get_environment("CHIK_QUALITY_LEVEL") != "":  # tests: hold one level
			level = clampi(int(OS.get_environment("CHIK_QUALITY_LEVEL")), 0, MAX_LEVEL)
			_pinned = true
		elif not _pinned:
			# start one step below the top on phones that get the HD world, never above the player's
			# pick; on every world, since the account a reload brings in has its own pick
			level = maxi(START_LEVEL if ChikFeat.native_hd() else 4, _ceiling(mn))
		_setup_world = mn
		_grass_tiles.clear()  # the old world's tiles were freed with it
		_fps.clear()
		_good_for = 0.0
		_t = 0.0
		_up_after = UP_AFTER
		_build_scenery(mn)
		_apply(mn)
		_cooldown = 8.0  # let loading hitches pass before judging
		return
	# the player changed the quality button: their pick sets the level, both ways, and is the ceiling
	var ut := user_tier()
	if mn.gfx_tier() != _applied_tier or ut != _applied_pick:
		level = maxi(_level_for_tier(ut), _ceiling(mn)) if ut < 2 else maxi(START_LEVEL, _ceiling(mn))
		_fps.clear()
		_good_for = 0.0
		_cooldown = 6.0
		_up_after = UP_AFTER
		_apply(mn)
	if _pinned:
		return
	# no judging while the world is still loading: voxel models are being meshed after entering
	var vm := get_node_or_null("/root/NativeVoxelMesh")
	if vm != null and not (vm.get("_queue") as Array).is_empty():
		_cooldown = maxf(_cooldown, 10.0)
		return
	if _cooldown > 0.0:
		_cooldown -= minf(delta, 0.25)  # the first frame back in the app spans the time away
		_t = 0.0
		return  # the frames right after a switch are not sampled
	_t += delta
	if _t < 1.0:
		return
	_t = 0.0
	_fps.append(Engine.get_frames_per_second())
	if _fps.size() > int(WINDOW):
		_fps.pop_front()
	if _fps.size() < int(WINDOW):
		return
	var avg := 0.0
	for v in _fps:
		avg += v
	avg /= _fps.size()
	if _last_up_at > 0.0 and _now() - _last_up_at > 45.0:
		_up_after = UP_AFTER  # the last step up held
		_last_up_at = -1000.0
	if avg < TARGET_LOW and level < MAX_LEVEL:
		if _now() - _last_up_at < 45.0:
			_up_after = minf(_up_after * 2.0, 600.0)  # that step up did not hold: wait longer next time
		_last_up_at = -1000.0
		level += 1
		_step(mn, "down", avg)
	elif avg >= TARGET_HIGH and level > _ceiling(mn):
		_good_for += 1.0
		if _good_for >= _up_after:
			level -= 1
			_last_up_at = _now()
			_step(mn, "up", avg)
	else:
		_good_for = 0.0


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED,
			NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		# the main loop stops while the app is away, and the engine's fps count spans the gap on
		# the way back (1 to 60, by timing): those seconds are not the phone's speed
		_fps.clear()
		_t = 0.0
		_good_for = 0.0
		_cooldown = maxf(_cooldown, 3.0)


func _step(mn: Node, dir: String, avg: float) -> void:
	print("[native] quality %s to level %d (%.0f fps)" % [dir, level, avg])
	_apply(mn)
	_fps.clear()
	_good_for = 0.0
	_cooldown = 6.0


## the player's graphics pick (GameHUD's quality button, saved in the profile). The light-world
## phones stop at Medium, as GameHUD and cycle_quality allow them. The button shows and steps from
## this, not from Main's tier, which the ladder moves under it.
func user_tier() -> int:
	var t := 2 if ChikFeat.native_hd() else 0
	var pf = get_tree().get_first_node_in_group("profile")
	if pf != null and "d" in pf:
		t = int(pf.d.get("gfx_tier_native", t))
	return t if ChikFeat.native_hd() else mini(t, 1)


## the best (lowest) level the ladder may climb to
func _ceiling(mn: Node) -> int:
	return _level_for_tier(user_tier())


func _level_for_tier(t: int) -> int:
	return 0 if t >= 2 else (3 if t == 1 else 4)


func _apply(mn: Node) -> void:
	var tier := 2 if level <= 2 else (1 if level == 3 else 0)
	if mn.gfx_tier() != tier:
		mn.set_quality_tier(tier)  # resets scale, shadows, fog for that tier
	_applied_tier = tier
	_applied_pick = user_tier()
	var vp := get_viewport()
	var ws := DisplayServer.window_get_size()
	var fhd := clampf(1080.0 / float(maxi(1, mini(ws.x, ws.y))), 0.5, 1.0)
	var sun = mn.get("_sun")
	if level < 4 or ChikFeat.native_hd():
		var sc: float = fhd * [1.0, 0.9, 0.8, 0.7, 0.6][clampi(level, 0, 4)]
		# the light-world phones keep Main's phone clamp (0.5 at Low): they got the light world for
		# lack of memory
		vp.scaling_3d_scale = sc if ChikFeat.native_hd() else minf(sc, 0.7)
	vp.msaa_3d = Viewport.MSAA_2X if (level == 0 and ChikFeat.native_hd()) else Viewport.MSAA_DISABLED
	if sun is DirectionalLight3D:
		# every level, the last too: the Low tier's own sun (2 cascades to 96 m) costs more than level 3's
		var d := sun as DirectionalLight3D
		d.directional_shadow_max_distance = [160.0, 130.0, 100.0, 80.0, 64.0][clampi(level, 0, 4)]
		d.directional_shadow_mode = (DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if level <= 1
			else DirectionalLight3D.SHADOW_ORTHOGONAL)
		vp.positional_shadow_atlas_size = 2048 if level <= 1 else 1024
	var env = mn.get("_env")
	if env is Environment:
		(env as Environment).ssao_enabled = false  # the Mobile renderer has none; keep the tier from asking
		# the fog closes where the terrain stops streaming, so the world has no hard edge (Main's
		# phone fog is sized for the per-tier distances the phone no longer streams)
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
	_world = mn  # _on_node_added gives new meshes in it their range
	for n in mn.find_children("*", "GeometryInstance3D", true, false):
		_range(n)


func _range(g: GeometryInstance3D) -> void:
	if not is_instance_valid(g) or not g.is_inside_tree():
		return
	if not is_instance_valid(_world) or g.get_viewport() != _world.get_viewport():
		# another camera draws it (the Chikiseum arena's own world 150 m off, a portrait): the
		# player's distances would hide it there
		if g.has_meta("chik_range"):
			g.remove_meta("chik_range")
			g.visibility_range_end = 0.0
		return
	if g.has_meta("chik_range_own"):
		return
	if not g.has_meta("chik_range"):
		if g.visibility_range_end > 0.0:
			g.set_meta("chik_range_own", true)  # the game chose this one
			return
		var size := (g.global_transform.basis * g.get_aabb().size).abs()
		var longest := maxf(size.x, maxf(size.y, size.z))
		# markers meant to be seen from afar (the waypoint pin, fixed-size labels) keep drawing
		var marker := (g is SpriteBase3D and (g as SpriteBase3D).no_depth_test) \
			or (g is Label3D and ((g as Label3D).no_depth_test or (g as Label3D).fixed_size))
		if longest >= 40.0 or longest <= 0.0 or g.name == "GrassField" or marker:
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
	# the tiles hold their own copies: drop the original's buffers (CPU and GPU, ~13 MB), and the
	# count Main cached from it, so its tier code sets 0 visible instead of 45% of a count now gone
	mm.instance_count = 0
	mn.set("_grass_full", 0)
	print("[native] grass: %d tufts in %d tiles of %d m" % [n, _grass_tiles.size(), int(GRASS_TILE)])
