# The wager pill: post a stake, take someone's, pay it, watch it settle.
#
# Built to be dropped in as a Control with no scene dependencies — it constructs its own children
# — so it can be parented to the Chikiseum gate next to the Cup without touching that scene's
# layout. Replace _build_ui() with the real skin once the look is decided; every other method is
# the behaviour and should survive the reskin.
#
# It owns no money logic. Caps, outcomes, who is owed what and when are the server's; this reads
# them back and shows them. Two rules it does enforce, because they are honesty rules:
#   * never show a stake as "yours to win" before the server says the wager is matched
#   * never show a payout as done until its leg reads `confirmed`
class_name ChikiseumWagerPanel
extends Control

signal enter_match_requested(match_id: String)
signal closed()

const REFRESH_SECONDS := 4.0
const DEPOSIT_POLL_SECONDS := 0.5
const DEPOSIT_CREDIT_ATTEMPTS := 24        # ≈ 72 s at 3 s apart: mainnet confirmation, comfortably

var client: ChikiseumWagerClient
var _stake := 0.001
var _timer := 0.0
var _status := ""
var _paying := false

@onready var _board_list: VBoxContainer = null
@onready var _mine_box: VBoxContainer = null
@onready var _status_label: Label = null
@onready var _stake_label: Label = null


func setup(wager_client: ChikiseumWagerClient) -> void:
	client = wager_client
	client.board_updated.connect(_on_board)
	client.mine_updated.connect(_on_mine)
	client.deposit_required.connect(_on_deposit_required)
	client.matched.connect(_on_matched)
	client.refunding.connect(func(_w, reason): _say(reason))
	client.failed.connect(func(_code, message): _say(message))
	_build_ui()
	_refresh()


func _process(delta: float) -> void:
	if not visible or client == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH_SECONDS
		_refresh()


func _refresh() -> void:
	if client == null or client.busy:
		return
	await client.refresh_mine()
	await client.refresh_board()


# ---------------------------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------------------------

func _on_post_pressed() -> void:
	_say("Posting %s…" % ChikiseumWagerClient.sol_text(_stake))
	await client.post(_stake)


func _on_accept_pressed(wager_id: String) -> void:
	_say("Accepting…")
	await client.accept(wager_id)


func _on_withdraw_pressed(wager_id: String) -> void:
	_say("Withdrawing…")
	await client.withdraw(wager_id)
	await _refresh()


func _on_deposit_required(wager: Dictionary) -> void:
	# Never pay automatically. Taking a player's SOL is always their explicit press.
	_say("%s — press Pay stake." % ChikiseumWagerClient.next_step(wager))


## The one path that moves real money. Everything it needs comes from the server: the treasury
## address, the exact lamports, and the memo that binds the payment to this wager and side.
func _on_pay_pressed(wager: Dictionary) -> void:
	if _paying:
		return
	var you: Dictionary = wager.get("you", {})
	var memo := String(you.get("memo", ""))
	var lamports := int(you.get("deposit_lamports", 0))
	if memo == "" or lamports <= 0 or client.treasury == "":
		_say("This deposit is not ready yet. Refresh and try again.")
		return
	if not OS.has_feature("web"):
		# Desktop has no wallet bridge. Say what to do rather than failing silently — the
		# transfer is perfectly valid if made by hand.
		_say("Send exactly %s to %s with the memo %s, from your wallet." % [
			ChikiseumWagerClient.sol_text(ChikiseumWagerClient.lamports_to_sol(lamports)),
			client.treasury, memo])
		return

	_paying = true
	var signature := await _sign_deposit(client.treasury, lamports, memo)
	if signature == "":
		_paying = false
		return                                    # _sign_deposit already explained why

	# The transaction is broadcast; the server still has to see it land. DEPOSIT_UNVERIFIED
	# means "not on chain yet", so it is retried rather than treated as a failure.
	_say("Payment sent. Waiting for confirmation…")
	var wager_id := String(wager.get("id", ""))
	for attempt in DEPOSIT_CREDIT_ATTEMPTS:
		await get_tree().create_timer(3.0).timeout
		var result := await client.submit_deposit(wager_id, signature)
		if not result.is_empty():
			_paying = false
			await _refresh()
			return
		if client.busy:
			continue
	_paying = false
	_say("Your payment has not appeared yet. It is not lost — reopen this panel in a minute and it will credit itself.")


