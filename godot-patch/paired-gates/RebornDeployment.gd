extends VBoxContainer
## Grimwick's compact wager. Selection never performs entry/payment or reward settlement.

signal creature_selected(uid: String)
signal deploy_requested
signal leave_requested
signal lore_requested

const Econ := preload("res://Econ.gd")
const SpeciesTraits := preload("res://ChikimonSpeciesTraits.gd")
const GateButtonArt := preload("res://GateButtonArt.gd")
const INK := Color("fff1dd")
const MUTED := Color("baa8c9")
const VIOLET := Color("d5a1ff")
const GOLD := Color("f2c875")
const BLACK_STONE := Color("140d21")
const RAISED_STONE := Color("241533")
const FONT := preload("res://ui_font.ttf")
const BOLD := preload("res://ui_font_bold.ttf")
const DISPLAY := preload("res://font_titan.ttf")

var _compact := false
var _scale := 1.0

func setup(units: Array, selected_uid: String, sandbox: bool, can_enter: bool,
		offering: int, runs: int, message: String, compact: bool, css_scale: float) -> void:
	name = "GrimwickWager"
	_compact = compact
	_scale = maxf(0.05, css_scale)
	add_theme_constant_override("separation", _px(5 if compact else 9))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", _px(10))
	add_child(top)
	var portrait := _art("res://grimwick_art.png", Vector2(43, 52) if compact else Vector2(54, 65))
	portrait.name = "GrimwickPortrait"
	top.add_child(portrait)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.alignment = BoxContainer.ALIGNMENT_CENTER
	heading.add_theme_constant_override("separation", _px(1))
	top.add_child(heading)
	heading.add_child(_label("GRIMWICK'S WAGER", 10, VIOLET, true))
	var title := _label("WICKED TEMPLE", 17 if compact else 22, INK, true)
	title.add_theme_font_override("font", DISPLAY)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(title)
	if not compact:
		heading.add_child(_label("One companion. Five sanctums.", 11, MUTED))
	var close_button := _button("×", false)
	close_button.name = "WagerClose"
	close_button.custom_minimum_size.x = ceilf(44.0 * _scale) + 1.0 if compact else _px(44)
	close_button.tooltip_text = "Leave the Wicked Temple"
	close_button.pressed.connect(func(): leave_requested.emit())
	top.add_child(close_button)
	var seam := ColorRect.new()
	seam.name = "TempleGoldSeam"
	seam.color = Color("ad7f55")
	seam.custom_minimum_size.y = _px(2)
	seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(seam)

	var selected: Dictionary = {}
	for value in units:
		if value is Dictionary and String(value.get("uid", "")) == selected_uid:
			selected = value
			break
	if selected.is_empty() and not units.is_empty():
		selected = units[0]
	if selected.is_empty():
		var empty := _label("No rested Chikimon. Restore your party before entering.", 12, GOLD)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(empty)
	else:
		_hero(selected)

	if units.size() > 1:
		var picker := OptionButton.new()
		picker.name = "WagerCreaturePicker"
		_style_button(picker, false)
		picker.custom_minimum_size.y = _touch_h()
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.fit_to_longest_item = false
		picker.clip_text = true
		picker.add_theme_constant_override("arrow_margin", _px(9))
		picker.tooltip_text = "Choose the one Chikimon who enters"
		var chosen := 0
		for i in units.size():
			var unit := units[i] as Dictionary
			picker.add_item(String(unit.get("display_name", Econ.disp(String(unit.get("species", ""))))))
			picker.set_item_metadata(i, String(unit.get("uid", "")))
			if String(unit.get("uid", "")) == String(selected.get("uid", "")):
				chosen = i
		picker.select(chosen)
		picker.text = "CHOOSE  /  " + picker.get_item_text(chosen)
		picker.item_selected.connect(func(index: int):
			creature_selected.emit(String(picker.get_item_metadata(index))))
		var popup := picker.get_popup()
		# PopupMenu's content minimum otherwise expands to all 41 rows and defeats max_size.
		# OptionButton clears min_size immediately before about_to_popup, so set it there.
		popup.wrap_controls = false
		popup.about_to_popup.connect(func():
			var row_h := maxi(_px(44 if compact else 30),
				ceili(BOLD.get_height(_px(12))) + popup.get_theme_constant("v_separation"))
			var list_h := mini(_px(220), row_h * units.size() + _px(12))
			popup.min_size = Vector2i(roundi(picker.size.x), list_h)
			popup.max_size = Vector2i(roundi(picker.size.x), list_h))
		popup.visibility_changed.connect(func():
			if popup.visible and popup.is_embedded():
				var display := preload("res://TempleMobileViewport.gd").sample(get_viewport())
				var css := display["css_size"] as Vector2
				var edges := display["safe_insets"] as Vector4
				var lower := Vector2(edges.x + 8.0, edges.y + 8.0) * _scale
				var upper := Vector2(css.x - edges.z - 8.0, css.y - edges.w - 8.0) * _scale
				popup.position = Vector2i(Vector2(popup.position).clamp(lower,
					(upper - Vector2(popup.size)).max(lower)).floor()))
		popup.add_theme_font_override("font", BOLD)
		popup.add_theme_font_size_override("font_size", _px(12))
		popup.add_theme_color_override("font_color", INK)
		popup.add_theme_stylebox_override("panel", _plate(Color("1d1427"), Color("65503c"), 6))
		popup.add_theme_stylebox_override("hover", _plate(Color("48305d"), VIOLET, 4))
		popup.add_theme_constant_override("v_separation", maxi(_px(12),
			ceili(44.0 * _scale) + 1 - floori(BOLD.get_height(_px(12)))) if compact else _px(12))
		add_child(picker)

	var entry := "FREE PRACTICE" if sandbox else "%d DARK ENERGY" % offering
	var availability := "NO REWARDS SAVED" if sandbox else ("%d RUNS LEFT" % runs if runs >= 0 else "CHECKING RUNS")
	var facts := _label("%s   /   %s" % [entry, availability], 10, GOLD, true)
	facts.name = "WagerEntryFacts"
	facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(facts)
	var odds := _label("VICTORY LOOT   ·   Fish 80% / Eggs 20%", 10, MUTED)
	odds.name = "WagerRewardOdds"
	odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	odds.tooltip_text = "Eggs: Normal 13.34%, Legendary 3.33%, Chikimount 2.22%, Meme Dynasty 1.11% overall. Fantasy fish rarity weights: 12:6:3:1."
	add_child(odds)
	if message != "":
		var warning := _label(message, 11, GOLD)
		warning.name = "WagerAvailability"
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(warning)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", _px(7))
	add_child(actions)
	var lore := _button("GRIMWICK", false)
	lore.name = "WagerReplay"
	lore.custom_minimum_size.x = _px(116)
	lore.tooltip_text = "Hear Grimwick's story again"
	lore.pressed.connect(func(): lore_requested.emit())
	actions.add_child(lore)
	var narrow_phone := _compact and get_viewport().get_visible_rect().size.x / _scale <= 350.0
	var go := _button("ENTER TEMPLE" if narrow_phone else "ENTER THE TEMPLE", true)
	go.name = "WagerEnter"
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.disabled = not can_enter or units.is_empty()
	go.pressed.connect(func(): deploy_requested.emit())
	actions.add_child(go)

