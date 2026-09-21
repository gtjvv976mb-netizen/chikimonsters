extends "res://Temple3D.gd"
class_name TempleHorde3D

# ==============================================================================================
# WICKED TEMPLE: CORRUPTION SIEGE
# One player-owned Chikimon, five compact arena waves, and the collection's real ability cards in
# the proven 2D-sprite / 3D-world temple.  The inherited hall remains the only geometry authority;
# this script owns the run state, enemies, combat and HUD without changing the legacy ritual.
# ==============================================================================================

signal stage_completed(stats: Dictionary)
signal exit_requested
signal creature_changed(uid: String)
signal mobile_options_visibility_changed(expanded: bool)

const Econ := preload("res://Econ.gd")
const SpeciesTraits := preload("res://ChikimonSpeciesTraits.gd")
const CardArt := preload("res://TempleCardArt.gd")
const AbilityVisual := preload("res://TempleAbilityVisual.gd")
const AbilitySprites := preload("res://TempleAbilitySprites.gd")
const AbilityArtStream := preload("res://TempleAbilityArtStream.gd")
const RebornFX := preload("res://RebornCombat.gd")
const StatusSprites := preload("res://TempleStatusSprites.gd")
const MobileLayout := preload("res://TempleMobileLayout.gd")
const MobileViewport := preload("res://TempleMobileViewport.gd")
const MobileRender := preload("res://TempleMobileRender.gd")

const SFX_CARD := preload("res://audio/sfx_card.wav")
const SFX_HIT := preload("res://audio/sfx_hit.wav")
const SFX_FOE := preload("res://audio/sfx_foe.wav")
const SFX_LEVEL := preload("res://audio/sfx_levelup.wav")
const SFX_WIN := preload("res://audio/sfx_win.wav")
const ENERGY_ICON_PATH := "res://mat/essence.png"

const WAVE_TOTAL := 5
const MAX_FOES := 16
const PHONE_FOES := 12
const MAX_ACTIVE_FOES := 6
const MAX_PROJECTILES := 28
const PHONE_PROJECTILES := 18
const MAX_EFFECTS := 36
const PHONE_EFFECTS := 24
const MAX_FLOATERS := 18
const PHONE_FLOATERS := 12
const STATUS_POOL_CAP := 10
# A close attack must reach a normal mob whose physical body already touches the player.
# Share this boundary with separation; canonical longer ranges and noncontact deliveries stay intact.
const ENEMY_PLAYER_CONTACT_DISTANCE_PX := 128.0
const CONTACT_DISTANCE_EPSILON_PX := 0.001 # Float32 normalization tolerance, one thousandth of a world pixel.

# The browser presents roughly 0.585 CSS px per Godot logical pixel at the 844×390 phone target.
# Touch and typography are authored against that real display scale, not against the backing canvas.
const PHONE_CSS_PER_LOGICAL := 0.585
const PHONE_TOUCH_LOGICAL := 104.0
const PHONE_FONTS := {
	# 24 logical px is 10.4 physical px in the unscaled 844x390 native proof and 14.0 CSS px
	# in the shipped phone canvas. Nothing informational is allowed below that floor.
	"unit": 24, "rarity": 24, "hp": 24, "wave": 30, "remaining": 24,
	"target": 24, "score": 28, "energy": 24, "message": 28,
	"card_name": 24, "card_footer": 24, "button": 24, "move": 24,
}

const ENERGY_MAX := 4.0
const ENERGY_REGEN := 0.55
const DODGE_TIME := 0.20
const DODGE_COOLDOWN := 0.85
const DODGE_SPEED := 620.0
const CARD_DASH_DISTANCE := 82.0
const CARD_DASH_MIN_TIME := 0.14
const CARD_DASH_MAX_TIME := 0.20
const COMBO_WINDOW := 2.25
const CARD_INPUT_BUFFER := 0.18
const CARD_DRAW_SCALE := 1.075
const CARD_DRAW_LIFT := 10.0
const CARD_DRAW_TIME := 0.14

# The dodge stays generous enough for touch, but only its opening beat earns the counter.  This is
# deliberately a reward, not extra immunity: the normal 0.24 s protection is unchanged.
const PERFECT_DODGE_WINDOW := 0.105
const PERFECT_DODGE_ENERGY := 0.70
const PERFECT_DODGE_RIPOSTE_TIME := 4.0
const PERFECT_DODGE_RIPOSTE_MUL := 1.22

# Both compact and streamed effect strips are eight beats with contact on frame four.  Playing all
# eight once for anticipation and then restarting all eight at contact made every cast visibly
# repeat itself; the world now plays the two halves as one continuous attack sentence.
const ABILITY_EFFECT_HIT_FRAME := 4
const FX_MATERIAL_CACHE_HD := 44
const FX_MATERIAL_CACHE_PHONE := 24

# Visible painted-silhouette heights. Rig3D normalizes transparent atlas padding, so these values
# now mean the same thing for a short/wide creature and a tall one.
const PLAYER_RIG_H_M := 1.42
const FOE_RIG_H_M := 1.12
const DARKEON_RIG_H_M := 1.24
const PLAYER_WALK_STRIDE_PX := 72.0
const BOSS_RIG_H_M := 1.62

# Combat nameplates live in the world, not in the screen HUD. Their source textures remain large
# enough for precise HP fills, while the rendered plates are deliberately compact: six simultaneous
# enemies must read as combat information, never as a wall of UI over the arena.
const COMBAT_PLATE_BAR_PX := Vector2i(76, 6)
const COMBAT_PLATE_PLAYER := Color("48bfff")
const COMBAT_PLATE_ENEMY := Color("ff4f68")
const COMBAT_PLATE_BACK := Color(0.025, 0.008, 0.045, 0.94)
const COMBAT_PLATE_FONT_HD := 14
const COMBAT_PLATE_FONT_PHONE := 16
# fixed_size cancels distance, not viewport resolution: one constant that is compact at 720p grows
# to more than twice the intended size on the project's 2880×1600 canvas. Solve pixel_size from the
# current vertical FOV and viewport height so the backplate remains the same screen width everywhere.
const COMBAT_PLATE_SCREEN_WIDTH_HD := 68.0
const COMBAT_PLATE_SCREEN_WIDTH_PHONE := 70.0
const COMBAT_PLATE_FALLBACK_FOV := 42.0

# This is intentionally explicit and visible in the HUD.  Scarcity is an advantage, never a hidden
# die roll: every member of a class receives the same multiplier and element/level remain separate.
const RARITY_STATS := {
	"normal": {"label": "NORMAL", "hp": 1.00, "damage": 1.00, "color": Color("8fd0ff")},
	"legendary": {"label": "LEGENDARY", "hp": 1.15, "damage": 1.15, "color": Color("ffc96a")},
	"meme": {"label": "MEME DYNASTY", "hp": 1.25, "damage": 1.25, "color": Color("ff86cf")},
}

const CORRUPTIMONS := ["darkeet", "shadowisp", "hogwert", "darkeon"]
const WAVE_ELEMENTS := ["Water", "Beast", "Storm", "Fire", "Light"]
const WAVE_TITLES := [
	"DROWNED SANCTUM", "FANG SANCTUM", "TEMPEST SANCTUM", "FURNACE SANCTUM",
	"GRIMWICK'S ECLIPSE",
]
const ARCHES := [
	"strike", "blast", "quick", "guard", "charge", "drain",
	"nova", "rend", "jolt", "rally", "wither", "bulwark",
]

const ACTIONS := {
	"strike": "forward cleave · reliable close hit",
	"blast": "seeking ember · explosive area hit",
	"quick": "invulnerable lunge · combo starter",
	"guard": "short parry · converts impact to energy",
	"charge": "restore energy · empower the next hit",
	"drain": "seeking tether · restores health on hit",
	"nova": "radial panic burst · clears enemy shots",
	"rend": "wide slash · bleed and armor crack",
	"jolt": "piercing bolt · stun and energy refund",
	"rally": "timed damage, speed and energy surge",
	"wither": "seeking curse · slow and weaken",
	"bulwark": "long shield · defensive shockwave",
}

# Five authored combat chambers on one continuous route. The larger sanctums leave readable dodge
# lanes around six actors; the connecting wings remain playable between fights.
const ARENAS := [
	{"element": "Water", "center": Vector2(-480.0, 520.0), "rect": Rect2(-880.0, 210.0, 800.0, 620.0)},
	{"element": "Beast", "center": Vector2(-480.0, 980.0), "rect": Rect2(-880.0, 670.0, 800.0, 620.0)},
	{"element": "Storm", "center": Vector2(2880.0, 980.0), "rect": Rect2(2480.0, 670.0, 800.0, 620.0)},
	{"element": "Fire", "center": Vector2(2880.0, 520.0), "rect": Rect2(2480.0, 210.0, 800.0, 620.0)},
	{"element": "Light", "center": Vector2(1200.0, 670.0), "rect": Rect2(400.0, 195.0, 1600.0, 950.0)},
]

# Three short reinforcement beats per sanctum feel authored and leave recovery windows. The
# director never exceeds six live foes on desktop or phone.
const WAVE_PACKS := [
	[["darkeet", "darkeet", "shadowisp", "darkeet", "hogwert"],
		["shadowisp", "darkeet", "hogwert", "shadowisp"],
		["hogwert", "darkeon", "darkeet", "shadowisp", "darkeet"]],
	[["darkeet", "hogwert", "darkeet", "hogwert", "shadowisp"],
		["hogwert", "shadowisp", "hogwert", "darkeet", "darkeon"],
		["darkeon", "hogwert", "darkeon", "shadowisp", "hogwert"]],
	[["shadowisp", "shadowisp", "darkeet", "shadowisp", "darkeet"],
		["shadowisp", "darkeon", "shadowisp", "hogwert", "darkeet"],
		["darkeon", "shadowisp", "darkeon", "hogwert", "shadowisp"]],
	[["darkeet", "hogwert", "darkeet", "shadowisp", "hogwert"],
		["hogwert", "darkeon", "shadowisp", "hogwert", "darkeet"],
		["darkeon", "hogwert", "darkeon", "shadowisp", "hogwert"]],
	[["shadowisp", "darkeet", "darkeon", "shadowisp", "darkeet"],
		["darkeon", "hogwert", "shadowisp", "darkeon", "hogwert"],
		["darkeon", "shadowisp", "hogwert"]],
]

var _roster: Array = []
var _selected_unit: Dictionary = {}
var _entered := false
var _started := false
var _stage_over := false
var _win := false
var _wave := -1
var _wave_phase := "idle" # idle | prep | fight | reinforce | clear | travel | done
var _wave_t := 0.0
var _run_t := 0.0
var _arena_rect := Rect2()
var _arena_center := Vector2.ZERO
var _wave_start_kills := 0
var _results: Array = []
var _pack_at := 0
var _pack_spawn_t := 0.0
var _wave_spawned := 0
var _travel_target := Vector2.ZERO
var _travel_marker: Node3D = null

var _hp := 100.0
var _max_hp := 100.0
var _shield := 0.0
var _energy := ENERGY_MAX
var _invuln_t := 0.0
var _parry_t := 0.0
var _dodge_t := 0.0
var _dodge_cd := 0.0
var _dodge_dir := Vector2.UP
var _damage_taken := 0.0

var _card_page := 0
var _card_at := 0
var _card_slots: Array = []
var _card_cooldowns := {}
var _card_texture_cache := {}
var _card_preview_texture_cache := {}
var _attack_cd := 0.0
var _empower_mul := 1.0
var _rally_t := 0.0
var _rally_mul := 1.0
var _heal_bank := 0.0
var _recoil_bank := 0.0
var _card_buffer_t := 0.0
var _buffered_card_at := -1
var _perfect_dodge_t := 0.0
var _perfect_dodge_claimed := false
var _riposte_t := 0.0
var _player_hit_flash := 0.0

var _score := 0
var _kills := 0
var _combo := 0
var _best_combo := 0
var _combo_t := 0.0
var _chain_arches: Array = []
var _cards_used: Array = []
var _species_trait: Dictionary = {}
var _trait_proc_ids: Array = []
var _trait_procs := 0
var _debug_casting := false
var _pending_cast: Dictionary = {}
var _card_dash: Dictionary = {}
var _last_visual_profile: Dictionary = {}
var _ability_art_stream: Node = null

var _foe_cap := MAX_FOES
var _projectile_cap := MAX_PROJECTILES
var _effect_cap := MAX_EFFECTS
# FEEL. Hit-stop freezes the FIGHT for a few hundredths of a second on a heavy landing — enemies,
# projectiles and effects hold, the HUD and camera do not — which is the single cheapest thing that
# makes a hit feel like it connected. Impact lights are a tiny fixed pool of OmniLight3D flashes on
# the HD tier only; the phone tier's whole design is "no combat lights", and that stays true.
var _hitstop_t := 0.0
var _impact_lights: Array = []
var _fx_materials: Dictionary = {}     # Texture2D -> the additive material bound to it
var _fx_material_lru: Array = []
var _floater_cap := MAX_FLOATERS
var _enemy_pool: Array = []
var _projectile_pool: Array = []
var _effect_pool: Array = []
var _floater_pool: Array = []
var _status_pool: Array = []
var _status_clock := 0.0
var _player_status_profiles: Dictionary = {}
var _boss: Dictionary = {}
var _boss_telegraph: MeshInstance3D = null
var _player_nameplate: Dictionary = {}
var _boss_nameplate: Dictionary = {}
var _combat_plate_texture: Texture2D = null
var _combat_plate_tick := 0.0

var _circle_tex: Texture2D = null
var _orb_tex: Texture2D = null
var _next_attack_id := 1
var _rng := RandomNumberGenerator.new()

var _hud_layer: CanvasLayer = null
var _energy_row: Label = null
var _pack_dots: Label = null           # pack progress as dots, not "PACK 1/3"
var _fighter_plate: PanelContainer = null
var _wave_plate: PanelContainer = null
var _score_plate: PanelContainer = null
var _wave_accent: Control = null
var _deck_accent: Control = null
var _preview_accent: Control = null
var _score_accent: Control = null
var _utility_accent: Control = null
var _message_accent: Control = null
var _hud_font_cache := {}
var _hud_root: Control = null
var _hp_bar: ProgressBar = null
var _hp_label: Label = null
var _hp_digits_t := 0.0        # seconds the HP digits stay legible after they move
var _hp_shown := -1.0
var _unit_label: Label = null
var _rarity_label: Label = null
var _wave_label: Label = null
var _remaining_label: Label = null
var _score_label: Label = null
var _run_status_label: Label = null
var _vitality: Control = null       # the bottom-left health block
var _target_holder: Control = null  # the engaged enemy's bar
var _plinth: Control = null
var _sel_card_label: Label = null
var _sockets: Array = []
var _energy_icon: TextureRect = null
var _energy_label: Label = null
var _card_preview: Panel = null
var _card_preview_art: TextureRect = null
var _card_preview_name: Label = null
var _card_preview_detail: Label = null
var _preview_hover_index := -1
var _preview_focus_index := -1
var _card_draw_tweens := {}
var _message_label: Label = null
var _target_bar: ProgressBar = null
var _target_label: Label = null
var _hud_target_eid := -1
var _card_hud: Array = []
var _page_button: Button = null
var _dodge_button: Button = null
var _camera_button: Button = null
var _exit_button: Button = null
var _settings_button: Button = null
var _cycle_button: Button = null
var _move_panel: Panel = null
var _mobile_deck_clip: Control = null
var _mobile_intro_t := 4.2
var _mobile_options_t := 0.0
var _utility_rail: Control = null
var _controls_overlay: PanelContainer = null
var _controls_overlay_label: Label = null
var _controls_overlay_token := 0
var _controls_overlay_pinned := false
var _hud_tick := 0.0
var _hud_cards_stamp := ""
var _message_t := 0.0

var _touch_move_id := -1
var _touch_move := Vector2.ZERO
const TOUCH_CARD_HOLD_SECONDS := 0.38
const TOUCH_OWNER_LIMIT := 10
var _touch_owners := {}
var _touch_serial := 0
var _touch_inspect_id := -1
var _touch_inspect_index := -1
var _mobile_preview_draw_tween: Tween = null
var _mobile_preview_draw_index := -1
var _zoom_tactical := false
var _zoom_dist := CAM_DIST
var _cam_aim := Vector3.ZERO
var _cam_travel_lead := Vector2.ZERO
var _cam_last_player_plane := Vector2.ZERO
var _audio_pool: Array[AudioStreamPlayer] = []
var _audio_at := 0


# ================================= public stage contract ======================================
func _ensure_ability_art_stream() -> void:
	if _ability_art_stream != null and is_instance_valid(_ability_art_stream):
		return
	var existing: Node = get_node_or_null("TempleAbilityArtStream")
	if existing != null:
		_ability_art_stream = existing
	else:
		_ability_art_stream = AbilityArtStream.new() as Node
		if _ability_art_stream == null:
			return
		_ability_art_stream.name = "TempleAbilityArtStream"
		add_child(_ability_art_stream)
	var ready_callback := Callable(self, "_on_ability_art_ready")
	if _ability_art_stream.has_signal("asset_ready") \
			and not _ability_art_stream.is_connected("asset_ready", ready_callback):
		_ability_art_stream.connect("asset_ready", ready_callback)


func _on_ability_art_ready(owner_key: String, kind: String) -> void:
	if _rig == null or not is_instance_valid(_rig) or not _rig.has_method("refresh_streamed_art"):
		return
	var species := _species()
	if (kind == "locomotion" and owner_key == species) \
			or (kind == "body" and owner_key.begins_with(species + ":")):
		_rig.call("refresh_streamed_art")


func _visible_card_profiles() -> Array:
	var profiles: Array = []
	for value in _page_indices():
		var index := int(value)
		if index < 0 or index >= _card_slots.size():
			continue
		var profile := AbilityVisual.profile(_species(), int(_card_slots[index]))
		if not profile.is_empty():
			profiles.append(profile)
	return profiles


func _prefetch_visible_card_art() -> void:
	_ensure_ability_art_stream()
	if _ability_art_stream == null or not is_instance_valid(_ability_art_stream):
		return
	_ability_art_stream.call("prefetch_profiles", _visible_card_profiles())


func _queue_profile_art(profile: Dictionary, urgent: bool = false) -> void:
	if profile.is_empty():
		return
	_ensure_ability_art_stream()
	if _ability_art_stream == null or not is_instance_valid(_ability_art_stream):
		return
	_ability_art_stream.call("queue_profile", profile, urgent)


func _ability_art_stream_status() -> Dictionary:
	if _ability_art_stream == null or not is_instance_valid(_ability_art_stream):
		return {"node_alive": false}
	var raw: Variant = _ability_art_stream.call("status")
	if raw is Dictionary:
		var report: Dictionary = (raw as Dictionary).duplicate(true)
		report["node_alive"] = true
		return report
	return {"node_alive": true, "status": String(raw)}


func set_party(units: Array) -> void:
	# Temple.gd intentionally supplies the roster before enter().  Cache it; the legacy base method
	# expects `_actors` to exist and would otherwise discard this exact call.
	_roster.clear()
	for value in units:
		if not (value is Dictionary):
			continue
		var src := value as Dictionary
		var species := String(src.get("species", "")).to_lower()
		var uid := String(src.get("uid", ""))
		if species == "" or uid == "":
			continue
		var unit := src.duplicate(true)
		unit["species"] = species
		unit["uid"] = uid
		var kind := String(unit.get("kind", Econ.unit_kind(species))).to_lower()
		unit["kind"] = kind if RARITY_STATS.has(kind) else Econ.unit_kind(species)
		unit["level"] = clampi(int(unit.get("level", 1)), 1, Econ.LEVEL_CAP)
		_roster.append(unit)
	# The world admits one creature.  A singleton passed by the chooser is authoritative; otherwise
	# the first fit party member is a deterministic fallback.
	if not _roster.is_empty() and (not _started or _selected_unit.is_empty()):
		_selected_unit = (_roster[0] as Dictionary).duplicate(true)


func select_unit(uid: String) -> bool:
	if _started:
		return false
	for value in _roster:
		var unit := value as Dictionary
		if String(unit.get("uid", "")) == uid:
			_selected_unit = unit.duplicate(true)
			return true
	return false


func enter(avatar_id: String) -> void:
	if _selected_unit.is_empty():
		# Honest playable fallback for malformed probes: still a Chikimon, never the trainer avatar.
		_selected_unit = {"uid": "temple_guest", "species": "firix", "kind": "normal", "level": 1}
	_rng.seed = hash("wicked-horde:" + String(_selected_unit.get("uid", "guest")))
	_reset_run_state()
	super.enter(avatar_id)
	_entered = true
	var resize_callback := Callable(self, "_on_horde_viewport_size_changed")
	if not get_viewport().size_changed.is_connected(resize_callback):
		get_viewport().size_changed.connect(resize_callback)
	_build_runtime_pools()
	_build_hud()
	_refresh_hud(true)
	_prefetch_visible_card_art()
	creature_changed.emit(String(_selected_unit.get("uid", "")))


func _on_horde_viewport_size_changed() -> void:
	_cancel_mobile_gestures()
	# Reproject immediately instead of waiting for the 50 ms combat tick; otherwise a browser
	# rotation/maximize can flash the old resolution's giant fixed-size quads for one frame.
	_refresh_combat_nameplates()
	if _hud_root != null and is_instance_valid(_hud_root):
		_layout_hud()


func _exit_tree() -> void:
	MobileRender.release(get_viewport())


func start_stage(party: Array = []) -> void:
	if not party.is_empty() and not _entered:
		set_party(party)
	if not _entered:
		enter("classic")
	if _started:
		return
	_started = true
	_mobile_intro_t = 4.2
	_mobile_options_t = 0.0
	_stage_over = false
	_run_t = 0.0
	_results.clear()
	for i in WAVE_TOTAL:
		_results.append(_blank_result(i))
	# Begin two creature-cells inside the threshold. At SPAWN the creature's feet sit immediately
	# behind the 3.2 m entrance cap, so correct depth testing hides most of the sprite from the
	# trailing horde camera. This is still the entrance procession, with enough floor for the whole
	# painted silhouette to clear the portal before the player takes control.
	_ppos = SPAWN + Vector2(0.0, -248.0)
	_plast = _ppos
	_face_dir = Vector2.UP
	_rig_call("face", _face_dir)
	_sync_player()
	_cam_ready = false
	# The run uses the real connected world. No arena teleport: the first objective rune teaches
	# traversal before the first corruption pack awakens.
	_wave = -1
	_begin_travel()


func set_input_enabled(on: bool) -> void:
	_input_on = on and not _stage_over
	if not _input_on:
		_cancel_mobile_gestures()
		super.set_input_enabled(false)
	else:
		super.set_input_enabled(true)


# This hall's camera pitch — ONE constant, read by both the camera solve and the base class's rig
# builder through _rig_pitch_deg(), so the billboard pre-stretch can never drift from the camera.
const HORDE_PITCH_DEG := 35.0
const HORDE_CAM_POSITION_DECAY := 9.0
const HORDE_CAM_AIM_DECAY := 11.5
const HORDE_CAM_LEAD_DECAY := 7.5

func _rig_pitch_deg() -> float:
	return HORDE_PITCH_DEG


func is_3d() -> bool:
	return true


func _show_decorative_sanctum_seals() -> bool:
	return false


func action_manifest() -> Dictionary:
	return ACTIONS.duplicate(true)


func rarity_stats(kind: String) -> Dictionary:
	return (RARITY_STATS.get(kind.to_lower(), RARITY_STATS["normal"]) as Dictionary).duplicate(true)


func touch_rects() -> Dictionary:
	var size := get_viewport().get_visible_rect().size
	var phone := _phone_hud_active()
	var layout := _mobile_layout() if phone else {}
	var rects: Dictionary = layout["rects"] if phone else _touch_rects_for(size, false)
	# Containers round fractional backing pixels. Input follows the actual settled painted slot,
	# not a second idealized rectangle that can drift by a pixel at each card/spacing boundary.
	# The pure layout remains the positioning authority; never feed these measured bounds into it.
	if _hud_root != null and is_instance_valid(_hud_root):
		for i in range(_card_hud.size()):
			var slot := (_card_hud[i] as Dictionary).get("slot") as Control
			if slot != null and slot.size.x > 1.0 and slot.is_visible_in_tree():
				rects["card_%d" % i] = slot.get_global_rect()
		for pair in [[_page_button, "page"], [_settings_button, "settings"],
			[_camera_button, "camera"], [_exit_button, "exit"], [_dodge_button, "dodge"],
			[_move_panel, "move"], [_cycle_button, "cycle"]]:
			var control := pair[0] as Control
			if control != null and control.size.x > 1.0 and control.is_visible_in_tree() and rects.has(pair[1]):
				rects[pair[1]] = control.get_global_rect()
			elif phone and rects.has(pair[1]):
				rects.erase(pair[1])
	if phone:
		# A concealed sliver is not an invisible button. Keep the exposed part of each card
		# at least 44 CSS px wide, matching the actual right-edge clipping mask.
		var clip := layout["deck_clip"] as Rect2
		for i in range(3):
			var key := "card_%d" % i
			if rects.has(key):
				rects[key] = (rects[key] as Rect2).intersection(clip)
	return rects


func _mobile_layout() -> Dictionary:
	var display := MobileViewport.sample(get_viewport())
	return MobileLayout.compute(get_viewport().get_visible_rect().size,
		display["css_size"] as Vector2, display["safe_insets"] as Vector4)


func debug_mobile_layout(logical: Vector2, css: Vector2, safe: Vector4 = Vector4.ZERO) -> Dictionary:
	return MobileLayout.compute(logical, css, safe)


func debug_touch_rects_for(size: Vector2) -> Dictionary:
	return _touch_rects_for(size, true)


func _hud_narrow_canvas_boost(size: Vector2, phone: bool) -> float:
	# With canvas_items + expand, a tall/narrow desktop browser keeps the 1600 logical width and
	# grows the logical height. The canvas then scales down to the 903px panel: uncorrected 16px HUD
	# type becomes roughly 9px and an enlarged card becomes smaller than its old desktop version.
	# Phones already have their own measured logical/CSS profile, so only compensate the expanded
	# desktop canvas. The cap keeps a portrait-ish window from turning the hand into a modal.
	if phone or size.x < 1200.0 or size.y <= size.x * 0.70:
		return 1.0
	return clampf(size.y / 900.0, 1.0, 1.35)


# ==============================================================================================
# THE HUD'S PLACEMENT, AND THE REASONING BEHIND IT.
# ==============================================================================================
# The first layout put the three ability cards in the bottom-RIGHT corner at 86 x 124 px, with the
# DECK page button to their left, DODGE next to the move stick bottom-left, and EXIT/TACTIC in a row
# top-right. On a phone the cards then sat under EXIT and TACTIC, the thing you press most was the
# smallest thing on screen, and the energy that gates every card was a text string in the opposite
# corner from the cards it gates.
#
# The deck is now a centred command hand. Movement remains bottom-left, dodge bottom-right, and the
# three card faces sit bottom-centre where either eye can acquire them without leaving the fight.
# Energy lives in the same plinth, but uses Chikoria's existing essence icon plus both a number and
# four charge sockets. Utility actions are explicit, separated buttons at the top-right.
#
# The probe's contract is unchanged: same keys, every target >= 44 CSS px on the phone, no target
# overlaps another, the status and message bands never cover a target, and the centre of the
# screen stays a gameplay-safe window at least 35% wide and 28% tall.
func _touch_rects_for(size: Vector2, phone: bool) -> Dictionary:
	if phone:
		return MobileLayout.compute(size, size)["rects"]
	# One geometry authority drives render, hit-test, and test metrics. Artwork rectangles contain
	# artwork only; key, energy, and recovery state live in each card's external status foot.
	var margin := 14.0 if phone else 22.0
	var touch := PHONE_TOUCH_LOGICAL if phone else 54.0
	var boost := _hud_narrow_canvas_boost(size, phone)
	var gap := 8.0 if phone else (9.0 if size.x < 1050.0 else 11.0 * boost)
	# Desktop art is still a substantial 112x168 physical px at 1280x720, but its complete dock is
	# now only 205 physical px tall. The former 200px-tall art plus a 77px header/footer began at
	# y=430 and covered the controlled Chikimon from its chest down. Phone uses a larger square icon
	# channel so the three cards land near 96 CSS px apiece in the shipped 0.585 profile.
	var card_w := clampf(size.x * 0.10, 144.0, 158.0) if phone else clampf(
		size.y * 0.156, 140.0 * boost, 142.0 * boost)
	if not phone:
		var width_floor := 118.0 if size.x < 840.0 else 140.0 * boost
		card_w = clampf(minf(card_w, (size.x * 0.58 - gap * 2.0) / 3.0),
			width_floor, 142.0 * boost)
	var card_h := card_w if phone else card_w * 1.5
	var pad_x := 12.0 if phone else 14.0 * boost
	var pad_top := 0.0 if phone else 1.0 * boost
	var pad_bottom := 0.0
	# The bundled display font has a 39 px logical line box at the phone's readable 24 px face.
	# Budget the real line box rather than letting the VBox silently overflow past the viewport.
	var energy_h := 40.0 if phone else 25.0 * boost
	var state_h := 40.0 if phone else 14.0 * boost
	var stack_gap := 0.0 if phone else 1.0 * boost
	var recovery_h := 4.0 if phone else 3.0 * boost
	var holder_gaps := 0.0 if phone else 2.0 * boost
	var cards_w := card_w * 3.0 + gap * 2.0
	var dock_w := cards_w + pad_x * 2.0
	var dock_h := pad_top + energy_h + stack_gap + card_h + recovery_h + holder_gaps \
		+ state_h + pad_bottom
	var dock_x := (size.x - dock_w) * 0.5
	var dock_y := size.y - margin - dock_h
	var cards_x := dock_x + pad_x
	var cards_y := dock_y + pad_top + energy_h + stack_gap

	var page_w := 90.0 if phone else 106.0 * boost
	var page_h := touch if phone else 54.0 * boost
	var page_x := dock_x + dock_w + 11.0
	if page_x + page_w > size.x - margin:
		page_x = maxf(margin, dock_x - page_w - 11.0)
	var page_y := cards_y + (card_h - page_h) * 0.5

	# Three explicit utility instruments share one top-right rail. At the measured phone scale each
	# target remains at least 44 CSS px, yet their compact copy leaves a real chamber crown between
	# the left run telemetry and the rail.
	var utility_h := touch if phone else 54.0 * boost
	var settings_w := 84.0 if phone else 80.0 * boost
	var tactical_w := 112.0 if phone else 112.0 * boost
	var exit_w := 80.0 if phone else 72.0 * boost
	var utility_gap := 6.0 if phone else 8.0 * boost
	var utility_y := 8.0 if phone else 12.0
	var utility_w := settings_w + tactical_w + exit_w + utility_gap * 2.0
	var utility_x := size.x - margin - utility_w
	var out := {
		"page": Rect2(page_x, page_y, page_w, page_h),
		"settings": Rect2(utility_x, utility_y, settings_w, utility_h),
		"camera": Rect2(utility_x + settings_w + utility_gap, utility_y,
			tactical_w, utility_h),
		"exit": Rect2(utility_x + settings_w + utility_gap + tactical_w + utility_gap,
			utility_y, exit_w, utility_h),
	}
	if _roster.size() > 1 and OS.get_environment("CHIK_TEMPLE_DEV") == "1":
		out["cycle"] = Rect2(maxf(margin, utility_x - utility_gap - utility_h), utility_y,
			utility_h, utility_h)
	if phone:
		var move_size := clampf(size.y * 0.29, touch, 132.0)
		var dodge_size := maxf(touch, 94.0)
		out["move"] = Rect2(margin, size.y - margin - move_size, move_size, move_size)
		out["dodge"] = Rect2(size.x - margin - dodge_size,
			cards_y + card_h * 0.5 - dodge_size * 0.5, dodge_size, dodge_size)
	for i in range(3):
		out["card_%d" % i] = Rect2(cards_x + float(i) * (card_w + gap), cards_y,
			card_w, card_h)
	return out


# The plinth is derived from the card rects rather than published as a role, because _touch_role
# returns the FIRST rect containing the point: a plinth entry in that table would swallow every
# card press.
func _plinth_rect(rects: Dictionary, phone: bool, layout_size: Vector2 = Vector2.ZERO) -> Rect2:
	if phone:
		var c0 := rects["card_0"] as Rect2
		var c2 := rects["card_2"] as Rect2
		var page := rects["page"] as Rect2
		var unit := page.size.y / 44.0
		return Rect2(c0.position.x, page.position.y, c2.end.x - c0.position.x,
			c0.end.y + 24.0 * unit - page.position.y)
	var c0 := rects["card_0"] as Rect2
	var c2 := rects["card_2"] as Rect2
	var inferred_width := c0.position.x + c2.end.x
	var size := layout_size if layout_size != Vector2.ZERO else Vector2(
		inferred_width, get_viewport().get_visible_rect().size.y)
	var boost := _hud_narrow_canvas_boost(size, phone)
	var pad_x := 12.0 if phone else 14.0 * boost
	var pad_top := 0.0 if phone else 1.0 * boost
	var pad_bottom := 0.0
	var energy_h := 40.0 if phone else 25.0 * boost
	var state_h := 40.0 if phone else 14.0 * boost
	var stack_gap := 0.0 if phone else 1.0 * boost
	var recovery_h := 4.0 if phone else 3.0 * boost
	var holder_gaps := 0.0 if phone else 2.0 * boost
	return Rect2(c0.position.x - pad_x,
		c0.position.y - (pad_top + energy_h + stack_gap),
		(c2.end.x - c0.position.x) + pad_x * 2.0,
		pad_top + pad_bottom + energy_h + stack_gap + c0.size.y + recovery_h \
			+ holder_gaps + state_h)


func _score_rect_for(size: Vector2, phone: bool) -> Rect2:
	if phone:
		return Rect2()
	var margin := 14.0 if phone else 22.0
	var stage := _wave_rect_for(size, phone, _touch_rects_for(size, phone))
	var width := 190.0 if phone or size.x < 1050.0 else 210.0
	var height := 88.0 if phone else 64.0 * _hud_narrow_canvas_boost(size, phone)
	return Rect2(stage.end.x + (10.0 if phone else 12.0), stage.position.y, width, height)


func _wave_rect_for(size: Vector2, phone: bool, rects: Dictionary) -> Rect2:
	if phone:
		var unit := (rects["exit"] as Rect2).size.y / 44.0
		var at := (rects["move"] as Rect2).position.x
		var y := (rects["exit"] as Rect2).position.y
		return Rect2(at, y, minf(300.0 * unit,
			(rects["settings"] as Rect2).position.x - at - 8.0 * unit), 44.0 * unit)
	# Stage progress begins at the reading edge instead of spanning the arena like a boss banner.
	# Score follows it as a quiet companion plate; utility actions own the opposite corner.
	var margin := 14.0 if phone else 22.0
	var utility_left := (rects["settings"] as Rect2).position.x
	var score_w := 190.0 if phone or size.x < 1050.0 else 210.0
	var gaps := (10.0 if phone else 12.0) + score_w + (10.0 if phone else 16.0)
	var desired := clampf(size.x * (0.27 if phone else 0.30),
		300.0 if phone else 290.0, 400.0 if phone else 430.0)
	var width := minf(desired, maxf(220.0, utility_left - margin - gaps))
	return Rect2(margin, 8.0 if phone else 12.0, width,
		88.0 if phone else 64.0 * _hud_narrow_canvas_boost(size, phone))


func _css_per_logical() -> float:
	return float(MobileViewport.sample(get_viewport())["css_per_logical"])


func debug_hud_metrics(size: Vector2 = Vector2.ZERO) -> Dictionary:
	if size != Vector2.ZERO or _phone_hud_active():
		var layout := MobileLayout.compute(size, size) if size != Vector2.ZERO else _mobile_layout()
		var rects := layout["rects"] as Dictionary
		var logical := size if size != Vector2.ZERO else get_viewport().get_visible_rect().size
		var wave := layout["wave"] as Rect2
		var deck := layout["plinth"] as Rect2
		var persistent := {"top_strip": wave, "plinth": deck,
			"move": rects["move"], "dodge": rects["dodge"], "deck": rects["page"],
			"settings": rects["settings"], "camera": rects["camera"], "exit": rects["exit"]}
		var centre := Rect2(logical * 0.25, logical * 0.5)
		var intruders := []
		var area := 0.0
		for key in persistent:
			var rect := persistent[key] as Rect2
			if centre.intersects(rect):
				intruders.append(key)
			# Deck page is inside the dock header, not an additional painted area.
			if key != "deck":
				area += rect.size.x * rect.size.y
		return {"css_per_logical": layout["css_scale"], "font_logical": layout["font_logical"],
			"font_css": layout["font_css"], "top_rect": wave, "message_rect": layout["message"],
			"game_safe_rect": Rect2(0.0, wave.end.y, logical.x, maxf(1.0, deck.position.y - wave.end.y)),
			"logical_size": logical, "persistent": persistent, "centre_rect": centre,
			"centre_intruders": intruders, "hud_coverage": area / maxf(1.0, logical.x * logical.y),
			"preview_rect": layout["preview"], "safe_rect": layout["safe_rect"]}
	# PASSING A SIZE MEANS "MEASURE THE PHONE LAYOUT AT THIS SIZE". The phone's LOGICAL viewport is
	# 1442x667 at 0.585 CSS/logical — taller than 560 — so phone-ness cannot be inferred from the
	# number. Pass nothing to measure whatever the live viewport actually is.
	var logical := size if size != Vector2.ZERO else get_viewport().get_visible_rect().size
	var phone := size != Vector2.ZERO or _low or logical.y < 560.0
	var css_scale := PHONE_CSS_PER_LOGICAL if phone else 1.0
	var font_logical: Dictionary = PHONE_FONTS.duplicate(true) if phone else {
		"unit": 19, "rarity": 12, "hp": 12, "wave": 21, "remaining": 13,
		"target": 11, "score": 18, "energy": 14, "message": 20,
		"card_name": 10, "card_footer": 13, "button": 16, "move": 11,
	}
	var narrow_boost := _hud_narrow_canvas_boost(logical, phone)
	if narrow_boost > 1.0:
		for key in font_logical:
			font_logical[key] = roundi(float(font_logical[key]) * narrow_boost)
	var font_css := {}
	for key in font_logical:
		font_css[key] = float(font_logical[key]) * css_scale
	var rects := _touch_rects_for(logical, phone)
	var plinth := _plinth_rect(rects, phone, logical)
	# Creature vitality is authored once above the creature. The screen HUD reports only stage,
	# score, utility, and the command hand, leaving the arena centre entirely to combat.
	var wave_rect := _wave_rect_for(logical, phone, rects)
	var score_rect := _score_rect_for(logical, phone)
	var top_rect := wave_rect.merge(score_rect)
	# Transient feedback stays tucked below the left status plates, never across the fighter lane.
	var message_h := 46.0 if phone else 34.0 * narrow_boost
	var message_w := minf(330.0 if phone else 300.0 * narrow_boost, logical.x * 0.25)
	var message_rect := Rect2(wave_rect.position.x, top_rect.end.y + 8.0,
		message_w, message_h)
	var safe_top := top_rect.end.y + 8.0
	var game_safe_rect := Rect2(0.0, safe_top, logical.x, maxf(1.0, plinth.position.y - safe_top - 8.0))

	# Persistent HUD stays outside the centre half. Numeric energy and wave values are deliberately
	# redundant with icon/sockets and progress dots so the state remains readable without colour.
	var centre := Rect2(logical.x * 0.25, logical.y * 0.25, logical.x * 0.5, logical.y * 0.5)
	var persistent := {"top_strip": wave_rect, "score": score_rect,
		"plinth": plinth, "deck": rects["page"] as Rect2,
		"settings": rects["settings"] as Rect2, "exit": rects["exit"] as Rect2,
		"camera": rects["camera"] as Rect2}
	if rects.has("move"):
		persistent["move"] = rects["move"] as Rect2
		persistent["dodge"] = rects["dodge"] as Rect2
	var centre_intruders := []
	for key in persistent:
		if centre.intersects(persistent[key] as Rect2):
			centre_intruders.append(key)
	var hud_area := 0.0
	for key in persistent:
		var r := persistent[key] as Rect2
		hud_area += r.size.x * r.size.y
	return {"css_per_logical": css_scale, "font_logical": font_logical,
		"font_css": font_css, "top_rect": top_rect, "message_rect": message_rect,
		"game_safe_rect": game_safe_rect, "logical_size": logical,
		"persistent": persistent, "centre_rect": centre, "centre_intruders": centre_intruders,
		"hud_coverage": hud_area / maxf(1.0, logical.x * logical.y)}


func _player_screen_norm() -> Vector2:
	if _cam == null or not is_instance_valid(_cam):
		return Vector2(-1.0, -1.0)
	var size := get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector2(-1.0, -1.0)
	var chest := px2m(_ppos, CAM_AIM_Y)
	if _cam.is_position_behind(chest):
		return Vector2(-1.0, -1.0)
	var screen := _cam.unproject_position(chest)
	return Vector2(screen.x / size.x, screen.y / size.y)


func _player_screen_is_safe(point: Vector2) -> bool:
	return point.x >= 0.12 and point.x <= 0.88 and point.y >= 0.18 and point.y <= 0.72


func debug_camera_metrics() -> Dictionary:
	if _cam == null or not is_instance_valid(_cam):
		return {}
	var prior_tactical := _zoom_tactical
	var prior_dist := _zoom_dist
	var prior_ready := _cam_ready
	var prior_pos := _cam_pos
	var prior_aim := _cam_aim
	var prior_lead := _cam_travel_lead
	var prior_last_plane := _cam_last_player_plane
	var prior_transform := _cam.global_transform
	var out := {}
	for tactical in [false, true]:
		_zoom_tactical = tactical
		_zoom_dist = _camera_target_dist()
		_cam_ready = false
		_cam_last_player_plane = _ppos
		_tick_cam(1.0)
		var point := _player_screen_norm()
		out["tactical" if tactical else "close"] = {"player_screen_norm": point,
			"player_screen_safe": _player_screen_is_safe(point), "distance": _zoom_dist}
	_zoom_tactical = prior_tactical
	_zoom_dist = prior_dist
	_cam_ready = prior_ready
	_cam_pos = prior_pos
	_cam_aim = prior_aim
	_cam_travel_lead = prior_lead
	_cam_last_player_plane = prior_last_plane
	_cam.global_transform = prior_transform
	return out


func _debug_camera_reversal_sample(fps: int) -> Dictionary:
	var frame_count := maxi(1, fps)
	var delta := 1.0 / float(frame_count)
	var speed_px := 240.0
	var lead_length := 52.0 if _low else 68.0
	_wave = -1
	_wave_phase = "travel"
	_arena_rect = Rect2()
	_travel_target = Vector2.ZERO
	_zoom_tactical = false
	_zoom_dist = _camera_target_dist()
	_ppos = Vector2(1000.0, 500.0)
	_face_dir = Vector2.LEFT
	_cam_ready = false
	_cam_last_player_plane = _ppos
	_tick_cam(delta)
	_face_dir = Vector2.RIGHT
	var first_aim_step := 0.0
	var first_position_step := 0.0
	var first_lead_x := 0.0
	for i in range(frame_count):
		var before_aim := _cam_aim
		var before_pos := _cam_pos
		_ppos += Vector2.RIGHT * speed_px * delta
		_tick_cam(delta)
		if i == 0:
			first_aim_step = before_aim.distance_to(_cam_aim)
			first_position_step = before_pos.distance_to(_cam_pos)
			first_lead_x = _cam_travel_lead.x
	return {"fps": frame_count, "aim": _cam_aim, "position": _cam_pos,
		"first_aim_step": first_aim_step, "first_position_step": first_position_step,
		"first_lead_x": first_lead_x, "settled_lead_x": _cam_travel_lead.x,
		"raw_reversal_span_m": lead_length * 2.0 * PX2M}


func debug_camera_reversal_probe() -> Dictionary:
	if _cam == null or not is_instance_valid(_cam):
		return {"available": false}
	var prior_wave := _wave
	var prior_phase := _wave_phase
	var prior_rect := _arena_rect
	var prior_target := _travel_target
	var prior_ppos := _ppos
	var prior_face := _face_dir
	var prior_tactical := _zoom_tactical
	var prior_dist := _zoom_dist
	var prior_ready := _cam_ready
	var prior_pos := _cam_pos
	var prior_aim := _cam_aim
	var prior_lead := _cam_travel_lead
	var prior_last_plane := _cam_last_player_plane
	var prior_transform := _cam.global_transform

	var sample_30 := _debug_camera_reversal_sample(30)
	var sample_120 := _debug_camera_reversal_sample(120)
	var aim_30 := sample_30.get("aim", Vector3.ZERO) as Vector3
	var aim_120 := sample_120.get("aim", Vector3.ZERO) as Vector3
	var pos_30 := sample_30.get("position", Vector3.ZERO) as Vector3
	var pos_120 := sample_120.get("position", Vector3.ZERO) as Vector3
	var out := {"available": true, "first_lead_x": float(sample_120["first_lead_x"]),
		"settled_lead_x": float(sample_120["settled_lead_x"]),
		"first_aim_step": float(sample_120["first_aim_step"]),
		"first_position_step": float(sample_120["first_position_step"]),
		"raw_reversal_span_m": float(sample_120["raw_reversal_span_m"]),
		"fps_aim_error": aim_30.distance_to(aim_120),
		"fps_position_error": pos_30.distance_to(pos_120)}

	_wave = prior_wave
	_wave_phase = prior_phase
	_arena_rect = prior_rect
	_travel_target = prior_target
	_ppos = prior_ppos
	_face_dir = prior_face
	_zoom_tactical = prior_tactical
	_zoom_dist = prior_dist
	_cam_ready = prior_ready
	_cam_pos = prior_pos
	_cam_aim = prior_aim
	_cam_travel_lead = prior_lead
	_cam_last_player_plane = prior_last_plane
	_cam.global_transform = prior_transform
	_sync_player()
	return out


func debug_state() -> Dictionary:
	var caps := {"profile": "phone" if _low else "hd", "foes": _foe_cap,
		"projectiles": _projectile_cap, "effects": _effect_cap + _floater_cap}
	var player_screen := _player_screen_norm()
	return {
		"player_species": _species(), "player_uid": String(_selected_unit.get("uid", "")),
		"player_count": 1, "avatar_visible": false, "follower_count": 0,
		"rarity_mult": _rarity_damage(),
		"rarity_hp_mult": _rarity_hp(), "wave": _wave + 1, "wave_total": WAVE_TOTAL,
		"wave_phase": _wave_phase, "active_foes": _active_foes(),
		"foe_cap": _foe_cap, "projectile_count": _active_projectiles(),
		"projectile_cap": _projectile_cap, "effect_count": _active_effects(),
		"effect_cap": _effect_cap + _floater_cap, "hp": _hp, "max_hp": _max_hp,
		"shield": _shield,
		"energy": _energy, "card_page": _card_page, "card_pages": _card_pages(),
		"card_slots": _card_slots.duplicate(), "selected_slot": _active_card_slot(),
		"selected_cooldown": _card_cooldown(_active_card_slot()), "input_enabled": _input_on,
		"score": _score, "combo": _combo, "kills": _kills, "stage_over": _stage_over,
		"won": _win, "player_is_species_rig": _rig != null and is_instance_valid(_rig),
		"caps": caps, "roster_count": _roster.size(), "cycle_enabled": _roster.size() > 1,
		"max_active_foes": MAX_ACTIVE_FOES, "pack": _pack_at, "packs": _wave_pack_count(_wave),
		"queued_foes": _queued_foes(), "travel_target": _travel_target,
		"pending_cast": not _pending_cast.is_empty(),
		"buffered_card": _buffered_card_at, "card_buffer_time": _card_buffer_t,
		"card_dash_active": not _card_dash.is_empty(),
		"card_dash_progress": 0.0 if _card_dash.is_empty() else clampf(
			float(_card_dash.get("elapsed", 0.0)) / maxf(0.001, float(_card_dash.get("duration", 1.0))),
			0.0, 1.0),
		"last_visual_profile": _last_visual_profile.duplicate(true),
		"perfect_dodge_window": _perfect_dodge_t,
		"species_trait": _species_trait.duplicate(), "species_trait_procs": _trait_procs,
		"riposte_time": _riposte_t,
		"riposte_multiplier": PERFECT_DODGE_RIPOSTE_MUL if _riposte_t > 0.0 else 1.0,
		"ability_sprite_cache": AbilitySprites.cache_report(),
		"ability_art_stream": _ability_art_stream_status(),
		"css_per_logical": _css_per_logical(), "player_screen_norm": player_screen,
		"player_screen_safe": _player_screen_is_safe(player_screen),
	}


# Deterministic probes.  These never grant rewards; only the normal completion signal can hand a
# summary to Temple's economy adapter.
func debug_start_wave(index: int) -> void:
	if not _entered:
		enter("classic")
	_started = true
	_stage_over = false
	_start_wave(clampi(index, 0, WAVE_TOTAL - 1))


func debug_complete_wave() -> void:
	_pack_at = _wave_pack_count(_wave)
	_pack_spawn_t = 0.0
	for value in _enemy_pool:
		var e := value as Dictionary
		if bool(e.get("active", false)):
			_defeat_enemy(e, "debug")
	if bool(_boss.get("active", false)):
		_boss["hp"] = 0.0
		_defeat_boss("debug")
	_check_wave_clear()


func debug_select_card(slot: int) -> bool:
	var at := _card_slots.find(slot)
	if at < 0:
		return false
	_card_at = at
	_card_page = int(at / 3.0)
	_refresh_hud(true)
	_prefetch_visible_card_art()
	return true


func debug_cast_card(slot: int = -1) -> bool:
	if slot >= 0 and not debug_select_card(slot):
		return false
	_debug_casting = true
	var cast := _activate_card(true)
	_debug_casting = false
	return cast


func debug_cast_arch(arch: String) -> bool:
	var idx := ARCHES.find(arch)
	return debug_cast_card(idx) if idx >= 0 else false


func debug_probe_card_dash() -> Dictionary:
	# Drive the real dash integrator without resolving combat. The midpoint proves the card moves
	# over time rather than teleporting at release; the endpoint proves its legacy reach is kept.
	var prior_ppos := _ppos
	var prior_face := _face_dir
	var prior_rect := _arena_rect
	var prior_dash := _card_dash.duplicate(true)
	var prior_invuln := _invuln_t
	var prior_stage_over := _stage_over
	var probe_origin := _arena_center
	if probe_origin == Vector2.ZERO:
		probe_origin = Vector2(1200.0, 670.0)
	_ppos = probe_origin
	_face_dir = Vector2.RIGHT
	_arena_rect = Rect2(probe_origin - Vector2(420.0, 320.0), Vector2(840.0, 640.0))
	_stage_over = false
	var profile := {"release": 0.045, "contact": 0.09, "duration": 0.28}
	_begin_card_dash({"arch": "quick", "profile": profile, "target_eid": -1}, {})
	var after_begin := _ppos
	var duration := float(_card_dash.get("duration", 0.0))
	_tick_card_dash(duration * 0.50, false)
	var midpoint := _ppos
	var active_at_midpoint := not _card_dash.is_empty()
	_tick_card_dash(duration * 0.50 + 0.001, false)
	var endpoint := _ppos
	var result := {
		"duration": duration,
		"begin_distance": after_begin.distance_to(probe_origin),
		"mid_distance": midpoint.distance_to(probe_origin),
		"end_distance": endpoint.distance_to(probe_origin),
		"active_at_midpoint": active_at_midpoint,
		"complete": _card_dash.is_empty(),
		"legacy_distance": CARD_DASH_DISTANCE,
	}
	_ppos = prior_ppos
	_face_dir = prior_face
	_arena_rect = prior_rect
	_card_dash = prior_dash
	_invuln_t = prior_invuln
	_stage_over = prior_stage_over
	_sync_player()
	if _rig != null and is_instance_valid(_rig):
		_rig.call("face", _face_dir)
	return result


func debug_cycle_roster() -> bool:
	return _cycle_roster()


func debug_grade(won: bool, elapsed: float, damage: float, max_combo: int) -> String:
	return _grade_for(won, elapsed, damage, max_combo)


func debug_probe_hogwert_charge() -> Dictionary:
	if not _entered:
		enter("classic")
	if _arena_rect.size == Vector2.ZERO:
		_start_wave(0)
	_deactivate_all_enemies()
	_stage_over = false
	_wave_phase = "fight"
	_input_on = true
	var hog: Dictionary = {}
	for value in _enemy_pool:
		var candidate := value as Dictionary
		if String(candidate.get("species", "")) == "hogwert":
			hog = candidate
			break
	if hog.is_empty():
		return {"hits": 0, "swept_hit": false, "hp_delta": 0.0, "second_delta": 0.0}
	var start := _ppos - Vector2(120.0, 0.0)
	_activate_enemy(hog, start, 2)
	hog["awake"] = true; hog["state"] = "charge"; hog["t"] = 0.52
	hog["charge_dir"] = Vector2.RIGHT; hog["charge_hit"] = false; hog["charge_hits"] = 0
	_hp = _max_hp; _shield = 0.0; _invuln_t = 0.0
	var before := _hp
	_tick_enemies(0.65)
	var first_delta := before - _hp
	var endpoint_distance := Vector2(hog["p"]).distance_to(_ppos)
	# Put the same charge back across the player with the latch intact and remove invulnerability.
	# A second hit here would prove the latch is missing rather than merely masked by i-frames.
	hog["p"] = _ppos - Vector2(70.0, 0.0)
	hog["state"] = "charge"; hog["t"] = 0.40; hog["charge_dir"] = Vector2.RIGHT
	_invuln_t = 0.0
	var before_second := _hp
	_tick_enemies(0.40)
	var second_delta := before_second - _hp
	var result := {"hits": int(hog.get("charge_hits", 0)),
		"swept_hit": first_delta > 0.0 and endpoint_distance > 42.0,
		"hp_delta": first_delta, "second_delta": second_delta,
		"latched": is_zero_approx(second_delta), "endpoint_distance": endpoint_distance}
	_deactivate_all_enemies()
	return result


func debug_probe_grimwick_tell() -> Dictionary:
	if not _entered:
		enter("classic")
	_deactivate_all_enemies()
	_deactivate_all_projectiles()
	var arena := ARENAS[4] as Dictionary
	_arena_rect = arena["rect"]
	_arena_center = arena["center"]
	_ppos = _arena_center + Vector2(0.0, 88.0)
	_sync_player()
	_prepare_boss()
	_boss["awake"] = true
	_boss["hp"] = float(_boss["maxhp"]) * 0.40
	_boss["state"] = "idle"; _boss["t"] = 0.0
	_stage_over = false; _wave_phase = "fight"; _input_on = true
	_hp = _max_hp; _shield = 0.0; _invuln_t = 0.0
	var before := _hp
	_tick_boss(0.01)
	var tell_delay := float(_boss.get("tell_total", 0.0))
	_tick_boss(tell_delay * 0.50)
	var early_damage := before - _hp
	_tick_boss(tell_delay * 0.55 + 0.02)
	var resolved_damage := before - _hp
	_invuln_t = 0.0
	var after_resolution := _hp
	_tick_boss(0.10)
	var repeat_damage := after_resolution - _hp
	var result := {"telegraph_delay": tell_delay, "early_damage": early_damage,
		"resolutions": int(_boss.get("resolutions", 0)), "hp_delta": resolved_damage,
		"repeat_damage": repeat_damage, "target_locked": true}
	_deactivate_all_enemies()
	_deactivate_all_projectiles()
	return result


func debug_restart_with(unit: Dictionary) -> bool:
	# Focused tests and the all-assets simulator need a deterministic reset seam.  This never appears
	# in the release HUD and never emits completion/rewards, so it cannot be used to reroll a run.
	_started = false
	set_party([unit])
	if _roster.is_empty():
		return false
	_selected_unit = (_roster[0] as Dictionary).duplicate(true)
	if not _entered:
		enter("classic")
	else:
		_restart_selected_unit()
	return true


func debug_advance(delta: float) -> void:
	_tick_horde(maxf(0.0, delta))


# ================================= inherited player/world bridge ===============================
func _build_player() -> void:
	_player = Node3D.new()
	_player.name = "ChikimonPlayer"
	_player.set_meta("species", _species())
	_actors.add_child(_player)
	_rig = _make_rig("species", _species(), PLAYER_RIG_H_M)
	_rig.name = "PlayerSpeciesRig"
	if _rig.has_method("set_distance_driven_walk"):
		_rig.call("set_distance_driven_walk", true, PLAYER_WALK_STRIDE_PX)
	_player.add_child(_rig)
	_configure_player_visibility()
	_player.add_child(_shadow(0.48))
	_player_nameplate = _make_combat_nameplate(_player, "PlayerCombatNameplate",
		PLAYER_RIG_H_M + 0.22, COMBAT_PLATE_PLAYER, true)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.near = 0.1
	_cam.far = 95.0
	add_child(_cam)
	_cam.current = true


func _replace_player_rig() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _rig != null and is_instance_valid(_rig):
		var old_rig := _rig
		_player.remove_child(old_rig)
		old_rig.queue_free()
	_rig = _make_rig("species", _species(), PLAYER_RIG_H_M)
	_rig.name = "PlayerSpeciesRig"
	if _rig.has_method("set_distance_driven_walk"):
		_rig.call("set_distance_driven_walk", true, PLAYER_WALK_STRIDE_PX)
	_player.add_child(_rig)
	_configure_player_visibility()
	_player.set_meta("species", _species())
	_refresh_combat_nameplates()


func _configure_player_visibility() -> void:
	# Real depth testing is essential in a 3D room: bypassing it made the painted body float through
	# pillars and stairs. Temple3D keeps camera-side walls low, so the player remains readable.
	if _rig == null or not is_instance_valid(_rig):
		return
	for child in _rig.get_children():
		if child is Sprite3D:
			var sprite := child as Sprite3D
			sprite.no_depth_test = false
			sprite.render_priority = 2


func _configure_enemy_visibility(rig: Node3D, priority: int = 7) -> void:
	# Corrupted creatures obey the same depth rules as the player; shadows/telegraphs ground them.
	if rig == null or not is_instance_valid(rig):
		return
	for child in rig.get_children():
		if child is Sprite3D:
			var sprite := child as Sprite3D
			sprite.no_depth_test = false
			sprite.render_priority = clampi(priority - 5, 0, 3)


func _set_rig_combat_flash(rig: Node3D, remaining: float, tint: Color) -> void:
	if rig == null or not is_instance_valid(rig):
		return
	var strength := clampf(remaining / 0.14, 0.0, 1.0)
	var flash := Color.WHITE.lerp(tint, strength * 0.56)
	for child in rig.get_children():
		if child is Sprite3D:
			(child as Sprite3D).modulate = flash


# ================================= world combat nameplates ====================================
func _combat_plate_texture_or_make() -> Texture2D:
	if _combat_plate_texture != null and is_instance_valid(_combat_plate_texture):
		return _combat_plate_texture
	var image := Image.create(COMBAT_PLATE_BAR_PX.x, COMBAT_PLATE_BAR_PX.y, false,
		Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	# A one-pixel chamfer keeps the tiny bar intentional and crisp without another texture/material.
	image.set_pixel(0, 0, Color.TRANSPARENT)
	image.set_pixel(COMBAT_PLATE_BAR_PX.x - 1, 0, Color.TRANSPARENT)
	image.set_pixel(0, COMBAT_PLATE_BAR_PX.y - 1, Color.TRANSPARENT)
	image.set_pixel(COMBAT_PLATE_BAR_PX.x - 1, COMBAT_PLATE_BAR_PX.y - 1,
		Color.TRANSPARENT)
	_combat_plate_texture = ImageTexture.create_from_image(image)
	return _combat_plate_texture


func _make_combat_plate_sprite(node_name: String, tint: Color, priority: int) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = node_name
	sprite.texture = _combat_plate_texture_or_make()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.fixed_size = true
	sprite.shaded = false
	sprite.transparent = true
	sprite.no_depth_test = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sprite.pixel_size = _combat_plate_base_pixel_size()
	sprite.offset = Vector2(0.0, 17.0 if _low else 15.0)
	sprite.modulate = tint
	sprite.render_priority = priority
	return sprite


func _make_combat_nameplate(owner: Node3D, node_name: String, height_m: float,
		tint: Color, player_plate: bool = false) -> Dictionary:
	if owner == null or not is_instance_valid(owner):
		return {}
	var root := Node3D.new()
	root.name = node_name
	root.position.y = height_m
	root.visible = false
	root.set_meta("combat_nameplate", true)
	root.set_meta("plate_role", "player" if player_plate else "enemy")
	root.set_meta("visual_bar_width_px", float(COMBAT_PLATE_BAR_PX.x))
	owner.add_child(root)

	var label := Label3D.new()
	label.name = "IdentityAndHP"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.font_size = COMBAT_PLATE_FONT_PHONE if _low else COMBAT_PLATE_FONT_HD
	label.pixel_size = _combat_plate_base_pixel_size()
	label.outline_size = 4 if _low else 3
	label.modulate = tint
	label.outline_modulate = Color(0.02, 0.005, 0.035, 0.98)
	label.no_depth_test = true
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.offset = Vector2(0.0, -6.0 if _low else -5.0)
	root.add_child(label)

	var back := _make_combat_plate_sprite("HealthTrack", COMBAT_PLATE_BACK, 8)
	back.scale = Vector3(1.04, 1.34, 1.0)
	root.add_child(back)
	var fill := _make_combat_plate_sprite("HealthFill", tint, 9)
	fill.region_enabled = true
	fill.region_rect = Rect2(Vector2.ZERO, Vector2(COMBAT_PLATE_BAR_PX))
	root.add_child(fill)

	var plate := {"root": root, "label": label, "back": back, "fill": fill,
		"tint": tint, "role": "player" if player_plate else "enemy"}
	_apply_combat_plate_projection(plate)
	return plate


func _combat_plate_screen_width() -> float:
	if _phone_hud_active():
		return 52.0 / maxf(0.05, _css_per_logical())
	return COMBAT_PLATE_SCREEN_WIDTH_PHONE if _low else COMBAT_PLATE_SCREEN_WIDTH_HD


func _combat_plate_fov() -> float:
	if _cam != null and is_instance_valid(_cam) and _cam.projection == Camera3D.PROJECTION_PERSPECTIVE:
		return clampf(_cam.fov, 1.0, 179.0)
	return COMBAT_PLATE_FALLBACK_FOV


func _combat_plate_base_pixel_size() -> float:
	var viewport_h := maxf(360.0, get_viewport().get_visible_rect().size.y)
	var projection_span := 2.0 * tan(deg_to_rad(_combat_plate_fov()) * 0.5)
	return _combat_plate_screen_width() * projection_span \
		/ (float(COMBAT_PLATE_BAR_PX.x) * viewport_h)


func _apply_combat_plate_projection(plate: Dictionary) -> void:
	if plate.is_empty():
		return
	var root := plate.get("root") as Node3D
	var back := plate.get("back") as Sprite3D
	if root == null or not is_instance_valid(root) or back == null or not is_instance_valid(back):
		return
	# Boss art is intentionally scaled as a body. Divide that inherited scale (and the track's tiny
	# 1.04 keyline expansion) back out so Grimwick's HUD is the same screen size as every minion's.
	var inherited_x := maxf(0.001, root.global_transform.basis.get_scale().abs().x)
	var track_x := maxf(0.001, absf(back.scale.x))
	var pixel_size := _combat_plate_base_pixel_size() / (inherited_x * track_x)
	for key in ["label", "back", "fill"]:
		var item := plate.get(key) as GeometryInstance3D
		if item is Sprite3D:
			(item as Sprite3D).pixel_size = pixel_size
		elif item is Label3D:
			(item as Label3D).pixel_size = pixel_size
			(item as Label3D).font_size = COMBAT_PLATE_FONT_PHONE if _phone_hud_active() else COMBAT_PLATE_FONT_HD
			(item as Label3D).outline_size = 2 if _phone_hud_active() else 3
	root.set_meta("plate_pixel_size", pixel_size)
	root.set_meta("target_screen_width_px", _combat_plate_screen_width())
	root.set_meta("plate_viewport_height", get_viewport().get_visible_rect().size.y)
	root.set_meta("plate_camera_fov", _combat_plate_fov())


func _combat_nameplates_allowed() -> bool:
	return _entered and _started and not _stage_over \
		and _wave_phase in ["prep", "fight", "reinforce"]


func _set_combat_nameplate(plate: Dictionary, display_name: String, hp: float,
		max_hp: float, shown: bool) -> void:
	if plate.is_empty():
		return
	var root := plate.get("root") as Node3D
	if root == null or not is_instance_valid(root):
		return
	_apply_combat_plate_projection(plate)
	var safe_max := maxf(0.001, max_hp)
	var safe_hp := clampf(hp, 0.0, safe_max)
	var visible_now := shown and safe_hp > 0.0
	root.visible = visible_now
	root.set_meta("hp_fraction", safe_hp / safe_max)
	root.set_meta("display_name", display_name)
	if not visible_now:
		return

	var text := display_name
	var label := plate.get("label") as Label3D
	if label != null and is_instance_valid(label) and label.text != text:
		label.text = text

	var fill := plate.get("fill") as Sprite3D
	if fill == null or not is_instance_valid(fill):
		return
	var fraction := safe_hp / safe_max
	var width_px := clampi(int(round(fraction * float(COMBAT_PLATE_BAR_PX.x))),
		1, COMBAT_PLATE_BAR_PX.x)
	fill.visible = fraction > 0.0
	fill.region_rect = Rect2(0.0, 0.0, float(width_px), float(COMBAT_PLATE_BAR_PX.y))
	# Sprite3D centers its cropped region. The negative offset pins the changing region to the
	# track's left edge, so taking damage shortens the red/blue bar instead of sliding it sideways.
	fill.offset.x = -float(COMBAT_PLATE_BAR_PX.x - width_px) * 0.5
	root.set_meta("bar_pixels", width_px)


func _plate_display_name(species: String) -> String:
	return Econ.strip_emoji(Econ.disp(species)).to_upper()


func _hide_combat_nameplate(plate: Dictionary) -> void:
	if plate.is_empty():
		return
	var root := plate.get("root") as Node3D
	if root != null and is_instance_valid(root):
		root.visible = false


func _refresh_combat_nameplates() -> void:
	var combat := _combat_nameplates_allowed()
	_set_combat_nameplate(_player_nameplate, _plate_display_name(_species()), _hp, _max_hp,
		combat)
	for value in _enemy_pool:
		var e := value as Dictionary
		_set_combat_nameplate(e.get("nameplate", {}) as Dictionary,
			_plate_display_name(String(e.get("species", "corruptimon"))),
			float(e.get("hp", 0.0)), float(e.get("maxhp", 1.0)),
			combat and bool(e.get("active", false)))
	_set_combat_nameplate(_boss_nameplate, "GRIMWICK", float(_boss.get("hp", 0.0)),
		float(_boss.get("maxhp", 1.0)), combat and bool(_boss.get("active", false)))


func debug_combat_nameplates() -> Dictionary:
	var enemy_visible := 0
	var enemy_total := 0
	var enemy_rows: Array = []
	for value in _enemy_pool:
		var e := value as Dictionary
		var plate := e.get("nameplate", {}) as Dictionary
		var root := plate.get("root") as Node3D
		if root == null or not is_instance_valid(root):
			continue
		enemy_total += 1
		if root.visible:
			enemy_visible += 1
		enemy_rows.append({"species": String(e.get("species", "")), "active": bool(e.get("active", false)),
			"visible": root.visible, "fraction": float(root.get_meta("hp_fraction", 0.0)),
			"bar_pixels": int(root.get_meta("bar_pixels", 0)),
			"plate_pixel_size": float(root.get_meta("plate_pixel_size", 0.0)),
			"target_screen_width_px": float(root.get_meta("target_screen_width_px", 0.0)),
			"parent_ok": root.get_parent() == e.get("body")})
	var player_root := _player_nameplate.get("root") as Node3D
	var boss_root := _boss_nameplate.get("root") as Node3D
	return {"allowed": _combat_nameplates_allowed(), "pool_total": enemy_total,
		"enemy_visible": enemy_visible, "enemies": enemy_rows,
		"player_visible": player_root != null and is_instance_valid(player_root) and player_root.visible,
		"player_parent_ok": player_root != null and is_instance_valid(player_root) and player_root.get_parent() == _player,
		"player_fraction": float(player_root.get_meta("hp_fraction", 0.0)) if player_root != null and is_instance_valid(player_root) else 0.0,
		"player_pixel_size": float(player_root.get_meta("plate_pixel_size", 0.0)) if player_root != null and is_instance_valid(player_root) else 0.0,
		"target_screen_width_px": _combat_plate_screen_width(),
		"plate_viewport_height": get_viewport().get_visible_rect().size.y,
		"plate_camera_fov": _combat_plate_fov(),
		"boss_visible": boss_root != null and is_instance_valid(boss_root) and boss_root.visible,
		"fixed_size": true, "bar_size": COMBAT_PLATE_BAR_PX,
		"profile": "phone" if _low else "hd"}


func _restart_selected_unit() -> void:
	_rng.seed = hash("wicked-horde:" + String(_selected_unit.get("uid", "guest")))
	_reset_run_state()
	_replace_player_rig()
	_deactivate_all_enemies()
	_deactivate_all_projectiles()
	_clear_transient_pools()
	_input_on = true
	creature_changed.emit(String(_selected_unit.get("uid", "")))
	start_stage()
	_refresh_hud(true)
	_prefetch_visible_card_art()


func _cycle_roster(step: int = 1) -> bool:
	if _roster.size() <= 1:
		return false
	var current := 0
	var uid := String(_selected_unit.get("uid", ""))
	for i in range(_roster.size()):
		if String((_roster[i] as Dictionary).get("uid", "")) == uid:
			current = i
			break
	_selected_unit = (_roster[posmod(current + step, _roster.size())] as Dictionary).duplicate(true)
	_restart_selected_unit()
	_set_message("TEST CHIKI  ·  %s" % Econ.disp(_species()).to_upper(), 1.2)
	return true


func _process(delta: float) -> void:
	super._process(delta)
	_tick_horde(delta)


func _tick_horde(delta: float) -> void:
	if not _entered:
		return
	_tick_mobile_hud_reveal(delta)
	_invuln_t = maxf(0.0, _invuln_t - delta)
	_parry_t = maxf(0.0, _parry_t - delta)
	_dodge_cd = maxf(0.0, _dodge_cd - delta)
	_perfect_dodge_t = maxf(0.0, _perfect_dodge_t - delta)
	_riposte_t = maxf(0.0, _riposte_t - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_card_buffer_t = maxf(0.0, _card_buffer_t - delta)
	_combo_t = maxf(0.0, _combo_t - delta)
	_rally_t = maxf(0.0, _rally_t - delta)
	_message_t = maxf(0.0, _message_t - delta)
	_player_hit_flash = maxf(0.0, _player_hit_flash - delta)
	_set_rig_combat_flash(_rig, _player_hit_flash, Color("ff6a82"))
	if _combo_t <= 0.0:
		_combo = 0
		_chain_arches.clear()
	for key in _card_cooldowns.keys():
		_card_cooldowns[key] = maxf(0.0, float(_card_cooldowns[key]) - delta)
	_tick_card_buffer()
	if _started and not _stage_over:
		_run_t += delta
		_energy = minf(ENERGY_MAX, _energy + ENERGY_REGEN
			* clampf(float(_species_trait.get("focus", 1.0)), 0.9, 1.1)
			* (1.28 if _rally_t > 0.0 else 1.0) * delta)
		_tick_dodge(delta)
		_tick_card_dash(delta)
		var cd := _combat_delta(delta)
		_tick_wave(cd)
		if _stage_over: return
		_tick_pending_cast(delta)
		if _stage_over: return
		_tick_enemies(cd)
		if _stage_over: return
		_tick_boss(cd)
		if _stage_over: return
		_tick_projectiles(cd)
		if _stage_over: return
		_tick_effects(cd)
		_tick_floaters(delta)
		_check_wave_clear()
	_refresh_status_visuals(delta)
	_combat_plate_tick -= delta
	if _combat_plate_tick <= 0.0:
		_combat_plate_tick = 0.05
		_refresh_combat_nameplates()
	# the HP digits surface on a change and fade; decayed once per frame, outside the combat block
	_hp_digits_t = maxf(0.0, _hp_digits_t - delta)
	_hud_tick -= delta
	if _hud_tick <= 0.0:
		_hud_tick = 0.05
		_refresh_hud(false)


func _input_dir() -> Vector2:
	if not _input_on or _stage_over:
		return Vector2.ZERO
	if _dodge_t > 0.0 or not _card_dash.is_empty():
		return Vector2.ZERO
	if _touch_move.length_squared() > 0.01:
		_has_tap = false
		return _touch_move.normalized()
	return super._input_dir()


func _move_player(dv: Vector2) -> void:
	super._move_player(dv)
	if _started and not _stage_over and _arena_rect.size != Vector2.ZERO:
		_ppos.x = clampf(_ppos.x, _arena_rect.position.x + 22.0, _arena_rect.end.x - 22.0)
		_ppos.y = clampf(_ppos.y, _arena_rect.position.y + 20.0, _arena_rect.end.y - 20.0)


func _move_speed_multiplier() -> float:
	return clampf(float(_species_trait.get("stride", 1.0)), 0.9, 1.1)


func _tick_triggers() -> void:
	# Arena progression owns the run.  Old sigil and exit signals must not open a turn-based overlay.
	pass


func _camera_target_dist() -> float:
	if _phone_hud_active():
		var display := MobileViewport.sample(get_viewport())
		var css := display["css_size"] as Vector2
		# Portrait gets a wider view of actual attack lanes instead of magnifying the centre slice.
		# Keep the existing exponential transition: rotation cannot snap the camera or the sprites.
		var aspect := css.x / maxf(1.0, css.y)
		var portrait_pullback := clampf(1.12 / aspect, 1.0, 1.85)
		return (24.0 if _zoom_tactical else 18.0) * portrait_pullback
	if _zoom_tactical:
		return 20.0 if _low else 22.5
	return 15.8 if _low else 17.5


func _tick_cam(delta: float) -> void:
	if _cam == null or not is_instance_valid(_cam):
		return
	var safe_delta := maxf(0.0, delta)
	_zoom_dist = lerpf(_zoom_dist, _camera_target_dist(),
		1.0 - exp(-6.0 * safe_delta))
	# Frame the controlled Chikimon in the lower foreground and spend the valuable middle of the
	# screen on enemies and dodge lanes. Combat looks toward the arena heart instead of centering the
	# camera on the player. The continuous capped vector has no centre-line direction flip, so a
	# left/right crossing cannot snap the view from one normalized direction to its opposite.
	var aim_plane := _ppos
	if _wave >= 0 and _arena_rect.size != Vector2.ZERO:
		var to_arena := _arena_center - _ppos
		# The phone hand needs a readable 40 px footer. A shorter phone-only combat lead moves the
		# controlled creature upward without changing camera damping, desktop composition, or aim logic.
		var look_ahead := 72.0 if _phone_hud_active() else (52.0 if _low else 148.0)
		if _zoom_tactical:
			look_ahead += 20.0 if _low else 42.0
		aim_plane += to_arena.limit_length(look_ahead)
	else:
		# Traversal leads from actual ground motion. Reversing left/right changes only the target lead;
		# exponential damping carries it through zero instead of teleporting the camera by two leads.
		var lead_length := 52.0 if _low else 68.0
		var motion := _ppos - _cam_last_player_plane
		var travel_dir := Vector2.ZERO
		if motion.length_squared() > 0.01:
			travel_dir = motion.normalized()
		elif _travel_target != Vector2.ZERO and _ppos.distance_squared_to(_travel_target) > 1.0:
			travel_dir = (_travel_target - _ppos).normalized()
		elif _face_dir.length_squared() > 0.01:
			travel_dir = _face_dir.normalized()
		else:
			travel_dir = Vector2.UP
		var wanted_lead := travel_dir * lead_length
		if not _cam_ready:
			_cam_travel_lead = wanted_lead
		else:
			_cam_travel_lead = _cam_travel_lead.lerp(wanted_lead,
				1.0 - exp(-HORDE_CAM_LEAD_DECAY * safe_delta))
		aim_plane += _cam_travel_lead
	_cam_last_player_plane = _ppos
	if _phone_hud_active():
		var display := MobileViewport.sample(get_viewport())
		var css := display["css_size"] as Vector2
		if css.y > css.x:
			# Spend portrait height on the actual arena instead of the empty horizon beyond its wall.
			# Keeping the wider lens still fits the outer enemies; the aim uses the same damping.
			aim_plane.y += 100.0
	# At the opening threshold, pushing the aim any farther south drops the camera ray below the
	# 3.2 m portal cap and exposes its solid back face. Clamp only the initial traversal sightline;
	# normal combat framing resumes as soon as the player walks north into the hall.
	if _wave < 0 and _wave_phase == "travel":
		aim_plane.y = minf(aim_plane.y, SPAWN.y)
	var wanted_aim := px2m(aim_plane, CAM_AIM_Y)
	var pr := deg_to_rad(HORDE_PITCH_DEG)
	var camera_offset := Vector3(0.0, _zoom_dist * sin(pr), _zoom_dist * cos(pr))
	if not _cam_ready:
		_cam_aim = wanted_aim
		_cam_pos = wanted_aim + camera_offset
		_cam_ready = true
	else:
		# Position and look target are damped independently. Smoothing only position while looking at
		# the raw aim still produces a one-frame rotation kick when facing reverses.
		_cam_aim = _cam_aim.lerp(wanted_aim,
			1.0 - exp(-HORDE_CAM_AIM_DECAY * safe_delta))
		_cam_pos = _cam_pos.lerp(_cam_aim + camera_offset,
			1.0 - exp(-HORDE_CAM_POSITION_DECAY * safe_delta))
	_cam.global_position = _cam_pos
	_cam.look_at(_cam_aim, Vector3.UP)


func _input(event: InputEvent) -> void:
	# Touch must be claimed before GUI Buttons see it. Handling it only in _unhandled_input
	# races the emulated mouse/Button path and cannot implement a non-casting long press.
	if not _entered or not is_visible_in_tree() or not _input_on or _stage_over:
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		get_viewport().set_input_as_handled()
		return
	if _route_mobile_event(event):
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED,
			NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_cancel_mobile_gestures()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_cancel_mobile_gestures()


func _cancel_mobile_gestures() -> void:
	_touch_serial += 1
	_touch_owners.clear()
	_touch_move_id = -1
	_touch_move = Vector2.ZERO
	_has_tap = false
	_touch_inspect_id = -1
	_touch_inspect_index = -1
	_sync_touch_move_knob()
	if _card_preview != null and is_instance_valid(_card_preview) and _phone_hud_active():
		_card_preview.visible = false


func _cancel_touch_card_gestures() -> void:
	# Paging retires card identities, not the other thumb's held movement stick.
	for value in _touch_owners.values():
		var owner := value as Dictionary
		if String(owner.get("role", "")).begins_with("card_"):
			owner["canceled"] = true
	_touch_inspect_id = -1
	_touch_inspect_index = -1
	_update_card_preview()


func _card_gesture_matches(owner: Dictionary) -> bool:
	if not _input_on or _stage_over or bool(owner.get("canceled", false)):
		return false
	var visible_index := int(owner.get("card_index", -1))
	var indices := _page_indices()
	if visible_index < 0 or visible_index >= indices.size():
		return false
	var global_index := int(indices[visible_index])
	return global_index >= 0 and global_index < _card_slots.size() \
		and int(_card_slots[global_index]) == int(owner.get("slot", -1)) \
		and _species() == String(owner.get("species", ""))


func _open_touch_card_inspection(index: int, token: int) -> void:
	var owner := _touch_owners.get(index, {}) as Dictionary
	if int(owner.get("token", -1)) != token or not _card_gesture_matches(owner):
		return
	owner["inspected"] = true
	_touch_inspect_id = index
	_touch_inspect_index = int(owner["card_index"])
	_update_card_preview()


func _close_touch_card_inspection(index: int) -> void:
	if index != _touch_inspect_id:
		return
	_touch_inspect_id = -1
	_touch_inspect_index = -1
	_update_card_preview()


func _route_mobile_event(event: InputEvent) -> bool:
	if not _entered or not _input_on or _stage_over or not is_visible_in_tree():
		return false
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if not touch.pressed or touch.canceled:
			if not _touch_owners.has(touch.index):
				return false
			var owner := _touch_owners[touch.index] as Dictionary
			_touch_owners.erase(touch.index)
			if touch.index == _touch_move_id:
				_touch_move_id = -1
				_touch_move = Vector2.ZERO
				_has_tap = false
				_sync_touch_move_knob()
			_close_touch_card_inspection(touch.index)
			var role := String(owner.get("role", ""))
			if role.begins_with("card_") and not touch.canceled \
					and not bool(owner.get("inspected", false)) and _card_gesture_matches(owner) \
					and Time.get_ticks_msec() - int(owner.get("started_ms", 0)) < int(TOUCH_CARD_HOLD_SECONDS * 1000.0) \
					and _touch_role(touch.position) == role:
				_on_card_pressed(int(owner["card_index"]))
			return true
		if _touch_owners.has(touch.index):
			return true
		var role := _touch_role(touch.position)
		if role == "":
			# Keep legacy tap-to-walk on the floor, but never let a second finger replace a
			# held stick's movement or leave a latent destination behind its release.
			return _touch_move_id >= 0
		if _touch_owners.size() >= TOUCH_OWNER_LIMIT:
			return true
		_touch_serial += 1
		var owner := {"role": role, "token": _touch_serial, "origin": touch.position,
			"started_ms": Time.get_ticks_msec(), "canceled": false, "inspected": false}
		_touch_owners[touch.index] = owner
		if role == "move":
			if _touch_move_id < 0:
				_touch_move_id = touch.index
				_has_tap = false
				_update_touch_move(touch.position)
			else:
				owner["role"] = "blocked"
		elif role.begins_with("card_"):
			_has_tap = false
			var visible_index := int(role.trim_prefix("card_"))
			var indices := _page_indices()
			if visible_index < 0 or visible_index >= indices.size():
				owner["canceled"] = true
				return true
			var global_index := int(indices[visible_index])
			if global_index < 0 or global_index >= _card_slots.size():
				owner["canceled"] = true
				return true
			owner["card_index"] = visible_index
			owner["slot"] = int(_card_slots[global_index])
			owner["species"] = _species()
			# Press peeks immediately at the fixed right-edge inspection panel. Only the hold
			# timer marks this inspect-only; a quick release still casts exactly once.
			_touch_inspect_id = touch.index
			_touch_inspect_index = visible_index
			_update_card_preview()
			get_tree().create_timer(TOUCH_CARD_HOLD_SECONDS).timeout.connect(
				_open_touch_card_inspection.bind(touch.index, _touch_serial))
		else:
			match role:
				"dodge": _try_dodge()
				"page": _next_card_page()
				"camera": _toggle_zoom()
				"exit": _request_exit()
				"cycle": _cycle_roster()
				"settings": _toggle_reborn_controls()
		return true
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if not _touch_owners.has(drag.index):
			return false
		if drag.index == _touch_move_id:
			_update_touch_move(drag.position)
		else:
			var owner := _touch_owners[drag.index] as Dictionary
			var role := String(owner.get("role", ""))
			if role.begins_with("card_") and _touch_role(drag.position) != role:
				owner["canceled"] = true
				_close_touch_card_inspection(drag.index)
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if _route_mobile_event(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		# A/X/Y/B form the same four-verb cluster as the phone controls: dodge plus three cards.
		# Shoulder paging and right-stick camera keep thumbs on movement during combat.
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_A: _try_dodge()
			JOY_BUTTON_X: _on_card_pressed(0)
			JOY_BUTTON_Y: _on_card_pressed(1)
			JOY_BUTTON_B: _on_card_pressed(2)
			JOY_BUTTON_LEFT_SHOULDER: _prev_card_page()
			JOY_BUTTON_RIGHT_SHOULDER: _next_card_page()
			JOY_BUTTON_RIGHT_STICK: _toggle_zoom()
			JOY_BUTTON_START: _request_exit()
			_: 
				super._unhandled_input(event)
				return
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var key := (event as InputEventKey).physical_keycode
		if key in [KEY_1, KEY_2, KEY_3]:
			_on_card_pressed(int(key - KEY_1))
			get_viewport().set_input_as_handled()
			return
		# Q/E PAGE THE DECK. 1/2/3 already fire (see _on_card_pressed), so E casting was a second
		# way to do a thing that already had one, while paging — a frequent verb on a 12-card deck —
		# was forward-only and unbound to the standard adjacent-to-WASD pair. C stays for one
		# release; X/Z stay as silent cast aliases so nobody's muscle memory breaks today.
		if key == KEY_E or key == KEY_C:
			_next_card_page()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_Q:
			_prev_card_page()
			get_viewport().set_input_as_handled()
			return
		if key in [KEY_X, KEY_Z]:
			_activate_card()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_H:
			_show_control_band()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_SPACE:
			_try_dodge()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_V:
			_toggle_zoom()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_R and _roster.size() > 1:
			_cycle_roster()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_ESCAPE:
			exit_requested.emit()
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)


func debug_cycle_control_present() -> bool:
	return _cycle_button != null and is_instance_valid(_cycle_button)


func _touch_role(at: Vector2) -> String:
	var rects := touch_rects()
	for key in ["card_0", "card_1", "card_2", "dodge", "settings", "camera", "exit", "cycle", "page", "move"]:
		if key == "page" and _card_pages() <= 1:
			continue
		if rects.has(key) and (rects[key] as Rect2).has_point(at):
			return String(key)
	return ""


func _update_touch_move(at: Vector2) -> void:
	var rects := touch_rects()
	if not rects.has("move"):
		_cancel_mobile_gestures()
		return
	var r := rects["move"] as Rect2
	var half := maxf(1.0, minf(r.size.x, r.size.y) * 0.5)
	_touch_move = (at - r.get_center()) / half
	if _touch_move.length() > 1.0:
		_touch_move = _touch_move.normalized()
	_has_tap = false
	_sync_touch_move_knob()


func _sync_touch_move_knob() -> void:
	if _move_panel == null or not is_instance_valid(_move_panel):
		return
	var knob := _move_panel.find_child("VectorKnob", true, false) as Control
	if knob == null:
		return
	var travel := maxf(0.0, minf(_move_panel.size.x - knob.size.x,
		_move_panel.size.y - knob.size.y) * 0.5)
	knob.position = (_move_panel.size - knob.size) * 0.5 + _touch_move * travel


# ================================= run and waves ===============================================
func _reset_run_state() -> void:
	_species_trait = SpeciesTraits.profile(_species())
	_trait_proc_ids.clear()
	_trait_procs = 0
	_cancel_mobile_gestures()
	_clear_status_visuals()
	_started = false
	_stage_over = false
	_win = false
	_wave = -1
	_wave_phase = "idle"
	_wave_t = 0.0
	_results.clear()
	_score = 0
	_kills = 0
	_combo = 0
	_best_combo = 0
	_combo_t = 0.0
	_chain_arches.clear()
	_cards_used.clear()
	_card_cooldowns.clear()
	_card_texture_cache.clear()
	_card_preview_texture_cache.clear()
	_preview_hover_index = -1
	_preview_focus_index = -1
	_card_page = 0
	_card_at = 0
	_pack_at = 0
	_pack_spawn_t = 0.0
	_wave_spawned = 0
	_travel_target = Vector2.ZERO
	_pending_cast.clear()
	_card_dash.clear()
	_card_buffer_t = 0.0
	_buffered_card_at = -1
	_last_visual_profile.clear()
	_hud_target_eid = -1
	if _travel_marker != null and is_instance_valid(_travel_marker):
		_travel_marker.visible = false
	_card_slots = Econ.unlocked_slots(_kind(), _level(), _species(), String(_selected_unit.get("uid", _species())))
	if _card_slots.is_empty():
		_card_slots = Econ.NORMAL_SLOTS.duplicate() if _kind() == "normal" else Econ.HATCH_SLOTS.duplicate()
	var rarity := _rarity()
	_max_hp = Econ.chiki_maxhp(_level()) * float(rarity["hp"])
	_hp = _max_hp
	_shield = 0.0
	_player_status_profiles.clear()
	_energy = ENERGY_MAX
	_invuln_t = 0.0
	_parry_t = 0.0
	_dodge_t = 0.0
	_dodge_cd = 0.0
	_perfect_dodge_t = 0.0
	_perfect_dodge_claimed = false
	_riposte_t = 0.0
	_player_hit_flash = 0.0
	_empower_mul = 1.0
	_rally_t = 0.0
	_rally_mul = 1.0
	_damage_taken = 0.0
	_next_attack_id = 1
	_combat_plate_tick = 0.0
	_refresh_combat_nameplates()


func _blank_result(index: int) -> Dictionary:
	return {"sigil": WAVE_ELEMENTS[index], "uid": String(_selected_unit.get("uid", "")),
		"creature_name": Econ.disp(_species()), "el": Econ.el_of(_species()), "lvl": _level(),
		"broke": false, "cleared": false, "kills": 0, "power": 0.0, "timing": 1.0}


func _start_wave(index: int, teleport_player: bool = true) -> void:
	_deactivate_all_enemies()
	_deactivate_all_projectiles()
	_pending_cast.clear()
	_card_dash.clear()
	_wave = clampi(index, 0, WAVE_TOTAL - 1)
	_wave_phase = "prep"
	_wave_t = 1.45
	_wave_start_kills = _kills
	_pack_at = 0
	_pack_spawn_t = 0.0
	_wave_spawned = 0
	var arena := ARENAS[_wave] as Dictionary
	_arena_rect = arena["rect"]
	_arena_center = arena["center"]
	if teleport_player:
		_ppos = _arena_center + Vector2(0.0, 92.0 if _wave < 4 else 150.0)
	else:
		_ppos = _enemy_legal(_ppos)
	_face_dir = Vector2.UP
	_sync_player()
	_cam_ready = false
	_zoom_tactical = _wave == 4
	_travel_target = Vector2.ZERO
	if _travel_marker != null and is_instance_valid(_travel_marker):
		_travel_marker.visible = false
	# The persistent header already owns the wave title. Keep the transient line actionable instead
	# of painting the same title twice over the arena.
	_set_message("CORRUPTION MANIFESTING  ·  HOLD THE DODGE LANES", 1.05)
	if _wave == 4:
		_prepare_boss()
	_spawn_next_pack()
	_refresh_hud(true)


func _tick_wave(delta: float) -> void:
	if _wave_phase == "prep":
		_wave_t -= delta
		if _wave_t <= 0.0:
			_wave_phase = "fight"
			for value in _enemy_pool:
				var e := value as Dictionary
				if bool(e.get("active", false)):
					e["awake"] = true
			if bool(_boss.get("active", false)):
				_boss["awake"] = true
			_play_sfx(SFX_LEVEL, 1.0)
	elif _wave_phase == "fight":
		if _pack_at < _wave_pack_count(_wave) and _active_minions() <= 1:
			_wave_phase = "reinforce"
			_pack_spawn_t = 0.95
			_set_message("CORRUPTION SURGE  ·  REINFORCEMENTS INCOMING", 1.0)
	elif _wave_phase == "reinforce":
		_pack_spawn_t -= delta
		if _pack_spawn_t <= 0.0:
			_spawn_next_pack()
			_wave_phase = "fight"
	elif _wave_phase == "clear":
		_wave_t -= delta
		if _wave_t <= 0.0:
			if _wave + 1 < WAVE_TOTAL:
				_begin_travel()
			else:
				_finish_stage(true)
	elif _wave_phase == "travel":
		if _travel_marker != null and is_instance_valid(_travel_marker):
			_travel_marker.rotation.y += delta * 0.75
			var pulse := 1.0 + sin(_run_t * 4.0) * 0.08
			_travel_marker.scale = Vector3(pulse, 1.0, pulse)
		if _ppos.distance_to(_travel_target) <= 88.0:
			_start_wave(_wave + 1, false)


func _wave_pack_count(index: int) -> int:
	if index < 0 or index >= WAVE_PACKS.size():
		return 0
	return (WAVE_PACKS[index] as Array).size()


func _queued_foes() -> int:
	if _wave < 0 or _wave >= WAVE_PACKS.size():
		return 0
	var total := 0
	var packs := WAVE_PACKS[_wave] as Array
	for i in range(_pack_at, packs.size()):
		total += (packs[i] as Array).size()
	return total


func _active_minions() -> int:
	var count := 0
	for value in _enemy_pool:
		if bool((value as Dictionary).get("active", false)):
			count += 1
	return count


func _inactive_enemy(species: String) -> Dictionary:
	for value in _enemy_pool:
		var e := value as Dictionary
		if not bool(e.get("active", false)) and String(e.get("species", "")) == species:
			return e
	for value in _enemy_pool:
		var e := value as Dictionary
		if not bool(e.get("active", false)):
			return e
	return {}


func _pack_spawn_point(ordinal: int, count: int) -> Vector2:
	# Six authored slots create two staggered rows, like a readable encounter composition rather
	# than a random ring. Packs use symmetric subsets so ranged foes inherit clean firing lanes and
	# every replay of a wave starts from the same tactical picture.
	const FORMATION := [
		Vector2(-0.31, -0.27), Vector2(0.0, -0.34), Vector2(0.31, -0.27),
		Vector2(-0.22, -0.08), Vector2(0.22, -0.08), Vector2(0.0, -0.15),
	]
	const PICKS := [
		[1], [0, 2], [0, 1, 2], [0, 2, 3, 4], [0, 1, 2, 3, 4], [0, 1, 2, 3, 4, 5],
	]
	var safe_count := clampi(count, 1, MAX_ACTIVE_FOES)
	var order := PICKS[safe_count - 1] as Array
	var slot := int(order[clampi(ordinal, 0, order.size() - 1)])
	var unit := FORMATION[slot] as Vector2
	var span := Vector2(minf(_arena_rect.size.x, 1040.0), minf(_arena_rect.size.y, 700.0))
	return _enemy_legal(_arena_center + Vector2(unit.x * span.x, unit.y * span.y))


func _spawn_next_pack() -> void:
	if _wave < 0 or _wave >= WAVE_PACKS.size():
		return
	var packs := WAVE_PACKS[_wave] as Array
	if _pack_at >= packs.size():
		return
	var requested := packs[_pack_at] as Array
	_pack_at += 1
	var room := maxi(0, MAX_ACTIVE_FOES - _active_foes())
	var spawned := 0
	for species_value in requested:
		if spawned >= room:
			break
		var e := _inactive_enemy(String(species_value))
		if e.is_empty():
			break
		_activate_enemy(e, _pack_spawn_point(spawned, mini(requested.size(), room)), _wave)
		e["awake"] = _wave_phase in ["fight", "reinforce"]
		spawned += 1
	_wave_spawned += spawned
	if spawned > 0 and _wave_phase != "prep":
		_play_sfx(SFX_FOE, 1.02)


func _begin_travel() -> void:
	_wave_phase = "travel"
	_arena_rect = Rect2()
	_travel_target = Vector2((ARENAS[_wave + 1] as Dictionary)["center"])
	_zoom_tactical = false
	if _travel_marker != null and is_instance_valid(_travel_marker):
		_travel_marker.visible = true
		_travel_marker.global_position = px2m(_travel_target, 0.035)
	_refresh_combat_nameplates()
	_set_message("TEMPLE PATH OPEN  ·  FOLLOW THE GREEN SANCTUM RUNE", 3.0)


func _check_wave_clear() -> void:
	if _wave_phase not in ["fight", "reinforce"] or _active_foes() > 0 \
			or _pack_at < _wave_pack_count(_wave):
		return
	_wave_phase = "clear"
	_wave_t = 1.15
	var result := _blank_result(_wave)
	result["broke"] = true
	result["cleared"] = true
	result["kills"] = _kills - _wave_start_kills
	result["power"] = 1.0 + float(_combo) * 0.01
	_results[_wave] = result
	_score += 500 + _wave * 150
	_energy = ENERGY_MAX
	_hp = minf(_max_hp, _hp + _max_hp * 0.10)
	_refresh_combat_nameplates()
	_set_message("SANCTUM PURGED  ·  +10% HEALTH  ·  ENERGY RESTORED", 2.0)
	_play_sfx(SFX_LEVEL, 1.12)


func _finish_stage(won: bool) -> void:
	if _stage_over:
		return
	_stage_over = true
	_win = won
	_wave_phase = "done"
	_input_on = false
	_cancel_mobile_gestures()
	_pending_cast.clear()
	_card_dash.clear()
	_deactivate_all_projectiles()
	_clear_status_visuals()
	# Combat no longer ticks after completion. Release moving and delayed images immediately,
	# otherwise a mid-siphon victory/death freezes the atlas behind the results presentation.
	_clear_transient_pools()
	_refresh_combat_nameplates()
	_set_message("THE CURSE BREAKS" if won else "THE CORRUPTION CLAIMS THIS RUN", 4.0)
	_play_sfx(SFX_WIN if won else SFX_FOE, 1.0)
	var cleared := 0
	for value in _results:
		if bool((value as Dictionary).get("broke", false)):
			cleared += 1
	var grade := _grade_for(won, _run_t, _damage_taken, _best_combo)
	var stats := {"purified": cleared, "sigils_broken": cleared, "seals": cleared,
		"results": _results.duplicate(true), "score": _score, "kills": _kills,
		"combo": _best_combo, "max_combo": _best_combo, "time": _run_t,
		"damage_taken": _damage_taken, "grade": grade,
		"uid": String(_selected_unit.get("uid", "")), "species": _species(), "won": won,
		"cards_used": _cards_used.duplicate(true)}
	stage_completed.emit(stats)


func _grade_for(won: bool, elapsed: float, damage: float, max_combo: int) -> String:
	# Victory earns the C floor.  Each clearly explained mastery goal advances one letter.
	if not won:
		return "C"
	var mastery := 0
	if elapsed <= 240.0:
		mastery += 1
	if damage <= _max_hp * 0.50:
		mastery += 1
	if max_combo >= 10:
		mastery += 1
	return ["C", "B", "A", "S"][mastery]


# ================================= bounded runtime pools =======================================
func _build_runtime_pools() -> void:
	_foe_cap = PHONE_FOES if _low else MAX_FOES
	_projectile_cap = PHONE_PROJECTILES if _low else MAX_PROJECTILES
	_effect_cap = PHONE_EFFECTS if _low else MAX_EFFECTS
	_floater_cap = PHONE_FLOATERS if _low else MAX_FLOATERS
	AbilitySprites.configure_low_memory(_low)
	_ensure_ability_art_stream()
	if _ability_art_stream != null and is_instance_valid(_ability_art_stream):
		_ability_art_stream.call("configure", _low)
	_circle_tex = _make_circle_texture(96, true)
	_orb_tex = _make_circle_texture(64, false)
	_boss_telegraph = _telegraph_mesh(Color("ef4cff"))
	_boss_telegraph.name = "GrimwickEclipseTelegraph"
	_boss_telegraph.visible = false
	add_child(_boss_telegraph)
	_build_travel_marker()
	_build_audio_pool()
	_build_enemy_pool()
	_build_projectile_pool()
	_build_effect_pool()
	_build_status_pool()
	_build_floater_pool()


func _build_audio_pool() -> void:
	_audio_pool.clear()
	for _i in range(4):
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_audio_pool.append(player)


func _build_enemy_pool() -> void:
	_enemy_pool.clear()
	var per_species := int(ceil(float(_foe_cap) / float(CORRUPTIMONS.size())))
	for species in CORRUPTIMONS:
		for ordinal in range(per_species):
			var body := Node3D.new()
			body.name = "Horde_%s_%d" % [species, ordinal]
			body.visible = false
			_actors.add_child(body)
			var rig_h := DARKEON_RIG_H_M if species == "darkeon" else FOE_RIG_H_M
			var rig := _make_rig("species", species, rig_h)
			if rig.has_method("set_distance_driven_walk"):
				rig.call("set_distance_driven_walk", true,
					PLAYER_WALK_STRIDE_PX * rig_h / PLAYER_RIG_H_M)
			body.add_child(rig)
			_configure_enemy_visibility(rig)
			body.add_child(_cached_shadow(0.42 if species != "darkeon" else 0.50))
			var tele := _telegraph_mesh(Color("ff496f"))
			tele.visible = false
			body.add_child(tele)
			var plate_h := rig_h + 0.22 + (0.28 if species == "shadowisp" else 0.0)
			var nameplate := _make_combat_nameplate(body,
				"CorruptimonNameplate_%d" % _enemy_pool.size(), plate_h,
				COMBAT_PLATE_ENEMY, false)
			var e := {"species": species, "body": body, "rig": rig, "tele": tele,
				"nameplate": nameplate,
				"active": false, "awake": false, "p": Vector2.ZERO, "v": Vector2.ZERO,
				"hp": 1.0, "maxhp": 1.0, "damage": 1.0, "speed": 90.0, "state": "hunt",
				"t": 0.0, "attack_cd": 0.0, "stun": 0.0, "slow": 0.0, "weaken": 0.0,
				"bleed": 0.0, "bleed_tick": 0.0, "armor_break": 0, "hit_flash": 0.0,
				"charge_dir": Vector2.ZERO, "charge_hit": false, "charge_hits": 0,
				"eid": _enemy_pool.size(), "wave": 0}
			_enemy_pool.append(e)
	_boss = {"active": false, "awake": false, "hp": 1.0, "maxhp": 1.0,
		"p": Vector2(1200.0, 300.0), "state": "idle", "t": 0.0, "phase": 1,
		"damage": 12.0, "weaken": 0.0, "stun": 0.0, "armor_break": 0}


func _build_projectile_pool() -> void:
	_projectile_pool.clear()
	for i in range(_projectile_cap):
		var sprite := Sprite3D.new()
		sprite.name = "HordeProjectile_%d" % i
		sprite.texture = _orb_tex
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.shaded = false
		sprite.transparent = true
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		sprite.pixel_size = 0.014
		sprite.visible = false
		sprite.render_priority = 3
		add_child(sprite)
		_projectile_pool.append({"node": sprite, "active": false, "owner": "", "p": Vector2.ZERO,
			"v": Vector2.ZERO, "life": 0.0, "radius": 16.0, "damage": 0.0, "arch": "",
			"element": "", "pierce": false, "hit_ids": {}, "heal": 0.0, "weak": 0.0,
			"blast": 0.0, "attack_id": 0, "profile": {}, "delivery": "straight_bolt",
			"target_eid": -1, "age": 0.0, "trail_t": 0.0, "trail_interval": 0.08,
			"base_scale": 1.0, "visual_height": 0.82, "spin_rate": 0.0,
			"core_color": Color.WHITE, "trail_color": Color.WHITE, "visual_phase": 0.0,
			"weave_amp": 0.0, "weave_rate": 0.0, "trail_alpha": 0.58,
			"trail_scale_decay": 0.22, "trail_texture_key": "", "visual_id": "",
			"signature_core": false, "hit_confirmed": false, "heal_confirmed": false})


# ADDITIVE, PER TEXTURE. Alpha-blended effects go MUDDY where they overlap — two purple discs make
# a darker purple — which is why the impacts read as translucent stickers. Additive makes overlap
# BRIGHTER, so a core over a halo over a ring builds toward white the way light does.
#
# WHY ONE MATERIAL PER TEXTURE AND NOT ONE SHARED ONE — MEASURED. A material_override on a Sprite3D
# REPLACES its generated material, texture included: a shared override with no albedo_texture drew
# every impact as a solid white quad the size of the stamp (screenshot horde_cast1_b, a white box
# over the fight). So the override has to carry the sprite's own texture, which makes it one per
# texture — bounded by TempleAbilityVisual's own 48-texture cache, and cleared with the pool. It
# also re-declares the billboard (the override dropped that too) with keep_scale, or the scale
# envelope is silently eaten by the billboard basis; and it reads the sprite's modulate through
# vertex colour, which an override does not do by default either.
func _fx_bind(node: Sprite3D) -> void:
	var tex := node.texture
	if tex == null:
		node.material_override = null
		return
	var m = _fx_materials.get(tex)
	if m == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
		mat.disable_receive_shadows = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = tex
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_fx_materials[tex] = mat
		m = mat
	node.material_override = m
	_fx_material_lru.erase(tex)
	_fx_material_lru.append(tex)
	var material_limit := FX_MATERIAL_CACHE_PHONE if _low else FX_MATERIAL_CACHE_HD
	# Active sprites retain their material after dictionary eviction; released sprites drop it. This
	# prevents cycling the 402 unique signatures in the sandbox from pinning 402 decoded textures.
	while _fx_material_lru.size() > material_limit:
		var evicted = _fx_material_lru.pop_front()
		_fx_materials.erase(evicted)


func _build_status_pool() -> void:
	_status_pool.clear()
	_status_clock = 0.0
	for i in range(STATUS_POOL_CAP):
		var sprite := Sprite3D.new()
		sprite.name = "PersistentStatus_%02d" % i
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.shaded = false
		sprite.transparent = true
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sprite.visible = false
		sprite.region_enabled = true
		sprite.render_priority = 0
		add_child(sprite)
		_status_pool.append({"node": sprite, "active": false, "owner": "", "kind": "",
			"states": [], "frame": 0, "at": Vector2.ZERO, "height": 0.0,
			"phase": float(i) * 0.61})


func _release_status_visual(status: Dictionary) -> void:
	status["active"] = false
	status["owner"] = ""
	status["kind"] = ""
	status["states"] = []
	status["frame"] = 0
	status["asset"] = {}
	status["profile"] = {}
	status["event_assets"] = {}
	status["body_event_asset"] = {}
	status["suspended"] = {}
	status["block_until"] = 0.0
	status["profile_key"] = ""
	status["direction"] = Vector2.RIGHT
	var node := status.get("node") as Sprite3D
	if node != null and is_instance_valid(node):
		node.visible = false
		node.texture = null
		node.material_override = null
		node.region_rect = Rect2()
		node.offset = Vector2.ZERO
		node.modulate = Color.WHITE
		node.rotation = Vector3.ZERO
		node.flip_h = false
		node.scale = Vector3.ONE
		node.billboard = BaseMaterial3D.BILLBOARD_ENABLED


func _clear_status_visuals(owner_prefix: String = "") -> void:
	# Stage/actor retirement cancels any short reaction already borrowed by the live rig.
	# Natural shield depletion uses _release_status_visual directly, so its final valid block
	# reaction may finish while owning the same exact texture for at most a quarter second.
	if (owner_prefix.is_empty() or "player:shield".begins_with(owner_prefix)) \
			and _rig != null and is_instance_valid(_rig) and _rig.has_method("clear_body_event"):
		_rig.call("clear_body_event")
	for value in _status_pool:
		var status := value as Dictionary
		if bool(status.get("active", false)) and (owner_prefix.is_empty() \
				or String(status.get("owner", "")).begins_with(owner_prefix)):
			_release_status_visual(status)


func _clear_status_owner(owner: String) -> void:
	var status := _status_visual_for(owner)
	if not status.is_empty():
		_release_status_visual(status)


func _status_visual_for(owner: String) -> Dictionary:
	for value in _status_pool:
		var status := value as Dictionary
		if bool(status.get("active", false)) and String(status.get("owner", "")) == owner:
			return status
	return {}


func _status_asset(kind: String, profile: Dictionary) -> Dictionary:
	if not _illustrated_only(profile):
		return StatusSprites.asset(kind)
	var trait_sunder := bool(profile.get("_trait_sunder_status", false))
	# A favored Blast/Quick/Strike need not author a separate long-form status strip. Its
	# existing exact-card impact drawing can supply one small held frame while the real Weaken
	# lasts. Retain the card atlas from cast time so deck paging cannot replace it mid-flight.
	var asset := (profile.get("_trait_status_asset", {}) as Dictionary).duplicate(true) \
		if trait_sunder else {}
	if asset.is_empty():
		asset = AbilitySprites.reborn_effect_layer_asset(profile, "status")
	if asset.is_empty() and trait_sunder:
		asset = AbilitySprites.reborn_effect_layer_asset(profile, "impact")
	if asset.is_empty():
		return {} # Never replace an approved card's missing sustained art with the old generic loop.
	var layer := asset.get("layer", {}) as Dictionary
	var window := asset.get("frames", Vector2i(-1, 0)) as Vector2i
	if window.x < 0 or window.y <= 0:
		return {}
	var held_impact := trait_sunder and String(asset.get("layer_name", "")) == "impact"
	asset["frame_start"] = window.x + maxi(0, int(window.y / 2) - 1) if held_impact else window.x
	asset["frames"] = 1 if held_impact else window.y
	asset["fps"] = 1.0 if held_impact else maxf(1.0, float(layer.get("fps", 8.0)))
	asset["height"] = float({"shield": 0.58, "rally": 0.22, "empower": 1.40}.get(kind, 0.56))
	asset["world_size"] = 0.68 if held_impact else float({"shield": 1.65,
		"rally": 1.38, "empower": 0.95}.get(kind, 1.10))
	if held_impact:
		asset["anchor"] = "target"
		asset["pivot"] = Vector2(0.5, 0.72)
		asset["opacity"] = 0.62
	if String(asset.get("anchor", "")) == "actor":
		if layer.has("height_m"):
			asset["height"] = float(layer["height_m"])
		if layer.has("world_size_m"):
			asset["world_size"] = float(layer["world_size_m"])
	asset["profile_key"] = String(profile.get("key", ""))
	return asset


func _ensure_status_visual(owner: String, kind: String, states: Array,
		at: Vector2, height_override: float = -1.0, profile: Dictionary = {}) -> bool:
	var status := _status_visual_for(owner)
	var profile_key := String(profile.get("key", ""))
	# A live state owns its texture until the actual state expires, including after deck-cache eviction.
	var same := not status.is_empty() and String(status.get("kind", "")) == kind \
		and String(status.get("profile_key", "")) == profile_key
	if not status.is_empty():
		_refresh_suspended_statuses(status, states, at)
	if not status.is_empty() and not same \
			and _status_profile_retired(status.get("profile", {}) as Dictionary, states):
		# A newer stun can end while an older curse remains. The owner still needs a status sprite,
		# but the outgoing stun must finish before its atlas ownership is replaced by that curse.
		# A recast/replacement of a still-live state is not an expiry and must not emit a fake break.
		status["at"] = at
		_spawn_status_event(status, "expire")
	elif not status.is_empty() and not same:
		_suspend_status_visual(status, profile, states)
	var restored: Dictionary = {}
	if not same and not status.is_empty():
		var suspended := status.get("suspended", {}) as Dictionary
		var arch := String(profile.get("arch", ""))
		var previous := suspended.get(arch, {}) as Dictionary
		if String(previous.get("profile_key", "")) == profile_key:
			restored = previous
		# A newer source for the same state replaces the old one; never keep every cast/card alive.
		suspended.erase(arch)
	var asset: Dictionary = status.get("asset", {}) as Dictionary if same else \
		(restored.get("asset", {}) as Dictionary if not restored.is_empty() else _status_asset(kind, profile))
	if asset.is_empty():
		var stale := _status_visual_for(owner)
		if not stale.is_empty():
			_release_status_visual(stale)
		return false
	if status.is_empty():
		for value in _status_pool:
			var candidate := value as Dictionary
			if not bool(candidate.get("active", false)):
				status = candidate
				break
	if status.is_empty():
		return false
	var node := status.get("node") as Sprite3D
	if node == null or not is_instance_valid(node):
		return false
	var changed := not same
	status["active"] = true
	status["owner"] = owner
	status["kind"] = kind
	status["profile_key"] = profile_key
	status["asset"] = asset
	if changed:
		status["profile"] = profile.duplicate(true)
		status["event_assets"] = (restored.get("event_assets", {}) as Dictionary).duplicate()
		status["body_event_asset"] = {}
		status["block_until"] = 0.0
		# Event windows share the live state's atlas. Retain these exact resources with the state,
		# so paging the deck cannot discard a later authored shield break or debuff expiry.
		if restored.is_empty() and _illustrated_only(profile):
			for role in ["block", "expire"]:
				var event_asset := AbilitySprites.reborn_effect_layer_asset(profile, role)
				if not event_asset.is_empty():
					(status["event_assets"] as Dictionary)[role] = event_asset
			if owner == "player:shield" and kind == "shield":
				var body := AbilitySprites.reborn_body_asset(profile)
				if not (body.get("events", {}) as Dictionary).is_empty():
					# The real shield, not the currently displayed deck page, owns its reaction art.
					# Retain one existing atlas only when this card supplies an authored event.
					status["body_event_asset"] = body
	# Snapshot belongs to the hit/buff application, not the player's later facing.
	status["direction"] = profile.get("_status_direction", Vector2.RIGHT) as Vector2
	status["states"] = states.duplicate()
	at = _illustrated_layer_at(asset, at, status["direction"] as Vector2)
	status["at"] = at
	status["height"] = float(asset.get("height", 0.5)) if height_override < 0.0 else height_override
	if String(asset.get("anchor", "")) == "floor":
		# A vortex/grounded debuff follows the afflicted actor's feet, not their face. Its world
		# position remains state-owned so moving or spawning another target cannot steal the mark.
		status["height"] = 0.04
	if changed or node.texture == null:
		var cell := asset.get("cell", StatusSprites.CELL) as Vector2i
		var pivot := _illustrated_billboard_pivot(asset, Vector2(0.5, 0.8))
		node.texture = asset.get("texture") as Texture2D
		node.material_override = asset.get("material") as Material
		node.pixel_size = float(asset.get("world_size", 1.0)) \
			/ float(maxi(1, (asset.get("cell", StatusSprites.CELL) as Vector2i).y))
		node.offset = Vector2((0.5 - pivot.x) * float(cell.x),
			(pivot.y - 0.5) * float(cell.y))
		node.render_priority = int(asset.get("render_priority", 0))
		node.region_enabled = true
	node.global_position = _illustrated_world_position(asset, at, float(status["height"]))
	var pose := _illustrated_layer_pose(asset.get("layer", {}) as Dictionary,
		status["direction"] as Vector2)
	node.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y if _fixed_y_illustrated_asset(asset) \
		else BaseMaterial3D.BILLBOARD_ENABLED
	node.rotation = Vector3(0.0, 0.0, float(pose["angle"]))
	node.flip_h = bool(pose["flip_h"])
	node.scale = Vector3.ONE * float(asset.get("scale", 1.0))
	node.modulate = Color(1.0, 1.0, 1.0, float(asset.get("opacity", 1.0)))
	node.visible = true
	return true


func _enemy_status_states(enemy: Dictionary) -> Array[String]:
	var states: Array[String] = []
	if float(enemy.get("stun", 0.0)) > 0.001: states.append("stun")
	if float(enemy.get("slow", 0.0)) > 0.001: states.append("slow")
	if float(enemy.get("weaken", 0.0)) > 0.001: states.append("weaken")
	if float(enemy.get("bleed", 0.0)) > 0.001: states.append("bleed")
	if int(enemy.get("armor_break", 0)) > 0: states.append("armor_break")
	return states


func _status_profile_snapshot(profile: Dictionary, direction: Vector2) -> Dictionary:
	var snapshot := profile.duplicate(true)
	var applied_direction := direction if direction.length_squared() > 0.0001 else _face_dir
	snapshot["_status_direction"] = applied_direction.normalized() \
		if applied_direction.length_squared() > 0.0001 else Vector2.RIGHT
	return snapshot


func _remember_trait_sunder_art(enemy: Dictionary, profile: Dictionary) -> void:
	if profile.is_empty():
		return
	var sources := enemy.get("status_profiles", {}) as Dictionary
	var snapshot := _status_profile_snapshot(profile,
		Vector2(enemy.get("p", _ppos)) - _ppos)
	snapshot["_trait_sunder_status"] = true
	sources.erase("weaken")
	sources["weaken"] = snapshot
	enemy["status_profiles"] = sources


func _remember_enemy_status_art(enemy: Dictionary, arch: String, profile: Dictionary,
		direction: Vector2 = Vector2.ZERO) -> void:
	if profile.is_empty() or arch not in ["rend", "jolt", "wither"]:
		return
	var sources := enemy.get("status_profiles", {}) as Dictionary
	var states: Array = {"rend": ["bleed", "armor_break"], "jolt": ["stun"],
		"wither": ["slow", "weaken"]}[arch]
	for state in states:
		sources.erase(state) # Latest applied, still-active ability owns the single bounded enemy loop.
		sources[state] = _status_profile_snapshot(profile, direction)
	enemy["status_profiles"] = sources


func _enemy_status_profile(enemy: Dictionary, states: Array) -> Dictionary:
	var sources := enemy.get("status_profiles", {}) as Dictionary
	var keys := sources.keys()
	keys.reverse()
	var chosen: Dictionary = {}
	for key in keys:
		if not states.has(key):
			sources.erase(key)
		elif chosen.is_empty():
			chosen = sources[key] as Dictionary
	return chosen


func _refresh_status_visuals(delta: float = 0.0) -> void:
	_status_clock += maxf(0.0, delta)
	if _status_pool.is_empty():
		return
	if not _entered or _stage_over:
		_clear_status_visuals()
		return
	var desired: Dictionary = {}
	if _shield > 0.001:
		desired["player:shield"] = true
		_ensure_status_visual("player:shield", "shield", ["shield"], _ppos, -1.0,
			_player_status_profiles.get("shield", {}) as Dictionary)
	else:
		_player_status_profiles.erase("shield")
	# The three real boons occupy intentionally separate zones—ward around the body, rally at the
	# feet, empowerment overhead—so simultaneous states remain visible for their full real duration.
	if _rally_t > 0.001:
		desired["player:rally"] = true
		_ensure_status_visual("player:rally", "rally", ["rally"], _ppos, -1.0,
			_player_status_profiles.get("rally", {}) as Dictionary)
	else:
		_player_status_profiles.erase("rally")
	if _empower_mul > 1.01:
		desired["player:empower"] = true
		_ensure_status_visual("player:empower", "empower", ["empower"], _ppos, -1.0,
			_player_status_profiles.get("empower", {}) as Dictionary)
	else:
		_player_status_profiles.erase("empower")
	for value in _enemy_pool:
		var enemy := value as Dictionary
		if not bool(enemy.get("active", false)):
			continue
		var states := _enemy_status_states(enemy)
		if states.is_empty():
			continue
		var owner := "enemy:%d" % int(enemy.get("eid", -1))
		desired[owner] = true
		var height := 0.56 + (0.22 if String(enemy.get("species", "")) == "shadowisp" else 0.0)
		_ensure_status_visual(owner, "corruption", states, Vector2(enemy.get("p", Vector2.ZERO)), height,
			_enemy_status_profile(enemy, states))
	if bool(_boss.get("active", false)):
		var boss_states := _enemy_status_states(_boss)
		# Grimwick's second phase is a real attack-state escalation. No boss shield/enrage is invented.
		if bool(_boss.get("awake", false)) and int(_boss.get("phase", 1)) == 2:
			boss_states.append("phase2")
		if not boss_states.is_empty():
			desired["boss:9999"] = true
			_ensure_status_visual("boss:9999", "corruption", boss_states,
				Vector2(_boss.get("p", Vector2.ZERO)), 0.92, _enemy_status_profile(_boss, boss_states))
	for value in _status_pool:
		var status := value as Dictionary
		if bool(status.get("active", false)) and not desired.has(String(status.get("owner", ""))):
			_refresh_suspended_statuses(status, [], status.get("at", Vector2.ZERO) as Vector2)
			_spawn_status_event(status, "expire")
			_release_status_visual(status)
	for value in _status_pool:
		var status := value as Dictionary
		if not bool(status.get("active", false)):
			continue
		var node := status.get("node") as Sprite3D
		var asset := status.get("asset", {}) as Dictionary
		if node == null or asset.is_empty():
			_release_status_visual(status)
			continue
		var frames := maxi(1, int(asset.get("frames", StatusSprites.FRAME_COUNT)))
		var frame := int(floor((_status_clock + float(status.get("phase", 0.0))) \
			* float(asset.get("fps", StatusSprites.FPS)))) % frames
		frame += int(asset.get("frame_start", 0))
		status["frame"] = frame
		var cell := asset.get("cell", StatusSprites.CELL) as Vector2i
		var grid := asset.get("grid", StatusSprites.GRID) as Vector2i
		node.region_rect = Rect2(float(frame % grid.x) * float(cell.x),
			float(int(frame / grid.x)) * float(cell.y), float(cell.x), float(cell.y))
		node.global_position = _illustrated_world_position(asset, status.get("at", Vector2.ZERO) as Vector2,
			float(status.get("height", 0.5)))


func _suspend_status_visual(status: Dictionary, incoming: Dictionary, states: Array) -> void:
	var profile := status.get("profile", {}) as Dictionary
	var arch := String(profile.get("arch", ""))
	if (arch not in ["rend", "jolt", "wither"] \
			and not bool(profile.get("_trait_sunder_status", false))) \
			or arch == String(incoming.get("arch", "")) \
			or _status_profile_retired(profile, states) \
			or String((status.get("asset", {}) as Dictionary).get("profile_key", "")).is_empty():
		return
	var suspended := status.get("suspended", {}) as Dictionary
	# Only real, currently live enemy-state archetypes can retain an interrupted sprite. This is
	# bounded by the existing ten slots: at most two hidden + one visible source per enemy slot,
	# never a new node, unbounded per-cast list or strong pin of the full ability catalogue.
	var saved: Dictionary = {}
	for key in ["profile", "asset", "event_assets", "direction", "at", "height", "kind",
			"profile_key", "owner", "block_until"]:
		saved[key] = status.get(key)
	saved["active"] = true
	suspended[arch] = saved
	status["suspended"] = suspended


func _refresh_suspended_statuses(status: Dictionary, states: Array, at: Vector2) -> void:
	var suspended := status.get("suspended", {}) as Dictionary
	for arch in suspended.keys():
		var saved := suspended[arch] as Dictionary
		if _status_profile_retired(saved.get("profile", {}) as Dictionary, states):
			saved["at"] = at
			_spawn_status_event(saved, "expire")
			suspended.erase(arch)


func _status_profile_retired(profile: Dictionary, states: Array) -> bool:
	if bool(profile.get("_trait_sunder_status", false)):
		return not states.has("weaken")
	var owned: Array = {"guard": ["shield"], "bulwark": ["shield"],
		"charge": ["empower"], "rally": ["rally"], "rend": ["bleed", "armor_break"],
		"jolt": ["stun"], "wither": ["slow", "weaken"]}.get(String(profile.get("arch", "")), [])
	for state in owned:
		if states.has(state):
			return false
	return not owned.is_empty()


func _spawn_status_event(status: Dictionary, role: String) -> bool:
	if role not in ["block", "expire"] or not bool(status.get("active", false)):
		return false
	var asset := (status.get("event_assets", {}) as Dictionary).get(role, {}) as Dictionary
	if asset.is_empty():
		return false # No invented generic flash for cards without an authored event window.
	var layer := asset.get("layer", {}) as Dictionary
	var window := asset.get("frames", Vector2i(-1, 0)) as Vector2i
	if window.x < 0 or window.y <= 0:
		return false
	var life := clampf(float(window.y) / maxf(1.0, float(layer.get("fps", 12.0))), 0.06, 0.6)
	var delay := maxf(0.0, float(status.get("block_until", 0.0)) - _status_clock) \
		if role == "expire" else 0.0
	var owner := String(status.get("owner", ""))
	var at := _ppos if owner.begins_with("player:") \
		else status.get("at", Vector2.ZERO) as Vector2
	var profile := status.get("profile", {}) as Dictionary
	var state_asset := status.get("asset", {}) as Dictionary
	if state_asset.has("world_size"):
		asset = asset.duplicate()
		# The break is the same physical wall, not a radius-scaled attack burst. Keep its atlas
		# pixel density continuous with the live state; each event still honors its reviewed scale.
		asset["_status_world_size"] = float(state_asset["world_size"])
	var spawned := _spawn_illustrated_card_layer(at, profile, role,
		float(profile.get("radius", 72.0)), life, float(status.get("height", 0.56)),
		-1, status.get("direction", Vector2.RIGHT) as Vector2, -1, false, asset, delay)
	if spawned and role == "block":
		status["block_until"] = _status_clock + life
	return spawned


func debug_status_visuals() -> Dictionary:
	_refresh_status_visuals(0.0)
	var active: Array[Dictionary] = []
	var per_owner: Dictionary = {}
	var per_actor: Dictionary = {}
	for value in _status_pool:
		var status := value as Dictionary
		if not bool(status.get("active", false)):
			continue
		var owner := String(status.get("owner", ""))
		per_owner[owner] = int(per_owner.get(owner, 0)) + 1
		var actor := "player" if owner.begins_with("player:") else owner
		per_actor[actor] = int(per_actor.get(actor, 0)) + 1
		var node := status.get("node") as Sprite3D
		active.append({"owner": owner, "kind": String(status.get("kind", "")),
			"states": (status.get("states", []) as Array).duplicate(),
			"frame": int(status.get("frame", 0)), "position": node.global_position if node != null else Vector3.ZERO,
			"visible": node != null and node.visible, "has_texture": node != null and node.texture != null,
			"asset_layer": String((status.get("asset", {}) as Dictionary).get("layer_name", "")),
			"node_id": node.get_instance_id() if node != null else 0,
			"region": node.region_rect if node != null else Rect2(),
			"pixel_size": node.pixel_size if node != null else 0.0,
			"profile_key": String(status.get("profile_key", "")),
			"direction": status.get("direction", Vector2.RIGHT),
			"angle": node.rotation.z if node != null else 0.0,
			"flip_h": node.flip_h if node != null else false,
			"scale": node.scale if node != null else Vector3.ONE,
			"source": "illustrated_card" if not String((status.get("asset", {}) as Dictionary).get("profile_key", "")).is_empty() else "shared_status",
			"cell": (status.get("asset", {}) as Dictionary).get("cell", StatusSprites.CELL),
			"grid": (status.get("asset", {}) as Dictionary).get("grid", StatusSprites.GRID)})
	var max_layers := 0
	for count_value in per_owner.values():
		max_layers = maxi(max_layers, int(count_value))
	var max_actor_layers := 0
	for count_value in per_actor.values():
		max_actor_layers = maxi(max_actor_layers, int(count_value))
	return {"pool_cap": _status_pool.size(), "active_count": active.size(), "active": active,
		"max_layers_per_status_key": max_layers, "max_layers_per_actor": max_actor_layers,
		"layers_per_actor": per_actor, "assets": StatusSprites.report()}


func _build_effect_pool() -> void:
	_effect_pool.clear()
	_fx_materials.clear()
	_fx_material_lru.clear()
	RebornFX.clear_cache()
	for i in range(_effect_cap):
		var sprite := Sprite3D.new()
		sprite.name = "HordeEffect_%d" % i
		sprite.texture = _orb_tex
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.shaded = false
		sprite.transparent = true
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		sprite.pixel_size = 0.012
		sprite.visible = false
		sprite.render_priority = 2
		add_child(sprite)
		_effect_pool.append({"node": sprite, "active": false, "life": 0.0, "max": 0.0,
			"start": 1.0, "end": 1.0, "rise": 0.0, "p": Vector2.ZERO, "height": 0.6,
			"spin": 0.0, "angle": 0.0, "pulse_count": 0, "pulse_phase": 0.0,
			"attack_id": -1, "profile_key": "", "layer_role": "generic", "sprite_sheet": false,
			"sheet_start": 0, "sheet_count": 0, "sheet_cell": AbilitySprites.CELL_PX,
			"sheet_cols": 0, "sheet_inset": 0.0, "axis_y": 1.0,
			"dedicated_card_sheet": false})

	# NO IMPACT LIGHTS. The first version of the effects pass allocated four pooled OmniLight3Ds
	# for impact flashes. dev_temple_horde_redesign counts every Light3D in the tree against a
	# reference-art budget of FOUR on HD (two on the phone) — a real cost ceiling for a WebGL
	# canvas, not a style rule — and the hall already spends all four. The flash is carried by the
	# additive shockwave ring instead, which on a dark floor reads as light without costing a pass.
	# The pool machinery stays so a future budget can turn it back on with one number.
	for l in _impact_lights:
		if l != null and is_instance_valid(l):
			(l as Node).queue_free()
	_impact_lights.clear()


func _build_travel_marker() -> void:
	if _travel_marker != null and is_instance_valid(_travel_marker):
		return
	_travel_marker = Node3D.new()
	_travel_marker.name = "NextSanctumMarker"
	_travel_marker.visible = false
	add_child(_travel_marker)
	var ring := _telegraph_mesh(Color("69f0d2"))
	ring.name = "RouteRune"
	ring.scale = Vector3(1.25, 1.0, 1.25)
	_travel_marker.add_child(ring)
	var beacon := Label3D.new()
	beacon.name = "RouteLabel"
	beacon.text = "NEXT SANCTUM"
	beacon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	beacon.font_size = 36
	beacon.pixel_size = 0.008
	beacon.outline_size = 8
	beacon.modulate = Color("d8fff4")
	beacon.position.y = 1.15
	beacon.no_depth_test = false
	_travel_marker.add_child(beacon)


func _build_floater_pool() -> void:
	_floater_pool.clear()
	for i in range(_floater_cap):
		var label := Label3D.new()
		label.name = "HordeFloater_%d" % i
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 44
		label.pixel_size = 0.008
		label.outline_size = 8
		label.outline_modulate = Color(0.03, 0.01, 0.06, 0.94)
		label.no_depth_test = true
		label.visible = false
		add_child(label)
		_floater_pool.append({"node": label, "active": false, "life": 0.0, "max": 0.0,
			"p": Vector2.ZERO, "height": 1.5})


func _cached_shadow(radius: float) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	var mesh := MeshInstance3D.new()
	mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.01, 0.0, 0.02, 0.46)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _orb_tex
	mat.render_priority = -1
	mesh.material_override = mat
	mesh.position.y = 0.012
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


func _telegraph_mesh(color: Color) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	var mesh := MeshInstance3D.new()
	mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.70)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _circle_tex
	mesh.material_override = mat
	mesh.position.y = 0.025
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


func _make_circle_texture(size: int, ring: bool) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var center := Vector2(float(size - 1), float(size - 1)) * 0.5
	var radius := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var d := Vector2(float(x), float(y)).distance_to(center) / radius
			var alpha := 0.0
			if ring:
				alpha = smoothstep(1.0, 0.86, d) * smoothstep(0.66, 0.78, d)
			else:
				alpha = pow(clampf(1.0 - d, 0.0, 1.0), 1.7)
			if alpha > 0.001:
				image.set_pixel(x, y, Color(1, 1, 1, alpha))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


# ================================= enemies =====================================================
func _activate_enemy(e: Dictionary, at: Vector2, wave_index: int) -> void:
	var species := String(e["species"])
	var mob: Dictionary = Econ.MOBS.get(species, {"hp": 180.0, "atk": 9.0, "el": "Beast"})
	var type_mul: float = float({"darkeet": 0.86, "shadowisp": 0.92,
		"hogwert": 1.08, "darkeon": 1.30}.get(species, 1.0))
	var level_hp := clampf(0.90 + 0.016 * float(_level() - 1), 0.90, 1.70)
	var hp_scale := (0.94 + float(wave_index) * 0.16) * float(type_mul) * level_hp
	e["maxhp"] = maxf(4.0, float(mob.get("hp", 180.0)) / 27.0 * hp_scale)
	e["hp"] = float(e["maxhp"])
	var level_damage := clampf(0.88 + 0.012 * float(_level() - 1), 0.88, 1.48)
	e["damage"] = float(mob.get("atk", 9.0)) * (0.50 + float(wave_index) * 0.055) * level_damage
	e["speed"] = float({"darkeet": 118.0, "shadowisp": 92.0, "hogwert": 82.0, "darkeon": 66.0}.get(species, 90.0))
	e["active"] = true
	e["awake"] = false
	e["p"] = at
	e["v"] = Vector2.ZERO
	e["state"] = "hunt"
	e["t"] = 0.45 + _rng.randf_range(0.0, 0.55)
	e["attack_cd"] = 0.8 + _rng.randf_range(0.0, 0.6)
	e["stun"] = 0.0; e["slow"] = 0.0; e["weaken"] = 0.0
	e["bleed"] = 0.0; e["bleed_tick"] = 0.0; e["bleed_profile"] = {}; e["armor_break"] = 0
	e["status_profiles"] = {}
	e["hit_flash"] = 0.0; e["wave"] = wave_index
	e["charge_hit"] = false; e["charge_hits"] = 0
	var body := e["body"] as Node3D
	body.visible = true
	body.scale = Vector3.ONE
	body.global_position = px2m(at, 0.0)
	var tele := e["tele"] as MeshInstance3D
	tele.visible = true
	tele.scale = Vector3(0.34, 1.0, 0.34)
	var rig := e["rig"] as Node3D
	_set_rig_combat_flash(rig, 0.0, Color("ff7aab"))
	# Only the painted Shadowisp body hovers. Its owner node, shadow and attack tell stay welded to
	# the floor, preventing the conspicuous floating ring/marker discrepancy.
	rig.position.y = 0.28 if species == "shadowisp" else 0.0
	rig.call("face", _arena_center - at)
	rig.call("play", "idle")
	_set_combat_nameplate(e.get("nameplate", {}) as Dictionary, _plate_display_name(species),
		float(e["hp"]), float(e["maxhp"]), _combat_nameplates_allowed())
	_effect(at, NP.el_color(String(mob.get("el", "Beast"))), 42.0, 0.38, 0.45)


func _deactivate_enemy(e: Dictionary) -> void:
	e["active"] = false
	e["awake"] = false
	_clear_status_owner("enemy:%d" % int(e.get("eid", -1)))
	_hide_combat_nameplate(e.get("nameplate", {}) as Dictionary)
	var body = e.get("body")
	if body != null and is_instance_valid(body):
		(body as Node3D).visible = false
	var tele = e.get("tele")
	if tele != null and is_instance_valid(tele):
		(tele as MeshInstance3D).visible = false


func _deactivate_all_enemies() -> void:
	for value in _enemy_pool:
		_deactivate_enemy(value as Dictionary)
	if not _boss.is_empty():
		_boss["active"] = false
		_boss["awake"] = false
	_clear_status_visuals("boss:")
	_hide_combat_nameplate(_boss_nameplate)
	if _boss_telegraph != null and is_instance_valid(_boss_telegraph):
		_boss_telegraph.visible = false


func _tick_enemies(delta: float) -> void:
	if _wave_phase not in ["prep", "fight", "reinforce"]:
		return
	for value in _enemy_pool:
		var e := value as Dictionary
		if not bool(e.get("active", false)):
			continue
		_tick_enemy_status(e, delta)
		if not bool(e.get("active", false)):
			continue
		var p := Vector2(e["p"])
		var body := e["body"] as Node3D
		var tele := e["tele"] as MeshInstance3D
		if not bool(e.get("awake", false)) or float(e.get("stun", 0.0)) > 0.0:
			tele.visible = true
			tele.scale = Vector3(0.36, 1.0, 0.36)
			body.global_position = px2m(p, 0.0)
			(e["rig"] as Node3D).position.y = 0.28 if String(e["species"]) == "shadowisp" else 0.0
			_sync_enemy_pose(e, Vector2.ZERO, _ppos - p)
			continue
		var species := String(e["species"])
		var to_player := _ppos - p
		var dist := to_player.length()
		var dir := to_player.normalized() if dist > 0.01 else Vector2.DOWN
		var slow_mul := 0.50 if float(e.get("slow", 0.0)) > 0.0 else 1.0
		e["attack_cd"] = maxf(0.0, float(e["attack_cd"]) - delta)
		e["t"] = float(e["t"]) - delta
		var moved := Vector2.ZERO
		match species:
			"darkeet": moved = _tick_darkeet(e, p, dir, dist, slow_mul, delta)
			"hogwert": moved = _tick_hogwert(e, p, dir, dist, slow_mul, delta)
			"shadowisp": moved = _tick_shadowisp(e, p, dir, dist, slow_mul, delta)
			"darkeon": moved = _tick_darkeon(e, p, dir, dist, slow_mul, delta)
		if _stage_over: return
		var next_p := _enemy_legal(p + moved)
		var actual := next_p - p
		e["p"] = next_p
		p = Vector2(e["p"])
		body.global_position = px2m(p, 0.0)
		(e["rig"] as Node3D).position.y = (0.28 + sin(_run_t * 3.2 + float(e["eid"])) * 0.10) \
			if species == "shadowisp" else 0.0
		_sync_enemy_pose(e, actual, dir)
	_resolve_enemy_separation()


func _tick_enemy_status(e: Dictionary, delta: float) -> void:
	for key in ["stun", "slow", "weaken", "hit_flash"]:
		e[key] = maxf(0.0, float(e.get(key, 0.0)) - delta)
	if float(e.get("bleed", 0.0)) > 0.0:
		e["bleed"] = maxf(0.0, float(e["bleed"]) - delta)
		e["bleed_tick"] = float(e.get("bleed_tick", 0.0)) - delta
		if float(e["bleed_tick"]) <= 0.0:
			e["bleed_tick"] = 0.56
			var bleed_profile := e.get("bleed_profile", {}) as Dictionary
			_damage_enemy(e, 0.55 + float(e.get("armor_break", 0)) * 0.12, "bleed", "",
				bleed_profile, Vector2(bleed_profile.get("_status_direction", Vector2.ZERO)))


func _tick_darkeet(e: Dictionary, _p: Vector2, dir: Vector2, dist: float, slow_mul: float, delta: float) -> Vector2:
	var tele := e["tele"] as MeshInstance3D
	if String(e["state"]) == "tell":
		tele.visible = true
		tele.scale = Vector3(0.60 + 0.12 * sin(_run_t * 18.0), 1.0, 0.60 + 0.12 * sin(_run_t * 18.0))
		if float(e["t"]) <= 0.0:
			e["state"] = "recover"; e["t"] = 0.42
			_enemy_melee(e, 126.0)
		return Vector2.ZERO
	if String(e["state"]) == "recover":
		tele.visible = false
		if float(e["t"]) <= 0.0: e["state"] = "hunt"
		return -dir * 28.0 * delta
	tele.visible = false
	if dist < 140.0 and float(e["attack_cd"]) <= 0.0:
		e["state"] = "tell"; e["t"] = 0.55; e["attack_cd"] = 1.32
		return Vector2.ZERO
	return dir * float(e["speed"]) * slow_mul * delta


func _tick_hogwert(e: Dictionary, p: Vector2, dir: Vector2, dist: float, slow_mul: float, delta: float) -> Vector2:
	var tele := e["tele"] as MeshInstance3D
	var state := String(e["state"])
	if state == "tell":
		tele.visible = true
		tele.scale = Vector3(1.15, 1.0, 1.15)
		if float(e["t"]) <= 0.0:
			e["state"] = "charge"; e["t"] = 0.52; e["charge_dir"] = dir
			e["charge_hit"] = false; e["charge_hits"] = 0
			(e["rig"] as Node3D).call("play", "attack")
		return Vector2.ZERO
	if state == "charge":
		tele.visible = false
		var step := Vector2(e["charge_dir"]) * 330.0 * slow_mul * delta
		var end := _enemy_legal(p + step)
		var closest := _closest_on_segment(_ppos, p, end)
		if not bool(e.get("charge_hit", false)) and closest.distance_to(_ppos) <= 42.0:
			e["charge_hit"] = true
			e["charge_hits"] = int(e.get("charge_hits", 0)) + 1
			var weak_mul := 0.64 if float(e.get("weaken", 0.0)) > 0.0 else 1.0
			_damage_player(float(e["damage"]) * 1.18 * weak_mul, closest)
			if _stage_over: return Vector2.ZERO
			_effect(closest, Color("ff7857"), 72.0, 0.32, 0.62)
		if float(e["t"]) <= 0.0:
			e["state"] = "recover"; e["t"] = 0.70
		return end - p
	if state == "recover":
		if float(e["t"]) <= 0.0: e["state"] = "hunt"
		return Vector2.ZERO
	tele.visible = false
	if dist < 285.0 and float(e["attack_cd"]) <= 0.0 and not _heavy_tell_active():
		e["state"] = "tell"; e["t"] = 0.95; e["attack_cd"] = 2.55
		return Vector2.ZERO
	return dir * float(e["speed"]) * slow_mul * delta


func _closest_on_segment(point: Vector2, start: Vector2, end: Vector2) -> Vector2:
	var segment := end - start
	var length_sq := segment.length_squared()
	if length_sq <= 0.0001:
		return start
	var along := clampf((point - start).dot(segment) / length_sq, 0.0, 1.0)
	return start + segment * along


func _tick_shadowisp(e: Dictionary, p: Vector2, dir: Vector2, dist: float, slow_mul: float, delta: float) -> Vector2:
	var tele := e["tele"] as MeshInstance3D
	if String(e["state"]) == "tell":
		tele.visible = true
		tele.scale = Vector3(0.72, 1.0, 0.72)
		if float(e["t"]) <= 0.0:
			_enemy_projectile(p, _ppos, float(e["damage"]), "hex")
			e["state"] = "hunt"; e["attack_cd"] = 1.75
		return Vector2.ZERO
	tele.visible = false
	if float(e["attack_cd"]) <= 0.0 and dist < 410.0:
		e["state"] = "tell"; e["t"] = 0.75
		return Vector2.ZERO
	var tangent := Vector2(-dir.y, dir.x) * (1.0 if int(e["eid"]) % 2 == 0 else -1.0)
	var radial := -dir if dist < 155.0 else (dir if dist > 255.0 else Vector2.ZERO)
	return (tangent * 0.72 + radial).normalized() * float(e["speed"]) * slow_mul * delta


func _tick_darkeon(e: Dictionary, p: Vector2, dir: Vector2, dist: float, slow_mul: float, delta: float) -> Vector2:
	var tele := e["tele"] as MeshInstance3D
	if String(e["state"]) == "tell":
		tele.visible = true
		tele.scale = Vector3(1.45, 1.0, 1.45)
		if float(e["t"]) <= 0.0:
			for angle in [-0.28, 0.0, 0.28]:
				_enemy_projectile(p, p + dir.rotated(float(angle)) * 400.0, float(e["damage"]), "void")
			e["state"] = "recover"; e["t"] = 0.65; e["attack_cd"] = 2.7
		return Vector2.ZERO
	if String(e["state"]) == "recover":
		tele.visible = false
		if float(e["t"]) <= 0.0: e["state"] = "hunt"
		return Vector2.ZERO
	tele.visible = false
	if float(e["attack_cd"]) <= 0.0 and dist < 330.0 and not _heavy_tell_active():
		e["state"] = "tell"; e["t"] = 1.00
		return Vector2.ZERO
	return dir * float(e["speed"]) * slow_mul * delta


func _enemy_melee(e: Dictionary, radius: float) -> void:
	var p := Vector2(e["p"])
	(e["rig"] as Node3D).call("face", _ppos - p)
	(e["rig"] as Node3D).call("play", "attack")
	_effect(_ppos.lerp(p, 0.5), Color("ff496f"), radius, 0.30, 0.70)
	if p.distance_to(_ppos) <= radius:
		_damage_player(float(e["damage"]) * (1.0 - (0.36 if float(e.get("weaken", 0.0)) > 0.0 else 0.0)), p)


func _enemy_projectile(from: Vector2, toward: Vector2, damage: float, arch: String) -> void:
	var projectile := _acquire_projectile()
	if projectile.is_empty():
		return
	var dir := (toward - from).normalized()
	projectile["owner"] = "enemy"; projectile["p"] = from; projectile["v"] = dir * 245.0
	projectile["life"] = 3.0; projectile["radius"] = 15.0; projectile["damage"] = damage
	projectile["arch"] = arch; projectile["element"] = "Void"; projectile["pierce"] = false
	projectile["hit_ids"] = {}; projectile["blast"] = 0.0; projectile["profile"] = {}
	projectile["hit_confirmed"] = false
	projectile["delivery"] = "enemy_orb"; projectile["target_eid"] = -1
	projectile["attack_id"] = _next_attack_id
	projectile["age"] = 0.0; projectile["trail_t"] = 0.0
	projectile["trail_interval"] = 0.105 if _low else 0.075
	projectile["base_scale"] = 1.15; projectile["visual_height"] = 0.78
	projectile["spin_rate"] = -1.8 if arch == "void" else 1.8
	_next_attack_id += 1
	var node := projectile["node"] as Sprite3D
	node.texture = _orb_tex
	node.material_override = null
	node.region_enabled = false
	node.pixel_size = 0.014
	var core := Color("e49bff") if arch in ["void", "eclipse"] else Color("ff88a5")
	projectile["core_color"] = core
	projectile["trail_color"] = Color("8e2fd0") if arch in ["void", "eclipse"] else Color("c72f63")
	node.modulate = core
	node.scale = Vector3.ONE * 1.15
	node.rotation.z = 0.0
	node.global_position = px2m(from, 0.78)
	node.visible = true


func _sync_enemy_pose(e: Dictionary, moved: Vector2, face_to_player: Vector2) -> void:
	var rig := e["rig"] as Node3D
	_set_rig_combat_flash(rig, float(e.get("hit_flash", 0.0)), Color("ff7aab"))
	var face := moved if moved.length_squared() > 0.01 else face_to_player
	rig.call("face", face)
	var clip := String(rig.call("clip")) if rig.has_method("clip") else "idle"
	if clip in ["hurt", "attack", "defeated"]:
		return
	var walking := moved.length_squared() > 0.01
	rig.call("play", "walk" if walking else "idle")
	if walking and rig.has_method("advance_walk_distance"):
		rig.call("advance_walk_distance", moved.length())


func _resolve_enemy_separation() -> void:
	var live: Array = []
	for value in _enemy_pool:
		if bool((value as Dictionary).get("active", false)):
			live.append(value)
	for i in range(live.size()):
		for j in range(i + 1, live.size()):
			var a := live[i] as Dictionary
			var b := live[j] as Dictionary
			var pa := Vector2(a["p"]); var pb := Vector2(b["p"])
			var delta := pb - pa
			var dist := delta.length()
			if dist > 0.01 and dist < 102.0:
				var push := delta / dist * (102.0 - dist) * 0.28
				a["p"] = _enemy_legal(pa - push)
				b["p"] = _enemy_legal(pb + push)
	# The player is a physical body in the composition, not a point enemies may stack on top of.
	for value in live:
		var e := value as Dictionary
		var ep := Vector2(e["p"])
		var away := ep - _ppos
		if away.length() > 0.01 and away.length() < ENEMY_PLAYER_CONTACT_DISTANCE_PX:
			e["p"] = _enemy_legal(_ppos + away.normalized() * ENEMY_PLAYER_CONTACT_DISTANCE_PX)


func _heavy_tell_active() -> bool:
	if bool(_boss.get("active", false)) and String(_boss.get("state", "")).begins_with("eclipse"):
		return true
	for value in _enemy_pool:
		var e := value as Dictionary
		if not bool(e.get("active", false)) or String(e.get("state", "")) != "tell":
			continue
		if String(e.get("species", "")) in ["hogwert", "darkeon"]:
			return true
	return false


func _enemy_legal(point: Vector2) -> Vector2:
	var p := point
	p.x = clampf(p.x, _arena_rect.position.x + 20.0, _arena_rect.end.x - 20.0)
	p.y = clampf(p.y, _arena_rect.position.y + 20.0, _arena_rect.end.y - 20.0)
	return p


func _damage_enemy(e: Dictionary, amount: float, arch: String, element: String,
		profile: Dictionary = {}, impact_direction: Vector2 = Vector2.ZERO) -> bool:
	if not bool(e.get("active", false)):
		return false
	var damage := maxf(0.0, amount) * _trait_damage_multiplier(arch, profile)
	if element != "":
		damage *= Econ.el_mult(element, String((Econ.MOBS.get(String(e["species"]), {}) as Dictionary).get("el", "Beast")))
	if int(e.get("armor_break", 0)) > 0 and arch != "rend":
		damage *= 1.0 + 0.12 * float(e["armor_break"])
	e["hp"] = float(e["hp"]) - damage
	e["hit_flash"] = 0.14
	match arch:
		"rend":
			e["bleed"] = maxf(float(e.get("bleed", 0.0)), 2.0)
			e["bleed_tick"] = 0.42
			if not profile.is_empty():
				e["bleed_profile"] = _status_profile_snapshot(profile, impact_direction)
			e["armor_break"] = mini(3, int(e.get("armor_break", 0)) + 1)
		"jolt":
			e["stun"] = maxf(float(e.get("stun", 0.0)), 0.42)
		"wither":
			e["slow"] = maxf(float(e.get("slow", 0.0)), 3.4)
			e["weaken"] = maxf(float(e.get("weaken", 0.0)), 3.4)
	var rig := e["rig"] as Node3D
	rig.call("play", "hurt")
	var palette := profile.get("palette", {}) as Dictionary
	var hit_color := Color(palette.get("core", palette.get("highlight", _element_color())))
	var defeated := float(e["hp"]) <= 0.0
	if profile.is_empty():
		_effect(Vector2(e["p"]), hit_color, 30.0 + damage * 2.0, 0.24, 0.85)
	else:
		_spawn_reborn_hit(Vector2(e["p"]), profile, defeated, impact_direction)
	if not defeated:
		_remember_enemy_status_art(e, arch, profile, impact_direction)
	if arch != "bleed":
		_register_hit(arch, damage, Vector2(e["p"]), e, profile)
	if defeated:
		_defeat_enemy(e, arch, profile)
	else:
		_set_combat_nameplate(e.get("nameplate", {}) as Dictionary,
			_plate_display_name(String(e["species"])), float(e["hp"]), float(e["maxhp"]),
			_combat_nameplates_allowed())
	_refresh_status_visuals(0.0)
	return true


func _defeat_enemy(e: Dictionary, arch: String, profile: Dictionary = {}) -> void:
	if not bool(e.get("active", false)):
		return
	var at := Vector2(e["p"])
	var rig := e["rig"] as Node3D
	rig.call("play", "defeated")
	if profile.is_empty():
		_effect(at, Color("9b5cff"), 78.0, 0.50, 1.0)
	_float_text(at, "+100  PURGED", Color("ffc96a"))
	_score += 100 + mini(80, _combo * 3)
	_kills += 1
	if not _debug_casting:
		_energy = minf(ENERGY_MAX, _energy + 0.28)
	_play_sfx(SFX_FOE, 0.94 + _rng.randf_range(-0.06, 0.06))
	_deactivate_enemy(e)


# ================================= Grimwick ====================================================
func _prepare_boss() -> void:
	if _grim_rig == null or not is_instance_valid(_grim_rig):
		return
	_configure_enemy_visibility(_grim_rig)
	var body := _grim_rig.get_parent() as Node3D
	body.scale = Vector3.ONE * (BOSS_RIG_H_M / 2.4)
	var old_boss_root := _boss_nameplate.get("root") as Node3D
	if old_boss_root == null or not is_instance_valid(old_boss_root) \
			or old_boss_root.get_parent() != body:
		_boss_nameplate = _make_combat_nameplate(body, "GrimwickCombatNameplate",
			3.20, COMBAT_PLATE_ENEMY, false)
	var level_hp := clampf(0.92 + 0.012 * float(_level() - 1), 0.92, 1.52)
	var boss_hp := 110.0 * level_hp
	var boss_damage := 16.0 * clampf(0.92 + 0.010 * float(_level() - 1), 0.92, 1.40)
	_boss = {"active": true, "awake": false, "body": body, "rig": _grim_rig,
		"p": _arena_center + Vector2(0.0, -170.0), "hp": boss_hp,
		"maxhp": boss_hp, "state": "idle", "t": 1.2, "phase": 1,
		"damage": boss_damage, "weaken": 0.0, "stun": 0.0, "armor_break": 0, "eid": 9999,
		"aoe_at": Vector2.ZERO, "tell_total": 0.0, "resolutions": 0, "hit_flash": 0.0}
	if _boss_telegraph != null and is_instance_valid(_boss_telegraph):
		_boss_telegraph.visible = false
	body.visible = true
	body.global_position = px2m(Vector2(_boss["p"]), 0.60)
	_grim_rig.call("face", Vector2.DOWN)
	_grim_rig.call("play", "idle")
	_set_combat_nameplate(_boss_nameplate, "GRIMWICK", boss_hp, boss_hp,
		_combat_nameplates_allowed())


func _tick_boss(delta: float) -> void:
	if not bool(_boss.get("active", false)) or not bool(_boss.get("awake", false)):
		return
	_boss["hit_flash"] = maxf(0.0, float(_boss.get("hit_flash", 0.0)) - delta)
	_set_rig_combat_flash(_boss.get("rig") as Node3D,
		float(_boss.get("hit_flash", 0.0)), Color("ff7aab"))
	_boss["stun"] = maxf(0.0, float(_boss.get("stun", 0.0)) - delta)
	_boss["weaken"] = maxf(0.0, float(_boss.get("weaken", 0.0)) - delta)
	if float(_boss["stun"]) > 0.0:
		if String(_boss.get("state", "idle")) == "eclipse_tell":
			_boss["state"] = "idle"
			_boss["t"] = 0.55
			_hide_boss_telegraph()
			_set_message("ECLIPSE INTERRUPTED", 0.7)
		return
	_boss["t"] = float(_boss["t"]) - delta
	var p := Vector2(_boss["p"])
	var rig := _boss["rig"] as Node3D
	var phase := 1 if float(_boss["hp"]) > float(_boss["maxhp"]) * 0.56 else 2
	_boss["phase"] = phase
	var state := String(_boss.get("state", "idle"))
	if phase == 1:
		if state.begins_with("eclipse"):
			_boss["state"] = "idle"
			_hide_boss_telegraph()
		if float(_boss["t"]) <= 0.0:
			for angle in [-0.46, -0.22, 0.0, 0.22, 0.46]:
				_enemy_projectile(p, p + (_ppos - p).normalized().rotated(float(angle)) * 500.0,
					float(_boss["damage"]), "void")
			_boss["t"] = 2.35
			rig.call("play", "attack")
		else:
			_boss_drift(p, 38.0, delta)
		_place_boss()
		return

	match state:
		"eclipse_tell":
			_update_boss_telegraph()
			if float(_boss["t"]) <= 0.0:
				_resolve_boss_eclipse()
			else:
				rig.call("face", Vector2(_boss["aoe_at"]) - p)
		"eclipse_recover":
			_hide_boss_telegraph()
			if float(_boss["t"]) <= 0.0:
				_boss["state"] = "idle"
				_boss["t"] = 0.42
		_:
			if float(_boss["t"]) <= 0.0:
				_start_boss_eclipse()
			else:
				_boss_drift(p, 62.0, delta)
	_place_boss()


func _boss_drift(from: Vector2, speed: float, delta: float) -> void:
	var to_player := _ppos - from
	if to_player.length_squared() <= 0.01:
		return
	_boss["p"] = _enemy_legal(from + to_player.normalized() * speed * delta)
	(_boss["rig"] as Node3D).call("face", _ppos - Vector2(_boss["p"]))


func _place_boss() -> void:
	if not bool(_boss.get("active", false)):
		return
	(_boss["body"] as Node3D).global_position = px2m(Vector2(_boss["p"]),
		0.60 + sin(_run_t * 2.2) * 0.10)


func _start_boss_eclipse() -> void:
	var delay := 1.00
	_boss["state"] = "eclipse_tell"
	_boss["t"] = delay
	_boss["tell_total"] = delay
	_boss["aoe_at"] = _ppos
	var rig := _boss["rig"] as Node3D
	rig.call("face", Vector2(_boss["aoe_at"]) - Vector2(_boss["p"]))
	rig.call("play", "attack")
	if _boss_telegraph != null and is_instance_valid(_boss_telegraph):
		_boss_telegraph.visible = true
		_boss_telegraph.global_position = px2m(Vector2(_boss["aoe_at"]), 0.035)
		var radius_m := 150.0 * PX2M
		_boss_telegraph.scale = Vector3(radius_m * 0.26, 1.0, radius_m * 0.26)
	_float_text(Vector2(_boss["aoe_at"]), "DODGE ECLIPSE", Color("ff8cff"))
	_set_message("GRIMWICK: ECLIPSE  ·  DODGE!", delay)


func _update_boss_telegraph() -> void:
	if _boss_telegraph == null or not is_instance_valid(_boss_telegraph):
		return
	var total := maxf(0.001, float(_boss.get("tell_total", 0.78)))
	var progress := clampf(1.0 - float(_boss["t"]) / total, 0.0, 1.0)
	var radius_m := 150.0 * PX2M
	var pulse := 1.0 + sin(progress * TAU * 4.0) * 0.035
	var scale := lerpf(radius_m * 0.26, radius_m, progress) * pulse
	_boss_telegraph.scale = Vector3(scale, 1.0, scale)


func _resolve_boss_eclipse() -> void:
	var p := Vector2(_boss["p"])
	var aoe_at := Vector2(_boss["aoe_at"])
	_hide_boss_telegraph()
	_effect(aoe_at, Color("ef4cff"), 165.0, 0.34, 0.38)
	if _ppos.distance_to(aoe_at) < 150.0:
		_damage_player(float(_boss["damage"]) * 1.25 \
			* (0.64 if float(_boss["weaken"]) > 0.0 else 1.0), aoe_at)
		if _stage_over: return
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		_enemy_projectile(p, p + Vector2.from_angle(float(angle)) * 500.0,
			float(_boss["damage"]) * 0.8, "eclipse")
	_boss["resolutions"] = int(_boss.get("resolutions", 0)) + 1
	_boss["state"] = "eclipse_recover"
	_boss["t"] = 0.72
	(_boss["rig"] as Node3D).call("play", "attack")


func _hide_boss_telegraph() -> void:
	if _boss_telegraph != null and is_instance_valid(_boss_telegraph):
		_boss_telegraph.visible = false


func _damage_boss_horde(amount: float, arch: String, element: String,
		profile: Dictionary = {}, impact_direction: Vector2 = Vector2.ZERO) -> bool:
	if not bool(_boss.get("active", false)):
		return false
	var damage := amount * (Econ.el_mult(element, "Light") if element != "" else 1.0) \
		* _trait_damage_multiplier(arch, profile)
	if int(_boss.get("armor_break", 0)) > 0 and arch != "rend":
		damage *= 1.0 + 0.10 * float(_boss["armor_break"])
	_boss["hp"] = float(_boss["hp"]) - damage
	match arch:
		"rend": _boss["armor_break"] = mini(3, int(_boss.get("armor_break", 0)) + 1)
		"jolt": _boss["stun"] = maxf(float(_boss.get("stun", 0.0)), 0.48)
		"wither": _boss["weaken"] = maxf(float(_boss.get("weaken", 0.0)), 3.6)
	(_boss["rig"] as Node3D).call("play", "hurt")
	_boss["hit_flash"] = 0.14
	var palette := profile.get("palette", {}) as Dictionary
	var hit_color := Color(palette.get("core", palette.get("highlight", _element_color())))
	var defeated := float(_boss["hp"]) <= 0.0
	if profile.is_empty():
		_effect(Vector2(_boss["p"]), hit_color, 44.0 + damage * 2.0, 0.28, 1.1)
	else:
		_spawn_reborn_hit(Vector2(_boss["p"]), profile, defeated, impact_direction)
	if not defeated:
		_remember_enemy_status_art(_boss, arch, profile, impact_direction)
	_register_hit(arch, damage, Vector2(_boss["p"]), _boss, profile)
	if defeated:
		_defeat_boss(arch, profile)
	else:
		_set_combat_nameplate(_boss_nameplate, "GRIMWICK", float(_boss["hp"]),
			float(_boss["maxhp"]), _combat_nameplates_allowed())
	_refresh_status_visuals(0.0)
	return true


func _defeat_boss(_arch: String, profile: Dictionary = {}) -> void:
	if not bool(_boss.get("active", false)):
		return
	_boss["active"] = false
	_boss["awake"] = false
	_clear_status_visuals("boss:")
	_hide_combat_nameplate(_boss_nameplate)
	_hide_boss_telegraph()
	(_boss["rig"] as Node3D).call("play", "defeated")
	if profile.is_empty():
		_effect(Vector2(_boss["p"]), Color("ffc96a"), 190.0, 0.85, 1.4)
	_float_text(Vector2(_boss["p"]), "GRIMWICK PURGED  +2000", Color("ffc96a"))
	_score += 2000
	_kills += 1
	_play_sfx(SFX_WIN, 1.0)


# ================================= player card combat =========================================
func _species() -> String:
	return String(_selected_unit.get("species", "firix"))


func _kind() -> String:
	return String(_selected_unit.get("kind", Econ.unit_kind(_species())))


func _level() -> int:
	return clampi(int(_selected_unit.get("level", 1)), 1, Econ.LEVEL_CAP)


func _rarity() -> Dictionary:
	return RARITY_STATS.get(_kind(), RARITY_STATS["normal"]) as Dictionary


func _rarity_damage() -> float:
	return float(_rarity()["damage"])


func _rarity_hp() -> float:
	return float(_rarity()["hp"])


func _trait_reach() -> float:
	return clampf(float(_species_trait.get("reach", 1.0)), 0.9, 1.1)


func _trait_signature_hit(arch: String, profile: Dictionary) -> bool:
	return arch == String(_species_trait.get("signature_arch", "")) \
		and int(profile.get("combat_attack_id", -1)) > 0


func _trait_damage_multiplier(arch: String, profile: Dictionary) -> float:
	return 1.07 if _trait_signature_hit(arch, profile) \
		and String(_species_trait.get("signature_effect", "")) == "fury" else 1.0


func _trait_feedback(label: String) -> void:
	_trait_procs += 1
	_float_text(_ppos, "%s  ·  %s" % [String(_species_trait.get("name", "TRAIT")).to_upper(), label],
		_element_color())


func _trait_mark_cast(attack_id: int) -> void:
	_trait_proc_ids.append(attack_id)
	if _trait_proc_ids.size() > 32:
		_trait_proc_ids.pop_front()


func _trait_on_self_cast(arch: String, profile: Dictionary) -> void:
	if not _trait_signature_hit(arch, profile):
		return
	var attack_id := int(profile["combat_attack_id"])
	if _trait_proc_ids.has(attack_id):
		return
	match String(_species_trait.get("signature_effect", "")):
		"surge":
			if _energy >= ENERGY_MAX - 0.001:
				return
			_energy = minf(ENERGY_MAX, _energy + 0.25)
			_trait_feedback("+ENERGY")
		"recover":
			if _hp >= _max_hp - 0.001:
				return
			_apply_heal(4.0)
			_trait_feedback("+HEALTH")
		_:
			return
	_trait_mark_cast(attack_id)


func _trait_on_confirmed_hit(arch: String, target: Dictionary, profile: Dictionary) -> void:
	if not _trait_signature_hit(arch, profile):
		return
	var attack_id := int(profile["combat_attack_id"])
	if _trait_proc_ids.has(attack_id):
		return
	match String(_species_trait.get("signature_effect", "")):
		"surge":
			if _energy >= ENERGY_MAX - 0.001:
				return
			_energy = minf(ENERGY_MAX, _energy + 0.25)
			_trait_feedback("+ENERGY")
		"recover":
			if _hp >= _max_hp - 0.001:
				return
			_apply_heal(4.0)
			_trait_feedback("+HEALTH")
		"sunder":
			# Temple foes have no card-energy pool. A two-second weakened attack is the
			# equivalent tactical opening: long enough for Hogwert's tell and charge,
			# but shorter than an authored Wither. Recasts remain capped.
			var existing := float(target.get("weaken", 0.0))
			var extended := minf(4.1, maxf(existing + 0.7, 2.0))
			if extended <= existing + 0.001:
				return
			target["weaken"] = extended
			_remember_trait_sunder_art(target, profile)
			_trait_feedback("FOE WEAKENED")
		"fury":
			_trait_feedback("FAVORED HIT")
		_:
			return
	_trait_mark_cast(attack_id)


func _element_color() -> Color:
	return NP.el_color(Econ.el_of(_species()))


func _card_pages() -> int:
	return maxi(1, int(ceil(float(_card_slots.size()) / 3.0)))


func _page_indices() -> Array:
	var out: Array = []
	var start := _card_page * 3
	for i in range(start, mini(start + 3, _card_slots.size())):
		out.append(i)
	return out


func _active_card_slot() -> int:
	if _card_slots.is_empty():
		return 0
	return int(_card_slots[clampi(_card_at, 0, _card_slots.size() - 1)])


func _card_cooldown(slot: int) -> float:
	return float(_card_cooldowns.get(slot, 0.0))


func _card_name(slot: int) -> String:
	var names: Array = Econ.CARD_NAMES.get(_species(), [])
	if slot >= 0 and slot < names.size() and names[slot] is Array and names[slot].size() >= 2:
		return String(names[slot][1])
	return String((Econ.CARDS[clampi(slot, 0, Econ.CARDS.size() - 1)] as Dictionary).get("name", "Strike"))


# THE PHONE ICON CROP IS PER TEMPLATE, NOT ONE BOX FOR ALL 402 CARDS. The single box shipped in
# b59ffeda2e was measured off ONE card and only frames its own family: on the wave-1 legendaries it
# swallowed the name banner and the description, and on the meme cards it caught the archetype chip
# and the DAMAGE bar — so a phone showed cropped TEXT where an ability icon should be.
#
# Each box below is a CENTRED, near-square window running from just BELOW the badge row down to
# just above the name banner, so no cost badge, element chip, banner or stat line can enter it.
# Measured off a percentage grid and verified by eye against 32 cards spanning every family, the
# ten galador cards with a baked margin, and the twenty cards whose source aspect is not 2:3.
const CARD_ART_BOX := {
	"legend1": Rect2(0.2938, 0.170, 0.4125, 0.275),   # species 10-14, the wave-1 legendary frame
	# legend2's bottom is 0.485, not the 0.535 first measured off three cards: rendering ALL 108 of
	# them showed a dozen leaking their name banner ("JADE PALM", "WEST PAW"). 0.485 is the minimum
	# banner top across the family, from a ruler validated against four hand-read cards.
	"legend2": Rect2(0.30125, 0.220, 0.3975, 0.265),  # species 31-39, the wave-2 legendary frame
	"meme":    Rect2(0.1820, 0.215, 0.6370, 0.425),   # species 15-20 and 40-50, the meme banner
	"plain":   Rect2(0.1590, 0.245, 0.6820, 0.455),   # species 21-30, the minimal frame
}


# TEN OF GALADOR'S TWELVE CARDS WERE RENDERED ONTO A WHITE PAGE. cards/10_1..10_10.jpg carry a flat
# light border baked into the image, which shows as a white halo around the card in the hand — and
# it is also why those ten are the wrong shape: their source aspect reads 0.66-0.71 instead of 2:3,
# and trimming the border brings every one of them back to 0.660-0.679. Insets measured per card
# (they are not uniform: 15-34 px left, 0-26 px bottom) and stored as fractions so they survive any
# resample. dev_cardbox asserts each entry STILL has a light border, so if the art is ever
# re-exported the probe fails loudly rather than silently cropping good art.
#
# The other ten off-aspect cards (10_11, 12_10, 12_11 and seven of dragonos's) have NO border to
# trim — they are genuinely mis-proportioned renders and need re-exporting at 2:3.
const CARD_TRIM := {
	"10_1": Rect2(0.06364, 0.02408, 0.87273, 0.93258),
	"10_2": Rect2(0.06818, 0.02412, 0.86818, 0.93248),
	"10_3": Rect2(0.05227, 0.02087, 0.88182, 0.93900),
	"10_4": Rect2(0.07955, 0.02090, 0.87955, 0.94051),
	"10_5": Rect2(0.04318, 0.02408, 0.92500, 0.96308),
	"10_6": Rect2(0.03636, 0.02412, 0.92045, 0.96302),
	"10_7": Rect2(0.04091, 0.02087, 0.93182, 0.97753),
	"10_8": Rect2(0.04091, 0.02090, 0.93409, 0.97749),
	"10_9": Rect2(0.04318, 0.02568, 0.92500, 0.96950),
	"10_10": Rect2(0.04318, 0.02572, 0.92045, 0.96945),
}

# Which frame a given card wears. Keyed off the species INDEX because the frame follows the render
# batch, not the creature — with one measured exception: cards/20_0..20_2.jpg are drolax's minimal
# cards misfiled under alon's index, so alon's first three slots wear the plain frame while its
# other nine wear the meme banner. That exception is a SYMPTOM: those three files are the wrong
# creature's art and want replacing, at which point this special case should go with them.
func _frame_family_for(idx: int, slot: int) -> String:
	if idx == 20:
		return "plain" if slot < 3 else "meme"
	if idx >= 10 and idx <= 14:
		return "legend1"
	if idx >= 21 and idx <= 30:
		return "plain"
	if idx >= 31 and idx <= 39:
		return "legend2"
	return "meme"


func _card_frame_family(slot: int) -> String:
	return _frame_family_for(CardArt.species_index(_species()), slot)


# THE TRIM APPLIES ON BOTH PLATFORMS; the icon crop applies only on a phone, and it is taken as a
# fraction OF THE TRIMMED CARD, not of the raw file — otherwise a bordered card's icon would be
# offset by the border it still carried.
func _card_source_rect(slot: int, tex: Texture2D, phone: bool = false) -> Rect2:
	return _source_rect_for(CardArt.species_index(_species()), slot, tex.get_size(), phone)


func _source_rect_for(idx: int, slot: int, sz: Vector2, phone: bool) -> Rect2:
	var key := "%d_%d" % [idx, slot]
	var t: Rect2 = CARD_TRIM.get(key, Rect2(0.0, 0.0, 1.0, 1.0))
	var card := Rect2(sz.x * t.position.x, sz.y * t.position.y, sz.x * t.size.x, sz.y * t.size.y)
	# Full authored card on every screen. Only the reviewed exterior white-page trim remains;
	# the former phone-only square artwork crop is no longer used by hand or inspection.
	return card


func _card_texture(slot: int) -> Texture2D:
	if not _card_texture_cache.has(slot):
		_card_texture_cache[slot] = _card_texture_region(slot, false)
	return _card_texture_cache.get(slot) as Texture2D


func _card_preview_texture(slot: int) -> Texture2D:
	if not _card_preview_texture_cache.has(slot):
		_card_preview_texture_cache[slot] = _card_texture_region(slot, false)
	return _card_preview_texture_cache.get(slot) as Texture2D


func _card_texture_region(slot: int, phone_crop: bool) -> Texture2D:
	var tex := CardArt.texture(_species(), slot)
	if tex == null:
		return null
	var region := _card_source_rect(slot, tex, phone_crop)
	if not region.is_equal_approx(Rect2(Vector2.ZERO, tex.get_size())):
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = region
		return atlas
	return tex


func debug_card_art_box(species: String, slot: int) -> Dictionary:
	var idx := CardArt.species_index(species)
	var fam := _frame_family_for(idx, slot)
	return {"family": fam, "box": CARD_ART_BOX.get(fam, Rect2()),
		"trimmed": CARD_TRIM.has("%d_%d" % [idx, slot])}


func debug_card_regions(species: String, slot: int, sz: Vector2) -> Dictionary:
	var idx := CardArt.species_index(species)
	return {"desktop": _source_rect_for(idx, slot, sz, false),
		"phone": _source_rect_for(idx, slot, sz, true)}


func _select_visible_card(visible_index: int) -> void:
	var indices := _page_indices()
	if visible_index < 0 or visible_index >= indices.size():
		return
	_card_at = int(indices[visible_index])
	if _card_at >= 0 and _card_at < _card_slots.size():
		# Hover/focus is useful download time. Promote the exact pair here instead of waiting until the
		# cast frame, where a healthy connection could still show the compact fallback once.
		_queue_profile_art(AbilityVisual.profile(_species(), int(_card_slots[_card_at])), true)
	_refresh_hud(true)


func _phone_hud_active() -> bool:
	return bool(MobileViewport.sample(get_viewport())["touch"])


func _card_draw_node(visible_index: int) -> Control:
	if visible_index < 0 or visible_index >= _card_hud.size():
		return null
	var ui := _card_hud[visible_index] as Dictionary
	return ui.get("draw", ui.get("panel")) as Control


func _stop_card_draw_tween(visible_index: int) -> void:
	var running = _card_draw_tweens.get(visible_index)
	if running is Tween and (running as Tween).is_valid():
		(running as Tween).kill()
	_card_draw_tweens.erase(visible_index)


func _animate_card_draw(visible_index: int, drawn: bool, immediate: bool = false) -> void:
	var face := _card_draw_node(visible_index)
	if face == null or not is_instance_valid(face):
		return
	_stop_card_draw_tween(visible_index)
	face.modulate = Color.WHITE
	# Phones have no hover and cannot spare overlap around the thumb targets. Keeping the authored
	# slot motionless also makes synthetic browser mouse events harmless on touch hardware.
	if _phone_hud_active():
		drawn = false
		immediate = true
	face.pivot_offset = Vector2(face.size.x * 0.5, face.size.y)
	var target_position := Vector2(0.0, -CARD_DRAW_LIFT) if drawn else Vector2.ZERO
	var target_scale := Vector2.ONE * CARD_DRAW_SCALE if drawn else Vector2.ONE
	face.z_index = 24 if drawn else 1
	if immediate or not is_inside_tree():
		face.position = target_position
		face.scale = target_scale
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(face, "position", target_position, CARD_DRAW_TIME)
	tween.tween_property(face, "scale", target_scale, CARD_DRAW_TIME)
	_card_draw_tweens[visible_index] = tween


func _reset_card_draws(immediate: bool = true) -> void:
	_preview_hover_index = -1
	_preview_focus_index = -1
	for i in range(_card_hud.size()):
		_animate_card_draw(i, false, immediate)
	if _card_preview != null and is_instance_valid(_card_preview):
		_card_preview.visible = false


func _on_card_preview_hover(visible_index: int, entered: bool) -> void:
	if _phone_hud_active():
		_preview_hover_index = -1
		_animate_card_draw(visible_index, false, true)
		_update_card_preview()
		return
	if entered:
		if _preview_hover_index >= 0 and _preview_hover_index != visible_index \
				and _preview_focus_index != _preview_hover_index:
			_animate_card_draw(_preview_hover_index, false)
		_preview_hover_index = visible_index
		_animate_card_draw(visible_index, true)
	elif _preview_hover_index == visible_index:
		_preview_hover_index = -1
		_animate_card_draw(visible_index, _preview_focus_index == visible_index)
	_update_card_preview()


func _on_card_preview_focus(visible_index: int, entered: bool) -> void:
	if entered:
		if _preview_focus_index >= 0 and _preview_focus_index != visible_index \
				and _preview_hover_index != _preview_focus_index:
			_animate_card_draw(_preview_focus_index, false)
		_preview_focus_index = visible_index
		_select_visible_card(visible_index)
		_animate_card_draw(visible_index, not _phone_hud_active())
	else:
		if _preview_focus_index == visible_index:
			_preview_focus_index = -1
		_animate_card_draw(visible_index, _preview_hover_index == visible_index)
		_update_card_preview()


func _update_card_preview() -> void:
	if _card_preview == null or not is_instance_valid(_card_preview):
		return
	var visible_index := _touch_inspect_index if _touch_inspect_index >= 0 else (
		_preview_focus_index if _preview_focus_index >= 0 else _preview_hover_index)
	if _phone_hud_active() and (_touch_inspect_index < 0 or _card_preview.size.x <= 0.0):
		_card_preview.visible = false
		return
	var indices := _page_indices()
	if visible_index < 0 or visible_index >= indices.size():
		_card_preview.visible = false
		return
	var global_index := int(indices[visible_index])
	if global_index < 0 or global_index >= _card_slots.size():
		_card_preview.visible = false
		return
	var slot := int(_card_slots[global_index])
	var card := Econ.CARDS[clampi(slot, 0, Econ.CARDS.size() - 1)] as Dictionary
	_card_preview_art.texture = _card_preview_texture(slot)
	_card_preview_name.text = _card_name(slot).to_upper()
	_card_preview_detail.text = "%s  ·  COST %d  ·  %s" % [
		String(card.get("arch", "strike")).to_upper(), int(card.get("cost", 1)),
		"READY" if _card_cooldown(slot) <= 0.01 else "%.1fs" % _card_cooldown(slot)]
	if _phone_hud_active() and _card_preview_art.texture != null \
			and (not _card_preview.visible or _mobile_preview_draw_index != global_index):
		if _mobile_preview_draw_tween != null and _mobile_preview_draw_tween.is_valid():
			_mobile_preview_draw_tween.kill()
		_mobile_preview_draw_index = global_index
		_card_preview.pivot_offset = _card_preview.size
		_card_preview.scale = Vector2.ONE * 0.88
		_mobile_preview_draw_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_mobile_preview_draw_tween.tween_property(_card_preview, "scale", Vector2.ONE, 0.12)
	_card_preview.visible = _card_preview_art.texture != null


func _on_card_pressed(visible_index: int) -> void:
	var indices := _page_indices()
	if visible_index < 0 or visible_index >= indices.size():
		return
	var global_index := int(indices[visible_index])
	_card_at = global_index
	_refresh_hud(true)
	var recovery_busy := _attack_cd > 0.0 or not _pending_cast.is_empty() or not _card_dash.is_empty()
	var activated := _activate_card()
	# A single short buffer makes quick keyboard/controller/touch sequences feel intentional without
	# auto-playing a stale command. Cooldown/energy failures still fail immediately and visibly.
	if not activated and recovery_busy and not _stage_over \
			and _wave_phase in ["fight", "reinforce"] and _input_on:
		_buffered_card_at = global_index
		_card_buffer_t = CARD_INPUT_BUFFER
		_set_message("%s  ·  QUEUED" % _card_name(int(_card_slots[global_index])).to_upper(), 0.45)
	# Mouse clicks must not leave a hidden keyboard focus trap behind. A keyboard/controller focus
	# still receives its activation first; releasing afterward restores SPACE as Dodge on the next beat.
	if visible_index < _card_hud.size():
		var button := (_card_hud[visible_index] as Dictionary).get("button") as TextureButton
		if button != null and is_instance_valid(button) and button.has_focus():
			button.release_focus()


func _tick_card_buffer() -> void:
	if _buffered_card_at < 0:
		return
	if _card_buffer_t <= 0.0 or _stage_over or _wave_phase not in ["fight", "reinforce"]:
		_buffered_card_at = -1
		_card_buffer_t = 0.0
		return
	if _attack_cd > 0.0 or not _pending_cast.is_empty() or not _card_dash.is_empty():
		return
	var buffered := _buffered_card_at
	_buffered_card_at = -1
	_card_buffer_t = 0.0
	if buffered < 0 or buffered >= _card_slots.size():
		return
	_card_at = buffered
	_activate_card()


func _next_card_page() -> void:
	_page_to(_card_page + 1)


# Overshooting the card you wanted on a four-page deck used to cost three more presses.
func _prev_card_page() -> void:
	_page_to(_card_page - 1)


func _page_to(page: int) -> void:
	_cancel_touch_card_gestures()
	var previous_page := _card_page
	_reset_card_draws(true)
	_card_page = posmod(page, _card_pages())
	_card_at = mini(_card_page * 3, _card_slots.size() - 1)
	_refresh_hud(true)
	if _card_page != previous_page:
		_animate_card_page(1.0 if page > previous_page else -1.0)
	_prefetch_visible_card_art()


func _animate_card_page(direction: float) -> void:
	# Draw the new hand into its existing slots. Input regions never move, and a fresh hover can
	# interrupt the visual tween immediately without leaving a translucent or displaced button.
	var phone := _phone_hud_active()
	var duration := 0.14 if phone else 0.20
	var distance := 12.0 if phone else 24.0
	for i in range(_card_hud.size()):
		var face := _card_draw_node(i)
		if face == null or not is_instance_valid(face) or not face.is_visible_in_tree():
			continue
		_stop_card_draw_tween(i)
		face.position = Vector2(direction * distance, 3.0)
		face.scale = Vector2.ONE
		face.modulate = Color(1.0, 1.0, 1.0, 0.12)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_ease(Tween.EASE_OUT)
		var delay := float(i) * (0.01 if phone else 0.02)
		tween.tween_property(face, "position", Vector2.ZERO, duration).set_delay(delay)
		tween.tween_property(face, "modulate:a", 1.0, duration).set_delay(delay)
		_card_draw_tweens[i] = tween


# THE HUD IS ITS OWN KEYMAP, so this is a reminder rather than a manual: one line, in the band the
# player is already reading during the pre-wave beat, and on H whenever they want it back.
func _show_control_band() -> void:
	if _low:
		return
	_set_message("WASD MOVE · SPACE DODGE · 1 2 3 CAST · Q/E DECK · V VIEW · PAD A + X/Y/B", 4.5)


func _card_personal_cooldown(arch: String) -> float:
	return float({"quick": 0.22, "strike": 0.34, "jolt": 0.42, "rend": 0.48,
		"wither": 0.62, "drain": 0.65, "blast": 0.78, "nova": 1.15,
		"guard": 2.20, "charge": 2.80, "bulwark": 3.00, "rally": 5.50}.get(arch, 0.48))


func _tier_value(card: Dictionary, key: String, tier: int, fallback: float = 0.0) -> float:
	var value = card.get(key, fallback)
	if value is Array and not (value as Array).is_empty():
		return float((value as Array)[clampi(tier, 0, (value as Array).size() - 1)])
	return float(value)


func _card_damage(card: Dictionary, tier: int) -> float:
	var authored = card.get("dmg", [])
	if not (authored is Array) or (authored as Array).is_empty():
		return 0.0
	# The real card values remain recognizable while the horde gets a compressed level curve.
	var level_mul := 1.0 + 0.012 * float(_level() - 1)
	return float((authored as Array)[clampi(tier, 0, (authored as Array).size() - 1)]) / 8.0 \
		* level_mul * _rarity_damage()


func _activate_card(debug_force: bool = false) -> bool:
	if (not debug_force and (_stage_over or _wave_phase not in ["fight", "reinforce"] or not _input_on)) \
			or _attack_cd > 0.0 or not _pending_cast.is_empty() or not _card_dash.is_empty():
		return false
	var slot := _active_card_slot()
	var card := Econ.CARDS[clampi(slot, 0, Econ.CARDS.size() - 1)] as Dictionary
	var arch := String(card.get("arch", "strike"))
	var profile := AbilityVisual.profile(_species(), slot)
	if profile.is_empty():
		return false
	# Reach changes the real contact footprint and its matching effect art together. Self-only
	# cards retain their authored radius; this is the same small positional tradeoff as PvP.
	if arch not in ["guard", "charge", "rally", "bulwark"] and profile.has("radius"):
		profile["radius"] = float(profile["radius"]) * _trait_reach()
	if _card_cooldown(slot) > 0.0:
		_set_message("%s RECHARGING  ·  %.1fs" % [_card_name(slot).to_upper(), _card_cooldown(slot)], 0.8)
		return false
	var cost := float(card.get("cost", 1))
	if _energy + 0.001 < cost:
		_set_message("NOT ENOUGH CARD ENERGY", 0.9)
		return false
	_queue_profile_art(profile, true)
	# A reviewed replacement is an all-or-nothing pair. Downloading art must never consume energy,
	# start a cooldown, or fall through to the old generic pose/effect for this same card.
	if AbilitySprites.reborn_card_is_illustrated(profile) \
			and not AbilitySprites.reborn_card_pair_ready(profile):
		_set_message("%s  ·  LOADING ART" % _card_name(slot).to_upper(), 0.9)
		_refresh_hud(false)
		return false
	if arch == String(_species_trait.get("signature_arch", "")) \
			and String(_species_trait.get("signature_effect", "")) == "sunder":
		var held_asset := AbilitySprites.reborn_effect_layer_asset(profile, "status")
		if held_asset.is_empty():
			held_asset = AbilitySprites.reborn_effect_layer_asset(profile, "impact")
		if not held_asset.is_empty():
			profile["_trait_status_asset"] = held_asset
	_energy -= cost
	# Hold just through contact and the first half of recovery. The action remains readable, while the
	# short input buffer below accepts the player's next decision before this lock ends.
	var release := float(profile.get("release", 0.10))
	var contact := float(profile.get("contact", 0.10))
	var recovery := float(profile.get("recovery", 0.16))
	_attack_cd = 0.12 if arch == "quick" else clampf(
		release + contact + minf(0.09, recovery * 0.55), 0.16, 0.44)
	_card_cooldowns[slot] = _card_personal_cooldown(arch)
	_buffered_card_at = -1
	_card_buffer_t = 0.0
	var attack_id := _next_attack_id
	_next_attack_id += 1
	profile["combat_attack_id"] = attack_id
	_cards_used.append({"slot": slot, "arch": arch, "species": _species(), "time": _run_t,
		"name": String(profile.get("card_name", _card_name(slot))),
		"delivery": String(profile.get("delivery", arch)), "attack_id": attack_id})
	if _cards_used.size() > 64:
		_cards_used.pop_front()
	var base_pitch := 1.10 if arch == "quick" else (0.88 if arch in ["nova", "bulwark"] else 1.0)
	var seed_pitch := 0.965 + float(int(profile.get("seed", 0)) % 8) * 0.01
	_play_sfx(SFX_CARD, base_pitch * seed_pitch)
	if _rig != null and is_instance_valid(_rig):
		if _rig.has_method("attack"):
			_rig.call("attack", arch, profile)
		else:
			_rig.call("play", "attack")
	var target := _soft_target(520.0 * _trait_reach())
	if not target.is_empty():
		_hud_target_eid = _target_id(target)
		var to := _target_pos(target) - _ppos
		if to.length_squared() > 0.01:
			_face_dir = _cardinal_h(to, _face_dir)
			_rig.call("face", _face_dir)
	var tier := Econ.card_tier(_level())
	var damage := _card_damage(card, tier)
	_last_visual_profile = profile.duplicate(true)
	_pending_cast = {"time": float(profile.get("release", 0.10)), "slot": slot,
		"arch": arch, "card": card.duplicate(true), "tier": tier, "damage": damage,
		"profile": profile, "target_eid": _target_id(target) if not target.is_empty() else -1,
		"attack_id": attack_id}
	_profile_effect(_card_effect_anchor(profile, target, "gather"), profile, "gather", attack_id)
	if debug_force:
		_tick_pending_cast(float(profile.get("release", 0.10)) + 0.001)
	_refresh_hud(false)
	return true


func _card_effect_anchor(profile: Dictionary, target: Dictionary, phase: String) -> Vector2:
	# Consume the authored origin/target vocabulary instead of placing every one of 402 effects at
	# the caster. A siphon now begins on its victim, a meteor gathers above its marked floor point,
	# a wall rises in front, and self buffs remain attached to their Chikimon.
	var recipe := profile.get("visual_recipe", {}) as Dictionary
	var anchor := String(recipe.get("origin_anchor" if phase == "gather" else "target_anchor",
		"actor_center" if phase == "gather" else "target_actor"))
	var has_target := not target.is_empty()
	var target_at := _target_pos(target) if has_target else _ppos
	if anchor.begins_with("target_"):
		return target_at if has_target else _ppos + _face_dir.normalized() * 110.0
	if anchor in ["self_actor", "self_floor", "actor_center", "actor_floor", "actor_head"]:
		return _ppos
	if anchor == "actor_front":
		return _ppos + _face_dir.normalized() * 30.0
	if anchor == "front_floor":
		var reach := clampf(float(profile.get("radius", 72.0)) * 0.78, 58.0, 145.0)
		return _ppos + _face_dir.normalized() * reach
	return target_at if phase == "impact" and has_target else _ppos


func _tick_pending_cast(delta: float) -> void:
	if _pending_cast.is_empty():
		return
	_pending_cast["time"] = float(_pending_cast.get("time", 0.0)) - delta
	if float(_pending_cast["time"]) > 0.0:
		return
	var cast := _pending_cast
	_pending_cast = {}
	_resolve_card_cast(cast)


func _begin_card_dash(cast: Dictionary, target: Dictionary) -> void:
	var profile := cast.get("profile", {}) as Dictionary
	var dash_dir := _target_pos(target) - _ppos if not target.is_empty() else _face_dir
	if dash_dir.length_squared() <= 0.001:
		dash_dir = _face_dir if _face_dir.length_squared() > 0.001 else Vector2.UP
	dash_dir = dash_dir.normalized()
	# The slide lives entirely inside the authored six-frame card action. Quick cards currently
	# reserve 0.235s after release; keeping a small recovery tail lets the final pose land cleanly.
	var action_remaining := maxf(CARD_DASH_MIN_TIME,
		float(profile.get("duration", 0.28)) - float(profile.get("release", 0.045)) - 0.025)
	var slide_time := minf(CARD_DASH_MAX_TIME, action_remaining)
	slide_time = minf(slide_time,
		maxf(CARD_DASH_MIN_TIME, float(profile.get("contact", 0.09)) + 0.085))
	_card_dash = {
		"cast": cast.duplicate(true), "dir": dash_dir, "elapsed": 0.0,
		"duration": slide_time, "planned_distance": 0.0, "actual_distance": 0.0,
		"steps": 0, "echo_t": 0.0,
	}
	_face_dir = _cardinal_h(dash_dir, _face_dir)
	if _rig != null and is_instance_valid(_rig):
		_rig.call("face", _face_dir)
	# A reviewed Quick card can opt in before the complete 402-card illustrated library exists. The
	# call is a no-op for every prototype card, so Powder Dash gets its authored snow streak while
	# the other 390 cards keep their established visuals.
	_spawn_illustrated_card_layer(_ppos, profile, "trail", float(profile.get("radius", 72.0)),
		slide_time, 0.62, int(cast.get("attack_id", -1)), dash_dir)
	# Hold protection for every visible slide frame instead of granting it after a teleport.
	_invuln_t = maxf(_invuln_t, slide_time + 0.04)


func _card_dash_curve(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _tick_card_dash(delta: float, resolve_on_finish: bool = true) -> void:
	if _card_dash.is_empty():
		return
	var duration := maxf(0.001, float(_card_dash.get("duration", CARD_DASH_MIN_TIME)))
	var elapsed := minf(duration, float(_card_dash.get("elapsed", 0.0)) + maxf(0.0, delta))
	var planned := CARD_DASH_DISTANCE * _card_dash_curve(elapsed / duration)
	var prior_planned := float(_card_dash.get("planned_distance", 0.0))
	var step_px := maxf(0.0, planned - prior_planned)
	var dash_dir := _card_dash.get("dir", _face_dir) as Vector2
	var before := _ppos
	_card_dash["echo_t"] = float(_card_dash.get("echo_t", 0.0)) - maxf(0.0, delta)
	if step_px > 0.0:
		# Reuse the normal axis-resolved collision path on each frame. A wall shortens the dash; it
		# never permits a late snap through geometry to catch up to the authored distance.
		_move_player(dash_dir * step_px)
		_sync_player()
	_card_dash["elapsed"] = elapsed
	_card_dash["planned_distance"] = planned
	_card_dash["actual_distance"] = float(_card_dash.get("actual_distance", 0.0)) \
		+ _ppos.distance_to(before)
	_card_dash["steps"] = int(_card_dash.get("steps", 0)) + 1
	if _ppos.distance_squared_to(before) > 0.25 and float(_card_dash.get("echo_t", 0.0)) <= 0.0:
		var dash_cast := _card_dash.get("cast", {}) as Dictionary
		_spawn_card_dash_echo(before, dash_cast.get("profile", {}) as Dictionary, dash_dir,
			elapsed / duration, int(dash_cast.get("attack_id", -1)))
		_card_dash["echo_t"] = 0.078 if _low else 0.055
	if elapsed + 0.0001 < duration:
		return
	var completed_cast := (_card_dash.get("cast", {}) as Dictionary).duplicate(true)
	completed_cast["dash_complete"] = true
	_card_dash.clear()
	if resolve_on_finish and not completed_cast.is_empty() and not _stage_over:
		_resolve_card_cast(completed_cast)


func _direction_row(direction: Vector2) -> int:
	if absf(direction.y) >= absf(direction.x):
		return 0 if direction.y >= 0.0 else 3
	return 2 if direction.x >= 0.0 else 1


func _spawn_card_dash_echo(at: Vector2, profile: Dictionary, direction: Vector2,
		progress: float, attack_id: int) -> void:
	if profile.is_empty():
		return
	var active := 0
	for value in _effect_pool:
		if bool((value as Dictionary).get("active", false)):
			active += 1
	if active >= maxi(0, _effect_cap - (6 if _low else 8)):
		return
	# Stamp the real card-authored trail along the collision-aware slide. This stays in the same
	# bounded effect pool and therefore costs at most the echoes it replaces on a busy phone frame.
	_spawn_illustrated_card_layer(at, profile, "trail",
		maxf(28.0, float(profile.get("radius", 72.0)) * 0.52), 0.13 if _low else 0.16,
		0.62, attack_id, direction)
	var effect: Dictionary = {}
	for value in _effect_pool:
		var candidate := value as Dictionary
		if not bool(candidate.get("active", false)):
			effect = candidate
			break
	if effect.is_empty():
		return
	var node := effect["node"] as Sprite3D
	var reborn_body := AbilitySprites.reborn_body_asset(profile)
	var action_texture: Texture2D = reborn_body.get("texture") as Texture2D
	if action_texture == null and not _illustrated_only(profile):
		action_texture = AbilitySprites.card_action_texture_for_profile(profile)
	# The approved Pokemon-style exact action sheet remains valid in strict mode. If it is not yet
	# streamed, omit this decorative echo; never replace the creature with a procedural speed mask.
	if action_texture == null and _illustrated_only(profile):
		return
	effect["active"] = true
	effect["life"] = 0.13 if _low else 0.16
	effect["max"] = float(effect["life"])
	effect["p"] = at
	effect["spin"] = 0.0
	effect["angle"] = 0.0
	effect["pulse_count"] = 0
	effect["pulse_phase"] = 0.0
	effect["attack_id"] = attack_id
	effect["profile_key"] = String(profile.get("key", ""))
	effect["layer_role"] = "dash_action_echo"
	effect["fx_vec"] = Vector2.ZERO
	effect["fx_travel"] = 0.0
	effect["fx_rise"] = 0.0
	effect["fx_arc"] = 0.0
	effect["fx_pop"] = 1.0
	effect["axis_y"] = 1.0 / maxf(0.5, cos(deg_to_rad(HORDE_PITCH_DEG)))
	if action_texture != null:
		# Echo the exact creature/card action frame, not a generic smoke smear. Three bounded echoes
		# make the sliding Quick readable while the live rig remains the opaque focal character.
		# The slide begins on release, so its echoes begin at the first contact drawing (column 2),
		# never replay the gather pose after the creature is already moving, and land on recovery.
		var grid := Vector2i(AbilitySprites.CARD_ACTION_FRAMES, 4)
		var cell := AbilitySprites.CARD_ACTION_CELL_PX
		var pivot := Vector2(0.5, 0.875)
		var frame := 0
		if not reborn_body.is_empty():
			grid = reborn_body.get("grid", grid) as Vector2i
			cell = reborn_body.get("cell", cell) as Vector2i
			pivot = reborn_body.get("pivot", pivot) as Vector2
			var phases := reborn_body.get("phases", {}) as Dictionary
			var phase_name := "contact" if progress < 0.58 else "recovery"
			var window := phases.get(phase_name, Vector2i(0, 1)) as Vector2i
			var local_t := clampf(progress / 0.58, 0.0, 0.999) if phase_name == "contact" \
				else clampf((progress - 0.58) / 0.42, 0.0, 0.999)
			frame = window.x + mini(int(floor(local_t * float(window.y))), window.y - 1)
			var directions := reborn_body.get("directions", ["right"]) as Array
			if directions.size() == 4:
				var row_name: String = ["down", "left", "right", "up"][_direction_row(direction)]
				frame += int((reborn_body.get("direction_offsets", {}) as Dictionary).get(row_name, 0))
			node.flip_h = directions == ["right"] and bool(reborn_body.get("flip_x", true)) \
				and direction.x < -0.05
		else:
			var contact_columns := maxi(1, AbilitySprites.CARD_ACTION_FRAMES - 2)
			var column := 2 + clampi(int(floor(clampf(progress, 0.0, 0.999) \
				* float(contact_columns))), 0, contact_columns - 1)
			frame = _direction_row(direction) * AbilitySprites.CARD_ACTION_FRAMES + column
			node.flip_h = false
		effect["sprite_sheet"] = true
		effect["sheet_start"] = frame
		effect["sheet_count"] = 1
		effect["sheet_cols"] = grid.x
		effect["sheet_cell"] = cell
		effect["sheet_inset"] = 0.5
		effect["dedicated_card_sheet"] = true
		effect["start"] = 0.94
		effect["end"] = 0.78
		effect["height"] = 0.012
		effect["peak_alpha"] = 0.30 if _low else 0.36
		node.texture = action_texture
		node.region_enabled = true
		node.region_rect = _sheet_region(effect, frame)
		node.material_override = null
		var reference_height := float(cell.y) * 0.82
		if not reborn_body.is_empty() and reborn_body.has("reference_height_px"):
			reference_height = float(reborn_body.get("reference_height_px", reference_height))
			# Share the live rig's measured neutral reference; transparent 256px padding is not body
			# height. Otherwise a full-sized dash leaves tiny duplicate creatures behind it.
			if _rig != null and is_instance_valid(_rig) and _rig.has_method("visual_metrics"):
				var rig_metrics := _rig.call("visual_metrics") as Dictionary
				if String(rig_metrics.get("card_profile_key", "")) == String(profile.get("key", "")):
					reference_height = float(rig_metrics.get("card_action_visible_height_px", reference_height))
		node.pixel_size = PLAYER_RIG_H_M / maxf(1.0, reference_height) \
			if not reborn_body.is_empty() else PLAYER_RIG_H_M / 148.0
		node.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		node.offset = Vector2((0.5 - pivot.x) * float(cell.x), (pivot.y - 0.5) * float(cell.y))
		node.modulate = Color(1.0, 1.0, 1.0, float(effect["peak_alpha"]))
	else:
		# No body sheet yet: leave the live opaque rig as the creature and trail it with a clean semantic
		# speed streak. An encoded crest here looked like a second floating character and is retired.
		var dash_shape := RebornFX.trail_shape(profile)
		effect["sprite_sheet"] = false
		effect["sheet_start"] = 0
		effect["sheet_count"] = 0
		effect["sheet_cols"] = 0
		effect["sheet_cell"] = AbilitySprites.CELL_PX
		effect["sheet_inset"] = 0.0
		effect["dedicated_card_sheet"] = false
		effect["start"] = 0.66
		effect["end"] = 0.26
		effect["height"] = 0.68
		effect["peak_alpha"] = 0.62
		effect["axis_y"] = 1.0
		node.texture = RebornFX.texture(dash_shape)
		node.region_enabled = false
		node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		node.offset = Vector2.ZERO
		node.pixel_size = 0.012
		node.material_override = RebornFX.material(dash_shape)
		node.flip_h = false
		var palette := profile.get("palette", {}) as Dictionary
		node.modulate = Color(palette.get("trail", palette.get("secondary", Color.WHITE)))
	node.global_position = px2m(at, float(effect["height"]))
	node.rotation.z = 0.0
	node.scale = Vector3(float(effect["start"]),
		float(effect["start"]) * float(effect["axis_y"]), float(effect["start"]))
	node.visible = true


func _target_by_eid(eid: int) -> Dictionary:
	if eid == 9999 and bool(_boss.get("active", false)):
		return _boss
	for value in _enemy_pool:
		var e := value as Dictionary
		if int(e.get("eid", -1)) == eid and bool(e.get("active", false)):
			return e
	return {}


func _resolve_card_cast(cast: Dictionary) -> void:
	var arch := String(cast.get("arch", "strike"))
	var card := cast.get("card", {}) as Dictionary
	var tier := int(cast.get("tier", 0))
	var profile := cast.get("profile", {}) as Dictionary
	var attack_id := int(cast.get("attack_id", -1))
	var delivery := String(profile.get("delivery", arch))
	var target := _target_by_eid(int(cast.get("target_eid", -1)))
	if target.is_empty():
		target = _soft_target(620.0 * _trait_reach())
	# Reborn atlases and the semantic fallback both own a distinct release beat. Playing it here keeps
	# card press, creature contact pose and outgoing attack aligned before travel/contact resolution.
	if not bool(cast.get("release_shown", false)):
		_spawn_reborn_card_release(_card_effect_anchor(profile, target, "gather"), profile, attack_id)
		cast["release_shown"] = true
	# Quick abilities used to perform their entire 82 px displacement in this release frame. Start
	# a short collision-aware slide instead, then return here once the final action frame connects.
	if arch == "quick" and not bool(cast.get("dash_complete", false)):
		_begin_card_dash(cast, target)
		return
	var damage := float(cast.get("damage", 0.0))
	if damage > 0.0:
		damage *= _empower_mul
		damage *= _rally_mul if _rally_t > 0.0 else 1.0
		if _empower_mul > 1.01:
			_float_text(_ppos, "EMPOWERED  ×%.2f" % _empower_mul, Color("ffc96a"))
			_empower_mul = 1.0
		if _riposte_t > 0.0:
			damage *= PERFECT_DODGE_RIPOSTE_MUL
			_riposte_t = 0.0
			_float_text(_ppos, "PERFECT RIPOSTE  ×%.2f" % PERFECT_DODGE_RIPOSTE_MUL,
				Color("69f0e2"))
			_set_message("%s  ·  PERFECT RIPOSTE" % String(profile.get(
				"card_name", _card_name(int(cast.get("slot", 0))))).to_upper(), 0.9)
	var hits := 0
	var launched_projectile := false
	# The melee siphon has no projectile to retain its art or remember the victim. Snapshot
	# both before damage can retire a target, finish combat or evict an atlas through UI changes.
	var siphon := _capture_lunge_siphon_return(profile, attack_id)
	var hit_evidence := {"positions": []} if not siphon.is_empty() else {}
	var hp_before_hit := _hp
	var heal_bank_before_hit := _heal_bank
	match arch:
		"guard":
			_player_status_profiles["shield"] = _status_profile_snapshot(profile, _face_dir)
			_shield = minf(_max_hp * 0.55, _shield + _tier_value(card, "shield", tier, 24.0))
			_parry_t = 0.26
		"bulwark":
			_player_status_profiles["shield"] = _status_profile_snapshot(profile, _face_dir)
			_shield = minf(_max_hp * 0.75, _shield + _tier_value(card, "shield", tier, 36.0))
			_parry_t = 0.42
			hits = _area_card(_ppos, float(profile.get("radius", 96.0)),
				0.8 + float(tier) * 0.35, arch, profile, true)
		"charge":
			_player_status_profiles["empower"] = _status_profile_snapshot(profile, _face_dir)
			_energy = minf(ENERGY_MAX, _energy + 1.0)
			_empower_mul = _tier_value(card, "nextmul", tier, 1.7)
			_float_text(_ppos, "NEXT HIT  ×%.2f" % _empower_mul, Color("ffc96a"))
		"rally":
			_player_status_profiles["rally"] = _status_profile_snapshot(profile, _face_dir)
			_rally_t = 5.0 + float(tier) * 0.65
			_rally_mul = 1.0 + _tier_value(card, "buff", tier, 0.25)
			_float_text(_ppos, "RALLY  ×%.2f" % _rally_mul, Color("69f0d2"))
		_:
			if delivery in ["straight_bolt", "homing_orb", "chain_bolt", "siphon_tether",
					"curse_spiral", "gaze_ray", "line_rend"]:
				_player_projectile(target, damage, arch, card, tier, profile, attack_id)
				launched_projectile = true
			else:
				hits = _resolve_delivery_hits(target, damage, arch, delivery, profile, hit_evidence)
	if arch in ["guard", "charge", "rally", "bulwark"]:
		_trait_on_self_cast(arch, profile)
	# The per-card state loop begins below and lasts exactly as long as shield/rally/empower state.
	# Release and impact already supply the activation beat; do not stack another short-lived copy.
	if arch == "drain" and hits > 0:
		_apply_heal(_tier_value(card, "heal", tier, 0.0))
	if arch == "jolt" and hits > 0:
		_energy = minf(ENERGY_MAX, _energy + minf(0.45, 0.16 * float(hits)))
	if arch == "nova":
		for value in _projectile_pool:
			var projectile := value as Dictionary
			if bool(projectile.get("active", false)) and String(projectile.get("owner", "")) == "enemy" \
					and Vector2(projectile["p"]).distance_to(_ppos) <= 190.0:
				_deactivate_projectile(projectile)
		_apply_recoil(_tier_value(card, "recoil", tier, 6.0))
	# Travelling attacks own their contact burst in _tick_projectiles. Showing an impact here would
	# make the target flash before the bolt arrives—the exact timing discrepancy this system fixes.
	if not launched_projectile:
		if not siphon.is_empty():
			_retire_cast_gather(profile, attack_id)
			var positions := hit_evidence.get("positions", []) as Array
			siphon["hit_confirmed"] = hits > 0 and not positions.is_empty()
			# Canonical drains can credit less than one HP into the existing heal bank. That is
			# real healing even before the next whole HP point, but full-health casts celebrate none.
			siphon["heal_confirmed"] = hp_before_hit > 0.0 and hp_before_hit < _max_hp \
				and (_hp > hp_before_hit or _heal_bank > heal_bank_before_hit)
			if bool(siphon["hit_confirmed"]) and bool(siphon["heal_confirmed"]):
				# One heal per cast stays one visual return, even when the melee catches a group.
				_spawn_siphon_return(siphon, Vector2(positions[0]))
		else:
			var confirmed_impact := hits > 0 or arch in ["guard", "bulwark", "charge", "rally", "nova"]
			if arch == "drain" and delivery == "self_siphon" and _illustrated_only(profile):
				# The victim's real hit art already played in damage dispatch. Only the caster's
				# explicit absorption needs a living, active owner and an actual deficit/credit.
				# Preserve all canonical heal-bank accounting and ordinary tether behavior.
				confirmed_impact = hits > 0 and _entered and not _stage_over and _hp > 0.0 \
					and hp_before_hit > 0.0 and hp_before_hit < _max_hp \
					and (_hp > hp_before_hit or _heal_bank > heal_bank_before_hit)
			_profile_effect(_card_effect_anchor(profile, target, "impact"), profile, "impact", attack_id,
				confirmed_impact)
	_refresh_status_visuals(0.0)
	_refresh_hud(false)


func _resolve_delivery_hits(target: Dictionary, damage: float, arch: String, delivery: String,
		profile: Dictionary, hit_evidence: Dictionary = {}) -> int:
	var radius := float(profile.get("radius", 100.0))
	var target_at := _target_pos(target) if not target.is_empty() else _ppos + _face_dir * minf(180.0, radius)
	if delivery in ["target_drop", "target_snap", "curse_field"]:
		return _area_card(target_at, radius, damage, arch, profile)
	if delivery in ["radial_burst", "ground_burst", "radial_snap", "fortress_ring",
			"aura_pulse", "banner_pulse", "self_gather", "inward_gather", "body_shell"]:
		return _area_card(_ppos, radius, damage, arch, profile, true)
	if delivery in ["ground_wave", "wide_wave", "cone_wave", "front_wall"]:
		return _directional_card(damage, arch, radius * 2.25, radius * (1.25 if delivery == "wide_wave" else 0.82),
			0.15 if delivery == "wide_wave" else 0.38, profile)
	var min_dot := 0.34 if delivery in ["whip_arc", "weapon_arc"] else 0.48
	return _melee_card(damage, arch, radius, min_dot, profile, hit_evidence)


func _directional_card(damage: float, arch: String, reach: float, half_width: float, min_dot: float,
		profile: Dictionary = {}) -> int:
	var hits := 0
	var facing := _face_dir.normalized()
	var side := Vector2(-facing.y, facing.x)
	for target in _all_targets():
		var to := _target_pos(target) - _ppos
		if to.dot(facing) < 0.0 or to.dot(facing) > reach or absf(to.dot(side)) > half_width:
			continue
		if to.length() > 0.01 and to.normalized().dot(facing) < min_dot:
			continue
		if _damage_target(target, damage, arch, Econ.el_of(_species()), profile):
			hits += 1
	return hits


func _normal_mob_contact_reach(target: Dictionary, authored_radius: float) -> float:
	# Only the exact active pooled mob participates in the shared body-separation geometry.
	# Bosses, target snapshots and projectile/target-centered fields keep their original reach.
	var eid := int(target.get("eid", -1))
	if eid < 0 or eid >= _enemy_pool.size(): return authored_radius
	var pooled := _enemy_pool[eid] as Dictionary
	if not bool(pooled.get("active", false)) or not is_same(pooled, target): return authored_radius
	return maxf(authored_radius, ENEMY_PLAYER_CONTACT_DISTANCE_PX + CONTACT_DISTANCE_EPSILON_PX)


func _melee_card(damage: float, arch: String, radius: float, min_dot: float,
		profile: Dictionary = {}, hit_evidence: Dictionary = {}) -> int:
	var hits := 0
	var facing := _face_dir.normalized()
	for target in _all_targets():
		var victim_at := _target_pos(target)
		var to := victim_at - _ppos
		if to.length() <= _normal_mob_contact_reach(target, radius) \
				and (to.normalized().dot(facing) >= min_dot or to.length() < 48.0):
			if _damage_target(target, damage, arch, Econ.el_of(_species()), profile):
				hits += 1
				if hit_evidence.has("positions"):
					(hit_evidence["positions"] as Array).append(victim_at)
	return hits


func _area_card(center: Vector2, radius: float, damage: float, arch: String,
		profile: Dictionary = {}, caster_contact: bool = false) -> int:
	var hits := 0
	for target in _all_targets():
		var reach := _normal_mob_contact_reach(target, radius) if caster_contact else radius
		if _target_pos(target).distance_to(center) <= reach:
			if _damage_target(target, damage, arch, Econ.el_of(_species()), profile):
				hits += 1
	return hits


func _player_projectile(target: Dictionary, damage: float, arch: String, card: Dictionary, tier: int,
		profile: Dictionary, attack_id: int = -1) -> void:
	var projectile := _acquire_projectile()
	if projectile.is_empty():
		return
	var aim := _target_pos(target) if not target.is_empty() else _ppos + _face_dir * 500.0
	var dir := (aim - _ppos).normalized()
	var delivery := String(profile.get("delivery", "straight_bolt"))
	var speed := float({"gaze_ray": 680.0, "chain_bolt": 610.0, "straight_bolt": 550.0,
		"line_rend": 520.0, "homing_orb": 410.0, "siphon_tether": 370.0,
		"curse_spiral": 350.0}.get(delivery, 430.0))
	projectile["owner"] = "player"; projectile["p"] = _ppos + dir * 34.0
	projectile["v"] = dir * speed
	projectile["life"] = 1.65
	projectile["radius"] = clampf(float(profile.get("radius", 68.0)) * 0.24, 14.0, 28.0)
	projectile["damage"] = damage; projectile["arch"] = arch
	projectile["element"] = Econ.el_of(_species())
	projectile["pierce"] = arch == "jolt" or delivery == "line_rend"
	projectile["hit_ids"] = {}; projectile["heal"] = _tier_value(card, "heal", tier, 0.0)
	projectile["weak"] = _tier_value(card, "weaken", tier, 0.0)
	projectile["blast"] = float(profile.get("radius", 72.0)) if arch == "blast" else 0.0
	projectile["profile"] = profile
	# A reviewed siphon can own separate outward travel and inward return art. Keep the same
	# streamed atlas resources until collision; paging the deck during flight must not lose them.
	if _illustrated_only(profile) and arch == "drain" and delivery == "siphon_tether":
		var returning := AbilitySprites.reborn_effect_layer_asset(profile, "return")
		if not returning.is_empty():
			projectile["return_asset"] = returning
			projectile["return_impact_asset"] = AbilitySprites.reborn_effect_layer_asset(profile, "impact")
	projectile["delivery"] = delivery
	projectile["target_eid"] = _target_id(target) if not target.is_empty() else -1
	projectile["attack_id"] = attack_id if attack_id >= 0 else _next_attack_id
	projectile["age"] = 0.0; projectile["trail_t"] = 0.0
	projectile["trail_interval"] = 0.085 if _low else 0.052
	if attack_id < 0:
		_next_attack_id += 1
	var node := projectile["node"] as Sprite3D
	var recipe := profile.get("visual_recipe", {}) as Dictionary
	var layer_keys := recipe.get("layer_texture_keys", []) as Array
	var core_texture_key := String(layer_keys[0]) if not layer_keys.is_empty() else \
		String(profile.get("vfx_texture_key", arch))
	# A moving attack must read as its delivery, not as an encoded card-number crest. The exact Reborn
	# lifecycle atlas owns anticipation/release/contact; flight uses a clean beam/comet/tether/etc.
	# silhouette selected by the canonical delivery and shared through RebornCombat's bounded cache.
	var travel_shape := ""
	var illustrated_asset := AbilitySprites.reborn_effect_layer_asset(profile, "projectile")
	if not illustrated_asset.is_empty():
		var layer := illustrated_asset.get("layer", {}) as Dictionary
		var window := illustrated_asset.get("frames", Vector2i(-1, -1)) as Vector2i
		var grid := illustrated_asset.get("grid", Vector2i.ONE) as Vector2i
		var cell := illustrated_asset.get("cell", Vector2i(96, 96)) as Vector2i
		var pivot := illustrated_asset.get("pivot", Vector2(0.5, 0.5)) as Vector2
		projectile["illustrated_sheet"] = true
		projectile["sheet_start"] = window.x
		projectile["sheet_count"] = window.y
		projectile["sheet_cols"] = grid.x
		projectile["sheet_cell"] = cell
		projectile["sheet_inset"] = 0.5
		projectile["sheet_fps"] = float(layer.get("fps", 0.0))
		projectile["sheet_loop"] = bool(layer.get("loop", true))
		projectile["sheet_orient"] = bool(layer.get("orient", true))
		projectile["sheet_mirror_x"] = bool(layer.get("mirror_x_with_direction", false))
		projectile["sheet_native_flip_x"] = bool(layer.get("native_flip_x", false))
		node.texture = illustrated_asset.get("texture") as Texture2D
		node.material_override = illustrated_asset.get("material") as Material
		node.region_enabled = true
		node.region_rect = _sheet_region(projectile, window.x)
		node.pixel_size = 0.012 * 96.0 / float(maxi(cell.x, cell.y))
		node.offset = Vector2((0.5 - pivot.x) * float(cell.x),
			(pivot.y - 0.5) * float(cell.y))
	elif _illustrated_only(profile):
		# Physics still resolves while an optional streamed image is unavailable; strict mode never
		# substitutes a procedural orb, mask or crest for the missing illustration.
		projectile["illustrated_sheet"] = false
		node.texture = null
		node.material_override = null
		node.region_enabled = false
	else:
		travel_shape = RebornFX.delivery_shape(profile)
		node.texture = RebornFX.texture(travel_shape)
		node.material_override = RebornFX.material(travel_shape)
		node.region_enabled = false
		node.pixel_size = 0.012
		node.offset = Vector2.ZERO
	projectile["visual_id"] = String(profile.get("visual_id", ""))
	projectile["signature_core"] = false
	projectile["reborn_shape"] = travel_shape
	var palette := profile.get("palette", {}) as Dictionary
	var signature := Color(palette.get("signature", _element_color()))
	var secondary := Color(palette.get("secondary", signature))
	var highlight := Color(palette.get("core", palette.get("highlight", Color.WHITE)))
	var seed := int(profile.get("seed", 0))
	var family := String(profile.get("motif_family", arch))
	var base_scale := float(profile.get("scale", 1.0))
	if not illustrated_asset.is_empty():
		base_scale *= float(illustrated_asset.get("scale", 1.0))
	if family in ["comet", "star", "moon"]:
		base_scale *= 1.10
	elif family in ["fang", "claw", "shark"]:
		base_scale *= 0.92
	var fallback_height := 0.92 if delivery in ["homing_orb", "curse_spiral"] else \
		(0.74 if delivery in ["gaze_ray", "line_rend"] else 0.82)
	var visual_height := maxf(0.24, float(recipe.get("travel_height_px", fallback_height / PX2M)) * PX2M)
	var weave_amp := float({"curse_spiral": 13.0, "homing_orb": 5.5,
		"chain_bolt": 4.0, "siphon_tether": 7.0}.get(delivery, 0.0))
	if family in ["shark", "comet"]:
		weave_amp += 2.0
	projectile["base_scale"] = base_scale
	projectile["visual_height"] = visual_height
	projectile["spin_rate"] = float(recipe.get("spin_radians_per_second",
		(2.4 + float(seed % 5) * 0.42) * (-1.0 if seed % 2 == 0 else 1.0)))
	projectile["visual_phase"] = float(recipe.get("phase_offset", float(seed % 628) * 0.01))
	projectile["weave_amp"] = weave_amp
	projectile["weave_rate"] = 8.0 + float(seed % 4) * 1.4
	projectile["core_color"] = signature.lerp(highlight, 0.42)
	projectile["trail_color"] = Color(palette.get("trail", secondary.lerp(signature, 0.38)))
	var trail_recipe := recipe.get("trail", {}) as Dictionary
	var spacing_px := float(trail_recipe.get("spacing_px", 14.0))
	projectile["trail_interval"] = maxf(0.080 if _low else 0.045, spacing_px / maxf(1.0, speed))
	projectile["trail_alpha"] = float(trail_recipe.get("alpha_decay", 0.58))
	projectile["trail_scale_decay"] = 1.0 - float(trail_recipe.get("scale_decay", 0.86))
	projectile["trail_texture_key"] = String(layer_keys[1]) if layer_keys.size() > 1 else core_texture_key
	node.modulate = Color.WHITE if not illustrated_asset.is_empty() or _illustrated_only(profile) \
		else Color(projectile["core_color"])
	node.scale = Vector3.ONE * base_scale
	if bool(projectile.get("illustrated_sheet", false)):
		_apply_illustrated_projectile_pose(node, projectile, dir)
	else:
		node.flip_h = false
		node.rotation.z = float(projectile["visual_phase"])
	node.global_position = px2m(Vector2(projectile["p"]), visual_height)
	node.visible = not _illustrated_only(profile) or not illustrated_asset.is_empty()
	if not target.is_empty():
		_hud_target_eid = _target_id(target)


func _soft_target(radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_score := 1e18
	var facing := _face_dir.normalized()
	for target in _all_targets():
		var to := _target_pos(target) - _ppos
		var distance := to.length()
		if distance > radius or distance < 0.01:
			continue
		var dot := to.normalized().dot(facing)
		if dot < -0.18 and distance > 105.0:
			continue
		var score := distance - dot * 95.0
		if score < best_score:
			best_score = score
			best = target
	return best


func _all_targets() -> Array:
	var out: Array = []
	for value in _enemy_pool:
		if bool((value as Dictionary).get("active", false)):
			out.append(value)
	if bool(_boss.get("active", false)):
		out.append(_boss)
	return out


func _target_pos(target: Dictionary) -> Vector2:
	return Vector2(target.get("p", _ppos))


func _target_id(target: Dictionary) -> int:
	return int(target.get("eid", -1))


func _damage_target(target: Dictionary, damage: float, arch: String, element: String,
		profile: Dictionary = {}, impact_direction: Vector2 = Vector2.ZERO) -> bool:
	return _damage_boss_horde(damage, arch, element, profile, impact_direction) \
		if int(target.get("eid", -1)) == 9999 else _damage_enemy(target, damage, arch, element, profile, impact_direction)


func _register_hit(arch: String, damage: float, at: Vector2, _target: Dictionary,
		profile: Dictionary = {}) -> void:
	_hud_target_eid = _target_id(_target)
	_combo = _combo + 1 if _combo_t > 0.0 else 1
	_best_combo = maxi(_best_combo, _combo)
	_combo_t = COMBO_WINDOW + minf(0.65, float(_combo) * 0.025)
	if arch != "bleed" and not _chain_arches.has(arch):
		_chain_arches.append(arch)
	var combo_score_mul := 1.0 + minf(0.48, float(int(_combo / 5)) * 0.08)
	_score += int(roundf(float(maxi(1, int(roundf(damage * 12.0))) + mini(50, _combo * 2))
		* combo_score_mul))
	var hit_name := String(profile.get("card_name", arch)).to_upper()
	if hit_name.length() > 20:
		hit_name = hit_name.substr(0, 19) + "…"
	var palette := profile.get("palette", {}) as Dictionary
	var hit_color := Color(palette.get("highlight", _element_color()))
	_float_text(at, "%s  %.1f" % [hit_name, damage], hit_color)
	_play_sfx(SFX_HIT, 0.96 + _rng.randf_range(-0.05, 0.06))
	if _combo in [5, 10, 20, 30]:
		var pulse_energy := 0.12 if _combo == 5 else (0.18 if _combo == 10 else 0.25)
		_energy = minf(ENERGY_MAX, _energy + pulse_energy)
		_set_message("%d HIT TEMPLE FURY  ·  SCORE ×%.2f  ·  +ENERGY" % [
			_combo, combo_score_mul], 1.0)
	if _chain_arches.size() >= 3:
		_energy = minf(ENERGY_MAX, _energy + 0.5)
		_score += 125
		_chain_arches.clear()
		_set_message("TRINITY CHAIN  ·  THREE DIFFERENT CARDS  ·  +ENERGY", 1.4)
	_trait_on_confirmed_hit(arch, _target, profile)


func _apply_heal(amount: float) -> void:
	_heal_bank += maxf(0.0, amount)
	while _heal_bank >= 1.0:
		_heal_bank -= 1.0
		_hp = minf(_max_hp, _hp + 1.0)
	_refresh_combat_nameplates()


func _apply_recoil(authored: float) -> void:
	# Authored Nova recoil is on the card-battle scale.  Convert it to a small percentage of this
	# mode's larger health pool and never let a self-cast be lethal.
	_recoil_bank += maxf(0.0, authored) * 0.18
	while _recoil_bank >= 1.0 and _hp > 1.0:
		_recoil_bank -= 1.0
		_hp -= 1.0
	_refresh_combat_nameplates()


# ================================= projectiles / player damage =================================
func _acquire_projectile() -> Dictionary:
	for value in _projectile_pool:
		var projectile := value as Dictionary
		if not bool(projectile.get("active", false)):
			projectile["active"] = true
			projectile["age"] = 0.0
			projectile["trail_t"] = 0.0
			projectile["weave_amp"] = 0.0
			projectile["weave_rate"] = 0.0
			projectile["visual_phase"] = 0.0
			projectile["trail_alpha"] = 0.58
			projectile["trail_scale_decay"] = 0.22
			projectile["trail_texture_key"] = ""
			projectile["hit_confirmed"] = false
			projectile["heal_confirmed"] = false
			projectile["illustrated_sheet"] = false
			projectile["sheet_start"] = 0
			projectile["sheet_count"] = 0
			projectile["sheet_cols"] = 0
			projectile["sheet_cell"] = AbilitySprites.CELL_PX
			projectile["sheet_inset"] = 0.0
			projectile["sheet_fps"] = 0.0
			projectile["sheet_loop"] = false
			projectile["sheet_orient"] = false
			projectile["sheet_mirror_x"] = false
			projectile["sheet_native_flip_x"] = false
			projectile["return_asset"] = {}
			projectile["return_impact_asset"] = {}
			# Initialize pooled transforms and artwork before reveal; this prevents a one-frame flash at
			# the previous projectile position.
			(projectile["node"] as Sprite3D).visible = false
			return projectile
	return {}


func _deactivate_projectile(projectile: Dictionary) -> void:
	projectile["active"] = false
	projectile["hit_ids"] = {}
	projectile["profile"] = {}
	projectile["target_eid"] = -1
	projectile["visual_id"] = ""
	projectile["signature_core"] = false
	projectile["hit_confirmed"] = false
	projectile["heal_confirmed"] = false
	projectile["illustrated_sheet"] = false
	projectile["sheet_count"] = 0
	projectile["sheet_fps"] = 0.0
	projectile["sheet_loop"] = false
	projectile["sheet_orient"] = false
	projectile["sheet_mirror_x"] = false
	projectile["sheet_native_flip_x"] = false
	projectile["return_asset"] = {}
	projectile["return_impact_asset"] = {}
	var node = projectile.get("node")
	if node != null and is_instance_valid(node):
		var sprite := node as Sprite3D
		sprite.visible = false
		sprite.texture = null
		sprite.material_override = null
		sprite.region_enabled = false
		sprite.pixel_size = 0.014
		sprite.offset = Vector2.ZERO
		sprite.flip_h = false


func _deactivate_all_projectiles() -> void:
	for value in _projectile_pool:
		_deactivate_projectile(value as Dictionary)


func _clear_transient_pools() -> void:
	for value in _effect_pool:
		_release_effect(value as Dictionary)
	for value in _floater_pool:
		var floater := value as Dictionary
		floater["active"] = false
		(floater["node"] as Node3D).visible = false
	for value in _impact_lights:
		var light := value as OmniLight3D
		if light != null and is_instance_valid(light):
			light.visible = false
			light.light_energy = 0.0


func _tick_projectiles(delta: float) -> void:
	if _stage_over:
		return
	for value in _projectile_pool:
		var projectile := value as Dictionary
		if not bool(projectile.get("active", false)):
			continue
		projectile["life"] = float(projectile["life"]) - delta
		projectile["age"] = float(projectile.get("age", 0.0)) + delta
		projectile["trail_t"] = float(projectile.get("trail_t", 0.0)) - delta
		var delivery := String(projectile.get("delivery", ""))
		if String(projectile.get("owner", "")) == "player" \
				and delivery in ["homing_orb", "siphon_tether", "curse_spiral"]:
			var homing_target := _target_by_eid(int(projectile.get("target_eid", -1)))
			if not homing_target.is_empty():
				var old_v := Vector2(projectile["v"])
				var wanted := (_target_pos(homing_target) - Vector2(projectile["p"])).normalized() * old_v.length()
				projectile["v"] = old_v.lerp(wanted, clampf(delta * 4.8, 0.0, 1.0))
		projectile["p"] = Vector2(projectile["p"]) + Vector2(projectile["v"]) * delta
		var p := Vector2(projectile["p"])
		var node := projectile["node"] as Sprite3D
		var visual_p := p
		var velocity := Vector2(projectile["v"])
		var weave_amp := float(projectile.get("weave_amp", 0.0))
		if weave_amp > 0.01 and velocity.length_squared() > 0.01:
			var side := Vector2(-velocity.y, velocity.x).normalized()
			var wave := sin(float(projectile["age"]) * float(projectile.get("weave_rate", 8.0))
				+ float(projectile.get("visual_phase", 0.0)))
			visual_p += side * wave * weave_amp
		var base_scale := float(projectile.get("base_scale", 1.0))
		var pulse := 1.0 + sin(float(projectile["age"]) * 17.0
			+ float(projectile.get("visual_phase", 0.0))) * 0.065
		if bool(projectile.get("illustrated_sheet", false)):
			var count := maxi(1, int(projectile.get("sheet_count", 1)))
			var fps := float(projectile.get("sheet_fps", 0.0))
			if fps <= 0.0:
				fps = 12.0
			var local_frame := int(floor(float(projectile["age"]) * fps))
			local_frame = local_frame % count if bool(projectile.get("sheet_loop", false)) \
				else mini(local_frame, count - 1)
			node.region_rect = _sheet_region(projectile,
				int(projectile.get("sheet_start", 0)) + local_frame)
			node.scale = Vector3.ONE * base_scale
			_apply_illustrated_projectile_pose(node, projectile, velocity)
			node.modulate = Color.WHITE
		else:
			node.scale = Vector3.ONE * base_scale * pulse
			node.rotation.z += float(projectile.get("spin_rate", 0.0)) * delta
			node.modulate = Color(projectile.get("core_color", node.modulate))
		node.global_position = px2m(visual_p, float(projectile.get("visual_height", 0.82)))
		if float(projectile["trail_t"]) <= 0.0:
			_projectile_trail(projectile, visual_p)
			projectile["trail_t"] = float(projectile.get("trail_interval", 0.08))
		var remove := float(projectile["life"]) <= 0.0 or not _arena_rect.grow(120.0).has_point(p)
		if not remove and String(projectile["owner"]) == "enemy":
			if p.distance_to(_ppos) <= float(projectile["radius"]) + 22.0:
				if _parry_t > 0.0:
					_energy = minf(ENERGY_MAX, _energy + 0.45)
					_score += 80
					_float_text(_ppos, "PERFECT PARRY  +ENERGY", Color("8fd0ff"))
				else:
					_damage_player(float(projectile["damage"]), p)
					# Finishing a run retires this very pooled dictionary. Never continue using its
					# cleared profile to spawn a generic miss flash, or process another attack.
					if _stage_over: return
				remove = true
		elif not remove:
			var hit_ids := projectile.get("hit_ids", {}) as Dictionary
			for target in _all_targets():
				var eid := _target_id(target)
				if hit_ids.has(eid) or p.distance_to(_target_pos(target)) > float(projectile["radius"]) + 24.0:
					continue
				hit_ids[eid] = true
				var arch := String(projectile["arch"])
				var profile := projectile.get("profile", {}) as Dictionary
				var hp_before_hit := _hp
				var heal_bank_before_hit := _heal_bank
				var landed := false
				if arch == "blast":
					landed = _area_card(p, float(projectile["blast"]),
						float(projectile["damage"]), arch, profile) > 0
				else:
					landed = _damage_target(target, float(projectile["damage"]), arch,
						String(projectile["element"]), profile, velocity)
				projectile["hit_confirmed"] = bool(projectile.get("hit_confirmed", false)) or landed
				if arch == "drain" and landed:
					_apply_heal(float(projectile["heal"]))
					# Keep canonical fractional healing unchanged. Its cosmetic return belongs
					# only to a wounded caster receiving credit, not a full-health hit.
					projectile["heal_confirmed"] = bool(projectile.get("heal_confirmed", false)) \
						or (hp_before_hit > 0.0 and hp_before_hit < _max_hp \
						and (_hp > hp_before_hit or _heal_bank > heal_bank_before_hit))
				if arch == "jolt": _energy = minf(ENERGY_MAX, _energy + 0.30)
				if bool(projectile["pierce"]):
					# Piercing bolts own an impact at every body crossed, not one late flash where the
					# projectile eventually expires. Attack id keeps each contact tied to this cast.
					if landed and not profile.is_empty():
						_profile_effect(p, profile, "impact", int(projectile.get("attack_id", -1)), true, velocity)
				else:
					remove = true
					break
			projectile["hit_ids"] = hit_ids
		if remove:
			var profile := projectile.get("profile", {}) as Dictionary
			if not (projectile.get("return_asset", {}) as Dictionary).is_empty():
				_retire_cast_gather(profile, int(projectile.get("attack_id", -1)))
				if bool(projectile.get("hit_confirmed", false)):
					_spawn_siphon_return(projectile, p)
				# Expiry/miss never celebrates a heal. The non-colliding return is visual only,
				# while damage and healing retain their established confirmed-hit timing above.
			elif profile.is_empty():
				_effect(p, Color(node.modulate), 35.0, 0.24, 0.7)
			elif not bool(projectile.get("pierce", false)):
				_profile_effect(p, profile, "impact", int(projectile.get("attack_id", -1)),
					bool(projectile.get("hit_confirmed", false)), velocity)
			elif not bool(projectile.get("hit_confirmed", false)):
				# A miss still resolves its authored final frames, but never earns combat hit-stop.
				_profile_effect(p, profile, "impact", int(projectile.get("attack_id", -1)), false, velocity)
			_deactivate_projectile(projectile)


func _capture_lunge_siphon_return(profile: Dictionary, attack_id: int) -> Dictionary:
	if String(profile.get("arch", "")) != "drain" \
			or String(profile.get("delivery", "")) != "lunge_siphon" or not _illustrated_only(profile):
		return {}
	var returning := AbilitySprites.reborn_effect_layer_asset(profile, "return")
	var impact := AbilitySprites.reborn_effect_layer_asset(profile, "impact")
	if returning.is_empty() or impact.is_empty(): return {}
	return {"profile": profile.duplicate(true), "return_asset": returning,
		"return_impact_asset": impact, "attack_id": attack_id, "v": _face_dir}


func _spawn_siphon_return(projectile: Dictionary, from: Vector2) -> bool:
	var profile := projectile.get("profile", {}) as Dictionary
	var asset := projectile.get("return_asset", {}) as Dictionary
	var impact := projectile.get("return_impact_asset", {}) as Dictionary
	if not bool(projectile.get("hit_confirmed", false)) \
			or not bool(projectile.get("heal_confirmed", false)) or asset.is_empty() or impact.is_empty() \
			or String(profile.get("arch", "")) != "drain" \
			or String(profile.get("delivery", "")) not in ["siphon_tether", "lunge_siphon"] \
			or not _entered or _stage_over or _hp <= 0.0:
		return false
	var layer := asset.get("layer", {}) as Dictionary
	var window := asset.get("frames", Vector2i.ZERO) as Vector2i
	var fps := float(layer.get("fps", 0.0))
	if window.y <= 0 or not is_finite(fps) or fps <= 0.0:
		return false
	var life := clampf(float(window.y) / fps, 0.12, 0.25)
	var radius := float(profile.get("radius", 72.0))
	var attack_id := int(projectile.get("attack_id", -1))
	var outward := from - _ppos
	if outward.length_squared() <= 0.0001:
		outward = Vector2(projectile.get("v", Vector2.RIGHT))
	var free_slots: Array = []
	for value in _effect_pool:
		if not bool((value as Dictionary).get("active", false)):
			free_slots.append(value)
			if free_slots.size() >= 2:
				break
	# Two existing slots show return then absorption. Under pressure, prefer the truthful
	# absorption alone; never allocate extra nodes, reload a texture or use a generic effect.
	var delay := 0.0
	if free_slots.size() >= 2 and _spawn_illustrated_card_layer(from, profile, "return",
			radius, life, 0.82, attack_id, outward, -1, false, asset):
		var effect := free_slots[0] as Dictionary
		effect["return_to_actor"] = true
		effect["return_start"] = from
		effect["return_layer"] = layer.duplicate()
		delay = life
	var impact_layer := impact.get("layer", {}) as Dictionary
	var impact_window := impact.get("frames", Vector2i.ZERO) as Vector2i
	var impact_fps := float(impact_layer.get("fps", 0.0))
	var impact_life := float(impact_window.y) / impact_fps if impact_fps > 0.0 else \
		maxf(0.22, float(profile.get("contact", 0.1)) + float(profile.get("recovery", 0.16)))
	return _spawn_illustrated_card_layer(_ppos, profile, "impact", radius,
		clampf(impact_life, 0.06, 0.8), 0.82, attack_id, outward, -1, true, impact, delay)


func _spawn_status_body_event(status: Dictionary, from: Vector2) -> bool:
	if status.is_empty() or not bool(status.get("active", false)) \
			or String(status.get("owner", "")) != "player:shield" \
			or not _entered or _stage_over or _hp <= 0.0:
		return false
	# A cosmetic reaction never replaces the player's committed card, slide or dodge. The rig
	# separately protects its active attack/hurt/death animation and any in-progress reaction.
	if not _pending_cast.is_empty() or not _card_dash.is_empty() \
			or _dodge_t > 0.0 or _attack_cd > 0.0:
		return false
	var body := status.get("body_event_asset", {}) as Dictionary
	if body.is_empty() or _rig == null or not is_instance_valid(_rig) \
			or not _rig.has_method("play_body_event"):
		return false
	return bool(_rig.call("play_body_event", body, "block", from - _ppos))


func _damage_player(amount: float, from: Vector2) -> void:
	if _stage_over:
		return
	if _invuln_t > 0.0:
		if _dodge_t > 0.0 and _perfect_dodge_t > 0.0 and not _perfect_dodge_claimed:
			_reward_perfect_dodge(from)
		return
	var damage := maxf(0.0, amount) / clampf(float(_species_trait.get("ward", 1.0)), 0.9, 1.1)
	if _shield > 0.0:
		var absorbed := minf(_shield, damage)
		_shield -= absorbed
		damage -= absorbed
		if absorbed > 0.0:
			_spawn_status_event(_status_visual_for("player:shield"), "block")
			# Spillover damage must show the ordinary HP-hurt/death reaction below, not a false
			# successful block. Fully absorbed hits may use the shield card's own body drawing.
			if damage <= 0.0:
				_spawn_status_body_event(_status_visual_for("player:shield"), from)
		_float_text(_ppos, "SHIELD  -%.0f" % absorbed, Color("8fd0ff"))
		_refresh_status_visuals(0.0)
	if damage <= 0.0:
		_invuln_t = 0.18
		return
	_hp = maxf(0.0, _hp - damage)
	_refresh_combat_nameplates()
	_damage_taken += damage
	_invuln_t = 0.72
	_combo = 0
	_combo_t = 0.0
	_chain_arches.clear()
	if _rig != null and is_instance_valid(_rig):
		_rig.call("face", from - _ppos)
		_rig.call("play", "hurt")
	_player_hit_flash = 0.16
	_effect(_ppos, Color("ff496f"), 62.0, 0.38, 0.95)
	_float_text(_ppos, "-%.0f HP" % damage, Color("ff6a72"))
	if _hp <= 0.0:
		if _rig != null and is_instance_valid(_rig): _rig.call("play", "defeated")
		_finish_stage(false)


func _reward_perfect_dodge(from: Vector2) -> void:
	_perfect_dodge_claimed = true
	_perfect_dodge_t = 0.0
	_riposte_t = PERFECT_DODGE_RIPOSTE_TIME
	_energy = minf(ENERGY_MAX, _energy + PERFECT_DODGE_ENERGY)
	_score += 125
	# Preserve a live combo through the evasive beat. No hit is added: the counter must still land.
	if _combo > 0:
		_combo_t = maxf(_combo_t, COMBO_WINDOW)
	var side := (_ppos - from).normalized() if _ppos.distance_squared_to(from) > 0.01 else -_dodge_dir
	_effect(_ppos + side * 18.0, Color("69f0e2"), 74.0, 0.34, 0.72)
	_float_text(_ppos, "PERFECT DODGE  +ENERGY", Color("bffff5"))
	_set_message("PERFECT DODGE  ·  RIPOSTE READY", 1.25)
	_hitstop_t = maxf(_hitstop_t, 0.018 if _low else 0.032)
	_refresh_hud(false)


func _try_dodge() -> bool:
	if not _input_on or _stage_over or _wave_phase not in ["fight", "reinforce"] \
			or _dodge_cd > 0.0 or not _card_dash.is_empty():
		return false
	if _rig != null and is_instance_valid(_rig) and _rig.has_method("clear_body_event"):
		_rig.call("clear_body_event")
	var input := _touch_move.normalized() if _touch_move.length_squared() > 0.01 else super._input_dir()
	_dodge_dir = input if input.length_squared() > 0.01 else _face_dir.normalized()
	_dodge_t = DODGE_TIME
	_dodge_cd = DODGE_COOLDOWN
	_perfect_dodge_t = PERFECT_DODGE_WINDOW
	_perfect_dodge_claimed = false
	_invuln_t = maxf(_invuln_t, DODGE_TIME + 0.04)
	_effect(_ppos, Color("d6b8ff"), 48.0, 0.28, 0.55)
	return true


func _tick_dodge(delta: float) -> void:
	if _dodge_t <= 0.0:
		return
	_dodge_t = maxf(0.0, _dodge_t - delta)
	var before := _ppos
	_move_player(_dodge_dir * DODGE_SPEED * delta)
	var actual := _ppos - before
	_sync_player()
	if _rig != null and is_instance_valid(_rig):
		_rig.call("face", _dodge_dir)
		var current_clip := String(_rig.call("clip")) if _rig.has_method("clip") else "idle"
		if not current_clip in ["attack", "hurt", "defeated"]:
			var moving := actual.length_squared() > 0.01
			_rig.call("play", "walk" if moving else "idle")
			if moving and _rig.has_method("advance_walk_distance"):
				_rig.call("advance_walk_distance", actual.length())


# ================================= bounded effects =============================================
# ==============================================================================================
# WHAT MAKES A CARD LOOK LIKE ITSELF: WHERE ITS EFFECT GOES.
# ==============================================================================================
# Every archetype used to snap to size at the cast point, hold and fade — twelve different stamps
# playing one animation. The stamp says what it is; the MOTION says what it does, and motion is the
# half a player reads at speed. These profiles are geometric so the difference survives any palette:
#
#   ACROSS facing (strike) vs ALONG facing (rend) vs BEHIND it (quick) — three attacks, three
#   directions relative to the same forward vector. INWARD to the chest (charge) vs OUTWARD from the
#   feet (rally). Ground-anchored and expanding-then-gone (nova) vs ground-anchored and rising-then-
#   held (bulwark). A line drawn BETWEEN two bodies (drain) vs a brand that travels and STOPS
#   (wither). Freeze any single frame and the archetype is identifiable from geometry alone.
#
#   dir   : where the effect lives, in the caster's frame
#   travel: metres of displacement over its life, along that direction
#   rise  : metres of vertical travel (positive = up)
#   curve : how the displacement is paced — "ease" out, "in", "hold" (arrive then stay), "loop"
#   beats : discrete strobe/stagger count; 0 = continuous
#   spin  : radians per second of roll
const FX_MOTION := {
	"strike":  {"dir": "tangent",  "travel": 1.05, "rise": 0.00, "curve": "ease", "beats": 0, "spin": 2.2},
	"rend":    {"dir": "forward",  "travel": 0.85, "rise": 0.00, "curve": "ease", "beats": 3, "spin": 0.0},
	"quick":   {"dir": "back",     "travel": 1.30, "rise": 0.00, "curve": "in",   "beats": 3, "spin": 0.0},
	"blast":   {"dir": "forward",  "travel": 1.90, "rise": 0.10, "curve": "in",   "beats": 0, "spin": 1.1},
	"jolt":    {"dir": "forward",  "travel": 0.00, "rise": 0.00, "curve": "hold", "beats": 3, "spin": 0.0},
	"nova":    {"dir": "ground",   "travel": 0.00, "rise": 0.00, "curve": "ease", "beats": 0, "spin": 0.5},
	"bulwark": {"dir": "ground",   "travel": 0.00, "rise": 0.55, "curve": "hold", "beats": 0, "spin": 0.0},
	"guard":   {"dir": "forward",  "travel": 0.22, "rise": 0.30, "curve": "hold", "beats": 0, "spin": 0.0},
	"charge":  {"dir": "inward",   "travel": 0.95, "rise": 0.55, "curve": "in",   "beats": 0, "spin": 3.0},
	"rally":   {"dir": "ground",   "travel": 0.00, "rise": 0.85, "curve": "loop", "beats": 0, "spin": 0.9},
	"drain":   {"dir": "toward",   "travel": 1.45, "rise": 0.25, "curve": "in",   "beats": 0, "spin": 0.0},
	"wither":  {"dir": "forward",  "travel": 1.10, "rise": 0.05, "curve": "hold", "beats": 0, "spin": 0.45},
}

# The element rides ON TOP of the archetype and never replaces it: a Fire strike is a strike.
#   flick : brightness flicker amplitude (Fire licks, Storm strobes)
#   sag   : downward drift over life, in metres (Water settles and drips)
#   hold  : fraction of life spent at full alpha (Light blooms and holds)
#   settle: end-of-life scale contraction (Beast lands with weight instead of easing away)
const FX_ELEMENT := {
	"Water": {"flick": 0.00, "sag": 0.22, "hold": 0.30, "settle": 0.00},
	"Fire":  {"flick": 0.16, "sag": -0.18, "hold": 0.22, "settle": 0.00},
	"Beast": {"flick": 0.04, "sag": 0.06, "hold": 0.28, "settle": 0.16},
	"Storm": {"flick": 0.34, "sag": 0.00, "hold": 0.16, "settle": 0.00},
	"Light": {"flick": 0.06, "sag": -0.05, "hold": 0.52, "settle": 0.00},
}

const ORIENTED_RUNTIME_FAMILIES := {
	"bolt": true, "jaws": true, "whip": true, "ground_wave": true,
	"cone": true, "dash": true, "siphon": true, "gaze": true,
}


# The caster's frame at cast time, in the flat gameplay plane: forward, and the tangent across it.
func _fx_frame() -> Array:
	var fwd: Vector2 = _face_dir if _face_dir.length() > 0.01 else Vector2.DOWN
	fwd = fwd.normalized()
	return [fwd, Vector2(-fwd.y, fwd.x)]


# Runtime delivery masks are authored pointing screen-right. Gameplay Y grows toward screen-down,
# while Sprite3D local Y grows up, hence the negative Y in this conversion.
func _runtime_sheet_angle(direction: Vector2) -> float:
	var normalized := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	return atan2(-normalized.y, normalized.x)


func _illustrated_layer_pose(layer: Dictionary, direction: Vector2) -> Dictionary:
	# A curling ground wave has an upright top and bottom. Mirror it for a left cast rather
	# than rotating it upside down; bolts and claw arcs can still use full aimed rotation.
	# Left-authored outbound art opts into one native reversal. XOR keeps it independent of
	# directional mirroring; absent/false retains every established pose, including inbound returns.
	var mirror := bool(layer.get("mirror_x_with_direction", false))
	var flip := bool(layer.get("native_flip_x", false)) != (mirror and direction.x < -0.0001)
	return {"angle": _runtime_sheet_angle(direction) \
		if not mirror and bool(layer.get("orient", false)) else 0.0, "flip_h": flip}


func _apply_illustrated_projectile_pose(node: Sprite3D, projectile: Dictionary, direction: Vector2) -> void:
	# Explicit authored orientation wins over the old random phase, including at spawn. Upright
	# fish and vortices must not inherit a previous pooled projectile's mirror or rotation.
	var mirror := bool(projectile.get("sheet_mirror_x", false))
	node.flip_h = bool(projectile.get("sheet_native_flip_x", false)) \
		!= (mirror and direction.x < -0.0001)
	node.rotation.z = _runtime_sheet_angle(direction) \
		if not mirror and bool(projectile.get("sheet_orient", false)) else 0.0


# Release every reference unique to a generated sheet when its pooled effect ends.  The explicit
# LRU can only bound memory if inactive Sprite3Ds and per-texture materials do not secretly retain
# evicted resources.  Shared code-native stamps are restored on the next fallback spawn.
func _release_effect(effect: Dictionary) -> void:
	effect["active"] = false
	effect["start_delay"] = 0.0
	effect["sprite_sheet"] = false
	effect["sheet_start"] = 0
	effect["sheet_count"] = 0
	effect["sheet_cell"] = AbilitySprites.CELL_PX
	effect["sheet_cols"] = 0
	effect["sheet_inset"] = 0.0
	effect["sheet_fps"] = 0.0
	effect["sheet_loop"] = false
	effect["dedicated_card_sheet"] = false
	effect["peak_alpha"] = 1.0
	effect["axis_y"] = 1.0
	effect["attack_id"] = -1
	effect["spin"] = 0.0
	effect["angle"] = 0.0
	effect["pulse_count"] = 0
	effect["pulse_phase"] = 0.0
	effect["fx_vec"] = Vector2.ZERO
	effect["fx_travel"] = 0.0
	effect["fx_rise"] = 0.0
	effect["fx_curve"] = "ease"
	effect["fx_beats"] = 0
	effect["fx_spin"] = 0.0
	effect["fx_el"] = {}
	effect["fx_arc"] = 0.0
	effect["fx_pop"] = 1.0
	effect["fx_home"] = Vector3.ZERO
	effect["follow_eid"] = -1
	effect["follow_actor"] = false
	effect["return_to_actor"] = false
	effect["return_start"] = Vector2.ZERO
	effect["return_layer"] = {}
	effect["physical_actor_extent"] = false
	effect["camera_plane_offset_m"] = 0.0
	effect["profile_key"] = ""
	effect["layer_role"] = "generic"
	var node = effect.get("node")
	if node == null or not is_instance_valid(node):
		return
	var sprite := node as Sprite3D
	sprite.visible = false
	sprite.region_enabled = false
	sprite.region_rect = Rect2()
	sprite.material_override = null
	sprite.texture = _orb_tex
	sprite.pixel_size = 0.012
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.offset = Vector2.ZERO
	sprite.flip_h = false
	sprite.rotation.z = 0.0
	sprite.scale = Vector3.ONE
	sprite.modulate = Color.WHITE


func _sheet_region(effect: Dictionary, frame: int) -> Rect2:
	var cell := Vector2i(effect.get("sheet_cell", AbilitySprites.CELL_PX))
	var cols := maxi(1, int(effect.get("sheet_cols", 1)))
	var inset := clampf(float(effect.get("sheet_inset", 0.0)), 0.0,
		maxf(0.0, minf(float(cell.x), float(cell.y)) * 0.20))
	return Rect2(float(frame % cols) * float(cell.x) + inset,
		float(int(frame / cols)) * float(cell.y) + inset,
		maxf(1.0, float(cell.x) - inset * 2.0), maxf(1.0, float(cell.y) - inset * 2.0))


func _reborn_manifest_anchor(asset: Dictionary, fallback: Vector2) -> Dictionary:
	var anchor := String(asset.get("anchor", "profile"))
	var resolved := fallback
	var floor_height := false
	match anchor:
		"actor":
			resolved = _ppos
		"target":
			# The caller already supplies the cast/hit target's actual position. The HUD selection can
			# change during flight, and piercing attacks can hit several different creatures; never
			# teleport every impact to whichever enemy happens to be highlighted now.
			resolved = fallback
		"floor":
			floor_height = true
		_: pass
	return {"at": resolved, "floor": floor_height}


func _illustrated_layer_at(asset: Dictionary, fallback: Vector2, direction: Vector2) -> Vector2:
	var layer := asset.get("layer", {}) as Dictionary
	if String(asset.get("anchor", "")) != "floor" or not layer.has("actor_forward_px"):
		return fallback
	var aim := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	# This is an actor-relative visual origin, not an additive offset on a cast's already-resolved
	# front_floor/target point. The same contract keeps construction, hold, hit and break aligned.
	return _ppos + aim * clampf(float(layer["actor_forward_px"]), 0.0, 145.0)


func _upright_floor_asset(asset: Dictionary) -> bool:
	return String(asset.get("anchor", "")) == "floor" \
		and not bool((asset.get("layer", {}) as Dictionary).get("orient", false))


func _fixed_y_illustrated_asset(asset: Dictionary) -> bool:
	# Physical caster wards share the creature's upright plane. Keep their authored center;
	# floor sprites alone receive the bottom pivot adjustment below. Depth testing stays on.
	return _upright_floor_asset(asset) or _physical_actor_ward_asset(asset)


func _physical_actor_ward_asset(asset: Dictionary) -> bool:
	var layer := asset.get("layer", {}) as Dictionary
	return String(asset.get("anchor", "")) == "actor" and layer.has("world_size_m") \
		and not bool(layer.get("orient", false))


func _actor_ward_front_position(position: Vector3, separation: float = 0.035) -> Vector3:
	if _cam == null or not is_instance_valid(_cam):
		return position
	# A tiny physical separation prevents the body and ward fighting for the same depth plane.
	# It follows the cylindrical billboard's camera-facing normal, never lifts the ward, and
	# keeps ordinary depth testing: scenery and creatures in front can still occlude it.
	var toward_viewer := _cam.global_transform.basis.z
	toward_viewer.y = 0.0
	return position + toward_viewer.normalized() * separation


func _illustrated_plane_offset(asset: Dictionary) -> float:
	if _physical_actor_ward_asset(asset):
		return 0.035
	if not _upright_floor_asset(asset):
		return 0.0
	var value: Variant = (asset.get("layer", {}) as Dictionary).get("camera_plane_offset_m", 0.0)
	if not (value is float or value is int):
		return 0.0
	var separation := float(value)
	return separation if is_finite(separation) and separation >= 0.0 and separation <= 0.06 else 0.0


func _illustrated_world_position(asset: Dictionary, at: Vector2, height: float) -> Vector3:
	var position := px2m(at, height)
	var separation := _illustrated_plane_offset(asset)
	return _actor_ward_front_position(position, separation) if separation > 0.0 else position


func _illustrated_billboard_pivot(asset: Dictionary,
		fallback: Vector2 = Vector2(0.5, 0.5)) -> Vector2:
	var pivot := asset.get("pivot", fallback) as Vector2
	if _upright_floor_asset(asset):
		# A floor coordinate is the base of an upright billboard, not its center.
		# Otherwise the lower half of wards/rings is hidden inside the opaque 3D floor.
		# Reviewed floor pivots use the window's maximum alpha bottom, excluding transparent
		# atlas margins. Keep that common baseline for every animation frame (no bobbing).
		# Unreviewed centered pivots fall back to the canvas base, safely above the floor.
		if pivot.y <= 0.5:
			pivot.y = 1.0
	return pivot


func _illustrated_only(profile: Dictionary = {}) -> bool:
	# Library-wide strict readiness and a single reviewed card are separate contracts. Once a
	# replacement is installed its policy does not change during a download, eviction or 404.
	return AbilitySprites.illustrated_only_active() \
		or AbilitySprites.reborn_card_is_illustrated(profile)


func _apply_reborn_motion(effect: Dictionary, profile: Dictionary, at: Vector2,
		motion: String, directional: bool) -> void:
	var fields := RebornFX.motion_fields(profile, motion)
	var frame := _fx_frame()
	var fwd: Vector2 = frame[0]
	var tangent: Vector2 = frame[1]
	var vector := Vector2.ZERO
	match String(fields.get("dir", "hold")):
		"forward": vector = fwd
		"back": vector = -fwd
		"tangent": vector = tangent
		"toward", "inward":
			vector = (_ppos - at).normalized() if _ppos.distance_squared_to(at) > 1.0 else -fwd
		_: pass
	effect["fx_vec"] = vector
	effect["fx_travel"] = float(fields.get("travel", 0.0))
	effect["fx_rise"] = float(fields.get("rise", 0.0))
	effect["fx_curve"] = String(fields.get("curve", "ease"))
	effect["fx_beats"] = int(fields.get("beats", 0))
	effect["fx_spin"] = 0.0 if directional else float(fields.get("fx_spin", 0.0))
	effect["fx_arc"] = float(fields.get("arc", 0.0))
	effect["fx_pop"] = float(fields.get("pop", 1.0))
	effect["fx_el"] = RebornFX.element_motion(profile)
	effect["fx_home"] = px2m(at, float(effect.get("height", 0.78)))


## Strict illustrated mode is deliberately boring in code: one manifest-owned transparent image
## layer is sampled as authored, without procedural masks, palette recolouring or encoded crests.
## Movement such as a projectile's world travel remains gameplay; its visible pixels come only from
## this atlas. Missing streamed art returns false and renders nothing for that layer.
func _spawn_illustrated_card_layer(at: Vector2, profile: Dictionary, layer_name: String,
		radius_px: float, lifetime: float, height: float, attack_id: int = -1,
		direction: Vector2 = Vector2.ZERO, follow_eid: int = -1,
		follow_actor: bool = false, retained_asset: Dictionary = {}, start_delay: float = 0.0) -> bool:
	var asset := retained_asset if not retained_asset.is_empty() \
		else AbilitySprites.reborn_effect_layer_asset(profile, layer_name)
	if asset.is_empty():
		return false
	var layer := asset.get("layer", {}) as Dictionary
	var window := asset.get("frames", Vector2i(-1, -1)) as Vector2i
	if window.x < 0 or window.y <= 0:
		return false
	var anchor_result := _reborn_manifest_anchor(asset, at)
	at = anchor_result.get("at", at) as Vector2
	var actor_metrics := String(asset.get("anchor", "")) == "actor"
	if actor_metrics and layer.has("height_m"):
		height = float(layer["height_m"])
	var aim := direction if direction.length_squared() > 0.0001 else _face_dir
	at = _illustrated_layer_at(asset, at, aim)
	if bool(anchor_result.get("floor", false)):
		height = 0.05
	var effect: Dictionary = {}
	for value in _effect_pool:
		var candidate := value as Dictionary
		if not bool(candidate.get("active", false)):
			effect = candidate
			break
	if effect.is_empty():
		return false
	var node := effect["node"] as Sprite3D
	var grid := asset.get("grid", Vector2i.ONE) as Vector2i
	var cell := asset.get("cell", Vector2i(96, 96)) as Vector2i
	var pivot := _illustrated_billboard_pivot(asset)
	var authored_scale := clampf(float(profile.get("scale", 1.0)) * radius_px / 90.0
		* float(asset.get("scale", 1.0)), 0.42, 2.25)
	if actor_metrics and layer.has("world_size_m"):
		# A physical caster shield must keep one reviewed size through construction, hold,
		# absorption and break. Attack radius is gameplay reach, not its visual diameter.
		authored_scale = float(asset.get("scale", 1.0))
	if asset.has("_status_world_size"):
		authored_scale = float(asset.get("scale", 1.0))
	var pose := _illustrated_layer_pose(layer, aim)
	var angle := float(pose["angle"])
	var role := "illustrated_%s" % layer_name
	if layer_name == "anticipation":
		role = "illustrated_gather"
	elif layer_name == "status":
		# A card's authored status drawing is its brief, bespoke activation beat. Long-lived state is
		# represented separately by the fixed TempleStatusSprites pool, so this must never masquerade
		# as a timer-driven sustained status layer.
		role = "illustrated_activation"
	effect["active"] = true
	effect["start_delay"] = maxf(0.0, start_delay)
	effect["life"] = maxf(0.06, lifetime)
	effect["max"] = float(effect["life"])
	effect["p"] = at
	effect["height"] = height
	effect["start"] = authored_scale
	effect["end"] = authored_scale
	effect["spin"] = 0.0
	effect["angle"] = angle
	effect["pulse_count"] = 0
	effect["pulse_phase"] = 0.0
	effect["peak_alpha"] = 1.0
	effect["axis_y"] = 1.0
	effect["attack_id"] = attack_id
	effect["profile_key"] = String(profile.get("key", ""))
	effect["layer_role"] = role
	effect["sprite_sheet"] = true
	effect["sheet_start"] = window.x
	effect["sheet_count"] = window.y
	effect["sheet_cols"] = grid.x
	effect["sheet_cell"] = cell
	effect["sheet_inset"] = 0.5
	effect["sheet_fps"] = float(layer.get("fps", 0.0))
	effect["sheet_loop"] = bool(layer.get("loop", false))
	effect["dedicated_card_sheet"] = true
	effect["fx_vec"] = Vector2.ZERO
	effect["fx_travel"] = 0.0
	effect["fx_rise"] = 0.0
	effect["fx_curve"] = "hold"
	effect["fx_beats"] = 0
	effect["fx_spin"] = 0.0
	effect["fx_el"] = {}
	effect["fx_arc"] = 0.0
	effect["fx_pop"] = 1.0
	effect["fx_home"] = px2m(at, height)
	effect["follow_eid"] = follow_eid
	effect["follow_actor"] = follow_actor
	effect["return_to_actor"] = false
	effect["return_start"] = Vector2.ZERO
	effect["return_layer"] = {}
	effect["physical_actor_extent"] = actor_metrics and layer.has("world_size_m")
	effect["camera_plane_offset_m"] = _illustrated_plane_offset(asset)
	node.texture = asset.get("texture") as Texture2D
	node.region_enabled = true
	node.region_rect = _sheet_region(effect, window.x)
	node.pixel_size = 0.012 * 96.0 / float(maxi(cell.x, cell.y))
	if actor_metrics and layer.has("world_size_m"):
		node.pixel_size = float(layer["world_size_m"]) / float(maxi(1, cell.y))
	if asset.has("_status_world_size"):
		node.pixel_size = float(asset["_status_world_size"]) / float(maxi(1, cell.y))
	node.material_override = asset.get("material") as Material
	node.modulate = Color.WHITE
	node.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y if _fixed_y_illustrated_asset(asset) \
		else BaseMaterial3D.BILLBOARD_ENABLED
	node.offset = Vector2((0.5 - pivot.x) * float(cell.x), (pivot.y - 0.5) * float(cell.y))
	node.flip_h = bool(pose["flip_h"])
	node.global_position = _illustrated_world_position(asset, at, height)
	node.rotation.z = angle
	node.scale = Vector3.ONE * authored_scale
	node.visible = start_delay <= 0.0
	return true


func _spawn_illustrated_status_activation(at: Vector2, profile: Dictionary,
		attack_id: int = -1, follow_eid: int = -1, follow_actor: bool = false) -> bool:
	var asset := AbilitySprites.reborn_effect_layer_asset(profile, "status")
	if asset.is_empty():
		return false
	var anchor := String(asset.get("anchor", "profile"))
	var life := clampf(float(profile.get("contact", 0.10)) \
		+ float(profile.get("recovery", 0.16)), 0.24, 0.48)
	# Floor constructions remain where the card built them; actor/target accents may follow only for
	# this short activation beat. Their real shield/timer/debuff loop has independent ownership.
	return _spawn_illustrated_card_layer(at, profile, "status",
		float(profile.get("radius", 72.0)), life, 0.78, attack_id, _face_dir,
		follow_eid if anchor != "floor" else -1, follow_actor and anchor != "floor")


func _spawn_reborn_card_release(at: Vector2, profile: Dictionary, attack_id: int) -> void:
	var contact := float(profile.get("contact", 0.10))
	# Exact art uses its manifest's release frames. Cards still waiting for art receive the semantic
	# director's release silhouette, so pressing a card can never produce only a delayed impact.
	var life := clampf(contact + 0.035, 0.085, 0.18)
	if _spawn_illustrated_card_layer(at, profile, "release",
			float(profile.get("radius", 72.0)), life, 0.78, attack_id, _face_dir):
		return
	if _illustrated_only(profile):
		return
	if _spawn_reborn_card_effect(at, profile, "release", float(profile.get("radius", 72.0)),
			life, 0.78, attack_id):
		return
	var plans := RebornFX.phase_plan(profile, "release", _low)
	if not plans.is_empty():
		_spawn_reborn_fallback_layer(at, profile, "release", life, 0.78,
			plans[0] as Dictionary, attack_id)


func _spawn_reborn_card_effect(at: Vector2, profile: Dictionary, phase: String,
		radius_px: float, lifetime: float, height: float, attack_id: int) -> bool:
	if _illustrated_only(profile):
		return _spawn_illustrated_card_layer(at, profile,
			"anticipation" if phase == "gather" else phase, radius_px, lifetime, height,
			attack_id, _face_dir)
	var asset := AbilitySprites.reborn_effect_asset(profile)
	if asset.is_empty():
		return false
	var manifest_phase := "anticipation" if phase == "gather" else phase
	var phases := asset.get("phases", {}) as Dictionary
	if not phases.has(manifest_phase):
		return false
	var window := phases[manifest_phase] as Vector2i
	var anchor_result := _reborn_manifest_anchor(asset, at)
	at = anchor_result.get("at", at) as Vector2
	if bool(anchor_result.get("floor", false)):
		height = 0.20
	var effect: Dictionary = {}
	for value in _effect_pool:
		var candidate := value as Dictionary
		if not bool(candidate.get("active", false)):
			effect = candidate
			break
	if effect.is_empty():
		return false
	var node := effect["node"] as Sprite3D
	var grid := asset.get("grid", Vector2i.ONE) as Vector2i
	var cell := asset.get("cell", Vector2i(96, 96)) as Vector2i
	var pivot := asset.get("pivot", Vector2(0.5, 0.5)) as Vector2
	var authored_scale := clampf(float(profile.get("scale", 1.0)) * radius_px / 90.0
		* float(asset.get("scale", 1.0)), 0.50, 2.10)
	var phase_plan := RebornFX.phase_plan(profile, phase, _low)
	var motion := String((phase_plan[0] as Dictionary).get("motion", "hold")) \
		if not phase_plan.is_empty() else "hold"
	var directional := RebornFX.is_directional(profile)
	effect["active"] = true
	effect["life"] = maxf(0.06, lifetime)
	effect["max"] = float(effect["life"])
	effect["p"] = at
	effect["height"] = height
	effect["spin"] = 0.0
	effect["angle"] = _runtime_sheet_angle(_face_dir) if directional else 0.0
	effect["pulse_count"] = 1 if phase == "gather" else 0
	effect["pulse_phase"] = 0.0
	effect["peak_alpha"] = 1.0
	effect["axis_y"] = 1.0
	effect["attack_id"] = attack_id
	effect["profile_key"] = String(profile.get("key", ""))
	effect["layer_role"] = "reborn_atlas_%s" % phase
	effect["sprite_sheet"] = true
	effect["sheet_start"] = window.x
	effect["sheet_count"] = window.y
	effect["sheet_cols"] = grid.x
	effect["sheet_cell"] = cell
	# A one-pixel inset is enough to keep linear sampling inside a 384px cell while preserving all
	# authored transparent gutters. There is no colour-key or background-removal rewrite at runtime.
	effect["sheet_inset"] = 1.0
	effect["dedicated_card_sheet"] = true
	effect["start"] = authored_scale * (0.72 if phase == "gather" else 0.92)
	effect["end"] = authored_scale * (0.94 if phase == "gather" else 1.08)
	node.texture = asset.get("texture") as Texture2D
	node.region_enabled = true
	node.region_rect = _sheet_region(effect, window.x)
	node.pixel_size = 0.012 * 96.0 / float(maxi(cell.x, cell.y))
	node.material_override = asset.get("material") as Material
	node.modulate = Color.WHITE
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.offset = Vector2((0.5 - pivot.x) * float(cell.x), (pivot.y - 0.5) * float(cell.y))
	node.global_position = px2m(at, height)
	node.rotation.z = float(effect["angle"])
	node.scale = Vector3.ONE * float(effect["start"])
	node.visible = true
	_apply_reborn_motion(effect, profile, at, motion, directional)
	# The atlas supplies its own beats and colour; element motion is reduced to spatial settling only.
	effect["fx_beats"] = 0
	effect["fx_el"] = {}
	effect["fx_pop"] = 1.0
	return true


func _spawn_dedicated_card_effect(at: Vector2, profile: Dictionary, phase: String,
		radius_px: float, lifetime: float, height: float, attack_id: int = -1) -> bool:
	if _illustrated_only(profile):
		return false
	# The streamed card sheet is already a complete, full-colour eight-frame composition. It owns
	# the visual slot by itself: shared masks and the generated sigil remain the exact fallback, but
	# stacking them over this sheet would muddy its authored silhouette and spend two extra draws.
	var texture: Texture2D = AbilitySprites.card_effect_texture_for_profile(profile)
	if texture == null:
		return false
	var profile_key := String(profile.get("key", ""))
	# A sheet can arrive between anticipation and contact. Retire only this cast's provisional gather
	# layers; a prior projectile from the same card may still be resolving elsewhere in the arena.
	for value in _effect_pool:
		var prior := value as Dictionary
		if not bool(prior.get("active", false)) or String(prior.get("profile_key", "")) != profile_key:
			continue
		var prior_role := String(prior.get("layer_role", ""))
		var same_cast := attack_id < 0 or int(prior.get("attack_id", -2)) == attack_id
		if same_cast and phase == "impact" and prior_role.ends_with("gather"):
			_release_effect(prior)
	var effect: Dictionary = {}
	for value in _effect_pool:
		var candidate := value as Dictionary
		if not bool(candidate.get("active", false)):
			effect = candidate
			break
	if effect.is_empty():
		return false
	var node := effect["node"] as Sprite3D
	var authored_scale := clampf(float(profile.get("scale", 1.0))
		* radius_px / 72.0, 0.62, 1.85)
	effect["active"] = true
	effect["life"] = lifetime
	effect["max"] = lifetime
	effect["p"] = at
	effect["height"] = height
	effect["spin"] = 0.0
	effect["angle"] = 0.0
	effect["pulse_count"] = 0
	effect["pulse_phase"] = 0.0
	effect["peak_alpha"] = 1.0
	effect["axis_y"] = 1.0
	effect["attack_id"] = attack_id
	effect["profile_key"] = profile_key
	effect["layer_role"] = "dedicated_card_%s" % phase
	effect["sprite_sheet"] = true
	effect["sheet_start"] = 0 if phase == "gather" else ABILITY_EFFECT_HIT_FRAME
	effect["sheet_count"] = ABILITY_EFFECT_HIT_FRAME if phase == "gather" \
		else AbilitySprites.CARD_FRAME_COUNT - ABILITY_EFFECT_HIT_FRAME
	effect["sheet_cols"] = AbilitySprites.CARD_FRAME_COUNT
	effect["sheet_cell"] = AbilitySprites.CARD_CELL_PX
	effect["sheet_inset"] = 0.5
	effect["dedicated_card_sheet"] = true
	# The sheet frames carry their own action; the world envelope stays deliberately restrained so
	# the art reads at game speed while the profile's spatial delivery still reaches in the correct
	# direction. A 160 px cell keeps the same physical baseline as the legacy 64 px effect stamp.
	effect["start"] = authored_scale * (0.82 if phase == "gather" else 0.94)
	effect["end"] = authored_scale * (1.00 if phase == "gather" else 1.08)
	node.texture = texture
	node.region_enabled = true
	node.region_rect = _sheet_region(effect, int(effect["sheet_start"]))
	node.pixel_size = 0.012 * 64.0 / float(AbilitySprites.CARD_CELL_PX.x)
	node.material_override = AbilitySprites.card_effect_material_for_profile(profile)
	node.modulate = Color(1.0, 1.0, 1.0, 0.98)
	node.global_position = px2m(at, height)
	var seed := int(profile.get("seed", 0))
	var family := AbilitySprites.delivery_family(profile)
	var directional := ORIENTED_RUNTIME_FAMILIES.has(family)
	var facing_angle := _runtime_sheet_angle(_face_dir) if directional else 0.0
	var seed_jitter := (float(seed % 19) - 9.0) * 0.005
	node.rotation.z = facing_angle + seed_jitter
	effect["angle"] = node.rotation.z
	node.scale = Vector3.ONE * float(effect["start"])
	node.visible = true
	_fx_stamp_motion(effect, profile, at)
	# Frame-authored colour, beats and impact growth supersede the shared-mask treatment; only the
	# card's deterministic trajectory remains code-driven.
	effect["fx_beats"] = 0
	effect["fx_el"] = {}
	effect["fx_pop"] = 1.0
	if directional:
		effect["fx_spin"] = 0.0
	return true


func _spawn_reborn_fallback_layer(at: Vector2, profile: Dictionary, phase: String,
		lifetime: float, default_height: float, plan: Dictionary, attack_id: int = -1) -> bool:
	if _illustrated_only(profile):
		return false
	var effect: Dictionary = {}
	for value in _effect_pool:
		var candidate := value as Dictionary
		if not bool(candidate.get("active", false)):
			effect = candidate
			break
	if effect.is_empty():
		return false
	var shape := String(plan.get("shape", "burst"))
	var role := String(plan.get("role", "reborn_%s" % phase))
	var height := float(plan.get("height", default_height))
	var directional := RebornFX.is_directional(profile) and shape in [
		"slash", "beam", "comet", "lightning", "tether", "streak", "rake",
		"wave", "cone", "jaws", "chevron"]
	var base_angle := float(plan.get("angle", 0.0))
	if directional:
		base_angle += _runtime_sheet_angle(_face_dir)
	effect["active"] = true
	effect["life"] = maxf(0.06, float(plan.get("life", lifetime)))
	effect["max"] = float(effect["life"])
	effect["start"] = maxf(0.08, float(plan.get("start", 0.32)))
	effect["end"] = maxf(0.10, float(plan.get("end", 0.92)))
	effect["p"] = at
	effect["height"] = height
	effect["spin"] = float(plan.get("spin", 0.0))
	effect["angle"] = base_angle
	effect["pulse_count"] = int(plan.get("pulse_count", 0))
	effect["pulse_phase"] = float(plan.get("pulse_phase", 0.0))
	effect["peak_alpha"] = clampf(float(plan.get("peak_alpha", 0.92)), 0.0, 1.0)
	effect["axis_y"] = 1.0
	effect["attack_id"] = attack_id
	effect["profile_key"] = String(profile.get("key", ""))
	effect["layer_role"] = role
	effect["sprite_sheet"] = false
	effect["sheet_start"] = 0
	effect["sheet_count"] = 0
	effect["sheet_cols"] = 0
	effect["sheet_cell"] = AbilitySprites.CELL_PX
	effect["sheet_inset"] = 0.0
	effect["dedicated_card_sheet"] = false
	var node := effect["node"] as Sprite3D
	node.texture = RebornFX.texture(shape)
	node.region_enabled = false
	node.material_override = RebornFX.material(shape, "alpha" if role.ends_with("telegraph") else "add")
	node.pixel_size = 0.012
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.offset = Vector2.ZERO
	var palette := profile.get("palette", {}) as Dictionary
	var color_key := String(plan.get("color_key", "highlight"))
	var color := Color(palette.get(color_key, _element_color()))
	node.modulate = Color(color.r, color.g, color.b, float(effect["peak_alpha"]))
	node.global_position = px2m(at, height)
	node.rotation.z = base_angle
	node.scale = Vector3.ONE * float(effect["start"])
	node.visible = true
	_apply_reborn_motion(effect, profile, at, String(plan.get("motion", "hold")), directional)
	return true


func _spawn_reborn_hit(at: Vector2, profile: Dictionary, defeated: bool,
		impact_direction: Vector2 = Vector2.ZERO) -> void:
	if profile.is_empty():
		return
	if _spawn_illustrated_card_layer(at, profile, "defeat" if defeated else "hit",
			float(profile.get("radius", 72.0)), 0.34 if defeated else 0.20, 0.86, -1,
			impact_direction if impact_direction.length_squared() > 0.0001 else _face_dir):
		return
	# The compact review atlases deliberately reuse their four impact drawings instead of carrying a
	# second hit/defeat copy. When that impact atlas is loaded, the normal cast resolution will play it
	# once a few lines later; do not cover it with a generic procedural hit stamp in the meantime.
	if not AbilitySprites.reborn_effect_layer_asset(profile, "impact").is_empty() \
			or _illustrated_only(profile):
		return
	var plan := RebornFX.hit_plan(profile, defeated)
	_spawn_reborn_fallback_layer(at, profile, "impact", float(plan.get("life", 0.20)),
		0.86, plan, -1)


func _retire_cast_gather(profile: Dictionary, attack_id: int) -> void:
	if attack_id < 0:
		return
	var profile_key := String(profile.get("key", ""))
	for value in _effect_pool:
		var effect := value as Dictionary
		if bool(effect.get("active", false)) and int(effect.get("attack_id", -2)) == attack_id \
				and String(effect.get("profile_key", "")) == profile_key \
				and String(effect.get("layer_role", "")).ends_with("gather"):
			_release_effect(effect)


func _profile_effect(at: Vector2, profile: Dictionary, phase: String, attack_id: int = -1,
		confirmed_hit: bool = true, effect_direction: Vector2 = Vector2.ZERO) -> void:
	if profile.is_empty():
		return
	if phase == "impact":
		_retire_cast_gather(profile, attack_id)
		# A self-siphon's final drawings celebrate an actual drain/heal, not an empty cast. Other
		# projectiles still resolve their authored miss/dissipation frames as before.
		if not confirmed_hit and String(profile.get("delivery", "")) == "self_siphon" \
				and _illustrated_only(profile):
			return
	var radius_px := float(profile.get("radius", 72.0))
	var lifetime := (float(profile.get("anticipation", 0.10)) + 0.035) if phase == "gather" \
		else maxf(0.22, float(profile.get("contact", 0.10)) + float(profile.get("recovery", 0.16)))
	var recipe := profile.get("visual_recipe", {}) as Dictionary
	var layering := profile.get("layering", {}) as Dictionary
	var depth_role := String(layering.get(phase, "world_depth"))
	var height := 0.24 if bool(recipe.get("grounded", false)) and phase == "impact" else \
		(0.62 if depth_role == "behind_actor" else (0.92 if depth_role == "front_depth" else 0.78))
	var illustrated_phase := "anticipation" if phase == "gather" else phase
	# Only a confirmed self-siphon's explicit caster absorption follows a moving owner.
	# Victim hits, floor/target impacts and every other delivery retain their existing anchors.
	var follow_caster := false
	var retained_impact: Dictionary = {}
	if phase == "impact" and confirmed_hit and String(profile.get("arch", "")) == "drain" \
			and String(profile.get("delivery", "")) == "self_siphon" and _illustrated_only(profile):
		retained_impact = AbilitySprites.reborn_effect_layer_asset(profile, "impact")
		follow_caster = String(retained_impact.get("anchor", "")) == "actor"
	if _spawn_illustrated_card_layer(at, profile, illustrated_phase, radius_px, lifetime, height,
			attack_id, effect_direction if effect_direction.length_squared() > 0.0001 else _face_dir,
			-1, follow_caster, retained_impact):
		if phase == "impact":
			_impact_extras(at, profile, radius_px, height, attack_id, confirmed_hit, true)
		return
	if _illustrated_only(profile):
		if phase == "impact":
			_impact_extras(at, profile, radius_px, height, attack_id, confirmed_hit, true)
		return
	# Reborn's runtime is a strict three-step ladder: new exact atlas, existing truthful per-card
	# sidecar, then one semantic delivery/motif composition. The former encoded-crest compatibility
	# branch has been removed entirely, so a malformed/missing optional asset cannot reintroduce it.
	var reborn_plans := RebornFX.phase_plan(profile, phase, _low)
	if not reborn_plans.is_empty():
		if _spawn_reborn_card_effect(at, profile, phase, radius_px, lifetime, height, attack_id) \
				or _spawn_dedicated_card_effect(at, profile, phase, radius_px, lifetime, height, attack_id):
			if phase == "impact":
				_impact_extras(at, profile, radius_px, height, attack_id, confirmed_hit)
			return
		for plan_value in reborn_plans:
			if not _spawn_reborn_fallback_layer(at, profile, phase, lifetime, height,
					plan_value as Dictionary, attack_id):
				break
		if phase == "impact":
			_impact_extras(at, profile, radius_px, height, attack_id, confirmed_hit)
		return


# WHAT AN IMPACT NEEDS THAT A STAMP CANNOT GIVE IT: a shockwave leaving the point of contact and a
# very short hold in the fight clock. The Reborn ring is transparent code-native art shared through
# the 24-entry cache; no encoded crest or extra real-time light is introduced on mobile.
func _impact_extras(at: Vector2, profile: Dictionary, radius_px: float, height: float,
		attack_id: int = -1, confirmed_hit: bool = true,
		suppress_procedural_ring: bool = false) -> void:
	var palette := profile.get("palette", {}) as Dictionary
	var col := Color(palette.get("highlight", _element_color()))
	var arch := String(profile.get("arch", "strike"))
	var heavy := arch in ["blast", "nova", "bulwark", "rend", "charge"]
	var free := 0
	for value in _effect_pool:
		if not bool((value as Dictionary).get("active", false)):
			free += 1
	# One reserved slot is enough. Projectile trails already stop six/eight slots before the cap, so
	# withholding the contact ring until three were free made hits vanish under the exact pressure
	# where feedback matters most.
	# In strict mode the manifest's own impact/hit frames are the only visible shock artwork. Keep the
	# tiny gameplay hit-stop and light response below, but never smuggle the procedural ring back in.
	if free >= 1 and not _illustrated_only(profile) and not suppress_procedural_ring:
		for value in _effect_pool:
			var effect := value as Dictionary
			if bool(effect.get("active", false)):
				continue
			var life := 0.30 if heavy else 0.22
			effect["active"] = true; effect["life"] = life; effect["max"] = life
			effect["start"] = maxf(0.12, radius_px * PX2M * 0.20)
			effect["end"] = maxf(0.60, radius_px * PX2M * (1.9 if heavy else 1.45))
			effect["p"] = at; effect["height"] = height
			effect["spin"] = 0.0; effect["angle"] = 0.0
			effect["pulse_count"] = 0; effect["pulse_phase"] = 0.0
			effect["attack_id"] = attack_id
			effect["axis_y"] = 1.0
			effect["profile_key"] = String(profile.get("key", ""))
			effect["layer_role"] = "reborn_shock_impact"
			effect["peak_alpha"] = 0.7
			var node := effect["node"] as Sprite3D
			node.texture = RebornFX.texture("ring")
			node.material_override = RebornFX.material("ring")
			node.region_enabled = false
			node.visible = true
			node.modulate = Color(col.r, col.g, col.b, 0.7)
			node.global_position = px2m(at, height)
			node.rotation.z = 0.0
			node.scale = Vector3.ONE * float(effect["start"])
			break
	if not _impact_lights.is_empty():
		var l := _impact_lights[_next_attack_id % _impact_lights.size()] as OmniLight3D
		if l != null and is_instance_valid(l):
			l.light_color = col
			l.light_energy = 5.5 if heavy else 3.0
			l.omni_range = clampf(radius_px * PX2M * 2.4, 3.0, 9.0)
			l.global_position = px2m(at, 0.9)
			l.visible = true
	if heavy and confirmed_hit:
		_hitstop_t = maxf(_hitstop_t, 0.028 if _low else 0.055)


func _tick_impact_lights(delta: float) -> void:
	for value in _impact_lights:
		var l := value as OmniLight3D
		if l == null or not is_instance_valid(l) or not l.visible:
			continue
		l.light_energy = maxf(0.0, l.light_energy - delta * 26.0)
		if l.light_energy <= 0.01:
			l.visible = false


# THE FIGHT'S OWN CLOCK. Everything that moves in combat reads this instead of the raw delta, so a
# heavy hit can hold the world for 55 ms while the HUD, camera and input keep running at full rate.
func _combat_delta(delta: float) -> float:
	if _hitstop_t <= 0.0:
		return delta
	_hitstop_t = maxf(0.0, _hitstop_t - delta)
	return delta * 0.08


func _projectile_trail(projectile: Dictionary, at: Vector2) -> void:
	# Trails borrow the existing bounded effect pool. No extra lights, particles or unbounded nodes
	# are created, and phone cadence is lower, so a busy volley remains inside the same render cap.
	# Keep a small reserve for hit/gather effects so decorative echoes can never hide combat feedback.
	var active_effects := 0
	for value in _effect_pool:
		if bool((value as Dictionary).get("active", false)):
			active_effects += 1
	if active_effects >= maxi(0, _effect_cap - (6 if _low else 8)):
		return
	var illustrated_profile := projectile.get("profile", {}) as Dictionary
	if not illustrated_profile.is_empty() and _spawn_illustrated_card_layer(at,
			illustrated_profile, "trail",
			maxf(28.0, float(illustrated_profile.get("radius", 72.0)) * 0.55),
			0.16 if _low else 0.19, float(projectile.get("visual_height", 0.82)),
			int(projectile.get("attack_id", -1)),
			Vector2(projectile.get("v", Vector2.RIGHT))):
		return
	if _illustrated_only(illustrated_profile):
		return
	for value in _effect_pool:
		var effect := value as Dictionary
		if bool(effect.get("active", false)):
			continue
		var base := maxf(0.24, float(projectile.get("base_scale", 1.0)) * 0.54)
		effect["active"] = true; effect["life"] = 0.16 if _low else 0.19
		effect["max"] = float(effect["life"])
		effect["start"] = base
		effect["end"] = base * clampf(float(projectile.get("trail_scale_decay", 0.22)), 0.12, 0.44)
		effect["p"] = at; effect["height"] = float(projectile.get("visual_height", 0.82))
		effect["spin"] = float(projectile.get("spin_rate", 0.0)) * 0.42
		effect["angle"] = float(projectile.get("visual_phase", 0.0))
		effect["pulse_count"] = 0; effect["pulse_phase"] = 0.0
		effect["attack_id"] = int(projectile.get("attack_id", -1))
		effect["axis_y"] = 1.0
		effect["profile_key"] = String((projectile.get("profile", {}) as Dictionary).get("key", ""))
		effect["layer_role"] = "reborn_trail"
		var node := effect["node"] as Sprite3D
		var profile := projectile.get("profile", {}) as Dictionary
		var trail_shape := RebornFX.trail_shape(profile) if not profile.is_empty() else "disc"
		effect["sprite_sheet"] = false
		effect["sheet_cell"] = AbilitySprites.CELL_PX
		effect["sheet_cols"] = 0
		effect["sheet_inset"] = 0.0
		effect["dedicated_card_sheet"] = false
		node.region_enabled = false
		node.pixel_size = 0.012
		node.texture = RebornFX.texture(trail_shape) if not profile.is_empty() else _orb_tex
		node.material_override = RebornFX.material(trail_shape) if not profile.is_empty() else null
		if not profile.is_empty() and RebornFX.is_directional(profile):
			effect["angle"] = _runtime_sheet_angle(Vector2(projectile.get("v", Vector2.RIGHT)))
			effect["spin"] = 0.0
		var trail := Color(projectile.get("trail_color", Color.WHITE))
		node.modulate = Color(trail.r, trail.g, trail.b,
			clampf(float(projectile.get("trail_alpha", 0.58)), 0.34, 0.72))
		node.global_position = px2m(at, float(effect["height"]))
		node.rotation.z = float(effect["angle"])
		node.scale = Vector3.ONE * base
		node.visible = true
		return


func _effect(at: Vector2, color: Color, radius_px: float, lifetime: float, height: float) -> void:
	for value in _effect_pool:
		var effect := value as Dictionary
		if bool(effect.get("active", false)):
			continue
		effect["active"] = true; effect["life"] = lifetime; effect["max"] = lifetime
		effect["start"] = maxf(0.2, radius_px * PX2M * 0.25)
		effect["end"] = maxf(0.3, radius_px * PX2M)
		effect["p"] = at; effect["height"] = height
		effect["spin"] = 0.0; effect["angle"] = 0.0
		effect["pulse_count"] = 0; effect["pulse_phase"] = 0.0
		effect["attack_id"] = -1; effect["axis_y"] = 1.0
		effect["sprite_sheet"] = false; effect["sheet_cols"] = 0
		effect["sheet_inset"] = 0.0
		effect["profile_key"] = ""; effect["layer_role"] = "generic"
		var node := effect["node"] as Sprite3D
		node.texture = _orb_tex
		node.visible = true
		node.modulate = Color(color.r, color.g, color.b, 0.86)
		node.global_position = px2m(at, height)
		node.rotation.z = 0.0
		node.scale = Vector3.ONE * float(effect["start"])
		return


# Record what this effect should DO, at spawn, from the caster's frame at that instant. Stored per
# effect rather than read later because facing changes while the effect is still in the air — a
# strike that re-aimed itself mid-sweep because the player turned would read as the world sliding.
func _fx_stamp_motion(effect: Dictionary, profile: Dictionary, at: Vector2) -> void:
	# THE KEY IS "arch". TempleAbilityVisual.profile() returns arch/motif_family/delivery/element;
	# there is no "archetype". Reading the wrong name fell through to motif_family ("flame") and
	# then delivery ("lunge_bite"), neither of which is in FX_MOTION, so every one of the 402 cards
	# resolved to an EMPTY profile: travel 0, rise 0, beats 0, spin 0. The whole per-card motion
	# layer was inert and nothing errored — it just quietly animated like it had before.
	# Caught by dev_cardcheck, which walks every L50 deck and refuses a card that cannot resolve.
	var arch := String(profile.get("arch", ""))
	if not FX_MOTION.has(arch):
		arch = String(profile.get("motif_family", ""))
	var m: Dictionary = FX_MOTION.get(arch, {}) as Dictionary
	var frame := _fx_frame()
	var fwd: Vector2 = frame[0]
	var tan: Vector2 = frame[1]
	var v := Vector2.ZERO
	match String(m.get("dir", "hold")):
		"forward": v = fwd
		"back":    v = -fwd
		"tangent": v = tan
		"toward", "inward":
			v = (_ppos - at).normalized() if (_ppos - at).length() > 1.0 else -fwd
		_: v = Vector2.ZERO
	effect["fx_vec"] = v
	effect["fx_travel"] = float(m.get("travel", 0.0))
	effect["fx_rise"] = float(m.get("rise", 0.0))
	effect["fx_curve"] = String(m.get("curve", "ease"))
	effect["fx_beats"] = int(m.get("beats", 0))
	effect["fx_spin"] = float(m.get("spin", 0.0))
	effect["fx_el"] = FX_ELEMENT.get(String(profile.get("element", "")), {}) as Dictionary
	_fx_card_variation(effect, profile, m)
	# Store the spawn point from the cast, not whatever location this pooled Sprite3D had during its
	# previous use.  Reading the node before callers repositioned it made effects jump from stale
	# pool coordinates on their first animated frame.
	effect["fx_home"] = px2m(at, float(effect.get("height", 0.78)))


# ==============================================================================================
# AND THEN EACH CARD, INDIVIDUALLY.
# ==============================================================================================
# Archetype gives twelve behaviours and element gives five treatments — sixty combinations across
# 402 cards, so Ember Bite and Flame Burst could still move identically. This layer makes every
# card its own, and it does it from the card's OWN authored fields rather than from noise: its
# motif (fang, comet, bloom...), its impact (fang_snap, shatter...), its delivery shape, its
# authored scale and radius, and its seed. Two cards that differ on paper differ on screen.
#
# THE VARIATION IS BOUNDED ON PURPOSE — roughly a quarter either side. A player must still be able
# to read "that was a Nova" at a glance, and a per-card swing wide enough to turn one archetype
# into another would buy uniqueness by destroying legibility. The archetype stays the sentence;
# the card is its accent.
func _fx_card_variation(effect: Dictionary, profile: Dictionary, m: Dictionary) -> void:
	var seed_v: int = int(profile.get("seed", 0))
	if seed_v == 0:
		seed_v = hash(String(profile.get("key", "")))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v                          # deterministic: a card looks the same every cast
	# the authored numbers first — a card with a big radius should throw a big effect
	var scale_a: float = clampf(float(profile.get("scale", 1.0)), 0.6, 1.8)
	var radius_a: float = float(profile.get("radius", 72.0))
	var reach: float = clampf(radius_a / 90.0, 0.65, 1.5)
	effect["fx_travel"] = float(effect.get("fx_travel", 0.0)) * reach * rng.randf_range(0.86, 1.16)
	effect["fx_rise"] = float(effect.get("fx_rise", 0.0)) * rng.randf_range(0.82, 1.20)
	effect["fx_spin"] = float(effect.get("fx_spin", 0.0)) * rng.randf_range(0.70, 1.35) \
		* (-1.0 if rng.randf() < 0.42 else 1.0)      # some cards turn the other way
	# ARC. The one addition that changes the SHAPE of a path rather than its size: the effect bows
	# sideways as it travels. A motif with a curve in its name bows harder than one without.
	var motif := String(profile.get("motif_family", profile.get("motif", "")))
	var curvy := motif in ["comet", "moon", "bloom", "spiral", "wave", "leaf", "wing", "flame"]
	effect["fx_arc"] = rng.randf_range(0.12, 0.46) * (1.55 if curvy else 0.55) \
		* (-1.0 if rng.randf() < 0.5 else 1.0)
	# IMPACT SHAPE. A snapping impact lands in one hard beat; a shattering or scattering one lands
	# in several. This is what makes a bite read differently from a burst inside one archetype.
	var impact := String(profile.get("impact", ""))
	var multi := impact.contains("shatter") or impact.contains("burst") or impact.contains("scatter") \
		or impact.contains("split") or impact.contains("storm")
	if int(effect.get("fx_beats", 0)) == 0 and multi:
		effect["fx_beats"] = 2 if rng.randf() < 0.6 else 3
	# and how hard it swells on arrival, from the card's own authored scale
	effect["fx_pop"] = clampf(scale_a * rng.randf_range(0.88, 1.18), 0.7, 1.9)

func _tick_effects(delta: float) -> void:
	_tick_impact_lights(delta)
	for value in _effect_pool:
		var effect := value as Dictionary
		if not bool(effect.get("active", false)):
			continue
		var node := effect["node"] as Sprite3D
		var step := delta
		var delay := float(effect.get("start_delay", 0.0))
		if delay > 0.0:
			effect["start_delay"] = maxf(0.0, delay - step)
			if delay > step:
				node.visible = false
				continue
			step -= delay
			node.visible = true
		effect["life"] = float(effect["life"]) - step
		if float(effect["life"]) <= 0.0:
			_release_effect(effect)
			continue
		var t := 1.0 - float(effect["life"]) / maxf(0.001, float(effect["max"]))
		if bool(effect.get("return_to_actor", false)):
			var start := effect.get("return_start", _ppos) as Vector2
			var pos := start.lerp(_ppos, t)
			effect["p"] = pos
			node.global_position = px2m(pos, float(effect.get("height", 0.82)))
			# Return sheets are authored facing left: outward aim rotates their leading ember
			# toward the moving caster, without a second damage projectile or arbitrary spin.
			var outward := start - _ppos
			if outward.length_squared() > 0.0001:
				var pose := _illustrated_layer_pose(effect.get("return_layer", {}) as Dictionary, outward)
				effect["angle"] = float(pose["angle"])
				node.flip_h = bool(pose["flip_h"])
		elif bool(effect.get("follow_actor", false)):
			effect["fx_home"] = px2m(_ppos, float(effect.get("height", 0.78)))
			node.global_position = effect["fx_home"] as Vector3
		elif int(effect.get("follow_eid", -1)) >= 0:
			var followed := _target_by_eid(int(effect.get("follow_eid", -1)))
			if not followed.is_empty():
				effect["fx_home"] = px2m(_target_pos(followed), float(effect.get("height", 0.78)))
				node.global_position = effect["fx_home"] as Vector3
		var plane_offset := float(effect.get("camera_plane_offset_m", 0.0))
		if plane_offset > 0.0:
			# Recompute from the unbiased anchor each tick; camera turns must not accumulate drift.
			node.global_position = _actor_ward_front_position(effect["fx_home"] as Vector3, plane_offset)
		if bool(effect.get("sprite_sheet", false)):
			var sheet_count := maxi(1, int(effect.get("sheet_count", AbilitySprites.FRAME_COUNT)))
			var sheet_local := mini(int(floor(t * float(sheet_count))), sheet_count - 1)
			var sheet_fps := float(effect.get("sheet_fps", 0.0))
			if sheet_fps > 0.0:
				sheet_local = int(floor((float(effect["max"]) - float(effect["life"])) * sheet_fps))
				sheet_local = sheet_local % sheet_count if bool(effect.get("sheet_loop", false)) \
					else mini(sheet_local, sheet_count - 1)
			var sheet_frame := int(effect.get("sheet_start", 0)) + sheet_local
			node.region_rect = _sheet_region(effect, sheet_frame)
		# THE ENVELOPE IS WHERE THE PUNCH LIVES. A linear scale lerp with a linear fade — what this
		# was — reads as a balloon inflating while it evaporates: no moment of arrival. An impact
		# SNAPS to size (overshoots to 1.12x its end scale in the first fifth of its life), HOLDS
		# bright through contact, then falls away on a curve. Gathers are the reverse: they close in.
		var st := float(effect["start"])
		var en := float(effect["end"])
		var role := String(effect.get("layer_role", ""))
		var scale: float
		var alpha: float
		if bool(effect.get("physical_actor_extent", false)) \
				or role in ["illustrated_block", "illustrated_expire", "illustrated_return"]:
			# These frames depict the same wall/status object through an event. A generic impact
			# overshoot would enlarge its physical silhouette between otherwise aligned drawings.
			scale = st
			alpha = 1.0 if role == "illustrated_return" or t < 0.75 \
				else maxf(0.0, 1.0 - (t - 0.75) / 0.25)
		elif role.ends_with("gather") or role.ends_with("telegraph"):
			scale = lerpf(st, en, t * t)
			alpha = 0.35 + 0.65 * t
		elif role == "dash_action_echo" or role.ends_with("_trail"):
			# Body afterimages and projectile trails should peel cleanly away from motion instead of
			# popping like a second impact. A fast ease-down preserves the readable action silhouette.
			scale = lerpf(st, en, 1.0 - pow(1.0 - t, 2.0))
			alpha = pow(1.0 - t, 1.35)
		else:
			var pop := clampf(t / 0.20, 0.0, 1.0)
			var over := 1.0 + 0.12 * sin(pop * PI)
			scale = lerpf(st, en, 1.0 - pow(1.0 - pop, 3.0)) * over
			alpha = 1.0 if t < 0.35 else 1.0 - pow((t - 0.35) / 0.65, 1.6)
		var pulses := int(effect.get("pulse_count", 0))
		if pulses > 0:
			scale *= 1.0 + sin(t * TAU * float(pulses) + float(effect.get("pulse_phase", 0.0))) \
				* 0.075 * (1.0 - t)
		# ── the archetype's own motion, on top of the shared envelope ──
		var beats := int(effect.get("fx_beats", 0))
		if beats > 0:
			# STORM AND JOLT ARE DISCONTINUOUS ON PURPOSE, as are rend's three staggered rakes and
			# quick's afterimages: discrete frames with gaps, never a smooth ramp. This is the one
			# motion property no palette can imitate.
			if floori(t * float(beats * 2)) % 2 == 1:
				alpha *= 0.18
		var elm: Dictionary = effect.get("fx_el", {}) as Dictionary
		if not elm.is_empty():
			var hold := float(elm.get("hold", 0.0))
			if hold > 0.0 and t < hold:
				alpha = maxf(alpha, 1.0)
			var flick := float(elm.get("flick", 0.0))
			if flick > 0.0:
				alpha *= 1.0 - flick * (0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.045 \
					+ float(effect.get("pulse_phase", 0.0))))
			var settle := float(elm.get("settle", 0.0))
			if settle > 0.0:
				scale *= 1.0 - settle * pow(t, 3.0)      # Beast lands rather than easing away
		var travel := float(effect.get("fx_travel", 0.0))
		var rise := float(effect.get("fx_rise", 0.0))
		if travel != 0.0 or rise != 0.0:
			var p: float
			match String(effect.get("fx_curve", "ease")):
				"in":   p = t * t                                   # accelerates away
				"hold": p = clampf(t / 0.28, 0.0, 1.0)              # arrives fast, then stays
				"loop": p = 0.5 - 0.5 * cos(t * TAU * 2.0)          # a buff announces itself again
				_:      p = 1.0 - pow(1.0 - t, 2.0)                 # eases out
			var vv: Vector2 = effect.get("fx_vec", Vector2.ZERO)
			var home: Vector3 = effect.get("fx_home", node.global_position)
			var sag := (float(elm.get("sag", 0.0)) * t) if not elm.is_empty() else 0.0
			# THE CARD'S OWN BOW. A sideways offset that peaks mid-flight and returns to zero, so
			# the effect arrives exactly where the archetype aims it but takes its own path there —
			# the difference between two same-archetype cards that a player can actually see.
			var arc := float(effect.get("fx_arc", 0.0)) * sin(p * PI)
			var side := Vector2(-vv.y, vv.x)
			node.global_position = home \
				+ Vector3(vv.x, 0.0, vv.y) * (travel * p) \
				+ Vector3(side.x, 0.0, side.y) * arc \
				+ Vector3(0.0, rise * p - sag, 0.0)
		scale *= float(effect.get("fx_pop", 1.0))
		node.scale = Vector3(scale, scale * float(effect.get("axis_y", 1.0)), scale)
		effect["angle"] = float(effect.get("angle", 0.0)) + float(effect.get("spin", 0.0)) * delta
		# Preserve the card-specific profile spin.  The prior two assignments wrote fx_spin and then
		# immediately overwrote it with angle, leaving every intended variation visually inert.
		node.rotation.z = float(effect["angle"]) + t * float(effect.get("fx_spin", 0.0))
		var color := node.modulate
		node.modulate = Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0) * float(effect.get("peak_alpha", 1.0)))


func _float_text(at: Vector2, text: String, color: Color) -> void:
	for value in _floater_pool:
		var floater := value as Dictionary
		if bool(floater.get("active", false)):
			continue
		# TWO FLOATERS ON ONE PIXEL PRINT ON TOP OF EACH OTHER. A kill spawns the damage number and
		# the PURGED banner in the same frame at the same world point, and the result on screen was
		# "+100ABURGED" — two correct strings, one illegible glyph soup, in every screenshot of a
		# kill. Give each new floater a lane: step it up and alternate it sideways past whatever is
		# still in the air near it, so a burst of three reads as three lines.
		var lane := 0
		for other in _floater_pool:
			var o := other as Dictionary
			if not bool(o.get("active", false)):
				continue
			if (Vector2(o.get("p", Vector2.ZERO)) - at).length() < 96.0:
				lane += 1
		floater["active"] = true; floater["life"] = 0.82; floater["max"] = 0.82
		var spread := Vector2(0.0, 0.0)
		if lane > 0:
			# +/- 46 px alternating, so a pair straddles the point instead of stacking on it
			spread.x = 46.0 * (float((lane + 1) / 2) * (1.0 if lane % 2 == 1 else -1.0))
		var h := 1.45 + 0.30 * float(lane)
		floater["p"] = at + spread; floater["height"] = h
		var label := floater["node"] as Label3D
		label.font_size = 28 if _phone_hud_active() else 44
		label.outline_size = 4 if _phone_hud_active() else 8
		label.text = text
		label.modulate = color
		label.global_position = px2m(at + spread, h)
		label.visible = true
		return


func _tick_floaters(delta: float) -> void:
	for value in _floater_pool:
		var floater := value as Dictionary
		if not bool(floater.get("active", false)):
			continue
		floater["life"] = float(floater["life"]) - delta
		var label := floater["node"] as Label3D
		if float(floater["life"]) <= 0.0:
			floater["active"] = false
			label.visible = false
			continue
		floater["height"] = float(floater["height"]) + 0.60 * delta
		label.global_position = px2m(Vector2(floater["p"]), float(floater["height"]))
		var a := float(floater["life"]) / float(floater["max"])
		var c := label.modulate
		label.modulate = Color(c.r, c.g, c.b, a)


# ================================= HUD ==========================================================
# ==============================================================================================
# THE COMBAT HUD — one command deck, one compact status crown, and an unobstructed arena.
# ==============================================================================================
# WHAT WAS WRONG. Three rounded plates across the top, a card block, five buttons and a message
# band: measured at 844x390 that is 48.6% of a landscape phone spent on chrome, and the certified
# gameplay-safe window was 844x112 — 28.7% of the screen height, a letterbox slot for a game whose
# whole verb is dodging. Counting readouts, the player was offered about thirty-six things while
# fighting. It read as a dashboard with a game behind it.
#
# WHAT REPLACES IT. The five-wave crown owns pace at top-centre, score/combo is a quiet top-left
# plaque, and the large centred plinth owns every card decision. Health/name remain attached to the
# creatures in world space; no duplicate lower-left character dashboard returns.
#
# THE CENTRE OF THE SCREEN IS LEFT EMPTY. Nothing persistent may sit in the middle half of the
# frame in either axis; that is where the fight is.
func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 44
	_hud_layer.name = "RebornCombatCockpit"
	add_child(_hud_layer)
	_hud_root = Control.new()
	_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_hud_root)

	# CHAMBER COMMAND: the run's destination and progress are one strong top-centre instrument.
	_wave_plate = PanelContainer.new()
	_wave_plate.name = "ChamberCommand"
	_wave_plate.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_wave_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_wave_plate)
	var wave_content := Control.new()
	wave_content.name = "ChamberCommandContent"
	wave_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_plate.add_child(wave_content)
	_wave_accent = _new_hud_accent("wave", wave_content)
	_wave_label = _hud_label("", int(PHONE_FONTS["wave"]) if _low else 21, Color("fff0d0"))
	_wave_label.name = "ChamberTitle"
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wave_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_wave_label.add_theme_color_override("font_outline_color", Color(0.005, 0.02, 0.03, 0.98))
	_wave_label.add_theme_constant_override("outline_size", 3)
	_apply_hud_font(_wave_label, "display")
	wave_content.add_child(_wave_label)
	_pack_dots = _hud_label("", int(PHONE_FONTS["remaining"]) if _low else 13, Color("55e3df"))
	_pack_dots.name = "SurgeProgress"
	_pack_dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_pack_dots.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pack_dots.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	wave_content.add_child(_pack_dots)
	_remaining_label = _hud_label("", int(PHONE_FONTS["remaining"]) if _low else 13, Color("f2b84b"))
	_remaining_label.name = "WavesRemaining"
	_remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_remaining_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_remaining_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	wave_content.add_child(_remaining_label)

	# RUN TELEMETRY: quiet and asymmetric at top-left, separated from creature vitality.
	_score_plate = PanelContainer.new()
	_score_plate.name = "RunTelemetry"
	_score_plate.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_score_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_score_plate)
	var score_content := Control.new()
	score_content.name = "RunTelemetryContent"
	score_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_plate.add_child(score_content)
	_score_accent = _new_hud_accent("score", score_content)
	_run_status_label = _hud_label("PURGE RUN  /  LIVE", 10 if _low else 11, Color("c99aff"))
	_run_status_label.name = "RunStatus"
	_run_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_run_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_hud_font(_run_status_label, "head")
	score_content.add_child(_run_status_label)
	_score_label = _hud_label("", int(PHONE_FONTS["score"]) if _low else 17, Color("ffe4a0"))
	_score_label.name = "ScoreCombo"
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_score_label.add_theme_color_override("font_outline_color", Color(0.005, 0.02, 0.03, 0.98))
	_score_label.add_theme_constant_override("outline_size", 3)
	_apply_hud_font(_score_label, "head")
	score_content.add_child(_score_label)

	# The utility rail sits behind three dedicated targets constructed with the touch HUD.
	_utility_rail = Control.new()
	_utility_rail.name = "UtilityRail"
	_utility_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_utility_rail)
	_utility_accent = _new_hud_accent("utility", _utility_rail)

	# EXIT is intentionally coral and terminal; tactical and settings remain cyan instruments.
	_exit_button = Button.new()
	_exit_button.name = "ExitTemple"
	_exit_button.text = "EXIT\nESC"
	_exit_button.tooltip_text = "Leave the Wicked Temple (Esc / controller Start)"
	_exit_button.add_theme_font_size_override("font_size", int(PHONE_FONTS["button"]) if _low else 15)
	_apply_hud_font(_exit_button, "head")
	_exit_button.add_theme_color_override("font_color", Color("fff0eb"))
	_exit_button.add_theme_stylebox_override("normal", _hud_style(
		Color(0.11, 0.027, 0.060, 0.94), Color("c94d61"), 1, 0))
	_exit_button.add_theme_stylebox_override("hover", _hud_style(
		Color(0.24, 0.041, 0.083, 0.98), Color("ff6478"), 2, 0))
	_exit_button.add_theme_stylebox_override("pressed", _hud_style(
		Color(0.34, 0.05, 0.09, 1.0), Color("fff0eb"), 2, 0))
	_exit_button.focus_mode = Control.FOCUS_NONE
	_exit_button.clip_text = true
	_exit_button.pressed.connect(_request_exit)
	_hud_root.add_child(_exit_button)

	# Hidden compatibility seam only. The player and every Corruptimon own tiny world-space plates;
	# the reborn cockpit never repeats health at lower-left.
	var vit := Panel.new()
	vit.name = "Vitality"
	vit.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	vit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vit.visible = false
	_hud_root.add_child(vit)
	_vitality = vit
	_hp_bar = ProgressBar.new(); _hp_bar.show_percentage = false
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vit.add_child(_hp_bar)
	_hp_label = _hud_label("", 1, Color.TRANSPARENT)
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vit.add_child(_hp_label)
	_unit_label = _hud_label("", 1, Color.TRANSPARENT)
	_unit_label.visible = false
	_hud_root.add_child(_unit_label)
	_rarity_label = _hud_label("", 1, Color.TRANSPARENT)
	_rarity_label.visible = false
	_hud_root.add_child(_rarity_label)

	# A tiny optional focus bar sits below chamber command; overhead red bars remain authoritative.
	var tgt := Control.new()
	tgt.name = "FocusedThreat"
	tgt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tgt.visible = false
	_hud_root.add_child(tgt)
	_target_holder = tgt
	_target_bar = ProgressBar.new(); _target_bar.show_percentage = false
	_target_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_target_bar.add_theme_stylebox_override("background", _hud_style(
		Color(0.015, 0.025, 0.035, 0.88), Color(0.30, 0.39, 0.43, 0.70), 1, 0))
	_target_bar.add_theme_stylebox_override("fill", _hud_style(
		Color("d84159"), Color("ff6478"), 1, 0))
	_target_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tgt.add_child(_target_bar)
	_target_label = _hud_label("", int(PHONE_FONTS["target"]) if _low else 10, Color("fff0eb"))
	_target_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_target_label.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.03, 0.98))
	_target_label.add_theme_constant_override("outline_size", 3)
	_target_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tgt.add_child(_target_label)

	# Transient feedback is a narrow cyan instrument ribbon, not a permanent centre panel.
	_fighter_plate = PanelContainer.new()
	_fighter_plate.name = "CombatMessage"
	_fighter_plate.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_fighter_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fighter_plate.visible = false
	_hud_root.add_child(_fighter_plate)
	_message_accent = _new_hud_accent("message", _fighter_plate)
	_message_label = _hud_label("", int(PHONE_FONTS["message"]) if _low else 18, Color("f6f1e7"))
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_label.add_theme_color_override("font_outline_color", Color(0.005, 0.02, 0.03, 0.98))
	_message_label.add_theme_constant_override("outline_size", 3)
	_apply_hud_font(_message_label, "head")
	_message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fighter_plate.add_child(_message_label)

	# Grounded energy core + three clean authored card faces.
	_build_plinth()
	_build_card_preview()
	_build_touch_hud()
	_build_controls_overlay()
	_layout_hud()
	_refresh_hud(true)
	# The arena opens clean. GUIDE remains one explicit top-right action when instructions are wanted.


# THE PLINTH. The card hand is centred and the resource band is physically above it. Chikoria's
# existing essence icon makes energy recognisable without relying on font glyph support; the number
# and sockets provide redundant, colour-independent state. All control hints live BELOW the art.
func _build_plinth() -> void:
	var block := PanelContainer.new()
	block.name = "AbilityDock"
	var empty_frame := StyleBoxEmpty.new()
	empty_frame.content_margin_left = 12.0 if _low else 14.0
	empty_frame.content_margin_right = 12.0 if _low else 14.0
	empty_frame.content_margin_top = 0.0 if _low else 1.0
	empty_frame.content_margin_bottom = 0.0
	block.add_theme_stylebox_override("panel", empty_frame)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mobile_deck_clip = Control.new()
	_mobile_deck_clip.name = "MobileDeckEdge"
	_mobile_deck_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_mobile_deck_clip)
	_mobile_deck_clip.add_child(block)
	_plinth = block
	_deck_accent = _new_hud_accent("deck", block)
	_deck_accent.visible = false
	var stack := VBoxContainer.new()
	stack.name = "CommandDeck"
	stack.add_theme_constant_override("separation", 0 if _low else 1)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(stack)

	var energy_band := HBoxContainer.new()
	energy_band.name = "EnergyCore"
	energy_band.custom_minimum_size.y = 40.0 if _low else 25.0
	energy_band.alignment = BoxContainer.ALIGNMENT_CENTER
	energy_band.add_theme_constant_override("separation", 6 if _low else 8)
	energy_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(energy_band)

	_sel_card_label = _hud_label("", int(PHONE_FONTS["card_name"]) if _low else 13,
		Color("f6f1e7"))
	_sel_card_label.name = "SelectedAbility"
	_sel_card_label.visible = false
	_sel_card_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sel_card_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sel_card_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_sel_card_label.add_theme_color_override("font_outline_color", Color(0.005, 0.02, 0.03, 0.98))
	_sel_card_label.add_theme_constant_override("outline_size", 3)
	_apply_hud_font(_sel_card_label, "head")
	_sel_card_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	energy_band.add_child(_sel_card_label)

	_energy_row = _hud_label("ENERGY CORE", 10 if _low else 11, Color("55e3df"))
	_energy_row.name = "EnergyCoreTitle"
	_energy_row.visible = false
	_energy_row.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_energy_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_hud_font(_energy_row, "head")
	energy_band.add_child(_energy_row)

	_energy_icon = TextureRect.new()
	_energy_icon.name = "EnergyIcon"
	_energy_icon.custom_minimum_size = Vector2(26.0, 26.0) if _low else Vector2(20.0, 20.0)
	_energy_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_energy_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_energy_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(ENERGY_ICON_PATH):
		_energy_icon.texture = load(ENERGY_ICON_PATH) as Texture2D
	energy_band.add_child(_energy_icon)

	_energy_label = _hud_label("", int(PHONE_FONTS["energy"]) if _low else 15, Color("f6f1e7"))
	_energy_label.name = "EnergyValue"
	_energy_label.custom_minimum_size.x = 52.0 if _low else 60.0
	_energy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_energy_label.tooltip_text = "Card energy available"
	_apply_hud_font(_energy_label, "head")
	_energy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	energy_band.add_child(_energy_label)

	var socket_row := HBoxContainer.new()
	socket_row.name = "EnergySockets"
	socket_row.alignment = BoxContainer.ALIGNMENT_CENTER
	socket_row.add_theme_constant_override("separation", 3)
	socket_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	energy_band.add_child(socket_row)
	_sockets.clear()
	for i in range(4):
		var sock := Panel.new()
		sock.name = "CoreCell%d" % i
		sock.custom_minimum_size = Vector2(12.0 if _low else 15.0, 8.0 if _low else 10.0)
		sock.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		sock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		socket_row.add_child(sock)
		_sockets.append(sock)

	var cards := HBoxContainer.new()
	cards.name = "AbilityCardRow"
	cards.add_theme_constant_override("separation", 8 if _low else 11)
	stack.add_child(cards)
	_build_card_row(cards)


func _build_card_preview() -> void:
	_card_preview = Panel.new()
	_card_preview.name = "AbilityInspection"
	_card_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_preview.z_index = 30
	_card_preview.visible = false
	_card_preview.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_hud_root.add_child(_card_preview)
	_preview_accent = _new_hud_accent("preview", _card_preview)
	_preview_accent.visible = false

	_card_preview_art = TextureRect.new()
	_card_preview_art.name = "FullCardArt"
	_card_preview_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_preview_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card_preview_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_card_preview_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_preview.add_child(_card_preview_art)
	_card_preview_name = _hud_label("", int(PHONE_FONTS["card_name"]) if _low else 17,
		Color("f6f1e7"))
	_card_preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_preview_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card_preview_name.add_theme_color_override("font_outline_color", Color(0.005, 0.02, 0.03, 0.98))
	_card_preview_name.add_theme_constant_override("outline_size", 3)
	_apply_hud_font(_card_preview_name, "head")
	_card_preview_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_preview_name.visible = false
	_card_preview.add_child(_card_preview_name)
	_card_preview_detail = _hud_label("", int(PHONE_FONTS["card_footer"]) if _low else 12,
		Color("9fb7bf"))
	_card_preview_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_preview_detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_hud_font(_card_preview_detail, "body")
	_card_preview_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_preview_detail.visible = false
	_card_preview.add_child(_card_preview_detail)


func _socket_fill(i: int, lit: bool) -> void:
	if i < 0 or i >= _sockets.size():
		return
	var p := _sockets[i] as Panel
	if p == null or not is_instance_valid(p):
		return
	# Cyan is exclusively actionable energy; spent cells recede into the ink rail.
	p.add_theme_stylebox_override("panel", _hud_style(
		Color("55e3df") if lit else Color(0.025, 0.10, 0.12, 0.88),
		Color("d9fffb") if lit else Color(0.18, 0.38, 0.40, 0.72), 1, 0))


# THE CARD ITSELF. The authored face is sacrosanct: no key badge, cost pip, cooldown shutter, label
# or generated mark is parented over it. Input hint, cost and cooldown sit in a separate line below.
func _build_card_row(parent: Control) -> void:
	_card_hud.clear()
	for i in range(3):
		var holder := VBoxContainer.new()
		holder.name = "AbilityChannel%d" % i
		holder.add_theme_constant_override("separation", 0 if _low else 1)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(holder)
		# The slot owns layout and input; only its visual child moves. A drawn card therefore never
		# shifts the published hit rectangle or asks a Container to reconcile an animated minimum size.
		var slot := Control.new()
		slot.name = "CardSlot%d" % i
		slot.custom_minimum_size = Vector2(164.0, 164.0) if _low else Vector2(140.0, 210.0)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.clip_contents = false
		holder.add_child(slot)
		var panel := Panel.new()
		panel.name = "CardDock%d" % i
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.clip_contents = false
		panel.z_index = 1
		panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		slot.add_child(panel)
		var art := TextureRect.new()
		art.name = "CleanCardFace%d" % i
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var art_inset := 0.0
		art.offset_left = art_inset; art.offset_top = art_inset
		art.offset_right = -art_inset; art.offset_bottom = -art_inset
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(art)
		var button := TextureButton.new()
		button.name = "CleanCardArt%d" % i
		button.set_anchors_preset(Control.PRESET_FULL_RECT)
		button.offset_left = 0.0; button.offset_top = 0.0
		button.offset_right = 0.0; button.offset_bottom = 0.0
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		# Texture stays attached for accessibility/tooling, while the dedicated visual layer draws it.
		# A transparent fixed button receives input even while the face lifts above the hand.
		button.self_modulate = Color(1.0, 1.0, 1.0, 0.0)
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		var idx := i
		button.pressed.connect(_on_card_pressed.bind(idx))
		button.mouse_entered.connect(_on_card_preview_hover.bind(idx, true))
		button.mouse_exited.connect(_on_card_preview_hover.bind(idx, false))
		button.focus_entered.connect(_on_card_preview_focus.bind(idx, true))
		button.focus_exited.connect(_on_card_preview_focus.bind(idx, false))
		slot.add_child(button)
		panel.resized.connect(_sync_card_draw_geometry.bind(idx))

		# Recovery is physically outside the authored artwork. It fills cyan back to ready; no shutter,
		# number, or badge can ever obscure the creature or ability illustration.
		var recovery := ProgressBar.new()
		recovery.name = "RecoveryRail%d" % i
		recovery.show_percentage = false
		recovery.custom_minimum_size.y = 4.0 if _low else 3.0
		recovery.min_value = 0.0
		recovery.max_value = 1.0
		recovery.value = 1.0
		recovery.mouse_filter = Control.MOUSE_FILTER_IGNORE
		recovery.add_theme_stylebox_override("background", _hud_style(
			Color(0.02, 0.07, 0.09, 0.88), Color(0.20, 0.39, 0.42, 0.55), 0, 0))
		recovery.add_theme_stylebox_override("fill", _hud_style(
			Color("55e3df"), Color("55e3df"), 0, 0))
		holder.add_child(recovery)

		var state := HBoxContainer.new()
		state.name = "CardResource%d" % i
		state.alignment = BoxContainer.ALIGNMENT_CENTER
		state.add_theme_constant_override("separation", 5 if _low else 4)
		state.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(state)
		var cost_icon := TextureRect.new()
		cost_icon.name = "CardEnergyIcon%d" % i
		cost_icon.texture = _energy_icon.texture if _energy_icon != null else null
		cost_icon.custom_minimum_size = Vector2(22.0, 22.0) if _low else Vector2(14.0, 14.0)
		cost_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cost_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cost_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cost_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		state.add_child(cost_icon)
		var hint := _hud_label("", int(PHONE_FONTS["card_footer"]) if _low else 13,
			Color("b8c8cc"))
		hint.name = "CardState%d" % i
		hint.custom_minimum_size.y = 40.0 if _low else 14.0
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# This label is content-sized inside a centered HBox. Ellipsis collapses its minimum width
		# to zero, hiding the cost while leaving only the icon visible on native renderers.
		hint.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		_apply_hud_font(hint, "head")
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		state.add_child(hint)
		# These invisible labels preserve the long-standing tooling dictionary without touching art.
		var name_label := _hud_label("", 1, Color(0, 0, 0, 0))
		name_label.visible = false
		holder.add_child(name_label)
		var cool := _hud_label("", 1, Color(0, 0, 0, 0))
		cool.visible = false
		holder.add_child(cool)
		_card_hud.append({"holder": holder, "slot": slot, "panel": panel, "draw": panel,
			"art": art, "button": button,
			"name": name_label, "cool": cool, "hint": hint, "recovery": recovery,
			"cost_icon": cost_icon, "state": state,
			"stones": []})


func _sync_card_draw_geometry(visible_index: int) -> void:
	var face := _card_draw_node(visible_index)
	if face != null and is_instance_valid(face):
		face.pivot_offset = Vector2(face.size.x * 0.5, face.size.y)


func _build_touch_hud() -> void:
	# BUILT ONLY FOR A THUMB. On a desktop these two were a decorative circle labelled MOVE next to
	# a keyboard, and a DODGE button duplicating SPACE. _touch_rects_for no longer emits their rects
	# there either, so the widgets, their hit-tests and their footprint all leave together.
	# Construct once regardless of graphics quality; live layout controls visibility after rotation
	# or device changes. A high-quality phone needs a stick, a low-quality desktop does not.
	if _move_panel == null:
		_move_panel = Panel.new()
		_move_panel.name = "VectorPad"
		_move_panel.add_theme_stylebox_override("panel", _hud_style(
			Color(0.015, 0.075, 0.095, 0.52), Color(0.33, 0.89, 0.87, 0.68), 1, 64))
		_move_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud_root.add_child(_move_panel)
		var move_label := _hud_label("MOVE", int(PHONE_FONTS["move"]), Color(0.83, 1.0, 0.98, 0.78))
		move_label.name = "MoveCaption"
		_apply_hud_font(move_label, "head")
		move_label.set_anchors_preset(Control.PRESET_FULL_RECT); move_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		move_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; move_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_move_panel.add_child(move_label)
		var knob := Panel.new()
		knob.name = "VectorKnob"
		knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		knob.add_theme_stylebox_override("panel", _hud_style(
			Color(0.24, 0.76, 0.74, 0.38), Color(0.64, 1.0, 0.96, 0.72), 1, 64))
		_move_panel.add_child(knob)
		_dodge_button = Button.new(); _dodge_button.name = "Dodge"; _dodge_button.text = "DODGE"
		_dodge_button.add_theme_font_size_override("font_size", int(PHONE_FONTS["button"]))
		_apply_hud_font(_dodge_button, "head")
		_dodge_button.add_theme_color_override("font_color", Color("f6f1e7"))
		_dodge_button.add_theme_stylebox_override("normal", _hud_style(
			Color(0.04, 0.11, 0.13, 0.84), Color("55e3df"), 2, 48))
		_dodge_button.add_theme_stylebox_override("pressed", _hud_style(
			Color(0.10, 0.28, 0.29, 0.96), Color("d9fffb"), 3, 48))
		_dodge_button.add_theme_stylebox_override("hover", _dodge_button.get_theme_stylebox("normal"))
		_dodge_button.pressed.connect(_try_dodge)
		_hud_root.add_child(_dodge_button)
	# SPACE AND ENTER ACTIVATE A FOCUSED CONTROL IN GODOT. Click EXIT once and it takes focus; from
	# then on every dodge press fires EXIT instead. FOCUS_NONE on all of them is the whole fix, and
	# it is applied at the end of this function to every Button it built.
	_page_button = Button.new(); _page_button.name = "DeckPage"; _page_button.text = "NEXT\nDECK"
	_page_button.add_theme_font_size_override("font_size", int(PHONE_FONTS["button"]) if _low else 13)
	_apply_hud_font(_page_button, "head")
	_page_button.tooltip_text = "Next ability page (E / controller RB); Q or LB goes back"
	_page_button.clip_text = true          # the tag is sized by the layout, never by its text
	_page_button.custom_minimum_size = Vector2.ZERO
	_page_button.add_theme_color_override("font_color", Color("ffe4a0"))
	_page_button.add_theme_stylebox_override("normal", _hud_style(
		Color(0.053, 0.027, 0.091, 0.92), Color("f2b84b"), 1, 0))
	_page_button.add_theme_stylebox_override("hover", _hud_style(
		Color(0.11, 0.043, 0.17, 0.98), Color("ffe4a0"), 2, 0))
	_page_button.add_theme_stylebox_override("pressed", _hud_style(
		Color(0.17, 0.065, 0.25, 1.0), Color("fff0d0"), 2, 0))
	_page_button.pressed.connect(_next_card_page)
	_hud_root.add_child(_page_button)

	_settings_button = Button.new(); _settings_button.name = "TempleSettings"
	_settings_button.text = "GUIDE"
	_settings_button.clip_text = true
	_settings_button.tooltip_text = "Show combat controls"
	_settings_button.add_theme_font_size_override("font_size", int(PHONE_FONTS["button"]) if _low else 14)
	_apply_hud_font(_settings_button, "head")
	_settings_button.add_theme_color_override("font_color", Color("e3cfff"))
	_settings_button.add_theme_stylebox_override("normal", _hud_style(
		Color(0.045, 0.024, 0.081, 0.90), Color("8d54cf"), 1, 0))
	_settings_button.add_theme_stylebox_override("hover", _hud_style(
		Color(0.09, 0.043, 0.14, 0.97), Color("c99aff"), 2, 0))
	_settings_button.add_theme_stylebox_override("pressed", _hud_style(
		Color(0.14, 0.060, 0.21, 1.0), Color("fff0d0"), 2, 0))
	_settings_button.pressed.connect(_toggle_reborn_controls)
	_hud_root.add_child(_settings_button)

	_camera_button = Button.new(); _camera_button.name = "TacticalView"; _camera_button.text = "TACTICAL\nV · WIDE"
	_camera_button.tooltip_text = "Tactical camera (V / controller right stick)"
	_camera_button.add_theme_font_size_override("font_size", int(PHONE_FONTS["button"]) if _low else 15)
	_apply_hud_font(_camera_button, "head")
	_camera_button.add_theme_color_override("font_color", Color("d9fffb"))
	_camera_button.add_theme_stylebox_override("normal", _hud_style(
		Color(0.027, 0.044, 0.083, 0.94), Color("55e3df"), 1, 0))
	_camera_button.add_theme_stylebox_override("hover", _hud_style(
		Color(0.047, 0.092, 0.15, 0.99), Color("a8fffa"), 2, 0))
	_camera_button.add_theme_stylebox_override("pressed", _hud_style(
		Color(0.070, 0.16, 0.22, 1.0), Color("f6f1e7"), 2, 0))
	_camera_button.clip_text = true
	_camera_button.pressed.connect(_toggle_zoom)
	_hud_root.add_child(_camera_button)
	# DEV AFFORDANCE, DEV FLAG. Gating this on roster size put a "TEST CHIKI · R · NEXT" plate in
	# front of any player whose sandbox happened to hold more than one creature.
	if _roster.size() > 1 and OS.get_environment("CHIK_TEMPLE_DEV") == "1":
		_cycle_button = Button.new(); _cycle_button.name = "TestChiki"
		_cycle_button.text = "R"
		_cycle_button.tooltip_text = "Dev \u2014 drive the next chikimon in the party (R)"
		_cycle_button.add_theme_font_size_override("font_size", 28 if _low else 15)
		_cycle_button.add_theme_stylebox_override("normal", _hud_style(
			Color(0.05, 0.08, 0.10, 0.92), Color("f2b84b"), 1, 0))
		_cycle_button.add_theme_stylebox_override("pressed", _hud_style(
			Color(0.18, 0.13, 0.05, 0.96), Color.WHITE, 2, 0))
		_cycle_button.clip_text = true
		_cycle_button.pressed.connect(_cycle_roster)
		_hud_root.add_child(_cycle_button)
	# (the desktop MOVE pad used to be dimmed to 0.34 here; there is no desktop MOVE pad now)

	for b in [_dodge_button, _page_button, _settings_button, _camera_button, _exit_button,
		_cycle_button]:
		if b != null and is_instance_valid(b):
			# These controls own their measured typography. The app-wide IconDirector must not
			# insert an extra card/close icon after layout and consume their 44 CSS-pixel face.
			b.set_meta("preserve_tab_art", true)
			# Clear fills communicate the hit target; extra outlined frames competed with the art.
			for style_name in ["normal", "hover", "pressed"]:
				var button_style := b.get_theme_stylebox(style_name).duplicate() as StyleBoxFlat
				if button_style != null:
					button_style.set_border_width_all(0)
					button_style.set_corner_radius_all(48 if b == _dodge_button else 3)
					b.add_theme_stylebox_override(style_name, button_style)
			b.focus_mode = Control.FOCUS_NONE
			if _low:
				b.mouse_default_cursor_shape = Control.CURSOR_ARROW
				b.add_theme_stylebox_override("hover", b.get_theme_stylebox("normal"))


func _build_controls_overlay() -> void:
	_controls_overlay = PanelContainer.new()
	_controls_overlay.name = "CombatGuide"
	_controls_overlay.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_controls_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls_overlay.visible = false
	_controls_overlay.z_index = 60
	_hud_root.add_child(_controls_overlay)
	_new_hud_accent("controls", _controls_overlay)
	_controls_overlay_label = _hud_label("", 13 if _low else 15, Color("f6f1e7"))
	_controls_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_controls_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_controls_overlay_label.add_theme_color_override("font_outline_color", Color(0.005, 0.02, 0.03, 0.98))
	_controls_overlay_label.add_theme_constant_override("outline_size", 3)
	_apply_hud_font(_controls_overlay_label, "head")
	_controls_overlay.add_child(_controls_overlay_label)


func _toggle_reborn_controls() -> void:
	if _phone_hud_active():
		_mobile_options_t = 0.0 if _mobile_options_t > 0.0 else 5.0
		_sync_mobile_visibility()
		return
	if _controls_overlay == null or not is_instance_valid(_controls_overlay):
		return
	_controls_overlay_token += 1
	if _controls_overlay.visible and _controls_overlay_pinned:
		_controls_overlay.visible = false
		_controls_overlay_pinned = false
		return
	_controls_overlay_pinned = true
	_controls_overlay.visible = true
	_layout_hud()


func _show_reborn_controls(pin: bool = false) -> void:
	if _controls_overlay == null or not is_instance_valid(_controls_overlay):
		return
	_controls_overlay_token += 1
	var token := _controls_overlay_token
	_controls_overlay_pinned = pin
	_controls_overlay.visible = true
	_layout_hud()
	if pin:
		return
	await get_tree().create_timer(4.2).timeout
	if token == _controls_overlay_token and not _controls_overlay_pinned \
		and _controls_overlay != null and is_instance_valid(_controls_overlay):
		_controls_overlay.visible = false


func _size_deck_children(rects: Dictionary, phone: bool, boost: float = 1.0,
		mobile: Dictionary = {}) -> void:
	var unit := 1.0 / float(mobile.get("css_scale", 1.0)) if phone else boost
	var header := 44.0 * unit if phone else 25.0 * boost
	var state_h := 22.0 * unit if phone else 14.0 * boost
	var c0 := rects["card_0"] as Rect2
	var c1 := rects["card_1"] as Rect2
	var frame := _plinth.get_theme_stylebox("panel") as StyleBoxEmpty
	frame.content_margin_left = 0.0 if phone else 14.0 * boost
	frame.content_margin_right = frame.content_margin_left
	frame.content_margin_top = 0.0 if phone else boost
	frame.content_margin_bottom = 0.0
	var stack := _plinth.get_node("CommandDeck") as VBoxContainer
	stack.custom_minimum_size = Vector2.ZERO
	stack.add_theme_constant_override("separation", 0 if phone else roundi(boost))
	var energy := stack.get_node("EnergyCore") as HBoxContainer
	energy.custom_minimum_size = Vector2(0.0, header)
	energy.alignment = BoxContainer.ALIGNMENT_BEGIN if phone else BoxContainer.ALIGNMENT_CENTER
	energy.add_theme_constant_override("separation", roundi((5.0 if phone else 8.0) * unit))
	_energy_icon.custom_minimum_size = Vector2.ONE * (18.0 if phone else 20.0) * unit
	_energy_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_energy_label.custom_minimum_size = Vector2(38.0 if phone else 60.0, 0.0) * unit
	var socket_row := energy.get_node("EnergySockets") as HBoxContainer
	socket_row.add_theme_constant_override("separation", roundi((2.0 if phone else 3.0) * unit))
	for socket in _sockets:
		(socket as Control).custom_minimum_size = (Vector2(5.0, 5.0) if phone else Vector2(15.0, 10.0)) * unit
	var row := stack.get_node("AbilityCardRow") as HBoxContainer
	row.custom_minimum_size = Vector2.ZERO
	row.add_theme_constant_override("separation", roundi(c1.position.x - c0.end.x))
	for card_index in range(_card_hud.size()):
		var ui := _card_hud[card_index] as Dictionary
		var holder := ui["holder"] as VBoxContainer
		holder.custom_minimum_size = Vector2.ZERO
		holder.add_theme_constant_override("separation", 0 if phone else roundi(boost))
		(ui["slot"] as Control).custom_minimum_size = c0.size
		(ui["recovery"] as Control).custom_minimum_size = Vector2(0.0, (2.0 if phone else 3.0) * unit)
		var state := ui["state"] as HBoxContainer
		# The painted card may peek under the right-edge mask, but its external cost/timer
		# must stay fully legible. Reserve one CSS pixel for container raster rounding.
		var footer_w := c0.size.x
		if phone and card_index == _card_hud.size() - 1:
			footer_w -= float(mobile.get("deck_tuck", 0.0)) + unit
		state.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if phone else Control.SIZE_FILL
		state.custom_minimum_size = Vector2(footer_w, state_h)
		state.add_theme_constant_override("separation", roundi((3.0 if phone else 4.0) * unit))
		(ui["cost_icon"] as Control).custom_minimum_size = Vector2.ONE * 12.0 * unit
		var hint := ui["hint"] as Label
		hint.custom_minimum_size = Vector2(0.0, state_h)
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL if phone else Control.SIZE_FILL
		hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if phone else TextServer.OVERRUN_NO_TRIMMING
		if phone:
			hint.add_theme_font_size_override("font_size", int((mobile["font_logical"] as Dictionary)["card_footer"]))
			_apply_hud_font(hint, "body")
		else:
			_apply_hud_font(hint, "head")


func _layout_mobile_hud(layout: Dictionary) -> void:
	var rects := layout["rects"] as Dictionary
	var fonts := layout["font_logical"] as Dictionary
	var unit := 1.0 / float(layout["css_scale"])
	var wave := layout["wave"] as Rect2
	_wave_plate.position = wave.position
	_wave_plate.size = wave.size
	_wave_accent.visible = true
	_wave_label.position = Vector2.ZERO
	_wave_label.size = Vector2(wave.size.x, 23.0 * unit)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_wave_label.add_theme_font_size_override("font_size", int(fonts["wave"]))
	_wave_label.add_theme_constant_override("outline_size", maxi(1, roundi(unit)))
	_pack_dots.position = Vector2(0.0, 24.0 * unit)
	_pack_dots.size = Vector2(wave.size.x * 0.38, 18.0 * unit)
	_remaining_label.position = Vector2(wave.size.x * 0.38, 24.0 * unit)
	_remaining_label.size = Vector2(wave.size.x * 0.62, 18.0 * unit)
	for label in [_pack_dots, _remaining_label]:
		label.add_theme_font_size_override("font_size", int(fonts["remaining"]))
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_apply_hud_font(label, "body")
	_score_plate.visible = false
	_utility_rail.visible = false
	for pair in [[_settings_button, "settings"], [_camera_button, "camera"],
		[_exit_button, "exit"], [_page_button, "page"], [_dodge_button, "dodge"]]:
		var control := pair[0] as Control
		if control == null:
			continue
		var rect := rects[String(pair[1])] as Rect2
		control.visible = String(pair[1]) != "page" or _card_pages() > 1
		control.custom_minimum_size = Vector2.ZERO
		control.position = rect.position
		control.size = rect.size
		control.add_theme_font_size_override("font_size", int(fonts["button"]))
		_apply_hud_font(control, "body")
		for style_name in ["normal", "hover", "pressed"]:
			var style := control.get_theme_stylebox(style_name) as StyleBoxFlat
			if style != null:
				style.content_margin_left = 2.0 * unit
				style.content_margin_right = 2.0 * unit
				style.content_margin_top = 2.0 * unit
				style.content_margin_bottom = 2.0 * unit
	if _cycle_button != null:
		_cycle_button.visible = false
	_exit_button.text = "EXIT"
	_settings_button.text = "···"
	_settings_button.tooltip_text = "Camera and exit options"
	var move_rect := rects["move"] as Rect2
	_move_panel.visible = true
	_move_panel.position = move_rect.position
	_move_panel.size = move_rect.size
	var caption := _move_panel.get_node("MoveCaption") as Label
	caption.set_anchors_preset(Control.PRESET_TOP_LEFT)
	caption.position = Vector2(0.0, move_rect.size.y - 22.0 * unit)
	caption.size = Vector2(move_rect.size.x, 20.0 * unit)
	caption.add_theme_font_size_override("font_size", int(fonts["move"]))
	_apply_hud_font(caption, "body")
	var knob := _move_panel.get_node("VectorKnob") as Control
	knob.size = Vector2.ONE * 30.0 * unit
	_sync_touch_move_knob()
	var plinth := layout["plinth"] as Rect2
	# Keep child coordinates in HUD space while clipping precisely at the phone's safe edge.
	_mobile_deck_clip.position = Vector2.ZERO
	_mobile_deck_clip.size = (layout["deck_clip"] as Rect2).end
	_mobile_deck_clip.clip_contents = true
	_energy_label.add_theme_font_size_override("font_size", int(fonts["energy"]))
	_apply_hud_font(_energy_label, "body")
	_size_deck_children(rects, true, 1.0, layout)
	_plinth.position = plinth.position
	_plinth.size = plinth.size
	for i in range(_card_hud.size()):
		_sync_card_draw_geometry(i)
	# Pressed-card inspection lives on the right, above the hand, never over the movement pad.
	var preview := layout["preview"] as Rect2
	_card_preview.position = preview.position
	_card_preview.size = preview.size
	_card_preview_art.position = Vector2.ZERO
	_card_preview_art.size = preview.size
	_card_preview_name.visible = false
	_card_preview_detail.visible = false
	_target_holder.visible = false
	_vitality.visible = false
	_unit_label.visible = false
	_rarity_label.visible = false
	var toast := layout["message"] as Rect2
	_fighter_plate.position = toast.position
	_fighter_plate.size = toast.size
	_message_label.add_theme_font_size_override("font_size", int(fonts["message"]))
	_message_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_message_label.position = Vector2.ZERO
	_message_label.size = toast.size
	_apply_hud_font(_message_label, "body")
	var guide := layout["guide"] as Rect2
	_controls_overlay.position = guide.position
	_controls_overlay.size = guide.size
	_controls_overlay_label.add_theme_font_size_override("font_size", int(fonts["button"]))
	_controls_overlay_label.text = "LEFT THUMB: MOVE  ·  DODGE: EVADE\nTAP A CARD: CAST  ·  HOLD: INSPECT\nDECK: NEXT HAND  ·  VIEW: CAMERA"
	_controls_overlay_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_hud_font(_controls_overlay_label, "body")
	_controls_overlay_label.position = Vector2(8.0, 4.0) * unit
	_controls_overlay_label.size = guide.size - Vector2(16.0, 8.0) * unit
	_sync_mobile_visibility()
	_tick_mobile_hud_reveal(0.0)


func _sync_mobile_visibility() -> void:
	if not _phone_hud_active() or _camera_button == null:
		return
	var expanded := _mobile_options_t > 0.0
	_camera_button.visible = expanded
	_exit_button.visible = expanded
	_settings_button.text = "×" if expanded else "···"
	mobile_options_visibility_changed.emit(expanded)


func mobile_options_open() -> bool:
	return _phone_hud_active() and _mobile_options_t > 0.0


func _tick_mobile_hud_reveal(delta: float) -> void:
	if not _phone_hud_active() or _move_panel == null:
		return
	_mobile_intro_t = maxf(0.0, _mobile_intro_t - delta)
	if _touch_move_id >= 0:
		_mobile_intro_t = minf(_mobile_intro_t, 0.65)
		if _controls_overlay != null and not _controls_overlay_pinned:
			_controls_overlay.visible = false
	var was_expanded := _mobile_options_t > 0.0
	_mobile_options_t = maxf(0.0, _mobile_options_t - delta)
	if _touch_move_id >= 0 or _touch_inspect_index >= 0:
		_mobile_options_t = 0.0
	if was_expanded != (_mobile_options_t > 0.0):
		_sync_mobile_visibility()
	# Fade the painted ring, not the Control or its hit area. A small thumb dot is the only
	# feedback after onboarding; lifting the finger makes that disappear as well.
	var intro_alpha := clampf(_mobile_intro_t / 0.45, 0.0, 1.0)
	_move_panel.self_modulate.a = intro_alpha
	(_move_panel.get_node("MoveCaption") as CanvasItem).modulate.a = intro_alpha
	(_move_panel.get_node("VectorKnob") as CanvasItem).modulate.a = \
		maxf(intro_alpha, 0.40 if _touch_move_id >= 0 else 0.0)


func _layout_hud() -> void:
	if _hud_root == null:
		return
	var size := get_viewport().get_visible_rect().size
	var phone := _phone_hud_active()
	MobileRender.apply(get_viewport(), MobileViewport.sample(get_viewport()))
	if phone:
		_layout_mobile_hud(_mobile_layout())
		return
	_score_plate.visible = true
	if _mobile_preview_draw_tween != null and _mobile_preview_draw_tween.is_valid():
		_mobile_preview_draw_tween.kill()
	_card_preview.scale = Vector2.ONE
	_mobile_deck_clip.clip_contents = false
	_mobile_deck_clip.position = Vector2.ZERO
	_mobile_deck_clip.size = size
	_camera_button.visible = true
	_exit_button.visible = true
	_settings_button.text = "GUIDE"
	_settings_button.tooltip_text = "Controls"
	_move_panel.self_modulate = Color.WHITE
	_wave_accent.visible = true
	_utility_rail.visible = true
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for restored_label in [_pack_dots, _remaining_label, _energy_label]:
		_apply_hud_font(restored_label, "head")
	for restored_button in [_settings_button, _camera_button, _exit_button, _page_button]:
		_apply_hud_font(restored_button, "head")
		for style_name in ["normal", "hover", "pressed"]:
			var style := restored_button.get_theme_stylebox(style_name) as StyleBoxFlat
			if style != null:
				style.content_margin_left = 8.0
				style.content_margin_right = 8.0
				style.content_margin_top = 5.0
				style.content_margin_bottom = 5.0
	_exit_button.text = "EXIT\nESC"
	var rects := _touch_rects_for(size, false)
	var narrow_boost := _hud_narrow_canvas_boost(size, phone)
	var wave_rect := _wave_rect_for(size, phone, rects)
	var score_rect := _score_rect_for(size, phone)
	var plinth_rect := _plinth_rect(rects, phone, size)
	_size_deck_children(rects, false, narrow_boost)

	# ── top information hierarchy ──
	if _wave_plate != null and is_instance_valid(_wave_plate):
		_wave_plate.position = wave_rect.position
		_wave_plate.size = wave_rect.size
		var title_h := 43.0 if phone else 35.0
		var sub_y := 47.0 if phone else 37.0
		var sub_h := 32.0 if phone else 20.0
		_wave_label.position = Vector2(18.0, 3.0 if phone else 4.0)
		_wave_label.size = Vector2(wave_rect.size.x - 36.0, title_h)
		_wave_label.add_theme_font_size_override("font_size",
			int(PHONE_FONTS["wave"]) - 3 if phone \
			else roundi((18.0 if size.x < 1050.0 else 21.0) * minf(narrow_boost, 1.05)))
		_pack_dots.add_theme_font_size_override("font_size",
			int(PHONE_FONTS["remaining"]) if phone else roundi(13.0 * narrow_boost))
		_remaining_label.add_theme_font_size_override("font_size",
			int(PHONE_FONTS["remaining"]) if phone else roundi(13.0 * narrow_boost))
		_pack_dots.position = Vector2(18.0, sub_y)
		_pack_dots.size = Vector2(wave_rect.size.x * 0.30 - 18.0, sub_h)
		_remaining_label.position = Vector2(wave_rect.size.x * 0.32, sub_y)
		_remaining_label.size = Vector2(wave_rect.size.x * 0.68 - 18.0, sub_h)
	if _score_plate != null and is_instance_valid(_score_plate):
		_score_plate.position = score_rect.position
		_score_plate.size = score_rect.size
		_run_status_label.position = Vector2(15.0, 6.0 if phone else 5.0)
		_run_status_label.size = Vector2(score_rect.size.x - 34.0, 31.0 if phone else 17.0)
		_run_status_label.add_theme_font_size_override("font_size",
			int(PHONE_FONTS["remaining"]) if phone else roundi(11.0 * narrow_boost))
		_score_label.position = Vector2(15.0, 36.0 if phone else 21.0)
		_score_label.size = Vector2(score_rect.size.x - 34.0,
			score_rect.size.y - (42.0 if phone else 26.0))
		_score_label.add_theme_font_size_override("font_size",
			int(PHONE_FONTS["score"]) if phone else roundi(17.0 * narrow_boost))

	# canvas_items/expand shrinks a tall browser canvas to the CSS panel; restore the intended visual
	# type size without changing the already-measured phone profile.
	_exit_button.add_theme_font_size_override("font_size",
		int(PHONE_FONTS["button"]) if phone else roundi(15.0 * narrow_boost))
	_settings_button.add_theme_font_size_override("font_size",
		int(PHONE_FONTS["button"]) if phone else roundi(14.0 * narrow_boost))
	_camera_button.add_theme_font_size_override("font_size",
		int(PHONE_FONTS["button"]) if phone else roundi(15.0 * narrow_boost))
	_page_button.add_theme_font_size_override("font_size",
		int(PHONE_FONTS["button"]) if phone else roundi(13.0 * narrow_boost))
	_sel_card_label.add_theme_font_size_override("font_size",
		int(PHONE_FONTS["card_name"]) if phone else roundi(12.0 * narrow_boost))
	_energy_label.add_theme_font_size_override("font_size",
		int(PHONE_FONTS["energy"]) if phone else roundi(13.0 * narrow_boost))
	_energy_row.add_theme_font_size_override("font_size",
		int(PHONE_FONTS["energy"]) if phone else roundi(10.0 * narrow_boost))
	_target_label.add_theme_font_size_override("font_size",
		int(PHONE_FONTS["target"]) if phone else roundi(10.0 * narrow_boost))
	_message_label.add_theme_font_size_override("font_size",
		int(PHONE_FONTS["message"]) if phone else roundi(18.0 * narrow_boost))
	_card_preview_name.add_theme_font_size_override("font_size",
		int(PHONE_FONTS["card_name"]) if phone else roundi(17.0 * narrow_boost))
	_card_preview_detail.add_theme_font_size_override("font_size",
		int(PHONE_FONTS["card_footer"]) if phone else roundi(12.0 * narrow_boost))
	for ui_value in _card_hud:
		var hint := (ui_value as Dictionary).get("hint") as Label
		if hint != null:
			hint.custom_minimum_size.y = 40.0 if phone else 14.0 * narrow_boost
			hint.add_theme_font_size_override("font_size",
				int(PHONE_FONTS["card_footer"]) if phone else roundi(13.0 * narrow_boost))

	# ── explicit utility actions, top-right ──
	for pair in [[_settings_button, "settings"], [_camera_button, "camera"],
		[_exit_button, "exit"], [_cycle_button, "cycle"]]:
		var btn := pair[0] as Control
		var key := String(pair[1])
		if btn == null or not is_instance_valid(btn):
			continue
		btn.visible = rects.has(key)
		if not btn.visible:
			continue
		var r := rects[key] as Rect2
		btn.position = r.position; btn.size = r.size
	if _utility_rail != null and is_instance_valid(_utility_rail):
		var first := rects["settings"] as Rect2
		var last := rects["exit"] as Rect2
		_utility_rail.position = first.position - Vector2(3.0, 2.0)
		_utility_rail.size = Vector2(last.end.x - first.position.x + 6.0,
			maxf(first.size.y, last.size.y) + 6.0)

	# ── the touch stick and dodge, phone only ──
	if _move_panel != null and is_instance_valid(_move_panel):
		_move_panel.visible = rects.has("move")
		if _move_panel.visible:
			var mr := rects["move"] as Rect2
			_move_panel.position = mr.position; _move_panel.size = mr.size
	if _dodge_button != null and is_instance_valid(_dodge_button):
		_dodge_button.visible = rects.has("dodge")
		if _dodge_button.visible:
			var dr := rects["dodge"] as Rect2
			_dodge_button.position = dr.position; _dodge_button.size = dr.size

	# ── the centred command deck ──
	var page := rects["page"] as Rect2
	_page_button.position = page.position; _page_button.size = page.size
	if _plinth != null and is_instance_valid(_plinth):
		_plinth.position = plinth_rect.position
		_plinth.size = plinth_rect.size
	for i in range(mini(3, _card_hud.size())):
		var slot := (_card_hud[i] as Dictionary).get("slot") as Control
		if slot != null and is_instance_valid(slot):
			slot.custom_minimum_size = (rects["card_%d" % i] as Rect2).size
		_sync_card_draw_geometry(i)

	# Hover/focus opens a true full-card inspection at the lower-left. It always uses the uncropped
	# card texture (even when the phone hand uses icon crops), keeps the authored 2:3 aspect, and is
	# sized from the free gutter so it cannot crowd the enlarged command hand on normal displays.
	if _card_preview != null and is_instance_valid(_card_preview):
		var preview_margin := 14.0 if phone else 22.0
		var inset := 0.0
		var footer_h := 0.0
		var preview_top := wave_rect.end.y + 26.0
		var preview_x := preview_margin
		var preview_floor := size.y - preview_margin
		# On touch layouts, connected-controller focus must not cover the movement pad. Mouse hover
		# does not exist there, so this is the closest usable lower-left anchor.
		if phone and rects.has("move"):
			preview_floor = (rects["move"] as Rect2).position.y - 10.0
		var available_h := maxf(0.0, preview_floor - preview_top)
		var available_w := maxf(0.0, plinth_rect.position.x - preview_margin * 2.0)
		var preview_w := minf(168.0, available_w) if phone \
			else minf(248.0 * narrow_boost, available_w)
		if phone:
			preview_w = minf(preview_w, maxf(0.0, (available_h - footer_h + inset * 3.0) / 1.5))
		# A tiny phone card is worse than no optional controller preview. Zero geometry is deliberate:
		# `_update_card_preview` may make it visible after layout, but it can never cover a control.
		if phone and preview_w < 94.0:
			_card_preview.position = Vector2(preview_x, preview_top)
			_card_preview.size = Vector2.ZERO
			_card_preview_art.size = Vector2.ZERO
			_card_preview_name.size = Vector2.ZERO
			_card_preview_detail.size = Vector2.ZERO
		else:
			var preview_h := minf((preview_w - inset * 2.0) * 1.5 + footer_h,
				available_h if phone else size.y - preview_top - preview_margin)
			var preview_y := maxf(preview_top, preview_floor - preview_h)
			_card_preview.position = Vector2(preview_x, preview_y)
			_card_preview.size = Vector2(preview_w, preview_h)
			var art_w := preview_w - inset * 2.0
			var art_h := minf(art_w * 1.5, preview_h - footer_h)
			_card_preview_art.position = Vector2(inset, inset)
			_card_preview_art.size = Vector2(art_w, art_h)
			_card_preview_name.position = Vector2(inset, inset + art_h + 2.0)
			_card_preview_name.size = Vector2(art_w,
				25.0 if phone else 30.0 * narrow_boost)
			_card_preview_detail.position = Vector2(inset,
				inset + art_h + (25.0 if phone else 32.0 * narrow_boost))
			_card_preview_detail.size = Vector2(art_w,
				20.0 if phone else 24.0 * narrow_boost)

	# Overhead world-space plates are the single source of enemy identity and vitality.
	if _target_holder != null and is_instance_valid(_target_holder):
		_target_holder.visible = false
		_target_holder.position = Vector2.ZERO
		_target_holder.size = Vector2.ZERO

	# The former lower-left vitality/name/rarity cluster is intentionally retired. Health and
	# identity now appear once, on the blue plate above the controlled Chikimon.
	if _vitality != null and is_instance_valid(_vitality):
		_vitality.visible = false
	if _unit_label != null and is_instance_valid(_unit_label):
		_unit_label.visible = false
	if _rarity_label != null and is_instance_valid(_rarity_label):
		_rarity_label.visible = false

	# A compact edge toast confirms actions without becoming a banner over player or enemies.
	if _fighter_plate != null and is_instance_valid(_fighter_plate):
		var message_h := 46.0 if phone else 34.0 * narrow_boost
		var message_w := minf(330.0 if phone else 300.0 * narrow_boost, size.x * 0.25)
		var message_y := maxf(wave_rect.end.y, score_rect.end.y) + 8.0
		_fighter_plate.position = Vector2(wave_rect.position.x, message_y)
		_fighter_plate.size = Vector2(message_w, message_h)
		_message_label.position = Vector2(14.0, 0.0)
		_message_label.size = Vector2(maxf(0.0, message_w - 28.0), message_h)

	if _controls_overlay != null and is_instance_valid(_controls_overlay):
		var utility := rects["settings"] as Rect2
		var guide_w := minf(size.x - 36.0, 360.0 if phone else 390.0 * narrow_boost)
		var guide_h := 92.0 if phone else 74.0 * narrow_boost
		var guide_y := utility.end.y + 8.0
		_controls_overlay.position = Vector2(size.x - (14.0 if phone else 22.0) - guide_w,
			guide_y)
		_controls_overlay.size = Vector2(guide_w, guide_h)
		_controls_overlay_label.position = Vector2(16.0, 6.0)
		_controls_overlay_label.size = Vector2(guide_w - 32.0, guide_h - 12.0)
		_controls_overlay_label.text = ("MOVE WITH LEFT THUMB\nDODGE · TAP AN ABILITY CARD"
			if phone else
			"WASD MOVE  ·  SPACE DODGE  ·  1 / 2 / 3 CAST\nQ / E DECK  ·  V TACTICAL  ·  ESC EXIT")
		_controls_overlay_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_controls_overlay_label.add_theme_font_size_override("font_size",
			int(PHONE_FONTS["remaining"]) if phone else roundi(13.0 * narrow_boost))


func _waves_remaining() -> int:
	if _wave < 0:
		return WAVE_TOTAL
	var current_cleared := _wave_phase in ["clear", "travel", "done"]
	return clampi(WAVE_TOTAL - _wave - (1 if current_cleared else 0), 0, WAVE_TOTAL)


func _travel_direction_cue() -> String:
	# Direction must describe what the player sees, not world X/Y: close and tactical cameras can
	# frame the same corridor differently. Project both endpoints through the live camera so an
	# off-screen sanctum gets a truthful edge cue even while the green beacon cannot be seen.
	if _travel_target == Vector2.ZERO or _cam == null or not is_instance_valid(_cam):
		return "AHEAD"
	var player_world := px2m(_ppos, CAM_AIM_Y)
	var target_world := px2m(_travel_target, CAM_AIM_Y)
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x > 1.0 and not _cam.is_position_behind(player_world) \
			and not _cam.is_position_behind(target_world):
		var player_screen := _cam.unproject_position(player_world)
		var target_screen := _cam.unproject_position(target_world)
		var screen_delta := target_screen - player_screen
		var side_gate := maxf(42.0, viewport_size.x * 0.075)
		if screen_delta.x < -side_gate:
			return "LEFT"
		if screen_delta.x > side_gate:
			return "RIGHT"
		return "AHEAD" if screen_delta.y <= 0.0 else "BEHIND"
	# A target very near the camera's rear plane cannot be projected reliably. Camera-local right
	# still gives a stable left/right instruction; the remaining case is explicitly behind.
	var to_target := (_travel_target - _ppos).normalized()
	var camera_right := Vector2(_cam.global_transform.basis.x.x,
		_cam.global_transform.basis.x.z).normalized()
	var side := to_target.dot(camera_right)
	if side < -0.18:
		return "LEFT"
	if side > 0.18:
		return "RIGHT"
	return "BEHIND"


func _refresh_hud(force_cards: bool) -> void:
	if _hud_root == null or not is_instance_valid(_hud_root):
		return
	_layout_hud()
	var rarity := _rarity()
	_unit_label.text = "%s  ·  L%d" % [Econ.disp(_species()).to_upper(), _level()]
	# the phone plate is 214 px: the rarity WORD fits beside the name, the multipliers do not
	_rarity_label.text = String(rarity["label"])
	_rarity_label.add_theme_color_override("font_color", Color(rarity["color"]))
	_hp_bar.max_value = _max_hp; _hp_bar.value = _hp
	# THE BAR CHANGES COLOUR BEFORE IT CHANGES LENGTH IS USEFUL — a length you have to compare
	# against a remembered length is not a warning. Gold while healthy, amber through the middle,
	# and a hard red under a quarter, so "run" is legible out of the corner of the eye.
	var hp_frac := clampf(_hp / maxf(1.0, _max_hp), 0.0, 1.0)
	var hp_col := Color("d8434f").lerp(Color("e8a33c"), clampf(hp_frac / 0.45, 0.0, 1.0))
	if hp_frac > 0.45:
		hp_col = Color("e8a33c").lerp(Color("e8b34a"), clampf((hp_frac - 0.45) / 0.55, 0.0, 1.0))
	_hp_bar.add_theme_stylebox_override("fill", _hud_style(hp_col, hp_col.lightened(0.35), 1, 2))
	# A NUMBER READ DURING A DODGE IS A DODGE LOST. The bar answers "press or roll" on its own; the
	# digits are only worth reading at the moment they move, so they surface on a change and fade.
	# SHIELD stays whenever it exists — it is a state, not a reading, and it gates whether you can
	# afford to stand still.
	# surface the digits for 1.6 s whenever the value actually moves
	if _hp_shown < 0.0:
		_hp_shown = _hp
	elif absf(_hp - _hp_shown) > 0.01:
		_hp_shown = _hp
		_hp_digits_t = 1.6
	var _hp_txt := ""
	if _hp_digits_t > 0.0:
		_hp_txt = "%.0f / %.0f" % [_hp, _max_hp]
	if _shield > 0.01:
		_hp_txt += ("  " if _hp_txt != "" else "") + "+%.0f SHIELD" % _shield
	_hp_label.text = _hp_txt
	var viewport_size := get_viewport().get_visible_rect().size
	var phone_hud := _phone_hud_active()
	var waves_left := _waves_remaining()
	if _wave_phase == "travel":
		var next_wave := clampi(_wave + 2, 1, WAVE_TOTAL)
		_wave_label.text = "NEXT %d/%d · %s" % [next_wave, WAVE_TOTAL,
			WAVE_TITLES[next_wave - 1]]
		_remaining_label.text = "%s  ·  %.1fm" % [_travel_direction_cue(),
			_ppos.distance_to(_travel_target) * PX2M]
	else:
		var current_wave := clampi(_wave + 1, 1, WAVE_TOTAL)
		_wave_label.text = "%d/%d · %s" % [current_wave, WAVE_TOTAL,
				WAVE_TITLES[current_wave - 1]]
		var _left := _active_foes() + _queued_foes()
		var after_this := maxi(0, WAVE_TOTAL - current_wave)
		var wave_copy := "FINAL" if after_this == 0 else (
			"%d MORE" % after_this if phone_hud else "%d AFTER THIS" % after_this)
		_remaining_label.text = "%s  ·  %d %s" % [wave_copy, _left,
			"FOE" if _left == 1 else "FOES"]
	if phone_hud:
		_wave_label.text = _wave_label.text.replace(" SANCTUM", "").replace("GRIMWICK'S ECLIPSE", "ECLIPSE")
	else:
		# Expanded/narrow desktop panels can be physically smaller than the logical 1600px canvas.
		# Fit the whole destination, never silently ellipsize which chamber is next.
		var title_font := _wave_label.get_theme_font("font")
		var title_size := _wave_label.get_theme_font_size("font_size")
		while title_size > 12 and title_font.get_string_size(_wave_label.text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > _wave_label.size.x:
			title_size -= 1
		_wave_label.add_theme_font_size_override("font_size", title_size)
	_score_label.text = "%06d  ·  x%d" % [_score, _combo]
	if _run_status_label != null and is_instance_valid(_run_status_label):
		var run_phase := String({"prep": "ARMING", "fight": "ENGAGED", "reinforce": "SURGE",
			"clear": "CHAMBER CLEAR", "travel": "IN TRANSIT", "done": "COMPLETE"}.get(
			_wave_phase, "LIVE"))
		_run_status_label.text = ("RUN  ·  " if phone_hud else "PURGE RUN  /  ") + run_phase
	# Energy is triply encoded: the existing essence icon establishes meaning, the numeric fraction is
	# screen-reader/plain-language friendly, and the sockets stay readable at a glance.
	if _energy_label != null and is_instance_valid(_energy_label):
		_energy_label.text = ("%d / %d" % [roundi(_energy), int(ENERGY_MAX)]) if phone_hud \
			else "%.1f / %d" % [_energy, int(ENERGY_MAX)]
	if _energy_row != null and is_instance_valid(_energy_row):
		_energy_row.text = ""
		_energy_row.visible = false
	var whole := int(floor(_energy + 0.001))
	for i in range(_sockets.size()):
		_socket_fill(i, i < whole)
	if whole < _sockets.size() and _energy - float(whole) > 0.05:
		var part := _sockets[whole] as Panel
		if part != null and is_instance_valid(part):
			var frac := clampf(_energy - float(whole), 0.0, 1.0)
			part.add_theme_stylebox_override("panel", _hud_style(
				Color(0.025, 0.10, 0.12, 0.88).lerp(Color("55e3df"), frac),
				Color(0.18, 0.38, 0.40, 0.72).lerp(Color("d9fffb"), frac), 1, 0))
	if _pack_dots != null and is_instance_valid(_pack_dots):
		var total := _wave_pack_count(_wave)
		var done := mini(_pack_at, total)
		# Numerals are present in every bundled HUD font. The former circle glyphs rendered as
		# missing-character boxes in the exported browser build, hiding reinforcement progress.
		_pack_dots.text = ("SURGE %d/%d" if phone_hud else "SURGE %d / %d") % [done, total] \
			if _wave_phase != "travel" else ("ROUTE" if phone_hud else "ROUTE LOCKED")
		if _wave_accent != null and is_instance_valid(_wave_accent):
			_wave_accent.call("set_wave_state", _wave, waves_left, _wave_phase, done, total)
	if _deck_accent != null and is_instance_valid(_deck_accent):
		_deck_accent.call("set_deck_state", posmod(_card_at, 3), _energy / ENERGY_MAX)
	if _fighter_plate != null and is_instance_valid(_fighter_plate):
		_fighter_plate.visible = _message_t > 0.0 and _message_label.text != ""
	_target_bar.value = 0.0; _target_bar.max_value = 1.0; _target_label.text = ""
	_target_holder.visible = false
	_refresh_card_hud(force_cards)
	# A ONE-PAGE DECK HAS NO PAGING. For most fighters this button reported "1 / 1" and did nothing
	# when pressed, while occupying a 118x52 target on a phone. It appears when it has a job.
	var _pages := _card_pages()
	_page_button.visible = _pages > 1
	_page_button.text = "DECK\n%d / %d" % [_card_page + 1, _pages]
	if _dodge_button != null and is_instance_valid(_dodge_button):
		_dodge_button.text = "DODGE" if _dodge_cd <= 0.0 else "DODGE\n%.1fs" % _dodge_cd
	if _camera_button != null and is_instance_valid(_camera_button):
		_camera_button.text = (("CLOSE\nVIEW" if _zoom_tactical else "TACTIC\nWIDE") if phone_hud \
			else ("CLOSE VIEW\nV · RETURN" if _zoom_tactical else "TACTICAL\nV · WIDE"))
		_camera_button.tooltip_text = ("Return to close camera (V / controller right stick)"
			if _zoom_tactical else "See the whole floor (V / controller right stick)")
	if _cycle_button != null and is_instance_valid(_cycle_button):
		_cycle_button.text = "R"


func _refresh_card_hud(force: bool) -> void:
	var stamp := "%s:%d:%d" % [_species(), _card_page, _card_at]
	var indices := _page_indices()
	for visible_index in range(3):
		var ui := _card_hud[visible_index] as Dictionary
		var holder := ui["holder"] as VBoxContainer
		var panel := ui["panel"] as Panel
		var button := ui["button"] as TextureButton
		var art := ui.get("art") as TextureRect
		var hint := ui["hint"] as Label
		if visible_index >= indices.size():
			holder.visible = false
			_animate_card_draw(visible_index, false, true)
			continue
		holder.visible = true
		var global_index := int(indices[visible_index])
		var slot := int(_card_slots[global_index])
		if force or stamp != _hud_cards_stamp:
			var texture := _card_texture(slot)
			button.texture_normal = texture
			if art != null and is_instance_valid(art):
				art.texture = texture
			(ui["name"] as Label).text = _card_name(slot)
		var left := _card_cooldown(slot)
		var card := Econ.CARDS[clampi(slot, 0, Econ.CARDS.size() - 1)] as Dictionary
		var cost := float(card.get("cost", 1))
		(ui["cool"] as Label).text = ""
		var affordable := _energy + 0.001 >= cost
		var ready := left <= 0.01
		var profile := AbilityVisual.profile(_species(), slot)
		var art_pending := AbilitySprites.reborn_card_is_illustrated(profile) \
			and not AbilitySprites.reborn_card_pair_ready(profile)
		# An energy symbol beside seconds or LOAD implies the wrong resource. Mobile shows
		# just that temporary state; the energy icon returns with the ready card's cost.
		(ui["cost_icon"] as Control).visible = not _phone_hud_active() or (not art_pending and ready)
		panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		panel.pivot_offset = Vector2(panel.size.x * 0.5, panel.size.y)
		panel.rotation = 0.0
		# Keep every authored pixel pristine. Only the external cost and recovery rail communicate
		# availability; no mask, selection border, or generated badge covers the card image.
		if not _card_draw_tweens.has(visible_index):
			panel.modulate = Color.WHITE
		button.modulate = Color.WHITE
		var recovery := ui.get("recovery") as ProgressBar
		if recovery != null and is_instance_valid(recovery):
			recovery.modulate.a = 0.0 if ready else 1.0
			var duration := maxf(0.01, _card_personal_cooldown(String(card.get("arch", "strike"))))
			recovery.value = 1.0 if ready else clampf(1.0 - left / duration, 0.0, 1.0)
			var recovery_color := Color("55e3df") if affordable else Color("ff6478")
			recovery.add_theme_stylebox_override("fill", _hud_style(
				recovery_color, recovery_color, 0, 0))
		var pad_button: String = String(["X", "Y", "B"][visible_index])
		if art_pending:
			hint.text = "LOAD" if _phone_hud_active() else "%d  /  LOADING" % int(cost)
			hint.add_theme_color_override("font_color", Color("91a9b2"))
		elif not ready:
			hint.text = "%.1fs" % left if _phone_hud_active() else "%d  /  %.1fs" % [int(cost), left]
			hint.add_theme_color_override("font_color", Color("91a9b2"))
		else:
			hint.text = str(int(cost))
			hint.add_theme_color_override("font_color",
				Color("d9fffb") if affordable else Color("ff8790"))
		button.tooltip_text = "%s — %s, cost %d. Press %d or controller %s." % [
			_card_name(slot), String(card.get("arch", "strike")).capitalize(), int(cost),
			visible_index + 1, pad_button]
		if art_pending:
			button.tooltip_text += " Custom animation is downloading; energy is not spent until ready."
	if _sel_card_label != null and is_instance_valid(_sel_card_label):
		_sel_card_label.text = ""
		_sel_card_label.visible = false
	_update_card_preview()
	_hud_cards_stamp = stamp


func _stable_hud_target() -> Dictionary:
	# Keep the header locked to the last selected or struck foe until that foe is gone or truly out
	# of the arena. Rapid facing changes should move aim, not make the health label flicker.
	var held := _target_by_eid(_hud_target_eid)
	if not held.is_empty() and _target_pos(held).distance_to(_ppos) <= 1080.0:
		return held
	var next := _soft_target(900.0)
	_hud_target_eid = _target_id(next) if not next.is_empty() else -1
	return next


# A PLATE IS NOT A RECT WITH A BORDER. What separates authored UI from programmer UI here is that
# every panel is the same physical object: a near-opaque fill, a one-pixel LIGHT stroke inside it,
# a one-pixel DARK stroke outside it (the shadow, at zero offset), and one corner radius. Identical
# on every plate, or the screen reads as assembled from parts. Gold is reserved for the selected
# card and the score — if gold is on five things, none of them is important.
# ==============================================================================================
# THE TEMPLE'S OWN FRAME — cut basalt, not a rounded rectangle in a purple colourway.
# ==============================================================================================
# The contrast to beat is Chikoria itself: the overworld's UI language is carved WOOD, gold on
# parchment, rounded plaques, wood-gold toasts. A dark-purple version of the same 10 px rounded
# rectangle reads as "dark mode", not as a temple — the identity has to come from the MATERIAL and
# the SILHOUETTE, which is the one lever that also lets the HUD shrink instead of grow.
#
# So: CHAMFERED, not rounded — a corner radius of 2-3 px reads as cut stone where 10 px reads as a
# web card. TORCHLIT, not backlit — the top border is warm gold and the bottom is near-black, so
# every plate looks lit from a point above it rather than filled with flat colour. And the fill is
# basalt at high opacity, because the accessibility rule for a flickering torchlit room is that no
# text may sit on the world.
func _hud_style(bg: Color, edge: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = edge
	style.set_border_width_all(width)
	style.set_corner_radius_all(maxi(0, radius))
	style.shadow_color = Color(0.0, 0.01, 0.018, 0.62)
	style.shadow_size = 3 if radius < 40 else 5
	style.shadow_offset = Vector2(0, 3)
	style.anti_aliasing = true
	style.content_margin_left = 8; style.content_margin_right = 8
	style.content_margin_top = 5; style.content_margin_bottom = 5
	return style


func _new_hud_accent(accent_mode: String, parent: Control) -> Control:
	# Ornament is isolated in a tiny custom-draw Control: it adds no texture uploads and redraws
	# only when its bounds or semantic state changes. If the helper asset is unavailable, every
	# interactive/readable layer still works; the accent is deliberately progressive enhancement.
	var script := load("res://RebornHUDChrome.gd") as Script
	if script == null:
		return null
	var accent := script.new() as Control
	if accent == null:
		return null
	accent.name = "%sAccent" % accent_mode.capitalize()
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(accent)
	accent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	accent.call("setup", accent_mode)
	return accent


func _hud_font(role: String) -> Font:
	if _hud_font_cache.has(role):
		return _hud_font_cache[role] as Font
	var path := "res://font_nunito.ttf"
	match role:
		"display": path = "res://font_titan.ttf"
		"head": path = "res://font_baloo.ttf"
		_: path = "res://font_nunito.ttf"
	var face := load(path) as Font if ResourceLoader.exists(path) else null
	_hud_font_cache[role] = face
	return face


func _apply_hud_font(control: Control, role: String = "body") -> void:
	var face := _hud_font(role)
	if face != null:
		control.add_theme_font_override("font", face)


func _hud_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_apply_hud_font(label, "body")
	return label


func _energy_pips() -> String:
	var out := ""
	for i in range(int(ENERGY_MAX)):
		# The bundled display face lacks WHITE DIAMOND, which rendered as a missing-glyph box when
		# energy was spent. Middle dot already belongs to the HUD's supported glyph set.
		out += "◆" if _energy >= float(i + 1) - 0.01 else "·"
	return out


func _set_message(text: String, seconds: float) -> void:
	_message_t = maxf(_message_t, seconds)
	if _message_label != null and is_instance_valid(_message_label):
		_message_label.text = text


func _toggle_zoom() -> void:
	_zoom_tactical = not _zoom_tactical
	_set_message("TACTICAL VIEW" if _zoom_tactical else "CLOSE VIEW", 0.75)


func _request_exit() -> void:
	exit_requested.emit()


func _play_sfx(stream: AudioStream, pitch: float = 1.0) -> void:
	if _audio_pool.is_empty() or stream == null:
		return
	var player := _audio_pool[_audio_at % _audio_pool.size()]
	_audio_at += 1
	player.stream = stream
	player.pitch_scale = pitch
	player.play()


func _active_foes() -> int:
	var count := 1 if bool(_boss.get("active", false)) else 0
	for value in _enemy_pool:
		if bool((value as Dictionary).get("active", false)):
			count += 1
	return count


func _active_projectiles() -> int:
	var count := 0
	for value in _projectile_pool:
		if bool((value as Dictionary).get("active", false)):
			count += 1
	return count


func _active_effects() -> int:
	var count := 0
	for value in _effect_pool:
		if bool((value as Dictionary).get("active", false)):
			count += 1
	for value in _floater_pool:
		if bool((value as Dictionary).get("active", false)):
			count += 1
	return count
