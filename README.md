# Flossify — marketing site

Dental practice software marketing site. Astro + Tailwind v4, static output.

## Run it

```bash
npm install
npm run dev      # http://localhost:4321
npm run build    # -> dist/
npm run preview
```

## Why Astro

The whole positioning is "try it now, no demo call." A page that argues for
speed has to be fast. Current build:

| | This site | Molarsoft (Sept 2026) |
| --- | --- | --- |
| Home page, gzipped | ~16 KB | ~580 KB of JS alone |
| JS shipped | 1.9 KB gzipped, one file | 580 KB, 23 files |

The odontogram script imports shared types, so Astro emits it as one small
module rather than inlining it. Keep it that way: before adding a framework,
check whether a few lines of vanilla JS will do. The whole site — ten pages
plus assets — is 34 KB gzipped.

## Layout

```
src/
  layouts/Base.astro        <head>, meta, JSON-LD, theme bootstrap
  components/Odontogram.astro   the interactive chart
  pages/index.astro         the landing page, content in frontmatter
  styles/global.css         design tokens, tooth states, dark mode
```

Page copy lives in the frontmatter arrays at the top of `index.astro`
(`steps`, `pillars`, `comparison`, `faqs`). Edit there, not in the markup.

## The odontogram

Full adult dentition. Every tooth is a real `<button>` rendered
server-side, so it is keyboard-operable and visible with JS disabled.

**Charting is a palette, not a cycle.** Clicking a tooth opens a popover:
pick the surfaces, then the finding. An earlier version cycled through
states on each click, which meant three clicks to record a crown and four
more to undo a mis-click — fine for a demo, wrong at the chair with gloves
on. The popover uses the native `popover` attribute, so Escape, light
dismiss and focus handling come from the browser.

Findings split the way dentists actually record them:

- **Per surface** — caries, filled, sealant. Stored against mesial, distal,
  buccal, lingual and the occlusal/incisal surface, and shown as pips placed
  where that surface sits on the drawn tooth. "Mesial" is toward the
  midline, so which side that is flips between quadrants; putting the pip on
  the wrong side is a clinical error, not a cosmetic one.
- **Whole tooth** — crown, bridge, veneer, root canal, implant, missing,
  unerupted, impacted. "Missing on the mesial" is not something a dentist
  can say, so picking one of these ignores the surface row.

Anteriors have an incisal edge, not an occlusal table; the palette relabels
that slot per tooth.

Arrow keys move between teeth under a roving tabindex — 32 tab stops in a
row is not navigation.

Three notation systems, because the market is not one country:

| Region | System | Example (upper right third molar) |
| --- | --- | --- |
| International / PH | FDI | 18 |
| United States | Universal | 1 |
| United Kingdom | Palmer | UR8 |

Each button carries all three as data attributes and the segmented control
relabels in place. Adding deciduous (child) dentition means extending the
`QUADRANTS` map with quadrants 5–8.

## Theming

Colors are CSS variables in `global.css`, mapped into Tailwind with
`@theme inline`. Dark mode is a variable swap, not a second set of
utilities. It follows the OS by default and `[data-theme]` overrides it;
the choice persists in `localStorage`, and every access is wrapped in
try/catch because private mode throws.

## Before this goes live

- [ ] Replace every `[YOUR ...]` placeholder: price, branch price, trial
      length, storage policy, SEC registration number, and the Data Privacy
      Act statement. **Do not claim NPC compliance before it is true.**
- [ ] Re-verify every row of the comparison table against the competitor's
      live site, and keep the date on the claim. Comparative marketing is
      fine; being wrong about a competitor is not.
- [ ] Settle the name. `flossify.com`, `flossify.app` and `getflossify.com`
      are taken, and Flossy (flossy.com) sells AI software to dental
      practices — one letter away, same buyer. `flossify.io`, `flossify.co`
      and `flossify.ph` were free as of September 2026.
- [ ] Point `site` in `astro.config.mjs` at the real domain.
- [ ] Add real product screenshots. The chart is currently the only real
      product surface on the page.
