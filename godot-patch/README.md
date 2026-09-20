# Getting AI practice, SOL wagers and the stake-free season match into the game

The backend has the first two. The shipped game has neither, and one of the blockers is not
obvious — so this folder is the exact work, written against the live API, ready to drop into
the Godot project. The **season match** is the third, added for the iOS app: PvP against real
players with nothing staked, where the server hosts the match and pays the winner in fantasy
fish, eggs and resources. It needs backend routes that do not exist yet; the contract is in
[`../IOS-APP.md`](../IOS-APP.md).

**The Godot project is not in any repository I can reach.** The game ships as compiled `.gdc`
bytecode. Everything here was written by reading that bytecode's string tables out of the live
313 MB pack, so it matches the client's real conventions (`auth_fields`, `attach_live_client`,
`command_failed`, `roster_received`, …).

### Re-checked independently, 2026-09-20

That claim was inherited, so it was verified again from scratch rather than repeated. Every
repository on the account was listed and its full file tree scanned:

| repository | files | `.gd` / `.tscn` / `.tres` / `project.godot` |
|---|---|---|
| `chikimonsters` (this one) | — | only `godot-patch/*.gd`, written by agents |
| `chiki-monsters` | — | 0 — the retired Three.js build |
| `Claude-Company` | 487 | 0 |
| `Markets-and-Makers` | 415 | 0 |
| `Claude-Company-Robinhood` | 395 | 0 |
| `backend` | 190 | 0 |
| `Project-Takeover` | 159 | 0 |
| `Claude-Company-Solana` | 108 | 0 |
| `claude-company-executor` | 24 | 0 |

**1,778 files, zero Godot project files.** Two private repositories — `Get-Stonked` and
`pumpfun-whale-welcome-agent` — could not be read from this session; both are named for unrelated
projects. `chiki-website-deploy.zip` inside `chiki-monsters` was opened and checked too: 18
entries, none of them Godot.

**What follows from that.** Steps 3, 4, 6 and 7 of the integration order below all need a Godot
export, and nothing on this account can produce one. Until the project is recovered or rebuilt,
the app cannot ship the season match, cannot hide the Trading Post gate, and cannot add the four
season routes to the pack's own allowlist. `../APPSTORE.md` states the two honest options.

**What is verified:** the original three scripts compile under real Godot 4.6.stable, and the
wager client was driven end to end against a fake server — post, deposit, match, and a refusal —
with 23 checks passing. `verify.gd` now also drives the season client the same way (board,
queue, pairing, claim, and three refusals). Run it yourself:

```sh
cd verify && cp ../*.gd .
godot --headless --path . --import
godot --headless --path . --script verify.gd     # exits non-zero on any failure
```

> The two season scripts and the extended `verify.gd` were written without a Godot toolchain to
> hand, so unlike the original three they have **not yet been run under the engine**. Run the
> command above before integrating them; they are written to the same conventions, but "compiles"
> is a claim only the engine can make.

The JavaScript half of the same revision — the iOS app's crypto lockdown and its wallet-less
sign-in — has harnesses that need no Godot and do pass here:

```sh
node verify/chiki-ios.test.mjs        # the policy layer itself: 118 checks
node verify/loader-policy.test.mjs    # that realm/index.html still wires it up
```

**What is not verified:** integration with the actual game — its scene tree, its skin, its gate
— because that project is not here. The UI in `ChikiseumWagerPanel.gd` and
`ChikiseumSeasonPanel.gd` builds plain Godot controls so it runs standalone; it is meant to be
reskinned, and the behaviour underneath it is what these tests pin.

---

## What is actually missing, precisely

### 1. The route allowlist — the blocker that is easy to miss

`ChikiseumLiveClient` installs a `window.fetch` guard in the web export and hardcodes which
arena routes the game may call:

```js
const bases  = ['https://api.chikimonsters.com', 'https://chiki-backend-singapore.onrender.com'];
const routes = ['roster','session','lobby','queue','challenge','accept','ready','state','cast','move','cancel'];
const allowed = new Set(bases.flatMap(base => routes.map(route => base + '/chikiseum/live/v1/' + route)));
```

Eleven routes. **Adding wager or season UI alone will not work** — the guard will block the
calls. Add the six wager routes and the four season routes to that array:

```js
const routes = ['roster','session','lobby','queue','challenge','accept','ready','state','cast','move','cancel',
                'wager_board','wager_mine','wager_post','wager_accept','wager_withdraw','wager_deposit',
                'season_board','season_queue','season_state','season_claim'];
```

