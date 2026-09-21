extends Control
class_name ChikiseumDuelHUD
## Presentation-only Chikiseum battle header. No combat, transport, wallet or art mutation.
## The parent owns viewport layout, timer authority, decks, tactical/exit controls and lobby.

const Econ := preload("res://Econ.gd")
const FONT := preload("res://ui_font.ttf")
const BOLD := preload("res://ui_font_bold.ttf")
const CrystalHealthBar := preload("res://ChikiseumCrystalHealthBar.gd")
const OFFICIAL_BANNER := preload("res://chikiseum_banner.png")
const OFFICIAL_BANNER_PATH := "res://chikiseum_banner.png"
const OFFICIAL_BANNER_SHA := "451172c1fda8aaefe8bfd961b68db46a84c1e1ca66cb09519c1a5dc9f157acfa"
const GOLD := Color("dbb469")
const IVORY := Color("f4eedf")
const MUTED := Color("ada99f")
const VIOLET := Color("c77cfa")
const CYAN := Color("56d8fa")
const TERMINAL := ["finished", "cancelled", "forfeit", "ready_timeout", "turn_timeout", "draw", "catalogue_changed", "arena_changed", "admission_revoked"]

var _built := false
var _players: Dictionary = {}
var _snapshot: Dictionary = {}
var _you := "A"
var _local_fixture := false
var _committed := false
var _seconds_left := 0
var _header_h := 92.0
var _mode := "desktop"
var _duelists: Dictionary = {}
var _turn: Control
var _title: Label
var _tag: Label
var _phase: Label
var _clock: Label
var _round: Label
var _outcome: Label
var _banner: TextureRect
var _banner_sha := ""
var _round_number := 1
var _round_source := "default_whole_match"
var _timer_source := "none"
var _summary_kind := "waiting"
var _reserved := Rect2()
var _portrait_index: Dictionary = {}
var _portrait_index_loaded := false
var _portrait_cache: Dictionary = {}
var _portrait_sources: Dictionary = {}
var _portrait_regions: Dictionary = {}


func _ready() -> void:
    _ensure_built()
    if not resized.is_connected(_layout): resized.connect(_layout)
    _layout()


func configure(players: Dictionary, you: String, snapshot: Dictionary, local_fixture: bool, committed: bool) -> void:
    _ensure_built()
    _players = players.duplicate(true)
    _you = you if you in ["A", "B"] else ""
    _snapshot = snapshot.duplicate(true)
    _local_fixture = local_fixture
    _committed = committed
    var realtime: Variant = snapshot.get("realtime")
    # Realtime.remaining is deliberately zero before both players are ready. The ready
    # check has its own authoritative deadline; never flash 0s on each state poll.
    if snapshot.get("status") == "ready" and _finite_number(snapshot.get("deadline")) and _finite_number(snapshot.get("server_time")):
        _seconds_left = maxi(0, ceili(float(snapshot.deadline) - float(snapshot.server_time)))
        _timer_source = "snapshot.deadline-server_time"
    elif snapshot.get("combat_mode") == "realtime" and realtime is Dictionary and _finite_number(realtime.get("remaining")):
        _seconds_left = maxi(0, ceili(float(realtime.remaining)))
        _timer_source = "snapshot.realtime.remaining"
    elif _finite_number(snapshot.get("match_remaining_seconds")):
        _seconds_left = maxi(0, ceili(float(snapshot.match_remaining_seconds)))
        _timer_source = "snapshot.match_remaining_seconds"
    elif _finite_number(snapshot.get("deadline")) and _finite_number(snapshot.get("server_time")):
        _seconds_left = maxi(0, ceili(float(snapshot.deadline) - float(snapshot.server_time)))
        _timer_source = "snapshot.deadline-server_time"
    else:
        _seconds_left = 0
        _timer_source = "none"
    for side in ["A", "B"]: _refresh_duelist(side)
    # Keep only the two current original portrait sheets, never a permanent species gallery.
    var keep := []
    for side in ["A", "B"]:
        var player := _player(side)
        keep.append(String(player.get("species", "")))
    for species in _portrait_cache.keys():
        if not species in keep:
            _portrait_cache.erase(species)
            _portrait_regions.erase(species)
    _refresh_turn()
    _layout()


