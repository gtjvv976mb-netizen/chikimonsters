# Speaks the four SEASON MATCH routes: PvP against real players with nothing staked.
#
# WHY THIS EXISTS BESIDE ChikiseumWagerClient
#
# The wager client posts a challenge, takes a SOL stake from each side and pays the winner. That is
# the website's Chikiseum. The iOS app cannot do any of it — it has no wallet, signs nothing and is
# refused every wager route before the request leaves the device (realm/chiki-ios.js §3). But the
# app must still fight real players, so the stake is replaced rather than the fight:
#
#   the SERVER hosts the match, and pays the winner in FANTASY FISH, EGGS AND RESOURCES.
#
# Those are the same rewards the Wicked Temple's Treasure Vault already awards, from the same
# server-side roll — decided before the player presses anything, exactly as the temple wheel is.
# Nothing is bought, nothing is staked, nothing is lost, and there is no currency anywhere in it.
#
# THE PRIZES ARE THE REAL ASSETS, NOT A SEPARATE APP-ONLY CURRENCY. A fish won here is credited to
# the linked account exactly as one won on the website is, on-chain where the asset is on-chain,
# and it is waiting in the satchel next time the player opens chikimonsters.com. What the app does
# NOT carry is any way to SELL or TRADE it: the Trading Post and the marketplace are website-only,
# and every route and bridge that could reach them is refused on the device. Earning here, selling
# there — one account, one inventory, two different surfaces.
#
# Transport-agnostic, like the wager client: bind it to the existing ChikiseumLiveClient's command
# function and it inherits authentication, the window.fetch guard and error handling unchanged. The
# only edit needed in that client is adding these four route names to its allowlist (README §1).
#
#   var season := ChikiseumSeasonClient.new()
#   add_child(season)
#   season.bind_transport(Callable(live_client, "command"))
#
# States a season entry moves through, server-side:
#   idle → queued → paired → ready → active → decided → claimed
#   with `left` for a queue the player walked out of. Only `paired` produces a battle, and only
#   `decided` has a reward waiting.
class_name ChikiseumSeasonClient
extends Node

signal board_updated(season: Dictionary, standing: Dictionary, prizes: Dictionary)
signal queued(position: int, eta_seconds: int)   ## waiting for the server to find an opponent
signal matched(match_id: String)                 ## the server has hosted a match; go fight
signal reward_ready(match_id: String)            ## the fight is decided and a roll is waiting
signal rewarded(rewards: Array, odds: Dictionary)
signal failed(code: String, message: String)

const ROUTES := ["season_board", "season_queue", "season_state", "season_claim"]

## Statuses that mean the match is over. A terminal status with no reward owed releases the panel.
const TERMINAL := ["decided", "left", "idle", "cancelled", "forfeit"]

## Reward kinds the server may send. Kept as a list rather than an enum so a new one added
## server-side still renders (as its own label) instead of vanishing from the ceremony.
const KNOWN_KINDS := ["fantasy_fish", "egg", "resource", "coins", "xp", "cosmetic"]

var season := {}                     ## {id, name, ends_in, enabled}
var standing := {}                   ## {rank, rating, wins, losses, streak, matches_today, daily_cap}
var prizes := {}                     ## {win: [...], loss: [...], streak_bonus: [...]}
var match_id := ""                   ## the hosted match, while there is one
var in_queue := false
var busy := false

var _last_match := ""                ## the match just finished, so a late reward can still name it

var _command: Callable


func bind_transport(command: Callable) -> void:
	_command = command


func is_ready() -> bool:
	return _command.is_valid()


# ---------------------------------------------------------------------------------------------
# Reads
# ---------------------------------------------------------------------------------------------

## The season, this player's standing in it, and what winning and losing pay. Everything shown on
## the panel comes from here — no odds, cap or prize is hardcoded in the client, because the
## server is the only thing that actually rolls them.
func refresh_board() -> Dictionary:
	var response := await _call("season_board", {})
	if response.is_empty():
		return {}
	season = response.get("season", {}) if typeof(response.get("season")) == TYPE_DICTIONARY else {}
	standing = response.get("you", {}) if typeof(response.get("you")) == TYPE_DICTIONARY else {}
	prizes = response.get("rewards", {}) if typeof(response.get("rewards")) == TYPE_DICTIONARY else {}
	board_updated.emit(season, standing, prizes)
	return response


