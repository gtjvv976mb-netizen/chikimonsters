## ADAPTIVE QUALITY: the game holds its frame rate by trading detail, one step at a time.
##
## Measured on an iPhone 15 Pro Max (build 115, /client-diag): the full HD world ran at 23 fps
## average, 9 at worst. A phone's speed also changes with heat, battery saving and what is on
## screen, so no fixed setting is right. This watches the frame rate once the world is up and,
## when it stays under TARGET_LOW, steps down a ladder; when it has run at the cap for a while
## it steps back up. The HD art and the Full HD user interface are untouched — only render
## resolution, draw distance, shadows and finally the graphics tier move.
##
##   level 0  Full HD 3D, desktop draw distance, HD shadows
##   level 1  3D at 90% of Full HD, draw distance 640
##   level 2  3D at 80%, draw distance 480, lighter shadows
##   level 3  Medium tier, 3D at 70%
##   level 4  Low tier (build 113's settings, which ran smoothly on this phone)
##
## The level is reported by NativeVitals, so the settings each phone settles on are visible.
extends Node

const TARGET_LOW := 50.0     # step down when a window averages below this
const TARGET_HIGH := 58.0    # step up after UP_AFTER seconds at or above this
const WINDOW := 4.0
const UP_AFTER := 45.0
const START_LEVEL := 1
const MAX_LEVEL := 4

var level := -1
var _fps: Array[float] = []
var _t := 0.0
var _good_for := 0.0
var _cooldown := 0.0
var _applied_tier := -1


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
		_build_scenery(mn)
		_apply(mn)
		_cooldown = 8.0  # let loading hitches pass before judging
		return
	# the player changed the quality button: follow it as the new ceiling
	if mn.gfx_tier() != _applied_tier:
		level = maxi(level, _level_for_tier(mn.gfx_tier()))
		_apply(mn)
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
		mn.set_quality_tier(tier)  # resets scale, distance, shadows for that tier
	_applied_tier = tier
	var vp := get_viewport()
	var ws := DisplayServer.window_get_size()
	var fhd := clampf(1080.0 / float(maxi(1, mini(ws.x, ws.y))), 0.5, 1.0)
	var terr: Node = mn.get_node_or_null("Terrain")
	var sun = mn.get("_sun")
	match level:
		0:
			vp.scaling_3d_scale = fhd
		1:
			vp.scaling_3d_scale = fhd * 0.9
			if terr != null:
				terr.set("max_view_distance", 640)
		2:
			vp.scaling_3d_scale = fhd * 0.8
			if terr != null:
				terr.set("max_view_distance", 480)
			vp.positional_shadow_atlas_size = 2048
			if sun is DirectionalLight3D:
				sun.directional_shadow_max_distance = 260.0
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		3:
			vp.scaling_3d_scale = fhd * 0.7
		_:
			pass  # Low tier's own settings
	_look(mn, vp)


## GRASS AND CLOUDS. The phone build never made them (Main skips both on phones). The grass is one
## MultiMesh of small wind-blown tufts over the island's grass surfaces; its density follows the
## quality level, so it never costs the frame rate the ladder is protecting.
const GRASS_SHARE := [1.0, 0.8, 0.6, 0.45, 0.3]


func _build_scenery(mn: Node) -> void:
	if mn.get_node_or_null("GrassField") == null and mn.has_method("_build_grass"):
		mn.call("_build_grass")
	if mn.get_node_or_null("Clouds") == null and mn.has_method("_build_clouds"):
		mn.call("_build_clouds")


## THE LOOK: a little glow on bright light, richer colour, sun-lit fog and debanding, on the
## upper levels; grass at every level; clouds while there is headroom. set_quality_tier resets
## these, so they are applied after it every time.
func _look(mn: Node, vp: Viewport) -> void:
	var grass := mn.get_node_or_null("GrassField") as MultiMeshInstance3D
	if grass != null and grass.multimesh != null:
		grass.visible = true
		grass.multimesh.visible_instance_count = int(grass.multimesh.instance_count * GRASS_SHARE[clampi(level, 0, 4)])
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
