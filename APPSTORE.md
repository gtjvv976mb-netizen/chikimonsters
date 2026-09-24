# App Store submission kit

Everything for App Store Connect that does not require a build. Copy the fields straight in.

**Read the next section before anything else.** This kit is complete; the app is not.

---

## Can this be submitted today? Everything that can be done without a Mac is done

Updated 2026-09-24. What is done and verified:

| Done | Evidence |
|---|---|
| Backend `/link/*` and `/account/*` routes deployed | `api.chikimonsters.com/link/new` → 401, `/link/redeem` → 400 (the routes exist and validate); backend `npm run test:link` passes |
| **Every trading surface is out of the iOS pack** | `godot-patch/apply-ios-trading-patch.py` — 165 more edits on top of the first 19, across 20 scripts, all gated on `ChikFeat` so the website is unchanged. See "The trading sweep" below |
| The rebuilt iOS pack is in `realm/` | `index.pck.ios.lite.*`, build `03a188af60`; every changed script loads from the built pack |
| **Quests are out of the app** | No Quests tab, no pinned story objective, no quest help topic or tutorial copy (`godot-patch/apply-ios-review-patch.py`, flag `quests`). Progress still counts and syncs, so the website's story is where the player left it. An app-only player is therefore never stuck at Chapter 36, "Open for Business", which requires a Trading Post listing |
| **The Meme Dynasty is out of the app, per species** | Pepe, Doge, Grumpy Cat and the rest are never drawn: not in the Chikidex, hatching, Mithra's shop, the world or the title art. A player who owns one keeps it, because the app sets it aside for the session and puts it back on every save (`verify/meme-stash.gd`: 17 checks, save signature unchanged). To bring one back, add its key to `meme_allow` in `realm/chiki-ios.js`, e.g. `meme_allow: ['doge']`. No app update is needed |
| **Account deletion is carried out** | Backend branch `claude/app-account-deletion`: an hourly sweep erases every app-made account whose deletion request is past its 24-hour undo window. That covers its save, rows, creatures and device credentials. `app-account-deletion.test.mjs` runs it end to end. It takes effect once that backend PR is merged and deployed |
| Privacy manifest matches what the app does | User ID, Device ID and Gameplay Content are declared as collected, linked to the player, for App Functionality only, and not used for tracking. §3 has the matching App Store Connect answers |
| A Mac compiles it on every change | `.github/workflows/ios-build.yml` builds the Xcode project for the simulator on a GitHub-hosted Mac whenever `ios/` changes |
| The app carries every game asset | The lite pack holds the same files as the HD pack except the soundtrack, which streams from `audio/stream-manifest.json`, and the Chikiseum gate crest. The crest was missing from the website's lite export, so `ChikiseumReferenceWorld.gd` failed to parse and the arena world could not load on a phone. `build-ios-pack.py` now adds the crest from the HD pack (`ADDED_FILES`). The *website's* `index.pck.lite.*` still lacks it, so mobile browsers have the same arena bug until that pack is re-exported |
| The app never boots a website pack | `realm/index.html` no longer falls back to the website's packs for the app, even on a network error; `loader-policy.test.mjs` pins it |
| The app's title screen shows the Chikoria key art | not the Meme Dynasty line-up (`hero.jpg`), which includes a caricature of a real person |
| Swift compile errors found by review are fixed | `Button(action.1)`, the shadowed `claim = nil`, and an iOS 17-only `Text.foregroundStyle` in a 16.0 target; `nonisolated` constants for the navigation delegate |
| iPhone-only, `LSRequiresIPhoneOS` | `TARGETED_DEVICE_FAMILY = 1`; no iPad screenshots needed for 1.0 |
| No trading language on any native screen | Pairing and Account talk about *backing up* an app-made account, not trading |
| The app's own web page | `chikimonsters.com/app/` — use it as the **Marketing URL** (§1) |
| `/link/`, `/privacy/`, `/support/` published; COOP/COEP on `/realm/` | all 200 |
| Chat refused in the app | §2; policy tests pass |
| Xcode project generated and consistent | `python3 ios/make-xcodeproj.py --check` passes |

What remains needs a Mac, an Apple Developer account, or a decision:

| Blocker | Why it blocks | Who can clear it |
|---|---|---|
| **No signed build uploaded** | The CI job proves the code compiles. The App Store build still has to be archived and signed with your team in Xcode (Product → Archive). | You, on the MacBook |
| **No screenshots or preview video** | Both must be captured from the running app. | You, once a build runs |
| **Mailboxes** | `/support/` and `/privacy/` name `support@` and `privacy@chikimonsters.com`. The domain has Google MX records; make sure both addresses exist and are read. | You |
| **Privacy page says "Draft — not yet reviewed by a lawyer"** | A reviewer opens that URL. | Legal review, then remove the banner |
| **Merge and deploy the backend deletion PR** | App-made accounts are erased by the new sweep once it is deployed. A *wallet* account (made on the website, or an app account already bound to a wallet) is still only logged: what deleting one means for on-chain assets is your decision. | You |

