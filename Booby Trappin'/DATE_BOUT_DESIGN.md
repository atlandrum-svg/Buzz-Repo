# Level 3, Minigame Round 2 — THE BOUT

**Status:** design + technical brief. Nothing built yet.
**Slots into:** the `# NEXT:` hook at the end of `TurnManager.run_date_lob_round()`.
**Model:** Punch-Out!!, played as a conversation.

---

## 1. Why this shape

Round 1 (the lob) is a *shot* game: aim, commit, watch. The watching is the
problem — the outcome is decided at release and you sit through the rest.
Punch-Out is the opposite: continuous reading, short reaction windows, and the
skill is **pattern recognition**, which is the one thing that rewards playing a
level twice.

It also fixes two structural holes:

- **Round 1 currently produces a list nobody uses.** `exposed_traits()` is the
  ammunition for this round. What you failed to hide is literally what she asks
  about, which is the payoff the lob has been missing.
- **Player 1 has nothing to do in level 3.** They get a real setup turn here
  (§4), using the same 3-point budget as the trap phases in rounds 1 and 2.

---

## 2. The core loop

She asks. You have a window to respond correctly. Land it and she is briefly
off balance — that is your opening to actually be charming.

```
IDLE ──► TELL ──► WINDOW ──► [correct]   ──► OPENING ──► COUNTER ──► IDLE
                     │                                      │
                     └──► [wrong / late] ──► YOU TAKE IT ────┘
```

**One exchange, beat by beat**

| Beat | Duration | What is on screen |
|---|---|---|
| TELL | 0.5–1.4s | She leans in. A speech bubble shows the trait icon + an attack colour. |
| WINDOW | 0.25–0.6s | The bubble pulses. You press one of three keys. |
| RESOLVE | 0.3s | Correct → she falters. Wrong → your composure drops. |
| OPENING | 0.8s | Only on a correct read. Press **W** to counter. |
| COUNTER | 0.4s | Her Interest climbs. Miss the window and you just stay safe. |

Skipping the counter is a legitimate defensive style — you survive but never
win her over. That tension is the whole game.

## 2.1 Attack types

Three, exactly like jab / hook / uppercut, each with a distinct tell colour so
it reads at a glance without text.

| Attack | Tell | Colour | Correct response | Damage if missed |
|---|---|---|---|---|
| **Probe** — small talk that drifts toward it | fast, 0.5s | gold | **A** — Deflect (change the subject) | 8 |
| **Dig** — she has heard something | 0.9s | orange | **D** — Turn it around (ask about her) | 14 |
| **Direct** — she just asks | 1.4s, unmissable | red | **S** — Own it. Cannot be dodged. | 25 |

**Direct is the design keystone.** Some things you cannot deflect; you have to
confess, and the timing of the confession is the skill. Owned cleanly it is
worth *more* Interest than any counter — vulnerability lands. Owned late it is
the worst hit in the game. That single rule stops the round being three-way
whack-a-mole and makes it a conversation.

## 2.2 The two bars

| Bar | Starts at | Meaning |
|---|---|---|
| **Composure** (yours) | `100 - anxiety` | Hit zero and you crack. This is how the whole run's anxiety cashes out — arrive at 90 anxiety and you are fighting with a sliver. |
| **Interest** (hers) | 50 | Counters and clean confessions raise it, eaten hits lower it. Where it lands at the final bell decides the ending. |

Composure doubling as the health bar is the important bit: anxiety stops being
a debuff sprinkled on top and becomes *the amount of punishment you can absorb*.

## 2.3 What anxiety changes

Same 25-point tiers as the lob, same `WOBBLE_TIER`-style table.

| Tier | Anxiety | Composure | Tell duration | Reading noise |
|---|---|---|---|---|
| 0 | 0–24 | 100–76 | ×1.00 | none |
| 1 | 25–49 | 75–51 | ×0.90 | faint |
| 2 | 50–74 | 50–26 | ×0.78 | the bubble flickers |
| 3 | 75–99 | 25–1 | ×0.66 | icon briefly wrong |
| 4 | 100 | 1 | ×0.55 | icon briefly wrong, more often |

