extends CanvasLayer
# ============================================================================================
# THE PURGE — the Wicked Temple's ritual (Chikoria, 2026-08-29)
# ============================================================================================
# The temple stood on the black peak as a COMING SOON placard for months. LoreBeacon.gd:25 already
# wrote this feature's brief, and it is the one followed here to the letter:
#
#     "High on the black peak squats a temple no trainer ever built. Within it the warlock Grimwick
#      weaves the corruption that twists wild chikimons into monsters."
#     tease: "Storm the temple · break Grimwick's curse"
#
# WHAT IT IS. Five rounds. Each round Grimwick lights one of five corrupted sigils — one per
# element — and you send ONE chikimon from your party at it. Whether the sigil breaks is decided by
# the element pentagon the rest of the game already fights on (Econ.el_mult, x1.5 strong / x0.7
# weak), your unit's level, its mood, and how well you time the channel. Three sigils broken is a
# clean purge.
#
# WHY THIS SHAPE, and not a wave defence or a rhythm game. Three reasons, all measurable:
#   1. It reuses the combat identity that already exists. Econ.PENTAGON, Econ.el_of, level scaling
#      and Profile.mood_card_mult are the REAL battle maths (Battle.gd:1044-1059) — so a chikimon
#      that is good here is good for reasons the player already understands, and no parallel stat
#      system has to be invented and then kept in sync forever.
#   2. It is short. One run is about ninety seconds, one objective, no tutorial. That is the whole
#      of the short-session design literature and it is also what a landmark you walk to deserves:
#      the walk is the cost, the ritual is the payoff.
#   3. It has a REASON to exist in the economy, below.
#
# ------------------------------------------------------------------------------------------------
# THE ECONOMY, WHICH IS THE PART THAT COULD HAVE GONE BADLY
# ------------------------------------------------------------------------------------------------
# Measured before designing (chiki_sink_flow.mjs, and the recon behind this change): soft $CHIKI
# sink recovery is 19.2% — four fifths of everything minted stays minted — and the task board is an
# uncapped faucet. Dropping a fresh uncapped reward into that would have been actively harmful, so
# this ritual is built as a SINK FIRST:
#
#   * ENTRY COSTS AN OFFERING: 3 x essence ("Dark Energy"), the material corruptimons drop. That
#     closes a real loop — fight the corruption, harvest it, feed it back to the temple to break it.
#     It is a material sink, and materials are the economy's time-currency (Profile.gd:5).
#   * THE PAYOUT IS THE SERVER'S NUMBER, NOT OURS. The client reports what happened and asks; the
#     server answers. See _report(). A client that lies gets the server's answer anyway.
#   * THE SERVER CAPS IT PER UTC DAY. Nothing here can outrun that cap, because nothing here
#     decides the amount.
#
# The one asymmetry worth knowing: Profile.earn() multiplies by the live emission factor (0.5-1.5,
# Chain.emission_factor) and then clamps to the pouch. So what LANDS can be less than what the
# server authorised — never more. That is the safe direction, and the result screen therefore shows
# the amount that actually landed (measured from the pouch, see _credit) rather than the number the
# server named, because a card that promises 120 and delivers 90 is a bug report.
# ------------------------------------------------------------------------------------------------
#
# NOTHING IN HERE PAYS REAL, ON-CHAIN $CHIKI. Real $CHIKI leaves the treasury by exactly two
# admin-signed batch routes and this is not one of them, by design.

# NOTHING HERE IS AN AUTOLOAD — only Backend is (project.godot). Econ, UISkin and Nameplate are
# plain scripts every caller preloads: Chikiseum.gd:13-14, PlayerPanel.gd:2-5, Companion.gd:7.
const UISkin = preload("res://UISkin.gd")
const Econ := preload("res://Econ.gd")
const Nameplate := preload("res://Nameplate.gd")
const TempleDuelScript := preload("res://TempleDuel.gd")
const TempleCardArt := preload("res://TempleCardArt.gd")
const TempleReward := preload("res://TempleReward.gd")
const TempleRewardCeremonyScene := preload("res://TempleRewardCeremony.gd")
const MobileViewport := preload("res://TempleMobileViewport.gd")
const WICKED_GATE_FRAME_PATH := "res://wicked_gate_frame.png"
# The Higgsfield plaque is an RGB image: its dark canvas continues outside the carved stone.
# Keep the inner writing surface opaque but key away only the outer canvas at draw time. This
# preserves every source pixel and avoids a rectangle around the irregular crystal silhouette.
const WICKED_GATE_EXTERIOR_MASK := """
shader_type canvas_item;
void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	float writing_surface = step(0.095, UV.x) * step(UV.x, 0.905)
		* step(0.140, UV.y) * step(UV.y, 0.865);
	float detail = max(max(ink.r, ink.g), ink.b);
	float carved_stone = smoothstep(0.105, 0.165, detail);
	COLOR = vec4(ink.rgb, ink.a * max(writing_surface, carved_stone));
}
"""

const OFFERING := {"essence": 3}      # what the temple eats to open the doors
const ROUNDS := 5
const ELEMENTS := ["Water", "Fire", "Beast", "Storm", "Light"]

# The bar the purge has to clear. power = el_mult x level x mood x timing; a same-element send with
# a mid-level unit and a decent tap lands near 1.15, a resisted one near 0.8 — so 1.0 is a real
# decision point rather than a formality, and element choice is the loudest term in it.
const PURIFY_BAR := 1.0

# THE CURVE, and the measured reason it is not Battle.gd's raw level scalar.
#
# The first cut used Battle's own `1 + 0.05*lvl`. A probe run then printed the same line three times
# — "Dragonos L30, el x1.00, timing x1.25, power 2.12, BROKEN" — a mid-level unit clearing every
# sigil on a NEUTRAL matchup. At L30 that term is 2.50 against an element spread of only 0.7..1.5,
# so level was not a thumb on the scale, it WAS the scale, and the one decision the mode contains
# (which chikimon answers which element) had no effect on the outcome. The assertions all passed;
# the design was broken anyway, which is why the number gets read and not just the tick.
#
# So the level term is compressed to 0.80..1.20 across L1..L50. Element (a 2.14x spread) is now the
# loudest term by a distance, and the ladder falls out where it should against the 1.0 bar:
#     strong element, any level, ordinary timing   -> ~1.44   breaks
#     neutral element, mid level, ordinary timing  -> ~0.96   HOLDS, and perfect timing saves it
#     resisted element, mid level, perfect timing  -> ~0.84   holds; only a high level rescues it
# A high-level roster is still better, but it cannot buy its way out of sending Fire at Water.
static func purge_power(el_mult: float, lvl: int, mood: float, timing: float) -> float:
	var lvl_term: float = 0.80 + 0.008 * float(clampi(lvl, 1, 50))
	return el_mult * lvl_term * mood * timing

const BG := Color(0.07, 0.04, 0.11, 0.97)       # the temple's own violet-black, not the shop brown
const EDGE := Color(0.62, 0.36, 0.92, 0.95)     # Grimwick's tag colour (grimwick_meta.json cc8cff)
const INK := Color(0.93, 0.90, 0.98)
const DIM := Color(0.70, 0.64, 0.82)
const GOLD := Color(1.00, 0.86, 0.42)
const BAD := Color(1.00, 0.44, 0.40)

# THE WORLD OVERLAY'S OWN TOUCH FLOOR, and it is deliberately not UISkin's — nor a constant.
#
# UISkin.touch_h floors a phone button at 44 LOGICAL px, and a logical pixel is not a pixel a thumb
# can see. MEASURED (dev_temple_mobile.gd): on an 844x390 phone the project's stretch
# (min(w/1600, h/900), aspect=expand) times Main.gd's content_scale_factor 1.35 gives 0.585 CSS px
# per logical px, so that 44 is 25.7 CSS px, and the overlay's shipped 40/46 px buttons measured
# 23.4 and 26.9 CSS px against a 44 CSS px guideline.
#
# A CONSTANT CANNOT FIX THAT, because the ratio is not constant. The same probe measured 0.5852 in
# landscape and 0.3291 in portrait — a hard-coded 76 is 44.5 CSS px one way up and 25.0 the other,
# and portrait is reachable in production (web_shell.html only rotates the canvas if the player
# accepts; declining leaves the engine a genuinely portrait viewport). So the floor is stated in
# the unit that matters and converted with the ratio actually in force.
#
# These are the ritual's ONLY controls and they sit over a live world, which is why they get this
# and the rest of the game does not: raising UISkin's game-wide 44 is the owner's call.
const OV_TOUCH_CSS := 44.0

# CSS px per logical pixel comes from the same browser/safe-area adapter as the horde HUD.
# CSS and render-buffer resolution are independent; do not divide CSS dimensions by DPR again.
func _css_per_logical() -> float:
	return maxf(0.05, float(MobileViewport.sample(get_viewport())["css_per_logical"]))

func _mobile_ui() -> bool:
	return bool(MobileViewport.sample(get_viewport())["touch"])

func _mobile_safe_panel_rect() -> Rect2:
	var display := MobileViewport.sample(get_viewport())
	var css := display["css_size"] as Vector2
	var edge := display["safe_insets"] as Vector4
	var scale := _css_per_logical()
	return Rect2(Vector2(edge.x + 10.0, edge.y + 10.0) / scale,
		Vector2(css.x - edge.x - edge.z - 20.0, css.y - edge.y - edge.w - 20.0) / scale)

func _ov_touch() -> float:
	# ceil + 1: 44.0 / 0.5852 is 75.19 logical px, and a button laid out at 75 measures back as
	# 43.89 CSS px — a hair UNDER the very bar it was derived from. Rounding down at the last step
	# is how a derived floor quietly fails to be a floor.
	# Clamped: never below UISkin's own 44, never so tall it eats the battle box.
	return clampf(ceilf(OV_TOUCH_CSS / _css_per_logical()) + 1.0, 44.0, 160.0)


# TYPE IS AUTHORED IN CSS PX AND CONVERTED, for exactly the reason _ov_touch() exists above: a
# logical pixel is not a pixel an eye can see. The SAME number, 15 logical px, is 12.0 CSS px on a
# 1280x800 desktop and 8.8 CSS px on an 844x390 phone — one constant, two completely different
# legibility verdicts. That is the whole reason the letters read as too small: not that the numbers
# were low, but that they were stated in the wrong unit and then scaled down again.
# Every font size on the lore and offering screens goes through here. Nothing on those two screens
# may hard-code a font_size.
func _fs(css: float) -> int:
	return int(clampf(roundf(css / _css_per_logical()), 10.0, 260.0))


# SPACING GETS ITS OWN CONVERTER, and it deliberately does NOT reuse _fs(). That clamp floors at 10
# logical px, which is right for type and wrong for gaps: every 4 CSS gutter would come back as 10
# and the whole rhythm would collapse into one value.
func _sp(css: float) -> int:
	return maxi(1, int(roundf(css / _css_per_logical())))


# THE FACES THIS SCREEN NEVER HAD. Measured before writing a line of this: Temple.gd carried 51
# font_size overrides and ZERO font-family or weight overrides, so the whole temple rendered in the
# engine's default UI face at one weight — the only major screen in the game not speaking in
# Chikoria's voice. Everything downstream followed from that absence: with no weight axis, hierarchy
# had to be faked with size and colour, which is how nine font sizes ended up inside a 15-27 CSS band
# and gold ended up on eight different kinds of element.
# The faces and the loader are the game's own (PlayerPanel.gd / InfoBar.gd use the same three).
var _f_cache: Dictionary = {}

func _font(role: String) -> Font:
	if _f_cache.has(role):
		return _f_cache[role]
	var f: Font = null
	match role:
		"display": f = _load_var("res://font_titan.ttf", 400)     # Titan One has one weight by design
		"head":    f = _load_var("res://font_baloo.ttf", 800)
		"bold":    f = _load_var("res://font_nunito.ttf", 800)
		_:         f = _load_var("res://font_nunito.ttf", 400)
	_f_cache[role] = f
	return f


func _load_var(path: String, wght: int) -> FontVariation:
	# exported builds only carry the IMPORTED font resource — raw ttf reads are dev-only
	var base: Font = null
	if ResourceLoader.exists(path):
		base = load(path) as Font
	if base == null:
		if not FileAccess.file_exists(path):
			return null
		var ff := FontFile.new()
		var ok := false
		if ff.has_method("load_dynamic_font"):
			ok = ff.load_dynamic_font(path) == OK
		if not ok:
			var by := FileAccess.get_file_as_bytes(path)
			if by.size() > 0:
				ff.data = by
				ok = true
		if not ok:
			return null
		base = ff
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": wght}
	var emo: Font = preload("res://Econ.gd").emoji_fallback()   # FontVariation needs its OWN fallback
	if emo != null:
		fv.fallbacks = [emo]
	return fv


# ONE CALL SETS A LABEL'S VOICE: face, size and colour together, so a size can never again be chosen
# without also choosing the weight that should have carried the emphasis instead.
func _type(c: Control, role: String, css: float, col: Color) -> void:
	var f := _font(role)
	if f != null:
		c.add_theme_font_override("font", f)
	c.add_theme_font_size_override("font_size", _fs(css))
	c.add_theme_color_override("font_color", col)
	if c is Label:
		(c as Label).text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING

var _profile: Node = null
var _scrim: Button = null
var _gate_frame: TextureRect = null
var _panel: PanelContainer = null
var _body: VBoxContainer = null
var _grim_host: Control = null      # the live voxel stage; survives _build() so it is not rebuilt per page
var _grim_tw: Tween = null
var _panel_drop := 0.0
var _strip_root: Control = null
var _scrim_sb: StyleBoxFlat = null     # how far the big card sits below centre to clear the top tab bar

# ==============================================================================================
# GRIMWICK SPEAKS FIRST.
# ==============================================================================================
# Walking into a mini-game and being handed a stat card is how a menu introduces itself. The temple
# has a villain standing in it, so he does the introducing: portrait, chat bubble, four beats of
# why this place is corrupted and what he wants — and only then the offer.
#
# THE VOICE RULE: he is not a tutorial. He never says "tap", "card", "wave" or "energy". He tells
# you what he did and what he wants; the offering screen after him handles the mechanics. A villain
# who explains your controls stops being a villain.
# HIS MONOLOGUE, RE-CUT FROM FOUR PAGES TO TEN — word for word identical. Normalising whitespace,
# the concatenation is 744 characters either way; every break falls on a sentence or paragraph
# boundary that was already there, and the one blank line inside the wager becomes a space.
# WHY: the strip has to be small AND the type has to be bigger, and those only stop fighting when
# the third variable moves. The old longest page was 270 characters; at 32 CSS px its TEXT ALONE
# measured 44.8% of a desktop screen before any padding, portrait or controls. No box shape fixes
# that — only fewer characters at a time do. The longest page is now 109.
const LORE := [
	{"say": "Ah. A trainer, and a small warm creature at your heel.", "beat": "THE WICKED TEMPLE"},
	{"say": "Come in. The stone remembers warmth. It has been a long time since it had any.", "beat": "THE WICKED TEMPLE"},
	{"say": "This was a sanctum once. Five seals, five elements, and a quiet order of keepers who fed them.", "beat": "WHAT IT WAS"},
	{"say": "I fed them something else.", "beat": "WHAT IT WAS"},
	{"say": "Corruption is not a curse I cast. It is a QUESTION I asked, and the seals answered.", "beat": "THE CORRUPTIMONS"},
	{"say": "Look at what came back through them. They were somebody's companions, once.", "beat": "THE CORRUPTIMONS"},
	{"say": "Now they are mine, and they do not remember being anything.", "beat": "THE CORRUPTIMONS"},
	{"say": "I want to know what a bond is worth. So: one of yours. Not three, not a party hiding behind each other — ONE.", "beat": "THE WAGER"},
	{"say": "Walk it through my five sanctums and let me watch how long affection lasts against arithmetic.", "beat": "THE WAGER"},
	{"say": "Break all five and I will pay you for the lesson. I always pay.", "beat": "THE WAGER"},
]

var _lore_page := 0
var _phase := "intro"        # intro | seek | pick | channel (Sigil Duel) | resolve | done
var _round := 0
var _purified := 0
var _sigil := ""             # the element burning this round
var _sigil_order: Array = []  # four shuffled side seals, then Light for the real Grimwick finale
var _pick_uid := ""
var _pick_slot := 0
var _log: Array = []         # per-round record, for the results card
var _horde_pick_uid := ""   # exactly one Chikimon crosses the Horde arena threshold
var _run_id := ""           # names one completed run for an idempotent server loot receipt
var _stage_stats := {}       # score/kills/combo/grade returned by the continuous combat world
var _loot_reward := {}       # authoritative production receipt OR clearly-unsaved sandbox preview
var _loot_why := ""
var _wheel: Control = null      # the transparent 2D reward ceremony, alive only on victory
var _wheel_spun := false        # one reveal per run: the receipt does not change if pressed again
var _loot_run_id := ""       # echoed authoritative id, including a durable no-grant receipt
var _sandbox_reward_index := 0
var _report_retries := 0

# --- the channel bar: a sweeping marker the player stops inside a band ---
var _chan_t := 0.0
var _chan_dir := 1.0
var _chan_band := 0.5
var _chan_marker: ColorRect = null
var _chan_zone: ColorRect = null
var _chan_running := false

# --- SIGIL DUEL: actual card combat between creature selection and the one round outcome -------
# The model is pure, ritual-local state.  It never mutates Profile vitals and still produces one
# boolean score for the existing five-round server contract.  Temple owns only UI and stage FX.
var _duel = null
var _duel_pending_hand := -1
var _duel_animating := false
var _duel_generation := 0
var _duel_focus := {}                 # uid -> ritual Focus, so a mid-fight swap has real meaning
var _duel_switcher: OptionButton = null
var _duel_last_line := ""

var _srv_on := true          # CHIK_TEMPLE, as the server reports it
var _loot_srv_on := false     # independent strict CHIK_TEMPLE_LOOT gate
var _loot_state_known := false
var _runs_left := -1         # -1 = not asked yet; the card shows "—" rather than a guess
var _chiki_left := -1.0
var _chiki_per := 0.0

var _sig_tw: Tween = null    # the looping sigil pulse, killed and remade per rebuild
var _bolt_tw: Tween = null   # the strike bolt's flight, killed on teardown (it outlives its target)
var _walk_tw: Tween = null   # the helper's walk-in, same reason: its callback holds the puppet

# ---- THE 2D WORLD (owner, 2026-08-29: "make it a 2d world like pokemon... miniature 2d models").
# The ritual now plays inside a walkable 2D temple hall (Temple2D.gd) with every creature remade as
# a miniature animated 2D puppet (Rig2D.gd). Both are loaded DYNAMICALLY so this file parses and the
# ritual still runs — as the verified modal flow — if either file is ever absent from a build. The
# economy contract (offering, server-decided tribute, caps) is identical in both modes.
var _mode := "modal"                 # "world" when Temple2D+Rig2D are present, else "modal"
var _svc: SubViewportContainer = null
var _sv: SubViewport = null
var _world: Node = null              # the Temple2D instance (untyped: loaded dynamically)
var _ov: Control = null              # the overlay: banner + bottom battle boxes
var _platformer_world := false       # the new continuous side-scroller owns its own HUD/gameplay
var _ov_banner_lbl: Label = null
var _ov_box: PanelContainer = null   # the current bottom box (pick strip / channel / result)
var _helper: Node = null             # the sent chikimon's rig, living IN the world
# Non-empty when _helper is a MEMBER OF THE TRAIL rather than a puppet spawned for the send.
# The distinction decides three things and it is worth naming: who owns the strike's position
# (Temple2D, not this file), whether the hurt pose is played through the world, and — the one that
# leaks if it is got wrong — whether the creature is FREED at the end of the round or walked back
# into formation. Freeing a follower would delete a third of the player's party from the hall.
var _helper_party := ""
var _alcove_pos := Vector2.ZERO      # where the lit plate is (captured when the player reaches it)

# The all-assets session is a test bench, so its temple picker may address the entire owned roster
# instead of only the three current party slots.  The popup stays names-only and owns ONE preview
# rig: decoding all 41 atlases together would defeat the phone build this sandbox exists to test.
var _asset_pick_uid := ""
var _asset_pick_units: Array = []
var _asset_picker: OptionButton = null
var _asset_preview: CenterContainer = null
var _asset_preview_animated := false
var _sandbox_victory_button: Button = null

var _busy := false           # a report is in flight — never let a second run start on top of it
var _mobile_resize_queued := false
var _resize_ceremony: TempleRewardCeremony = null

func _ready() -> void:
	add_to_group("temple")
	# 63: ABOVE EVERY INFOBAR SURFACE THAT COULD DRAW ON TOP OF A FULL-SCREEN RITUAL — the HUD (52),
	# the wallet gate (60), the touch guide (61) and the Viranimal panel (62, InfoBar.gd:4126) — and
	# BELOW the wallet pop (66), which must always win because it is how a player signs in.
	#
	# The history is worth keeping: this shipped at 46, under the InfoBar entirely. It was raised to
	# 56 to clear the top tab bar, which an audit then showed was still under _vira_layer at 62. A
	# hit-test proved the layer does NOT gate input at any of these values — a click reaches the
	# buttons at 46 too — so this is purely about what DRAWS over a screen-filling card.
	#
	# HONEST NOTE: this is NOT proven to be the reported freeze. A hit-test probe (dev_templeclick)
	# showed a real click reaches the Leave button at 46 AND at 56 on desktop, so the layer does not
	# block input. It is corrected because the draw order is wrong, not because it is the cure.
	layer = 63
	visible = false
	set_process(true)
	set_process_unhandled_input(true)

func is_open() -> bool:
	return visible


func _set_sandbox_launcher_visible(on: bool) -> void:
	var lab := get_tree().get_first_node_in_group("all_assets_lab")
	if lab != null and lab.has_method("set_launcher_visible"):
		lab.call("set_launcher_visible", on)


func close() -> void:
	visible = false
	# the voxel stage is kept alive across page turns, so closing is the one place it must go: a
	# SubViewport left running renders an 8841-instance MultiMesh every frame behind a hidden panel
	_grim_free()
	_set_sandbox_launcher_visible(true)
	_chan_running = false
	_duel_generation += 1
	_duel = null
	_duel_pending_hand = -1
	_duel_animating = false
	_duel_focus.clear()
	_duel_switcher = null
	_teardown_world()
	set_process_unhandled_input(false)
	_keys(false)

# THE KEYBOARD IS HANDED OVER, NOT SHARED.
#
# Temple2D walks the hall on the same WASD (and SPACE) the 3D avatar walks the island on, and BOTH
# poll the Input singleton directly — Temple2D.gd:181 with is_physical_key_pressed, Player.gd:580
# with is_key_pressed. Two readers, one keyboard, nothing between them. Measured before this
# hand-off existed (dev_temple_desktop.gd phase 1, at the SEEK beat): forty frames of held W moved
# the hall 227.994 px and moved the avatar 12.096 world units in the same forty frames — the avatar's
# closed-temple speed over that window is 12.300 units, so it was walking the island at full pace
# while the player walked the hall. SPACE jumped it 2.417 units while SPACE was the channel key.
#
# The comment on _unhandled_input's ESC branch claimed this modal "swallows movement". It did not.
# It does now, and BOTH modes take the keys: the flat modal covers the screen just as completely,
# and its ESC and SPACE are not the world's either.
#
# The grab is released by close() and self-heals besides — Player.keys_taken() drops an owner that
# was freed or whose is_open() has gone false, so no path out of this screen can leave the avatar
# unable to move.
func _keys(take: bool) -> void:
	# TouchControls polls globally just like the desktop player did before grab_keys existed. Pause
	# that reader for the full ritual lifetime as well, otherwise the platformer's on-screen arrows
	# also walk the hidden 3D avatar underneath the viewport. close() always calls this with false.
	var touchui := get_tree().get_first_node_in_group("touchui")
	if touchui != null and touchui.has_method("set_suspended"):
		touchui.call("set_suspended", take)
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return
	if take:
		if p.has_method("grab_keys"):
			p.call("grab_keys", self)
	elif p.has_method("release_keys"):
		p.call("release_keys", self)

func open() -> void:
	if _busy:
		return
	# ALREADY OPEN = DO NOTHING. Player._on_action calls this on EVERY E press inside the 46 m
	# circle, and this function resets the ritual to its intro — so without this guard a second E
	# mid-run would discard a purge whose offering had already been spent. That is the same robbery
	# the scrim guard in _build refuses, reached through a different door. Re-entry is only from a
	# closed screen; the Chikiseum can re-enter freely because its open() costs the player nothing.
	if visible:
		return
	if _profile == null:
		_profile = get_tree().get_first_node_in_group("profile")
	if _profile == null:
		return
	# Each deliberate fresh E interaction begins with Grimwick. The remembered flag records
	# progress only; it must not silently remove the story from returning players.
	_lore_page = 0
	_phase = "lore"
	_round = 0
	_purified = 0
	_sigil_order.clear()
	_duel = null
	_duel_pending_hand = -1
	_duel_animating = false
	_duel_focus.clear()
	_duel_switcher = null
	_asset_pick_uid = ""
	_horde_pick_uid = ""
	_run_id = ""
	_stage_stats.clear()
	_loot_reward.clear()
	_wheel = null
	_wheel_spun = false            # one spin per run
	_loot_why = ""
	_loot_run_id = ""
	_report_retries = 0
	_loot_state_known = false
	_paid_amt = 0.0
	_paid_why = ""
	_log.clear()
	visible = true
	_set_sandbox_launcher_visible(false)
	set_process_unhandled_input(true)
	_keys(true)          # from here the movement keys are the hall's, not the island's (see _keys)
	_build()
	_fetch_state()

# What is left of today's tribute, and the server's own numbers for it. Asked once per open; the
# card renders fine before it lands (the row simply says "—") and refreshes when it does.
func _fetch_state() -> void:
	var net := get_tree().get_first_node_in_group("net")
	if net == null or not net.has_method("temple_state"):
		return
	net.call("temple_state", func(code: int, j: Dictionary):
		if code != 200 or j.is_empty():
			return
		_srv_on = bool(j.get("on", false))
		_loot_srv_on = bool(j.get("lootOn", false))
		_loot_state_known = true
		_runs_left = int(j.get("runsLeft", -1))
		_chiki_left = float(j.get("chikiLeft", -1.0))
		_chiki_per = float(j.get("chikiPer", 0.0))
		if _phase == "intro" and visible:
			_build())

