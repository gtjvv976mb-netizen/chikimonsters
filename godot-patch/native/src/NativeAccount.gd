extends CanvasLayer
## THE ACCOUNT SCREENS OF THE NATIVE iOS APP.
##
## In the web-view app these were SwiftUI screens around the page. The native app has no page and
## no Swift shell — the whole app is the game — so they live here, as an autoload added by
## godot-patch/native/overlay/override.cfg. Only ever active on iOS (ChikFeat.native()).
##
## Three things, all against the same backend routes the Swift shell used:
##   * WELCOME, when this iPhone holds no account: "Create an account" (POST /account/new) or
##     "I already have an account" with a code from chikimonsters.com/link (POST /link/redeem).
##   * ACCOUNT, from the small button in the top corner: back the account up to a wallet on the
##     website (POST /account/claim → a code), unlink this iPhone, or delete the account
##     (POST /link/delete_account) — the in-app deletion path App Review 5.1.1(v) requires.
##   * REJECTED: Chain.gd calls show_welcome(reason) when the server refuses this device's link.
##
## The credential is written with ChikFeat.save_native_account (user://, inside the app sandbox),
## and the game picks it up on the reload that follows — the same path a cold launch takes.

const API := "https://api.chikimonsters.com"
const INK_BG := Color(0.043, 0.071, 0.125, 0.97)
const INK_PANEL := Color(0.071, 0.110, 0.188, 1.0)
const INK_LINE := Color(0.141, 0.200, 0.306, 1.0)
const INK_TEXT := Color(0.918, 0.949, 1.0)
const INK_DIM := Color(0.576, 0.651, 0.769)
const INK_GOLD := Color(1.0, 0.827, 0.302)
const INK_BAD := Color(0.973, 0.443, 0.443)

var _root: Control
var _http: HTTPRequest
var _busy := false
var _corner: Button


func _ready() -> void:
	if not ChikFeat.native():
		queue_free()
		return
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_http = HTTPRequest.new()
	_http.timeout = 25.0
	add_child(_http)
	_corner = Button.new()
	_corner.text = "Account"
	_corner.focus_mode = Control.FOCUS_NONE
	_corner.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_corner.offset_left = -118
	_corner.offset_top = 8
	_corner.offset_right = -10
	_corner.offset_bottom = 48
	_corner.add_theme_font_size_override("font_size", 18)
	_corner.pressed.connect(show_account)
	add_child(_corner)
	if ChikFeat.native_account().is_empty():
		show_welcome("")
	else:
		_corner.visible = true
	_probe_network()


## One line in the device log at start-up saying whether HTTPS to the backend works — the first
## thing to look at when a phone "can't connect".
func _probe_network() -> void:
	var probe := HTTPRequest.new()
	probe.timeout = 20.0
	add_child(probe)
	if probe.request(API + "/health") != OK:
		print("[native] network probe could not start")
		probe.queue_free()
		return
	var r: Array = await probe.request_completed
	print("[native] network probe: result %d, HTTP %d" % [int(r[0]), int(r[1])])
	probe.queue_free()


## THE SAVE WHEN THE APP GOES AWAY. The website flushes the cloud save from the browser's pagehide
## (Chain.gd's unload hook); an iPhone app has no page, and iOS may suspend or kill it at any time
## after it leaves the screen. So the same final flush runs here, on the app-level notifications.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		var chain := get_tree().get_first_node_in_group("chain") if is_inside_tree() else null
		if chain != null and chain.has_method("_final_flush"):
			chain.call("_final_flush")


# ------------------------------------------------------------------ screens

func show_welcome(reason: String) -> void:
	_corner.visible = false
	var box := _screen("Welcome to Chiki Monsters")
	if reason != "":
		box.add_child(_label(reason, INK_BAD, 18))
	box.add_child(_label("Start playing straight away. Your island, your creatures and everything you gather are saved to your account and waiting whenever you come back.", INK_DIM, 20))
	var err := _label("", INK_BAD, 18)
	var create := _button("Create an account", true)
	create.pressed.connect(func(): _create(create, err))
	box.add_child(create)
	box.add_child(err)
	box.add_child(_label("No email, no password — the account lives on this iPhone. You can back it up to your chikimonsters.com account later from Account.", INK_DIM, 16))
	var have := _button("I already have a Chiki Monsters account", false)
	have.pressed.connect(show_link)
	box.add_child(have)


