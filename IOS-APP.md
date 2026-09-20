# The Chikoria iOS app — a gameplay-only client on the same account

The app is the realm with the money taken out of it: gathering, the Wicked Temple, Chikiseum PvP,
the campaign, the whole island — on the player's **real Chikoria account**, with no wallet on the
device and no way to buy, sell, trade or stake anything.

Two sentences carry most of the design:

> **Everything you earn in the app is really yours.** Fish, eggs, chikimon and resources won in
> the app are credited to the linked account exactly as the website credits them — on-chain where
> the asset is on-chain — and they are in the satchel next time the player opens
> chikimonsters.com.
>
> **Selling and trading only happen on the website.** The Trading Post and the marketplace are
> website surfaces. The app carries no code that can build, sign or send a transaction.

Earning here, selling there. One account, one inventory, two different surfaces.

---

## What the app is, feature by feature

| | in the app | notes |
|---|---|---|
| Gathering, crafting, cooking, fishing | **yes** | the core loop, unchanged |
| Wicked Temple | **yes** | five sanctums, the Treasure Vault roll, unchanged |
| Chikiseum PvP vs real players | **yes** | via the **season match** — see below |
| AI practice | **yes** | no wallet, no chain, no risk |
| Hatching, eggs, the ChikiDex | **yes** | syncs both ways with the website |
| Campaign / quests | **yes** | the $CHIKI chapter payout is claimed on the website |
| The cloud save | **yes** | the same one the website reads |
| Wallet connect, signatures | no | there is no provider on the device |
| Trading Post ($CHIKI player market) | no | website |
| Magic Eden marketplace | no | website |
| SOL wagers on PvP | no | replaced by the season match |
| Buying $CHIKI, the 500k token gate | no | the app is not gated on holding a token |

---

## How the account gets there: Realm Link

The app has no wallet, so identity is moved off the device.

```
chikimonsters.com/link/            the app
  │ player signs in with Phantom     │
  │ POST /link/new         ────────► │
  │ ◄──── code "K4T9 2XPD"           │
  │                                  │ player types the code
  │                          POST /link/redeem {code, device_id}
  │                                  │ ◄──── {wallet, linkToken}
  │                                  │
  │                          every launch: POST /verify {wallet, linkToken, device_id}
  │                                  │ ◄──── {signedIn, mktToken, sessionId, sessionEpoch}
```

`linkToken` is **this device's** credential for that account. It is not a key: it cannot sign,
spend, trade or move anything on-chain. It authorises exactly what a signature authorises today —
playing that account — and the player can revoke it from the website at any time.

**Multiple wallets, one device.** A player may link several accounts and switch between them in
the app; each keeps its own token. Switching reloads the page, which is the path the website's
wallet-switch already takes.

### Why it needs no change to the compiled game

`Chain.gd` already knows how to resume a session it did not create: `sessionStorage.chikResume`
`{a, m, s, t}`, posted to `/verify`. So `realm/chiki-ios.js`:

1. seeds that resume with the wallet and a **sentinel** in the signature slot (`CHIKI-LINK-V1`),
2. intercepts the `/verify` request on its way out and swaps the sentinel for the link token.

The pack is untouched and never sees the token — it is held in a closure in the loader, not in
`sessionStorage`, not on `window`, and `CHIK_LINK.status()` does not report it. A request that
carries a real signature is left completely alone, and the token is only ever attached to
`/verify` on an allowed origin.

---

## Chikiseum PvP without a stake: the season match

Wagers are suspended in the app. The fight is kept and the money is dropped:

| | website | iOS app |
|---|---|---|
| enter | post or accept a SOL wager | press **Find a match** |
| stake | 0.001–0.05 SOL, treasury-held | nothing |
| pairing | another player accepts your wager | the server queues and pairs you |
| the fight | identical | identical |
| prize | the pot, in SOL | fantasy fish, eggs, resources — the real assets, on the account |
| what stops farming | a per-wallet daily SOL cap | a daily rewarded-match count |

