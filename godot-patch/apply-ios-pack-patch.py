#!/usr/bin/env python3
"""Make the compiled game hide what the iOS app is not allowed to present.

    python3 godot-patch/apply-ios-pack-patch.py /path/to/recovered [--check]

`realm/chiki-ios.js` can already stop every crypto capability from *working* in the app — no
wallet, no transaction, no marketplace request. What it cannot do is stop the pack from *drawing*
a shop, because that is GDScript building its own UI. App Review guideline 3.1.1 is about what an
app presents, so the drawing has to stop too, and only a rebuilt pack can stop it.

This script is that change. It is deliberately a patcher rather than a diff: the project it edits
is recovered game source and must not be committed to this repository (`RECOVERY.md` explains
why), so what lives here is the *instruction*, not the code.

Nineteen changes, every one gated on the loader's published policy and therefore a no-op on the
website:

  1. adds `ChikFeat.gd`, a small reader for `window.CHIK_FEATURES`
  2. **the welcome panel** — the first screen a player sees — stops offering "Connect Phantom
     Wallet" as its primary action, and its subtitle stops framing a wallet as the way in
  3. `GameHUD.open_market()` refuses when `trading_post` is off — that one function is the only
     way into the marketplace (`Player.gd` is its sole caller, at the Trading Post's world
     location), so gating it removes the Magic Eden tab and every Phantom purchase string with it
  4. the Chikiseum drops its **Chikoria Cup** tab when `crypto` is off, opens on My Deck instead,
     and stops claiming "champions win real SOL" in HOW TO BATTLE — the Cup pays a real SOL prize
     pool and was the default tab, so it is the first thing a reviewer would have seen
  5. the wallet gate stops naming Phantom and stops drawing its "Get Phantom ↗" button
  6. the token gate stops telling the player to "Hold 500,000 $CHIKI to enter"
  7. **the chat box goes** — world, whisper and party channels and the text input. News and system
     stay, because the pack itself treats those two as read-only
  8. the news banner stops saying "Hold 500,000 $CHIKI to keep earning"
  9. the in-game help loses its "$CHIKI economy", "Play & earn" and "Safe by design" sections and
     its $CHIKI and Trading Post topics, and Getting Started stops opening on a wallet

It does NOT touch PvP. The Chikiseum's duels are already stake-free and stay exactly as they are.

Items 2, 8 and 9 were found by BOOTING the rebuilt pack in a browser, not by reading the source.
The welcome panel in particular is the first thing on screen, and reading alone had missed it.

It does not change any GATE'S BEHAVIOUR either — only what the gate says. Whether an app player
needs the 500k hold is an open product decision and the server's to enforce; this makes the refusal
readable without naming a token, an amount, or somewhere to go and get one.

Idempotent: running it twice is a no-op. `--check` reports what would change and writes nothing.

Afterwards — **re-import first**, then verify:

    godot --headless --path <project> --import
    godot --headless --path <project> --check-only --script res://GameHUD.gd

The import is not optional and the failure it prevents is misleading. `ChikFeat.gd` declares a
`class_name`, and a global class is only registered when Godot rescans the filesystem. Skip the
rescan and the two patched scripts fail with `Identifier "ChikFeat" not declared in the current
scope` — which reads like a bug in this patch and is not one.
"""

import re
import sys
from pathlib import Path


def _anchor(text: str) -> "re.Pattern[str]":
	"""An anchor that ignores trailing whitespace at the end of each line.

	Decompiled GDScript keeps a trailing space after some argument commas, and that space does not
	survive every editor, diff or copy-paste on the way here. Matching on it exactly means the
	script fails against a project that is, for its purposes, identical. Everything else — the
	indentation, which is tabs, and the text itself — still has to match exactly.
	"""
	return re.compile(r"[ \t]*\n".join(re.escape(line.rstrip()) for line in text.split("\n")) + r"[ \t]*")


def _find(text: str, old: str):
	"""Return the single match for `old`, or None if it is absent or ambiguous."""
	found = list(_anchor(old).finditer(text))
	return found[0] if len(found) == 1 else None

