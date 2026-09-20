extends Node
# Real Temple intro + global IconDirector. Only in-memory roster/entry/replay spies.
# Launch with CHIK_ALL_ASSETS=1 so the unrelated Backend autoload does no health probe.
const TempleScript := preload("res://Temple.gd")
const Director := preload("res://IconDirector.gd")
const ViewportAdapter := preload("res://TempleMobileViewport.gd")
const Economy := preload("res://Econ.gd")
const SOURCES := ["res://Temple.gd", "res://RebornDeployment.gd", "res://IconDirector.gd",
	"res://TempleMobileViewport.gd", "res://ui_font_bold.ttf", "res://dev_grimwick_popup_layout_qa.gd"]
const CASES := [
	{"key":"desktop1280", "css":Vector2(1280,720), "mobile":false, "safe":Vector4.ZERO},
	{"key":"desktop903", "css":Vector2(903,797), "mobile":false, "safe":Vector4.ZERO},
	{"key":"landscape844", "css":Vector2(844,390), "mobile":true, "safe":Vector4(44,0,44,21)},
	{"key":"landscape568", "css":Vector2(568,320), "mobile":true, "safe":Vector4.ZERO},
	{"key":"portrait390", "css":Vector2(390,844), "mobile":true, "safe":Vector4(0,47,0,34)},
	{"key":"portrait320", "css":Vector2(320,568), "mobile":true, "safe":Vector4.ZERO},
]

class OfflineTemple extends TempleScript:
	var fixture_units: Array = []
	var fixture_offering := true
	var fixture_sandbox := true
	var deploy_calls := 0
	var leave_calls := 0
	var replay_calls := 0
	func _ready() -> void: pass
	func _horde_candidates() -> Array: return fixture_units.duplicate(true)
	func _has_offering() -> bool: return fixture_offering
	func _asset_test_mode() -> bool: return fixture_sandbox
	func _begin() -> void: deploy_calls += 1
	func close() -> void: leave_calls += 1
	func _replay_lore() -> void: replay_calls += 1

var _temple: OfflineTemple
var _director: Node
var _checks := 0
var _fails := 0
var _scale := 1.0
var _safe := Rect2()
var _css := Vector2.ZERO
var _mobile := false
var _case := ""
var _source_hashes := {}
var _fixture_uid := ""

func _ok(value: bool, label: String) -> void:
	_checks += 1
	print(("ok: " if value else "FAIL: ") + _case + " " + label)
	if not value: _fails += 1

func _frames(count: int = 5) -> void:
	for _i in count: await get_tree().process_frame

func _descendants(node: Node, type_name: String) -> Array:
	var out: Array = []
	if node.is_class(type_name): out.append(node)
	for child in node.get_children(): out.append_array(_descendants(child, type_name))
	return out

func _named(value: String) -> Node:
	return _temple._panel.find_child(value, true, false)

func _bounds(control: Control) -> Rect2:
	var bounds := control.get_global_rect()
	return Rect2(bounds.position * _scale, bounds.size * _scale)

func _fixture_roster() -> Array:
	var roster: Array = []
	var species: Array = Economy.CARD_NAMES.keys()
	species.sort()
	for key in species:
		roster.append({"uid":"grimwick-fixture-" + str(key), "species":str(key),
			"name":Economy.disp(str(key)), "level":50})
	for unit in roster:
		if unit["species"] == "ansem":
			unit["name"] = "Ansem Blackbull"
			_fixture_uid = str(unit["uid"])
	# A second long, explicitly Meme Dynasty name tests truncation/wrapping at the last selection.
	var last: Dictionary = roster.back()
	last["species"] = "ansem"
	last["name"] = "Meme Dynasty Ansem Blackbull"
	return roster

