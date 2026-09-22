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
| Chikiseum PvP vs real players | **yes** | the shipped Chikiseum, unchanged — it is already stake-free |
| AI practice | **yes** | no wallet, no chain, no risk |
| Hatching, eggs, the ChikiDex | **yes** | syncs both ways with the website |
| Campaign / quests | **yes** | the $CHIKI chapter payout is claimed on the website |
| The cloud save | **yes** | the same one the website reads |
| Wallet connect, signatures | no | there is no provider on the device |
| Trading Post ($CHIKI player market) | no | website |
| Magic Eden marketplace | no | website |
| SOL wagers on PvP | no | there were never any — the live client rejects any response that is not `currency: "NONE"` |
| Buying $CHIKI | no | no purchase surface of any kind |
| The 500k token gate | client says no | **undecided server-side** — see the open decision under App Store review |

---

## Two ways in, and a one-way door between them

The app has no wallet and never will. That used to mean there was exactly one way to have an
account — pair one you already owned — and it made the app's first screen an instruction to go and
get a crypto wallet somewhere else. Almost nobody who downloads a monster-collecting game from the
App Store owns one, and asking them to is both a dead end for the player and a guideline 3.1.1
problem for the build.

So there are two, and the 500,000 $CHIKI entry gate is off in the app for both.

| | **Create** | **Pair** |
| --- | --- | --- |
| Who it is for | a player with no wallet, which is most of them | a player who already plays on the website |
| Where it happens | on the phone, one tap, nothing else needed | website mints a code, player types it in the app |
| The account's address | off-curve — see below | their real Phantom wallet |
| Can play, gather, hatch, save, PvP | yes | yes |
| Can sell | **no, and cannot be made to** | not from the app; on the website, yes |
| Route | `POST /account/new` | `POST /link/new` → `POST /link/redeem` |

**Bind** is the door between them, and it only opens one way: the app mints a claim code
(`POST /account/claim`), the player types it on `chikimonsters.com/link/` while signed in with
Phantom, and `POST /link/bind` moves the account — profile, creatures, quest pouch, device
credentials — onto that wallet. That is the only way an app-made account ever gains the ability to
sell, which is exactly the rule: **play on an app account, sell with Phantom.**

### What an app-made account's address actually is

Every table, map, socket, cloud save and compiled-GDScript call site in this game is keyed by a
base58 Solana address, and `/verify` refuses anything `new PublicKey()` will not parse. The pack is
compiled bytecode that cannot be rebuilt from source here, so "give app accounts a different kind of
id" was never an option.

So an app-made account **is** given an address: 32 random bytes that land **off** the Ed25519 curve.

* It parses as a `PublicKey`, so every one of those call sites works unchanged.
* **No private key for it can exist.** Not lost, not escrowed, not "discarded by the server" —
  mathematically absent, the same reason a PDA cannot sign.
* So the server can tell an app account from a real wallet **from the address alone**. No database
  lookup, no flag to fall out of sync, nothing a stale token or a dropped row can defeat. Every
  wallet a player can actually sign with is on-curve — measured, 1000 out of 1000 generated
  keypairs — so there are no false positives.

That is what `isWalletless()` in `server.js` is, and it is why "this account cannot sell" is a proof
rather than a promise.

**The price, stated plainly:** an app-made account cannot receive anything on-chain, because nobody
— including us — can ever spend from it. Sending it SOL or minting it an NFT would destroy the
asset. `unpayable()` guards all four paths that broadcast a transaction naming a player's address
(`/claim`, `sendChikiRaw`, `nftCoreCreate`, and the quest and winner payouts), and
`NO_WALLET_DENY_PATH` refuses the routes that compose them. A quest reward earned before there was a
wallet is **held**, not cleared, and the bind carries it across.

**And the other price:** the credential on the phone is the only way into an app-made account. There
is no email, no password and no recovery — lose the phone and it is gone. Binding a wallet is the
recovery story, and the app says so where it matters.

## How a paired account gets there: Realm Link

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

## Chikiseum PvP without a stake — already true in the shipped build

**This section used to describe a "season match" that had to be built. It does not have to be
built.** Recovering the Godot project (`godot-patch/RECOVERY.md`) showed the shipped Chikiseum is
already a server-hosted, stake-free match, and that no wager system exists in the pack to suspend.

