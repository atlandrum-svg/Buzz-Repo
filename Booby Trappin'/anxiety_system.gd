extends Node
## Central anxiety model for Stick Figure Game 4.
##
## Replaces the old Agility / Charisma / Intelligence stat block.
## Anxiety is a single 0..100 value that starts at ANX_START each round and is
## the SUM of active modifiers, not a running total. Every modifier is also an
## icon: props, traps, items and social outcomes all register one here, and the
## HUD reads this registry to draw the hover list over the bar.
##
## Because modifiers are addressed by id, an effect can be re-priced later
## (giving the gun to the lizard weakens it from -10 to -5) or expire, and the
## bar just recomputes. One-time deltas are simply modifiers nobody removes.
##
## Attached as a child of TurnManager; TurnManager forwards the public API.

signal anxiety_changed(value: int, previous: int)
## Emitted when a modifier is added so the HUD can flash the bar.
signal modifier_applied(id: String, amount: int)

const ANX_MAX := 100
const ANX_MIN := 0
## Every round opens here. 25/100 = "manageable, for now".
const ANX_START := 25
## Murder is permanent: +35 that cannot be removed, and a hard floor.
const ANX_MURDER := 35
const ANX_MURDER_FLOOR := 35

## Modifier catalogue: id -> {label, amount, tex, tip, next_round}
## `amount`     signed anxiety contribution while active
## `next_round` if present, amount changes to this at the start of the next round
##              (used by the booby-trapped pills: helps now, ruins you later)
## `locked`     cannot be removed once applied
const DEF := {
	# --- items held ---
	"gun": {
		"label": "Packing Heat",
		"amount": -10,
		"tex": "res://handgun.png",
		"tip": "A handgun in your bag. Nobody can hurt you if you shoot first.\nAnxiety -10",
	},
	"adhd_boost": {
		"label": "ADHD Meds",
		"amount": -10,
		"tex": "res://pill_bottle.png",
		"tip": "Premium focus juice. Everything is a project plan now.\nAnxiety -10\nAlso: walk speed goes brrr.",
	},
	"drowsy": {
		"label": "Fent Pills",
		"amount": -15,
		"next_round": 10,
		"tex": "res://pill_bottle.png",
		"tip": "You took the bad pills. Everything is soft and warm.\nAnxiety -15 right now.\nNext round this becomes +10. It always does.",
	},
	"fannypack": {
		"label": "Cool Fanny Pack",
		"amount": -5,
		"tex": "res://icon_fannypack.png",
		"tip": "A fanny pack from the dresser. Utility is its own kind of confidence.\nAnxiety -5\nClick it in your bag to stash the lizard.",
	},
	# --- prop outcomes ---
	"emasculation": {
		"label": "Emasculation",
		"amount": 10,
		"tex": "res://icon_emasculation.png",
		"tip": "The plant did something to you that you will not be describing to anyone.\nAnxiety +10",
	},
	"zen": {
		"label": "Zen",
		"amount": -20,
		"tex": "res://icon_zen.png",
		"tip": "You sat on the mat and nothing came out of the walls.\nAnxiety -20",
	},
	"vishnu_demon": {
		"label": "Possession",
		"amount": 5,
		"tex": "res://vishnu_demon_possess.png",
		"tip": "A 4th dimensional demon is riding along inside you.\nAnxiety +5\nIt will interrupt you at the worst possible moment.",
	},
	"escapism": {
		"label": "Escapism",
		"amount": -15,
		"tex": "res://icon_escapism.png",
		"tip": "You played video games instead of thinking about it.\nAnxiety -15",
	},
	"cyber_crime": {
		"label": "Cyber Crime",
		"amount": 15,
		"tex": "res://icon_cyber_crime.png",
		"tip": "There is now highly illegal material on your laptop.\nAnxiety +15",
	},
	"ptsd": {
		"label": "PTSD",
		"amount": 10,
		"tex": "res://icon_ptsd.png",
		"tip": "The dresser had a pipe bomb in it. You keep hearing it.\nAnxiety +10",
	},
	"mourning": {
		"label": "Mourning",
		"amount": 5,
		"tex": "res://icon_mourning.png",
		"tip": "You gave the lizard something and now the lizard is gone.\nAnxiety +5",
	},
	# --- fireman encounter outcomes ---
	"viral_wrong": {
		"label": "Viral For The Wrong Reasons",
		"amount": 10,
		"tex": "res://icon_viral_wrong.png",
		"tip": "He posted the video. The comments are not on your side.\nAnxiety +10",
	},
	"beat_up": {
		"label": "Beat Up The Fireman",
		"amount": -10,
		"tex": "res://icon_beat_up.png",
		"tip": "You won, and he is far too embarrassed to tell anyone.\nAnxiety -10",
	},
	"spurned_lover": {
		"label": "Spurned Lover",
		"amount": 15,
		"tex": "res://icon_spurned_lover.png",
		"tip": "You went for it. He did not go for it.\nAnxiety +15",
	},
	"casanova": {
		"label": "Casanova",
		"amount": -15,
		"tex": "res://icon_casanova.png",
		"tip": "Heretofore a heterosexual man. He left confused and limping.\nAnxiety -15",
	},
	"spilled_spaghetti": {
		"label": "Spilled Spaghetti",
		"amount": 5,
		"tex": "res://icon_spilled_spaghetti.png",
		"tip": "The small talk went badly in a way people will remember.\nAnxiety +5",
	},
	"smooth_talker": {
		"label": "Smooth Talker",
		"amount": -5,
		"tex": "res://icon_smooth_talker.png",
		"tip": "You talked him back out the door. Nothing happened. Perfect.\nAnxiety -5",
	},
	"glad_not_me": {
		"label": "Glad It Wasn't Me",
		"amount": -10,
		"tex": "res://icon_glad_not_me.png",
		"tip": "The lizard did it. You were simply present.\nAnxiety -10",
	},
	"bravado": {
		"label": "Bravado",
		"amount": -10,
		"tex": "res://icon_bravado.png",
		"tip": "You waved a gun around and they believed you.\nAnxiety -10\nWhatever they just did to you does not count any more.",
	},
	# Dev tools only — a free-floating nudge so the panel can move the bar
	# without faking one of the real modifiers.
	"dev_nudge": {
		"label": "Dev Override",
		"amount": 0,
		"tex": "",
		"tip": "Set by the dev panel. Not reachable in normal play.",
	},
	# --- permanent ---
	"murderer": {
		"label": "Murderer",
		"amount": ANX_MURDER,
		"locked": true,
		"tex": "res://murderer_skull_icon.png",
		"tip": "You killed a man. This never comes off.\nAnxiety +35, permanently.\nYour anxiety can never drop below 35 again.",
	},
	"attempted_murder": {
		"label": "Attempted Murder",
		"amount": ANX_MURDER,
		"locked": true,
		"tex": "res://attempted_murder_fist_icon.png",
		"tip": "You shot a guy's leg off while extremely not sober.\nHe is still crawling. That is not better.\nAnxiety +35, permanently.",
	},
}