func set_clock(seconds_left: int) -> void:
    _seconds_left = maxi(0, seconds_left)
    _timer_source = "parent_authoritative_deadline_countdown"
    _ensure_built()
    _refresh_turn()


func header_height() -> float:
    return _header_h


static func _finite_number(value: Variant) -> bool:
    return (value is int or value is float) and is_finite(float(value))


static func _number_text(value: float) -> String:
    var text := "%.3f" % value
    while text.ends_with("0"): text = text.trim_suffix("0")
    return text.trim_suffix(".")


func _player(side: String) -> Dictionary:
    var value: Variant = _players.get(side, {})
    return value as Dictionary if value is Dictionary else {}


func _realtime() -> bool:
    return _local_fixture or _snapshot.get("combat_mode") == "realtime"


func _status_seconds(state: Variant) -> Variant:
    if not state is Dictionary: return null
    if _finite_number(state.get("remaining_seconds")): return float(state.remaining_seconds)
    if _finite_number(state.get("expires_at")) and _finite_number(_snapshot.get("server_time")):
        return float(state.expires_at) - float(_snapshot.server_time)
    return null


func _label(parent: Control, node_name: String, color: Color = IVORY, bold: bool = false) -> Label:
    var label := Label.new(); label.name = node_name
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.add_theme_font_override("font", BOLD if bold else FONT)
    label.add_theme_color_override("font_color", color)
    label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
    label.add_theme_constant_override("shadow_offset_y", 1)
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.clip_text = true
    label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    parent.add_child(label); return label


func _ensure_built() -> void:
    if _built: return
    _built = true
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    for side in ["A", "B"]:
        var panel := Control.new(); panel.name = "Duelist" + side
        panel.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(panel)
        var portrait := TextureRect.new(); portrait.name = "OriginalPortrait"
        portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE; panel.add_child(portrait)
        var badge := _label(panel, "Side", VIOLET if side == "A" else CYAN, true)
        var species := _label(panel, "Species", IVORY, true)
        var trainer := _label(panel, "Trainer", MUTED)
        var health := CrystalHealthBar.new(); health.name = "Health"
        health.configure_skin(VIOLET if side == "A" else CYAN,side == "B")
        panel.add_child(health)
        var hp := _label(panel, "HealthNumber", IVORY)
        hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        var statuses := Control.new(); statuses.name = "Statuses"
        statuses.mouse_filter = Control.MOUSE_FILTER_IGNORE; panel.add_child(statuses)
        _duelists[side] = {"root": panel, "portrait": portrait, "badge": badge,
            "species": species, "trainer": trainer, "health": health, "hp": hp,
            "statuses": statuses, "status_names": []}
    _turn = Control.new(); _turn.name = "TurnPanel"
    _turn.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_turn)
    _banner = TextureRect.new(); _banner.name = "OfficialBanner"; _banner.texture = OFFICIAL_BANNER
    _banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _banner.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    _banner.mouse_filter = Control.MOUSE_FILTER_IGNORE; _turn.add_child(_banner)
    _banner_sha = FileAccess.get_sha256(OFFICIAL_BANNER_PATH)
    _title = _label(_turn, "ArenaName", GOLD, true); _title.text = "CHIKISEUM"
    _tag = _label(_turn, "PracticeLabel", MUTED)
    _phase = _label(_turn, "TurnPhase", IVORY, true)
    _clock = _label(_turn, "Countdown", GOLD, true)
    _round = _label(_turn, "RoundLabel", GOLD, true)
    _outcome = _label(_turn, "OutcomeLabel", IVORY, true)
    for label in [_title, _round, _clock, _outcome]:
        label.add_theme_color_override("font_outline_color", Color(0.055, 0.055, 0.09, 0.98))
        label.add_theme_color_override("font_shadow_color", Color(0.015, 0.01, 0.04, 0.8))
        label.add_theme_constant_override("shadow_offset_y", 2)
        label.add_theme_constant_override("outline_size", 2)
    for label in [_title, _tag, _phase, _clock, _round, _outcome]: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    # One compact summary row below the official banner carries the actual match clock
    # or ready check. No new panel, fighter backplate or additional header height.
    _title.hide(); _tag.hide(); _phase.hide(); _clock.hide(); _outcome.hide()
    _refresh_turn()


