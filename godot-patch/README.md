# Getting the AI practice opponent and SOL wagers into the game

The backend has both. The shipped game has neither, and one of the two blockers is not
obvious — so this folder is the exact work, written against the live API, ready to drop into
the Godot project.

**The Godot project is not in any repository I can reach.** Eleven repos, nine branches,
zero `.gd` / `.tscn` / `project.godot`. The game ships as compiled `.gdc` bytecode. Everything
here was written by reading that bytecode's string tables out of the live 313 MB pack, so it
matches the client's real conventions (`auth_fields`, `attach_live_client`, `command_failed`,
`roster_received`, …).

**What is verified:** all three scripts compile under real Godot 4.6.stable, and the wager
client was driven end to end against a fake server — post, deposit, match, and a refusal —
with 23 checks passing. Run it yourself:

```sh
cd verify && cp ../*.gd .
godot --headless --path . --import
godot --headless --path . --script verify.gd     # exits non-zero on any failure
```

**What is not verified:** integration with the actual game — its scene tree, its skin, its gate
— because that project is not here. The UI in `ChikiseumWagerPanel.gd` builds plain Godot
controls so it runs standalone; it is meant to be reskinned, and the behaviour underneath it is
what these tests pin.

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

Eleven routes. **Adding wager UI alone will not work** — the guard will block the calls. Add
the six wager routes to that array:

```js
const routes = ['roster','session','lobby','queue','challenge','accept','ready','state','cast','move','cancel',
                'wager_board','wager_mine','wager_post','wager_accept','wager_withdraw','wager_deposit'];
```

That is the whole change to the transport. Everything else is additive.

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

---

## Files here

| file | what it is |
|---|---|
| `ChikiseumWagerClient.gd` | Speaks the six wager routes. Transport-agnostic: bind it to the existing client's command function so it inherits auth and the fetch guard. |
| `ChikiseumWagerPanel.gd` | The pill: board, post, accept, pay, withdraw, live status. |
| `ChikiseumRehearsalLobby.gd` | Finds the practice opponent in a lobby payload and starts it correctly. |
| `chikiseum-wager-bridge.js` | Phantom deposit for the web export: builds the memo-tagged transfer, signs, returns the signature. Goes in `realm/` and is referenced from `realm/index.html`. |

## Integration, in order

1. Add the six route names to the allowlist (§1). Nothing else works before this.
2. Drop `ChikiseumRehearsalLobby.gd` in and call it where the lobby list is built. Practice
   works immediately — no wallet, no chain, no risk. **Ship this first and on its own.**
3. Copy `chikiseum-wager-bridge.js` into `realm/` and add one `<script>` tag to
   `realm/index.html`. Note: promoting a new export overwrites `realm/index.html`, so this tag
   has to be re-applied or moved into the export template.
4. Add `ChikiseumWagerClient.gd` + `ChikiseumWagerPanel.gd`, open the panel from the Chikiseum
   gate next to the Cup.
5. Fix the six "no wagering" strings.

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

## Verifying without a Godot build

`https://chikimonsters.com/arena/` is a plain web client that drives these exact routes.
Anything it can do, the contract supports; if something misbehaves there, it is a backend
problem, not a client one.
