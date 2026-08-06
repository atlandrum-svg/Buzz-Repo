# Level architecture

## Structure

```
Stick Figure 4.tscn          ← shell (always running)
├── Level/                   ← swapped packed scene (bedroom or office)
│   ├── Background
│   ├── RoomBoundaries
│   └── props / traps…
├── Player1                  ← persists across levels
├── Player2                  ← persists
└── TurnManager              ← persists (anxiety, inventory HUD, round flags)
```

| Scene | Path | Contents |
|--------|------|----------|
| Shell | `Stick Figure 4.tscn` | Players + TurnManager + instances Level |
| Bedroom | `levels/bedroom.tscn` | Full round-1 apartment |
| Office | `levels/office.tscn` | Grey office bg + walls/stairs (props TBD) |
| Date | `levels/date.tscn` | Round-3 venue. Bare on purpose — the round is the minigame |

## Memory that carries level 1 → 2

Owned by **TurnManager** (and promoted actors), not by the level scene:

- Anxiety bar + modifiers (including next-round re-prices via `begin_next_round()`)
- Held inventory (gun, pills, etc.)
- Status / debuff icons (ADHD, fent, murderer, demon, …)
- Murder / attempted-murder timers
- Lizard: reparented to `Main` before the bedroom Level is freed so it survives

## What is *not* carried

- Bedroom furniture / trap props (they live only in `bedroom.tscn`)
- Arrival NPCs (fireman/cop/landlord) from the prior encounter
- Transient FX (smoke, bomb eject, etc.)

## Editing in Godot

- **Bedroom layout:** open `levels/bedroom.tscn` (not the shell)
- **Office layout:** open `levels/office.tscn`, add desks/computers here
- **Shell / systems:** `Stick Figure 4.tscn` (players + TurnManager only)

## Round flow

1. Boot → shell loads **bedroom** as `Main/Level`
2. 3 traps → 3 uses → leave → evaluation + NPC
3. NPC exits → stairs arrow again → leave Yes
4. `start_next_map_round()` → `load_level(office.tscn)` + P1 trap phase again
5. Leave the office → `round_index` hits `DATE_ROUND` (3) → `_begin_date_round()`

Monolith backup (pre-split): `Stick Figure 4.bedroom_monolith.bak.tscn`

## Level 3 — the date

Round 3 takes its own branch out of `start_next_map_round()`. There is no trap
phase and no Player 1 turn: everything you are judged for was already decided
upstairs. `_begin_date_round()` loads `levels/date.tscn`, parks P2 in it, and
opens `trait_lob_minigame.gd` on the HUD layer.

### Minigame round 1 — HIDE IT (built)

`TurnManager.run_date_lob_round()` → `TraitLobMinigame.show_and_play(traits, anxiety)`

A Worms-style throw, not an Angry Birds slingshot — and with the target now
flush in the far corner, the shot that solves it is flat and fast: you stick it
like an arrow rather than lobbing it into a bucket.

- **Ammo** = `AnxietySystem.negative_traits()` — every modifier with a positive
  amount, worst-first, murder included. One shot each, no refills.
- **Controls**: `W`/`S` set the angle, hold `SPACE`/`E` to charge, release to
  throw. `ESC` bails; anything unthrown counts as exposed.
- **Feedback**: a gold arrow that grows out of the thrower is the power
  readout, and only the **first 20%** of the arc is traced. You never get the
  whole solution — you judge the rest.
- **Room**: 548x256 board units at 2x — a long, low bar, 1096x512 on screen.
  The **ceiling is solid**.
- **Target**: ONE small square socket in the upper right. You do not lob into
  it from above — you stick it, flat and fast, like an arrow into a mark.
- **It RELOCATES before every throw**, anywhere in `SOCKET_ROAM_*`
  (x 396-528, y 18-66), never within `SOCKET_MIN_MOVE` of where it just was.
  This is the real difficulty: you cannot groove one shot and repeat it, you
  re-read the range every time with the wobble fighting you. Every position in
  that box was checked reachable — best angles land between 19 and 25 degrees
  and the power window never drops below 0.65 of the meter. The bottom edge
  stops short of the mirror so the socket never sits on top of it. Set
  `SOCKET_MOVES = false` to pin it back at `SOCKET_HOME_*`.
- **No capacity limit.** Land every trait and you walk in with nothing showing.
- **A bounce off anything disqualifies the shot.** Without that rule the right
  wall sits one icon-width from the socket and rebounds everything into it.
- **Capture is generous**: `CAPTURE_HALF` (13 units) against a 13-unit icon and
  a 15-unit socket, so roughly any real contact counts. On a hit the icon snaps
  dead centre and fills the square. **This is the difficulty knob** — tightening
  toward 8 makes the corner brutal at high anxiety, past 14 and anxiety stops
  mattering.
