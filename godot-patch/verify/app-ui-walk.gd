## app-ui-walk.gd — what does the iOS app actually DRAW? (test harness, never shipped)
##
## Runs the recovered game natively and headless with the app's feature policy forced on, opens
## every InfoBar popup, every PlayerPanel tab, the onboarding gate, the Chikiseum entry and the
## Temple, and prints every visible Label / Button / RichTextLabel / tooltip text (after
## TranslationServer, i.e. as it would be drawn) that still mentions wallets, tokens, trading,
## prices or money.
##
## Use:
##   cp -al recovered walk                       # hard-link copy; edits below replace files
##   rm walk/ChikFeat.gd && <write a ChikFeat.gd whose _cache is the app's CHIK_FEATURES and
##                           whose _read is true>     # the policy the page publishes in the app
##   cp godot-patch/verify/app-ui-walk.gd walk/AppWalk.gd
##   add  AppWalk="*res://AppWalk.gd"  under [autoload] in walk/project.godot (fresh file, not the link)
##   godot --headless --path walk | grep -E "HIT\[|STAGE|WALK DONE"
##
## Run the same walk with the real ChikFeat.gd (website mode) as a control: on 2026-09-24 it found
## 59 trading texts on the website and none in the app beyond the app's own neutral refusals.
##
## Limits: the world is paused (the headless dummy renderer crashes on the game's per-frame meshes),
## so the GameHUD shops (Craft, Mystic, Azulon, Hospital), which build their contents only once the
## game is running and signed in, are not reached. Walk those by hand on a device.
extends Node
## App-mode UI walker: opens every panel it can reach and reports visible text that still talks
## about trading, wallets, tokens or money. Test harness only — never shipped.
var KW: = RegEx.new()
var seen: = {}
var stage: = "boot"
var nvis: = 0

func _process(_d: float) -> void:
	# The dummy renderer cannot hold Weather.gd's per-frame meshes; keep it off for the walk.
	var w: = _node_by_script(get_tree().root, "Weather.gd") if Engine.get_process_frames() % 30 == 0 else null
	if w != null and w.is_processing():
		w.set_process(false)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	KW.compile("(?i)phantom|solscan|magic ?eden|trading post|\\$CHIKI|\\bSOL\\b|marketplace|\\bmarket\\b|\\bsell|\\bsold\\b|\\bbuy|\\bbought|listing|wallet|\\bNFTs?\\b|\\bmint|pump\\.fun|withdraw|payout|open gates|creator.fee|reward pool|tradab|\\btrad(e|ing)\\b|on-chain|onchain|blockchain|\\btoken|\\bburn|explorer|escrow|\\bprice|\\bbid\\b|auction|airdrop|\\bcrypto")
	_run.call_deferred()

func _node_by_script(n: Node, file: String) -> Node:
	var s: Script = n.get_script()
	if s != null and s.resource_path.ends_with("/" + file):
		return n
	for c in n.get_children():
		var r: = _node_by_script(c, file)
		if r != null:
			return r
	return null

var force_self: = false
func _scan(n: Node) -> void:
	if n is CanvasItem and not force_self and not (n as CanvasItem).is_visible_in_tree():
		return

	var texts: Array = []
	if n is Label or n is Button or n is LinkButton:
		texts.append(n.atr(n.text))
	elif n is RichTextLabel:
		texts.append((n as RichTextLabel).get_parsed_text())
	elif n is LineEdit:
		texts.append(n.atr((n as LineEdit).placeholder_text))
	if n is Control and (n as Control).tooltip_text != "":
		texts.append("[tooltip] " + n.atr((n as Control).tooltip_text))
	for t in texts:
		var s: = String(t).strip_edges()
		if s != "": nvis += 1
		if s != "" and KW.search(s) != null:
			var key: = s.substr(0, 160)
			if not seen.has(key):
				seen[key] = stage
				print("HIT[", stage, "] ", key.replace("\n", " ⏎ "))
	for c in n.get_children():
		_scan(c)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _snap(name: String) -> void:
	stage = name
	await _wait(0.6)
	nvis = 0
	_scan(get_tree().root)
	print("STAGE ", name, " visible_texts=", nvis)

func _try(obj: Object, method: String, args: Array = []) -> bool:
	if obj == null or not obj.has_method(method) or obj.get_method_argument_count(method) > args.size():
		print("SKIP ", method)
		return false
	obj.callv(method, args)
	return true

