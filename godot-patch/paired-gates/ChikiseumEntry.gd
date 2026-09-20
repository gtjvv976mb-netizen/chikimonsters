extends CanvasLayer
## The actual Chikoria E-entry router. Cup retains its existing script/auth/service.
## Online arena requires verified server admission; rehearsal remains native-debug sandbox only.
## No wallet, ownership, combat, reward, payment or opponent is created by this router.
signal route_changed(route: String)
const CUP_SCRIPT := "res://Chikiseum.gd"
const ARENA_SCENE := "res://ChikiseumReferenceWorld.tscn"
const ONLINE_UNAVAILABLE := "Connect and sign in with your wallet to check verified online PvP availability. No rehearsal replaces an online match."
const ENTRY_SKIN := preload("res://ChikiseumUISkin.gd")
const GATE_BUTTON_ART := preload("res://GateButtonArt.gd")
const BANNER_PATH := "res://chikiseum_banner.png"
const GATE_FRAME_PATH := "res://chikiseum_gate_frame.png"
var _route := "closed"
var _shell: Control
var _gate_frame: TextureRect
var _panel: PanelContainer
var _cup: CanvasLayer
var _arena: Control
var _rehearsal: Button
var _status: Label
var _keys_owned := false
var _return_pending := false
var _world_at_entry := Vector3.ZERO
var _live: Node
var _fighter_select: OptionButton
var _refresh_online: Button
var _enter_online: Button
var _online_available := false
var _entry_scroll: ScrollContainer
var _entry_column: VBoxContainer
var _entry_banner: TextureRect
var _entry_purpose: Label
var _fighter_card: PanelContainer
var _fighter_portrait: TextureRect
var _fighter_heading: Label
var _fighter_name: Label
var _fighter_hint: Label
var _secondary_actions: HBoxContainer
var _fighter_presentations: Array[Dictionary] = []
var _portrait_species := ""
var _portrait_index: Dictionary = {}
var _entry_mode := "desktop"

static func rehearsal_allowed(debug_build: bool, web_build: bool, asset_sandbox: bool) -> bool:
    return debug_build and not web_build and asset_sandbox

func _native_sandbox_allowed() -> bool:
    var profile := get_tree().get_first_node_in_group("profile")
    return rehearsal_allowed(OS.is_debug_build(),OS.has_feature("web"),profile!=null and bool(profile.get("asset_sandbox")))

func _ready() -> void:
    layer=65
    add_to_group("chikiseum")
    _build_entry()
    get_viewport().size_changed.connect(_layout)
    set_process(false)