Risks that remain, for you to decide on:

* **A PvP opponent can still field a Meme Dynasty creature.** The app never shows the player's own
  creature, but a Chikiseum match against a website player who picked one draws it. It is rare, and
  a reviewer will not meet it, but it is not zero.
* **Player names are user-generated content** (guideline 1.2). Chat is off in the app, but other
  players' handles still show above their heads. Apple can ask for a way to report or block an
  offensive name; the backend has a word filter but no report route.
* **Guideline 4.2 (minimum functionality).** The game runs in a WebKit view. The native Pairing,
  Account and deletion screens, plus the screenshots in §5, are the evidence that this is an app
  and not a website. Keep them.

### Uploading from GitHub, with no Mac needed

`.github/workflows/ios-release.yml` archives, signs and uploads the app to App Store Connect on a GitHub-hosted Mac. The build then shows up under TestFlight, ready to submit. Set it up once:

1. **Create the app record.** App Store Connect → Apps → **+** → New App. Choose iOS, name `Chikoria`, bundle id `com.chikimonsters.Chikoria`, and enter any SKU. If that bundle id isn't in the list, register it first: developer.apple.com → Certificates, IDs & Profiles → Identifiers → **+** → App IDs.
2. **Make an API key.** App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys → **+**. Choose the **Admin** role, which is what lets Xcode create the distribution certificate for you. Download the `.p8` file straight away, because Apple only offers it once. Note the **Key ID** and the **Issuer ID** shown above the list.
3. **Add four repository secrets.** GitHub → this repo → Settings → Secrets and variables → Actions → New repository secret:
   - `APPLE_TEAM_ID`: the 10-character Team ID from developer.apple.com → Membership
   - `ASC_KEY_ID`: the Key ID
   - `ASC_ISSUER_ID`: the Issuer ID
   - `ASC_PRIVATE_KEY`: the whole text of the `.p8` file, including the BEGIN and END lines

Then go to Actions → **iOS release** → Run workflow and enter the version, for example `1.0`. Each run uploads a new build, numbered by the run. No certificate or profile is stored anywhere: signing is Xcode's cloud-managed automatic signing, authorised by the key. Then go through steps 5–8 below in App Store Connect.

### From a Mac: the submission, in order

Budget an afternoon. Nothing here is subtle; the order matters.

1. **Prerequisites.** A Mac with the current Xcode, an Apple Developer Program membership that is
   already approved (individual: about a day; organisation: needs a D-U-N-S number), a real iPhone,
   and this repository cloned.
2. **Open the project.** `open ios/Chikoria.xcodeproj`. Target → *Signing & Capabilities* → tick
   *Automatically manage signing* and pick your Team. Target → *General* → Version `1.0`, Build `1`.
   Supported Destinations: iPhone only unless you will also capture iPad screenshots.
3. **Run on the iPhone.** The four Swift files were written without a Mac. Three compile errors
   found by review are fixed; fix whatever else Xcode flags first. Then, inside the app, open `https://chikimonsters.com/realm/selftest.html`: both
   answers must read yes. Pair: on a computer sign in at `chikimonsters.com/link/`, press *New
   code*, type it into the app.
4. **Walk the app as a reviewer.** No Trading Post, no WALLET tab, no Magic Eden, no chat box, no
   $CHIKI or SOL anywhere (the balance reads "coins"). Open every tab of the player panel, the
   Chikiseum, the Temple and the help pages. Anything that still names a wallet, a token, a price
   or a marketplace is a bug in `godot-patch/ios-trading-edits.json` — note where and it is one
   more edit.
5. **Capture** the six screenshots and the preview video from §5, on the device, in landscape.
6. **App Store Connect.** *My Apps → + → New App*: iOS, name `Chikoria`, bundle id
   `com.chikimonsters.Chikoria`, SKU `chikoria-ios-001`. Fill §1 (information), §2 (age rating),
   §3 (privacy), §4 (review notes, with the test account and the pairing recording attached).
7. **Archive and upload.** Xcode: *Product → Archive → Distribute App → App Store Connect →
   Upload*. Processing takes about ten minutes; then pick the build on the version page.
8. **TestFlight** on two phones, including the oldest you intend to support. Confirm pairing, the
   world booting, Airplane Mode showing the native offline screen, and no chat box anywhere.
9. **Submit for Review.** First responses usually arrive within one to two days.

One product decision is still yours: **what account deletion does** on a wallet-backed account. (An
account the *app* made now deletes cleanly — there is no wallet behind it and nothing on-chain to
orphan, so 5.1.1(v) is satisfied for that kind outright.)

