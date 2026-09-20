extends Node3D
# ============================================================================================
# Temple3D — the Wicked Temple's hall as a REAL 3D room, with the cast as 2D billboards.
# ============================================================================================
# This replaces the hand-drawn 2D hall. The 2D one faked depth by foreshortening its flagstones,
# which is a trick that works right up until the player looks at it: the pillars had painted height,
# the floor had implied height, and nothing in the scene could ever occlude anything else. Here the
# room is actual geometry and the perspective is computed rather than drawn.
#
# THE ONE DECISION EVERYTHING ELSE FOLLOWS FROM: GAMEPLAY STAYS IN THE ORIGINAL PIXEL PLANE.
# The recognizable hall, spawn, altar and exit keep their measured coordinates; four side sanctums
# extend that same plane rather than introducing a second ruler. 3D enters at one line — px2m() —
# which lays the plane onto the world's XZ. Movement, triggers and the party formation therefore use
# exactly the same region and collision truth as the 2D fallback.
#
# THE CAMERA IS LOCKED IN YAW, AND THAT IS NOT LAZINESS. The cast has four drawn directions. If the
# camera can orbit, the sheet's "north" stops being the screen's north: the character faces away
# from you in sheet space while the camera has swung ninety degrees, and they read as walking
# sideways. This is the exact reason the Pokemon line eventually abandoned sprites for models. The
# hall gives up free look; the rest of Chikoria keeps it.
#
# THE HALL HAS NO CEILING, ON PURPOSE. At PITCH_DEG 38 and CAM_DIST 11 the camera sits about 7.8 m
# above the target. Any roof below that height puts the camera inside it. Fixed-angle interiors in
# this genre simply do not model the roof or the near wall, and neither does this one.

signal sigil_reached(el: String)
signal door_reached

const NP := preload("res://Nameplate.gd")
const WICKED_FLOOR_TEX := preload("res://wicked_temple_floor_v2.png")
const WICKED_WALL_TEX := preload("res://wicked_temple_wall_v2.png")

# ---- the gameplay plane, in the ORIGINAL pixel space (unchanged from Temple2D) ----------------
const HALL_W := 2400.0
const HALL_H := 1400.0
const WALL_L := 96.0
const WALL_R := 2304.0
const FLOOR_TOP := 176.0
const FLOOR_BOT := 1336.0
const RENDER_FLOOR_BOT := 1800.0 # render-only forecourt; navigation remains unchanged
const DOOR_X0 := 1120.0
const DOOR_X1 := 1280.0
const TILE := 48.0
const SPEED := 260.0
const NEAR_R := 90.0
const SPAWN := Vector2(1200.0, 1288.0)
const DOOR_PLATE := Rect2(1128.0, 1332.0, 144.0, 92.0)
const DOOR_ARM_R := 200.0
const CARPET := Rect2(1090.0, 380.0, 220.0, 956.0)

# The original hall remains the spine of the temple, but each side is now one continuous wing
# rather than two disconnected shoeboxes.  Geometry, navigation and the horde arenas all share
# these measured rectangles.  The connector rectangles overlap both the hall and wing by a small
# amount so a feet box can cross every doorway without finding a one-pixel crack in the union.
const WEST_WING := Rect2(-920.0, FLOOR_TOP, 880.0, FLOOR_BOT - FLOOR_TOP)
const EAST_WING := Rect2(2440.0, FLOOR_TOP, 880.0, FLOOR_BOT - FLOOR_TOP)
const WEST_UPPER_CONNECTOR := Rect2(-60.0, 410.0, 216.0, 220.0)
const WEST_LOWER_CONNECTOR := Rect2(-60.0, 870.0, 216.0, 220.0)
const EAST_UPPER_CONNECTOR := Rect2(2244.0, 410.0, 216.0, 220.0)
const EAST_LOWER_CONNECTOR := Rect2(2244.0, 870.0, 216.0, 220.0)
const PLAYABLE_REGIONS: Array[Rect2] = [
	Rect2(WALL_L, FLOOR_TOP, WALL_R - WALL_L, FLOOR_BOT - FLOOR_TOP),
	Rect2(1100.0, 1312.0, 200.0, 112.0),
	WEST_WING,
	WEST_UPPER_CONNECTOR,
	WEST_LOWER_CONNECTOR,
	EAST_WING,
	EAST_UPPER_CONNECTOR,
	EAST_LOWER_CONNECTOR,
]
const GAMEPLAY_BOUNDS := Rect2(-920.0, FLOOR_TOP, 4240.0, DOOR_PLATE.end.y - FLOOR_TOP)

const PILLARS: Array[Vector2] = [
	Vector2(820.0, 480.0), Vector2(1580.0, 480.0),
	Vector2(820.0, 760.0), Vector2(1580.0, 760.0),
	Vector2(820.0, 1040.0), Vector2(1580.0, 1040.0),
]
const PLATE_POS := {
	"Water": Vector2(-480.0, 520.0),
	"Fire": Vector2(2880.0, 520.0),
	"Beast": Vector2(-480.0, 980.0),
	"Storm": Vector2(2880.0, 980.0),
	"Light": Vector2(1200.0, 470.0),
}

# ---- the party trail: identical constants to Temple2D, identical solve ------------------------
const PARTY_SLOTS: Array[Vector2] = [
	Vector2(-92.0, -100.0), Vector2(92.0, -100.0), Vector2(0.0, -186.0),
]
const FOLLOW_RATE := 4.6
const FOLLOW_MAX := SPEED * 1.5
const FOLLOW_SNAP := 620.0
const FOLLOW_STOP := 9.0
const FOLLOW_GO := 17.0
const PARTY_SEP := 92.0
const POST_R := 13.0
const DEADBAND := 1.30

# ---- the 3D read ------------------------------------------------------------------------------
# PX2M sets how big the room is in metres, and it is chosen from how tall a character should stand
# in frame, not from a guess about architecture. A 96 px cell becomes 1.9 m; the character inside it
# is about 1.7 m. Visible world height at CAM_DIST 11 and FOV 40 is 2*11*tan(20 deg) = 8.01 m, so
# the character occupies 21% of frame height — the band this genre sits in.
const PX2M := 1.9 / 96.0
const PITCH_DEG := 38.0
const CAM_FOV := 40.0
const CAM_DIST := 11.0
const CAM_AIM_Y := 1.0            # aim at the chest, NOT the feet: aiming low tips the horizon
const CAM_DECAY := 8.0            # framerate-independent smoothing, ~0.125 s time constant
const WALL_H := 5.4
const CHAR_CELL_M := 1.9

var _avatar := ""
var _player: Node3D = null
var _rig: Node3D = null
var _grim_rig: Node3D = null
var _foe_body: Node3D = null
var _foe_rig: Node3D = null
var _foe_is_grim := false
var _cam: Camera3D = null
var _actors: Node3D = null
var _plates := {}
var _plate_light: OmniLight3D = null
var _solids: Array[Rect2] = []
var _lit := ""
var _sig_fired := false
var _door_in := false
var _door_armed := false
var _input_on := true
var _dbg_dir := Vector2.ZERO
var _face_dir := Vector2.DOWN
var _walking := false
var _low := false
var _ppos := SPAWN                # the player's position IN THE GAMEPLAY PLANE (px)
var _tap_to := Vector2.ZERO
var _has_tap := false
var _party: Array = []
var _heading := -PI * 0.5
var _plast := SPAWN
var _cam_pos := Vector3.ZERO
var _cam_ready := false
var _flames: Array = []
var _ft := 0.0
var _material_cache: Dictionary = {}
var _mesh_cache: Dictionary = {}
var _shared_flame_tex: Texture2D = null
var _shared_blob_tex: Texture2D = null
var _shared_rune_tex: Texture2D = null
var _world_light_count := 0

