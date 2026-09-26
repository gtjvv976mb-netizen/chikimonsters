## THE PHONE HUD: a mobile-game layout, one art style, nothing clipped or overlapping.
##
## The HUD was laid out for a browser window. On the iPhone this places every piece on one grid inside
## the safe area (the Dynamic Island side and the home-indicator strip), without rewriting the game's
## HUD scripts:
##
##   top-left      SETTINGS gear; opening it drops a 2 x 3 grid of the six setting buttons under it,
##                 with the minimap and the chat beside it
##   top centre    the header bar, scaled to fit between the corner buttons, with an ACCOUNT tab where
##                 the wallet plaque was, and the "online" pill just under it
##   top-right     MENU; the world clock under it; MENU opens the tab column under the
##                 clock (and the action buttons step aside while it is open)
##   bottom-left   the joystick (TouchControls, native: always shown, floats to your thumb)
##   bottom-right  the action cluster: the big action button, jump and sprint (TouchControls)
##
## Every button is the same art: a gold-and-sapphire ring with a cream pixel glyph (Higgsfield made
## the gear, menu, globe, profile and joystick knob in the game's own style; the other glyphs are
## drawn on the same blank ring at the same pixel scale). The bottom panels (quest tracker, buff timers,
## material counts, food quick-use) stay removed; the same things are in the Menu's tabs.
extends Node

const BTN := 64.0   # canvas units: 43 pt on a Pro Max
const GAP := 8.0
const ROW := {"QualityToggle": "quality", "LangToggle": "lang", "MusicToggle": "music",
	"ChatToggle": "chat", "ControlsToggle": "controls", "ScreenFlip": "flip"}

var _layer: CanvasLayer
var _gear: TextureButton
var _menu: TextureButton
var _col: GridContainer
var _hidden: Control
var _plaque: Button  # the header's ACCOUNT tab
var _settings_open := false
var _tabs_open := false
var _chat_was_open := false
var _done := false
var _tex := {}
var _art_w := 0.0


func _ready() -> void:
	if not ChikFeat.native() or not HDStruct_phone():
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000  # after the game's own HUD scripts, which re-place some panels every frame
	for k in ["gear", "menu", "close", "topbar"] + ROW.values():
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
	_layout(ib)


# ---------------------------------------------------------------- building


func _build(mn: Node, hud: Node, ib: Node) -> void:
	_layer = CanvasLayer.new()
	_layer.name = "NativeHUD"
	_layer.layer = 60
	mn.add_child(_layer)

	_gear = _button("gear", "Settings")
	_gear.pressed.connect(func(): _set_settings(not _settings_open))
	_layer.add_child(_gear)
	_menu = _button("menu", "Menu")
	_menu.pressed.connect(func(): _set_tabs(not _tabs_open))
	_layer.add_child(_menu)

	# the six setting buttons, restyled as round icons in a 2 x 3 grid under the gear
	_col = GridContainer.new()
	_col.columns = 2
	_col.add_theme_constant_override("h_separation", int(GAP))
	_col.add_theme_constant_override("v_separation", int(GAP))
	_col.visible = false
	_layer.add_child(_col)
	for n in ROW:
		var b: Button = hud.get_node_or_null(n)
		if b == null:
			continue
		b.remove_from_group("utility_row")  # the popup code hides and shows that group
		b.get_parent().remove_child(b)
		_iconify(b, ROW[n])
		_col.add_child(b)

	# the header: the game's art with its crypto-wallet plaque (blanked in the app with a flat brown
	# box) redrawn as an ACCOUNT tab in the same plaque and lettering; its own width, for fitting it
	var host: Control = ib.get("_top_bar_host")
	host.set_meta("safe_area_ignore", true)
	_art_w = host.size.x
	for c in host.find_children("*", "TextureRect", true, false):
		var tr := c as TextureRect
		if tr.texture != null and tr.texture.get_width() > 1000:
			if _tex.has("topbar"):
				tr.texture = _tex["topbar"]
			_art_w = minf(host.size.x, host.size.y * tr.texture.get_width() / float(tr.texture.get_height()))
	for c in host.find_children("*", "Panel", true, false):
		var sb := (c as Panel).get_theme_stylebox("panel") as StyleBoxFlat
		if sb != null and sb.bg_color.is_equal_approx(Color("862b00")):
			_plaque_button(c as Control)
	# the old corner Account button: its job is the plaque's now
	var acc := get_node_or_null("/root/NativeAccount")
	if acc != null and acc.get("_corner") is Control:
		(acc.get("_corner") as Control).set_meta("native_retired", true)

	# pieces this layout places itself: the safe-area pass must leave them alone
	for c in _placed(ib):
		c.set_meta("safe_area_ignore", true)

	# the bottom panels: parked inside a hidden holder, so the game can keep updating them
	_hidden = Control.new()
	_hidden.name = "NativeHiddenDocks"
	_hidden.visible = false
	_hidden.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_hidden)
	for k in ["_dock_l", "_dock_r"]:
		var d: Control = hud.get(k)
		if d != null and is_instance_valid(d):
			d.get_parent().remove_child(d)
			_hidden.add_child(d)

	_set_settings(false)
	_set_tabs(false)


