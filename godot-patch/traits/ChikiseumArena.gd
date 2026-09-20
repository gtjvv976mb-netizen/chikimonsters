extends Control
class_name ChikiseumArena

## Server-authoritative presentation. No SOL, Cup, AI, collision damage, combat math or payout.
## Verified live admission is isolated from the native-debug practice transport and art rehearsal.
## Snapshot schema is chikiseum.battle/v1. Server owns private hand, HP, energy, turns and outcomes.
## The separate local fixture is a TWO-HUMAN ART REHEARSAL; it never changes HP or awards anything.
signal request(intent: Dictionary)
signal close_requested
signal snapshot_rejected(reason: String)

const Visual := preload("res://TempleAbilityVisual.gd")
const Sprites := preload("res://TempleAbilitySprites.gd")
const ArtStream := preload("res://TempleAbilityArtStream.gd")
const CardArt := preload("res://TempleCardArt.gd")
const CardPresentation := preload("res://ChikiseumCardPresentation.gd")
const DeckCard := preload("res://ChikiseumDeckCard.gd")
const WorldRig := preload("res://Rig3D.gd")
const Architecture := preload("res://ChikiseumArenaWorld.gd")
const MoveSurface := preload("res://ChikiseumArenaControls.gd")
const Navigation := preload("res://ChikiseumArenaNavigation.gd")
const ReferenceFloor := preload("res://ChikiseumReferenceFloor.gd")
const ReferenceWorld := preload("res://ChikiseumReferenceWorld.gd")
const ChikoriaSurround := preload("res://ChikiseumChikoriaSurround.gd")
const Device := preload("res://HDStruct.gd")
const ReferenceNavigation := preload("res://ChikiseumReferenceNavigation.gd")
const DuelHUD := preload("res://ChikiseumDuelHUD.gd")
const Targeting := preload("res://ChikiseumTargeting.gd")
const UISkin := preload("res://ChikiseumUISkin.gd")
const EnergyMeter := preload("res://ChikiseumEnergyMeter.gd")
const REFERENCE_IMAGE := preload("res://chikiseum_reference_interior_v1.png")
const REFERENCE_PIXELS := Vector2(1672, 941)
const REFERENCE_CAMERA_AT := Vector3(0, 11.16741731, 31.02274794)
const REFERENCE_CAMERA_TARGET := Vector3(0, 0, -6.64769235)
const REFERENCE_FOV := 31.89796133
const REFERENCE_PITCH := 16.51247825
const Econ := preload("res://Econ.gd")
const FONT := preload("res://ui_font.ttf")
const BOLD := preload("res://ui_font_bold.ttf")
const GOLD := Color("dfb963")
const NAVY := Color("091323")
const BLUE := Color("4eaef3")
const RED := Color("ee6c74")
const SIDES := ["A", "B"]
const TRAVELLING := ["straight_bolt", "homing_orb", "chain_bolt", "siphon_tether", "curse_spiral", "gaze_ray", "line_rend"]
const EVENT_TYPES := ["cast", "impact", "block", "status_start", "status_end", "heal", "recoil", "finish"]
const FX_LIMIT := 40
const TERMINAL := ["finished", "cancelled", "forfeit", "ready_timeout", "turn_timeout", "draw", "catalogue_changed", "arena_changed", "admission_revoked"]

var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _arena_environment: Environment
var _arena_sun: DirectionalLight3D
var _crystal_lights: Array[OmniLight3D] = []
var _render_quality_tier := -1
var _quality_check_clock := 0.0
var _stream: TempleAbilityArtStream
var _rigs: Dictionary = {}
var _plates: Dictionary = {}
var _hands: Dictionary = {"A": [], "B": []}
var _decks: Dictionary = {}
var _selected: Dictionary = {"A": [], "B": []}
var _pages: Dictionary = {"A": 0, "B": 0}
var _players: Dictionary = {}
var _effects: Array[Dictionary] = []
var _states: Dictionary = {}
var _events: Array[Dictionary] = []
var _seen: Dictionary = {}
var _max_seq := 0
var _event_delay := 0.0
var _revision := -1
var _match_id := ""
var _local_fixture := false
var _you := "A"
var _committed := false
var _snapshot: Dictionary = {}
var _server_time := 0.0
var _received_ticks := 0
var _title: Label
var _clock: Label
var _note: Label
var _lobby: PanelContainer
var _lobby_note: Label
var _invite: LineEdit
var _species: Dictionary = {}
var _reset: Button
var _tweens: Array[Tween] = []
var _transport: Node
var _handle: LineEdit
var _server: LineEdit
var _level: SpinBox
var _peers: OptionButton
var _challenges: OptionButton
var _pinned_layers: Dictionary = {} # Four exact-card FX sheets; delayed phases survive LRU eviction.
var _pin_order: Array[String] = []
var _art_wait := 0.0
var _stake: SpinBox
var _cancel_pending := false
var _close_after_cancel := false
var _finish_pending := false
var _move_surface: Control
var _movement_targets: Dictionary = {}
var _move_clock := 0.0
var _movement_revision := -1
var _camera_close := false
var _view_button: Button
var _dashing: Dictionary = {}
var _camera_target_size := Architecture.CAMERA_SIZE
var _camera_focus := Vector3.ZERO
var _camera_match_framed := false
@export var reference_image_mode := false # Isolated OFFLINE image-based art rehearsal, never old server physics.
@export var reference_world_mode := true # ACTUAL 3D arena reconstructed from the 2D reference.
@export var online_entry_mode := false # Builds an online lobby, NEVER grants admission or a match.
var _live_authenticated := false
var _live_session: Dictionary = {}
var _live_fighter_label: Label
var _practice_controls: Array[Control] = []
var _live_actions: Array[Control] = []
var _live_retry: Button
var _auth_connection_lost := false
var _live_art_bound := false
var _admission_retry: Button
var _stage: Control
var _reference_backdrop: TextureRect
var _reference_guide: Line2D
var _duel_hud: Control
var _targeting: Control
var _practice_view_side := "A"
var _hover_side := ""
var _hover_index := -1
var _inspector: Panel
var _inspect_image: TextureRect
var _inspect_title: Label
var _inspect_detail: Label
var _switch_trainer: Button
var _help_button: Button
var _rules: AcceptDialog
var _leave_dialog: ConfirmationDialog
var _feedback: Label
var _feedback_left := 0.0
var _ui_clock := 0.0
var _target_state: Dictionary = {}
var _hover_tweens: Dictionary = {}
var _commit_pending := false
var _ready_pending := false
var _card_dialog: AcceptDialog
var _card_dialog_image: TextureRect
var _local_cast_until := {"A": 0.0, "B": 0.0}
var _inspection_tween: Tween
const LIVE_COOLDOWN_SECONDS := {"strike":.65,"blast":1.2,"quick":1.5,"guard":3.0,"charge":6.0,"drain":1.6,"nova":4.0,"rend":1.1,"jolt":1.6,"rally":7.0,"wither":3.0,"bulwark":5.0}

func _continuous() -> bool:
	return _snapshot.get("combat_mode") == "realtime" or (_local_fixture and reference_world_mode)

func _server_now() -> float:
	return _server_time + float(Time.get_ticks_msec() - _received_ticks) / 1000.0

func _cooldown_left(slot: int) -> float:
	if _local_fixture:return maxf(0,float(_local_cast_until[_active_side()])-float(Time.get_ticks_msec())/1000.0)
	var you:Dictionary=_snapshot.get("you",{})
	var cooldowns:Dictionary=you.get("cooldowns",{})
	return maxf(0,maxf(float(cooldowns.get(str(slot),0)),float(you.get("global_cooldown_until",0)))-_server_now())


static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _actor_map(value: Variant) -> Dictionary:
	if value is Dictionary and value.size() == 2 and value.has("A") and value.has("B"): return value
	if value is Array and value.size() == 2:
		var actors := {}
		for player in value:
			if not player is Dictionary or not SIDES.has(String(player.get("side", ""))) or actors.has(player.side): return {}
			actors[player.side] = player
		return actors
	return {}


static func validate_snapshot(value: Dictionary, reference_world: bool = false, expected_mode: String = "practice") -> Array[String]:
	var errors: Array[String] = []
	var reference_plan := ReferenceNavigation.binding() if reference_world else {}
	if reference_world and reference_plan.is_empty():
		errors.append("The matching full-floor Chikiseum geometry contract is unavailable.")
		return errors
	if expected_mode not in ["practice", "live"] or value.get("schema") != "chikiseum.battle/v1" or value.get("mode") != expected_mode:
		errors.append("The explicitly selected battle contract is required.")
	if expected_mode == "live" and (not reference_world or value.get("inventory_verified") != true or value.get("currency") != "NONE" or value.get("real_sol_enabled") != false or value.get("combat_mode") != "realtime" or not value.has("arena")):
		errors.append("Live battles require verified inventory, no currency, and the matching realtime arena.")
	if (value.has("currency") and value.currency != ("NONE" if expected_mode == "live" else "TEST_CREDITS")) or value.get("real_sol_enabled", false) != false:
		errors.append("Real-money presentation is disabled.")
	if not value.get("match_id") is String or String(value.get("match_id", "")).is_empty() or not _integer(value.get("revision")) or float(value.get("revision", -1)) < 0:
		errors.append("Match ID and nonnegative integer revision are required.")
	if not _integer(value.get("turn")) or float(value.get("turn", -1)) < 0:
		errors.append("A server turn is required.")
	if (not _number(value.get("deadline")) and not (value.get("deadline") == null and value.get("status") in TERMINAL)) or not _number(value.get("server_time")):
		errors.append("Server clock/deadline are required.")
	if not String(value.get("status", "")) in ["ready", "active", "waiting"] + TERMINAL:
		errors.append("Explicit server battle status is required.")
	var players := _actor_map(value.get("players"))
	if players.size() != 2:
		errors.append("Exactly two human actor sides are required.")
		return errors
	for side in SIDES:
		var player: Variant = players.get(side)
		if not player is Dictionary:
			errors.append("Missing actor side " + side)
			continue
		var p := player as Dictionary
		var sp := String(p.get("species", ""))
		if p.get("side") != side or String(p.get("trainer_id", "")).is_empty() or Visual.profile(sp, 0).is_empty():
			errors.append("Invalid frozen human actor identity " + side)
		if not _integer(p.get("level")) or not 1 <= float(p.get("level", 0)) or float(p.get("level", 0)) > 50:
			errors.append("Invalid server-owned level " + side)
		if not _number(p.get("max_hp")) or float(p.get("max_hp", 0)) <= 0 or not _number(p.get("hp")) or float(p.get("hp", -1)) < 0 or float(p.get("hp", 0)) > float(p.get("max_hp", 0)):
			errors.append("Invalid authoritative health " + side)
		if not _number(p.get("energy")) or float(p.get("energy", -1)) < 0:
			errors.append("Invalid authoritative energy " + side)
		if not p.get("statuses") is Dictionary or not p.get("display_name") is String or not p.get("rarity") is String:
			errors.append("Explicit actor name, rarity and status state are required.")
		if p.has("position"):
			if not p.position is Dictionary or not _number(p.position.get("x")) or not _number(p.position.get("y")) or not _number(p.position.get("z")):
				errors.append("Authoritative arena positions must have finite x/y/z coordinates.")
			elif Vector2(float(p.position.x), float(p.position.z)).length() > (float(reference_plan.floor_radius_m) if reference_world else 13.69) or float(p.position.y) < -0.001 or float(p.position.y) > (0.001 if reference_world else 0.361):
				errors.append("Authoritative arena position lies outside the playable floor.")
			else:
				var floor := ReferenceNavigation.ground_height(Vector2(float(p.position.x), float(p.position.z))) if reference_world else Navigation.ground_height(Vector2(float(p.position.x), float(p.position.z)))
				if not floor.valid or absf(float(floor.height_m) - float(p.position.y)) > 0.0001:
					errors.append("Authoritative fighter position overlaps the original geometry or mismatches its floor height.")
	if value.has("movement_revision") and (not _integer(value.movement_revision) or float(value.movement_revision) < 0):
		errors.append("Movement revision must be a nonnegative server integer.")
	if value.has("arena"):
		if reference_world:
			if not value.arena is Dictionary or value.arena.get("arena_id") != reference_plan.id \
				or value.arena.get("reference_plan_sha256") != ReferenceNavigation.PLAN_SHA256 \
				or value.arena.get("presentation") != "realtime_3d_rebuilt_from_2d_reference" \
				or value.arena.get("safe_radius_m") != reference_plan.floor_radius_m or value.arena.get("actor_radius_m") != reference_plan.actor_radius_m or value.arena.get("actor_height_m") != reference_plan.actor_height_m:
				errors.append("Reference-built 3D battles require their matching floor and visible-cover contract.")
		elif not value.arena is Dictionary or value.arena.get("voxel_sha256") != Architecture.VOXEL_SHA256 or value.arena.get("palette_sha256") != Architecture.PALETTE_SHA256 or value.arena.get("unit_scale") != Architecture.UNIT_SCALE \
				or value.arena.get("source_cells") != Architecture.SOURCE_CELL_COUNT or value.arena.get("safe_radius_m") != Navigation.PLAY_RADIUS_SOURCE * Architecture.UNIT_SCALE \
				or value.arena.get("actor_radius_m") != Navigation.FOOT_RADIUS_M or value.arena.get("actor_height_m") != Navigation.ACTOR_HEIGHT_M:
			errors.append("Server movement must use this exact Chikiseum landmark and scale.")
	if (players.get("A", {}) as Dictionary).get("trainer_id") == (players.get("B", {}) as Dictionary).get("trainer_id"):
		errors.append("Two distinct authenticated human trainer IDs are required.")
	var you: Variant = value.get("you")
	if not you is Dictionary or not SIDES.has(String(you.get("side", ""))) or not you.get("hand") is Array or not you.get("committed") is bool:
		errors.append("Authenticated private side/hand/commit state is required.")
		return errors
	var sp := String((players.get(String(you.side), {}) as Dictionary).get("species", ""))
	if value.get("combat_mode") == "realtime":
		var realtime:Variant=value.get("realtime")
		if not realtime is Dictionary or not _number(realtime.get("duration")) or float(realtime.get("duration",0))<=0 or not _number(realtime.get("remaining")) or not _number(realtime.get("energy_regen_per_second")):
			errors.append("Realtime match clock and energy rules must come from the server.")
		if int(value.get("turn",-1))!=0 or you.committed!=false:errors.append("Realtime matches cannot have locked turns.")
		if not you.get("cooldowns",{}) is Dictionary or not _number(you.get("global_cooldown_until",0)):
			errors.append("Realtime cooldown state is invalid.")
		else:
			for slot in (you.get("cooldowns",{}) as Dictionary):
				if not String(slot).is_valid_int() or int(slot)<0 or int(slot)>11 or not _number(you.cooldowns[slot]):errors.append("Realtime card cooldown is invalid.")
	var hand_slots := {}
	for card in you.hand:
		if not card is Dictionary or not _integer(card.get("slot")):
			errors.append("Hand entries require canonical slots, never hand-position aliases.")
			continue
		var profile := Visual.profile(sp, int(card.slot))
		if profile.is_empty() or card.get("key") != profile.get("key") or card.get("name") != profile.get("card_name") or not _number(card.get("cost")) or card.get("cost") != (Econ.CARDS[int(card.slot)] as Dictionary).get("cost", 1) or hand_slots.has(int(card.slot)):
			errors.append("Hand card does not belong to its canonical actor.")
		hand_slots[int(card.slot)] = true
	var events: Variant = value.get("events", [])
	if not events is Array or (events as Array).size() > (1024 if expected_mode == "live" else 512):
		errors.append("Bounded confirmed event history is required.")
		return errors
	var ids := {}; var seqs := {}; var previous_seq := 0
	for event in events:
		if not event is Dictionary:
			errors.append("Invalid event object.")
			continue
		var e := event as Dictionary
		if String(e.get("id", "")).is_empty() or not _integer(e.get("seq")) or float(e.get("seq", 0)) <= 0 or not _integer(e.get("turn")) or e.get("confirmed") != true or not EVENT_TYPES.has(String(e.get("type", ""))):
			errors.append("Confirmed event ID/sequence/turn/type are required.")
			continue
		if ids.has(e.id) or seqs.has(int(e.seq)) or int(e.seq) <= previous_seq:
			errors.append("Event history must have unique IDs and increasing sequences.")
		ids[e.id] = true; seqs[int(e.seq)] = true; previous_seq = int(e.seq)
		if e.type == "finish":
			continue
		var side := String(e.get("side", ""))
		var actor := players.get(side, {}) as Dictionary
		if not SIDES.has(side) or not _integer(e.get("slot")) or e.get("species") != actor.get("species") or Visual.profile(String(e.get("species", "")), int(e.get("slot", -1))).is_empty():
			errors.append("Event actor/card identity differs from the frozen fighter.")
		if not SIDES.has(String(e.get("target_side", ""))) or not _number(e.get("amount")) or float(e.get("amount", -1)) < 0:
			errors.append("Explicit target/outcome amount is required.")
	return errors