The roll is the server's and is decided when the match is decided, exactly as the Wicked Temple's
wheel already works — pressing **Collect** reveals it, it does not roll it. Claiming twice, late,
or from another device returns the same items.

Client: `godot-patch/ChikiseumSeasonClient.gd` + `ChikiseumSeasonPanel.gd`.
Web reference implementation: `arena/index.html` (add `?nocrypto=1` to see the app's surface).

---

## What is enforced where

This matters more than it looks, because **the Godot project is not in any repository we can
reach** (see `godot-patch/README.md`). The pack ships as compiled bytecode. We cannot delete the
Trading Post button today — so the guarantee is not "the button is hidden", it is "the button
cannot do anything".

Every crypto capability the game has is a JavaScript function `realm/index.html` defines and the
engine calls through `JavaScriptBridge`. The loader is the only gate that capability passes
through, so a capability never defined cannot be reached by **any** build of the pack, present or
future.

| enforced by | how | needs a pack rebuild? |
|---|---|---|
| no wallet | `window.solana` / `phantom` / `solflare` / `backpack` / `ethereum` made permanently `undefined` and unwritable | no |
| no transaction can be built | `solana-web3.js` is never loaded in the app | no |
| no Trading Post purchase | `__chikiBuy` is a refusal stub; the real one is never defined | no |
| no marketplace purchase | `__chikiMeSign` is a refusal stub; `__chikiMeReady` reports no capability | no |
| no chain traffic at all | `fetch` / `XHR` / `WebSocket` refuse every host but this origin and the backend | no |
| no SOL wagers | `/chikiseum/live/v1/wager_*` refused by name | no |
| no token gate, no payout promises | the `$CHIKI` and `REWARDS` tabs are removed; the sign-in, Trading Post and campaign copy are rewritten | no |
| **the Trading Post gate is not drawn at all** | the pack reads `window.CHIK_FEATURES` | **yes** |

The last row is the only outstanding piece, and it is a feature gate, nothing more — see
`godot-patch/README.md` §5 for the four lines of GDScript. Until it ships the app is safe but not
tidy: a player can walk up to a Trading Post that then tells them trading is on the website.

The refusal stubs matter as much as the removals. The pack polls `__chikiBuyDone` /
`__chikiMeDone` after a purchase, so an *absent* function leaves a "purchasing…" modal up
forever — the one failure a player cannot get out of. The stubs answer immediately, in the exact
poll shape the pack already reads, with a code (`no_wallet`) the pack already branches on.

### Turning the policy on

`realm/chiki-ios.js` decides at parse time:

- `window.CHIK_IOS_APP` — injected by the shell's `WKUserScript` at document start. Already used
  by the loader to pick the HD pack, so nothing new is needed on the native side.
- `?nocrypto=1` — reviews the same policy in an ordinary browser. It deliberately does **not**
  set `CHIK_IOS_APP`, because that flag also selects the HD pack and would memory-kill a phone.

---

## What the native shell must do

The shell is a `WKWebView` pointed at `https://chikimonsters.com/realm/`. It is not in this repo.

**1. Inject the flag at document start.** A `WKUserScript` with
`injectionTime: .atDocumentStart`, `forMainFrameOnly: true`:

```swift
window.CHIK_IOS_APP = { deviceName: "iPhone", version: "1.0.0" };
```

If the Keychain holds a link, hand it in on the same object — `chiki-ios.js` adopts it and then
**deletes it from the object**, so the pack can never read it:

```swift
window.CHIK_IOS_APP = { deviceName: "…", wallet: "…", linkToken: "…" };
```

**2. Drive pairing through `window.CHIK_LINK`.** Every function is safe to call at any time and
none of them expose a token.

| call | returns |
|---|---|
| `CHIK_LINK.status()` | `{linked, wallet, deviceId, accounts:[{wallet,label,linkedAt}]}` |
| `CHIK_LINK.redeem(code)` | Promise → `{wallet}`; rejects with a message worth showing |
| `CHIK_LINK.use(wallet)` | switch account (reloads); `false` if not linked |
| `CHIK_LINK.forget(wallet)` / `forgetAll()` | unlink here and revoke server-side |
| `CHIK_LINK.setToken(wallet, token, label)` | restore from the Keychain |
| `CHIK_LINK.features()` | the `CHIK_FEATURES` policy object |

**3. Listen for link events.** The page posts to `webkit.messageHandlers.chikiLink` (and fires a
`chiki-link` DOM event) with `{kind: "ready"|"linked"|"switched"|"unlinked", wallet}`. On
`ready` with `linked: false`, show the pairing screen; on `linked`, persist the token to the
**Keychain** — a WKWebView data purge takes `localStorage` with it, and the Keychain is what
makes the link survive.

**4. Configure the WebView for the realm.** It needs a secure context and cross-origin isolation
(SharedArrayBuffer/threads). It is landscape-only on phones and runs the HD pack — the existing
loader comments in `realm/index.html` explain the memory budget, the DPR cap and the OOM net, all
of which already special-case the app and should not be changed.

**5. Ship nothing that can reach a wallet.** No wallet SDK, no deep links to `phantom://`,
`solflare://` or a marketplace, no in-app browser that can reach one, no `SFSafariViewController`
opening an exchange. The web policy is thorough, but it cannot police what the native side does
on its own.

### App Store review notes

- The app is not a wallet and contains no wallet. It never asks for a key, a seed phrase or a
  signature, and cannot construct a transaction.
- Nothing is bought, sold or traded in the app, and there is no external purchase flow. The
  assets a player earns are earned by playing.
- Nothing is gated on holding a cryptocurrency. The 500k $CHIKI gate is a website rule; the app
  is not gated on it.
- PvP has no stake and no prize pool. Matches are hosted by the server and pay in-game items.
- Account pairing is a code the player types, not a purchase and not a sign-in with a wallet.

---

## Backend work this needs

Nothing in the app can ship without these. None of them move money.

### Realm Link

**`POST /link/new`** — mint a pairing code. Wallet-authenticated exactly like any other route.

```jsonc
// →  {wallet, authMsg, authSig, mktToken, sessionId, sessionEpoch}
// ←  {code: "K4T92XPD", expires_at: "2026-09-20T12:10:00Z", expires_in: 600}
```

Short code, short life (≈10 min), single use, rate-limited per wallet.

**`POST /link/redeem`** — trade a code for a device credential. **Unauthenticated** — the code is
the proof, and the device has nothing else.

```jsonc
// →  {code, device_id, device_name, client: "ios-app"}
// ←  {wallet, linkToken, label?, expires_at?}
```

Burn the code on first use. Bind the token to `device_id`. A token authorises playing that
account and nothing more — it must be rejected by every route that moves value.

**`POST /verify`** — accept `linkToken` as an alternative proof.

```jsonc
// →  {wallet, linkToken, device_id, client: "ios-app"}     // instead of authMsg/authSig
// ←  {signedIn: true, mktToken, sessionId, sessionEpoch, …}   // the SAME envelope as today
```

The response shape must not change — the compiled game reads it and cannot be rebuilt cheaply.

**`POST /link/devices`** — list this wallet's linked devices (`device_id`, `device_name`,
`linked_at`, `last_seen`). Wallet-authenticated.

