# Homepage gameplay clip slots

Three of the four gameplay cards now play recorded footage from the real game. Each is a poster, a `<video controls playsinline muted preload="none">` and one accessible play button; `site.js` swaps the button for native controls on the first press. No clip is requested by the browser until a visitor presses play — verified against the server's request log, which does show the stage's walk video on every load.

| Slot (`data-video-slot`) | Footage | File | Status |
| --- | --- | --- | --- |
| `exploration` | Griffin flight across the realm, 0:20 | `site-assets/video-exploration.mp4` + `-poster.webp` | **Live** |
| `gathering` | Quarrying, chopping, mining, fishing, 0:50 | `site-assets/video-gathering.mp4` + `-poster.webp` | **Live** |
| `wicked-temple` | Drowned Sanctum fight, 1:30 | `site-assets/video-wicked-temple.mp4` + `-poster.webp` | **Live** |
| `chikiseum` | A live Chikiseum battle | `site-assets/video-chikiseum.mp4` | Still to record — the card stays an inert preview |

Record from the actual game, ideally in 16:9 at 1280×720 or higher. Aim for a clear 8–15 second moment per slot, with readable gameplay and no wallet details, private chat, or test/debug labels. H.264 MP4 with `+faststart` and a compressed WebP poster is suitable for the site. Keep playback click-to-start and load clips only when requested; never replace these slots with the intro trailer or AI scenery and call it gameplay.

## Before a clip goes up

* **Look at frames across the whole clip, not the first one.** The exploration recording carried Chrome's `"Claude" started debugging this browser` bar for its first 18.25 s, and the page re-laid out to the wider window by 18.5 s; the published clip starts at 18.5 s. Gathering opened on the pointer-lock `To show your cursor, press esc` toast until 1.5 s; the published clip starts there.
* The in-game world chat is visible in every recording. It is the public **World** tab, not whispers — still read it before publishing, since player names appear in it.
* The source recordings are 3018×1730 at ~58 Mbps — 280–660 MB each, far over GitHub's 100 MB limit. The published clips are 1920×1100 H.264 at 4 Mbps with the `moov` atom first and no metadata (10–46 MB).

To add the Chikiseum clip: drop in `video-chikiseum.mp4` and its poster, then give that card the same `has-clip` markup as the other three. `site.js` picks it up with no change.
