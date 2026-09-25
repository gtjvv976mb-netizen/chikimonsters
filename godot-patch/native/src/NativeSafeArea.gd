## THE HUD STAYS CLEAR OF THE DYNAMIC ISLAND AND THE HOME INDICATOR.
##
## The game was laid out for a browser tab, and the iOS web view kept the page inside the safe area.
## The native app draws edge to edge: in landscape the Dynamic Island (and the rounded corners)
## covers 59 pt on the sides, and the home indicator 21 pt at the bottom. The 3D world should fill
## the whole screen; the controls should not. So every top-level HUD control — the direct Control
## children of the root window and of each CanvasLayer — is pulled inside the safe area by its own
## anchors: an edge anchored to the left moves right by the left inset, one anchored to the right
## moves left by the right inset, one anchored to the bottom moves up by the bottom inset. A
## full-screen HUD root therefore shrinks to the safe rectangle, a top-right button slides in, and
## anything centred is untouched. Backdrops (ColorRect / TextureRect) stay full-bleed.
##
## The game sets its own offsets when it builds or re-lays out a panel; each pass takes whatever the
## game last wrote as the base and re-applies the inset, so the two never fight.
## CHIK_SAFE_TEST="left,right,bottom" (points) simulates a phone's insets on a desktop.
extends Node

const META := "_safe_area_applied"  # [base offsets (4), applied offsets (4)]
const PASS_EVERY := 0.25

var _insets := Vector4.ZERO  # left, top, right, bottom — in canvas units
var _t := 0.0
var _layers: Array[CanvasLayer] = []


func _ready() -> void:
	if not ChikFeat.native():
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().size_changed.connect(_refresh_insets)
	_refresh_insets()
	get_tree().node_added.connect(func(n: Node):
		if n is CanvasLayer:
			_layers.append(n))
	_collect(get_tree().root)


func _collect(n: Node) -> void:
	if n is CanvasLayer:
		_layers.append(n)
	for c in n.get_children():
		_collect(c)


func _process(delta: float) -> void:
	_t += delta
	if _t < PASS_EVERY:
		return
	_t = 0.0
	if _insets == Vector4.ZERO:
		return
	for c in get_tree().root.get_children():
		if c is Control:
			_fit(c)
	var i := 0
	while i < _layers.size():
		var l := _layers[i]
		if not is_instance_valid(l) or not l.is_inside_tree():
			_layers.remove_at(i)
			continue
		i += 1
		if l.follow_viewport_enabled or not l.visible or l.custom_viewport != null:
			continue  # world-space UI (nameplates) and sub-viewport layers are not screen HUD
		for c in l.get_children():
			if c is Control:
				_fit(c)


func _fit(c: Control) -> void:
	if c is ColorRect or c is TextureRect or c is VideoStreamPlayer:
		return
	if c.top_level or c.get_meta("safe_area_ignore", false):
		return
	var cur := Vector4(c.offset_left, c.offset_top, c.offset_right, c.offset_bottom)
	var base := cur
	if c.has_meta(META):
		var m: Array = c.get_meta(META)
		if cur == m[1]:
			base = m[0]  # still ours: re-apply to the base (the insets may have changed)
	var want := base
	if is_zero_approx(c.anchor_left):
		want.x += _insets.x
	elif is_equal_approx(c.anchor_left, 1.0):
		want.x -= _insets.z
	if is_zero_approx(c.anchor_right):
		want.z += _insets.x
	elif is_equal_approx(c.anchor_right, 1.0):
		want.z -= _insets.z
	if is_zero_approx(c.anchor_top):
		want.y += _insets.y
	elif is_equal_approx(c.anchor_top, 1.0):
		want.y -= _insets.w
	if is_zero_approx(c.anchor_bottom):
		want.w += _insets.y
	elif is_equal_approx(c.anchor_bottom, 1.0):
		want.w -= _insets.w
	if want != cur:
		c.offset_left = want.x
		c.offset_top = want.y
		c.offset_right = want.z
		c.offset_bottom = want.w
	c.set_meta(META, [base, want])


func _refresh_insets() -> void:
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0 or win.y <= 0:
		return
	var px := Vector4.ZERO  # in window pixels
	var test := OS.get_environment("CHIK_SAFE_TEST")
	if test != "":
		var p := test.split(",")
		var pt := win.y / 430.0
		px = Vector4(float(p[0]) * pt, 0.0, float(p[1]) * pt, float(p[2]) * pt)
	else:
		var safe := DisplayServer.get_display_safe_area()
		if safe.size.x <= 0 or safe.size.y <= 0:
			return
		px = Vector4(safe.position.x, safe.position.y,
			win.x - safe.end.x, win.y - safe.end.y)
		# iOS reports the island side only; the phone turns either way in landscape, so both
		# sides get the larger inset and the HUD does not jump when it is rotated
		var side := maxf(px.x, px.z)
		px.x = side
		px.z = side
	# window pixels -> canvas units of the root viewport (canvas_items stretch + content scale)
	var k := get_viewport().get_final_transform().get_scale()
	_insets = Vector4(maxf(0.0, px.x) / k.x, maxf(0.0, px.y) / k.y,
		maxf(0.0, px.z) / k.x, maxf(0.0, px.w) / k.y)
