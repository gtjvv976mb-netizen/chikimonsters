extends VBoxContainer
class_name TempleRewardCeremony
# Premium reveal UI for a reward that the authoritative Temple flow has already settled.
# This scene presents the receipt; it never rerolls, grants, saves, or mutates player economy.

signal revealed(reward_key: String)

const UISkin := preload("res://UISkin.gd")
const Reward := preload("res://TempleReward.gd")
const RewardWheel := preload("res://TempleRewardWheel.gd")
const HDStruct := preload("res://HDStruct.gd")
const MobileViewport := preload("res://TempleMobileViewport.gd")
const FONT_DISPLAY := preload("res://font_titan.ttf")
const FONT_BOLD := preload("res://ui_font_bold.ttf")
const FONT_BODY := preload("res://ui_font.ttf")
const WIN_SFX := preload("res://audio/sfx_win.wav")

const INK := Color("1a1024")
const DEEP_SLATE := Color("160e23")
const SLATE := Color("2b1c3b")
const IVORY := Color("fff0db")
const DIM_IVORY := Color("c8b8d4")
const CYAN := Color("91dceb")
const AMBER := Color("f4c775")
const CORAL := Color("f29485")
const VIOLET := Color("bd80ef")

const EGG_ART := {
	"normal": "res://egg_normal.png",
	"legendary": "res://egg_legendary.png",
	"mount": "res://egg_chikimount.png",
	"meme": "res://egg_meme.png",
}

var _data: Dictionary = {}
var _revealed := false
var _reduced := false
var _compact := false
var _mobile := false
var _css_unit := 1.0
var _stacked := false
var _wheel_side := 440.0
var _touch_height := 48.0
var _stage: PanelContainer = null
var _wheel: Control = null
var _pre_reveal: Control = null
var _winner: Control = null
var _reveal_button: Button = null
var _skip_button: Button = null
var _status: Label = null
var _audio: AudioStreamPlayer = null


static func _canonical_key(receipt: Dictionary) -> String:
	var key := String(receipt.get("reward_key", receipt.get("rewardKey", "")))
	if key == "chikimount_egg":
		return "mount_egg"
	if key == "meme_dynasty_egg":
		return "meme_egg"
	return key


static func display_data(receipt: Dictionary) -> Dictionary:
	var key := _canonical_key(receipt)
	if not Reward.REWARD_META.has(key):
		return {"ok": false, "error": "unknown_reward"}
	var meta := Reward.REWARD_META[key] as Dictionary
	var reward_type := String(receipt.get("reward_type", receipt.get("type", meta.get("reward_type", ""))))
	var item_id := String(receipt.get("item_id", ""))
	var item_meta: Dictionary = meta
	var art_path := String(meta.get("art_path", ""))
	var top_level := "Fantasy Fish" if key == "fantasy_fish" else "Egg"
	var top_chance := 80.0 if key == "fantasy_fish" else 20.0
	var within_chance := 0.0
	var overall_chance := 0.0

	if reward_type == "ffish" or key == "fantasy_fish":
		reward_type = "ffish"
		if item_id == "":
			item_id = String(receipt.get("species", receipt.get("sp", receipt.get("item", ""))))
		if not Reward.FISH_META.has(item_id) or item_id == "leviathan":
			return {"ok": false, "error": "unknown_fantasy_fish"}
		item_meta = Reward.FISH_META[item_id] as Dictionary
		var fish_index := Reward.FISH_KEYS.find(item_id)
		within_chance = float(Reward.FISH_WEIGHTS[fish_index]) / 100.0
		overall_chance = top_chance * within_chance / 100.0
		art_path = String(item_meta.get("art_path", ""))
	else:
		reward_type = "egg"
		var expected_kind := String(meta.get("egg_kind", ""))
		var received_kind := String(receipt.get("kind", receipt.get("sp", item_id)))
		if received_kind != "" and received_kind != expected_kind:
			return {"ok": false, "error": "egg_kind_mismatch"}
		item_id = expected_kind
		if not EGG_ART.has(item_id):
			return {"ok": false, "error": "unknown_egg"}
		art_path = String(EGG_ART[item_id])
		var reward_index := Reward.REWARD_KEYS.find(key)
		var weight := int(Reward.GUARANTEED_WEIGHTS[reward_index])
		within_chance = float(weight) * 100.0 / float(Reward.EGG_CATEGORY_WEIGHT)
		overall_chance = float(weight) / 100.0

	if art_path == "" or not ResourceLoader.exists(art_path):
		return {"ok": false, "error": "missing_reward_art", "art_path": art_path}
	var supplied_qty := int(receipt.get("quantity", receipt.get("qty", 1)))
	if supplied_qty != 1:
		return {"ok": false, "error": "quantity_must_be_one"}
	var sandbox := bool(receipt.get("sandbox_preview", false))
	return {
		"ok": true,
		"reward_key": key,
		"reward_type": reward_type,
		"item_id": item_id,
		"quantity": 1,
		"label": String(item_meta.get("label", meta.get("label", ""))),
		"rarity": String(item_meta.get("rarity", meta.get("rarity", ""))),
		"icon": String(item_meta.get("icon", meta.get("icon", ""))),
		"color": Color(String(item_meta.get("color_hex", meta.get("color_hex", "#EFB84D")))),
		"art_path": art_path,
		"top_level_category": top_level,
		"top_level_chance_percent": top_chance,
		"chance_within_category_percent": within_chance,
		"overall_chance_percent": overall_chance,
		"sandbox_preview": sandbox,
		"claim_status": "PREVIEW ONLY - NOT SAVED" if sandbox else "CLAIMED - EXACTLY 1 REWARD",
	}


