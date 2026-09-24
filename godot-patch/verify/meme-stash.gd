extends SceneTree
## Tripwire for the app's Meme Dynasty set-aside (apply-ios-review-patch.py).
##
##   godot --headless --path <patched project> -s res://meme-stash.gd
##
## Copy this file into the patched project first. It never touches a real save: the Profile is built
## off-tree and its `d` is filled by hand.

var _fails: = 0


func _ok(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		_fails += 1


func _policy(allow: Array) -> void:
	ChikFeat._cache = {"crypto": false, "meme_dynasty": false, "meme_allow": allow}
	ChikFeat._read = true


func _fresh() -> Node:
	var p: Node = load("res://Profile.gd").new()
	p.d = p._defaults()
	p.d["units"] = {
		"u1": {"uid": "u1", "species": "firix", "level": 5, "xp": 1},
		"u2": {"uid": "u2", "species": "pepe", "level": 9, "xp": 2, "asset_id": "A2"},
		"u3": {"uid": "u3", "species": "doge", "level": 3, "xp": 3},
		"u4": {"uid": "u4", "species": "jellox", "level": 2, "xp": 4},
	}
	p.d["party"] = ["u2", "u1", "u3"]
	p.d["bench"] = ["u4"]
	p.d["lead"] = 0
	p.d["companion"] = {"species": "pepe", "level": 9, "xp": 2}
	p.d["eggs"] = [{"kind": "meme", "asset_id": "E1", "tended": 1, "fed_at": 5.0}, {"kind": "normal", "tended": 0, "fed_at": 1.0}]
	p._meme_ready = true
	return p


func _init() -> void:
	print("hide, then put back untouched")
	_policy([])
	var p: = _fresh()
	var before: Dictionary = p.d.duplicate(true)
	var sig_before: String = p._econ_sig(p.SIG_VER)
	p._meme_hide()
	_ok(not p.d["units"].has("u2") and not p.d["units"].has("u3"), "pepe and doge are out of units")
	_ok(p.d["party"] == ["u1"] and p.d["bench"] == ["u4"], "party and bench hold only what the app shows")
	_ok(String(p.d["companion"]["species"]) == "firix", "the companion is a creature the app shows")
	_ok((p.d["eggs"] as Array).size() == 1, "the meme egg is set aside")
	_ok(p.meme_stash_asset_ids().has("A2") and p.meme_stash_asset_ids().has("E1"), "set-aside asset ids still count as held")
	p._meme_unhide()
	_ok(p.d["units"] == before["units"], "units restored exactly")
	_ok(p.d["party"] == before["party"] and p.d["bench"] == before["bench"] and p.d["lead"] == before["lead"], "party, bench and lead restored exactly")
	_ok(p.d["companion"] == before["companion"], "companion restored exactly")
	_ok(p._econ_sig(p.SIG_VER) == sig_before, "the save signature is unchanged")

	print("the player rearranges while they are hidden")
	p = _fresh()
	p._meme_hide()
	(p.d["bench"] as Array).append("u1")
	p.d["party"] = []
	p.d["lead"] = 0
	p._meme_unhide()
	var all: Array = (p.d["party"] as Array) + (p.d["bench"] as Array)
	_ok(all.size() == 4 and all.has("u1") and all.has("u2") and all.has("u3") and all.has("u4"), "every creature is back, once")
	_ok((p.d["party"] as Array).size() <= 3, "the party is never over its cap")

	print("save_now-style cycle leaves nothing behind")
	p = _fresh()
	p._meme_hide()
	p._mark()
	p._meme_unhide()
	p._meme_hide()
	p._meme_unhide()
	_ok(p.d["units"].size() == 4 and (p.d["eggs"] as Array).size() == 2, "repeated cycles lose nothing")

	print("one species allowed")
	_policy(["doge"])
	p = _fresh()
	p._meme_hide()
	_ok(p.d["units"].has("u3") and not p.d["units"].has("u2"), "doge shows, pepe stays set aside")
	_ok((p.d["eggs"] as Array).size() == 2, "meme eggs show once any species is allowed")
	p._meme_unhide()

	print("no second copy of a set-aside creature")
	_policy([])
	p = _fresh()
	p._meme_hide()
	p.own_chiki("pepe", "test")
	var n: = 0
	for uid in p.d["units"]:
		if String(p.d["units"][uid]["species"]) == "pepe":
			n += 1
	_ok(n == 0 and p._meme_stash_has("pepe"), "own_chiki does not mint a duplicate")

	print("the website is untouched")
	ChikFeat._cache = {"crypto": true, "meme_dynasty": true}
	p = _fresh()
	p._meme_hide()
	_ok(p.d["units"].size() == 4 and (p.d["party"] as Array).size() == 3, "nothing is hidden on the website")

	print("\n%s" % ("ALL PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)
