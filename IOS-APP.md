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
| Buying $CHIKI | no | no purchase surface of any kind |
| The 500k token gate | client says no | **undecided server-side** — see the open decision under App Store review |

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

The pack is untouched. A request carrying a real signature is left completely alone, and the token
is only ever attached to `/verify` on an allowed origin.

### Who holds the credential

The first version of this wrote the tokens to `localStorage` and claimed the pack could not read
them. **That was wrong twice over**: `localStorage` is readable by anything in this JS context,
`JavaScriptBridge.eval` included, and a WKWebView data purge — the exact event the Keychain exists
to survive — takes it away. Ownership is now inverted:

- **In the app**, when the shell sets `CHIK_IOS_APP.keychain === true`, tokens live **only** in a
  closure and in the shell's Keychain. Nothing is written to `localStorage`. Every change is pushed
  to the shell as a `persist` message for it to write.
- **Without a shell** (a browser on `?nocrypto=1`, or a shell that does not set the flag)
  `localStorage` is the fallback, because the alternative is a link that does not survive a reload.

Be honest about the limit: this reduces exposure, it does not create isolation. Any script in this
realm — the pack included — can hook `CHIK_LINK`. **The property that actually protects the player
is server-side**: a link token authorises play and must be refused by every route that moves value.

### What a rejected token does

A token can be revoked, expire, or belong to an account the server stops admitting. Previously all
three produced a dead screen that survived every relaunch. Now a `/verify` carrying our token is
watched: a 4xx, or a 200 without `signedIn`, drops the credential, clears the resume, tells the
shell (`link-rejected`) and leaves the device in the honest "not linked" state. A **5xx does not** —
a backend having a bad day must not unlink the player.

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
| no navigation out of the realm | `window.open`, anchor clicks and form posts are guarded; **same-origin `/arena/` and `/link/` are refused too** | no |
| no token gate, no payout promises | the `$CHIKI` and `REWARDS` tabs are removed; the WELCOME, HOW TO PLAY, ROLES and EVERFLAME ISLE copy is rewritten | no |
| the in-game news feed does not advertise markets | `updates.json` is filtered at the fetch layer — 38 of 169 entries dropped | no |
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

**1. Inject everything at document start.** A `WKUserScript` with
`injectionTime: .atDocumentStart`, `forMainFrameOnly: true`. `chiki-ios.js` reads this object as it
parses, so it must be complete before the first script runs:

```js
window.CHIK_IOS_APP = {
  deviceName: "iPhone",
  version:    "1.0.0",     // compared against MIN_SHELL; too old → a "stale-shell" message
  keychain:   true,        // "I hold the credential" — turns OFF all localStorage writes
  deviceId:   "…",         // from the Keychain. MUST be stable: the token is bound to it
  active:     "…",         // which wallet to play
  accounts:   [ { wallet: "…", token: "…", label: "…", linkedAt: 0 } ]
};
```

`chiki-ios.js` takes the credentials and then **deletes `accounts` and `linkToken` from the
object**, so the pack cannot simply read the global. Setting `keychain: true` without supplying
`deviceId` is a bug: a regenerated id makes the server reject a token it issued.

**2. Drive pairing through `window.CHIK_LINK`.**

| call | returns |
|---|---|
| `CHIK_LINK.status()` | `{linked, wallet, deviceId, accounts:[{wallet,label,linkedAt}]}` — never a token |
| `CHIK_LINK.redeem(code)` | Promise → `{wallet}`; rejects with a message worth showing |
| `CHIK_LINK.use(wallet)` | switch account (reloads); `false` if not linked |
| `CHIK_LINK.forget(wallet)` / `forgetAll()` | unlink here and revoke server-side |
| `CHIK_LINK.setToken(wallet, token, label)` | late restore, if the Keychain read missed injection |
| `CHIK_LINK.deviceId()` | the id the token is bound to — store it beside the token |
| `CHIK_LINK.features()` | the `CHIK_FEATURES` policy object |
| `CHIK_LINK_CONFIG({paused, message, min_shell})` | server-driven pause / minimum-version bump |