That is the whole change to the transport. Everything else is additive.

**The six wager routes stay off the iOS app, and this allowlist is not what stops them.**
`realm/chiki-ios.js` refuses `/chikiseum/live/v1/wager_*` outright in the app, below this guard
and outside the pack, so adding them here does not hand the app a stake — which is deliberate:
one pack serves both platforms, and the platform that must not stake is policed by the page that
hosts it, not by a build flag inside it. The season routes are allowed on both.

### 2. The AI practice opponent is not in the lobby

The build's own strings show it has never heard of it — `"Training Dummy"` appears **zero**
times. (The word "rehearsal" *does* appear 13 times, but it means something else entirely:
`"IMAGE REHEARSAL"`, `"LOCAL HUMAN REHEARSAL"`, `"Rehearsal is offline"` — an offline art
preview. Do not confuse the two.)

The server already offers it. Every `lobby` response now carries:

```json
{ "rehearsal_available": true,
  "trainers": [ { "trainer_id": "ai-…", "handle": "Training Dummy (AI)",
                  "rehearsal": true, "instant": true, "compatible": true, "fighter": {…} } ] }
```

Find it by the **`rehearsal` flag**, never by matching the handle — the flag is the contract,
the string is copy. `instant: true` means `challenge` starts the match immediately and there is
**no accept step**; the dummy is already marked ready. Practice records no completion, so it
awards no battle XP and cannot be farmed.

See `ChikiseumRehearsalLobby.gd`.

### 3. The wager UI does not exist — and the current copy denies it

Six strings in the shipped build tell players there is no wagering:

> "Online duels have no wagering" · "No SOL wagering" · "No wagering or currency payouts"

Those must change, or the game will contradict itself. See `ChikiseumWagerPanel.gd` and
`chikiseum-wager-bridge.js`.

**Careful with the rewrite: those strings are now TRUE on the iOS app.** "No SOL wagering" is
exactly right there. Rewrite them against `CHIK_FEATURES.wagers` (§5) rather than replacing them
with copy that promises wagering unconditionally, or the app will advertise a stake it refuses.

### 4. PvP for a client with no wallet — the season match

The iOS app cannot stake, and nothing on the device can be made to. So the Chikiseum keeps the
fight and drops the money:

| | website | iOS app |
|---|---|---|
| enter | post or accept a SOL wager | press **Find a match** |
| stake | 0.001–0.05 SOL, held by the treasury | nothing |
| pairing | a player accepts your posted wager | the server queues and pairs you |
| the fight | identical | identical |
| prize | the pot, in SOL | fantasy fish, eggs, resources — **the real assets, on your account** |

The prize is not app-only play money. A fish won here is credited to the linked account exactly
as one won on the website is, and it is in the satchel next time the player opens
chikimonsters.com. What the app has no surface for is **selling or trading** it — that is the
Trading Post and the marketplace, and both are website-only. Earning here, selling there.

Rewards use the same vocabulary and the same server-side roll as the Wicked Temple's Treasure
Vault, decided before the player presses anything. The cap that stops farming is a **daily match
count**, not a money cap.

See `ChikiseumSeasonClient.gd` and `ChikiseumSeasonPanel.gd`. The four routes do not exist on the
backend yet — the contract they are written against is in [`../IOS-APP.md`](../IOS-APP.md).

### 5. The build cannot yet tell which platform it is on

`realm/chiki-ios.js` publishes `window.CHIK_FEATURES` — one object saying whether this client may
show a wallet, a market, a wager or a token gate, and which PvP mode it has. Nothing in the pack
reads it, because nothing knew to. Read it once at start-up:

```gdscript
var raw := JavaScriptBridge.eval("JSON.stringify(window.CHIK_FEATURES || {})", true)
var features: Dictionary = JSON.parse_string(str(raw)) if raw != null else {}
var can_trade: bool = features.get("trading_post", true)
var pvp_mode := String(features.get("pvp_mode", "wager"))
```

Then hide the Trading Post gate, the marketplace header and the wager panel when they are off,
and open `ChikiseumSeasonPanel` instead of `ChikiseumWagerPanel` when `pvp_mode == "season"`.
Default every flag to the WEB value, as above, so an old pack on a new loader behaves as it does
today rather than losing features to a missing key.