func _ready() -> void:
	name = "ChikiseumArena"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not OS.is_debug_build() and not online_entry_mode:
		hide()
		return
	add_theme_font_override("font", FONT)
	_build_world()
	_build_ui()
	_stream = ArtStream.new()
	add_child(_stream)
	_stream.configure("", false, false) # Explicit loopback opt-in only; no production art requests.
	_stream.asset_ready.connect(_art_ready)
	for raw in ([] if online_entry_mode else OS.get_cmdline_user_args()):
		var arg := String(raw)
		if arg.begins_with("--art-base="):
			configure_art(arg.trim_prefix("--art-base="))
	resized.connect(_layout)
	_layout()
	_note.text = "DEVELOPMENT ONLY · no SOL · no Cup changes · no combat/currency logic in this client"
	set_process(true)
	if not online_entry_mode and (reference_image_mode or reference_world_mode) and not "--start-lobby" in OS.get_cmdline_user_args(): start_local_rehearsal.call_deferred()


func configure_art(base: String) -> bool:
	# A native rehearsal can use the exact frozen402 manifest via --art-manifest, never activation.
	var local := (base.begins_with("http://127.0.0.1:") or base.begins_with("http://localhost:")) and not "@" in base and not "?" in base and not "#" in base and not "\\" in base
	if online_entry_mode or not OS.is_debug_build() or not local:
		return false
	Sprites.set_reborn_external_dev_enabled(false)
	_stream.configure(base, true, false)
	return true


func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.72
	return mat