func begin(receipt: Dictionary, reduced_motion: bool = false, available_size: Vector2 = Vector2.ZERO) -> bool:
	_data = display_data(receipt)
	if not bool(_data.get("ok", false)):
		return false
	for child in get_children():
		child.free()
	_revealed = false
	_reduced = reduced_motion
	_configure_geometry(available_size)
	_build_stage()
	return true


func _configure_geometry(available_size: Vector2) -> void:
	var display := MobileViewport.sample(get_viewport())
	_mobile = bool(display["touch"])
	_css_unit = 1.0 / maxf(0.05, float(display["css_per_logical"])) if _mobile else 1.0
	_compact = _mobile or UISkin.lite_world()
	_touch_height = ceilf(44.0 * _css_unit) + 1.0 if _mobile else 48.0
	# Temple attaches the ceremony before configuration so CSS/input identity uses its actual
	# viewport. Explicit available_size reserves the result header and navigation outside the wheel.
	var viewport_size := Vector2(DisplayServer.window_get_size())
	if viewport_size.x <= 1.0:
		viewport_size = Vector2(1280, 720)
	if get_viewport() != null:
		viewport_size = get_viewport().get_visible_rect().size
	if available_size.x > 1.0 and available_size.y > 1.0:
		viewport_size = available_size
	_stacked = true
	# One centered presentation at every size. Budget for the title, receipt and navigation first,
	# then give all remaining height to the actual wheel, not a statistics sidebar.
	_wheel_side = minf(520.0, maxf(224.0, viewport_size.y - (338.0 if HDStruct.phone_world() else 310.0)))
	_wheel_side = minf(_wheel_side, maxf(180.0, viewport_size.x - 72.0))
	if _mobile:
		_wheel_side = minf(420.0 * _css_unit,
			minf(viewport_size.y - 80.0 * _css_unit, viewport_size.x - 12.0 * _css_unit))
		_wheel_side = maxf(100.0 * _css_unit, _wheel_side)
	add_theme_constant_override("separation", 0)
	custom_minimum_size = Vector2(0.0, _wheel_side + (136.0 if HDStruct.phone_world() else 116.0))
	if _mobile:
		custom_minimum_size.y = _wheel_side + 80.0 * _css_unit
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func relayout(available_size: Vector2) -> void:
	# Resize the existing settled presentation, including the same running wheel node. Never call
	# begin/configure/start here: those would reset the spin, receipt or one-reveal contract.
	if _wheel == null or _stage == null:
		return
	_configure_geometry(available_size)
	_stage.custom_minimum_size.y = custom_minimum_size.y
	_wheel.custom_minimum_size = Vector2.ONE * _wheel_side
	for value in find_children("*", "Label", true, false):
		var label := value as Label
		if label.has_meta("ceremony_base_font"):
			label.add_theme_font_size_override("font_size",
				maxi(1, roundi(float(label.get_meta("ceremony_base_font")) * _css_unit)))
	_reveal_button.custom_minimum_size = Vector2(160.0 * _css_unit if _mobile else
		(176.0 if _compact else 220.0), _touch_height)
	_skip_button.custom_minimum_size = Vector2.ONE * _touch_height
	_style_button(_reveal_button, true)
	_style_button(_skip_button, false)
	_stage.queue_sort()
	queue_sort()


