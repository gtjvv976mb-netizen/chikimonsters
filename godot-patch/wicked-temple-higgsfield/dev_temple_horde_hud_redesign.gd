extends Node
# Focused regression gate for the compact Wicked Temple combat HUD.
#
# This intentionally inspects the real runtime Controls and world-following nameplates. It does not
# duplicate the layout implementation and it never advances or rewards a run.

const Horde := preload("res://TempleHorde3D.gd")
const CardArt := preload("res://TempleCardArt.gd")

const HD_CARD_MIN := Vector2(140.0, 210.0)
const PHONE_CARD_MIN := Vector2(94.0, 94.0)
const MAX_PLATE_BAR := Vector2i(80, 6)
const MAX_FIXED_BAR_SCREEN := Vector2(80.0, 12.0)
const MAX_FIXED_PLATE_SCREEN := Vector2(124.0, 48.0)
const MAX_BAR_WORLD := Vector2(0.10, 0.012)
const HD_REFERENCE_SIZE := Vector2(1280.0, 720.0)
const HD_REFERENCE_DOCK_MAX := 224.0
# The existing72-logical-pixel body gap belongs to the1600x900 canvas at the .8 shell scale.
const HD_REFERENCE_BODY_GAP_MIN := 72.0 * 0.8

var _game: Node = null
var _fails := 0
var _checks := 0
var _phone := false
var _headless := false


func _presentation_scale() -> float:
	# Headless has no physical window: the dummy64px screen cannot prove readable controls.
	# Model the existing1280x720 HD shell or844x390 phone CSS/logical contract explicitly.
	return (Horde.PHONE_CSS_PER_LOGICAL if _phone else 0.8) if _headless \
		else get_viewport().get_screen_transform().get_scale().y


func _ok(condition: bool, message: String) -> void:
	_checks += 1
	print(("ok:   " if condition else "FAIL: ") + message)
	if not condition:
		_fails += 1


func _frames(count: int = 2) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _first_active_enemy() -> Dictionary:
	for value in _game.get("_enemy_pool") as Array:
		var enemy := value as Dictionary
		if bool(enemy.get("active", false)):
			return enemy
	return {}


func _control_hidden_or_absent(value: Variant) -> bool:
	if value == null:
		return true
	if not (value is CanvasItem) or not is_instance_valid(value):
		return true
	return not (value as CanvasItem).is_visible_in_tree()


func _texture_region_size(texture: Texture2D) -> Vector2:
	if texture == null:
		return Vector2.ZERO
	if texture is AtlasTexture:
		return (texture as AtlasTexture).region.size
	return texture.get_size()


func _screen_rect(control: Control) -> Rect2:
	var logical := control.get_global_rect()
	if _headless:
		var scale := _presentation_scale()
		return Rect2(logical.position * scale, logical.size * scale)
	var transform := get_viewport().get_screen_transform()
	var a := transform * logical.position
	var b := transform * logical.end
	return Rect2(a.min(b), (b - a).abs())


func _label_fits(label: Label) -> bool:
	if label == null:
		return false
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x \
		<= label.size.x + 1.0


func _phone_preview_is_safe(preview: Control) -> bool:
	var phone_rect := Rect2(preview.position, preview.size)
	var viewport_rect := get_viewport().get_visible_rect()
	var rects := _game.call("touch_rects") as Dictionary
	var clear := viewport_rect.encloses(phone_rect)
	for key in ["move", "dodge", "card_0", "card_1", "card_2", "page"]:
		if rects.has(key):
			clear = clear and not phone_rect.intersects(rects[key] as Rect2)
	return clear


# SpriteBase3D.fixed_size renders the quad at the apparent size it would have one metre from the
# camera. Measuring only the 76x6 source texture misses pixel_size and Node3D scale—the exact knobs
# that can turn a tiny texture into a screen-filling plate. These helpers reconstruct that live
# camera-space footprint from get_item_rect(), font metrics, pixel_size, and the global scale.
func _sprite_world_rect(node: Sprite3D) -> Rect2:
	var item := node.get_item_rect()
	var scale_3d := node.global_transform.basis.get_scale().abs()
	return Rect2(item.position * node.pixel_size * Vector2(scale_3d.x, scale_3d.y),
		item.size * node.pixel_size * Vector2(scale_3d.x, scale_3d.y))