`ChikiseumLiveClient.gd` does not merely avoid stakes — it **refuses a server that offers one**:

```gdscript
static func live_contract(data: Dictionary) -> bool:
	return data.get("mode") == "live" and data.get("currency") == "NONE" \
		and data.get("real_sol_enabled") == false and data.get("inventory_verified") == true
```

Every response is checked against it, and a response that fails is discarded with an error rather
than played. Practice mode is `currency: "TEST_CREDITS"`, capped at 1000. Searching all 128 scripts
for "wager" returns **UI copy only** — *"No wagering"*, *"no real SOL"*, *"Online duels have no
wagering."* There is no wager route, no stake field on a live request, and no SOL anywhere in the
arena.

So what the app needs from PvP is what the game already does:

| | what ships today |
|---|---|
| enter | the Chikiseum admits a verified **owned** Chikimon; challenge a player or queue |
| stake | none — the client rejects any response that says otherwise |
| pairing | the server queues, pairs and runs the match |
| prize | in-game, on the account |
| currency | `"NONE"`, server-asserted and client-verified |

The one requirement this puts on the app is **authentication**, not payment. `_auth_fields()` needs
`signed_in == true` plus a non-empty `wallet`, `mktToken`, `sessionId` and `sessionEpoch` — all of
which come from the server's `/verify` response (`signed_in = bool(j.get("signedIn", false))`), not
from a wallet extension. That is exactly what Realm Link supplies, which is why PvP works in the
app with no provider present. See the `/verify` contract below.

`godot-patch/ChikiseumSeasonClient.gd` and `ChikiseumSeasonPanel.gd` remain in the tree as a record
of the design, but **nothing needs them** and they should not be dropped into the project.

---

## What is enforced where

This matters more than it looks, because the pack ships as compiled bytecode and **no rebuilt pack
is available**. The project itself has since been recovered (`godot-patch/RECOVERY.md`), but
re-exporting it needs a custom Godot web export template that does not exist as a download, so
nothing inside the pack can be changed today. We cannot delete the Trading Post button — so the
guarantee is not "the button is hidden", it is "the button cannot do anything".

Be clear-eyed about the limit of that: **it is a guarantee about capability, not about what is on
screen.** A player can still walk to the Trading Post and open a marketplace with a `🪄 Magic Eden`
tab. `APPSTORE.md` treats that as a submission blocker, because guideline 3.1.1 is about what an
app presents.

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
| **no selling, listing, bidding or order-filling** | `/market/op` — the single route behind every Trading Post write — plus the Magic Eden writes, refused by name. **A listing is not a transaction**: `Market.gd` authenticates it with `{wallet, mktToken}` and no signature, and the app has a valid `mktToken`, so the refusal stubs never covered this | no |
| no entering the Chikoria Cup | `/cup/register` and `/cup/ready` refused — the Cup pays a real SOL prize pool, and entry is free, which makes it a prize contest | no |
| reads are deliberately left open | browsing prices moves no value, and `/nft/market/mine` is how the client learns an asset is escrowed — blocking it would show an escrowed chikimon as available | no |
| no chain traffic at all | `fetch` / `XHR` / `WebSocket` / `EventSource` / **`navigator.sendBeacon`** refuse every host but this origin and the backend | no |
| no SOL wagers | nothing to refuse — the pack has no wager route, and the live client rejects any response that is not `currency: "NONE"` (the by-name refusal is kept as a belt-and-braces measure) | no |
| **nothing tells the player where to get a wallet** | `__chikiPkErr` is owned by the loader, so `Chain.gd`'s *"Phantom not found — get it free at phantom.app"* is replaced before the pack can show it | no |
| **no chat, whispers or player messages** | refused by name. `Chat.gd` calls exactly two endpoints — `/world/chat` and **`/world/dm`**, the second carrying both whispers and party chat — plus `/chat*` on any other surface. Chat is plain HTTP; the WebSocket carries only `/world/move`, so movement is untouched | no |
| no navigation out of the realm | `window.open`, anchor clicks and form posts are guarded; **same-origin `/arena/` and `/link/` are refused too** | no |
| no token gate, no payout promises | the `$CHIKI` and `REWARDS` tabs are removed; the WELCOME, HOW TO PLAY, ROLES and EVERFLAME ISLE copy is rewritten | no |
| the in-game news feed does not advertise markets | `updates.json` is filtered at the fetch layer — 38 of 169 entries dropped | no |
| **the Trading Post and Magic Eden UI are not drawn at all** | the pack itself must stop drawing them | **yes** |
| **the Cup stops advertising real SOL** | static labels in `Chikiseum.gd` — *"champions win real SOL"*, *"Pool of 4 SOL"* — drawn regardless of server data | **yes** |

