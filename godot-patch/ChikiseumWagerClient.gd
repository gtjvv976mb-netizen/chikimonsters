# Speaks the six SOL wager routes. Holds no key, decides nothing, and trusts nothing it is told
# about money — every amount, cap and outcome in here is whatever the server last said.
#
# Transport-agnostic on purpose: bind it to the existing ChikiseumLiveClient's command function
# and it inherits authentication, the window.fetch guard and error handling unchanged. The only
# edit needed in the existing client is adding the six route names to its allowlist (see
# README §1) — without that, every call here is blocked before it leaves the browser.
#
#   var wagers := ChikiseumWagerClient.new()
#   add_child(wagers)
#   wagers.bind_transport(Callable(live_client, "command"))
#
# States a wager moves through, server-side:
#   posted → open → accepting → funded → matched → settling → settled | refunded
#   with expired / void for ones that were never funded. Only `matched` produces a battle.
class_name ChikiseumWagerClient
extends Node

signal board_updated(board: Array)          ## open challenges others can accept
signal mine_updated(active: Dictionary, pending: Array, recent: Array)
signal deposit_required(wager: Dictionary)  ## this wallet must pay its stake now
signal matched(match_id: String, wager: Dictionary)
signal refunding(wager: Dictionary, reason: String)
signal failed(code: String, message: String)

const ROUTES := ["wager_board", "wager_mine", "wager_post", "wager_accept", "wager_withdraw", "wager_deposit"]
const LAMPORTS_PER_SOL := 1_000_000_000

var treasury := ""                          ## where deposits must be sent; from the server
var limits := {}                            ## min/max/daily, from health().wagers
var active: Dictionary = {}                 ## this wallet's live wager, if any
var busy := false

var _command: Callable


func bind_transport(command: Callable) -> void:
	_command = command


func is_ready() -> bool:
	return _command.is_valid()


# ---------------------------------------------------------------------------------------------
# Reads
# ---------------------------------------------------------------------------------------------

## Open challenges. Also refreshes `treasury`, which every deposit needs.
func refresh_board() -> Array:
	var response := await _call("wager_board", {})
	if response.is_empty():
		return []
	treasury = String(response.get("deposit_to", treasury))
	limits = response.get("wagers", limits)
	var board: Array = response.get("board", [])
	board_updated.emit(board)
	return board


## This wallet's own wagers: the live one, ones whose payout is still in flight, and recent
## finished ones. A wager in `pending` is settled as far as the fight goes — the money is just
## still moving — so it does NOT block posting a new one.
func refresh_mine() -> Dictionary:
	var response := await _call("wager_mine", {})
	if response.is_empty():
		return {}
	treasury = String(response.get("deposit_to", treasury))
	active = response.get("active", {}) if typeof(response.get("active")) == TYPE_DICTIONARY else {}
	var pending: Array = response.get("pending", [])
	var recent: Array = response.get("recent", [])
	mine_updated.emit(active, pending, recent)
	_announce(active)
	return response


# ---------------------------------------------------------------------------------------------
# Writes
# ---------------------------------------------------------------------------------------------

## Post a challenge. It does NOT appear on the board until this wallet's stake is paid, so a
## post always leads straight to a deposit — no unfunded bait is ever shown to anyone.
func post(stake_sol: float) -> Dictionary:
	var response := await _call("wager_post", {"stake_sol": stake_sol})
	return _absorb(response)


## Lock someone's open challenge. The server checks the fighters are compatible and that the
## challenger is still in the arena; both refusals are reported, not guessed at.
func accept(wager_id: String) -> Dictionary:
	var response := await _call("wager_accept", {"wager_id": wager_id})
	return _absorb(response)


## Back out. Before funding this is free; after funding it refunds. Once the match exists the
## server refuses — at that point the fight decides the money, which is the whole point.
func withdraw(wager_id: String) -> Dictionary:
	var response := await _call("wager_withdraw", {"wager_id": wager_id})
	return _absorb(response)