func _build_stage() -> void:
	_stage = PanelContainer.new()
	_stage.name = "VictoryReceiptStage"
	_stage.custom_minimum_size = Vector2(0.0, custom_minimum_size.y)
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.add_theme_stylebox_override("panel", _stage_style())
	add_child(_stage)

	var layout := GridContainer.new()
	layout.name = "CircularRewardLayout"
	layout.columns = 1
	layout.add_theme_constant_override("h_separation", 14 if _compact else 20)
	layout.add_theme_constant_override("v_separation", 8)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.add_child(layout)

	var wheel_column := VBoxContainer.new()
	wheel_column.name = "WheelColumn"
	wheel_column.add_theme_constant_override("separation", -2)
	wheel_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(wheel_column)

	_wheel = RewardWheel.new()
	_wheel.name = "SettledRewardWheel"
	_wheel.configure(_data, _compact, _reduced)
	_wheel.custom_minimum_size = Vector2.ONE * _wheel_side
	_wheel.landed.connect(_on_wheel_landed)
	wheel_column.add_child(_wheel)

	var wheel_truth := _text("80% FANTASY FISH   /   20% EGGS", 10 if _compact else 11,
		DIM_IVORY, FONT_BOLD)
	wheel_truth.name = "WheelOddsTruth"
	wheel_truth.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wheel_column.add_child(wheel_truth)

	var detail_panel := PanelContainer.new()
	detail_panel.name = "RewardCommandPanel"
	detail_panel.custom_minimum_size.x = 0.0
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	layout.add_child(detail_panel)

	var details := VBoxContainer.new()
	details.name = "RewardDetailsStack"
	details.add_theme_constant_override("separation", 4)
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_child(details)

	_pre_reveal = VBoxContainer.new()
	_pre_reveal.name = "RevealControls"
	_pre_reveal.add_theme_constant_override("separation", 7)
	_pre_reveal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(_pre_reveal)
	_build_intro()

	_winner = VBoxContainer.new()
	_winner.name = "LandedRewardDetails"
	_winner.visible = false
	_winner.add_theme_constant_override("separation", 4 if _compact else 6)
	_winner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(_winner)
	_build_winner()

	_audio = AudioStreamPlayer.new()
	_audio.name = "VictoryChime"
	_audio.stream = WIN_SFX
	_audio.volume_db = -7.0
	add_child(_audio)


func _build_intro() -> void:
	_status = _text("PRACTICE REWARD / NOT SAVED" if bool(_data["sandbox_preview"]) else "One victory. One reward.",
		10 if _compact else 12, DIM_IVORY, FONT_BODY)
	_status.name = "ReceiptTruth"
	_status.tooltip_text = "Your victory result is already secured. The wheel presents that result and does not reroll it."
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pre_reveal.add_child(_status)

	var actions := HBoxContainer.new()
	actions.name = "CeremonyActions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 7)
	_pre_reveal.add_child(actions)

	_reveal_button = Button.new()
	_reveal_button.name = "RevealRewardButton"
	_reveal_button.text = "SPIN AND REVEAL"
	_reveal_button.custom_minimum_size = Vector2(176.0 if _compact else 220.0,
		_touch_height)
	if _mobile: _reveal_button.custom_minimum_size.x = 160.0 * _css_unit
	_reveal_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_reveal_button.tooltip_text = "Reveal the reward already secured by this victory."
	_style_button(_reveal_button, true)
	_reveal_button.pressed.connect(reveal)
	actions.add_child(_reveal_button)

	_skip_button = Button.new()
	_skip_button.name = "SkipRewardAnimationButton"
	_skip_button.text = "SKIP"
	_skip_button.visible = false
	_skip_button.custom_minimum_size = Vector2(_touch_height, _touch_height)
	_style_button(_skip_button, false)
	_skip_button.pressed.connect(skip_animation)
	actions.add_child(_skip_button)


func _build_winner() -> void:
	var name := _text(String(_data["label"]) + "  x1", 20 if _compact else 24,
		Color(_data["color"]).lerp(IVORY, 0.22), FONT_DISPLAY)
	name.name = "SettledRewardName"
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_winner.add_child(name)
	var category := _text("%s  /  %s" % [String(_data["rarity"]).to_upper(),
		String(_data["top_level_category"]).to_upper()], 10 if _compact else 12,
		Color(_data["color"]), FONT_BOLD)
	category.name = "SettledRewardCategory"
	category.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_winner.add_child(category)
	var odds_copy := ("%.0f%% %s pool  |  %.2f%% within pool\n%.2f%% overall chance") % [
		float(_data["top_level_chance_percent"]), String(_data["top_level_category"]),
		float(_data["chance_within_category_percent"]), float(_data["overall_chance_percent"])]
	category.tooltip_text = odds_copy
	var claim_copy := "PRACTICE REWARD / NOT SAVED" if bool(_data["sandbox_preview"]) else \
		"CLAIMED / EXACTLY 1 REWARD"
	var claim := _text(claim_copy, 10 if _compact else 12,
		CORAL if bool(_data["sandbox_preview"]) else CYAN, FONT_BOLD)
	claim.name = "RewardClaimStatus"
	claim.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_winner.add_child(claim)