func show_link() -> void:
	var box := _screen("Link your account")
	box.add_child(_label("1 · On a computer or tablet, open chikimonsters.com/link\n2 · Sign in there and press New code\n3 · Type the code below", INK_DIM, 20))
	var code := LineEdit.new()
	code.placeholder_text = "ABCD1234"
	code.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.max_length = 12
	code.custom_minimum_size = Vector2(0, 64)
	code.add_theme_font_size_override("font_size", 32)
	box.add_child(code)
	var err := _label("", INK_BAD, 18)
	var link := _button("Link this iPhone", true)
	link.pressed.connect(func(): _redeem(code.text, link, err))
	box.add_child(link)
	box.add_child(err)
	var back := _button("Back", false)
	back.pressed.connect(func(): show_welcome(""))
	box.add_child(back)


func show_account() -> void:
	var acct := ChikFeat.native_account()
	if acct.is_empty():
		show_welcome("")
		return
	_corner.visible = false
	var box := _screen("Account")
	var w := String(acct.get("wallet", ""))
	box.add_child(_label("Playing as " + (w.left(4) + "…" + w.right(4) if w.length() > 12 else w), INK_TEXT, 20))
	var app_made := bool(acct.get("app_made", false))
	var note := _label("", INK_DIM, 18)
	if app_made:
		var backup := _button("Back up this account", false)
		backup.pressed.connect(func(): _claim(backup, note))
		box.add_child(backup)
		box.add_child(_label("This account was made on this iPhone, and only this iPhone can open it. Backing it up moves it, and everything on it, onto your chikimonsters.com account, so you keep it if you lose this phone.", INK_DIM, 16))
	box.add_child(note)
	var unlink := _button("Lose this account on this iPhone" if app_made else "Unlink this iPhone", false)
	unlink.pressed.connect(func(): _confirm(box,
		"This account was made on this iPhone and the only key to it is here. Unlinking loses it for good. Back it up first if you want to keep it." if app_made
		else "This removes this iPhone's access. Your account is untouched and you can link again with a new code.",
		"Unlink", func(): _unlink()))
	box.add_child(unlink)
	var del := _button("Delete my account…", false)
	del.add_theme_color_override("font_color", INK_BAD)
	del.pressed.connect(func(): _confirm(box,
		"This asks us to delete this account and everything on it, permanently. It cannot be undone." ,
		"Delete", func(): _delete(note)))
	box.add_child(del)
	box.add_child(_label("Chiki Monsters %s · device %s" % [ProjectSettings.get_setting("application/config/version", ""), String(acct.get("device_id", "")).left(8)], INK_DIM, 14))
	var done := _button("Done", true)
	done.pressed.connect(_close)
	box.add_child(done)


func _close() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_corner.visible = not ChikFeat.native_account().is_empty()


# ------------------------------------------------------------------ actions

func _create(btn: Button, err: Label) -> void:
	var j := await _post("/account/new", {"device_id": ChikFeat.native_device_id(), "device_name": "iPhone", "client": "ios-app"}, btn, err,
		"Your account could not be created. Check your connection and try again.")
	if j.is_empty():
		return
	_adopt(j, true)


func _redeem(raw: String, btn: Button, err: Label) -> void:
	var code := ""
	for ch in raw.to_upper():
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			code += ch
	if code.length() < 6:
		err.text = "That code looks too short."
		return
	var j := await _post("/link/redeem", {"code": code, "device_id": ChikFeat.native_device_id(), "device_name": "iPhone", "client": "ios-app"}, btn, err,
		"That code is not valid any more. Mint a new one on the website.")
	if j.is_empty():
		return
	_adopt(j, false)


