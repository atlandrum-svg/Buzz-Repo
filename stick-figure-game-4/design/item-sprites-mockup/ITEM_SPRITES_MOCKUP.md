---
title: "Level-one item sprite mockups"
tags: [art, sprites, mockup, level-one]
status: draft
created: 2026-08-02
---

# Level-one item sprite mockups

**Status:** Design review only. Not wired into Godot scenes or the TRAPS menu yet.  
**Request:** Andy Landy / Awoody item list for level one — individual sprites consistent with room art.  
**Channel:** Items

## Style contract (from existing game art)

| Property | Target |
|----------|--------|
| Medium | 16-bit SNES-era pixel art |
| Palette | Warm woods, cream highlights, soft purple accents; grey/blue for tech props |
| Outline | Thick dark / black pixel outline |
| Background | Flat pure magenta `#FF00FF` chroma key |
| Size (mockup) | 256×256 PNG, nearest-neighbor friendly |
| Silhouette | Isolated prop only — no floor, no cast shadow, no scene |

Anchors used: `Room Cleaned 1.png`, `Plant Cutout.png`, `Laptop Cut Out.png`, TRAPS menu icon language.

## Deliverables

| File | Item | Notes |
|------|------|-------|
| [pill_bottle.png](pill_bottle.png) | Pill Bottle | Amber bottle, white cap, red-cross label |
| [pipe_bomb.png](pipe_bomb.png) | Pipe Bomb | Cartoon grey pipe + coiled fuse (dark-comedy trap tone) |
| [laptop.png](laptop.png) | Laptop | Clean front-open laptop; alternative to existing cutout |
| [dresser.png](dresser.png) | Dresser | 3-drawer wood dresser, matches room nightstand browns |
| [hat_rack.png](hat_rack.png) | Hat Rack | Freestanding wood stand with one hanging hat |
| [bookshelf.png](bookshelf.png) | Bookshelf | 3-shelf wood case with colorful book blocks |
| [ITEM_SPRITES_CONTACT_SHEET.png](ITEM_SPRITES_CONTACT_SHEET.png) | All six | Labeled 3×2 review sheet |

## View / usage notes

- **Hand / trap props** (pill bottle, pipe bomb, laptop): icon / inventory friendly.
- **Furniture** (dresser, hat rack, bookshelf): readable 3/4 or front orthographic — not pure top-down like the room painting. If you want them as drop-in room replacements, a second pass can re-render pure top-down to match `Room Cleaned 1.png` perspective.
- Magenta is for keying out; production import can convert to transparent PNG.

## Out of scope (this package)

- Godot scene wiring, collision, trap scripts  
- TRAPS menu slot icons (can downscale these later)  
- Animation frames  
- Final production atlas / import settings  

## Review ask

Approve, request tweaks (palette, angle, detail level), or reject any of the six before build work.
