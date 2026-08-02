---
title: "Shared explosion FX animation mockup"
tags: [art, animation, fx, mockup]
status: draft
created: 2026-08-02
---

# Shared explosion FX animation mockup

**Status:** Design review only. Not wired into Godot yet.  
**Request:** Archie via Items thread — reusable 6–10 frame explosion for pipe bomb trigger + other destructive traps. Andy: proceed with next steps.  
**Channel:** Items

## Why this exists

Interactable traps need reaction animations. Rather than animating every prop from scratch:

1. **One shared explosion sheet** covers pipe bomb and any future blast trap.
2. Other items only need cheap reactions (shake, tip, flash) — separate later.

Plant trap already proves the pipeline: horizontal spritesheet + `AnimationPlayer` frame track (`PlantMonster.png`, 10 frames).

## Deliverables

| File | Purpose |
|------|---------|
| [EXPLOSION_FX_CONTACT_SHEET.png](EXPLOSION_FX_CONTACT_SHEET.png) | Labeled 8-frame review sheet |
| [explosion_fx_sheet_8x1.png](explosion_fx_sheet_8x1.png) | Horizontal strip (8 equal cells, no dividers) |
| `frame_01_spark.png` … `frame_08_embers.png` | Individual 128×128 frames |

## Sequence (play once, ~10–12 fps)

| # | Phase | Read |
|---|-------|------|
| 1 | spark | Tiny white-yellow ignition |
| 2 | grow-a | Small fireball + rays |
| 3 | grow-b | Medium-large blast |
| 4 | peak | Full white-core explosion |
| 5 | break | Fireball fragments + smoke |
| 6 | smoke | Grey core, orange debris |
| 7 | fade | Single smoke puff + embers |
| 8 | embers | Last smoke puffs |

**Intended use:** one-shot VFX (not a loop). After frame 8, hide / free node.

## Style contract

Matches item sprite mockups + room art:

- 16-bit chunky pixels, thick black outlines  
- Palette: cream / yellow / orange / red / charcoal  
- Flat magenta `#FF00FF` chroma key  
- Centered origin (place at trap prop position)

## Godot sketch (not implemented)

```
Sprite2D (ExplosionFX)
  texture = explosion_fx_sheet_8x1.png
  hframes = 8
  vframes = 1
AnimationPlayer
  "explode" → frame 0→7, one-shot
```

Reuse instance for any trap that blasts.

## Related notes (thread)

- Pipe bomb art: Archie suggested cartoon bomb / firework reskin if store-policy worry about realistic pipe bombs — separate art tweak, same explosion FX.
- Items mockups still awaiting approve/tweak before build wiring.

## Review ask

Approve, request more/fewer frames, softer cartoon blast, or different scale before engine import.
