# Booby Trap / Stick Figure Game 4 — Agent Handoff

**Purpose:** One-shot handoff for a stronger agent (Fable / high-capability mode).  
**Owner:** joshua (group leader)  
**Play loop:** Joshua never opens Godot. Agent edits files + relaunches; he tests via Desktop bat.  
**Date of handoff:** 2026-08-02  

---

## 1. What the game is (product intent)

Pass-and-play **2-player booby-trap bedroom tactics** on one device (later: web / phone browser).

### Core fantasy
- **Player 1 (trap setter)** places hidden traps on room objects during their setup phase.
- **Player 2 (victim / explorer)** walks around and uses objects; if they use a trapped object without inspecting, a bad event triggers (animation + stat/story outcome).
- Tone: dark-comedy / edgy college-dorm chaos (see historical notes in §7). Content can be cleaned up later; mechanics first.

### Vision joshua has stated (channel Game-building-logistics)

| Topic | Intent |
|-------|--------|
| Turns | Not “one step then pass.” Free walk until **N meaningful actions** complete the turn. |
| P1 actions | Walk freely; near object → prompt; **E** sets a trap. Inventory of traps (e.g. **3 of 6 props**). After 3 traps set → P2 turn. |
| Prompts | Near object only: “Press E to Set a Trap” / for P2 “Use Object” or “Press I to inspect or E to use”. Walk away → hide. After trap set: “A Trap Has Been Set!” (P1 only; P2 must **not** see which are trapped). |
| Visibility | **Only active player on screen.** Inactive player invisible + **no collision**. Controls only affect active player. |
| P2 | Use objects; inspect vs use; trap triggers animation/event. Expand more props after plant works. |
| Art | Prefer **existing full room painting** over 16×16 tile assembly. No AI “slop” if free packs or existing art work. |
| Workflow | Joshua: play bat → feedback. Agent: edit project → relaunch. |

### Secondary experiment (do not prioritize)
`C:\Users\joshc\Documents\booby-trap-game` — greenfield Godot greybox + bitglow crop attempt. **Stale / failed art path.** Do not continue unless asked. Lessons: don’t freestyle crop free packs; use game 4’s room.

---

## 2. Canonical project (use this)

| Item | Value |
|------|--------|
| Path | `C:\Users\joshc\Documents\stick-figure-game-4` |
| Engine | Godot **4.7.1** at `C:\Users\joshc\Desktop\Stick Figure\Godot_v4.7.1-stable_win64.exe` |
| Main scene | `res://Stick Figure 4.tscn` (set in `project.godot`) |
| Play launcher | Desktop: `Play Stick Figure Game 4.bat` → `godot --path "...\stick-figure-game-4"` |
| Room art size | `Room Cleaned 1.png` = **1390×1640** (full painted room, not tiles). Displayed at **scale 0.4**. |
| Phone | Workable; portrait-tall. Scale camera/window — not a reason to abandon the image. |

### Do **not** launch
- `main.tscn` — almost empty (player only) → grey void. That was the bug when bat first pointed at wrong scene.
- `Stick Figure 5.tscn` — alternate/incomplete.

---

## 3. Current scene structure (`Stick Figure 4.tscn`)

Root: `Main` (Node2D)

```
Main
├── Background (Sprite2D) — Room Cleaned 1.png, scale 0.4, z=-1
├── Plant (Sprite2D) — trap prop; PlantMonster.png, hframes=10
│   ├── PlantArea (Area2D) + plant_area.gd
│   │   └── CollisionShape2D (CircleShape2D)
│   ├── Label — proximity prompt
│   └── AnimationPlayer — "normal" idle, "monster" trap trigger
├── Lamp (Sprite2D) — misnamed; uses Plant Cutout 2.png (legacy prop art)
├── RoomBoundaries (StaticBody2D) — walls + furniture colliders
│   ├── LeftWall, RightWall, TopWall, BottomWall
│   ├── Dresser, Bed, Table, Stairs, Chest
├── Player1 (instance Player1.tscn)
├── Player2 (instance Player2.tscn)
└── TurnManager (Node) — turn_manager.gd
```

### Collision props present (static)
Bed, Dresser, Table, Chest, Stairs, walls. These block movement only; most are **not** yet wired as trap/interact targets (only **Plant** is fully interactive).

### Players
- `Player1.tscn` / `Player2.tscn` → CharacterBody2D + Assange-style 4×4 sprite sheet + Camera2D (zoom 2).
- Shared logic: `player_body.gd`
- P1 sheet: `julian assange sprite sheet.png`
- P2 sheet: `julian assange sprite sheet black.png`

---

## 4. How mechanics work today

### Turn manager (`turn_manager.gd`)
- `current_turn`: `"Player1"` | `"Player2"`
- On ready: P1 active, P2 inactive
- `switch_turn()` flips both via `set_active`

### Player active state (`player_body.gd`)
When inactive:
- `visible = false`
- camera off
- **collision disabled** (layer/mask 0, shape disabled) — so P1 cannot bump invisible P2
- physics process off  

Movement: WASD / arrows (`ui_*`). Speed 100. 4-dir walk frames.

### Plant trap (`plant_area.gd`) — only fully implemented trap
| Actor | Near plant | Input | Result |
|-------|------------|-------|--------|
| P1 | “Press E to booby trap” | **E** | `is_booby_trapped = true`, switch to P2 |
| P2 | “Press I to inspect or E to use” | **I** | If trapped: clear trap, “Trap found!”; else “No trap found.” Then switch turn |
| P2 | same | **E** | If trapped: play **monster** animation, “Trap triggered!”; else “Used plant…”. Then switch turn |