**The 500,000 $CHIKI gate is settled and gone from the app** (owner, 2026-09-22). An App Store build
may not ask a player to go and acquire half a million of a token somewhere else before it will let
them play. A player now either creates an account in the app — no wallet, no email, no password — or
pairs the Phantom wallet they already have; either way the gate is waived for app sessions. **The
website is unchanged** and still enforces the hold, and there is a test that fails if that stops
being true.

Note the shape, because the obvious version of this change is a trap twice over:

* Setting `MIN_HOLD=0` would also have opened `/claim`, `/chat/send` and the ten 1,000,000 $CHIKI
  quest winner slots, which re-read the hold for themselves. The waiver is scoped to *entry*.
* Setting `/verify`'s `eligible` alone would have done nothing. The compiled pack does not read
  `eligible` — `Onboarding` recomputes the gate from the balance against its own hardcoded 500,000
  and only a `gateWaived` flag overrides it. Verified by decoding the shipped bytecode:
  `Onboarding.gdc`'s identifier table contains `gateWaived` and `waived`, and does not contain
  `eligible`. So the gate opens **with no pack rebuild**.

### The trading sweep — how the rest of the pack was cleared

The first patch (`apply-ios-pack-patch.py`, 19 edits) took the surfaces a reviewer meets first off
the screen. Three more were then found by reading the compiled bytecode — the WALLET tab, PlayerPanel's
Magic Eden rail and the Open Gates card — and the owner's decision (2026-09-24) was to rebuild the pack
and take **every** trading scheme out of the app, with progress still syncing to the account so
that anything earned in the app can be sold on the website.

`apply-ios-trading-patch.py` is that rebuild. It was made by sweeping every string literal in the
recovered project for wallet, market, token and SOL wording (about 870 of them in 28 scripts),
tracing each to what draws it, and gating the entry points rather than the strings where possible:

| Surface | Now in the app |
|---|---|
| WALLET tab and popup (Phantom connect/sign-in, Solscan, "Open browser version") | not built; the tab art's painted label is covered |
| Magic Eden rail tab, NFT certificate, minting and listing cards | not built / refuse with a neutral line |
| Trading Post world prompt, minimap label, `open_market` | gone / refused |
| Trading Post background toasts ("SOLD to…", "Outbid…", on-chain retries) that fire when a sale happens on the website | silent; the credit still lands |
| Open Gates card and gate events naming the 500,000 $CHIKI gate | neutral welcome, no token named |
| Chain.gd sign-in toasts ("verifying your $CHIKI hold…") on every launch | neutral |
| $CHIKI / SOL lines in quests, the Temple, the Chikiseum, help pages, news and Dispatch | hidden or reworded |
| The balance itself | named **"coins"** everywhere it is drawn, by a TranslationServer translation `ChikFeat` installs only in the app |

Kept on purpose: earning, gathering, hatching, quests, the Temple, PvP, cloud save — and the coin
pouch's **Collect** button, which is an in-game purse (daily quests will not pay into a full pouch).

Verification: every script re-parses under the voxel-module editor; the patch reproduces the
verified source byte-for-byte from a fresh recovery and is a no-op on a second run; the 20 compiled
scripts round-trip through GDRE's decompiler; the rebuilt pack boots in Chromium under the app
policy (cross-origin isolated, `CHIK_FEATURES.crypto === false`). **Only a walk-through on a real
device proves nothing was missed** — step 4 above.

To rebuild after the website's pack changes: recover (`RECOVERY.md`), run all three patchers in
order (`apply-ios-pack-patch.py`, `apply-ios-trading-patch.py`, `apply-ios-review-patch.py`),
re-import, `--check-only` each changed script, compile them with
`gdre_tools --compile=<file> --bytecode=4.6.0` into `godot-patch/ios-overlay/`, run
`ios-app-art.py realm/ godot-patch/ios-overlay/app-art`, then `build-ios-pack.py` and
`chunk-pack.py --ios --lite`. `verify/meme-stash.gd` is the tripwire for the Meme Dynasty set-aside.

### The Godot problem, restated — the project is no longer missing

This section used to say the project was gone and that PvP therefore could not ship. Both halves
were wrong, and `godot-patch/RECOVERY.md` has the evidence for what replaced them.

**The project was recovered** from the pack this repo publishes, using GDRE Tools, in about forty
seconds, and with the matching editor it imports with **zero parse errors** across all 91 scripts.

**PvP needs no change at all.** `ChikiseumLiveClient.gd` does not merely avoid stakes, it rejects
any server response that is not `currency: "NONE"` with `real_sol_enabled: false`. There is no
wager route in the pack. The season-match allowlist work this section used to demand had nothing to
add routes for — the shipped build already is a server-hosted, stake-free match. So option 1,
"ship v1.0 without PvP", is off the table in the good way: **PvP can ship as is.**