func _label_world_rect(node: Label3D) -> Rect2:
	var font := node.font if node.font != null else ThemeDB.fallback_font
	var text_size := font.get_string_size(node.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		node.font_size)
	text_size.y = font.get_height(node.font_size)
	text_size += Vector2.ONE * float(node.outline_size * 2)
	var scale_3d := node.global_transform.basis.get_scale().abs()
	var scale_2d := node.pixel_size * Vector2(scale_3d.x, scale_3d.y)
	return Rect2((node.offset - text_size * 0.5) * scale_2d, text_size * scale_2d)


func _projected_geometry_rect(node: GeometryInstance3D, camera: Camera3D) -> Rect2:
	if node == null or camera == null or not is_instance_valid(node) \
			or not is_instance_valid(camera):
		return Rect2()
	var world_rect := _sprite_world_rect(node as Sprite3D) if node is Sprite3D \
		else _label_world_rect(node as Label3D)
	var right := camera.global_transform.basis.x.normalized()
	var up := camera.global_transform.basis.y.normalized()
	var forward := -camera.global_transform.basis.z.normalized()
	var fixed := (node is SpriteBase3D and bool(node.get("fixed_size"))) \
		or (node is Label3D and (node as Label3D).fixed_size)
	var center := camera.global_position + forward if fixed else node.global_position
	var xs := [world_rect.position.x, world_rect.end.x]
	var ys := [world_rect.position.y, world_rect.end.y]
	var first := true
	var minimum := Vector2.ZERO
	var maximum := Vector2.ZERO
	for x in xs:
		for y in ys:
			var screen := camera.unproject_position(center + right * float(x) + up * float(y))
			if first:
				minimum = screen; maximum = screen; first = false
			else:
				minimum = minimum.min(screen); maximum = maximum.max(screen)
	return Rect2(minimum, maximum - minimum)


func _world_geometry_size(node: GeometryInstance3D) -> Vector2:
	if node == null or not is_instance_valid(node):
		return Vector2.ZERO
	if node is Sprite3D:
		return _sprite_world_rect(node as Sprite3D).size
	return _label_world_rect(node as Label3D).size


func _plate_projection(plate: Dictionary, camera: Camera3D) -> Dictionary:
	var back := plate.get("back") as Sprite3D
	var label := plate.get("label") as Label3D
	var bar_rect := _projected_geometry_rect(back, camera)
	var label_rect := _projected_geometry_rect(label, camera)
	return {"bar": bar_rect, "label": label_rect, "whole": bar_rect.merge(label_rect),
		"bar_world": _world_geometry_size(back)}


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_phone = OS.get_environment("CHIK_FORCEPHONE") == "1"
	_headless = DisplayServer.get_name() == "headless"
	if _headless:
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		get_window().content_scale_size = Vector2i(1442, 667) if _phone else Vector2i(1600, 900)
		print("HUD_GEOMETRY_MODE=headless-modeled-css logical=%s css_scale=%.3f; native pixels/screenshots NOT proved" % [
			get_window().content_scale_size, _presentation_scale()])
	elif _phone:
		# Same native phone-shell setup as dev_temple_clean_hud_qa: avoid squeezing the
		# desktop1600x900 canvas into a phone while claiming that is the phone CSS layout.
		get_window().content_scale_size = Vector2i((Vector2(get_window().size) / Horde.PHONE_CSS_PER_LOGICAL).round())
	print("=== WICKED TEMPLE HUD REDESIGN · %s ===" % ("PHONE" if _phone else "HD"))
	_game = Horde.new()
	_game.call("set_party", [{"uid": "hud-redesign", "species": "firix",
		"kind": "normal", "level": 50}])
	add_child(_game)
	await _frames(1)
	_game.call("enter", "classic")
	await _frames(2)
	_game.call("start_stage")
	_game.call("debug_start_wave", 0)
	_game.call("_refresh_combat_nameplates")
	_game.call("_refresh_hud", true)
	await _frames(3)
	_game.set_process(false)
	_game.set_physics_process(false)

	_test_compact_overhead_plates()
	_test_projected_plate_footprint()
	_test_no_duplicate_target_bar()
	_test_legacy_lower_left_removed()
	_test_large_centered_deck()
	_test_live_deck_rendering()
	_test_card_inspection()
	_test_narrow_browser_geometry()
	await _test_reborn_cockpit_architecture()
	await _capture_reborn_hud()

	print("TEMPLE_HORDE_HUD_REDESIGN_DONE profile=%s checks=%d fails=%d" % [
		"phone" if _phone else "hd", _checks, _fails])
	_game.queue_free()
	_game = null
	await _frames(3)
	get_tree().quit(1 if _fails > 0 else 0)


