extends Control
class_name TempleRewardWheel
# Circular presentation for an already-settled Wicked Temple reward receipt.
#
# The wheel has ten equal-area wedges: eight FISH and two EGG. It never rolls a reward, changes
# inventory, or invents a near miss. The receipt chooses only which matching category wedge sits
# beneath the fixed pointer; the exact authored reward art is revealed after that truthful landing.

signal landed(category: String)

const FONT_BOLD := preload("res://ui_font_bold.ttf")
const RADIANCE_PATH := "res://astra_fx/victory_radiance.png"
const ORNAMENT_PATH := "res://wicked_reward_wheel_frame.png"
const FALLBACK_ORNAMENT_PATH := "res://reborn_art/treasure_wheel_rim.png"
const CATEGORY_SLOTS := [
	"fish", "fish", "fish", "fish", "egg",
	"fish", "fish", "fish", "fish", "egg",
]
const FISH_SLOT_INDICES := [0, 1, 2, 3, 5, 6, 7, 8]
const EGG_SLOT_INDICES := [4, 9]
const FISH_ART_PATHS := [
	"res://fish_ico_golden_chikifish.png",
	"res://fish_ico_crystal_koi.png",
	"res://fish_ico_mystic_eel.png",
	"res://fish_ico_rainbow_fish.png",
]
const EGG_ART_PATHS := [
	"res://egg_normal.png",
	"res://egg_legendary.png",
	"res://egg_chikimount.png",
	"res://egg_meme.png",
]
const WEDGE_COUNT := 10
const WEDGE_ANGLE := TAU / float(WEDGE_COUNT)
const POINTER_ANGLE := -PI * 0.5
const SPIN_SECONDS := 2.45
const COMPACT_SPIN_SECONDS := 1.72
const BURST_SECONDS := 1.05
const DEEP_SLATE := Color("1b1029")
const IVORY := Color("fff0db")
const CYAN := Color("85dce9")
const VIOLET := Color("c18af0")
const AMBER := Color("f4c775")
const DARK_AMBER := Color("8b5727")

var _data: Dictionary = {}
var _compact := false
var _reduced := false
var _running := false
var _landed := false
var _elapsed := 0.0
var _burst_t := 0.0
var _spin_from := 0.0
var _spin_to := 0.0
var _target_slot := 0
var _art: TextureRect = null
var _radiance: TextureRect = null
var _fish_art: Array[Texture2D] = []
var _egg_art: Array[Texture2D] = []
var _ornament: Texture2D = null


func configure(data: Dictionary, compact: bool = false, reduced_motion: bool = false) -> bool:
	if not bool(data.get("ok", false)):
		return false
	var art_path := String(data.get("art_path", ""))
	if art_path == "" or not ResourceLoader.exists(art_path):
		return false
	_data = data.duplicate(true)
	_compact = compact
	_reduced = reduced_motion
	_running = false
	_landed = false
	_elapsed = 0.0
	_burst_t = 0.0
	_spin_from = 0.0
	custom_minimum_size = Vector2(224.0, 224.0) if _compact else Vector2(310.0, 310.0)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	_load_category_art()
	_ornament = _load_texture(ORNAMENT_PATH)
	if _ornament == null:
		_ornament = _load_texture(FALLBACK_ORNAMENT_PATH)
	_build_reveal_layers(art_path)
	var matches: Array = FISH_SLOT_INDICES if _settled_category() == "fish" else EGG_SLOT_INDICES
	var key_hash := absi(String(_data.get("item_id", _data.get("reward_key", "reward"))).hash())
	_target_slot = int(matches[posmod(key_hash, matches.size())])
	var target_center := (float(_target_slot) + 0.5) * WEDGE_ANGLE
	var desired_rotation := fposmod(POINTER_ANGLE - target_center, TAU)
	var turns := 4 if _compact else 6
	_spin_to = float(turns) * TAU + desired_rotation
	set_process(false)
	queue_redraw()
	return true