What replaced it is narrower: the marketplace, the Cup's SOL copy, the welcome screen's wallet
button and the chat box are GDScript drawing its own UI, which no loader can reach. The change for
all of it is written, applied and verified — `godot-patch/apply-ios-pack-patch.py`, **19 edits**,
parse-clean, and confirmed on screen in a running build.

The engine turned out to be the easy half, and that has now been run end to end rather than
estimated:

> `realm/index.wasm` is a **custom Godot 4.6 build with the `godot_voxel` module compiled in**.
> The **editor** for it is a download — Zylann's v1.6 build reports `4.6.stable.custom_build.89cea1439`,
> the same commit as stock 4.6-stable. Only the **web export template** has to be compiled, and it
> compiles in **12 minutes** on four cores. With that editor the recovered project imports with
> **zero parse errors**, and a full web export completes: a 371 MB `index.pck` plus engine and glue.

One thing does still fail, and it is worth understanding rather than fearing. The project's own
export plugin audits 402 Chikiseum cards against a pinned manifest and rejects the build at the
first one:

```
ERROR: CHIKISEUM_CARD_EXPORT_REJECTED: Approved original or mask bytes changed: adalor:0
```

That audit is a **provenance gate, not a functional one**, and the difference was settled by
running the rebuilt pack rather than reasoning about it. `ChikiseumCardPresentation._prepare()`
does not fail on an unverifiable binding — it degrades, and says so in the field name:
`reason = "source_binding_changed_original_preserved"`. The original card art is displayed; only
the mask-based cleaning pass is skipped.

Served cross-origin-isolated and opened in Chromium, the rebuilt pack boots, the world renders,
the offline Action Lab opens, and **Adalor — the species the audit rejects by name — renders
correctly with all twelve of its ability cards**. PvP is untouched either way:
`ChikiseumLiveClient.valid_bindings()` compares the server's response to client constants, and a
rebuild changes neither side.

What is missing is exactly **402 original card JPEGs** (`res://cards/10_0.jpg` … `50_9.jpg`),
which were never in a pack — Godot ships imported textures, not source art. The manifest and all
402 masks recover byte-identical. Get those files when you can; they restore exact provenance and
make the plugin bless the build again. **They are not a prerequisite for shipping one.**

### And the app gets its own pack — the website keeps the one it has

The rebuilt pack is **not** published over the website's. `realm/index.html` now tries an
`index.pck.ios[.lite]` family first, and only when `window.CHIK_IOS_APP` is set.

That pack is not a separate build of the game either. `godot-patch/build-ios-pack.py` takes the
**shipped** pack and swaps in only the compiled scripts the patch changed — **8 files out of
5,459**. Same textures, same scenes, same card art, same engine binary. Worth doing that way for a
measured reason: compiling the recovered project produces 17 different scripts out of 91, but only
6 were patched — the other 11 differ purely because decompiling and recompiling GDScript does not
round-trip byte-exactly. Swapping only the patched files keeps those 11 out of the app entirely.

Verified by booting it both ways against the real loader:

| | mounts | `CHIK_NO_CRYPTO` |
|---|---|---|
| native app (iPhone UA + `CHIK_IOS_APP`) | `ios-lite` | `true` |
| plain mobile browser | the website's `lite` | `false` |

and the website's 24 pack files came out **byte-identical**. In both cases the shipped engine
(`4.6.stable.custom_build.89cea1439`, Emscripten 4.0.11) loaded and the island built.

So the remaining step is to publish `index.pck.ios.lite.*` into `realm/` — seven chunks and a
manifest, about 175 MB, alongside the packs already there. Nothing the website serves changes.

---

## 1. App information

| Field | Value | Limit |
|---|---|---|
| **App name** | `Chikoria` | 30 |
| **Subtitle** | `Gather, hatch, and battle` | 30 |
| **Primary category** | Games → Role Playing | |
| **Secondary category** | Games → Adventure | |
| **Bundle ID** | `com.chikimonsters.Chikoria` | |
| **SKU** | `chikoria-ios-001` | |
| **Copyright** | `2026 Chikimonsters` | |
| **Support URL** | `https://chikimonsters.com/support/` | written, and names `support@chikimonsters.com`. **Create that mailbox and read it before submitting** |
| **Marketing URL** | `https://chikimonsters.com/app/` | the app's own page — describes only what the app does |
| **Privacy Policy URL** | `https://chikimonsters.com/privacy/` | drafted, names `privacy@chikimonsters.com`; still needs legal review |

### Promotional text (170 chars, editable without review)

```
Your Chikoria account, in your pocket. Gather across the island, clear the Wicked Temple, and raise a team that grows with you.
```

### Description (4000 chars)

**Written to lead with what is native**, because guideline 4.2 rejects apps that read as a repackaged website. See §6 — this is not decoration, it is the defence.