CHIKFEAT = '''class_name ChikFeat
## The feature policy the page publishes as window.CHIK_FEATURES.
##
## realm/chiki-ios.js sets it: every flag true on the website, the restricted set inside the iOS
## app. Read once and cached, because JavaScriptBridge.eval is not free and the policy cannot
## change within a session.
##
## A missing or unreadable policy means "not restricted". That is the website's behaviour and the
## right default for it; the app's guarantee does not rest on this file, it rests on the loader,
## which also removes the wallet and the transaction library. godot-patch/verify/
## loader-policy.test.mjs is the tripwire that keeps the loader wired up.

static var _cache: Dictionary = {}
static var _read: bool = false


static func _all() -> Dictionary:
	if _read:
		return _cache
	_read = true
	if OS.has_feature("web"):
		var raw: Variant = JavaScriptBridge.eval("JSON.stringify(window.CHIK_FEATURES || {})", true)
		if raw is String:
			var parsed: Variant = JSON.parse_string(String(raw))
			if parsed is Dictionary:
				_cache = parsed
	return _cache


static func on(key: String) -> bool:
	return bool(_all().get(key, true))
'''

MARKET_OLD = '''func open_market() -> void :
	if _intro.visible or not _refs():
		return
	if bool(_profile.get("demo")):'''

MARKET_NEW = '''func open_market() -> void :
	if _intro.visible or not _refs():
		return
	if not ChikFeat.on("trading_post"):
		_toast("The Trading Post is not part of the app. Everything you earn here is yours to keep.", Color(0.9, 0.8, 0.6))
		return
	if bool(_profile.get("demo")):'''

TABS_OLD = '''	for t in [["cup", "\U0001F3C6 Chikoria Cup"], ["deck", "\U0001F0CF My Deck"], ["how", "⚔️ How to Battle"]]:'''

TABS_NEW = '''	var _visible_tabs: Array = [["cup", "\U0001F3C6 Chikoria Cup"], ["deck", "\U0001F0CF My Deck"], ["how", "⚔️ How to Battle"]]
	if not ChikFeat.on("crypto"):
		_visible_tabs.remove_at(0)
	for t in _visible_tabs:'''

OPEN_OLD = '''	_tab = "cup"
	_rebuild()'''

OPEN_NEW = '''	_tab = "cup" if ChikFeat.on("crypto") else "deck"
	_rebuild()'''

HOW_OLD = '''	_lbl(rew, "\U0001F3DF The Chikiseum hosts only the CHIKORIA CUP — champions win real SOL.", 12, GOLD)'''

HOW_NEW = '''	if ChikFeat.on("crypto"):
		_lbl(rew, "\U0001F3DF The Chikiseum hosts only the CHIKORIA CUP — champions win real SOL.", 12, GOLD)'''

# The wallet gate in Onboarding._show_gate(). In the app this screen should not be reachable at all
# — Realm Link signs the player in before it matters — but it IS reachable when a link is rejected
# or /verify fails, and what it draws then is a "Get Phantom  →" button pointing at phantom.app.
# The navigation guard in chiki-ios.js stops that button from going anywhere (OS.shell_open compiles
# to window.open, which is guarded), so this is about what is on screen, not what it does.
#
# The `else` branch is no good as a fallback either: it sends the player to the browser version,
# which is an outside destination for a problem the app can state plainly instead.
GATE_OLD = '''		if OS.has_feature("web"):
			_wallet_primary(v, "Waiting for Phantom…" if signing else "Sign in with Phantom", _phantom_connect, not signing, "res://ico_connect.png")
			_wallet_security_strip(v)
			var getp: = _btn(v, "Get Phantom  ↗", func(): OS.shell_open("https://phantom.app/"), true)
			getp.custom_minimum_size = Vector2(150, 30)
		else:'''

GATE_NEW = '''		if not ChikFeat.on("crypto"):
			_wallet_notice(v, "This device is not linked", "Link it to your Chikoria account to play. You can do that from the app's pairing screen.", UISkin.RED)
		elif OS.has_feature("web"):
			_wallet_primary(v, "Waiting for Phantom…" if signing else "Sign in with Phantom", _phantom_connect, not signing, "res://ico_connect.png")
			_wallet_security_strip(v)
			var getp: = _btn(v, "Get Phantom  ↗", func(): OS.shell_open("https://phantom.app/"), true)
			getp.custom_minimum_size = Vector2(150, 30)
		else:'''

