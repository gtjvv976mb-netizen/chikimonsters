# Frozen Chikiseum release 1eb4980816

This branch versions the already published, unlisted official-origin free PvP test. It does not promote or modify the normal main game.

Test: https://chikimonsters.com/realm/chikiseum-test-1eb4980816/?nocdn=1&rev=official-v3

Cloudflare Direct Static Assets deployment d68b7d7b was observed live. The 870 frozen runtime files are under `realm/chikiseum-test-1eb4980816`. For a future identical static upload, place the scoped `_headers` from this directory at the upload root alongside that nested realm directory. Do not copy it to the normal site's root.

Evidence: historical v2 full scan SHA-256 `c628b4b5315fe936234467860a077e2619c7ac334a1bffa7d4724ab7ef849273`; v3 delta scan `eb30c9e4d717ab555ea24cbff47c756e5822142c335ba6e86c03779a759c63e3`. V3 did not refetch every unchanged payload. No wallet credentials or private authentication metadata are included.

Two real signed-in owners completing a verified public duel and a physical-phone check remain pending. Entry is free: currency NONE; SOL betting, stakes and financial rewards are disabled. PvP levels are separate server-earned levels; main-world levels are unchanged.

DO NOT MERGE THIS 649 MB RELEASE TREE INTO PAGES MAIN. The existing Pages tree already exceeds its published-site budget. The normal site also has a separately recorded origin certificate problem; this release neither repairs nor certifies its TLS.