```
Chikoria is a living voxel world you can carry with you.

Explore a hand-built island, gather and craft, fish the coasts, clear the Wicked Temple, and raise a team of creatures that grows with how you play.

ONE ACCOUNT, TWO PLACES
Pair the app once and it plays the Chikoria account you already have. Every creature, egg, fish and resource is there, and everything you gather here is waiting next time you play on the web. No passwords to remember — pairing is a code you type once, and this device stays signed in.

BUILT FOR THE PHONE
· Pair and manage your account without ever leaving the app
· Switch between accounts, see every linked device, and unlink any of them
· Knows when you are on mobile data and downloads the lighter world instead
· Keeps playing where you left off, and tells you plainly when something is wrong instead of showing you a blank screen

A REAL WORLD TO WORK
14 resources, 130 recipes, ten levels of tools, eight fish and four sea legends, six mounts. Everything is gathered, crafted and cooked by hand.

THE WICKED TEMPLE
Take one creature into five escalating sanctums against the corrupted horde. Your deck is the creature's own ability cards. Clear all five and the vault opens.

A TEAM THAT KNOWS YOU
Twenty-four species: ten elemental chikimon and fourteen legendaries. Every creature levels to 50, learns up to twelve ability cards, and grows a personality shaped by how you treat it.

Chikoria is free to play. There are no purchases in the app.
```

> That text makes no PvP claim, so it is safe as it stands. **PvP can now ship** (the Chikiseum is
> already stake-free — see "The Godot problem" above), so you may add a paragraph for it. Say
> nothing about prizes beyond in-game items, and do not use the word "wager":
>
> ```
> THE CHIKISEUM
> Take a creature you own into real-time duels against other trainers. Move, cast and hold ground — there are no turns. The server runs the match; nothing is staked and nothing is wagered.
> ```

### Keywords (100 chars, comma separated, no spaces after commas)

```
voxel,creature,monster,collect,rpg,adventure,craft,gather,fishing,island,pets,breeding,team,explore
```

---

## 2. Age rating

Apple replaced the old tiers in 2025 — **12+ and 17+ are gone; 13+, 16+ and 18+ are new**, and the expanded questionnaire is mandatory. Answer it in App Store Connect; these are the answers that match the app as built.

| Question | Answer | Why |
|---|---|---|
| Cartoon or Fantasy Violence | **Infrequent/Mild** | Creature battles, no blood, no injury depiction |
| Realistic Violence | None | |
| Sexual Content / Nudity | None | |
| Profanity or Crude Humor | None | |
| Alcohol, Tobacco, or Drug Use | None | |
| Horror/Fear Themes | **Infrequent/Mild** | Grimwick and the "corruptimons" are mildly menacing |
| Medical/Treatment Information | None | |
| Gambling | **No** | See the note below — this matters |
| Contests | No | |
| Unrestricted Web Access | **No** | The app cannot navigate outside `/realm/`; there is no in-app browser |
| User-Generated Content | **Yes** | Chikimon nicknames, player handles, chat messages |
| Messaging / Chat | **No** | The game has chat; **the app refuses every chat route** — see below |

**Expected rating: 9+**, on the two "Infrequent/Mild" answers — but only because chat is blocked. Read the next section before answering either of the last two rows.

### Gambling — answer No, and know why

The app has no wagers, no purchases and no real-money stake. The Wicked Temple's reward roll is randomised, but nothing is paid to enter and nothing of monetary value is risked, so it is not gambling and not a loot box. **The website's SOL wagers are not in this app and must not be described as if they were.**

### The game has chat — and the app now refuses it

This was listed as unknown. It is not. The game's own release notes say so plainly:

| Evidence | Source |
|---|---|
| *"Your wallet address is public — it's on the roster, **in world chat** and on the market board"* | `realm/updates.json` |
| *"parties of four **with their own chat**"* | `realm/updates.json` |
| *"**whispers** were audited end to end: clicking a name, whispering, replying and the self-echo all verified working"* | `realm/updates.json` |
| *"💬 **The chatbox** lets go of you"* — a whole release about it | `realm/updates.json` |
| *"The **System tab in Chat** keeps a timestamped log"* | `realm/index.html` |
| `chat` ×41, `Chat` ×6 in the shipped pack | `index.pck.*.bin` |

So: **world chat, party chat and private whispers between strangers.** Plus user-set chikimon
nicknames, which other players see.

**Guideline 1.2 then requires all four of these** of any app carrying user-generated content:

1. a method for filtering objectionable material
2. a mechanism to report offensive content, **with timely responses**
3. the ability to block abusive users
4. published contact information

### Which of the four actually exist — read from the backend

An earlier draft of this file said none of the four existed, on the evidence that the release
notes and the pack never mention them. **That was wrong**, and the backend repository settles it:

| 1.2 requirement | Status | Evidence in `server.js` |
|---|---|---|
| A filter for objectionable material | **exists** | `cleanText()` — a server-authoritative profanity mask over a 23-word list, leetspeak-normalised (`1→i`, `3→e`, `@→a`…), also stripping `<>` so chat and handles cannot inject HTML. Applied to messages, whispers and handles alike. |
| A way to **report** offensive content | **absent** | The only `/report` routes are `/world/fish/report` and `/world/kill/report` — gameplay telemetry |
| A way to **block** an abusive user | **absent** | No route, no table, nothing |
| Published contact information | **exists now** | `support/` |

Two of four. The filter is also a mask, not moderation: 23 English words, no phrases, no repeat
offender handling, and nothing a determined person cannot write around.

### The decision: chat is switched off in the app

Building report and block means changing the game, which means rebuilding the pack, which needs a
custom Godot web export template that does not exist (`godot-patch/RECOVERY.md`). So the app ships
without chat. `Chat.gd` is 1,169 lines with no report, block, mute or filter of any kind — the
profanity mask is server-side — so this is a genuine absence, not a gap in what we looked at.

**This is possible because of how chat is transported, which I checked rather than assumed:**

```
POST /chat/send   GET /chat      POST /chat/react   POST /chat/pin
GET  /chat/online GET/POST /world/chat              GET/POST /cup/chat
```

That list came from the backend. **The client's list is shorter, and one of its two routes was not
on it.** `Chat.gd` in the recovered pack calls exactly two endpoints:

```
POST /world/chat    world chat
POST /world/dm      whispers AND party chat  — {to, text, …}
```

`/world/dm` was not matched by the deny rule, so **private messages between strangers were still
open in the app** — precisely the surface guideline 1.2 is about, and the one with no report or
block behind it. It is refused by name now, with tests for it and for the near-miss `/world/dmg`.

All plain HTTP. The WebSocket carries **only `/world/move`** — `server.js` says so at the handler:
*"ONE MOVE HANDLER, TWO TRANSPORTS … a WebSocket now carries the same contract."* So refusing the
chat routes takes the chat away and leaves movement, presence and the rest of the world working.

`realm/chiki-ios.js` refuses all of them, and `CHIK_FEATURES.chat` / `.whispers` are false —
which a pack built with `godot-patch/apply-ios-pack-patch.py` could also act on to stop drawing
the chat box. Seventeen checks in `godot-patch/verify/chiki-ios.test.mjs` pin it, including that
`/world/move` still works.

**So the answers above stand as written:** UGC **yes** (handles and chikimon nicknames still
exist elsewhere in the game), Chat **no** — because it genuinely is not reachable from the app.
Say exactly that in the review notes, since a reviewer who finds a chat box after you answered
"no" is the worst possible outcome.

This was never only a store problem. A 9+ game with open chat between strangers, a 23-word filter
and no way to block anyone is a real safety gap **on the website too** — the app is now the safer
of the two surfaces, which is worth fixing at the source when the project is recoverable.

---

## 3. App Privacy ("nutrition label")

These must agree with `ios/Chikoria/PrivacyInfo.xcprivacy`. The app can now create its own account and syncs the save to it, so it **does** collect data. It is all linked to the player, used only for App Functionality, and never used for tracking.

| Question | Answer |
|---|---|
| Does this app collect data? | **Yes** |
| Identifiers → **User ID** | Collected, linked to the user, App Functionality, not tracking. This is the account id: the app can create one, and it travels with every save. |
| Identifiers → **Device ID** | Collected, linked, App Functionality, not tracking. This is a random id made on first launch (`LinkKeychain.swift`) so a device can be listed and revoked. It is not the IDFA. |
| Other Data → **Gameplay Content** | Collected, linked, App Functionality, not tracking. This is the save: creatures, items and progress, synced so the player can continue on the website. |
| Does this app use data for tracking? | **No** |
| Third-party SDKs | **None**: the app links no analytics, ads or attribution framework. |

**Adding telemetry changes these answers.** If anything is added later, crash reporting included, both this table and the manifest must change.

---

## 4. App Review notes

Paste into the "Notes" field. A reviewer who cannot sign in rejects the app, so the test account matters more than everything else here.