# ============================== the shell =====================================================
# Modal, and built on the Chikiseum's shell (Chikiseum.gd:123) rather than the shop rect: this is a
# LANDMARK activity — you walked to the peak for it — and those take the screen. The scrim is made
# first so it stays a lower sibling and draws behind the panel through every rebuild.
func _build() -> void:
	if not get_viewport().size_changed.is_connected(_queue_mobile_surface_resize):
		get_viewport().size_changed.connect(_queue_mobile_surface_resize)
	_asset_clear_picker_refs()
	if _panel == null:
		_scrim = Button.new()
		_scrim.flat = true
		_scrim.focus_mode = Control.FOCUS_NONE
		_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(0.03, 0.01, 0.05, 0.66)
		_scrim_sb = bsb
		_scrim.add_theme_stylebox_override("normal", bsb)
		_scrim.add_theme_stylebox_override("hover", bsb)
		_scrim.add_theme_stylebox_override("pressed", bsb)
		# MID-RITUAL THE SCRIM IS INERT. Walking out of a round you have already paid the offering
		# for would eat the essence and pay nothing — the one way this screen could rob someone.
		# MID-RITUAL THE SCRIM IS INERT. Walking out of a round you have already paid the offering
		# for would eat the essence and pay nothing — the one way this screen could rob someone.
		# During the monologue it is not a dismiss target at all: it turns the page, the way every
		# dialogue box in the genre does.
		_scrim.pressed.connect(func():
			if _phase == "lore":
				_lore_advance()
			elif _phase == "intro" or _phase == "done":
				close())
		add_child(_scrim)
		_gate_frame = TextureRect.new()
		_gate_frame.name = "WickedHiggsfieldGateFrame"
		_gate_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_gate_frame.stretch_mode = TextureRect.STRETCH_SCALE
		_gate_frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_gate_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_gate_frame.texture = _temple_gate_texture()
		var gate_mask := ShaderMaterial.new()
		var mask_shader := Shader.new()
		mask_shader.code = WICKED_GATE_EXTERIOR_MASK
		gate_mask.shader = mask_shader
		_gate_frame.material = gate_mask
		_gate_frame.visible = false
		add_child(_gate_frame)
		_panel = PanelContainer.new()
		_panel.set_anchors_preset(Control.PRESET_CENTER)
		add_child(_panel)
		# Containers report transient minimum-size growth while the entry subtree is rebuilt.
		# Position the frame after the final layout, never against an intermediate tall panel.
		_panel.resized.connect(func(): _layout_gate_frame.call_deferred())
	if _gate_frame != null:
		_gate_frame.visible = false
	var vw := get_viewport().get_visible_rect().size
	var lite := UISkin.lite_world()
	# THE TWO SCREENS THE OWNER NAMED GET THE WHOLE CARD. Measured on the shipped 1280x800 frame:
	# persistent world HUD occupied 31.8% of the screen and the lore pop-up 19.8%. With the lower
	# minibars standing down (GameHUD.modal_owns_screen) a centred modal can hold ~72.8% — 3.7x the
	# old pop-up — which is what buys room for type at nearly double the size AND more content,
	# instead of trading one against the other.
	# Every other phase keeps its existing sizing untouched: the blast radius is the two screens.
	# THE LORE PHASE IS NO LONGER A CARD. It is a rail welded near the bottom edge, so its "panel" is
	# a transparent full-screen canvas that the rail, the bust and the tabs position themselves
	# inside; only the offering screen still wants a centred slab.
	var strip := _phase == "lore"
	var big := _phase == "intro"
	var result_screen := _phase == "done"
	_panel_drop = 0.0
	var w: float
	var h_min := 0.0
	if big:
		# A small character-owned invitation, measured in displayed pixels on every quality tier.
		w = minf(vw.x - float(_sp(32.0)), float(_sp(540.0)))
		h_min = 0.0
	elif result_screen:
		w = minf(vw.x * 0.88, 820.0)
		# Reserve a clean wheel-centered stage. The ceremony sizes the wheel from this viewport's
		# actual logical height; short screens retain the ScrollContainer fallback below.
		h_min = minf(800.0, vw.y - 32.0)
	else:
		w = minf(vw.x * (0.90 if lite else 0.92), 700.0 if lite else 860.0)
	var mobile_surface := _mobile_ui() and (big or result_screen)
	var mobile_rect := _mobile_safe_panel_rect() if mobile_surface else Rect2()
	if mobile_surface:
		w = minf(mobile_rect.size.x, float(_sp(480.0 if big else 540.0)))
		h_min = 0.0 if big else minf(mobile_rect.size.y,
			minf(float(_sp(420.0)), w - float(_sp(32.0))) + float(_sp(160.0)))
		_panel_drop = 0.0
	# THE CARD IS AS TALL AS WHAT IS IN IT. A fixed landmark-sized slab left the intro's five lines
	# floating in the top third of an empty 660 px panel — the "unnecessary spaces" the owner has
	# twice asked me to stop adding. Width stays fixed so the frame does not jitter between phases
	# (the pick grid is wider than the intro's stat box); height grows from the content, centred by
	# the both-directions grow, and every phase here is well under a screen.
	_panel.anchor_left = 0.5; _panel.anchor_right = 0.5
	_panel.anchor_top = 0.5; _panel.anchor_bottom = 0.5
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.offset_left = 0.0; _panel.offset_right = 0.0
	_panel.offset_top = _panel_drop; _panel.offset_bottom = _panel_drop
	_panel.custom_minimum_size = Vector2(w, h_min)
	if mobile_surface:
		var safe_offset := mobile_rect.get_center() - vw * 0.5
		_panel.offset_left = safe_offset.x; _panel.offset_right = safe_offset.x
		_panel.offset_top = safe_offset.y; _panel.offset_bottom = safe_offset.y
	if strip:
		_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		_panel.offset_left = 0.0; _panel.offset_top = 0.0
		_panel.offset_right = 0.0; _panel.offset_bottom = 0.0
		_panel.custom_minimum_size = Vector2.ZERO
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb: StyleBoxFlat
	if strip:
		# no frame at all: the rail draws its own, and a second one round the whole screen is exactly
		# the "obstructs the centre" the correction was about
		sb = StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
	elif false:
		# GRIMWICK'S CARD IS ONE OF OURS. Every pop-up in Chiki Monsters is cream parchment inside a
		# dark-brown carved frame under a plaque header — the satchel, the shops, the quest pins.
		# The temple's own violet-black slab is right for the ritual screens, and wrong here: this is
		# a character talking to you, and it should look like the game he lives in. He supplies the
		# colour (his tag violet on the plaque, his plinth), the game supplies the material.
		sb = UISkin.panel()
		sb.set_content_margin_all(14 if lite else 20)
	else:
		sb = StyleBoxFlat.new()
		sb.bg_color = BG
		sb.border_color = EDGE
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(18)
		sb.set_content_margin_all(10 if lite else 16)
		sb.shadow_color = Color(0, 0, 0, 0.66); sb.shadow_size = 26; sb.shadow_offset = Vector2(0, 14)
	if result_screen:
		# The receipt lives in the same obsidian and violet stone as Grimwick's sanctum. Keep the
		# middle quiet so the wheel, not a generic result box, is the focal point.
		sb.bg_color = Color("120d20")
		sb.border_color = Color("c59b68") if _purified >= ROUNDS else Color("685b77")
		sb.set_border_width_all(1)
		sb.border_width_top = 2
		sb.set_content_margin_all(10 if lite else 14)
		sb.set_corner_radius_all(18)
		sb.shadow_color = Color(0.0, 0.0, 0.0, 0.72)
		sb.shadow_size = 24
		sb.shadow_offset = Vector2(0.0, 12.0)
		if mobile_surface:
			sb.set_content_margin_all(_sp(8.0))
	if _scrim_sb != null:
		# THE WORLD STAYS LIT BEHIND THE RAIL. A 66% dim over the whole screen is an obstruction even
		# when nothing is drawn on top of it, and the correction was about the centre staying clear.
		_scrim_sb.bg_color = Color(0.03, 0.01, 0.05, 0.0 if strip else (0.86 if result_screen else 0.66))
		# Flat Buttons omit their normal style, so the previous result dimmer only appeared on hover.
		# Always draw the victory scrim: the wheel stays the focus even when the cursor is on it.
		_scrim.flat = not result_screen
	_panel.add_theme_stylebox_override("panel", sb)
	# THE VOXEL STAGE OUTLIVES A REBUILD. _build() runs on every page turn; rebuilding an 8841-voxel
	# MultiMesh and its viewport four times would be pure waste and would restart the sway. Detach it
	# before the sweep so it is not freed, then re-parent it in _draw_lore.
	if _grim_host != null and is_instance_valid(_grim_host) and _grim_host.get_parent() != null:
		_grim_host.get_parent().remove_child(_grim_host)
	for c in _panel.get_children():
		c.queue_free()
	if strip:
		# a PLAIN Control, not a VBox: the rail, the bust that breaks out above it and the tabs seated
		# on its top edge are placed absolutely, which no container arrangement can express
		var canvas := Control.new()
		canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
		canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(canvas)
		_strip_root = canvas
		_draw_lore()
		return
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 0 if big else 8)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# the body is NOT told to fill any more: with a content-sized card that would be circular, and it
	# is what put the dead space back the last time
	# NO SCROLLER ON THE OFFERING CARD. It was the overflow guard for a card pinned to full height,
	# and a ScrollContainer's own minimum height is ZERO — so the moment the card became
	# content-sized the whole panel collapsed to an empty violet bar. The card cannot overflow now
	# by construction: every block above the grid is measured, and the grid is sized from the card
	# width at a fixed ratio rather than from leftover space.
	# (If a scroller is ever needed here again, note UISkin.popup_scroll_surface() must NOT be the
	# route: it schedules compact_popup a frame later, which multiplies every font_size in the
	# subtree by 0.84 and would silently undo the device conversion _fs() just performed.)
	if result_screen:
		var scroll := ScrollContainer.new()
		scroll.name = "VictoryResultScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		# The reward wheel is the visual centerpiece; a permanent scrollbar track beside it reads
		# like a settings panel. Keep wheel/drag scrolling available on short displays but hide the
		# track itself. The two actions remain in view in the normal desktop and landscape layouts.
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.custom_minimum_size.y = maxf(1.0, h_min - float(_sp(16.0))) if mobile_surface \
			else maxf(240.0, h_min - 56.0)
		_panel.add_child(scroll)
		scroll.add_child(_body)
	else:
		_panel.add_child(_body)
	match _phase:
		"lore":    _draw_lore()
		"intro":   _draw_intro()
		"pick":    _draw_pick()
		"channel": _draw_channel()
		"resolve": _draw_resolve()
		"done":    _draw_done()


func _queue_mobile_surface_resize() -> void:
	if visible and _phase == "stage":
		_layout_sandbox_victory_control.call_deferred()
	if _mobile_resize_queued or not visible or _phase not in ["lore", "intro", "done"]:
		return
	if not _mobile_ui() and _phase == "done":
		return
	_mobile_resize_queued = true
	_rebuild_mobile_surface.call_deferred()


func _rebuild_mobile_surface() -> void:
	_mobile_resize_queued = false
	if not visible or _phase not in ["lore", "intro", "done"]:
		return
	# Entry rebuild uses the already-selected uid. Result rebuild retains the SAME ceremony and
	# wheel nodes, including in-flight progress, revealed state and exact settled receipt.
	if _phase == "done" and _wheel is TempleRewardCeremony and is_instance_valid(_wheel):
		_resize_ceremony = _wheel as TempleRewardCeremony
		if _resize_ceremony.get_parent() != null:
			_resize_ceremony.get_parent().remove_child(_resize_ceremony)
	_build()
	# Busy/no-grant/fallback screens may no longer want a ceremony. Release it without authority
	# callbacks rather than retaining an orphan if that state changed during the deferred resize.
	if _resize_ceremony != null:
		_resize_ceremony.queue_free()
		_resize_ceremony = null

func _head(txt: String, px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(220, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(l)
	return l

# ============================== 0. Grimwick ===================================================
func _lore_seen() -> bool:
	return _profile != null and bool(_profile.d.get("temple_lore_seen", false))


func _mark_lore_seen() -> void:
	# Keep existing profile compatibility without using this marker to suppress future dialogue.
	if _profile != null and not bool(_profile.d.get("temple_lore_seen", false)):
		_profile.d["temple_lore_seen"] = true
		if _profile.has_method("save_now"):
			_profile.call("save_now")


func _replay_lore() -> void:
	# Replay is an entry-screen action only, never a way to interrupt an active paid encounter.
	if not visible or _busy or _phase != "intro":
		return
	_lore_page = 0
	_phase = "lore"
	_build()



# GRIMWICK'S OWN CROP, as a fraction of his height. He is a 9.50 m model (42x51x30 voxels at vsize
# 0.1863) and the strip that holds him is 156 logical px tall, so framing him whole renders his head
# at 32 px — a doll, not a character.
# 0.30 WAS CHOSEN BY LOOKING, and it overrides the arithmetic that first suggested 0.60. That number
# came from budgeting "head + hat" as the top 1.68 m — but this model has NO FACE: the head IS the
# hat, and under its brim is beard and collar. Cropping to 0.60 therefore framed a hat on a shelf,
# which measured perfectly and read as a mistake. 0.30 keeps the hat, the collar and the shoulders,
# which is the least that reads as a person. Rendered side by side at 0.00 / 0.30 / 0.45 / 0.60 in
# dev_grimcrop before choosing.
const GRIM_CROP_LO := 0.30

func _accum_aabb(root: Node3D) -> AABB:
	# THE MESH'S OWN EXTENT, IN THE WRAPPER'S SPACE. MultiMeshInstance3D.get_aabb() is the LOCAL
	# box and the wrapper's child carries the vsize scale, so the scale has to be applied here or
	# every framing term below is out by a factor of ~5.4.
	var out := AABB()
	var got := false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mmi := n as MultiMeshInstance3D
		if mmi != null and mmi.multimesh != null:
			var b := mmi.multimesh.get_aabb()
			var s := mmi.scale
			var scaled := AABB(b.position * s, b.size * s)
			out = scaled if not got else out.merge(scaled)
			got = true
	return out


func _sub_mass(root: Node3D, y_min: float) -> Dictionary:
	# every voxel at or above y_min, in the wrapper's space: the extent AND the median x/z of the
	# mass that the crop actually leaves on screen
	var xs: Array[float] = []
	var zs: Array[float] = []
	var x0 := INF; var x1 := -INF; var z0 := INF; var z1 := -INF
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mmi := n as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		var sc: float = mmi.scale.x
		for i in range(mmi.multimesh.instance_count):
			var p := mmi.multimesh.get_instance_transform(i).origin * sc
			if p.y < y_min:
				continue
			xs.append(p.x); zs.append(p.z)
			x0 = minf(x0, p.x); x1 = maxf(x1, p.x)
			z0 = minf(z0, p.z); z1 = maxf(z1, p.z)
	if xs.is_empty():
		return {}
	xs.sort(); zs.sort()
	return {"n": xs.size(), "mx": xs[xs.size() / 2], "mz": zs[zs.size() / 2],
		"x0": x0, "x1": x1, "z0": z0, "z1": z1}


func _grim_free() -> void:
	if _grim_tw != null and is_instance_valid(_grim_tw):
		_grim_tw.kill()
	_grim_tw = null
	if _grim_host != null and is_instance_valid(_grim_host):
		_grim_host.queue_free()
	_grim_host = null


func _grim_stage(size: Vector2) -> Control:
	# THE REAL HD VOXEL MODEL, not the 2D sprite. grimwick_voxels.bin is 8841 voxels at vsize
	# 0.1863 — the same model that stands on the black peak — and until now there was no way to put
	# one in a UI panel: every consumer of this format inlines its own parser and places straight
	# into the world. Npc.build_vox_bin() is that parser, lifted out once.
	if _grim_host != null and is_instance_valid(_grim_host):
		_grim_host.custom_minimum_size = size
		return _grim_host
	var model: Node3D = load("res://Npc.gd").build_vox_bin("grimwick")
	if model == null:
		return null                          # caller falls back to the 2D sprite
	var host := Control.new()
	host.custom_minimum_size = size
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(cont)
	var vp := SubViewport.new()
	vp.size = Vector2i(maxi(64, int(size.x)), maxi(64, int(size.y)))
	vp.own_world_3d = true
	vp.transparent_bg = true
	# render_target_update_mode is deliberately NOT set: SubViewportContainer force-writes
	# UPDATE_ALWAYS when the viewport is added and again on every visibility change, so an explicit
	# value here is silently overwritten and reads as a bug in whatever set it.
	vp.msaa_3d = Viewport.MSAA_DISABLED if UISkin.lite_world() else Viewport.MSAA_4X
	cont.add_child(vp)
	# LIGHTING IS MANDATORY. own_world_3d inherits NOTHING from the game world — no environment, no
	# sun — so without this block the model renders as a black silhouette and looks like a broken
	# mesh rather than an unlit one.
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.74, 0.82)
	env.ambient_light_energy = 1.5
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -38, 0)
	key.light_energy = 1.35
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-14, 150, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.70, 0.80, 1.00)
	vp.add_child(rim)
	var pivot := Node3D.new()
	vp.add_child(pivot)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.current = true
	vp.add_child(cam)                        # a SIBLING of the pivot, never a child of it
	pivot.add_child(model)
	# FRAME FROM THE MESH'S OWN BOX, NOT THE ORIGIN. This model's voxel AABB starts at (-20, 0, -15),
	# so a camera aimed at the origin looks at the floor beside his feet — the exact failure the
	# project's probe rule warns about.
	var aabb := _accum_aabb(model)
	var gh: float = maxf(0.2, aabb.size.y)
	var cy: float = aabb.position.y + (GRIM_CROP_LO + 1.04) * 0.5 * gh
	var half_v: float = (1.04 - GRIM_CROP_LO) * 0.5 * gh
	# FRAME FROM THE VOXELS THAT ARE ACTUALLY ON SCREEN. Raising the crop alone does nothing, because
	# need_h was computed from the FULL model box: the camera then pulls back far enough to fit a robe
	# hem that is cropped away, and he renders as a doll in a letterbox. The failure looks like "the
	# model is small", not like a bug, which is why it is worth this much comment.
	# The aim is the MEDIAN x/z of the visible mass, not its bounding-box midpoint — the mounts lesson:
	# a midpoint is set by whichever voxel sticks out furthest, and a staff or a sleeve is enough to
	# shove a body off centre.
	var sub := _sub_mass(model, aabb.position.y + GRIM_CROP_LO * gh)
	var aim_x: float = float(sub.get("mx", aabb.get_center().x))
	var aim_z: float = float(sub.get("mz", aabb.get_center().z))
	var need_h: float = 1.06 * maxf(
		maxf(absf(float(sub.get("x1", 0.0)) - aim_x), absf(aim_x - float(sub.get("x0", 0.0)))),
		maxf(absf(float(sub.get("z1", 0.0)) - aim_z), absf(aim_z - float(sub.get("z0", 0.0)))))
	model.position = Vector3(-aim_x, -cy, -aim_z)
	var aspect: float = size.x / maxf(1.0, size.y)
	var fit_v: float = maxf(half_v, need_h / maxf(0.2, aspect))
	var dist: float = fit_v / tan(deg_to_rad(15.0))
	cam.transform = Transform3D(Basis(), Vector3(0.10, -0.08, 1.0).normalized() * dist).looking_at(Vector3.ZERO, Vector3.UP)
	if OS.get_environment("CHIK_UI_BUDGET") == "1":
		print("GRIMFRAME bay=%.0fx%.0f aspect=%.3f  gh=%.2f cy=%.2f half_v=%.2f  sub_n=%d need_h=%.2f aim=(%.2f,%.2f)  fit_v=%.2f dist=%.2f  band=%.2f..%.2f m = %.2f..%.2f of height"
			% [size.x, size.y, aspect, gh, cy, half_v, int(sub.get("n", 0)), need_h, aim_x, aim_z,
			fit_v, dist, cy - fit_v, cy + fit_v, (cy - fit_v) / gh, (cy + fit_v) / gh])
	# A SWAY, NOT A TURNTABLE. A full spin would show the player his back for half of every loop,
	# which is the wrong read for a man delivering a monologue to your face.
	if not UISkin.lite_world():
		pivot.rotation.y = -0.12
		_grim_tw = create_tween().set_loops()
		_grim_tw.tween_property(pivot, "rotation:y", 0.12, 3.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_grim_tw.tween_property(pivot, "rotation:y", -0.12, 3.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_grim_host = host
	return host


func _lore_plate_h(css: float, width: float) -> float:
	# THE PLATE IS SIZED TO THE LONGEST PAGE, ALWAYS. Sized to the current page it would grow and
	# shrink as the player advances, and Grimwick above it would resize with it — the card would
	# breathe. Measured with the real font at the real width, so it is the true wrapped height.
	var l := Label.new()
	var fnt := l.get_theme_font("font")
	var fs := _fs(css)
	l.queue_free()
	var tallest := 0.0
	for pg in LORE:
		var t := String((pg as Dictionary).get("say", ""))
		var sz := fnt.get_multiline_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, width, fs)
		tallest = maxf(tallest, sz.y)
	return tallest


func _lore_advance() -> void:
	if _lore_page < LORE.size() - 1:
		_lore_page += 1
		_build()
	else:
		_mark_lore_seen()
		_phase = "intro"
		_build()


func _abs(parent: Control, r: Rect2) -> Control:
	var c := Control.new()
	c.position = r.position
	c.size = r.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


func _lore_tab(parent: Control, txt: String, primary: bool, fs: int, h: float, on: Callable) -> Button:
	# THE CONTROLS SIT ON THE RAIL'S TOP EDGE, not inside it, so they cost the rail no interior height
	# at all — which is where a good part of the narration's new size comes from.
	var b := Button.new()
	b.text = txt
	b.set_meta("preserve_tab_art", true)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = false
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if _mobile_ui() else TextServer.AUTOWRAP_OFF
	b.add_theme_font_override("font", preload("res://ui_font_bold.ttf"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.42, 0.22, 0.66) if primary else Color(0.16, 0.11, 0.22, 0.95)
	sb.border_color = Color("82643f") if primary else Color("594069")
	sb.set_border_width_all(2)
	sb.border_width_bottom = 0                 # it meets the rail; a line there is a seam, not an edge
	sb.corner_radius_top_left = 10; sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 0; sb.corner_radius_bottom_right = 0
	sb.content_margin_left = _sp(6.0); sb.content_margin_right = _sp(6.0)
	sb.content_margin_top = _sp(4.0); sb.content_margin_bottom = _sp(4.0)
	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = sb.bg_color.lightened(0.12)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, hov if st == "hover" else sb)
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", Color("ffe9c2") if primary else Color(0.82, 0.76, 0.94))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.custom_minimum_size = Vector2(0, h)
	b.pressed.connect(on)
	parent.add_child(b)
	return b


func _draw_lore() -> void:
	# The original ten story beats stay intact. Geometry follows input/display size, not HD/lite.
	var root := _strip_root
	if root == null:
		return
	var page: Dictionary = LORE[clampi(_lore_page, 0, LORE.size() - 1)]
	var display := MobileViewport.sample(get_viewport())
	var css := display["css_size"] as Vector2
	var mobile := _mobile_ui()
	var edge := display["safe_insets"] as Vector4 if mobile else Vector4.ZERO
	var unit := 1.0 / _css_per_logical()
	var available := Rect2(Vector2(edge.x + 12.0, edge.y + 12.0),
		Vector2(css.x - edge.x - edge.z - 24.0, css.y - edge.y - edge.w - 24.0))
	var rail_w := minf(available.size.x, 700.0 if mobile else 960.0)
	var narrow := rail_w < 420.0
	var pad := 14.0 if mobile else 20.0
	var portrait_h := 86.0 if narrow else (142.0 if mobile else 220.0)
	var tex: Texture2D = load("res://grimwick_art.png") if ResourceLoader.exists("res://grimwick_art.png") else null
	var aspect := float(tex.get_width()) / float(tex.get_height()) if tex != null else 0.84
	var portrait_w := portrait_h * aspect
	var text_inset := pad if narrow else pad + portrait_w + (12.0 if mobile else 20.0)
	var text_w := maxf(1.0, rail_w - text_inset - pad)
	var say_px := _fs(15.0 if mobile else 21.0)
	var face := preload("res://ui_font.ttf")
	var tallest := 0.0
	for beat in LORE:
		tallest = maxf(tallest, face.get_multiline_string_size(String(beat["say"]),
			HORIZONTAL_ALIGNMENT_LEFT, text_w * unit, say_px).y / unit)
	var speaker_h := 16.0 if mobile else 21.0
	var rail_h := pad * 2.0 + speaker_h + tallest
	var rail := Rect2(Vector2(available.get_center().x - rail_w * 0.5,
		available.end.y - rail_h), Vector2(rail_w, rail_h))
	var bar := Panel.new()
	bar.name = "GrimwickStoryRail"
	var style := StyleBoxFlat.new()
	style.bg_color = Color("181020")
	style.border_color = Color("82643f")
	style.set_border_width_all(_sp(1.0))
	style.border_width_top = _sp(2.0)
	style.set_corner_radius_all(_sp(7.0))
	style.shadow_color = Color(0.02, 0.01, 0.04, 0.55)
	style.shadow_size = _sp(14.0)
	style.shadow_offset = Vector2(0, -_sp(3.0))
	bar.add_theme_stylebox_override("panel", style)
	bar.position = rail.position * unit
	bar.size = rail.size * unit
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)

	var bay := Rect2(Vector2(rail.position.x + pad,
		rail.position.y - portrait_h - 4.0 if narrow else rail.end.y - pad - portrait_h),
		Vector2(portrait_w, portrait_h))
	if tex != null:
		var art := TextureRect.new()
		art.name = "GrimwickStoryPortrait"
		art.texture = tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.position = bay.position * unit
		art.size = bay.size * unit
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(art)
	else:
		var host := _grim_stage(bay.size * unit)
		if host != null:
			if host.get_parent() != null:
				host.get_parent().remove_child(host)
			host.position = bay.position * unit
			host.size = bay.size * unit
			root.add_child(host)

	var col := Vector2(rail.position.x + text_inset, rail.position.y + pad)
	var tag := Label.new()
	tag.name = "GrimwickStorySpeaker"
	tag.text = "GRIMWICK  /  %d / %d" % [_lore_page + 1, LORE.size()]
	tag.add_theme_font_override("font", preload("res://ui_font_bold.ttf"))
	tag.add_theme_font_size_override("font_size", _fs(10.0 if mobile else 12.0))
	tag.add_theme_color_override("font_color", Color("c298e9"))
	tag.position = col * unit
	tag.size = Vector2(text_w, speaker_h) * unit
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tag)
	var say := Label.new()
	say.name = "GrimwickStoryText"
	say.text = String(page.get("say", ""))
	say.add_theme_font_override("font", face)
	say.add_theme_font_size_override("font_size", say_px)
	say.add_theme_color_override("font_color", Color("f1e6d2"))
	say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	say.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	say.clip_text = false
	say.position = (col + Vector2(0, speaker_h)) * unit
	say.size = Vector2(text_w, tallest) * unit
	say.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(say)

	var last := _lore_page >= LORE.size() - 1
	var p_txt := "I accept the wager" if last else "Hear him out"
	var s_txt := "Not today" if last else "Skip"
	var p_fs := _fs(12.0 if mobile else 14.0)
	var s_fs := _fs(11.0 if mobile else 13.0)
	var tab_h := 44.0 if mobile else 38.0
	var primary_w := 130.0 if narrow else maxf(140.0,
		face.get_string_size(p_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, p_fs).x / unit + 30.0)
	var secondary_w := 62.0 if narrow else 84.0
	var primary_x := rail.end.x - pad - primary_w
	var tab_y := rail.position.y - tab_h
	var next := _lore_tab(root, p_txt, true, p_fs, ceilf(tab_h * unit) + 1.0, _lore_advance)
	next.name = "GrimwickStoryNext"
	next.position = Vector2(primary_x, tab_y) * unit
	next.size = Vector2(primary_w, tab_h) * unit
	var skip := _lore_tab(root, s_txt, false, s_fs, ceilf(tab_h * unit) + 1.0, func():
		_mark_lore_seen()
		if last:
			close()
		else:
			_phase = "intro"
			_build())
	skip.name = "GrimwickStorySkip"
	skip.position = Vector2(primary_x - 8.0 - secondary_w, tab_y) * unit
	skip.size = Vector2(secondary_w, tab_h) * unit
	var progress := ColorRect.new()
	progress.name = "GrimwickStoryProgress"
	progress.color = Color("a66bdd")
	progress.position = Vector2(rail.position.x + pad, rail.end.y - 4.0) * unit
	progress.size = Vector2((rail_w - pad * 2.0) * float(_lore_page + 1) / float(LORE.size()), 2.0) * unit
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(progress)