## Drives chikiseum-wager-bridge.js. Returns the signature, or "" with the reason already shown.
func _sign_deposit(treasury: String, lamports: int, memo: String) -> String:
	var gate: Variant = JSON.parse_string(String(JavaScriptBridge.eval(
		"JSON.stringify((window.ChikiseumWagerBridge||{ready:function(){return {ok:false,error:'Wallet bridge not installed.'}}}).ready())", true)))
	if typeof(gate) != TYPE_DICTIONARY or gate.get("ok", false) != true:
		_say(String(gate.get("error", "No wallet available.")) if typeof(gate) == TYPE_DICTIONARY else "No wallet available.")
		return ""

	var request := JSON.stringify({"treasury": treasury, "lamports": lamports, "memo": memo})
	var started: Variant = JSON.parse_string(String(JavaScriptBridge.eval(
		"JSON.stringify(window.ChikiseumWagerBridge.pay(%s))" % JSON.stringify(request), true)))
	if typeof(started) != TYPE_DICTIONARY or not started.has("id"):
		_say("The wallet could not be opened.")
		return ""
	var job := String(started["id"])
	_say("Approve the payment in your wallet…")

	while true:
		await get_tree().create_timer(DEPOSIT_POLL_SECONDS).timeout
		var raw := String(JavaScriptBridge.eval(
			"JSON.stringify(window.ChikiseumWagerBridge.result(%s))" % JSON.stringify(job), true))
		var state: Variant = JSON.parse_string(raw)
		if typeof(state) != TYPE_DICTIONARY:
			_say("Lost track of the payment. Check your wallet before retrying.")
			return ""
		match String(state.get("status", "pending")):
			"pending":
				continue
			"sent":
				return String(state.get("signature", ""))
			"cancelled":
				_say("Payment cancelled. Nothing was sent.")
				return ""
			_:
				_say(String(state.get("error", "The payment failed.")))
				return ""
	return ""


func _on_matched(match_id: String, _wager: Dictionary) -> void:
	_say("Both stakes are in. Entering the arena…")
	enter_match_requested.emit(match_id)


# ---------------------------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------------------------

func _on_board(board: Array) -> void:
	if _board_list == null:
		return
	for child in _board_list.get_children():
		child.queue_free()
	if board.is_empty():
		_board_list.add_child(_note("No open challenges. Post one."))
		return
	for wager in board:
		_board_list.add_child(_board_row(wager))


func _on_mine(active: Dictionary, pending: Array, _recent: Array) -> void:
	if _mine_box == null:
		return
	for child in _mine_box.get_children():
		child.queue_free()
	if not active.is_empty():
		_mine_box.add_child(_mine_row(active))
	# A payout still moving is worth showing: the fight is over but the money has not landed,
	# and a player who sees nothing assumes they were not paid.
	for wager in pending:
		_mine_box.add_child(_mine_row(wager, true))


