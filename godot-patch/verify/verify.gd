# Compiles the patch scripts and drives both arena clients against a fake server, so the files in
# this folder are checked rather than merely written. It proves each client's shape and logic —
# it cannot prove integration with the real game, which needs the Godot project.
#
#   the WAGER client   — the website's Chikiseum: SOL stakes, deposits, payouts
#   the SEASON client  — the iOS app's Chikiseum: nothing staked, the server hosts the match and
#                        pays the winner in fantasy fish, eggs and resources
#
# Run:
#   cp ../*.gd .
#   godot --headless --path . --import
#   godot --headless --path . --script verify.gd
#
# The JavaScript half of the same revision has its own harnesses, which need no Godot:
#   node ../chiki-ios.test.mjs        # the app's crypto lockdown and Realm Link sign-in
#   node ../loader-policy.test.mjs    # that realm/index.html still wires them up
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
func transport(route: String, body: Dictionary) -> Dictionary:
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
		# --- the stake-free season match (the iOS app's only PvP mode) ---
		"season_board":
			return {"season": {"id": "s3", "name": "Season 3", "ends_in": 183600, "enabled": true},
				"you": {"rank": 41, "rating": 1180, "wins": 12, "losses": 7, "streak": 3,
					"matches_today": 4, "daily_cap": 20},
				"rewards": {
					"win": [{"kind": "fantasy_fish", "id": "aurelfin", "label": "Aurelfin", "weight": 0.55},
						{"kind": "egg", "id": "normal_egg", "label": "Chikimon Egg", "weight": 0.2}],
					"loss": [{"kind": "resource", "id": "berry", "label": "Berry", "qty": 3}]}}
		"season_queue":
			# join answers with the pairing the moment one exists — which here is immediately.
			if String(body.get("action", "")) == "leave":
				return {"queued": false, "status": "left"}
			return {"queued": false, "status": "paired", "match_id": "m77"}
		"season_state":
			return {"queued": false, "status": "decided", "reward_pending": true,
				"reward_match_id": "m77", "you": {"wins": 13, "losses": 7, "streak": 4}}
		"season_claim":
			return {"rewards": [{"kind": "fantasy_fish", "id": "aurelfin", "label": "Aurelfin", "qty": 2}],
				"odds": {"fantasy_fish": "55%", "egg": "20%"},
				"you": {"rank": 38, "wins": 13, "losses": 7, "streak": 4}}
	return {"error": "unknown route", "code": "NOT_FOUND"}


## A third transport: a match that is OVER and owes nothing. This is the case that used to strand
## the panel — match_id stayed set, _sync_buttons() computed fighting = true, and "Find a match" was
## dead for the rest of the session after the first loss that paid no prize.
func terminal_transport(route: String, _body: Dictionary) -> Dictionary:
	calls.append(route)
	match route:
		"season_state":
			return {"queued": false, "status": "decided", "reward_pending": false,
				"you": {"wins": 13, "losses": 8, "streak": 0}}
		"season_queue":
			return {"queued": false, "status": "paired", "match_id": "m99"}
	return {"error": "unknown route", "code": "NOT_FOUND"}


## A second transport, for the refusals the season client must surface rather than swallow.
func refusing_transport(route: String, _body: Dictionary) -> Dictionary:
	calls.append(route)
	match route:
		"season_queue":
			return {"error": "You have had every rewarded match today", "code": "DAILY_CAP"}
		"season_state":
			return {"error": "the season is over", "code": "SEASON_CLOSED"}
		"season_board":
			return {"error": "rate limited", "code": "RATE_LIMIT"}
	return {"error": "unknown route", "code": "NOT_FOUND"}