func _claim(btn: Button, note: Label) -> void:
	var acct := ChikFeat.native_account()
	var j := await _post("/account/claim", {"linkToken": acct.get("token", ""), "device_id": ChikFeat.native_device_id()}, btn, note,
		"That code could not be issued.")
	if j.is_empty():
		return
	note.add_theme_color_override("font_color", INK_GOLD)
	note.text = "Your code: %s\n1 · On the device you use for chikimonsters.com, open chikimonsters.com/link\n2 · Sign in there\n3 · Enter this code under Connect an app account\nIt lasts about %d minutes and works once." % [String(j.get("code", "")), max(1, int(j.get("expires_in", 600)) / 60)]


func _unlink() -> void:
	ChikFeat.clear_native_account()
	_restart()
	show_welcome("")


func _delete(note: Label) -> void:
	var acct := ChikFeat.native_account()
	var j := await _post("/link/delete_account", {"linkToken": acct.get("token", ""), "device_id": ChikFeat.native_device_id(), "client": "ios-app"}, null, note,
		"That request could not be sent. Check your connection and try again.")
	if j.is_empty():
		return
	ChikFeat.clear_native_account()
	_restart()
	show_welcome("Your account is scheduled for deletion. Signing in again before it completes cancels it.")


func _adopt(j: Dictionary, app_made: bool) -> void:
	var wallet := String(j.get("wallet", ""))
	var token := String(j.get("linkToken", ""))
	if wallet == "" or token == "":
		return
	ChikFeat.save_native_account({"wallet": wallet, "token": token, "label": String(j.get("label", "")), "app_made": app_made})
	_restart()


## Reload the game so Chain.gd starts signed in as the account now on this iPhone — the same path a
## cold launch takes.
func _restart() -> void:
	_close()
	get_tree().paused = false
	get_tree().call_deferred("reload_current_scene")


func _post(path: String, body: Dictionary, btn: Button, err: Label, fallback: String) -> Dictionary:
	if _busy:
		return {}
	_busy = true
	if btn != null:
		btn.disabled = true
	err.text = ""
	var e := _http.request(API + path, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(body))
	var out: Dictionary = {}
	if e != OK:
		err.text = "Chiki Monsters could not reach its server. Check your connection and try again."
	else:
		var r: Array = await _http.request_completed
		var code: int = r[1]
		var parsed: Variant = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
		var j: Dictionary = parsed if parsed is Dictionary else {}
		if code >= 200 and code < 300:
			out = j
			if out.is_empty():
				out = {"ok": true}
		elif code == 0:
			err.text = "Chiki Monsters could not reach its server. Check your connection and try again."
		else:
			var said := String(j.get("error", ""))
			err.text = (said.left(1).to_upper() + said.substr(1)) if said != "" else fallback
	_busy = false
	if btn != null and is_instance_valid(btn):
		btn.disabled = false
	return out


# ------------------------------------------------------------------ widgets

func _screen(title: String) -> VBoxContainer:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = INK_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	var head := _label(title, INK_TEXT, 34)
	box.add_child(head)
	return box


func _label(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(560, 60)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = INK_GOLD if primary else INK_PANEL
	sb.border_color = INK_LINE
	sb.set_border_width_all(0 if primary else 2)
	sb.set_corner_radius_all(12)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	var sd := sb.duplicate() as StyleBoxFlat
	sd.bg_color = sb.bg_color.darkened(0.4)
	b.add_theme_stylebox_override("disabled", sd)
	b.add_theme_color_override("font_color", Color.BLACK if primary else INK_GOLD)
	return b


func _confirm(box: VBoxContainer, text: String, action: String, then: Callable) -> void:
	for c in box.get_children():
		c.queue_free()
	box.add_child(_label(text, INK_TEXT, 22))
	var yes := _button(action, true)
	yes.pressed.connect(then)
	box.add_child(yes)
	var no := _button("Cancel", false)
	no.pressed.connect(show_account)
	box.add_child(no)
