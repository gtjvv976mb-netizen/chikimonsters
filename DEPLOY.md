# Deploying chikimonsters.com

## What serves what

| URL | served by | comes from |
|---|---|---|
| `chikimonsters.com/` | **GitHub Pages**, behind Cloudflare | this repo (`CNAME` → chikimonsters.com) |
| `chikimonsters.com/realm/` | same | `realm/` in this repo |
| `chikimonsters.com/realm/chikiseum-test-1eb4980816/` | **Cloudflare Workers static assets** | **not this repo** — see below |

The first two are what this document is about: editing them here and publishing Pages puts them
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

**Current build: `a4b9b46510`** (desktop pack) and **`b238eae98c`** (mobile/lite pack).
These are the `"v"` fields in the manifests — read them, don't trust this line:

```sh
python3 -c "import json;print(json.load(open('realm/index.pck.manifest.json'))['v'])"
python3 -c "import json;print(json.load(open('realm/index.pck.lite.manifest.json'))['v'])"
```

### Upload the whole `realm/` folder — all 42 top-level files, plus `realm/reborn-art/`

Do not upload a subset. A partial upload does not fail loudly: the loader assembles whatever
chunks it gets and mounts a pack that is quietly wrong.

The version-stamped files that **must** go up together, and all of them:

| group | files | count |
|---|---|---|
| desktop pack | `index.pck.0.bin` … `index.pck.12.bin` | **13** |
| mobile/lite pack | `index.pck.lite.0.bin` … `index.pck.lite.7.bin` | **8** |
| engine | `index.wasm.0.bin`, `index.wasm.1.bin` | 2 |
| manifests | `index.pck.manifest.json`, `index.pck.lite.manifest.json`, `virtual-files.json` | 3 |
| loader + engine glue | `index.html`, `index.js`, `coi-serviceworker.min.js`, `index.audio.worklet.js`, `index.audio.position.worklet.js`, `solana-web3.js` | 6 |
| loading screen | `loading.png`, `loading_font.ttf`, `hero.jpg`, `coin.png` | 4 |
| icons + media | `index.png`, `index.icon.png`, `index.apple-touch-icon.png`, `after_loading.mp4` | 4 |
| content | `updates.json` | 1 |
| art tree | `realm/reborn-art/` (a whole directory) | — |

Verify before you publish:

```sh
ls realm/index.pck.[0-9]*.bin      | wc -l   # 13
ls realm/index.pck.lite.[0-9]*.bin | wc -l   # 8
ls realm/index.wasm.[0-9]*.bin     | wc -l   # 2
ls realm/ | wc -l                            # 42 (+ reborn-art/)
```

The build stamp busts caches automatically; players get the new build on their next load.

## First-time / full deploy

Upload the whole repo. Required for serving: `index.html`, `realm/`, `ui/`, `chikidex/`, `audio/`,
`models.js`, `intro.mp4`, `homepage-hero.png`, `.nojekyll`, `CNAME`.

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

`/quest/claim` **does not transfer tokens.** `server.js` is explicit at the route:

> `POST /quest/claim` — STATUS ONLY (payouts are an admin batch, never user-triggered).
> No token transfer here.

Claim reports status; payouts are a manual admin-signed batch. Any page copy or release note
saying Claim pays on-chain is wrong and should be corrected rather than repeated here.

## Also in the repo, not linked from the site

`play.html` is **tracked in this repo and served** — `https://chikimonsters.com/play.html` returns
200. It is not reachable from `index.html` or `realm/`, but it is public. It is not in `.gitignore`;
`.gitignore` contains only `.DS_Store` and `*.dump`. Decide deliberately whether to keep publishing
it rather than assuming it is already excluded.