func _cylinder(radius: float, height: float, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius; mesh.bottom_radius = radius; mesh.height = height; mesh.radial_segments = 48
	var node := MeshInstance3D.new()
	node.mesh = mesh; node.material_override = _material(color); node.position = at
	_world.add_child(node)
	return node


func _box(dim: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new(); mesh.size = dim
	var node := MeshInstance3D.new(); node.mesh = mesh; node.material_override = _material(color); node.position = at
	_world.add_child(node)


func _desired_reference_quality() -> int:
	var phone := Device.phone_world() or OS.has_feature("mobile")
	var main := get_tree().get_first_node_in_group("world_main")
	if main != null and main.has_method("gfx_tier"):
		return clampi(int(main.call("gfx_tier")), 0, 1 if phone else 2)
	return 0 if phone else 1 if OS.has_feature("web") else 2


func _apply_reference_quality(compact_screen: bool) -> void:
	if not reference_world_mode or _arena_environment == null or _arena_sun == null: return
	var tier := _desired_reference_quality()
	var phone := Device.phone_world() or OS.has_feature("mobile")
	var low := tier == 0
	var hd := tier == 2 and not compact_screen
	_render_quality_tier = tier
	# The duel is rendered in its own 3D viewport, so a phone can reduce fill cost
	# without blurring the separate cards, health bars or control surfaces.
	_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_viewport.scaling_3d_scale = 0.82 if low else 0.92 if tier == 1 or compact_screen else 1.0
	_viewport.msaa_3d = Viewport.MSAA_2X if phone or compact_screen or not hd else Viewport.MSAA_4X
	_viewport.positional_shadow_atlas_size = 1024 if low else 2048 if not hd else 4096
	_arena_environment.ambient_light_energy = 0.40 if low else 0.36 if not hd else 0.33
	_arena_environment.ssao_enabled = hd
	_arena_environment.ssao_radius = 1.25
	_arena_environment.ssao_intensity = 1.25
	_arena_environment.glow_enabled = not low
	_arena_environment.glow_intensity = 0.27 if not hd else 0.48
	_arena_environment.glow_bloom = 0.01 if not hd else 0.02
	# Keep genuine sprite silhouette shadows on every tier. The long-lens camera
	# starts far outside the ring, so even LOW needs a 190m shadow reach.
	_arena_sun.shadow_enabled = true
	_arena_sun.light_energy = 1.24 if low else 1.30
	_arena_sun.directional_shadow_max_distance = 190.0 if low else 220.0 if not hd else 240.0
	_arena_sun.directional_shadow_mode = (DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if not hd
		else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	for pool in _crystal_lights:
		pool.light_energy = 1.0 if low else 1.16 if not hd else 1.34


func _build_world() -> void:
	_stage = Control.new(); _stage.name = "CalibratedImageStage"; _stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(_stage)
	if reference_image_mode:
		var matte := ColorRect.new(); matte.name = "ImageLetterbox"; matte.color = Color("080810")
		matte.mouse_filter = Control.MOUSE_FILTER_IGNORE; matte.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(matte); move_child(matte, 0)
		_reference_backdrop = TextureRect.new(); _reference_backdrop.name = "ReferenceImageInterior"
		_reference_backdrop.texture = REFERENCE_IMAGE; _reference_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_reference_backdrop.stretch_mode = TextureRect.STRETCH_SCALE; _reference_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_reference_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _stage.add_child(_reference_backdrop)
	var holder := SubViewportContainer.new()
	holder.name = "ArenaViewport"; holder.stretch = true; holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _stage.add_child(holder)
	_viewport = SubViewport.new(); _viewport.name = "IsolatedArenaWorld"; _viewport.own_world_3d = true
	_viewport.size = Vector2i(1280, 720); _viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = reference_image_mode
	_viewport.msaa_3d = Viewport.MSAA_4X; holder.add_child(_viewport)
	_world = Node3D.new(); _viewport.add_child(_world)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR if reference_image_mode else Environment.BG_COLOR
	environment.environment.background_color = Color(0.018, 0.010, 0.034)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.48, 0.43, 0.58); environment.environment.ambient_light_energy = 1.05
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment.glow_enabled = true; environment.environment.glow_intensity = 0.66; environment.environment.glow_bloom = 0.12
	environment.environment.fog_enabled = not reference_image_mode; environment.environment.fog_density = 0.007
	environment.environment.fog_light_color = Color(0.20, 0.10, 0.28)
	_world.add_child(environment)
	_arena_environment = environment.environment
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-55, -28, 0); light.light_energy = 1.1
	light.shadow_enabled = true
	_world.add_child(light)
	_arena_sun = light
	for side in [-1.0, 1.0]:
		for lane in ([8.0,-8.0] if reference_world_mode else [-3.0]):
			var pool := OmniLight3D.new(); pool.light_color = Color(0.60, 0.36, 0.80) if side < 0 else Color(0.28, 0.62, 0.80)
			pool.light_energy = 1.18 if reference_world_mode else 2.8; pool.omni_range = 11.5 if reference_world_mode else 18.0; pool.shadow_enabled = false
			pool.position = Vector3(side * (13.0 if reference_world_mode else 12.5), 4.8, float(lane)); _world.add_child(pool)
			if reference_world_mode: _crystal_lights.append(pool)
	if reference_world_mode:
		ReferenceWorld.build(_world)
		ChikoriaSurround.build(_world)
	elif not reference_image_mode: Architecture.build(_world)
	_camera = Camera3D.new(); _camera.position = Architecture.CAMERA_AT
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL; _camera.size = Architecture.CAMERA_SIZE; _camera.current = true
	_world.add_child(_camera); _camera.look_at(Architecture.CAMERA_TARGET)
	if reference_world_mode:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE; _camera.fov = ReferenceWorld.CAMERA_FOV
		# A long-lens camera needs a bounded depth range, otherwise adjacent stone
		# bevels at 150m shimmer with the default 0.05m near clip.
		_camera.near = 16.0; _camera.far = 420.0
		_camera.position = ReferenceWorld.CAMERA_AT; _camera.look_at(ReferenceWorld.CAMERA_TARGET)
		environment.environment.ambient_light_color = Color("e1e1ef")
		environment.environment.ambient_light_energy = 0.30
		environment.environment.fog_enabled = false
		environment.environment.background_color = Color("83b6c2")
		environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		environment.environment.glow_intensity = 0.55
		environment.environment.glow_bloom = 0.02
		light.light_energy = 1.35; light.light_color = Color("fff5e7")
		light.light_angular_distance = 0.0
		light.directional_shadow_max_distance = 240.0
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		light.directional_shadow_split_1 = 0.6
		light.directional_shadow_split_2 = 0.78
		light.directional_shadow_split_3 = 0.9
		light.shadow_blur = 1.0
		light.shadow_bias = 0.12
		light.shadow_normal_bias = 1.4
		environment.environment.ssao_enabled = true
		environment.environment.ssao_radius = 1.5
		environment.environment.ssao_intensity = 1.8
		environment.environment.ssao_light_affect = 0.6
	elif reference_image_mode:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE; _camera.keep_aspect = Camera3D.KEEP_HEIGHT
		_camera.fov = REFERENCE_FOV; _camera.position = REFERENCE_CAMERA_AT; _camera.look_at(REFERENCE_CAMERA_TARGET)
		_reference_guide = Line2D.new(); _reference_guide.name = "ImageFloorGuide"; _reference_guide.width = 1.5
		_reference_guide.default_color = Color(0.3, 0.8, 1, 0.45); _reference_guide.visible = false
		_viewport.add_child(_reference_guide)


func _ground(at: Vector2) -> Dictionary:
	if reference_world_mode: return ReferenceNavigation.ground_height(at)
	return ReferenceFloor.ground_height(at) if reference_image_mode else Navigation.ground_height(at)


func _sweep(from: Vector3, to: Vector3) -> Dictionary:
	if reference_world_mode: return ReferenceNavigation.sweep(from, to)
	return ReferenceFloor.sweep(from, to) if reference_image_mode else Navigation.sweep(from, to)


func _contact_shadow() -> MeshInstance3D:
	var gradient := Gradient.new(); gradient.offsets = PackedFloat32Array([0, 0.35, 1])
	gradient.colors = PackedColorArray([Color(1,1,1,1), Color(1,1,1,0.65), Color(1,1,1,0)])
	var texture := GradientTexture2D.new(); texture.gradient = gradient; texture.width = 64; texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL; texture.fill_from = Vector2(0.5,0.5); texture.fill_to = Vector2(1,0.5)
	var mesh := PlaneMesh.new(); mesh.size = Vector2(1.12, 0.9)
	var shadow := MeshInstance3D.new(); shadow.name = "FootContactShadow"; shadow.mesh = mesh
	var material := StandardMaterial3D.new(); material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; material.albedo_color = Color(0,0,0,0.48)
	material.albedo_texture = texture; material.render_priority = -1; shadow.material_override = material
	shadow.position.y = 0.012; shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return shadow


func _label(text: String, pixels: int = 13, color: Color = Color.WHITE) -> Label:
	var label := Label.new(); label.text = text; label.add_theme_font_size_override("font_size", pixels)
	label.add_theme_color_override("font_color", color); label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new(); button.text = text; button.add_theme_font_size_override("font_size", 12)
	var normal := StyleBoxFlat.new(); normal.bg_color = Color("17283f"); normal.set_corner_radius_all(7)
	normal.content_margin_left = 12; normal.content_margin_right = 12; normal.content_margin_top = 8; normal.content_margin_bottom = 8
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat; hover.bg_color = Color("28405a")
	button.add_theme_stylebox_override("hover", hover); button.add_theme_stylebox_override("pressed", hover)
	button.pressed.connect(callback)
	UISkin.button(button)
	return button


func _fit_header_icon(button: Button) -> void:
	# Text-button padding must not enlarge the compact header's icon controls.
	# Copy only these local skins; keep lobby/card buttons and focus styling intact.
	for state in ["normal", "hover", "pressed", "disabled"]:
		var skin := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		skin.content_margin_left = 2; skin.content_margin_right = 2
		skin.content_margin_top = 0; skin.content_margin_bottom = 0
		button.add_theme_stylebox_override(state, skin)


func _build_ui() -> void:
	_targeting = Targeting.new(); _targeting.name="CardTargeting";_targeting.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(_targeting)
	_duel_hud = DuelHUD.new();_duel_hud.name="ChikiseumDuelHUD";_duel_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(_duel_hud)
	_title = _label("CHIKISEUM", 24, GOLD); _title.add_theme_font_override("font", BOLD); add_child(_title)
	_clock = _label("PRACTICE PRESENTATION", 12, Color("c4d2e6")); _clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; add_child(_clock)
	_note = _label("", 11, Color("9bacc6")); _note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(_note)
	var exit := _button("×", _request_exit); exit.name = "Exit";exit.tooltip_text="Leave battle";exit.add_theme_font_size_override("font_size",22);add_child(exit)
	_fit_header_icon(exit)
	_view_button = _button("◈", func():
		_camera_close = not _camera_close
		if reference_image_mode:
			_reference_guide.visible = _camera_close; _view_button.text = "HIDE GUIDE" if _camera_close else "GUIDE"
		else: _view_button.tooltip_text = "Wider player view · click to focus" if _camera_close else "Focused player view · click to widen"
		_layout())
	_view_button.name = "ViewMode"; add_child(_view_button)
	_view_button.tooltip_text="Focused player view · click to widen";_view_button.add_theme_font_size_override("font_size",19)
	if not reference_image_mode: _fit_header_icon(_view_button)
	if reference_image_mode:
		_view_button.text = "GUIDE"; _view_button.tooltip_text = "Show the image-calibrated floor boundary without moving the camera."
	_move_surface = MoveSurface.new(); _move_surface.name = "MovementSurface"; add_child(_move_surface)
	_reset = _button("LOBBY", _return_lobby); _reset.name = "Reset";add_child(_reset)
	_lobby = PanelContainer.new(); _lobby.name = "PracticeLobby"
	var style := StyleBoxFlat.new(); style.bg_color = Color(0.03, 0.075, 0.14, 0.94); style.set_corner_radius_all(13)
	style.content_margin_left = 24; style.content_margin_right = 24; style.content_margin_top = 20; style.content_margin_bottom = 20
	_lobby.add_theme_stylebox_override("panel", style); add_child(_lobby)
	_lobby.add_theme_stylebox_override("panel",UISkin.panel(UISkin.GOLD,true))
	var scroll := ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; _lobby.add_child(scroll)
	var stack := VBoxContainer.new(); stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL; stack.add_theme_constant_override("separation", 13); scroll.add_child(stack)
	stack.add_child(_label("ENTER THE ARENA", 21, GOLD))
	var introduction := _label("One Chikimon each. Move freely. Cast instantly. No turns.", 12, Color("c4d2e6")); introduction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; stack.add_child(introduction)
	var pickers := HBoxContainer.new(); pickers.add_theme_constant_override("separation", 16); stack.add_child(pickers)
	_practice_controls.append(pickers)
	var available: Array = Econ.CARD_NAMES.keys(); available.sort()
	for side in SIDES:
		var column := VBoxContainer.new(); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; pickers.add_child(column)
		column.add_child(_label("YOUR CHIKIMON" if side=="A" else "TRAINING PARTNER", 11, UISkin.VIOLET if side == "A" else UISkin.CYAN))
		var picker := OptionButton.new(); picker.add_theme_font_size_override("font_size", 12); column.add_child(picker)
		for sp in available:
			if ResourceLoader.exists(WorldRig.SHEET_DIR + String(sp) + ".webp"):
				picker.add_item(Econ.disp(String(sp)))
				picker.set_item_metadata(picker.item_count - 1, sp)
		_species[side] = picker
		for i in range(picker.item_count):
			if picker.get_item_metadata(i) == ("galador" if side == "A" else "dragonos"): picker.select(i)
	var session_row := HBoxContainer.new(); session_row.add_theme_constant_override("separation", 9); stack.add_child(session_row)
	_practice_controls.append(session_row)
	_handle = LineEdit.new(); _handle.placeholder_text = "Your practice handle"; _handle.text = "Human trainer"; _handle.max_length = 24
	_handle.add_theme_font_size_override("font_size", 12); _handle.size_flags_horizontal = Control.SIZE_EXPAND_FILL; session_row.add_child(_handle)
	_level = SpinBox.new(); _level.min_value = 1; _level.max_value = 30; _level.value = 20; _level.prefix = "L"; _level.add_theme_font_size_override("font_size", 12); session_row.add_child(_level)
	_server = LineEdit.new(); _server.text = "http://127.0.0.1:8798" if reference_world_mode else "http://127.0.0.1:8795"; _server.placeholder_text = "Explicit loopback practice server"
	_server.add_theme_font_size_override("font_size", 12); stack.add_child(_server)
	_practice_controls.append(_server)
	_stake = SpinBox.new(); _stake.min_value = 0; _stake.max_value = 1000; _stake.step = 1; _stake.value = 0
	_stake.prefix = "TEST CREDITS"; _stake.add_theme_font_size_override("font_size", 12); stack.add_child(_stake)
	_practice_controls.append(_stake)
	var practice_join := _button("JOIN LOCAL PVP PRACTICE", _connect_practice); stack.add_child(practice_join); _practice_controls.append(practice_join)
	_live_fighter_label = _label("Waiting for verified fighter admission…", 12, GOLD)
	_live_fighter_label.name = "VerifiedFighter"; _live_fighter_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; stack.add_child(_live_fighter_label)
	_live_fighter_label.visible = online_entry_mode
	_live_retry = _button("Return to sign in again", _exit_pressed); _live_retry.name = "ReconnectWalletSession"
	stack.add_child(_live_retry); _live_retry.hide()
	_admission_retry = _button("Refresh verified fighter", func():
		if _live_authenticated and _transport != null: _transport.call("refresh_admission"))
	_admission_retry.name = "RefreshVerifiedFighter"; stack.add_child(_admission_retry); _admission_retry.hide()
	_peers = OptionButton.new(); _peers.add_theme_font_size_override("font_size", 12); _peers.add_item("Real human practice sessions appear after connecting")
	_peers.item_selected.connect(func(index: int):
		var id: Variant = _peers.get_item_metadata(index)
		if id is String: _invite.text = id)
	stack.add_child(_peers)
	_invite = LineEdit.new(); _invite.placeholder_text = "Trainer handle / invite ID (adapter required)"; _invite.add_theme_font_size_override("font_size", 12); stack.add_child(_invite)
	var actions := HBoxContainer.new(); actions.add_theme_constant_override("separation", 9); stack.add_child(actions)
	var challenge_button := _button("INVITE / CHALLENGE", func(): _lobby_request("challenge")); challenge_button.name = "ChallengePlayer"; actions.add_child(challenge_button); _live_actions.append(challenge_button)
	var find_button := _button("FIND MATCH", func(): _lobby_request("queue")); find_button.name = "FindPlayer"; actions.add_child(find_button); _live_actions.append(find_button)
	var incoming := HBoxContainer.new(); incoming.add_theme_constant_override("separation", 9); stack.add_child(incoming)
	_challenges = OptionButton.new(); _challenges.add_theme_font_size_override("font_size", 12); _challenges.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_challenges.add_item("No incoming human challenges"); incoming.add_child(_challenges)
	var accept_button := _button("ACCEPT", func():
		var id: Variant = _challenges.get_item_metadata(_challenges.selected)
		if id is String: request.emit({"op": "accept", "mode": _intent_mode(), "challenge_id": id}))
	accept_button.name = "AcceptChallenge"; incoming.add_child(accept_button); _live_actions.append(accept_button)
	var free_play := _button("FREE PLAY · TRY CREATURES & ABILITIES", start_local_rehearsal); stack.add_child(free_play); _practice_controls.append(free_play)
	_lobby_note = _label("No transport attached. Rehearsal is offline and changes no HP, balance or ownership.", 11, Color("9bacc6"))
	_lobby_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; stack.add_child(_lobby_note)
	if online_entry_mode:
		_lobby.name = "OnlineLobby"
		for control in _practice_controls: control.hide()
		for action in _live_actions: (action as Button).disabled = true
		_peers.clear(); _peers.add_item("Verified players appear after admission")
		_invite.placeholder_text = "Select an available verified player"
		_lobby_note.text = "Online admission pending. No rehearsal or AI match is substituted."
	if reference_image_mode:
		for index in range(3, stack.get_child_count() - 2): (stack.get_child(index) as Control).hide()
		_lobby_note.text = "Reference-image art rehearsal only. No authenticated battle, AI, damage, betting or rewards."
	for side in SIDES:
		var deck := Control.new(); deck.name = "Deck" + side; add_child(deck)
		var accent:=UISkin.VIOLET if side=="A" else UISkin.CYAN
		deck.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var energy := _label("", 12, GOLD); deck.add_child(energy)
		var meter:=EnergyMeter.new();meter.name="EnergyBudget";deck.add_child(meter)
		var heading:=_label("YOUR ABILITIES",11,UISkin.MUTED);deck.add_child(heading)
		var action_name:=_label("Choose a card",16,UISkin.LIGHT);action_name.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;deck.add_child(action_name)
		var hint:=_label("Range and cover appear when selected",11,UISkin.MUTED);hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;deck.add_child(hint)
		var reserve:=_label("",10,UISkin.MUTED);deck.add_child(reserve)
		var movement:=_label("",11,UISkin.MUTED);deck.add_child(movement)
		var icon := TextureRect.new(); icon.texture = load("res://mat/essence.png") as Texture2D
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE; deck.add_child(icon)
		var cards: Array[Button] = []
		var cooldown_labels: Array[Label] = []
		for i in range(3):
			var index := i
			var card := DeckCard.new();card.pressed.connect(func():_select_card(side,index));card.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND;card.name = "Card%d" % i
			card.clip_contents = false; deck.add_child(card)
			for state in ["normal","hover","pressed","disabled","focus"]:card.add_theme_stylebox_override(state,StyleBoxEmpty.new())
			var image := TextureRect.new(); image.name = "PaintedCard"; image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE; card.add_child(image)
			card.mouse_entered.connect(func(): _card_hover(side,index,true))
			card.mouse_exited.connect(func(): _card_hover(side,index,false))
			card.focus_entered.connect(func(): _card_hover(side,index,true))
			card.focus_exited.connect(func(): _card_hover(side,index,false))
			cards.append(card)
			var cooldown_label:=_label("",9,UISkin.MUTED);cooldown_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;cooldown_label.name="Cooldown%d"%i;deck.add_child(cooldown_label);cooldown_labels.append(cooldown_label)
		var previous := _button("‹", func(): _page(side, -1)); deck.add_child(previous)
		var next := _button("›", func(): _page(side, 1)); deck.add_child(next)
		var commit := _button("COMMIT", func(): commit_side(side)); deck.add_child(commit)
		UISkin.button(commit,true,UISkin.GOLD)
		var count := _label("", 10, Color("aabdd4")); deck.add_child(count)
		var inspect:=_button("⊕",_show_full_card);inspect.name="InspectFullCard";deck.add_child(inspect)
		_decks[side] = {"root": deck, "energy": energy, "icon": icon, "cards": cards, "previous": previous, "next": next, "commit": commit, "count": count,"meter":meter,"heading":heading,"action_name":action_name,"hint":hint,"reserve":reserve,"movement":movement,"inspect":inspect,"cooldowns":cooldown_labels}
		deck.hide()
		var plate := Control.new(); plate.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(plate)
		var name_label := _label("", 10); name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; plate.add_child(name_label)
		var hp := ProgressBar.new(); hp.show_percentage = false; hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var empty := StyleBoxFlat.new(); empty.bg_color = Color("0a1020"); empty.set_corner_radius_all(3)
		var fill := empty.duplicate() as StyleBoxFlat; fill.bg_color = UISkin.VIOLET if side == "A" else UISkin.CYAN
		hp.add_theme_stylebox_override("background", empty); hp.add_theme_stylebox_override("fill", fill); plate.add_child(hp)
		_plates[side] = {"root": plate, "name": name_label, "hp": hp}; plate.hide()
	_inspector=Panel.new();_inspector.name="AbilityInspection";_inspector.add_theme_stylebox_override("panel",StyleBoxEmpty.new());_inspector.mouse_filter=Control.MOUSE_FILTER_IGNORE;_inspector.z_index=12;add_child(_inspector)
	_inspect_title=_label("",12,UISkin.LIGHT);_inspect_title.clip_text=true;_inspector.add_child(_inspect_title)
	_inspect_image=TextureRect.new();_inspect_image.name="FullCardInspection";_inspect_image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_inspect_image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;_inspect_image.mouse_filter=Control.MOUSE_FILTER_IGNORE;_inspector.add_child(_inspect_image)
	_inspect_detail=_label("",10,UISkin.MUTED);_inspect_detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_inspector.add_child(_inspect_detail);_inspector.hide()
	_inspect_title.hide();_inspect_detail.hide()
	_switch_trainer=_button("TRAINER A  ⇄",_switch_practice_side);_switch_trainer.name="TrainingSide";_switch_trainer.tooltip_text="Tab: switch the local training hand";add_child(_switch_trainer)
	_help_button=_button("?",func():_rules.popup_centered(Vector2i(mini(480,int(size.x)-32),mini(360,int(size.y)-40))));_help_button.name="BattleHelp";_help_button.tooltip_text="How to duel";add_child(_help_button)
	_rules=AcceptDialog.new();_rules.title="The Chikiseum duel";_rules.dialog_text="MOVE. CAST. KEEP FIGHTING.\n\nWASD / touch pad: move continuously.\nClick a card or press 1 / 2 / 3: cast immediately.\nSpace: repeat your selected ability. Q / E: change ability page.\nHover: inspect range and cover. ⊕: read the full card.\nThere are no turns and no waiting for your opponent.\n\nEnergy regenerates over time. Each ability has its own cooldown. Hold the center crest for faster energy recovery. Move behind crystal pillars to break line of sight.\n\nThe server decides hits, health and results. Training previews artwork without damage or rewards. Connected practice uses test credits only. No SOL wagering.";add_child(_rules)
	_leave_dialog=ConfirmationDialog.new();_leave_dialog.title="Leave the Chikiseum?";_leave_dialog.dialog_text="Leaving an active duel counts as a forfeit. Wait for the server to confirm cancellation.";_leave_dialog.ok_button_text="Leave duel";_leave_dialog.confirmed.connect(_exit_pressed);add_child(_leave_dialog)
	_card_dialog=AcceptDialog.new();_card_dialog.title="Ability card";add_child(_card_dialog)
	_card_dialog_image=TextureRect.new();_card_dialog_image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_card_dialog_image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;_card_dialog.add_child(_card_dialog_image)
	_feedback=_label("",12,UISkin.LIGHT);_feedback.name="BattleFeedback";_feedback.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_feedback.add_theme_stylebox_override("normal",UISkin.panel());_feedback.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_feedback);_feedback.hide()
	_title.hide();_clock.hide();_note.hide()


