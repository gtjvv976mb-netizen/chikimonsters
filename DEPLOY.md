# Deploying chikimonsters.com

## What serves what

| URL | served by | comes from |
|---|---|---|
| `chikimonsters.com/` | **GitHub Pages**, behind Cloudflare | this repo (`CNAME` → chikimonsters.com) |
| `chikimonsters.com/realm/` | same | `realm/` in this repo |
| `chikimonsters.com/link/` | same | `link/` in this repo — pairs the iOS app to an account |
| `chikimonsters.com/realm/chikiseum-test-1eb4980816/` | **Cloudflare Workers static assets** | **not this repo** — see below |

The first three are what this document is about: editing them here and publishing Pages puts them
live. Confirm with `curl -I https://chikimonsters.com/` — the response carries
`x-github-request-id`, `via: 1.1 varnish` and `x-served-by: cache-iad-…`. Cloudflare fronts it, but
the origin is Pages.

The third is **not served from this repo at all**, so editing it here changes nothing for players.
It is a Cloudflare Workers deployment (`deploy/chikiseum-1eb4980816/release.json` on the
`codex/chikiseum-canary-1eb4980816` branch records `"hosting": "Cloudflare Workers Direct Static
Assets"` and `"observed_deployment": "d68b7d7b"`). That branch is a frozen, receipt-verified record
of what is live there; it is not a source tree to edit. Its README also says, in capitals, not to
merge its 649 MB runtime into this repo.

- **Homepage:** `index.html` — press the $CHIKI token → intro video → routes into the 3D MMO at `realm/`.
- **The MMO:** `realm/` — a Godot 4.6 web export. The engine files are split into ≤24 MB chunks so
  GitHub's 25 MB web uploader accepts them; `realm/index.html` streams them back into one Blob at
  runtime, stamping every chunk URL with the build hash so browsers never mix old and new chunks.

## Updating the game (the usual case)

A game change only rebuilds `realm/`. Nothing else in the repo changes.

**Current build: `1eb4980816`** (desktop pack) and **`9117070a6d`** (mobile/lite pack).
These are the `"v"` fields in the manifests — read them, don't trust this line. It had drifted
once already: it still named `a4b9b46510` / `b238eae98c` long after PR #5 promoted `1eb4980816`.

```sh
python3 -c "import json;print(json.load(open('realm/index.pck.manifest.json'))['v'])"
python3 -c "import json;print(json.load(open('realm/index.pck.lite.manifest.json'))['v'])"
```

### Upload the whole `realm/` folder — all 41 top-level files, plus `realm/reborn-art/`

Do not upload a subset. A partial upload does not fail loudly: the loader assembles whatever
chunks it gets and mounts a pack that is quietly wrong.

The version-stamped files that **must** go up together, and all of them:

| group | files | count |
|---|---|---|
| desktop pack | `index.pck.0.bin` … `index.pck.12.bin` | **13** |
| mobile/lite pack | `index.pck.lite.0.bin` … `index.pck.lite.6.bin` | **7** |
| engine | `index.wasm.0.bin`, `index.wasm.1.bin` | 2 |
| manifests | `index.pck.manifest.json`, `index.pck.lite.manifest.json`, `virtual-files.json` | 3 |
| loader + engine glue | `index.html`, `index.js`, `chiki-ios.js`, `coi-serviceworker.min.js`, `index.audio.worklet.js`, `index.audio.position.worklet.js`, `solana-web3.js` | 7 |
| loading screen | `loading.png`, `loading_font.ttf`, `hero.jpg`, `coin.png` | 4 |
| icons + media | `index.png`, `index.icon.png`, `index.apple-touch-icon.png`, `after_loading.mp4` | 4 |
| content | `updates.json` | 1 |
| art tree | `realm/reborn-art/` (a whole directory) | — |

Verify before you publish:

```sh
ls realm/index.pck.[0-9]*.bin      | wc -l   # 13
ls realm/index.pck.lite.[0-9]*.bin | wc -l   # 7
ls realm/index.wasm.[0-9]*.bin     | wc -l   # 2
ls -p realm/ | grep -v /           | wc -l   # 41 files, + reborn-art/
```

> These counts were wrong in this document until `chiki-ios.js` was added: it claimed 8 lite
> chunks against a 7-chunk pack, and 42 top-level files against a folder holding 40 files plus
> `reborn-art/`. It is 41 files now because this change adds one. Count them, don't trust the
> table either.

**`chiki-ios.js` is not optional.** It is the first script `index.html` loads, and it is the only
thing that takes the wallet, the marketplace and off-origin requests away from the native iOS
app. Publishing `index.html` without it means the app boots with the Trading Post live. See
`IOS-APP.md`.

The build stamp busts caches automatically; players get the new build on their next load.

### After promoting an export, re-apply the policy wiring

**Promoting a new Godot export overwrites `realm/index.html`**, and that file carries every hook
the iOS app depends on. Losing one does not fail loudly — the app simply ships a working Phantom
bridge again. Run the tripwire before you publish:

```sh
node godot-patch/verify/loader-policy.test.mjs   # exits non-zero if a hook is missing
node godot-patch/verify/chiki-ios.test.mjs       # the policy layer itself
```

It names each missing hook. `IOS-APP.md` has what each one is and why.

## First-time / full deploy

Upload the whole repo. Required for serving: `index.html`, `realm/`, `link/`, `ui/`, `chikidex/`,
`audio/`, `models.js`, `intro.mp4`, `homepage-hero.png`, `.nojekyll`, `CNAME`.

`link/` is where a player pairs the iOS app to their account; the app sends them to
`chikimonsters.com/link/` by name, so it has to be live before the app ships.

**In GitHub → Settings → Pages, turn on "Enforce HTTPS."** The realm needs a secure context
(SharedArrayBuffer/threads via the cross-origin-isolation service worker); an `http://` hit can't
register the service worker.

## Pages, and why the arena is not here

GitHub Pages has a published-site budget, and this repo is already large. The realm loader's own
source records what happened the last time a full pack was committed per release:

> Committing a fresh ~370MB of chunks on every release grew .git to about 45GB and GitHub Pages
> stopped publishing entirely — nothing reached players for a day.

That is why the Chikiseum staging build lives on Cloudflare and why its release branch must not be
merged here.

## Rewards: what the server actually does

`/quest/claim` **does not transfer tokens.** The backend is explicit at the route (it lives in the
backend repo, not here — see the section below):

> `POST /quest/claim` — STATUS ONLY (payouts are an admin batch, never user-triggered).
> No token transfer here.

Claim reports status; payouts are a manual admin-signed batch. Any page copy or release note
saying Claim pays on-chain is wrong and should be corrected rather than repeated here.

## Never put backend source in this repo

Everything tracked here is published at `chikimonsters.com/<path>` by Pages. There is no build step
and no server-side filtering: a file in this repo is a file on the public web.

This repo used to carry four Node modules at its root — `server.js`, `cup-live.js`,
`cup-resolver.js` and `pvp-engine.js` — left over from when it doubled as the backend source tree.
All four were served, `chikimonsters.com/server.js` returning 123,932 bytes of backend source. They
were unreferenced (no shipped page loaded them, and they are Node ESM that a browser cannot run) and
long stale — the published `server.js` was 1,893 lines against the live backend's 19,064. They
contained no credentials, but they did publish the payout, Cup-resolution and PvP logic in full.
They were removed; the live copies are in the backend repo and deploy to Render.

If you need to read backend code, read it in the backend repo. Do not copy a module here "to have
it handy" — that publishes it.

## `play.html`

Still tracked and served, deliberately. It is a redirect stub: a `<meta refresh>` plus
`location.replace("/realm/")`, so every old link, bookmark and post lands in the realm instead of a
dead page. The original game it replaced is in git history at `e64e939`. Keep it.