# ================================ coordinates ==================================================
# THE WHOLE 2D-TO-3D BRIDGE, IN ONE FUNCTION. The gameplay plane's +y runs toward the door; the
# world's +z runs toward the camera. They are the same direction, so the mapping is a scale and
# nothing else — no flips, no swaps, nothing to get backwards later.
static func px2m(p: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(p.x * PX2M, y, p.y * PX2M)


# A compact, read-only seam for release probes.  The dimensions are reported in both legacy plane
# pixels and world metres so a future camera or combat pass cannot silently shrink the wings back
# into one-screen rooms while the geometry still parses.
func debug_world_metrics() -> Dictionary:
	return {
		"px2m": PX2M,
		"hall_px": Vector2(WALL_R - WALL_L, FLOOR_BOT - FLOOR_TOP),
		"hall_m": Vector2(WALL_R - WALL_L, FLOOR_BOT - FLOOR_TOP) * PX2M,
		"west_wing": WEST_WING,
		"east_wing": EAST_WING,
		"wing_m": WEST_WING.size * PX2M,
		"connectors": [WEST_UPPER_CONNECTOR, WEST_LOWER_CONNECTOR,
			EAST_UPPER_CONNECTOR, EAST_LOWER_CONNECTOR],
		"plates": PLATE_POS.duplicate(true),
		"gameplay_bounds": GAMEPLAY_BOUNDS,
	}


# Legacy ritual mode uses the elemental court seals as interactive landmarks. Horde mode overrides
# this because its encounters and waypoint already communicate the active sanctum.
func _show_decorative_sanctum_seals() -> bool:
	return true


# =============================== public surface ================================================
func enter(avatar_id: String) -> void:
	_avatar = avatar_id
	clear_foe()
	_clear_party()
	for c in get_children():
		c.queue_free()
	_plates.clear()
	_plate_light = null
	_solids.clear()
	_lit = ""
	_sig_fired = false
	_walking = false
	_flames.clear()
	_world_light_count = 0
	_dbg_dir = Vector2.ZERO
	_input_on = true
	_has_tap = false
	_build()
	_ppos = SPAWN
	_door_in = DOOR_PLATE.has_point(SPAWN)
	_door_armed = false
	_face_dir = Vector2.UP
	_heading = Vector2.UP.angle()
	_plast = SPAWN
	_rig_call("face", Vector2.UP)
	_rig_call("play", "idle")
	_sync_player()
	_cam_ready = false
	_tick_cam(1.0)

func set_lit(el: String) -> void:
	if not _plates.has(el):
		push_warning("Temple3D.set_lit: unknown element " + el)
		return
	_lit = el
	_sig_fired = false
	for k in _plates:
		_plate_state(String(k), String(k) == el)

func clear_lit() -> void:
	_lit = ""
	_sig_fired = false
	for k in _plates:
		_plate_state(String(k), false)
	if _plate_light != null and is_instance_valid(_plate_light):
		_plate_light.light_energy = 0.0

func near_lit() -> bool:
	if _lit == "" or not _plates.has(_lit):
		return false
	return _ppos.distance_to(Vector2(PLATE_POS[_lit])) <= NEAR_R

func set_input_enabled(on: bool) -> void:
	_input_on = on
	if not on:
		_has_tap = false
	if not on and _walking:
		_walking = false
		_rig_call("play", "idle")

func player_pos() -> Vector2:
	return _ppos

func debug_move(dir: Vector2) -> void:
	_dbg_dir = dir

# Read-only geometry for probes and renderer-neutral gameplay. Callers receive a copy so the
# temple's collision truth cannot be mutated from an overlay or debug tool.
func gameplay_regions() -> Array[Rect2]:
	return PLAYABLE_REGIONS.duplicate()

func gameplay_bounds() -> Rect2:
	return GAMEPLAY_BOUNDS

func plate_pos(el: String) -> Vector2:
	return Vector2(PLATE_POS.get(el, Vector2.ZERO))

func helper_spot(at: Vector2) -> Dictionary:
	var side := -1.0 if at.x >= HALL_W * 0.5 else 1.0
	return {
		"from": at + Vector2(212.0 * side, 52.0),
		"to": at + Vector2(140.0 * side, 34.0),
		"face": Vector2(-side, 0.0),
	}

# The combat model speaks only in the hall's original 2D gameplay plane. This adapter supplies one
# grounded 3D billboard for regular corruptimons and borrows the altar's existing Grimwick rig for
# the boss beat. No lights, particles, extra viewport or model assets are introduced here.
func spawn_foe(id: String, at: Vector2) -> void:
	clear_foe()
	var foe_id := id.strip_edges().to_lower()
	if foe_id == "grimwick":
		if _grim_rig == null or not is_instance_valid(_grim_rig):
			return
		_foe_rig = _grim_rig
		_foe_body = _grim_rig.get_parent() as Node3D
		_foe_is_grim = true
		if _foe_rig.has_method("face"):
			_foe_rig.call("face", Vector2.DOWN)
		foe_play("idle")
		return
	if foe_id == "" or _actors == null or not is_instance_valid(_actors):
		return
	var body := Node3D.new()
	body.name = "TempleFoe"
	_actors.add_child(body)
	var rig := _make_rig("species", foe_id, CHAR_CELL_M)
	body.add_child(rig)
	body.add_child(_shadow(0.44))
	body.global_position = px2m(at)
	_foe_body = body
	_foe_rig = rig
	_foe_is_grim = false
	if rig.has_method("face"):
		rig.call("face", Vector2(HALL_W * 0.5, HALL_H * 0.5) - at)
	foe_play("idle")

func foe_pos() -> Vector2:
	var node := _foe_body
	if node == null or not is_instance_valid(node):
		node = _foe_rig
	if node == null or not is_instance_valid(node):
		return Vector2.ZERO
	var p: Vector3 = node.global_position
	return Vector2(p.x / PX2M, p.z / PX2M)

func foe_play(clip: String) -> void:
	if not (clip in ["idle", "attack", "hurt", "defeated"]):
		return
	if _foe_rig != null and is_instance_valid(_foe_rig) and _foe_rig.has_method("play"):
		_foe_rig.call("play", clip)

func clear_foe() -> void:
	if _foe_is_grim:
		if _foe_rig != null and is_instance_valid(_foe_rig):
			if _foe_rig.has_method("play"):
				_foe_rig.call("play", "idle")
			if _foe_rig.has_method("face"):
				_foe_rig.call("face", Vector2.DOWN)
	elif _foe_body != null and is_instance_valid(_foe_body):
		# Immediate free prevents one-frame overlap when a new wave replaces the old target.
		_foe_body.free()
	elif _foe_rig != null and is_instance_valid(_foe_rig):
		_foe_rig.free()
	_foe_body = null
	_foe_rig = null
	_foe_is_grim = false

func camera() -> Camera3D:
	return _cam

# =============================== movement ======================================================
func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var intent := _input_dir()
	var before := _ppos
	if intent != Vector2.ZERO:
		_move_player(intent * SPEED * _move_speed_multiplier() * delta)
	var actual := _ppos - before
	var moving := actual.length_squared() > 0.01
	if intent != Vector2.ZERO:
		# Face the collision-resolved slide when one axis moved, or the intended wall when fully
		# blocked. Animation, however, advances only from real ground covered.
		var facing := actual if moving else intent
		var f := _cardinal_h(facing, _face_dir)
		if f != _face_dir:
			_face_dir = f
			_rig_call("face", f)
	var current_clip := String(_rig.call("clip")) \
		if _rig != null and is_instance_valid(_rig) and _rig.has_method("clip") else "idle"
	var one_shot_locked := current_clip in ["attack", "hurt", "defeated"]
	_walking = moving
	if not one_shot_locked:
		_rig_call("play", "walk" if moving else "idle")
		if moving and _rig != null and is_instance_valid(_rig) \
				and _rig.has_method("advance_walk_distance"):
			_rig.call("advance_walk_distance", actual.length())
	_sync_player()
	_tick_party(delta)
	_tick_triggers()
	_tick_cam(delta)
	_tick_flames(delta)

func _tick_cam(delta: float) -> void:
	if _cam == null or not is_instance_valid(_cam):
		return
	var aim := px2m(_ppos, CAM_AIM_Y)
	var pr := deg_to_rad(PITCH_DEG)
	var want := aim + Vector3(0.0, CAM_DIST * sin(pr), CAM_DIST * cos(pr))
	if not _cam_ready:
		_cam_pos = want
		_cam_ready = true
	else:
		# FRAMERATE-INDEPENDENT. A raw lerp(target, 0.1) changes speed with the frame rate, and this
		# hall has to behave the same in a 500 fps editor run and a 30 fps WASM build on a phone.
		_cam_pos = _cam_pos.lerp(want, 1.0 - exp(-CAM_DECAY * delta))
	_cam.global_position = _cam_pos
	_cam.look_at(aim, Vector3.UP)

func _unhandled_input(ev: InputEvent) -> void:
	if not _input_on or _cam == null or not is_instance_valid(_cam):
		return
	var at := Vector2.ZERO
	if ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
		at = (ev as InputEventScreenTouch).position
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
			and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		at = (ev as InputEventMouseButton).position
	else:
		return
	# TAP TO WALK, now a real ray against the floor plane rather than an inverse canvas transform.
	# Same guarantee as the 2D hall's version and for the same reason: whatever corner a touch pad
	# lands in, a tap on the floor must always be able to move the player.
	var from := _cam.project_ray_origin(at)
	var dir := _cam.project_ray_normal(at)
	if absf(dir.y) < 0.0001:
		return
	var t: float = -from.y / dir.y
	if t <= 0.0:
		return
	var hit := from + dir * t
	var world := Vector2(hit.x / PX2M, hit.z / PX2M)
	if _hits(Rect2(world.x - 18.0, world.y - 16.0, 36.0, 20.0)):
		return
	_tap_to = world
	_has_tap = true

func _input_dir() -> Vector2:
	if not _input_on:
		return Vector2.ZERO
	if _dbg_dir != Vector2.ZERO:
		_has_tap = false
		return _dbg_dir.normalized()
	var d := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		d.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		d.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		d.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		d.x += 1.0
	if d != Vector2.ZERO:
		_has_tap = false
	elif _has_tap:
		var to: Vector2 = _tap_to - _ppos
		if to.length() <= 14.0:
			_has_tap = false
		else:
			d = to
	return d.normalized() if d != Vector2.ZERO else d

func _cardinal_h(d: Vector2, cur: Vector2) -> Vector2:
	var hx := absf(d.x)
	var hy := absf(d.y)
	var horiz := hx >= hy
	if cur.x != 0.0:
		horiz = hx * DEADBAND >= hy
	elif cur.y != 0.0:
		horiz = hx >= hy * DEADBAND
	if horiz:
		return Vector2.RIGHT if d.x > 0.0 else Vector2.LEFT
	return Vector2.DOWN if d.y > 0.0 else Vector2.UP

func _move_speed_multiplier() -> float:
	# A virtual movement hook lets the horde mode use species Stride without changing legacy
	# exploration movement or scaling dodge/card-dash displacement through _move_player().
	return 1.0

func _move_player(dv: Vector2) -> void:
	var p := _ppos
	if dv.x != 0.0:
		var nx := p.x + dv.x
		if not _hits(Rect2(nx - 18.0, p.y - 16.0, 36.0, 20.0)):
			p.x = nx
	if dv.y != 0.0:
		var ny := p.y + dv.y
		if not _hits(Rect2(p.x - 18.0, ny - 16.0, 36.0, 20.0)):
			p.y = ny
	_ppos = p

func _sync_player() -> void:
	if _player != null and is_instance_valid(_player):
		_player.global_position = px2m(_ppos)

func _blocked(p: Vector2) -> bool:
	return _hits(Rect2(p.x - 21.0, p.y - 15.0, 42.0, 19.0))

func _slide(p: Vector2, dv: Vector2) -> Vector2:
	if _blocked(p):
		return p + dv
	var out := p
	if dv.x != 0.0 and not _blocked(Vector2(out.x + dv.x, out.y)):
		out.x += dv.x
	if dv.y != 0.0 and not _blocked(Vector2(out.x, out.y + dv.y)):
		out.y += dv.y
	return out

func _legal_spot(from: Vector2, want: Vector2) -> Vector2:
	if not _blocked(want):
		return want
	for k in range(9, 0, -1):
		var p: Vector2 = from.lerp(want, float(k) / 10.0)
		if not _blocked(p):
			return p
	return from

func _hits(r: Rect2) -> bool:
	if not _inside_playable(r):
		return true
	for s in _solids:
		if s.intersects(r):
			return true
	return false

func _walk_point(p: Vector2) -> bool:
	for region in PLAYABLE_REGIONS:
		if region.has_point(p):
			return true
	return false

func _inside_playable(r: Rect2) -> bool:
	# Test inset corners against the UNION, not require one region to enclose the whole box. That
	# lets a feet box straddle an overlapping doorway while still rejecting every outside corner.
	var e := r.end - Vector2(0.5, 0.5)
	var p := r.position + Vector2(0.5, 0.5)
	return _walk_point(p) and _walk_point(Vector2(e.x, p.y)) \
		and _walk_point(Vector2(p.x, e.y)) and _walk_point(e)

func _tick_triggers() -> void:
	if _lit != "" and _plates.has(_lit):
		var pp: Vector2 = Vector2(PLATE_POS[_lit])
		if not _sig_fired and Rect2(pp.x - 48.0, pp.y - 32.0, 96.0, 64.0).has_point(_ppos):
			_sig_fired = true
			emit_signal("sigil_reached", _lit)
	var din := DOOR_PLATE.has_point(_ppos)
	if not _door_armed:
		if _ppos.distance_to(DOOR_PLATE.get_center()) > DOOR_ARM_R:
			_door_armed = true
	elif din and not _door_in:
		emit_signal("door_reached")
	_door_in = din

func _rig_call(m: String, arg: Variant) -> void:
	if _rig != null and is_instance_valid(_rig) and _rig.has_method(m):
		_rig.call(m, arg)

# =============================== the party trail ===============================================
# Byte-for-byte the same solve as Temple2D, operating on the same plane in the same units. Only the
# two lines that touch a transform differ: a follower's position is written to a Node3D through
# px2m() instead of to a Node2D directly.

func set_party(units: Array) -> void:
	_clear_party()
	if _actors == null or not is_instance_valid(_actors):
		return
	var i := 0
	for u in units:
		if i >= PARTY_SLOTS.size():
			break
		if not (u is Dictionary):
			continue
		var d := u as Dictionary
		var sp := String(d.get("species", ""))
		var uid := String(d.get("uid", ""))
		if sp == "" or uid == "":
			continue
		var body := Node3D.new()
		_actors.add_child(body)
		var rig := _make_rig("species", sp, CHAR_CELL_M)
		body.add_child(rig)
		body.add_child(_shadow(0.42))
		var slot: Vector2 = PARTY_SLOTS[i]
		var fwd := Vector2(cos(_heading), sin(_heading))
		var per := Vector2(-fwd.y, fwd.x)
		var at: Vector2 = _legal_spot(_ppos, _ppos + per * slot.x + fwd * slot.y)
		body.global_position = px2m(at)
		var f := {
			"uid": uid, "sp": sp, "body": body, "rig": rig, "slot": i, "p": at,
			"mode": "follow", "goal": at, "gface": Vector2.UP,
			"face": Vector2.ZERO, "walk": false, "tw": null, "mdir": Vector2.ZERO,
		}
		_party.append(f)
		_f_face(f, Vector2.UP)
		_f_play(f, "idle")
		i += 1

func party_size() -> int:
	return _party.size()

func has_follower(uid: String) -> bool:
	return not _find_follower(uid).is_empty()

func send_follower(uid: String, at: Vector2) -> bool:
	var f := _find_follower(uid)
	if f.is_empty():
		return false
	var spot: Dictionary = helper_spot(at)
	_kill_tw(f)
	f["mode"] = "goto"
	f["goal"] = Vector2(spot["to"])
	f["gface"] = Vector2(spot["face"])
	f["walk"] = true
	return true

func follower_posted(uid: String) -> bool:
	var f := _find_follower(uid)
	return (not f.is_empty()) and String(f["mode"]) == "posted"

func follower_pos(uid: String) -> Vector2:
	var f := _find_follower(uid)
	return Vector2(f["p"]) if not f.is_empty() else Vector2.ZERO

func follower_rig(uid: String) -> Node3D:
	var f := _find_follower(uid)
	if f.is_empty():
		return null
	var r = f["rig"]
	return r as Node3D if r != null and is_instance_valid(r) else null

# The strike, owned here for the same reason it is owned by Temple2D: the follow solve writes this
# node's position every frame, so a tween started from outside would be fighting it for the whole
# blow. "held" takes it out of the solve for exactly the length of the swing.
func strike_follower(uid: String, at: Vector2) -> void:
	var f := _find_follower(uid)
	if f.is_empty():
		return
	var home: Vector2 = f["p"]
	var aim: Vector2 = at - home
	if aim.length() < 1.0:
		aim = Vector2.RIGHT
	_f_face(f, aim)
	_kill_tw(f)
	f["mode"] = "held"
	f["goal"] = home
	var n: Vector2 = aim.normalized()
	var tw := create_tween()
	f["tw"] = tw
	# wind up away from the sigil, then drive through it — the package's attack cell is one held
	# pose and carries no anticipation of its own
	tw.tween_method(func(v: Vector2): _f_place(f, v), home, home - n * 15.0, 0.11) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): _f_play(f, "attack"))
	tw.tween_method(func(v: Vector2): _f_place(f, v), home - n * 15.0, home + n * 36.0, 0.08) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.06)
	tw.tween_method(func(v: Vector2): _f_place(f, v), home + n * 36.0, home, 0.21) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): f["mode"] = "posted")