func _build_entry() -> void:
    _shell=Control.new();_shell.name="ChikiseumEntrySurface"
    _shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(_shell)
    var scrim:=Button.new();scrim.name="EntryScrim";scrim.flat=true;scrim.focus_mode=Control.FOCUS_NONE
    scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var shadow:=StyleBoxFlat.new();shadow.bg_color=Color(0.035,0.025,0.07,.82)
    for state in ["normal","hover","pressed"]:scrim.add_theme_stylebox_override(state,shadow)
    scrim.pressed.connect(close);_shell.add_child(scrim)
    _gate_frame=TextureRect.new();_gate_frame.name="HiggsfieldGateFrame"
    _gate_frame.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
    _gate_frame.stretch_mode=TextureRect.STRETCH_SCALE
    _gate_frame.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
    _gate_frame.mouse_filter=Control.MOUSE_FILTER_IGNORE
    if ResourceLoader.exists(GATE_FRAME_PATH):_gate_frame.texture=load(GATE_FRAME_PATH) as Texture2D
    if _gate_frame.texture!=null:
        var edge_shader:=Shader.new()
        edge_shader.code="shader_type canvas_item;\nvoid fragment() {\n    vec4 pixel = texture(TEXTURE, UV);\n    float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));\n    if (edge < 0.055 && max(pixel.r, max(pixel.g, pixel.b)) < 0.065) pixel.a = 0.0;\n    COLOR = pixel;\n}"
        var edge_material:=ShaderMaterial.new();edge_material.shader=edge_shader
        _gate_frame.material=edge_material
    _shell.add_child(_gate_frame)
    _panel=PanelContainer.new();_panel.name="ChikiseumEntryPanel"
    var stone:=ENTRY_SKIN.panel(ENTRY_SKIN.GOLD,true)
    stone.bg_color=Color.TRANSPARENT if _gate_frame.texture!=null else Color("191822f5")
    stone.border_color=Color.TRANSPARENT if _gate_frame.texture!=null else ENTRY_SKIN.GOLD
    stone.set_border_width_all(0 if _gate_frame.texture!=null else 2)
    stone.shadow_size=0 if _gate_frame.texture!=null else 10
    stone.set_corner_radius_all(12)
    stone.content_margin_left=36;stone.content_margin_right=36
    stone.content_margin_top=28;stone.content_margin_bottom=30
    _panel.add_theme_stylebox_override("panel",stone);_shell.add_child(_panel)
    _entry_scroll=ScrollContainer.new();_entry_scroll.name="EntryScroll"
    _entry_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
    _entry_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
    _entry_scroll.follow_focus=true;_panel.add_child(_entry_scroll)
    var column:=VBoxContainer.new();column.name="EntryContent";column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    column.add_theme_constant_override("separation",7);_entry_scroll.add_child(column);_entry_column=column
    _entry_banner=TextureRect.new();_entry_banner.name="OfficialEntryBanner"
    _entry_banner.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_entry_banner.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _entry_banner.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR;_entry_banner.mouse_filter=Control.MOUSE_FILTER_IGNORE
    if ResourceLoader.exists(BANNER_PATH):_entry_banner.texture=load(BANNER_PATH) as Texture2D
    _entry_banner.custom_minimum_size=Vector2(0,66);column.add_child(_entry_banner)
    var title:=Label.new();title.name="EntryTitle";title.text="THE CHIKISEUM"
    title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.add_theme_color_override("font_color",ENTRY_SKIN.GOLD)
    title.add_theme_font_size_override("font_size",20);title.visible=_entry_banner.texture==null;column.add_child(title)
    _entry_purpose=Label.new();_entry_purpose.name="EntryPurpose";_entry_purpose.text="ONE CHAMPION  ·  REAL-TIME DUELS"
    _entry_purpose.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
    _entry_purpose.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_entry_purpose.add_theme_font_size_override("font_size",11)
    _entry_purpose.add_theme_color_override("font_color",ENTRY_SKIN.CYAN)
    _entry_purpose.add_theme_color_override("font_shadow_color",Color(0,0,0,.85))
    _entry_purpose.add_theme_constant_override("shadow_offset_y",2)
    column.add_child(_entry_purpose)
    _fighter_card=PanelContainer.new();_fighter_card.name="SelectedOwnedFighter"
    var fighter_skin:=ENTRY_SKIN.panel(ENTRY_SKIN.VIOLET);fighter_skin.shadow_size=0
    fighter_skin.bg_color=Color("242033ef");fighter_skin.border_color=Color("9075c8")
    fighter_skin.border_width_left=3;fighter_skin.border_width_top=1
    fighter_skin.set_content_margin_all(9)
    _fighter_card.add_theme_stylebox_override("panel",fighter_skin);column.add_child(_fighter_card)
    var fighter_row:=HBoxContainer.new();fighter_row.add_theme_constant_override("separation",10);_fighter_card.add_child(fighter_row)
    _fighter_portrait=TextureRect.new();_fighter_portrait.name="SelectedOriginalPortrait"
    _fighter_portrait.custom_minimum_size=Vector2(72,72);_fighter_portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
    _fighter_portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;_fighter_portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
    fighter_row.add_child(_fighter_portrait)
    var identity:=VBoxContainer.new();identity.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    identity.alignment=BoxContainer.ALIGNMENT_CENTER;identity.add_theme_constant_override("separation",4);fighter_row.add_child(identity)
    _fighter_heading=Label.new();_fighter_heading.text="YOUR CHAMPION";_fighter_heading.add_theme_font_size_override("font_size",10)
    _fighter_heading.add_theme_color_override("font_color",ENTRY_SKIN.GOLD);identity.add_child(_fighter_heading)
    _fighter_name=Label.new();_fighter_name.name="SelectedFighterName";_fighter_name.text="Choose an owned Chikimon"
    _fighter_name.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_fighter_name.add_theme_font_size_override("font_size",17)
    _fighter_name.add_theme_color_override("font_color",ENTRY_SKIN.LIGHT);identity.add_child(_fighter_name)
    _fighter_hint=Label.new();_fighter_hint.name="SelectedFighterHint";_fighter_hint.text="Wallet-verified ownership required"
    _fighter_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_fighter_hint.add_theme_font_size_override("font_size",11)
    _fighter_hint.add_theme_color_override("font_color",ENTRY_SKIN.MUTED);identity.add_child(_fighter_hint)
    _fighter_select=OptionButton.new();_fighter_select.name="OwnedArenaFighter";_fighter_select.add_item("Verified owned Chikimons appear here")
    _fighter_select.fit_to_longest_item=false;_fighter_select.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
    _entry_button(_fighter_select,false,ENTRY_SKIN.VIOLET);_fighter_select.custom_minimum_size=Vector2(0,42)
    _fighter_select.get_popup().add_theme_font_size_override("font_size",13)
    _fighter_select.get_popup().add_theme_stylebox_override("panel",ENTRY_SKIN.panel(ENTRY_SKIN.VIOLET))
    _fighter_select.get_popup().add_theme_color_override("font_color",ENTRY_SKIN.LIGHT)
    _fighter_select.item_selected.connect(func(_index:int):_enter_online.disabled=not _selected_eligible();_update_selected_fighter())
    column.add_child(_fighter_select)
    _enter_online=Button.new();_enter_online.name="EnterVerifiedArena";_enter_online.text="ENTER THE CHIKISEUM";_enter_online.disabled=true
    _entry_button(_enter_online,true,ENTRY_SKIN.GOLD);_enter_online.custom_minimum_size=Vector2(0,48)
    _enter_online.pressed.connect(_enter_live);column.add_child(_enter_online)
    var status_frame:=PanelContainer.new();status_frame.name="ArenaGateStatusFrame"
    var status_skin:=ENTRY_SKIN.panel(ENTRY_SKIN.CYAN);status_skin.shadow_size=0
    status_skin.bg_color=Color("101d2bcc");status_skin.border_color=Color("367fa5")
    status_skin.border_width_left=3;status_skin.border_width_top=0
    status_skin.set_content_margin_all(7)
    status_frame.add_theme_stylebox_override("panel",status_skin);column.add_child(status_frame)
    _status=Label.new();_status.name="OnlineAvailability";_status.text=ONLINE_UNAVAILABLE
    _status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_status.add_theme_font_size_override("font_size",11)
    _status.add_theme_color_override("font_color",Color("c5d8e5"))
    status_frame.add_child(_status)
    _secondary_actions=HBoxContainer.new();_secondary_actions.name="EntrySecondaryActions";_secondary_actions.add_theme_constant_override("separation",6);column.add_child(_secondary_actions)
    _refresh_online=Button.new();_refresh_online.name="RefreshOwnedFighters";_refresh_online.text="Refresh"
    _entry_button(_refresh_online);_refresh_online.tooltip_text="Refresh verified owned Chikimons"
    _refresh_online.pressed.connect(_refresh_roster);_secondary_actions.add_child(_refresh_online)
    var cup:=Button.new();cup.name="OpenExistingCup";cup.text="Chikoria Cup";cup.focus_mode=Control.FOCUS_NONE
    _entry_button(cup);cup.pressed.connect(_open_cup);_secondary_actions.add_child(cup)
    var exit:=Button.new();exit.name="ReturnToChikoria";exit.text="Return";_entry_button(exit)
    exit.tooltip_text="Return to Chikoria";exit.pressed.connect(close);_secondary_actions.add_child(exit)
    cup.tooltip_text="Chikoria Cup keeps its own rules and service. Arena battle progression is separate from Chikoria."
    _rehearsal=Button.new();_rehearsal.name="OpenSandboxArena";_rehearsal.text="Explore arena · sandbox only"
    _entry_button(_rehearsal,false,ENTRY_SKIN.CYAN)
    _rehearsal.pressed.connect(open_rehearsal);column.add_child(_rehearsal)
    _layout();_shell.hide()