func _active_side() -> String: return _practice_view_side if _local_fixture else _you

func _switch_practice_side() -> void:
	if not _local_fixture:return
	_practice_view_side="B" if _practice_view_side=="A" else "A"
	_hover_side="";_hover_index=-1;_inspector.hide();_targeting.clear_preview();_refresh_decks();_layout()
	_toast("Training hand: "+String(_players[_practice_view_side].display_name))

func _request_exit() -> void:
	if not _local_fixture and not _match_id.is_empty() and _snapshot.get("status")=="active":
		_leave_dialog.popup_centered(Vector2i(mini(450,int(size.x)-28),180))
	else:_exit_pressed()

func _toast(message: String) -> void:
	if _feedback==null:return
	_feedback.text=message;_feedback_left=3.5;_feedback.show()

func _fighter_trait_label(fighter: Dictionary) -> String:
	var title := "%s · Battle Lv. %d" % [String(fighter.get("display_name", "Chikimon")), int(fighter.get("level", 1))]
	var species_trait := {}
	if fighter.get("trait") is Dictionary: species_trait = fighter.get("trait")
	if species_trait.is_empty(): return title + "\nArena progression is separate from Chikoria."
	var effect := String(species_trait.get("signature_effect", ""))
	var boon := "+¼ energy" if effect == "surge" else "heal up to 4" if effect == "recover" else "drain ¼ energy" if effect == "sunder" else "+7% hit" if effect == "fury" else ""
	return title + "\n%s · %s → %s" % [String(species_trait.get("name", "Trait")), String(species_trait.get("signature_arch", "card")).capitalize(), boon]

func _signature_cue(event: Dictionary) -> String:
	var title := String(event.get("signature_name", "Trait"))
	var amount := float(event.get("signature_amount", 0))
	match String(event.get("signature_effect", "")):
		"surge": return "%s · +%.2f energy" % [title, amount]
		"recover": return "%s · +%.1f HP" % [title, amount]
		"sunder": return "%s · −%.2f foe energy" % [title, amount]
		"fury": return "%s · empowered hit" % title
	return title

func _favored_card_detail(fighter: Dictionary, card: Dictionary) -> String:
	if not fighter.get("trait") is Dictionary: return ""
	var species_trait := fighter.get("trait") as Dictionary
	var profile := Visual.profile(String(fighter.get("species", "")), int(card.get("slot", -1)))
	if String(profile.get("arch", "")) != String(species_trait.get("signature_arch", "")): return ""
	var effect := String(species_trait.get("signature_effect", ""))
	var result := "+¼ energy" if effect == "surge" else "heal up to 4 HP" if effect == "recover" else "drain ¼ enemy energy" if effect == "sunder" else "+7% hit damage" if effect == "fury" else ""
	var condition := "on cast" if String(profile.get("arch", "")) in ["guard", "bulwark", "charge", "rally"] else "on hit"
	return "%s · %s %s" % [String(species_trait.get("name", "Trait")), result, condition]

func _show_full_card() -> void:
	var side:=_active_side();var card:=_selected_card(side)
	if card.is_empty():_toast("Select a card first");return
	_card_dialog.title=String(card.name)
	_card_dialog_image.texture=CardPresentation.texture(String(_players[side].species),int(card.slot))
	_card_dialog.dialog_text = _favored_card_detail(_players[side] as Dictionary, card)
	var height:=minf(530,size.y-120);var width:=minf(size.x-36,height*0.72+32)
	_card_dialog_image.custom_minimum_size=Vector2(width-32,height-(80 if not _card_dialog.dialog_text.is_empty() else 50))
	_card_dialog.popup_centered(Vector2i(int(width),int(height)))

func _card_hover(side: String, index: int, hovered: bool) -> void:
	if _players.is_empty() or side!=_active_side():return
	if hovered:_hover_side=side;_hover_index=index
	elif _hover_side==side and _hover_index==index:_hover_side="";_hover_index=-1
	for i in 3:_pose_card(side,i,true)
	_order_deck_hit_targets.call_deferred(side)
	_update_tactical_ui()

func _order_deck_hit_targets(side: String) -> void:
	if not _decks.has(side): return
	var deck:Dictionary=_decks[side]
	# CanvasItem.z_index changes paint order, not Control's mouse picking order.
	# Match both orders so an enlarged card receives clicks in its overlapped area.
	for card in deck.cards: deck.root.move_child(card,-1)
	if _hover_side==side and _hover_index>=0:
		deck.root.move_child(deck.cards[_hover_index],-1)

func _pose_card(side: String,index: int,animate: bool=false) -> void:
	var button:Button=_decks[side].cards[index]
	if not button.has_meta("resting_position"):return
	var hovered:=_hover_side==side and _hover_index==index
	var lift:=8.0 if size.x<760 or size.y<500 else 14.0
	var at:Vector2=button.get_meta("resting_position")
	if hovered:at.y-=lift
	var angle:=0.0 if hovered else float(button.get_meta("resting_rotation",0.0))
	var zoom:=1.085 if hovered else 1.0
	var goal:=[at,angle,zoom]
	if button.get_meta("pose_goal",[])==goal:return
	button.set_meta("pose_goal",goal);button.z_index=10 if hovered else index
	if _hover_tweens.has(button) and _hover_tweens[button].is_valid():_hover_tweens[button].kill()
	if animate:
		var tween:=create_tween().set_parallel();_hover_tweens[button]=tween
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(button,"position",at,.18);tween.tween_property(button,"scale",Vector2.ONE*zoom,.18);tween.tween_property(button,"rotation",angle,.18)
	else:button.position=at;button.scale=Vector2.ONE*zoom;button.rotation=angle

func _inspection_visible(show_card: bool) -> void:
	if show_card==bool(_inspector.get_meta("revealed",false)) and _inspector.visible==show_card:return
	_inspector.set_meta("revealed",show_card)
	if _inspection_tween!=null and _inspection_tween.is_valid():_inspection_tween.kill()
	if not show_card:_inspector.hide();return
	_inspector.show();_inspector.modulate.a=0;_inspector.scale=Vector2.ONE*.96
	_inspection_tween=create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_inspection_tween.tween_property(_inspector,"modulate:a",1.0,.16);_inspection_tween.tween_property(_inspector,"scale",Vector2.ONE,.16)

func _selected_card(side: String) -> Dictionary:
	if _hover_side==side and _hover_index>=0:
		var index:=int(_pages[side])*3+_hover_index
		if index<(_hands[side] as Array).size():return _hands[side][index]
	for card in _hands[side]:
		if (_selected[side] as Array).has(int(card.slot)):return card
	return {}

func _update_tactical_ui() -> void:
	if _duel_hud==null:return
	_duel_hud.configure(_players,_active_side(),_snapshot,_local_fixture,_committed or _commit_pending)
	if _players.is_empty():_targeting.clear_preview();_inspector.hide();return
	if _continuous():_update_continuous_controls()
	var side:=_active_side();var deck:Dictionary=_decks[side];var card:=_selected_card(side)
	var moving:Variant=_players[side].get("movement_remaining")
	var at:Vector3=(_rigs[side] as Node3D).position
	var on_crest:bool=_players[side].get("on_emblem",Vector2(at.x,at.z).length()<=2.6)
	deck.movement.text=("CREST · ENERGY BOOST" if on_crest else "MOVE FREELY · CONTROL THE CREST") if _continuous() else ("MOVE %.1fm  ·  "%float(moving) if moving!=null else "")+("CREST +1" if on_crest else "CENTER CREST +1")
	deck.movement.add_theme_color_override("font_color",UISkin.GOLD if on_crest else UISkin.MUTED)
	if card.is_empty():
		_targeting.clear_preview();_inspector.hide();_target_state={}
		deck.action_name.text="Tap to cast" if _continuous() else "Choose your move";deck.hint.text="1 · 2 · 3 to attack" if _continuous() else "Select a card\nto see range & cover";return
	var profile:=Visual.profile(String(_players[side].species),int(card.slot))
	var other:="B" if side=="A" else "A"
	_target_state=_targeting.show_preview(_camera,Rect2(_stage.position,_stage.size),Vector2(_viewport.size),at,(_rigs[other] as Node3D).position,card,profile)
	deck.action_name.text=String(profile.card_name)
	var status:=String(_target_state.get("status","unknown"))
	var hint:="SELF · defensive ability" if status=="self" else "CLEAR SHOT · %.1fm"%float(_target_state.get("distance_m",0)) if status=="ready" else "BLOCKED · reposition" if status=="blocked" or _target_state.get("path_blocked",false) else "OUT OF RANGE · close in" if status=="out_of_range" else "Choose a target"
	deck.hint.text=hint if size.x<760 or size.y<500 else hint+"\nRange preview · server resolves"
	deck.hint.add_theme_color_override("font_color",UISkin.CYAN if status in ["ready","self"] else UISkin.GOLD)
	var inspect:=not _hover_side.is_empty()
	_inspection_visible(inspect and not _lobby.visible)
	if inspect:
		_inspect_image.texture=CardPresentation.texture(String(_players[side].species),int(card.slot));_inspect_title.text=String(profile.card_name)
		_inspect_detail.text="%d energy  ·  %s"%[int(card.cost),"Self" if status=="self" else "%.1fm range"%float(_target_state.get("range_m",0))]
		var favored_detail := _favored_card_detail(_players[side] as Dictionary, card)
		if not favored_detail.is_empty(): _inspect_detail.text += "\n" + favored_detail

func _update_continuous_controls() -> void:
	var side:=_active_side();var deck:Dictionary=_decks[side];var hand:Array=_hands[side]
	var energy:=float(_players[side].energy)
	var chosen_slot: int = int(_selected[side][0]) if not (_selected[side] as Array).is_empty() else -1
	var cost:=0
	for card in hand:
		if int(card.slot)==chosen_slot:cost=int(card.cost)
	deck.energy.text="∞" if _local_fixture else "%.1f / 6"%energy
	var inspected:=_selected_card(side)
	var preview_cost:=int(inspected.get("cost",0)) if not _hover_side.is_empty() else 0
	deck.meter.configure(6.0 if _local_fixture else energy,preview_cost,6,UISkin.VIOLET if side=="A" else UISkin.CYAN)
	var regen:=float((_snapshot.get("realtime",{}) as Dictionary).get("energy_regen_per_second",1.0))
	if _players[side].get("on_emblem",false):regen+=1.0
	deck.reserve.text="FREE PLAY · ORIGINAL ART" if _local_fixture else "COST %d · +%.1f ENERGY / s"%[cost,regen]
	var cooling:=_cooldown_left(chosen_slot)
	var ready_wait:bool=_snapshot.get("status")=="ready" and _players[side].get("ready",false)
	deck.commit.text="SENDING…" if _commit_pending else "WAITING…" if ready_wait else "I'M READY" if _snapshot.get("status")=="ready" else "DUEL COMPLETE" if _snapshot.get("status") in TERMINAL else "CAST · %.1fs"%cooling if cooling>0.05 else "CAST AGAIN" if chosen_slot>=0 else "TAP A CARD"
	deck.commit.disabled=_cancel_pending or _commit_pending or ready_wait or (_snapshot.get("status")!="ready" and (chosen_slot<0 or cooling>0.05 or cost>energy or _snapshot.get("status")!="active"))
	for index in 3:
		var hand_index:=int(_pages[side])*3+index;var label:Label=deck.cooldowns[index];var button:Button=deck.cards[index]
		label.visible=false
		if hand_index>=hand.size():continue
		var card:Dictionary=hand[hand_index];var left:=_cooldown_left(int(card.slot))
		label.text="%.1fs"%left if left>0.05 else "ENERGY" if float(card.cost)>energy else "READY"
		label.add_theme_color_override("font_color",UISkin.GOLD if left>0.05 else UISkin.MUTED if float(card.cost)>energy else UISkin.CYAN)
		button.disabled=_cancel_pending or _commit_pending or left>0.05 or float(card.cost)>energy or _snapshot.get("status")!="active"
		var fraction:=_card_cooldown_fraction(card,side)
		var tint:=maxf(.68*fraction,.30 if float(card.cost)>energy else 0.0)
		button.set_meta("cooldown_fraction",fraction);button.set_meta("tint_strength",tint)
		(button.get_node("PaintedCard") as TextureRect).self_modulate=Color(1-tint,1-tint,1-tint,1)
	deck.commit.visible=_snapshot.get("status")=="ready" and not _local_fixture

func _card_cooldown_fraction(card: Dictionary,side: String) -> float:
	if _local_fixture:return clampf((float(_local_cast_until[side])-float(Time.get_ticks_msec())/1000.0)/.55,0,1)
	var you:Dictionary=_snapshot.get("you",{});var cds:Dictionary=you.get("cooldowns",{})
	var duration:=float(card.get("cooldown_seconds",0.0))
	if duration<=0:
		var profile:=Visual.profile(String(_players[side].species),int(card.slot))
		duration=float(LIVE_COOLDOWN_SECONDS.get(profile.get("arch","strike"),.65))
	var card_fraction:=clampf((float(cds.get(str(card.slot),0))-_server_now())/duration,0,1)
	var global_fraction:=clampf((float(you.get("global_cooldown_until",0))-_server_now())/.18,0,1)
	return maxf(card_fraction,global_fraction)

