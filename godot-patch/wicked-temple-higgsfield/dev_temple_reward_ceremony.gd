extends Node
# Deterministic receipt, circular-wheel, art-safety and responsive-layout regression.

const Reward := preload("res://TempleReward.gd")
const Ceremony2D := preload("res://TempleRewardCeremony.gd")
const HDStruct := preload("res://HDStruct.gd")

var fails := 0


func ok(condition: bool, message: String) -> void:
	print(("ok:   " if condition else "FAIL: ") + message)
	if not condition:
		fails += 1


func _frames(count: int = 2) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _ready() -> void:
	get_window().size = Vector2i(900, 680)
	await _frames()
	var expected_paths := {
		"golden_chikifish": "res://fish_ico_golden_chikifish.png",
		"crystal_koi": "res://fish_ico_crystal_koi.png",
		"mystic_eel": "res://fish_ico_mystic_eel.png",
		"rainbow_fish": "res://fish_ico_rainbow_fish.png",
		"normal": "res://egg_normal.png",
		"legendary": "res://egg_legendary.png",
		"mount": "res://egg_chikimount.png",
		"meme": "res://egg_meme.png",
	}
	var seen := {}
	for i in range(Reward.SANDBOX_SEQUENCE.size()):
		var receipt: Dictionary = Reward.sandbox_preview_at(i)
		var data: Dictionary = Ceremony2D.display_data(receipt)
		var item := String(data.get("item_id", ""))
		seen[item] = true
		ok(bool(data.get("ok", false)) and int(data.get("quantity", 0)) == 1,
			"preview %d produces one exact reward receipt" % i)
		ok(String(data.get("art_path", "")) == String(expected_paths.get(item, "")),
			"%s uses its exact authored transparent PNG" % item)
		ok(String(data.get("rarity", "")) != ""
			and float(data.get("top_level_chance_percent", 0.0)) in [80.0, 20.0]
			and float(data.get("chance_within_category_percent", 0.0)) > 0.0
			and float(data.get("overall_chance_percent", 0.0)) > 0.0,
			"%s exposes category, conditional and overall odds" % item)
		ok(_transparent_corners(String(data.get("art_path", ""))),
			"%s art has transparent corners and no white rectangle" % item)

		var probe := Ceremony2D.new()
		probe.size = Vector2(820.0, 400.0)
		add_child(probe)
		ok(probe.begin(receipt, true), "%s builds the new reward ceremony" % item)
		await _frames()
		var before: Dictionary = probe.reward_data()
		var wheel := probe.find_child("SettledRewardWheel", true, false)
		var slots: Array = wheel.call("category_slots") if wheel != null else []
		ok(slots.size() == 10 and slots.count("fish") == 8 and slots.count("egg") == 2,
			"%s wheel contains eight fish and two egg wedges" % item)
		probe.reveal()
		await _frames()
		var state: Dictionary = probe.wheel_debug_state()
		var expected_category := "fish" if String(data.get("reward_type", "")) == "ffish" else "egg"
		ok(not probe.animation_running() and bool(state.get("landed", false)),
			"%s reduced-motion reveal lands synchronously" % item)
		ok(String(state.get("settled_key", "")) == String(data.get("reward_key", ""))
			and String(state.get("settled_category", "")) == expected_category
			and String(state.get("target_wedge_category", "")) == expected_category
			and String(state.get("art_path", "")) == String(data.get("art_path", "")),
			"%s lands only its settled category and exact receipt art" % item)
		ok(int(state.get("wedge_count", 0)) == 10
			and is_equal_approx(float(state.get("equal_wedge_sweep_radians", 0.0)), TAU / 10.0)
			and is_equal_approx(float(state.get("fish_area_percent", 0.0)), 80.0)
			and is_equal_approx(float(state.get("egg_area_percent", 0.0)), 20.0),
			"%s circular area truthfully communicates the 80/20 split" % item)
		ok(float(state.get("pointer_alignment_error_radians", 1.0)) < 0.0001,
			"%s exact category wedge settles beneath the fixed pointer" % item)
		ok(probe.reward_data() == before and probe.target_art_path() == String(data.get("art_path", "")),
			"%s presentation cannot reroll or rewrite receipt truth" % item)
		ok(probe.art_is_safe_fit(),
			"%s complete asset is padded and aspect-centered" % item)
		ok(int(state.get("fish_category_art_count", 0)) == 4
			and int(state.get("egg_category_art_count", 0)) == 4,
			"%s wheel loads all authentic fish and egg source art" % item)
		probe.free()
		await _frames(1)
	ok(seen.size() == 8, "the ceremony resolves all four fish and all four egg kinds")

	var bg := ColorRect.new()
	bg.color = Color("071117")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var ceremony := Ceremony2D.new()
	ceremony.position = Vector2(50, 120)
	ceremony.size = Vector2(800, 400)
	add_child(ceremony)
	var rainbow: Dictionary = Reward.roll_reward("C", 0, 9999, true)
	ok(ceremony.begin(rainbow, false), "animated exact receipt builds")
	await _frames(3)
	var pre_min := ceremony.get_combined_minimum_size()
	ok(not ceremony.is_revealed() and ceremony.target_art_path() == expected_paths["rainbow_fish"],
		"pre-reveal keeps the exact landed art hidden but fixed")
	ok(_has_visible_button(ceremony, "SPIN AND REVEAL"),
		"ceremony exposes its explicit player-controlled reveal")
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(
			"/private/tmp/reborn_reward_ceremony_pre.png")
	var settled_before: Dictionary = ceremony.reward_data()
	ceremony.reveal()
	ok(ceremony.is_revealed() and ceremony.animation_running(),
		"circular wheel starts without changing the public reveal contract")
	ok(_has_visible_button(ceremony, "SKIP"),
		"animated ceremony exposes an explicit skip control")
	var live_wheel := ceremony.find_child("SettledRewardWheel", true, false)
	var motion_a: Dictionary = ceremony.wheel_debug_state()
	if live_wheel != null:
		live_wheel.call("_process", 0.18)
	var motion_b: Dictionary = ceremony.wheel_debug_state()
	ok(float(motion_b.get("spin_progress", 0.0)) > float(motion_a.get("spin_progress", -1.0))
		and float(motion_b.get("wheel_rotation_radians", 0.0))
		> float(motion_a.get("wheel_rotation_radians", -1.0))
		and float(motion_b.get("spin_duration_seconds", 9.0)) <= 2.45,
		"wheel advances monotonically through a bounded decelerating spin")
	ceremony.skip_animation()
	await get_tree().create_timer(0.50).timeout
	await _frames(2)
	var settled_after: Dictionary = ceremony.reward_data()
	var final_state: Dictionary = ceremony.wheel_debug_state()
	ok(not ceremony.animation_running() and bool(final_state.get("landed", false))
		and ceremony.art_is_safe_fit(),
		"skip lands the complete PNG immediately and safely")
	ok(settled_after == settled_before and String(final_state.get("settled_key", ""))
		== String(settled_before.get("reward_key", "")),
		"skip cannot alter the authoritative settled reward")
	ok(_has_label(ceremony, "PRACTICE REWARD / NOT SAVED"),
		"sandbox ceremony keeps one compact not-saved badge after landing")

	var expected_compact := HDStruct.lite_world() or HDStruct.phone_world()
	var stage := ceremony.find_child("VictoryReceiptStage", true, false) as Control
	var wheel := ceremony.find_child("SettledRewardWheel", true, false) as Control
	var art := ceremony.find_child("SettledRewardArt", true, false) as Control
	var winner := ceremony.find_child("LandedRewardDetails", true, false) as Control
	var stage_rect := stage.get_global_rect() if stage != null else Rect2()
	var wheel_rect := wheel.get_global_rect() if wheel != null else Rect2()
	var art_rect := art.get_global_rect() if art != null else Rect2()
	var winner_rect := winner.get_global_rect() if winner != null else Rect2()
	var geometry_ok := stage != null and wheel != null and art != null and winner != null \
		and stage_rect.encloses(wheel_rect) and stage_rect.encloses(art_rect) \
		and stage_rect.encloses(winner_rect) and not wheel_rect.intersects(winner_rect)
	ok(geometry_ok, "landed prize art, wheel and receipt occupy distinct contained regions")
	ok(bool(final_state.get("compact", not expected_compact)) == expected_compact
		and Vector2(final_state.get("minimum_size", Vector2.ZERO)).y
		>= 400.0,
		"ceremony gives the centered wheel the available display height")
	var height_limit := 650.0
	ok(pre_min.y <= height_limit and ceremony.get_combined_minimum_size().y <= height_limit,
		"pre-roll and landed ceremony remain in the result modal height budget")
	ok(absf(wheel_rect.get_center().x - stage_rect.get_center().x) < 1.0
		and wheel_rect.size.y >= stage_rect.size.y * 0.70,
		"the wheel is centered and occupies most of the ceremony")
	ok(ceremony.find_child("HonestCategoryOdds", true, false) == null
		and ceremony.find_child("CeremonyTitle", true, false) == null,
		"duplicate titles and boxed odds panels do not compete with the wheel")
	ok(bool(final_state.get("uses_authored_rim", false)),
		"circular wheel uses the authored obsidian, gold and cyan rim")
	ok(bool(final_state.get("uses_authored_radiance", false)),
		"landed reward uses the authored transparent victory radiance")
	ok(_ascii_safe_visible_copy(ceremony),
		"ceremony avoids unsupported decorative Unicode glyphs")
	ok(_transparent_corners("res://astra_fx/victory_radiance.png")
		and _transparent_corners("res://reborn_art/treasure_wheel_rim.png"),
		"authored ornament assets retain transparent open space")
	ok(not bool(Ceremony2D.display_data({}).get("ok", true)),
		"an empty receipt cannot produce a fake reward reveal")
	print("REBORN_CEREMONY_LAYOUT compact=%s pre=%s landed=%s wheel=%s art=%s winner=%s" % [
		expected_compact, pre_min, ceremony.get_combined_minimum_size(), wheel_rect, art_rect, winner_rect])
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(
			"/private/tmp/reborn_reward_ceremony_landed.png")
	print("TEMPLE_REWARD_CEREMONY_DONE fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _transparent_corners(path: String) -> bool:
	if path == "":
		return false
	var image: Image = null
	if ResourceLoader.exists(path):
		var texture := load(path) as Texture2D
		if texture != null:
			image = texture.get_image()
	else:
		image = Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return false
	var last := image.get_size() - Vector2i.ONE
	for point in [Vector2i.ZERO, Vector2i(last.x, 0), Vector2i(0, last.y), last]:
		if image.get_pixelv(point).a > 0.01:
			return false
	return true


func _has_label(root: Node, needle: String) -> bool:
	if root is Label and String((root as Label).text).find(needle) >= 0 \
		and (root as Label).is_visible_in_tree():
		return true
	for child in root.get_children():
		if _has_label(child, needle):
			return true
	return false


func _has_visible_button(root: Node, needle: String) -> bool:
	if root is Button and String((root as Button).text).find(needle) >= 0 \
		and (root as Button).is_visible_in_tree():
		return true
	for child in root.get_children():
		if _has_visible_button(child, needle):
			return true
	return false


func _ascii_safe_visible_copy(root: Node) -> bool:
	if root is Label and (root as Label).is_visible_in_tree():
		var value := String((root as Label).text)
		for bad in ["•", "×", "◆", "◇", "…", "»"]:
			if value.find(bad) >= 0:
				return false
	if root is Button and (root as Button).is_visible_in_tree():
		var value := String((root as Button).text)
		for bad in ["•", "×", "◆", "◇", "…", "»"]:
			if value.find(bad) >= 0:
				return false
	for child in root.get_children():
		if not _ascii_safe_visible_copy(child):
			return false
	return true
