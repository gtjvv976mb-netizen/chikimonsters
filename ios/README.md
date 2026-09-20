# Building the Chikoria iOS app

The shell is a `WKWebView` around `https://chikimonsters.com/realm/` plus the native screens the
web layer cannot draw: pairing, account, and the failure states that have no page to fall back on.

The Swift in `Chikoria/` is complete and pasteable. What is *not* here is an Xcode project file —
`.xcodeproj` is machine-generated, merges badly and would be stale within a week. You create it
once, in five minutes, and add these files.

> **Not compiled.** These sources were written without a Mac. They are structurally checked and
> two compile errors were caught by review before they shipped, but "it builds" is a claim only
> Xcode can make. Expect to fix something the first time you press Run.

---

## 0. Before you start: what blocks what

**Do not build the shell first.** The order is load-bearing, and it is set out in
[`../IOS-APP.md`](../IOS-APP.md) under "Release order". The short version:

1. The backend routes do not exist yet (`/link/*`, `season_*`). Without `/link/redeem` the pairing
   screen has nothing to call, so **the app cannot sign in at all**.
2. The app's PvP needs a **new Godot export**. The compiled game installs its own `fetch` guard
   with a hardcoded eleven-route allowlist, so the season routes are refused by the game itself
   even against a correct backend.
3. Promoting that export overwrites `realm/index.html` and needs the policy wiring re-applied.

You can build and run the shell today against the live realm — it will load, and pairing will fail
at the network call. That is a reasonable way to develop. It is not a reasonable way to ship.

**One open product decision blocks the App Store submission**, not the build: whether an app player
must hold 500k $CHIKI. See `../IOS-APP.md`.

---

## 1. Prerequisites