func follower_hurt(uid: String) -> void:
	var f := _find_follower(uid)
	if not f.is_empty():
		_f_play(f, "hurt")

func recall_follower(uid: String) -> void:
	var f := _find_follower(uid)
	if f.is_empty():
		return
	_kill_tw(f)
	f["mode"] = "follow"
	f["walk"] = true

func _find_follower(uid: String) -> Dictionary:
	for e in _party:
		var f: Dictionary = e
		if String(f.get("uid", "")) == uid:
			return f
	return {}

func _kill_tw(f: Dictionary) -> void:
	var t = f.get("tw")
	if t != null and (t as Tween).is_valid():
		(t as Tween).kill()
	f["tw"] = null

func _clear_party() -> void:
	for f in _party:
		_kill_tw(f)
		var b = f.get("body")
		if b != null and is_instance_valid(b):
			(b as Node3D).queue_free()
	_party.clear()

# the single place a follower's plane position becomes a world transform
func _f_place(f: Dictionary, p: Vector2) -> void:
	f["p"] = p
	var b = f.get("body")
	if b != null and is_instance_valid(b):
		(b as Node3D).global_position = px2m(p)

func _f_play(f: Dictionary, clip: String) -> void:
	var r = f.get("rig")
	if r == null or not is_instance_valid(r) or not r.has_method("play"):
		return
	# a one-shot must be allowed to finish: the walk/idle decision runs every frame and would
	# otherwise overwrite the hurt pose on the frame after it is set
	if r.has_method("clip") and clip in ["idle", "walk"]:
		var cur := String(r.call("clip"))
		if cur == "attack" or cur == "hurt" or cur == "defeated":
			return
	r.call("play", clip)

func _f_face(f: Dictionary, d: Vector2) -> void:
	var r = f.get("rig")
	if r == null or not is_instance_valid(r) or not r.has_method("face"):
		return
	var cur: Vector2 = f.get("face", Vector2.ZERO)
	var c := _cardinal_h(d, cur)
	if c == cur:
		return
	f["face"] = c
	r.call("face", c)

func _tick_party(delta: float) -> void:
	if _party.is_empty():
		return
	var pp: Vector2 = _ppos
	var mv: Vector2 = pp - _plast
	# gate on SPEED, not per-frame distance: at 500 fps a 260 px/s walk advances 0.5 px a frame and
	# a distance gate never fires, so the formation's heading would never update on fast hardware
	var spd: float = mv.length() / maxf(delta, 0.0001)
	if spd > 24.0:
		_heading = lerp_angle(_heading, mv.angle(), clampf(3.2 * delta, 0.0, 1.0))
	_plast = pp
	var fwd := Vector2(cos(_heading), sin(_heading))
	var per := Vector2(-fwd.y, fwd.x)
	for f in _party:
		_tick_follower(f, delta, pp, fwd, per)
	_separate_party()

func _tick_follower(f: Dictionary, delta: float, pp: Vector2, fwd: Vector2, per: Vector2) -> void:
	var b = f.get("body")
	if b == null or not is_instance_valid(b):
		return
	var mode := String(f["mode"])
	if mode == "held":
		return
	var here: Vector2 = f["p"]
	var goal: Vector2 = pp
	var stop_r := FOLLOW_STOP
	if mode == "goto" or mode == "posted":
		goal = f["goal"]
		stop_r = POST_R
	else:
		var slot: Vector2 = PARTY_SLOTS[clampi(int(f["slot"]), 0, PARTY_SLOTS.size() - 1)]
		goal = pp + per * slot.x + fwd * slot.y
	var to: Vector2 = goal - here
	var dist: float = to.length()
	if dist > FOLLOW_SNAP:
		_f_place(f, goal if not _blocked(goal) else pp)
		f["walk"] = false
		_f_play(f, "idle")
		return
	var moving := bool(f.get("walk", false))
	if moving and dist <= stop_r:
		moving = false
	elif not moving and dist > stop_r + FOLLOW_GO:
		moving = true
		f["mdir"] = Vector2.ZERO
	f["walk"] = moving
	if moving:
		var step: float = minf(minf(dist * FOLLOW_RATE, FOLLOW_MAX) * delta, dist)
		var was: Vector2 = here
		_f_place(f, _slide(here, to.normalized() * step))
		var went: Vector2 = Vector2(f["p"]) - was
		if went.length() > 0.05:
			var md: Vector2 = f.get("mdir", Vector2.ZERO)
			md = went.normalized() if md == Vector2.ZERO else md.lerp(went.normalized(), clampf(9.0 * delta, 0.0, 1.0))
			f["mdir"] = md
			_f_face(f, md)
			_f_play(f, "walk")
			var rig = f.get("rig")
			if rig != null and is_instance_valid(rig) and rig.has_method("advance_walk_distance") \
					and (not rig.has_method("clip") or String(rig.call("clip")) == "walk"):
				rig.call("advance_walk_distance", went.length())
		else:
			_f_play(f, "idle")
	else:
		_f_play(f, "idle")
		if mode == "goto":
			f["mode"] = "posted"
		if mode == "goto" or mode == "posted":
			_f_face(f, Vector2(f["gface"]))
		else:
			var la: Vector2 = pp - Vector2(f["p"])
			if la.length() > 1.0:
				_f_face(f, la)

func _separate_party() -> void:
	for i in range(_party.size()):
		for j in range(i + 1, _party.size()):
			var fa: Dictionary = _party[i]
			var fb: Dictionary = _party[j]
			if String(fa["mode"]) != "follow" or String(fb["mode"]) != "follow":
				continue
			var pa: Vector2 = fa["p"]
			var pb: Vector2 = fb["p"]
			var dv: Vector2 = pb - pa
			var dl: float = dv.length()
			if dl < PARTY_SEP and dl > 0.01:
				var push: float = (PARTY_SEP - dl) * 0.28
				var n: Vector2 = dv / dl
				_f_place(fa, _slide(pa, -n * push))
				_f_place(fb, _slide(pb, n * push))

# =============================== construction ==================================================
static func _is_low() -> bool:
	var H = load("res://HDStruct.gd")
	return H.phone_world() or H.lite_world()

func _build() -> void:
	_low = _is_low()
	_actors = Node3D.new()
	add_child(_actors)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.018, 0.010, 0.034)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# The generated stone is already charcoal. Multiplying it by another near-black purple made the
	# Compatibility/WebGL court read as an empty void even though the texture detail was present.
	# A neutral-violet fill keeps the night palette while restoring the reference's readable bevels,
	# mortar and stairs. This is a single environment term, so it is cheaper than adding fill lights.
	e.ambient_light_color = Color(0.48, 0.43, 0.58) if not _low \
		else Color(0.50, 0.45, 0.62)
	# The characters are UNSHADED — they carry their own painted light — so ambient energy only
	# lifts the ROOM. Set for the stone to read as dusk without the torch pools losing their job.
	# The generated stone already carries deep violet-charcoal values. A modest global lift reveals
	# its cracks and bevels in the north-facing courts without adding lights or touching unshaded
	# creature cards. Phone receives slightly more fill because it intentionally has no fog/bloom.
	e.ambient_light_energy = 1.05 if not _low else 1.12
	e.fog_enabled = not _low
	e.fog_light_color = Color(0.20, 0.10, 0.28)
	e.fog_density = 0.010
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if not _low:
		e.glow_enabled = true
		e.glow_intensity = 0.66
		e.glow_bloom = 0.12
	env.environment = e
	add_child(env)

	_build_floor()
	# The old round medallion was meaningful only to the ritual's Light trial. Horde mode has no
	# interaction on it, so the subclass now receives uninterrupted stone instead of a fake target.
	if _show_decorative_sanctum_seals():
		_build_boss_space()
	_build_walls()
	_build_sanctums()
	_build_reference_depth()
	_build_architecture()
	_build_pillars()
	_build_dais()
	if _show_decorative_sanctum_seals():
		_build_plates()
	_build_torches()
	_build_player()
	_build_solids()

# ---- materials ----
func _stone_mat(base: Color, rough: float = 0.92) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = base
	m.roughness = rough
	m.metallic = 0.0
	return m


func _shared_stone(key: String, base: Color, rough: float = 0.92) -> StandardMaterial3D:
	var cache_key := "stone:" + key
	if _material_cache.has(cache_key):
		return _material_cache[cache_key] as StandardMaterial3D
	var mat := _stone_mat(base, rough)
	_material_cache[cache_key] = mat
	return mat


func _shared_textured_stone(key: String, texture: Texture2D, tint: Color,
	rough: float, metres_per_repeat: float) -> StandardMaterial3D:
	var cache_key := "texstone:%s:%s" % [key, "low" if _low else "hd"]
	if _material_cache.has(cache_key):
		return _material_cache[cache_key] as StandardMaterial3D
	var mat := _stone_mat(tint, rough)
	mat.albedo_texture = texture
	# Triplanar projection keeps the scale of the generated masonry identical on a small threshold,
	# a long wall and a MultiMesh ruin. It also removes stretched UVs from scaled primitive boxes.
	mat.uv1_triplanar = true
	var density := 1.0 / maxf(0.25, metres_per_repeat)
	mat.uv1_scale = Vector3(density, density, density)
	mat.texture_repeat = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS \
		if _low else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_material_cache[cache_key] = mat
	return mat


func _shared_glow(key: String, col: Color, energy: float = 1.0) -> StandardMaterial3D:
	var cache_key := "glow:" + key
	if _material_cache.has(cache_key):
		return _material_cache[cache_key] as StandardMaterial3D
	var mat := _glow_mat(col, energy)
	_material_cache[cache_key] = mat
	return mat


