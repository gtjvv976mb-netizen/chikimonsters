# Chiki Monsters

A 3D voxel MMO set in Chikoria, tied to the **$CHIKI** Solana memecoin. Players raise chikimon,
gather and craft across the island, clear the Wicked Temple and fight each other in the Chikiseum.

This repo is the **static site**: pure files, no build step, published by GitHub Pages. The live
game at `/realm/` is a **Godot 4.6 web export** built from a custom engine — Godot 4.6 with the
`godot_voxel` module compiled in. The project source is not in any repository, but it can be
recovered from the published pack: `godot-patch/RECOVERY.md` has the reproduction, and why a
rebuild still needs a web export template that nobody ships. The original Three.js
build this repo started as is retired; `play.html` is now a redirect stub to `/realm/`, and the
game itself is in git history at `e64e939`.

## Run locally
Serve the folder over HTTP — `file://` will not work:

```bash
python3 -m http.server 8080
# then open http://localhost:8080
```

`index.html` is the homepage; it routes into the realm. The realm needs a **secure context** for
SharedArrayBuffer/threads, so over plain `http://` it only runs on `localhost`.

## Deploy (GitHub Pages)
1. Push this folder to a GitHub repo.
2. Settings → Pages → Build from branch → `main` / root.
3. Your game will be live at `https://<user>.github.io/<repo>/`.

## Structure
| File | Purpose |
|------|---------|
| `index.html` | Homepage (tabs, hero, Play button) |
| `realm/`     | The live 3D MMO — a Godot 4.6 web export, split into chunks. See `DEPLOY.md` |
| `link/`      | Pairs the iOS app to a Chikoria account. See `IOS-APP.md` |
| `arena/`     | A plain web client for the Chikiseum live routes (a test surface, not the game) |
| `godot-patch/` | Drop-in Godot scripts for the arena, plus the verification harnesses |
| `play.html`  | Redirect stub → `/realm/` (keeps old links alive) |
| `models.js`  | All voxel models (chikimons, boat, tree, mailbox, hive, berry, arena) embedded as base64 |
| `intro.mp4`  | Intro cinematic |
| `homepage-hero.png`, `play-now.png`, `splash.png` | Homepage art |
| `ui/`        | In-game tab/button/frame images |

## The iOS app

The native app is the same realm on the same account, with the money taken out: gathering, the
Wicked Temple and Chikiseum PvP, but no wallet, no trading and no wagers. What a player earns
there is the real asset on their real account — they just sell and trade it on the website.

The shell itself is not in this repo; what is here is the policy that makes the guarantee hold
(`realm/chiki-ios.js`), the pairing page (`link/`) and the stake-free PvP client
(`godot-patch/ChikiseumSeason*.gd`). **`IOS-APP.md` is the whole spec** — the native shell
contract, the backend routes it needs, and what is enforced where.

```sh
node godot-patch/verify/chiki-ios.test.mjs      # the app's crypto lockdown + account sync
node godot-patch/verify/loader-policy.test.mjs  # that realm/index.html still wires it up
```

`APPSTORE.md` is the App Store submission kit, and `ios/README.md` builds the shell.

> This README used to end by saying wallets, $CHIKI balances and SOL payouts were simulated. That
> has not been true of `/realm/`, which runs against the live backend; the line is dropped rather
> than left to mislead.

## The native shell

`ios/` holds the complete Swift source for the iOS app and a step-by-step build guide. There is no
`.xcodeproj` — it is machine-generated and would be stale within a week; `ios/README.md` walks
through creating one and adding these four files.

The shell is not in this repo's deploy path: nothing under `ios/` is needed to serve
chikimonsters.com. It lives here so the web policy and the native policy stay in one place, because
each is load-bearing for the other.
