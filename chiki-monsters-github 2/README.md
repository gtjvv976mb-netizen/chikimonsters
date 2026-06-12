# Chiki Monsters

A 3D voxel browser game tied to the **$CHIKI** Solana memecoin. Token holders
(≥ 500,000 $CHIKI) receive an autonomous Chiki that roams the world of Chikoria,
completes timed tasks, and earns SOL from the creator-fee pool.

Built with **Three.js (r128)** — pure static files, no build step.

## Run locally
Just serve the folder over HTTP (the game loads `models.js` and assets by path):

```bash
# any static server works, e.g.
python3 -m http.server 8080
# then open http://localhost:8080
```

Open `index.html` for the homepage; it launches the game (`play.html`) in an iframe.

## Deploy (GitHub Pages)
1. Push this folder to a GitHub repo.
2. Settings → Pages → Build from branch → `main` / root.
3. Your game will be live at `https://<user>.github.io/<repo>/`.

## Structure
| File | Purpose |
|------|---------|
| `index.html` | Homepage (tabs, hero, Play button) |
| `play.html`  | The full 3D game |
| `models.js`  | All voxel models (chikimons, boat, tree, mailbox, hive, berry, arena) embedded as base64 |
| `intro.mp4`  | Intro cinematic |
| `homepage-hero.png`, `play-now.png`, `splash.png` | Homepage art |
| `ui/`        | In-game tab/button/frame images |

> Wallets, $CHIKI balances and SOL payouts are **simulated** in this build.