func _wicked_floor_mat() -> StandardMaterial3D:
	var mat := _shared_textured_stone("wicked_floor", WICKED_FLOOR_TEX,
		Color(0.92, 0.88, 1.0), 0.96, 8.0)
	if _low and not mat.emission_enabled:
		# A tiny constant lift replaces the many point lights removed on phone; it is deliberately
		# below the cyan/violet accents, so the floor stays charcoal instead of turning lavender.
		mat.emission_enabled = true
		mat.emission = Color(0.026, 0.018, 0.040)
		mat.emission_energy_multiplier = 0.18
	return mat


func _wicked_wall_mat() -> StandardMaterial3D:
	var mat := _shared_textured_stone("wicked_wall", WICKED_WALL_TEX,
		Color(0.90, 0.84, 1.0), 0.94, 7.5)
	if _low and not mat.emission_enabled:
		mat.emission_enabled = true
		mat.emission = Color(0.024, 0.016, 0.038)
		mat.emission_energy_multiplier = 0.16
	return mat


func _wicked_deep_mat() -> StandardMaterial3D:
	return _shared_textured_stone("wicked_deep", WICKED_WALL_TEX,
		Color(0.36, 0.29, 0.48), 0.99, 7.5)


func _wicked_trim_mat() -> StandardMaterial3D:
	return _shared_textured_stone("wicked_trim", WICKED_WALL_TEX,
		Color(0.60, 0.40, 0.78), 0.88, 7.5)


func _wicked_backdrop_mat() -> StandardMaterial3D:
	var mat := _shared_textured_stone("wicked_backdrop", WICKED_WALL_TEX,
		Color(1.18, 1.02, 1.32), 0.92, 7.5)
	if not mat.emission_enabled:
		# The fixed fight camera looks into the unlit north face. A restrained purple ambient lift
		# keeps the generated masonry readable there without spending another point light.
		mat.emission_enabled = true
		mat.emission = Color(0.072, 0.044, 0.105)
		mat.emission_energy_multiplier = 0.32 if _low else 0.24
	return mat


func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "box:%.4f:%.4f:%.4f" % [size.x, size.y, size.z]
	if _mesh_cache.has(key):
		return _mesh_cache[key] as BoxMesh
	var mesh := BoxMesh.new()
	mesh.size = size
	_mesh_cache[key] = mesh
	return mesh


func _plane_mesh(size: Vector2) -> PlaneMesh:
	var key := "plane:%.4f:%.4f" % [size.x, size.y]
	if _mesh_cache.has(key):
		return _mesh_cache[key] as PlaneMesh
	var mesh := PlaneMesh.new()
	mesh.size = size
	_mesh_cache[key] = mesh
	return mesh


func _cylinder_mesh(radius: float, h: float, segments: int) -> CylinderMesh:
	var key := "cyl:%.4f:%.4f:%d" % [radius, h, segments]
	if _mesh_cache.has(key):
		return _mesh_cache[key] as CylinderMesh
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = h
	mesh.radial_segments = segments
	_mesh_cache[key] = mesh
	return mesh


func _frustum_mesh(key: String, top_radius: float, bottom_radius: float,
	h: float, segments: int) -> CylinderMesh:
	var cache_key := "frustum:%s:%.4f:%.4f:%.4f:%d" % [
		key, top_radius, bottom_radius, h, segments]
	if _mesh_cache.has(cache_key):
		return _mesh_cache[cache_key] as CylinderMesh
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = h
	mesh.radial_segments = segments
	_mesh_cache[cache_key] = mesh
	return mesh


# Decorative masonry is expressed as scaled unit boxes in a MultiMesh. Dozens of blocks, stairs
# and buttresses therefore cost one draw per palette material, while every playable rectangle and
# collision API remains exactly as authored.
func _multi_box_group(group_name: String, pieces: Array, mat: Material,
	cast_shadows: bool = false) -> MultiMeshInstance3D:
	if pieces.is_empty():
		return null
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _box_mesh(Vector3.ONE)
	multimesh.instance_count = pieces.size()
	for i in range(pieces.size()):
		var piece := pieces[i] as Dictionary
		var at: Vector3 = piece.get("at", Vector3.ZERO)
		var size: Vector3 = piece.get("size", Vector3.ONE)
		var rotation: Vector3 = piece.get("rotation", Vector3.ZERO)
		# Sizes in a piece spec are local box dimensions. Global-axis scaling after rotation turns a
		# circular ring into a row of vertical slivers; local scaling preserves each segment's authored
		# tangent and also makes rotated rubble keep its intended proportions.
		var basis := Basis.from_euler(rotation).scaled_local(size)
		multimesh.set_instance_transform(i, Transform3D(basis, at))
	var instance := MultiMeshInstance3D.new()
	instance.name = group_name
	instance.multimesh = multimesh
	instance.material_override = mat
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
		if cast_shadows and not _low else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance

# Cheap architectural depth. These are primitive meshes with shared materials: no imported
# texture memory, particles, extra viewports, or dynamic lights. The mobile tier receives the
# same strong silhouette with fewer decorative pieces rather than a visually different room.
func _box_piece(at: Vector3, size: Vector3, mat: Material, parent: Node = self) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.mesh = _box_mesh(size)
	piece.material_override = mat
	piece.position = at
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _low else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(piece)
	return piece

func _disc_piece(at: Vector2, radius: float, h: float, mat: Material) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.mesh = _cylinder_mesh(radius, h, 16 if _low else 32)
	piece.material_override = mat
	piece.position = px2m(at, h * 0.5)
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(piece)
	return piece

