extends Node
## Offline real-Player E -> real Temple -> real entry/replay regression.
## Launch with CHIK_ALL_ASSETS=1 BEFORE Godot starts: Backend autoload then performs no probe.
## Only world startup is replaced; Player's input/action/key-ownership methods are inherited.
## The profile is an in-memory Node, not Profile.gd. Its save/spend spies never persist anything.
const TempleScript := preload("res://Temple.gd")
const PlayerScript := preload("res://Player.gd")
const EntryScript := preload("res://RebornDeployment.gd")
const MobileViewport := preload("res://TempleMobileViewport.gd")
const Director := preload("res://IconDirector.gd")
const ORIGINAL_LORE := [
	{"say": "Ah. A trainer, and a small warm creature at your heel.", "beat": "THE WICKED TEMPLE"},
	{"say": "Come in. The stone remembers warmth. It has been a long time since it had any.", "beat": "THE WICKED TEMPLE"},
	{"say": "This was a sanctum once. Five seals, five elements, and a quiet order of keepers who fed them.", "beat": "WHAT IT WAS"},
	{"say": "I fed them something else.", "beat": "WHAT IT WAS"},
	{"say": "Corruption is not a curse I cast. It is a QUESTION I asked, and the seals answered.", "beat": "THE CORRUPTIMONS"},
	{"say": "Look at what came back through them. They were somebody's companions, once.", "beat": "THE CORRUPTIMONS"},
	{"say": "Now they are mine, and they do not remember being anything.", "beat": "THE CORRUPTIMONS"},
	{"say": "I want to know what a bond is worth. So: one of yours. Not three, not a party hiding behind each other — ONE.", "beat": "THE WAGER"},
	{"say": "Walk it through my five sanctums and let me watch how long affection lasts against arithmetic.", "beat": "THE WAGER"},
	{"say": "Break all five and I will pay you for the lesson. I always pay.", "beat": "THE WAGER"},
]

class MemoryProfile extends Node:
	var demo := true
	var asset_sandbox := false
	var saves := 0
	var spends := 0
	var d := {
		"temple_lore_seen": true,
		"mats": {"essence": 30},
		"party": ["qa-firix", "qa-dragonos"],
		"units": {
			"qa-firix": {"uid": "qa-firix", "species": "firix", "level": 50},
			"qa-dragonos": {"uid": "qa-dragonos", "species": "dragonos", "level": 50}
		}
	}
	func _ready() -> void: add_to_group("profile")
	func save_now() -> void: saves += 1
	func spend_mats(_mats: Dictionary, _why: String) -> void: spends += 1
	func party_units() -> Array:
		var out: Array = []
		for uid in d["party"]: out.append(d["units"][uid])
		return out
	func unit_ok_to_fight(_uid: String) -> String: return ""
	func unit_name(unit: Dictionary) -> String: return String(unit["species"]).capitalize()

class InputOnlyPlayer extends PlayerScript:
	func _ready() -> void:
		add_to_group("player")
		set_process(false)
		set_physics_process(false)
		set_process_unhandled_input(true)

class TouchSpy extends Node:
	var suspended := false
	var calls: Array[bool] = []
	func _ready() -> void: add_to_group("touchui")
	func set_suspended(value: bool) -> void:
		suspended = value
		calls.append(value)

var _profile: MemoryProfile
var _player: InputOnlyPlayer
var _touch: TouchSpy
var _temple: TempleScript
var _checks := 0
var _fails := 0
var _hashes := {}

func _ok(value: bool, label: String) -> void:
	_checks += 1
	print(("ok: " if value else "FAIL: ") + label)
	if not value: _fails += 1

func _frames(n: int = 3) -> void:
	for _i in n: await get_tree().process_frame

func _button(node: Node, label: String) -> Button:
	if node is Button and (node as Button).text.strip_edges() == label: return node as Button
	for child in node.get_children():
		var found := _button(child, label)
		if found != null: return found
	return null

func _entry(node: Node) -> EntryScript:
	if node is EntryScript: return node as EntryScript
	for child in node.get_children():
		var found := _entry(child)
		if found != null: return found
	return null

func _requests(node: Node) -> int:
	var count := 1 if node is HTTPRequest else 0
	for child in node.get_children(): count += _requests(child)
	return count