# The token gate. When the account holds less than 500,000 $CHIKI and no waiver applies, the app
# tells the player: "Hold 500,000 $CHIKI to enter." That is an instruction to go and acquire half a
# million units of a crypto token in order to play an App Store app, which is a 3.1.1 problem on its
# own and reads as a purchase requirement besides.
#
# This changes the WORDS ONLY. Whether an app player needs the hold at all is a product decision
# that is still open (IOS-APP.md), and it is the server's to enforce either way — so the gate still
# closes exactly when it closed before. It just stops naming a token and an amount, and stops
# offering a "check balance again" button whose only remedy is buying some.
GATE_HOLD_OLD = '''			_wallet_notice(v, "More $CHIKI required",
				"Hold 500,000 $CHIKI to enter. Your wallet is connected safely. Played during an Open Gates event? Your progress and cloud save are kept safe — hold 500,000 $CHIKI and sign in again to continue right where you left off.",
				UISkin.RED)
			_wallet_primary(v, "Check balance again", _recheck_wallet, true, "res://ico_wallet.png")'''

GATE_HOLD_NEW = '''			if ChikFeat.on("crypto"):
				_wallet_notice(v, "More $CHIKI required",
					"Hold 500,000 $CHIKI to enter. Your wallet is connected safely. Played during an Open Gates event? Your progress and cloud save are kept safe — hold 500,000 $CHIKI and sign in again to continue right where you left off.",
					UISkin.RED)
				_wallet_primary(v, "Check balance again", _recheck_wallet, true, "res://ico_wallet.png")
			else:
				_wallet_notice(v, "This account cannot enter yet",
					"Your progress and cloud save are safe. Nothing is lost — open Chikoria on the web with this account to see what it needs.",
					UISkin.RED)'''

# The notice above that block names Phantom too, so it cannot stand on its own in the app.
NOTICE_OLD = '''		_wallet_notice(v, "One secure step", "Approve a sign-in message in Phantom. This proves the wallet is yours and restores your cloud save.", Color("a98bff"), "res://ico_connect.png")'''

NOTICE_NEW = '''		if ChikFeat.on("crypto"):
			_wallet_notice(v, "One secure step", "Approve a sign-in message in Phantom. This proves the wallet is yours and restores your cloud save.", Color("a98bff"), "res://ico_connect.png")'''

# ----------------------------------------------------------------------------- the chat box
#
# The app already refuses every chat route, so the box is inert — but an inert chat box is still a
# chat box on screen: a player can type into it and watch nothing happen, and a reviewer answering
# "does this app have user-generated content?" is looking at what is drawn, not at a network guard.
#
# Chat.gd carries FIVE channels, and only three of them are user-generated:
#
#     world, whisper, party   players talking to players   ← removed
#     news, system            announcements, read-only     ← kept
#
# `_input.editable = (c != "news" and c != "system")` in the pack's own `_switch()` is what says so.
# So the panel stays, keeps the news feed the loader already filters, and loses the three channels
# and the text box. Removing the whole CanvasLayer would take the news feed with it.
CHAT_TABS_OLD = '''	(_tabbtns["party"] as Button).visible = false'''

CHAT_TABS_NEW = '''	(_tabbtns["party"] as Button).visible = false
	if not ChikFeat.on("chat"):
		for _gone in ["world", "whisper", "party"]:
			if _tabbtns.has(_gone):
				(_tabbtns[_gone] as Button).visible = false'''

# The text box itself. It stays in the tree rather than being left unparented, because the pack
# calls _input.grab_focus() elsewhere and Godot errors when that reaches a node outside the tree.
# Hidden and non-editable is enough, and `editable` is what the focus path already checks.
CHAT_INPUT_OLD = '''	col.add_child(_input)'''

CHAT_INPUT_NEW = '''	col.add_child(_input)
	if not ChikFeat.on("chat"):
		_input.visible = false
		_input.editable = false'''

# ...and the collapse toggle, which would otherwise show it again on the next open.
CHAT_TOGGLE_OLD = '''	_input.visible = not _collapsed'''

CHAT_TOGGLE_NEW = '''	_input.visible = (not _collapsed) and ChikFeat.on("chat")'''