**Gaps vs full vision:**
- Only **one** trap prop (plant), not 3-of-6 inventory
- Trap set instantly ends P1 turn (not “walk free until 3 traps”)
- No HUD inventory 3/3
- No multi-prop trap map
- Inspect/use only on plant
- Laptop/chest scripts exist as legacy (`laptop_*.gd`, `chest_area.gd`) but are **not** the main path in Stick Figure 4.tscn

### Plant art pipeline (current)
- Idle/monster frames: horizontal spritesheet **`PlantMonster.png`** (rebuilt from `plant_trap.gif`, 10 frames, large)
- Old tiny strip backed up as `PlantMonster_old.png`
- Baked plant in room wallpaper was **painted out** of `Room Cleaned 1.png` (backup: `Room Cleaned 1_backup.png`) so only the sprite plant shows
- AnimationPlayer tracks `frame` 0→9 for “monster”

---

## 5. What has been done (session history, high level)

### A. Greenfield `booby-trap-game` (mostly abandoned)
- Greybox bedroom, 16px grid, continuous walk + deceleration
- P1 free walk, 3 traps inventory, proximity prompts, one player visible
- Attempted free **bitglow** art integration via bad auto-crops → looked wrong
- Editor-editable props experiment + Godot baby-mode docs
- Lesson: use finished room art, not freestyle crops

### B. Pivot to `stick-figure-game-4`
- Discovered existing project with full room + turn scaffolding
- Fixed main scene → `Stick Figure 4.tscn`
- Desktop bat: `Play Stick Figure Game 4.bat`
- P2 collision only on P2 turn
- Plant trap animation scale/align + GIF rebuild + bg plant removal

### C. Explicit non-goals this session
- Not finishing all 6 props’ trap effects
- Not UI bars (charisma/agility) unless requested next
- Not shipping web export yet

---

## 6. Historical design dump (from Desktop Stick Figure notes)

From `Desktop\Stick Figure\Stick Figure Game.txt` / early design (may still be desired later):

Possible trap props and outcomes (content TBD / soften as needed):
- Dresser / plant / computer / chest / pill bottle good vs bad outcomes
- Charisma & agility bars (default 50%, step 5%)
- Inventory top-left; inspect ammo; dialog popup for events
- P2 places traps on three items; P1 suffers if uses without inspect

Treat as **backlog**, not current implementation.

---

## 7. Recommended next implementation (for one-shot agent)

Priority order:

1. **Verify plant path still plays cleanly** (position/scale may need one more nudge after human playtest).
2. **Generalize trap props**  
   - Shared `TrapInteractable` component (Area2D + prompt label + trapped flag + P1 set / P2 inspect|use).  
   - Props: plant (done pattern), dresser, bed, laptop/computer, chest, pill bottle — pick 6 that match room art.  
   - P1: free walk until **3 traps** placed; HUD `Traps: n/3`.  
   - P2: no trap markers visible; only Use / Inspect prompts.
3. **One active player only** — already partly done; ensure spawn positions so P2 doesn’t start inside furniture.
4. **Trap outcomes** — per prop: animation and/or dialog; plant already has monster anim.
5. **Polish** — remove unused “Lamp” plant cutout if redundant; clean dead scripts; phone viewport (stretch/keep aspect).
6. **Do not** reopen bitglow greybox unless art direction changes.

### Agent workflow with joshua
1. Edit files under `stick-figure-game-4`
2. Relaunch:  
   `Godot_v4.7.1-stable_win64.exe --path "C:\Users\joshc\Documents\stick-figure-game-4"`
3. Tell him to use **Play Stick Figure Game 4.bat**
4. He reports; you iterate. He does not use Godot editor.

### Concurrent edit note
If Godot editor is open, disk edits prompt Reload. Prefer play-only testing to avoid overwrite fights.

---

## 8. Key file index

| File | Role |
|------|------|
| `Stick Figure 4.tscn` | **Live level** |
| `project.godot` | main_scene → Stick Figure 4.tscn |
| `turn_manager.gd` | Turn state |
| `player_body.gd` | Move + active/collision |
| `plant_area.gd` | Plant trap interaction |
| `Player1.tscn` / `Player2.tscn` | Player prefabs |
| `Room Cleaned 1.png` | Room background (plant removed) |
| `PlantMonster.png` | 10-frame trap sheet (from GIF) |
| `plant_trap.gif` | Source commission animation |
| `main.tscn` | **Broken/empty — do not use** |

---

## 9. Channel / collab context

- Buzz channel: **Game-building-logistics**  
- Human: **joshua** (group leader)  
- Agent: **ROBOT SLAVE** (lean Godot implementer)  
- Sibling agents exist (Bumble, Fizz, Honey) but this game work is owned by ROBOT SLAVE unless reassigned.

---

## 10. One-paragraph brief for Fable

Build on `Documents\stick-figure-game-4` (Godot 4.7.1), main scene `Stick Figure 4.tscn`: full painted bedroom (1390×1640 @ 0.4 scale), pass-and-play P1/P2 with free walk, only active player visible and collidable. Expand from the working plant booby-trap (P1 E sets trap → P2 turn; P2 I inspects / E uses; trapped E plays monster frames from PlantMonster.png) into a 3-trap inventory across ~6 room props without revealing traps to P2, with proximity prompts and per-prop outcomes. Joshua only playtests via Desktop bat; implementer edits and relaunches. Ignore `booby-trap-game` greybox and `main.tscn`.