**3. Handle every message.** The page posts to `webkit.messageHandlers.chikiLink` (and fires a
`chiki-link` DOM event). **`persist` is the one the shell must not ignore** — it is the only way
the shell ever obtains a token, and the earlier spec told the shell to store one without providing
it.

| `kind` | payload | what the shell does |
|---|---|---|
| `ready` | `{linked, wallet, deviceId, custody}` | `linked: false` → show the pairing screen |
| `persist` | `{deviceId, active, accounts:[{wallet,token,label,linkedAt}]}` | **write to the Keychain** (replace wholesale; an empty `accounts` means erase) |
| `linked` | `{wallet}` | dismiss pairing, show the game |
| `switched` | `{wallet}` | the page is reloading with another account |
| `unlinked` | `{wallet?}` | back to pairing |
| `link-rejected` | `{wallet, reason}` | the token is dead: clear the Keychain, show pairing with a reason |
| `stale-shell` | `{version, minimum}` | block with "update the app" |
| `paused` | `{message}` | show maintenance |
| `external-link` | `{url}` | open in Safari (`UIApplication.shared.open`) — never in-app |

**3b. Refuse navigation out of the realm.** The web layer wraps `window.open`, anchor clicks and
form posts, but `location.href` assignment cannot be intercepted from script — and the engine hands
the pack a navigation primitive directly (`realm/index.js` defines `_godot_js_os_shell_open` as a
bare `window.open`). So the shell is the backstop:

- `WKNavigationDelegate.decidePolicyFor`: `.cancel` any top-level navigation whose URL is not under
  `https://chikimonsters.com/realm/`. **Same-origin is not sufficient** — `/arena/` is the full SOL
  wager client and `/link/` carries a Phantom sign-in, and neither loads the policy layer.
- `WKUIDelegate.createWebViewWith`: return `nil`, so no popup can open a window.

**4. Configure the WebView for the realm.** It needs a secure context and cross-origin isolation
(SharedArrayBuffer/threads). It is landscape-only on phones and runs the HD pack — the existing
loader comments in `realm/index.html` explain the memory budget, the DPR cap and the OOM net, all
of which already special-case the app and should not be changed.

**5. Ship nothing that can reach a wallet.** No wallet SDK, no deep links to `phantom://`,
`solflare://` or a marketplace, no in-app browser that can reach one, no `SFSafariViewController`
opening an exchange. The web policy is thorough, but it cannot police what the native side does
on its own.

### App Store review

The crypto question is the one this design answers well. It is **not** the one most likely to
reject the app. Three areas, in order of real risk:

**1. Guideline 4.2, minimum functionality.** A binary whose whole function is to display a website
is the textbook rejection, and as specified the shell is exactly that. This is decided before the
shell is built, not at submission. The native scope below is the minimum that makes the app a real
app rather than a wrapper: pairing, account management and deletion, settings and support, the
download/loading experience, offline and failure states, and the navigation policy. Build them
natively; do not put them in the web layer.

**2. Guideline 3.1.1, steering.** The app earns real assets and the player sells them elsewhere, so
copy that names where is a steering risk. The refusal string has been changed from *"Selling and
trading happen on chikimonsters.com"* to **"Selling and trading are not available in the app.
Everything you earn here is yours to keep."** — it states the fact and offers no outside route. The
loading-screen copy was changed the same way. Anti-steering rules have moved (notably in the US
since 2025), so **check the current text of 3.1.1 and 3.1.3 before submitting** rather than trusting
this paragraph.

**3. Guideline 3.1.5(b) / 3.1.1, crypto and NFTs.** The app is not a wallet and contains no wallet.
It never asks for a key, a seed phrase or a signature, and carries no code that can construct a
transaction. Nothing is bought, sold, traded or staked. PvP has no stake and no prize pool. Pairing
is a code the player types, not a wallet sign-in. Nothing in the app is gated on holding a
cryptocurrency — **but see the open decision below, because that claim is currently not verified
server-side.**

Also required, and not yet built anywhere:

