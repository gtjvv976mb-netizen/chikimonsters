# Homepage gameplay clip slots

The homepage currently shows four scenic, non-interactive video templates. They are intentionally **not** labeled as recorded gameplay, and no video file is requested by the browser.

| Slot (`data-video-slot`) | Footage to record | Suggested filename |
| --- | --- | --- |
| `exploration` | Roaming the Chikoria Realm | `site-assets/video-exploration.mp4` |
| `gathering` | Fishing or gathering in Chikoria | `site-assets/video-gathering.mp4` |
| `wicked-temple` | A live Wicked Temple fight | `site-assets/video-wicked-temple.mp4` |
| `chikiseum` | A live Chikiseum battle | `site-assets/video-chikiseum.mp4` |

Record from the actual game, ideally in 16:9 at 1280×720 or higher. Aim for a clear 8–15 second moment per slot, with readable gameplay and no wallet details, private chat, or test/debug labels. H.264 MP4 with `+faststart` and a compressed WebP poster is suitable for the site. Keep playback click-to-start and load clips only when requested; never replace these slots with the intro trailer or AI scenery and call it gameplay.

When clips are ready, add the files and posters, then replace each matching template in `index.html` with a poster, `<video controls playsinline preload="none">`, and an accessible play button. Validate desktop/mobile loading and confirm no video downloads before a visitor clicks.
