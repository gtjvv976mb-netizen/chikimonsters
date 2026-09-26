## THE PHONE HUD, COLLAPSIBLE AND FIXED.
##
## The HUD was laid out for a browser window: a row of six small toggles, the minimap and the chat
## down the left, a column of tabs down the right, two panels along the bottom and a header bar as
## wide as the screen, so the Dynamic Island and the rounded corners cut its ends off. On the iPhone
## this regroups it without rewriting the game's HUD scripts:
##   - a SETTINGS gear, fixed top-left under the header, folds the utility row, the minimap and the
##     chat away and brings them back (the row slides out beside the gear, as before);
##   - a MENU button, fixed top-right, opens and closes the tab column (it turns into a close cross);
##   - the bottom panels (quest tracker, buff timers, the "0/60" material counts, food quick-use)
##     are removed — the same food and items are in the Food and Inventory tabs;
##   - the header bar is drawn smaller and centred, so the whole of it is on screen.
## Both panels start folded, so the world gets the screen. Icons: Higgsfield, made to match the
## game's own gold-and-sapphire HUD art.
extends Node

const HEADER_SCALE := 0.82
const BTN := 60.0  # canvas units; 43 pt on a Pro Max, like the utility row
const ROW := ["QualityToggle", "LangToggle", "MusicToggle", "ChatToggle", "ControlsToggle", "ScreenFlip"]

var _layer: CanvasLayer
var _gear: TextureButton
var _menu: TextureButton
var _row: HBoxContainer
var _hidden: Control
var _settings_open := false
var _tabs_open := false
var _chat_was_open := false
var _done := false
var _header_done := false
var _tex := {}


func _ready() -> void:
	if not ChikFeat.native() or not HDStruct_phone():
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	for k in ["gear", "menu", "close", "map"]:
		var img := Image.load_from_file("res://nat_%s.png" % k)
		if img != null and not img.is_empty():
			_tex[k] = ImageTexture.create_from_image(img)


static func HDStruct_phone() -> bool:
	return load("res://HDStruct.gd").phone_world()


func _process(_d: float) -> void:
	var mn := get_tree().get_first_node_in_group("world_main")
	if mn == null:
		return
	var hud: Node = mn.get_node_or_null("GameHUD")
	var ib: Node = get_tree().get_first_node_in_group("infobar")
	if hud == null or ib == null or ib.get("_top_bar_host") == null:
		return  # the HUD is still being built
	if not _done:
		_done = true
		_build(mn, hud, ib)
	_keep(hud)


func _build(mn: Node, hud: Node, ib: Node) -> void:
	_layer = CanvasLayer.new()
	_layer.name = "NativeHUD"
	_layer.layer = 60
	mn.add_child(_layer)
	_shrink_header(hud, ib)

	# settings: the gear, then the utility row folded out beside it
	var y: float = ib.top_bar_bottom_y() + 6.0
	_gear = _button("gear", "Settings")
	_gear.position = Vector2(14, y)
	_gear.pressed.connect(func(): _set_settings(not _settings_open))
	_layer.add_child(_gear)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 8)
	_row.position = Vector2(14 + BTN + 10, y)
	_row.visible = false
	_layer.add_child(_row)
	for n in ROW:
		var b: Button = hud.get_node_or_null(n)
		if b == null:
			continue
		b.remove_from_group("utility_row")  # the popup code hides and shows that group
		b.get_parent().remove_child(b)
		b.set_anchors_preset(Control.PRESET_TOP_LEFT)
		b.position = Vector2.ZERO
		b.custom_minimum_size = Vector2(BTN, BTN)
		_row.add_child(b)
	# the minimap and the rest of the left column now start under the gear
	hud.set("_utility_y", y)
	hud.set("_utility_size", BTN)
	var mm := get_tree().get_first_node_in_group("minimap")
	if mm != null:
		mm.set("_last_vs", Vector2.ZERO)
		if mm.has_method("_place"):
			mm.call("_place")

	# tabs: the menu button, fixed top-right; the column opens under it
	_menu = _button("menu", "Menu")
	_menu.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_menu.offset_left = -BTN - 14
	_menu.offset_right = -14
	_menu.offset_top = y
	_menu.offset_bottom = y + BTN
	_menu.pressed.connect(func(): _set_tabs(not _tabs_open))
	_layer.add_child(_menu)

	# the bottom panels: parked inside a hidden holder, so the game can keep updating them
	_hidden = Control.new()
	_hidden.name = "NativeHiddenDocks"
	_hidden.visible = false
	_hidden.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hidden.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_hidden)
	for k in ["_dock_l", "_dock_r"]:
		var d: Control = hud.get(k)
		if d != null and is_instance_valid(d):
			d.get_parent().remove_child(d)
			_hidden.add_child(d)

	_set_settings(false)
	_set_tabs(false)