func _test_reborn_cockpit_architecture() -> void:
	print("--- reborn cockpit architecture ---")
	var score := _game.get("_score_plate") as Control
	var wave := _game.get("_wave_plate") as Control
	var settings := _game.get("_settings_button") as Button
	var camera_button := _game.get("_camera_button") as Button
	var exit_button := _game.get("_exit_button") as Button
	var utility := _game.get("_utility_rail") as Control
	var controls := _game.get("_controls_overlay") as Control
	_ok(score != null and score.name == "RunTelemetry"
		and wave != null and wave.name == "ChamberCommand",
		"run telemetry and chamber command replace the old matched top plates")
	_ok(settings != null and settings.is_visible_in_tree() and settings.text == "GUIDE"
		and camera_button != null and camera_button.is_visible_in_tree()
		and exit_button != null and exit_button.is_visible_in_tree() and utility != null,
		"Guide, Tactical, and Exit are visible dedicated utility controls")
	_ok(settings != null and camera_button != null and exit_button != null
		and settings.pressed.is_connected(Callable(_game, "_toggle_reborn_controls"))
		and camera_button.pressed.is_connected(Callable(_game, "_toggle_zoom"))
		and exit_button.pressed.is_connected(Callable(_game, "_request_exit")),
		"utility buttons connect to their real guide, camera, and exit actions")
	_ok(controls != null and controls.name == "CombatGuide",
		"the cockpit owns an optional first-entry controls guide")
	if settings != null and controls != null:
		settings.emit_signal("pressed")
		_ok(controls.is_visible_in_tree(),
			"the Guide control opens the readable combat guide")
		settings.emit_signal("pressed")
		_ok(not controls.is_visible_in_tree(), "pressing Guide again closes the optional overlay")
	if camera_button != null:
		var prior_camera := bool(_game.get("_zoom_tactical"))
		camera_button.emit_signal("pressed")
		_game.call("_refresh_hud", true)
		_ok(bool(_game.get("_zoom_tactical")) != prior_camera,
			"Tactical control actually switches camera mode")
		_test_camera_caption(camera_button)
		camera_button.emit_signal("pressed")
		_game.call("_refresh_hud", true)
		_ok(bool(_game.get("_zoom_tactical")) == prior_camera,
			"Tactical control returns to the initial camera mode")
		_test_camera_caption(camera_button)
	var rects := _game.call("touch_rects") as Dictionary
	var utility_clear := rects.has("settings") and rects.has("camera") and rects.has("exit")
	if utility_clear:
		utility_clear = not (rects["settings"] as Rect2).intersects(rects["camera"] as Rect2) \
			and not (rects["camera"] as Rect2).intersects(rects["exit"] as Rect2)
	_ok(utility_clear, "all three utility targets have independent hit geometry")
	var utilities_borderless := true
	for button in [settings, camera_button, exit_button]:
		if button == null:
			utilities_borderless = false
			continue
		for style_name in ["normal", "hover", "pressed"]:
			var style := button.get_theme_stylebox(style_name) as StyleBoxFlat
			utilities_borderless = utilities_borderless and style != null \
				and style.border_width_left == 0 and style.border_width_right == 0 \
				and style.border_width_top == 0 and style.border_width_bottom == 0
	_ok(utilities_borderless, "utility controls use readable fills without extra outline frames")
	var quiet_panels := true
	for panel in [score, wave, _game.get("_plinth"), _game.get("_card_preview")]:
		quiet_panels = quiet_panels and panel != null \
			and panel.get_theme_stylebox("panel") is StyleBoxEmpty
	_ok(quiet_panels, "persistent HUD and full-card preview containers have no decorative panel border")
	if _phone and utility_clear:
		var touch_sized := true
		for key in ["settings", "camera", "exit"]:
			var button := {"settings": settings, "camera": _game.get("_camera_button"),
				"exit": _game.get("_exit_button")}[key] as Control
			var rect := _screen_rect(button)
			touch_sized = touch_sized and rect.size.x >= 44.0 and rect.size.y >= 44.0
		_ok(touch_sized,
			"every phone utility instrument is at least44 %s pixels" % (
				"modeled CSS" if _headless else "native physical"))
		var wave_label := _game.get("_wave_label") as Label
		var surge_label := _game.get("_pack_dots") as Label
		var score_label := _game.get("_score_label") as Label
		var status_label := _game.get("_run_status_label") as Label
		var physical_scale := _presentation_scale()
		_ok(float(wave_label.get_theme_font_size("font_size")) * physical_scale >= 12.0
			and float(surge_label.get_theme_font_size("font_size")) * physical_scale >= 10.0
			and float(score_label.get_theme_font_size("font_size")) * physical_scale >= 10.0,
			"phone chamber title is at least12px and secondary telemetry at least10px (%s)" % (
				"modeled CSS" if _headless else "native physical"))
		_ok(_label_fits(wave_label) and _label_fits(score_label) and _label_fits(status_label),
			"phone wave and run-score copy fit without ellipsis or clipping")
	var clean_cards := true
	var external_feedback := true
	for value in _game.get("_card_hud") as Array:
		var ui := value as Dictionary
		var holder := ui.get("holder") as Control
		var slot := ui.get("slot") as Control
		var panel := ui.get("panel") as Control
		var recovery := ui.get("recovery") as ProgressBar
		var hint := ui.get("hint") as Label
		var art := ui.get("art") as TextureRect
		var button := ui.get("button") as TextureButton
		var state := ui.get("state") as Control
		var cost_icon := ui.get("cost_icon") as TextureRect
		clean_cards = clean_cards and holder != null and slot != null and panel != null \
			and art != null and button != null and panel.get_parent() == slot \
			and art.get_parent() == panel and panel.get_child_count() == 1 \
			and art.get_child_count() == 0 and panel.get_theme_stylebox("panel") is StyleBoxEmpty \
			and art.texture != null and art.texture == button.texture_normal \
			and art.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED \
			and button.get_parent() == slot and is_zero_approx(button.self_modulate.a) \
			and art.mouse_filter == Control.MOUSE_FILTER_IGNORE
		external_feedback = external_feedback and holder != null and panel != null \
			and recovery != null and hint != null and state != null and cost_icon != null \
			and recovery.get_parent() == holder and state.get_parent() == holder \
			and hint.get_parent() == state and cost_icon.get_parent() == state \
			and cost_icon.texture != null and not panel.is_ancestor_of(recovery) \
			and not panel.is_ancestor_of(state)
	_ok(clean_cards,
		"each animated card face is one unmarked aspect-centered image, with transparent fixed input outside it")
	_ok(external_feedback,
		"recovery, cost icon and input feedback belong to a separate footer outside every card face")
	var cards := _game.get("_card_hud") as Array
	if not cards.is_empty():
		_game.call("_reset_card_draws", true)
		var ui := cards[0] as Dictionary
		var button := ui["button"] as Control
		var face := ui["panel"] as Control
		var input_before := button.get_global_rect()
		var face_before := face.get_global_rect()
		_game.call("_on_card_preview_hover", 0, true)
		await get_tree().create_timer(0.24).timeout
		_ok(button.get_global_rect().is_equal_approx(input_before),
			"hover animation never shifts the actual card hit rectangle")
		if _phone:
			_ok(face.get_global_rect().is_equal_approx(face_before),
				"synthetic phone hover leaves card geometry motionless")
		else:
			_ok(face.scale.x > 1.0 and face.position.y < 0.0,
				"desktop hover draws the actual card upward and enlarges it")
		_game.call("_on_card_preview_hover", 0, false)
		await get_tree().create_timer(0.24).timeout
		_ok(face.get_global_rect().is_equal_approx(face_before)
			and button.get_global_rect().is_equal_approx(input_before),
			"hover exit restores the card without layout or input drift")


