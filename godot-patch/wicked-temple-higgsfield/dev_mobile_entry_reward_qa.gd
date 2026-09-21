extends Node
# Real entry/result builders; fixed offline fixture receipts only. Never opens/settles a run.
const TempleScript := preload("res://Temple.gd")
const ViewportAdapter := preload("res://TempleMobileViewport.gd")
class OfflineTemple extends TempleScript:
	var deploy_calls := 0
	var leave_calls := 0
	var reduced := true
	func _ready() -> void: pass
	func _horde_candidates() -> Array:
		return [{"uid":"fixture-firix", "species":"firix", "level":50},
			{"uid":"fixture-dragonos", "species":"dragonos", "level":50},
			{"uid":"fixture-rivaros", "species":"rivaros", "level":50}]
	func _has_offering() -> bool: return true
	func _asset_test_mode() -> bool: return true
	func _begin() -> void: deploy_calls += 1
	func close() -> void: leave_calls += 1
	func _reward_reduced_motion() -> bool: return reduced
var _temple: OfflineTemple
var _fails := 0
var _checks := 0
var _scale := 1.0
var _safe := Rect2()
var _source_hashes := {}
var _mobile := true
func _ok(value: bool, label: String) -> void:
	_checks += 1
	print(("ok: " if value else "FAIL: ") + label)
	if not value: _fails += 1
func _frames(n: int = 4) -> void:
	for _i in n: await get_tree().process_frame
func _all(node: Node, type: String) -> Array:
	var out: Array = []
	if node.is_class(type): out.append(node)
	for child in node.get_children(): out.append_array(_all(child, type))
	return out
func _bounds(c: Control) -> Rect2:
	var r := c.get_global_rect()
	return Rect2(r.position * _scale, r.size * _scale)