func _entry_button(button:Button,primary:bool=false,accent:Color=ENTRY_SKIN.GOLD)->void:
    ENTRY_SKIN.button(button,primary,accent)
    var normal:=button.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
    var hover:=button.get_theme_stylebox("hover").duplicate() as StyleBoxFlat
    var pressed:=button.get_theme_stylebox("pressed").duplicate() as StyleBoxFlat
    normal.bg_color=Color("593e24") if primary else Color("222333")
    hover.bg_color=Color("80572d") if primary else Color("33364b")
    pressed.bg_color=Color("3d2c1e") if primary else Color("171b27")
    for skin in [normal,hover,pressed]:
        skin.border_width_top=2 if primary else 1
        skin.border_width_bottom=3 if primary else 1
        skin.border_color=accent if primary else Color(accent,.45)
        skin.set_corner_radius_all(5)
    button.add_theme_stylebox_override("normal",normal)
    button.add_theme_stylebox_override("hover",hover)
    button.add_theme_stylebox_override("pressed",pressed)
    button.focus_mode=Control.FOCUS_ALL;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
    button.custom_minimum_size=Vector2(0,42);button.add_theme_font_size_override("font_size",13)
    GATE_BUTTON_ART.apply(button,"chikiseum",primary)

func _update_selected_fighter()->void:
    var index:=_fighter_select.selected
    var presentation:Dictionary=_fighter_presentations[index] if _online_available and index>=0 and index<_fighter_presentations.size() else {}
    _fighter_name.text=String(presentation.get("display_name","Choose an owned Chikimon"))
    _fighter_hint.text="Battle Lv. %d · Verified owned"%int(presentation.level) if not presentation.is_empty() and _selected_eligible() else "Wallet-verified ownership required"
    var species:=String(presentation.get("species",""))
    if species==_portrait_species:return
    _portrait_species=species;_fighter_portrait.texture=null
    if _portrait_index.is_empty():
        var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://sprites2d/index.json"))
        if parsed is Dictionary:_portrait_index=parsed
    var data:Variant=_portrait_index.get(species)
    if not data is Dictionary or data.get("category")!="chikimon":return
    var path:="res://sprites2d/"+species+".webp"
    if not ResourceLoader.exists(path):return
    var sheet:=load(path) as Texture2D
    var cell:Variant=data.get("cell")
    if sheet==null or not cell is Array or cell.size()!=2:return
    var portrait:=AtlasTexture.new();portrait.atlas=sheet
    portrait.region=Rect2(0,0,int(cell[0]),int(cell[1]));portrait.filter_clip=true
    _fighter_portrait.texture=portrait # Full original idle cell, no crop/resave/neighbor-frame sampling.