func _glow_mat(col: Color, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _build_architecture() -> void:
	var stone := _wicked_wall_mat()
	var deep := _wicked_deep_mat()
	var violet := _wicked_trim_mat()
	var gold := _shared_glow("aged_gold", Color(0.80, 0.54, 0.16), 0.64)

	# ALTAR APSE. A dark inset, twin piers and a stepped lintel give Grimwick a readable throne-like
	# silhouette. All pieces sit behind gameplay and cannot affect navigation or collision.
	var north_z := (FLOOR_TOP - 25.0) * PX2M
	_box_piece(Vector3(1200.0 * PX2M, 2.65, north_z + 0.10), Vector3(8.4, 4.55, 0.34), deep)
	for sx in [-1.0, 1.0]:
		var x: float = (1200.0 + float(sx) * 255.0) * PX2M
		_box_piece(Vector3(x, 2.42, north_z + 0.34), Vector3(0.72, 4.85, 0.72), stone)
		_box_piece(Vector3(x, 0.24, north_z + 0.34), Vector3(1.12, 0.48, 1.05), violet)
		_box_piece(Vector3(x, 4.82, north_z + 0.34), Vector3(1.12, 0.42, 1.05), violet)
	_box_piece(Vector3(1200.0 * PX2M, 4.78, north_z + 0.34), Vector3(11.1, 0.52, 0.72), stone)
	_box_piece(Vector3(1200.0 * PX2M, 4.48, north_z + 0.56), Vector3(7.3, 0.13, 0.12), gold)

	# PROCESSIONAL RIBS. Repeating cross-members make camera movement reveal depth and break the long
	# hall into readable beats. Low/mobile keeps two clear of the doors; desktop gets three.
	# Keep the two doorway bands clear: a rib in either opening would look passable but block the view.
	var ribs := [700.0, 1240.0] if _low else [270.0, 700.0, 1240.0]
	for py in ribs:
		for px in [WALL_L + 36.0, WALL_R - 36.0]:
			_box_piece(px2m(Vector2(px, py), 2.55), Vector3(0.34, 5.1, 0.62), stone)
			_box_piece(px2m(Vector2(px, py), 4.82), Vector3(1.05, 0.30, 0.88), violet)

	# CARPET EDGE INLAYS. Two emissive strips lead the eye to the ritual without adding a single
	# light. They cost two tiny meshes and remain visible when mobile disables glow and fog.
	var aisle_z := CARPET.get_center().y * PX2M
	var aisle_d := CARPET.size.y * PX2M
	for px in [CARPET.position.x + 8.0, CARPET.end.x - 8.0]:
		_box_piece(Vector3(px * PX2M, 0.018, aisle_z), Vector3(0.055, 0.018, aisle_d), gold)

	# Five wall marks echo the elemental pentagon and make the far wall uniquely Wicked Temple.
	# The low tier keeps three central marks, saving two draw calls without weakening the landmark.
	var marks := [-2, -1, 0, 1, 2] if not _low else [-1, 0, 1]
	for i in marks:
		var mark_col := NP.el_color(["Water", "Fire", "Light", "Beast", "Storm"][i + 2])
		_box_piece(Vector3((1200.0 + float(i) * 92.0) * PX2M, 3.45, north_z + 0.57), Vector3(0.24, 1.18, 0.10), _glow_mat(mark_col, 0.58))


func _box_spec_px(at: Vector2, size_px: Vector2, height: float,
	base_y: float = 0.0, rotation_y: float = 0.0) -> Dictionary:
	return {
		"at": px2m(at, base_y + height * 0.5),
		"size": Vector3(size_px.x * PX2M, height, size_px.y * PX2M),
		"rotation": Vector3(0.0, rotation_y, 0.0),
	}


# The reference arena feels large because the playable floor is framed by multiple depth planes,
# not because props are scattered through combat. Every piece below is behind or beyond the
# PLAYABLE_REGIONS union; the centre stays clean for movement, dodges and card targeting.
func _build_reference_depth() -> void:
	var wall := _wicked_wall_mat()
	var deep := _wicked_deep_mat()
	var trim := _wicked_trim_mat()
	var backdrop := _wicked_backdrop_mat()
	var cyan := _shared_glow("sanctum_cyan", Color(0.04, 0.66, 0.92), 1.28 if _low else 1.75)
	var violet := _shared_glow("wicked_violet", Color(0.60, 0.16, 0.92), 1.20 if _low else 1.72)

	# Opaque emissive water-channels hug the arena edges. A dark trough makes each one read as an
	# architectural cut in the floor even when mobile bloom is disabled.
	var troughs: Array = []
	var channels: Array = []
	var channel_runs := [
		[Vector2(WALL_L + 15.0, 735.0), Vector2(10.0, 1010.0)],
		[Vector2(WALL_R - 15.0, 735.0), Vector2(10.0, 1010.0)],
		[Vector2(WEST_WING.position.x + 9.0, 755.0), Vector2(10.0, 1060.0)],
		[Vector2(WEST_WING.end.x - 9.0, 755.0), Vector2(10.0, 1060.0)],
		[Vector2(EAST_WING.position.x + 9.0, 755.0), Vector2(10.0, 1060.0)],
		[Vector2(EAST_WING.end.x - 9.0, 755.0), Vector2(10.0, 1060.0)],
	]
	for run in channel_runs:
		var at := run[0] as Vector2
		var size := run[1] as Vector2
		troughs.append(_box_spec_px(at, size + Vector2(10.0, 0.0), 0.040, 0.004))
		channels.append(_box_spec_px(at, size, 0.026, 0.028))
	_multi_box_group("CyanChannelTroughs", troughs, deep)
	_multi_box_group("CyanSanctumChannels", channels, cyan)
	_build_wing_backdrops(backdrop, deep, trim, cyan, violet)

	# Three layers of background masonry, repeated buttresses and broken outer-wall towers establish
	# a real ruin silhouette. All 30-odd blocks below are two shared MultiMesh draws.
	var masonry: Array = []
	var shadow_masonry: Array = []
	for step in range(4):
		var step_w := 1380.0 - float(step) * 185.0
		var step_z := FLOOR_TOP - 112.0 - float(step) * 44.0
		# These are full-height supported terrace blocks, not thin slabs suspended behind the wall.
		# The enclosing north wall hides their lower mass while the stepped tops create the skyline.
		var terrace_top := 4.69 + float(step) * 0.33
		masonry.append(_box_spec_px(Vector2(1200.0, step_z), Vector2(step_w, 92.0),
			terrace_top))
	for px in [360.0, 655.0, 1745.0, 2040.0]:
		masonry.append(_box_spec_px(Vector2(px, FLOOR_TOP - 58.0), Vector2(72.0, 118.0), 5.9))
		masonry.append(_box_spec_px(Vector2(px, FLOOR_TOP - 30.0), Vector2(118.0, 160.0), 0.42))
	for py in [300.0, 530.0, 760.0, 990.0, 1220.0]:
		masonry.append(_box_spec_px(Vector2(-1000.0, py), Vector2(92.0, 138.0), 4.5))
		masonry.append(_box_spec_px(Vector2(3400.0, py), Vector2(92.0, 138.0), 4.5))
		shadow_masonry.append(_box_spec_px(Vector2(-1046.0, py + 34.0), Vector2(86.0, 154.0), 1.15))
		shadow_masonry.append(_box_spec_px(Vector2(3446.0, py + 34.0), Vector2(86.0, 154.0), 1.15))
	for py in [340.0, 760.0, 1180.0]:
		masonry.append(_box_spec_px(Vector2(18.0, py), Vector2(78.0, 128.0), 4.1))
		masonry.append(_box_spec_px(Vector2(2382.0, py), Vector2(78.0, 128.0), 4.1))
	_multi_box_group("LayeredTempleMasonry", masonry, wall, true)
	_multi_box_group("DeepTempleButtresses", shadow_masonry, trim)

	# Deterministic rubble lives outside the navigation union. It breaks the straight outer silhouette
	# without producing a forest of individual MeshInstance nodes or a nondeterministic screenshot.
	var rubble: Array = []
	var anchors := [
		Vector2(-1035.0, 315.0), Vector2(-1035.0, 690.0), Vector2(-1035.0, 1110.0),
		Vector2(3435.0, 315.0), Vector2(3435.0, 690.0), Vector2(3435.0, 1110.0),
		Vector2(10.0, 470.0), Vector2(10.0, 1040.0),
		Vector2(2390.0, 470.0), Vector2(2390.0, 1040.0),
		Vector2(285.0, 78.0), Vector2(790.0, 62.0),
		Vector2(1610.0, 62.0), Vector2(2115.0, 78.0),
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 684219
	var rubble_count := 20 if _low else 34
	for i in range(rubble_count):
		var anchor: Vector2 = anchors[i % anchors.size()]
		var sx := rng.randf_range(38.0, 92.0)
		var sz := rng.randf_range(34.0, 78.0)
		var h := rng.randf_range(0.22, 0.72)
		var at := anchor + Vector2(rng.randf_range(-32.0, 32.0), rng.randf_range(-38.0, 38.0))
		rubble.append(_box_spec_px(at, Vector2(sx, sz), h, 0.0, rng.randf_range(-0.28, 0.28)))
	_multi_box_group("BatchedTempleRubble", rubble, deep)

	# A low-poly violet wheel and stepped aperture sit on the far wall, echoing the reference's
	# central landmark. It is vertical wall ornament, never another floor seal.
	var gateway: Array = []
	var gate_z := (FLOOR_TOP - 25.0) * PX2M + 0.61
	var gate_center := Vector3(1200.0 * PX2M, 3.30, gate_z)
	for i in range(12):
		var a := TAU * float(i) / 12.0
		gateway.append({
			"at": gate_center + Vector3(cos(a) * 1.22, sin(a) * 1.22, 0.0),
			"size": Vector3(0.16, 0.62, 0.11),
			"rotation": Vector3(0.0, 0.0, a),
		})
	for i in range(8):
		var a := TAU * float(i) / 8.0
		gateway.append({
			"at": gate_center + Vector3(cos(a) * 0.53, sin(a) * 0.53, 0.03),
			"size": Vector3(0.13, 1.06, 0.10),
			"rotation": Vector3(0.0, 0.0, a - PI * 0.5),
		})
	gateway.append({"at": gate_center + Vector3(0.0, 0.0, 0.06),
		"size": Vector3(0.48, 0.48, 0.14), "rotation": Vector3.ZERO})
	_multi_box_group("VioletGatewayWheel", gateway, violet)


# One composition serves both encounters in each continuous wing. It is built wholly north of the
# wing's y=176 navigation boundary: four broad steps, a recessed apse, framed opening, guardian
# silhouettes, buttresses and restrained rubble. The fight camera sees their tops and faces over
# the low central parapet, while pathing and arena rectangles remain untouched.
func _build_wing_backdrops(wall: Material, deep: Material, trim: Material,
	cyan: Material, violet: Material) -> void:
	var steps: Array = []
	var stair_nosing: Array = []
	var apse_mass: Array = []
	var frame_mass: Array = []
	var guardians: Array = []
	var violet_frame: Array = []
	var gateway_wheels: Array = []
	var rubble: Array = []
	for wing_v in [WEST_WING, EAST_WING]:
		var wing := wing_v as Rect2
		var cx := wing.get_center().x

		# Four overlapping tiers descend to the exact playable edge. Their width narrows toward the
		# recess, giving the fixed camera converging architectural lines without entering combat.
		var front_y := FLOOR_TOP
		for step in range(4):
			var depth_px := 44.0 - float(step) * 3.0
			var width_px := 580.0 - float(step) * 38.0
			var h := 0.34 + float(step) * 0.38
			steps.append(_box_spec_px(
				Vector2(cx, front_y - depth_px * 0.5), Vector2(width_px, depth_px), h))
			stair_nosing.append(_box_spec_px(Vector2(cx, front_y - 3.0),
				Vector2(width_px + 12.0, 7.0), 0.08, h))
			front_y -= depth_px - 2.0

		# The dark back slab is the depth plane; the brighter piers/lintel sit forward of it. All
		# masses reach the ground, so the reveal never depends on floating caps hidden by the wall.
		var apse_y := front_y - 30.0
		apse_mass.append(_box_spec_px(Vector2(cx, apse_y), Vector2(490.0, 60.0), 4.75))
		apse_mass.append(_box_spec_px(Vector2(cx, apse_y + 33.0), Vector2(238.0, 24.0), 3.35, 0.34))
		for side in [-1.0, 1.0]:
			var sx := cx + float(side) * 258.0
			frame_mass.append(_box_spec_px(Vector2(sx, apse_y + 26.0), Vector2(68.0, 96.0), 5.05))
			frame_mass.append(_box_spec_px(Vector2(cx + float(side) * 350.0, apse_y + 48.0),
				Vector2(92.0, 118.0), 4.15))
			# Paired guardian silhouettes: stepped base, torso and square crown. They stay blocky and
			# readable instead of pretending to be another detailed creature sprite.
			var gx := cx + float(side) * 194.0
			guardians.append(_box_spec_px(Vector2(gx, 106.0), Vector2(104.0, 78.0), 0.72))
			guardians.append(_box_spec_px(Vector2(gx, 101.0), Vector2(72.0, 62.0), 1.04, 0.72))
			guardians.append(_box_spec_px(Vector2(gx, 97.0), Vector2(52.0, 50.0), 0.58, 1.76,
				float(side) * 0.10))
		frame_mass.append(_box_spec_px(Vector2(cx, apse_y + 22.0), Vector2(584.0, 74.0),
			0.46, 4.70))

		# A restrained violet inner frame and two cyan wall-cascades give the recess readable colour
		# separation without adding any Light3D nodes.
		# The inner 238 px recess projects 12 px farther toward the camera than the broad apse slab.
		# Mount the luminous frame on that nearer face; the former +31 value left the radial wheel
		# physically correct but hidden inside the inset masonry.
		var face_z := (apse_y + 43.0) * PX2M
		for side in [-1.0, 1.0]:
			violet_frame.append({
				"at": Vector3((cx + float(side) * 112.0) * PX2M, 2.05, face_z),
				"size": Vector3(0.15, 3.25, 0.11), "rotation": Vector3.ZERO,
			})
			# Kept as two real MeshInstances per wing so material audits can prove cyan is bound to
			# visible world geometry rather than only existing in a batched metadata path.
			_box_piece(Vector3((cx + float(side) * 154.0) * PX2M, 2.10, face_z + 0.035),
				Vector3(0.14, 2.55, 0.10), cyan)
		violet_frame.append({
			"at": Vector3(cx * PX2M, 3.63, face_z),
			"size": Vector3(4.55, 0.16, 0.11), "rotation": Vector3.ZERO,
		})

		# The reference's strongest rear landmark is its corrupted radial gate. Repeating it in both
		# side apses gives every fight a clear focal point; all segments share one MultiMesh draw and
		# emit light visually without allocating a Light3D or casting another shadow.
		var wheel_center := Vector3(cx * PX2M, 2.30, face_z + 0.055)
		for i in range(12):
			var a := TAU * float(i) / 12.0
			gateway_wheels.append({
				"at": wheel_center + Vector3(cos(a) * 0.82, sin(a) * 0.82, 0.0),
				"size": Vector3(0.12, 0.43, 0.10),
				"rotation": Vector3(0.0, 0.0, a),
			})
		for i in range(8):
			var a := TAU * float(i) / 8.0
			gateway_wheels.append({
				"at": wheel_center + Vector3(cos(a) * 0.34, sin(a) * 0.34, 0.025),
				"size": Vector3(0.10, 0.67, 0.09),
				"rotation": Vector3(0.0, 0.0, a - PI * 0.5),
			})
		gateway_wheels.append({"at": wheel_center + Vector3(0.0, 0.0, 0.045),
			"size": Vector3(0.30, 0.30, 0.12), "rotation": Vector3.ZERO})

		# Four to eight chipped blocks per wing cluster against the framed side masses. Their forward
		# edges stop short of y=176, and phone simply keeps the smaller subset.
		var rubble_per_side := 2 if _low else 4
		for side in [-1.0, 1.0]:
			for i in range(rubble_per_side):
				var size_x := 42.0 + float((i * 17) % 31)
				var size_z := 34.0 + float((i * 13) % 24)
				var rx := cx + float(side) * (300.0 + float(i) * 34.0)
				var rz := 140.0 - float(i % 2) * 29.0
				rubble.append(_box_spec_px(Vector2(rx, rz), Vector2(size_x, size_z),
					0.25 + float(i) * 0.11, 0.0, float(side) * (0.08 + float(i) * 0.035)))

	_multi_box_group("WingCourtSteps", steps, wall, true)
	_multi_box_group("WingStairNosing", stair_nosing, trim)
	_multi_box_group("WingDeepApses", apse_mass, deep)
	_multi_box_group("WingApseFrames", frame_mass, wall, true)
	_multi_box_group("WingGuardianSilhouettes", guardians, trim)
	_multi_box_group("WingVioletFrames", violet_frame, violet)
	_multi_box_group("WingGatewayWheels", gateway_wheels, violet)
	_multi_box_group("WingBackdropRubble", rubble, deep)

# The generated production texture is preloaded once and shared by the hall, wings and thresholds.
# Unlike the former 128 px procedural placeholder, it carries chipped edges, cracks and restrained
# bronze wear at a useful mip resolution while still remaining one texture/material bind.
func _floor_tex() -> Texture2D:
	return WICKED_FLOOR_TEX

func _build_floor() -> void:
	var w: float = (WALL_R - WALL_L) * PX2M
	var d: float = (RENDER_FLOOR_BOT - FLOOR_TOP) * PX2M
	var mi := MeshInstance3D.new()
	mi.mesh = _plane_mesh(Vector2(w, d))
	mi.material_override = _wicked_floor_mat()
	mi.position = px2m(Vector2((WALL_L + WALL_R) * 0.5, (FLOOR_TOP + RENDER_FLOOR_BOT) * 0.5))
	add_child(mi)

	# the runner, a slab lifted a millimetre so it never z-fights the floor it lies on
	var cmi := MeshInstance3D.new()
	cmi.mesh = _plane_mesh(Vector2(CARPET.size.x * PX2M, CARPET.size.y * PX2M))
	var cmat := _shared_stone("runner_outer", Color(0.115, 0.058, 0.170), 0.96)
	cmi.material_override = cmat
	cmi.position = px2m(CARPET.get_center(), 0.004)
	add_child(cmi)
	var tmi := MeshInstance3D.new()
	tmi.mesh = _plane_mesh(Vector2((CARPET.size.x - 22.0) * PX2M,
		(CARPET.size.y - 22.0) * PX2M))
	tmi.material_override = _shared_stone("runner_inner", Color(0.165, 0.086, 0.230), 0.96)
	tmi.position = px2m(CARPET.get_center(), 0.008)
	add_child(tmi)

# The Light trial and Grimwick now share one unmistakable arena instead of reading as a plate left
# in the aisle. Three low-poly discs make a dark boss seal with one thin gold ring. It is geometry,
# not a light or particle system, and therefore costs the phone tier the same three small draws.
func _build_boss_space() -> void:
	var at := Vector2(1200.0, 470.0)
	var base := _wicked_deep_mat()
	var gold := _shared_glow("aged_gold", Color(0.78, 0.56, 0.22), 0.50)
	var inner := _wicked_trim_mat()
	_disc_piece(at, 5.25, 0.020, base)
	_disc_piece(at, 4.78, 0.027, gold)
	_disc_piece(at, 4.56, 0.034, inner)

func _wall(from: Vector2, to: Vector2, thick: float, h: float, mat: StandardMaterial3D) -> void:
	var mid := (from + to) * 0.5
	var len_px := (to - from).length()
	var horiz := absf(to.x - from.x) >= absf(to.y - from.y)
	var size := Vector3(
		(len_px if horiz else thick) * PX2M,
		h,
		(thick if horiz else len_px) * PX2M)
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size)
	mi.material_override = mat
	mi.position = px2m(mid, h * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _low else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)


func _floor_piece(rect: Rect2, mat: Material, y: float = -0.006) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.mesh = _plane_mesh(rect.size * PX2M)
	piece.material_override = mat
	piece.position = px2m(rect.get_center(), y)
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(piece)
	return piece


# A narrow flush inlay, never a collision obstacle.  Channels and route lines use these shared
# boxes rather than unique textures, so the expanded wings add shape without adding download size.
func _floor_strip(from: Vector2, to: Vector2, thick: float, mat: Material,
	y: float = 0.018) -> MeshInstance3D:
	var mid := (from + to) * 0.5
	var len_px := maxf(1.0, (to - from).length())
	var horiz := absf(to.x - from.x) >= absf(to.y - from.y)
	return _box_piece(px2m(mid, y), Vector3(
		(len_px if horiz else thick) * PX2M, 0.026,
		(thick if horiz else len_px) * PX2M), mat)


func _sanctum_column(at: Vector2, h: float, stone: Material, accent: Material) -> void:
	_box_piece(px2m(at, h * 0.5), Vector3(0.62, h, 0.62), stone)
	_box_piece(px2m(at, 0.13), Vector3(0.92, 0.26, 0.92), stone)
	_box_piece(px2m(at, h - 0.12), Vector3(0.82, 0.24, 0.82), accent)


# These frames sit exactly on the non-playable wall line.  The clear span remains over four metres
# wide, while the high lintel gives the connector real height without ever occluding feet.
func _sanctum_arch(x: float, span: Vector2, stone: Material, accent: Material) -> void:
	var inset := 18.0
	for py in [span.x + inset, span.y - inset]:
		_box_piece(px2m(Vector2(x, py), 1.75), Vector3(0.66, 3.5, 0.66), stone)
	var centre_y := (span.x + span.y) * 0.5
	var length_m := (span.y - span.x) * PX2M
	_box_piece(px2m(Vector2(x, centre_y), 3.58), Vector3(0.72, 0.46, length_m), stone)
	_box_piece(px2m(Vector2(x, centre_y), 3.36), Vector3(0.80, 0.10, length_m * 0.82), accent)


# Three low steps live beyond the outer wall, outside both navigation and horde combat rectangles.
# They raise each elemental backdrop above an otherwise flat horizon without creating gameplay
# collision or requiring a navmesh.
func _sanctum_terrace(at: Vector2, west: bool, stone: Material, accent: Material) -> void:
	var edge_x := WEST_WING.position.x if west else EAST_WING.end.x
	var side := -1.0 if west else 1.0
	for step in range(3):
		var depth_px := 72.0 - float(step) * 13.0
		var away := 36.0 + float(step) * 27.0 + depth_px * 0.5
		var h := 0.18 + float(step) * 0.18
		var width_px := 250.0 - float(step) * 34.0
		_box_piece(px2m(Vector2(edge_x + side * away, at.y), h * 0.5),
			Vector3(depth_px * PX2M, h, width_px * PX2M), stone)
	_box_piece(px2m(Vector2(edge_x + side * 128.0, at.y), 1.32),
		Vector3(0.13, 1.72, 3.25), accent)


# Two continuous wings replace four one-screen boxes.  One floor and one material are shared per
# pair of wings; elemental identity comes from flush inlays, while every solid prop sits beyond a
# playable boundary.  The phone tier keeps exactly the same silhouette and only loses shadows and
# dynamic wing lights through the existing low-quality rules.
func _build_sanctums() -> void:
	var floor_mat := _wicked_floor_mat()
	var wall_mat := _wicked_wall_mat()
	var inner_mat := _wicked_deep_mat()
	var gold_mat := _shared_glow("aged_gold", Color(0.80, 0.57, 0.20), 0.54)
	var threshold_mat := _shared_glow("threshold_cyan", Color(0.04, 0.66, 0.92), 0.24)
	var arch_accent: Material = gold_mat if _show_decorative_sanctum_seals() \
		else _wicked_trim_mat()

	# Six planes cover both wings and all four broad thresholds.  The tiny negative offset lets the
	# original hall floor win cleanly where the connector overlaps it, avoiding a flickering seam.
	_floor_piece(WEST_WING, floor_mat)
	_floor_piece(EAST_WING, floor_mat)
	for connector in [WEST_UPPER_CONNECTOR, WEST_LOWER_CONNECTOR,
		EAST_UPPER_CONNECTOR, EAST_LOWER_CONNECTOR]:
		_floor_piece(connector, floor_mat, -0.004)

	for wing_v in [WEST_WING, EAST_WING]:
		var wing := wing_v as Rect2
		var west := wing.position.x < 0.0
		var outer_x := wing.position.x - 35.0 if west else wing.end.x + 35.0
		var inner_x := wing.end.x + 35.0 if west else wing.position.x - 35.0
		var left := wing.position.x - 35.0
		var right := wing.end.x + 35.0
		var centre_x := wing.get_center().x
		# A full blank wall made the fight read like a dark box. Side masses now frame a broad, low
		# central parapet; the batched stairs and apse behind it remain outside navigation but visible
		# to the fixed fight camera.
		var opening_half := 270.0
		_wall(Vector2(left, wing.position.y - 35.0),
			Vector2(centre_x - opening_half, wing.position.y - 35.0), 70.0, 4.25, wall_mat)
		_wall(Vector2(centre_x - opening_half, wing.position.y - 35.0),
			Vector2(centre_x + opening_half, wing.position.y - 35.0), 70.0, 0.22, wall_mat)
		_wall(Vector2(centre_x + opening_half, wing.position.y - 35.0),
			Vector2(right, wing.position.y - 35.0), 70.0, 4.25, wall_mat)
		_wall(Vector2(left, wing.end.y + 35.0), Vector2(right, wing.end.y + 35.0),
			70.0, 0.68, wall_mat)
		_wall(Vector2(outer_x, wing.position.y - 35.0), Vector2(outer_x, wing.end.y + 35.0),
			70.0, 3.95, wall_mat)
		for span in [Vector2(wing.position.y - 35.0, 410.0), Vector2(630.0, 870.0),
			Vector2(1090.0, wing.end.y + 35.0)]:
			_wall(Vector2(inner_x, span.x), Vector2(inner_x, span.y), 70.0, 3.45, wall_mat)

		var upper_connector := WEST_UPPER_CONNECTOR if west else EAST_UPPER_CONNECTOR
		var lower_connector := WEST_LOWER_CONNECTOR if west else EAST_LOWER_CONNECTOR
		_sanctum_arch(inner_x, Vector2(upper_connector.position.y, upper_connector.end.y),
			wall_mat, arch_accent)
		_sanctum_arch(inner_x, Vector2(lower_connector.position.y, lower_connector.end.y),
			wall_mat, arch_accent)

		# The old version placed a huge luminous purple rectangle here. It read as a debug pad and
		# dominated every combat shot. The stone now remains uninterrupted; one hairline threshold is
		# enough to reveal the upper/lower connection without painting a target on the arena.
		if _show_decorative_sanctum_seals():
			_floor_strip(Vector2(centre_x - 58.0, 760.0), Vector2(centre_x + 58.0, 760.0),
				1.1, threshold_mat, 0.026)

		# Repeated edge columns reveal scale as the camera moves.  They sit beyond the playable outer
		# wall, so neither the legacy ritual nor the horde needs new collision data.
		var column_x := wing.position.x - 78.0 if west else wing.end.x + 78.0
		for py in [330.0, 760.0, 1190.0]:
			_sanctum_column(Vector2(column_x, py), 3.55, wall_mat, arch_accent)

	# Four large but unobstructed elemental courts.  Long inlays lead to both the hall and central
	# passage, making the expanded floor legible even when phone mode removes dynamic wing lights.
	for el in ["Water", "Beast", "Fire", "Storm"]:
		var center := Vector2(PLATE_POS[el])
		var west := center.x < 0.0
		var element_color := NP.el_color(String(el))
		var accent := _glow_mat(element_color.darkened(0.25), 0.28) \
			if _show_decorative_sanctum_seals() else _shared_glow(
				"wicked_violet", Color(0.60, 0.16, 0.92), 1.20 if _low else 1.72)
		if _show_decorative_sanctum_seals():
			# Ritual mode keeps a restrained interactive landmark. Horde mode has its own waypoint and
			# encounter HUD, so the subclass removes these non-functional floor marks entirely.
			_disc_piece(center, 2.35, 0.016, accent)
			_disc_piece(center, 2.22, 0.024, inner_mat)
		if _show_decorative_sanctum_seals():
			var route_accent := _glow_mat(element_color.darkened(0.62), 0.07)
			var hall_x := WALL_L if west else WALL_R
			# Ritual mode retains a restrained cue because the player must locate the active seal.
			_floor_strip(center, Vector2(hall_x, center.y), 0.85, route_accent)
			# A pair of short cross-inlays gives each ritual court a readable interaction diameter.
			_floor_strip(center + Vector2(-86.0, -54.0), center + Vector2(86.0, -54.0),
				1.4, route_accent)
			_floor_strip(center + Vector2(-86.0, 54.0), center + Vector2(86.0, 54.0),
				1.4, route_accent)
		_sanctum_terrace(center, west, wall_mat, accent)

	# Corridor curbs are decorative and desktop-only.  They lie just outside the connector union;
	# the navigation rectangles, not these meshes, remain the collision authority.
	if not _low:
		for connector in [WEST_UPPER_CONNECTOR, WEST_LOWER_CONNECTOR,
			EAST_UPPER_CONNECTOR, EAST_LOWER_CONNECTOR]:
			_wall(Vector2(connector.position.x, connector.position.y - 9.0),
				Vector2(connector.end.x, connector.position.y - 9.0), 18.0, 0.38, wall_mat)
			_wall(Vector2(connector.position.x, connector.end.y + 9.0),
				Vector2(connector.end.x, connector.end.y + 9.0), 18.0, 0.38, wall_mat)

# Shared high-detail stacked masonry generated for the reference-matched art pass.
func _wall_tex() -> Texture2D:
	return WICKED_WALL_TEX

func _build_walls() -> void:
	var mat := _wicked_wall_mat()
	var T := 120.0
	# NORTH wall, behind the altar — the one the camera looks INTO, so it carries the room's face
	_wall(Vector2(WALL_L - T, FLOOR_TOP - T * 0.5), Vector2(WALL_R + T, FLOOR_TOP - T * 0.5), T, WALL_H, mat)
	# Side walls retain their original line, now split at the two elemental doorways.
	var side_spans := [
		Vector2(FLOOR_TOP - T, 410.0), Vector2(630.0, 870.0),
		Vector2(1090.0, FLOOR_BOT + T),
	]
	for span in side_spans:
		_wall(Vector2(WALL_L - T * 0.5, span.x), Vector2(WALL_L - T * 0.5, span.y), T, WALL_H, mat)
		_wall(Vector2(WALL_R + T * 0.5, span.x), Vector2(WALL_R + T * 0.5, span.y), T, WALL_H, mat)
	# SOUTH wall, split around the doorway. Kept LOW (1.5 m) because it sits between the camera and
	# the player: a full-height wall here would hide the character every time they walked to the door.
	_wall(Vector2(WALL_L - T, FLOOR_BOT + T * 0.5), Vector2(DOOR_X0, FLOOR_BOT + T * 0.5), T, 1.5, mat)
	_wall(Vector2(DOOR_X1, FLOOR_BOT + T * 0.5), Vector2(WALL_R + T, FLOOR_BOT + T * 0.5), T, 1.5, mat)
	# A real aperture with a flush dark threshold; raised near-camera caps consume phone play space.
	var dark := _wicked_deep_mat()
	_floor_piece(Rect2(DOOR_X0, DOOR_PLATE.end.y, DOOR_X1 - DOOR_X0, 60.0), dark, 0.020)
	var post := _wicked_trim_mat()
	for px in [DOOR_X0 - 20.0, DOOR_X1 + 20.0]:
		_wall(Vector2(px, FLOOR_BOT + 40.0), Vector2(px, DOOR_PLATE.end.y), 44.0, 3.4, post)

func _build_pillars() -> void:
	var shaft := _wicked_wall_mat()
	var trim := _wicked_trim_mat()
	var cylinder_key := "pillar_shaft:%s" % ("low" if _low else "hd")
	var cy: CylinderMesh = _mesh_cache.get(cylinder_key) as CylinderMesh
	if cy == null:
		cy = CylinderMesh.new()
		cy.top_radius = 0.40
		cy.bottom_radius = 0.44
		cy.height = WALL_H * 0.82
		cy.radial_segments = 12 if _low else 20
		_mesh_cache[cylinder_key] = cy
	var band := _cylinder_mesh(0.46, 0.22, 12 if _low else 20)
	for p in PILLARS:
		var col := Node3D.new()
		col.position = px2m(p)
		add_child(col)
		var m := MeshInstance3D.new()
		m.mesh = cy
		m.material_override = shaft
		m.position = Vector3(0, WALL_H * 0.41, 0)
		col.add_child(m)
		for yb in [0.22, WALL_H * 0.80]:
			_box_piece(Vector3(0, yb, 0), Vector3(1.16, 0.36, 1.16), shaft, col)
		var bd := MeshInstance3D.new()
		bd.mesh = band
		bd.material_override = trim
		bd.position = Vector3(0, WALL_H * 0.46, 0)
		col.add_child(bd)

func _build_dais() -> void:
	var mat := _wicked_wall_mat()
	# Five broad rear steps reproduce the reference's layered sanctum approach. They remain wholly
	# inside the altar's existing solid rectangle, so the extra visual depth cannot enter combat.
	for i in range(5):
		var inset := float(i) * 34.0
		_box_piece(px2m(Vector2(1200.0, 300.0 - inset * 0.5), 0.10 + float(i) * 0.20),
			Vector3((560.0 - inset * 2.0) * PX2M, 0.20, (200.0 - inset) * PX2M), mat)
	# the altar table, and Grimwick standing behind it
	_box_piece(px2m(Vector2(1200.0, 330.0), 1.45), Vector3(2.5, 0.9, 0.8),
		_wicked_deep_mat())
	_grim_rig = _make_rig("grimwick", "grimwick", 2.4)
	var gh := Node3D.new()
	gh.position = px2m(Vector2(1200.0, 250.0), 1.00)
	_actors.add_child(gh)
	gh.add_child(_grim_rig)
	if _grim_rig.has_method("face"):
		_grim_rig.call("face", Vector2.DOWN)

func _build_plates() -> void:
	for el in PLATE_POS:
		var holder := Node3D.new()
		# Raised above the shallow sanctum/boss inlays so the rune never z-fights or disappears.
		holder.position = px2m(Vector2(PLATE_POS[el]), 0.040)
		add_child(holder)
		var pm := PlaneMesh.new()
		pm.size = Vector2(2.3, 2.3)
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		var m := StandardMaterial3D.new()
		m.albedo_color = NP.el_color(String(el))
		m.emission_enabled = true
		m.emission = NP.el_color(String(el))
		m.emission_energy_multiplier = 0.12
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_texture = _rune_tex()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		holder.add_child(mi)
		_plates[el] = {"mesh": mi, "mat": m}
	# Exactly one ritual seal can be active, so five dormant OmniLight nodes were pure overhead. HD
	# moves one shared lamp to the active plate; phone communicates the same state through emission.
	if not _low and _world_light_count < 4:
		_plate_light = OmniLight3D.new()
		_plate_light.light_energy = 0.0
		_plate_light.omni_range = 6.5
		_plate_light.shadow_enabled = false
		add_child(_plate_light)
		_world_light_count += 1

func _plate_state(el: String, on: bool) -> void:
	if not _plates.has(el):
		return
	var d: Dictionary = _plates[el]
	var m := d["mat"] as StandardMaterial3D
	# 0.78 of the element colour when lit, not full: an emissive surface plus a light of the same
	# hue drives the dominant channel into the clip and every element collapses toward white — the
	# same measurement that set the 2D hall's rune colours.
	m.emission_energy_multiplier = 1.9 if on else 0.10
	m.albedo_color = NP.el_color(el) * (0.78 if on else 0.42)
	# On phone/lite the emissive rune carries the state alone. HD reuses one lamp for whichever seal
	# is active rather than keeping five lights resident.
	if on and _plate_light != null and is_instance_valid(_plate_light):
		_plate_light.light_color = NP.el_color(el)
		_plate_light.global_position = px2m(Vector2(PLATE_POS[el]), 0.94)
		_plate_light.light_energy = 1.5

func _rune_tex() -> Texture2D:
	if _shared_rune_tex != null:
		return _shared_rune_tex
	var N := 192
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(N) * 0.5
	for y in range(N):
		for x in range(N):
			var dx := float(x) - c
			var dy := float(y) - c
			var r := sqrt(dx * dx + dy * dy) / c
			var a := 0.0
			if r < 0.96 and r > 0.86: a = 1.0                 # outer ring
			elif r < 0.66 and r > 0.60: a = 0.9               # inner ring
			elif r < 0.58: a = 0.20                           # the disc it all sits on
			if a > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, a))
	# the five-point star, drawn as lines between the ring's vertices
	for i in range(5):
		var a1 := -PI * 0.5 + TAU * float(i) / 5.0
		var a2 := -PI * 0.5 + TAU * float((i + 2) % 5) / 5.0
		var p1 := Vector2(c + cos(a1) * c * 0.60, c + sin(a1) * c * 0.60)
		var p2 := Vector2(c + cos(a2) * c * 0.60, c + sin(a2) * c * 0.60)
		var steps := int(p1.distance_to(p2))
		for s in range(steps):
			var p := p1.lerp(p2, float(s) / float(maxi(1, steps)))
			for oy in range(-2, 3):
				for ox in range(-2, 3):
					var xx := int(p.x) + ox
					var yy := int(p.y) + oy
					if xx >= 0 and xx < N and yy >= 0 and yy < N:
						img.set_pixel(xx, yy, Color(1, 1, 1, 1))
	img.generate_mipmaps()
	_shared_rune_tex = ImageTexture.create_from_image(img)
	return _shared_rune_tex