**`POST /link/revoke`** — kill one device's token. Accepted **either** wallet-authenticated (the
website's "Revoke" button) **or** with the token itself (the app signing itself out).

### The season match

All four are POST, JSON, under `/chikiseum/live/v1/`, carrying the same four auth fields as every
other arena command, and require an admitted fighter (`session` first).

**`season_board`**

```jsonc
{
  "season": { "id": "s3", "name": "Season 3", "ends_in": 183600, "enabled": true },
  "you":    { "rank": 41, "rating": 1180, "wins": 12, "losses": 7, "streak": 3,
              "matches_today": 4, "daily_cap": 20 },
  "rewards": {
    "win":  [ { "kind": "fantasy_fish", "id": "aurelfin", "label": "Aurelfin", "weight": 0.55 },
              { "kind": "egg", "id": "normal_egg", "label": "Chikimon Egg", "weight": 0.2 } ],
    "loss": [ { "kind": "resource", "id": "berry", "label": "Berry", "qty": 3 } ],
    "streak_bonus": [ … ]
  },
  "leaderboard": [ { "rank": 1, "handle": "Ken", "wins": 88 } ]
}
```

`weight` is optional; the client prints an odd only when the server sent one, and never
reconstructs one. `kind` is open — an unknown kind still renders by its `label`.