## Hand the server a deposit transaction signature. It reads the transaction off-chain-of-us —
## from the chain itself — and credits it only if this wallet signed, the treasury gained the
## stake, and the memo names this wager and side.
##
## DEPOSIT_UNVERIFIED is not a failure: it means the transaction has not landed yet. Retry.
func submit_deposit(wager_id: String, signature: String) -> Dictionary:
	var response := await _call("wager_deposit", {"wager_id": wager_id, "signature": signature})
	if response.is_empty():
		return {}
	# Funding the second side both creates the match and answers here, in one step: there is no
	# window in which two stakes are held with no match.
	if response.get("matched", false) == true:
		var match_id := String(response.get("match_id", ""))
		if match_id != "":
			matched.emit(match_id, response.get("wager", {}))
	elif response.get("refunding", false) == true:
		refunding.emit(response.get("wager", {}),
			String(response.get("reason", "Both stakes are being refunded.")))
	return _absorb(response)


# ---------------------------------------------------------------------------------------------
# Presentation helpers — so every screen formats money the same way.
# ---------------------------------------------------------------------------------------------

static func sol_text(sol: float) -> String:
	return String.num(sol, 4).rstrip("0").rstrip(".") + " SOL"

static func lamports_to_sol(lamports: int) -> float:
	return float(lamports) / float(LAMPORTS_PER_SOL)

## What this wallet must do next, in one line, or "" when it is waiting on someone else.
static func next_step(wager: Dictionary) -> String:
	var you: Dictionary = wager.get("you", {})
	if you.get("deposit_required", false) == true:
		return "Pay your stake to enter."
	match String(wager.get("status", "")):
		"posted":    return "Waiting for your stake."
		"open":      return "On the board — waiting for an opponent."
		"accepting": return "Someone accepted. Waiting for their stake."
		"funded":    return "Both paid. Starting the match…"
		"matched":   return "Fight!"
		"settling":  return "Paying out…"
		"settled":   return "Settled."
		"refunded":  return "Refunded."
		"expired", "void": return "Closed — nothing was staked."
	return ""


# ---------------------------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------------------------

func _call(route: String, body: Dictionary) -> Dictionary:
	if not _command.is_valid():
		failed.emit("NO_TRANSPORT", "The arena connection is not attached.")
		return {}
	if busy:
		# One wager command at a time. These move money; overlapping them is never worth it.
		failed.emit("BUSY", "Finishing the last request…")
		return {}
	busy = true
	var response: Variant = await _command.call(route, body)
	busy = false

	if typeof(response) != TYPE_DICTIONARY:
		failed.emit("UNAVAILABLE", "The arena did not answer.")
		return {}
	if response.has("error"):
		var code := String(response.get("code", "INVALID_COMMAND"))
		failed.emit(code, _friendly(code, String(response["error"])))
		return {}
	return response


func _absorb(response: Dictionary) -> Dictionary:
	if response.is_empty():
		return {}
	var wager: Dictionary = response.get("wager", {})
	if not wager.is_empty():
		active = wager
		_announce(wager)
	return wager


func _announce(wager: Dictionary) -> void:
	if wager.is_empty():
		return
	var you: Dictionary = wager.get("you", {})
	if you.get("deposit_required", false) == true:
		deposit_required.emit(wager)


## The server's messages are already written for players; these only soften the few codes whose
## wording is about protocol rather than about what the player should do.
func _friendly(code: String, message: String) -> String:
	match code:
		"WAGERS_DISABLED":   return "Wagers are switched off right now."
		"DEPOSIT_UNVERIFIED": return "Your payment has not landed yet — retrying."
		"DEPOSIT_REPLAYED":  return "That payment was already used."
		"WAGER_BUSY":        return "Finish your current wager first."
		"ACCOUNT_BUSY":      return "Finish your current match first."
		"CHALLENGER_AWAY":   return "That challenger has left the arena."
		"INCOMPATIBLE":      return "Your fighter is outside this wager's matchmaking band."
		"RATE_LIMIT":        return "Too quick — try again in a moment."
		"UNAVAILABLE":       return "The arena is restarting. Try again shortly."
	return message