```
HOW TO SIGN IN (please read — the app cannot be tested without this)

Chikoria accounts are created on our website, and the app pairs to one with a
short code. We have created a test account for review:

  1. On a computer, open https://chikimonsters.com/link/
  2. The test account is already signed in there. Press "New code".
  3. Type that code into the app's pairing screen.

The code lasts 10 minutes. If it expires, press "New code" again.
[ATTACH: a short screen recording of these three steps]

THERE IS NO CHAT IN THIS APP

The browser version of Chikoria has player chat. The app does not: every chat
route is refused at the network layer, so no message can be sent or received
and no chat content is displayed. This is why the age rating questionnaire
answers "no" to messaging.

ABOUT THE TECHNOLOGY

Chikoria is tied to a blockchain-based game economy on the website. The app is
deliberately NOT part of that:

· The app contains no wallet. It cannot create, sign or send a transaction,
  and it never asks for a key or a recovery phrase.
· Nothing can be bought, sold, traded or staked in the app. There is no
  purchase flow of any kind, and no external purchase is offered or linked.
· Nothing in the app is gated on holding any cryptocurrency.
· The app communicates only with chikimonsters.com and our own game server.
  It cannot reach a blockchain node, an exchange or a marketplace — this is
  enforced in the app, not merely intended.

Players earn in-game items by playing. Those items belong to their account. The
app provides no way to sell or exchange them.

WHAT IS NATIVE

Account pairing, account switching, device management, account deletion,
settings and support details are all native screens. The app also handles
offline and connection-failure states natively — in Airplane Mode you will see
a native screen, not a browser error.

FIRST LAUNCH

The game world downloads on first launch (about 175 MB on cellular, more on
Wi-Fi) and is cached. Please allow it to finish; on a slow connection this can
take a few minutes. A progress indicator is shown throughout.
```

### Export compliance

`ITSAppUsesNonExemptEncryption` is set to `false` in `Info.plist`, so the per-upload questionnaire is skipped. Correct: the app uses only HTTPS via the system, and implements no encryption of its own.

---

## 5. Screenshots and the preview video

**Neither can be produced without a running build.** What follows is the complete brief so that capturing them is an hour, not a day.

### Sizes you actually need

Apple scales down, so two sets cover everything:

| | Portrait | Landscape | Required |
|---|---|---|---|
| **iPhone 6.9"** (16/17/18 Pro Max) | 1320 × 2868 | **2868 × 1320** | yes — or 6.5" instead |
| **iPad 13"** (Pro M4/M5, Air M2+) | 2064 × 2752 | **2752 × 2064** | yes, if the app ships for iPad |

1–10 per size. JPEG or PNG. **No alpha channel** — a transparent PNG is rejected at upload.

**Capture in LANDSCAPE.** The realm is landscape-only on phones, and the `Info.plist` in this repo restricts the app to landscape. Portrait screenshots would misrepresent it.

> If you do not want to maintain iPad assets, remove iPad from Supported Destinations in Xcode and the iPad set is not required. Given the HD-pack memory finding is untested on iPad, shipping iPhone-only for v1.0 is defensible.

### The shot list — six, in this order

The first two are what most people ever see, so they carry the argument.

1. **The world.** Your creature in the overworld, island and castle visible. Caption: *"A hand-built island to explore"*
2. **The Wicked Temple mid-fight.** Cards visible in the HUD. Caption: *"Five sanctums. One creature. Your deck."*
3. **Gathering or crafting.** The satchel or craft shop open. Caption: *"14 resources. 130 recipes. All by hand."*
4. **The ChikiDex.** Several creatures collected. Caption: *"24 species to raise to level 50"*
5. **The native pairing screen.** Caption: *"Pair once. Your account travels with you."*
6. **The native account screen.** Linked devices visible. Caption: *"Your devices, your control"*

Shots 5 and 6 are not filler — they are the visual evidence for guideline 4.2 that this is an app and not a website. Do not drop them for a prettier sixth gameplay shot.

### How to capture

```
Simulator → iPhone 16 Pro Max → run the app → ⌘S
```
Simulator screenshots are already the exact pixel dimensions and have no alpha. For the gameplay shots use a **real device** (Xcode → Window → Devices and Simulators → Take Screenshot) — the simulator renders the world differently and can miss the memory limits entirely.

### App preview video

- **15–30 seconds**, ≤ 500 MB, H.264 `.mp4`/`.mov` or ProRes 422 HQ
- **1920 × 886** landscape for iPhone; **1600 × 1200** for iPad
- Up to 3 per device class
- Audio optional — stereo AAC ≥ 256 kbps if included

**Capture from a real device**, not the simulator: QuickTime → File → New Movie Recording → select the iPhone. Then trim in iMovie.

A 25-second cut that works:

| Time | Shot |
|---|---|
| 0–4s | Walking through the island, camera following |
| 4–10s | Gathering, then the satchel filling |
| 10–18s | Wicked Temple: a card cast, an enemy going down |
| 18–22s | A hatch, or the vault reward reveal |
| 22–25s | Title card: Chikoria |

**Show only what is in the app.** No website footage, no wallet, no trading, no token. A preview containing the Trading Post would contradict the review notes above and undo the whole argument.

---

## 6. Guideline 4.2 — the rejection this app is most exposed to

A `WKWebView` pointed at a website is the textbook 4.2 rejection, and that is structurally what this shell is.