func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# ============================== 1. the doors ==================================================
func _chip(parent: Control, label: String, ratio: float, edge: Color) -> BoxContainer:
	# A CHIP, NOT A ROW. Six label-left / value-right rows across 850 logical px left the middle 60%
	# of every row empty BY CONSTRUCTION — that emptiness is the row geometry, not the content, so
	# no amount of rearranging rows could fix it. Stacking the label over the value reclaims the
	# vertical the row was throwing away and fits the same facts at 2.5x the type size in LESS
	# total height.
	var chip := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.13, 0.09, 0.19, 0.95)
	cs.border_color = edge
	cs.set_border_width_all(2)
	cs.set_corner_radius_all(_sp(8.0))
	cs.content_margin_left = _sp(12.0); cs.content_margin_right = _sp(12.0)
	cs.content_margin_top = _sp(8.0); cs.content_margin_bottom = _sp(8.0)
	chip.add_theme_stylebox_override("panel", cs)
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.size_flags_stretch_ratio = ratio
	parent.add_child(chip)
	# STACKED ON A DESKTOP, INLINE ON A PHONE. The stack is what reclaims the row's dead middle on a
	# wide card; on a 390-tall screen that same stack is 99 logical px of chrome per chip, and three
	# of them push the roster off the bottom.
	var v: BoxContainer
	if UISkin.lite_world():
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		v = h
	else:
		var c := VBoxContainer.new()
		c.add_theme_constant_override("separation", 2)
		v = c
	chip.add_child(v)
	var l := Label.new()
	l.text = label
	_type(l, "bold", 16.0, Color(0.70, 0.64, 0.82))          # L1: labels are small, bold and quiet
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(l)
	return v


func _icon(parent: Control, path: String, px: float) -> void:
	if not ResourceLoader.exists(path):
		return
	var t := TextureRect.new()
	t.texture = load(path)
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)


func _vrule(parent: Control, h: float) -> void:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.18)
	r.custom_minimum_size = Vector2(2, h)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)


func _intro_card_name(unit: Dictionary) -> String:
	var raw: String = _profile.unit_name(unit) if _profile != null else \
		String(unit.get("name", unit.get("species", "Chikimon"))).capitalize()
	return raw.substr(0, 22) + "…" if raw.length() > 22 else raw


func _intro_name_line_count(text: String, available_width: float, lite: bool) -> int:
	# Ask the exact display face used by the Label. Character counts cannot predict Titan One: at
	# 903x797 the CSS-correct 23px face makes "Ansem Blackbull" wider than the 132 CSS-pixel card,
	# while the same 15 characters fit at 1280x720. Greedy word wrapping mirrors WORD_SMART; an
	# over-wide single word is allowed to break just as the Label is.
	var face := _font("display")
	var font_px := _fs(18.0 if lite else 23.0)
	var width := maxf(1.0, available_width)
	if face == null:
		return clampi(ceili(float(text.length()) * float(font_px) * 0.62 / width), 1, 3)
	var lines := 0
	var current := ""
	for word_v in text.split(" ", false):
		var word := String(word_v)
		var candidate := word if current == "" else current + " " + word
		if current == "" or face.get_string_size(candidate,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x <= width:
			current = candidate
			continue
		var current_w := face.get_string_size(current,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
		lines += maxi(1, ceili(current_w / width))
		current = word
	if current != "":
		var current_w := face.get_string_size(current,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
		lines += maxi(1, ceili(current_w / width))
	return clampi(lines, 1, 3)


func _intro_name_height(text: String, available_width: float, lite: bool) -> float:
	var face := _font("display")
	var font_px := _fs(18.0 if lite else 23.0)
	var line_h := face.get_height(font_px) if face != null else float(font_px) * 1.24
	return ceilf(line_h * float(_intro_name_line_count(text, available_width, lite)) \
		+ float(_sp(2.0)))


func _intro_grid_height(card_width: float, lite: bool, units: Array) -> float:
	# Phone cards already have a deliberately compact 0.62 ratio and names fit their much wider
	# logical face; do not enlarge that layout. Desktop height is the sum of what is really inside:
	# the 150px portrait, measured one/two-line display name, both stat rows, three VBox gaps, the
	# explicit 14px inner offsets, and a four-CSS-pixel optical safety gutter.
	if lite:
		return maxf(card_width * 0.62, 176.0)
	var name_h := 0.0
	var name_width := maxf(1.0, card_width - 28.0)
	for unit_v in units:
		if unit_v is Dictionary:
			name_h = maxf(name_h, _intro_name_height(
				_intro_card_name(unit_v as Dictionary), name_width, false))
	if name_h <= 0.0:
		name_h = _intro_name_height("Chikimon", name_width, false)
	var bold := _font("bold")
	var stat_px := _fs(19.0)
	var stat_h := bold.get_height(stat_px) if bold != null else float(stat_px) * 1.24
	var meta_h := maxf(26.0, stat_h)
	var mult_h := maxf(28.0, stat_h)
	var measured := 28.0 + 150.0 + name_h + meta_h + mult_h + 18.0 + float(_sp(4.0))
	return maxf(card_width * 1.16, ceilf(measured))


func _draw_intro() -> void:
	var fit := _horde_candidates()
	if not fit.is_empty() and (_horde_pick_uid == "" or not _unit_list_has(fit, _horde_pick_uid)):
		_horde_pick_uid = String((fit[0] as Dictionary).get("uid", ""))
	var units: Array = []
	for value in fit:
		var unit := (value as Dictionary).duplicate()
		unit["display_name"] = _intro_card_name(unit)
		units.append(unit)
	var message := ""
	if not _has_offering():
		message = "Collect %d Dark Energy from corruptimons to enter." % int(OFFERING["essence"])
	elif not _asset_test_mode() and not _srv_on:
		message = "Practice is open. Reward tribute is not open today."
	elif not _asset_test_mode() and _runs_left == 0:
		message = "Today's reward runs are spent. Further practice pays no tribute."
	var screen = load("res://RebornDeployment.gd").new()
	_body.add_child(screen)
	screen.setup(units, _horde_pick_uid, _asset_test_mode(), _has_offering(),
		int(OFFERING["essence"]), _runs_left, message, _mobile_ui(),
		1.0 / maxf(0.1, _css_per_logical()))
	screen.creature_selected.connect(func(uid: String):
		_horde_pick_uid = uid
		_build())
	screen.deploy_requested.connect(_begin)
	screen.leave_requested.connect(close)
	screen.lore_requested.connect(_replay_lore)
	var framed := not _mobile_ui() and _gate_frame != null and _gate_frame.texture != null
	_panel.add_theme_stylebox_override("panel", _temple_gate_plate(framed))
	if framed:
		_gate_frame.visible = true
		_layout_gate_frame.call_deferred()


func _temple_gate_texture() -> Texture2D:
	if ResourceLoader.exists(WICKED_GATE_FRAME_PATH):
		return load(WICKED_GATE_FRAME_PATH) as Texture2D
	if FileAccess.file_exists(ProjectSettings.globalize_path(WICKED_GATE_FRAME_PATH)):
		var source := Image.load_from_file(ProjectSettings.globalize_path(WICKED_GATE_FRAME_PATH))
		if source != null and not source.is_empty():
			return ImageTexture.create_from_image(source)
	return null


func _layout_gate_frame() -> void:
	if _gate_frame == null or _panel == null or not _gate_frame.visible or _phase != "intro":
		return
	var available := get_viewport().get_visible_rect().size - Vector2(float(_sp(24.0)), float(_sp(24.0)))
	if _panel.size.y > available.y or _panel.size.x > available.x:
		# PanelContainer temporarily exposes an unconstrained child minimum during _build(). The
		# next resized signal delivers the actual settled rect; do not disable the frame early.
		return
	# The visible arch's inner opening is roughly 81% wide and 72.5% tall. Keep the entire
	# invitation (including actions) within that opening rather than stretching ornament across
	# its text. Letterbox to the source aspect ratio so crystals and stonework stay proportional.
	var wanted := _panel.size + Vector2(float(_sp(240.0)), float(_sp(230.0)))
	var aspect := float(_gate_frame.texture.get_width()) / float(_gate_frame.texture.get_height())
	wanted.y = maxf(wanted.y, wanted.x / aspect)
	wanted.x = maxf(wanted.x, wanted.y * aspect)
	var fit := minf(1.0, minf(available.x / wanted.x, available.y / wanted.y))
	var frame_size := wanted * fit
	# At a genuinely tight viewport, use the compact carved panel instead of forcing the text or
	# hit targets through the frame. Mobile already uses that same fallback.
	if frame_size.x * 0.81 < _panel.size.x + float(_sp(24.0)) \
		or frame_size.y * 0.725 < _panel.size.y + float(_sp(24.0)):
		_gate_frame.visible = false
		_panel.add_theme_stylebox_override("panel", _temple_gate_plate(false))
		return
	_gate_frame.size = frame_size
	_gate_frame.position = _panel.position + (_panel.size - frame_size) * 0.5


func _temple_gate_plate(framed: bool = false) -> StyleBoxFlat:
	# The full Higgsfield arch is a sibling BEHIND this readable card. Phones use only this lighter
	# carved-stone card: squeezing the arch into a 390px display would obstruct its controls.
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.0, 0.0, 0.0, 0.0) if framed else Color("160e21")
	plate.border_color = Color(0.0, 0.0, 0.0, 0.0) if framed else Color("a47c56")
	plate.set_border_width_all(0 if framed else _sp(1.0))
	plate.border_width_top = 0 if framed else _sp(3.0)
	plate.set_corner_radius_all(_sp(9.0))
	plate.set_content_margin_all(_sp(10.0) if _mobile_ui() else _sp(16.0))
	plate.shadow_color = Color(0, 0, 0, 0.65)
	plate.shadow_size = 0 if framed else _sp(20.0)
	return plate


func _draw_intro_legacy() -> void:
	var lite := UISkin.lite_world()
	var gap: float = 10.0 if lite else 16.0
	var inner_w: float = _panel.custom_minimum_size.x - 6.0 - (28.0 if lite else 40.0)
	var inner_h: float = _panel.custom_minimum_size.y - 6.0 - (28.0 if lite else 40.0)
	var offer_ok := _has_offering()
	var fit := _horde_candidates()
	if not fit.is_empty() and (_horde_pick_uid == "" or not _unit_list_has(fit, _horde_pick_uid)):
		_horde_pick_uid = String((fit[0] as Dictionary).get("uid", ""))
	# The laboratory owns all 41 test creatures, but this panel was deliberately designed for a
	# three-member production party.  Feeding the whole laboratory roster into a non-scrolling grid
	# made thirteen extra rows and pushed the primary action off-screen.  Keep the selected creature
	# plus two visual alternatives here; the complete roster is still passed to Horde and remains
	# switchable through its sandbox-only TEST CHIKI control.
	var intro_units: Array = fit
	if _asset_test_mode() and fit.size() > 3:
		intro_units = []
		for value in fit:
			if value is Dictionary and String((value as Dictionary).get("uid", "")) == _horde_pick_uid:
				intro_units.append(value)
				break
		for value in fit:
			if intro_units.size() >= 3:
				break
			if value is Dictionary and String((value as Dictionary).get("uid", "")) != _horde_pick_uid:
				intro_units.append(value)
	var loot_live: bool = _asset_test_mode() or _loot_srv_on
	# decided up front: the footer band is only RESERVED when there is actually something to say
	var msg := ""
	var msg_col := DIM
	if not _has_offering():
		msg = "Dark Energy drops from corruptimons. Bring %d." % int(OFFERING["essence"])
		msg_col = BAD
	elif not _srv_on:
		msg = "The temple stirs, but its tribute is not open yet. You can purge — it pays nothing today."
	elif _runs_left == 0:
		msg = "Today's tribute is spent. The sigils still burn, but they pay nothing until reset."

	# ── A. the plaque ──
	var hdr := PanelContainer.new()
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.42, 0.22, 0.66)
	hs.border_color = Color(0.165, 0.102, 0.031)
	hs.set_border_width_all(3)
	hs.border_width_bottom = 6
	hs.set_corner_radius_all(_sp(8.0))
	hs.set_content_margin_all(_sp(12.0))
	hdr.add_theme_stylebox_override("panel", hs)
	_body.add_child(hdr)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	hdr.add_child(hv)
	var t1 := Label.new()
	t1.text = "WICKED TEMPLE  ·  THE PURGE"
	# L5 display. The title is the only thing on the screen allowed this size, and it gets the game's
	# own display face rather than the engine default.
	_type(t1, "display", 24.0 if lite else 34.0, Color("ffe9c2"))
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hv.add_child(t1)
	# THE KICKER IS SCENE-SETTING, and scene-setting is the first thing to go on a phone: the wave
	# count is a constant no choice on this screen alters, and Grimwick has just spent four pages
	# saying it. On a desktop it costs nothing; on an 844x390 landscape it costs a card.
	var t2 := Label.new()
	t2.visible = not lite
	t2.text = "%d arenas.  One Chikimon.  Defeat the corruption." % ROUNDS
	_type(t2, "body", 16.0, Color(1, 1, 1, 0.62))
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hv.add_child(t2)
	_body.add_child(_spacer(gap))

	# ── B. the gates, as chips ──

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", int(gap))
	_body.add_child(chips)
	# the offering chip does the comparison FOR the player instead of asking them to make it across
	# two rows twelve pixels apart
	var c_off := _chip(chips, "THE OFFERING", 2.0, GOLD if offer_ok else BAD)
	var ov := HBoxContainer.new()
	ov.add_theme_constant_override("separation", 10)
	c_off.add_child(ov)
	_icon(ov, "res://mat/essence.png", 34.0)
	var ol := Label.new()
	ol.text = "FREE PRACTICE" if _asset_test_mode() else "%d × DARK ENERGY" % int(OFFERING["essence"])
	# GOLD IS NO LONGER SPENT HERE. It was on twelve elements and therefore meant nothing; it is now
	# reserved for exactly two things on this screen — the primary action and the selected card.
	# Affordability is carried by the chip's own border and by BAD when it genuinely fails.
	_type(ol, "bold", 28.0, Color(0.93, 0.90, 0.98) if offer_ok else BAD)
	ov.add_child(ol)
	_vrule(ov, 28.0)
	var oh := Label.new()
	oh.text = "test every Chikimon" if _asset_test_mode() else "you hold %d" % _mat_n("essence")
	_type(oh, "body", 19.0, Color(0.70, 0.64, 0.82) if offer_ok else BAD)
	oh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ov.add_child(oh)
	# TODAY'S CEILING, SHOWN ON THE WAY IN, and "—" until the server read lands — never a guess.
	var runs_col: Color = Color(0.70, 0.64, 0.82) if _runs_left < 0 else (Color(0.93, 0.90, 0.98) if _runs_left > 0 else BAD)
	var c_runs := _chip(chips, "RUNS LEFT TODAY", 1.0, runs_col if _runs_left == 0 else Color(0.45, 0.40, 0.55))
	var rl := Label.new()
	rl.text = "UNLIMITED" if _asset_test_mode() else ("—" if _runs_left < 0 else str(_runs_left))
	_type(rl, "bold", 28.0, runs_col)
	c_runs.add_child(rl)
	if _chiki_per > 0.0:
		var c_pay := _chip(chips, "PER SIGIL BROKEN", 1.0, Color(0.45, 0.40, 0.55))
		var pv := HBoxContainer.new()
		pv.add_theme_constant_override("separation", 8)
		c_pay.add_child(pv)
		var ct := TextureRect.new()
		ct.texture = UISkin.coin_tex()
		ct.custom_minimum_size = Vector2(28, 28)
		ct.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ct.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pv.add_child(ct)
		var pl := Label.new()
		pl.text = "%d $CHIKI" % int(_chiki_per)
		_type(pl, "bold", 28.0, Color(0.93, 0.90, 0.98))
		pv.add_child(pl)
	_body.add_child(_spacer(gap))

	# ── C. the rule about the grid, which is also the selection readback ──
	var sel_name := ""
	for u in fit:
		if String((u as Dictionary).get("uid", "")) == _horde_pick_uid:
			sel_name = _profile.unit_name(u as Dictionary)
	if sel_name.length() > 22:
		sel_name = sel_name.substr(0, 22) + "…"
	var rule := Label.new()
	rule.text = ("SEND ONE  —  %s walks in alone" % sel_name) if sel_name != "" else "SEND ONE  —  no chikimon is able"
	if _asset_test_mode() and sel_name != "":
		rule.text += "  ·  all 41 switchable inside the fight"
	_type(rule, "bold", 16.0, Color(0.70, 0.64, 0.82))     # a section LABEL, not a headline competing with the title
	rule.visible = not lite
	_body.add_child(rule)
	var hr := ColorRect.new()
	hr.color = Color(1, 1, 1, 0.10)
	hr.custom_minimum_size = Vector2(0, 0 if lite else 2)
	hr.visible = not lite
	_body.add_child(hr)
	_body.add_child(_spacer(gap * 0.75))

	# ── D. the roster, as cards you can actually look at ──
	# A DROPDOWN IS A CONTROL FOR CHOOSING AMONG MANY, and Econ.PARTY_MAX is 3. It hid all three
	# candidates behind a click and rendered the chosen one as a text row with no picture, no
	# element and no rarity — the worst element on a screen whose whole job is deciding which
	# creature to stake. The cards write the same single _horde_pick_uid String, so nothing
	# downstream changes.
	var btn_h: float = maxf(72.0, _ov_touch())
	# THE GRID GETS WHAT IS LEFT, MEASURED — not what a desktop constant guessed. The blocks above it
	# are already built, so their real minimum heights are askable; the two blocks below it are
	# stated in CSS and converted, because a logical constant is a different size on every device.
	# The desktop-shaped 80/38/48/30 constants under-counted the phone by enough to push the loot
	# strip through the cards and the buttons clean off the bottom of an 844x390 screen.
	var above: float = hdr.get_combined_minimum_size().y + chips.get_combined_minimum_size().y 		+ rule.get_combined_minimum_size().y + 2.0
	var loot_h: float = 0.0 if lite else maxf(34.0, float(_fs(18.0)) * 1.6)
	var status_h: float = 0.0 if msg == "" else float(_fs(16.0)) * 1.5
	var fixed: float = above + loot_h + btn_h + status_h + gap * (4.0 if not lite else 3.0)
	# THE CARD SIZE IS NOW A CAUSE, NOT AN EFFECT. It used to be "whatever is left of a full-height
	# panel", which is exactly how the panel came to be full-height. A creature card is sized from
	# its own width at a fixed 5:6 portrait ratio, and the panel adds up to whatever that needs.
	var cols_n: float = float(maxi(1, mini(intro_units.size(), 3)))
	var card_w0: float = minf(262.0 if not lite else 344.0,
		(inner_w - 18.0 * (cols_n - 1.0)) / cols_n)
	var grid_h: float = _intro_grid_height(card_w0, lite, intro_units)
	if OS.get_environment("CHIK_UI_BUDGET") == "1":
		print("INTROCARD panel=%.0fx%.0f of vw %.0fx%.0f = %.1f%% of screen area"
			% [_panel.custom_minimum_size.x, fixed + grid_h + 6.0 + (28.0 if lite else 40.0),
			get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y,
			100.0 * (_panel.custom_minimum_size.x * (fixed + grid_h + 6.0 + (28.0 if lite else 40.0)))
			/ (get_viewport().get_visible_rect().size.x * get_viewport().get_visible_rect().size.y)])
		print("INTROBUDGET lite=%s inner=%.0fx%.0f above=%.0f loot=%.0f btn=%.0f status=%.0f grid=%.0f sum=%.0f over=%.0f"
			% [str(lite), inner_w, inner_h, above, loot_h, btn_h, status_h, grid_h,
			fixed + grid_h, 0.0])   # content-sized: there is nothing to overflow
	var n := intro_units.size()
	if n == 0:
		var empty := VBoxContainer.new()
		empty.alignment = BoxContainer.ALIGNMENT_CENTER
		empty.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		empty.custom_minimum_size = Vector2(0, grid_h * 0.6)
		_body.add_child(empty)
		_icon(empty, "res://ico_asleep.png", 96.0)
		var el := Label.new()
		el.text = "Every chikimon in your party is fainted, resting or spent."
		el.add_theme_font_size_override("font_size", _fs(19.0))
		el.add_theme_color_override("font_color", BAD)
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		el.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		empty.add_child(el)
	else:
		var grid := GridContainer.new()
		grid.columns = mini(n, 3)
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 18)
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		grid.size_flags_vertical = Control.SIZE_EXPAND_FILL   # the cards absorb the leftover height
		_body.add_child(grid)
		# the 560 cap matters: without it a single candidate stretches the full card width and
		# balloons its dex art
		var card_w: float = card_w0
		var card_h: float = grid_h
		for u_v in intro_units:
			var u: Dictionary = u_v
			var uid := String(u.get("uid", ""))
			var sp := String(u.get("species", ""))
			var kind := String(u.get("kind", Econ.unit_kind(sp)))
			var on := uid == _horde_pick_uid
			var card := Button.new()
			card.custom_minimum_size = Vector2(card_w, card_h)
			card.focus_mode = Control.FOCUS_NONE
			var cs := StyleBoxFlat.new()
			# STATE READS FROM FILL AND LIFT, NOT FROM A THICKER STROKE. Measured on the old values,
			# the card fill sat 1.12:1 against the panel and the selected fill 1.20:1 against
			# unselected — both invisible — so a 4px-to-8px gold border was doing 100% of the work.
			# The fills now carry it and one border width serves every state.
			cs.bg_color = Color(0.26, 0.17, 0.40, 0.98) if on else Color(0.155, 0.115, 0.235, 0.96)
			cs.border_color = GOLD if on else Color(0.34, 0.29, 0.44)
			cs.set_border_width_all(2)
			cs.set_corner_radius_all(_sp(12.0))
			cs.set_content_margin_all(_sp(16.0))
			cs.shadow_color = Color(0, 0, 0, 0.45)
			cs.shadow_size = _sp(10.0)
			cs.shadow_offset = Vector2(0, _sp(4.0))
			# the SAME box on all three states: a Button with only "normal" set flashes its theme
			# default on hover, and flat = true would drop the box entirely
			card.add_theme_stylebox_override("normal", cs)
			card.add_theme_stylebox_override("hover", cs)
			card.add_theme_stylebox_override("pressed", cs)
			card.pressed.connect(func():
				_horde_pick_uid = uid
				_build())
			grid.add_child(card)
			var cv := VBoxContainer.new()
			cv.set_anchors_preset(Control.PRESET_FULL_RECT)
			cv.offset_left = 14; cv.offset_top = 14
			cv.offset_right = -14; cv.offset_bottom = -14
			cv.add_theme_constant_override("separation", 4 if lite else 6)
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(cv)
			var dex := "res://dex_%s.png" % sp
			if ResourceLoader.exists(dex):
				var pic := TextureRect.new()
				pic.texture = load(dex)
				pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				pic.custom_minimum_size = Vector2(0, 86.0 if lite else 150.0)
				pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
				pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
				cv.add_child(pic)
			var nm := Label.new()
			# NEVER clip_text and NEVER OVERRUN_TRIM_ELLIPSIS: a trimmable Label reports ~0 minimum
			# width and renders BLANK inside a tight box. This project has hit that three times.
			nm.text = _intro_card_name(u)
			_type(nm, "display", 18.0 if lite else 23.0, Color(0.93, 0.90, 0.98))
			nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			nm.custom_minimum_size.y = _intro_name_height(nm.text,
				maxf(1.0, card_w - 28.0), lite)
			nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cv.add_child(nm)
			var el_key := Econ.el_of(sp)
			var meta := HBoxContainer.new()
			meta.alignment = BoxContainer.ALIGNMENT_CENTER
			meta.add_theme_constant_override("separation", 12)
			meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cv.add_child(meta)
			_icon(meta, String(Econ.el_icon(el_key)), 26.0)
			var ell := Label.new()
			ell.text = el_key
			# el_color does NOT lowercase its key and falls back silently, so pass Econ.el_of straight.
			# The element keeps its own hue: it is the one place colour is genuinely the information.
			_type(ell, "bold", 12.0 if lite else 16.0, Nameplate.el_color(el_key))
			meta.add_child(ell)
			_vrule(meta, 22.0)
			var lvl := Label.new()
			lvl.text = "Lv %d" % int(u.get("level", 1))
			_type(lvl, "bold", 12.0 if lite else 19.0, Color(0.93, 0.90, 0.98))
			meta.add_child(lvl)
			# THE TWO MULTIPLIERS THAT ACTUALLY DECIDE THE RUN, on the creature they belong to, so
			# two candidates can be compared by looking instead of by remembering a sentence.
			var mult := HBoxContainer.new()
			mult.alignment = BoxContainer.ALIGNMENT_CENTER
			mult.add_theme_constant_override("separation", 10)
			mult.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cv.add_child(mult)
			_icon(mult, String(Econ.class_icon(sp)), 28.0)   # emblem only, never the word
			var rs: Dictionary = TempleHorde3D.RARITY_STATS.get(kind, TempleHorde3D.RARITY_STATS.get("normal", {}))
			var dmg := Label.new()
			dmg.text = "×%.2f" % float(rs.get("damage", 1.0))
			_type(dmg, "bold", 12.0 if lite else 19.0, Color(rs.get("color", "ffffff")))
			mult.add_child(dmg)
			if _profile != null and _profile.has_method("mood_card_mult"):
				_vrule(mult, 22.0)
				var bond := Label.new()
				# bond is a real 0.92-1.20 term in purge_power and nothing has ever shown it
				bond.text = "♥ ×%.2f" % _profile.mood_card_mult(uid)
				_type(bond, "bold", 12.0 if lite else 19.0, Color(0.93, 0.90, 0.98))
				mult.add_child(bond)
			# NO element-matchup edge here: _sigil is "" during "intro" (the order is shuffled inside
			# _begin), so every card would read "even" — a fabrication. That belongs to _draw_pick.
	_body.add_child(_spacer(gap))

	# ── E. what it pays, as five icons: five percentages ARE a table ──
	var loot := HFlowContainer.new()
	loot.visible = not lite     # read once, not per run — the first infotab to go on a small screen
	loot.alignment = FlowContainer.ALIGNMENT_CENTER
	loot.add_theme_constant_override("h_separation", 20)
	loot.add_theme_constant_override("v_separation", 8)
	_body.add_child(loot)
	var lhead := Label.new()
	lhead.text = "VICTORY LOOT  ·  ONE REWARD" if loot_live else (
		"VICTORY LOOT  ·  not open yet" if _loot_state_known else "VICTORY LOOT")
	_type(lhead, "bold", 16.0, Color(0.70, 0.64, 0.82))
	loot.add_child(lhead)
	# These are the exact overall chances from the same 10,000-slot contract used by the client
	# and server: 80% Fantasy Fish, then the 20% egg pool normalized from 60:15:10:5.
	for pair in [["res://ico_fish.png", "80%"], ["res://ico_egg.png", "13.34%"],
			["res://ico_class_legendary.png", "3.33%"], ["res://ico_mountdex.png", "2.22%"],
			["res://ico_class_meme.png", "1.11%"]]:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 8)
		loot.add_child(cell)
		_icon(cell, String(pair[0]), 28.0)
		var pc := Label.new()
		pc.text = String(pair[1])
		_type(pc, "bold", 19.0, Color(0.93, 0.90, 0.98) if loot_live else Color(0.70, 0.64, 0.82))
		pc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.add_child(pc)
	_body.add_child(_spacer(gap))

	# ── F. the one action, and the two ways out ──
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	_body.add_child(row)
	var go := Button.new()
	go.text = "  Begin the Purge  "
	UISkin.plaque(go, EDGE)
	UISkin.touch_h(go, btn_h)
	# THE ACCENT FINALLY LANDS ON THE ACTION. UISkin.plaque paints violet with brown ink at 4.2:1;
	# on this screen the primary is GOLD with near-black ink (~11:1) and it is the only gold surface.
	# Applied AFTER the skin call, which writes its own font and size.
	_type(go, "display", 23.0, Color(0.10, 0.06, 0.02))
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = GOLD
	gsb.border_color = Color(0.36, 0.24, 0.04)
	gsb.set_border_width_all(2)
	gsb.border_width_bottom = _sp(5.0)      # the extrude survives HERE ONLY: this one is pressable
	gsb.set_corner_radius_all(_sp(8.0))
	gsb.content_margin_left = _sp(24.0); gsb.content_margin_right = _sp(24.0)
	var ghov := gsb.duplicate() as StyleBoxFlat
	ghov.bg_color = GOLD.lightened(0.14)
	var gdis := gsb.duplicate() as StyleBoxFlat
	gdis.bg_color = Color(0.30, 0.26, 0.20)
	gdis.border_color = Color(0.24, 0.21, 0.17)
	for st in ["normal", "focus"]:
		go.add_theme_stylebox_override(st, gsb)
	go.add_theme_stylebox_override("hover", ghov)
	go.add_theme_stylebox_override("pressed", ghov)
	go.add_theme_stylebox_override("disabled", gdis)
	go.add_theme_color_override("font_disabled_color", Color(0.62, 0.60, 0.56))
	go.disabled = not offer_ok or fit.is_empty()
	go.pressed.connect(_begin)
	row.add_child(go)
	var again := Button.new()
	again.text = "  Grimwick  "
	again.tooltip_text = "Hear the warlock's account of this place again."
	UISkin.ghost(again)
	UISkin.touch_h(again, btn_h)
	_type(again, "bold", 19.0, Color(0.26, 0.19, 0.08))   # brown ink: ghost is cream parchment
	again.pressed.connect(func():
		_lore_page = 0
		_phase = "lore"
		_build())
	row.add_child(again)
	var leave := Button.new()
	leave.text = "  Leave  "
	UISkin.ghost(leave)
	UISkin.touch_h(leave, btn_h)
	_type(leave, "bold", 19.0, Color(0.26, 0.19, 0.08))   # brown ink: ghost is cream parchment
	leave.pressed.connect(close)
	row.add_child(leave)

	# ── G. why you cannot go, when you cannot. Decided at the top of this function so its band is
	#    only reserved in the budget when it exists; the grid's own empty state covers the no-roster
	#    case, and saying it twice is noise. ──
	if fit.is_empty():
		msg = ""
	if msg != "":
		_body.add_child(_spacer(gap * 0.5))
		var ml := Label.new()
		ml.text = msg
		ml.add_theme_font_size_override("font_size", _fs(16.0))
		ml.add_theme_color_override("font_color", msg_col)
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ml.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		_body.add_child(ml)