func _portrait(species: String) -> Texture2D:
    if _portrait_cache.has(species): return _portrait_cache[species] as Texture2D
    if not _portrait_index_loaded:
        _portrait_index_loaded = true
        var file := FileAccess.open("res://sprites2d/index.json", FileAccess.READ)
        if file != null:
            var value: Variant = JSON.parse_string(file.get_as_text())
            if value is Dictionary: _portrait_index = value
    var entry: Variant = _portrait_index.get(species)
    var path := "res://sprites2d/" + species + ".webp"
    if not entry is Dictionary or not ResourceLoader.exists(path): return null
    var cell: Variant = entry.get("cell")
    if not cell is Array or cell.size() != 2: return null
    var sheet := load(path) as Texture2D
    if sheet == null: return null
    var atlas := AtlasTexture.new(); atlas.atlas = sheet
    # Inspect only the original DOWN/idle cell, once per current species. Trim empty alpha
    # gutter from the UV region, never creature pixels: even faint nonzero-alpha edges count.
    # Keep two pixels of safety where available; no asset edit or neighboring-frame sampling.
    var cell_rect := Rect2i(0, 0, int(cell[0]), int(cell[1]))
    var region := cell_rect
    var image := sheet.get_image()
    if image != null and not image.is_empty():
        var idle := image.get_region(cell_rect)
        var used := idle.get_used_rect()
        if used.has_area(): region = used.grow(2).intersection(cell_rect)
    atlas.region = Rect2(region); atlas.filter_clip = true
    _portrait_regions[species] = {"cell": Rect2(cell_rect), "region": Rect2(region),
        "empty_gutter_only": true, "alpha_threshold": 0, "safe_margin_pixels": 2}
    _portrait_cache[species] = atlas; return atlas


func _refresh_duelist(side: String) -> void:
    var player := _player(side); var view: Dictionary = _duelists[side]
    var species := String(player.get("species", ""))
    view.portrait.texture = _portrait(species) if not species.is_empty() else null
    _portrait_sources[side] = {"species": species, "path": "res://sprites2d/" + species + ".webp",
        "original_idle_frame": 0, "full_cell": false, "valid": view.portrait.texture != null,
        "uv_framing": _portrait_regions.get(species, {}).duplicate(true)}
    view.species.text = String(player.get("display_name", Econ.disp(species))) if not species.is_empty() else "AWAITING CHIKIMON"
    view.species.tooltip_text = view.species.text
    var handle := String(player.get("handle", player.get("trainer_name", "")))
    var level := "Lv. " + str(int(player.level)) if _finite_number(player.get("level")) else ""
    view.trainer.text = handle + ("  ·  " if not handle.is_empty() and not level.is_empty() else "") + level
    view.trainer.tooltip_text = view.trainer.text
    view.badge.text = side + ("  ·  HUMAN" if _local_fixture else "  ·  YOU" if side == _you else "  ·  RIVAL")
    var known := _finite_number(player.get("hp")) and _finite_number(player.get("max_hp")) and float(player.max_hp) > 0
    view.health.visible = known
    if known:
        view.health.max_value = float(player.max_hp); view.health.value = float(player.hp)
        view.hp.text = _number_text(float(player.hp)) + " / " + _number_text(float(player.max_hp)) + " HP"
    else: view.hp.text = "— HP"
    view.hp.tooltip_text = view.hp.text
    var names: Array[String] = []
    var statuses: Variant = player.get("statuses", {})
    if statuses is Dictionary:
        for key in statuses.keys():
            var status: Variant = statuses[key]
            if _realtime():
                var seconds: Variant = _status_seconds(status)
                if _finite_number(seconds) and float(seconds) <= 0: continue
            elif status is Dictionary and _finite_number(status.get("turns")) and float(status.turns) <= 0: continue
            names.append(String(key))
    names.sort(); view.status_names = names