func _layout() -> void:
    if _panel==null:return
    var screen:=get_viewport().get_visible_rect().size
    _entry_mode="portrait" if screen.y>screen.x and screen.x<760 else "short_landscape" if screen.y<520 else "desktop"
    var compact:=_entry_mode!="desktop"
    var short_landscape:=_entry_mode=="short_landscape"
    _entry_banner.custom_minimum_size.y=38 if short_landscape else 54 if compact else 66
    _entry_column.add_theme_constant_override("separation",4 if short_landscape else 5 if compact else 7)
    _entry_purpose.add_theme_font_size_override("font_size",10 if compact else 11)
    _fighter_portrait.custom_minimum_size=Vector2(50,50) if short_landscape else Vector2(60,60) if screen.x<350 else Vector2(72,72)
    _fighter_heading.add_theme_font_size_override("font_size",9 if short_landscape else 10)
    _fighter_name.add_theme_font_size_override("font_size",14 if short_landscape else 15 if compact else 17)
    _fighter_hint.add_theme_font_size_override("font_size",10 if short_landscape else 11)
    _fighter_select.custom_minimum_size.y=42
    _enter_online.custom_minimum_size.y=48
    _secondary_actions.add_theme_constant_override("separation",4 if compact else 6)
    for action in _secondary_actions.get_children():
        if action is Button:
            action.custom_minimum_size.y=42
            action.add_theme_font_size_override("font_size",11 if screen.x<400 else 12 if compact else 13)
    _status.add_theme_font_size_override("font_size",10 if compact else 11)
    _fighter_card.visible=_fighter_select.visible
    _panel.custom_minimum_size=Vector2.ZERO
    _panel.size=Vector2(minf(480,maxf(180,screen.x-24)),minf(456 if _fighter_select.visible else 292,maxf(120,screen.y-24)))
    _panel.position=(screen-_panel.size)*.5
    _gate_frame.position=_panel.position
    _gate_frame.size=_panel.size
    var stone:=_panel.get_theme_stylebox("panel") as StyleBoxFlat
    var horizontal_margin:=25 if screen.x<400 else 29 if compact else 36
    # The lower gold lintel/crystals occupy more of the short frame than the
    # generic PanelContainer inset. Keep the scroll viewport inside that art.
    var vertical_margin:=31 if short_landscape else 25 if compact else 28
    stone.content_margin_left=horizontal_margin;stone.content_margin_right=horizontal_margin
    stone.content_margin_top=vertical_margin;stone.content_margin_bottom=vertical_margin
    _fighter_select.get_popup().max_size=Vector2i(maxf(160,screen.x-24),maxf(120,screen.y-24))

