# chikimonsters.com — the public site, the realm, and the iOS app

## The one rule that shapes everything

**Everything tracked in this repo is served publicly at `chikimonsters.com/<path>`.** There is no
build step, no bundler and no server-side filtering — GitHub Pages serves the tree as it stands,
behind Cloudflare. A file committed here is a file on the internet.

Two consequences that have bitten before:

* **Never put backend source in this repo.** It lives in `gtjvv976mb-netizen/backend` and deploys
  to Render. `DEPLOY.md` says this too.
* **Never commit the recovered Godot project.** The game's source is reconstructed with GDRE Tools
  when a pack rebuild is needed (see `godot-patch/RECOVERY.md`); committing it would publish the
  entire game's source, card art provenance included.

## What is being built

An iOS app, **Chikoria**, that ships the same Godot web game the website runs — as a gameplay-only
client on the player's real account, with no wallet on the device, no trading, and PvP without
crypto. The goal is App Store submission. `APPSTORE.md` is the submission kit and the live
checklist; `IOS-APP.md` is the design. **Read both before changing anything iOS-related.**

The app is a native SwiftUI shell (`ios/`) around a `WKWebView` pointed at
`chikimonsters.com/realm/`, with `realm/chiki-ios.js` as a policy layer injected before everything
else.

## The three pack families

`realm/` carries three chunked Godot packs. They must stay on one build:

| Family | Who gets it | Notes |
| --- | --- | --- |
| `index.pck.*` | desktop web | GDPC format |
| `index.pck.lite.*` | phones on the web | ZIP format, `fs_name: index.pcz` |
| `index.pck.ios.lite.*` | the iOS app only | the lite pack with 8 files swapped |

The iOS pack is built by `godot-patch/build-ios-pack.py` from the **shipped** lite pack plus
`godot-patch/ios-overlay/`. It is not a separate export — that keeps it byte-identical to the
website except for the patched scripts.

**When `main` ships a new Godot export, the iOS pack must be rebuilt.** Check the overlay is still
valid first: extract the new lite pack and compare the six replaced `.gdc` files against the ones
the patch was authored against. If any moved, the patch must be re-applied to the new source before
rebuilding.

## Traps that have already cost a day each

* **A ZIP pack is recognised by file EXTENSION, not magic bytes.** Godot's PCK reader rejects
  anything without `GDPC`, and its ZIP reader only engages for a path ending `.zip`/`.pcz`. The
  loader hand-rolls `init` → `preloadFile(blob, fs_name)` → `start --main-pack <fs_name>` for
  exactly this reason. A chunker that drops `format`/`fs_name`/`sha256` from the manifest produces
  a pack that fails with "Couldn't load project data at path '/'".
* **The compiled pack does not read `/verify`'s `eligible`.** `Onboarding` recomputes the entry
  gate itself against a hardcoded `MIN_HOLD := 500000` and only a `gateWaived` flag overrides it.
  Verified by decoding the bytecode: `Onboarding.gdc`'s identifier table has `gateWaived`,
  `gateWaivedEnds`, `gateWaivedUntil`, `gate_waived`, `event_open_gates` — and no `eligible`.
* **`CHIK_FEATURES` keys must exist in BOTH branches** of `features()` in `chiki-ios.js`.
  `ChikFeat.on()` reads a missing key as **true**, so a key present in one branch and absent from
  the other reads as "on" — backwards for anything that gates a money surface.
* **Decompiled GDScript keeps trailing whitespace after argument commas.** The patch anchors in
  `godot-patch/apply-ios-pack-patch.py` are whitespace-tolerant for this reason. Don't "tidy" them.
* **The engine is a custom build.** `realm/index.wasm` has `godot_voxel` compiled in as a C++
  module, so the stock Godot editor cannot open the project (9 scripts fail to parse). Use
  Zylann's voxel editor build — `4.6.stable.custom_build.89cea1439`.

## Verifying a change

All four must pass. None needs a network or a device.

```bash
node godot-patch/verify/chiki-ios.test.mjs        # the policy layer, in a VM sandbox
node godot-patch/verify/loader-policy.test.mjs    # index.html, by parsing it
node godot-patch/verify/app-account.e2e.mjs       # the real thing — see below
python3 godot-patch/apply-ios-pack-patch.py <recovered-project> --check
```

`app-account.e2e.mjs` is the one that counts: it boots the real backend from
`/home/user/backend`, serves `realm/` with the isolation headers Cloudflare applies, and drives the
real policy layer in Chromium through create account → play → claim code → bind → the phone
catching up. The backend is **proxied onto the page's own origin** rather than allowlisted, because
`chiki-ios.js` refuses every other host and a test that relaxed that would be testing a policy layer
nobody ships.

Chromium is pre-installed; do not run `playwright install`.

## Accounts: two ways in, one-way door

An app player either **creates** an account on the device (no wallet, no email, no password) or
**pairs** the Phantom wallet they already have. **Bind** moves a created account onto a real wallet
and is the only way it gains the ability to sell. The full design is in `IOS-APP.md`; the server
side is in the backend repo's `CLAUDE.md`.

The 500,000 $CHIKI entry gate is **off for app sessions and unchanged on the website**. That scoping
is deliberate and there is a test that fails if the website stops enforcing it.

## What is still outstanding

See `APPSTORE.md` for the full checklist. The short version:

1. **Deploy the backend.** `/account/*` and `/link/*` 404 until `gtjvv976mb-netizen/backend` `main`
   is live on Render. Nothing in the app works past the first screen without it.
2. **Three unpatched pack surfaces**, all needing the recovered Godot project and a pack rebuild —
   InfoBar's WALLET tab, `PlayerPanel`'s Magic Eden rail, and the Open Gates card. Listed with their
   exact strings in `APPSTORE.md` and in a comment block in `godot-patch/apply-ios-pack-patch.py`.
3. **Create `support@chikimonsters.com` and `privacy@chikimonsters.com`.** Both are published and
   linked; a bouncing address fails review.
4. **Screenshots and the preview video** — must be captured from the app on a real device.
5. **Decide what account deletion removes** for a *wallet-backed* account. An app-made account
   already deletes cleanly.

## Conventions

* Develop on a `claude/*` branch, then merge to `main`. The owner has previously asked for direct
  merges to `main` rather than PRs — confirm before assuming that still holds.
* There is no Swift toolchain in the Claude Code environment. `ios/*.swift` can only be checked
  structurally here; it compiles on the owner's Mac. The deployment target is **iOS 16.0**, so
  iOS 17-only API (the two-parameter `onChange(of:)`, for one) will not build.
* Commit messages in this repo are long on purpose. They are where the reasoning lives.
