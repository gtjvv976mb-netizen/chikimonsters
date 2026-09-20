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

Which the next section then confirms outright: against an editor that *does* carry the voxel
module, the same project imports with **zero parse errors**. All 91. Treat "82 of 91" as a
measurement of the wrong editor, not of the recovery.

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

### The engine can be rebuilt — this was done, not assumed

An earlier version of this section said no download could rebuild the game and left it there. That
was half right and unhelpfully pessimistic. The full pipeline has now been run end to end.

**The editor does not need building.** Zylann ships prebuilt custom Godot builds, and release
**v1.6** reports itself as:

```
4.6.stable.custom_build.89cea1439
```

`89cea1439` is *the same commit as stock 4.6-stable*. So it is the stock engine plus the voxel
module — exactly what this project needs — and `godot.linuxbsd.editor.x86_64.zip` (68.5 MB) is a
download, not a build.

**Only the web export template has to be compiled**, because that is the one platform Zylann's
release does not ship and the GDExtension edition has no binary for. On four cores:

```sh
git clone --depth 1 --branch 4.6-stable https://github.com/godotengine/godot.git godot-src
git clone --depth 1 https://github.com/Zylann/godot_voxel.git godot-src/modules/voxel
git clone --depth 1 https://github.com/emscripten-core/emsdk.git
./emsdk/emsdk install latest && ./emsdk/emsdk activate latest
source ./emsdk/emsdk_env.sh
cd godot-src && scons platform=web target=template_release threads=yes -j4
```

| | |
|---|---|
| time | **12m 04s**, 4 cores |
| emscripten | 6.0.9 (`4e42238`) — Godot 4.6 requires ≥ 4.0.0 |
| `godot_voxel` | `master` at `c8c3411`; there is no `godot4.6` branch, and master built without a patch |
| template | `bin/godot.web.template_release.wasm32.zip`, 10,121,978 bytes, sha256 `bc538e750bf517588b3c8f882b0f03ff21ac0cb57ee8a80dfc2176445765d86d` |
| engine | `godot.web.template_release.wasm32.wasm`, 39,071,527 bytes (shipped: 40,092,042) |

It is the right engine, checked the same way the shipped one was — by counting registered class
names in the binary:

| symbol | built here | shipped |
|---|---|---|
| `VoxelBuffer` | 20 | 21 |
| `VoxelTerrain` | 6 | 7 |
| `VoxelLodTerrain` | 6 | 6 |
| `VoxelMesherCubes` | 5 | 5 |
| `VoxelColorPalette` | 4 | 4 |
| `VoxelGeneratorScript` | 3 | 3 |
| `VoxelMesherTransvoxel` | 3 | 3 |
| `MeshInstance3D` (stock, for scale) | 9 | 9 |

The small differences are module drift between `master` and whatever commit built `1eb4980816`.
The `# TODO Feature: check webassembly builds` in `godot_voxel`'s `SCsub` is still there; web is
still not a tested configuration upstream; it still compiled first time.

**With the voxel editor, the recovered project imports with zero parse errors.** All 91 scripts.
The nine failures reported above are entirely an artefact of checking against the *stock* editor,
and nothing is wrong with the recovered code at all.

**And a full web export completes:**

```sh
godot --headless --path <project> --export-release "Web" out/index.html
```

`index.pck` 371,701,536 bytes, `index.wasm`, `index.js`, the audio worklets and the icons — a
complete, mountable build. (No `export_presets.cfg` survives in a pack, so one has to be written;
the Web preset needs `variant/thread_support=true` and `custom_template/release` pointing at the
zip above.)

### The card audit fails — and it is a provenance gate, not a functional one

The export finishes, and the project's own export plugin refuses to bless it:

```
ERROR: CHIKISEUM_CARD_EXPORT_REJECTED: Approved original or mask bytes changed: adalor:0
```

`addons/chikiseum_export/export_plugin.gd` audits **402 Chikiseum cards** against a pinned
manifest, comparing `FileAccess.get_sha256(original)` to an approved `source_sha256` for each. It
fails on the first card.

Auditing every file the manifest pins, **taken raw out of the pack** rather than through the
decompiler, says exactly what is missing:

| | result |
|---|---|
| `card-presentation-v4/manifest.json` | **byte-identical** to the pinned `354b8bb8…` |
| the 402 masks (`card-presentation-v4/masks/*.png`) | **402 byte-identical, 0 differ** — and they total 839,504 bytes, exactly the plugin's `RAW_MASK_BYTES` |
| the 402 originals (`res://cards/10_0.jpg` … `50_9.jpg`) | **not in the pack at all.** Only their `.import` stubs are, all 402 of them |

Nothing is corrupted. The masks and the manifest come back perfect. What is missing is exactly
**402 original card JPEGs**, which were never in a pack to begin with — Godot ships the imported
`.ctex`, not the artist's source.

**A practical trap, since it produced the wrong answer first.** GDRE's `--recover` reconstructs
source images from imported textures, and it does that for the masks too — overwriting raw PNGs
that were already perfect with re-encodes that are not. Use `--extract` for anything whose exact
bytes matter:

```sh
./gdre_tools.x86_64 --headless --extract=index.pck --output=extracted   # 5464 files, verbatim
```

`--recover` is right for getting a project that opens; `--extract` is right for getting bytes.

#### What the failure actually costs: less than it sounds