func _set_route(value: String) -> void:
    _route=value
    set_process(value!="closed")
    route_changed.emit(value)

func is_open() -> bool:
    if _route=="closed":return false
    if _route=="cup":return is_instance_valid(_cup) and bool(_cup.call("is_open"))
    return true

func open() -> void:
    if _route!="closed":return
    var temple:=get_tree().get_first_node_in_group("temple")
    if temple!=null and temple.has_method("is_open") and bool(temple.call("is_open")):return
    var player:=get_tree().get_first_node_in_group("player")
    if player!=null and player.has_method("keys_taken") and bool(player.call("keys_taken")):return
    if player is Node3D:_world_at_entry=player.global_position
    _status.text=ONLINE_UNAVAILABLE
    _update_selected_fighter()
    _rehearsal.visible=_native_sandbox_allowed()
    _refresh_online.visible=not _native_sandbox_allowed();_fighter_select.visible=not _native_sandbox_allowed();_enter_online.visible=not _native_sandbox_allowed()
    _set_route("entry");_shell.show();_layout();_keys(true)
    if not _native_sandbox_allowed():_refresh_roster()

func _create_live_client() -> Node:
    var script:=load("res://ChikiseumLiveClient.gd") as Script
    return script.new() if script!=null else null

func _ensure_live_client() -> bool:
    if is_instance_valid(_live):return true
    _live=_create_live_client()
    if _live==null:_status.text="The online transport resource is unavailable.";return false
    add_child(_live)
    _live.connect("roster_received",_live_roster)
    _live.connect("admitted",_live_admitted)
    _live.connect("notice",func(text:String):if _route=="entry":_status.text=text)
    _live.connect("command_failed",func(_op:String,text:String):
        if _route=="entry":_status.text=text;_refresh_online.disabled=false;_enter_online.disabled=not _selected_eligible())
    _live.connect("authentication_lost",func():
        _online_available=false
        _update_selected_fighter()
        if _route=="entry":_status.text="Wallet session expired. Sign in again, then refresh owned Chikimons.";_enter_online.disabled=true;_refresh_online.disabled=false)
    return true

func _refresh_roster() -> void:
    if _route!="entry" or _native_sandbox_allowed():return
    _online_available=false;_enter_online.disabled=true
    _update_selected_fighter()
    if not _ensure_live_client():return
    if not _live.call("configure_from_chain") or not _live.call("fetch_roster"):
        _status.text=ONLINE_UNAVAILABLE
        _refresh_online.disabled=false;return
    _refresh_online.disabled=true;_status.text="Checking verified owned Chikimons…"