func _row(parent: Control, k: String, v: String, col: Color) -> void:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var a := Label.new()
	a.text = k
	a.add_theme_font_size_override("font_size", 12)
	a.add_theme_color_override("font_color", DIM)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(a)
	var b := Label.new()
	b.text = v
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", col)
	h.add_child(b)

func _begin() -> void:
	# ONE PRESS, ONE OFFERING. Godot delivers a frame's accumulated input in one flush, so two taps
	# inside a single frame — 50 ms at the phone tier's 20 fps, which is an ordinary impatient
	# double-tap — both reach this handler before the Begin button's queue_free lands. Measured in
	# dev_temple_attack A8: two presses took essence 12 -> 6, SIX Dark Energy for ONE ritual, and
	# the second _begin also restarted _round/_purified/_log under the run the first had started.
	# The offering is the only thing this screen can take from a player, so it takes it once.
	if _phase != "intro":
		return
	if not _has_offering() or _fit_units().is_empty():
		return
	# PAID ONCE, HERE, BEFORE THE FIRST SIGIL. Charging per round would let a player walk after a bad
	# opening having paid a third of the price; charging at the end would let them walk having paid
	# none. The offering buys the whole ritual.
	# The all-assets laboratory is a read-only presentation sandbox. It neither earns rewards nor
	# consumes the three-energy offering; otherwise the result screen's "inventory unchanged" claim
	# would already be false before its preview-only ceremony opened.
	if not _asset_test_mode():
		_profile.spend_mats(OFFERING, "temple purge")
	_run_id = _new_run_id()
	_stage_stats.clear()
	_loot_reward.clear()
	_loot_why = ""
	_loot_run_id = ""
	_report_retries = 0
	_paid_amt = 0.0
	_paid_why = ""
	_round = 0
	_purified = 0
	_log.clear()
	_duel_focus.clear()
	# A run now has a readable arc instead of five rolls with replacement: each side-alcove seal
	# appears once, in a fresh order, and the central Light seal is always the Grimwick finale.
	_sigil_order = ["Water", "Fire", "Beast", "Storm"]
	_sigil_order.shuffle()
	_sigil_order.append("Light")
	_mode = "world" if _world_available() else "modal"
	if _mode == "world":
		_enter_world()
		if _phase == "done" or _busy:
			return
		# The side-scroller is one continuous five-seal stage. Its world owns encounters, creature
		# attacks and pacing, then returns one final run summary; the old hall advances through five
		# separate seek/duel screens and must keep doing so when explicitly selected.
		if _mode == "world" and _platformer_world:
			_phase = "stage"
			return
	_next_round()

static func _world_available() -> bool:
	# CHIK_TEMPLE_FLAT=1 still forces the modal card ritual, and it is now a DEVELOPER escape hatch
	# rather than a fallback: it is the only way to open this screen without the arena, which a
	# probe occasionally needs. No player reaches it, because nothing sets the variable for them.
	if OS.get_environment("CHIK_TEMPLE_FLAT") == "1":
		return false
	return _world_script() != ""

# WHICH HALL — there is one. See _world_script for the ruling and the reason.
# ==============================================================================================
# THE WICKED TEMPLE IS ONE GAME: your single chikimon against the corruptimons.
# ==============================================================================================
# OWNER RULING (2026-09-03). Four halls had accumulated here — the horde siege, a side-scrolling
# platformer, the legacy turn-based ritual on Temple3D, and the flat modal fallback — each
# selectable by its own environment flag. They are four different games wearing one door, and a
# player who reaches that door should always get the same one.
#
# WHY THIS IS A HARD RETURN AND NOT A PREFERENCE. The fallback chain was not a safety net, it was a
# trapdoor: if TempleHorde3D failed to load for any reason, the player silently landed in a
# DIFFERENT GAME with different rules, a different win condition and — critically — a different
# round count. The client reports {rounds, purified} to a server that rejects any count but its
# own, so a silent hall swap is also a silent payment failure. One hall means one contract.
#
# The other three files stay on disk and keep their probes; nothing here loads them. They are
# reachable only by editing this function, which is the honest way to run an experiment.
static func _world_script() -> String:
	if ResourceLoader.exists("res://TempleHorde3D.gd") and ResourceLoader.exists("res://Rig3D.gd"):
		return "res://TempleHorde3D.gd"
	return ""

static func _continuous_world_path(path: String) -> bool:
	return path == "res://TempleHorde3D.gd"

static func _world_path_is_3d(path: String) -> bool:
	return path == "res://TempleHorde3D.gd"

# ============================== 2. the sigil ==================================================
func _next_round() -> void:
	# THE RITUAL IS OVER ONCE IT IS OVER. Same one-frame double-press as _begin, on the advance
	# button this time. Measured in dev_temple_attack A7: two "Face Grimwick" presses in one frame
	# drove _round to 5 and ran _finish() — and therefore _report() — TWICE for one offering.
	# The money survived only because server.js refuses the second post inside TEMPLE_MIN_GAP_MS
	# (measured: runs=1, chiki=40, not 80). But the 429 reply then landed in _paid() AFTER the
	# honest one and overwrote the card with "nothing was paid this run" while 20 $CHIKI was
	# already in the pouch. A client must not depend on a server's rate limiter for its own
	# arithmetic, so the second press stops here.
	if _phase == "done" or _busy:
		return
	_round += 1
	if _round > ROUNDS:
		_finish()
		return
	# Four different Corruptimon wardens guard the side seals; the fifth beat is the central Light
	# seal and Grimwick himself.  The order is shuffled once in _begin so every element matters and
	# the button that says "Face Grimwick" finally leads to a boss fight.
	if _sigil_order.size() != ROUNDS:
		_sigil_order = ["Water", "Fire", "Beast", "Storm", "Light"]
	_sigil = String(_sigil_order[clampi(_round - 1, 0, _sigil_order.size() - 1)])
	_pick_uid = ""
	if _mode == "world":
		# THE SEEK BEAT — the Pokemon half of the redesign. The sigil is not a menu any more: the
		# hall lights ONE alcove and the player has to walk to it. Temple2D owns movement, collision
		# and the reach signal; this side only names the element and waits.
		_phase = "seek"
		if _world != null:
			_world.call("set_lit", _sigil)
			_world.call("set_input_enabled", true)
		_ov_clear()
		_ov_say("SIGIL %d OF %d  —  the %s sigil burns. Find it." % [_round, ROUNDS, _sigil.to_upper()])
		return
	_phase = "pick"
	_build()

# EVERY PHASE MUST HAVE A DOOR (owner, 2026-08-29: "the game lags and gets stuck").
#
# It shipped without one. The scrim only closed on intro and done, and pick/channel/resolve carried
# no Leave at all — so pressing "Begin the Purge" sealed a full-screen modal that eats world input
# until the run finishes. Worse, the roster grid is built from _fit_units(), and corruptimons go on
# attacking the party THROUGH the modal (Monsters.gd never stops, and they chase the player up the
# south approach). A party knocked out or drained mid-run therefore drew ZERO cards with no exit:
# an unrecoverable lock, reload the only way out. That is the "gets stuck".
#
# So: one abandon door, on every mid-ritual phase, saying plainly what it costs.
func _abandon_row() -> void:
	var r := HBoxContainer.new()
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(r)
	var b := Button.new()
	b.text = "  Abandon the purge  "
	b.add_theme_font_size_override("font_size", 12)
	UISkin.ghost(b)
	UISkin.touch_h(b, _ov_touch())
	b.tooltip_text = "Leave now. The offering you paid is not returned."
	b.pressed.connect(close)
	r.add_child(b)
	_head("Leaving now forfeits the offering.", 10, DIM)

func _draw_pick() -> void:
	_head("SIGIL %d OF %d" % [_round, ROUNDS], 14, DIM)
	var col := _el_col(_sigil)
	_head(_sigil.to_upper(), 34, col)
	_sigil_art(col)
	_head("Send a chikimon. Strong elements break the sigil; the pentagon is the same one you\nfight on.", 12, DIM)

	# CENTRED IN WHAT IS LEFT. The frame is a fixed landmark-sized panel (the Chikiseum's rule), so
	# a small party would otherwise sit marooned against the top edge with two thirds of the card
	# empty below it. The centre container takes the slack; the grid stays its natural size.
	var able := _asset_test_units() if _asset_test_mode() else _fit_units()
	if _asset_test_mode():
		_asset_build_picker(_body, able, false)
	else:
		var mid := CenterContainer.new()
		_body.add_child(mid)
		var grid := GridContainer.new()
		grid.columns = 3 if UISkin.lite_world() else 4
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		mid.add_child(grid)
		for u in able:
			grid.add_child(_unit_card(u))
	# THE DEAD END, NAMED. A party that was able at the doors can be unable by round two — the world
	# keeps running behind this card. Say so instead of rendering an empty grid the player cannot act
	# on and cannot leave.
	if able.is_empty():
		_head("Every chikimon in your party has fallen or is spent. The sigil cannot be answered.", 12, BAD)
	_abandon_row()

# The sigil itself: a rotating, breathing rune plate. Control-space animation, so it costs nothing
# on the phone tier and cannot fight the 3D scene for draw calls.
func _sigil_art(col: Color) -> void:
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(0, 96)
	_body.add_child(holder)
	var plate := PanelContainer.new()
	plate.custom_minimum_size = Vector2(96, 96)
	plate.pivot_offset = Vector2(48, 48)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(col.r * 0.22, col.g * 0.22, col.b * 0.22, 0.92)
	ps.border_color = col
	ps.set_border_width_all(3)
	ps.set_corner_radius_all(14)
	plate.add_theme_stylebox_override("panel", ps)
	holder.add_child(plate)
	var ic := TextureRect.new()
	var ip := Econ.el_icon(_sigil)
	if ip != "" and ResourceLoader.exists(ip):
		ic.texture = load(ip)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(64, 64)
		plate.add_child(ic)
	# KILLED ON THE NEXT REBUILD. An infinite tween per _build() would otherwise pile up across the
	# ten sigil draws in a run (pick + resolve, five rounds) and keep ticking against freed plates.
	if _sig_tw != null and _sig_tw.is_valid():
		_sig_tw.kill()
	var tw := create_tween().set_loops()
	_sig_tw = tw
	tw.tween_property(plate, "rotation", deg_to_rad(6.0), 1.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(plate, "rotation", deg_to_rad(-6.0), 1.4).set_trans(Tween.TRANS_SINE)

func _unit_card(u: Dictionary) -> Control:
	var sp := String(u["species"])
	var el := Econ.el_of(sp)
	var mult := Econ.el_mult(el, _sigil)
	var b := Button.new()
	b.custom_minimum_size = Vector2(120, 150)
	# NOT flat. A flat Button draws NO stylebox, which silently threw away the matchup edge below —
	# the one affordance this screen exists to give. Caught by looking at the render; every
	# assertion about the maths passed while the colour that carries it was invisible.
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.13, 0.09, 0.19, 0.95)
	# THE MATCHUP IS THE CARD'S EDGE, so the read is instant and needs no legend: gold for the
	# advantage, red for the resisted send, neutral otherwise.
	bs.border_color = GOLD if mult > 1.0 else (BAD if mult < 1.0 else Color(0.45, 0.40, 0.55))
	bs.set_border_width_all(2)
	bs.set_corner_radius_all(12)
	bs.set_content_margin_all(6)
	b.add_theme_stylebox_override("normal", bs)
	b.add_theme_stylebox_override("hover", bs)
	b.add_theme_stylebox_override("pressed", bs)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(v)
	var art := TextureRect.new()
	var dp := "res://dex_%s.png" % sp
	if ResourceLoader.exists(dp):
		art.texture = load(dp)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = Vector2(0, 74)
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(art)
	var nm := Label.new()
	nm.text = _profile.unit_name(u)
	nm.add_theme_font_size_override("font_size", 12)
	nm.add_theme_color_override("font_color", INK)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	v.add_child(nm)
	var sub := Label.new()
	sub.text = "%s · L%d" % [el, int(u["level"])]
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", _el_col(el))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var tag := Label.new()
	tag.text = "STRONG" if mult > 1.0 else ("RESISTED" if mult < 1.0 else "even")
	tag.add_theme_font_size_override("font_size", 10)
	tag.add_theme_color_override("font_color", GOLD if mult > 1.0 else (BAD if mult < 1.0 else DIM))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)
	var uid := String(u["uid"])
	b.pressed.connect(func(): _chose(uid))
	return b

func _chose(uid: String) -> void:
	# The phase flips before any profile/world work: two taps delivered in one input flush can only
	# commit the first creature.  Production still accepts only a fit party member; the sealed test
	# session accepts any owned Chikimon and repairs its disposable test vitals on Send.
	if not visible or _phase != "pick" or _busy or _chan_running:
		return
	var allowed := _asset_test_units() if _asset_test_mode() else _fit_units()
	var found := false
	for candidate in allowed:
		if candidate is Dictionary and String((candidate as Dictionary).get("uid", "")) == uid:
			found = true
			break
	if not found:
		return
	_phase = "channel"
	if _asset_test_mode():
		_asset_restore_unit(uid)
		_release_helper()
		if not _profile.has_method("lead_unit"):
			_asset_send_failed()
			return
		_profile.call("lead_unit", uid)
		var active: Dictionary = _profile.active_unit() if _profile.has_method("active_unit") else {}
		if String(active.get("uid", "")) != uid:
			_asset_send_failed()
			return
		if _mode == "world":
			if _world == null or not is_instance_valid(_world):
				_asset_send_failed()
				return
			var has_selected := _world.has_method("has_follower") and bool(_world.call("has_follower", uid))
			if not has_selected and _world.has_method("set_party"):
				_world.call("set_party", _party_for_world())
			has_selected = _world.has_method("has_follower") and bool(_world.call("has_follower", uid))
			if not has_selected:
				_asset_send_failed()
				return
	_pick_uid = uid
	var u := _unit(uid)
	var sp := String(u.get("species", ""))
	var kit: Array = Econ.SIGNATURE.get(sp, [0, 1, 2])
	_pick_slot = int(kit[(_round - 1) % maxi(1, kit.size())])
	_phase = "channel"
	if _mode == "world":
		# THE SEND, in the world: the chosen miniature steps out of formation and the sigil becomes
		# a real multi-turn duel.  The old path auto-picked one move here and offered only a timing
		# tap; the player now chooses cards, reads the enemy intent and may swap creatures mid-fight.
		_spawn_helper(uid)
		_duel_begin(uid)
		return
	_build()

# ============================== 3. the channel ================================================
# One tap, and it is the only twitch in the mode. It exists so a favourable matchup still asks
# something of the player, and so an unfavourable one is not hopeless — the band is wide enough
# (12% of the sweep) that it rewards attention rather than reflexes.
func _draw_channel() -> void:
	var col := _el_col(_sigil)
	_head("CHANNEL THE PURGE", 22, EDGE)
	_head("Stop the light inside the band.  [SPACE] or tap", 12, DIM)
	var track := PanelContainer.new()
	track.custom_minimum_size = Vector2(0, 46)
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.09, 0.06, 0.13, 0.95)
	ts.border_color = Color(0.35, 0.30, 0.45)
	ts.set_border_width_all(2)
	ts.set_corner_radius_all(10)
	track.add_theme_stylebox_override("panel", ts)
	_body.add_child(track)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(0, 34)
	track.add_child(inner)
	_chan_zone = ColorRect.new()
	_chan_zone.color = Color(col.r, col.g, col.b, 0.42)
	inner.add_child(_chan_zone)
	_chan_marker = ColorRect.new()
	_chan_marker.color = Color(1, 1, 1, 0.95)
	inner.add_child(_chan_marker)
	# The band is placed fresh every round so it cannot be learned as muscle memory in one sitting.
	_chan_band = randf_range(0.18, 0.82)
	_chan_t = 0.0
	_chan_dir = 1.0
	_chan_running = true
	var tap := Button.new()
	tap.text = "  CHANNEL  "
	tap.add_theme_font_size_override("font_size", 18)
	UISkin.plaque(tap, EDGE)
	UISkin.touch_h(tap, maxf(50.0, _ov_touch()))
	tap.pressed.connect(_stop_channel)
	var r := HBoxContainer.new()
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(r)
	r.add_child(tap)
	_abandon_row()

func _process(delta: float) -> void:
	if not _chan_running or _chan_marker == null or not is_instance_valid(_chan_marker):
		return
	# 1.35 sweeps a second, ping-ponged. Fast enough to matter, slow enough to be fair on a phone
	# where the tap has to travel through a touch event.
	_chan_t += delta * 1.35 * _chan_dir
	if _chan_t >= 1.0:
		_chan_t = 1.0; _chan_dir = -1.0
	elif _chan_t <= 0.0:
		_chan_t = 0.0; _chan_dir = 1.0
	var w: float = _chan_marker.get_parent().size.x
	var h: float = _chan_marker.get_parent().size.y
	if w <= 1.0:
		return
	_chan_zone.position = Vector2((_chan_band - 0.06) * w, 0)
	_chan_zone.size = Vector2(0.12 * w, h)
	_chan_marker.position = Vector2(_chan_t * w - 2.0, 0)
	_chan_marker.size = Vector2(4, h)

func _unhandled_input(ev: InputEvent) -> void:
	if not visible:
		return
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE:
		# ESC ALWAYS LEAVES. Not only from the phases that happen to have a button — this modal
		# covers the screen and swallows movement, so there has to be one key that always works.
		close()
		get_viewport().set_input_as_handled()
		return
	if _chan_running and ev is InputEventKey and ev.pressed and not ev.echo \
			and (ev.keycode == KEY_SPACE or ev.keycode == KEY_ENTER):
		_stop_channel()
		get_viewport().set_input_as_handled()

func _stop_channel() -> void:
	if not _chan_running:
		return
	_chan_running = false
	var off: float = absf(_chan_t - _chan_band)
	# 0.06 is the band's half-width, so "inside the band" is exactly what the eye was told it was.
	var timing: float = 1.25 if off <= 0.06 else (1.0 if off <= 0.16 else 0.8)
	if _duel != null and _duel_pending_hand >= 0 and _mode == "world":
		_duel_commit(timing)
	else:
		# Flat/no-world fallback keeps the compact classic beat; the shipped 3D and 2D worlds use
		# the full Sigil Duel above.
		_resolve(timing)

# ============================== 4. the break ==================================================
func _resolve(timing: float) -> void:
	var u: Dictionary = _unit(_pick_uid)
	var sp := String(u.get("species", ""))
	var el := Econ.el_of(sp)
	var lvl := int(u.get("level", 1))
	# THE REAL BATTLE TERMS, in the order Battle.gd:1059 applies them: element, then the level
	# scalar, then mood. Nothing invented, so a strong chikimon here is strong for a reason the
	# player has already learned somewhere else.
	var mult := Econ.el_mult(el, _sigil)
	var mood: float = 1.0
	if _profile.has_method("mood_card_mult"):
		mood = float(_profile.mood_card_mult(_pick_uid))
	var card_mul := _purge_card_mul(_pick_slot, lvl)
	var power: float = purge_power(mult, lvl, mood, timing) * card_mul
	var broke: bool = power >= PURIFY_BAR
	if broke:
		_purified += 1
	_log.append({"sigil": _sigil, "uid": _pick_uid, "name": _profile.unit_name(u), "el": el,
		"lvl": lvl, "mult": mult, "timing": timing, "power": power, "broke": broke,
		"card_slot": _pick_slot, "card": _purge_card_name(sp, _pick_slot),
		"arch": String(Econ.CARDS[_pick_slot].get("arch", "strike")), "card_mul": card_mul})
	_phase = "resolve"
	if _mode == "world":
		_ov_attack(_log[_log.size() - 1])
		return
	_build()

func _draw_resolve() -> void:
	var e: Dictionary = _log[_log.size() - 1]
	var broke: bool = bool(e["broke"])
	var col := _el_col(String(e["sigil"]))
	_head("SIGIL BROKEN" if broke else "THE SIGIL HOLDS", 26, GOLD if broke else BAD)
	_sigil_art(col)
	# THE MATHS, SHOWN. A player who loses a round is owed the reason — and the reason is a
	# decision they can make differently next time, which is the only thing that makes the choice
	# real. Printing the actual multipliers is also how this screen stays honest about its own rules.
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_body.add_child(box)
	_row(box, String(e["name"]), "%s · L%d" % [e["el"], int(e["lvl"])], INK)
	_row(box, "Element", "×%.2f" % float(e["mult"]),
		GOLD if float(e["mult"]) > 1.0 else (BAD if float(e["mult"]) < 1.0 else DIM))
	_row(box, "Channel", "×%.2f" % float(e["timing"]),
		GOLD if float(e["timing"]) > 1.0 else DIM)
	_row(box, "Purge power", "%.2f  (need %.2f)" % [float(e["power"]), PURIFY_BAR],
		GOLD if broke else BAD)
	var r := HBoxContainer.new()
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(r)
	var nx := Button.new()
	nx.text = "  Next sigil  " if _round < ROUNDS else "  Face Grimwick  "
	nx.add_theme_font_size_override("font_size", 17)
	UISkin.plaque(nx, EDGE)
	UISkin.touch_h(nx, _ov_touch())
	nx.pressed.connect(_next_round)
	r.add_child(nx)
	_abandon_row()
	if _panel != null:
		var t := create_tween()
		if broke:
			t.tween_property(_panel, "modulate", Color(1.25, 1.18, 1.0), 0.10)
			t.tween_property(_panel, "modulate", Color(1, 1, 1), 0.28)
		else:
			# a short recoil rather than a flash — failure should feel like the temple pushing back
			t.tween_property(_panel, "position:x", _panel.position.x + 9.0, 0.05)
			t.tween_property(_panel, "position:x", _panel.position.x - 9.0, 0.05)
			t.tween_property(_panel, "position:x", _panel.position.x, 0.05)

# ============================== 5. the tribute ================================================
func _finish() -> void:
	# THE MONEY CALL GUARDS ITSELF. _next_round already refuses a second advance, but _report() is
	# the one function in this file that asks for $CHIKI, and it should not be one caller away from
	# being asked twice.
	if _busy:
		return
	_phase = "done"
	_busy = true
	# BACK TO THE CARD for the tribute: the results screen and the server call are the verified
	# economy surface and they did not move. The world is torn down first so the card is not
	# fighting a live viewport for input.
	_teardown_world()
	if _panel != null and is_instance_valid(_panel):
		_panel.visible = true
	if _scrim != null and is_instance_valid(_scrim):
		_scrim.visible = true
	_build()
	_report()

