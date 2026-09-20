# The season pill: queue for a hosted match, fight a real player, collect what you won.
#
# This is the wager panel's counterpart for a client that has no wallet. Same place in the
# Chikiseum, same shape on screen, and none of the money: there is no stake to set, nothing to
# deposit, no treasury and no payout legs to watch. The player presses one button, the server
# finds them an opponent and hosts the match, and the winner's prize is rolled server-side.
#
# Built to be dropped in as a Control with no scene dependencies — it constructs its own children
# — so it can be parented to the Chikiseum gate next to the Cup without touching that scene's
# layout. Replace _build_ui() with the real skin once the look is decided; every other method is
# the behaviour and should survive the reskin.
#
# It owns no reward logic. The prize table, the odds, the daily cap and the roll are the server's;
# this reads them back and shows them. Three rules it does enforce, because they are honesty rules:
#   * never show a prize as won before the server says the match is decided
#   * never print odds this client made up — an unknown prize table shows as unknown
#   * never imply the prize is app-only play money: it is the real asset, on the real account
class_name ChikiseumSeasonPanel
extends Control

signal enter_match_requested(match_id: String)
signal closed()

const IDLE_REFRESH_SECONDS := 8.0      ## the board barely moves when nothing is happening
const LIVE_POLL_SECONDS := 2.0         ## queued or fighting: the player is waiting on this

var client: ChikiseumSeasonClient
var _timer := 0.0
var _status := ""
var _reward_match := ""

# NOT @onready. These are assigned by _build_ui(), which setup() calls — and setup() may well run
# before this Control is added to the tree. @onready assigns at tree-entry, so it would overwrite
# every reference with null AFTER _build_ui() had filled them, and the panel would silently render
# nothing. (The wager panel carries the same pattern; it has the same hazard.)
var _standing_label: Label = null
var _season_label: Label = null
var _prize_box: VBoxContainer = null
var _status_label: Label = null
var _queue_button: Button = null
var _claim_button: Button = null


func setup(season_client: ChikiseumSeasonClient) -> void:
	client = season_client
	client.board_updated.connect(_on_board)
	client.queued.connect(_on_queued)
	client.matched.connect(_on_matched)
	client.reward_ready.connect(_on_reward_ready)
	client.rewarded.connect(_on_rewarded)
	client.failed.connect(func(_code, message): _say(message))
	_build_ui()
	_refresh()


func _process(delta: float) -> void:
	if not visible or client == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	# Poll hard only while the player is actually waiting on the server for something.
	var live := client.in_queue or client.match_id != ""
	_timer = LIVE_POLL_SECONDS if live else IDLE_REFRESH_SECONDS
	_tick(live)                            # deliberately not awaited: _process must not suspend


func _tick(live: bool) -> void:
	if live:
		await client.poll()
	else:
		await client.refresh_board()


func _refresh() -> void:
	if client == null or client.busy:
		return
	await client.refresh_board()
	await client.poll()


# ---------------------------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------------------------

func _on_queue_pressed() -> void:
	if client == null:
		return
	if client.in_queue:
		_say("Leaving the queue…")
		await client.leave_queue()
		_say("You left the queue.")
	else:
		_say("Looking for an opponent…")
		await client.join_queue()
	_sync_buttons()


func _on_claim_pressed() -> void:
	if client == null or _reward_match == "":
		return
	_claim_button.disabled = true
	_say("Opening your prize…")
	await client.claim(_reward_match)


# ---------------------------------------------------------------------------------------------
# Signals in
# ---------------------------------------------------------------------------------------------

func _on_board(season: Dictionary, standing: Dictionary, prizes: Dictionary) -> void:
	if _season_label:
		# NOT `name` — that is Node.name, and shadowing it here is a GDScript error.
		var season_name := String(season.get("name", "Season"))
		var left := ChikiseumSeasonClient.countdown_text(int(season.get("ends_in", 0)))
		_season_label.text = season_name if left == "" else "%s · %s left" % [season_name, left]

	if _standing_label:
		_standing_label.text = _standing_text(standing)

	_render_prizes(prizes)
	_sync_buttons()


func _on_queued(position: int, eta_seconds: int) -> void:
	# Position 0 means the server is not counting places — don't invent one.
	if position > 0:
		_say("In the queue — %d ahead of you%s." % [position, _eta_suffix(eta_seconds)])
	else:
		_say("In the queue — finding an opponent%s." % _eta_suffix(eta_seconds))
	_sync_buttons()


func _on_matched(match_id: String) -> void:
	_say("Opponent found. The arena is hosting your match…")
	_sync_buttons()
	enter_match_requested.emit(match_id)


func _on_reward_ready(match_id: String) -> void:
	_reward_match = match_id
	_say("Your match is decided — collect your prize.")
	_sync_buttons()