# ---- torches: the only real lights in the room -------------------------------------------------
func _torch(at: Vector2, h: float, energy: float, keep_light: bool) -> void:
	var n := Node3D.new()
	n.position = px2m(at)
	add_child(n)
	# A BRAZIER, NOT A CONE. The first pass was a tall thin cylinder with an emissive ball on top,
	# which from a camera looking down read as a traffic cone wearing a flat yellow oval. A stand
	# has a foot, a stem and a bowl, and the silhouette is most of what says "this is furniture".
	var segments := 8 if _low else 12
	var foot := _frustum_mesh("brazier_foot", 0.20, 0.34, 0.16, segments)
	var fmi := MeshInstance3D.new()
	fmi.mesh = foot
	fmi.material_override = _wicked_wall_mat()
	fmi.position = Vector3(0, 0.08, 0)
	n.add_child(fmi)
	var stem := _frustum_mesh("brazier_stem", 0.075, 0.10, h - 0.28, segments)
	var smi := MeshInstance3D.new()
	smi.mesh = stem
	smi.material_override = _wicked_trim_mat()
	smi.position = Vector3(0, 0.16 + (h - 0.28) * 0.5, 0)
	n.add_child(smi)
	var bowl := _frustum_mesh("brazier_bowl", 0.34, 0.16, 0.26, segments)
	var bmi := MeshInstance3D.new()
	bmi.mesh = bowl
	# DARK IRON, NOT PALE STONE. At 0.30 the bowl sat directly under its own light, came out the
	# brightest thing on the stand, and the whole brazier read as a candlestick with a wick. A fire
	# bowl is scorched: the flame should be the only bright thing up there.
	bmi.material_override = _wicked_deep_mat()
	bmi.position = Vector3(0, h - 0.02, 0)
	n.add_child(bmi)
	# THE STAND MUST NOT CAST. Its own light sits 25 cm above it, so it shadowed itself and printed
	# a hard black disc on the floor under every brazier — twelve dark holes in a torchlit room.
	# The pillars still cast, which is where a shadow actually tells you about the space.
	for m in [fmi, smi, bmi]:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# THE FLAME IS A BILLBOARD, NOT GEOMETRY. An emissive sphere seen from above is a disc, and a
	# disc is the one shape fire never makes. A soft vertical teardrop that always faces the camera
	# reads as flame from any angle, costs one quad, and is what every game of this kind uses.
	var fl := Sprite3D.new()
	fl.texture = _flame_tex()
	fl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	fl.shaded = false
	fl.double_sided = true
	fl.transparent = true
	fl.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	fl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	fl.pixel_size = 0.0115
	fl.modulate = Color(0.88, 0.54, 1.0)
	fl.position = Vector3(0, h + 0.42, 0)
	fl.render_priority = 1
	n.add_child(fl)
	# Phone renders the flame alone. The second translucent halo costs another sorted draw per
	# brazier and is redundant without bloom; desktop retains it for the reference's soft violet fog.
	if not _low and keep_light:
		var glow := Sprite3D.new()
		glow.texture = _blob_tex()
		glow.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		glow.shaded = false
		glow.transparent = true
		glow.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		glow.pixel_size = 0.034
		glow.modulate = Color(0.64, 0.24, 1.0, 0.36)
		glow.position = Vector3(0, h + 0.34, 0)
		glow.render_priority = 0
		n.add_child(glow)
	# THE LIGHT IS THE EXPENSIVE PART, so the low tier keeps the flame and drops the lamp. That is
	# the same split the 2D hall made and for the same reason: the glow is what you SEE, the light
	# is what costs. Only the landmarks down the processional way keep theirs.
	var light_cap := 2 if _low else 4
	if keep_light and _world_light_count < light_cap:
		var l := OmniLight3D.new()
		# 0.78 saturation, not 0.38. At full warmth every torch multiplied the violet stone toward
		# brown and the hall lost the colour it is supposed to have — measured by eye against the
		# 2D hall, which is purple. The flame sprite stays hot; the LIGHT is pulled back toward
		# white so it lifts the stone instead of dyeing it.
		l.light_color = Color(0.69, 0.42, 1.0)
		l.light_energy = energy
		l.omni_range = 9.0
		l.position = Vector3(0, h + 0.44, 0)
		# One authored shadow light on desktop gives the columns depth; every other violet pool is
		# shadowless. Phone keeps zero shadow maps.
		l.shadow_enabled = (not _low) and _world_light_count == 0
		n.add_child(l)
		_world_light_count += 1
	# the flicker, unsynchronised: twelve metronomes read as a machine, not a fire
	_flames.append({"n": n, "ph": randf() * TAU, "e": energy, "h": h})

