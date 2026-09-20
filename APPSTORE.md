# App Store submission kit

Everything for App Store Connect that does not require a build. Copy the fields straight in.

**Read the next section before anything else.** This kit is complete; the app is not.

---

## Can this be submitted today? No — and here is exactly why

Four things block submission, and none of them can be fixed by writing more code in this repo.
(A fifth — chat with no report or block mechanism — **was** a blocker and has been closed: the
app now refuses every chat route. See §2.)

| Blocker | Why it blocks | Who can clear it |
|---|---|---|
| **No build exists** | The Swift in `ios/` has never been compiled. Submission needs an archive uploaded from Xcode on a Mac. | You, with a Mac |
| **The backend has no `/link/*` routes** | Pairing calls `/link/redeem`, which 404s. **A reviewer cannot get past the first screen.** | Backend work — see `IOS-APP.md` |
| **No screenshots or preview video** | Both must be captured from the running app. They cannot be drawn, and faking them is a rejection *and* a guideline violation. | You, once a build runs |
| **The app still shows a shop** | Until the pack is rebuilt: a player can walk to the Trading Post and open a marketplace with a `🪄 Magic Eden` tab, the welcome screen's main button is *Connect Phantom Wallet*, and the Chikiseum says *"champions win real SOL"*. Every button refuses — but 3.1.1 is about what an app **presents**. | **Ready to clear:** rebuild the pack with `godot-patch/apply-ios-pack-patch.py` — see below |

Two product decisions are also unmade and are yours: **the 500k $CHIKI gate** (`IOS-APP.md`) and **what account deletion does** on a wallet-backed account.

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

So the recommended path is now just:

1. **Rebuild the pack with the patch and ship it.** The editor is a download, the template is a
   12-minute compile, the export works, and the patch is 19 changes, parse-clean and verified on
   screen. `RECOVERY.md` has every command.
2. If you would rather not rebuild yet, you *can* submit as is and argue it — the app genuinely
   cannot transact, and since this pass it cannot list, bid or sell either. But the shop is on
   screen, and that is a real 3.1.1 risk that may cost a rejection cycle.

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
| **Support URL** | `https://chikimonsters.com/support/` | written (`support/`); **replace the placeholder email with a monitored inbox** |
| **Marketing URL** | `https://chikimonsters.com/` | |
| **Privacy Policy URL** | `https://chikimonsters.com/privacy/` | drafted, needs legal review + a real contact address |

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
Twenty-one species across ten elemental lines, five ancient legendaries and the Meme Dynasty. Every creature levels to 50, learns up to twelve ability cards, and grows a personality shaped by how you treat it.

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

These must agree with `ios/Chikoria/PrivacyInfo.xcprivacy`, which declares no collected data and no tracking.

| Question | Answer |
|---|---|
| Does this app collect data? | **No** |
| Does this app use data for tracking? | **No** |
| Third-party SDKs | **None** — the app links no analytics, ads or attribution framework |

**This answer is only true because the app has no telemetry.** The moment anything is added — crash reporting included — both this and the manifest must change. The audit flagged that the app currently has *no* field signal at all; adding it is a reasonable decision, but it is a privacy-declaration decision too, so make it before submitting rather than after.

The wallet address is the player's own account identifier, created by them on the website and held by the game server. It is not gathered by this app. If your legal review disagrees, declare it as an identifier linked to the user — over-declaring costs nothing and mis-declaring is what gets apps pulled.

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
4. **The ChikiDex.** Several creatures collected. Caption: *"21 species to raise to level 50"*
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

- [ ] **Decide:** submit with the marketplace UI visible and argue it, or build the web export template and cut it from the pack
- [ ] **Decide:** does an app player need the 500k $CHIKI hold
- [ ] **Decide:** what account deletion does
- [ ] Backend: `/link/new`, `/link/redeem`, `linkToken` on `/verify`, `/link/devices`, `/link/revoke`, `/link/delete_account`
- [ ] Publish `link/` and `privacy/` (they are on the branch, not on `main`)
- [x] Support page — `support/` is written
- [ ] Replace the placeholder addresses in `support/` and `privacy/` with a monitored inbox
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