func _load_category_art() -> void:
	_fish_art.clear()
	_egg_art.clear()
	for path in FISH_ART_PATHS:
		var texture := _load_texture(String(path))
		if texture != null:
			_fish_art.append(texture)
	for path in EGG_ART_PATHS:
		var texture := _load_texture(String(path))
		if texture != null:
			_egg_art.append(texture)


func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	# Allows source-image tests to run before a fresh optional ornament has an import sidecar.
	if not FileAccess.file_exists(ProjectSettings.globalize_path(path)):
		return null
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


func _build_reveal_layers(art_path: String) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_radiance = null
	var radiance_texture := _load_texture(RADIANCE_PATH)
	if radiance_texture != null:
		_radiance = TextureRect.new()
		_radiance.name = "VictoryRadiance"
		_radiance.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_radiance.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_radiance.texture = radiance_texture
		_radiance.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_radiance.visible = false
		add_child(_radiance)
	_art = TextureRect.new()
	_art.name = "SettledRewardArt"
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.texture = _load_texture(art_path)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.clip_contents = false
	_art.visible = false
	add_child(_art)
	call_deferred("_layout_reveal_layers")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_reveal_layers()


func _layout_reveal_layers() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var center := _wheel_center()
	var radius := _wheel_radius()
	if _radiance != null and is_instance_valid(_radiance):
		var halo_side := radius * 2.22
		_radiance.position = center - Vector2.ONE * halo_side * 0.5
		_radiance.size = Vector2.ONE * halo_side
	if _art != null and is_instance_valid(_art):
		# The receipt art is deliberately larger than the hub but still has a generous safe-fit box.
		var art_side := radius * (1.24 if _compact else 1.30)
		_art.position = center - Vector2.ONE * art_side * 0.5
		_art.size = Vector2.ONE * art_side


func start() -> void:
	if _running or _landed or _data.is_empty():
		return
	if _reduced:
		_finish_landing()
		return
	_running = true
	_elapsed = 0.0
	set_process(true)
	queue_redraw()


func skip() -> void:
	if _running and not _landed:
		_finish_landing()


func _process(delta: float) -> void:
	if _running:
		_elapsed += maxf(0.0, delta)
		if _elapsed >= _spin_duration():
			_finish_landing()
		else:
			queue_redraw()
	elif _landed and _burst_t < BURST_SECONDS:
		_burst_t = minf(BURST_SECONDS, _burst_t + maxf(0.0, delta))
		queue_redraw()
		if _burst_t >= BURST_SECONDS:
			set_process(false)


func _spin_duration() -> float:
	return COMPACT_SPIN_SECONDS if _compact else SPIN_SECONDS


func _spin_progress() -> float:
	var t := clampf(_elapsed / _spin_duration(), 0.0, 1.0)
	# Monotonic ease-out: no bounce toward an item the player did not receive.
	return 1.0 - pow(1.0 - t, 5.0)


func _wheel_rotation() -> float:
	if _landed:
		return _spin_to
	return lerpf(_spin_from, _spin_to, _spin_progress()) if _running else _spin_from


func _finish_landing() -> void:
	if _landed:
		return
	_running = false
	_landed = true
	_elapsed = _spin_duration()
	_burst_t = BURST_SECONDS if _reduced else 0.0
	_show_exact_prize()
	set_process(not _reduced)
	queue_redraw()
	landed.emit(_settled_category())


