# Chikiseum gate and duel HUD release source

This folder is the Godot source snapshot used for the packaged Chikiseum UI update. Apply it after the prior `godot-patch/traits` release; copy the files to the root of the Godot `game/` project. It changes presentation only: the verified fighter admission, real-time combat, wallet, payment, and reward contracts are unchanged.

The gate panel keeps the official Chikiseum banner and adds the new stone-and-crystal frame. The duel header and health rail polish are in `ChikiseumDuelHUD.gd` and `ChikiseumCrystalHealthBar.gd`; `ChikiseumArena.gd` contains the waiting-lobby presentation update. The generated frame is bundled in both web exports with `chikiseum_gate_frame.png.import`.

Packaging source was an isolated copy of `wicked-reborn/game`. Godot 4.6 `4.6.stable.custom_build.89cea1439` produced the HD PCK and mobile-lite PCZ, then `split_for_github.py` emitted 24 MiB chunks. The existing official `realm/index.html` loader was deliberately retained from `main` to preserve its mobile, accessibility, sign-in, and same-origin loading fixes.

| Release check | Result |
| --- | --- |
| HD manifest stamp | `c22f8763a6` |
| Mobile manifest stamp | `c59fc00673` |
| HD chunks | 13, each <= 24 MiB |
| Mobile chunks | 7, each <= 24 MiB |
| Gate texture runtime load | HD 1024×1024; mobile 512×512 |
| Mobile sprite preservation | 68 creature sheets and 24 ability sheets byte-for-byte |
| Mobile card preservation | 402 card art and mask pairs verified |
| Mobile runtime size | 166.7 MiB, under 170 MiB cap |

Gate frame SHA-256: `cd0b5c2f916a73e20149b6a917e74197f52515cb3cd06af6055bcfbcdc430fc9`.

No backend or online-match rules are included in this package.
