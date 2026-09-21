# Chikimon tactical traits: Godot source snapshot

This directory preserves the reviewed Godot source for the 41-species Wicked Temple
and Chikiseum trait release. These files are exact-byte copies of the corresponding
`res://` files in the local Godot project. Place the `.gd`, `.gd.uid`, and QA scene
files at the **project root** before rebuilding; they are not standalone scripts
inside this folder. The JSON mirrors the server's canonical
`chikiseum-species-traits.json`; the server, not the browser, owns PvP combat values.

The existing `godot-patch/` rehearsal/wager work and `arena/` browser client are
separate and must remain intact. The new game pack changes combat traits only. It
does **not** add the rehearsal/wager work to the compiled realm game.

The official frontend main at `4e1939e0bba86f377937819d40d3bd82dd9c5652`
contains the same previous Godot build as the local project: all 22 previous HD,
mobile, and WASM chunk Git blob IDs match the local prior release byte for byte.
The approved `realm/reborn-art/02400b320307/manifest.json` also matches the
embedded source art manifest (SHA-256
`c52bbc8c43bfd1a0aaa77e261259846ab20e2911627e58b0d041af322eb559ca`).
This release retains the frontend's current loader and WASM. It also adds the
41 locomotion sheets referenced by that existing manifest but absent from the
previous frontend tree; every added sheet was checked against its manifest
size and SHA-256. All previously published sidecar files remain untouched.

The new HD and mobile archives were exported from the same source snapshot using
Godot `4.6.stable.custom_build.89cea1439` (executable SHA-256
`6c3fdc42c97e27bdc45c2c13f59c599755d16a3e03ea3cf993fe8612b6fbb921`).
Both controlled export receipts reported `source_unchanged_during_export=true`.
All five changed compiled scripts have identical HD/mobile bytecode. The exact
PCK/PCZ, chunk and build-stamp bindings live in `release-provenance.json`.

Run the Temple trait QA in a complete Godot source project with
`CHIKI_TRAIT_MANIFEST` pointing to the canonical server manifest, then run the
Sunder status-art QA. The source snapshot here intentionally does not claim to
be a complete, rebuildable copy of every asset in the Godot project.