# `_active` starts on "world", which is now hidden, so the panel would open on a dead tab. Done in
# _ready() rather than inside _build_ui() because _switch() touches widgets that _build_ui() has
# not created yet at the point the input is added.
CHAT_READY_OLD = '''	_build_ui()
	_panel.visible = false'''

CHAT_READY_NEW = '''	_build_ui()
	if not ChikFeat.on("chat"):
		_switch("news")
	_panel.visible = false'''

# The news banner. Also found by booting: with the chat channels gone the panel opens on News, and
# the banner at the top of it reads "Hold 500,000 $CHIKI to keep earning." — the same instruction
# removed from the onboarding gate, arriving by another route. The loader's news filter cannot
# reach it, because this string is not in the feed; it is hardcoded in Chat.gd.
NEWS_BANNER_OLD = '''		_news_banner.text = "\U0001F30D The Open-Gates event has ended — thanks for playing! Hold 500,000 $CHIKI to keep earning."'''

NEWS_BANNER_NEW = '''		_news_banner.text = "\U0001F30D The Open-Gates event has ended — thanks for playing!" if not ChikFeat.on("crypto") else "\U0001F30D The Open-Gates event has ended — thanks for playing! Hold 500,000 $CHIKI to keep earning."'''

# ----------------------------------------------------------------------- the in-game help
#
# Three consecutive help sections explain $CHIKI as a real Solana token, tell the player to
# hold 500,000 of it, and describe collecting real SOL rewards to a wallet. None of it is true
# of the app, and all of it reads as instructions for transacting outside it.
HELP_ECON_OLD = '''	_h2(body, "🪙  The $CHIKI economy")
	var c3: = _card(body)
	_p(c3, "$CHIKI is the only in-game token — a real Solana token (pump.fun), 1 billion supply, deflationary. In-game $CHIKI mirrors your real wallet hold and can never exceed it. Shop fees, eggs and craft costs SINK it; Collect banks Pouch coins and burns 10%. Trading Post buys settle on-chain and split three ways:\\n👤 75% to the seller   ·   🏦 20% into the live reward pool   ·   🔥 5% burned forever.\\nThe pool refills from on-chain trading fees, so the rewards grow as the community grows.", INKB, 13)


	_h2(body, "💰  Play & earn")
	var c4: = _card(body)
	_p(c4, "Hold at least 500,000 $CHIKI to enter the realm. As you play, real SOL rewards accrue in your Pouch from the shared pool — Collect anytime to move them to your wallet (a small burn keeps $CHIKI deflationary). Hold 800,000+ and a bonus second egg is yours.", INKB, 13)


	_h2(body, "🛡  Safe by design")
	var c5: = _card(body)
	_p(c5, "Phantom asks for one free sign-in signature to prove the wallet is yours. It is never a transaction, never exposes your keys or seed phrase, and never gives the game permission to move funds.", INKB, 13)'''

HELP_ECON_NEW = '''	if ChikFeat.on("crypto"):
		_h2(body, "🪙  The $CHIKI economy")
		var c3: = _card(body)
		_p(c3, "$CHIKI is the only in-game token — a real Solana token (pump.fun), 1 billion supply, deflationary. In-game $CHIKI mirrors your real wallet hold and can never exceed it. Shop fees, eggs and craft costs SINK it; Collect banks Pouch coins and burns 10%. Trading Post buys settle on-chain and split three ways:\\n👤 75% to the seller   ·   🏦 20% into the live reward pool   ·   🔥 5% burned forever.\\nThe pool refills from on-chain trading fees, so the rewards grow as the community grows.", INKB, 13)


		_h2(body, "💰  Play & earn")
		var c4: = _card(body)
		_p(c4, "Hold at least 500,000 $CHIKI to enter the realm. As you play, real SOL rewards accrue in your Pouch from the shared pool — Collect anytime to move them to your wallet (a small burn keeps $CHIKI deflationary). Hold 800,000+ and a bonus second egg is yours.", INKB, 13)


		_h2(body, "🛡  Safe by design")
		var c5: = _card(body)
		_p(c5, "Phantom asks for one free sign-in signature to prove the wallet is yours. It is never a transaction, never exposes your keys or seed phrase, and never gives the game permission to move funds.", INKB, 13)'''