func _all(node: Node, type_name: String) -> Array:
	var out: Array = []
	if node.is_class(type_name): out.append(node)
	for child in node.get_children(): out.append_array(_all(child, type_name))
	return out

func _css_rect(control: Control, scale: float) -> Rect2:
	var rect := control.get_global_rect()
	return Rect2(rect.position * scale, rect.size * scale)

func _display(css: Vector2i, scale: float, safe: String, mobile: bool) -> void:
	OS.set_environment("CHIK_MOBILE_UI", "1" if mobile else "0")
	OS.set_environment("CHIK_MOBILE_CSS", "%dx%d" % [css.x, css.y])
	OS.set_environment("CHIK_MOBILE_SAFE", safe)
	if DisplayServer.get_name() != "headless": get_window().size = css
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().content_scale_size = Vector2i((Vector2(css) / scale).round())
	MobileViewport.invalidate(get_viewport())
	await _frames(6)

func _check_lore_layout(context: String) -> void:
	var display := MobileViewport.sample(get_viewport())
	var scale := float(display["css_per_logical"])
	var css: Vector2 = display["css_size"]
	var edge: Vector4 = display["safe_insets"]
	var safe := Rect2(edge.x, edge.y, css.x - edge.x - edge.z, css.y - edge.y - edge.w)
	var mobile := bool(display["touch"])
	var speaker := _temple._strip_root.find_child("GrimwickStorySpeaker", true, false) as Label
	_ok(speaker != null and speaker.text.begins_with("GRIMWICK  /  ") and "·" not in speaker.text \
		and speaker.get_theme_font("font").has_char(47),
		context + ": authored bold story separators use supported ASCII slash glyphs")
	var narration: Label = null
	for candidate in _all(_temple._strip_root, "Label"):
		if (candidate as Label).text == String(ORIGINAL_LORE[_temple._lore_page]["say"]):
			narration = candidate as Label
			break
	_ok(narration != null and narration.is_visible_in_tree(), context + ": current full original narration is visible")
	if narration == null: return
	var story := _css_rect(narration, scale)
	var font: Font = narration.get_theme_font("font")
	var font_size := narration.get_theme_font_size("font_size")
	var measured := font.get_multiline_string_size(narration.text, narration.horizontal_alignment,
		narration.size.x, font_size)
	_ok(safe.grow(0.8).encloses(story), context + ": narration is inside the safe area")
	_ok(narration.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING,
		context + ": story never ellipsizes the original text")
	_ok(measured.y <= narration.size.y + 1.0 and narration.get_visible_line_count() >= narration.get_line_count(),
		context + ": measured wrapped story height fits all lines (%.1f <= %.1f logical)" % [measured.y, narration.size.y])
	_ok(float(font_size) * scale >= 13.5, context + ": narration typography remains at least 13.5CSS pixels")
	var last := _temple._lore_page == ORIGINAL_LORE.size() - 1
	var buttons: Array[Button] = [
		_button(_temple._strip_root, "I accept the wager" if last else "Hear him out"),
		_button(_temple._strip_root, "Not today" if last else "Skip")]
	for button in buttons:
		_ok(button != null and button.is_visible_in_tree(), context + ": both story choices remain visible")
		if button == null: continue
		var box := _css_rect(button, scale)
		_ok(button.icon == null and button.get_meta("preserve_tab_art", false),
			context + ": real global IconDirector preserves measured story action: " + button.text)
		_ok(safe.grow(0.8).encloses(box), context + ": choice stays inside safe area: " + button.text)
		_ok(not mobile or (box.size.x >= 43.9 and box.size.y >= 43.9),
			context + ": mobile choice has a full 44CSS target: " + button.text)
		_ok(not box.intersects(story), context + ": choice does not obstruct narration: " + button.text)
		var style: StyleBox = button.get_theme_stylebox("normal")
		var available := button.size - style.get_minimum_size()
		var button_font: Font = button.get_theme_font("font")
		var button_fs := button.get_theme_font_size("font_size")
		var text_size := button_font.get_multiline_string_size(button.text, HORIZONTAL_ALIGNMENT_CENTER,
			available.x if button.autowrap_mode != TextServer.AUTOWRAP_OFF else -1.0, button_fs)
		_ok(text_size.x <= available.x + 1.0 and text_size.y <= available.y + 1.0,
			context + ": actual choice text fits inside style margins: " + button.text)
	if buttons[0] != null and buttons[1] != null:
		_ok(not _css_rect(buttons[0], scale).intersects(_css_rect(buttons[1], scale)),
			context + ": story choice hit rectangles do not overlap")
	var portrait: TextureRect = null
	for candidate in _all(_temple._strip_root, "TextureRect"):
		var rect := candidate as TextureRect
		if rect.texture != null and rect.texture.resource_path == "res://grimwick_art.png":
			portrait = rect
			break
	_ok(portrait != null and portrait.is_visible_in_tree(), context + ": original Grimwick image is retained")
	if portrait != null:
		_ok(portrait.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED \
			and portrait.expand_mode == TextureRect.EXPAND_IGNORE_SIZE,
			context + ": complete original portrait uses aspect-preserving fit, never crop")
		_ok(safe.grow(0.8).encloses(_css_rect(portrait, scale)), context + ": full portrait stays within safe area")
	print("GRIMWICK_LORE_GEOMETRY context=%s css=%s logical=%s narration=%s font_css=%.2f lines=%d" % [
		context, css, get_viewport().get_visible_rect().size, story, float(font_size) * scale, narration.get_line_count()])

