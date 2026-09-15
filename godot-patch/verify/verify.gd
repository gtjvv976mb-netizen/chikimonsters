# Compiles the patch scripts and drives the wager client against a fake server, so the files in
# this folder are checked rather than merely written. It proves the client's shape and logic —
# it cannot prove integration with the real game, which needs the Godot project.
#
# Run:
#   cp ../*.gd .
#   godot --headless --path . --import
#   godot --headless --path . --script verify.gd
#
# Exits non-zero if anything fails.
extends SceneTree

var calls: Array[String] = []
var failures := 0

func check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    ", label)
	else:
		failures += 1
		print("  FAIL  ", label)

## Stands in for the game's live client: returns what the real server returns for each route.
func transport(route: String, _body: Dictionary) -> Dictionary:
	calls.append(route)
	match route:
		"wager_board":
			return {"deposit_to": "Treasury111",
				"wagers": {"min_stake_sol": 0.001, "max_stake_sol": 0.05, "wallet_daily_sol": 0.25},
				"board": [{"id": "w9", "stake_sol": 0.01, "yours": false,
					"challenger": {"handle": "Ken", "fighter": {"display_name": "Galador"}}}]}
		"wager_mine":
			return {"deposit_to": "Treasury111", "active": {}, "pending": [], "recent": []}
		"wager_post":
			return {"wager": {"id": "w1", "status": "posted", "stake_sol": 0.01,
				"you": {"side": "A", "deposit_required": true, "deposit_lamports": 10000000,
					"memo": "chikiseum-wager:w1:A"}}}
		"wager_deposit":
			return {"matched": true, "match_id": "m42",
				"wager": {"id": "w1", "status": "matched", "stake_sol": 0.01, "match_id": "m42", "you": {}}}
		"wager_accept":
			return {"error": "Your fighter is outside this wager's matchmaking limits", "code": "INCOMPATIBLE"}
		"wager_withdraw":
			return {"wager": {"id": "w1", "status": "void", "stake_sol": 0.01, "you": {}}}
	return {"error": "unknown route", "code": "NOT_FOUND"}


func _init() -> void:
	print("\n== compile ==")
	var scripts := {}
	for f in ["ChikiseumRehearsalLobby.gd", "ChikiseumWagerClient.gd", "ChikiseumWagerPanel.gd"]:
		var s = load("res://" + f)
		check(s != null and s.can_instantiate(), "%s compiles" % f)
		scripts[f] = s

	print("\n== rehearsal lobby ==")
	var R = scripts["ChikiseumRehearsalLobby.gd"]
	var lobby := {"rehearsal_available": true, "trainers": [
		{"trainer_id": "human1", "handle": "Ken", "rehearsal": false, "instant": false,
			"fighter": {"display_name": "Galador"}},
		{"trainer_id": "ai-x", "handle": "Training Dummy (AI)", "rehearsal": true, "instant": true,
			"fighter": {"display_name": "Galador"}}]}
	var bot: Dictionary = R.find(lobby)
	check(R.is_available(lobby), "rehearsal_available is read")
	check(bot.get("trainer_id") == "ai-x", "the dummy is found by its flag, not its handle")
	check(R.is_instant(bot), "instant is read — no accept step")
	check(R.humans(lobby).size() == 1, "humans() excludes the dummy")
	check(R.label_for({"handle": "Dummy"}) == "Dummy (AI)", "an unmarked handle is still marked AI")
	# A lobby whose dummy is withdrawn must yield nothing, not the first human.
	var off := {"rehearsal_available": false, "trainers": [lobby["trainers"][0]]}
	check(R.find(off).is_empty(), "no dummy when rehearsal is withdrawn")
	check(not R.is_available(off), "withdrawal is reported")

	print("\n== wager client ==")
	var C = scripts["ChikiseumWagerClient.gd"]
	var c = C.new()
	get_root().add_child(c)
	c.bind_transport(Callable(self, "transport"))
	check(c.is_ready(), "transport binds")

	var seen := {"deposit": "", "matched": "", "failed": ""}
	c.deposit_required.connect(func(w): seen["deposit"] = str(w.get("id")))
	c.matched.connect(func(mid, _w): seen["matched"] = mid)
	c.failed.connect(func(code, msg): seen["failed"] = code + " | " + msg)

	await c.refresh_board()
	check(c.treasury == "Treasury111", "treasury address is taken from the server")
	check(float(c.limits.get("max_stake_sol", 0.0)) == 0.05, "caps are read back, not hardcoded")

	var w: Dictionary = await c.post(0.01)
	check(w.get("id") == "w1", "post returns the wager")
	check(seen["deposit"] == "w1", "deposit_required fires for the poster")
	check(C.next_step(w) == "Pay your stake to enter.", "next step is the deposit")

	await c.submit_deposit("w1", "sig")
	check(seen["matched"] == "m42", "funding the second side emits the match")

	await c.accept("w9")
	check(seen["failed"].begins_with("INCOMPATIBLE"), "a server refusal reaches the UI with its code")
	check(seen["failed"].contains("matchmaking band"), "the refusal is phrased for a player")

	print("\n== contract ==")
	check(calls.all(func(r): return r in C.ROUTES), "every route called is one the server serves")
	check(C.ROUTES.size() == 6, "six wager routes")
	check(C.sol_text(0.01) == "0.01 SOL", "SOL is formatted without trailing zeros")
	check(C.lamports_to_sol(50000000) == 0.05, "lamports convert exactly")
	check(C.next_step({"status": "settling", "you": {}}) == "Paying out…", "settling is explained")

	print("\nroutes exercised: %s" % ", ".join(calls))
	print("failures: %d\n" % failures)
	quit(1 if failures > 0 else 0)