func _refresh_turn() -> void:
    var round_value: Variant = _snapshot.get("round_number")
    var valid_round := _finite_number(round_value) and float(round_value) >= 1 and float(round_value) < 9223372036854775807.0 and floorf(float(round_value)) == float(round_value)
    _round_number = int(round_value) if valid_round else 1
    _round_source = "snapshot.round_number" if valid_round else "default_whole_match"
    if _round != null: _round.text = "ROUND " + str(_round_number)
    var status := String(_snapshot.get("status", ""))
    var winner: Variant = _snapshot.get("winner")
    _tag.text = "TRAINING • NO STAKES" if _local_fixture else "LIVE DUEL" if _snapshot.get("mode") == "live" else "PRACTICE DUEL"
    _summary_kind = "waiting"
    _clock.visible = false
    _round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    if status in TERMINAL:
        if winner is String and winner in ["A", "B"]:
            _phase.text = String(winner) + " WINS" if _local_fixture or _you.is_empty() else "VICTORY" if winner == _you else "DEFEAT"
        else:
            var endings := {"finished":"DRAW", "draw":"DRAW", "cancelled":"MATCH CANCELLED",
                "ready_timeout":"READY CHECK EXPIRED", "turn_timeout":"TIME EXPIRED",
                "catalogue_changed":"CARDS UPDATED", "arena_changed":"ARENA UPDATED",
                "admission_revoked":"ENTRY EXPIRED"}
            _phase.text = endings.get(status, "MATCH ENDED")
        _clock.text = status.replace("_", " ").to_upper()
        _summary_kind = "terminal"
    elif _local_fixture:
        _phase.text = "LIVE TRAINING"; _clock.text = "FREE PLAY"
        _round.text = "TRAINING · NO STAKES"
        _summary_kind = "training"
    elif status == "ready":
        var own_ready: bool = _player(_you).get("ready") == true
        _phase.text = "WAITING FOR RIVAL" if own_ready else "SENDING READY" if _committed else "READY TO DUEL"
        _round.text = "WAITING" if own_ready else "SENDING…" if _committed else "READY?"
        _clock.text = str(_seconds_left) + "s"
        _clock.visible = true
        _round.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        _summary_kind = "ready"
    elif status == "active":
        # The separately retained legacy turn rehearsal keeps its old hidden clock;
        # its longer diagnostic turn text is not squeezed into the live timer cell.
        _clock.visible = _realtime()
        _round.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if _clock.visible else HORIZONTAL_ALIGNMENT_CENTER
        _summary_kind = "combat"
        if _realtime():
            _phase.text = "LIVE DUEL"
            _clock.text = "%d:%02d" % [_seconds_left / 60, _seconds_left % 60]
            var live_clock: Variant = _snapshot.get("realtime")
            if live_clock is Dictionary and live_clock.get("phase") == "overtime":
                _phase.text = "OVERTIME"
                _round.text = "OVERTIME"
                _summary_kind = "overtime"
        else:
            _phase.text = "LOCKED IN" if _committed else "CHOOSE YOUR MOVE"
            _clock.text = ("TURN %d • " % int(_snapshot.turn) if _finite_number(_snapshot.get("turn")) else "") + str(_seconds_left) + "s"
    else:
        _phase.text = "AWAITING MATCH"; _clock.text = "—"
        _round.text = "AWAITING MATCH"
    _clock.add_theme_color_override("font_color", GOLD if _summary_kind == "overtime" or (status == "active" and _seconds_left <= 20) else IVORY)
    _phase.add_theme_color_override("font_color", GOLD if status in TERMINAL else (VIOLET if _you == "A" else CYAN) if _committed and not _realtime() else IVORY)
    var tempo: Variant = _snapshot.get("tempo")
    _tag.add_theme_color_override("font_color", MUTED)
    if not _realtime() and not status in TERMINAL and tempo is Dictionary:
        if tempo.get("phase") == "overtime":
            _tag.text = "OVERTIME"
            if _finite_number(tempo.get("base_energy_regen")):
                _tag.text += " • " + _number_text(float(tempo.base_energy_regen)) + " ENERGY/TURN"
            _tag.add_theme_color_override("font_color", GOLD)
            _clock.text += " • PRACTICE"
        elif tempo.get("next_phase") == "overtime":
            _tag.text = "OVERTIME NEXT TURN"
            _tag.add_theme_color_override("font_color", GOLD)
            _clock.text += " • PRACTICE"
    if _mode == "portrait":
        if _local_fixture and not status in TERMINAL: _phase.text = "TRAINING • NO STAKES"
        elif not status in TERMINAL:
            if not _realtime() and tempo is Dictionary and tempo.get("phase") == "overtime": _phase.text = _tag.text
            if not _realtime() and not _clock.text.ends_with("PRACTICE"): _clock.text += " • PRACTICE"
    if _outcome != null:
        _outcome.text = _phase.text if status in TERMINAL else ""
        if status == "forfeit" and winner is String and winner in ["A", "B"]:
            _outcome.text += " · FORFEIT"
        _outcome.visible = status in TERMINAL
        _outcome.add_theme_color_override("font_color",GOLD if _phase.text in ["VICTORY","DRAW"] else IVORY)
    if _round != null and _round.size.x > 0:
        _fit_summary(_round, 10 if _mode == "portrait" else 11 if _mode == "landscape" else 13, 8)
        _fit_summary(_clock, 11 if _mode == "portrait" else 12 if _mode == "landscape" else 13, 9)
        _fit_summary(_outcome, 11 if _mode == "portrait" else 12 if _mode == "landscape" else 13, 9)


