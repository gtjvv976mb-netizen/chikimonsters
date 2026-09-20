extends ProgressBar
## Presentation-only health rail. Range.value/max_value remain authoritative and immediate;
## only an amber after-image eases away after damage. No combat or interpolation of HP.
const STONE := Color("292833")
const SHADOW := Color("13131b")
const GOLD := Color("b99659")
var accent := Color("c77cfa")
var mirrored := false
var _last_ratio := 0.0
var _trail_ratio := 0.0
var _hold := 0.0
var _initialized := false


func _ready() -> void:
    show_percentage = false; step = 0.0
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    custom_minimum_size = Vector2(0,20)
    # Disable inherited default paint, not its Range API/accessibility semantics.
    add_theme_stylebox_override("background",StyleBoxEmpty.new())
    add_theme_stylebox_override("fill",StyleBoxEmpty.new())
    if not value_changed.is_connected(_on_value_changed): value_changed.connect(_on_value_changed)
    if not changed.is_connected(_on_range_changed): changed.connect(_on_range_changed)
    _on_range_changed(); set_process(false)


func configure_skin(color: Color,reverse: bool) -> void:
    accent = color; mirrored = reverse; queue_redraw()


func _ratio() -> float:
    return clampf((value-min_value)/(max_value-min_value),0,1) if max_value>min_value else 0.0


func _on_range_changed() -> void:
    _last_ratio = _ratio(); _trail_ratio = _last_ratio
    _hold = 0; _initialized = true; set_process(false); queue_redraw()


func _on_value_changed(_new_value: float) -> void:
    var actual := _ratio()
    if not _initialized or actual>=_last_ratio:
        _trail_ratio = actual; _hold = 0; set_process(false)
    else:
        _trail_ratio = maxf(_trail_ratio,_last_ratio); _hold = .16; set_process(true)
    _last_ratio = actual; _initialized = true; queue_redraw()


func _process(delta: float) -> void:
    _hold = maxf(0,_hold-delta)
    var actual := _ratio()
    if _hold<=0: _trail_ratio = lerpf(_trail_ratio,actual,1.0-exp(-delta*10))
    if _trail_ratio-actual<.001:
        _trail_ratio = actual; set_process(false)
    queue_redraw()


func _polygon(points: Array[Vector2],color: Color,reverse: bool=false) -> void:
    var packed := PackedVector2Array()
    for point in points: packed.append(Vector2(size.x-point.x,point.y) if reverse else point)
    draw_colored_polygon(packed,color)


func _gradient(points: Array[Vector2],colors: Array[Color],reverse: bool=false) -> void:
    var packed := PackedVector2Array()
    for point in points: packed.append(Vector2(size.x-point.x,point.y) if reverse else point)
    draw_polygon(packed,PackedColorArray(colors))


func _outline(points: Array[Vector2],color: Color,width: float,reverse: bool=false) -> void:
    var packed := PackedVector2Array()
    for point in points: packed.append(Vector2(size.x-point.x,point.y) if reverse else point)
    packed.append(packed[0])
    draw_polyline(packed,color,width,true)


func _fill(ratio: float,color: Color,facets: bool) -> void:
    var length := maxf(0,(size.x-16)*ratio)
    if length<=.01: return
    var left := 8.0; var right := left+length; var top := 4.0; var bottom := size.y-4
    var middle := (top+bottom)*.5
    var cut := minf((bottom-top)*.52,length*.45)
    var shape: Array[Vector2] = [Vector2(left,top),Vector2(right-cut,top),
        Vector2(right,middle),Vector2(right-cut,bottom),Vector2(left,bottom)]
    if not facets:
        _polygon(shape,color,mirrored)
        _outline(shape,color.lightened(.22),1.0,mirrored)
        return
    # Native per-vertex interpolation gives the thick crystal a luminous top bevel and
    # darker lower face, with a pointed centerward end. No imported fighting-game art.
    _gradient(shape,[color.lightened(.38),color.lightened(.27),color,
        color.darkened(.34),color.darkened(.20)],mirrored)
    _polygon([Vector2(left,top+1),Vector2(right-cut,top+1),
        Vector2(right-cut*.45,middle-2),Vector2(left,middle-2)],Color(1,1,1,.13),mirrored)
    # Sparse broad facets stay inside the exact authoritative fill edge.
    var interval := maxf(22,(size.x-16)/7)
    var x := left+interval*.5
    while x<right-cut-2:
        var span := minf(8,right-cut-x)
        _polygon([Vector2(x,top+.7),Vector2(x+span,middle),Vector2(x,bottom-.7)],Color(1,1,1,.16),mirrored)
        x += interval
    var head := Vector2(size.x-right if mirrored else right,middle)
    _outline(shape,Color(color.r,color.g,color.b,.82).lightened(.24),1.0,mirrored)
    draw_line(Vector2(head.x,top+cut*.45),Vector2(head.x,bottom-cut*.45),Color(1,1,1,.76),1,true)


