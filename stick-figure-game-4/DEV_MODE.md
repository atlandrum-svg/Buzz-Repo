---
title: "Dev Mode — bookmarks & CLI jump points"
tags: [godot, debug, bookmarks, agent-testing]
status: active
created: 2026-08-03
---

# Dev Mode (debug builds only)

Skip the full playthrough. Jump to named **bookmarks** from the terminal or an in-game **F1** menu.

## Release / export behavior

- **Debug builds** (`OS.is_debug_build() == true`): `TurnManager` creates a `DevMode` child; CLI flags and F1 work.
- **Release builds**: `DevMode` is **never constructed**. Bookmarks, F1, and CLI hooks are **inert** (no menu, no CLI side effects).
- Source files (`dev_mode.gd`, `dev_bookmarks.gd`, …) may still sit in the project folder. To also **exclude them from an exported PCK**, add them to the export filter (Project → Export → Resources → exclude `dev_*.gd`, `_dev_*.gd`, `DEV_MODE.md`). Inertia does not require that exclusion; excluding is optional hygiene.

## Files

| File | Role |
|------|------|
| `dev_bookmarks.gd` | **Edit this** — all named jump points |
| `dev_mode.gd` | Full-state apply + F1 menu + CLI assert/capture (attached only in debug) |

## Launch into a bookmark (normal CLI boot path)

Godot passes everything after `--` as user args. **Do not** use a separate re-apply test script — exercise the real game boot:

```bat
REM Play from mid-game
Godot_v4.7.1-stable_win64.exe --path . -- --bookmark=mid_game

REM Headless state assert (agents) — fails nonzero on any mismatch
Godot_v4.7.1-stable_win64_console.exe --headless --path . -- --bookmark=mid_game --dev-assert --dev-quit

REM Windowed screenshot (fails nonzero if PNG cannot be saved)
Godot_v4.7.1-stable_win64.exe --path . -- --bookmark=plant_monster --dev-capture=C:\temp\proof.png --dev-quit
```

### Flags

| Flag | Meaning |
|------|---------|
| `--bookmark=NAME` | Full-state reset + apply after scene load |
| `--dev-assert` | After apply (×2 for idempotence), assert live state matches bookmark; exit 1 on fail |
| `--dev-capture=PATH` | Save PNG after apply; **exit 1 if capture fails** (including headless dummy renderer) |
| `--dev-quit` | Quit after automation (implied when assert/capture runs) |

Expect stdout `[DEV-ASSERT] PASS` and process exit code **0** on success; **1** on any failure.

## Bookmark = full reset

Each apply:

1. Wipes blast/speed-boost, dresser FX, plant smoke, inventory, pills dialog, all shimmer trap/used flags  
2. Restores counters, inventory, prop traps, pill world presence, player positions  
3. Sets turn + HUD  

Applying the same bookmark twice must yield identical asserted state (`--dev-assert` checks this).

## Seeded bookmarks

| Name | What it does |
|------|----------------|
| `start` | Fresh P1 game, full traps |
| `trap_placement` | P1 mid-setup; plant trapped; near dresser |
| `mid_game` | P2; plant+dresser trapped; clean pill in inventory (world bottle picked up) |
| `plant_monster` | P2 at plant; plays plant monster animation |
| `dresser_bomb` | P2 at dresser; pipe-bomb FX |
| `p2_cartwheel` | P2 cartwheel blast |

## In-game menu (F1)

- **Live setters:** traps ±1, P2 uses ±1, Turn P1/P2, +Pill / +TrapPill / ClrInv  
- **Bookmarks:** one-click full reset jump  
- **Anims:** plant / bomb / cartwheel  
- Esc / click dim closes  

## Add a bookmark

1. Open `dev_bookmarks.gd`.  
2. Copy an entry in `BOOKMARKS`.  

```gdscript
"my_spot": {
    "label": "Human-readable name",
    "turn": "Player2",
    "traps_left": 0,
    "p2_items_used": 1,
    "p1_pos": Vector2(20, 100),
    "p2_pos": Vector2(120, -160),
    "prop_traps": { "plant": true, "dresser": false, "laptop": false, "pill": false },
    "prop_used": { "plant": false, "dresser": false, "laptop": false, "pill": false },
    "inventory_pills": [false],  # false=clean, true=trapped
    "pill_picked_up": true,      # optional; defaults true if inventory_pills non-empty
    "p2_adhd_boost": false,
    "trigger": "",  # "" | "plant_monster" | "dresser_bomb" | "p2_cartwheel"
},
```

3. Launch: `-- --bookmark=my_spot`
