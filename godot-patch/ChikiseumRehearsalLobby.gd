# Finds the AI practice opponent in a lobby payload and starts a practice match correctly.
#
# The server offers one practice partner per trainer, mirroring their fighter exactly (same
# species, level and card tier), so it is always inside the matchmaking band. It is offered in
# the LOBBY only and is never placed in the matchmaking queue — "no AI fills the queue" stays
# literally true.
#
# Three rules this file exists to enforce:
#   1. Find it by the `rehearsal` FLAG, never by matching its handle. The flag is the contract;
#      "Training Dummy (AI)" is copy and may be translated or changed.
#   2. Never present it as another player. It is labelled AI everywhere it appears.
#   3. `instant` means challenge() returns a match_id straight away — there is no accept step,
#      and the dummy is already marked ready, so only the human presses Ready.
#
# Practice records no completion on the server, so it awards NO battle XP and cannot be farmed.
# Say so in the UI; players will otherwise assume it levels them.
class_name ChikiseumRehearsalLobby
extends RefCounted

const HANDLE_FALLBACK := "Training Dummy (AI)"

## True when this backend is offering practice at all (CHIK_REHEARSAL=off withdraws it,
## and withdrawal takes effect immediately — an existing dummy is revoked, not left to expire).
static func is_available(lobby: Dictionary) -> bool:
	return bool(lobby.get("rehearsal_available", false))

## The practice opponent from a lobby payload, or an empty Dictionary if none is offered.
static func find(lobby: Dictionary) -> Dictionary:
	for trainer in lobby.get("trainers", []):
		if typeof(trainer) == TYPE_DICTIONARY and trainer.get("rehearsal", false) == true:
			return trainer
	return {}

## Every trainer that is a real person. Use this for the "players here" list so the dummy is
## never mixed in with humans.
static func humans(lobby: Dictionary) -> Array:
	var out: Array = []
	for trainer in lobby.get("trainers", []):
		if typeof(trainer) == TYPE_DICTIONARY and trainer.get("rehearsal", false) != true:
			out.append(trainer)
	return out

## Display name, always marked. Never render a rehearsal trainer's handle unadorned.
static func label_for(trainer: Dictionary) -> String:
	var handle := String(trainer.get("handle", HANDLE_FALLBACK))
	return handle if handle.findn("(AI)") >= 0 else "%s (AI)" % handle

## One line of honest UI copy for the practice card.
static func description_for(trainer: Dictionary) -> String:
	var fighter: Dictionary = trainer.get("fighter", {})
	return "Practise against a copy of your own %s. Awards no battle XP." % String(
		fighter.get("display_name", "fighter"))

## True when challenging this trainer starts the match with no accept step.
static func is_instant(trainer: Dictionary) -> bool:
	return trainer.get("instant", false) == true


# ---------------------------------------------------------------------------------------------
# Starting one.
#
# `command` is the existing live client's command function — the same one used for queue and
# challenge — so this inherits authentication, the fetch guard and error handling unchanged.
# It must accept (route: String, body: Dictionary) and return the decoded response Dictionary.
#
#   var match_id := await ChikiseumRehearsalLobby.start(
#       Callable(live_client, "command"), ChikiseumRehearsalLobby.find(lobby))
#
# Returns "" if practice is unavailable or the server refused; the reason is in `last_error`.
# ---------------------------------------------------------------------------------------------
static var last_error := ""

static func start(command: Callable, trainer: Dictionary) -> String:
	last_error = ""
	if trainer.is_empty():
		last_error = "Practice is not available right now."
		return ""
	var target := String(trainer.get("trainer_id", ""))
	if target == "":
		last_error = "That practice opponent has gone."
		return ""

	var response: Variant = await command.call("challenge", {"target": target})
	if typeof(response) != TYPE_DICTIONARY:
		last_error = "The arena did not answer."
		return ""
	if response.has("error"):
		last_error = String(response["error"])
		return ""

	# The dummy has nobody to press accept for it, so the server starts the match immediately
	# and returns match_id here. A missing match_id means it was NOT the dummy after all —
	# treat that as a challenge sent to a human, not as a failure.
	var match_id := String(response.get("match_id", ""))
	if match_id == "":
		last_error = "Challenge sent — the other player must accept."
		return ""
	return match_id