**`season_queue`** — `{action: "join" | "leave"}`

```jsonc
{ "queued": true,  "status": "queued", "position": 3, "eta_s": 25 }
{ "queued": false, "status": "paired", "match_id": "m77" }   // pairing can be immediate
```

**`season_state`** — poll while queued or fighting

```jsonc
{ "queued": false, "status": "decided", "reward_pending": true,
  "reward_match_id": "m77", "you": { "wins": 13, "losses": 7, "streak": 4 } }
```

`status` ∈ `idle | queued | paired | ready | active | decided | left`.

**`season_claim`** — `{match_id}`

```jsonc
{ "rewards": [ { "kind": "fantasy_fish", "id": "aurelfin", "label": "Aurelfin", "qty": 2 } ],
  "odds": { "fantasy_fish": "55%", "egg": "20%" },
  "you": { "rank": 38, "wins": 13, "losses": 7, "streak": 4 } }
```

Idempotent: the roll happened when the match was decided. Credit the items to the account the
same way the Wicked Temple's vault does — this is the same inventory, not a parallel one.

Refusal codes the client already phrases for players: `SEASON_DISABLED`, `SEASON_CLOSED`,
`NOT_ADMITTED`, `ALREADY_QUEUED`, `NOT_QUEUED`, `ACCOUNT_BUSY`, `DAILY_CAP`, `INCOMPATIBLE`,
`ALREADY_CLAIMED`, `MATCH_UNDECIDED`, `RATE_LIMIT`, `UNAVAILABLE`.

### One rule across all of it

**A link token must never be accepted by a route that moves value.** Wagers, Trading Post sales,
marketplace listings, withdrawals and payout claims stay signature-only. The device policy in
`realm/chiki-ios.js` is a client and a client can be bypassed by someone who is not using our
client; the server is what makes "the app cannot sell" true rather than merely tidy.

---

## Files in this repo

| file | what it does |
|---|---|
| `realm/chiki-ios.js` | the whole policy: mode, `CHIK_FEATURES`, the network/wallet/bridge lockdown, Realm Link |
| `realm/index.html` | loads it **first**, and gates `solana-web3.js`, `__chikiBuy`, the Magic Eden bridge and the Phantom stay-signed-in bridge behind `CHIK_NO_CRYPTO`; rewrites the loading-screen copy |
| `link/index.html` | the website page where a player mints a pairing code and manages linked devices |
| `arena/index.html` | the test client; now drives the season routes, and `?nocrypto=1` shows the app's surface |
| `godot-patch/ChikiseumSeason*.gd` | the season client and panel, ready to drop into the Godot project |
| `godot-patch/verify/chiki-ios.test.mjs` | 74 checks over the policy layer — `node` only, no Godot |
| `godot-patch/verify/loader-policy.test.mjs` | tripwire: fails if `realm/index.html` loses the wiring |
| `godot-patch/verify/verify.gd` | drives both arena clients against a fake server — needs Godot |

### Run the checks

```sh
node godot-patch/verify/chiki-ios.test.mjs
node godot-patch/verify/loader-policy.test.mjs
```

**Run `loader-policy.test.mjs` after every Godot export promotion.** Promoting an export
overwrites `realm/index.html`, and losing the policy wiring does not fail loudly — the app would
simply boot with a working Phantom bridge again. The tripwire is what makes that loud.