func _show_exact_prize() -> void:
	_layout_reveal_layers()
	if _radiance != null and is_instance_valid(_radiance):
		_radiance.visible = true
		_radiance.pivot_offset = _radiance.size * 0.5
		_radiance.modulate = Color(0.94, 0.78, 1.0, 0.70 if _reduced else 0.0)
		_radiance.scale = Vector2.ONE if _reduced else Vector2.ONE * 0.78
		if not _reduced:
			var halo_tween := create_tween().set_parallel(true)
			halo_tween.tween_property(_radiance, "modulate", Color(0.94, 0.78, 1.0, 0.70), 0.30)
			halo_tween.tween_property(_radiance, "scale", Vector2.ONE, 0.62) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _art != null and is_instance_valid(_art):
		_art.visible = true
		_art.pivot_offset = _art.size * 0.5
		_art.modulate = Color.WHITE if _reduced else Color(1.0, 1.0, 1.0, 0.0)
		_art.scale = Vector2.ONE if _reduced else Vector2.ONE * 0.70
		if not _reduced:
			var art_tween := create_tween().set_parallel(true)
			art_tween.tween_property(_art, "modulate", Color.WHITE, 0.22)
			art_tween.tween_property(_art, "scale", Vector2.ONE, 0.44) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _settled_category() -> String:
	return "fish" if String(_data.get("reward_type", "")) == "ffish" else "egg"


func _wheel_center() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.52)


func _wheel_radius() -> float:
	return maxf(24.0, minf(size.x, size.y) * 0.425)


func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var center := _wheel_center()
	var radius := _wheel_radius()
	_draw_shadow(center, radius)
	_draw_wheel(center, radius, _wheel_rotation())
	if _landed:
		_draw_landing_burst(center, radius)
	_draw_fixed_pointer(center, radius)


func _draw_shadow(center: Vector2, radius: float) -> void:
	for i in range(5, 0, -1):
		var expand := float(i) * 4.0
		draw_circle(center + Vector2(0.0, 6.0), radius + expand,
			Color(0.0, 0.0, 0.0, 0.025 * float(i)))