func _ready() -> void:
	for path in SOURCES: _source_hashes[path] = FileAccess.get_sha256(path)
	print("GRIMWICK_LAYOUT_SOURCE_BEGIN=" + JSON.stringify(_source_hashes))
	_ok(OS.get_environment("CHIK_ALL_ASSETS") == "1", "offline Backend fixture flag active before startup")
	_director = Director.new()
	add_child(_director)
	await _frames(3)
	var chosen := OS.get_environment("CHIK_QA_CASE")
	for config in CASES:
		if not chosen.is_empty() and chosen != config["key"]: continue
		await _run_case(config)
	_director.queue_free()
	await _frames(4)
	var unchanged := true
	for path in SOURCES: unchanged = unchanged and FileAccess.get_sha256(path) == _source_hashes[path]
	_ok(unchanged, "production and fixture source stayed byte-identical throughout this run")
	print("GRIMWICK_LAYOUT_SOURCE_END=" + JSON.stringify(_source_hashes))
	print("GRIMWICK_POPUP_LAYOUT_QA_DONE checks=%d failures=%d" % [_checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)

func _run_case(config: Dictionary) -> void:
	_case = config["key"]
	_css = config["css"]
	_mobile = config["mobile"]
	var edges: Vector4 = config["safe"]
	OS.set_environment("CHIK_MOBILE_UI", "1" if _mobile else "0")
	OS.set_environment("CHIK_MOBILE_CSS", "%dx%d" % [int(_css.x), int(_css.y)])
	OS.set_environment("CHIK_MOBILE_SAFE", "%s,%s,%s,%s" % [edges.x,edges.y,edges.z,edges.w])
	if DisplayServer.get_name() != "headless": get_window().size = Vector2i(_css)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_window().content_scale_size = Vector2i((_css / (0.585 if _mobile else 0.8)).round())
	ViewportAdapter.invalidate()
	await _frames(5)
	var sample := ViewportAdapter.sample(get_viewport())
	_scale = sample["css_per_logical"]
	_safe = Rect2(edges.x, edges.y, _css.x-edges.x-edges.z, _css.y-edges.y-edges.w)
	print("GRIMWICK_LAYOUT_CASE " + JSON.stringify({"case":_case,"css":str(_css),
		"logical":str(get_viewport().get_visible_rect().size),"actual_window":str(get_window().size),
		"scale":_scale,"safe":str(_safe),"native":DisplayServer.get_name() != "headless"}))
	_temple = OfflineTemple.new()
	add_child(_temple)
	_temple.visible = true
	_temple.set_process(false)
	_temple.fixture_units = _fixture_roster()
	_temple._horde_pick_uid = _fixture_uid
	_ok(_temple.fixture_units.size() == 41, "all41 selectable roster entries are in memory only")
	for state in ["available", "empty", "no_offering", "warning_server", "warning_runs", "long_warning"]:
		_temple.fixture_units = [] if state == "empty" else _fixture_roster()
		_temple.fixture_offering = state != "no_offering"
		_temple.fixture_sandbox = state in ["available", "empty"]
		_temple._srv_on = state not in ["warning_server", "long_warning"]
		_temple._runs_left = 0 if state == "warning_runs" else 3
		_temple._horde_pick_uid = _fixture_uid
		if state == "long_warning":
			_temple._horde_pick_uid = String((_temple.fixture_units.back() as Dictionary)["uid"])
		_temple._phase = "intro"
		_temple._build()
		await _frames(7)
		_check_screen(state)
		if state == "available":
			await _capture(state)
			await _check_interactions()
			_check_screen("last_long_name")
			await _capture("last_long_name")
		elif state == "no_offering":
			await _capture(state)
	_ok(_temple.deploy_calls == 0 and _temple.leave_calls == 0 and _temple._profile == null,
		"no deployment, payment, leave, Profile save, or reward-grant path was called")
	_temple.queue_free()
	await _frames(5)

func _check_screen(state: String) -> void:
	var panel := _bounds(_temple._panel)
	print("GRIMWICK_PANEL " + JSON.stringify({"case":_case,"state":state,"bounds":str(panel),
		"minimum_logical":str(_temple._panel.get_combined_minimum_size())}))
	_ok(_safe.grow(1.0).encloses(panel), state + " complete compact panel is within viewport/notch safe area")
	_ok(panel.size.x <= (480.0 if _mobile else 540.0) + 1.1,
		state + " compact width cap respected")
	var portrait := _named("GrimwickPortrait") as TextureRect
	_ok(portrait != null and portrait.texture != null
		and portrait.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		and portrait.expand_mode == TextureRect.EXPAND_IGNORE_SIZE,
		state + " canonical Grimwick portrait is present and fully aspect-fitted")
	if portrait != null: _ok(panel.grow(0.5).encloses(_bounds(portrait)), state + " portrait rectangle stays inside panel")
	var creature_art := _named("WagerCreatureArt") as TextureRect
	if state != "empty":
		_ok(creature_art != null and creature_art.texture != null
			and creature_art.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			and panel.grow(0.5).encloses(_bounds(creature_art)),
			state + " selected creature artwork is present and full aspect-fit without cropping")
	var enter := _named("WagerEnter") as Button
	var should_disable := state in ["empty", "no_offering"]
	_ok(enter != null and enter.disabled == should_disable, state + " entry enabled/disabled reflects roster/offering")
	var warning := _named("WagerAvailability") as Label
	_ok((warning != null) == (state.begins_with("warning") or state in ["no_offering", "long_warning"]),
		state + " availability warning matches fixture state")
	var controls: Array = _descendants(_temple._panel, "Button")
	for value in controls:
		var button := value as Button
		if not button.is_visible_in_tree(): continue
		var rect := _bounds(button)
		_ok(panel.grow(0.6).encloses(rect) and _safe.grow(1.0).encloses(rect), state + " button reachable " + button.name)
		_ok(not _mobile or (rect.size.x >= 43.9 and rect.size.y >= 43.9),
			state + " minimum44CSS touch target " + button.name + " actual=" + str(rect.size))
		_ok(button.icon == null and button.get_meta("preserve_tab_art", false), state + " real IconDirector preserves measured button " + button.name)
		if button is OptionButton:
			_ok(button.text.begins_with("CHOOSE  /  ") and "·" not in button.text \
				and button.get_theme_font("font").has_char(47),
				state + " authored picker separator is ASCII slash supported by actual bold font")
		if not button is OptionButton:
			var style := button.get_theme_stylebox("normal")
			var available := button.size.x - style.get_content_margin(SIDE_LEFT) - style.get_content_margin(SIDE_RIGHT)
			var text_width := button.get_theme_font("font").get_string_size(button.text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
			_ok(text_width <= available + 1.0, state + " action text fully fits " + button.name)
	var labels := _descendants(_temple._panel, "Label")
	for value in labels:
		var label := value as Label
		if not label.is_visible_in_tree() or label.text.is_empty(): continue
		if label.get_theme_font("font").resource_path == "res://ui_font_bold.ttf" and "/" in label.text:
			_ok("·" not in label.text and label.get_theme_font("font").has_char(47),
				state + " authored bold label separators have actual font glyph coverage: " + label.text)
		var fits := label.size.y + 1.0 >= label.get_minimum_size().y
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
			var text_width := label.get_theme_font("font").get_string_size(label.text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
			fits = fits and text_width <= label.size.x + 1.0
		_ok(fits and panel.grow(0.6).encloses(_bounds(label)), state + " complete unclipped text: " + label.text)
	# Text controls may share a VBox ancestor, but none may geometrically overlap another label.
	var overlap_free := true
	for i in labels.size():
		var first := labels[i] as Label
		if not first.is_visible_in_tree() or first.text.is_empty(): continue
		for j in range(i + 1, labels.size()):
			var second := labels[j] as Label
			if not second.is_visible_in_tree() or second.text.is_empty(): continue
			if _bounds(first).grow(-0.3).intersects(_bounds(second).grow(-0.3)): overlap_free = false
	_ok(overlap_free, state + " title, creature name, element, stats and availability text never overlap")

func _check_interactions() -> void:
	var picker := _named("WagerCreaturePicker") as OptionButton
	_ok(picker != null and picker.item_count == 41, "actual OptionButton contains all41 selectable creatures")
	if picker != null:
		picker.show_popup()
		await _frames(4)
		var popup := picker.get_popup()
		print("GRIMWICK_PICKER_POPUP " + JSON.stringify({"case":_case,"position":str(popup.position),
			"size":str(popup.size),"max_size":str(popup.max_size),
			"visible_rect":str(popup.get_visible_rect()), "embedded":popup.is_embedded(),
			"font_css":popup.get_theme_font_size("font_size") * _scale,
			"vertical_separation_css":popup.get_theme_constant("v_separation") * _scale}))
		_ok(popup.visible and popup.item_count == 41, "real41-item selection popup opens")
		_ok(float(popup.size.y) * _scale <= 220.0 + 1.1,
			"roster popup height stays bounded to220CSS with41 choices")
		var popup_bounds := Rect2(Vector2(popup.position) * _scale, Vector2(popup.size) * _scale)
		_ok(_safe.grow(1.1).encloses(popup_bounds), "complete roster popup stays within the viewport/notch safe area")
		var row_height := popup.get_theme_font("font").get_height(popup.get_theme_font_size("font_size")) \
			+ popup.get_theme_constant("v_separation")
		_ok(not _mobile or row_height * _scale >= 43.9,
			"real PopupMenu font and separation provide44CSS mobile selection rows actual=%.2f" % (row_height * _scale))
		await _capture("picker_open")
		popup.hide()
		var last := picker.item_count - 1
		var uid := String(picker.get_item_metadata(last))
		picker.select(last)
		picker.item_selected.emit(last)
		await _frames(7)
		var rebuilt := _named("WagerCreaturePicker") as OptionButton
		_ok(_temple._horde_pick_uid == uid and rebuilt != null
			and String(rebuilt.get_item_metadata(rebuilt.selected)) == uid,
			"last roster uid survives real picker signal and Temple rebuild")
		var name_label := _named("WagerCreatureName") as Label
		_ok(name_label != null and name_label.text.begins_with("Meme Dynasty"),
			"long Meme Dynasty name renders in the selected creature details")
	var replay := _named("WagerReplay") as Button
	_ok(replay != null and not replay.disabled and replay.focus_mode != Control.FOCUS_NONE,
		"story replay is an accessible enabled focusable action")
	if replay != null:
		replay.pressed.emit()
		_ok(_temple.replay_calls == 1, "actual replay signal reaches only the in-memory spy")

func _capture(state: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await _frames(2)
	RenderingServer.force_draw()
	RenderingServer.force_draw()
	var prefix := OS.get_environment("CHIK_QA_CAPTURE_PREFIX").validate_filename()
	var path := "/private/tmp/wicked_grimwick_popup_%s_%s_%s.png" % [prefix,_case,state]
	_ok(get_viewport().get_texture().get_image().save_png(path) == OK, "native screenshot " + path)