func _animate_cooldown_tints() -> void:
	if _players.is_empty() or not _continuous():return
	var side:=_active_side();var hand:Array=_hands[side];var energy:=float(_players[side].energy)
	for i in 3:
		var index:=int(_pages[side])*3+i
		if index>=hand.size():continue
		var card:Dictionary=hand[index];var button:Button=_decks[side].cards[i]
		var fraction:=_card_cooldown_fraction(card,side)
		var tint:=maxf(.68*fraction,.30 if float(card.cost)>energy else 0.0)
		button.set_meta("cooldown_fraction",fraction);button.set_meta("tint_strength",tint)
		(button.get_node("PaintedCard") as TextureRect).self_modulate=Color(1-tint,1-tint,1-tint,1)


func _lobby_request(op: String) -> void:
	if _cancel_pending: return
	if online_entry_mode:
		if not _live_authenticated: return
		request.emit({"op": op, "mode": "live", "target": _invite.text.strip_edges()})
		_lobby_note.text = "Contacting the verified player service…"
	else:
		request.emit({"op": op, "mode": "practice", "target": _invite.text.strip_edges(), "stake": int(_stake.value), "currency": "TEST_CREDITS"})
		_lobby_note.text = "Practice " + op + " intent emitted. No request or match is invented by this presentation."

func _intent_mode() -> String: return "live" if online_entry_mode else "practice"

func attach_live_client(client: Node, session: Dictionary) -> bool:
	if not online_entry_mode or not is_node_ready() or _transport != null or client == null or not client.has_method("diagnostics"): return false
	var state := client.call("diagnostics") as Dictionary
	if state.get("authenticated") != true or state.get("inventory_verified") != true or state.get("currency") != "NONE" or state.get("development_only") != false or session.get("mode") != "live": return false
	_live_session = session.duplicate(true); _live_authenticated = true; _transport = client
	_bind_transport()
	_transport.connect("admission_refreshing", func(pending: bool):
		for action in _live_actions: (action as Button).disabled = pending
		if pending: _lobby_note.text = "Refreshing server-earned Battle Level and verified fighter before the next duel…"; _admission_retry.hide())
	_transport.connect("admitted", func(refreshed: Dictionary):
		if not _live_authenticated or not _match_id.is_empty() or refreshed.get("trainer_id") != _live_session.get("trainer_id") or refreshed.get("fighter", {}).get("asset_id") != _live_session.fighter.asset_id: return
		_live_session = refreshed.duplicate(true)
		_live_fighter_label.text = _fighter_trait_label(refreshed.fighter)
		_admission_retry.hide(); _lobby_note.text = "Verified fighter refreshed. Challenge a player or find a match.")
	_transport.connect("authentication_lost", func():
		_live_authenticated = false; _auth_connection_lost = true; _cancel_pending = false; _commit_pending = false
		_clear_match() # Retire an unsafe DISPLAY, not the server duel or its result.
		for action in _live_actions: (action as Button).disabled = true
		_admission_retry.hide()
		_live_retry.show(); _live_retry.disabled = false; _lobby.show()
		_lobby_note.text = "Wallet session expired. Commands stopped; the previous result is unconfirmed. Return, sign in again, and re-enter with fresh verified admission."
		_refresh_decks())
	for action in _live_actions: (action as Button).disabled = false
	var fighter := session.get("fighter", {}) as Dictionary
	_live_fighter_label.text = _fighter_trait_label(fighter)
	_lobby_note.text = "Verified owned Chikimon admitted. Challenge a player or find a match. No wagering."
	_rules.dialog_text = _rules.dialog_text.replace("Connected practice uses test credits only. No SOL wagering.", "Online duels use verified owned Chikimons. No wagering or currency payouts.")
	_live_art_bound = Sprites.reborn_sidecar_route().contains("/" + String(session.art_version) + "/")
	# Public art is allowed only after actual live admission, and only from this exported page.
	if OS.has_feature("web"):
		var base: Variant = JavaScriptBridge.eval("new URL('.', window.location.href).href", true)
		if base is String and not String(base).is_empty() and _live_art_bound:
			_stream.configure(String(base), true, size.x < 760 or size.y < 500)
	if not _live_art_bound: _lobby_note.text = "Verified admission accepted. This build's exact ability-art release is unavailable; no substitute effects will be displayed."
	return true


func _connect_practice() -> void:
	if online_entry_mode: return
	if reference_image_mode:
		_lobby_note.text = "Image rehearsal cannot use the old voxel-physics server. No invisible cover or substitute match is invented."
		return
	if _cancel_pending: return
	if not _match_id.is_empty():
		_lobby_note.text = "Reset/cancel the current match before connecting a practice session."; return
	if _transport == null:
		_transport = (load("res://ChikiseumPracticeClient.gd") as Script).new()
		add_child(_transport)
		_bind_transport()
	if not _transport.call("configure", _server.text.strip_edges(), reference_world_mode):
		_lobby_note.text = "Use a loopback-only development URL; an existing session cannot be silently replaced."; return
	var picker := _species.A as OptionButton
	if not _transport.call("start_session", _handle.text, String(picker.get_item_metadata(picker.selected)), int(_level.value)):
		_lobby_note.text = "Choose a valid handle, fixture species and level1–30."; return
	_lobby_note.text = "Connecting explicitly to local practice. This grants only unverified development fixtures and TEST CREDITS."


func _bind_transport() -> void:
	request.connect(func(intent: Dictionary):
		var sent:bool=_transport.call("handle_intent", intent)
		if not sent and intent.get("op") in ["cast","ready","commit"]:
			_commit_pending=false;_ready_pending=false;_toast("Action could not be sent · check the connection");_refresh_decks())
	_transport.connect("snapshot_received", apply_snapshot)
	_transport.connect("lobby_received", _practice_lobby)
	_transport.connect("notice", func(text: String): _lobby_note.text = text)
	_transport.connect("command_failed", func(op: String, text: String):
		_lobby_note.text = text
		_toast(text)
		if online_entry_mode and op == "session" and _live_authenticated:
			for action in _live_actions: (action as Button).disabled = true
			_admission_retry.show()
		if op in ["commit","ready","cast"]:_commit_pending=false;_ready_pending=false;_refresh_decks()
		if op == "cancel": _reset.text = "RETRY CANCEL"; _reset.disabled = false; _note.text = "Cancellation not confirmed. Current server match is retained; retry cancellation.")
	_transport.connect("cancelled", _practice_cancelled)
	if _transport.has_signal("session_started"):
		_transport.connect("session_started", func(session: Dictionary):
			_lobby_note.text = "Authenticated LOCAL practice human " + String(session.trainer_id) + " · fixture inventory only · no real SOL")
	if _transport.has_signal("cast_acknowledged"):
		_transport.connect("cast_acknowledged",func(_slot:int,_request_id:String,_confirmed:Dictionary):_commit_pending=false;_refresh_decks())


func _practice_lobby(lobby: Dictionary) -> void:
	_peers.clear()
	for raw in lobby.get("trainers", []) as Array:
		var trainer := raw as Dictionary; var index := _peers.item_count
		var peer_trait := {}
		if trainer.get("fighter") is Dictionary and (trainer.fighter as Dictionary).get("trait") is Dictionary:
			peer_trait = (trainer.fighter as Dictionary).get("trait")
		var trait_name := " · " + String(peer_trait.get("name", "")) if not peer_trait.is_empty() else ""
		_peers.add_item(String(trainer.get("handle", "Human")) + trait_name + (" · compatible" if trainer.get("compatible") == true else " · outside limits"))
		_peers.set_item_metadata(index, String(trainer.get("trainer_id", ""))); _peers.set_item_disabled(index, trainer.get("compatible") != true)
	if _peers.item_count == 0: _peers.add_item("Waiting for another real human · no AI fill")
	_challenges.clear()
	for raw in lobby.get("challenges", []) as Array:
		var challenge := raw as Dictionary
		_challenges.add_item("Human invite " + String(challenge.get("from", ""))); _challenges.set_item_metadata(_challenges.item_count - 1, String(challenge.get("id", "")))
	if _challenges.item_count == 0: _challenges.add_item("No incoming human challenges")


func _return_lobby() -> void:
	if online_entry_mode and not _live_authenticated:
		_clear_match(); _lobby.show()
		_lobby_note.text = "Disconnected. The previous server result is unconfirmed; no cancellation or reward was fabricated."
		return
	var context := {"op": "cancel", "mode": _intent_mode(), "match_id": _match_id, "revision": _revision}
	if _transport != null and (not _match_id.is_empty() or (online_entry_mode and _live_authenticated)) and not _local_fixture:
		_cancel_pending = true; _reset.text = "CANCELLING"; _reset.disabled = true
		_note.text = "Waiting for server cancellation. Leaving an active match is a forfeit; no new match until acknowledgement."
		_refresh_decks(); request.emit(context); return
	_clear_match()
	_lobby.show(); _title.text = "CHIKISEUM"; _clock.text = "PRACTICE PRESENTATION"
	request.emit(context)
	_layout()


func _exit_pressed() -> void:
	_close_after_cancel = true; _return_lobby()
	if not _cancel_pending: close_requested.emit(); _close_after_cancel = false


func _practice_cancelled() -> void:
	_cancel_pending = false; _clear_match(); _lobby.show()
	_title.text = "CHIKISEUM"; _clock.text = "CANCELLATION CONFIRMED" if online_entry_mode else "CANCELLATION CONFIRMED · TEST ONLY"
	_reset.text = "LOBBY / RESET"; _reset.disabled = false; _layout()
	if _close_after_cancel: _close_after_cancel = false; close_requested.emit()


func _clear_match() -> void:
	for tween in _tweens:
		if tween.is_valid(): tween.kill()
	_tweens.clear()
	for rig in _rigs.values(): rig.queue_free()
	_rigs.clear(); _players.clear(); _events.clear(); _seen.clear(); _states.clear()
	for fx in _effects:
		if is_instance_valid(fx.node): fx.node.queue_free()
	_effects.clear(); _revision = -1; _max_seq = 0; _match_id = ""; _local_fixture = false
	_movement_targets.clear(); _movement_revision = -1; _move_clock = 0
	_dashing.clear(); _camera_focus = Vector3.ZERO; _camera_match_framed = false
	if _move_surface != null: _move_surface.call("activate", false)
	_event_delay = 0; _snapshot = {}; _committed = false; _you = "A"
	_pinned_layers.clear(); _pin_order.clear(); _art_wait = 0
	_finish_pending = false
	_commit_pending=false;_ready_pending=false;_hover_side="";_hover_index=-1
	for side in SIDES: _order_deck_hit_targets(side)
	_local_cast_until={"A":0.0,"B":0.0};_feedback_left=0
	if _targeting!=null:_targeting.clear_preview()
	if _inspector!=null:_inspector.hide()
	_selected = {"A": [], "B": []}; _hands = {"A": [], "B": []}; _pages = {"A": 0, "B": 0}
	for side in SIDES: _decks[side].root.hide(); _plates[side].root.hide()


func _hand_for(sp: String) -> Array:
	var hand: Array = []
	for slot in range(12):
		var p := Visual.profile(sp, slot)
		if not p.is_empty(): hand.append({"slot": slot, "key": p.key, "name": p.card_name, "cost": (Econ.CARDS[slot] as Dictionary).get("cost", 1)})
	return hand


func start_local_rehearsal() -> void:
	if online_entry_mode or not OS.is_debug_build(): return
	if _transport != null and bool((_transport.call("diagnostics") as Dictionary).get("authenticated", false)):
		_lobby_note.text = "Use a separate disconnected window for offline art rehearsal; this window is an authenticated practice human."; return
	_clear_match()
	var players := {}
	for side in SIDES:
		var picker := _species[side] as OptionButton
		var sp := String(picker.get_item_metadata(picker.selected))
		players[side] = {"side": side, "trainer_id": "local-human-" + side, "species": sp,
			"display_name": Econ.disp(sp), "level": 50, "rarity": "fixture",
			"hp": 100, "max_hp": 100, "energy": 10, "statuses": {}}
	var fixture := {"schema": "chikiseum.battle/v1", "mode": "practice", "match_id": "local-two-human-art-rehearsal",
		"revision": 0, "status": "active", "turn": 1, "deadline": 0, "server_time": 0,
		"players": players, "you": {"side": "A", "hand": _hand_for(String(players.A.species)), "committed": false}, "events": []}
	apply_snapshot(fixture)
	_local_fixture = true; _hands.B = _hand_for(String(players.B.species))
	_title.text = "CHIKISEUM · LOCAL 2-HUMAN"
	_note.text = "OFFLINE VISUAL TEST · A and B choose their own cards · HP stays unchanged · no AI, payouts or SOL"
	if reference_image_mode:
		_title.text = "CHIKISEUM · IMAGE REHEARSAL"
		_note.text = "A: WASD · B: arrow keys · choose cards to rehearse their exact sprite actions · OFFLINE / NO SOL"
	_refresh_decks(); _layout()