# The help INDEX carries the same thing as browsable topics. _howto_topics() is a function, so
# the crypto topics can be filtered out by key rather than each string being rewritten. 'nft'
# stays: it is display-only avatars and the Meme Dynasty, with nothing to buy.
HELP_TOPICS_OLD = '''func _howto_topics() -> Array:\n\treturn ['''

HELP_TOPICS_NEW = """func _howto_topics() -> Array:
\tvar _topics: Array = _howto_topics_all()
\tif ChikFeat.on("crypto"):
\t\treturn _topics
\tvar _kept: Array = []
\tfor _t in _topics:
\t\tif not String(_t.get("k", "")) in ["chiki", "trade"]:
\t\t\t_kept.append(_t)
\treturn _kept


func _howto_topics_all() -> Array:
\treturn ["""

# ...and the Getting Started topic, which survives, still opened on a wallet.
HELP_START_HOW_OLD = '''		"how": ["Connect Phantom at the gate — or press Play Demo to try a sealed sandbox first.", '''

HELP_START_HOW_NEW = '''		"how": [("Pair this device with your Chikoria account \\u2014 or press Play Demo to try a sealed sandbox first." if not ChikFeat.on("crypto") else "Connect Phantom at the gate \\u2014 or press Play Demo to try a sealed sandbox first."), '''

HELP_START_NUM_OLD = '''		"num": ["Hold 500,000 $CHIKI to start earning", "800,000 unlocks a 2nd starter egg", "Demo progress is sandboxed and never touches a wallet"]}, '''

HELP_START_NUM_NEW = '''		"num": (["Everything starts at zero \\u2014 the island pays for work", "Your progress syncs with the website", "Demo progress is sandboxed"] if not ChikFeat.on("crypto") else ["Hold 500,000 $CHIKI to start earning", "800,000 unlocks a 2nd starter egg", "Demo progress is sandboxed and never touches a wallet"])}, '''

# ----------------------------------------------------------------------------- the welcome panel
#
# FOUND BY BOOTING THE REBUILT PACK, not by reading. `Onboarding._show_gate()` is not the screen a
# player actually sees first — `InfoBar` draws a "Welcome to Chikoria" panel with a
# "🔗  Connect Phantom Wallet" button as the primary action, and it is the very first thing on
# screen. Patching the other gate and stopping there would have shipped an app whose opening screen
# is a wallet-connect button.
#
# The subtitle goes too: it names Phantom and $CHIKI and frames a wallet as the way to load your
# own trainer, which in the app is done by pairing instead.
WELCOME_TEXT_OLD = '''	p1.text = "Connect your Phantom wallet to load YOUR trainer, progress and $CHIKI — or step in as a guest first."'''

WELCOME_TEXT_NEW = '''	p1.text = "Pair this device with your Chikoria account to load your trainer and progress — or step in as a guest first." if not ChikFeat.on("crypto") else "Connect your Phantom wallet to load YOUR trainer, progress and $CHIKI — or step in as a guest first."'''

WELCOME_BTN_OLD = '''	var cb: = Button.new()
	cb.text = "\U0001F517  Connect Phantom Wallet"
	cb.custom_minimum_size = Vector2(0, 46)
	UISkin.plaque(cb, Color("7b5cd6"))
	cb.pressed.connect(open_wallet_pop)
	v.add_child(cb)'''

WELCOME_BTN_NEW = '''	if ChikFeat.on("crypto"):
		var cb: = Button.new()
		cb.text = "\U0001F517  Connect Phantom Wallet"
		cb.custom_minimum_size = Vector2(0, 46)
		UISkin.plaque(cb, Color("7b5cd6"))
		cb.pressed.connect(open_wallet_pop)
		v.add_child(cb)'''

