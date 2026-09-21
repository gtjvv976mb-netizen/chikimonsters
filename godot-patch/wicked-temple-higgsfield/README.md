# Wicked Temple visual release source

This is the Godot source snapshot for the Wicked Temple gate, combat HUD, reward
ceremony, and brighter 3D room. Copy these files to the **root** of the complete
Godot `game/` project before rebuilding; this folder is not a standalone project.
The two new PNGs are the Higgsfield-directed Temple UI artwork, kept as separate
runtime assets with their Godot `.import` settings. The original creature sprites,
ability sheets, card faces, reward rules, and Chikiseum network contracts were not
replaced by this visual release.

The published realm HTML loader and `index.js` stay exactly as they were on
official frontend `main` at `3bb89430b2292fc0bf2e3a6910466eade7a974cc`.
Only the packaged Godot data chunks and their manifests are updated. The WebAssembly
chunks are byte-identical to that main release.

| Release check | Result |
| --- | --- |
| HD pack stamp | `43de4bb195` (13 chunks) |
| Mobile-lite pack stamp | `757e8afb52` (7 chunks) |
| Mobile runtime | 167.2 MiB, below 170 MiB cap |
| Imported gate art | HD 1168×880; mobile 584×440 |
| Imported wheel art | HD 1254×1254; mobile 627×627 |
| Wheel alpha | HD 1,119,296 clear/453,220 painted pixels; mobile 280,764 clear/112,365 painted |
| Original sprite preservation | 68 creature sheets, 24 ability sheets, 434 Reborn sheets byte-for-byte |
| Card preservation | All 402 card and mask bindings exact |

The two art files were loaded directly from the final HD and mobile Godot packs in
an empty audit project; the alpha counts above come from the decoded runtime
textures, not merely the source PNGs. The controlled exports and chunked release
passed `verify_chikiseum_live_export.py`; see `release-verification.json` for the
release receipt. This verification does not claim a browser, device, or live PvP
session was tested.