func apply_snapshot(snapshot: Dictionary) -> bool:
	if online_entry_mode and not _live_authenticated:
		snapshot_rejected.emit("Verified online admission is required."); return false
	if reference_image_mode and snapshot.get("match_id") != "local-two-human-art-rehearsal":
		snapshot_rejected.emit("Reference-image rehearsal is offline only; the old server geometry is not silently substituted.")
		return false
	if reference_world_mode and snapshot.get("match_id")!="local-two-human-art-rehearsal" and snapshot.get("combat_mode")!="realtime":
		snapshot_rejected.emit("This arena uses continuous combat. Connect to the reference-live-v1 server.");return false
	var errors := validate_snapshot(snapshot, reference_world_mode, _intent_mode())
	if not errors.is_empty():
		snapshot_rejected.emit(errors[0]); return false
	snapshot = snapshot.duplicate(true); snapshot.players = _actor_map(snapshot.players).duplicate(true)
	if not _match_id.is_empty() and String(snapshot.match_id) != _match_id:
		snapshot_rejected.emit("Different active match context; explicitly reset before attaching another match."); return false
	if int(snapshot.revision) < _revision:
		snapshot_rejected.emit("Stale snapshot revision."); return false
	if int(snapshot.get("movement_revision", _movement_revision)) < _movement_revision:
		snapshot_rejected.emit("Stale movement snapshot revision."); return false
	if not _players.is_empty():
		for side in SIDES:
			for field in ["trainer_id", "species", "level", "rarity"]:
				if snapshot.players[side][field] != _players[side][field]:
					snapshot_rejected.emit("Frozen fighter identity changed inside the active match."); return false
		if String(snapshot.you.side) != _you:
			snapshot_rejected.emit("Authenticated private side changed inside the active match."); return false
	if online_entry_mode:
		var own := snapshot.players.get(String(snapshot.you.side), {}) as Dictionary
		if own.get("trainer_id") != _live_session.get("trainer_id") or snapshot.you.get("asset_id") != _live_session.fighter.asset_id or own.get("species") != _live_session.fighter.species:
			snapshot_rejected.emit("Battle fighter differs from verified admission."); return false
	var previous_turn := int(_snapshot.get("turn", -1))
	var previous_hand: Array = (_hands.get(_you, []) as Array).duplicate(true)
	_snapshot = snapshot.duplicate(true); _match_id = String(snapshot.match_id); _revision = int(snapshot.revision)
	_movement_revision = int(snapshot.get("movement_revision", _movement_revision))
	if not _local_fixture:
		_title.text = "CHIKISEUM · ONLINE" if online_entry_mode else "CHIKISEUM · PRACTICE"
		_note.text = "Server-confirmed online duel · no wagering" if online_entry_mode else "WASD / drag to reposition · SPACE plays your card · pillars provide cover · center emblem gives +1 energy · TEST ONLY"
	_players = (snapshot.players as Dictionary).duplicate(true)
	_you = String(snapshot.you.side); _committed = bool(snapshot.you.committed)
	if _ready_pending and snapshot.players[_you].get("ready", false) == true:
		_ready_pending = false; _commit_pending = false
	if _committed or previous_turn!=int(snapshot.turn) or snapshot.get("status") in TERMINAL or (snapshot.get("status")=="ready" and snapshot.players[_you].get("ready",false)):_commit_pending=false
	_server_time = float(snapshot.server_time); _received_ticks = Time.get_ticks_msec()
	_hands[_you] = (snapshot.you.hand as Array).duplicate(true)
	for side in SIDES:
		var p := _players[side] as Dictionary
		if not _rigs.has(side):
			var pitch := ReferenceWorld.camera_pitch_degrees() if reference_world_mode else REFERENCE_PITCH if reference_image_mode else Architecture.camera_pitch_degrees()
			var rig := WorldRig.for_species(String(p.species), 1.7, pitch)
			rig.position = ReferenceNavigation.actor_home(side) if reference_world_mode else Architecture.actor_home(side)
			_world.add_child(rig); rig.call("face", Vector2.RIGHT if side == "A" else Vector2.LEFT); _rigs[side] = rig
			# The reconstructed 3D arena already receives each alpha-cut Sprite3D's natural
			# silhouette shadow. Keep the painted-floor contact cue only in image rehearsal.
			if reference_image_mode: rig.add_child(_contact_shadow())
			rig.call("set_distance_driven_walk", true, 72.0)
			for slot in 3:
				var initial_profile:=Visual.profile(String(p.species),slot)
				if not initial_profile.is_empty():_stream.queue_profile(initial_profile,false)
		if p.get("position") is Dictionary:
			var at := Vector3(float(p.position.x), float(p.position.y), float(p.position.z))
			if not _movement_targets.has(side): (_rigs[side] as Node3D).position = at
			_movement_targets[side] = at
		_plates[side].name.text = "%s · L%d" % [String(p.display_name), int(p.level)]
		_plates[side].hp.max_value = float(p.max_hp); _plates[side].hp.value = float(p.hp); _plates[side].root.show()
	for raw in snapshot.get("events", []) as Array:
		var event := raw as Dictionary
		var id := String(event.id); var seq := int(event.seq)
		if _seen.has(id) or seq <= _max_seq: continue
		_seen[id] = true; _max_seq = seq; _events.append(event.duplicate(true))
		if _seen.size() > 256: _seen.erase(_seen.keys()[0])
	_lobby.hide()
	# Movement/state polling must not erase the player's card selection every fraction of a second.
	if not _continuous() and (previous_turn != int(snapshot.turn) or previous_hand != (_hands[_you] as Array) or _committed): _selected[_you] = []
	_refresh_decks(); _layout()
	if reference_world_mode and not _camera_match_framed and _rigs.has(_active_side()):
		var owner_at:Vector3=(_rigs[_active_side()] as Node3D).position
		_camera_focus=_reference_battle_focus(owner_at)
		_camera.position=ReferenceWorld.CAMERA_AT+_camera_focus
		_camera.look_at(ReferenceWorld.CAMERA_TARGET+_camera_focus)
		_camera.fov=_camera_target_size
		_camera_match_framed=true
	return true


func _refresh_decks() -> void:
	for side in SIDES:
		var deck := _decks[side] as Dictionary
		var visible_hand: bool = not _players.is_empty() and side == _active_side()
		deck.root.visible = visible_hand
		if not visible_hand: continue
		var hand := _hands[side] as Array
		var page_count := maxi(1, ceili(float(hand.size()) / 3.0)); _pages[side] = clampi(int(_pages[side]), 0, page_count - 1)
		var cost:=0
		for card in hand:
			if (_selected[side] as Array).has(int(card.slot)):cost+=int(card.cost)
		var energy:=int(_players[side].energy)
		deck.energy.text = "%d / %d"%[energy,maxi(6,energy)]
		deck.meter.configure(energy,cost,maxi(6,energy),UISkin.VIOLET if side=="A" else UISkin.CYAN)
		var regen:=int((_snapshot.get("tempo",{}) as Dictionary).get("next_base_energy_regen",1))+int(_players[side].get("next_turn_energy_bonus",0))
		deck.reserve.text="COST %d · TRAINING"%cost if _local_fixture else "%d AFTER PLAY · +%d NEXT"%[maxi(0,energy-cost),regen]
		deck.count.text="%d / %d"%[int(_pages[side])+1,page_count]
		deck.heading.text="ABILITY" if size.x<760 or size.y<500 else "YOUR ABILITIES" if not _local_fixture else "TRAINER "+side+" · ABILITIES"
		var ready_wait: bool = _snapshot.get("status") == "ready" and _players[side].get("ready") == true
		deck.commit.text = "SENDING…" if _commit_pending else "WAITING…" if ready_wait else "I'M READY" if _snapshot.get("status") == "ready" else "LOCKED IN" if _committed and not _local_fixture else "PASS TURN" if (_selected[side] as Array).is_empty() else "TEST ABILITY" if _local_fixture else "LOCK IN"
		deck.commit.disabled = _cancel_pending or _commit_pending or cost>energy or ((_committed or ready_wait or _snapshot.get("status") not in ["ready", "active"]) and not _local_fixture)
		deck.previous.disabled = page_count <= 1; deck.next.disabled = page_count <= 1
		for i in range(3):
			var index := int(_pages[side]) * 3 + i; var button := deck.cards[i] as Button
			button.visible = index < hand.size()
			if not button.visible: continue
			var card := hand[index] as Dictionary; var sp := String(_players[side].species)
			var profile := Visual.profile(sp, int(card.slot))
			button.set_meta("canonical_key", String(profile.key)); button.set_meta("canonical_slot", int(card.slot))
			(button.get_node("PaintedCard") as TextureRect).texture = CardPresentation.texture(sp, int(card.slot))
			button.tooltip_text = ""
			if _players[side].get("trait") is Dictionary:
				var own_trait := _players[side].get("trait") as Dictionary
				if String(profile.get("arch", "")) == String(own_trait.get("signature_arch", "")):
					button.tooltip_text = "%s · favored ability (%s)" % [String(own_trait.get("name", "Trait")), String(own_trait.get("signature_effect", ""))]
			button.modulate = Color.WHITE # Preserve the actual painted card; no badges or markings.
			var chosen:=(_selected[side] as Array).has(int(card.slot))
			_pose_card(side,i)
			button.disabled = _cancel_pending or _commit_pending or (_committed and not _local_fixture) or int(card.cost)>energy
			_stream.queue_profile(profile, false)
		_order_deck_hit_targets(side)
	_update_tactical_ui()


func _select_card(side: String, position: int) -> void:
	if _cancel_pending or _commit_pending or side!=_active_side() or not _hands.has(side) or position<0:return
	var index := int(_pages[side]) * 3 + position
	if index >= (_hands[side] as Array).size() or (_committed and not _local_fixture): return
	if int(_hands[side][index].cost)>int(_players[side].energy):_toast("Not enough energy for this card");return
	var slot := int(_hands[side][index].slot); var selected := _selected[side] as Array
	if _continuous():
		if _snapshot.get("status")!="active":return
		if _cooldown_left(slot)>0.05:return
		selected.clear();selected.append(slot)
		_stream.queue_profile(Visual.profile(String(_players[side].species),slot),true)
		commit_side(side);return
	if selected.has(slot): selected.erase(slot)
	else:
		selected.clear()
		selected.append(slot)
		_stream.queue_profile(Visual.profile(String(_players[side].species), slot), true)
	_refresh_decks()
	if size.x<760 or size.y<500:_hover_side=side;_hover_index=position;_update_tactical_ui()


func _page(side: String, direction: int) -> void:
	var count := maxi(1, ceili(float((_hands[side] as Array).size()) / 3.0))
	_hover_side="";_hover_index=-1;_inspector.hide()
	_pages[side] = posmod(int(_pages[side]) + direction, count); _refresh_decks()


func commit_side(side: String) -> void:
	if _cancel_pending or _commit_pending: return
	if not SIDES.has(side) or _players.is_empty() or (not _local_fixture and (side != _you or _committed)): return
	if _snapshot.get("status") == "ready":
		_commit_pending=not _local_fixture;_ready_pending=not _local_fixture;request.emit({"op": "ready", "mode": _intent_mode(), "match_id": _match_id});_refresh_decks();return
	if _snapshot.get("status") != "active": return
	var slots := (_selected[side] as Array).duplicate()
	var cost:=0
	for slot in slots:
		var found:=false
		for card in _hands[side]:
			if int(card.slot)==int(slot):cost+=int(card.cost);found=true;break
		if not found:_toast("That card is no longer in your hand");return
	if cost>int(_players[side].energy):_toast("Not enough energy · choose another card");_refresh_decks();return
	if _continuous():
		if slots.is_empty():return
		if _cooldown_left(int(slots[0]))>0.05:return
		if not _local_fixture:
			_commit_pending=true
			request.emit({"op":"cast","mode":_intent_mode(),"match_id":_match_id,"slot":int(slots[0])})
			_refresh_decks();return
		_local_cast_until[side]=float(Time.get_ticks_msec())/1000.0+0.55
	_commit_pending=not _local_fixture
	_hover_side="";_hover_index=-1;_inspector.hide();_targeting.clear_preview()
	if not _continuous():
		request.emit({"op": "commit", "mode": "practice", "match_id": _match_id, "revision": _revision,
			"turn": int(_snapshot.turn), "side": side, "slots": slots, "slot": slots[0] if not slots.is_empty() else null})
	if not _local_fixture:_toast("Move sent · waiting for opponent");_refresh_decks();return # No optimistic combat or fabricated server events.
	for slot in slots:
		var profile := Visual.profile(String(_players[side].species), int(slot))
		_stream.queue_profile(profile, true)
		for type in ["cast", "impact"]:
			_max_seq += 1
			_events.append({"id": "local-human-%d" % _max_seq, "seq": _max_seq, "turn": 1,
				"side": side, "species": profile.species, "slot": slot, "type": type,
				"target_side": "B" if side == "A" else "A", "amount": 0,
				"status": "art_rehearsal", "remaining_turns": 0, "confirmed": true})
	if not _continuous():_selected[side] = []
	_refresh_decks()


func _art_ready(_key: String, _kind: String) -> void:
	for rig in _rigs.values(): rig.call("refresh_streamed_art")


func _pin_card(profile: Dictionary) -> bool:
	var key := String(profile.key)
	if _pinned_layers.has(key):
		_pin_order.erase(key); _pin_order.append(key); return true
	var base := Sprites.reborn_effect_asset(profile)
	if base.is_empty(): return false
	var layers := {}
	for role in (base.get("layers", {}) as Dictionary):
		var asset := Sprites.reborn_effect_layer_asset(profile, String(role))
		if not asset.is_empty(): layers[role] = asset
	if layers.is_empty(): return false
	_pinned_layers[key] = layers; _pin_order.append(key)
	while _pin_order.size() > 4: _pinned_layers.erase(_pin_order.pop_front())
	return true


func _get_layer(profile: Dictionary, role: String) -> Dictionary:
	var asset: Dictionary = (_pinned_layers.get(String(profile.key), {}) as Dictionary).get(role, {})
	return asset if not asset.is_empty() else Sprites.reborn_effect_layer_asset(profile, role)