func _test_camera_caption(button: Button) -> void:
	var wide := bool(_game.get("_zoom_tactical"))
	var expected := (("CLOSE\nVIEW" if wide else "TACTIC\nWIDE") if _phone
		else ("CLOSE VIEW\nV · RETURN" if wide else "TACTICAL\nV · WIDE"))
	print("TACTICAL_CAPTION wide=%s text=%s" % [wide, button.text.replace("\n", " / ")])
	_ok(button.text == expected
		and button.tooltip_text == ("Return to close camera (V / controller right stick)"
			if wide else "See the whole floor (V / controller right stick)"),
		"after the actual toggle and normal HUD refresh, the %s caption offers %s" % [
			"wide-view" if wide else "close-view", "CLOSE / RETURN" if wide else "TACTIC / WIDE"])


func _capture_reborn_hud() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var controls := _game.get("_controls_overlay") as Control
	if controls != null:
		controls.visible = false
	await _frames(2)
	# A frozen or obscured native QA window may stop frame_post_draw indefinitely.
	# Match the existing cast-QA capture helper without changing game behavior.
	RenderingServer.force_draw()
	RenderingServer.force_draw()
	var profile := "phone" if _phone else "hd"
	var run_prefix := OS.get_environment("CHIK_QA_CAPTURE_PREFIX").validate_filename()
	if not run_prefix.is_empty(): run_prefix += "_"
	var path := "/private/tmp/wicked_reborn_hud_%s%s.png" % [run_prefix, profile]
	var error := get_viewport().get_texture().get_image().save_png(path)
	_ok(error == OK, "the native %s cockpit screenshot is captured" % profile)
	if not _phone:
		_game.call("_on_card_preview_hover", 0, true)
		await _frames(2)
		RenderingServer.force_draw()
		RenderingServer.force_draw()
		var preview_error := get_viewport().get_texture().get_image().save_png(
			"/private/tmp/wicked_reborn_hud_%spreview_hd.png" % run_prefix)
		_ok(preview_error == OK, "the lower-left full-card inspection screenshot is captured")
		_game.call("_on_card_preview_hover", 0, false)