func _button(icon: String, tip: String) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = _tex.get(icon)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.custom_minimum_size = Vector2(BTN, BTN)
	b.size = Vector2(BTN, BTN)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.button_down.connect(func(): b.modulate = Color(1.25, 1.25, 1.1))  # a visible press
	b.button_up.connect(func(): b.modulate = Color.WHITE)
	return b


func _set_settings(open: bool) -> void:
	_settings_open = open
	_row.visible = open
	_gear.texture_normal = _tex.get("close") if open else _tex.get("gear")
	var mm := get_tree().get_first_node_in_group("minimap")
	if mm is CanvasLayer:
		(mm as CanvasLayer).visible = open
	var chat := get_tree().get_first_node_in_group("chat")
	if chat != null and chat.has_method("toggle"):
		if open:
			if _chat_was_open and not bool(chat.get("_open")):
				chat.call("toggle")
		else:
			_chat_was_open = bool(chat.get("_open"))
			if _chat_was_open:
				chat.call("toggle")


func _set_tabs(open: bool) -> void:
	_tabs_open = open
	_menu.texture_normal = _tex.get("close") if open else _tex.get("menu")


# every frame: the tab column follows the menu button (the game rebuilds it now and then)
func _keep(hud: Node) -> void:
	var pp := get_tree().get_first_node_in_group("playerpanel")
	if pp != null:
		var rail: Control = pp.get("_rail")
		if rail != null and is_instance_valid(rail):
			rail.visible = _tabs_open
			if _tabs_open:
				var top := _menu.get_global_rect().end.y + 8.0
				if rail.offset_top < top - 0.5:
					var h := rail.offset_bottom - rail.offset_top
					rail.offset_top = top
					rail.offset_bottom = top + h
	# the chat toggle inside the row may reopen chat while settings are folded: fold it back
	if not _settings_open:
		var chat := get_tree().get_first_node_in_group("chat")
		if chat != null and bool(chat.get("_open")) and chat.has_method("toggle"):
			chat.call("toggle")


# the header, 82% and centred: all of it inside the safe area
func _shrink_header(hud: Node, ib: Node) -> void:
	if _header_done:
		return
	_header_done = true
	var host: Control = ib.get("_top_bar_host")
	var before: float = ib.top_bar_bottom_y()
	host.set_meta("safe_area_ignore", true)
	host.pivot_offset = Vector2(host.size.x * 0.5, 0.0)
	host.scale = Vector2(HEADER_SCALE, HEADER_SCALE)
	var lift: float = before - ib.top_bar_bottom_y()
	var clock: Control = ib.get("_clock_panel")
	if clock != null and is_instance_valid(clock):
		clock.offset_top -= lift
		clock.offset_bottom -= lift
	var pp := get_tree().get_first_node_in_group("playerpanel")
	if pp != null and pp.has_method("_layout_rail"):
		pp.set("_rail_vs", Vector2.ZERO)
		pp.call("_layout_rail")