func _build_torches() -> void:
	# Each side court gets a pair of lightless altar flames around its radial gate. The flame is the
	# visible reference cue; omitting local Light3D nodes keeps the existing two/four-light budget.
	for wing_v in [WEST_WING, EAST_WING]:
		var wing := wing_v as Rect2
		for offset in [-250.0, 250.0]:
			_torch(Vector2(wing.get_center().x + float(offset), 158.0), 1.18, 1.15, false)
	for by in [560.0, 880.0, 1200.0]:
		# Desktop adds one central pair; the phone tier pays for only the altar pair below.
		var lit_pair := (not _low) and (not _show_decorative_sanctum_seals()) \
			and is_equal_approx(by, 880.0)
		_torch(Vector2(950.0, by), 1.5, 2.4, lit_pair)
		_torch(Vector2(1450.0, by), 1.5, 2.4, lit_pair)
	_torch(Vector2(980.0, 358.0), 1.3, 2.0, true)
	_torch(Vector2(1420.0, 358.0), 1.3, 2.0, true)
	_torch(Vector2(1060.0, 1320.0), 1.3, 1.8, false)
	_torch(Vector2(1340.0, 1320.0), 1.3, 1.8, false)
	# The old side lamps still sat in the central hall after the wings moved hundreds of pixels
	# outward.  Three landmarks now run down each true outer wall.  Phone keeps their flame cards and
	# drops their lights through _torch's existing low-tier branch; desktop pays no more wing lights
	# than the former six-lamp layout.
	for ty in [330.0, 760.0, 1190.0]:
		_torch(Vector2(WEST_WING.position.x + 22.0, ty), 1.4, 1.6, false)
		_torch(Vector2(EAST_WING.end.x - 22.0, ty), 1.4, 1.6, false)