- **Ammo is the anxiety bar's slot, chrome and all** — `_make_icon_square()`
  rebuilds `anxiety_bar.gd`'s hover-row square exactly: same 26px bordered
  panel, same 20px icon centred inside, same red/green border rule. Reusing the
  slot and not just the texture is what makes every trait a uniform square
  whatever shape the source art is. Card, queue, projectile, floor and summary
  all use it.

**Anxiety is the entire difficulty curve**, in 25-point steps as requested:

| Anxiety | Tier | Vertical aim wobble | Charge sweep | Hit rate* | Hidden of 7 |
|---|---|---|---|---|---|
| 0-24 | 0 | none | 2.9s | 100% | 7.0 |
| 25-49 | 1 | ±2.0° | 1.4s | ~90% | 6.3 |
| 50-74 | 2 | ±4.0° | 0.9s | ~53% | 3.7 |
| 75-99 | 3 | ±6.5° | 0.7s | ~32% | 2.2 |
| 100 | 4 | ±9.5° | 0.55s | ~20% | 1.4 |

\* simulated against the real collision code, for a player who has learned the
shot, averaged over random socket positions across the roam box. With no
capacity limit the "hidden of 7" column is the number that matters: calm and
you hide everything, wrecked and roughly one thing stays covered.

Gravity, the bounce constants, the wobble tiers and the charge rates are
unchanged from the previous build — the throw feels identical. Only the speed
bracket moved (855-1475), and it had to: the socket is now ~480 units away in
the far corner instead of ~250, which is simply out of range at the old speeds.

The wobble is **visible**: the arrow drifts up and down in front of you and the
shot leaves at the angle you were actually sitting on when you let go. Nothing
is hidden from the player except the back four-fifths of the arc.

Result is written back with `AnxietySystem.set_obscured()`. Obscuring a trait
does **not** change its anxiety cost — it is a social outcome, not a cure.

### Minigame round 2 — THE BOUT (built)

`TurnManager.run_date_bout_round()` → `DateBoutMinigame.show_and_play(...)`

Punch-Out!!, played as a conversation. Everything the lob failed to hide is now
an attack she throws at you.

- **Her repertoire** = `AnxietySystem.exposed_traits()`, worst-first, capped at
  5. Hide everything in round 1 and she has nothing to go on — instant win.
- **Three attacks, and the bubble COLOUR is the whole read:**

| Attack | Tell | Window | Colour | Answer | Damage |
|---|---|---|---|---|---|
| Probe — small talk drifting toward it | 0.55s | 0.70s | gold | `A` deflect | 5 |
| Dig — she has heard something | 0.95s | 0.58s | orange | `D` turn it around | 9 |
| Direct — she just asks | 1.40s | 0.48s | red | `S` own it | 14 |

- **Direct is the keystone.** It cannot be dodged, only confessed, and a clean
  confession is worth **more** than any counter (+16 vs +9) — vulnerability
  lands. That one rule is what stops this being three-way whack-a-mole.
- Read a Probe or a Dig correctly and she is briefly off balance: that is the
  **OPENING**, and `W` turns it into charm. Skipping it is a legitimate
  defensive style — you survive and never win her over.
- **Three rounds** (Drinks / Dinner / The Walk Home), 11 exchanges, with a
  corner beat between rounds that gives composure back.

**Two bars:**

| Bar | Starts at | Meaning |
|---|---|---|
| COMPOSURE | `100 - anxiety`, floored at 35 | Your health. This is where the whole run's dread finally cashes out — arrive wrecked and you fight with a sliver. Zero is a public meltdown. |
| HER INTEREST | 50 | Where it lands at the final bell is the ending. |

**Anxiety attacks your reading, never your input.** Randomising a keypress you
pressed correctly reads as a bug, so it does not happen. Instead the tell
shortens and the bubble **lies about its colour** for longer before settling:

| Tier | Anxiety | Window scale | Bubble lies for | Corner recovery |
|---|---|---|---|---|
| 0 | 0-24 | ×1.00 | — (honest at once) | full |
| 1 | 25-49 | ×0.55 | 90% of the tell | -12% |
| 2 | 50-74 | ×0.44 | the whole tell | -26% |
| 3 | 75-99 | ×0.36 | the whole tell | -42% |
| 4 | 100 | ×0.30 | the whole tell | -58% |

You may answer at any point from the moment the bubble appears, so high anxiety
squeezes from both sides: at tier 0 the colour is honest immediately and you
can bank the entire wind-up as extra time; from tier 2 up it lies right until
the window opens and that bonus is gone, while the window itself is a third of
what it was.