**The test reviewers actually run is Airplane Mode.** Turn the network off and open the app. A blank web view or a browser error is what flags it as a repackaged website.

What the app does today: a native screen saying *"Chikoria needs a connection to load the realm"* with a Try Again button. **That is necessary but thin** — it is an error, not usefulness.

Worth adding before submission, in rough order of value per hour:

1. **Make the offline screen useful.** Show the linked account, which creatures are on the team, when they last played — cached natively at last launch. That turns an error into a screen with content.
2. **Settings as a real native screen.** Graphics/world detail, language, sound — native controls, not a web panel.
3. **Push notifications** for a finished match or a hatched egg. The single most recognised "this is a real app" signal, and honest here because there is genuinely something to notify about.
4. **A widget** showing the team. Cheap, and very visibly not-a-website.

None of these are optional if a first submission gets rejected under 4.2 — they are simply what the second attempt has to contain, so doing one or two first is cheaper.

---

## 7. Order of operations

Nothing below can move ahead of the thing above it.

- [x] **The iOS pack is published** — `realm/index.pck.ios.lite.*` is live, and the app's loader takes it. The shop, the welcome-screen wallet button, the Chikiseum SOL copy and the chat box are off the screen.
- [x] **Rebuilt the pack** with every trading surface removed (`apply-ios-trading-patch.py`, 165 edits) — the three surfaces above and everything else the sweep found. Every piece of the recipe is ready and verified (`godot-patch/RECOVERY.md`):
      ```sh
      # 1. recover the project from the pack this repo publishes   (~40s)
      cat realm/index.pck.[0-9].bin realm/index.pck.1[0-2].bin > index.pck
      ./gdre_tools.x86_64 --headless --recover=index.pck --output=recovered

      # 2. apply the 19 iOS changes                                 (instant)
      python3 godot-patch/apply-ios-pack-patch.py recovered

      # 3. import + export with Zylann's v1.6 editor and a web template you built (~12 min once)
      godot --headless --path recovered --import
      godot --headless --path recovered --export-release "Web" out/index.html

      # 4. chunk it the way realm/ serves, and verify the round trip
      python3 godot-patch/chunk-pack.py out realm/
      node godot-patch/verify/loader-policy.test.mjs
      ```
      Expect `CHIKISEUM_CARD_EXPORT_REJECTED` at step 3 — it is a provenance gate, not a failure.
- [x] **Decided:** an app player does **not** need the 500k $CHIKI hold — the gate is waived for app sessions and unchanged on the website
- [x] Backend: `/link/new`, `/link/redeem`, `linkToken` on `/verify`, `/link/devices`, `/link/revoke`, `/link/delete_account` — written, tested (50 checks against the real server), **merged and live on `api.chikimonsters.com`**
- [x] Backend: `/account/new`, `/account/claim`, `/link/bind` — app-native accounts and connecting a wallet to one, tested against the real server
- [x] **Patched the pack's WALLET tab and `PlayerPanel`'s Magic Eden rail** — in the rebuilt pack
- [ ] **Decide** what account deletion actually removes **for a wallet-backed account**. The request/grace/cancel flow is live; the execution step is deliberately unwired (`realmLink.due()` lists what is past its grace). An app-made account has no such question — nothing of it lives anywhere but our database
- [x] Publish `link/` and `privacy/` — live
- [x] Support page — `support/` is written
- [ ] Create `support@chikimonsters.com` and `privacy@chikimonsters.com` (forwarding is fine) — both pages name them
- [ ] Apple Developer Program enrolment, if not already done
- [ ] Create the Xcode project (`ios/README.md`) and get it running on a real iPhone
- [ ] **Open `/realm/selftest.html` inside the app** — confirms the engine can run there at all
- [x] Chat — blocked in the app (§2). Verify in TestFlight that no chat box can receive anything
- [ ] Consider adding report and block **to the website**, where chat is still open and the filter
      is 23 words long
- [ ] Legal review of `privacy/index.html`
- [ ] Decide on telemetry → then finalise the privacy answers
- [ ] 4.2 hardening (§6) — at least the offline screen
- [ ] Create the test account and record the pairing walkthrough for the review notes
- [ ] Capture screenshots and the preview video
- [ ] TestFlight on at least two real iPhones, including the oldest you intend to support
- [ ] Fill in everything above in App Store Connect
- [ ] Submit

---

## Sources

Apple's own pages, checked 2026-09-20:

- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/)
- [App preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications/)
- [Updated age ratings in App Store Connect](https://developer.apple.com/news/?id=ks775ehf)
- [Age rating upcoming requirements](https://developer.apple.com/news/upcoming-requirements/?id=07242025a)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — re-read 3.1.1, 3.1.5(b), 4.2 and 5.1.1(v) before submitting; they change

Verify anything version-dependent yourself. This file will go stale.