## the ACCOUNT tab: a see-through button over the plaque, highlighted like the game's own tabs
func _plaque_button(blank: Control) -> void:
	blank.visible = false
	_plaque = Button.new()
	_plaque.name = "AccountTab"
	_plaque.tooltip_text = "Account"
	_plaque.focus_mode = Control.FOCUS_NONE
	var grow := Vector2(blank.size.x * 0.14, blank.size.y * 0.55)
	_plaque.position = blank.position - grow
	_plaque.size = blank.size + grow * 2.0
	var off := StyleBoxEmpty.new()
	var lit := StyleBoxFlat.new()
	lit.bg_color = Color(1.0, 0.83, 0.28, 0.22)
	lit.border_color = Color(1.0, 0.94, 0.63, 0.9)
	lit.set_border_width_all(2)
	lit.set_corner_radius_all(10)
	for st in ["normal", "focus", "disabled"]:
		_plaque.add_theme_stylebox_override(st, off)
	for st in ["hover", "pressed", "hover_pressed"]:
		_plaque.add_theme_stylebox_override(st, lit)
	_plaque.pressed.connect(func():
		var acc := get_node_or_null("/root/NativeAccount")
		if acc == null:
			return
		if ChikFeat.native_account().is_empty():
			acc.call("show_welcome", "")
		else:
			acc.call("show_account"))
	blank.get_parent().add_child(_plaque)


func _button(icon: String, tip: String) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = _tex.get(icon)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.custom_minimum_size = Vector2(BTN, BTN)
	b.size = Vector2(BTN, BTN)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	_press_feedback(b)
	return b


## a game Button redrawn as one of the round icons: no box, no text, the icon filling it
func _iconify(b: Button, icon: String) -> void:
	b.set_anchors_preset(Control.PRESET_TOP_LEFT)
	b.position = Vector2.ZERO
	b.text = ""
	if _tex.has(icon):
		b.icon = _tex[icon]
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", int(BTN))
	b.custom_minimum_size = Vector2(BTN, BTN)
	b.size = Vector2(BTN, BTN)
	b.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	for c in b.get_children():
		if c is TextureRect:
			(c as TextureRect).visible = false  # the old icon art, where it is a child
	_press_feedback(b)


func _press_feedback(b: BaseButton) -> void:
	b.button_down.connect(func(): b.self_modulate = Color(1.3, 1.25, 1.05))
	b.button_up.connect(func(): b.self_modulate = Color.WHITE)


# ---------------------------------------------------------------- state


func _set_settings(open: bool) -> void:
	_settings_open = open
	_col.visible = open
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


# ---------------------------------------------------------------- layout, every frame


func _insets() -> Vector4:
	var sa := get_node_or_null("/root/NativeSafeArea")
	return sa.get("_insets") if sa != null else Vector4.ZERO


func _placed(ib: Node) -> Array[Control]:
	var out: Array[Control] = []
	for c in [ib.get("_clock_panel"), _chat_panel()] + _minimap_panels():
		if c is Control and is_instance_valid(c):
			out.append(c)
	return out


## the minimap first, then the other panels on its layer
func _minimap_panels() -> Array:
	var out := []
	var mm := get_tree().get_first_node_in_group("minimap")
	if mm != null:
		for c in mm.get_children():
			if c is Control and (c as Control).visible:
				out.append(c)
	return out


func _chat_panel() -> Control:
	var chat := get_tree().get_first_node_in_group("chat")
	return chat.get("_panel") if chat != null else null