# THE SERVER DECIDES. We send what happened and take back a number. A run that cannot reach the
# server pays NOTHING and says so — inventing a local reward here is exactly the client-authored
# faucet this design exists to avoid, and it would also desynchronise the daily cap.
func _report() -> void:
	# The all-assets laboratory never writes inventory.  It still walks every visual reward so the
	# whole presentation can be tested without turning a demo wallet into an item faucet.
	if _asset_test_mode():
		if _purified >= ROUNDS:
			_loot_reward = TempleReward.sandbox_preview_at(_sandbox_reward_index)
			_sandbox_reward_index += 1
			_loot_why = "sandbox"
		else:
			_loot_reward.clear()
			_loot_why = "defeat"
		_paid(0.0, "sandbox")
		return
	var net := get_tree().get_first_node_in_group("net")
	if net == null or not net.has_method("temple_purge"):
		_loot_why = "offline"
		_paid(-1.0, "offline")
		return
	net.call("temple_purge", _purified, ROUNDS, func(code: int, j: Dictionary):
		# THE SERVER'S OWN VOCABULARY, kept distinct. Lumping these into one "offline" would have
		# shipped a lie as the DEFAULT experience: CHIK_TEMPLE starts off, and the off reply is a
		# clean 200 that the flat branch would have reported as "could not reach the ledger".
		if code == 429:
			_loot_why = "cooling"
			_paid(-1.0, "cooling")
			return
		# A STALE CREDENTIAL IS NOT A NETWORK FAULT, and telling a player it is sends them to
		# restart their router over a problem they fix by reconnecting a wallet. server.js refuses a
		# WRONG mktToken with 401 even though the token is OPTIONAL on this route, so a save whose
		# token outlived its session posts a perfectly healthy run into a 401 forever — three Dark
		# Energy a time, with "could not reach the ledger" on the card. Found by walking into it:
		# dev_temple_attack's first run reported EVERY purge as offline while the harness was up and
		# answering, because the dev save carried a 20-character token bound to a different wallet.
		if code == 401:
			_loot_why = "auth"
			_paid(-1.0, "auth")
			return
		if code != 200:
			# A lost accepted reply is the dangerous case for item rewards. Retry once with the exact
			# same run id; the server's receipt-before-pace contract returns the original fish/egg and
			# never rolls or grants twice.
			if (code == 0 or code >= 500) and _report_retries < 1:
				_report_retries += 1
				get_tree().create_timer(0.8).timeout.connect(_report)
				return
			_loot_why = "offline"
			_paid(-1.0, "offline")
			return
		if not bool(j.get("ok", false)):
			_loot_why = String(j.get("reason", "off"))
			_paid(-1.0, String(j.get("reason", "offline")))
			return
		var run_v: Variant = j.get("runId", "")
		var server_run_id := String(run_v) if run_v is String else ""
		_accept_server_loot(j.get("loot", {}), server_run_id,
			String(j.get("lootReason", "")))
		_runs_left = int(j.get("runsLeft", -1))
		var why := "ok"
		if bool(j.get("capped", false)):
			why = "spent" if float(j.get("chiki", 0.0)) <= 0.0 else "capped"
		_paid(float(j.get("chiki", 0.0)), why), _run_id)

func _accept_server_loot(value: Variant, server_run_id: String = "", server_reason: String = "") -> void:
	_loot_reward.clear()
	_loot_run_id = server_run_id.strip_edges()
	if not (value is Dictionary) or (value as Dictionary).is_empty():
		_loot_why = server_reason if server_reason != "" else "off"
		# Keep the top-level receipt fields even when `loot` is null.  That is the backend's normal wire
		# shape for a proved refusal, not an absent response, and the HUD must explain the exact outcome.
		if server_reason != "" or _loot_run_id != "":
			_loot_reward = {"no_grant": true, "granted": false, "reason": _loot_why,
				"run_id": _loot_run_id}
		return
	var loot := (value as Dictionary).duplicate(true)
	loot["run_id"] = _loot_run_id
	_enrich_server_loot(loot)
	var wire_type := String(loot.get("reward_type", loot.get("type", "")))
	var granted := bool(loot.get("ok", loot.get("granted", wire_type in ["ffish", "egg"])))
	# A valuable card and a refusal reason are mutually exclusive in the server contract.  Fail a
	# contradictory response closed rather than materialising value while showing an error.
	if server_reason != "" or not granted:
		_loot_why = server_reason if server_reason != "" else String(loot.get("reason", "unavailable"))
		loot["no_grant"] = true
		loot["granted"] = false
		loot["reason"] = _loot_why
		_loot_reward = loot
		return
	var reward_type := wire_type
	var landed := false
	var where := ""
	if reward_type == "ffish":
		var fish := String(loot.get("item_id", loot.get("species", loot.get("sp", loot.get("item", "")))))
		if _profile != null and _profile.has_method("receive_fantasy_fish"):
			landed = bool(_profile.call("receive_fantasy_fish", fish, "wicked_temple", _loot_run_id))
			where = "Fantasy Fish inventory" if landed else ""
	elif reward_type == "egg":
		var card_v: Variant = loot.get("card", loot.get("egg", {}))
		if card_v is Dictionary and (card_v as Dictionary).is_empty() \
				and String(loot.get("id", "")) != "":
			card_v = loot
		if card_v is Dictionary and _profile != null and _profile.has_method("nft_receive"):
			var card := (card_v as Dictionary).duplicate(true)
			# The Profile arrival contract identifies an egg's subtype through `sp`.
			if String(card.get("type", "")) == "":
				card["type"] = "egg"
			if String(card.get("sp", "")) == "":
				card["sp"] = String(loot.get("item_id", loot.get("kind", "")))
			var rep_v: Variant = _profile.call("nft_receive", card)
			if rep_v is Dictionary:
				var rep := rep_v as Dictionary
				landed = bool(rep.get("added", false)) or bool(rep.get("already", false))
				where = String(rep.get("where", "nest" if landed else ""))
	loot["landed"] = landed
	loot["granted"] = true
	loot["where"] = where
	_loot_reward = loot
	_loot_why = "ok" if landed else "arrival"

func _enrich_server_loot(loot: Dictionary) -> void:
	var backend_key := String(loot.get("rewardKey", loot.get("reward_key", "")))
	var policy_key := backend_key
	if backend_key == "chikimount_egg":
		policy_key = "mount_egg"
	elif backend_key == "meme_dynasty_egg":
		policy_key = "meme_egg"
	if TempleReward.REWARD_META.has(policy_key):
		var meta := TempleReward.REWARD_META[policy_key] as Dictionary
		loot["reward_key"] = policy_key
		loot["category_label"] = String(meta.get("label", "Temple reward"))
		loot["inventory_label"] = String(meta.get("inventory_label", meta.get("label", "Temple reward")))
		loot["icon"] = String(meta.get("icon", "✦"))
		loot["color_hex"] = String(meta.get("color_hex", "#FFD86B"))
		var ctable := TempleReward.grade_table("C")
		var weights: Dictionary = ctable.get("weights", {})
		if weights.has(policy_key):
			loot["chance_percent"] = float(weights[policy_key]) / 100.0
	if String(loot.get("type", "")) == "ffish":
		var species := String(loot.get("species", ""))
		loot["item_id"] = species
		if TempleReward.FISH_META.has(species):
			var fish_meta := TempleReward.FISH_META[species] as Dictionary
			loot["label"] = String(fish_meta.get("label", "Fantasy Fish"))
			loot["icon"] = String(fish_meta.get("icon", loot.get("icon", "🐠")))
	elif String(loot.get("type", "")) == "egg":
		loot["item_id"] = String(loot.get("kind", loot.get("sp", "")))
		loot["label"] = String(loot.get("category_label", "Temple Egg"))
	# The server wire stays deliberately small. Rebuild display-only rarity, exact transparent art,
	# and the three honest odds numbers from the same pure policy the sandbox uses.
	var display := TempleRewardCeremonyScene.display_data(loot)
	if bool(display.get("ok", false)):
		for field in ["quantity", "rarity", "art_path", "top_level_category",
				"top_level_chance_percent", "chance_within_category_percent",
				"overall_chance_percent", "claim_status"]:
			loot[field] = display[field]

var _paid_amt := 0.0
var _paid_why := ""

func _paid(amount: float, why: String) -> void:
	_busy = false
	_paid_why = why
	_paid_amt = 0.0
	if amount > 0.0:
		_paid_amt = _credit(amount)
	if visible:
		_build()

# Credit through Profile.earn so the pouch cap, the emission factor and the flow ledger all behave
# exactly as they do for every other reward — then MEASURE what landed. earn() returns nothing and
# can clamp, so the pouch delta is the only truthful number to show.
func _credit(amount: float) -> float:
	var before: float = float(_profile.d.get("pouch", 0.0))
	_profile.earn(amount, "temple purge")
	return maxf(0.0, float(_profile.d.get("pouch", 0.0)) - before)

func _draw_done() -> void:
	var clean: bool = _purified >= ROUNDS
	# Let the wheel own the victory screen. The full statistics layout remains for incomplete
	# runs; a settled victory needs only its title, reveal and navigation, not competing panels.
	if clean and not _busy and not _loot_reward.is_empty() \
			and not bool(_loot_reward.get("no_grant", false)):
		_draw_wheel_done()
		return
	var result_ink := Color("0b151c")
	var result_slate := Color("1b343e")
	var result_ivory := Color("f4eddb")
	var result_dim := Color("aebeba")
	var result_cyan := Color("57d6d1")
	var result_amber := Color("efb84d")
	var header := HBoxContainer.new()
	header.name = "VictoryConclusionHeader"
	header.add_theme_constant_override("separation", 12)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(header)
	var grade := String(_stage_stats.get("grade", "C")).to_upper()
	var badge := PanelContainer.new()
	badge.name = "AnimatedGradeBadge"
	badge.custom_minimum_size = Vector2(72.0, 56.0)
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = result_amber if clean else result_slate
	badge_style.border_color = Color("ffe6a6") if clean else Color("67838b")
	badge_style.set_border_width_all(2)
	badge_style.border_width_bottom = 4
	badge_style.set_corner_radius_all(10)
	badge_style.set_content_margin_all(5)
	badge.add_theme_stylebox_override("panel", badge_style)
	header.add_child(badge)
	var badge_rows := VBoxContainer.new()
	badge_rows.add_theme_constant_override("separation", -3)
	badge.add_child(badge_rows)
	var badge_caption := Label.new()
	badge_caption.text = "PURGE GRADE"
	badge_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_caption.add_theme_font_override("font", preload("res://ui_font_bold.ttf"))
	badge_caption.add_theme_font_size_override("font_size", 8)
	badge_caption.add_theme_color_override("font_color", result_ink if clean else result_dim)
	badge_rows.add_child(badge_caption)
	var badge_grade := Label.new()
	badge_grade.text = grade
	badge_grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_grade.add_theme_font_override("font", preload("res://font_titan.ttf"))
	badge_grade.add_theme_font_size_override("font_size", 29)
	badge_grade.add_theme_color_override("font_color", result_ink if clean else result_ivory)
	badge_rows.add_child(badge_grade)
	var title_rows := VBoxContainer.new()
	title_rows.add_theme_constant_override("separation", -1)
	title_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_rows)
	var kicker := Label.new()
	kicker.text = "WICKED TEMPLE  /  EXPEDITION COMPLETE"
	kicker.add_theme_font_override("font", preload("res://ui_font_bold.ttf"))
	kicker.add_theme_font_size_override("font_size", 10)
	kicker.add_theme_color_override("font_color", result_cyan if clean else result_dim)
	title_rows.add_child(kicker)
	var headline := Label.new()
	headline.name = "VictoryConclusionTitle"
	headline.text = "SANCTUM PURIFIED" if clean else ("GRIMWICK HOLDS" if _purified == 0 else "PURGE INCOMPLETE")
	headline.add_theme_font_override("font", preload("res://font_titan.ttf"))
	headline.add_theme_font_size_override("font_size", 31)
	headline.add_theme_color_override("font_color", result_ivory)
	headline.add_theme_color_override("font_outline_color", result_ink)
	headline.add_theme_constant_override("outline_size", 2)
	title_rows.add_child(headline)
	var subtitle := Label.new()
	subtitle.text = "The horde is broken. Your secured treasure awaits." if clean else \
		"Study the route, rebuild your rhythm, and return."
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", result_dim)
	title_rows.add_child(subtitle)
	if not _stage_stats.is_empty():
		var summary := GridContainer.new()
		summary.name = "VictoryStatGrid"
		summary.columns = 3
		summary.add_theme_constant_override("h_separation", 8)
		summary.add_theme_constant_override("v_separation", 5)
		_body.add_child(summary)
		_result_stat(summary, "SCORE", "%06d" % int(_stage_stats.get("score", 0)), result_ivory)
		_result_stat(summary, "CORRUPTED DEFEATED", str(int(_stage_stats.get("kills", 0))), result_cyan)
		_result_stat(summary, "BEST COMBO", "x%d" % int(_stage_stats.get("max_combo", _stage_stats.get("combo", 0))), result_amber)
	var progress := HBoxContainer.new()
	progress.name = "VictoryWaveJourney"
	progress.alignment = BoxContainer.ALIGNMENT_CENTER
	progress.add_theme_constant_override("separation", 5)
	_body.add_child(progress)
	var wave_nodes: Array[Control] = []
	for i in range(ROUNDS):
		var cleared := i < _purified
		var wave := _result_wave_node(i + 1, cleared)
		progress.add_child(wave)
		wave_nodes.append(wave)
		if i < ROUNDS - 1:
			var connector := Label.new()
			connector.text = "-"
			connector.add_theme_font_override("font", preload("res://ui_font_bold.ttf"))
			connector.add_theme_font_size_override("font_size", 14)
			connector.add_theme_color_override("font_color", Color(result_cyan.r,
				result_cyan.g, result_cyan.b, 0.36) if cleared else Color("43555a"))
			progress.add_child(connector)
	var waves := Label.new()
	waves.name = "VictoryWavesRemaining"
	waves.text = "  %d / %d CLEARED  |  %d LEFT" % [_purified, ROUNDS,
		maxi(0, ROUNDS - _purified)]
	waves.add_theme_font_override("font", preload("res://ui_font_bold.ttf"))
	waves.add_theme_font_size_override("font_size", 10)
	waves.add_theme_color_override("font_color", result_dim)
	progress.add_child(waves)
	_draw_loot_result()
	if _busy:
		_head("Sealing the reward and tribute...", 11, result_dim)
	elif _paid_why == "sandbox":
		_head("SANDBOX PREVIEW  /  REWARDS AND INVENTORY ARE NOT SAVED", 10, result_dim)
	elif _paid_why == "off":
		# THE SHIPPED DEFAULT. CHIK_TEMPLE starts off, so this is the first thing anyone sees, and it
		# must not read as a fault — the ritual worked, the tribute simply is not open yet.
		_head("The tribute is not open yet. The purge stands; nothing was paid.", 11, result_dim)
	elif _paid_why == "cooling":
		_head("The sigils are still cooling from your last purge. Nothing was paid this run.", 11, result_dim)
	elif _paid_why == "spent":
		_head("Today's tribute is already spent. Nothing was paid; the ceiling resets at 00:00 UTC.", 11, result_dim)
	elif _paid_why == "auth":
		# NAMES THE FIX, because this one has one. The run happened; the ledger would not take our
		# word for who we are.
		_head("The temple did not recognise your seal. Reconnect your wallet before the next purge.", 11, BAD)
	elif _paid_why == "offline":
		# NAMED, not hidden. A silent zero after paying an offering is the thing players rage about.
		_head("The temple could not reach the ledger. No tribute was recorded.", 11, BAD)
	elif _paid_amt <= 0.0:
		_head("No sigil broken; no tribute.", 11, result_dim)
	else:
		UISkin.coin_row(_body, "+%d $CHIKI" % int(round(_paid_amt)), 18, result_amber, 18)
		if _paid_why == "capped":
			_head("The temple's daily tribute is spent; this run paid the remainder.", 10, result_dim)
	var r := HBoxContainer.new()
	r.name = "VictoryConclusionActions"
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.add_theme_constant_override("separation", 8)
	_body.add_child(r)
	var again := Button.new()
	again.text = "PLAY AGAIN"
	UISkin.plaque(again, EDGE)
	UISkin.touch_h(again, _ov_touch())
	_result_button(again, true)
	again.disabled = _busy
	again.pressed.connect(func():
		_phase = "intro"
		_build())
	r.add_child(again)
	var leave := Button.new()
	leave.text = "RETURN TO ISLAND"
	UISkin.ghost(leave)
	UISkin.touch_h(leave, _ov_touch())
	_result_button(leave, false)
	leave.disabled = _busy
	leave.pressed.connect(close)
	r.add_child(leave)
	call_deferred("_animate_result_victory", badge, wave_nodes)


func _draw_wheel_done() -> void:
	_body.add_theme_constant_override("separation", 6)
	var header := Label.new()
	header.name = "VictoryConclusionHeader"
	header.text = "TEMPLE CONQUERED"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_override("font", preload("res://font_titan.ttf"))
	header.add_theme_font_size_override("font_size", _fs(18.0) if _mobile_ui() else 26)
	header.add_theme_color_override("font_color", Color("fff0d7"))
	header.tooltip_text = "5 / 5 waves cleared | Grade %s | Score %06d | %d defeated | Best combo x%d" % [
		String(_stage_stats.get("grade", "C")), int(_stage_stats.get("score", 0)),
		int(_stage_stats.get("kills", 0)), int(_stage_stats.get("max_combo", 0))]
	_body.add_child(header)
	var victory_seam := ColorRect.new()
	victory_seam.name = "WickedVictorySeam"
	victory_seam.color = Color("a263d1")
	victory_seam.custom_minimum_size.y = _sp(2.0)
	victory_seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(victory_seam)
	_draw_loot_result()
	# Currency settlement and failures remain truthful, without repeating the sandbox disclaimer
	# already attached to the prize. The reveal never changes reward odds or grants inventory.
	if _paid_amt > 0.0:
		UISkin.coin_row(_body, "+%d $CHIKI" % int(round(_paid_amt)), 14, Color("efb84d"), 16)
	elif _paid_why in ["offline", "auth"]:
		_head("Currency tribute was not recorded. Your item receipt is shown above.", 10, DIM)
	var actions := HBoxContainer.new()
	actions.name = "VictoryConclusionActions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	_body.add_child(actions)
	for label in ["PLAY AGAIN", "RETURN TO ISLAND"]:
		var button := Button.new()
		button.text = label
		_result_button(button, false)
		if _mobile_ui():
			button.custom_minimum_size.y = ceilf(44.0 / _css_per_logical()) + 1.0
			button.add_theme_font_size_override("font_size", _fs(11.0))
		for state in ["normal", "pressed", "focus", "hover"]:
			var style := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
			style.set_border_width_all(0)
			style.bg_color = Color("172b34") if state == "hover" else Color(0, 0, 0, 0)
			button.add_theme_stylebox_override(state, style)
		if label == "PLAY AGAIN":
			button.pressed.connect(func():
				_phase = "intro"
				_build())
		else:
			button.pressed.connect(close)
		actions.add_child(button)


