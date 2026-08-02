---
title: "TRAPS Menu Design (overlay HUD)"
status: design-only
created: 2026-08-02
channel: Game-building-logistics
---

# TRAPS Menu Design

**Status:** Design only. No engine controls, inventory backend, or placement logic in this change.  
**Viewport:** 640×360, integer scale, nearest-neighbor (matches project pixel settings).  
**Presentation:** In-game **overlay** (not a separate scene). Room stays visible behind a dim layer.

## Reference mockups

| File | Purpose |
|------|---------|
| [traps-menu-v2-640x360.png](traps-menu-v2-640x360.png) | Approved visual target (polished) |
| [traps-menu-v2-640x360-layout.png](traps-menu-v2-640x360-layout.png) | Layout-accurate native render (slot math source) |

## Locked decisions

| Topic | Decision |
|-------|----------|
| Grid | **4×4 = 16 slots** |
| Title | **TRAPS** (not ITEMS) for v0 |
| Slot meaning | One cell per **trap type** + **stack count** (`xN`) |
| Empty slots | Dim / blank (no lock silhouettes until real unlocks exist) |
| Visibility | **P1 trap-setup phase only.** P2 cannot open this menu |
| Placements | Live on **world props**, not as a browsable list (avoids pass-and-play leaks) |
| Modal | Open freezes walk; focus trapped in grid; close with **I** / **ESC** |
| Input (later) | Arrows/WASD move focus; confirm places; mouse/touch later on same Controls |

## Production UI states (for implementers)

When backend work starts, support at least:

1. **Phase banner** — e.g. `ACTIVE: P1 — TRAP SETUP — P2 cannot open this`
2. **Header** — `TRAPS` + used/total (e.g. `3/16`) + private-view note
3. **Focused slot** — gold/highlight border
4. **Filled slot** — icon + optional qty badge
5. **Empty slot** — recessed dim cell
6. **Description strip** — focused item name + one-line help
7. **Control hint** — move / place / close

## Suggested Godot shape (not implemented here)

```
CanvasLayer (TRAPS HUD)
├── ColorRect (dim, mouse_filter STOP when open)
└── Panel (centered)
    ├── Label title / count / phase
    ├── GridContainer (4 columns)
    │   └── 16 × slot Control (TextureRect + qty Label)
    ├── Label description
    └── Label controls
```

- Toggle open only if `current_turn == Player1` and phase is trap setup.
- On P2 turn: ignore open key (optional toast later).

## Out of scope (this PR)

- Input maps, focus neighbor wiring, controller icons  
- Spending stack counts when placing on props  
- Per-prop trap data model  
- P2 inspect UI  
- Web/phone layout pass  

## History

- Requested by Andy Landy as 4×4 overlay mockup.  
- Reviewed by Karen (visibility, slot meaning, production states, 640×360).  
- Adjudicated by Monkey: TRAPS, phase-gated, type+stack, dim empties, modal overlay.
