extends SceneTree
## Native gate-button contract: missing art must not replace functional controls.

const GateButtonArt := preload("res://GateButtonArt.gd")


func _init() -> void:
	call_deferred("_check")


func _check() -> void:
	var failures: Array[String] = []
	for gate in ["wicked", "chikiseum"]:
		for primary in [false, true]:
			var button := Button.new()
			button.text = "LIVE LABEL"
			button.custom_minimum_size = Vector2(82, 44)
			button.focus_mode = Control.FOCUS_ALL
			var original := StyleBoxFlat.new()
			original.bg_color = Color.RED
			button.add_theme_stylebox_override("normal", original)
			var focus := StyleBoxFlat.new()
			button.add_theme_stylebox_override("focus", focus)
			var applied := GateButtonArt.apply(button, gate, primary)
			var path: String = GateButtonArt.PATHS[gate]["primary" if primary else "secondary"]
			if ResourceLoader.exists(path):
				var source := load(path) as Texture2D
				var image := source.get_image()
				print("GATE_BUTTON_SOURCE ", path, " size=", image.get_size(), " used=", image.get_used_rect(), " format=", image.get_format())
			if applied:
				for state in ["normal", "hover", "pressed", "disabled"]:
					var style := button.get_theme_stylebox(state)
					if not style is StyleBoxTexture or (style as StyleBoxTexture).texture == null:
						failures.append("%s %s missing %s texture" % [gate, str(primary), state])
				if not ResourceLoader.exists(path):
					failures.append("%s %s accepted a missing asset" % [gate, str(primary)])
				var art := (button.get_theme_stylebox("normal") as StyleBoxTexture).texture
				print("GATE_BUTTON_ART ", path, " packed=", art.get_size())
			else:
				if ResourceLoader.exists(path):
					failures.append("%s %s rejected a present asset" % [gate, str(primary)])
				if button.get_theme_stylebox("normal") != original:
					failures.append("%s %s changed fallback skin" % [gate, str(primary)])
			if button.get_theme_stylebox("focus") != focus or button.text != "LIVE LABEL":
				failures.append("%s %s changed focus or text" % [gate, str(primary)])
			if button.custom_minimum_size != Vector2(82, 44) or button.focus_mode != Control.FOCUS_ALL:
				failures.append("%s %s changed touch/keyboard control" % [gate, str(primary)])
			button.free()
	# Exercise the actual art path without creating placeholder files. The texture
	# is transient and never packaged; the production loader still uses real PNGs.
	var sample := Image.create(256, 64, false, Image.FORMAT_RGBA8)
	sample.fill(Color("8a668f"))
	var sample_texture := ImageTexture.create_from_image(sample)
	for gate in ["wicked", "chikiseum"]:
		for primary in [false, true]:
			var path: String = GateButtonArt.PATHS[gate]["primary" if primary else "secondary"]
			GateButtonArt._prepared[path] = sample_texture
			var button := Button.new()
			button.text = "LIVE LABEL"
			button.custom_minimum_size = Vector2(82, 44)
			button.focus_mode = Control.FOCUS_ALL
			var focus := StyleBoxFlat.new()
			button.add_theme_stylebox_override("focus", focus)
			if not GateButtonArt.apply(button, gate, primary):
				failures.append("%s %s rejected valid in-memory art" % [gate, str(primary)])
			for state in ["normal", "hover", "pressed", "disabled"]:
				var skin := button.get_theme_stylebox(state)
				if not skin is StyleBoxTexture:
					failures.append("%s %s missing %s nine-slice" % [gate, str(primary), state])
				elif (skin as StyleBoxTexture).texture != sample_texture:
					failures.append("%s %s changed %s texture" % [gate, str(primary), state])
			if button.get_theme_stylebox("focus") != focus or button.text != "LIVE LABEL":
				failures.append("%s %s art changed focus or live text" % [gate, str(primary)])
			if button.custom_minimum_size != Vector2(82, 44) or button.focus_mode != Control.FOCUS_ALL:
				failures.append("%s %s art changed touch/keyboard control" % [gate, str(primary)])
			button.free()
			GateButtonArt._prepared.erase(path)
	for gate in ["wicked", "chikiseum"]:
		var picker := OptionButton.new()
		picker.text = "CHOOSE / GALADOR"
		if GateButtonArt.apply(picker, gate, false):
			var normal := picker.get_theme_stylebox("normal")
			if normal.get_content_margin(SIDE_LEFT) < 39.9 or normal.get_content_margin(SIDE_RIGHT) < 33.9:
				failures.append(gate + " picker text crosses decorated endcaps")
			if picker.get_theme_constant("arrow_margin") < 34:
				failures.append(gate + " picker arrow crosses decorated endcap")
		picker.free()
	if failures.is_empty():
		print("GATE_BUTTON_ART_QA PASS")
	else:
		for failure in failures:
			printerr("GATE_BUTTON_ART_QA FAIL ", failure)
	quit(0 if failures.is_empty() else 1)