func _hero(unit: Dictionary) -> void:
	var species := String(unit.get("species", ""))
	var kind := Econ.unit_kind(species)
	var tone := GOLD if kind == "legendary" else (Color("e6a9d8") if kind == "meme" else VIOLET)
	var panel := PanelContainer.new()
	panel.name = "WagerChosenChikimon"
	var hero_plate := _plate(RAISED_STONE, Color("745283"), 7 if _compact else 9)
	hero_plate.border_width_left = _px(3)
	panel.add_theme_stylebox_override("panel", hero_plate)
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _px(10))
	panel.add_child(row)
	var art := _art("res://dex_%s.png" % species, Vector2(58, 62) if _compact else Vector2(78, 80))
	art.name = "WagerCreatureArt"
	row.add_child(art)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", _px(2))
	row.add_child(text)
	var name_label := _label(String(unit.get("display_name", Econ.disp(species))), 17 if _compact else 20, INK, true)
	name_label.name = "WagerCreatureName"
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(name_label)
	var details := _label("%s  /  LV %d" % [Econ.el_of(species).to_upper(), int(unit.get("level", 1))], 10, tone, true)
	text.add_child(details)
	var multiplier := 1.15 if kind == "legendary" else (1.25 if kind == "meme" else 1.0)
	var stats := _label("%s  ·  HP / POWER ×%.2f" % [
		"MEME DYNASTY" if kind == "meme" else kind.to_upper(), multiplier], 10, MUTED)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(stats)
	var species_profile := SpeciesTraits.profile(species)
	var signature := _label("%s  ·  %s" % [String(species_profile["name"]).to_upper(),
		SpeciesTraits.signature_description(species)], 10, VIOLET, true)
	signature.name = "WagerSpeciesTrait"
	signature.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	signature.mouse_filter = Control.MOUSE_FILTER_PASS
	signature.tooltip_text = "Stride %.0f%% · Focus %.0f%% · Ward %.0f%% · Reach %.0f%%\n%s" % [
		float(species_profile["stride"]) * 100.0, float(species_profile["focus"]) * 100.0,
		float(species_profile["ward"]) * 100.0, float(species_profile["reach"]) * 100.0,
		SpeciesTraits.signature_description(species)]
	text.add_child(signature)