func _live_roster(roster:Dictionary) -> void:
    if _route!="entry":return
    _fighter_select.clear();_online_available=true;_refresh_online.disabled=false
    _fighter_presentations.clear()
    var first:=-1
    for fighter in roster.get("fighters",[]) as Array:
        var index:=_fighter_select.item_count
        _fighter_select.add_item("%s · Battle Lv. %d"%[String(fighter.display_name),int(fighter.level)])
        _fighter_presentations.append({"species":String(fighter.get("species","")),"display_name":String(fighter.display_name),"level":int(fighter.level)})
        _fighter_select.set_item_metadata(index,{"asset_id":String(fighter.asset_id),"eligible":fighter.get("eligible")==true})
        _fighter_select.set_item_disabled(index,fighter.get("eligible")!=true)
        if fighter.get("eligible")==true and first<0:first=index
    if _fighter_select.item_count==0:_fighter_select.add_item("No eligible owned Chikimon returned by the server")
    if first>=0:_fighter_select.select(first)
    _enter_online.disabled=not _selected_eligible()
    _update_selected_fighter()
    _status.text="Choose one verified owned Chikimon. Online duels have no wagering." if first>=0 else "No eligible owned Chikimon is available. Listed, escrowed or inactive assets cannot enter."
    _layout()

func _selected_eligible() -> bool:
    if not _online_available or _fighter_select==null or _fighter_select.selected<0:return false
    var value:Variant=_fighter_select.get_item_metadata(_fighter_select.selected)
    return value is Dictionary and value.get("eligible")==true and not String(value.get("asset_id","")).is_empty()

func _enter_live() -> void:
    if _route!="entry" or _native_sandbox_allowed() or not _selected_eligible() or not is_instance_valid(_live):return
    var selected:=_fighter_select.get_item_metadata(_fighter_select.selected) as Dictionary
    if not _live.call("start_session",String(selected.asset_id)):
        _status.text="Admission could not start. Refresh ownership or reconnect your wallet.";return
    _enter_online.disabled=true;_refresh_online.disabled=true;_status.text="Verifying arena admission…"

func _live_admitted(session:Dictionary) -> void:
    if _route!="entry" or not is_instance_valid(_live):return
    _arena=_create_arena()
    if _arena==null or not _arena.has_signal("close_requested") or not _arena.has_method("attach_live_client"):
        if _arena!=null:_arena.free();_arena=null
        _live.call("handle_intent",{"op":"cancel","mode":"live"})
        _status.text="The online arena resource is unavailable. No rehearsal was substituted.";return
    _arena.set("online_entry_mode",true)
    _arena.connect("close_requested",_arena_closed)
    add_child(_arena);_arena.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    if not _arena.call("attach_live_client",_live,session):
        _arena.queue_free();_arena=null;_live.call("handle_intent",{"op":"cancel","mode":"live"})
        _status.text="Verified admission could not attach safely. Retry after refreshing your wallet.";return
    for dialog in _arena.find_children("*","ConfirmationDialog",true,false):dialog.canceled.connect(func():_return_pending=false)
    _shell.hide();_set_route("arena");_keys(true)

func _keys(take: bool) -> void:
    var player:=get_tree().get_first_node_in_group("player")
    if player!=null:
        if take and player.has_method("grab_keys"):player.call("grab_keys",self)
        elif not take and player.has_method("release_keys"):player.call("release_keys",self)
    _keys_owned=take
    var touch:=get_tree().get_first_node_in_group("touchui")
    if touch!=null and touch.has_method("set_suspended"):
        # Existing Cup touch scrolling is driven by TouchControls. Keep that GUI
        # reader available in Cup, while Player's weak keyboard owner blocks world motion.
        # Arena owns its own touch movement; its island controls must stay suspended.
        if not take:
            touch.call("set_suspended",true) # Clear any pending Cup gesture before return.
            touch.call("set_suspended",false)
        else:touch.call("set_suspended",_route!="cup")
    if take:Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _create_cup() -> CanvasLayer:
    if not ResourceLoader.exists(CUP_SCRIPT):return null
    var script:=load(CUP_SCRIPT) as Script
    return script.new() if script!=null else null