func _lore_layout_matrix() -> void:
	_temple.open()
	_temple._horde_pick_uid = "qa-dragonos"
	var cases := [
		[Vector2i(844,390),0.585,"44,0,44,21",true],
		[Vector2i(667,375),0.5,"0,0,0,0",true],
		[Vector2i(390,844),0.33,"0,47,0,34",true],
		[Vector2i(360,640),0.4,"0,0,0,0",true],
		[Vector2i(568,320),0.5,"0,0,0,0",true],
		[Vector2i(320,568),0.3,"0,0,0,0",true],
		[Vector2i(1024,768),0.8,"0,0,0,0",true],
		[Vector2i(1280,720),1.0,"0,0,0,0",false]]
	for fixture in cases:
		await _display(fixture[0], fixture[1], fixture[2], fixture[3])
		for page in range(ORIGINAL_LORE.size()):
			_temple._lore_page = page
			_temple._build()
			await _frames(2)
			_check_lore_layout("%dx%d_page%d" % [fixture[0].x, fixture[0].y, page])
			if page in [0,7,9] and fixture[0] in [Vector2i(1280,720),Vector2i(844,390),Vector2i(390,844)]:
				await _capture_lore("%dx%d_page%d" % [fixture[0].x, fixture[0].y, page])
	# A real resize event, without manual _build, must reflow the live current page.
	await _display(Vector2i(844,390),0.585,"44,0,44,21",true)
	_temple._lore_page = 7
	_temple._build()
	await _frames()
	await _display(Vector2i(390,844),0.33,"0,47,0,34",true)
	_ok(_temple._lore_page == 7 and _temple._phase == "lore" and _temple._horde_pick_uid == "qa-dragonos",
		"live landscape->portrait resize preserves lore page and selected uid")
	_check_lore_layout("live_rotated_page7")
	_assert_owned("live lore rotation")
	_temple.close()
	_assert_released("close after layout matrix")