The last two rows are the outstanding pieces, and they are worse than "not tidy". The pack does
**not** read `window.CHIK_FEATURES` — confirmed by searching all 128 scripts, which return nothing
for `CHIK_FEATURES`, `CHIK_NO_CRYPTO`, `CHIK_IOS_APP` or `CHIK_HD`. The only window flag the pack
reads is `CHIK_PHONE` / `CHIK_TABLET`. So the flags in §2 of `chiki-ios.js` are advisory exactly as
that file says, and making the pack act on them is a rebuild.

Which is the hard part: `realm/index.wasm` is a **custom Godot 4.6 build with the `godot_voxel`
module compiled in**, and no prebuilt web export template with that module exists to download.
`godot-patch/RECOVERY.md` has the proof and the build recipe.

The GDScript change those two rows need is already written and verified —
`godot-patch/apply-ios-pack-patch.py`, applied to the recovered project and parse-checked against
stock Godot 4.6. It adds the `CHIK_FEATURES` reader, makes `open_market()` refuse, and drops the
Cup tab. It is waiting on nothing but a web export template.

The refusal stubs matter as much as the removals. The pack polls `__chikiBuyDone` /
`__chikiMeDone` after a purchase, so an *absent* function leaves a "purchasing…" modal up
forever — the one failure a player cannot get out of. The stubs answer immediately, in the exact
poll shape the pack already reads, with a code (`no_wallet`) the pack already branches on.

### Turning the policy on

`realm/chiki-ios.js` decides at parse time:

- `window.CHIK_IOS_APP` — injected by the shell's `WKUserScript` at document start. Already used
  by the loader for its phone special-cases, so nothing new is needed on the native side.
- `?nocrypto=1` — reviews the same policy in an ordinary browser. It deliberately does **not**
  set `CHIK_IOS_APP`, because that flag also drives the loader's phone special-cases.

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
  keychain:   true,        // "I hold the credential" — no link data is written to localStorage
  deviceId:   "…",         // from the Keychain. MUST be stable: the token is bound to it
  metered:    false,       // NWPathMonitor isExpensive/isConstrained. The page CANNOT see this:
                           // WebKit implements no Network Information API, so navigator.connection
                           // is undefined on iOS. A true here takes the 174MB pack, not the 313MB one
  hd:         false,       // may this device take the 313MB HD pack? MEASURED ON A REAL iPhone:
                           // it runs out of memory. Default false; grant it only from
                           // ProcessInfo.physicalMemory — there is no navigator.deviceMemory in
                           // WebKit, so the page cannot decide this either. Literal true only
  locale:     "ja-JP",     // device language; the in-game switcher lives inside the compiled pack
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

**A separate global, not a member of `CHIK_LINK`:** `window.CHIK_LINK_CONFIG({paused, message,
min_shell})`. It only *reports* — it announces `paused` / `stale-shell` and fetches nothing. So the
kill switch does not exist until the **shell** fetches a config document from an allowed host and
calls this itself. Budget for that; do not assume `/verify` drives it.

**3. Handle every message.** The page posts to `webkit.messageHandlers.chikiLink` (and fires a
`chiki-link` DOM event). **`persist` is the one the shell must not ignore** — it is the only way
the shell ever obtains a token, and the earlier spec told the shell to store one without providing
it.

| `kind` | payload | what the shell does |
|---|---|---|
| `ready` | `{linked, wallet, deviceId, custody}` | `linked: false` → show the pairing screen |
| `progress` | `{percent, note, metered}` | show it — a cold boot is minutes of black box otherwise |
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
(SharedArrayBuffer/threads). It is landscape-only on phones — the existing
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
  cap on wallets per device. No such cap exists today.

Decide this before writing the review notes, because one of the five bullets above depends on it.

---

## Backend work this needs

**Status: written, tested and pushed** — `gtjvv976mb-netizen/backend`, branch
`claude/vigilant-clarke-bpkqwt`, in `realm-link.js` plus a small amount of wiring in `server.js`.
`realm-link.test.mjs` boots the real server and drives the whole flow with genuine Ed25519
sign-ins: 50 checks. It is not live until that branch is merged and Render redeploys.