## Poll while queued or fighting. Deliberately exempt from the `busy` gate below: it runs on a
## timer, and making a routine poll emit BUSY behind a slower write would spam the panel with
## failures that are not failures.
func poll() -> Dictionary:
	var response := await _call("season_state", {}, true)
	if response.is_empty():
		return {}
	_absorb(response)
	return response


# ---------------------------------------------------------------------------------------------
# Writes
# ---------------------------------------------------------------------------------------------

## Join the queue. The server pairs by rating and fighter band, hosts the match itself, and
## answers with a match_id the moment a pairing exists — which can be immediately, so this
## handles both "you are waiting" and "you are fighting" from one call.
func join_queue() -> Dictionary:
	var response := await _call("season_queue", {"action": "join"})
	if response.is_empty():
		return {}
	_absorb(response)
	return response


## Leave the queue. Free and always allowed while queued; once a match exists the server refuses,
## because walking out of a hosted match is a forfeit, not a cancellation.
func leave_queue() -> Dictionary:
	var response := await _call("season_queue", {"action": "leave"})
	if response.is_empty():
		return {}
	in_queue = false
	_absorb(response)
	return response


## Claim the roll for a decided match. The result was rolled server-side when the match was
## decided — this only reveals and banks it, so pressing it late, twice or from another device
## returns the same items rather than rolling again.
func claim(for_match_id: String = "") -> Dictionary:
	var id := for_match_id
	if id == "":
		id = match_id if match_id != "" else _last_match
	if id == "":
		failed.emit("NOTHING_TO_CLAIM", "There is no finished match to collect.")
		return {}
	var response := await _call("season_claim", {"match_id": id})
	if response.is_empty():
		return {}
	var rewards: Array = response.get("rewards", [])
	var odds: Dictionary = response.get("odds", {}) if typeof(response.get("odds")) == TYPE_DICTIONARY else {}
	if response.has("you") and typeof(response["you"]) == TYPE_DICTIONARY:
		standing = response["you"]
	_last_match = id
	match_id = ""
	rewarded.emit(rewards, odds)
	return response


# ---------------------------------------------------------------------------------------------
# Presentation helpers — so every screen names a prize the same way.
# ---------------------------------------------------------------------------------------------

## "Aurelfin ×2", or just "Aurelfin" for a single item. The server's label wins; the id is only a
## fallback so an item this build has never heard of still reads as something.
static func reward_text(reward: Dictionary) -> String:
	var label := String(reward.get("label", ""))
	if label == "":
		label = String(reward.get("id", "Reward")).capitalize()
	var qty := int(reward.get("qty", 1))
	return label if qty <= 1 else "%s ×%d" % [label, qty]


## One line for a whole haul, for a toast or a chat line.
static func rewards_text(rewards: Array) -> String:
	var parts: PackedStringArray = []
	for reward in rewards:
		if typeof(reward) == TYPE_DICTIONARY:
			parts.append(reward_text(reward))
	return ", ".join(parts)


## What the player should do next, in one line, or "" when it is the server's move.
static func next_step(state: Dictionary) -> String:
	if state.get("reward_pending", false) == true:
		return "Collect your prize."
	match String(state.get("status", "")):
		"idle":    return "Queue for a match."
		"queued":  return "Finding an opponent…"
		"paired":  return "Opponent found. Entering…"
		"ready":   return "Waiting for both fighters…"
		"active":  return "Fight!"
		"decided": return "Collect your prize."
		"left":    return "You left the queue."
	return ""