func _draw_wheel(center: Vector2, radius: float, rotation: float) -> void:
	draw_set_transform(center, rotation, Vector2.ONE)
	var arc_steps := 5 if _compact else 8
	for index in range(WEDGE_COUNT):
		var category := String(CATEGORY_SLOTS[index])
		var a0 := float(index) * WEDGE_ANGLE
		var a1 := float(index + 1) * WEDGE_ANGLE
		var points := PackedVector2Array([Vector2.ZERO])
		for step in range(arc_steps + 1):
			points.append(Vector2.from_angle(lerpf(a0, a1, float(step) / float(arc_steps))) * radius)
		var base := _wedge_color(index, category)
		draw_colored_polygon(points, base)
		draw_polyline(points, Color(IVORY.r, IVORY.g, IVORY.b, 0.23), 1.0, true)
		var mid := (a0 + a1) * 0.5
		draw_line(Vector2.from_angle(a0) * radius * 0.23,
			Vector2.from_angle(a0) * radius, Color(0.08, 0.03, 0.12, 0.86), 2.0)
		_draw_wedge_art(index, category, mid, radius)
		_draw_wedge_label(category, mid, radius)
	# Metallic nested rim, teeth and registration bolts stay part of the rotating mechanism.
	var tooth_count := 14 if _compact else 20
	for tooth in range(tooth_count):
		var angle := TAU * float(tooth) / float(tooth_count)
		var inner := Vector2.from_angle(angle) * radius * 0.96
		var outer := Vector2.from_angle(angle) * radius * 1.055
		draw_line(inner, outer, AMBER.darkened(0.22), 3.0 if _compact else 4.0)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, Color("11091d"), 8.0)
	draw_arc(Vector2.ZERO, radius * 0.965, 0.0, TAU, 96, AMBER, 2.5)
	draw_arc(Vector2.ZERO, radius * 0.79, 0.0, TAU, 96, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.48), 1.5)
	for bolt in range(WEDGE_COUNT):
		var angle := (float(bolt) + 0.5) * WEDGE_ANGLE
		var p := Vector2.from_angle(angle) * radius * 0.91
		draw_circle(p, radius * 0.025, Color("3c2552"))
		draw_circle(p - Vector2.ONE, radius * 0.010, IVORY)
	# Optional authored ornament can add detail without becoming a runtime dependency.
	if _ornament != null:
		_draw_texture_fit(_ornament, Rect2(Vector2.ONE * -radius * 1.11,
			Vector2.ONE * radius * 2.22), Color(1.0, 1.0, 1.0, 0.88))
	# Dimensional hub and celestial compass.
	for ring in range(4, 0, -1):
		var rr := radius * (0.19 + float(ring) * 0.025)
		draw_circle(Vector2.ZERO, rr, Color(0.09 + ring * 0.013, 0.04 + ring * 0.010,
			0.13 + ring * 0.015, 1.0))
	draw_arc(Vector2.ZERO, radius * 0.285, 0.0, TAU, 64, AMBER, 3.0)
	draw_arc(Vector2.ZERO, radius * 0.245, 0.0, TAU, 64, VIOLET, 1.5)
	for ray in range(8):
		var angle := TAU * float(ray) / 8.0
		draw_line(Vector2.from_angle(angle) * radius * 0.17,
			Vector2.from_angle(angle) * radius * 0.235, AMBER, 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _wedge_color(index: int, category: String) -> Color:
	if category == "egg":
		return Color("9b6232") if index % 2 == 0 else Color("85542d")
	var fish_colors := [Color("4c2868"), Color("3d2256"), Color("603979"), Color("49285f")]
	return fish_colors[index % fish_colors.size()]


func _draw_wedge_art(index: int, category: String, angle: float, radius: float) -> void:
	var center := Vector2.from_angle(angle) * radius * 0.60
	if category == "fish" and not _fish_art.is_empty():
		var fish_order := FISH_SLOT_INDICES.find(index)
		var texture := _fish_art[posmod(fish_order, _fish_art.size())]
		var side := radius * (0.29 if _compact else 0.32)
		_draw_texture_fit(texture, Rect2(center - Vector2.ONE * side * 0.5,
			Vector2.ONE * side), Color.WHITE)
	elif category == "egg" and not _egg_art.is_empty():
		# Two egg wedges carry two authentic egg silhouettes each, showing the whole category pool.
		var group := 0 if index == EGG_SLOT_INDICES[0] else 1
		var side := radius * (0.19 if _compact else 0.22)
		for j in range(2):
			var texture := _egg_art[mini(group * 2 + j, _egg_art.size() - 1)]
			var offset := Vector2((float(j) - 0.5) * side * 0.72, 0.0)
			_draw_texture_fit(texture, Rect2(center + offset - Vector2.ONE * side * 0.5,
				Vector2.ONE * side), Color.WHITE)


func _draw_wedge_label(category: String, angle: float, radius: float) -> void:
	var value := "FISH" if category == "fish" else "EGG"
	var px := 8 if _compact else 10
	var center := Vector2.from_angle(angle) * radius * 0.83
	var extent := FONT_BOLD.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
	draw_string(FONT_BOLD, center + Vector2(-extent.x * 0.5, extent.y * 0.30),
		value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, IVORY)


func _draw_fixed_pointer(center: Vector2, radius: float) -> void:
	var tip := center + Vector2.from_angle(POINTER_ANGLE) * radius * 0.88
	var base := center + Vector2.from_angle(POINTER_ANGLE) * radius * 1.15
	var tangent := Vector2.from_angle(POINTER_ANGLE + PI * 0.5)
	var wing := radius * 0.095
	# Shadow then ivory/amber pointer; it is never transformed with the wheel.
	draw_colored_polygon(PackedVector2Array([
		base + tangent * wing + Vector2(0.0, 4.0),
		base - tangent * wing + Vector2(0.0, 4.0), tip + Vector2(0.0, 4.0),
	]), Color(0.0, 0.0, 0.0, 0.58))
	draw_colored_polygon(PackedVector2Array([
		base + tangent * wing, base - tangent * wing, tip,
	]), IVORY)
	draw_polyline(PackedVector2Array([
		base + tangent * wing, base - tangent * wing, tip, base + tangent * wing,
	]), AMBER, 3.0)
	draw_circle(base, radius * 0.033, DARK_AMBER)
	draw_circle(base - Vector2.ONE, radius * 0.014, IVORY)


func _draw_landing_burst(center: Vector2, radius: float) -> void:
	var t := 1.0 if _reduced else clampf(_burst_t / BURST_SECONDS, 0.0, 1.0)
	var flare := sin(minf(1.0, t * 1.6) * PI * 0.5)
	var ray_count := 10 if _compact else 16
	for index in range(ray_count):
		var angle := TAU * float(index) / float(ray_count) + 0.07
		var inner := radius * 0.28
		var outer := radius * lerpf(0.38, 1.13, flare)
		var color := AMBER if index % 2 == 0 else VIOLET
		color.a = 0.34 * (1.0 - t * 0.58)
		draw_line(center + Vector2.from_angle(angle) * inner,
			center + Vector2.from_angle(angle) * outer, color, 3.0)
	for ring in range(2):
		var ring_color := AMBER if ring == 0 else VIOLET
		ring_color.a = 0.48 * (1.0 - t * 0.62)
		draw_arc(center, radius * lerpf(0.32 + ring * 0.12, 0.74 + ring * 0.18, flare),
			0.0, TAU, 72, ring_color, 2.0)


func _draw_texture_fit(texture: Texture2D, bounds: Rect2, modulate: Color) -> void:
	if texture == null:
		return
	var natural := texture.get_size()
	if natural.x <= 0.0 or natural.y <= 0.0:
		return
	var factor := minf(bounds.size.x / natural.x, bounds.size.y / natural.y)
	var fitted := natural * factor
	draw_texture_rect(texture, Rect2(bounds.get_center() - fitted * 0.5, fitted), false, modulate)


func is_running() -> bool:
	return _running


func has_landed() -> bool:
	return _landed


func settled_category() -> String:
	return _settled_category()


func settled_key() -> String:
	return String(_data.get("reward_key", ""))


func category_slots() -> Array:
	return CATEGORY_SLOTS.duplicate()


func art_control() -> TextureRect:
	return _art


func debug_state() -> Dictionary:
	var fish_wedges := CATEGORY_SLOTS.count("fish")
	var landed_center := (float(_target_slot) + 0.5) * WEDGE_ANGLE + _spin_to
	var pointer_error := absf(wrapf(landed_center - POINTER_ANGLE, -PI, PI))
	return {
		"running": _running,
		"landed": _landed,
		"spin_progress": _spin_progress(),
		"wheel_rotation_radians": _wheel_rotation(),
		"spin_duration_seconds": _spin_duration(),
		"reduced_motion": _reduced,
		"compact": _compact,
		"minimum_size": custom_minimum_size,
		"settled_key": settled_key(),
		"settled_category": _settled_category(),
		"target_wedge": _target_slot,
		"target_wedge_category": String(CATEGORY_SLOTS[_target_slot]),
		"wedge_count": WEDGE_COUNT,
		"equal_wedge_sweep_radians": WEDGE_ANGLE,
		"fish_wedges": fish_wedges,
		"egg_wedges": WEDGE_COUNT - fish_wedges,
		"fish_area_percent": float(fish_wedges) * 100.0 / float(WEDGE_COUNT),
		"egg_area_percent": float(WEDGE_COUNT - fish_wedges) * 100.0 / float(WEDGE_COUNT),
		"pointer_alignment_error_radians": pointer_error if _landed else -1.0,
		"fish_category_art_count": _fish_art.size(),
		"egg_category_art_count": _egg_art.size(),
		"uses_authored_rim": _ornament != null,
		"uses_authored_radiance": _radiance != null,
		"art_path": String(_data.get("art_path", "")),
	}