func _test_compact_overhead_plates() -> void:
	print("--- compact world-following health plates ---")
	var report := _game.call("debug_combat_nameplates") as Dictionary
	var bar_size := Vector2i(report.get("bar_size", Vector2i.ZERO))
	_ok(bar_size.x > 0 and bar_size.y > 0
		and bar_size.x <= MAX_PLATE_BAR.x and bar_size.y <= MAX_PLATE_BAR.y,
		"overhead HP tracks are compact (at most %dx%d source pixels)" % [
			MAX_PLATE_BAR.x, MAX_PLATE_BAR.y])
	var player_plate := _game.get("_player_nameplate") as Dictionary
	var player_label := player_plate.get("label") as Label3D
	var player_back := player_plate.get("back") as Sprite3D
	var enemy := _first_active_enemy()
	var enemy_plate := enemy.get("nameplate", {}) as Dictionary
	var enemy_label := enemy_plate.get("label") as Label3D
	var enemy_back := enemy_plate.get("back") as Sprite3D
	var max_font := 16 if _phone else 14
	_ok(player_label != null and enemy_label != null
		and player_label.font_size <= max_font and enemy_label.font_size <= max_font,
		"player and Corruptimon overhead names use compact %s typography" % (
			"phone" if _phone else "HD"))
	_ok(player_back != null and enemy_back != null
		and player_back.fixed_size and enemy_back.fixed_size
		and player_back.scale.x <= 1.10 and enemy_back.scale.x <= 1.10,
		"compact fixed-size bars cannot expand across the arena with world distance")
	_ok(player_label != null and enemy_label != null
		and not String(player_label.text).contains("\n")
		and not String(enemy_label.text).contains("\n")
		and not String(player_label.text).contains("/")
		and not String(enemy_label.text).contains("/"),
		"each overhead plate is a concise name-only line above its bar")


func _test_projected_plate_footprint() -> void:
	print("--- live world / camera-space plate footprint ---")
	var camera := _game.get("_cam") as Camera3D
	var enemy := _first_active_enemy()
	var plates := [_game.get("_player_nameplate") as Dictionary,
		enemy.get("nameplate", {}) as Dictionary]
	var valid := camera != null and plates.size() == 2 and not (plates[1] as Dictionary).is_empty()
	_ok(valid, "a live camera, player plate, and Corruptimon plate are available for projection")
	if not valid:
		return
	var projected_ok := true
	var world_ok := true
	for plate_value in plates:
		var measurement := _plate_projection(plate_value as Dictionary, camera)
		var bar := measurement.get("bar", Rect2()) as Rect2
		var whole := measurement.get("whole", Rect2()) as Rect2
		var world := measurement.get("bar_world", Vector2.ZERO) as Vector2
		print("plate footprint bar_screen=%s whole_screen=%s bar_world=%s" % [
			bar.size, whole.size, world])
		projected_ok = projected_ok and bar.size.x > 0.0 and bar.size.y > 0.0 \
			and bar.size.x <= MAX_FIXED_BAR_SCREEN.x \
			and bar.size.y <= MAX_FIXED_BAR_SCREEN.y \
			and whole.size.x <= MAX_FIXED_PLATE_SCREEN.x \
			and whole.size.y <= MAX_FIXED_PLATE_SCREEN.y
		world_ok = world_ok and world.x > 0.0 and world.y > 0.0 \
			and world.x <= MAX_BAR_WORLD.x and world.y <= MAX_BAR_WORLD.y
	_ok(projected_ok,
		"live fixed-size nameplates project to at most %.0fx%.0f px (bar %.0fx%.0f)" % [
			MAX_FIXED_PLATE_SCREEN.x, MAX_FIXED_PLATE_SCREEN.y,
			MAX_FIXED_BAR_SCREEN.x, MAX_FIXED_BAR_SCREEN.y])
	_ok(world_ok,
		"live bar quads stay within the compact %.2fx%.2fm authored footprint" % [
			MAX_BAR_WORLD.x, MAX_BAR_WORLD.y])