**Deliberately not doing:** randomising the *player's input* at high anxiety.
Punishing execution you performed correctly feels broken. Punishing your
**reading** — she is harder to parse when you are panicking — is fair, thematic,
and still brutal.

---

## 3. Match structure

Three rounds, boxing style, roughly 25–35s each.

- **Round 1 — Drinks.** Probes only. Teaches the tells.
- **Round 2 — Dinner.** Probes + Digs. Her repertoire is the exposed traits.
- **Round 3 — The walk.** All three types, Directs weighted toward your worst
  exposed trait.

Between rounds: a corner beat. Composure partially recovers (less at high
anxiety), you see which traits she has already used, and P1 gets a one-line taunt.

**Her repertoire** = `AnxietySystem.exposed_traits()`, capped at 5, worst-first.
Hide everything in the lob and she has nothing to work with — the round becomes
a short, easy victory lap. That is the reward the lob has never paid out.

### Endings

Interest at the final bell, applied through the existing modifier system:

| Interest | Ending | Modifier |
|---|---|---|
| 75+ | Second date | `second_date`, −25 |
| 45–74 | She is thinking about it | `left_on_read`, +5 |
| 1–44 | Politely never again | `ghosted`, +15 |
| Composure hit 0 | Public meltdown | `meltdown`, +30, locked |

---

## 4. Player 1's setup turn

Before the bout, P1 gets a phase with **3 pressure points** — the same budget as
`TRAPS_MAX`, so the mental model carries over from the apartment and the office.

Spend a point on an exposed trait and she presses harder on it:

| Points on a trait | Effect |
|---|---|
| 1 | Appears at least once |
| 2 | Tell duration ×0.8 on that trait |
| 3 | Its attacks are upgraded one tier (Probe → Dig → Direct) |

Stack all three on Murderer and she goes straight at it with a Direct in round
one. Spread them and she is broadly better informed. Real decision, no new UI
grammar to learn — it is the trap phase again, wearing a different hat.

P1 never sees which traits P2 successfully hid in the lob, only the exposed
list. Same information asymmetry the traps already run on.

---

## 5. Technical plan

### 5.1 Files

| File | Role |
|---|---|
| `date_bout_minigame.gd` | New `Control`, same shape as `trait_lob_minigame.gd` |
| `date_bout_minigame/tl_*.png` | Art, generated |
| `date_bout_minigame/_src_magenta/gen_art.py` | Generator, forked from the lob's |
| `turn_manager.gd` | `run_date_bout_round()` + `_run_p1_pressure_phase()` |
| `anxiety_system.gd` | Four ending modifiers in `DEF` |

### 5.2 Public API

Mirrors the lob exactly, so `run_date_lob_round()` and `run_date_bout_round()`
are interchangeable at the call site.

```gdscript
## exposed  : trait dicts that survived round 1 (AnxietySystem.exposed_traits())
## anxiety  : live value, drives composure and tell speed
## pressure : { trait_id: int } — P1's 3 points
##
## returns {
##   outcome   : "second_date" | "thinking" | "ghosted" | "meltdown" | "empty"
##   interest  : int 0..100
##   composure : int remaining
##   log       : [{trait, attack, response, result, ms_late}, …]
## }
func show_and_play(exposed: Array, anxiety: int, pressure: Dictionary) -> Dictionary
```

### 5.3 Shape of the code

Reuse wholesale from `trait_lob_minigame.gd` — it is all already solved there:

- `_load_tex()` with the raw-image fallback
- `_atlas()` / `_atlas_grid()` / `_pixel_rect()`
- `_make_icon_square()` — **the trait icons must look identical here too**
- `_wait()` / `_tick()` — the pause-safe coroutine clock
- `get_tree().paused = true` while the bout runs, `process_mode = ALWAYS`
- The header / summary panel scaffolding

New machinery:

```gdscript
enum Beat { IDLE, TELL, WINDOW, RESOLVE, OPENING, COUNTER }

const ATTACKS := {
    "probe":  {"tell": 0.50, "window": 0.60, "dmg": 8,  "key": KEY_A, "colour": C_GOLD},
    "dig":    {"tell": 0.90, "window": 0.45, "dmg": 14, "key": KEY_D, "colour": C_ORANGE},
    "direct": {"tell": 1.40, "window": 0.35, "dmg": 25, "key": KEY_S, "colour": C_RED},
}
const TELL_SCALE_BY_TIER := [1.00, 0.90, 0.78, 0.66, 0.55]
const NOISE_BY_TIER      := [0.00, 0.10, 0.25, 0.45, 0.65]
const COUNTER_INTEREST   := 9
const OWNED_INTEREST     := 16   # confession beats charm
const HIT_INTEREST       := -7
```

One `await`-driven exchange function, same style as `_play_one_trait()`:

```gdscript
func _play_exchange(trait: Dictionary, kind: String) -> Dictionary:
    # TELL   — show the bubble, scaled by tier, optionally lying for a frame
    # WINDOW — poll for A / D / S, record ms_late
    # RESOLVE / OPENING / COUNTER
```

Input is **polled**, not event-driven, exactly as the lob does it — the timing
windows need frame-accurate reads and events are one frame late.

### 5.4 Art

Cheapest readable staging, and it reuses the language the game already speaks:

- **Side view, both figures at a table.** Not over-the-shoulder — that needs a
  full animated face and it is not worth the budget.
- P2 is the **existing player sprite** (`julian assange sprite sheet black.png`,
  right-facing), same as the lob's thrower.
- The date needs ~6 frames: idle, lean-in, three attack poses, one falter.
  Procedural pixel art like everything else.
- **Tells are speech bubbles, not body language** — a bubble with the trait icon
  and the attack colour. Readable at any size, no animation budget, and it keeps
  the icons as the game's core visual vocabulary.
- Reuse the bar palette (`INK`/`WALL*`/`GLOW*`/`WOOD*`) and `Canvas` verbatim.
  Warm key light over the table, everything else falling off.

### 5.5 Wiring

```gdscript
# turn_manager.gd, replacing the "# NEXT:" comment
func run_date_bout_round() -> Dictionary:
    var exposed: Array = anxiety.exposed_traits()
    if exposed.is_empty():
        # Nothing to defend. Short victory lap, then straight to the ending.
        ...
    var pressure: Dictionary = await _run_p1_pressure_phase(exposed)
    var game: Control = _ensure_date_bout()
    var result: Dictionary = await game.show_and_play(exposed, get_anxiety(), pressure)
    apply_anxiety(_ending_modifier(String(result.get("outcome", ""))))
    ...
```

### 5.6 Build order

Each phase leaves the game runnable, so this can be stopped between any two.

| Phase | Scope |
|---|---|
| **1** | Core loop on placeholder rectangles: tells, windows, counters, both bars, endings. Cheat key jumps straight in with seeded exposed traits. **This is the phase that answers "is it fun".** |
| **2** | Tuning pass — simulate the timing windows against tier scaling the way the lob's physics were solved, so the anxiety curve is measured, not guessed. |
| **3** | Art pass: backdrop, date sprite, bubbles, bars. |
| **4** | P1 pressure phase + its HUD. |
| **5** | Ending modifiers, `AnxietySystem` entries, `LEVELS.md`, cheat keys. |

**Do phase 1 and stop.** If the loop is not fun with rectangles, no amount of
art fixes it — and that is precisely the mistake the lob made, where the art and
physics were polished before the core verb had proven itself.

---

## 6. Open questions

1. **Does the lob survive as round 1?** The bout is strong enough to carry level
   3 alone. Keeping the lob means two very different verbs back to back, which
   is good variety but a long level. Alternative: shorten the lob to 3 throws.
2. **Is Interest visible during the bout?** Hiding it until the final bell is
   more dramatic; showing it teaches the player what works. Probably show it in
   phase 1 and consider hiding it later.
3. **Should P1 watch the bout?** Pass-and-play says the inactive player looks
   away. But P1 watching their sabotage land is most of the fun of this game.