EDITS = [
	("GameHUD.gd", MARKET_OLD, MARKET_NEW, "the Trading Post refuses when trading is off"),
	("Chikiseum.gd", TABS_OLD, TABS_NEW, "the Chikoria Cup tab is not built"),
	("Chikiseum.gd", OPEN_OLD, OPEN_NEW, "the Chikiseum opens on My Deck, not the Cup"),
	("Chikiseum.gd", HOW_OLD, HOW_NEW, '"champions win real SOL" is not drawn'),
	("Onboarding.gd", GATE_HOLD_OLD, GATE_HOLD_NEW, 'the 500k token gate stops naming a token'),
	("Onboarding.gd", NOTICE_OLD, NOTICE_NEW, 'the wallet gate stops naming Phantom'),
	("Onboarding.gd", GATE_OLD, GATE_NEW, 'the "Get Phantom" button is not drawn'),
	("Chat.gd", CHAT_TABS_OLD, CHAT_TABS_NEW, "world, whisper and party tabs are not built"),
	("Chat.gd", CHAT_INPUT_OLD, CHAT_INPUT_NEW, "the chat text box is hidden and not editable"),
	("Chat.gd", CHAT_TOGGLE_OLD, CHAT_TOGGLE_NEW, "collapsing and reopening does not bring it back"),
	("Chat.gd", CHAT_READY_OLD, CHAT_READY_NEW, "the panel opens on News instead of a dead tab"),
	("Chat.gd", NEWS_BANNER_OLD, NEWS_BANNER_NEW, 'the news banner stops saying "Hold 500,000 $CHIKI"'),
	("InfoBar.gd", HELP_ECON_OLD, HELP_ECON_NEW, "the $CHIKI / play-and-earn help sections are not drawn"),
	("InfoBar.gd", HELP_TOPICS_OLD, HELP_TOPICS_NEW, "the $CHIKI and Trading Post help topics are filtered out"),
	("InfoBar.gd", HELP_START_HOW_OLD, HELP_START_HOW_NEW, "Getting Started stops opening on a wallet"),
	("InfoBar.gd", HELP_START_NUM_OLD, HELP_START_NUM_NEW, "Getting Started stops naming a token hold"),
	("InfoBar.gd", WELCOME_TEXT_OLD, WELCOME_TEXT_NEW, "the welcome panel stops selling a wallet"),
	("InfoBar.gd", WELCOME_BTN_OLD, WELCOME_BTN_NEW, 'the "Connect Phantom Wallet" button is not built'),
]


def main() -> int:
	args = [a for a in sys.argv[1:] if not a.startswith("-")]
	check = "--check" in sys.argv
	if len(args) != 1:
		print(__doc__)
		return 2

	root = Path(args[0])
	if not (root / "project.godot").is_file():
		print(f"error: {root} is not a Godot project (no project.godot)")
		return 1

	planned, done, failed = [], [], []

	target = root / "ChikFeat.gd"
	if target.exists():
		done.append("ChikFeat.gd already present")
	else:
		planned.append(("ChikFeat.gd", None, "adds the window.CHIK_FEATURES reader"))

	for name, old, new, label in EDITS:
		path = root / name
		if not path.is_file():
			failed.append(f"{name}: missing")
			continue
		text = path.read_text(encoding="utf-8")
		if _find(text, new):
			done.append(f"{name}: {label} (already applied)")
		elif _find(text, old):
			planned.append((name, (old, new), label))
		else:
			n = len(list(_anchor(old).finditer(text)))
			failed.append(f"{name}: {label} — anchor found {n}x, expected 1")

	for line in done:
		print(f"  --  {line}")
	for name, edit, label in planned:
		print(f"  {'??' if check else '->'}  {name}: {label}")
	for line in failed:
		print(f"  !!  {line}")

	if failed:
		print("\nRefusing to patch: the project does not match what this script was written "
		      "against.\nIt targets the build recovered from pack 1eb4980816 — see RECOVERY.md.")
		return 1

	if check:
		print(f"\n--check: {len(planned)} change(s) would be made, nothing written.")
		return 0

	for name, edit, _label in planned:
		path = root / name
		if edit is None:
			path.write_text(CHIKFEAT, encoding="utf-8")
			continue
		old, new = edit
		text = path.read_text(encoding="utf-8")
		hit = _find(text, old)
		if hit is None:
			print(f"  !!  {name}: anchor moved while patching — nothing further written")
			return 1
		path.write_text(text[:hit.start()] + new + text[hit.end():], encoding="utf-8")

	if not planned:
		print("\nNothing to do — already patched.")
		return 0

	print(f"\nApplied {len(planned)} change(s). Re-import FIRST, or the new class_name will not")
	print("be registered and the patched scripts will not parse:")
	print(f"  godot --headless --path {root} --import")
	for f in ("ChikFeat.gd", "GameHUD.gd", "Chikiseum.gd", "Onboarding.gd"):
		print(f"  godot --headless --path {root} --check-only --script res://{f}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