func _render_event(event: Dictionary) -> void:
	if event.type == "finish":
		for state_id in _states.keys(): _end_state(String(state_id))
		_finish_pending = true; return # Terminal reveal waits for queued confirmed effects to retire.
	var side := String(event.side); var target := String(event.target_side)
	if event.get("signature_triggered") == true and side == _active_side(): _toast(_signature_cue(event))
	var profile := Visual.profile(String(event.species), int(event.slot))
	_pin_card(profile)
	var rig := _rigs[side] as Node3D; var victim := _rigs[target] as Node3D
	var direction := Vector2(victim.position.x - rig.position.x, victim.position.z - rig.position.z).normalized()
	if direction.is_zero_approx(): direction = Vector2.RIGHT if side == "A" else Vector2.LEFT
	match String(event.type):
		"cast":
			_stream.queue_profile(profile, true); rig.call("face", direction); rig.call("attack", String(profile.arch), profile)
			_fx(profile, "anticipation", side, target, direction)
			_fx(profile, "release", side, target, direction, float(profile.release))
			if TRAVELLING.has(String(profile.delivery)):
				_fx(profile, "projectile", side, target, direction, float(profile.release), true)
				_fx(profile, "trail", side, target, direction, float(profile.release) + 0.05, true)
			if String(profile.arch) == "quick":
				var home := rig.position
				var authored_server_dash: bool = event.get("dash_to") is Dictionary
				var desired := home + Vector3(direction.x, 0, direction.y) * minf(1.44, maxf(0, home.distance_to(victim.position) - 1.25))
				if authored_server_dash:
					desired = _position_vector(event.dash_to, home)
				var stop := _sweep(home, desired).position as Vector3
				var tween := create_tween()
				tween.tween_method(func(at: Vector3):
					var ground := _ground(Vector2(at.x, at.z))
					if ground.valid: at.y = float(ground.height_m)
					rig.position = at, home, stop, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
				if not authored_server_dash:
					tween.tween_method(func(at: Vector3):
						var ground := _ground(Vector2(at.x, at.z))
						if ground.valid: at.y = float(ground.height_m)
						rig.position = at, stop, home, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				_dashing[side] = 0.55
				_tweens.append(tween)
				_fx(profile, "trail", side, target, direction, float(profile.release))
		"impact":
			# Heal art is not inferred from damage, HP deltas, drain flavor or a missed cast.
			if float(event.amount) > 0:
				var impact_asset := _get_layer(profile, "impact")
				if String(impact_asset.get("anchor", "")) != "actor" or String(profile.arch) != "drain": _fx(profile, "impact", side, target, direction)
				_fx(profile, "hit", side, target, direction); victim.call("play", "hurt")
			elif event.get("reason") in ["out_of_range", "blocked_line_of_sight"]:
				_note.text = "OUT OF RANGE · reposition before a close attack" if event.reason == "out_of_range" else "BLOCKED BY COVER · find a clear line of sight"
				if side==_active_side():_toast("Out of range · move closer" if event.reason=="out_of_range" else "Blocked by cover · find a clear shot")
		"heal":
			# A target-contact attack frame is NOT a healing image. Honor only exact actor-absorption art.
			if float(event.amount) > 0 and String(profile.arch) == "drain" and String(_get_layer(profile, "impact").get("anchor", "")) == "actor":
				var other := "B" if side == "A" else "A"
				_fx(profile, "return", side, other, direction, 0, true, true)
				_fx(profile, "impact", side, side, direction, 0.22)
		"recoil":
			# Explicit self-damage never produces another cast, projectile or enemy hit.
			if float(event.amount) > 0: rig.call("play", "hurt")
		"block":
			_fx(profile, "block", side, target, direction)
			var body := Sprites.reborn_body_asset(profile)
			if not body.is_empty(): rig.call("play_body_event", body, "block", direction)
		"status_start":
			var state_id := target + ":" + String(profile.key) + ":" + String(event.get("status", ""))
			_end_state(state_id); _fx(profile, "status", target, target, direction, 0, false, false, state_id)
		"status_end":
			_end_state(target + ":" + String(profile.key) + ":" + String(event.get("status", "")))
			_fx(profile, "expire", side, target, direction)


func _fx(profile: Dictionary, role: String, side: String, target: String, direction: Vector2,
		delay: float = 0, travel: bool = false, returning: bool = false, state_id: String = "") -> bool:
	if _effects.size() >= FX_LIMIT: return false
	var asset := _get_layer(profile, role)
	if asset.is_empty(): return false # Never a generic orb, slash, aura or borrowed creature effect.
	var layer := asset.get("layer", {}) as Dictionary
	var window := asset.get("frames", Vector2i(-1, -1)) as Vector2i
	if window.x < 0 or window.y <= 0: return false
	var node := Sprite3D.new(); node.texture = asset.texture
	# This scene composes its own camera basis; neither shared camera ShaderMaterials nor floor
	# materials are mutated. Preserve the same atlas, alpha/add blending and linear sampler locally.
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if String(layer.get("blend", asset.get("blend", "alpha"))) == "add" else BaseMaterial3D.BLEND_MODE_MIX
	material.disable_receive_shadows = true; material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true; material.albedo_texture = asset.texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED; node.material_override = material
	node.region_enabled = true; node.shaded = false; node.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	var cell := asset.cell as Vector2i; var pivot := asset.pivot as Vector2
	node.pixel_size = 1.7 / float(maxi(cell.x, cell.y)); node.scale = Vector3.ONE * float(asset.scale)
	if layer.has("world_size_m"): node.pixel_size = float(layer.world_size_m) / float(maxi(1, cell.y))
	node.offset = Vector2((0.5 - pivot.x) * cell.x, (pivot.y - 0.5) * cell.y)
	node.flip_h = bool(layer.get("native_flip_x", false)) != (bool(layer.get("mirror_x_with_direction", false)) and direction.x < 0)
	var angle := atan2(-direction.y, direction.x) if bool(layer.get("orient", false)) and not bool(layer.get("mirror_x_with_direction", false)) else 0.0
	var upright: bool = not bool(layer.get("orient", false)) and (asset.anchor == "floor" or (asset.anchor == "actor" and layer.has("world_size_m")))
	var plane := _camera.global_basis
	if upright:
		var right := Vector3(plane.x.x, 0, plane.x.z).normalized(); plane = Basis(right, Vector3.UP, right.cross(Vector3.UP))
	node.basis = (plane * Basis(Vector3.BACK, angle)).scaled(Vector3.ONE * float(asset.scale))
	var caster := _rigs[side] as Node3D; var victim := _rigs[target] as Node3D
	var anchor := String(asset.get("anchor", "profile"))
	var actor_phase: bool = role in ["anticipation", "release", "projectile", "trail"]
	var follow := side if anchor == "actor" or (anchor == "profile" and actor_phase) else target
	if not state_id.is_empty(): follow = target
	var start := caster.position + Vector3(direction.x, 0.78, direction.y) * Vector3(0.45, 1, 0.45)
	var finish := victim.position + Vector3.UP * 0.78
	if returning:
		start = victim.position + Vector3.UP * 0.78; finish = caster.position + Vector3.UP * 0.78
	var fixed := (_rigs[follow] as Node3D).position + Vector3.UP * float(layer.get("height_m", 0.78))
	if anchor == "floor":
		fixed.y = (_rigs[follow] as Node3D).position.y + 0.10
		if layer.has("actor_forward_px"):
			fixed = caster.position + Vector3(direction.x, 0, direction.y) * float(layer.actor_forward_px) * 0.012
			fixed.y = caster.position.y + 0.10; follow = side
	var plane_offset := float(layer.get("camera_plane_offset_m", 0))
	if anchor == "actor" and layer.has("world_size_m"): plane_offset = 0.035
	var toward_camera := Vector3(_camera.global_basis.z.x, 0, _camera.global_basis.z.z).normalized() * plane_offset
	fixed += toward_camera; start += toward_camera; finish += toward_camera
	var fps := maxf(1, float(layer.get("fps", 20)))
	node.visible = false; _world.add_child(node)
	var fx := {"node": node, "asset": asset, "frames": window, "age": -delay,
		"duration": maxf(0.08, float(window.y) / fps),
		"fps": fps, "loop": not state_id.is_empty(),
		"follow": follow, "anchor": anchor, "fixed": fixed, "travel": travel,
		"start": start, "finish": finish, "transit": 0.22 if returning else 0.30,
		"state_id": state_id, "role": role, "key": String(profile.key), "follow_actor": anchor == "actor" or not state_id.is_empty() or (anchor == "profile" and actor_phase),
		"plane_offset": toward_camera, "direction": direction}
	_effects.append(fx)
	if not state_id.is_empty(): _states[state_id] = node
	return true


func _end_state(state_id: String) -> void:
	if not _states.has(state_id): return
	var node: Node = _states[state_id]; _states.erase(state_id)
	if is_instance_valid(node): node.queue_free()


func _position_vector(value: Variant, fallback: Vector3) -> Vector3:
	if not value is Dictionary or not _number(value.get("x")) or not _number(value.get("y")) or not _number(value.get("z")): return fallback
	return Vector3(float(value.x), float(value.y), float(value.z))


func _movement_direction(side: String) -> Vector2:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return Vector2.ZERO
	if side == _active_side() and _move_surface != null and (_move_surface.get("axis") as Vector2).length() > 0:
		return _move_surface.get("axis") as Vector2
	if _local_fixture and side == "B":
		return Vector2(float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)),
			float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP))).limit_length(1)
	return Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))).limit_length(1)


func _reference_battle_focus(actor: Vector3) -> Vector3:
	# The desktop lens looks a little toward the arena's gate so its real 3D
	# stands frame the duel. Ease that look-ahead out before the rear wall; this
	# remains the owner's private follow camera, never a rival/midpoint camera.
	var compact := size.x < 760 or size.y < 500
	var rear_lead := 0.0 if compact else 4.0 * smoothstep(-20.0, -8.0, actor.z)
	return Vector3(actor.x, -4.2, actor.z + 2.0 - rear_lead)


func _movement_frame(dt: float) -> void:
	var active: bool = not _players.is_empty() and not _cancel_pending and _snapshot.get("status") == "active"
	var transient_cast := not _events.is_empty() or not _dashing.is_empty()
	for effect in _effects:
		if not bool(effect.get("loop", false)): transient_cast = true
	var can_plan: bool = active and (_continuous() or ((_local_fixture or not _committed) and not _commit_pending and not transient_cast)) and not _rules.visible and not _leave_dialog.visible and not _card_dialog.visible
	if _move_surface != null: _move_surface.call("activate", can_plan)
	_move_clock -= dt
	for side in SIDES:
		if not _rigs.has(side): continue
		var rig := _rigs[side] as Node3D
		var before := rig.position
		if _dashing.has(side):
			_dashing[side] = float(_dashing[side]) - dt
			if float(_dashing[side]) <= 0: _dashing.erase(side)
			continue
		if _local_fixture and can_plan:
			var axis := _movement_direction(side)
			var intent := before + Vector3(axis.x, 0, axis.y) * minf(dt, 0.05) * 3.8
			rig.position = _sweep(before, intent).position
		elif _movement_targets.has(side) and (_continuous() or _events.is_empty()):
			var goal: Vector3 = _movement_targets[side]
			var next := before.lerp(goal, 1.0 - exp(-dt * 15.0))
			rig.position = _sweep(before, next).position
		var traveled := Vector2(rig.position.x - before.x, rig.position.z - before.z)
		var metrics: Dictionary = rig.call("visual_metrics")
		if not bool(metrics.get("dedicated_card_action", false)) and not bool(metrics.get("body_event_active", false)) and String(rig.call("clip")) not in ["attack", "hurt", "defeated"]:
			if traveled.length() > 0.001:
				rig.call("face", traveled.normalized())
				if not bool(rig.get("_distance_walk")): rig.call("set_distance_driven_walk", true, 72.0)
				rig.call("play", "walk"); rig.call("advance_walk_distance", traveled.length() / 0.012)
			else: rig.call("play", "idle")
	if can_plan and not _local_fixture and _transport != null and _move_clock <= 0:
		_move_clock = 0.10
		var direction := _movement_direction(_you)
		if not direction.is_zero_approx() and (_continuous() or float(_players[_you].get("movement_remaining", 0)) > 0):
			request.emit({"op": "move", "mode": _intent_mode(), "match_id": _match_id, "dx": direction.x, "dz": direction.y})
	var target := Vector3.ZERO
	if reference_world_mode and _rigs.has(_active_side()):
		# Private player POV, never a midpoint of both combatants or a whole-map reveal.
		# The fixed lens bearing also avoids camera yaw jerks when reversing direction.
		var actor := (_rigs[_active_side()] as Node3D).position
		target = _reference_battle_focus(actor)
	elif not reference_image_mode and not _camera_close and _rigs.has(_active_side()):
		var actor := (_rigs[_active_side()] as Node3D).position
		target = Vector3(actor.x * 0.30, 0, actor.z * 0.20)
	_camera_focus = _camera_focus.lerp(target, 1.0 - exp(-dt * 5))
	if not reference_image_mode:
		_camera.position = (ReferenceWorld.CAMERA_AT if reference_world_mode else Architecture.CAMERA_AT) + _camera_focus
		_camera.look_at((ReferenceWorld.CAMERA_TARGET if reference_world_mode else Architecture.CAMERA_TARGET) + _camera_focus)
		if reference_world_mode: _camera.fov = lerpf(_camera.fov, _camera_target_size, 1.0 - exp(-dt * 5))
		else: _camera.size = lerpf(_camera.size, _camera_target_size, 1.0 - exp(-dt * 5))