func _result_wave_node(number: int, cleared: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "WaveNode%d" % number
	panel.custom_minimum_size = Vector2(42.0, 28.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("17343c") if cleared else Color("142229")
	style.border_color = Color("57d6d1") if cleared else Color("3d5158")
	style.set_border_width_all(1)
	style.border_width_bottom = 2
	style.set_corner_radius_all(7)
	style.set_content_margin_all(3)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = "W%d" % number
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", preload("res://ui_font_bold.ttf"))
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color("f4eddb") if cleared else Color("72868a"))
	panel.add_child(label)
	return panel


func _animate_result_victory(badge: Control, waves: Array[Control]) -> void:
	if _reward_reduced_motion():
		return
	await get_tree().process_frame
	if not is_instance_valid(badge) or not badge.is_inside_tree():
		return
	badge.pivot_offset = badge.size * 0.5
	badge.scale = Vector2.ONE * 0.72
	badge.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var badge_tween := create_tween().set_parallel(true)
	badge_tween.tween_property(badge, "scale", Vector2.ONE, 0.34) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	badge_tween.tween_property(badge, "modulate", Color.WHITE, 0.20)
	for i in range(waves.size()):
		var wave := waves[i]
		if not is_instance_valid(wave):
			continue
		wave.modulate = Color(1.0, 1.0, 1.0, 0.22)
		var wave_tween := create_tween()
		wave_tween.tween_interval(0.05 * float(i))
		wave_tween.tween_property(wave, "modulate", Color.WHITE, 0.16)


func _result_stat(parent: Control, caption: String, value: String, tint: Color) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.y = 48.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color("132831")
	style.border_color = Color("35515a")
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.set_corner_radius_all(7)
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	style.content_margin_left = 8
	style.content_margin_right = 8
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	panel.add_child(rows)
	for pair in [[value, 20, tint], [caption, 9, Color("aebeba")]]:
		var label := Label.new()
		label.text = String(pair[0])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", preload("res://ui_font_bold.ttf"))
		label.add_theme_font_size_override("font_size", int(pair[1]))
		label.add_theme_color_override("font_color", Color(pair[2]))
		rows.add_child(label)


func _result_button(button: Button, primary: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("efb84d") if primary else Color("17303a")
	style.border_color = Color("ffe19a") if primary else Color("4c6b74")
	style.set_border_width_all(1)
	style.border_width_bottom = 3
	style.set_corner_radius_all(8)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = style.bg_color.lightened(0.12)
	for state in ["normal", "focus", "pressed"]:
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_font_override("font", preload("res://ui_font_bold.ttf"))
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color("172027") if primary else Color("f4eddb"))
	button.add_theme_color_override("font_hover_color", Color("271708") if primary else Color.WHITE)
	# Result actions must remain present below the full reward ceremony. The CSS-derived touch floor
	# can report its defensive 160px cap in headless/zero-window startup; bound only this conclusion
	# row while retaining a 46px desktop target and up to 76 logical px for phones.
	button.custom_minimum_size.y = minf(76.0, maxf(46.0, _ov_touch()))


func _reward_reduced_motion() -> bool:
	if OS.has_feature("web"):
		var preference = JavaScriptBridge.eval("window.matchMedia('(prefers-reduced-motion: reduce)').matches", true)
		return bool(preference) if typeof(preference) == TYPE_BOOL else false
	return OS.get_environment("CHIKI_REDUCED_MOTION") == "1"

# ==============================================================================================
# THE REWARD WHEEL — five prizes on a rail, turning past a window.
# ==============================================================================================
# ONE SubViewport, one World3D, five slots on a shared rail that slides horizontally. NOT five
# viewports: each one carries its own world, environment and camera, and five of those live on a
# phone during a victory screen is exactly the kind of cost this project keeps measuring and
# regretting. Sliding one rail also gives the horizontal-wheel motion for free.
#
# THE SPIN DOES NOT DECIDE ANYTHING. The server already rolled and already committed the reward
# before this screen exists — _loot_reward is a receipt, not a proposal. So the wheel is told where
# to stop and eases into it. Anything else would be a client deciding what a player owns, which is
# the one thing this codebase never lets the client do.
#
# The eggs are voxel, because Chikoria is a voxel game and a smooth primitive would read as
# borrowed. The fantasy fish rides the same rail as its authored 2D icon, by owner ruling.
class RewardWheel extends SubViewportContainer:
	signal landed(key: String)

	const SLOT_GAP := 2.35
	const ORDER := ["fantasy_fish", "normal_egg", "legendary_egg", "mount_egg", "meme_egg"]
	# base shell, then the band — pulled well off white so the four tiers read apart under light.
	# The band colours are TempleReward.REWARD_META's own hexes, so the wheel and the receipt line
	# below it name the same prize in the same colour.
	const EGG_TINT := {
		"normal_egg":    [Color("9fd6ab"), Color("4f9e63")],
		"legendary_egg": [Color("b98cf0"), Color("7a3fc4")],
		"mount_egg":     [Color("f0a94f"), Color("c96f1e")],
		"meme_egg":      [Color("f07cc0"), Color("c2318b")],
	}

	var _rail: Node3D = null
	var _slots: Array = []
	var _target := 0
	var _t := 0.0
	var _dur := 0.0
	var _from := 0.0
	var _to := 0.0
	var _spinning := false
	var _done := false

	func _init() -> void:
		stretch = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func build(px: Vector2) -> void:
		custom_minimum_size = px
		var vp := SubViewport.new()
		vp.size = Vector2i(int(px.x), int(px.y))
		vp.own_world_3d = true
		vp.transparent_bg = true
		vp.msaa_3d = Viewport.MSAA_DISABLED if UISkin.lite_world() else Viewport.MSAA_4X
		add_child(vp)
		var we := WorldEnvironment.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0, 0, 0, 0)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		# 0.85, not 1.55. A pale shell under a 1.55 ambient plus two directionals renders WHITE, and
		# the four tiers became one egg in four sizes — measured off the first render, where the
		# green, violet, amber and pink shells were indistinguishable.
		env.ambient_light_color = Color(0.72, 0.68, 0.86)
		env.ambient_light_energy = 0.85
		we.environment = env
		vp.add_child(we)
		var key := DirectionalLight3D.new()
		key.rotation_degrees = Vector3(-38, -34, 0)
		key.light_energy = 0.95
		vp.add_child(key)
		var rim := DirectionalLight3D.new()
		rim.rotation_degrees = Vector3(-10, 148, 0)
		rim.light_energy = 0.55
		rim.light_color = Color(0.78, 0.72, 1.0)
		vp.add_child(rim)
		_rail = Node3D.new()
		vp.add_child(_rail)
		for i in range(ORDER.size()):
			var slot := Node3D.new()
			slot.position = Vector3(float(i) * SLOT_GAP, 0.0, 0.0)
			_rail.add_child(slot)
			var spin := Node3D.new()          # the turntable itself
			slot.add_child(spin)
			var key_id := String(ORDER[i])
			if key_id == "fantasy_fish":
				var s3 := Sprite3D.new()
				var ico := "res://fish_ico_crystal_koi.png"
				if ResourceLoader.exists(ico):
					s3.texture = load(ico)
				s3.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				s3.shaded = false
				s3.pixel_size = 0.0042
				s3.position = Vector3(0, 0.42, 0)
				spin.add_child(s3)
			else:
				spin.add_child(_voxel_egg(EGG_TINT[key_id][0], EGG_TINT[key_id][1]))
			_slots.append({"key": key_id, "spin": spin})
		var cam := Camera3D.new()
		cam.fov = 34.0
		cam.position = Vector3(0.0, 0.62, 4.15)
		cam.current = true
		vp.add_child(cam)
		_rail.position.x = 0.0
		_layout(0.0)
		set_process(true)


	# one placement rule, used at rest and mid-spin, so the wheel never jumps when the spin starts
	func _layout(scroll: float) -> void:
		var total: float = SLOT_GAP * float(_slots.size())
		for i in range(_slots.size()):
			var entry: Dictionary = _slots[i]
			var sp := entry["spin"] as Node3D
			var slot := sp.get_parent() as Node3D
			var dx: float = fposmod(float(i) * SLOT_GAP + scroll + total * 0.5, total) - total * 0.5
			slot.position.x = dx
			var near: float = clampf(1.0 - absf(dx) / SLOT_GAP, 0.0, 1.0)
			sp.scale = Vector3.ONE * (0.70 + 0.50 * near)
			sp.position.y = 0.10 * near

	# A VOXEL EGG, built rather than shipped: an ellipsoid of cubes, banded so it turns visibly.
	# ~1.1k instances in ONE MultiMesh — one draw call, and it belongs to the same world the island
	# is made of instead of looking like a primitive borrowed from a different game.
	func _voxel_egg(pale: Color, deep: Color) -> MultiMeshInstance3D:
		var step := 0.085
		var rx := 0.46
		var ry := 0.62
		var pts: Array = []
		var cols: Array = []
		var y := -ry
		while y <= ry:
			# an egg is not a sphere: the top half tapers harder than the bottom
			var ty: float = y / ry
			var squeeze: float = 1.0 - 0.28 * maxf(0.0, ty) * maxf(0.0, ty)
			var r: float = rx * sqrt(maxf(0.0, 1.0 - ty * ty)) * squeeze
			var x := -r
			while x <= r:
				var z := -r
				while z <= r:
					if x * x + z * z <= r * r:
						# hollow: keep only the shell, so 1.1k cubes instead of 9k
						var inner: float = r - step * 1.4
						if x * x + z * z >= inner * inner or absf(y) > ry - step * 1.4:
							pts.append(Vector3(x, y, z))
							var band: bool = fposmod(y + ry, 0.26) < 0.11
							cols.append(deep if band else pale)
					z += step
				x += step
			y += step
		var box := BoxMesh.new()
		box.size = Vector3(step, step, step) * 1.02
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.42
		mat.metallic = 0.05
		box.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = box
		mm.instance_count = pts.size()
		for i in range(pts.size()):
			mm.set_instance_transform(i, Transform3D(Basis(), pts[i]))
			mm.set_instance_color(i, cols[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = Vector3(0, 0.30, 0)
		return mmi

	func index_of(key: String) -> int:
		for i in range(ORDER.size()):
			if String(ORDER[i]) == key:
				return i
		return 0

	# `key` is the reward the SERVER already granted. The wheel travels several whole turns past it
	# and eases to rest on it, which is theatre over a settled fact.
	func spin_to(key: String) -> void:
		if _spinning or _rail == null:
			return
		_target = index_of(key)
		_from = _rail.position.x
		var loops := 2
		_to = -(float(_target) + float(loops) * float(ORDER.size())) * SLOT_GAP
		_dur = 3.1
		_t = 0.0
		_spinning = true
		_done = false

	func settled() -> bool:
		return _done

	func _process(delta: float) -> void:
		if _rail == null:
			return
		for entry in _slots:
			var sp := (entry as Dictionary)["spin"] as Node3D
			if sp != null and is_instance_valid(sp):
				sp.rotation.y += delta * 1.15          # every prize turns, always
		if not _spinning:
			return
		_t = minf(_dur, _t + delta)
		var p: float = _t / _dur
		# ease-out quintic: fast enough to blur, slow enough at the end to read the landing
		var e: float = 1.0 - pow(1.0 - p, 5.0)
		var span: float = _to - _from
		var raw: float = _from + span * e
		# A CAROUSEL, NOT A STRIP. The rail must not actually travel: at 2 loops it ends 28 units
		# from the camera and every prize is off-screen — measured, the spin and landing frames came
		# back empty while the arithmetic said it had landed on the right slot. So the SCROLL is
		# what travels, and each slot is placed at its scrolled offset WRAPPED into one wheel-width
		# about the window. Slot 4 leaving the right edge reappears at the left, which is what makes
		# it read as endless instead of as a long ribbon being dragged past.
		var total: float = SLOT_GAP * float(_slots.size())
		_rail.position.x = 0.0
		for i in range(_slots.size()):
			var entry: Dictionary = _slots[i]
			var sp2 := entry["spin"] as Node3D
			var slot := sp2.get_parent() as Node3D
			var dx: float = fposmod(float(i) * SLOT_GAP + raw + total * 0.5, total) - total * 0.5
			slot.position.x = dx
			# the prize under the window swells and the rest shrink away, so the eye is told where
			# the answer will be before the wheel gets there
			var near: float = clampf(1.0 - absf(dx) / SLOT_GAP, 0.0, 1.0)
			sp2.scale = Vector3.ONE * (0.70 + 0.50 * near)
			sp2.position.y = 0.10 * near
		if _t >= _dur and not _done:
			_done = true
			_spinning = false
			landed.emit(String(ORDER[_target]))


func _draw_loot_result() -> void:
	# The ceremony owns its visual stage. Wrapping it in the former purple reward box created two
	# competing frames and wasted the vertical space the real circular wheel now needs.
	var reward_box := VBoxContainer.new()
	reward_box.name = "VictoryRewardPresentation"
	reward_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(reward_box)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reward_box.add_child(rows)
	if _busy:
		_row(rows, "Victory reward", "Server roll pending...", DIM)
		return
	if _loot_reward.is_empty():
		_row(rows, "Victory reward", _loot_no_grant_copy(_loot_why), DIM)
		return
	if bool(_loot_reward.get("no_grant", false)):
		_row(rows, "Victory reward", _loot_no_grant_copy(
			String(_loot_reward.get("reason", _loot_why))), DIM)
		return
	# ── THE GUARANTEED 2D RECEIPT REVEAL ────────────────────────────────────────────────────────
	# The old generated 3D wheel showed a generic Crystal Koi even when another fish had landed.
	# This ceremony renders the exact authored transparent fish/egg PNG named by the settled server
	# receipt, fully letterboxed with safe padding. It never rolls and never substitutes another item.
	var wheel_key := String(_loot_reward.get("reward_key", ""))
	if wheel_key != "" and TempleReward.REWARD_META.has(wheel_key):
		var ceremony := _resize_ceremony if _resize_ceremony != null else TempleRewardCeremonyScene.new()
		# Attach first so the shared CSS/safe-area adapter samples the actual owning viewport.
		rows.add_child(ceremony)
		var available := get_viewport().get_visible_rect().size
		if _mobile_ui():
			available = Vector2(_panel.custom_minimum_size.x - float(_sp(16.0)),
				_panel.custom_minimum_size.y - float(_sp(88.0)))
		if ceremony == _resize_ceremony:
			_resize_ceremony = null
			ceremony.relayout(available)
			_wheel = ceremony
			return
		if ceremony.begin(_loot_reward, _reward_reduced_motion(), available):
			_wheel = ceremony
			ceremony.revealed.connect(func(_key: String): _wheel_spun = true)
			# someone re-opening the screen after revealing gets the same answer immediately
			if _wheel_spun:
				ceremony.reveal()
			return
		rows.remove_child(ceremony)
		ceremony.queue_free()
	_draw_reward_lines(rows)


func _draw_reward_lines(rows: Control) -> void:
	var banner := String(_loot_reward.get("banner", ""))
	if banner != "":
		_row(rows, banner, "preview only", BAD)
	var label := String(_loot_reward.get("label", _loot_reward.get("item_label",
		_loot_reward.get("category_label", "Temple reward"))))
	var rarity := String(_loot_reward.get("rarity", "Reward"))
	var top_category := String(_loot_reward.get("top_level_category", "Prize"))
	var top_chance := float(_loot_reward.get("top_level_chance_percent", 0.0))
	var within_chance := float(_loot_reward.get("chance_within_category_percent", 0.0))
	var overall_chance := float(_loot_reward.get("overall_chance_percent",
		_loot_reward.get("chance_percent", _loot_reward.get("chance", 0.0))))
	_row(rows, "Reward claimed", "%s  x1" % label, GOLD)
	_row(rows, "Rarity", rarity, INK)
	if top_chance > 0.0:
		_row(rows, top_category + " category", "%.0f%%" % top_chance, INK)
	if within_chance > 0.0 and overall_chance > 0.0:
		_row(rows, "Exact reward odds", "%.2f%% of category / %.2f%% overall" % [within_chance, overall_chance], DIM)
	if bool(_loot_reward.get("sandbox_preview", false)):
		_row(rows, "Inventory", "unchanged / this sandbox result is not saved", BAD)
	elif bool(_loot_reward.get("landed", false)):
		_row(rows, "Stored in", String(_loot_reward.get("where", "inventory")), GOLD)
	else:
		_row(rows, "Arrival", "recorded by server; waiting for a free inventory slot", DIM)

func _loot_no_grant_copy(reason: String) -> String:
	match reason:
		"defeat", "victory_required":
			return "clear all five waves to earn a reward roll"
		"identity_proof_required":
			return "reconnect your wallet to prove ownership; no item was issued"
		"capped":
			return "today's Temple reward allowance is spent"
		"reward_store_unavailable":
			return "the reward ledger is starting up; no item was issued this run"
		"issuance_failed":
			return "the reward could not be issued; no item was granted"
		"valid_run_id_required":
			return "the run receipt was invalid; no item was issued"
		"off":
			return "reward drops are not open on this server"
		_:
			return "no item was granted this run"

# ============================== the 2D world ==================================================
# Everything below exists only in world mode. Temple2D owns the hall, movement and collision;
# Rig2D owns every miniature; this file owns the RITUAL — what a sigil is, what a send costs,
# what the server pays. The split means the world can be rebuilt without touching the economy.

func _enter_world() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.visible = false
	if _scrim != null and is_instance_valid(_scrim):
		_scrim.visible = false
	_svc = SubViewportContainer.new()
	_svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_svc.stretch = true
	add_child(_svc)
	_sv = SubViewport.new()
	var wpath := _world_script()
	_platformer_world = _continuous_world_path(wpath)
	if _platformer_world:
		_phase = "stage"
	# THE 3D HALL NEEDS A 3D WORLD IN ITS VIEWPORT. This used to be an unconditional disable_3d,
	# which was correct while the hall was Node2D and is silently fatal now: a SubViewport with 3D
	# disabled renders a Node3D scene as an empty black rectangle, with no error anywhere.
	_sv.disable_3d = not _world_path_is_3d(wpath)
	_sv.own_world_3d = true
	_svc.add_child(_sv)
	var wscript = load(wpath) if wpath != "" else null
	if wscript == null:
		# the availability check passed but the load failed — degrade to the modal ritual rather
		# than presenting a black screen. The offering is already spent; the modal path honours it.
		_teardown_world()
		_mode = "modal"
		return
	_world = wscript.new()
	_sv.add_child(_world)
	# Connect the continuous stage before enter(): the platformer may begin immediately and owns
	# every encounter until it emits its one final result. Legacy halls keep their old sigil/door
	# adapter below.
	if _platformer_world:
		if _world.has_signal("stage_completed"):
			_world.connect("stage_completed", _on_platformer_completed)
		if _world.has_signal("exit_requested"):
			_world.connect("exit_requested", _on_platformer_exit)
		if _world.has_signal("creature_changed"):
			_world.connect("creature_changed", func(uid: String): _horde_pick_uid = uid)
	else:
		if _world.has_signal("sigil_reached"):
			_world.connect("sigil_reached", _on_world_sigil)
		if _world.has_signal("door_reached"):
			_world.connect("door_reached", _on_world_door)
	# THE PARTY WALKS IN WITH THE TRAINER. The side-scroller also receives the same compact party
	# dictionaries, so creature/card actions stay tied to the player's real roster.
	var world_party := _party_for_world()
	if wpath == "res://TempleHorde3D.gd":
		world_party = _horde_sandbox_roster() if _asset_test_mode() else _solo_for_world()
	if _world.has_method("set_party"):
		_world.call("set_party", world_party)
	_world.call("enter", String(_profile.d.get("avatar", "classic")))
	if _platformer_world:
		# enter() already makes the stage playable; start_stage() is the explicit reset point after
		# the party is installed and is intentionally optional for thin/test implementations.
		if _world.has_method("start_stage"):
			_world.call("start_stage", world_party)
		if _world.has_method("set_input_enabled"):
			_world.call("set_input_enabled", true)
	# The platformer renders its own stage HUD. Temple contributes only the economy-safe abandon
	# door; the legacy halls still need the seek banner and the duel boxes they were built around.
	_ov = Control.new()
	_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ov)
	if _platformer_world and _asset_test_mode():
		_build_sandbox_victory_control()
	if not _platformer_world:
		var bp := PanelContainer.new()
		bp.anchor_left = 0.5; bp.anchor_right = 0.5
		bp.grow_horizontal = Control.GROW_DIRECTION_BOTH
		bp.offset_top = 12.0
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = Color(BG.r, BG.g, BG.b, 0.85)
		bsb.border_color = EDGE
		bsb.set_border_width_all(2)
		bsb.set_corner_radius_all(10)
		bsb.content_margin_left = 14; bsb.content_margin_right = 14
		bsb.content_margin_top = 6; bsb.content_margin_bottom = 6
		bp.add_theme_stylebox_override("panel", bsb)
		bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ov.add_child(bp)
		_ov_banner_lbl = Label.new()
		_ov_banner_lbl.add_theme_font_size_override("font_size", 15)
		_ov_banner_lbl.add_theme_color_override("font_color", INK)
		bp.add_child(_ov_banner_lbl)
	# Horde owns a HUD-aligned EXIT control; placing this generic legacy button on top of its score
	# panel hid the exact information the player uses to chase a grade. Older halls still need it.
	if wpath != "res://TempleHorde3D.gd":
		var ab := Button.new()
		ab.text = "  Abandon  "
		ab.tooltip_text = "Leave the ritual. The offering is not returned."
		UISkin.ghost(ab)
		UISkin.touch_h(ab, _ov_touch())
		ab.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		ab.offset_left = -130.0; ab.offset_top = 10.0; ab.offset_right = -10.0
		ab.pressed.connect(close)
		_ov.add_child(ab)


func _build_sandbox_victory_control() -> void:
	# This button lives outside TempleHorde3D so it can drive the real Temple completion adapter,
	# results card, and reward ceremony. Production never constructs it: asset_sandbox is armed only
	# by the sealed `?sandbox=all` profile bootstrap.
	if not _sandbox_victory_available() or _ov == null or not is_instance_valid(_ov):
		return
	var button := Button.new()
	button.name = "SandboxInstantVictory"
	button.set_meta("preserve_tab_art", true)
	button.text = "INSTANT VICTORY\nPREVIEW REWARD"
	button.tooltip_text = "Sandbox only — preview a 5/5 result and reward ceremony; saves nothing"
	button.focus_mode = Control.FOCUS_NONE
	button.z_index = 80
	# The combat HUD owns the upper-left progress and notice stack. Keep this sandbox-only tool
	# below the opposite utility rail so it cannot cover route or combat messages.
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var phone := UISkin.lite_world()
	button.offset_left = -(270.0 if phone else 232.0) - 18.0
	button.offset_right = -18.0
	button.offset_top = 108.0 if phone else 100.0
	button.offset_bottom = button.offset_top + maxf(_ov_touch(), 58.0)
	UISkin.plaque(button, Color("9870c8"))
	_result_button(button, false)
	button.add_theme_font_size_override("font_size", _fs(13.0))
	button.pressed.connect(_sandbox_preview_victory)
	_ov.add_child(button)
	_sandbox_victory_button = button
	if _world.has_signal("mobile_options_visibility_changed") \
			and not _world.is_connected("mobile_options_visibility_changed", _layout_sandbox_victory_control):
		_world.connect("mobile_options_visibility_changed", _layout_sandbox_victory_control)
	if not get_viewport().size_changed.is_connected(_queue_mobile_surface_resize):
		get_viewport().size_changed.connect(_queue_mobile_surface_resize)
	_layout_sandbox_victory_control()


func _layout_sandbox_victory_control(_expanded: bool = false) -> void:
	var button := _sandbox_victory_button
	if button == null or not is_instance_valid(button):
		return
	var display := MobileViewport.sample(get_viewport())
	var mobile := bool(display["touch"])
	var expanded := _world != null and is_instance_valid(_world) \
		and _world.has_method("mobile_options_open") and bool(_world.call("mobile_options_open"))
	var menu_row := Rect2()
	if mobile and _world != null and is_instance_valid(_world) and _world.has_method("touch_rects"):
		var rects := _world.call("touch_rects") as Dictionary
		if rects.has("settings"): menu_row = rects["settings"] as Rect2
	# Horde also emits after its regular HUD layout. Only change actual controls/fonts when the
	# display, settled utility row or menu state changed; do not re-style this overlay every tick.
	var signature := [mobile, expanded, display["css_size"], display["safe_insets"],
		display["css_per_logical"], get_viewport().get_visible_rect().size, menu_row,
		_phase, button.disabled, UISkin.lite_world()]
	if button.get_meta("sandbox_layout_signature", []) == signature:
		return
	button.set_meta("sandbox_layout_signature", signature)
	if not mobile:
		# Preserve the original desktop sandbox shortcut and its established right-hand placement.
		button.visible = true
		button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		var lite := UISkin.lite_world()
		button.custom_minimum_size = Vector2.ZERO
		button.offset_left = -(270.0 if lite else 232.0) - 18.0
		button.offset_right = -18.0
		button.offset_top = 108.0 if lite else 100.0
		button.offset_bottom = button.offset_top + maxf(_ov_touch(), 58.0)
		if not button.disabled: button.text = "INSTANT VICTORY\nPREVIEW REWARD"
		button.add_theme_font_size_override("font_size", _fs(13.0))
		return
	button.visible = expanded and _phase == "stage"
	var css := display["css_size"] as Vector2
	var edges := display["safe_insets"] as Vector4
	var scale := _css_per_logical()
	var top := edges.y + 58.0
	if menu_row.has_area(): top = menu_row.end.y * scale + 6.0
	var height := ceilf(44.0 / scale) + 1.0
	var width := minf(164.0, css.x - edges.x - edges.z - 20.0) / scale
	button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	button.grow_horizontal = Control.GROW_DIRECTION_END
	button.custom_minimum_size = Vector2(0.0, height)
	button.position = Vector2((css.x - edges.z - 10.0) / scale - width, top / scale)
	button.size = Vector2(width, height)
	if not button.disabled: button.text = "PREVIEW REWARD"
	button.add_theme_font_size_override("font_size", maxi(1, roundi(11.0 / scale)))


func _sandbox_victory_available() -> bool:
	# Two independent profile flags plus the exact script path keep this dev seam out of production
	# and out of any future/legacy platformer that happens to share the continuous-world interface.
	if not _asset_test_mode() or _profile == null or not bool(_profile.get("demo")) \
			or not _platformer_world or _world == null or not is_instance_valid(_world):
		return false
	var script := _world.get_script() as Script
	return script != null and script.resource_path == "res://TempleHorde3D.gd" \
		and _world.has_method("debug_start_wave") and _world.has_method("debug_complete_wave") \
		and _world.has_method("debug_advance") and _world.has_method("_finish_stage")


func _sandbox_preview_victory() -> void:
	# Defence in depth: even a direct scripted call is inert outside the all-assets stage. The real
	# completion adapter below is deliberately reused so this previews exactly what a 5/5 win shows,
	# while _report()'s first sandbox branch guarantees no backend, grant, or $CHIKI path is reached.
	if not _sandbox_victory_available() or _phase != "stage" or _busy:
		return
	if _sandbox_victory_button != null and is_instance_valid(_sandbox_victory_button):
		_sandbox_victory_button.disabled = true
		_sandbox_victory_button.text = "BUILDING 5/5 RESULTS…"
	# Exercise the real Horde debug seam: each sanctum enters, clears its actual active Corruptimons,
	# records through _check_wave_clear(), and only Horde itself composes/emits the completion stats.
	# Temple therefore cannot accidentally invent a result shape that production never produces.
	for i in ROUNDS:
		_world.call("debug_start_wave", i)
		_world.call("debug_advance", 1.46)
		_world.call("debug_complete_wave")
	_world.call("_finish_stage", true)

func _teardown_world() -> void:
	for n in [_svc, _ov]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_svc = null; _sv = null; _world = null; _ov = null
	_sandbox_victory_button = null
	_platformer_world = false
	_ov_banner_lbl = null; _ov_box = null; _helper = null; _helper_party = ""
	# THE ATTACK BOLT'S TWEEN OUTLIVES ITS TARGET. create_tween() binds to THIS node, not to the
	# bolt, so freeing the viewport under it leaves the tween running and its callback holding a
	# freed capture — "Lambda capture at index 0 was freed", logged on every abandon taken during
	# the strike (measured: once per close, five times over five cycles in dev_temple_attack A11).
	if _bolt_tw != null and _bolt_tw.is_valid():
		_bolt_tw.kill()
	_bolt_tw = null
	if _walk_tw != null and _walk_tw.is_valid():
		_walk_tw.kill()
	_walk_tw = null
	# THE EXACT INVERSE OF _enter_world, AND THE REASON THIS FUNCTION IS THE PLACE FOR IT.
	#
	# _enter_world hides the modal card so the hall has the screen. NOTHING PUT IT BACK except
	# _finish(), so any run that ended some OTHER way — the Abandon button, ESC, the door, a
	# Temple2D load failure — left _panel.visible = false forever. open() then rebuilt the intro
	# into a hidden panel: measured in dev_temple_attack A2/A3/A4 as
	#     re-entered: _panel.visible=false _scrim.visible=false, Begin visible_in_tree=false
	# on EVERY re-entry after an abandon. The temple was a blank screen with an invisible Begin
	# button for the rest of the session — the "gets stuck" class this file was already fixed for
	# once, reached through the one exit the fix did not cover. Restoring here covers all four.
	if _panel != null and is_instance_valid(_panel):
		_panel.visible = true
	if _scrim != null and is_instance_valid(_scrim):
		_scrim.visible = true

func _ov_say(t: String) -> void:
	if _ov_banner_lbl != null and is_instance_valid(_ov_banner_lbl):
		_ov_banner_lbl.text = t

func _ov_clear() -> void:
	_asset_clear_picker_refs()
	if _ov_box != null and is_instance_valid(_ov_box):
		_ov_box.queue_free()
	_ov_box = null

# one bottom battle box, Pokemon-shaped: dark plate, element edge, content handed back to the caller
func _ov_open_box(edge: Color) -> VBoxContainer:
	_ov_clear()
	_ov_box = PanelContainer.new()
	_ov_box.anchor_left = 0.5; _ov_box.anchor_right = 0.5
	_ov_box.anchor_top = 1.0; _ov_box.anchor_bottom = 1.0
	_ov_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ov_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ov_box.offset_bottom = -14.0
	# ONE PLATE, ONE SIZE. Measured across a run, the bottom box went 181x220 (pick) -> 544x112
	# (channel) -> 231x168 (result): three differently shaped panels appearing in the same corner,
	# which reads as three UI elements rather than one battle box the beats play inside. A floor
	# under both axes holds the frame still; content larger than the floor still grows it.
	_ov_box.custom_minimum_size = Vector2(600, 214)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(BG.r, BG.g, BG.b, 0.96)
	sb.border_color = edge
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.5); sb.shadow_size = 12
	_ov_box.add_theme_stylebox_override("panel", sb)
	_ov_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_ov.add_child(_ov_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	# centred, so a short beat (the channel bar) sits in the middle of the plate instead of clinging
	# to its top edge with dead space underneath
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_ov_box.add_child(v)
	return v

func _on_world_sigil(el: String) -> void:
	if _phase != "seek" or String(el) != _sigil:
		return
	# Anchor the whole encounter to the authored centre of the rune, not to the particular edge of
	# its trigger the trainer happened to cross.  The expanded side sanctums are symmetrical, and a
	# stable centre keeps the foe, helper, bolts and impacts centred in every room.  Older/fallback
	# worlds without the layout adapter still degrade to the trainer's proven reachable position.
	_alcove_pos = Vector2(_world.call("plate_pos", el)) if _world.has_method("plate_pos") \
		else Vector2(_world.call("player_pos"))
	_world.call("set_input_enabled", false)
	_phase = "pick"
	_ov_pick()

func _on_world_door() -> void:
	# mid-ritual the door is the abandon door — the banner and every box say what leaving costs
	if _phase != "done":
		close()

# The side-scroller is deliberately a single authority hand-off: it reports one summary and this
# adapter turns that into the five rows the existing result/economy contract has always consumed.
# A duplicated completion signal cannot report or pay twice because only the live `stage` phase is
# accepted; _finish() changes it synchronously before the server request begins.
func _on_platformer_completed(stats: Dictionary) -> void:
	if _phase != "stage" or _busy:
		return
	_stage_stats = stats.duplicate(true)
	if _world != null and is_instance_valid(_world) and _world.has_method("set_input_enabled"):
		_world.call("set_input_enabled", false)

	var raw_rows: Array = []
	var results = stats.get("results", [])
	if results is Array:
		raw_rows = (results as Array).duplicate(true)
	var seals = stats.get("seals", 0)
	if raw_rows.is_empty() and seals is Array:
		raw_rows = (seals as Array).duplicate(true)

	var has_explicit_total := stats.has("purified") or stats.has("sigils_broken") \
		or (stats.has("seals") and (seals is int or seals is float))
	var reported_total := 0
	if stats.has("purified"):
		reported_total = int(stats.get("purified", 0))
	elif stats.has("sigils_broken"):
		reported_total = int(stats.get("sigils_broken", 0))
	elif seals is int or seals is float:
		reported_total = int(seals)
	else:
		for raw in raw_rows:
			if raw is Dictionary and bool((raw as Dictionary).get("broke", false)):
				reported_total += 1
	_purified = clampi(reported_total, 0, ROUNDS)
	_round = ROUNDS
	_log.clear()
	var roster := _solo_for_world()
	if roster.is_empty():
		roster = _fit_units()
	for i in ROUNDS:
		var src: Dictionary = {}
		if i < raw_rows.size() and raw_rows[i] is Dictionary:
			src = raw_rows[i] as Dictionary
		var unit: Dictionary = {}
		if not roster.is_empty():
			unit = roster[i % roster.size()] as Dictionary
		var fallback_name := "Chiki Monsters"
		if not unit.is_empty():
			fallback_name = _profile.unit_name(unit)
		var sigil := String(src.get("sigil", src.get("seal", ELEMENTS[i])))
		var creature_name := String(src.get("creature_name", src.get("creature", src.get("name", fallback_name))))
		var broke := bool(src.get("broke", src.get("cleared", i < _purified if has_explicit_total else false)))
		_log.append({
			"sigil": sigil,
			"uid": String(src.get("uid", unit.get("uid", ""))),
			"name": creature_name,
			"el": String(src.get("el", src.get("element", unit.get("element", sigil)))),
			"lvl": int(src.get("lvl", unit.get("lvl", 1))),
			"timing": float(src.get("timing", 1.0)),
			"power": float(src.get("power", 1.0 if broke else 0.0)),
			"broke": broke,
		})

	# Keep the five visible rows arithmetically consistent with the server-bound total even if a
	# test world emits only a total, or a future world sends partially populated result entries.
	var row_total := 0
	for row in _log:
		if bool((row as Dictionary).get("broke", false)):
			row_total += 1
	if row_total < _purified:
		for i in _log.size():
			if row_total >= _purified:
				break
			if not bool((_log[i] as Dictionary).get("broke", false)):
				(_log[i] as Dictionary)["broke"] = true
				row_total += 1
	elif row_total > _purified:
		for i in range(_log.size() - 1, -1, -1):
			if row_total <= _purified:
				break
			if bool((_log[i] as Dictionary).get("broke", false)):
				(_log[i] as Dictionary)["broke"] = false
				row_total -= 1
	_finish()

func _on_platformer_exit() -> void:
	if _phase == "stage":
		close()

func _ov_pick() -> void:
	var col := _el_col(_sigil)
	var v := _ov_open_box(col)
	_ov_say("The %s sigil waits. Send a chikimon." % _sigil.to_upper())
	var able := _asset_test_units() if _asset_test_mode() else _fit_units()
	if able.is_empty():
		var dl := Label.new()
		dl.text = "Every chikimon in your party has fallen or is spent. The sigil cannot be answered."
		dl.add_theme_font_size_override("font_size", 13)
		dl.add_theme_color_override("font_color", BAD)
		v.add_child(dl)
	if _asset_test_mode():
		_asset_build_picker(v, able, true)
	else:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		var R = load("res://Rig2D.gd")
		for u in able:
			row.add_child(_ov_unit_card(u, R))
	var ar := HBoxContainer.new()
	ar.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(ar)
	var ab := Button.new()
	ab.text = "  Abandon the purge  "
	UISkin.ghost(ab)
	UISkin.touch_h(ab, _ov_touch())
	ab.pressed.connect(close)
	ar.add_child(ab)


# ============================== all-assets creature switcher =================================
# This surface exists only in the sealed `?sandbox=all` session.  Normal trainers still choose
# among their three fit party members above; the tester gets every owned creature without turning
# the production temple into a roster-management loophole.
func _asset_test_mode() -> bool:
	return _profile != null and bool(_profile.get("asset_sandbox"))


# Party + bench is the profile's canonical owned roster.  Sorting by display/species keeps the
# list stable when lead_unit() swaps a tested bench creature with the current party lead.
func _asset_test_units() -> Array:
	var out: Array = []
	if not _asset_test_mode():
		return out
	var units: Dictionary = _profile.d.get("units", {})
	var seen := {}
	for source in [_profile.d.get("party", []), _profile.d.get("bench", [])]:
		for uid_v in source:
			var uid := String(uid_v)
			if uid == "" or seen.has(uid) or not units.has(uid):
				continue
			var u = units[uid]
			if not (u is Dictionary) or String((u as Dictionary).get("species", "")) == "":
				continue
			seen[uid] = true
			out.append(u)
	# A malformed test profile should still expose an owned unit that fell out of both arrays; the
	# commit path uses Profile.lead_unit(), so such a record remains non-sendable instead of being
	# silently inserted by this read-only list builder.
	for uid_v in units:
		var uid := String(uid_v)
		if uid == "" or seen.has(uid):
			continue
		var u = units[uid]
		if u is Dictionary and String((u as Dictionary).get("species", "")) != "":
			seen[uid] = true
			out.append(u)
	out.sort_custom(_asset_unit_less)
	return out


func _asset_unit_less(a: Dictionary, b: Dictionary) -> bool:
	var an := "%s|%s" % [_profile.unit_name(a), String(a.get("species", ""))]
	var bn := "%s|%s" % [_profile.unit_name(b), String(b.get("species", ""))]
	return an.to_lower() < bn.to_lower()


func _asset_index_for(uid: String) -> int:
	for i in range(_asset_pick_units.size()):
		var u = _asset_pick_units[i]
		if u is Dictionary and String((u as Dictionary).get("uid", "")) == uid:
			return i
	return -1


# A names-only OptionButton is deliberate: its 41 rows cost no decoded sprite textures.  Exactly
# one existing creature card lives below it, so Previous/Next can be tapped through the collection
# even on a small phone without creating an atlas wall.
func _asset_build_picker(parent: Control, units: Array, animated_preview: bool) -> void:
	_asset_pick_units = units
	_asset_preview_animated = animated_preview
	if units.is_empty():
		return
	var at := _asset_index_for(_asset_pick_uid)
	if at < 0 and _profile.has_method("active_unit"):
		var active: Dictionary = _profile.active_unit()
		at = _asset_index_for(String(active.get("uid", "")))
	if at < 0:
		at = 0
	_asset_pick_uid = String((units[at] as Dictionary).get("uid", ""))

	var title := Label.new()
	title.text = "ALL-ASSETS CREATURE SWITCHER  ·  %d CHIKIMONS" % units.size()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", GOLD)
	parent.add_child(title)

	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 8)
	parent.add_child(nav)
	var prev := Button.new()
	prev.name = "AllAssetsPrev"
	prev.text = "◀  PREV"
	prev.custom_minimum_size = Vector2(92, 0)
	UISkin.ghost(prev)
	UISkin.touch_h(prev, _ov_touch())
	prev.pressed.connect(_asset_step.bind(-1))
	nav.add_child(prev)

	_asset_picker = OptionButton.new()
	_asset_picker.name = "AllAssetsCreaturePicker"
	_asset_picker.custom_minimum_size = Vector2(300, 0)
	_asset_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_asset_picker.clip_text = true
	_asset_picker.add_theme_font_size_override("font_size", 13)
	UISkin.ghost(_asset_picker)
	UISkin.touch_h(_asset_picker, _ov_touch())
	for i in range(units.size()):
		var u := units[i] as Dictionary
		var sp := String(u.get("species", ""))
		_asset_picker.add_item("%02d/%02d  ·  %s  ·  %s" % [i + 1, units.size(), _profile.unit_name(u), Econ.el_of(sp)])
		_asset_picker.set_item_metadata(i, String(u.get("uid", "")))
	_asset_picker.select(at)
	_asset_picker.item_selected.connect(_asset_select_index)
	nav.add_child(_asset_picker)

	var next := Button.new()
	next.name = "AllAssetsNext"
	next.text = "NEXT  ▶"
	next.custom_minimum_size = Vector2(92, 0)
	UISkin.ghost(next)
	UISkin.touch_h(next, _ov_touch())
	next.pressed.connect(_asset_step.bind(1))
	nav.add_child(next)

	_asset_preview = CenterContainer.new()
	_asset_preview.name = "AllAssetsCreaturePreview"
	_asset_preview.custom_minimum_size = Vector2(0, 150)
	parent.add_child(_asset_preview)
	_asset_refresh_preview()
	var hint := Label.new()
	hint.text = "Tap the creature card to send it. Only this preview rig is loaded."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", DIM)
	parent.add_child(hint)