func _test_no_duplicate_target_bar() -> void:
	print("--- authoritative overhead bars, no duplicate target HUD ---")
	var holder := _game.get("_target_holder") as Control
	_ok(_control_hidden_or_absent(holder), "the duplicate top target health panel is hidden or absent")
	var enemy := _first_active_enemy()
	_ok(not enemy.is_empty(), "a real active Corruptimon is available to engage")
	if enemy.is_empty(): return
	_game.set("_hud_target_eid", int(enemy["eid"]))
	_game.call("_refresh_hud", true)
	_ok(_control_hidden_or_absent(holder),
		"engaging a live Corruptimon never revives the duplicate target panel")
	var plate := enemy.get("nameplate", {}) as Dictionary
	var back := plate.get("back") as Sprite3D
	_ok(back != null and back.is_visible_in_tree(),
		"the engaged Corruptimon keeps its world-following overhead health track")


func _test_legacy_lower_left_removed() -> void:
	print("--- no duplicate lower-left vitality panel ---")
	var no_legacy := _control_hidden_or_absent(_game.get("_vitality")) \
		and _control_hidden_or_absent(_game.get("_unit_label")) \
		and _control_hidden_or_absent(_game.get("_rarity_label")) \
		and _control_hidden_or_absent(_game.get("_hp_bar")) \
		and _control_hidden_or_absent(_game.get("_hp_label"))
	_ok(no_legacy,
		"the old lower-left health/name/rarity/details block is hidden or absent")
	var metrics := _game.call("debug_hud_metrics") as Dictionary
	var persistent := metrics.get("persistent", {}) as Dictionary
	_ok(not persistent.has("vitality"),
		"HUD coverage metrics no longer reserve a lower-left vitality rectangle")


