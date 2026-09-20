# Recovering the Chikoria Godot project from the shipped pack

Everything under `godot-patch/` used to be written blind: the `.gd` files here are *proposed*
patches, authored against a game nobody in this repo could read. That is no longer necessary. The
project can be recovered from the pack this repo already publishes, in about a minute, and the
result opens in Godot.

This document records how, what came out, and the three things the recovery settled that guesswork
had got wrong.

## Do not commit the recovered project here

`DEPLOY.md` is explicit: everything tracked in this repo is served at `chikimonsters.com/<path>`.
There is no build step and no server-side filtering. Committing the recovered source would publish
the entire game's source code, including `Chain.gd` and `Net.gd`. Keep it in a **private** repo.

That said — see [What this means for the pack](#what-this-means-for-the-pack) — the pack itself is
already public, so the source is already recoverable by anyone. The private repo protects the
convenience, not the secret.

## The reproduction

Inputs, both from this repo:

| | |
|---|---|
| pack | `realm/index.pck.0.bin` … `index.pck.12.bin`, concatenated in order |
| pack sha256 | `5b7b48d69130d655be7c7fb6a75741cef00709438a0ab850b86968adee78914a` |
| pack size | 313,445,440 bytes, magic `GDPC` |
| build | `1eb4980816` (the `"v"` field of `realm/index.pck.manifest.json`) |

Tool: **Godot RE Tools v2.6.4**, `GDRE_tools-v2.6.4-linux.zip`,
sha256 `eda8cb09e64a060728fa371aa80ae148d3c5584a7de2f553699936daa84e7b4e`.

```sh
# 1. reassemble the pack from the published chunks
cat realm/index.pck.[0-9].bin realm/index.pck.1[0-2].bin > index.pck
sha256sum index.pck        # must match the hash above

# 2. recover
./gdre_tools.x86_64 --headless --recover=index.pck --output=recovered
```

It finishes in about 40 seconds and prints, on success:

> Recovery finished in 00m41s… Use Godot editor version 4.6.0 to edit the project.

Out come **9,708 files / 883 MB** (620 MB excluding `.godot/`): `project.godot`, 128 `.gd` scripts,
11 `.tscn` scenes, and the art tree. No decompiler bailout markers anywhere — `Net.gd` is 3,601
lines, `Chain.gd` 3,041, `Chat.gd` 1,169.

### Verifying it, rather than assuming it

Recovered GDScript is decompiled from `.gdc` bytecode. It is *equivalent*, not identical: comments
and original formatting are gone, and inferred-type declarations come back as `const X: = …`
(valid, just not how a person writes it). So it has to be checked, not trusted.

```sh
godot --headless --path recovered --import                      # full import
godot --headless --path recovered --check-only --script res://Net.gd   # one script
```

Import completes cleanly. Parse-checking every script against **stock Godot 4.6.stable
(`89cea1439`)** gives:

> **82 of 91 root scripts parse clean. 9 fail.**

and every one of the nine fails for the same reason — `VoxelTerrain`, `VoxelMesherCubes`,
`VoxelColorPalette`, `VoxelBuffer`, `VoxelGeneratorScript` are not declared. **Not one failure is a
decompiler artifact.** The recovered code is sound; the stock editor is what is missing something.

## The engine is not stock Godot

This is the part nobody had written down, and it gates everything else.

`project.godot` carries a `[voxel]` section:

```ini
[voxel]
threads/count/ratio_over_max.web=0.0
```

and the project contains **no `.gdextension` file**. That combination means the voxel classes come
from [`godot_voxel`](https://github.com/Zylann/godot_voxel) compiled into the engine as a **C++
module**, not loaded as an add-on.

The shipped WebAssembly confirms it. Reassembling `realm/index.wasm.0.bin` + `index.wasm.1.bin`
(40,092,042 bytes, sha256 `49df352f9b64f7fc5913d6ff2b64c76011de5ea92023b8c3bee463cbca5fcbda`,
magic `\0asm`) and searching for class names:

| symbol | occurrences |
|---|---|
| `VoxelBuffer` | 21 |
| `VoxelTerrain` | 7 |
| `VoxelLodTerrain` | 6 |
| `VoxelMesherCubes` | 5 |
| `VoxelColorPalette` | 4 |
| `VoxelGeneratorScript` | 3 |
| `VoxelMesherTransvoxel` | 3 |
| `MeshInstance3D` (a stock class, for scale) | 9 |

`realm/index.wasm` **is a custom Godot 4.6 build with the voxel module compiled in.**

### Which means there is no download that can rebuild this game

To re-export the web build you need a **web export template** built from that same custom engine.
Checked on 2026-09-20:

- Zylann publishes prebuilt custom Godot builds. Release **v1.6** is
  `Godot 4.6.stable.custom_build` — the exact version. Its eleven assets are editor and template
  builds for **Linux, macOS and Windows only**. There is no web/HTML5/wasm template among them.
- The **GDExtension** edition (v1.6x, for official Godot 4.4.1+) ships binaries for Windows, Linux,
  macOS, iOS and Android — **also no web**.

So the only route to a new pack is to compile Godot 4.6 + `godot_voxel` for the web yourself, with
emscripten. Whoever produced build `1eb4980816` did exactly that, and that toolchain is the real
dependency behind every "just change it in the pack" task below.

```sh
git clone --depth 1 --branch 4.6-stable https://github.com/godotengine/godot.git
git clone --depth 1 https://github.com/Zylann/godot_voxel.git godot/modules/voxel
# then, with the emsdk version Godot 4.6 pins:
scons platform=web target=template_release threads=yes
```

Two cautions before anyone starts. `godot_voxel`'s own `SCsub` still carries
`# TODO Feature: check webassembly builds` — web is not a tested configuration upstream. And the
pack's `[voxel] threads/count/ratio_over_max.web=0.0` and
`[threading] worker_pool/max_threads.web=2` say whoever built it had already been through tuning
that the defaults get wrong.

## What the source settled

Three things this repo believed, corrected by reading the game rather than probing it.

### 1. Chikiseum PvP is already exactly what the iOS app needs — no patch required

`ChikiseumLiveClient.gd` does not merely avoid stakes, it **refuses a server that offers one**:

```gdscript
static func live_contract(data: Dictionary) -> bool:
	return data.get("mode") == "live" and data.get("currency") == "NONE" \
		and data.get("real_sol_enabled") == false and data.get("inventory_verified") == true
```

Every response is checked against it (`if not live_contract(data): _fail(...)`). Practice mode is
`currency: "TEST_CREDITS"` and capped at 1000. **There is no wager route anywhere in the pack** —
the only matches for "wager" in 128 scripts are UI copy saying *"No wagering"*, *"no real SOL"*,
*"Online duels have no wagering."*

So "suspend the wagers, have the server host the match, pay out in-game assets" was already true in
the shipped build. `ChikiseumSeasonClient.gd` and `ChikiseumWagerClient.gd` in this directory were
written against a wager system that does not exist here, and the plan to "add `season_*` routes to
the allowlist" had nothing to add them for.

For the record, the allowlist is real but narrower than it looked. Routes are gated in three
places that must agree — `ROUTES.has(op)` in `_enqueue`, `_valid_web_request_url()`, and a
hardcoded copy of the list inside `LIVE_FETCH_GUARD_JS` — but that JS guard only judges requests
carrying an `X-Chikiseum-Live-Owner` header and passes everything else straight through. It is
request de-duplication and hardening for the live client, not a site-wide allowlist.

### 2. The loader could not have known about two egress paths

Both are now fixed in `realm/chiki-ios.js`; both were found by reading `Chain.gd`.

- **`navigator.sendBeacon`** — `Chain.gd` registers a `pagehide` flush that tries `sendBeacon`
  first and only falls back to `fetch`. The fetch fallback was guarded; the beacon was not.
- **`__chikiPkErr`** — `Chain.gd` injects its own sign-in JS and, when no wallet provider is
  present, sets the error to `'Phantom not found — get it free at phantom.app'`, which the pack
  shows the player verbatim. Because the policy layer is what makes the provider absent, that was
  the *only* outcome of pressing sign in inside the app.

### 3. The pack ignores `window.CHIK_FEATURES` entirely

Searching all 128 scripts for the loader's flags returns **nothing** for `CHIK_FEATURES`,
`CHIK_NO_CRYPTO`, `CHIK_IOS_APP` or `CHIK_HD`. The one window flag the pack does read is
`window.CHIK_PHONE` / `CHIK_TABLET`, via `TempleMobileViewport.gd`, which also honours a
`window.CHIK_MOBILE_VIEWPORT()` function if one exists.

So the flags published in `chiki-ios.js` §2 are advisory exactly as that file says, and making the
pack act on them is a rebuild, not a configuration change.

## What still needs a rebuild

Everything below is invisible to the loader, because it is GDScript drawing its own UI. Each one
needs the custom web export template above.

| what | where | why it matters |
|---|---|---|
| **The Trading Post is visible in the app** | `GameHUD.gd` — a full marketplace with a `🪄 Magic Eden` tab, *"Pay N real $CHIKI from your wallet — you'll approve in Phantom"*, *"75% → your Phantom wallet as REAL $CHIKI"* | `open_market()` refuses only in demo mode. It is a **world location**: a player walks to it (`Player.gd`, near x +52 / z +120) and it opens. The buttons all fail in the app, but the storefront is on screen. |
| **The Cup advertises real SOL** | `Chikiseum.gd` — *"champions win real SOL"* (in the HOW TO PLAY tab, unconditional), *"Pool of 4 SOL split across top placements"*, *"🔒 Link your wallet first (the Cup pays real SOL)"* | Static labels, drawn regardless of any server data, so blocking `/cup/*` does not remove them. |
| Report and block in chat | `Chat.gd` | 1,169 lines with no report, block, mute or filter of any kind. The profanity mask is server-side (`cleanText()`), not here. Moot while chat is blocked outright in the app, and required the moment it is turned back on. |
| Pack reads `CHIK_FEATURES` | anywhere | Would let the pack hide what the loader disables, instead of the loader hiding it from outside. |

The first two are App Review problems, not cosmetic ones: guideline 3.1.1 is about what an app
*presents* as a way to transact, not only about what it can execute. The policy layer has made
buying impossible; it cannot make the shop invisible.

## What this means for the pack

`realm/index.pck.*.bin` is served publicly at `chikimonsters.com/realm/`. Anyone can do what this
document describes, with a public tool, in a minute. That is worth knowing on its own terms:

- **The game's client source is effectively public.** Treat `Chain.gd`, `Net.gd` and the rest as
  readable by anyone — including every backend URL, route name and client-side check in them.
- **Client-side checks are not security.** `live_contract()` and the fetch guard are good
  engineering, and an attacker reads them as easily as we just did. The server has to be the one
  enforcing the contract; the live client already assumes that, which is the right shape.
- **This is normal for a web export**, not a failure. Every shipped browser game is in the same
  position. The useful response is to keep secrets on the server, not to try to hide the pack.
