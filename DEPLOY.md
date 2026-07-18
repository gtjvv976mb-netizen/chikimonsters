# Deploying chikimonsters.com

This repo IS the live site (GitHub Pages, `CNAME` → chikimonsters.com).

- **Homepage:** `index.html` — press the $CHIKI token → intro video → routes into the 3D MMO at `realm/`.
- **The MMO:** `realm/` — a Godot 4.6 web export. Big engine files are split into ≤24 MB chunks
  (`index.pck.0…10`, `index.wasm.0…1`) so GitHub's 25 MB web-uploader accepts them. The loader
  (`realm/index.html`) streams the chunks back into one Blob at runtime, using a per-build cache
  stamp (`?v=…`) so browsers never mix old + new chunks.

## Updating the game (the usual case)

A game change only rebuilds `realm/`. Nothing else in the repo changes.

**Current build: `v=c5d9741992`** (Connect-Wallet pop redesign — wallet-icon hero, three HD icon feature cards (earn/whale-bonus/safe), a big balance card with tier badge when connected; all info-bar pops now hug their content (no dead space). Backend /verify fix ships separately in the `backend` repo.
solid wall with one clean road-width arched opening each; remote-trainer avatars can no longer perch
on the wall top. Prior: fishes moved inside Inventory (Normal/Fantasy tabs) + full fantasy-fish
descriptions in the Catalog; fantasy-fish trainer-level gates Lv5/10/15/20; thin matched-height HUD
minibars with have/need craft chips; quest shows the next objective.
Prior: voxel puffy clouds — replaced the flat white slabs, plus slow drift; Trading Post banner-above +
Buy-tab categories; P2P economy sim + cheat-proofing —
phantom-buyer $CHIKI-mint closed, save signature v3 seals fish/roster/listings/mounts/avatars,
list→cancel goods-loss + XP-farm fixed; shops overhaul — free hospital heal-queue, multi-category
Trading Post, avatars have no HP/attack, shorter right tabs).

1. Re-upload the **whole `realm/` folder** (23 files, all ≤24 MB). The critical version-stamped
   files that MUST go up together: `index.pck.0…10`, `index.wasm.0…1`, `index.pck.manifest.json`,
   `virtual-files.json`.
2. That's it — the `?v=` stamp busts caches automatically; players get the new build on next load.

## First-time / full deploy

Upload the whole repo. Required for serving: `index.html`, `realm/`, `ui/`, `chikidex/`, `audio/`,
`models.js`, `intro.mp4`, `homepage-hero.png`, `.nojekyll`, `CNAME`.

**In GitHub → Settings → Pages, turn on "Enforce HTTPS."** The realm needs a secure context
(SharedArrayBuffer/threads via the cross-origin-isolation service worker); an `http://` hit can't
register the service worker.

## Not part of the site (safe to leave out of an upload)

These are unreferenced by `index.html` / `realm/` — local source & backups only, now in `.gitignore`:
`blockbench/` (Blockbench source), `_old_meme_art/`, `ui 2/` + `ui 3/` (duplicate copies of `ui/`),
`ui-cards.zip`, `homepage-hero-old.png`, `homepage-hero-orig-backup.png`, `intro-old.mp4`,
`_cup_full_transparent.png`, `*.litematic`, and the orphaned pages `play.html` /
`chikoria-world.html` / `chikiseum-demo.html`. Deleting them locally would slim the repo by ~77 MB,
but they're your source/backups so that's your call.