func _board_row(wager: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var challenger: Dictionary = wager.get("challenger", {})
	var fighter: Dictionary = challenger.get("fighter", {})
	row.add_child(_text("%s — %s (%s)" % [
		ChikiseumWagerClient.sol_text(float(wager.get("stake_sol", 0.0))),
		String(challenger.get("handle", "Trainer")),
		String(fighter.get("display_name", "?"))]))
	var button := Button.new()
	if wager.get("yours", false) == true:
		button.text = "Yours"
		button.disabled = true
	else:
		button.text = "Accept"
		button.pressed.connect(_on_accept_pressed.bind(String(wager.get("id", ""))))
	row.add_child(button)
	return row


func _mine_row(wager: Dictionary, payout_only := false) -> Control:
	var box := VBoxContainer.new()
	box.add_child(_text("Your wager — %s · %s" % [
		ChikiseumWagerClient.sol_text(float(wager.get("stake_sol", 0.0))),
		ChikiseumWagerClient.next_step(wager)]))

	var you: Dictionary = wager.get("you", {})
	var buttons := HBoxContainer.new()
	if you.get("deposit_required", false) == true:
		var pay := Button.new()
		pay.text = "Pay stake"
		pay.pressed.connect(_on_pay_pressed.bind(wager))
		buttons.add_child(pay)
	if not payout_only and String(wager.get("status", "")) in ["posted", "open", "accepting"]:
		var cancel := Button.new()
		cancel.text = "Withdraw"
		cancel.pressed.connect(_on_withdraw_pressed.bind(String(wager.get("id", ""))))
		buttons.add_child(cancel)
	if String(wager.get("status", "")) == "matched" and String(wager.get("match_id", "")) != "":
		var enter := Button.new()
		enter.text = "Enter match"
		enter.pressed.connect(func(): enter_match_requested.emit(String(wager.get("match_id", ""))))
		buttons.add_child(enter)
	if buttons.get_child_count() > 0:
		box.add_child(buttons)

	# Payout legs, honestly: only `confirmed` is money that has arrived.
	for leg in wager.get("legs", []):
		if typeof(leg) != TYPE_DICTIONARY:
			continue
		var state := String(leg.get("status", ""))
		var word := "paid" if state == "confirmed" else ("held for review" if state == "stuck" else "sending")
		box.add_child(_note("  %s %s — %s" % [
			String(leg.get("reason", "payout")),
			ChikiseumWagerClient.sol_text(float(leg.get("sol", 0.0))), word]))
	return box


func _build_ui() -> void:
	var root := VBoxContainer.new()
	add_child(root)

	var title := HBoxContainer.new()
	title.add_child(_text("Chikiseum wagers"))
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): closed.emit())
	title.add_child(close)
	root.add_child(title)

	var post_row := HBoxContainer.new()
	_stake_label = _text(ChikiseumWagerClient.sol_text(_stake))
	var down := Button.new(); down.text = "−"
	var up := Button.new(); up.text = "+"
	down.pressed.connect(func(): _nudge_stake(-1))
	up.pressed.connect(func(): _nudge_stake(1))
	var post := Button.new(); post.text = "Post challenge"
	post.pressed.connect(_on_post_pressed)
	post_row.add_child(down); post_row.add_child(_stake_label); post_row.add_child(up); post_row.add_child(post)
	root.add_child(post_row)

	_mine_box = VBoxContainer.new()
	root.add_child(_mine_box)
	root.add_child(_note("Open challenges"))
	_board_list = VBoxContainer.new()
	root.add_child(_board_list)

	_status_label = _note("")
	root.add_child(_status_label)
	# The caps are the server's and can change without a client release, so they are read back
	# rather than written in. Show them: a refusal the player could have predicted is a bad one.
	root.add_child(_note(_caps_text()))


func _caps_text() -> String:
	if client == null or client.limits.is_empty():
		return ""
	return "Stakes %s–%s · %s per day · your stake is held by the arena until the match is decided." % [
		ChikiseumWagerClient.sol_text(float(client.limits.get("min_stake_sol", 0.0))),
		ChikiseumWagerClient.sol_text(float(client.limits.get("max_stake_sol", 0.0))),
		ChikiseumWagerClient.sol_text(float(client.limits.get("wallet_daily_sol", 0.0)))]


func _nudge_stake(direction: int) -> void:
	var steps := [0.001, 0.005, 0.01, 0.025, 0.05]
	var index := steps.find(_stake)
	if index < 0:
		index = 0
	index = clampi(index + direction, 0, steps.size() - 1)
	_stake = steps[index]
	if _stake_label:
		_stake_label.text = ChikiseumWagerClient.sol_text(_stake)


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