func _init() -> void:
	print("\n== compile ==")
	var scripts := {}
	for f in ["ChikiseumRehearsalLobby.gd", "ChikiseumWagerClient.gd", "ChikiseumWagerPanel.gd",
			"ChikiseumSeasonClient.gd", "ChikiseumSeasonPanel.gd"]:
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

	print("\n== wager contract ==")
	check(calls.all(func(r): return r in C.ROUTES), "every route called is one the server serves")
	check(C.ROUTES.size() == 6, "six wager routes")
	check(C.sol_text(0.01) == "0.01 SOL", "SOL is formatted without trailing zeros")
	check(C.lamports_to_sol(50000000) == 0.05, "lamports convert exactly")
	check(C.next_step({"status": "settling", "you": {}}) == "Paying out…", "settling is explained")

	# -----------------------------------------------------------------------------------------
	# The season match: PvP with nothing staked. This is the iOS app's ONLY PvP mode, and it must
	# reach a prize without ever touching a wallet, a stake, a treasury or a signature.
	# -----------------------------------------------------------------------------------------
	print("\n== season client ==")
	calls.clear()
	var S = scripts["ChikiseumSeasonClient.gd"]
	var s = S.new()
	get_root().add_child(s)
	s.bind_transport(Callable(self, "transport"))
	check(s.is_ready(), "transport binds")

	var got := {"queued": -1, "matched": "", "ready": "", "rewards": [], "failed": ""}
	s.queued.connect(func(pos, _eta): got["queued"] = pos)
	s.matched.connect(func(mid): got["matched"] = mid)
	s.reward_ready.connect(func(mid): got["ready"] = mid)
	s.rewarded.connect(func(items, _odds): got["rewards"] = items)
	s.failed.connect(func(code, msg): got["failed"] = code + " | " + msg)

	await s.refresh_board()
	check(String(s.season.get("name", "")) == "Season 3", "the season is read from the server")
	check(int(s.standing.get("daily_cap", 0)) == 20, "the daily cap is read back, not hardcoded")
	check(s.prizes.has("win") and s.prizes.has("loss"), "the prize table is the server's")

	await s.join_queue()
	check(got["matched"] == "m77", "the server pairs and hosts — no stake, no deposit, no accept step")
	check(not s.in_queue, "a paired player is out of the queue")

	await s.poll()
	check(got["ready"] == "m77", "a decided match announces that a prize is waiting")
	check(int(s.standing.get("wins", 0)) == 13, "the standing updates from the poll")

	await s.claim("m77")
	check(got["rewards"].size() == 1, "the prize is a real item, not a balance")
	check(String(got["rewards"][0].get("kind", "")) == "fantasy_fish", "and it is a fantasy fish")
	check(s.match_id == "", "claiming clears the owed match so it cannot be claimed twice")

	print("\n== a finished match releases the panel ==")
	var s3 = S.new()
	get_root().add_child(s3)
	s3.bind_transport(Callable(self, "terminal_transport"))
	await s3.join_queue()
	check(s3.match_id == "m99", "a match is held while it is live")
	await s3.poll()
	check(s3.match_id == "", "a decided match that owes nothing CLEARS match_id")
	check(not s3.in_queue, "and leaves the queue")
	check(int(s3.standing.get("losses", 0)) == 8, "the standing still updates from that poll")
	# The panel's gate is `client.match_id != "" and _reward_match == ""`, so this is what unsticks it.
	await s3.join_queue()
	check(s3.match_id == "m99", "so the player can queue again straight away")

	print("\n== season refusals reach the player ==")
	var s2 = S.new()
	get_root().add_child(s2)
	s2.bind_transport(Callable(self, "refusing_transport"))
	var refused := {"code": ""}
	s2.failed.connect(func(code, msg): refused["code"] = code + " | " + msg)
	await s2.join_queue()
	check(refused["code"].begins_with("DAILY_CAP"), "the daily cap reaches the UI with its code")
	check(refused["code"].contains("Come back tomorrow"), "and is phrased for a player")
	# A routine poll must stay quiet about blips, but never about the season ending under the player.
	refused["code"] = ""
	await s2.refresh_board()
	check(refused["code"].begins_with("RATE_LIMIT"), "a write refusal is always reported")
	refused["code"] = ""
	await s2.poll()
	check(refused["code"].begins_with("SEASON_CLOSED"), "a poll still reports the season closing")

	print("\n== season contract ==")
	check(calls.all(func(r): return r in S.ROUTES), "every route called is one the server serves")
	check(S.ROUTES.size() == 4, "four season routes")
	check(S.ROUTES.all(func(r): return not r.begins_with("wager")), "not one of them is a wager route")
	check(S.reward_text({"label": "Aurelfin", "qty": 2}) == "Aurelfin ×2", "a stack is named with its count")
	check(S.reward_text({"label": "Aurelfin"}) == "Aurelfin", "a single item is not named ×1")
	# String.capitalize() is Godot's snake_case→Title Case, so "sea_legend" becomes "Sea Legend".
	check(S.reward_text({"id": "sea_legend"}) == "Sea Legend", "an unknown prize still reads as something")
	check(S.rewards_text([{"label": "Aurelfin", "qty": 2}, {"label": "Berry", "qty": 3}])
		== "Aurelfin ×2, Berry ×3", "a whole haul reads as one line")
	check(S.countdown_text(183600) == "2d 3h", "the season countdown reads in days and hours")
	check(S.countdown_text(0) == "", "a season with no end shows no countdown")
	check(S.next_step({"status": "queued"}) == "Finding an opponent…", "queueing is explained")
	check(S.next_step({"reward_pending": true}) == "Collect your prize.", "a waiting prize wins over status")

	print("\nroutes exercised: %s" % ", ".join(calls))
	print("failures: %d\n" % failures)
	quit(1 if failures > 0 else 0)
