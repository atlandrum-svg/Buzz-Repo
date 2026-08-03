---
title: "Dev Mode — bookmarks & CLI jump points"
tags: [godot, debug, bookmarks, agent-testing]
status: active
created: 2026-08-03
---

# Dev Mode (debug builds only)

Skip the full playthrough. Jump to named **bookmarks** from the terminal or an in-game **F1** menu.  
**Release exports:** completely inert (`OS.is_debug_build()` is false — no menu, no CLI hooks).

## Files

| File | Role |
|------|------|
| `dev_bookmarks.gd` | **Edit this** — all named jump points |
| `dev_mode.gd` | CLI + F1 menu + apply / capture (auto-attached by `turn_manager.gd` in debug) |
| `_dev_bookmark_capture.gd` | Agent-friendly headless state proof script |

## Launch into a bookmark (CLI)

Godot passes everything after `--` as user args:

```bat
REM Windowed — play from mid-game
Godot_v4.7.1-stable_win64.exe --path . -- --bookmark=mid_game

REM Headless state proof (agents)
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://_dev_bookmark_capture.gd -- --bookmark=plant_monster

REM Windowed apply + screenshot + quit (best screenshot path)
Godot_v4.7.1-stable_win64.exe --path . -- --bookmark=plant_monster --dev-capture=user://dev_proof.png --dev-quit
```

### Flags

| Flag | Meaning |
|------|---------|
| `--bookmark=NAME` or `--bookmark NAME` | Apply bookmark after scene load |
| `--dev-capture=PATH` | Save a PNG after apply (e.g. `user://dev_proof.png`) |
| `--dev-quit` | Quit the game after capture / bookmark apply (with capture) |

## Seeded bookmarks

| Name | What it does |
|------|----------------|
| `start` | Fresh P1 game, full traps |
| `trap_placement` | P1 mid-setup; plant already trapped; near dresser |
| `mid_game` | P2 turn; plant+dresser trapped; clean pill in inventory |
| `plant_monster` | P2 at plant; plays plant **monster** animation |
| `dresser_bomb` | P2 at dresser; triggers pipe-bomb eject FX |
| `p2_cartwheel` | Plays P2 cartwheel blast knockback |

## In-game menu

Press **F1** (debug builds only). Pick a bookmark or fire **Anim: plant / bomb / cartwheel**. Esc / click dim closes.

## Add a bookmark

1. Open `dev_bookmarks.gd`.
2. Copy an existing entry in `BOOKMARKS`.
3. Set fields:

```gdscript
"my_spot": {
    "label": "Human-readable name",
    "turn": "Player2",
    "traps_left": 0,
    "p2_items_used": 1,
    "p1_pos": Vector2(20, 100),
    "p2_pos": Vector2(120, -160),
    "prop_traps": {
        "plant": true,
        "dresser": false,
        "laptop": false,
        "pill": false,
    },
    "inventory_pills": [false],  # false=clean, true=trapped bottle
    "trigger": "",  # or "plant_monster" | "dresser_bomb" | "p2_cartwheel"
},
```

4. Launch: `-- --bookmark=my_spot`

## Agent workflow (repeatable)

```bat
cd stick-figure-game-4
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://_dev_bookmark_capture.gd -- --bookmark=mid_game
```

Expect stdout containing `[DEV-CAPTURE] PASS` and `user://dev_bookmark_proof.txt` under the project user data dir.  
For a real PNG of the room + HUD, use the windowed `--dev-capture` line above (headless uses a dummy renderer and often cannot grab pixels).