An earlier draft of this file called the artwork "the real blocker" and said a rebuild was gated
on getting those 402 files. **That was wrong, and booting the rebuilt pack is what showed it.**

Read what the runtime does with a binding it cannot verify. `ChikiseumCardPresentation._prepare()`
does not fail — it degrades, deliberately, and says so in the field name:

```gdscript
receipt.reason = "source_binding_changed_original_preserved"
```

The original card texture is **preserved and displayed**; what is skipped is the mask-based
cleaning applied on top of it. Every branch in that function ends in `…original_preserved`. It was
written to survive exactly this.

Confirmed by running it. The rebuilt pack was served cross-origin-isolated and opened in Chromium:
the engine starts, the world renders, the offline Action Lab opens, and **Adalor — the species the
audit rejects by name — renders correctly with all twelve of its ability cards**.

And PvP is untouched. `ChikiseumLiveClient.valid_bindings()` compares the *server's* response to
client constants (`CATALOGUE_SHA256`, `ART_SHA256`, `ART_VERSION`, `Nav.binding()`). A rebuild
changes neither side of that comparison.

So, precisely:

- **Verified:** the rebuilt pack boots and plays, including the rejected species.
- **From the code:** a failed binding keeps the original art and skips the cleaning pass — a
  cosmetic difference in Chikiseum card exteriors.
- **Not verified:** a side-by-side of one card exterior with and without that cleaning. If the
  difference matters to you, look at that before shipping.

**Get the 402 JPEGs when you can** — they restore exact provenance and make the plugin bless the
build again. They are not a prerequisite for shipping one.

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

### The change itself is written and verified — `apply-ios-pack-patch.py`

The first two rows are done, as far as they can be done without a template:

```sh
python3 godot-patch/apply-ios-pack-patch.py <recovered-project> --check   # dry run
python3 godot-patch/apply-ios-pack-patch.py <recovered-project>
godot --headless --path <recovered-project> --import                     # not optional
```

It is a patcher rather than a diff on purpose: the tree it edits is recovered game source that
must not be committed here, so this repo carries the instruction, not the code. Five changes, all
gated on the loader's published policy and therefore no-ops on the website:

1. `ChikFeat.gd` — a small reader for `window.CHIK_FEATURES`, which is the `CHIK_FEATURES` row of
   the table above, and the thing the other changes are built on.
2. `GameHUD.open_market()` refuses when `trading_post` is off. That one function is the *only* way
   into the marketplace — `Player.gd` is its sole caller — so gating it takes the Magic Eden tab
   and every Phantom purchase string with it.
3. The Chikiseum drops its **Chikoria Cup** tab, opens on My Deck instead, and stops claiming
   "champions win real SOL" in HOW TO BATTLE.
4. The wallet gate in `Onboarding._show_gate()` stops naming Phantom and stops drawing its
   **"Get Phantom ↗"** button, which points at `phantom.app`. That screen should be unreachable in
   the app — Realm Link signs the player in first — but it *is* reached when a link is rejected or
   `/verify` fails. The button already goes nowhere (`OS.shell_open` compiles to `window.open`,
   which §3b guards, verified in `realm/index.js`: `window.open(GodotRuntime.parseString(p_uri))`),
   so this is about what is on screen, not what it does.
5. The token gate stops saying **"Hold 500,000 $CHIKI to enter."** — an instruction to go and
   acquire half a million units of a crypto token in order to play an App Store app — and drops
   the "Check balance again" button whose only remedy is buying some.

   **Words only.** Whether an app player needs the hold at all is an open product decision
   (`IOS-APP.md`) and the server's to enforce either way, so the gate still closes exactly when it
   closed before. It just refuses readably instead of naming a token, an amount and a reason to go
   shopping.

PvP is untouched: the duels are already stake-free.

**Verified, not assumed.** Applied to the recovered project and parse-checked against stock Godot
4.6: `ChikFeat.gd`, `GameHUD.gd`, `Chikiseum.gd` and `Onboarding.gd` all parse clean, and a full
sweep of the patched tree gives the same 9 voxel failures as before and no new ones. The script is idempotent, and
refuses to write anything if an anchor does not match exactly once — it was written against build
`1eb4980816` and should not be trusted to guess at a different one.

One gotcha, because its symptom is misleading: **re-import before checking.** `ChikFeat.gd`
declares a `class_name`, and a global class is only registered when Godot rescans the filesystem.
Skip the rescan and both patched scripts fail with `Identifier "ChikFeat" not declared in the
current scope`, which reads like a broken patch and is not one.

### A rebuilt pack is a new build, not a patched one

Worth saying before anyone exports and ships the result. Exporting the recovered project does not
reproduce `1eb4980816`; it produces a **new** build that happens to contain the same game:

- Assets are re-imported from the recovered originals with whatever import settings the recovered
  `.import` files carry. Texture compression, mesh settings and audio can all come out different —
  and the measured difference is not small: `index.pck` came out 371,701,536 bytes against the
  shipped 313,445,440.
- The GDScript is decompiled, so it is equivalent rather than identical.
- The engine would be your emscripten build, not whoever's built `1eb4980816`.
- **The Chikiseum card audit fails**, and that one is not a QA risk but a known defect — see
  "The real blocker is the card artwork" above.

That is a QA job, not a drop-in replacement, and it should be played through before it reaches
players. Keep the current chunks until the new ones have been.

Chat's report and block are deliberately not in the script. They are a feature, not a few lines,
and they are moot while the app refuses every chat route.

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