## How long the season has left, as "4d 2h" / "2h 15m" / "9m". Empty when the season has no end.
static func countdown_text(seconds: int) -> String:
	if seconds <= 0:
		return ""
	var days := seconds / 86400
	var hours := (seconds % 86400) / 3600
	var minutes := (seconds % 3600) / 60
	if days > 0:
		return "%dd %dh" % [days, hours]
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	return "%dm" % max(minutes, 1)


# ---------------------------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------------------------

func _call(route: String, body: Dictionary, is_poll: bool = false) -> Dictionary:
	if not _command.is_valid():
		if not is_poll:
			failed.emit("NO_TRANSPORT", "The arena connection is not attached.")
		return {}
	if busy and not is_poll:
		failed.emit("BUSY", "Finishing the last request…")
		return {}
	if not is_poll:
		busy = true
	var response: Variant = await _command.call(route, body)
	if not is_poll:
		busy = false

	if typeof(response) != TYPE_DICTIONARY:
		if not is_poll:
			failed.emit("UNAVAILABLE", "The arena did not answer.")
		return {}
	if response.has("error"):
		var code := String(response.get("code", "INVALID_COMMAND"))
		# A poll that fails is a blip; a poll that fails because the season closed is not, so
		# those codes are always reported even from the timer.
		if not is_poll or code in ["SEASON_CLOSED", "SEASON_DISABLED", "NOT_ADMITTED"]:
			failed.emit(code, _friendly(code, String(response["error"])))
		return {}
	return response


## Take whatever a queue or state response says about where the player stands, and raise the one
## signal that changed. Written so the same function serves join_queue() and the poll timer —
## the server sends the same shape from both, and the panel must not care which it came from.
func _absorb(response: Dictionary) -> void:
	var status := String(response.get("status", ""))
	var new_match := String(response.get("match_id", ""))

	var was_queued := in_queue
	in_queue = response.get("queued", status == "queued") == true

	if typeof(response.get("you")) == TYPE_DICTIONARY:
		standing = response["you"]

	if new_match != "" and new_match != match_id:
		match_id = new_match
		in_queue = false
		matched.emit(new_match)
	elif in_queue and (not was_queued or response.has("position")):
		queued.emit(int(response.get("position", 0)), int(response.get("eta_s", 0)))

	if response.get("reward_pending", false) == true:
		# The match that owns the reward, even once the fight is over and match_id was cleared.
		var owed := String(response.get("reward_match_id", ""))
		if owed == "":
			owed = new_match if new_match != "" else (match_id if match_id != "" else _last_match)
		if owed != "":
			match_id = owed
			reward_ready.emit(owed)
	elif status in TERMINAL and match_id != "":
		# A FINISHED MATCH THAT OWES NOTHING MUST RELEASE THE PANEL. Without this, match_id stayed
		# set for the rest of the session: ChikiseumSeasonPanel._sync_buttons() computes
		# `fighting = client.match_id != "" and _reward_match == ""`, so one loss that paid no prize
		# left "Find a match" disabled until the game was restarted. Remember the id first — a later
		# poll may still announce a reward for it.
		_last_match = match_id
		match_id = ""
		in_queue = false


## The server's messages are already written for players; these only soften the few codes whose
## wording is about protocol rather than about what the player should do.
func _friendly(code: String, message: String) -> String:
	match code:
		"SEASON_DISABLED":  return "Season matches are switched off right now."
		"SEASON_CLOSED":    return "This season has ended. The next one starts soon."
		"NOT_ADMITTED":     return "Pick a chikimon for the arena first."
		"ALREADY_QUEUED":   return "You are already in the queue."
		"NOT_QUEUED":       return "You are not in the queue."
		"ACCOUNT_BUSY":     return "Finish your current match first."
		"DAILY_CAP":        return "You have had every rewarded match today. Come back tomorrow."
		"INCOMPATIBLE":     return "No opponent in your band right now — try again in a moment."
		"ALREADY_CLAIMED":  return "You have already collected that prize."
		"MATCH_UNDECIDED":  return "That match is not finished yet."
		"RATE_LIMIT":       return "Too quick — try again in a moment."
		"UNAVAILABLE":      return "The arena is restarting. Try again shortly."
	return message
