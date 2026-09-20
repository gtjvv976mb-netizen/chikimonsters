extends Control
class_name RebornHUDChrome
# The Temple's combat instruments are carved stone, not floating web panels. This is intentionally
# code-native chrome: a few cached canvas primitives redraw only when bounds or wave state change.
# Card faces, their inspection, and the energy bar remain completely borderless.

const OBSIDIAN := Color(0.023, 0.018, 0.045, 0.94)
const OBSIDIAN_DEEP := Color(0.010, 0.009, 0.026, 0.97)
const STONE_EDGE := Color(0.31, 0.25, 0.42, 0.90)
const FLAME := Color("b46bfa")
const WATER := Color("55e3df")
const GOLD := Color("f2b84b")
const GOLD_PALE := Color("ffe4a0")

var mode := "deck"
var wave_index := -1
var waves_remaining := 5
var wave_phase := "idle"
var surge_index := 0
var surge_total := 3
var selected_card := 0
var energy_fraction := 1.0


func setup(next_mode: String) -> void:
	mode = next_mode
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	queue_redraw()


func set_wave_state(index: int, remaining: int, phase: String, surge: int, total: int) -> void:
	if wave_index == index and waves_remaining == remaining and wave_phase == phase \
			and surge_index == surge and surge_total == total:
		return
	wave_index = index
	waves_remaining = remaining
	wave_phase = phase
	surge_index = surge
	surge_total = maxi(1, total)
	queue_redraw()


func set_deck_state(card: int, energy: float) -> void:
	var next_energy := clampf(energy, 0.0, 1.0)
	if selected_card == card and is_equal_approx(energy_fraction, next_energy):
		return
	selected_card = clampi(card, 0, 2)
	energy_fraction = next_energy
	queue_redraw()


func _cut_stone(rect: Rect2, cut: float) -> PackedVector2Array:
	var p := rect.position
	var e := rect.end
	var c := minf(cut, minf(rect.size.x, rect.size.y) * 0.22)
	return PackedVector2Array([
		Vector2(p.x + c, p.y), Vector2(e.x - c, p.y),
		Vector2(e.x, p.y + c), Vector2(e.x, e.y - c),
		Vector2(e.x - c, e.y), Vector2(p.x + c, e.y),
		Vector2(p.x, e.y - c), Vector2(p.x, p.y + c),
	])


func _outline(points: PackedVector2Array, color: Color, width: float = 1.0) -> void:
	var closed := PackedVector2Array(points)
	if not points.is_empty():
		closed.append(points[0])
	draw_polyline(closed, color, width, true)


func _stone_plate(rect: Rect2, cut: float, fill: Color = OBSIDIAN) -> void:
	if rect.size.x < 6.0 or rect.size.y < 6.0:
		return
	var shadow := _cut_stone(Rect2(rect.position + Vector2(0.0, 3.0), rect.size), cut)
	draw_colored_polygon(shadow, Color(0.002, 0.002, 0.013, 0.48))
	var shape := _cut_stone(rect, cut)
	draw_colored_polygon(shape, fill)
	_outline(shape, STONE_EDGE, 1.0)
	var inner := _cut_stone(rect.grow(-3.0), maxf(2.0, cut - 2.0))
	_outline(inner, Color(0.54, 0.41, 0.64, 0.19), 1.0)
	# Chipped horizontal strata catch torchlight without putting noise behind type.
	draw_line(Vector2(rect.position.x + cut + 3.0, rect.position.y + 2.0),
		Vector2(rect.end.x - cut - 3.0, rect.position.y + 2.0),
		Color(GOLD.r, GOLD.g, GOLD.b, 0.56), 1.0, true)
	draw_line(Vector2(rect.position.x + cut + 4.0, rect.end.y - 3.0),
		Vector2(rect.end.x - cut - 4.0, rect.end.y - 3.0),
		Color(0.08, 0.04, 0.16, 0.70), 1.0, true)


func _rune(at: Vector2, radius: float, tint: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(0.0, -radius), at + Vector2(radius * 0.70, 0.0),
		at + Vector2(0.0, radius), at + Vector2(-radius * 0.70, 0.0),
	]), tint)
	draw_circle(at, maxf(0.8, radius * 0.19), GOLD_PALE)