The one thing it deliberately does **not** do is execute an account deletion — see the note at the
end of this section.

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

**`POST /link/delete_account`** — the App Store requires an in-app account-deletion path
(5.1.1(v)), and the app calls this. It is the hardest route here, because a Chikoria account *is* a
wallet and the app deliberately cannot prove ownership of one.

```jsonc
// →  {wallet, device_id, client: "ios-app"}     // authorised by the device's link token
// ←  {accepted: true, completes_at?: "…"}
```

A link token authorises play, so it must **not** be enough to destroy an account on its own. Pick
one and write it down:

- **Confirm out of band** — accept the request, email or in-game-notify the account, and require a
  confirmation from the website (where the wallet is) before anything is deleted; or
- **Delay and allow cancellation** — accept, schedule deletion some days out, and cancel it if the
  wallet signs in on the website meanwhile.

Either satisfies the guideline (the *request* must be possible in-app; the deletion itself may be
confirmed elsewhere) without letting a stolen phone erase an account. What is not acceptable is the
app having no path at all, which is where it stands today.

### The season match — not needed, and not to be built

This section used to specify four backend routes (`season_board`, `season_queue`, `season_state`,
`season_claim`). **Do not build them.** They were designed to replace a SOL wager system that,
as the recovered source shows, does not exist: the shipped Chikiseum is already a server-hosted
match that the client refuses to play unless the server asserts `currency: "NONE"` and
`real_sol_enabled: false`. See the PvP section above and `godot-patch/RECOVERY.md`.

The full route spec is in this file's git history if a genuinely separate ranked season is ever
wanted as its own feature. It is not a prerequisite for the app.

What the app *does* need from the backend for PvP is nothing new at all — only that `/verify`
answers a link-token request the way it answers a signed one, because that is what `Chain.gd`
turns into an authenticated session:

```gdscript
signed_in = bool(j.get("signedIn", false))
```

and `ChikiseumLiveClient._auth_fields()` then requires a non-empty `wallet`, `mktToken`,
`sessionId` and an integer `sessionEpoch` — all four from that same response. Get `/verify` right
and the Chikiseum works in the app with no wallet provider present.

### One rule across all of it

**A link token must never be accepted by a route that moves value.** Wagers, Trading Post sales,
marketplace listings, withdrawals and payout claims stay signature-only. The device policy in
`realm/chiki-ios.js` is a client and a client can be bypassed by someone who is not using our
client; the server is what makes "the app cannot sell" true rather than merely tidy.

**This is now enforced.** A link session's market token is drawn from a separate pool, keyed by
token rather than by wallet — so a player signed in on the web and paired on a phone stay
distinguishable even for the same wallet at the same moment. One middleware refuses that fact on
`/market/op`, `/market/buy-onchain`, `/market/order-pay`, the four `/nft/market/*` writes,
`/meme/buy`, `/claim`, the quest payouts and `/cup/register` + `/cup/ready`. Earning is untouched
on purpose: minting, hatching, gathering, node claims and profile saves all still work from the
app, and the test asserts both halves.

---

## Release order — read this before shipping anything

The order is load-bearing in both directions, and nothing else in the repo states it. Publish the
website half early and live players get a pairing page against a 404. Ship the binary before the
pack and the app advertises PvP it cannot reach.

**The app's Chikiseum works on the pack that is live today.** This paragraph used to say the
opposite — that the compiled client's own eleven-route `fetch` allowlist would refuse the season
routes, so PvP needed a Godot export. Reading the recovered source corrected both halves: there
are no season routes to allow, and that guard is not a site-wide allowlist anyway. It judges only
requests carrying an `X-Chikiseum-Live-Owner` header and passes everything else through — it is
request de-duplication and hardening for the live client, not a gate on the app.

What PvP does depend on is `/verify` returning a usable session for a link token, which is the same
dependency pairing already has.

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
| `arena/index.html` | the test client; `?nocrypto=1` shows the app's surface |
| `godot-patch/RECOVERY.md` | how the Godot project was recovered from the published pack, and why the pack cannot be rebuilt without a custom engine |
| `godot-patch/verify/chiki-ios.test.mjs` | 175 checks over the policy layer — `node` only, no Godot |
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