func reveal() -> void:
	if _revealed or not bool(_data.get("ok", false)):
		return
	_revealed = true
	if _reveal_button != null:
		_reveal_button.disabled = true
		_reveal_button.text = "WHEEL IN MOTION"
	if _status != null:
		_status.text = "PRACTICE REWARD / NOT SAVED" if bool(_data["sandbox_preview"]) else "Revealing your secured reward..."
	if _skip_button != null and not _reduced:
		_skip_button.visible = true
	if _wheel != null:
		_wheel.start()
	revealed.emit(String(_data["reward_key"]))


func _on_wheel_landed(_category: String) -> void:
	if _pre_reveal != null:
		_pre_reveal.visible = false
	if _winner != null:
		_winner.visible = true
		_winner.modulate = Color.WHITE if _reduced else Color(1.0, 1.0, 1.0, 0.0)
		var parent := _winner.get_parent() as Container
		if parent != null:
			parent.queue_sort()
		if _stage != null:
			_stage.queue_sort()
		if not _reduced:
			var tween := create_tween()
			tween.tween_property(_winner, "modulate", Color.WHITE, 0.24)
	if not _reduced and DisplayServer.get_name() != "headless" and _audio != null:
		_audio.play()


func skip_animation() -> void:
	if _wheel != null:
		_wheel.skip()


func animation_running() -> bool:
	return _wheel != null and _wheel.is_running()


func wheel_debug_state() -> Dictionary:
	return _wheel.debug_state() if _wheel != null else {}


func is_revealed() -> bool:
	return _revealed


func target_art_path() -> String:
	return String(_data.get("art_path", ""))


func reward_data() -> Dictionary:
	return _data.duplicate(true)


func art_is_safe_fit() -> bool:
	var art: TextureRect = _wheel.art_control() if _wheel != null else null
	if art == null or art.texture == null:
		return false
	return art.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED \
		and not art.clip_contents and art.position.x > 0.0 and art.position.y > 0.0 \
		and art.position.x + art.size.x < _wheel.size.x \
		and art.position.y + art.size.y < _wheel.size.y


func _odds_chip(host: Control, title: String, chance: String, color: Color) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0.0, 46.0 if _compact else 52.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r * 0.075, color.g * 0.075, color.b * 0.075, 0.96)
	style.border_color = Color(color.r, color.g, color.b, 0.68)
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.set_corner_radius_all(7)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	host.add_child(panel)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var pct := _text(chance, 17 if _compact else 21, color, FONT_DISPLAY)
	row.add_child(pct)
	var label := _text(title, 8 if _compact else 9, IVORY, FONT_BOLD)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(label)


func _text(value: String, px: int, color: Color, font: Font = FONT_BODY) -> Label:
	var label := Label.new()
	label.set_meta("ceremony_base_font", px)
	label.text = value
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", roundi(float(px) * _css_unit))
	label.add_theme_color_override("font_color", color)
	return label


func _stage_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_border_width_all(0)
	style.set_content_margin_all(0)
	return style


func _detail_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = DEEP_SLATE
	style.border_color = Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.30)
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.set_corner_radius_all(9)
	style.content_margin_left = 12.0 if _compact else 17.0
	style.content_margin_right = 12.0 if _compact else 17.0
	style.content_margin_top = 10.0 if _compact else 14.0
	style.content_margin_bottom = 10.0 if _compact else 14.0
	return style


func _separator_style() -> StyleBoxLine:
	var style := StyleBoxLine.new()
	style.color = Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.30)
	style.thickness = 1
	return style


func _style_button(button: Button, primary: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = AMBER if primary else SLATE
	normal.border_color = Color("ffebaf") if primary else Color("8c6ba5")
	normal.set_border_width_all(1)
	normal.border_width_bottom = 4 if primary else 2
	normal.set_corner_radius_all(9)
	normal.set_content_margin_all(7)
	normal.shadow_color = Color(0.02, 0.0, 0.04, 0.36)
	normal.shadow_size = 7
	normal.shadow_offset = Vector2(0.0, 3.0)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = normal.bg_color.lightened(0.10)
	for state in ["normal", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_font_override("font", FONT_BOLD)
	button.add_theme_font_size_override("font_size", roundi((11.0 if _compact else 13.0) * _css_unit))
	button.add_theme_color_override("font_color", INK if primary else IVORY)
	button.add_theme_color_override("font_hover_color", INK if primary else Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(INK.r, INK.g, INK.b, 0.62) if primary else DIM_IVORY)