# ---- the player ----
func _build_player() -> void:
	_player = Node3D.new()
	_actors.add_child(_player)
	_rig = _make_rig("avatar", _avatar, CHAR_CELL_M)
	_player.add_child(_rig)
	_player.add_child(_shadow(0.46))
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.near = 0.1
	_cam.far = 90.0
	add_child(_cam)
	_cam.current = true

# A BLOB SHADOW, NOT A CAST ONE. A billboard's real shadow degenerates as the camera pitches — the
# card turns edge-on to the light and throws a sliver. A decal on the floor is what actually welds
# a sprite to the ground, and it costs nothing.
func _shadow(r: float) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(r * 2.0, r * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0, 0, 0, 0.42)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _blob_tex()
	m.render_priority = -1
	mi.material_override = m
	mi.position = Vector3(0, 0.012, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

# a soft vertical teardrop: hot core, warm body, transparent tips
func _flame_tex() -> Texture2D:
	if _shared_flame_tex != null:
		return _shared_flame_tex
	var W := 48
	var H := 96
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(H):
		var v: float = float(y) / float(H - 1)          # 0 at the tip, 1 at the base
		# the profile: narrow at the top, widest a third up from the base, tucked in at the bottom
		var wprof: float = sin(pow(v, 0.62) * PI)
		var half: float = wprof * float(W) * 0.46
		if half < 0.5:
			continue
		for x in range(W):
			var dx: float = absf(float(x) - float(W) * 0.5)
			if dx > half:
				continue
			var r: float = dx / maxf(0.001, half)
			var body: float = pow(1.0 - r * r, 1.4)
			var a: float = body * clampf(1.0 - pow(1.0 - v, 2.2), 0.0, 1.0)
			# The core runs pale while the body stays violet; one neutral-violet texture serves every
			# brazier and modulates cleanly instead of multiplying purple over the old orange pixels.
			var heat: float = clampf(body * (0.35 + 0.85 * v), 0.0, 1.0)
			var c := Color(0.80, 0.46, 1.0).lerp(Color(1.0, 0.95, 1.0), heat)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	_shared_flame_tex = ImageTexture.create_from_image(img)
	return _shared_flame_tex

func _tick_flames(delta: float) -> void:
	_ft += delta
	for f in _flames:
		var n = f.get("n")
		if n == null or not is_instance_valid(n):
			continue
		var ph: float = float(f["ph"])
		# two incommensurate rates so the loop never audibly repeats
		var k: float = 0.86 + 0.14 * sin(_ft * 7.3 + ph) + 0.07 * sin(_ft * 17.1 + ph * 2.0)
		for c in (n as Node3D).get_children():
			if c is OmniLight3D:
				(c as OmniLight3D).light_energy = float(f["e"]) * k
			elif c is Sprite3D:
				var s := c as Sprite3D
				s.scale = Vector3(1.0 + 0.06 * (k - 1.0) * 4.0, k, 1.0)

func _blob_tex() -> Texture2D:
	if _shared_blob_tex != null:
		return _shared_blob_tex
	var N := 64
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var c := float(N) * 0.5
	for y in range(N):
		for x in range(N):
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a * 0.9))
	img.generate_mipmaps()
	_shared_blob_tex = ImageTexture.create_from_image(img)
	return _shared_blob_tex

# THE PITCH THE RIGS ARE STRETCHED FOR MUST BE THE PITCH THE CAMERA ACTUALLY USES. A subclass
# that runs its own camera at a different angle overrides this, or every billboard it shows is
# pre-stretched for the wrong elevation. Measured: TempleHorde3D pitches at 35 while this base
# says 38 — 1/cos(38) = 1.2690 baked in against a correct 1/cos(35) = 1.2208, so every fighter in
# the shipping hall stood 3.95% too tall. Not visible as an error, only as a slightly wrong world.
func _rig_pitch_deg() -> float:
	return PITCH_DEG

func _make_rig(kind: String, id: String, h_m: float) -> Node3D:
	var R = load("res://Rig3D.gd")
	var n: Node3D = null
	var pitch := _rig_pitch_deg()
	if kind == "avatar":
		n = R.for_avatar(id, h_m, pitch)
	elif kind == "grimwick":
		n = R.for_grimwick(h_m, pitch)
	else:
		n = R.for_species(id, h_m, pitch)
	if n != null and n.has_method("set_distance_driven_walk"):
		n.call("set_distance_driven_walk", true, 72.0)
	return n

func _build_solids() -> void:
	# The union of PLAYABLE_REGIONS is the outer boundary; solids are reserved for furniture.
	_solids.append(Rect2(DOOR_X0, FLOOR_BOT + 88.0, DOOR_X1 - DOOR_X0, 400.0))
	_solids.append(Rect2(940.0, FLOOR_TOP, 520.0, 200.0))
	for pp in PILLARS:
		_solids.append(Rect2(pp.x - 42.0, pp.y - 26.0, 84.0, 44.0))

# =============================== the ritual's effects ==========================================
# THE BOLT AND THE BURST HAVE TO LIVE HERE NOW. Temple.gd used to build a Sprite2D and a
# CPUParticles2D and parent them to the world, which was fine while the world was a Node2D. Parent
# a Sprite2D to a Node3D and it simply does not render — no error, no warning, just a strike with
# nothing coming out of it. So the ritual asks for an effect and the world decides what that means.

func is_3d() -> bool:
	return true

func bolt_fx(from: Vector2, at: Vector2, col: Color, secs: float = 0.22) -> void:
	var s := Sprite3D.new()
	s.texture = _blob_tex()
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.transparent = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	s.pixel_size = 0.012
	s.modulate = Color(col.r, col.g, col.b, 0.95)
	s.render_priority = 2
	add_child(s)
	s.global_position = px2m(from, 0.9)
	# The duel can throw several bolts per turn.  Emissive billboard colour is enough on the phone
	# tier; a fresh dynamic light per card would multiply the most expensive part of the effect.
	if not _low:
		var l := OmniLight3D.new()
		l.light_color = col
		l.light_energy = 2.2
		l.omni_range = 4.5
		s.add_child(l)
	var tw := create_tween()
	# AN ARC, NOT A STRAIGHT LINE. A bolt travelling flat across the floor reads as a slide; the
	# lift is what makes it read as thrown. Written as a bound method rather than a multi-line
	# lambda inside the argument list — that form parsed, which is worse than failing, because the
	# trailing tween arguments ended up inside the lambda body where nothing would ever use them.
	tw.tween_method(_bolt_step.bind(s, from, at), 0.0, 1.0, secs)
	tw.tween_callback(_free_node.bind(s))

func _bolt_step(t: float, s: Sprite3D, from: Vector2, at: Vector2) -> void:
	if s == null or not is_instance_valid(s):
		return
	s.global_position = px2m(from.lerp(at, t), 0.9 + sin(t * PI) * 0.85)

func _free_node(n: Node) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()

func impact_fx(at: Vector2, col: Color, big: bool) -> void:
	var p := GPUParticles3D.new()
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 65.0
	m.initial_velocity_min = 2.2
	m.initial_velocity_max = 6.0 if big else 3.4
	m.gravity = Vector3(0, -7.5, 0)
	m.scale_min = 0.5
	m.scale_max = 1.3
	m.color = col
	p.process_material = m
	var dm := StandardMaterial3D.new()
	dm.albedo_color = col
	dm.emission_enabled = true
	dm.emission = col
	dm.emission_energy_multiplier = 2.4
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.albedo_texture = _blob_tex()
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.16)
	q.material = dm
	p.draw_pass_1 = q
	p.amount = (18 if big else 8) if _low else (48 if big else 20)
	p.lifetime = 0.75
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = true
	add_child(p)
	p.global_position = px2m(at, 0.35)
	# a Callable bound to the node itself, never a lambda capturing it: the world can be torn down
	# under this timer, and a bound callable simply finds nobody home
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)
	# Keep the HD flash, skip its full-scene light pass on mobile.  The reduced emissive burst above
	# preserves hit readability without allowing rapid card plays to overlap dynamic lights.
	if not _low:
		var fl := OmniLight3D.new()
		fl.light_color = col
		fl.light_energy = 5.0 if big else 2.0
		fl.omni_range = 8.0
		add_child(fl)
		fl.global_position = px2m(at, 0.8)
		var t2 := create_tween()
		t2.tween_property(fl, "light_energy", 0.0, 0.45)
		t2.tween_callback(_free_node.bind(fl))