func _capture_lore(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await _frames(2)
	RenderingServer.force_draw()
	RenderingServer.force_draw()
	var prefix := OS.get_environment("CHIK_QA_CAPTURE_PREFIX").validate_filename()
	var path := "/private/tmp/wicked_grimwick_lore_%s_%s.png" % [prefix,label]
	_ok(get_viewport().get_texture().get_image().save_png(path) == OK, "native screenshot " + path)

func _key(code: Key, echo: bool = false) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.pressed = true
	down.echo = echo
	get_viewport().push_input(down, true)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	get_viewport().push_input(up, true)

func _press(label: String) -> bool:
	var button := _button(_temple, label)
	_ok(button != null and button.is_visible_in_tree() and not button.disabled,
		"actual visible button exists: " + label)
	if button == null: return false
	button.pressed.emit()
	await _frames()
	return true

func _assert_owned(context: String) -> void:
	_ok(_temple.is_open() and _player.keys_taken(), context + ": Temple owns movement keys")
	_ok(_touch.suspended, context + ": world touch controls are suspended")
	_ok(_temple._world == null and _profile.spends == 0, context + ": no run or payment was started")

func _assert_released(context: String) -> void:
	_ok(not _temple.is_open() and not _player.keys_taken(), context + ": movement keys released")
	_ok(not _touch.suspended, context + ": world touch controls resumed")

func _ready() -> void:
	# Backend initializes before this scene: the shell must opt out before startup, not here.
	if OS.get_environment("CHIK_ALL_ASSETS") != "1":
		push_error("This offline fixture REQUIRES CHIK_ALL_ASSETS=1 before engine launch")
		get_tree().quit(2)
		return
	OS.set_environment("CHIK_MOBILE_UI", "0")
	OS.set_environment("CHIK_MOBILE_CSS", "1280x720")
	OS.set_environment("CHIK_MOBILE_SAFE", "0,0,0,0")
	get_window().content_scale_size = Vector2i(1280, 720)
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	for path in ["res://Temple.gd", "res://RebornDeployment.gd", "res://Player.gd",
			"res://Backend.gd", "res://IconDirector.gd", "res://TempleMobileViewport.gd", "res://grimwick_art.png", "res://ui_font_bold.ttf",
			"res://dev_temple_grimwick_entry_qa.gd", "res://dev_temple_grimwick_entry_qa.tscn"]:
		_hashes[path] = FileAccess.get_sha256(path)
	print("GRIMWICK_ENTRY_SOURCE_BEGIN=" + JSON.stringify(_hashes))
	add_child(Director.new())
	_profile = MemoryProfile.new()
	add_child(_profile)
	_touch = TouchSpy.new()
	add_child(_touch)
	_player = InputOnlyPlayer.new()
	add_child(_player)
	_player.global_position = Vector3(-303, 0, 276)
	_temple = TempleScript.new()
	add_child(_temple)
	await _frames()
	var unchanged_profile := _profile.d.duplicate(true)
	_ok(get_tree().get_nodes_in_group("net").is_empty(), "no Net instance exists")
	_ok(_requests(get_tree().root) == 0, "offline Backend and fixture create zero HTTP requests")
	_ok(not _temple.is_open() and not _player.keys_taken(), "initially closed and player owns movement")
	_ok(_temple.LORE.size() == 10, "all ten original Grimwick story pages remain")
	for page in range(ORIGINAL_LORE.size()):
		_ok(page < _temple.LORE.size() and _temple.LORE[page] == ORIGINAL_LORE[page],
			"original narration and beat title remain exact at page %d" % page)
	_player._move_target = Vector3(-300, 0, 276)
	_player._move_stuck_t = 1.0
	_player._mouse_run = true
	_player._lmb_down = true
	_player._lmb_held = 1.0
	_player._click_act = true
	_key(KEY_E)
	await _frames()
	_ok(_temple._phase == "lore" and _temple._lore_page == 0,
		"real E at the Temple starts page zero despite the existing seen flag")
	_assert_owned("first E")
	_ok(_player._move_target == null and _player._move_stuck_t == 0.0 and not _player._mouse_run \
		and not _player._lmb_down and _player._lmb_held == 0.0 and not _player._click_act,
		"real key handoff cancels stale click navigation and held movement")
	_ok(_profile.saves == 0 and _profile.d == unchanged_profile, "opening an already-seen story changes no profile data")
	await _press("Hear him out")
	_ok(_temple._lore_page == 1, "first story button advances exactly one page")
	var owner_calls := _touch.calls.size()
	_key(KEY_E)
	_key(KEY_E, true)
	_temple.open()
	await _frames()
	_ok(_temple._lore_page == 1 and _temple._phase == "lore", "repeated real E, echo and direct open do not reset lore")
	_ok(_touch.calls.size() == owner_calls, "re-entry guard does not retake movement ownership")
	await _press("Skip")
	_ok(_temple._phase == "intro" and _entry(_temple) != null, "actual Skip enters the current deployment UI")
	_assert_owned("skip to intro")
	var screen := _entry(_temple)
	_ok(screen != null and screen.has_signal("lore_requested"), "current entry exposes the replay signal")
	if screen == null:
		_finish()
		return
	var picker := screen.find_child("WagerCreaturePicker", true, false) as OptionButton
	_ok(picker != null and picker.item_count == 2, "entry exposes the two real eligible fixture creatures")
	if picker != null: picker.item_selected.emit(1)
	await _frames()
	_ok(_temple._horde_pick_uid == "qa-dragonos", "real entry picker selects the second creature")
	_key(KEY_E)
	_temple.open()
	await _frames()
	_ok(_temple._phase == "intro" and _temple._horde_pick_uid == "qa-dragonos",
		"repeated E and direct open preserve intro and the selected creature")
	await _press("GRIMWICK")
	_ok(_temple._phase == "lore" and _temple._lore_page == 0, "actual replay button -> new signal -> lore page zero")
	_ok(_temple._horde_pick_uid == "qa-dragonos", "replaying story preserves the selected uid")
	_assert_owned("replayed story")
	for page in range(10):
		_ok(_temple._phase == "lore" and _temple._lore_page == page, "story page %d is sequential" % page)
		await _press("I accept the wager" if page == 9 else "Hear him out")
	_ok(_temple._phase == "intro" and _entry(_temple) != null, "finishing all ten story pages returns to entry")
	_ok(_temple._horde_pick_uid == "qa-dragonos", "story completion preserves the selected uid")
	_ok(_profile.saves == 0 and _profile.d == unchanged_profile, "seen-player replay and completion do not save or mutate data")
	# A stale replay event must never interrupt an active encounter or a busy report.
	_temple._phase = "stage"
	_temple._lore_page = 7
	_temple._run_id = "qa-unpaid-sentinel"
	_temple._replay_lore()
	_ok(_temple._phase == "stage" and _temple._lore_page == 7 and _temple._run_id == "qa-unpaid-sentinel",
		"replay refuses an active-stage sentinel without resetting run state")
	_temple._phase = "intro"
	_temple._busy = true
	_temple._replay_lore()
	_ok(_temple._phase == "intro" and _temple._lore_page == 7, "busy entry refuses replay")
	_temple._busy = false
	_temple.close()
	_assert_released("close after intro")
	_temple._replay_lore()
	_ok(not _temple.visible and _temple._phase == "intro", "closed entry refuses a stale replay")
	_key(KEY_E)
	await _frames()
	_ok(_temple._phase == "lore" and _temple._lore_page == 0, "fresh E after closing restarts story even after completion")
	_assert_owned("reopened story")
	_key(KEY_ESCAPE)
	await _frames()
	_assert_released("real Escape from lore")
	_temple._busy = true
	_key(KEY_E)
	await _frames()
	_assert_released("busy closed Temple refuses E")
	_temple._busy = false
	# First-time compatibility: only a mark-seen save spy is invoked, once, and no economy data changes.
	_profile.d["temple_lore_seen"] = false
	_key(KEY_E)
	await _frames()
	_ok(_temple._phase == "lore" and _temple._lore_page == 0, "unseen-player E also starts the original story")
	await _press("Skip")
	_ok(_temple._phase == "intro" and _profile.saves == 1 and bool(_profile.d["temple_lore_seen"]),
		"first-time Skip enters intro and marks compatibility flag with one in-memory save call")
	await _press("GRIMWICK")
	await _press("Skip")
	_ok(_profile.saves == 1, "subsequent Skip never repeats the mark-seen save")
	_temple.close()
	_key(KEY_E)
	await _frames()
	_ok(_temple._phase == "lore", "fresh open still shows lore after first-time mark-seen")
	# The final explicit decline is intentionally different from Skip; it must keep releasing keys.
	_temple._lore_page = 9
	_temple._build()
	await _frames()
	await _press("Not today")
	_assert_released("last-page explicit decline")
	_ok(_profile.d == unchanged_profile and _profile.spends == 0,
		"only the compatibility seen flag changed; roster, materials and rewards remain untouched")
	_ok(get_tree().get_nodes_in_group("net").is_empty() and _requests(get_tree().root) == 0,
		"entire flow stayed offline with no Net or HTTPRequest nodes")
	if "--lore-layout" in OS.get_cmdline_user_args():
		await _lore_layout_matrix()
	_finish()

func _finish() -> void:
	if _temple != null: _temple.close()
	for path in _hashes:
		_ok(FileAccess.get_sha256(path) == String(_hashes[path]), "source unchanged: " + path)
	print("GRIMWICK_ENTRY_SOURCE_END=" + JSON.stringify(_hashes))
	print("GRIMWICK_ENTRY_QA_DONE checks=%d fails=%d fake_profile=true real_player_e=true network=false persistent_save=false" % [_checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