- **Account deletion (5.1.1(v)).** `forget()` and `forgetAll()` only unlink a *device*. An app with
  account creation must offer account deletion in-app. Decide what that means here — the account is
  a wallet on a server the app cannot authenticate to as its owner — and build it.
- **Privacy manifest** (`PrivacyInfo.xcprivacy`) and the App Privacy answers. These have to describe
  whatever telemetry ends up existing, so decide telemetry first.
- **Age rating**, given the memecoin association and randomized reward rolls.
- **Export compliance** (`ITSAppUsesNonExemptEncryption`).

#### An open product decision that blocks the review notes

**Does an app player need to hold 500k $CHIKI?** The website gate is entry-level
(`realm/index.html`: "500,000 $CHIKI to enter the realm"). The app switches the gate off on the
*client* and the review note above asserts the app is not gated — but the gate is enforced
**server-side against the wallet**, and none of the link routes below say whether a link-token
session is admitted for a wallet under the threshold. Both answers need work:

- If the server still gates: every new player and every App Review tester dead-ends at the door,
  with no copy explaining why (the panel that explained it is removed on the app). Needs a refusal
  code and a pairing-screen message.
- If it does not: the app is a free, App-Store-distributed entrance to a token-gated economy whose
  rewards are real assets. Needs per-account earning caps, a cap on linked devices per wallet, and a
  cap on wallets per device. Only the season match has a cap today.

Decide this before writing the review notes, because one of the five bullets above depends on it.

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

## Release order — read this before shipping anything

The order is load-bearing in both directions, and nothing else in the repo states it. Publish the
website half early and live players get a pairing page against a 404. Ship the binary before the
pack and the app advertises PvP it cannot reach.

**The app's Chikiseum is unreachable on the pack that is live today**, and not only because the
backend routes are missing. The compiled client installs *its own* `window.fetch` guard with a
hardcoded eleven-route allowlist (`godot-patch/README.md` §1). `season_board`, `season_queue`,
`season_state` and `season_claim` are not in it, so a correct backend is still refused **by the game
itself**. That takes a Godot export to fix, and promoting an export overwrites `realm/index.html`
and needs the whole policy wiring re-applied.

So, in order:

1. **Decide the 500k gate question** above. It changes the backend and the pairing copy.
2. **Backend**: the link routes, then the season routes. `/link/` and `/arena/` both exercise them.
3. **Publish `link/`** only once `/link/new` answers. Until then it correctly says the backend does
   not offer Realm Link yet, which is honest but not something to put in front of players.
4. **One Godot export** carrying, together: the four season route names added to the pack's own
   allowlist (step 1 of `godot-patch/README.md`, not step 4), the `CHIK_FEATURES` read, the season
   panel, and the AI practice lobby.
5. **Re-apply the loader policy** to the overwritten `realm/index.html` and get both harnesses green
   — `node godot-patch/verify/loader-policy.test.mjs` fails until they are.
6. **Build the shell**, TestFlight it on a real device, then submit.

**If the pack is not ready when the binary is**, do not ship the promise: cut the season-match line
from the app copy and turn `pvp_mode` off, rather than shipping a Chikiseum that is a dead room.

## Files in this repo

| file | what it does |
|---|---|
| `realm/chiki-ios.js` | the whole policy: mode, `CHIK_FEATURES`, the network/wallet/bridge lockdown, Realm Link |
| `realm/index.html` | loads it **first**, and gates `solana-web3.js`, `__chikiBuy`, the Magic Eden bridge and the Phantom stay-signed-in bridge behind `CHIK_NO_CRYPTO`; rewrites the loading-screen copy |
| `link/index.html` | the website page where a player mints a pairing code and manages linked devices |
| `arena/index.html` | the test client; now drives the season routes, and `?nocrypto=1` shows the app's surface |
| `godot-patch/ChikiseumSeason*.gd` | the season client and panel, ready to drop into the Godot project |
| `godot-patch/verify/chiki-ios.test.mjs` | 118 checks over the policy layer — `node` only, no Godot |
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