func _draw() -> void:
    if size.x<14 or size.y<8: return
    var w := size.x; var h := size.y; var cut := h*.48
    var outer: Array[Vector2] = [Vector2(3,.75),Vector2(w-cut,.75),Vector2(w-.75,h*.5),
        Vector2(w-cut,h-.75),Vector2(3,h-.75),Vector2(.75,h-3),Vector2(.75,3)]
    _polygon(outer,STONE,mirrored)
    _polygon([Vector2(5,3),Vector2(w-cut-1,3),Vector2(w-4,h*.5),
        Vector2(w-cut-1,h-3),Vector2(5,h-3)],SHADOW,mirrored)
    # The shallow colored recess belongs to the arena's violet/cyan team lighting,
    # but leaves the unfilled portion unmistakably dark at a glance.
    _polygon([Vector2(8,4),Vector2(w-cut-2,4),Vector2(w-5,h*.5),
        Vector2(w-cut-2,h-4),Vector2(8,h-4)],Color(accent.r,accent.g,accent.b,.10),mirrored)
    for fraction in [.25,.5,.75]:
        var inset_x: float = 8+(w-16)*float(fraction)
        var etch_x: float = w-inset_x if mirrored else inset_x
        draw_line(Vector2(etch_x,5),Vector2(etch_x,h-5),Color(GOLD.r,GOLD.g,GOLD.b,.14),1,true)
    _outline(outer,Color(GOLD.r,GOLD.g,GOLD.b,.92),1.5,mirrored)
    if _trail_ratio>_ratio(): _fill(_trail_ratio,Color(.96,.57,.18,.80),false)
    _fill(_ratio(),accent,true)
    # Partial-health dividers make the wide fighting-game rails readable without
    # numerals or a panel. The inner accent remains the authoritative HP fill.
    for fraction in [.25,.5,.75]:
        var marker_x: float = 8+(w-16)*float(fraction)
        if mirrored: marker_x = w-marker_x
        draw_line(Vector2(marker_x,6),Vector2(marker_x,h-6),Color(.07,.065,.10,.26),1,true)
    var ratio := _ratio()
    if ratio>0 and ratio<=.25:
        var tip_x: float = 8+(w-16)*ratio
        if mirrored: tip_x = w-tip_x
        _polygon([Vector2(tip_x,h*.5-4),Vector2(tip_x+3,h*.5),
            Vector2(tip_x,h*.5+4),Vector2(tip_x-3,h*.5)],Color(1,.56,.29,.78))
    # Brushed gold portrait-side cap and a narrow top glint, not a fighter backplate.
    _polygon([Vector2(1.5,4),Vector2(4,1.5),Vector2(7,1.5),Vector2(7,h-1.5),
        Vector2(4,h-1.5),Vector2(1.5,h-4)],GOLD,mirrored)
    var cap_x := w-4 if mirrored else 4.0
    draw_line(Vector2(cap_x,4),Vector2(cap_x,h-4),Color("f4d995"),1,true)
    _polygon([Vector2(8,1.7),Vector2(w-cut-1,1.7),Vector2(w-cut-1,2.4),
        Vector2(8,2.4)],Color(1,.89,.65,.28),mirrored)
    for fraction in [.25,.5,.75]:
        var x: float = 8+(w-16)*float(fraction)
        draw_line(Vector2(x,0),Vector2(x,3),Color(GOLD.r,GOLD.g,GOLD.b,.65),1,true)
        draw_line(Vector2(x,h-3),Vector2(x,h),Color(GOLD.r,GOLD.g,GOLD.b,.50),1,true)


func diagnostics() -> Dictionary:
    return {"module":"ChikiseumCrystalHealthBar","decorative":true,"health_authority":false,
        "value":value,"min_value":min_value,"max_value":max_value,"ratio":_ratio(),
        "damage_trail_ratio":_trail_ratio,"damage_trail_active":is_processing(),
        "authoritative_fill_is_immediate":true,"damage_trail_does_not_change_value":true,
        "gold_trim":true,"stone_rail":true,"crystal_facets":true,"segment_markers":3,
        "design":"angular_crystal_fighting_header_v7","native_vertex_gradient":true,
        "angular_outline":true,"slanted_centerward_end":true,"amber_damage_chip":true,
        "team_tinted_recess":true,"readable_quarter_marks":true,"low_hp_tip":_ratio()>0 and _ratio()<=.25,
        "health_bar_height":size.y,"recoverable_health_mechanic":false,"heat_gauge":false,
        "mirrored":mirrored,"screen_rect":get_global_rect(),"mouse_passthrough":true}