| | |
|---|---|
| **Apple Developer Program** | $99/year. Enrol at [developer.apple.com/programs](https://developer.apple.com/programs/). An individual enrolment can be approved in a day; an organisation needs a D-U-N-S number and takes longer. You can build and run on your own device without it — you need it for TestFlight and the App Store. |
| **A Mac** | There is no supported way to build an iOS app without one. |
| **Xcode** | Free from the Mac App Store. Check [developer.apple.com/news](https://developer.apple.com/news/) before your first upload — App Store Connect periodically requires a minimum Xcode version. |
| **An iPhone** | Non-negotiable for this app. The simulator runs on your Mac's RAM and cores, which is precisely the environment that *cannot* reproduce the memory pressure of a 313 MB pack plus a 40 MB wasm module on a phone. |

---

## 2. Create the project

1. Xcode → **File → New → Project…**
2. **iOS → App**. Next.
3. Fill in:
   - **Product Name**: `Chikoria`
   - **Team**: your Apple Developer team (or "Add an Account…")
   - **Organization Identifier**: your reverse-DNS, e.g. `com.chikimonsters`
   - **Bundle Identifier** is then `com.chikimonsters.Chikoria` — write it down, it is permanent
   - **Interface**: SwiftUI · **Language**: Swift · **Storage**: None · **Testing System**: None
4. Save it *outside* this repository. This repo is published by GitHub Pages — every tracked file
   is served at `chikimonsters.com/<path>`, and an Xcode project has no business there.
5. Delete the generated `ContentView.swift` and `ChikoriaApp.swift`.
6. Drag in everything from `ios/Chikoria/`: `ChikoriaApp.swift`, `ShellModel.swift`,
   `Screens.swift`, `LinkKeychain.swift` and `PrivacyInfo.xcprivacy`. Tick **Copy items if
   needed**, and check that the privacy manifest lands in **Copy Bundle Resources**.

---

## 3. Configure it

**Target → General**

- **Minimum Deployments**: **iOS 17.0**.
  The hard floor is iOS 15.2 — that is when WebKit shipped `SharedArrayBuffer` for
  cross-origin-isolated pages, and the realm cannot boot without it. But 15.2 is an API floor, not
  a sensible target: below **16.4** you cannot attach Safari Web Inspector to a `WKWebView` at all,
  which makes every device-only bug guesswork. Ship 17.0 unless you have a reason not to.
- **Supported Destinations**: iPhone, iPad. Remove Mac.
- **Device Orientation**: Landscape Left and Landscape Right only.

**Target → Signing & Capabilities**

- Tick **Automatically manage signing**, pick your Team. No capabilities are needed — no push, no
  background modes, no App Groups, no Keychain Sharing (the Keychain item is this app's own).

**Info.plist**

Use `ios/Chikoria/Info.plist` as the reference. It documents two deliberate absences — read the
comment at the top before you add anything to it.

**Assets**

- App icon: a 1024×1024 PNG with no alpha and no rounded corners. `nft/collection.png` or
  `realm/index.png` in this repo are starting points.
- Add a colour set named `LaunchBackground` set to `#0b1220`, which is what the Info.plist
  launch-screen key refers to. The launch screen should be a flat colour: it is shown for a moment
  before the web view has anything to draw, and anything more is a second thing to keep in sync.

---

## 4. App-bound domains: a decision, not a default

`WKAppBoundDomains` is an Info.plist key that locks the app's web views to a list of domains, with
WebKit itself refusing top-level navigation anywhere else. It is genuinely attractive here — an
OS-enforced version of the navigation policy, and a clean line in review notes.

**The trap is that it is all-or-nothing, and half of it fails silently.** Merely *adding* the key
puts every `WKWebView` in the app into a mode where script injection, message handlers and cookie
manipulation are denied. Setting `configuration.limitsNavigationsToAppBoundDomains = true` is what
restores them for the listed domains. If you add the key and forget the flag:

- `window.CHIK_IOS_APP` is never injected,
- so `realm/chiki-ios.js` sees no app flag and **stands down entirely**,
- so the app boots with `solana-web3.js` loaded and the wallet bridges live,
- and **nothing tells you.** No crash, no log, no failed check.

That is the exact outcome the whole policy layer exists to prevent. This project therefore ships
**neither** — the navigation policy in `ShellModel.webView(_:decidePolicyFor:)` covers the same
ground explicitly and visibly. If you decide to adopt app-bound domains later, adopt both halves in
one commit, and verify by confirming the `ready` message still arrives (`model.policyIsLive`).

You do **not** need to list the backend hosts either way: the restriction applies to top-level
navigation only, so `fetch` to `api.chikimonsters.com` is unaffected.

---

## 5. Run it

**Simulator** — fine for the pairing screen, the account sheet and the failure states. It is not
fine for judging memory, thermals or frame rate.

**A real device** — plug it in, select it, press Run. First time: on the phone, Settings → General
→ VPN & Device Management → trust your developer certificate.

**The five-second check** — open `https://chikimonsters.com/realm/selftest.html`, in Safari on the
iPhone **and** inside the app. It prints whether cross-origin isolation is live and whether shared
memory actually allocates, in words, with a Copy button. No Web Inspector needed. If Safari passes
and the app fails, the problem is this shell's `WKWebView` configuration, not the headers.

**Safari Web Inspector** — for everything past that:

1. On the phone: Settings → Apps → Safari → Advanced → **Web Inspector** on.
2. On the Mac: Safari → Settings → Advanced → **Show features for web developers**.
3. Run the app, then Safari → Develop → *your phone* → the Chikoria page.
4. `isInspectable = true` is already set in `ShellModel`, but only under `#if DEBUG`.

Useful things to type into that console:

```js
CHIK_FEATURES            // the policy the page is applying
CHIK_LINK.status()       // linked wallet, device id, accounts — never a token
CHIK_POLICY_BLOCKED      // everything the guard has refused this session
crossOriginIsolated      // MUST be true, or the engine cannot start its threads
```

---

## 6. Verify the policy is actually on

**Do this on day one, before building anything else.** Two checks, five minutes, and both are
load-bearing:

Open `/realm/selftest.html` in the app. It answers both in plain words. Or, in the console:

```js
crossOriginIsolated      // expect: true
CHIK_FEATURES.crypto     // expect: false
```

`crossOriginIsolated` is the one to watch. The realm gets it from real `Cross-Origin-Opener-Policy`
and `Cross-Origin-Embedder-Policy` headers that **Cloudflare** adds in front of GitHub Pages —
confirmed live, and scoped to `/realm/*` (`/link/` does not get them). This is an off-repo
dependency that `DEPLOY.md` does not mention and nobody owns in writing. If someone narrows that
rule, the page falls back to a service worker that synthesises the headers — and service workers in
`WKWebView` are undocumented, unsupported by Apple's own statements, and unproven for this purpose.
The realm would stop booting in the app while continuing to work in every desktop browser.

`CHIK_FEATURES.crypto === false` proves the injection ran. If it is `true`, `window.CHIK_IOS_APP`
did not arrive and the app is running the website's policy — see §4.

---

## 7. What the shell gets right, and why

Each of these is a way the app can fail that is not obvious from the outside.

| Rule | Why |
|---|---|
| **One `WKWebView`, for the process lifetime** | The loader keeps its boot guards in `sessionStorage`. A new web view resets them, so the cross-origin-isolation retry loses its loop guard and the memory-kill detector goes blind at the same moment. Recover with `reload()`, never `load()`. |
| **Never touch the query string** | The loader reloads itself with `?swretry=1` to break an isolation deadlock. A shell that "restores the canonical URL" strips it and loops forever. |
| **Handle `webViewWebContentProcessDidTerminate` by reloading the same view** | That is the *only* path by which the loader's memory-kill detector fires and drops the phone to the lighter pack for 24 hours. Without the delegate the player gets a white screen; with a *recreated* view the detector never fires and the phone dies at 90% forever. |
| **No short watchdog on the first load** | A cold boot is ~350 MB of downloads, a wasm compile and a full pack copy, plus up to two reloads before any of it. A 60-second "failed to load" timeout tears the app down mid-boot. |
| **Persistent data store** | A non-persistent one re-downloads the pack every launch and loses every save. |
| **`persist` rebuilds the injection script** | A `WKUserScript` is a frozen string re-run on every load. Write the Keychain but leave the old script and an account switch silently reverts, and the reload after a first pairing lands unlinked. |
| **Message handler in the *page* world** | `chiki-ios.js` looks it up on the page's `window.webkit` and *silently returns* if it is absent. Register it in `.defaultClient` and the Keychain is never written, with no error anywhere. |
| **Re-validate `external-link` natively** | The handler lives in the page world, so the compiled game pack can post to it directly. The web-side allowlist is not a guarantee about what arrives. |
| **`createWebViewWith` returns nil** | The engine gives the pack a bare `window.open` via `OS.shell_open`. Returning nil makes it a no-op. |
| **Same-origin is not safe** | `/arena/` is the full SOL wager client and `/link/` carries a Phantom sign-in. Only `/realm/` is allowed. |

---

## 8. Before you submit

Read the **App Store review** section of [`../IOS-APP.md`](../IOS-APP.md) — it covers the two
grounds this app is most likely to be rejected on (4.2 minimum functionality and 3.1.1 steering),
which matter more here than the crypto question everyone expects.

Still to build before a submission is realistic:

- [ ] The backend routes (`../IOS-APP.md`, "Backend work this needs")
- [ ] Account deletion — the app asks `/link/delete_account`, which does not exist yet
- [x] A privacy policy — `/privacy/` (DRAFT, needs legal review and a real contact address)
- [ ] A support URL and a monitored contact address
- [x] `PrivacyInfo.xcprivacy` — written; add it to the target. Read its header comment: two of the
      answers are only true because the app has no SDKs, and they stop being true the day it does
- [ ] The App Privacy answers in App Store Connect — they must agree with that manifest
- [ ] Age rating answers
- [ ] A decision on the 500k $CHIKI gate
- [x] Metered connections — the shell watches `NWPathMonitor` and the loader takes the 174 MB pack
      instead of the 313 MB one on cellular or Low Data Mode. The page cannot do this by itself:
      WebKit implements no Network Information API, so `navigator.connection` is undefined on iOS
- [x] Localisation of the surfaces this revision added — the policy refusals, the pairing page and
      the season panel are EN/日本語/中文. **Still English:** the native screens in `Screens.swift`
      (extract to a String Catalog) and the loading-screen panels, which have always been
      English-only markup — the in-game switcher lives inside the compiled pack

---

## Open questions

Honest about what could not be settled without a device or a conversation:

| Question | How to settle it |
|---|---|
| Does `crossOriginIsolated` hold inside a `WKWebView` against the live headers? | §6. Ten minutes on a real device. **Do this first** — everything depends on it. |
| Who owns the Cloudflare COOP/COEP rule? | Ask whoever administers the zone, then write it down in `DEPLOY.md`. It is the app's only load-bearing isolation dependency and it is currently undocumented. |
| Which backend mints tokens in production? | `chiki-ios.js` defaults to `api.chikimonsters.com`; the arena client uses the Render host. If it is the latter, set `window.CHIK_API`. |
| Does the backend bind a token to `device_id` strictly or advisorily? | Ask. If strictly, the device-id stability this shell provides is load-bearing before any public build. |
| Does `sessionStorage` survive a content-process kill and reload? | Boot on a 4 GB phone, force a kill, reload, read `sessionStorage['realm-was-running']`. Determines whether the loader's memory net works on its own. |