func _put(c: Control, pos: Vector2) -> void:
	c.set_meta("safe_area_ignore", true)  # placed here, inside the safe area already
	if c.anchor_left != 0.0 or c.anchor_top != 0.0 or c.anchor_right != 0.0 or c.anchor_bottom != 0.0:
		var sz0 := c.size
		c.set_anchors_preset(Control.PRESET_TOP_LEFT)
		c.grow_horizontal = Control.GROW_DIRECTION_END
		c.grow_vertical = Control.GROW_DIRECTION_END
		c.size = sz0
	if not c.position.is_equal_approx(pos):
		var sz := c.size
		c.position = pos
		c.size = sz


func _layout(ib: Node) -> void:
	var vs := _gear.get_viewport_rect().size
	var ins := _insets()
	var x0 := ins.x + 6.0
	var x1 := vs.x - ins.z - 6.0
	var top := 8.0

	# corners
	_gear.position = Vector2(x0, top)
	_menu.position = Vector2(x1 - BTN, top)
	var right_cluster := x1 - BTN
	var acc := get_node_or_null("/root/NativeAccount")
	if acc != null:
		var corner = acc.get("_corner")
		if corner is Control and (corner as Control).visible:
			(corner as Control).visible = false  # the header's ACCOUNT tab does its job

	# header: centred, as large as fits between the gear and the right-hand buttons
	var host: Control = ib.get("_top_bar_host")
	if host != null and is_instance_valid(host) and _art_w > 0.0:
		var cx := vs.x * 0.5
		var half := minf(cx - (x0 + BTN + GAP * 2.0), (right_cluster - GAP * 2.0) - cx)
		var s := clampf(half * 2.0 / _art_w, 0.45, 0.85)
		host.pivot_offset = Vector2(host.size.x * 0.5, 0.0)
		if not is_equal_approx(host.scale.x, s):
			host.scale = Vector2(s, s)

	# settings column under the gear; minimap and chat beside it
	var col_top := top + BTN + GAP * 1.5
	_col.position = Vector2(x0, col_top)
	var side_x := x0 + BTN * 2.0 + GAP * 2.5
	# the minimap only: the layer's other panels (the "Island's Chronicles" feed, the ping pill) are
	# desktop extras that would stack onto the joystick on a phone
	var chat_x := side_x
	var panels := _minimap_panels()
	for i in panels.size():
		var c: Control = panels[i]
		if i == 0:
			_put(c, Vector2(side_x, col_top))
			chat_x = side_x + c.size.x + GAP
		else:
			c.visible = false
	var cp := _chat_panel()
	if cp != null and is_instance_valid(cp):
		_put(cp, Vector2(chat_x, col_top))

	# clock under the right-hand buttons, right-aligned; the tab column under the clock
	var clock: Control = ib.get("_clock_panel")
	var rail_top := top + BTN + GAP * 1.5
	if clock != null and is_instance_valid(clock):
		_put(clock, Vector2(x1 - clock.size.x, top + BTN + GAP * 1.5))
		if clock.visible:
			rail_top = clock.position.y + clock.size.y + GAP
	var pp := get_tree().get_first_node_in_group("playerpanel")
	if pp != null:
		var rail: Control = pp.get("_rail")
		if rail != null and is_instance_valid(rail):
			rail.visible = _tabs_open
			if _tabs_open and absf(rail.offset_top - rail_top) > 0.5:
				var h := rail.offset_bottom - rail.offset_top
				rail.offset_top = rail_top
				rail.offset_bottom = rail_top + h

	# the "online" pill, and the event pill below it, just under the header
	var net := get_node_or_null("/root/Net")
	if net != null and host != null:
		var under: float = host.position.y + host.size.y * host.scale.y + 4.0
		var pill: Control = net.get("_online_pill")
		if pill != null and is_instance_valid(pill):
			var h := pill.offset_bottom - pill.offset_top
			var dy := under - pill.offset_top
			if absf(dy) > 0.5:
				pill.offset_top = under
				pill.offset_bottom = under + h
				var ev: Control = net.get("_event_panel")
				if ev != null and is_instance_valid(ev):
					ev.offset_top += dy
					ev.offset_bottom += dy

	# the chat toggle inside the column may reopen chat while settings are folded: fold it back
	if not _settings_open:
		var chat := get_tree().get_first_node_in_group("chat")
		if chat != null and bool(chat.get("_open")) and chat.has_method("toggle"):
			chat.call("toggle")