func _on_rewarded(rewards: Array, odds: Dictionary) -> void:
	_reward_match = ""
	if rewards.is_empty():
		# A decided match with no items is a real outcome, not an error: say so plainly rather
		# than leaving the player staring at a ceremony that never resolves.
		_say("No prize from that one. Queue again.")
	else:
		_say("You won %s — it is on your account." % ChikiseumSeasonClient.rewards_text(rewards))
	# The odds the server actually rolled against, when it sends them. Never reconstructed here.
	if not odds.is_empty() and _prize_box:
		_prize_box.add_child(_note(_odds_text(odds)))
	_sync_buttons()


# ---------------------------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------------------------

func _standing_text(standing: Dictionary) -> String:
	if standing.is_empty():
		return "Your first season match is waiting."
	var parts: PackedStringArray = []
	if standing.has("rank"):
		parts.append("rank %d" % int(standing["rank"]))
	parts.append("%d–%d" % [int(standing.get("wins", 0)), int(standing.get("losses", 0))])
	var streak := int(standing.get("streak", 0))
	if streak > 1:
		parts.append("%d in a row" % streak)
	# The cap is the server's and can change without a client release, so it is read back rather
	# than written in. Show it: a refusal the player could have predicted is a bad one.
	var cap := int(standing.get("daily_cap", 0))
	if cap > 0:
		parts.append("%d/%d rewarded today" % [int(standing.get("matches_today", 0)), cap])
	return " · ".join(parts)


func _render_prizes(prizes: Dictionary) -> void:
	if _prize_box == null:
		return
	for child in _prize_box.get_children():
		child.queue_free()
	if prizes.is_empty():
		_prize_box.add_child(_note("The prize table is loading…"))
		return
	for bucket in ["win", "loss", "streak_bonus"]:
		var rows: Variant = prizes.get(bucket, [])
		if typeof(rows) != TYPE_ARRAY or rows.is_empty():
			continue
		_prize_box.add_child(_note(_bucket_title(bucket)))
		for reward in rows:
			if typeof(reward) != TYPE_DICTIONARY:
				continue
			_prize_box.add_child(_note("  " + _prize_line(reward)))
	_prize_box.add_child(_note("Prizes land on your account — the same one the website shows."))


func _bucket_title(bucket: String) -> String:
	match bucket:
		"win":          return "Win"
		"loss":         return "Play"          # losing still pays something; don't call it "Loss"
		"streak_bonus": return "On a streak"
	return bucket.capitalize()


## "Aurelfin — 55%", or just the name when the server did not send a weight. Never a guessed odd.
func _prize_line(reward: Dictionary) -> String:
	var text := ChikiseumSeasonClient.reward_text(reward)
	if not reward.has("weight"):
		return text
	var pct := float(reward["weight"]) * 100.0
	return "%s — %s%%" % [text, String.num(pct, 1).rstrip("0").rstrip(".")]


func _odds_text(odds: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key in odds.keys():
		parts.append("%s %s" % [String(key).capitalize(), String(odds[key])])
	if parts.is_empty():
		return ""
	return "Rolled against " + ", ".join(parts)


func _eta_suffix(eta_seconds: int) -> String:
	return "" if eta_seconds <= 0 else " · about %ds" % eta_seconds


func _sync_buttons() -> void:
	if client == null:
		return
	if _queue_button:
		var fighting := client.match_id != "" and _reward_match == ""
		_queue_button.text = "Leave queue" if client.in_queue else "Find a match"
		# While a hosted match is live there is nothing to queue for, and leaving it is a forfeit
		# the server decides — not something this button should offer.
		_queue_button.disabled = fighting
	if _claim_button:
		_claim_button.visible = _reward_match != ""
		_claim_button.disabled = false


func _build_ui() -> void:
	var root := VBoxContainer.new()
	add_child(root)

	var title := HBoxContainer.new()
	title.add_child(_text("Chikiseum · season match"))
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): closed.emit())
	title.add_child(close)
	root.add_child(title)

	_season_label = _text("Season")
	root.add_child(_season_label)
	_standing_label = _note("")
	root.add_child(_standing_label)

	var actions := HBoxContainer.new()
	_queue_button = Button.new()
	_queue_button.text = "Find a match"
	_queue_button.pressed.connect(_on_queue_pressed)
	actions.add_child(_queue_button)
	_claim_button = Button.new()
	_claim_button.text = "Collect prize"
	_claim_button.visible = false
	_claim_button.pressed.connect(_on_claim_pressed)
	actions.add_child(_claim_button)
	root.add_child(actions)

	root.add_child(_note("Free to enter. The arena hosts the match; the winner takes fish, eggs and resources."))

	_prize_box = VBoxContainer.new()
	root.add_child(_prize_box)

	_status_label = _note("")
	root.add_child(_status_label)


func _say(message: String) -> void:
	_status = message
	if _status_label:
		_status_label.text = message


func _text(value: String) -> Label:
	var label := Label.new()
	label.text = value
	return label


func _note(value: String) -> Label:
	var label := _text(value)
	label.modulate = Color(1, 1, 1, 0.7)
	return label