func _open_cup() -> void:
    if _route!="entry":return
    _dispose_live() # A pending roster/admission must not keep an unseen live lobby polling behind Cup.
    if not is_instance_valid(_cup):
        _cup=_create_cup()
        if _cup==null:_status.text="The existing Cup screen is unavailable. Return to Chikoria and try again.";return
        _cup.name="ChikoriaCupHub";add_child(_cup)
    _cup.call("open")
    _shell.hide();_set_route("cup");_keys(true)

func _create_arena() -> Control:
    if not ResourceLoader.exists(ARENA_SCENE):return null
    var scene:=load(ARENA_SCENE) as PackedScene
    return scene.instantiate() as Control if scene!=null else null

func open_rehearsal() -> bool:
    if _route!="entry" or not _native_sandbox_allowed():return false
    _arena=_create_arena()
    if _arena==null:
        _status.text="The sandbox arena resource is unavailable. No substitute scene or match was created.";return false
    if not _arena.has_signal("close_requested"):
        _arena.free();_arena=null;_status.text="The arena has no safe return contract.";return false
    _arena.connect("close_requested",_arena_closed)
    _arena.name="ChikiseumReferenceWorld";_shell.hide();_set_route("arena");_keys(true)
    add_child(_arena)
    _arena.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for dialog in _arena.find_children("*","ConfirmationDialog",true,false):
        dialog.canceled.connect(func():_return_pending=false)
    return true

func close() -> void:
    if _route=="closed":return
    if _route=="arena":
        # Trigger exactly the existing user Exit path. It retains cancellation ACK,
        # confirmation and pending-server-match handling; never force-free an active duel.
        var exit:=_arena.get_node_or_null("Exit") as Button if is_instance_valid(_arena) else null
        if exit!=null and not exit.disabled:
            _return_pending=true
            exit.pressed.emit()
        return
    if is_instance_valid(_cup):_cup.call("close")
    _finish_return()

func _arena_closed() -> void:
    if is_instance_valid(_arena):
        remove_child(_arena)
        _arena.queue_free() # SubViewport, streaming requests, FX and practice transport are disposed.
    _arena=null;_return_pending=false
    _dispose_live()
    _finish_return()

func _finish_return() -> void:
    _dispose_live()
    _shell.hide();_set_route("closed");_keys(false)
    # Deliberately no player teleport, profile/save write, scene reload, payout or wallet call.

func _process(_delta: float) -> void:
    if _route=="cup" and (not is_instance_valid(_cup) or not bool(_cup.call("is_open"))):
        _finish_return()
    if _route=="arena" and not is_instance_valid(_arena):
        _arena=null;_return_pending=false;_finish_return()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE and _route in ["entry","arena"]:
        close();get_viewport().set_input_as_handled()

func diagnostics() -> Dictionary:
    return {"route":_route,"open":is_open(),"keys_owned":_keys_owned,"return_pending":_return_pending,
        "native_sandbox_rehearsal_allowed":_native_sandbox_allowed(),"online_arena_available":_online_available,
        "online_arena_reason":ONLINE_UNAVAILABLE,"cup_script":CUP_SCRIPT,"arena_scene":ARENA_SCENE,
        "arena_allocated":is_instance_valid(_arena),"world_position_at_entry":_world_at_entry,
        "profile_or_auth_mutated":false,"rewards_created":false,"real_sol_enabled":false,
        "entry_presentation":{"mode":_entry_mode,"panel":_panel.get_global_rect(),"scroll_view":_entry_scroll.get_global_rect(),
            "scrolling":_entry_scroll.get_v_scroll_bar().max_value>_entry_scroll.get_v_scroll_bar().page,
            "banner_path":BANNER_PATH,"banner_full_image":_entry_banner.texture!=null and not _entry_banner.texture is AtlasTexture,
            "primary_action":"EnterVerifiedArena","selected_portrait_species":_portrait_species,"portrait_original_full_idle_cell":true,
            "presentation_only":true}}

func _exit_tree() -> void:
    _dispose_live()
    if _keys_owned:_keys(false)

func _dispose_live() -> void:
    if is_instance_valid(_live):
        _live.call("dispose");_live.queue_free()
    _live=null;_online_available=false