## id -> {amount, label, tex, tip, locked, next_round}
var _mods: Dictionary = {}
## Once true, anxiety can never fall below ANX_MURDER_FLOOR.
var _floor_locked: bool = false
var round_number: int = 1
var _last_value: int = ANX_START


## Current anxiety, clamped, with the murder floor applied.
func value() -> int:
	var total: int = ANX_START
	for id in _mods:
		total += int(_mods[id].get("amount", 0))
	if _floor_locked:
		total = maxi(total, ANX_MURDER_FLOOR)
	return clampi(total, ANX_MIN, ANX_MAX)


## 0.0..1.0 for bar fill.
func ratio() -> float:
	return float(value()) / float(ANX_MAX)


## Portion of the bar that is permanently locked (murder), 0.0..1.0.
func locked_ratio() -> float:
	if not _floor_locked:
		return 0.0
	return float(ANX_MURDER_FLOOR) / float(ANX_MAX)


func is_floor_locked() -> bool:
	return _floor_locked


## Apply a catalogued modifier. `amount_override` re-prices it (gun given away).
## Re-adding an existing id is a no-op except for the override.
func apply(id: String, amount_override = null) -> void:
	if id.is_empty():
		return
	var def: Dictionary = DEF.get(id, {})
	var entry: Dictionary = {
		"amount": int(def.get("amount", 0)),
		"label": String(def.get("label", id)),
		"tex": String(def.get("tex", "")),
		"tip": String(def.get("tip", String(def.get("label", id)))),
		"locked": bool(def.get("locked", false)),
		"next_round": def.get("next_round", null),
	}
	if amount_override != null:
		entry["amount"] = int(amount_override)
	if _mods.has(id) and bool(_mods[id].get("locked", false)):
		return # locked modifiers never change
	var prev: int = _last_value
	_mods[id] = entry
	if bool(entry["locked"]):
		_floor_locked = true
	_emit(prev)
	modifier_applied.emit(id, int(entry["amount"]))


