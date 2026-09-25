## UI AUDIT for the native iPhone app: Apple's layout rules checked against the live HUD.
##
## Loaded as an extra autoload in a test build (never shipped). It enters the world from the title
## screen, then every AUDIT_EVERY seconds screenshots the game and reports, in points (1 pt = 3 px
## on a Pro Max, scaled by the test window):
##   SAFE  a visible control inside the landscape unsafe zones — the Dynamic Island / sensor housing
##         side (59 pt on both sides, because the phone can be turned either way) and the home
##         indicator strip (21 pt at the bottom);
##   TOUCH a visible, clickable control smaller than 44 x 44 pt (Human Interface Guidelines);
##   TEXT  visible text drawn smaller than 11 pt.
## Output lines start with "[audit]" (JSON), shots go to $CHIK_AUDIT_DIR.
extends Node

const AUDIT_EVERY := 20.0
const SHOTS := 5
const PT_PER_SCREEN_H := 430.0  # iPhone 15/16 Pro Max landscape: 932 x 430 pt
const SAFE_SIDE := 59.0
const SAFE_BOTTOM := 21.0
const MIN_TOUCH := 44.0
const MIN_TEXT := 11.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().create_timer(6.0).timeout
	var title := _find_with_method(get_tree().root, "_enter")
	if title != null:
		title.call("_enter")
		print("[audit] {\"event\":\"entered\"}")
	for i in SHOTS:
		await get_tree().create_timer(AUDIT_EVERY).timeout
		_audit(i)


func _find_with_method(n: Node, m: String) -> Node:
	var s: Script = n.get_script()
	if s != null and s.resource_path.ends_with("Title.gd") and n.has_method(m):
		return n
	for c in n.get_children():
		var f := _find_with_method(c, m)
		if f != null:
			return f
	return null


func _audit(i: int) -> void:
	var win := DisplayServer.window_get_size()
	var pt := float(win.y) / PT_PER_SCREEN_H  # window pixels per point
	var unsafe_l := SAFE_SIDE * pt
	var unsafe_r := win.x - SAFE_SIDE * pt
	var unsafe_b := win.y - SAFE_BOTTOM * pt
	var found := {"safe": [], "touch": [], "text": []}
	_walk(get_tree().root, pt, unsafe_l, unsafe_r, unsafe_b, found)
	for k in found:
		for item in found[k]:
			print("[audit] ", JSON.stringify(item))
	print("[audit] ", JSON.stringify({"event": "summary", "shot": i, "window": [win.x, win.y],
		"safe": found.safe.size(), "touch": found.touch.size(), "text": found.text.size()}))
	var dir := OS.get_environment("CHIK_AUDIT_DIR")
	if dir != "":
		get_viewport().get_texture().get_image().save_png(dir.path_join("shot%d.png" % i))


func _window_rect(c: Control) -> Rect2:
	var xf := c.get_viewport().get_final_transform() * c.get_global_transform_with_canvas()
	return xf * Rect2(Vector2.ZERO, c.size)


func _label(c: Control) -> String:
	var t := ""
	if "text" in c:
		t = str(c.get("text")).strip_edges().left(40)
	if t == "" and "tooltip_text" in c:
		t = str(c.tooltip_text).left(40)
	return "%s %s \"%s\"" % [c.get_class(), c.name, t]


func _walk(n: Node, pt: float, ul: float, ur: float, ub: float, found: Dictionary) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Control:
		var c := n as Control
		var r := _window_rect(c)
		var win := Vector2(DisplayServer.window_get_size())
		var on_screen := r.size.x > 1.0 and r.size.y > 1.0 and r.end.x > 0 and r.end.y > 0 \
			and r.position.x < win.x and r.position.y < win.y
		var covers_screen := r.size.x > win.x * 0.9 and r.size.y > win.y * 0.9
		var interactive := c is BaseButton or c is LineEdit or c is Slider or c is ItemList \
			or (c.mouse_filter == Control.MOUSE_FILTER_STOP and c.gui_input.get_connections().size() > 0)
		var has_text := (c is Label or c is Button or c is RichTextLabel) and "text" in c \
			and str(c.get("text")).strip_edges() != ""
		if on_screen and not covers_screen and (interactive or has_text):
			var bad := []
			if r.position.x < ul:
				bad.append("left %.0f pt" % ((ul - r.position.x) / pt))
			if r.end.x > ur:
				bad.append("right %.0f pt" % ((r.end.x - ur) / pt))
			if r.end.y > ub:
				bad.append("bottom %.0f pt" % ((r.end.y - ub) / pt))
			if r.position.x < -1.0 or r.end.x > win.x + 1.0 or r.end.y > win.y + 1.0:
				bad.append("OFF SCREEN")
			if not bad.is_empty():
				found.safe.append({"kind": "SAFE", "what": _label(c), "into": ", ".join(bad),
					"rect_pt": _pt(r, pt)})
		if on_screen and interactive and not (c is LineEdit):
			var w := r.size.x / pt
			var h := r.size.y / pt
			if (w < MIN_TOUCH or h < MIN_TOUCH) and not covers_screen:
				found.touch.append({"kind": "TOUCH", "what": _label(c), "size_pt": [snappedf(w, 0.1), snappedf(h, 0.1)]})
		if on_screen and has_text:
			var fs := 0
			if c is RichTextLabel:
				fs = c.get_theme_font_size("normal_font_size")
			else:
				fs = c.get_theme_font_size("font_size")
			var scale := _window_rect(c).size.y / maxf(1.0, c.size.y)
			var fpt := fs * scale / pt
			if fs > 0 and fpt < MIN_TEXT:
				found.text.append({"kind": "TEXT", "what": _label(c), "size_pt": snappedf(fpt, 0.1)})
	for ch in n.get_children():
		_walk(ch, pt, ul, ur, ub, found)


func _pt(r: Rect2, pt: float) -> Array:
	return [snappedf(r.position.x / pt, 0.1), snappedf(r.position.y / pt, 0.1),
		snappedf(r.size.x / pt, 0.1), snappedf(r.size.y / pt, 0.1)]