func _test_large_centered_deck() -> void:
	print("--- enlarged bottom-centre command deck ---")
	var viewport_size := get_viewport().get_visible_rect().size
	var rects := _game.call("touch_rects") as Dictionary
	var required := rects.has("card_0") and rects.has("card_1") and rects.has("card_2")
	_ok(required, "all three visible ability-card rectangles are published")
	if not required:
		return
	var c0 := rects["card_0"] as Rect2
	var c1 := rects["card_1"] as Rect2
	var c2 := rects["card_2"] as Rect2
	var minimum := PHONE_CARD_MIN if _phone else HD_CARD_MIN
	var large := true
	for rect in [c0, c1, c2]:
		large = large and rect.size.x + 0.01 >= minimum.x \
			and rect.size.y + 0.01 >= minimum.y
	_ok(large, "the %s deck enlarges every card to at least %.0fx%.0f" % [
		"phone" if _phone else "HD", minimum.x, minimum.y])
	var hand := c0.merge(c1).merge(c2)
	_ok(absf(hand.get_center().x - viewport_size.x * 0.5) <= 2.0,
		"the enlarged three-card hand remains exactly centred")
	_ok(hand.end.y <= viewport_size.y + 0.01
		and viewport_size.y - hand.end.y <= (64.0 if _phone else 72.0),
		"the command hand remains anchored to the bottom action lane")
	var plinth := _game.get("_plinth") as Control
	_ok(plinth != null and plinth.visible
		and absf((plinth.position.x + plinth.size.x * 0.5) - viewport_size.x * 0.5) <= 2.0,
		"the carved deck plinth grows around the cards without drifting off-centre")
	if not _phone and plinth != null:
		var plinth_screen := _screen_rect(plinth)
		var player_norm := _game.call("_player_screen_norm") as Vector2
		var player_chest_y := player_norm.y * viewport_size.y
		var presentation_scale := _presentation_scale()
		var presented_size := viewport_size * presentation_scale
		var reference_scale := HD_REFERENCE_SIZE.y / presented_size.y
		var body_gap := (plinth.get_global_rect().position.y - player_chest_y) * presentation_scale
		print("HD_DOCK_SCREEN rect=%s presented_viewport=%s player_chest_logical=%.1f body_gap=%.2f reference720_dock=%.2f reference720_gap=%.2f" % [
			plinth_screen, presented_size, player_chest_y, body_gap,
			plinth_screen.size.y * reference_scale, body_gap * reference_scale])
		if not _headless:
			var reference_run := OS.get_environment("CHIK_QA_HD_REFERENCE") == "1"
			var expected_size := HD_REFERENCE_SIZE if reference_run else Vector2(1600.0, 900.0)
			_ok(presented_size.is_equal_approx(expected_size)
				and Vector2(get_window().size).is_equal_approx(expected_size),
				"native HD gate uses the requested true%s physical window and presented viewport" % expected_size)
			if reference_run:
				_ok(plinth_screen.size.y <= HD_REFERENCE_DOCK_MAX,
					"the true1280x720 native command dock stays at or below224 absolute physical pixels")
		_ok(plinth_screen.size.y * reference_scale <= HD_REFERENCE_DOCK_MAX,
			"the HD dock stays at or below224 reference720 pixels, normalized from %s geometry" % (
				"modeled CSS" if _headless else "actual native physical"))
		_ok(player_norm.y >= 0.0 and body_gap * reference_scale >= HD_REFERENCE_BODY_GAP_MIN,
			"the dock-to-Chikimon body gap stays at least57.6 reference720 pixels after the same normalization")


func _test_live_deck_rendering() -> void:
	print("--- live card-control rendering ---")
	var cards := _game.get("_card_hud") as Array
	var all_visible := cards.size() == 3
	var all_textured := cards.size() == 3
	var all_sized := cards.size() == 3
	for value in cards:
		var ui := value as Dictionary
		var holder := ui.get("holder") as Control
		var panel := ui.get("panel") as Control
		var button := ui.get("button") as TextureButton
		all_visible = all_visible and holder != null and panel != null and button != null \
			and holder.is_visible_in_tree() and panel.is_visible_in_tree() \
			and button.is_visible_in_tree()
		all_textured = all_textured and button != null and button.texture_normal != null
		all_sized = all_sized and panel != null and button != null \
			and panel.size.x >= (PHONE_CARD_MIN.x if _phone else HD_CARD_MIN.x) \
			and panel.size.y >= (PHONE_CARD_MIN.y if _phone else HD_CARD_MIN.y) \
			and button.size.x >= panel.size.x - 12.0 and button.size.y >= panel.size.y - 12.0
		if panel != null and button != null:
			print("live card panel=%s button=%s visible=%s texture=%s" % [
				panel.size, button.size, button.is_visible_in_tree(), button.texture_normal != null])
	_ok(all_visible, "all three runtime card controls are visible in the live HUD tree")
	_ok(all_textured, "all three runtime card controls carry their authored card texture")
	_ok(all_sized, "the rendered card Controls fill the published enlarged card rectangles")
	var plinth := _game.get("_plinth") as Control
	var accent := _game.get("_deck_accent") as Control
	var stack := plinth.find_child("CommandDeck", false, false) as Control if plinth != null else null
	_ok(plinth != null and accent != null and stack != null
		and accent.get_index() < stack.get_index(),
		"the decorative plinth layer renders behind, never over, the interactive card stack")