## Re-price an already-active modifier (gun -10 -> -5 when the lizard holds it).
## No-op if the modifier is not active, so callers do not have to check.
func reprice(id: String, amount: int) -> void:
	if not _mods.has(id):
		return
	if bool(_mods[id].get("locked", false)):
		return
	var prev: int = _last_value
	_mods[id]["amount"] = amount
	_emit(prev)


func remove(id: String) -> void:
	if not _mods.has(id):
		return
	if bool(_mods[id].get("locked", false)):
		return
	var prev: int = _last_value
	_mods.erase(id)
	_emit(prev)


## Replace one locked modifier with another of the same weight. This is the
## only sanctioned way past the locked guard, and it exists for exactly one
## case: Attempted Murder becoming Murderer 15 seconds later. The bar must not
## move — only the icon and the story change.
func swap_locked(from_id: String, to_id: String) -> void:
	if not _mods.has(from_id):
		return
	var prev: int = _last_value
	_mods.erase(from_id)
	_floor_locked = false
	for id in _mods:
		if bool(_mods[id].get("locked", false)):
			_floor_locked = true
			break
	_last_value = value()
	apply(to_id)
	_emit(prev)


func has(id: String) -> bool:
	return _mods.has(id)


func amount_of(id: String) -> int:
	if not _mods.has(id):
		return 0
	return int(_mods[id].get("amount", 0))


## Ordered list for the hover panel: [{id, label, amount, tex, tip, locked}]
## Sorted worst-first so the biggest problem reads at the top.
func listing() -> Array:
	var out: Array = []
	for id in _mods:
		var e: Dictionary = _mods[id]
		out.append({
			"id": String(id),
			"label": String(e.get("label", id)),
			"amount": int(e.get("amount", 0)),
			"tex": String(e.get("tex", "")),
			"tip": String(e.get("tip", "")),
			"locked": bool(e.get("locked", false)),
		})
	out.sort_custom(func(a, b): return int(a["amount"]) > int(b["amount"]))
	return out


## Round transition. Modifiers carrying `next_round` re-price themselves — this
## is how the booby-trapped pills stop helping and start hurting. Round 2 does
## not exist yet; call this from wherever it eventually starts.
func advance_round() -> Array:
	round_number += 1
	var changes: Array = []
	var prev: int = _last_value
	for id in _mods:
		var e: Dictionary = _mods[id]
		var nxt = e.get("next_round", null)
		if nxt == null:
			continue
		var before: int = int(e.get("amount", 0))
		e["amount"] = int(nxt)
		e["next_round"] = null
		changes.append({
			"id": String(id),
			"label": String(e.get("label", id)),
			"from": before,
			"to": int(nxt),
		})
	_emit(prev)
	return changes


## Modifiers that will change at the start of next round (for HUD warnings).
func pending_next_round() -> Array:
	var out: Array = []
	for id in _mods:
		var nxt = _mods[id].get("next_round", null)
		if nxt == null:
			continue
		out.append({
			"id": String(id),
			"label": String(_mods[id].get("label", id)),
			"from": int(_mods[id].get("amount", 0)),
			"to": int(nxt),
		})
	return out


## New round of the same run: wipe everything except locked modifiers.
func reset_for_new_run() -> void:
	var prev: int = _last_value
	for id in _mods.keys().duplicate():
		if not bool(_mods[id].get("locked", false)):
			_mods.erase(id)
	round_number = 1
	_emit(prev)


func _emit(prev: int) -> void:
	var now: int = value()
	_last_value = now
	if now != prev:
		anxiety_changed.emit(now, prev)