func _draw() -> void:
	if size.x < 4.0 or size.y < 4.0:
		return
	match mode:
		"wave": _draw_wave()
		"score": _draw_score()
		"utility": _draw_utility()
		"message": _draw_message()
		"controls": _draw_controls()
		# The actual illustrated cards and enlarged card inspection are the whole surface.
		"deck", "preview": pass


func _draw_wave() -> void:
	var outer := Rect2(1.0, 1.0, size.x - 2.0, size.y - 5.0)
	_stone_plate(outer, 9.0)
	# Purple corruption burns at the entrance; cyan water runs toward the cleansed exit.
	draw_line(Vector2(outer.position.x + 3.0, outer.position.y + 11.0),
		Vector2(outer.position.x + 3.0, outer.end.y - 9.0), FLAME, 2.0, true)
	draw_line(Vector2(outer.end.x - 3.0, outer.position.y + 11.0),
		Vector2(outer.end.x - 3.0, outer.end.y - 9.0), WATER, 2.0, true)
	var segment_y := outer.end.y - 6.0
	var rail_x := outer.position.x + 16.0
	var rail_w := maxf(24.0, outer.size.x - 32.0)
	var gap := clampf(rail_w * 0.018, 2.0, 5.0)
	var segment_w := maxf(2.0, (rail_w - gap * 4.0) / 5.0)
	for i in range(5):
		var segment := Rect2(rail_x + float(i) * (segment_w + gap), segment_y,
			segment_w, 3.0)
		var cleared := i < wave_index or (i == wave_index and wave_phase in ["clear", "travel", "done"])
		var current := i == wave_index and not cleared
		draw_rect(segment, Color(0.16, 0.11, 0.24, 0.88), true)
		if cleared:
			draw_rect(segment, GOLD, true)
		elif current:
			var progress := clampf(float(surge_index) / float(maxi(1, surge_total)), 0.10, 1.0)
			draw_rect(Rect2(segment.position, Vector2(segment.size.x * progress, segment.size.y)),
				FLAME if wave_phase != "travel" else WATER, true)
	# One quiet crest; no oversized title art competes with the wave/location copy.
	_rune(Vector2(size.x * 0.5, 2.0), 3.0, GOLD)


func _draw_score() -> void:
	var outer := Rect2(1.0, 1.0, size.x - 4.0, size.y - 5.0)
	_stone_plate(outer, 8.0, Color(OBSIDIAN_DEEP.r, OBSIDIAN_DEEP.g, OBSIDIAN_DEEP.b, 0.93))
	# Left inset is a violet flame channel; score remains readable on flat dark stone.
	draw_line(Vector2(outer.position.x + 5.0, 12.0),
		Vector2(outer.position.x + 5.0, outer.end.y - 12.0), FLAME, 2.0, true)
	_rune(Vector2(outer.end.x - 13.0, 9.0), 2.6, GOLD)


func _draw_utility() -> void:
	# The buttons provide their own hit-area fills. A rail here would turn three actions into another
	# popup; a fine temple lintel instead gives them shared identity without a backing rectangle.
	draw_line(Vector2(11.0, 1.0), Vector2(size.x - 11.0, 1.0),
		Color(GOLD.r, GOLD.g, GOLD.b, 0.70), 1.0, true)
	_rune(Vector2(6.0, 2.0), 2.0, FLAME)
	_rune(Vector2(size.x - 6.0, 2.0), 2.0, WATER)


func _draw_message() -> void:
	var outer := Rect2(1.0, 1.0, size.x - 5.0, size.y - 5.0)
	_stone_plate(outer, 7.0, Color(0.009, 0.024, 0.042, 0.94))
	draw_line(Vector2(outer.position.x + 6.0, 8.0),
		Vector2(outer.position.x + 6.0, outer.end.y - 7.0), WATER, 2.0, true)


func _draw_controls() -> void:
	_stone_plate(Rect2(1.0, 1.0, size.x - 5.0, size.y - 5.0), 10.0,
		Color(0.008, 0.015, 0.034, 0.97))
