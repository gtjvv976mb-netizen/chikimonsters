## HUD SHOTS (test only, never shipped): the in-game HUD as a player sees it.
##
## Enters the world from the title, presses through the first-run cards by their button text, then
## screenshots the HUD folded, with Settings open and with the Menu open, into $CHIK_AUDIT_DIR.
## Run it at the phone's own pixel size (2796 x 1290 for a Pro Max) with CHIK_SAFE_TEST insets.
extends Node

const CLICK := ["Got it", "Accept", "Play Demo", "Continue", "Close", "OK", "Enter"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().create_timer(6.0).timeout
	var title := _find_script(get_tree().root, "Title.gd")
	if title != null and title.has_method("_enter"):
		title.call("_enter")
	for i in 12:
		await get_tree().create_timer(8.0).timeout
		var pressed := _press_first(get_tree().root)
		print("[hud] step %d pressed %s" % [i, pressed])
		if pressed == "" and get_tree().get_first_node_in_group("world_main") != null and i > 5:
			break
	await get_tree().create_timer(10.0).timeout
	_shot("1_folded")
	var hud := get_node_or_null("/root/NativeHUD")
	if hud != null:
		hud.call("_set_settings", true)
		await get_tree().create_timer(4.0).timeout
		_shot("2_settings")
		hud.call("_set_settings", false)
		hud.call("_set_tabs", true)
		await get_tree().create_timer(4.0).timeout
		_shot("3_menu")
		hud.call("_set_tabs", false)
	_dump(get_tree().root, 0)
	get_tree().quit()


func _shot(tag: String) -> void:
	var dir := OS.get_environment("CHIK_AUDIT_DIR")
	if dir != "":
		get_viewport().get_texture().get_image().save_png(dir.path_join(tag + ".png"))
	print("[hud] shot ", tag)


func _find_script(n: Node, file: String) -> Node:
	var s: Script = n.get_script()
	if s != null and s.resource_path.ends_with(file):
		return n
	for c in n.get_children():
		var f := _find_script(c, file)
		if f != null:
			return f
	return null


## press the first visible button whose text starts with one of CLICK
func _press_first(n: Node) -> String:
	if n is BaseButton and (n as CanvasItem).is_visible_in_tree() and "text" in n:
		var t := str(n.get("text")).strip_edges()
		for c in CLICK:
			if t.findn(c) >= 0:
				(n as BaseButton).pressed.emit()
				return t
	for c in n.get_children():
		var r := _press_first(c)
		if r != "":
			return r
	return ""


## every visible Control on the CanvasLayers: where it is and how big, in points (for the layout review)
func _dump(n: Node, depth: int) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Control and depth < 7:
		var c := n as Control
		var xf := c.get_viewport().get_final_transform() * c.get_global_transform_with_canvas()
		var r := xf * Rect2(Vector2.ZERO, c.size)
		var pt := 3.0
		if r.size.x > 20 and r.size.y > 20:
			var t := ""
			if "text" in c:
				t = str(c.get("text")).strip_edges().left(30)
			print("[hudmap] %s%s %s \"%s\" pt(%d,%d %dx%d)" % ["  ".repeat(depth), c.get_class(), c.name, t,
				int(r.position.x / pt), int(r.position.y / pt), int(r.size.x / pt), int(r.size.y / pt)])
	for ch in n.get_children():
		_dump(ch, depth + (1 if n is Control else 0))