This is the only part of the iOS revision that needs a pack rebuild. Until it ships, the app is
already safe — the capability is gone, not just hidden (see `../IOS-APP.md` §"What is enforced
where") — but a player can still walk up to a Trading Post that then refuses them, which is a
worse experience than not seeing it.

---

## Files here

| file | what it is |
|---|---|
| `ChikiseumWagerClient.gd` | Speaks the six wager routes. Transport-agnostic: bind it to the existing client's command function so it inherits auth and the fetch guard. **Website only.** |
| `ChikiseumWagerPanel.gd` | The pill: board, post, accept, pay, withdraw, live status. **Website only.** |
| `ChikiseumSeasonClient.gd` | Speaks the four season routes. Same transport contract, no money in it. Both platforms; the app's only PvP mode. |
| `ChikiseumSeasonPanel.gd` | The pill: queue, standing, prize table, collect. Both platforms. |
| `ChikiseumRehearsalLobby.gd` | Finds the practice opponent in a lobby payload and starts it correctly. |
| `chikiseum-wager-bridge.js` | Phantom deposit for the web export: builds the memo-tagged transfer, signs, returns the signature. Goes in `realm/` and is referenced from `realm/index.html`. **Must stay behind the `CHIK_NO_CRYPTO` guard there** — see `../IOS-APP.md`. |
| `verify/verify.gd` | Drives both arena clients against a fake server. Needs Godot. |
| `verify/chiki-ios.test.mjs` | Drives `realm/chiki-ios.js` in a stubbed browser. Needs only Node. |
| `verify/loader-policy.test.mjs` | Tripwire: fails if `realm/index.html` loses the policy wiring — which a re-export silently does. |

## Integration, in order

1. Add the route names to the allowlist (§1). Nothing else works before this.
2. Drop `ChikiseumRehearsalLobby.gd` in and call it where the lobby list is built. Practice
   works immediately — no wallet, no chain, no risk. **Ship this first and on its own.**
3. Read `window.CHIK_FEATURES` (§5) and gate the existing money UI on it. **Ship this second:**
   it is what actually removes the Trading Post from the app's screen, and it is additive on the
   web, where every flag reads the same as today.
4. Add `ChikiseumSeasonClient.gd` + `ChikiseumSeasonPanel.gd` and open the season panel from the
   Chikiseum gate when `pvp_mode == "season"`. Needs the backend routes first.
5. Copy `chikiseum-wager-bridge.js` into `realm/` and add one `<script>` tag to
   `realm/index.html`, **inside the `if (!window.CHIK_NO_CRYPTO)` guard** the other two bridges
   already sit behind. Note: promoting a new export overwrites `realm/index.html`, so this tag
   and the whole policy wiring have to be re-applied — `node verify/loader-policy.test.mjs`
   fails until they are.
6. Add `ChikiseumWagerClient.gd` + `ChikiseumWagerPanel.gd`, open the panel from the Chikiseum
   gate next to the Cup, on the web only.
7. Fix the six "no wagering" strings — against the feature flag, not unconditionally (§3).

## The contract these are written against

Full detail in the backend repo's `CHIKISEUM-WAGERS.md`. The short version:

- All six routes are POST, JSON, under `/chikiseum/live/v1/`, and carry the same four auth
  fields as every other arena command (`wallet`, `mktToken`, `sessionId`, `sessionEpoch`), and
  require an admitted fighter (call `session` first).
- A deposit is a plain SOL transfer to `deposit_to` carrying an SPL Memo instruction with the
  exact string the server returns as `wager.you.memo`. The server credits it only if the
  player's wallet signed, the treasury gained the stake, the memo names that wager and side,
  and the signature has never been used before.
- Caps are server-side (0.001–0.05 SOL, 0.25 SOL per wallet per day by default). Do not
  duplicate them in the client as truth — read them from `health().wagers` and show them.

The season routes follow the same four rules — POST, JSON, under `/chikiseum/live/v1/`, the same
four auth fields, an admitted fighter — and add none of their own, because they carry no money.
Their full shapes are in [`../IOS-APP.md`](../IOS-APP.md); `ChikiseumSeasonClient.gd` is written
against them and `verify/verify.gd` pins them.

## Verifying without a Godot build

`https://chikimonsters.com/arena/` is a plain web client that drives these exact routes.
Anything it can do, the contract supports; if something misbehaves there, it is a backend
problem, not a client one. It now drives the season routes too, and `?nocrypto=1` hides the
wager section so you see exactly the surface the iOS app has.