func _ready() -> void:
	for path in ["res://Temple.gd", "res://RebornDeployment.gd", "res://TempleRewardCeremony.gd",
			"res://TempleMobileViewport.gd", "res://TempleReward.gd", "res://TempleRewardWheel.gd",
			"res://dev_mobile_entry_reward_qa.gd"]:
		_source_hashes[path] = FileAccess.get_sha256(path)
	print("ENTRY_REWARD_SOURCE_BEGIN=" + JSON.stringify(_source_hashes))
	if OS.get_environment("CHIK_MOBILE_UI").is_empty(): OS.set_environment("CHIK_MOBILE_UI", "1")
	if OS.get_environment("CHIK_MOBILE_CSS").is_empty(): OS.set_environment("CHIK_MOBILE_CSS", "844x390")
	var dims := OS.get_environment("CHIK_MOBILE_CSS").split("x")
	var css := Vector2(float(dims[0]), float(dims[1]))
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	get_window().content_scale_size = Vector2i((css / 0.585).round())
	await _frames()
	var display := ViewportAdapter.sample(get_viewport())
	_mobile = bool(display["touch"])
	_scale = float(display["css_per_logical"])
	var edges := display["safe_insets"] as Vector4
	_safe = Rect2(edges.x, edges.y, css.x - edges.x - edges.z, css.y - edges.y - edges.w)
	print("ENTRY_REWARD_GEOMETRY css=%s logical=%s scale=%.6f native=%s" % [css,
		get_viewport().get_visible_rect().size, _scale, DisplayServer.get_name() != "headless"])
	_temple = OfflineTemple.new()
	add_child(_temple)
	_temple.visible = true
	_temple.set_process(false)
	for phase in ["intro", "done"]:
		_temple._phase = phase
		_temple._purified = 5
		_temple._loot_reward = {"reward_key":"normal_egg", "kind":"normal", "quantity":1, "sandbox_preview":true}
		_temple._build()
		await _frames(6)
		_check_screen(phase + "_initial")
		await _capture(phase + "_initial")
		if phase == "done":
			var ceremony := _temple._wheel as TempleRewardCeremony
			_ok(ceremony != null, "real settled result instantiates the existing reward ceremony")
			if ceremony != null:
				var before := ceremony.reward_data()
				ceremony.reveal()
				await _frames(4)
				_check_screen("done_revealed")
				_ok(ceremony.reward_data() == before and ceremony.art_is_safe_fit(),
					"reveal keeps the exact offline receipt and fully letterboxed authored reward image")
				await _capture("done_revealed")
	if _mobile: await _check_live_rotation(css)
	_ok(_temple.deploy_calls == 0 and _temple.leave_calls == 0,
		"layout/reveal checks never request entry, payment, grant or return")
	_temple.queue_free()
	await _frames(3)
	var source_unchanged := true
	for path in _source_hashes:
		source_unchanged = source_unchanged and FileAccess.get_sha256(path) == _source_hashes[path]
	_ok(source_unchanged, "production and fixture source hashes stay unchanged throughout the gate")
	print("ENTRY_REWARD_SOURCE_END=" + JSON.stringify(_source_hashes))
	print("MOBILE_ENTRY_REWARD_QA_DONE checks=%d failures=%d" % [_checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)

func _rotate_display(css: Vector2) -> void:
	OS.set_environment("CHIK_MOBILE_CSS", "%dx%d" % [int(css.x), int(css.y)])
	# Rotate notch/home edges with the fixture; they are display-owned, not game-authored data.
	var edges := OS.get_environment("CHIK_MOBILE_SAFE").split(",")
	if edges.size() == 4:
		OS.set_environment("CHIK_MOBILE_SAFE", "%s,%s,%s,%s" % [edges[3],edges[0],edges[1],edges[2]])
	if DisplayServer.get_name() != "headless": get_window().size = Vector2i(css)
	# Deliberately vary CSS/logical scale too: relayout must not retain the old fonts or hit sizes.
	get_window().content_scale_size = Vector2i((css / (0.42 if css.y > css.x else 0.72)).round())
	await _frames(8)
	var display := ViewportAdapter.sample(get_viewport())
	_scale = float(display["css_per_logical"])
	var edge := display["safe_insets"] as Vector4
	_safe = Rect2(edge.x, edge.y, css.x - edge.x - edge.z, css.y - edge.y - edge.w)

func _check_live_rotation(initial_css: Vector2) -> void:
	var other := Vector2(initial_css.y, initial_css.x)
	_temple._phase = "intro"
	_temple._horde_pick_uid = "fixture-rivaros"
	_temple._build()
	await _frames(4)
	await _rotate_display(other)
	_check_screen("rotated_intro")
	_ok(_temple._horde_pick_uid == "fixture-rivaros", "live entry rotation preserves the selected creature uid")
	_temple._phase = "done"
	_temple.reduced = false
	_temple._wheel_spun = false
	_temple._build()
	await _frames(4)
	var ceremony := _temple._wheel as TempleRewardCeremony
	var node_id := ceremony.get_instance_id()
	var wheel := ceremony._wheel
	var wheel_id := wheel.get_instance_id()
	var receipt := ceremony.reward_data()
	await _rotate_display(initial_css)
	_check_screen("rotated_unrevealed")
	_ok(_temple._wheel.get_instance_id() == node_id and ceremony._wheel.get_instance_id() == wheel_id
		and ceremony.reward_data() == receipt and not ceremony.is_revealed(),
		"pre-reveal rotation retains the identical ceremony, wheel and secured receipt without spinning")
	ceremony.reveal()
	wheel.set_process(false)
	wheel.call("_process", 0.23)
	var before := ceremony.wheel_debug_state()
	await _rotate_display(other)
	var during := ceremony.wheel_debug_state()
	_check_screen("rotated_midspin")
	_ok(ceremony.get_instance_id() == node_id and ceremony._wheel.get_instance_id() == wheel_id
		and ceremony.animation_running() and ceremony.reward_data() == receipt
		and is_equal_approx(float(before["spin_progress"]), float(during["spin_progress"]))
		and is_equal_approx(float(before["wheel_rotation_radians"]), float(during["wheel_rotation_radians"])),
		"mid-spin rotation preserves the same wheel's exact progress and angle, never restarting or rerolling")
	ceremony.skip_animation()
	await _frames(3)
	await _rotate_display(initial_css)
	_check_screen("rotated_revealed")
	_ok(ceremony.get_instance_id() == node_id and ceremony._wheel.get_instance_id() == wheel_id
		and ceremony.is_revealed() and not ceremony.animation_running()
		and ceremony.reward_data() == receipt and _temple._wheel_spun,
		"landed-result rotation preserves the identical settled wheel and one-reveal state")
func _check_screen(phase: String) -> void:
	var panel := _bounds(_temple._panel)
	print("ENTRY_REWARD_PANEL %s rect=%s min=%s" % [phase,panel,_temple._panel.get_combined_minimum_size()])
	_ok(_safe.grow(1.0).encloses(panel), phase + " panel stays within displayed safe area")
	var buttons_ok := true
	var count := 0
	for value in _all(_temple._panel, "Button"):
		var button := value as Button
		if not button.is_visible_in_tree(): continue
		# Picker strip may scroll horizontally; only current actions must stay directly reachable.
		if button.text in ["Firix", "Dragonos", "Rivaros"]: continue
		var rect := _bounds(button)
		print("ENTRY_REWARD_BUTTON %s %s rect=%s font_css=%.1f" % [phase,button.text,rect,
			float(button.get_theme_font_size("font_size")) * _scale])
		var minimum := 43.9 if _mobile else 1.0
		buttons_ok = buttons_ok and rect.size.y >= minimum and rect.size.x >= minimum \
			and _safe.grow(1.0).encloses(rect)
		count += 1
	_ok(count >= 2 and buttons_ok, phase + (" essential buttons are visible and at least44CSS pixels" if _mobile
		else " desktop actions remain visible and inside the viewport without forced touch sizing"))
	var type_ok := true
	for value in _all(_temple._panel, "Label"):
		var label := value as Label
		if not label.is_visible_in_tree() or label.text.is_empty(): continue
		var pixels := float(label.get_theme_font_size("font_size")) * _scale
		type_ok = type_ok and pixels >= (9.4 if _mobile else 5.0) and pixels <= (24.5 if _mobile else 40.0)
	_ok(type_ok, phase + (" visible mobile type stays proportional at approximately10–24CSS pixels" if _mobile
		else " desktop type remains in its original separate hierarchy"))
func _capture(key: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await _frames(2)
	RenderingServer.force_draw()
	RenderingServer.force_draw()
	var prefix := OS.get_environment("CHIK_QA_CAPTURE_PREFIX").validate_filename()
	var path := "/private/tmp/wicked_mobile_entry_reward_%s_%s.png" % [prefix,key]
	_ok(get_viewport().get_texture().get_image().save_png(path) == OK, "native capture " + key)