func _input(event: InputEvent) -> void:
	if not is_node_ready() or _lobby==null or _lobby.visible:return
	if get_viewport().gui_get_focus_owner() is LineEdit:return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_SPACE,KEY_1,KEY_2,KEY_3,KEY_Q,KEY_E,KEY_TAB]:
		_unhandled_key_input(event)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or _lobby.visible:return
	if _rules.visible or _leave_dialog.visible or _card_dialog.visible:return
	if event.physical_keycode==KEY_SPACE:commit_side(_active_side());get_viewport().set_input_as_handled()
	elif event.physical_keycode in [KEY_1,KEY_2,KEY_3]:_select_card(_active_side(),int(event.physical_keycode)-KEY_1);get_viewport().set_input_as_handled()
	elif event.physical_keycode==KEY_Q:_page(_active_side(),-1);get_viewport().set_input_as_handled()
	elif event.physical_keycode==KEY_E:_page(_active_side(),1);get_viewport().set_input_as_handled()
	elif event.physical_keycode==KEY_TAB and _local_fixture:_switch_practice_side();get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	_movement_frame(dt)
	_animate_cooldown_tints()
	_feedback_left=maxf(0,_feedback_left-dt);_feedback.visible=_feedback_left>0
	if reference_world_mode:
		_quality_check_clock -= dt
		if _quality_check_clock <= 0.0:
			_quality_check_clock = 1.0
			if _render_quality_tier != _desired_reference_quality():
				_apply_reference_quality(size.x < 760 or size.y < 500)
	_ui_clock-=dt
	if _ui_clock<=0:_ui_clock=0.08;_update_tactical_ui()
	_event_delay -= dt
	if _event_delay <= 0 and not _events.is_empty() and not _cancel_pending:
		var event: Dictionary = _events.front()
		var art_ready := true
		if event.type != "finish" and (online_entry_mode or bool(_stream.status().enabled)):
			var profile := Visual.profile(String(event.species), int(event.slot))
			_stream.queue_profile(profile, true)
			art_ready = (not online_entry_mode or _live_art_bound) and _pin_card(profile) and (event.type != "cast" or not Sprites.reborn_body_asset(profile).is_empty())
		if art_ready:
			_render_event(_events.pop_front()); _event_delay = 0.025 if _continuous() else 0.34; _art_wait = 0
		else:
			_art_wait += dt
			if _art_wait > 2.0:
				_events.pop_front(); _art_wait = 0
				_note.text = "Confirmed server state remains authoritative. Exact card art unavailable; no substitute effect was shown."
	for i in range(_effects.size() - 1, -1, -1):
		var fx := _effects[i] as Dictionary
		if not is_instance_valid(fx.node): _effects.remove_at(i); continue
		var node := fx.node as Sprite3D
		fx.age = float(fx.age) + dt
		if fx.age < 0: continue
		if not fx.loop and fx.age > maxf(fx.duration, fx.transit if fx.travel else 0):
			node.queue_free(); _effects.remove_at(i); continue
		node.visible = true
		var window := fx.frames as Vector2i; var offset := floori(float(fx.age) * fx.fps)
		offset = posmod(offset, window.y) if fx.loop else mini(offset, window.y - 1)
		var frame := window.x + offset; var grid := fx.asset.grid as Vector2i; var cell := fx.asset.cell as Vector2i
		node.region_rect = Rect2((frame % grid.x) * cell.x + 0.5, floori(float(frame) / grid.x) * cell.y + 0.5, cell.x - 1, cell.y - 1)
		if fx.travel: node.position = (fx.start as Vector3).lerp(fx.finish, clampf(float(fx.age) / float(fx.transit), 0, 1))
		elif fx.follow_actor and _rigs.has(fx.follow):
			node.position = (_rigs[fx.follow] as Node3D).position + Vector3.UP * float((fx.asset.layer as Dictionary).get("height_m", 0.78))
			if fx.anchor == "floor":
				node.position.y = (_rigs[fx.follow] as Node3D).position.y + 0.10
				node.position += Vector3(fx.direction.x, 0, fx.direction.y) * float((fx.asset.layer as Dictionary).get("actor_forward_px", 0)) * 0.012
			node.position += fx.plane_offset
		else: node.position = fx.fixed
	if _finish_pending and _events.is_empty() and _effects.is_empty():
		_finish_pending = false; _pinned_layers.clear(); _pin_order.clear()
		_clock.text = "DUEL COMPLETE" if online_entry_mode else "PRACTICE COMPLETE · NO SOL"
		var winner := String(_snapshot.get("winner", "")) if _snapshot.get("winner") != null else ""
		_note.text = ("Server-confirmed online " if online_entry_mode else "Server-confirmed practice ") + ("winner: " + winner if SIDES.has(winner) else "draw / cancellation") + (" · no wagering" if online_entry_mode else " · TEST CREDITS only · no NFT ownership or SOL claim")
	for side in _rigs:
		var head_at:=(_rigs[side] as Node3D).position + Vector3.UP * 2.03
		var screen := _camera.unproject_position(head_at)
		var plate := _plates[side].root as Control
		plate.position = _stage.position + screen * _stage.size / Vector2(_viewport.size) - Vector2(plate.size.x * 0.5, plate.size.y)
		# A private camera can lose sight of the rival. Do not leave a half-name or
		# a detached health tag clipped against the edge when the actor is offscreen.
		plate.visible=not _lobby.visible and not _camera.is_position_behind(head_at) and Rect2(_stage.position,_stage.size).encloses(Rect2(plate.position,plate.size))
	if not _players.is_empty() and _snapshot.get("status") in ["ready", "active"]:
		var elapsed := float(Time.get_ticks_msec() - _received_ticks) / 1000.0
		var left := maxi(0, ceili(float(_snapshot.deadline) - _server_time - elapsed))
		_clock.text = "LOCAL HUMAN REHEARSAL" if _local_fixture else "ONLINE DUEL · %ds" % left if online_entry_mode else "TURN %d · %ds · TEST CREDITS ONLY" % [int(_snapshot.turn), left]
		_duel_hud.set_clock(left)


func _layout() -> void:
	if _title == null: return
	var viewport_size := size; var mobile := viewport_size.x < 760 or viewport_size.y < 500
	if reference_image_mode:
		_stage.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		var scale := minf(viewport_size.x / REFERENCE_PIXELS.x, viewport_size.y / REFERENCE_PIXELS.y)
		_stage.size = REFERENCE_PIXELS * scale; _stage.position = (viewport_size - _stage.size) * 0.5
	else: _stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := 12.0 if mobile else 24.0
	var portrait:=viewport_size.x<viewport_size.y
	# Header owns the reserved toolbar slot, keeping both opposing HP rails equal.
	var toolbar:Rect2=_duel_hud.call("diagnostics").reserved_controls
	var toolbar_at:=toolbar.position-global_position+Vector2(0,maxf(0,(toolbar.size.y-32)*.5))
	(get_node("Exit") as Control).position = toolbar_at+Vector2(46,0)
	(get_node("Exit") as Control).size = Vector2(34,32)
	_view_button.position = toolbar_at;_view_button.size=Vector2(34,32)
	_move_surface.visible=mobile and not _lobby.visible
	_viewport.msaa_3d = Viewport.MSAA_2X if mobile else Viewport.MSAA_4X
	if reference_world_mode: _apply_reference_quality(mobile)
	var header:=float(_duel_hud.header_height())
	_lobby.size=Vector2(minf(600,viewport_size.x-margin*2),minf(590,maxf(160,viewport_size.y-header-30)))
	_lobby.position=Vector2((viewport_size.x-_lobby.size.x)*0.5,header+10)
	var card_w:=clampf(viewport_size.y*.11,90,118) if not mobile else 62.0 if not portrait else minf(82,(viewport_size.x-132)/3.0)
	var card_h := card_w * 1.5
	# A genuine hand: shallow overlap, a low fan, and no dock/backing rectangle.
	# Bottom padding accounts for the tilted outer card corners, not a generic panel margin.
	var card_stride := card_w * .70
	var cards_y:=36.0 if mobile else 42.0
	var fan_bottom := 5.0 + sin(deg_to_rad(4.0)) * card_w * .5
	var deck_w:=card_w+card_stride*2;var deck_h:=card_h+cards_y+fan_bottom
	var dock_x:=(viewport_size.x-deck_w)*.5 if not mobile or portrait else viewport_size.x-54-deck_w
	var dock_y:=viewport_size.y-deck_h-4.0
	var pad_size:=104.0 if mobile else 120.0
	_move_surface.size=Vector2.ONE*pad_size
	_move_surface.position=Vector2(margin,viewport_size.y-margin-pad_size-42)
	if portrait:_move_surface.position.y=dock_y-pad_size-44
	_reset.text="↩";_reset.tooltip_text="Lobby";_reset.position=Vector2(margin,viewport_size.y-margin-32);_reset.size=Vector2(32,32)
	_help_button.position=Vector2(margin+38,viewport_size.y-margin-32);_help_button.size=Vector2(32,32)
	_switch_trainer.visible=_local_fixture and not _lobby.visible
	_switch_trainer.text="⇄";_switch_trainer.tooltip_text="Switch training creature · Tab"
	_switch_trainer.position=Vector2(margin+76,viewport_size.y-margin-32);_switch_trainer.size=Vector2(32,32)
	if portrait:
		_reset.position.y=dock_y-40;_help_button.position.y=dock_y-40
		_switch_trainer.position=Vector2(viewport_size.x-margin-32,dock_y-40)
	_reset.visible=not _lobby.visible
	_feedback.size=Vector2(minf(540,viewport_size.x-32),32)
	_feedback.position=Vector2((viewport_size.x-_feedback.size.x)/2,header+8)
	var inspect_h:=minf(440,viewport_size.y-header-62)
	if mobile:inspect_h=minf(270,viewport_size.y-header-60) if not portrait else minf(340,dock_y-header-28)
	var inspect_w:=inspect_h*.70
	_inspector.size=Vector2(inspect_w,inspect_h);_inspector.pivot_offset=Vector2(0,inspect_h)
	_inspector.position=Vector2(margin,viewport_size.y-margin-inspect_h-52 if not portrait else header+16)
	_inspect_image.position=Vector2.ZERO;_inspect_image.size=_inspector.size
	_inspect_title.hide();_inspect_detail.hide()
	for side in SIDES:
		var deck := _decks[side] as Dictionary; var root := deck.root as Control
		root.size = Vector2(deck_w, deck_h)
		root.position=Vector2(dock_x,dock_y)
		for field in ["icon","energy","heading","action_name","hint","reserve","movement","inspect","count"]:(deck[field] as Control).hide()
		var meter_w:=160.0 if mobile else 190.0
		deck.meter.position=Vector2((deck_w-meter_w)*.5,0);deck.meter.size=Vector2(meter_w,18 if mobile else 24)
		for i in range(3):
			var card:Button=deck.cards[i];card.size=Vector2(card_w,card_h);card.pivot_offset=Vector2(card_w*.5,card_h)
			card.set_meta("resting_position",Vector2(i*card_stride,cards_y+(5 if i!=1 else 0)))
			card.set_meta("resting_rotation",deg_to_rad(float(i-1)*4.0));_pose_card(side,i)
			deck.cooldowns[i].hide()
		deck.commit.position=Vector2((deck_w-130)*.5,64);deck.commit.size=Vector2(130,36)
		deck.commit.visible=_snapshot.get("status")=="ready" and not _local_fixture
		deck.previous.position=Vector2(-42,cards_y+card_h*.55);deck.previous.size=Vector2(26,30)
		deck.next.position=Vector2(deck_w+16,cards_y+card_h*.55);deck.next.size=Vector2(26,30)
		for arrow in [deck.previous,deck.next]:
			arrow.visible=not arrow.disabled
			arrow.add_theme_font_size_override("font_size",23)
			for state in ["normal","hover","pressed","disabled","focus"]:arrow.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		var plate := _plates[side] as Dictionary
		plate.root.size = Vector2(70 if mobile and viewport_size.x < viewport_size.y else 90 if mobile else 120, 24)
		plate.name.position = Vector2.ZERO; plate.name.size = Vector2(plate.root.size.x, 16)
		plate.hp.position = Vector2(8, 18); plate.hp.size = Vector2(plate.root.size.x - 16, 5)
		plate.name.add_theme_color_override("font_outline_color",Color("181421"));plate.name.add_theme_constant_override("outline_size",3)
	_camera_target_size = (Architecture.CAMERA_SIZE if viewport_size.x > viewport_size.y else 36.0) * (0.72 if _camera_close else 1.0)
	if reference_world_mode:
		_camera.keep_aspect = Camera3D.KEEP_HEIGHT if viewport_size.x > viewport_size.y else Camera3D.KEEP_WIDTH
		# Desktop shows the actual gate and stands while retaining a private combat
		# camera; compact/mobile keeps the proven tighter creature scale. Preserve
		# the original 1.5x world-span conversion rather than scaling angles.
		var previous_fov := (4.2 if _camera_close else 3.0) if mobile else (8.4 if _camera_close else 6.0)
		_camera_target_size=rad_to_deg(2.0*atan(tan(deg_to_rad(previous_fov)*0.5)*1.5))
		if _lobby.visible or _players.is_empty():
			_camera_target_size=16.0 if not portrait else 18.0
		# In short landscape windows, compose the duel above the right-hand card dock.
		# This shifts only the lens framing, never actors, navigation or server aim.
		_camera.v_offset=-1.4 if mobile and not portrait else 0.0
	if reference_image_mode and _reference_guide != null:
		var outline := PackedVector2Array()
		for index in range(129):
			var angle := TAU * float(index) / 128.0
			outline.append(_camera.unproject_position(Vector3(cos(angle), 0, sin(angle)) * (ReferenceFloor.FLOOR_RADIUS_M - ReferenceFloor.FOOT_RADIUS_M)))
		_reference_guide.points = outline


func diagnostics() -> Dictionary:
	return {"development_only": not online_entry_mode, "live_authenticated": _live_authenticated, "live_art_release_bound": _live_art_bound, "authentication_lost_display_retired": _auth_connection_lost, "local_two_human": _local_fixture, "match_id": _match_id,
		"revision": _revision, "event_seq": _max_seq, "queued_events": _events.size(),
		"fx_count": _effects.size(), "actor_count": _rigs.size(), "states": _states.size(),
		"pinned_card_sheets": _pinned_layers.size(),
		"cancel_pending": _cancel_pending, "finish_pending": _finish_pending,
		"combat_math": false, "ai": false, "sol_enabled": false, "cup_mutations": false,
		"stream": _stream.status() if _stream != null else {}, "architecture": Architecture.diagnostics(),
		"navigation": Navigation.diagnostics(), "movement_revision": _movement_revision,
		"image_reference": reference_image_mode or reference_world_mode, "visible_voxel_model": not reference_image_mode and not reference_world_mode,
		"realtime_reference_world": reference_world_mode, "reference_world": ReferenceWorld.diagnostics() if reference_world_mode else {},
		"chikoria_surround": ChikoriaSurround.diagnostics() if reference_world_mode else {},
		"player_camera": {"follow_side":_active_side(),"private_follow":reference_world_mode,"fov_target":_camera_target_size,
			"whole_map_mode":_lobby.visible or _players.is_empty(),"smooth_follow":true,"focus":_camera_focus,"fixed_bearing":true,
			"battle_view_span_scale":1.5 if reference_world_mode else 1.0},
		"reference_floor": ReferenceFloor.diagnostics() if reference_image_mode else {},
		"movement_authority": "offline_visual_only" if _local_fixture else "server", "hd_msaa": _viewport.msaa_3d,
		"render_quality_tier": _render_quality_tier if reference_world_mode else -1,
		"render_scale": _viewport.scaling_3d_scale if reference_world_mode else 1.0,
		"natural_sun_shadows": _arena_sun.shadow_enabled if reference_world_mode and _arena_sun != null else false}


func _exit_tree() -> void:
	if _stream != null: _stream.cancel_all()
