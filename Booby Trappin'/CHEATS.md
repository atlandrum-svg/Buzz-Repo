# Debug cheats

Durable jump points for playtesting. **Press the key while the game window is focused.**

| Key | Jump | What it does |
|-----|------|----------------|
| **F1** | Help | Lists cheats in the console + status line |
| **F5** | P2 roam | End-of-round state: P2 free walk, props locked |
| **F6** | Fireman | Spawn/reset fireman at stand (normal sheet) |
| **F7** | **Possess** | Zombie fireman follows P2 at half speed |
| **F8** | Wheel → Possess | Real outcome popup + possess (same as wheel land) |
| **F9** | Buffs | Give ADHD + Demon debuff |
| **F10** | Stats | Reset tech-bro base (AGI 25 / CHA 25 / INT 75) |
| **F11** | Gun fail | Gun + failed Attack → gun Yes/No prompt |
| **F12** | Fent gun | Drowsy + gun leg-shot crawl / Attempted Murder |

## Your case: zombie fireman

1. Launch the game (bat).
2. Press **F7** — instant possessed zombie follower.  
   **or** **F8** — also plays the possession message popup first.

## How to add a new cheat (durable pattern)

1. **Write a `cheat_*` method on `turn_manager.gd`** that sets real game state and reuses production functions (`_spawn_*`, `resolve_*`, etc.). Avoid one-off visual hacks.
2. **Register it** in `debug_cheats.gd` → `_register_cheats()`:
   ```gdscript
   _add("my_id", KEY_F11, "Short label", "cheat_my_method")
   ```
3. **Document it** in this file’s table.
4. Keep `DEBUG_CHEATS_ENABLED` in `debug_cheats.gd` — set `false` for a “release” build if you ship.

## Files

| File | Role |
|------|------|
| `debug_cheats.gd` | Keybinds + registry |
| `turn_manager.gd` | `cheat_*` implementations |
| `CHEATS.md` | This list |
