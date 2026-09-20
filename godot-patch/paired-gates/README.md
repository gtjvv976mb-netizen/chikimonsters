# Wicked Temple and Chikiseum gate release source

This is the reviewed Godot source delta for both entry gates. Copy these files to
the **root** of the complete `game/` project before rebuilding. This folder is
not a standalone project. The four button PNGs are text-free, transparent
Higgsfield-directed art; labels, focus rings, touch targets, signals, wallet and
reward logic remain native controls. `GateButtonArt.gd` trims transparent canvas
in memory, nine-slices only the plate, and leaves a functional fallback skin if
an asset is unavailable.

The public web shell (`realm/index.html` and `index.js`) and both WebAssembly
chunks are unchanged from official frontend `main` at
`fb095ca6ffccb310d6f28d538b9d3f33f4bc12b9`. This patch replaces only the
HD/mobile Godot data chunks and their cache-stamped manifests. It does not
change PvP backend contracts, creature sheets, ability atlases, cards, reward
rules, or game-world geometry.

| Release check | Result |
| --- | --- |
| HD | stamp `51623df109`, SHA-256 `40af5947938cb8257670ae4e0f5c250bc31bff9da8895ac965f8692fbe43d416`, 13 chunks |
| Mobile-lite | stamp `a4422f379f`, SHA-256 `744a6ab36acbadc7394384b58cfeb0c7e9af3868f7715efab4013e8e7e8d8f9c`, 8 chunks |
| Mobile transport | 176,258,845 bytes (168.1 MiB), below 170 MiB cap |
| Button art | four RGBA PNGs present as imported Godot textures in both packs; 1,925–1,926 × 817 HD, half-size mobile |
| Packed scripts | Temple, RebornDeployment, ChikiseumEntry, and GateButtonArt all have compiled remaps in both packs |
| Card preservation | all 402 card/mask bindings exact; original creature, ability, and Reborn sheets preserved |

Focused native checks passed: button art/fallback, Chikiseum gate safe area
(60/60), Wicked Temple gate layout (1,480/1,480), mobile entry/reward
(30/30), and Grimwick story/entry (1,885/1,885). The complete controlled
HD/lite export and chunk reconstruction passed
`verify_chikiseum_live_export.py`; its append-only receipt is
`release-verification.json` (SHA-256
`31c93dab91b78111aaa4a2377204bd42ae74f65949bc9714de95dcfe3747bf6a`).
This receipt proves package/source/chunk integrity, not a browser session or
authenticated public PvP battle.
