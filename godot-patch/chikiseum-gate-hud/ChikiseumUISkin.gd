extends RefCounted
const INK:=Color("151420")
const GOLD:=Color("d3b67d")
const LIGHT:=Color("f2e8d5")
const MUTED:=Color("aca5ba")
const VIOLET:=Color("a376ee")
const CYAN:=Color("55c8ec")
static func panel(accent: Color=GOLD, emphatic: bool=false) -> StyleBoxFlat:
	var skin:=StyleBoxFlat.new();skin.bg_color=Color("191822f5")
	skin.border_color=Color(accent,0.52 if emphatic else 0.25)
	skin.border_width_left=1;skin.border_width_right=1;skin.border_width_bottom=1;skin.border_width_top=2 if emphatic else 1
	skin.set_corner_radius_all(5);skin.corner_detail=1
	skin.shadow_color=Color(0,0,0,0.27);skin.shadow_size=10;skin.shadow_offset=Vector2(0,4)
	skin.content_margin_left=14;skin.content_margin_right=14;skin.content_margin_top=12;skin.content_margin_bottom=12
	return skin
static func button(button: Button, primary: bool=false, accent: Color=GOLD) -> void:
	var normal:=panel(accent,primary);normal.shadow_size=0
	normal.bg_color=Color("574332") if primary else Color("272432")
	normal.content_margin_top=6;normal.content_margin_bottom=6;normal.content_margin_left=8;normal.content_margin_right=8
	var hover:=normal.duplicate() as StyleBoxFlat;hover.bg_color=Color("745637") if primary else Color("3b344c");hover.border_color=accent
	var pressed:=hover.duplicate() as StyleBoxFlat;pressed.bg_color=Color("473927") if primary else Color("201c2b")
	var disabled:=normal.duplicate() as StyleBoxFlat;disabled.bg_color=Color("24212b");disabled.border_color=Color("48424e")
	button.add_theme_stylebox_override("normal",normal);button.add_theme_stylebox_override("hover",hover);button.add_theme_stylebox_override("pressed",pressed);button.add_theme_stylebox_override("disabled",disabled)
	button.add_theme_color_override("font_color",LIGHT);button.add_theme_color_override("font_hover_color",Color.WHITE);button.add_theme_color_override("font_pressed_color",LIGHT);button.add_theme_color_override("font_disabled_color",Color("79727f"))
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	var focus:=StyleBoxFlat.new();focus.bg_color=Color.TRANSPARENT;focus.border_color=Color("fff1b9");focus.set_border_width_all(2);focus.set_corner_radius_all(5)
	button.add_theme_stylebox_override("focus",focus)
static func card(button: Button, selected: bool, accent: Color) -> void:
	var normal:=StyleBoxFlat.new();normal.bg_color=Color("1b1720");normal.set_corner_radius_all(5)
	normal.border_color=accent if selected else Color("62564a");normal.set_border_width_all(2 if selected else 1)
	normal.expand_margin_left=3;normal.expand_margin_right=3;normal.expand_margin_top=3;normal.expand_margin_bottom=3
	normal.shadow_color=Color(accent,0.23) if selected else Color(0,0,0,0.35);normal.shadow_size=8;normal.shadow_offset=Vector2(0,4)
	var hover:=normal.duplicate() as StyleBoxFlat;hover.border_color=GOLD;hover.set_border_width_all(2)
	button.add_theme_stylebox_override("normal",normal);button.add_theme_stylebox_override("hover",hover);button.add_theme_stylebox_override("pressed",hover)
	var disabled:=normal.duplicate() as StyleBoxFlat;disabled.border_color=Color("463d49");button.add_theme_stylebox_override("disabled",disabled)
	button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