func _test_card_inspection() -> void:
	print("--- lower-left full-card hover inspection ---")
	var preview := _game.get("_card_preview") as Control
	var art := _game.get("_card_preview_art") as TextureRect
	_ok(preview != null and art != null, "the deck owns a dedicated full-card inspection panel")
	if preview == null or art == null:
		return
	_game.call("_on_card_preview_hover", 0, true)
	if _phone:
		_ok(not preview.visible or _phone_preview_is_safe(preview),
			"a phone hover preview is suppressed or leaves every action target clear")
		_game.call("_on_card_preview_hover", 0, false)
		_game.call("_on_card_preview_focus", 0, true)
		if preview.visible:
			_ok(_phone_preview_is_safe(preview),
				"controller focus preview is bounded and leaves every phone action target clear")
		else:
			_ok(true, "phone may suppress the optional controller preview to preserve play space")
		_game.call("_on_card_preview_focus", 0, false)
		return

	_ok(preview.visible and art.texture != null,
		"hovering a desktop ability immediately reveals its enlarged card")
	var viewport_size := get_viewport().get_visible_rect().size
	var preview_rect := Rect2(preview.position, preview.size)
	var rects := _game.call("touch_rects") as Dictionary
	var card0 := rects["card_0"] as Rect2
	_ok(preview_rect.position.x <= 32.0
		and viewport_size.y - preview_rect.end.y >= -0.01
		and viewport_size.y - preview_rect.end.y <= 24.0,
		"the hover card is popped out at the lower-left screen edge")
	_ok(preview_rect.size.x >= 240.0 and preview_rect.size.y >= 360.0
		and is_equal_approx(preview_rect.size.y / preview_rect.size.x, 1.5),
		"desktop inspection is an enlarged pure2:3 card of at least240x360, without the removed details footer")
	_ok(preview_rect.end.x + 12.0 <= card0.position.x,
		"the lower-left preview never covers the centred command deck")
	_ok(art.size.x >= card0.size.x * 1.20 and art.size.y >= card0.size.y * 1.20,
		"the inspection artwork is materially larger than the playable deck card")
	_ok(art.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
		"the enlarged card uses keep-aspect centring rather than a fill crop")

	var slots := _game.get("_card_slots") as Array
	var slot := int(slots[0]) if not slots.is_empty() else -1
	var raw := CardArt.texture("firix", slot) if slot >= 0 else null
	var regions := _game.call("debug_card_regions", "firix", slot, raw.get_size()) as Dictionary \
		if raw != null else {}
	var desktop_region := regions.get("desktop", Rect2()) as Rect2
	_ok(raw != null and not desktop_region.size.is_zero_approx()
		and _texture_region_size(art.texture).is_equal_approx(desktop_region.size),
		"hover inspection uses the full trimmed desktop card, never the phone icon crop")
	_game.call("_on_card_preview_hover", 0, false)
	_ok(not preview.visible, "leaving the card closes the transient preview")


func _test_narrow_browser_geometry() -> void:
	print("--- narrow 903x797 in-app-browser geometry ---")
	# The browser panel is desktop input with a narrow canvas, not the square-card phone layout.
	# Exercise that branch directly so the normal 1600x900 test cannot conceal width regressions.
	var size := Vector2(903.0, 797.0)
	var rects := _game.call("_touch_rects_for", size, false) as Dictionary
	var wave := _game.call("_wave_rect_for", size, false, rects) as Rect2
	var score := _game.call("_score_rect_for", size, false) as Rect2
	var plinth := _game.call("_plinth_rect", rects, false) as Rect2
	var camera := rects.get("camera", Rect2()) as Rect2
	var exit := rects.get("exit", Rect2()) as Rect2
	var cards := (rects["card_0"] as Rect2).merge(rects["card_1"] as Rect2) \
		.merge(rects["card_2"] as Rect2)
	_ok(not wave.intersects(score) and not wave.intersects(camera) and not wave.intersects(exit),
		"the narrow wave crown leaves independent score and Tactical/Exit lanes")
	_ok(Rect2(Vector2.ZERO, size).encloses(wave)
		and Rect2(Vector2.ZERO, size).encloses(score)
		and Rect2(Vector2.ZERO, size).encloses(plinth)
		and Rect2(Vector2.ZERO, size).encloses(camera)
		and Rect2(Vector2.ZERO, size).encloses(exit),
		"all persistent narrow-browser plates stay wholly inside 903x797")
	_ok(absf(cards.get_center().x - size.x * 0.5) <= 2.0
		and (rects["card_0"] as Rect2).size.x >= HD_CARD_MIN.x
		and (rects["card_0"] as Rect2).size.y >= HD_CARD_MIN.y,
		"the 903px deck remains centred with full-size portrait cards")
	var lower_left_gutter := plinth.position.x - 44.0
	_ok(lower_left_gutter >= 160.0,
		"the narrow layout preserves a usable lower-left full-card inspection gutter")