func _asset_select_index(index: int) -> void:
	if index < 0 or index >= _asset_pick_units.size() or _phase != "pick":
		return
	_asset_pick_uid = String((_asset_pick_units[index] as Dictionary).get("uid", ""))
	if _asset_picker != null and is_instance_valid(_asset_picker):
		_asset_picker.select(index)
	_asset_refresh_preview()


func _asset_step(step: int) -> void:
	if _asset_pick_units.is_empty() or _phase != "pick":
		return
	var at := _asset_index_for(_asset_pick_uid)
	at = 0 if at < 0 else posmod(at + step, _asset_pick_units.size())
	_asset_select_index(at)


func _asset_refresh_preview() -> void:
	if _asset_preview == null or not is_instance_valid(_asset_preview):
		return
	# Immediate free is safe here: navigation lives outside the card.  It also prevents a burst of
	# fast Prev/Next taps from retaining several atlases until the end of the render frame.
	for child in _asset_preview.get_children():
		child.free()
	var at := _asset_index_for(_asset_pick_uid)
	if at < 0:
		return
	var u := _asset_pick_units[at] as Dictionary
	var card: Control
	if _asset_preview_animated:
		card = _ov_unit_card(u, load("res://Rig2D.gd"))
	else:
		card = _unit_card(u)
	card.tooltip_text = "Send %s against the %s sigil" % [_profile.unit_name(u), _sigil]
	_asset_preview.add_child(card)


func _asset_clear_picker_refs() -> void:
	_asset_pick_units = []
	_asset_picker = null
	_asset_preview = null
	_asset_preview_animated = false


func _asset_restore_unit(uid: String) -> void:
	var u := _unit(uid)
	if u.is_empty():
		return
	u["fainted"] = false
	u["recover_at"] = 0.0
	u["rest_until"] = 0.0
	u["stam"] = 100.0
	u["hunger"] = 100.0


func _asset_send_failed() -> void:
	_pick_uid = ""
	_phase = "pick"
	if _mode == "world" and _ov != null and is_instance_valid(_ov):
		_ov_pick()
	else:
		_build()


# a roster card with the LIVING miniature on it — the puppet idles right on the button
func _ov_unit_card(u: Dictionary, R) -> Button:
	var sp := String(u["species"])
	var el := Econ.el_of(sp)
	var mult := Econ.el_mult(el, _sigil)
	var b := Button.new()
	b.custom_minimum_size = Vector2(120, 150)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.13, 0.09, 0.19, 0.95)
	bs.border_color = GOLD if mult > 1.0 else (BAD if mult < 1.0 else Color(0.45, 0.40, 0.55))
	bs.set_border_width_all(2)
	bs.set_corner_radius_all(12)
	bs.set_content_margin_all(6)
	b.add_theme_stylebox_override("normal", bs)
	b.add_theme_stylebox_override("hover", bs)
	b.add_theme_stylebox_override("pressed", bs)
	b.set_meta("purge_uid", String(u["uid"]))
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var art := Control.new()
	art.custom_minimum_size = Vector2(0, 84)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(art)
	if R != null:
		var pup = R.call("for_species", sp, 72.0)
		if pup is Node2D:
			(pup as Node2D).position = Vector2(54, 46)
			if pup.has_method("play"):
				pup.call("play", "idle")
			art.add_child(pup)
	var nm := Label.new()
	nm.text = _profile.unit_name(u)
	nm.add_theme_font_size_override("font_size", 12)
	nm.add_theme_color_override("font_color", INK)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nm)
	var tag := Label.new()
	tag.text = "%s L%d · %s" % [el, int(u["level"]), ("STRONG" if mult > 1.0 else ("RESIST" if mult < 1.0 else "even"))]
	tag.add_theme_font_size_override("font_size", 10)
	tag.add_theme_color_override("font_color", GOLD if mult > 1.0 else (BAD if mult < 1.0 else DIM))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)
	var uid := String(u["uid"])
	b.pressed.connect(func(): _chose(uid))
	return b

func _spawn_helper(uid: String) -> void:
	# a PUPPET from a previous round is ours to free; a FOLLOWER belongs to the hall and was already
	# recalled into formation, so touching it here would delete a party member mid-run
	if _helper_party == "" and _helper != null and is_instance_valid(_helper):
		_helper.queue_free()
	_helper = null
	_helper_party = ""
	var R = load("res://Rig2D.gd")
	if R == null or _world == null:
		return
	# THE SEND IS A PARTY MEMBER STEPPING OUT OF THE TRAIL. It used to be a second copy of the same
	# creature fading into existence beside the sigil while the original stood in formation — which
	# only stopped being visibly wrong because, until now, there was no formation to stand in.
	if _world.has_method("send_follower") and bool(_world.call("send_follower", uid, _alcove_pos)):
		_helper_party = uid
		_helper = _world.call("follower_rig", uid)
		return
	var sp := String(_unit(uid).get("species", ""))
	var pup = R.call("for_species", sp, 96.0)
	if not (pup is Node2D):
		return
	_helper = pup
	# Into the world's OWN y-sorted layer, not onto the Temple2D root: a child of the root draws over
	# the player whatever their relative depth, and the summoned creature stood in front of an avatar
	# that was upstage of it. Temple2D also grounds it — Rig2D's sprite is centred, so a rig dropped
	# at a floor position sinks to its waist (measured: 48.5 px on a 97 px sprite).
	if _world.has_method("attach_actor"):
		_world.call("attach_actor", pup, 22.0)   # attach_actor grounds it and gives it a blob shadow
	else:
		_world.add_child(pup)
	# The spot is the WORLD's call, not this file's: a fixed -150 px put the creature half inside the
	# west wall band at the Water and Beast alcoves, because those plates sit 134 px from the wall.
	var spot: Dictionary = {"from": _alcove_pos + Vector2(-150, 52), "to": _alcove_pos + Vector2(-96, 34), "face": Vector2(1, 0)}
	if _world.has_method("helper_spot"):
		spot = _world.call("helper_spot", _alcove_pos)
	# attach_actor already grounded it, and grounding is expressed AS the node's y — so the feet
	# offset is simply what is sitting in position.y now, and both waypoints carry it.
	var foot: float = (pup as Node2D).position.y
	(pup as Node2D).position = Vector2(spot["from"]) + Vector2(0.0, foot)
	var land: Vector2 = Vector2(spot["to"]) + Vector2(0.0, foot)
	if pup.has_method("face"):
		pup.call("face", Vector2(spot["face"]))
	if pup.has_method("play"):
		pup.call("play", "walk")
	# KEPT, so teardown can kill it. This tween is bound to THIS node and its callback captures the
	# puppet, which lives in the world — abandon during the 0.55 s walk and the puppet is freed
	# under a callback that still holds it: "Lambda capture at index 0 was freed", once per abandon.
	if _walk_tw != null and _walk_tw.is_valid():
		_walk_tw.kill()
	var tw := create_tween()
	_walk_tw = tw
	tw.tween_property(pup, "position", land, 0.55)
	tw.tween_callback(func(): if is_instance_valid(pup) and pup.has_method("play"): pup.call("play", "idle"))

# THE ROUND LETS GO OF THE CREATURE IT SENT. Which of the two things that means depends entirely
# on where the creature came from, and getting it backwards is silent in both directions: freeing a
# follower deletes a party member from the hall for the rest of the run, and recalling a puppet
# leaves it standing at the dead sigil until teardown.
func _release_helper() -> void:
	if _helper_party != "":
		if _world != null and is_instance_valid(_world) and _world.has_method("recall_follower"):
			_world.call("recall_follower", _helper_party)
	elif _helper != null and is_instance_valid(_helper):
		_helper.queue_free()
	_helper = null
	_helper_party = ""

func _ov_channel() -> void:
	var col := _el_col(_sigil)
	var v := _ov_open_box(EDGE)
	_ov_say("Channel the purge — stop the light inside the band.  [SPACE]")
	# THE MATCHUP LINE. With the box held at one size the channel beat was a lone bar in an empty
	# plate, and the one thing the player wants at that moment — who they just sent, and whether the
	# element is with them — was only ever shown on the card they had already dismissed.
	var u := _unit(_pick_uid)
	if not u.is_empty():
		var uel := Econ.el_of(String(u.get("species", "")))
		var um := Econ.el_mult(uel, _sigil)
		var hd := Label.new()
		hd.text = "%s  ·  %s  vs  %s   ×%.2f" % [_profile.unit_name(u), uel, _sigil.to_upper(), um]
		hd.add_theme_font_size_override("font_size", 14)
		hd.add_theme_color_override("font_color", GOLD if um > 1.0 else (BAD if um < 1.0 else DIM))
		hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(hd)
		var move := Label.new()
		move.text = "CARD  ·  %s  ·  %s" % [_purge_card_name(String(u.get("species", "")), _pick_slot), String(Econ.CARDS[_pick_slot].get("arch", "strike")).to_upper()]
		move.add_theme_font_size_override("font_size", 13)
		move.add_theme_color_override("font_color", EDGE)
		move.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(move)
	var track := PanelContainer.new()
	track.custom_minimum_size = Vector2(520, 42)
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.09, 0.06, 0.13, 0.95)
	ts.border_color = Color(0.35, 0.30, 0.45)
	ts.set_border_width_all(2)
	ts.set_corner_radius_all(10)
	track.add_theme_stylebox_override("panel", ts)
	v.add_child(track)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(0, 30)
	track.add_child(inner)
	_chan_zone = ColorRect.new()
	_chan_zone.color = Color(col.r, col.g, col.b, 0.42)
	inner.add_child(_chan_zone)
	_chan_marker = ColorRect.new()
	_chan_marker.color = Color(1, 1, 1, 0.95)
	inner.add_child(_chan_marker)
	_chan_band = randf_range(0.18, 0.82)
	_chan_t = 0.0
	_chan_dir = 1.0
	_chan_running = true
	var r := HBoxContainer.new()
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.add_theme_constant_override("separation", 10)
	v.add_child(r)
	var tap := Button.new()
	tap.text = "  CHANNEL  "
	tap.add_theme_font_size_override("font_size", 17)
	UISkin.plaque(tap, EDGE)
	UISkin.touch_h(tap, _ov_touch())
	tap.pressed.connect(_stop_channel)
	r.add_child(tap)
	var ab := Button.new()
	ab.text = "  Abandon  "
	UISkin.ghost(ab)
	UISkin.touch_h(ab, _ov_touch())
	ab.pressed.connect(close)
	r.add_child(ab)


# ============================== SIGIL DUELS ===================================================
# The old world ritual arrived here, auto-selected one card and resolved one timing tap.  A duel
# keeps that tactile action command, but puts it behind a real decision: three live ability cards,
# a three-energy turn, readable enemy intent, defensive/status archetypes and voluntary switching.
# It still ends in exactly ONE `broke` boolean, so the offering and server payout remain unchanged.
func _duel_begin(uid: String) -> void:
	if _mode != "world" or _phase != "channel" or _duel_animating:
		return
	var u := _unit(uid)
	if u.is_empty():
		_asset_send_failed()
		return
	_duel_generation += 1
	_duel_pending_hand = -1
	_duel_animating = false
	_chan_running = false
	_duel = TempleDuelScript.new()
	var mood := 1.0
	if _profile.has_method("mood_card_mult"):
		mood = float(_profile.mood_card_mult(uid))
	var started: Dictionary = _duel.start(u, _sigil, _round, mood)
	if not bool(started.get("ok", false)):
		_duel = null
		_asset_send_failed()
		return
	if not _duel_focus.has(uid):
		_duel_focus[uid] = 100.0
	_duel.set("focus", clampf(float(_duel_focus[uid]), 0.0, 100.0))
	if _world != null and is_instance_valid(_world) and _world.has_method("spawn_foe"):
		_world.call("spawn_foe", String(_duel.get("foe_id")), _alcove_pos)
	_duel_last_line = "Choose an ability, then land its action command."
	_ov_duel()


func _duel_snapshot() -> Dictionary:
	return _duel.snapshot() if _duel != null else {}


func _duel_ready_units() -> Array:
	var src := _asset_test_units() if _asset_test_mode() else _fit_units()
	var out: Array = []
	for u in src:
		if not (u is Dictionary):
			continue
		var uid := String((u as Dictionary).get("uid", ""))
		if uid == "":
			continue
		if float(_duel_focus.get(uid, 100.0)) > 0.0 or uid == _pick_uid:
			out.append(u)
	return out


func _duel_meter(parent: Control, title: String, value: float, maximum: float, col: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := Label.new()
	l.text = title
	l.custom_minimum_size = Vector2(145, 0)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", INK)
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.name = title.replace(" ", "") + "Meter"
	bar.min_value = 0.0
	bar.max_value = maxf(1.0, maximum)
	bar.value = clampf(value, 0.0, bar.max_value)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(330, 17)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.055, 0.035, 0.085, 0.98)
	bg.set_corner_radius_all(7)
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(7)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	var n := Label.new()
	n.text = "%d/%d" % [int(ceil(value)), int(ceil(maximum))]
	n.custom_minimum_size = Vector2(72, 0)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	n.add_theme_font_size_override("font_size", 11)
	n.add_theme_color_override("font_color", DIM)
	row.add_child(n)


func _duel_card_desc(slot: int, lvl: int) -> String:
	if slot < 0 or slot >= Econ.CARDS.size():
		return ""
	var c: Dictionary = Econ.CARDS[slot]
	var tier := Econ.card_tier(lvl)
	var bits: Array[String] = []
	if c.has("dmg"):
		bits.append("%d DMG" % int(c["dmg"][tier]))
	if c.has("shield"):
		bits.append("+%d SHIELD" % int(c["shield"][tier]))
	if c.has("heal"):
		bits.append("DRAIN %d%%" % int(float(c["heal"][tier]) * 100.0))
	if c.has("nextmul"):
		bits.append("NEXT ×%.2f" % float(c["nextmul"][tier]))
	if c.has("buff"):
		bits.append("POWER +%d%%" % int(float(c["buff"][tier]) * 100.0))
	if c.has("weaken"):
		bits.append("WEAKEN %d%%" % int(float(c["weaken"][tier]) * 100.0))
	if c.has("drain_e"):
		bits.append("JOLT")
	return " · ".join(bits)


func _ov_duel() -> void:
	if _duel == null or _phase != "channel" or not visible:
		return
	_chan_running = false
	_duel_pending_hand = -1
	var s := _duel_snapshot()
	var v := _ov_open_box(_el_col(_sigil))
	if _ov_box != null:
		_ov_box.custom_minimum_size = Vector2(760, 306)
	var boss := _round == ROUNDS
	_ov_say("FINAL DUEL — GRIMWICK" if boss else "SIGIL DUEL %d/%d — %s" % [_round, ROUNDS, String(s.get("foe_name", "WARDEN")).to_upper()])

	var intent: Dictionary = s.get("intent", {}) as Dictionary
	var top := Label.new()
	var intent_name := String(intent.get("name", "Silenced"))
	var intent_damage := int(ceil(float(intent.get("damage", 0.0))))
	top.text = "ENEMY INTENT  ·  %s%s" % [intent_name.to_upper(), ("  ·  %d FOCUS" % intent_damage) if intent_damage > 0 else ""]
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_theme_font_size_override("font_size", 14)
	top.add_theme_color_override("font_color", BAD if intent_damage >= 25 else GOLD)
	v.add_child(top)
	_duel_meter(v, "%s STABILITY" % String(s.get("foe_name", "WARDEN")).to_upper(),
		float(s.get("stability", 0.0)), float(s.get("stability_max", 1.0)), _el_col(_sigil))
	_duel_meter(v, "%s FOCUS" % _profile.unit_name(_unit(_pick_uid)).to_upper(),
		float(s.get("focus", 0.0)), float(s.get("focus_max", 100.0)), Color(0.38, 0.90, 0.62))

	var status := Label.new()
	status.text = "ENERGY %d/%d  ·  SHIELD %d  ·  TURN %d/%d  ·  %s" % [
		int(s.get("energy", 0)), int(s.get("energy_max", 3)), int(s.get("shield", 0)),
		int(s.get("enemy_casts", 0)) + 1, int(s.get("max_enemy_casts", 3)), _duel_last_line]
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 11)
	status.add_theme_color_override("font_color", DIM)
	status.clip_text = true
	v.add_child(status)

	var hand := HBoxContainer.new()
	hand.name = "DuelAbilityHand"
	hand.alignment = BoxContainer.ALIGNMENT_CENTER
	hand.add_theme_constant_override("separation", 8)
	v.add_child(hand)
	var u := _unit(_pick_uid)
	var sp := String(u.get("species", ""))
	var lvl := int(u.get("level", 1))
	for i in range(3):
		var slot := int(_duel.card_slot(i))
		if slot < 0 or slot >= Econ.CARDS.size():
			continue
		var c: Dictionary = Econ.CARDS[slot]
		var b := Button.new()
		b.name = "DuelCard%d" % i
		b.custom_minimum_size = Vector2(226, maxf(92.0, _ov_touch()))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.expand_icon = true
		# `icon_max_width` is a Button THEME CONSTANT in Godot 4.6, not an object property.  Assigning
		# it directly aborts this function at runtime and leaves the duel with no three-card hand.
		b.add_theme_constant_override("icon_max_width", 54)
		b.icon = TempleCardArt.texture(sp, slot)
		b.text = "%s\n%d EN · %s" % [_purge_card_name(sp, slot).to_upper(), int(c.get("cost", 0)), _duel_card_desc(slot, lvl)]
		b.add_theme_font_size_override("font_size", 11)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = "%s · %s" % [String(c.get("arch", "strike")).to_upper(), _duel_card_desc(slot, lvl)]
		UISkin.plaque(b, _el_col(Econ.el_of(sp)))
		b.disabled = _duel_animating or not bool(_duel.affordable(i)) or float(s.get("focus", 0.0)) <= 0.0
		b.pressed.connect(_duel_choose_card.bind(i))
		hand.add_child(b)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 8)
	v.add_child(foot)
	var ready := _duel_ready_units()
	_duel_switcher = OptionButton.new()
	_duel_switcher.name = "DuelCreatureSwitcher"
	_duel_switcher.custom_minimum_size = Vector2(250, 0)
	_duel_switcher.clip_text = true
	UISkin.ghost(_duel_switcher)
	UISkin.touch_h(_duel_switcher, _ov_touch())
	var selected := 0
	for i in range(ready.size()):
		var ru := ready[i] as Dictionary
		var ruid := String(ru.get("uid", ""))
		_duel_switcher.add_item("%s · %s · FOCUS %d" % [_profile.unit_name(ru), Econ.el_of(String(ru.get("species", ""))), int(_duel_focus.get(ruid, 100.0))])
		_duel_switcher.set_item_metadata(i, ruid)
		if ruid == _pick_uid:
			selected = i
	_duel_switcher.select(selected)
	foot.add_child(_duel_switcher)
	var swap := Button.new()
	swap.name = "DuelSwap"
	swap.text = "  SWAP  "
	# At the 844×390 phone scale the text-only natural width was 42.1 CSS px: visibly fine, but
	# 1.9 px short of the same 44×44 touch floor every other duel control honours.
	swap.custom_minimum_size = Vector2(80, 0)
	swap.tooltip_text = "Change the active Chikimon. In a normal run, Grimwick takes the telegraphed action."
	UISkin.ghost(swap)
	UISkin.touch_h(swap, _ov_touch())
	swap.disabled = _duel_animating or ready.size() < 2
	swap.pressed.connect(_duel_swap_selected)
	foot.add_child(swap)
	var end := Button.new()
	end.name = "DuelEndTurn"
	end.text = "  END TURN  "
	UISkin.plaque(end, EDGE)
	UISkin.touch_h(end, _ov_touch())
	end.disabled = _duel_animating or int(s.get("plays", 0)) <= 0 or float(s.get("focus", 0.0)) <= 0.0
	end.pressed.connect(_duel_end_turn)
	foot.add_child(end)


func _duel_choose_card(hand_index: int) -> void:
	if _duel == null or _duel_animating or _phase != "channel" or not bool(_duel.affordable(hand_index)):
		return
	_duel_pending_hand = hand_index
	_pick_slot = int(_duel.card_slot(hand_index))
	_ov_duel_command()


