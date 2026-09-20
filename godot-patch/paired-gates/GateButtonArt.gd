extends RefCounted
## Optional, text-free nine-slice art for the two landmark entry gates.
## Call after the existing button skin. A missing or unsuitable PNG leaves every
## original stylebox, focus ring, label, signal, and touch target unchanged.

const PATHS := {
	"wicked": {
		"primary": "res://wicked_enter_button.png",
		"secondary": "res://wicked_secondary_button.png",
	},
	"chikiseum": {
		"primary": "res://chikiseum_enter_button.png",
		"secondary": "res://chikiseum_secondary_button.png",
	},
}

static var _prepared: Dictionary = {}


static func apply(button: Button, gate: String, primary: bool = false) -> bool:
	if button == null or not PATHS.has(gate):
		return false
	var path: String = PATHS[gate]["primary" if primary else "secondary"]
	var texture := _button_texture(path)
	if texture == null:
		return false
	# The exterior and engraved corners live in the PNG; the quiet center stretches
	# across narrow secondary actions and the full-width primary action alike.
	var edge_x := minf(28.0, texture.get_width() * 0.10)
	var edge_y := minf(12.0, texture.get_height() * 0.20)
	var colors := {
		"normal": Color.WHITE,
		"hover": Color(1.0, 0.96, 0.85) if primary else Color(0.96, 0.90, 1.0),
		"pressed": Color(0.77, 0.71, 0.67) if primary else Color(0.70, 0.62, 0.78),
		"disabled": Color(0.47, 0.45, 0.50, 0.78),
	}
	for state in colors:
		var skin := StyleBoxTexture.new()
		skin.texture = texture
		skin.texture_margin_left = edge_x
		skin.texture_margin_right = edge_x
		skin.texture_margin_top = edge_y
		skin.texture_margin_bottom = edge_y
		# Pickers left-align their native label, unlike centered action buttons.
		# Reserve the engraved endcaps so names and the arrow never sit on jewels.
		skin.content_margin_left = 40.0 if button is OptionButton else 8.0
		skin.content_margin_right = 34.0 if button is OptionButton else 8.0
		skin.content_margin_top = 4.0
		skin.content_margin_bottom = 4.0
		skin.modulate_color = colors[state]
		button.add_theme_stylebox_override(state, skin)
	if button is OptionButton:
		button.add_theme_constant_override("arrow_margin", 34)
	# Native labels remain readable and localized; no text is baked into the art.
	var ink := Color("1e1520") if primary else Color("fff2e5")
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, ink)
	button.add_theme_color_override("font_disabled_color", Color("b1a7b7"))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return true


static func _button_texture(path: String) -> Texture2D:
	if _prepared.has(path):
		return _prepared[path] as Texture2D
	if not ResourceLoader.exists(path):
		return null
	var source := load(path) as Texture2D
	if source == null:
		return null
	var image := source.get_image()
	if image == null or image.is_empty() or image.get_height() == 0:
		return null
	if image.is_compressed() and image.decompress() != OK:
		return null
	# Higgsfield's clean PNGs can carry a generous transparent canvas. Nine-slicing
	# that canvas would stretch empty space and make the actual plate look tiny.
	# Trim only fully transparent exterior pixels in memory; keep the authored PNG.
	var used := _visible_art_rect(image, image.get_used_rect())
	if used.size.x <= 0 or used.size.y <= 0:
		return null
	if used.size != image.get_size():
		image = image.get_region(used)
	# A square generator output is not a button. Fallback is safer than stretching
	# decorative corners into an unusable entry control.
	if float(image.get_width()) / float(image.get_height()) < 2.6:
		return null
	# Bound decoded/mobile memory while retaining more than enough texels for the
	# 42-48 logical-pixel controls. The source PNG itself is never modified.
	if image.get_height() > 96:
		var width := maxi(1, roundi(float(image.get_width()) * 96.0 / float(image.get_height())))
		image.resize(width, 96, Image.INTERPOLATE_LANCZOS)
	var texture := ImageTexture.create_from_image(image)
	_prepared[path] = texture
	return texture


static func _visible_art_rect(image: Image, occupied: Rect2i) -> Rect2i:
	if occupied.size.x <= 0 or occupied.size.y <= 0:
		return Rect2i()
	# A few generator pixels can have alpha=1 at the canvas edge. Godot's
	# get_used_rect() includes them, so refine its bounds at a barely-visible
	# threshold. Sampling every other pixel and padding by two protects thin
	# antialiasing while keeping this one-time mobile load inexpensive.
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var pixels := image.get_data()
	var stride := image.get_width() * 4
	var left := image.get_width()
	var top := image.get_height()
	var right := -1
	var bottom := -1
	var end := occupied.end
	for y in range(occupied.position.y, end.y, 2):
		var row := y * stride + 3
		for x in range(occupied.position.x, end.x, 2):
			if pixels[row + x * 4] <= 3:
				continue
			left = mini(left, x)
			top = mini(top, y)
			right = maxi(right, x)
			bottom = maxi(bottom, y)
	if right < left:
		return Rect2i()
	var origin := Vector2i(maxi(occupied.position.x, left - 2), maxi(occupied.position.y, top - 2))
	var finish := Vector2i(mini(end.x, right + 3), mini(end.y, bottom + 3))
	return Rect2i(origin, finish - origin)