func _place(node: Control, rect: Rect2, font_size: int = 0) -> void:
    if font_size > 0: node.add_theme_font_size_override("font_size", font_size)
    # Set typography first so the previous orientation's font minimum cannot inflate this rect.
    node.position = rect.position; node.size = rect.size


func _fit_summary(label: Label, preferred: int, minimum: int) -> void:
    # Long ready/terminal copy shares the same small, unobtrusive strip as the clock.
    # Scale only the text, never the banner or health rows, so it remains fully visible.
    var font := label.get_theme_font("font")
    var font_size := preferred
    while font_size > minimum and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > label.size.x - 2:
        font_size -= 1
    label.add_theme_font_size_override("font_size", font_size)


func _layout() -> void:
    if not _built or size.x < 1 or size.y < 1: return
    var portrait := size.x < 760 and size.y > size.x
    var landscape := not portrait and (size.x < 940 or size.y < 520)
    _mode = "portrait" if portrait else "landscape" if landscape else "compact" if size.x < 1440 else "desktop"
    var terminal := String(_snapshot.get("status","")) in TERMINAL
    var margin := 10.0 if portrait or landscape else 16.0 if _mode == "compact" else 24.0
    var controls_y := 8.0 if portrait else 54.0 if landscape else 76.0 if _mode=="compact" else 82.0
    _reserved = Rect2(size.x - margin - 84,controls_y,84,42)
    var image_size := 34.0 if portrait else 40.0 if landscape else 50.0 if _mode == "compact" else 56.0
    # Health-first fighting-game hierarchy: a smaller official center banner, original
    # outer portraits and thick opposing rails. The source image/UVs remain unchanged.
    var turn_width := 148.0 if portrait else 160.0 if landscape else 268.8 if _mode == "compact" else 285.6
    if portrait:
        # Keep the small banner above the health row and clear of the controls. Narrow
        # phones fit the entire image, never clip its gold frame or overlap exit.
        turn_width = minf(turn_width,maxf(80.0,size.x-2.0*(margin+84.0+12.0)))
    else:
        var fitting_width := size.x - 2.0 * (margin + 16.0 + image_size + 8.0 + 40.0)
        turn_width = minf(turn_width, maxf(80.0, fitting_width))
    var banner_height := turn_width * float(OFFICIAL_BANNER.get_height()) / float(OFFICIAL_BANNER.get_width())
    var turn_y := 2.0 if portrait or landscape else 4.0
    var turn_rect := Rect2((size.x - turn_width) * .5, turn_y, turn_width, banner_height + 22 + (18 if terminal else 0))
    _place(_turn, turn_rect)
    var panel_y := maxf(70.0,turn_rect.end.y+8.0) if portrait else 12.0
    var panel_height := image_size + 4
    for side in ["A", "B"]:
        var view: Dictionary = _duelists[side]
        var end_x := size.x - margin
        var available := (size.x - margin * 2 - 16) * .5 if portrait else turn_rect.position.x - margin - 16 if side == "A" else end_x - turn_rect.end.x - 16
        # Span every available pixel toward the banner; there is no preferred rail cap.
        var panel_width := maxf(image_size + 8, available)
        _place(view.root, Rect2(margin if side == "A" else end_x - panel_width, panel_y, panel_width, panel_height))
        _place(view.portrait, Rect2(0 if side == "A" else panel_width - image_size, 0, image_size, image_size))
        var hp_width := panel_width - image_size - 8
        var bar_height := 20.0 if portrait else 22.0 if landscape else 28.0 if _mode == "compact" else 32.0
        _place(view.health, Rect2(image_size + 8 if side == "A" else 0, (image_size-bar_height)*.5, hp_width, bar_height))
        for key in ["badge", "species", "trainer", "hp", "statuses"]:
            (view[key] as Control).hide()
        for child in (view.statuses as Control).get_children():
            view.statuses.remove_child(child); child.queue_free()
    _header_h = maxf(_reserved.end.y,maxf(turn_rect.end.y,panel_y+panel_height))+4.0
    _place(_banner, Rect2(0,0,turn_width,banner_height))
    var summary_width := minf(turn_width, 148.0 if portrait or landscape else 180.0)
    var summary_x := (turn_width-summary_width)*.5
    var clock_width := 46.0 if portrait or landscape else 52.0
    var status := String(_snapshot.get("status", ""))
    var timed := not _local_fixture and (status == "ready" or (status == "active" and _realtime()))
    _place(_round, Rect2(summary_x if timed else 0,banner_height+4,summary_width-clock_width-8 if timed else turn_width,16),10 if portrait else 11 if landscape else 13)
    _place(_clock, Rect2(summary_x+summary_width-clock_width,banner_height+4,clock_width,16),11 if portrait else 12 if landscape else 13)
    _clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _place(_outcome, Rect2(0,banner_height+22,turn_width,16),11 if portrait else 12 if landscape else 13)
    _title.hide(); _tag.hide(); _phase.hide()
    _refresh_turn(); queue_redraw()