func _ov_duel_command() -> void:
	if _duel == null or _duel_pending_hand < 0 or _pick_slot < 0:
		return
	var u := _unit(_pick_uid)
	var sp := String(u.get("species", ""))
	var col := _el_col(Econ.el_of(sp))
	var v := _ov_open_box(col)
	if _ov_box != null:
		_ov_box.custom_minimum_size = Vector2(680, 238)
	_ov_say("ACTION COMMAND — %s" % _purge_card_name(sp, _pick_slot).to_upper())
	var info := HBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 12)
	v.add_child(info)
	var art := TextureRect.new()
	art.texture = TempleCardArt.texture(sp, _pick_slot)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = Vector2(66, 98)
	info.add_child(art)
	var text := Label.new()
	text.text = "%s\n%s\nStop the light inside the rune band." % [
		_purge_card_name(sp, _pick_slot), _duel_card_desc(_pick_slot, int(u.get("level", 1)))]
	text.add_theme_font_size_override("font_size", 13)
	text.add_theme_color_override("font_color", INK)
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.add_child(text)

	var track := PanelContainer.new()
	track.custom_minimum_size = Vector2(520, 42)
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.09, 0.06, 0.13, 0.95)
	ts.border_color = Color(0.35, 0.30, 0.45)
	ts.set_border_width_all(2)
	ts.set_corner_radius_all(10)
	track.add_theme_stylebox_override("panel", ts)
	v.add_child(track)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(0, 30)
	track.add_child(inner)
	_chan_zone = ColorRect.new()
	_chan_zone.color = Color(col.r, col.g, col.b, 0.48)
	inner.add_child(_chan_zone)
	_chan_marker = ColorRect.new()
	_chan_marker.color = Color(1, 1, 1, 0.98)
	inner.add_child(_chan_marker)
	_chan_band = randf_range(0.18, 0.82)
	_chan_t = 0.0
	_chan_dir = 1.0
	_chan_running = true
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var cast := Button.new()
	cast.name = "DuelActionCommand"
	cast.text = "  ACTIVATE  "
	cast.add_theme_font_size_override("font_size", 17)
	UISkin.plaque(cast, col)
	UISkin.touch_h(cast, _ov_touch())
	cast.pressed.connect(_stop_channel)
	row.add_child(cast)
	var back := Button.new()
	back.text = "  Change card  "
	UISkin.ghost(back)
	UISkin.touch_h(back, _ov_touch())
	back.pressed.connect(func():
		_chan_running = false
		_duel_pending_hand = -1
		_ov_duel())
	row.add_child(back)


func _duel_commit(timing: float) -> void:
	if _duel == null or _duel_pending_hand < 0 or _duel_animating or _phase != "channel":
		return
	var hand_index := _duel_pending_hand
	_duel_pending_hand = -1
	_duel_animating = true
	var gen := _duel_generation
	var r: Dictionary = _duel.play_hand(hand_index, timing)
	if not bool(r.get("ok", false)):
		_duel_animating = false
		_duel_last_line = "That card cannot be played now."
		_ov_duel()
		return
	_duel_focus[_pick_uid] = float(r.get("focus_after", _duel.get("focus")))
	var dmg := int(r.get("damage", 0))
	var extras: Array[String] = []
	if int(r.get("shield_gain", 0)) > 0:
		extras.append("+%d shield" % int(r.get("shield_gain", 0)))
	if int(r.get("healed", 0)) > 0:
		extras.append("+%d focus" % int(r.get("healed", 0)))
	if String(r.get("arch", "")) == "jolt":
		extras.append("enemy jolted")
	_duel_last_line = "%s%s" % [("%d damage" % dmg) if dmg > 0 else String(r.get("name", "Ability")), (" · " + " · ".join(extras)) if not extras.is_empty() else ""]
	await _duel_player_fx(r)
	if gen != _duel_generation or not visible or _duel == null:
		return
	_duel_animating = false
	if bool(_duel.get("over")):
		_duel_complete()
	else:
		_ov_duel()


func _duel_player_fx(r: Dictionary) -> void:
	if _world == null or not is_instance_valid(_world):
		return
	var damage := float(r.get("damage", 0.0))
	var u := _unit(_pick_uid)
	var col := _el_col(Econ.el_of(String(u.get("species", ""))))
	var from := _alcove_pos
	if _helper_party != "" and _world.has_method("follower_pos"):
		from = Vector2(_world.call("follower_pos", _helper_party))
	var target := _alcove_pos
	if _world.has_method("foe_pos"):
		target = Vector2(_world.call("foe_pos"))
	if damage > 0.0:
		if _helper_party != "" and _world.has_method("strike_follower"):
			_world.call("strike_follower", _helper_party, target)
		elif _helper != null and is_instance_valid(_helper) and _helper.has_method("play"):
			_helper.call("play", "attack")
		if _world.has_method("bolt_fx"):
			_world.call("bolt_fx", from, target, col, 0.18)
		await get_tree().create_timer(0.18).timeout
		if _world != null and is_instance_valid(_world):
			if _world.has_method("foe_play"):
				_world.call("foe_play", "hurt")
			if _world.has_method("impact_fx"):
				_world.call("impact_fx", target, col, damage >= 35.0)
	else:
		# Guard/setup cards still get a readable pulse on the creature, without spawning another rig.
		if _world.has_method("impact_fx"):
			_world.call("impact_fx", from, col, false)
	await get_tree().create_timer(0.18).timeout


func _duel_end_turn(force: bool = false) -> void:
	if _duel == null or _duel_animating or _phase != "channel":
		return
	var s := _duel_snapshot()
	if not force and int(s.get("plays", 0)) <= 0 and float(s.get("focus", 0.0)) > 0.0:
		_duel_last_line = "Play at least one ability before ending the turn."
		_ov_duel()
		return
	_duel_animating = true
	_chan_running = false
	var gen := _duel_generation
	var r: Dictionary = _duel.end_turn()
	if not bool(r.get("ok", false)):
		_duel_animating = false
		_ov_duel()
		return
	_duel_focus[_pick_uid] = float(r.get("focus_after", _duel.get("focus")))
	if bool(r.get("skipped", false)):
		_duel_last_line = "JOLT! %s loses the cast." % String((r.get("intent", {}) as Dictionary).get("name", "The enemy"))
	else:
		_duel_last_line = "%s hits for %d%s" % [
			String((r.get("intent", {}) as Dictionary).get("name", "Enemy attack")), int(r.get("damage", 0)),
			(" · %d blocked" % int(r.get("absorbed", 0))) if int(r.get("absorbed", 0)) > 0 else ""]
	await _duel_enemy_fx(r)
	if gen != _duel_generation or not visible or _duel == null:
		return
	_duel_animating = false
	if bool(r.get("needs_switch", false)):
		var replacements := _duel_ready_units().filter(func(u): return String((u as Dictionary).get("uid", "")) != _pick_uid and float(_duel_focus.get(String((u as Dictionary).get("uid", "")), 100.0)) > 0.0)
		if replacements.is_empty():
			if _duel.has_method("forfeit"):
				_duel.forfeit()
			_duel_complete()
			return
		_duel_last_line = "%s is out of Focus — choose a replacement." % _profile.unit_name(_unit(_pick_uid))
		_ov_duel()
		return
	if bool(_duel.get("over")):
		_duel_complete()
	else:
		_ov_duel()


func _duel_enemy_fx(r: Dictionary) -> void:
	if _world == null or not is_instance_valid(_world):
		return
	if bool(r.get("skipped", false)):
		if _world.has_method("foe_play"):
			_world.call("foe_play", "hurt")
		await get_tree().create_timer(0.24).timeout
		return
	var target := _alcove_pos
	if _helper_party != "" and _world.has_method("follower_pos"):
		target = Vector2(_world.call("follower_pos", _helper_party))
	var from := _alcove_pos
	if _world.has_method("foe_pos"):
		from = Vector2(_world.call("foe_pos"))
	if _world.has_method("foe_play"):
		_world.call("foe_play", "attack")
	if _world.has_method("bolt_fx"):
		_world.call("bolt_fx", from, target, _el_col(_sigil), 0.22)
	await get_tree().create_timer(0.22).timeout
	if _world != null and is_instance_valid(_world) and float(r.get("damage", 0.0)) > 0.0:
		if _helper_party != "" and _world.has_method("follower_hurt"):
			_world.call("follower_hurt", _helper_party)
		elif _helper != null and is_instance_valid(_helper) and _helper.has_method("play"):
			_helper.call("play", "hurt")
		if _world.has_method("impact_fx"):
			_world.call("impact_fx", target, BAD, false)
	await get_tree().create_timer(0.20).timeout


func _duel_swap_selected() -> void:
	if _duel_switcher == null or not is_instance_valid(_duel_switcher) or _duel_switcher.item_count <= 0:
		return
	var uid := String(_duel_switcher.get_item_metadata(_duel_switcher.selected))
	_duel_switch_to(uid)


func _duel_switch_to(uid: String) -> void:
	if _duel == null or _duel_animating or uid == "" or uid == _pick_uid or _phase != "channel":
		return
	var allowed := false
	for u in _duel_ready_units():
		if String((u as Dictionary).get("uid", "")) == uid and float(_duel_focus.get(uid, 100.0)) > 0.0:
			allowed = true
			break
	if not allowed:
		return
	_duel_focus[_pick_uid] = float(_duel.get("focus"))
	if _asset_test_mode():
		_asset_restore_unit(uid)
	_release_helper()
	_profile.call("lead_unit", uid)
	if _world != null and is_instance_valid(_world) and _world.has_method("set_party"):
		_world.call("set_party", _party_for_world())
	_pick_uid = uid
	_spawn_helper(uid)
	var u := _unit(uid)
	var mood := float(_profile.mood_card_mult(uid)) if _profile.has_method("mood_card_mult") else 1.0
	var switched: Dictionary = _duel.switch_unit(u, mood, float(_duel_focus.get(uid, 100.0)))
	if not bool(switched.get("ok", false)):
		return
	_duel_last_line = "%s enters with its own ability deck." % _profile.unit_name(u)
	if _asset_test_mode():
		# The all-assets build is a visual/test bench: free swapping lets every rig and kit be inspected
		# without forty enemy punishment turns. Production swaps deliberately yield the enemy action.
		_ov_duel()
	else:
		_duel_end_turn(true)


func _duel_complete() -> void:
	if _duel == null or _phase != "channel":
		return
	_phase = "resolve"                 # latch BEFORE animation/timers: one duel banks one result
	_chan_running = false
	_duel_pending_hand = -1
	_duel_animating = true
	var s := _duel_snapshot()
	var broke := bool(s.get("won", false))
	if broke:
		_purified += 1
	var u := _unit(_pick_uid)
	var sp := String(u.get("species", ""))
	var hist_card := _purge_card_name(sp, _pick_slot)
	var entry := {
		"duel": true, "sigil": _sigil, "uid": _pick_uid, "name": _profile.unit_name(u),
		"el": Econ.el_of(sp), "lvl": int(u.get("level", 1)), "mult": Econ.el_mult(Econ.el_of(sp), _sigil),
		"timing": 1.0, "power": float(s.get("stability_max", 1.0)) - float(s.get("stability", 0.0)),
		"broke": broke, "card_slot": _pick_slot, "card": hist_card,
		"arch": String(Econ.CARDS[clampi(_pick_slot, 0, Econ.CARDS.size() - 1)].get("arch", "strike")), "card_mul": 1.0,
		"foe": String(s.get("foe_name", "Warden")), "stability_max": float(s.get("stability_max", 1.0)),
		"stability_left": float(s.get("stability", 0.0)), "focus": float(s.get("focus", 0.0)),
		"shield": float(s.get("shield", 0.0)), "casts": int(s.get("enemy_casts", 0)),
		"casts_max": int(s.get("max_enemy_casts", 3)),
	}
	_log.append(entry)
	_duel_focus[_pick_uid] = float(s.get("focus", 0.0))
	if _world != null and is_instance_valid(_world) and _world.has_method("foe_play"):
		_world.call("foe_play", "defeated" if broke else "idle")
	if broke and _world != null and is_instance_valid(_world) and _world.has_method("clear_lit"):
		_world.call("clear_lit")
	var gen := _duel_generation
	await get_tree().create_timer(0.52).timeout
	if gen != _duel_generation or not visible or _mode != "world":
		return
	_duel_animating = false
	_ov_result(entry)


func _duel_clear() -> void:
	_duel_generation += 1
	_chan_running = false
	_duel_pending_hand = -1
	_duel_animating = false
	_duel_switcher = null
	_duel = null
	if _world != null and is_instance_valid(_world) and _world.has_method("clear_foe"):
		_world.call("clear_foe")

# the strike, staged in the world: lunge, bolt, impact — then the honest arithmetic
func _ov_attack(e: Dictionary) -> void:
	_ov_clear()
	var broke: bool = bool(e["broke"])
	var col := _el_col(String(e["el"]))
	var scol := _el_col(String(e["sigil"]))
	# the lunge goes TOWARD the plate, whichever side the creature was summoned on (it used to be a
	# hardcoded +34 px, so at an east alcove the attacker lunged away from the sigil it was hitting)
	var lunge := Vector2(34, -6)
	var from: Vector2 = _alcove_pos + Vector2(-70, 0)
	if _helper_party != "" and _world != null and is_instance_valid(_world) \
			and _world.has_method("strike_follower"):
		# THE HALL SWINGS ITS OWN CREATURE. A follower is driven every frame by the follow solve,
		# so a tween started from out here would be fighting that solve for the whole blow — the
		# lunge would be dragged back toward the formation slot while it was still going out.
		# Temple2D holds it still for the length of the swing, which is a thing only Temple2D can do.
		var fpos: Vector2 = _world.call("follower_pos", _helper_party)
		var toward2: float = signf(_alcove_pos.x - fpos.x)
		if toward2 == 0.0:
			toward2 = 1.0
		from = fpos + Vector2(46.0 * toward2, -18.0)
		_world.call("strike_follower", _helper_party, _alcove_pos)
	elif _helper != null and is_instance_valid(_helper):
		var home: Vector2 = (_helper as Node2D).position
		var toward: float = signf(_alcove_pos.x - home.x)
		if toward == 0.0:
			toward = 1.0
		lunge = Vector2(34.0 * toward, -6.0)
		from = home + Vector2(46.0 * toward, -18.0)
		# THE REAL ATTACK FRAME, not just a shove. The sprite package supplies a painted attack pose
		# per direction (frames 3/7/11/15), so the creature is drawn striking rather than sliding —
		# and it faces the PLATE, which is what makes an east-side and a west-side send look right
		# without any mirroring. The lunge stays underneath it: the pose sells the blow, the motion
		# sells the distance.
		if _helper.has_method("face"):
			_helper.call("face", Vector2(_alcove_pos.x - home.x, _alcove_pos.y - home.y))
		if _helper.has_method("play"):
			_helper.call("play", "attack")
		var lt := create_tween()
		lt.tween_property(_helper, "position", home + lunge, 0.12).set_trans(Tween.TRANS_BACK)
		lt.tween_property(_helper, "position", home, 0.18)
	# the bolt is a radial-gradient dot in the ATTACKER'S element colour, thrown at the plate
	if _world != null and is_instance_valid(_world) and _world.has_method("bolt_fx"):
		# THE WORLD OWNS ITS OWN EFFECTS. A Sprite2D parented to a Node3D does not render — no
		# error, no warning, just a strike with nothing coming out of it.
		_world.call("bolt_fx", from, _alcove_pos, col, 0.22)
		await get_tree().create_timer(0.22).timeout
		_ov_impact(broke, scol)
	elif _world != null and is_instance_valid(_world):
		var g := GradientTexture2D.new()
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5); g.fill_to = Vector2(0.5, 0.0)
		var gr := Gradient.new()
		gr.set_color(0, Color(col.r, col.g, col.b, 1.0))
		gr.set_color(1, Color(col.r, col.g, col.b, 0.0))
		g.gradient = gr
		g.width = 28; g.height = 28
		var bolt := Sprite2D.new()
		bolt.texture = g
		bolt.scale = Vector2(1.6, 1.6)
		bolt.position = from
		_world.add_child(bolt)
		var bt := create_tween()
		_bolt_tw = bt                      # so _teardown_world can kill it before its target is freed
		bt.tween_property(bolt, "position", _alcove_pos, 0.22)
		bt.tween_callback(func():
			if is_instance_valid(bolt):
				bolt.queue_free()
			_ov_impact(broke, scol))
	else:
		_ov_impact(broke, scol)
	await get_tree().create_timer(0.85).timeout
	if _phase == "resolve" and visible:
		_ov_result(e)

func _ov_impact(broke: bool, scol: Color) -> void:
	# A SIGIL THAT HOLDS PUSHES BACK. The package supplies a hurt pose per direction (16/17/18, with
	# UP falling back to hurt-down), so a failed purge now reads on the creature itself instead of
	# only in the arithmetic on the card. It is a one-shot: Rig2D returns it to idle on its own.
	if not broke:
		if _helper_party != "" and _world != null and is_instance_valid(_world) \
				and _world.has_method("follower_hurt"):
			_world.call("follower_hurt", _helper_party)
		elif _helper != null and is_instance_valid(_helper) and _helper.has_method("play"):
			_helper.call("play", "hurt")
	if _world != null and is_instance_valid(_world) and _world.has_method("impact_fx"):
		_world.call("impact_fx", _alcove_pos, scol, broke)
	elif _world != null and is_instance_valid(_world):
		var burst := CPUParticles2D.new()
		burst.one_shot = true
		burst.emitting = true
		burst.amount = 42 if broke else 16
		burst.lifetime = 0.55
		burst.explosiveness = 1.0
		burst.direction = Vector2(0, -1)
		burst.spread = 180.0
		burst.initial_velocity_min = 60.0
		burst.initial_velocity_max = 190.0
		burst.gravity = Vector2(0, 240)
		burst.color = scol
		burst.position = _alcove_pos
		_world.add_child(burst)
		# NO LAMBDA HERE. A lambda capturing `burst` outlives it — the world is torn down at _finish
		# about 0.85 s in, the timer fires at 1.2 s, and the engine logs "Lambda capture at index 0
		# was freed" on every single run (measured: 18 of them across one dev_temple_attack pass).
		# A Callable bound to the object itself is disconnected when the object frees, so the timer
		# simply finds nobody home. Same behaviour, no error, one less thing in a player's log.
		get_tree().create_timer(1.2).timeout.connect(burst.queue_free)
	if broke and _world != null and is_instance_valid(_world):
		_world.call("clear_lit")
	# the screen kick — ±7 px on the CONTAINER, so the world jolts and the UI does not
	if _svc != null and is_instance_valid(_svc):
		var st := create_tween()
		st.tween_property(_svc, "position", Vector2(7, -4), 0.05)
		st.tween_property(_svc, "position", Vector2(-6, 3), 0.05)
		st.tween_property(_svc, "position", Vector2.ZERO, 0.08)

func _ov_result(e: Dictionary) -> void:
	var broke: bool = bool(e["broke"])
	var v := _ov_open_box(GOLD if broke else BAD)
	_ov_say(("GRIMWICK DEFEATED" if _round == ROUNDS else "SIGIL BROKEN") if broke else ("GRIMWICK HOLDS" if _round == ROUNDS else "THE SIGIL HOLDS"))
	_row(v, String(e["name"]), "%s · L%d" % [e["el"], int(e["lvl"])], INK)
	if bool(e.get("duel", false)):
		_row(v, "Opponent", String(e.get("foe", "Sigil Warden")), BAD if not broke else DIM)
		_row(v, "Last ability", "%s · %s" % [String(e.get("card", "Strike")), String(e.get("arch", "strike")).to_upper()], EDGE)
		_row(v, "Stability", "%d/%d remaining" % [int(ceil(float(e.get("stability_left", 0.0)))), int(ceil(float(e.get("stability_max", 1.0))))], GOLD if broke else BAD)
		_row(v, "Enemy casts", "%d/%d" % [int(e.get("casts", 0)), int(e.get("casts_max", 3))], DIM)
		_row(v, "Focus left", "%d" % int(ceil(float(e.get("focus", 0.0)))), Color(0.38, 0.90, 0.62) if float(e.get("focus", 0.0)) > 0.0 else BAD)
	else:
		_row(v, "Ability card", "%s · %s" % [String(e.get("card", "Strike")), String(e.get("arch", "strike")).to_upper()], EDGE)
		_row(v, "Card force", "×%.2f" % float(e.get("card_mul", 1.0)), GOLD if float(e.get("card_mul", 1.0)) > 1.0 else DIM)
		_row(v, "Element", "×%.2f" % float(e["mult"]),
			GOLD if float(e["mult"]) > 1.0 else (BAD if float(e["mult"]) < 1.0 else DIM))
		_row(v, "Channel", "×%.2f" % float(e["timing"]), GOLD if float(e["timing"]) > 1.0 else DIM)
		_row(v, "Purge power", "%.2f  (need %.2f)" % [float(e["power"]), PURIFY_BAR], GOLD if broke else BAD)
	var r := HBoxContainer.new()
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.add_theme_constant_override("separation", 10)
	v.add_child(r)
	var nx := Button.new()
	nx.text = "  Next duel  " if _round < ROUNDS else "  Seal the Purge  "
	nx.add_theme_font_size_override("font_size", 16)
	UISkin.plaque(nx, EDGE)
	UISkin.touch_h(nx, _ov_touch())
	nx.pressed.connect(func():
		_ov_clear()
		_duel_clear()
		_release_helper()
		_next_round())
	r.add_child(nx)
	var ab := Button.new()
	ab.text = "  Abandon  "
	UISkin.ghost(ab)
	UISkin.touch_h(ab, _ov_touch())
	ab.pressed.connect(close)
	r.add_child(ab)

# ============================== helpers =======================================================
func _purge_card_name(sp: String, slot: int) -> String:
	var names: Array = Econ.CARD_NAMES.get(sp, [])
	if slot >= 0 and slot < names.size() and names[slot] is Array and names[slot].size() >= 2:
		return String(names[slot][1])
	return String(Econ.CARDS[clampi(slot, 0, Econ.CARDS.size() - 1)].get("name", "Strike"))

func _purge_card_mul(slot: int, lvl: int) -> float:
	var c: Dictionary = Econ.CARDS[clampi(slot, 0, Econ.CARDS.size() - 1)]
	var arch := String(c.get("arch", "strike"))
	var tier := Econ.card_tier(lvl)
	match arch:
		"nova": return 1.28
		"blast": return 1.16
		"rend", "drain": return 1.08
		"strike": return 1.02
		"quick", "jolt": return 0.96
		"charge", "rally": return 1.12 + float(tier) * 0.03
		"guard", "bulwark": return 0.92 + float(tier) * 0.03
		"wither": return 1.00
	return 1.0

func _mat_n(m: String) -> int:
	var mats: Dictionary = _profile.d.get("mats", {})
	return int(mats.get(m, 0))

func _has_offering() -> bool:
	for m in OFFERING:
		if _mat_n(String(m)) < int(OFFERING[m]):
			return false
	return true

# The party, minus anyone the rest of the game already refuses to send into a fight — fainted,
# resting, starving or out of stamina. Profile.unit_ok_to_fight is that single authority (it
# returns "" when the unit may fight), so the temple cannot become a loophole around recovery.
func _fit_units() -> Array:
	var out: Array = []
	if _profile == null or not _profile.has_method("party_units"):
		return out
	for u in _profile.party_units():
		if not (u is Dictionary):
			continue
		var uid := String((u as Dictionary).get("uid", ""))
		if uid == "":
			continue
		if _profile.has_method("unit_ok_to_fight") and String(_profile.unit_ok_to_fight(uid)) != "":
			continue
		# Focus is a run-local Temple resource, separate from persistent HP/stamina. A creature whose
		# Focus broke in an earlier duel cannot be re-sent until the next Purge run.
		if _duel_focus.has(uid) and float(_duel_focus[uid]) <= 0.0:
			continue
		out.append(u)
	return out

# EVERY ACTIVE PARTY MEMBER FOLLOWS, not only the ones fit to fight. _fit_units() is the send
# filter — fainted, resting and starving units may not answer a sigil — but they still walk with
# their trainer everywhere else in the game, and a party member who vanished from the hall because
# they were tired would read as a bug, not as a rule.
func _party_for_world() -> Array:
	var out: Array = []
	if _profile == null or not _profile.has_method("party_units"):
		return out
	for u in _profile.party_units():
		if not (u is Dictionary):
			continue
		var d := u as Dictionary
		if String(d.get("uid", "")) == "" or String(d.get("species", "")) == "":
			continue
		# The platformer consumes the same progression contract as Chikiseum: level/kind determine
		# unlocked painted cards and their tier. Preserve the unit rather than reducing it to an id pair.
		var world_unit := d.duplicate(true)
		world_unit["uid"] = String(d.get("uid", ""))
		world_unit["species"] = String(d.get("species", ""))
		world_unit["kind"] = String(d.get("kind", Econ.unit_kind(world_unit["species"])))
		world_unit["level"] = clampi(int(d.get("level", 1)), 1, Econ.LEVEL_CAP)
		out.append(world_unit)
	return out

# The horde gate is intentionally narrower than the old follower hall: one selected combatant goes
# in and no trainer/follower bodies are sent.  The all-assets laboratory may select from its owned
# bench as well, but remains save-free; production candidates are the normal fit party only.
func _horde_candidates() -> Array:
	var source := _asset_test_units() if _asset_test_mode() else _fit_units()
	var out: Array = []
	for value in source:
		if not (value is Dictionary):
			continue
		var d := (value as Dictionary).duplicate(true)
		var uid := String(d.get("uid", ""))
		var species := String(d.get("species", ""))
		if uid == "" or species == "":
			continue
		d["uid"] = uid
		d["species"] = species
		d["kind"] = String(d.get("kind", Econ.unit_kind(species)))
		d["level"] = clampi(int(d.get("level", 1)), 1, Econ.LEVEL_CAP)
		out.append(d)
	return out

func _unit_list_has(units: Array, uid: String) -> bool:
	for value in units:
		if value is Dictionary and String((value as Dictionary).get("uid", "")) == uid:
			return true
	return false

func _solo_for_world() -> Array:
	var candidates := _horde_candidates()
	if candidates.is_empty():
		return []
	for value in candidates:
		if value is Dictionary and String((value as Dictionary).get("uid", "")) == _horde_pick_uid:
			return [(value as Dictionary).duplicate(true)]
	_horde_pick_uid = String((candidates[0] as Dictionary).get("uid", ""))
	return [(candidates[0] as Dictionary).duplicate(true)]

func _horde_sandbox_roster() -> Array:
	var candidates := _horde_candidates()
	if candidates.size() <= 1:
		return candidates
	# The chosen creature goes first because Horde's pre-enter contract selects index zero.  The
	# remaining test roster is retained only so its sandbox-only cycle button can replace that one
	# rig; none of them exists as a follower or second combat body.
	var out: Array = []
	for value in candidates:
		if value is Dictionary and String((value as Dictionary).get("uid", "")) == _horde_pick_uid:
			out.append((value as Dictionary).duplicate(true))
			break
	for value in candidates:
		if value is Dictionary and String((value as Dictionary).get("uid", "")) != _horde_pick_uid:
			out.append((value as Dictionary).duplicate(true))
	return out

func _new_run_id() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	if not bytes.is_empty():
		return bytes.hex_encode()
	# Native crypto is expected everywhere Godot ships, but a bounded fallback still names a run
	# uniquely enough for retry recovery without ever affecting the server-owned reward roll.
	return "%x-%x" % [Time.get_ticks_usec(), get_instance_id()]

func _unit(uid: String) -> Dictionary:
	var units: Dictionary = _profile.d.get("units", {})
	return units.get(uid, {}) as Dictionary

func _el_col(el: String) -> Color:
	return Nameplate.el_color(el)
