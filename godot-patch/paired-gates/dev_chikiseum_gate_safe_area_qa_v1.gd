extends SceneTree
## Synthetic geometry QA for the framed entry. No wallet or PvP state is created.
const EntryFixture := preload("res://dev_chikiseum_entry_presentation_qa_v1.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func _inside(rect: Rect2, container: Rect2) -> bool:
	return rect.size.x > 0 and rect.size.y > 0 and rect.position.x >= container.position.x - 0.5 and rect.position.y >= container.position.y - 0.5 and rect.end.x <= container.end.x + 0.5 and rect.end.y <= container.end.y + 0.5

func _run() -> void:
	for size in [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(844, 390), Vector2i(640, 320), Vector2i(390, 844), Vector2i(320, 568)]:
		var viewport := SubViewport.new()
		viewport.size = size
		root.add_child(viewport)
		var entry := EntryFixture.FixtureEntry.new()
		viewport.add_child(entry)
		await process_frame
		entry.open()
		entry.call("_live_roster", {"fighters": [{"asset_id": "synthetic", "species": "galador", "display_name": "Galador", "level": 3, "eligible": true}]})
		for tick in 3:
			await process_frame
		var panel := entry.get("_panel") as PanelContainer
		var gate_art := entry.get("_gate_frame") as TextureRect
		var scroll := entry.get("_entry_scroll") as ScrollContainer
		var enter := entry.get("_enter_online") as Button
		var bounds := panel.get_global_rect()
		var safe := scroll.get_global_rect()
		var label := str(size)
		_check(_inside(bounds, Rect2(Vector2.ZERO, Vector2(size))), label + " panel in viewport")
		_check(gate_art.get_global_rect() == bounds, label + " art aligned with panel")
		_check(safe.position.x - bounds.position.x >= 24.5 and bounds.end.x - safe.end.x >= 24.5, label + " side trim clear")
		_check(safe.position.y - bounds.position.y >= 24.5 and bounds.end.y - safe.end.y >= 24.5, label + " crest and lower lintel clear")
		_check(_inside(enter.get_global_rect(), safe), label + " primary action initially visible")
		for name in ["OwnedArenaFighter", "EnterVerifiedArena", "RefreshOwnedFighters", "OpenExistingCup", "ReturnToChikoria"]:
			var action := entry._shell.find_child(name, true, false) as Button
			scroll.ensure_control_visible(action)
			for tick in 2:
				await process_frame
			_check(action.size.y >= 41.5 and _inside(action.get_global_rect(), safe), label + " accessible " + name)
		entry.close()
		viewport.free()
	print("CHIKISEUM_GATE_SAFE_AREA_QA ", checks, " checks; failures=", failures)
	quit(0 if failures.is_empty() else 1)