**The window numbers are solved, not guessed.** Simulated against the real
exchange logic with a 280ms ±70ms reaction time and a 1-in-3 chance on a forced
guess, over whole 11-exchange matches:

| Anxiety | Composure | Correct | Meltdown | 2nd date / thinking / ghosted |
|---|---|---|---|---|
| 0 | 100 | 100% | 0% | 100 / 0 / 0 |
| 25 | 75 | 98% | 0% | 100 / 0 / 0 |
| 50 | 50 | 67% | 1% | 58 / 32 / 9 |
| 75 | 35 | 50% | 28% | 21 / 36 / 14 |
| 100 | 35 | 40% | 49% | 9 / 27 / 14 |

A clean run through levels 1-2 and a clean lob buys you a guaranteed second
date. That is the payoff the whole game has been withholding. The first pass at
these numbers had windows nearly three times as wide and simulated at 100%
across every tier — the squeeze simply never happened.

**Endings** apply through the normal modifier system:

| Interest | Ending | Modifier |
|---|---|---|
| 75+ | Second Date | `second_date`, −25 |
| 45-74 | Left On Read | `left_on_read`, +5 |
| 0-44 | Ghosted | `ghosted`, +15 |
| composure 0 | Public Meltdown | `meltdown`, +30, **locked** |

### Player 1's setup turn

Before the bout, P1 spends **3 pressure points** across her repertoire — the
same budget as `TRAPS_MAX`, so it reads as the trap phase wearing a different
hat.

| Points on a trait | Effect |
|---|---|
| 1 | She will definitely ask, and it hits 25% harder |
| 2 | Her tell on it is 20% shorter |
| 3 | Its attacks are upgraded a whole tier (Probe→Dig→Direct) |

Stack all three on Murderer and she opens with a Direct. P1 sees only the
exposed list, never what P2 managed to hide — same information asymmetry the
traps already run on.

### Testing without playing rounds 1-2

| Key | Cheat |
|-----|-------|
| `0` | Jump to the date, mid anxiety (~65) |
| `9` | Jump to the date, maxed anxiety (100, murder included) |
| `8` | Skip the lob, straight into round 2 (the bout) |

### Art — round 1

`trait_lob_minigame/tl_*.png`, regenerated by
`trait_lob_minigame/_src_magenta/gen_art.py` (`python gen_art.py`, then copy
`out/keyed/*.png` up one level). The board geometry constants at the top of that
script and the ones at the top of `trait_lob_minigame.gd` **must** stay in sync.
`out/preview.png` composites the whole field so the layout can be checked
without opening Godot — set `DEBUG_GUIDES = True` in that script to overlay the
holder hit rects.

The thrower is **not** bespoke art: it is the real Player 2 sheet
(`julian assange sprite sheet black.png`), frame 8, the right-facing idle,
drawn at 2x. Nor is the ammo — those are the project's own `icon_*.png` files
in the anxiety bar's own slot chrome.

Shading rules that keep it out of flat-rectangle territory: 4-6 step ramps per
material, real alpha blending rather than Bayer screens for gradients and light,
one warm key light (the pendants) with everything shading away from it, and
three depth planes. `Canvas.blend()` deliberately refuses to touch chroma-key
pixels — letting a glow bleed onto the magenta produces pink fringes that never
key out.

### Art — round 2

`date_bout_minigame/db_*.png`, from `date_bout_minigame/_src_magenta/gen_art.py`.

That generator imports `_lib.py`, which is a **verbatim copy** of the palette
table and `Canvas` class out of the lob's generator — imported rather than
duplicated so the two minigames physically cannot drift apart. Retune the
palette in the lob's generator and re-copy that block.

**The one art rule: no faces are drawn procedurally.** Player 2 is the real
in-game sprite (frame 8 of the assange sheet, same as the lob's thrower). The
date is a **backlit silhouette** lit from the doorway behind her — one flat
shape, a warm rim, no interior detail, three poses. That is an art choice as
much as a capability one: she reads as something judging you, and every scrap
of information lives in the bubble instead. What makes a silhouette read as a
person is the neck and the shoulder line, not a face.

Every `db_*.png` is a drop-in replacement for hand-drawn or commissioned art
without touching the GDScript, as long as the cell sizes in that folder's
README hold.

The four ending icons (`icon_second_date`, `icon_left_on_read`, `icon_ghosted`,
`icon_meltdown`) live in `res://` root with the other trait icons. They are
authored at 16x16 and nearest-upscaled to 64, which is how the existing chunky
`icon_*.png` files are built.