func _art(path: String, dimensions: Vector2) -> TextureRect:
	var art := TextureRect.new()
	art.custom_minimum_size = dimensions * _scale
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(path):
		art.texture = load(path)
	return art

func _px(value: float) -> int:
	return maxi(1, roundi(value * _scale))

func _touch_h() -> float:
	return ceilf(44.0 * _scale) + 1.0 if _compact else _px(38)

func _label(value: String, px: int, color: Color, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", BOLD if bold else FONT)
	label.add_theme_font_size_override("font_size", _px(px))
	label.add_theme_color_override("font_color", color)
	return label

func _plate(fill: Color, edge: Color, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(_px(7))
	style.set_content_margin_all(_px(padding))
	return style

func _style_button(button: Button, primary: bool) -> void:
	# Prevent the global icon decorator from enlarging these deliberately compact authored actions.
	button.set_meta("preserve_tab_art", true)
	button.add_theme_font_override("font", BOLD)
	var narrow_phone := _compact and get_viewport().get_visible_rect().size.x / _scale <= 350.0
	button.add_theme_font_size_override("font_size", _px(10 if primary and narrow_phone else 11))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, BLACK_STONE if primary else INK)
	button.add_theme_color_override("font_disabled_color", MUTED)
	var normal := _plate(GOLD if primary else RAISED_STONE,
		Color("ffe5aa") if primary else Color("644b77"), 8)
	normal.border_width_bottom = _px(3)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", _plate(Color("ffe09a") if primary else Color("39244a"),
		Color("fff0c7") if primary else VIOLET, 8))
	button.add_theme_stylebox_override("pressed", _plate(Color("d5a950") if primary else BLACK_STONE,
		GOLD, 8))
	button.add_theme_stylebox_override("disabled", _plate(Color("372e40"), Color("584966"), 8))
	var focus := _plate(Color.TRANSPARENT, GOLD, 0)
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
	# The square close control keeps its compact stone treatment; the horizontal
	# Higgsfield plate is reserved for picker and action buttons.
	if button.text != "×":
		GateButtonArt.apply(button, "wicked", primary)

func _button(value: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(_px(82), _touch_h())
	_style_button(button, primary)
	return button