func diagnostics() -> Dictionary:
    _ensure_built()
    var rects := {}; var health := {}; var status_state := {}; var reserved_clear := true
    for side in ["A", "B"]:
        var view: Dictionary = _duelists[side]; var player := _player(side)
        rects["Duelist" + side] = (view.root as Control).get_global_rect()
        for key in ["portrait", "badge", "species", "trainer", "health", "hp", "statuses"]:
            var node := view[key] as Control
            if node.visible:
                rects[side + "." + key] = node.get_global_rect()
                if node.get_global_rect().intersects(Rect2(global_position + _reserved.position, _reserved.size)): reserved_clear = false
        health[side] = {"hp": player.get("hp"), "max_hp": player.get("max_hp"), "display": String(view.hp.text)}
        status_state[side] = (view.status_names as Array).duplicate()
    rects["TurnPanel"] = _turn.get_global_rect()
    rects["OfficialBanner"] = _banner.get_global_rect()
    rects["ArenaName"] = _banner.get_global_rect() # Compatibility display-field alias, now official art.
    if _banner.get_global_rect().intersects(Rect2(global_position+_reserved.position,_reserved.size)): reserved_clear = false
    for label in [_title, _tag, _phase, _clock, _round, _outcome]:
        if label.visible:
            rects[label.name] = label.get_global_rect()
            if label.get_global_rect().intersects(Rect2(global_position + _reserved.position, _reserved.size)): reserved_clear = false
    return {"module": "ChikiseumDuelHUD", "mode": _mode, "header_height": _header_h,
        "viewport_size": size, "screen_rects": rects, "reserved_controls": Rect2(global_position + _reserved.position, _reserved.size),
        "reserved_controls_clear": reserved_clear, "B_panel_notched_around_controls": false,
        "controls_below_fighter_row":_mode!="portrait","opposing_health_rails_equal_width":true,
        "original_portraits": _portrait_sources.duplicate(true), "portrait_sheet_cache": _portrait_cache.size(),
        "authoritative_health": health, "active_status_keys": status_state, "phase": _phase.text,
        "clock": _clock.text, "practice_label": _tag.text, "local_fixture": _local_fixture,
        "you": _you, "committed": _committed, "snapshot_status": _snapshot.get("status"), "winner": _snapshot.get("winner"),
        "authoritative_tempo": _snapshot.get("tempo"), "tempo_ignored_in_training": _local_fixture,
        "combat_mode": _snapshot.get("combat_mode"), "realtime_presentation": _realtime(),
        "authoritative_realtime": _snapshot.get("realtime"),
        "round_number": _round_number, "round_label": _round.text, "round_source": _round_source,
        "legacy_turn_used_for_round": false, "fighter_backgrounds": false,
        "visible_fighter_fields": ["portrait", "health"], "match_clock_visible": _clock.visible,
        "timer_source":_timer_source, "summary_kind":_summary_kind, "phase_visible_in_summary":_realtime() or _snapshot.get("status")!="active",
        "timer_scope":"live_realtime_and_ready_check",
        "round_identity":"ROUND " + str(_round_number), "summary_row_height":16,
        "center_banner_backplate": false, "visible_words": [_round.text] + ([_clock.text] if _clock.visible else []) + ([_outcome.text] if _outcome.visible else []),
        "outcome_visible": _outcome.visible, "outcome": _outcome.text,
        "official_banner": {"path":OFFICIAL_BANNER_PATH,"sha256":_banner_sha,"expected_sha256":OFFICIAL_BANNER_SHA,
            "exact_official_source":_banner_sha==OFFICIAL_BANNER_SHA,"full_image":true,"texture_size":OFFICIAL_BANNER.get_size(),
            "aspect_centered":true,"generated_or_edited":false,
            "preferred_width":148.0 if _mode=="portrait" else 160.0 if _mode=="landscape" else 268.8 if _mode=="compact" else 285.6,
            "display_width":_banner.size.x,"desktop_enlargement_factor":1.4,"reduction_from_doubled_banner":0.30,
            "portrait_below_controls":false,"compact_top_center":true},
        "header_design":"opposing_crystal_rails_legible_summary_v7",
        "health_bar_height":_duelists.A.health.size.y,"health_header_dominant":true,
        "health_rails_span_available":true,"health_rails_width_cap":false,
        "health_to_banner_gap":{} if _mode=="portrait" else {"A":_banner.get_global_rect().position.x-_duelists.A.health.get_global_rect().end.x,
            "B":_duelists.B.health.get_global_rect().position.x-_banner.get_global_rect().end.x},
        "portrait_health_row_below_banner":_mode=="portrait",
        "health_design": {"A":_duelists.A.health.diagnostics(),"B":_duelists.B.health.diagnostics()},
        "mouse_passthrough": mouse_filter == Control.MOUSE_FILTER_IGNORE, "combat_math": false,
        "currency_mutations": false, "rank_or_latency_invented": false, "production_integration": false}