func _run() -> void:
	await get_tree().process_frame
	var root: = get_tree().root
	var onb: = _node_by_script(root, "Onboarding.gd")
	var hud: = _node_by_script(root, "GameHUD.gd")
	var ib: = _node_by_script(root, "InfoBar.gd")
	var pp: = _node_by_script(root, "PlayerPanel.gd")
	var ce: = _node_by_script(root, "ChikiseumEntry.gd")
	var cs: = _node_by_script(root, "Chikiseum.gd")
	var tp: = _node_by_script(root, "Temple.gd")
	for ui in [onb, hud, ib, pp, ce, cs, tp]:
		if ui != null:
			ui.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	await _wait(8.0)
	await _snap("boot")
	print("FOUND onb=", onb != null, " hud=", hud != null, " ib=", ib != null, " pp=", pp != null, " ce=", ce != null, " cs=", cs != null, " tp=", tp != null)
	if onb != null:
		for m in ["_show_gate", "_show_hatch", "_show_avatar_gallery", "show_egg_primer"]:
			if onb.has_method(m) and onb.get_method_argument_count(m) == 0:
				onb.call(m)
				await _snap("onboarding." + m)
		if onb is CanvasItem: (onb as CanvasItem).visible = false
		if onb is CanvasLayer: (onb as CanvasLayer).visible = false
	if ib != null:
		for id in ["chikidex", "mountdex", "mlegacy", "avatars", "catalog", "ledger", "codex", "devnest", "dispatch", "statistics", "wallet", "chronicles"]:
			ib.call("_open_pop", id)
			await _snap("infobar." + id)
		ib.call("_open_pop", "chronicles")
	if pp != null:
		pp.call("toggle")
		await _snap("playerpanel.open")
		for id in ["avatar", "quests", "satchel", "mounts", "inventory", "food", "potions", "creator", "marketplace"]:
			if pp.has_method("_pick_tab"):
				pp.call("_pick_tab", id)
				await _snap("playerpanel." + id)
		for inv in ["items", "fish", "eggs", "gear"]:
			pp.set("_inv_tab", inv)
			pp.call("_pick_tab", "inventory")
			await _snap("playerpanel.inventory." + inv)
		_try(pp, "open_me_market")
		await _snap("playerpanel.open_me_market")
		pp.call("toggle")
	if hud != null:
		if hud is CanvasLayer: (hud as CanvasLayer).visible = true
		var intro = hud.get("_intro")
		if intro != null: intro.visible = false
		var prof = hud.get("_profile")
		if prof != null: prof.d["seen_intro"] = true
		for m in ["open_craft", "open_market", "open_mystic", "open_azulon", "open_hospital", "open_avatars", "open_wallet"]:
			_try(hud, m)
			await get_tree().process_frame
			print("DBG ", m, " intro=", (hud.get("_intro") as CanvasItem).visible if hud.get("_intro") != null else "none", " refs=", hud.call("_refs"), " mystic=", hud.get("_mystic_panel"), " modal=", hud.call("modal_owns_screen") if hud.has_method("modal_owns_screen") else "?")
			await _snap("hud." + m)
			for pn in ["_craft_panel", "_mystic_panel", "_azulon_panel", "_hospital_panel", "_avatars_panel", "_market_panel"]:
				var pnl = hud.get(pn)
				if pnl != null and is_instance_valid(pnl):
					stage = "hud." + m + "/" + pn
					force_self = true
					nvis = 0
					_scan(pnl)
					force_self = false
					print("STAGE ", stage, " visible_texts=", nvis)
			if hud.has_method("_close_all_dialogs"): hud.call("_close_all_dialogs")
	if ce != null:
		if ce is CanvasLayer: (ce as CanvasLayer).visible = true
		_try(ce, "open")
		await _snap("chikiseum_entry.open")
	if cs != null:
		_try(cs, "open")
		await _snap("chikiseum.open")
		for t in ["cup", "deck", "how"]:
			if cs.has_method("_fill_tab"):
				cs.call("_fill_tab", t)
				await _snap("chikiseum." + t)
	if tp != null:
		if tp is CanvasLayer: (tp as CanvasLayer).visible = true
		_try(tp, "open")
		await _snap("temple.open")
	await _wait(1.0)
	await _snap("end")
	print("WALK DONE hits=", seen.size())
	get_tree().quit()
