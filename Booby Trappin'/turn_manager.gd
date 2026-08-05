extends Node

const UsableShimmer = preload("res://usable_shimmer.gd")
const FiremanNpc = preload("res://fireman_npc.gd")
const LandlordNpc = preload("res://landlord_npc.gd")
const PoliceNpc = preload("res://police_npc.gd")
const SpinWheelPopup = preload("res://spin_wheel_popup.gd")
const AnxietySystem = preload("res://anxiety_system.gd")
const AnxietyBar = preload("res://anxiety_bar.gd")
const DevPanel = preload("res://dev_panel.gd")

@onready var player1 = $/root/Main/Player1/Player1Body
@onready var player2 = $/root/Main/Player2/Player2Body
var current_turn = "Player1"

const TRAPS_MAX := 3
const P2_USES_MAX := 3
## One inspect for the entire round. Inspecting is free of the use budget —
## it costs you this instead, which is what makes it a real decision.
const P2_INSPECTS_MAX := 1
var traps_left := TRAPS_MAX
var p2_items_used := 0
var p2_inspects_left := P2_INSPECTS_MAX

## --- Anxiety (replaces Agility / Charisma / Intelligence) ---
## The single stat. Owned by AnxietySystem; TurnManager just forwards.
var anxiety: Node = null

## Success odds for the fireman encounter, as a function of anxiety.
## `best` applies at or below ANX_START (25), `worst` at 100, linear between.
## Payout scales with risk: Seduce is the longest shot and the biggest swing
## (-15 / +15), Attack is the middle (-10 / +10), Schmooze is the safe, small
## play (-5 / +5). At the round-opening 25 anxiety nothing is a coin flip; by
## 100 every option is a bad idea, which is the point.
const ACTION_ODDS := {
	"schmooze": {"best": 85, "worst": 35},
	"attack": {"best": 70, "worst": 20},
	"seduce": {"best": 55, "worst": 10},
}

## Per-arrival encounter copy. Odds and anxiety values are shared — only the
## words change — so this is the one place to edit flavour for any NPC.
## Keys: <action>_desc for the option panel, <action>_win / <action>_lose for
## the outcome popup.
const ENCOUNTER_COPY := {
	"fireman": {
		"attack_desc": "Swing first. Win and he is too embarrassed to tell anyone (-10 anxiety). Lose and it is on the internet by morning (+10).",
		"seduce_desc": "The long shot with the biggest payoff. Casanova (-15) if it lands, Spurned Lover (+15) if it does not.",
		"schmooze_desc": "Talk him back out the door. Safest odds, smallest swing: Smooth Talker (-5) or Spilled Spaghetti (+5).",
		"attack_win": "You beat up the Fireman. He is too embarrassed to tell anyone.",
		"attack_lose": "You tried to attack the Fireman. He whooped your ass, and posted a video of it to social media.",
		"seduce_win": "You have seduced the Fireman, heretofore a heterosexual man. He leaves highly confused and limping.",
		"seduce_lose": "You tried to seduced the Fireman. It failed, and he whooped your ass.",
		"schmooze_win": "You have schmoozed the Fireman. He leaves without causing a scene.",
		"schmooze_lose": "You tried to schmooze the Fireman. It did not work, and he called you dusty before taking a dump on your floor.",
	},
	"landlord": {
		"attack_desc": "Swing on the man who holds your lease. Win and he never mentions it, or the rent, again (-10 anxiety). Lose and it is on the internet by morning (+10).",
		"seduce_desc": "Change the subject entirely. Casanova (-15) if it lands. If it does not, the whole building hears about it (+15).",
		"schmooze_desc": "Ask for another week. Safest odds, smallest swing: Smooth Talker (-5) or Spilled Spaghetti (+5).",
		"attack_win": "You beat up the Landlord. He will not be mentioning this, or the rent, again.",
		"attack_lose": "You swung on the Landlord. He put you on the floor, then filmed the eviction notice for his story.",
		"seduce_win": "You have seduced the Landlord. Rent is somehow no longer the subject. He leaves whistling.",
		"seduce_lose": "You tried to seduce the Landlord. He is already telling the entire building, unit by unit.",
		"schmooze_win": "You talked the Landlord into another week. He leaves almost cheerful.",
		"schmooze_lose": "You tried to schmooze the Landlord. He was not moved. The notice goes on the door on his way out.",
	},
	"police": {
		"attack_desc": "Swing on a police officer. Win and it never makes it into a report (-10 anxiety). Lose and the bodycam footage does numbers (+10).",
		"seduce_desc": "Try it on Officer Bramm. Casanova (-15) if it lands, and a very specific kind of infamy (+15) if it does not.",
		"schmooze_desc": "Talk him out of opening the laptop. Safest odds, smallest swing: Smooth Talker (-5) or Spilled Spaghetti (+5).",
		"attack_win": "You beat up Officer Bramm. He is far too embarrassed to file the report.",
		"attack_lose": "You swung on Officer Bramm. He put you down, and the bodycam footage is already doing numbers.",
		"seduce_win": "You have seduced Officer Bramm. He forgets what he came about entirely and leaves adjusting his collar.",
		"seduce_lose": "You tried to seduce Officer Bramm. It is going in the report, verbatim.",
		"schmooze_win": "You talked Officer Bramm out of it. He leaves without ever opening the laptop.",
		"schmooze_lose": "You tried to schmooze Officer Bramm. He was not charmed, and he wrote down your full name.",
	},
}

# HUD / dialog styling (matches Fizz PR art language)
const HUD_BG := Color(0.08, 0.08, 0.12, 0.82)
const HUD_BORDER := Color(0.95, 0.78, 0.28, 0.95)
const HUD_TEXT := Color(1.0, 0.92, 0.55, 1.0)
const HUD_FONT_SIZE := 14
const INV_PURPLE := Color(0.48, 0.30, 0.62, 0.98)

const ITEM_PILLS := "pills"
const ITEM_GUN := "gun"
const ITEM_FANNYPACK := "fannypack"

## Anxiety modifier ids (mirrors AnxietySystem.DEF keys).
const EFFECT_ADHD := "adhd_boost"
const EFFECT_DROWSY := "drowsy"
const EFFECT_VISHNU := "vishnu_demon"
const EFFECT_MURDERER := "murderer"
const EFFECT_ATTEMPTED_MURDER := "attempted_murder"

const TEX_FANNYPACK_ICON := "res://icon_fannypack.png"
const TEX_FANNYPACK_LIZARD_ICON := "res://icon_fannypack_lizard.png"
const TEX_FANNYPACK_WORLD := "res://fannypack.png"

const MSG_GUN_PROMPT := "You have a gun. Wave it at the %s?"
const MSG_GUN_SHOT := "You have shot the %s's head smoove off!"
const MSG_GUN_FENT_LEG := "You tried to shoot the %s, but your aim was bad due to being on fent. You have blown off his leg..."
## Demon murder with no gun in the bag — no firearm anywhere in the story.
const MSG_BAREHAND_KILL := "The demon puts your hands through the %s. There is no weapon, no warning, and very little left of him."
## Gun-wave wheel: they almost always back down, but it can go off.
const MSG_GUN_WAVE_WIN := "You wave the gun around like a man with nothing left to lose. The %s decides this is not worth it and leaves at speed."
const MSG_BAREHAND_MAIM := "The demon goes for the %s through you, but the fent turns it into a slow, clumsy mauling. He is not dead. He is crawling."
## After fent gun miss: Attempted Murder lasts this long, then upgrades to Murderer.
const ATTEMPTED_MURDER_UPGRADE_SEC := 15.0
## Fireman bleeds out / stops for good after this (even mid-crawl or later rounds).
const FIREMAN_CRAWL_DEATH_SEC := 120.0

## Sidebar status dialog (scrollable). Replaced by set_status_message().
const MSG_P2_DEFAULT := "Use (3) Items Before You Can Proceed!"
const MSG_VISHNU_POSSESS := "You have been possessed by a 4 dimensional demon..."
const MSG_FENT_PILLS := "You have taken fent..."
const MSG_LAPTOP_GAMES := "You played video games, distracting you from your woes"
## End-of-round evaluation lines (set on Label in Godot — not baked art).
const MSG_EVAL_FIRE_DEPT := "The Fire Department was called because an explosion was heard!"
const MSG_EVAL_ILLEGAL_DOWNLOAD := "You have downloaded illegal material onto your laptop! The cops have been called!"
## No explosion, no fire department — so the landlord turns up instead, and he
## is not here about the noise.
const MSG_EVAL_LANDLORD := "The landlord is coming up, looking for rent!"
const STATUS_DIALOG_H := 88.0
const STATUS_DIALOG_W := 168.0
const STATUS_FONT_SIZE := 10

## Stairs leave zone (world AABB: x -240..-140, y 100..225). Invisible trigger only.
const LEAVE_ZONE_MIN := Vector2(-240.0, 100.0)
const LEAVE_ZONE_MAX := Vector2(-140.0, 225.0)
const STAIRS_ARROW_POS := Vector2(-156.0, 95.0)
const ARROW_BOB_AMP := 7.0
const ARROW_BOB_SPEED := 3.2
const MSG_LEAVE_READY := "Leave the apartment via the stairs when ready."
const MSG_LEAVE_PROMPT := "Leave Apartment?"
const EVAL_TYPE_CPS := 32.0
const EVAL_HOLD_AFTER_TEXT_SEC := 2.5
const EVAL_GAP_BETWEEN_MSGS_SEC := 0.35
const NPC_ARRIVAL_WHEEL_DELAY_SEC := 2.0

signal pills_take_pressed
signal pills_dialog_cancelled
signal end_of_round_evaluation_finished

var _hud_layer: CanvasLayer
var _hud_label: Label
var _hud_panel: PanelContainer
var _sidebar: VBoxContainer
var _anxiety_bar: PanelContainer

## Held consumables (gameplay bag — not a permanent empty inventory grid).
## { "id": String, "trapped": bool, "slot": Control, "icon": TextureRect }
var _inv: Array = []
var _inv_panel: PanelContainer
var _inv_grid: HBoxContainer

## Sidebar narrative dialog (both turns; under counter for P1, under full HUD for P2).
var _status_panel: PanelContainer
var _status_scroll: ScrollContainer
var _status_label: Label
var _status_message: String = ""

var _pixel_font: Font
var _pills_dialog: Control
var _pills_dialog_open: bool = false
var _gun_give_dialog: Control
var _gun_give_dialog_open: bool = false
var _pack_dialog: Control
var _pack_dialog_open: bool = false
var _pending_inv_entry: Dictionary = {}
var _download_dialog: Control
var _download_dots_label: Label
var _gun_lesson_dialog: Control
var _gun_lesson_dialog_open: bool = false
var _gun_lesson_waiting: bool = false
var _gun_lesson_choice: int = -1

## End-of-round evaluation (after P2 confirms leave at stairs).
var evaluation_active: bool = false
var leave_available: bool = false
## "end_round" = first leave (eval + NPC). "next_map" = after NPC exits → new map/round.
var leave_intent: String = "end_round"
## 1 = bedroom, 2 = grey office.
var round_index: int = 1
const MAP_BEDROOM := "res://Room Cleaned 1.png"
const MAP_OFFICE := "res://grey-office-1390x1640.png"
const MSG_LEAVE_NEXT_MAP := "Leave via the stairs when ready."
var pipe_bomb_detonated: bool = false
var illegal_download: bool = false
## Persisted P2 status (re-asserted after evaluation so HUD + speed never drop).
var p2_adhd_active: bool = false
var p2_drowsy_active: bool = false
var p2_vishnu_active: bool = false
var p2_murderer_active: bool = false
var p2_attempted_murder_active: bool = false
## True once the player has handed the lizard anything — gates the Mourning icon.
var _lizard_adopted: bool = false
var _mourned_lizard: bool = false
## Lizard is zipped inside the fanny pack (off the map, gear intact).
var _lizard_in_pack: bool = false
## Durable countdown (seconds left). Survives free-roam / later rounds.
var _attempted_murder_timer: float = -1.0
var _fireman_death_timer: float = -1.0
## The end-of-round arrival: fireman if the bomb went off, otherwise landlord.
## Both implement the same interface, so one encounter path drives either.
var _fireman: Node2D = null
var _npc_name: String = "Fireman"
## Set when the NPC should leave at a run rather than a walk.
var _npc_flees: bool = false
var _spin_wheel: Control = null
## Dev tools (F3). Null in a build with the panel removed; every read is guarded.
var _dev: Control = null
var _eval_dialog: Control
var _eval_label: Label
var _eval_title: Label
var _leave_zone: Area2D
var _leave_arrow: Node2D
var _leave_dialog: Control
var _leave_dialog_open: bool = false
var _in_leave_zone: bool = false
var _leave_prompt_blocked: bool = false
var _arrow_bob_t: float = 0.0


func _ready():
	player1.set_active(true)
	player2.set_active(false)
	set_process_input(true)
	set_process_unhandled_input(true)
	set_process(true)
	_ensure_anxiety_system()
	call_deferred("_build_hud")
	call_deferred("_ensure_debug_cheats")


func _ensure_anxiety_system() -> void:
	if anxiety != null and is_instance_valid(anxiety):
		return
	var node: Node = AnxietySystem.new()
	node.name = "AnxietySystem"
	add_child(node)
	anxiety = node


func _ensure_debug_cheats() -> void:
	if get_node_or_null("DebugCheats") != null:
		return
	var dbg := load("res://debug_cheats.gd")
	if dbg == null:
		return
	var node: Node = (dbg as GDScript).new()
	node.name = "DebugCheats"
	add_child(node)


func _process(delta: float) -> void:
	_process_pending_murder_timers(delta)
	if _leave_arrow == null or not is_instance_valid(_leave_arrow):
		return
	if not leave_available or evaluation_active or not _leave_arrow.visible:
		return
	_arrow_bob_t += delta
	var bob: float = sin(_arrow_bob_t * ARROW_BOB_SPEED) * ARROW_BOB_AMP
	_leave_arrow.position = STAIRS_ARROW_POS + Vector2(0.0, bob)


func _process_pending_murder_timers(delta: float) -> void:
	if _attempted_murder_timer >= 0.0:
		_attempted_murder_timer -= delta
		if _attempted_murder_timer <= 0.0:
			_attempted_murder_timer = -1.0
			_upgrade_attempted_murder_to_murderer()
	if _fireman_death_timer >= 0.0:
		_fireman_death_timer -= delta
		if _fireman_death_timer <= 0.0:
			_fireman_death_timer = -1.0
			_finish_fireman_crawl_death()


func switch_turn():
	if current_turn == "Player1":
		current_turn = "Player2"
		player1.set_active(false)
		player2.set_active(true)
		set_status_message(MSG_P2_DEFAULT)
	else:
		current_turn = "Player1"
		player1.set_active(true)
		player2.set_active(false)
		set_status_message("")
	UsableShimmer.on_turn_changed(current_turn)
	call_deferred("_refresh_visuals")
	_update_held_items_visibility()


func consume_trap() -> bool:
	if current_turn != "Player1" or traps_left <= 0:
		return false
	traps_left -= 1
	_update_hud()
	if traps_left <= 0:
		switch_turn()
	return true


func consume_p2_use() -> bool:
	if evaluation_active:
		return false
	if current_turn != "Player2" or p2_items_used >= P2_USES_MAX:
		return false
	p2_items_used += 1
	_update_hud()
	if p2_items_used >= P2_USES_MAX:
		UsableShimmer.set_p2_world_uses_exhausted(true)
		call_deferred("enable_leave_exit")
	return true


func can_p2_use_world_item() -> bool:
	if evaluation_active or _leave_dialog_open:
		return false
	if current_turn != "Player2":
		return false
	return p2_items_used < P2_USES_MAX


## True while P2 still has their one inspect (and is still in the use phase).
func can_p2_inspect() -> bool:
	if not can_p2_use_world_item():
		return false
	return p2_inspects_left > 0


## Spend the round's single inspect. Does NOT touch the 3-use budget and does
## not mark the prop used — you can still press E on it afterwards.
func consume_p2_inspect() -> bool:
	if not can_p2_inspect():
		return false
	p2_inspects_left -= 1
	_update_hud()
	return true


func mark_pipe_bomb_detonated() -> void:
	pipe_bomb_detonated = true


func mark_illegal_download() -> void:
	illegal_download = true


func can_player_interact() -> bool:
	if evaluation_active or _leave_dialog_open:
		return false
	return current_turn == "Player1" or current_turn == "Player2"


## ============================================================================
## ANXIETY API — the only stat. Props and items call these.
## ============================================================================

func get_anxiety() -> int:
	_ensure_anxiety_system()
	return anxiety.value()


## Apply a catalogued modifier by id (see AnxietySystem.DEF).
## `amount_override` re-prices it for special cases (gun handed to the lizard).
func apply_anxiety(id: String, amount_override = null) -> void:
	_ensure_anxiety_system()
	anxiety.apply(id, amount_override)
	_mark_status_flag(id, true)
	_refresh_anxiety_bar()


func remove_anxiety(id: String) -> void:
	_ensure_anxiety_system()
	anxiety.remove(id)
	_mark_status_flag(id, false)
	_refresh_anxiety_bar()


## Change the value of an already-active modifier without re-announcing it.
func reprice_anxiety(id: String, amount: int) -> void:
	_ensure_anxiety_system()
	anxiety.reprice(id, amount)
	_refresh_anxiety_bar()


func has_anxiety_modifier(id: String) -> bool:
	_ensure_anxiety_system()
	return anxiety.has(id)


## Round transition hook. Round 2 does not exist yet — when it does, call this
## first: it is what turns the booby-trapped pills from -15 into +10.
## Returns the list of modifiers that flipped, so the caller can narrate them.
func begin_next_round() -> Array:
	_ensure_anxiety_system()
	var changes: Array = anxiety.advance_round()
	_refresh_anxiety_bar()
	for c in changes:
		print("[ANXIETY] next round: ", c["label"], " ", c["from"], " -> ", c["to"])
	return changes


## Success chance (0..100) for a fireman action at the current anxiety.
func action_success_chance(action_id: String) -> int:
	var d: Dictionary = ACTION_ODDS.get(action_id, {})
	if d.is_empty():
		return 50
	var best: float = float(d.get("best", 50))
	var worst: float = float(d.get("worst", 20))
	var a: int = get_anxiety()
	var start: int = AnxietySystem.ANX_START
	if a <= start:
		return int(round(best))
	var t: float = float(a - start) / float(AnxietySystem.ANX_MAX - start)
	return int(round(lerpf(best, worst, clampf(t, 0.0, 1.0))))


## Pinned outcome from the dev panel, or "auto" when it should behave normally.
func _dev_override(key: String) -> String:
	if _dev == null or not is_instance_valid(_dev):
		return "auto"
	return String(_dev.get_override(key))


## Dev panel anxiety nudge. Anxiety is a sum of modifiers with no raw setter,
## so this rides on its own modifier rather than corrupting a real one.
func dev_nudge_anxiety(amount: int) -> void:
	_ensure_anxiety_system()
	anxiety.apply("dev_nudge", anxiety.amount_of("dev_nudge") + amount)
	_refresh_anxiety_bar()


func _refresh_anxiety_bar() -> void:
	if _anxiety_bar and is_instance_valid(_anxiety_bar) and _anxiety_bar.has_method("refresh"):
		_anxiety_bar.refresh()


## Keep the old gameplay booleans in sync with the modifier registry.
func _mark_status_flag(id: String, active: bool) -> void:
	match id:
		EFFECT_ADHD, "adhd", "pill":
			p2_adhd_active = active
			if active:
				p2_drowsy_active = false
		EFFECT_DROWSY, "drowsy", "fent":
			p2_drowsy_active = active
			if active:
				p2_adhd_active = false
		EFFECT_VISHNU, "vishnu", "vishnu_demon":
			p2_vishnu_active = active
		EFFECT_MURDERER, "murderer":
			p2_murderer_active = active
		EFFECT_ATTEMPTED_MURDER, "attempted_murder":
			p2_attempted_murder_active = active
		_:
			pass


## Compatibility shim: prop scripts written against the old buff/debuff sidebar
## still call add_status_effect(). The sidebar is gone; route to anxiety.
func add_status_effect(id: String, _kind: String = "debuff", _texture: Texture2D = null, _display_name: String = "") -> void:
	apply_anxiety(id)


func remove_status_effect(id: String) -> void:
	remove_anxiety(id)


func has_status_effect(id: String) -> bool:
	return has_anxiety_modifier(id)


func clear_status_effects() -> void:
	_ensure_anxiety_system()
	for e in anxiety.listing():
		anxiety.remove(String(e["id"]))
	_refresh_anxiety_bar()


## ============================================================================
## End-of-round flow
## ============================================================================

## intent: "end_round" (after 3 uses → evaluation) or "next_map" (after NPC leaves → round 2).
func enable_leave_exit(intent: String = "end_round") -> void:
	if leave_available:
		return
	# First leave only while still in P2 use phase; next-map leave is allowed mid-evaluation.
	if evaluation_active and intent != "next_map":
		return
	leave_available = true
	leave_intent = intent
	_leave_prompt_blocked = false
	if intent == "end_round":
		UsableShimmer.set_p2_world_uses_exhausted(true)
	_ensure_leave_zone()
	if _leave_zone:
		_leave_zone.monitoring = true
		_leave_zone.visible = true
	if _leave_arrow:
		_leave_arrow.visible = true
		_arrow_bob_t = 0.0
		_leave_arrow.position = STAIRS_ARROW_POS
	set_status_message(MSG_LEAVE_NEXT_MAP if intent == "next_map" else MSG_LEAVE_READY)
	_update_hud()
	_update_held_items_visibility()
	# Free P2 to walk to stairs for next-map exit.
	if intent == "next_map":
		var p2: Node = _get_player2_body()
		if p2:
			if p2.has_method("set_active"):
				p2.set_active(true)
			if p2.has_method("set_movement_locked"):
				p2.set_movement_locked(false)
	call_deferred("_prompt_leave_if_overlapping")


func _prompt_leave_if_overlapping() -> void:
	if not leave_available or _leave_zone == null:
		return
	if evaluation_active and leave_intent != "next_map":
		return
	for b in _leave_zone.get_overlapping_bodies():
		_on_leave_zone_body_entered(b)


func _build_eval_message_queue() -> Array:
	# Match arrival priority: only announce who actually shows up.
	# Police supersede fire department — never show both messages.
	var queue: Array = []
	match _pick_arrival():
		"police":
			queue.append(MSG_EVAL_ILLEGAL_DOWNLOAD)
		"fireman":
			queue.append(MSG_EVAL_FIRE_DEPT)
		_:
			# Landlord (or quiet round) — landlord copy is shown later in begin_end_of_round.
			pass
	return queue


func begin_end_of_round_evaluation() -> void:
	if evaluation_active:
		return
	evaluation_active = true
	leave_available = false
	hide_leave_apartment_dialog()
	if _leave_arrow:
		_leave_arrow.visible = false
	if _leave_zone:
		_leave_zone.monitoring = false

	current_turn = "Evaluation"
	if is_instance_valid(player1):
		player1.set_active(false)
	var p2: Node = _get_player2_body()
	if p2:
		if p2.has_method("set_active"):
			p2.set_active(true)
		if p2.has_method("set_movement_locked"):
			p2.set_movement_locked(true)
	UsableShimmer.on_turn_changed("Player2")
	_update_hud()
	_update_held_items_visibility()
	if _pills_dialog_open:
		hide_pills_dialog()
	if _gun_give_dialog_open:
		hide_gun_give_dialog()
	if _pack_dialog_open:
		hide_pack_dialog()

	var messages: Array = _build_eval_message_queue()
	for i in messages.size():
		await show_evaluation_popup(String(messages[i]))
		if i < messages.size() - 1:
			await get_tree().create_timer(EVAL_GAP_BETWEEN_MSGS_SEC).timeout

	_unlock_player_after_evaluation()

	# Exactly one arrival per round, by priority. Cops outrank the fire
	# department (if both were called, the cops are the one at your door);
	# a quiet round gets the landlord instead. The dev panel can pin this.
	match _pick_arrival():
		"police":
			await _spawn_arrival(PoliceNpc, "PoliceNPC")
			await _on_npc_arrived_for_wheel("Officer")
		"fireman":
			await _spawn_fireman_from_stairs()
			await _on_npc_arrived_for_wheel("Fireman")
		_:
			# Nobody called anyone, so the landlord shows up on his own time.
			await show_evaluation_popup(MSG_EVAL_LANDLORD)
			await _spawn_arrival(LandlordNpc, "LandlordNPC")
			await _on_npc_arrived_for_wheel("Landlord")

	end_of_round_evaluation_finished.emit()
	_update_held_items_visibility()


func _unlock_player_after_evaluation() -> void:
	var p2: Node = _get_player2_body()
	if p2 == null:
		return
	if p2.has_method("set_active"):
		p2.set_active(true)
	if p2.has_method("set_movement_locked"):
		p2.set_movement_locked(false)
	_reassert_p2_status()
	set_status_message("")
	_update_hud()
	_update_held_items_visibility()


## Keep pill speed effects after the end-of-round sequence.
func _reassert_p2_status() -> void:
	var p2: Node = _get_player2_body()
	if p2 and p2.has_method("reassert_status"):
		p2.call("reassert_status")
	elif p2:
		if p2_adhd_active and p2.has_method("apply_adhd_boost"):
			p2.call("apply_adhd_boost")
		elif p2_drowsy_active and p2.has_method("apply_drowsy_debuff"):
			p2.call("apply_drowsy_debuff")
	_refresh_anxiety_bar()


func _spawn_fireman_from_stairs() -> void:
	if _fireman != null and is_instance_valid(_fireman):
		return
	var scene = get_tree().current_scene
	if scene == null:
		scene = get_parent()
	if scene == null:
		return
	var fm: Node = FiremanNpc.new()
	fm.name = "FiremanNPC"
	scene.add_child(fm)
	_fireman = fm as Node2D
	if fm.has_method("arrive_from_stairs"):
		await fm.arrive_from_stairs()
	_reassert_p2_status()
	_update_hud()


## Encounter over: the NPC retraces their walk to the stairs and vanishes.
## Skipped for anyone dead, crawling, or currently possessed by the demon —
## those keep whatever state the outcome left them in.
func _npc_departs(run: bool = false) -> void:
	if _fireman == null or not is_instance_valid(_fireman):
		return
	for blocker in ["is_dead", "is_crawling", "is_possessed"]:
		if _fireman.has_method(blocker) and bool(_fireman.call(blocker)):
			return
	if not _fireman.has_method("depart_and_vanish"):
		return
	await _fireman.call("depart_and_vanish", run)
	_fireman = null
	_update_hud()


## Who comes up the stairs: police > fireman > landlord, unless pinned.
func _pick_arrival() -> String:
	var forced: String = _dev_override("arrival")
	if forced != "auto":
		return forced
	if illegal_download:
		return "police"
	if pipe_bomb_detonated:
		return "fireman"
	return "landlord"


## Spawn and walk in any arrival_npc.gd subclass. The `_fireman` guard is what
## keeps this to one NPC per round no matter which branch called it.
func _spawn_arrival(npc_script: GDScript, node_name: String) -> void:
	if _fireman != null and is_instance_valid(_fireman):
		return
	var scene = get_tree().current_scene
	if scene == null:
		scene = get_parent()
	if scene == null:
		return
	var npc: Node = npc_script.new()
	npc.name = node_name
	scene.add_child(npc)
	_fireman = npc as Node2D
	if npc.has_method("arrive_from_stairs"):
		await npc.arrive_from_stairs()
	_reassert_p2_status()
	_update_hud()


## ============================================================================
## End-of-round encounter — options, possession interrupt, outcomes
## ============================================================================

## Called after any arrival NPC finishes entering. The old spinning fate wheel
## is gone: the player now picks Attack / Seduce / Schmooze, each with odds
## derived from anxiety. If they are possessed, the demon interrupts first and
## THAT is where the (purple) wheel and its RNG live.
func _on_npc_arrived_for_wheel(npc_name: String = "NPC") -> void:
	_npc_name = npc_name
	await get_tree().create_timer(NPC_ARRIVAL_WHEEL_DELAY_SEC).timeout
	var p2: Node = _get_player2_body()
	if p2 and p2.has_method("set_movement_locked"):
		p2.set_movement_locked(true)
	await run_fireman_encounter()
	if p2 and p2.has_method("set_movement_locked"):
		p2.set_movement_locked(false)


func run_fireman_encounter() -> void:
	_ensure_spin_wheel()
	if _spin_wheel == null:
		return

	var choice: Dictionary = await _spin_wheel.show_action_choice(
		"%s — WHAT DO YOU DO?" % _npc_name.to_upper(),
		get_anxiety(),
		_build_action_options()
	)
	var action_id: String = String(choice.get("id", ""))
	if action_id.is_empty():
		return
	# Ctrl+P dev strip inside the popup: this action just works.
	var dev_win: bool = bool(choice.get("force_win", false))

	_npc_flees = false
	var resolved := false

	# Possessed? The demon cuts you off before you can act.
	if p2_vishnu_active:
		var interrupted: Dictionary = await _run_possession_interrupt()
		var outcome: String = String(interrupted.get("id", "nothing"))
		match outcome:
			"murder":
				await _demon_murders_fireman()
				resolved = true
			"possess_person":
				await _demon_possesses_fireman()
				resolved = true
			"possess_lizard":
				resolved = await _demon_possesses_lizard()
			_:
				# Nothing happens — the chosen action proceeds as normal.
				pass
	elif _is_lizard_possessed():
		# The demon is riding the lizard from a previous encounter, and the
		# lizard has been following you around ever since. It gets its own roll.
		var liz: Dictionary = await _run_lizard_interrupt()
		if String(liz.get("id", "nothing")) == "lizard_murder":
			await _lizard_kills_npc()
			resolved = true

	if not resolved:
		await _resolve_fireman_action(action_id, dev_win)

	# Belt and braces: the popup root carries the full-screen dim, so make sure
	# it is down before anyone watches the NPC walk out.
	if _spin_wheel and is_instance_valid(_spin_wheel) and _spin_wheel.has_method("hide_popup"):
		_spin_wheel.hide_popup()

	# Whatever happened, anyone still standing walks back out the way they came.
	await _npc_departs(_npc_flees)

	# Encounter finished (NPC gone or left in place). Stairs open again for next map.
	if round_index < 2:
		enable_leave_exit("next_map")


## Which arrival is standing there. Drives copy only — odds and anxiety values
## are identical for all three, so the encounter stays balanced.
func _npc_kind() -> String:
	var n: String = _npc_name.to_lower()
	if n.contains("officer") or n.contains("police") or n.contains("cop"):
		return "police"
	if n.contains("landlord"):
		return "landlord"
	return "fireman"


func _build_action_options() -> Array:
	var copy: Dictionary = ENCOUNTER_COPY.get(_npc_kind(), ENCOUNTER_COPY["fireman"])
	var out: Array = []
	for id in ["attack", "seduce", "schmooze"]:
		out.append({
			"id": id,
			"label": id.to_upper(),
			"odds": action_success_chance(id),
			"desc": String(copy.get("%s_desc" % id, "")),
		})
	return out


## Weighted outcomes for the purple possession wheel. Anxiety deliberately has
## no influence here — once the demon takes the wheel it is pure chance.
##
## Base:                         Murder 15 / Possess Person 35 / Nothing 50
## Lizard alive:                 Murder 15 / Possess Person 35 / Possess Lizard 20 / Nothing 30
## Lizard alive on clean pills:  Murder 15 / Possess Person 35 / Possess Lizard 35 / Nothing 15
func _possession_wheel_segments() -> Array:
	var segs: Array = [
		{"id": "murder", "label": "MURDER", "weight": 15.0},
		{"id": "possess_person", "label": "POSSESS PERSON", "weight": 35.0},
	]
	var lizard: Node = _get_lizard()
	var lizard_alive: bool = _is_pet_lizard_alive()
	if lizard_alive:
		var juiced: bool = false
		if lizard and lizard.has_method("is_on_clean_pills"):
			juiced = bool(lizard.call("is_on_clean_pills"))
		# A pill-zooted lizard is a far more attractive host.
		segs.append({
			"id": "possess_lizard",
			"label": "POSSESS LIZARD",
			"weight": 35.0 if juiced else 20.0,
		})
		segs.append({"id": "nothing", "label": "NOTHING HAPPENS", "weight": 15.0 if juiced else 30.0})
	else:
		segs.append({"id": "nothing", "label": "NOTHING HAPPENS", "weight": 50.0})
	return segs


func _is_lizard_possessed() -> bool:
	var lizard: Node = _get_lizard()
	if lizard == null or not _is_pet_lizard_alive():
		return false
	return lizard.has_method("is_demon_possessed") and bool(lizard.call("is_demon_possessed"))


## Every encounter after the demon moves into the lizard. Not the full demon
## wheel — the lizard only has one idea. Doubles if it is on the clean pills.
##
##   Lizard murders him  25%  (50% on the clean pills)
##   Nothing happens     75%  (50% on the clean pills)
func _lizard_wheel_segments() -> Array:
	var lizard: Node = _get_lizard()
	var juiced: bool = lizard != null and lizard.has_method("is_on_clean_pills") and bool(lizard.call("is_on_clean_pills"))
	var kill: float = 50.0 if juiced else 25.0
	return [
		{"id": "lizard_murder", "label": "LIZARD MURDERS HIM", "weight": kill},
		{"id": "nothing", "label": "NOTHING HAPPENS", "weight": 100.0 - kill},
	]


func _run_lizard_interrupt() -> Dictionary:
	_ensure_spin_wheel()
	if _spin_wheel == null:
		return {"id": "nothing"}
	var demon_tex: Texture2D = _load_texture_any("res://vishnu_demon_possess.png")
	if demon_tex == null:
		demon_tex = _load_texture_any("res://meditation_demon.png")
	var forced: String = _dev_override("lizard")
	return await _spin_wheel.show_possession_wheel(
		_lizard_wheel_segments(), demon_tex, "" if forced == "auto" else forced
	)


func _run_possession_interrupt() -> Dictionary:
	_ensure_spin_wheel()
	if _spin_wheel == null:
		return {"id": "nothing"}
	var demon_tex: Texture2D = _load_texture_any("res://vishnu_demon_possess.png")
	if demon_tex == null:
		demon_tex = _load_texture_any("res://meditation_demon.png")
	var forced: String = _dev_override("demon")
	return await _spin_wheel.show_possession_wheel(
		_possession_wheel_segments(), demon_tex, "" if forced == "auto" else forced
	)


## Demon murder. The gun only enters the story if you are actually holding one;
## either way the fent decides whether they end up dead or merely destroyed.
func _demon_murders_fireman() -> void:
	var armed: bool = has_inventory_item(ITEM_GUN)
	if armed:
		remove_inventory_item(ITEM_GUN)
		remove_anxiety(ITEM_GUN)
		if p2_drowsy_active:
			await _execute_gun_fent_leg_shot()
		else:
			await _execute_gun_clean_headshot()
		return
	# No gun: the demon uses you instead. Same two end states, no firearm.
	if p2_drowsy_active:
		await _maim_npc(MSG_BAREHAND_MAIM % _npc_name)
	else:
		await _kill_npc_outright(MSG_BAREHAND_KILL % _npc_name)


func _demon_possesses_fireman() -> void:
	var msg := "The demon rips free of you and seizes the %s. He rises as a shambling thrall." % _npc_name
	_possess_fireman()
	# The demon left you — so did its anxiety.
	remove_anxiety(EFFECT_VISHNU)
	await show_evaluation_popup(msg)
	set_status_message(msg)


## Returns true if the encounter is over (the lizard shot him).
func _demon_possesses_lizard() -> bool:
	var lizard: Node = _get_lizard()
	if lizard == null or not _is_pet_lizard_alive():
		return false
	var has_gun: bool = lizard.has_method("has_gun") and bool(lizard.call("has_gun"))
	var juiced: bool = lizard.has_method("is_on_clean_pills") and bool(lizard.call("is_on_clean_pills"))
	# The demon is out of you either way.
	remove_anxiety(EFFECT_VISHNU)

	# Armed and medicated: it acts immediately and the encounter is over.
	if has_gun and juiced:
		if lizard.has_method("become_possessed"):
			lizard.call("become_possessed")
		await _lizard_kills_npc(true)
		return true

	# Otherwise it is possessed but not yet useful — so it follows you, and
	# rolls again at every encounter from here on.
	if lizard.has_method("become_possessed"):
		lizard.call("become_possessed", _get_player2_body() as Node2D)
	var msg2 := "The demon abandons you for the lizard. It turns to face you, and starts following. The %s is still waiting." % _npc_name
	await show_evaluation_popup(msg2)
	set_status_message(msg2)
	return false


## The possessed lizard kills whoever came up the stairs. Reached either from
## the armed-and-medicated shortcut or from a later lizard wheel landing on
## Murder. You were merely present, so this is not YOUR murder: no +35 lock.
func _lizard_kills_npc(first_time: bool = false) -> void:
	if _fireman and is_instance_valid(_fireman) and _fireman.has_method("become_headless_corpse"):
		_fireman.call("become_headless_corpse")
	apply_anxiety("glad_not_me")
	var msg: String = (
		"The lizard, possessed and full of your medication, shoots the %s dead. You did not move." % _npc_name
		if first_time else
		"The lizard gets to the %s before you can say anything. You watch. It was not you." % _npc_name
	)
	await show_evaluation_popup(msg)
	set_status_message(msg)


## force_win comes from the popup's Ctrl+P strip and beats everything else.
func _resolve_fireman_action(action_id: String, force_win: bool = false) -> void:
	var chance: int = action_success_chance(action_id)
	var roll: int = randi() % 100
	var success: bool = roll < chance
	var forced: String = _dev_override("action")
	if forced == "win":
		success = true
	elif forced == "fail":
		success = false
	if force_win:
		success = true
		forced = "win (Ctrl+P)"
	print("[ENCOUNTER] ", action_id, " chance=", chance, "% roll=", roll,
		" -> ", "SUCCESS" if success else "FAIL", "" if forced == "auto" else "  (DEV forced %s)" % forced)

	var copy: Dictionary = ENCOUNTER_COPY.get(_npc_kind(), ENCOUNTER_COPY["fireman"])
	var failed_social: bool = not success
	var msg: String = String(copy.get("%s_%s" % [action_id, "win" if success else "lose"], ""))
	# Remembered so a successful gun wave can undo whatever they just did to you.
	var failure_icon := ""
	match action_id:
		"attack":
			failure_icon = "viral_wrong"
			apply_anxiety("beat_up" if success else failure_icon)
		"seduce":
			failure_icon = "spurned_lover"
			apply_anxiety("casanova" if success else failure_icon)
		"schmooze":
			failure_icon = "spilled_spaghetti"
			apply_anxiety("smooth_talker" if success else failure_icon)
		_:
			msg = "Nothing further happens."
			failed_social = false

	if not msg.is_empty():
		await show_evaluation_popup(msg)
	set_status_message(msg)

	# Failed check + gun in bag → the chance to wave it around instead.
	if failed_social and has_inventory_item(ITEM_GUN):
		var wave: bool = await show_gun_lesson_dialog()
		if wave:
			await _resolve_gun_wave(failure_icon)


## Waving the gun: 85% they back off, 15% it goes off. On a win the debuff they
## just gave you is undone and you keep the gun — you never actually fired it.
func _resolve_gun_wave(failure_icon: String) -> void:
	_ensure_spin_wheel()
	if _spin_wheel == null:
		return
	var forced: String = _dev_override("gunwave")
	var segs: Array = [
		{"id": "bravado", "label": "THEY BACK DOWN", "short": "BACK OFF", "weight": 85.0},
		{"id": "murder", "label": "IT GOES OFF", "short": "BANG", "weight": 15.0},
	]
	var result: Dictionary = await _spin_wheel.show_possession_wheel(
		segs,
		_load_texture_any("res://handgun.png"),
		"" if forced == "auto" else forced,
		"YOU WAVE THE GUN"
	)
	if String(result.get("id", "")) == "murder":
		# It discharges. Fent decides whether they die or just get wrecked.
		await _execute_gun_kill_fireman()
		return
	if not failure_icon.is_empty():
		remove_anxiety(failure_icon)
	apply_anxiety("bravado")
	_npc_flees = true
	var msg: String = MSG_GUN_WAVE_WIN % _npc_name
	await show_evaluation_popup(msg)
	set_status_message(msg)


func _ensure_spin_wheel() -> void:
	if _spin_wheel != null and is_instance_valid(_spin_wheel):
		return
	if _hud_layer == null:
		return
	var wheel: Control = SpinWheelPopup.new()
	wheel.name = "SpinWheelPopup"
	_hud_layer.add_child(wheel)
	_spin_wheel = wheel


func has_inventory_item(item_id: String) -> bool:
	for e in _inv:
		if String(e.get("id", "")) == item_id:
			return true
	return false


func remove_inventory_item(item_id: String) -> bool:
	for e in _inv.duplicate():
		if String(e.get("id", "")) != item_id:
			continue
		_inv.erase(e)
		var slot: Control = e.get("slot") as Control
		if slot and is_instance_valid(slot):
			slot.queue_free()
		_update_held_items_visibility()
		return true
	return false


func _possess_fireman() -> void:
	if _fireman == null or not is_instance_valid(_fireman):
		return
	if _fireman.has_method("is_dead") and _fireman.call("is_dead"):
		return
	var p2: Node = _get_player2_body()
	var target: Node2D = p2 as Node2D
	if _fireman.has_method("become_possessed"):
		_fireman.call("become_possessed", target)
	else:
		push_error("Fireman missing become_possessed()")


func _execute_gun_kill_fireman() -> void:
	remove_inventory_item(ITEM_GUN)
	remove_anxiety(ITEM_GUN)
	if p2_drowsy_active:
		await _execute_gun_fent_leg_shot()
	else:
		await _execute_gun_clean_headshot()


## Dead on the spot. Murder anxiety is permanent and floors you at 35 forever.
## Narration is passed in so the gun and bare-hands paths share the mechanics.
func _kill_npc_outright(msg: String) -> void:
	if _fireman and is_instance_valid(_fireman) and _fireman.has_method("become_headless_corpse"):
		_fireman.call("become_headless_corpse")
	_attempted_murder_timer = -1.0
	_fireman_death_timer = -1.0
	apply_anxiety(EFFECT_MURDERER)
	await show_evaluation_popup(msg)
	set_status_message(msg)


## Not dead — wrecked, and crawling. Upgrades to Murderer on the usual timer.
func _maim_npc(msg: String) -> void:
	if _fireman and is_instance_valid(_fireman) and _fireman.has_method("become_legless_crawl"):
		_fireman.call("become_legless_crawl")
	apply_anxiety(EFFECT_ATTEMPTED_MURDER)
	_attempted_murder_timer = ATTEMPTED_MURDER_UPGRADE_SEC
	_fireman_death_timer = FIREMAN_CRAWL_DEATH_SEC
	await show_evaluation_popup(msg)
	set_status_message(msg)


func _execute_gun_clean_headshot() -> void:
	await _kill_npc_outright(MSG_GUN_SHOT % _npc_name)


func _execute_gun_fent_leg_shot() -> void:
	await _maim_npc(MSG_GUN_FENT_LEG % _npc_name)


## Attempted Murder becomes Murderer. Both are locked at +35, so the bar does
## not move — only the icon and the story do.
func _upgrade_attempted_murder_to_murderer() -> void:
	if not p2_attempted_murder_active:
		return
	_ensure_anxiety_system()
	anxiety.swap_locked(EFFECT_ATTEMPTED_MURDER, EFFECT_MURDERER)
	p2_attempted_murder_active = false
	p2_murderer_active = true
	_refresh_anxiety_bar()
	set_status_message("The %s isn't getting up. You're a Murderer now." % _npc_name)
	print("[MURDER] Attempted Murder -> Murderer after 15s")


func _finish_fireman_crawl_death() -> void:
	if _fireman == null or not is_instance_valid(_fireman):
		return
	if _fireman.has_method("is_dead") and _fireman.call("is_dead"):
		return
	if _fireman.has_method("die_in_place"):
		_fireman.call("die_in_place")
	elif _fireman.has_method("become_headless_corpse"):
		_fireman.call("become_headless_corpse")
	if p2_attempted_murder_active:
		_upgrade_attempted_murder_to_murderer()
	print("[MURDER] Fireman crawl death at 2 minutes")


## ============================================================================
## DEBUG CHEATS (called from debug_cheats.gd)
## ============================================================================

func cheat_toast(text: String) -> void:
	set_status_message(text)


func cheat_help() -> void:
	set_status_message("Cheats: F2 police | F4 landlord | F5 P2 roam | F6 fireman | F7 possess | F8 encounter | F9 demon+pills | F10 reset anxiety | F11 gun fail | F12 fent gun | F1 list")


func cheat_p2_eval_roam() -> void:
	current_turn = "Evaluation"
	evaluation_active = true
	leave_available = false
	pipe_bomb_detonated = true
	p2_items_used = P2_USES_MAX
	traps_left = 0
	if is_instance_valid(player1):
		player1.set_active(false)
	var p2: Node = _get_player2_body()
	if p2:
		if p2.has_method("set_active"):
			p2.set_active(true)
		if p2.has_method("set_movement_locked"):
			p2.set_movement_locked(false)
	UsableShimmer.set_p2_world_uses_exhausted(true)
	if _leave_arrow:
		_leave_arrow.visible = false
	if _leave_zone:
		_leave_zone.monitoring = false
	_reassert_p2_status()
	_update_hud()
	_update_held_items_visibility()
	set_status_message("CHEAT: P2 free roam (end-of-round)")


## Drop any arrival straight into the stand pose, replacing whoever is there.
func _cheat_place_arrival(npc_script: GDScript, node_name: String, display: String) -> void:
	cheat_p2_eval_roam()
	pipe_bomb_detonated = false
	illegal_download = false
	_npc_name = display
	if _fireman != null and is_instance_valid(_fireman):
		_fireman.queue_free()
	_fireman = null
	var scene = get_tree().current_scene
	if scene == null:
		scene = get_parent()
	var npc: Node = npc_script.new()
	npc.name = node_name
	scene.add_child(npc)
	_fireman = npc as Node2D
	if npc.has_method("place_at_stand"):
		npc.call("place_at_stand")
	_update_hud()
	set_status_message("CHEAT: %s at stand" % display)


func cheat_run_landlord_encounter() -> void:
	_cheat_place_arrival(LandlordNpc, "LandlordNPC", "Landlord")
	run_fireman_encounter()


func cheat_run_police_encounter() -> void:
	_cheat_place_arrival(PoliceNpc, "PoliceNPC", "Officer")
	run_fireman_encounter()


func cheat_spawn_fireman() -> void:
	cheat_p2_eval_roam()
	_npc_name = "Fireman"
	if _fireman != null and is_instance_valid(_fireman):
		if _fireman.has_method("place_at_stand"):
			_fireman.call("place_at_stand")
		else:
			_fireman.global_position = Vector2(-160, 35)
			_fireman.visible = true
		set_status_message("CHEAT: Fireman at stand")
		return
	var scene = get_tree().current_scene
	if scene == null:
		scene = get_parent()
	var fm: Node = FiremanNpc.new()
	fm.name = "FiremanNPC"
	scene.add_child(fm)
	_fireman = fm as Node2D
	if fm.has_method("place_at_stand"):
		fm.call("place_at_stand")
	elif fm.has_method("arrive_from_stairs"):
		fm.call("arrive_from_stairs")
	set_status_message("CHEAT: Fireman spawned")


func cheat_possess_fireman() -> void:
	cheat_spawn_fireman()
	apply_anxiety(EFFECT_VISHNU)
	_possess_fireman()
	set_status_message("CHEAT: Fireman possessed — zombie follows you")


## Run the real encounter (options -> possession interrupt -> outcome).
func cheat_run_encounter() -> void:
	cheat_spawn_fireman()
	run_fireman_encounter()


func cheat_give_demon_and_adhd() -> void:
	apply_anxiety(EFFECT_ADHD)
	apply_anxiety(EFFECT_VISHNU)
	_apply_p2_speed_boost()
	set_status_message("CHEAT: ADHD + Demon applied")


func cheat_reset_anxiety() -> void:
	_ensure_anxiety_system()
	anxiety.reset_for_new_run()
	_refresh_anxiety_bar()
	set_status_message("CHEAT: anxiety reset to %d" % get_anxiety())


func cheat_gun_fail_then_offer() -> void:
	cheat_spawn_fireman()
	if not has_inventory_item(ITEM_GUN):
		add_inventory_gun()
	# Guarantee a fail by maxing anxiety first.
	apply_anxiety("cyber_crime")
	apply_anxiety("ptsd")
	apply_anxiety("emasculation")
	apply_anxiety("spurned_lover")
	_resolve_fireman_action("attack")


func cheat_gun_fent_leg() -> void:
	cheat_spawn_fireman()
	apply_anxiety(EFFECT_DROWSY)
	_apply_p2_drowsy_debuff()
	if not has_inventory_item(ITEM_GUN):
		add_inventory_gun()
	_execute_gun_kill_fireman()


## ============================================================================
## Textures / status text
## ============================================================================

## Load texture via ResourceLoader or raw Image (works before .import exists).
func _load_texture_any(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		var t: Variant = load(path)
		if t is Texture2D:
			return t as Texture2D
	var abs_path: String = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img:
			return ImageTexture.create_from_image(img)
	return null


func set_status_message(text: String) -> void:
	_status_message = text
	if _status_label == null:
		return
	_status_label.text = text
	if _status_scroll:
		_status_scroll.scroll_vertical = 0


func get_status_message() -> String:
	return _status_message


## Hover text for held inventory items.
func get_inventory_tooltip(item_id: String, extra: Dictionary = {}) -> String:
	match item_id:
		ITEM_GUN, "gun":
			return (
				"Handgun. Found in a plant, which is already a red flag.\n"
				+ "Anxiety -10 while it is in your bag.\n"
				+ "Hand it to the lizard and the comfort drops to -5."
			)
		ITEM_PILLS, "pill", "pills":
			if bool(extra.get("trapped", false)):
				return (
					"Pill bottle (looks normal). Your roommate's 'vitamins.'\n"
					+ "Anxiety -15 now... and +10 next round. It is always +10 next round.\n"
					+ "Click to consider a life choice."
				)
			return (
				"Pill bottle. Premium focus juice (allegedly).\n"
				+ "Anxiety -10, and go-fast legs.\n"
				+ "Click to Take, or hand them to the lizard."
			)
		ITEM_FANNYPACK, "fannypack":
			if _lizard_in_pack:
				return (
					"Fanny pack. There is a lizard in it.\n"
					+ "Anxiety -5.\n"
					+ "Click to let the lizard out. It keeps whatever it was holding."
					+ _armed_lizard_note()
				)
			return (
				"Fanny pack from the dresser. Utility is its own kind of confidence.\n"
				+ "Anxiety -5.\n"
				+ "Click to stash the lizard in it."
			)
		_:
			return item_id


## ============================================================================
## Inventory
## ============================================================================

func add_inventory_pill(trapped: bool) -> void:
	if _inv_grid == null:
		call_deferred("add_inventory_pill", trapped)
		return
	var tex: Texture2D = _load_texture_any("res://pill_bottle.png")
	_add_inventory_slot(ITEM_PILLS, tex, {"trapped": trapped})


## Gun into the bag. Carrying it is worth -10 anxiety; if it is coming back
## from the lizard, apply() resets the modifier to its full -10.
func add_inventory_gun() -> void:
	if _inv_grid == null:
		call_deferred("add_inventory_gun")
		return
	for e in _inv:
		if String(e.get("id", "")) == ITEM_GUN:
			return
	var tex: Texture2D = _load_texture_any("res://handgun.png")
	_add_inventory_slot(ITEM_GUN, tex, {})
	apply_anxiety(ITEM_GUN)


func add_inventory_fannypack() -> void:
	if _inv_grid == null:
		call_deferred("add_inventory_fannypack")
		return
	for e in _inv:
		if String(e.get("id", "")) == ITEM_FANNYPACK:
			return
	var tex: Texture2D = _load_texture_any(TEX_FANNYPACK_ICON)
	_add_inventory_slot(ITEM_FANNYPACK, tex, {})
	apply_anxiety(ITEM_FANNYPACK)


func _add_inventory_slot(id: String, tex: Texture2D, extra: Dictionary = {}) -> void:
	# Plain Panel + icon — clicks handled in _input via global rect hit-test
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(40, 40)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.focus_mode = Control.FOCUS_NONE
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var slot_style := StyleBoxFlat.new()
	slot_style.bg_color = Color(0.12, 0.1, 0.08, 0.9)
	slot_style.border_color = Color(0.95, 0.78, 0.28, 0.8)
	slot_style.set_border_width_all(2)
	slot_style.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("panel", slot_style)

	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 3
	icon.offset_top = 3
	icon.offset_right = -3
	icon.offset_bottom = -3
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.focus_mode = Control.FOCUS_NONE
	if tex:
		icon.texture = tex
	slot.add_child(icon)

	var entry := {"id": id, "slot": slot, "icon": icon}
	for k in extra:
		entry[k] = extra[k]
	slot.tooltip_text = get_inventory_tooltip(id, extra)
	_inv.append(entry)
	_inv_grid.add_child(slot)
	_update_held_items_visibility()


func _find_inv_entry(item_id: String) -> Dictionary:
	for e in _inv:
		if String(e.get("id", "")) == item_id:
			return e
	return {}


## Global mouse hit-test for held-item slots (does not rely on Button signals).
func _input(event: InputEvent) -> void:
	if _pills_dialog_open or _gun_give_dialog_open or _leave_dialog_open or _gun_lesson_dialog_open or _pack_dialog_open:
		return
	if _inv.is_empty():
		return
	if current_turn != "Player2" and current_turn != "Evaluation":
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var mouse: Vector2 = get_viewport().get_mouse_position()
	for e in _inv.duplicate():
		var slot: Control = e.get("slot") as Control
		if slot == null or not is_instance_valid(slot):
			continue
		if not slot.is_visible_in_tree():
			continue
		var rect: Rect2 = slot.get_global_rect()
		if rect.has_point(mouse):
			_on_inventory_slot_selected(e)
			get_viewport().set_input_as_handled()
			return


func _on_inventory_slot_selected(entry: Dictionary) -> void:
	var id: String = String(entry.get("id", ""))
	if id == ITEM_PILLS or id == "pill":
		_pending_inv_entry = entry
		show_pills_dialog()
		return
	# Both of these only exist to interact with the lizard. With no lizard to
	# hand to (or hold), the dialog would be a Cancel button — skip it.
	var lizard_available: bool = _is_pet_lizard_alive() and not _lizard_in_pack
	if id == ITEM_GUN:
		if not lizard_available:
			return
		_pending_inv_entry = entry
		show_gun_give_dialog()
		return
	if id == ITEM_FANNYPACK:
		if not lizard_available and not _lizard_in_pack:
			return
		_pending_inv_entry = entry
		show_pack_dialog()
		return


func _consume_inv_entry(entry: Dictionary) -> void:
	entry = _rebind_entry(entry)
	if entry.is_empty():
		return
	_inv.erase(entry)
	var slot: Control = entry.get("slot") as Control
	if slot and is_instance_valid(slot):
		slot.queue_free()

	# Clean -> ADHD boost (-10). Booby-trapped -> fent: -15 now, +10 next round.
	var was_trapped: bool = bool(entry.get("trapped", false))
	if was_trapped:
		_apply_p2_drowsy_debuff()
		apply_anxiety(EFFECT_DROWSY)
		set_status_message(MSG_FENT_PILLS)
	else:
		_apply_p2_speed_boost()
		apply_anxiety(EFFECT_ADHD)
		set_status_message("The meds kick in. Everything feels handleable.")
	_update_held_items_visibility()


## Inventory dictionaries get copied around; find the live entry by slot.
func _rebind_entry(entry: Dictionary) -> Dictionary:
	if _inv.has(entry):
		return entry
	for e in _inv:
		if e.get("slot") == entry.get("slot"):
			return e
	return {}


func _get_player2_body() -> Node:
	var p2: Node = null
	if is_instance_valid(player2):
		p2 = player2
	if p2 == null:
		p2 = get_node_or_null("/root/Main/Player2/Player2Body")
	if p2 == null:
		for b in get_tree().get_nodes_in_group("player_bodies"):
			if b.name == "Player2Body":
				p2 = b
				break
	return p2


func _apply_p2_speed_boost() -> void:
	var p2: Node = _get_player2_body()
	if p2 == null:
		push_error("ADHD boost FAILED: Player2Body not found")
		return
	if p2.has_method("apply_adhd_boost"):
		p2.call("apply_adhd_boost")
	else:
		p2.set("speed_mult", 2.5)
		p2.set("speed", 200.0)
		p2.set("anim_speed", 0.07)


func _apply_p2_drowsy_debuff() -> void:
	var p2: Node = _get_player2_body()
	if p2 == null:
		push_error("Drowsy debuff FAILED: Player2Body not found")
		return
	if p2.has_method("apply_drowsy_debuff"):
		p2.call("apply_drowsy_debuff")
	else:
		p2.set("speed_mult", 1.0)
		p2.set("speed", 50.0)
		p2.set("anim_speed", 0.28)


## ============================================================================
## HUD
## ============================================================================

func _build_hud() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		scene = get_parent()
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "GameHUD"
	_hud_layer.layer = 100
	_hud_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	scene.add_child(_hud_layer)

	if ResourceLoader.exists("res://PressStart2P-Regular.ttf"):
		_pixel_font = load("res://PressStart2P-Regular.ttf")

	var margin := MarginContainer.new()
	margin.name = "SidebarMargin"
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.offset_left = 16
	margin.offset_top = 16
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	_hud_layer.add_child(margin)

	_sidebar = VBoxContainer.new()
	_sidebar.name = "SidebarColumn"
	_sidebar.add_theme_constant_override("separation", 6)
	_sidebar.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(_sidebar)

	_build_trap_counter_panel()
	_build_anxiety_panel()
	_build_held_items_panel()
	_build_status_dialog_panel()
	_build_pills_dialog()
	_build_gun_give_dialog()
	_build_pack_dialog()
	_build_download_dialog()
	_build_evaluation_dialog()
	_build_leave_apartment_dialog()
	_build_gun_lesson_dialog()
	_ensure_leave_zone()
	_build_dev_panel()
	_update_hud()
	_update_held_items_visibility()
	set_status_message("")


func _build_dev_panel() -> void:
	if _hud_layer == null or not DevPanel.ENABLED:
		return
	var panel: Control = DevPanel.new()
	panel.name = "DevPanel"
	_hud_layer.add_child(panel)
	_dev = panel
	panel.setup(self, _pixel_font)


## Every prop in the scene that can hold a trap.
func _all_trappable_props() -> Array:
	var scene = get_tree().current_scene
	if scene == null:
		scene = get_parent()
	if scene == null:
		return []
	var out: Array = []
	var stack: Array = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.get("is_booby_trapped") != null:
			out.append(node)
		for c in node.get_children():
			stack.append(c)
	return out


## Dev: skip P1's setup phase and drop straight into P2's turn with `count`
## props trapped at random.
##
## Deliberately silent about WHICH props — the whole game is not knowing, so
## this logs a count only. Nothing is written to the console or the HUD that
## would give it away, and no P1 trap shimmer is applied.
func dev_start_p2_with_random_traps(count: int = 3) -> void:
	var props: Array = _all_trappable_props()
	if props.is_empty():
		push_warning("[DEV] no trappable props found")
		return
	for p in props:
		p.set("is_booby_trapped", false)
	props.shuffle()
	var n: int = mini(count, props.size())
	for i in n:
		props[i].set("is_booby_trapped", true)

	# Consume P1's phase outright and hand over.
	traps_left = 0
	p2_items_used = 0
	p2_inspects_left = P2_INSPECTS_MAX
	leave_available = false
	evaluation_active = false
	if current_turn != "Player2":
		current_turn = "Player1"
		switch_turn()
	UsableShimmer.set_p2_world_uses_exhausted(false)
	_update_hud()
	_update_held_items_visibility()
	set_status_message(MSG_P2_DEFAULT)
	print("[DEV] P2 turn started — %d of %d props trapped (not telling you which)" % [n, props.size()])


## Place-only variants for the dev panel (spawn without starting the encounter).
func cheat_run_police_encounter_setup() -> void:
	_cheat_place_arrival(PoliceNpc, "PoliceNPC", "Officer")


func cheat_run_landlord_encounter_setup() -> void:
	_cheat_place_arrival(LandlordNpc, "LandlordNPC", "Landlord")


func _build_trap_counter_panel() -> void:
	_hud_panel = PanelContainer.new()
	_hud_panel.name = "TrapCounterPanel"
	_hud_panel.add_theme_stylebox_override("panel", _gold_panel_style(12))
	_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sidebar.add_child(_hud_panel)

	_hud_label = Label.new()
	_apply_hud_label(_hud_label)
	_hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_panel.add_child(_hud_label)


## The one bar. Hovering it reveals every active modifier as an icon row.
func _build_anxiety_panel() -> void:
	_ensure_anxiety_system()
	var bar: PanelContainer = AnxietyBar.new()
	bar.name = "AnxietyPanel"
	_sidebar.add_child(bar)
	_anxiety_bar = bar
	bar.bind(anxiety, _pixel_font)


func _build_status_dialog_panel() -> void:
	_status_panel = PanelContainer.new()
	_status_panel.name = "StatusDialogPanel"
	_status_panel.add_theme_stylebox_override("panel", _gold_panel_style(8))
	_status_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_status_panel.custom_minimum_size = Vector2(STATUS_DIALOG_W, STATUS_DIALOG_H)
	_sidebar.add_child(_status_panel)

	_status_scroll = ScrollContainer.new()
	_status_scroll.name = "StatusScroll"
	_status_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_status_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_status_scroll.custom_minimum_size = Vector2(STATUS_DIALOG_W - 16.0, STATUS_DIALOG_H - 16.0)
	_status_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_status_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_status_panel.add_child(_status_scroll)

	_status_label = Label.new()
	_status_label.name = "StatusText"
	_apply_hud_label(_status_label)
	_status_label.add_theme_font_size_override("font_size", STATUS_FONT_SIZE)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.custom_minimum_size = Vector2(STATUS_DIALOG_W - 28.0, 0)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_scroll.add_child(_status_label)


func _build_held_items_panel() -> void:
	_inv_panel = PanelContainer.new()
	_inv_panel.name = "HeldItemsPanel"
	_inv_panel.add_theme_stylebox_override("panel", _gold_panel_style(8))
	_inv_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_inv_panel.visible = false
	_sidebar.add_child(_inv_panel)

	var inv_vbox := VBoxContainer.new()
	inv_vbox.add_theme_constant_override("separation", 6)
	inv_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inv_panel.add_child(inv_vbox)

	var inv_title := Label.new()
	inv_title.text = "Use"
	_apply_hud_label(inv_title)
	inv_title.add_theme_font_size_override("font_size", 10)
	inv_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inv_vbox.add_child(inv_title)

	_inv_grid = HBoxContainer.new()
	_inv_grid.name = "HeldGrid"
	_inv_grid.add_theme_constant_override("separation", 6)
	_inv_grid.custom_minimum_size = Vector2(148, 40)
	_inv_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inv_vbox.add_child(_inv_grid)


## ============================================================================
## Dialogs
## ============================================================================

func _build_pills_dialog() -> void:
	var built := _build_modal_shell("PillsDialog", "Pills", 220)
	var root: Control = built["root"]
	var col: VBoxContainer = built["col"]
	root.get_node("Dim").gui_input.connect(_on_pills_dim_gui_input)
	_pills_dialog = root

	var icon_row := CenterContainer.new()
	col.add_child(icon_row)
	var pill_tex: Texture2D = _load_texture_any("res://pill_bottle.png")
	if pill_tex:
		var icon := TextureRect.new()
		icon.texture = pill_tex
		icon.custom_minimum_size = Vector2(40, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_row.add_child(icon)

	var prompt := Label.new()
	_apply_hud_label(prompt)
	prompt.name = "Prompt"
	prompt.text = "Take pills?"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 10)
	col.add_child(prompt)

	var btn_row := HBoxContainer.new()
	btn_row.name = "Buttons"
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 10)
	col.add_child(btn_row)

	var take_btn := _make_dialog_button("Take", "TakeButton")
	take_btn.pressed.connect(_on_pills_take_pressed)
	btn_row.add_child(take_btn)

	var cancel_btn := _make_dialog_button("Cancel", "CancelButton")
	cancel_btn.pressed.connect(_on_pills_cancel_pressed)
	btn_row.add_child(cancel_btn)

	var give_btn := _make_dialog_button("Give pills to pet lizard", "GiveLizardButton")
	give_btn.custom_minimum_size = Vector2(200, 28)
	give_btn.pressed.connect(_on_pills_give_lizard_pressed)
	col.add_child(give_btn)


## Shared modal chrome: dim + purple frame + gold panel + content column.
func _build_modal_shell(node_name: String, title_text: String, width: int) -> Dictionary:
	var root := Control.new()
	root.name = node_name
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	_hud_layer.add_child(root)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.02, 0.05, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var outer := PanelContainer.new()
	outer.name = "OuterFrame"
	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = INV_PURPLE
	outer_style.border_color = INV_PURPLE.lightened(0.15)
	outer_style.set_border_width_all(2)
	outer_style.set_corner_radius_all(6)
	outer_style.set_content_margin_all(4)
	outer.add_theme_stylebox_override("panel", outer_style)
	center.add_child(outer)

	var panel := PanelContainer.new()
	panel.name = "DialogPanel"
	var panel_style := _gold_panel_style(14)
	panel_style.bg_color = Color(0.12, 0.08, 0.10, 0.96)
	panel.add_theme_stylebox_override("panel", panel_style)
	outer.add_child(panel)

	var col := VBoxContainer.new()
	col.name = "Content"
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(width, 0)
	panel.add_child(col)

	var title := Label.new()
	_apply_hud_label(title)
	title.name = "Title"
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	return {"root": root, "col": col, "panel": panel}


func _make_dialog_button(text: String, node_name: String) -> Button:
	var btn := Button.new()
	btn.name = node_name
	btn.text = text
	btn.custom_minimum_size = Vector2(84, 28)
	btn.focus_mode = Control.FOCUS_ALL
	if _pixel_font != null:
		btn.add_theme_font_override("font", _pixel_font)
	btn.add_theme_font_size_override("font_size", 10)
	btn.add_theme_color_override("font_color", HUD_TEXT)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.75, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.72, 0.35, 1.0))
	btn.add_theme_stylebox_override("normal", _dialog_button_style(false, false))
	btn.add_theme_stylebox_override("hover", _dialog_button_style(true, false))
	btn.add_theme_stylebox_override("pressed", _dialog_button_style(false, true))
	btn.add_theme_stylebox_override("focus", _dialog_button_style(true, false))
	return btn


func _dialog_button_style(hover: bool, pressed: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if pressed:
		style.bg_color = Color(0.22, 0.14, 0.08, 0.98)
	elif hover:
		style.bg_color = Color(0.20, 0.14, 0.18, 0.96)
	else:
		style.bg_color = Color(0.10, 0.08, 0.12, 0.96)
	style.border_color = HUD_BORDER if (hover or pressed) else HUD_BORDER.darkened(0.15)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	return style


func show_pills_dialog() -> void:
	if _pills_dialog == null:
		return
	_pills_dialog.visible = true
	_pills_dialog_open = true
	var give_btn := _pills_dialog.find_child("GiveLizardButton", true, false) as Button
	if give_btn:
		# Works through the fanny pack — you can reach in and feed it.
		give_btn.visible = _is_pet_lizard_alive()
		give_btn.text = "Give pills to lizard in pack" if _lizard_in_pack else "Give pills to pet lizard"
	var take_btn := _pills_dialog.find_child("TakeButton", true, false) as Button
	if take_btn:
		take_btn.grab_focus()


func _get_lizard() -> Node:
	return get_node_or_null("/root/Main/Roomate")


func _is_pet_lizard_alive() -> bool:
	var lizard := _get_lizard()
	if lizard == null:
		return false
	if lizard.has_method("is_alive"):
		return bool(lizard.call("is_alive"))
	return is_instance_valid(lizard)


## Called by the lizard when it dies. Mourning only lands if the player had
## adopted it (handed it pills), which is what the design asks for.
func notify_lizard_died(_cause: String = "") -> void:
	if _mourned_lizard or not _lizard_adopted:
		return
	_mourned_lizard = true
	apply_anxiety("mourning")
	set_status_message("The lizard is dead. You gave it those.")


## --- Gun give dialog (inventory click) ---

func _build_gun_give_dialog() -> void:
	var built := _build_modal_shell("GunGiveDialog", "Gun", 220)
	var root: Control = built["root"]
	var col: VBoxContainer = built["col"]
	root.get_node("Dim").gui_input.connect(_on_gun_give_dim_gui_input)
	_gun_give_dialog = root

	var icon_row := CenterContainer.new()
	col.add_child(icon_row)
	var gun_tex: Texture2D = _load_texture_any("res://handgun.png")
	if gun_tex:
		var icon := TextureRect.new()
		icon.texture = gun_tex
		icon.custom_minimum_size = Vector2(48, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_row.add_child(icon)

	var prompt := Label.new()
	_apply_hud_label(prompt)
	prompt.name = "Prompt"
	prompt.text = "Hand it over? Comfort drops to -5."
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.custom_minimum_size = Vector2(200, 0)
	prompt.add_theme_font_size_override("font_size", 10)
	col.add_child(prompt)

	var give_btn := _make_dialog_button("Give gun to lizard", "GiveGunLizardButton")
	give_btn.custom_minimum_size = Vector2(200, 28)
	give_btn.pressed.connect(_on_gun_give_lizard_pressed)
	col.add_child(give_btn)

	var cancel_btn := _make_dialog_button("Cancel", "GunCancelButton")
	cancel_btn.pressed.connect(_on_gun_give_cancel_pressed)
	col.add_child(cancel_btn)


func show_gun_give_dialog() -> void:
	if _gun_give_dialog == null:
		return
	_gun_give_dialog.visible = true
	_gun_give_dialog_open = true
	var give_btn := _gun_give_dialog.find_child("GiveGunLizardButton", true, false) as Button
	if give_btn:
		give_btn.visible = _is_pet_lizard_alive() and not _lizard_in_pack
		if give_btn.visible:
			give_btn.grab_focus()
		else:
			var cancel_btn := _gun_give_dialog.find_child("GunCancelButton", true, false) as Button
			if cancel_btn:
				cancel_btn.grab_focus()


func hide_gun_give_dialog() -> void:
	if _gun_give_dialog == null:
		return
	_gun_give_dialog.visible = false
	_gun_give_dialog_open = false


func _on_gun_give_lizard_pressed() -> void:
	var entry: Dictionary = _rebind_entry(_pending_inv_entry)
	_pending_inv_entry = {}
	hide_gun_give_dialog()
	if entry.is_empty() or not _is_pet_lizard_alive():
		return
	_inv.erase(entry)
	var slot: Control = entry.get("slot") as Control
	if slot and is_instance_valid(slot):
		slot.queue_free()
	_update_held_items_visibility()

	# You still feel safer knowing the gun is in the room — just less so.
	reprice_anxiety(ITEM_GUN, -5)

	var lizard := _get_lizard()
	if lizard and lizard.has_method("give_gun"):
		lizard.call("give_gun")
	set_status_message("The pet lizard took the gun — careful where it points that tail.")


func _on_gun_give_cancel_pressed() -> void:
	_pending_inv_entry = {}
	hide_gun_give_dialog()


func _on_gun_give_dim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_gun_give_cancel_pressed()


## --- Fanny pack dialog (stash / release the lizard) ---

func _build_pack_dialog() -> void:
	var built := _build_modal_shell("FannyPackDialog", "Fanny Pack", 240)
	var root: Control = built["root"]
	var col: VBoxContainer = built["col"]
	root.get_node("Dim").gui_input.connect(_on_pack_dim_gui_input)
	_pack_dialog = root

	var icon_row := CenterContainer.new()
	col.add_child(icon_row)
	var icon := TextureRect.new()
	icon.name = "PackIcon"
	icon.texture = _load_texture_any(TEX_FANNYPACK_ICON)
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_row.add_child(icon)

	var prompt := Label.new()
	_apply_hud_label(prompt)
	prompt.name = "PackPrompt"
	prompt.text = "What do you want to do?"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.custom_minimum_size = Vector2(220, 0)
	prompt.add_theme_font_size_override("font_size", 10)
	col.add_child(prompt)

	var stash_btn := _make_dialog_button("Put lizard in fanny pack", "PackStashButton")
	stash_btn.custom_minimum_size = Vector2(220, 28)
	stash_btn.pressed.connect(_on_pack_stash_pressed)
	col.add_child(stash_btn)

	var release_btn := _make_dialog_button("Let the lizard out", "PackReleaseButton")
	release_btn.custom_minimum_size = Vector2(220, 28)
	release_btn.pressed.connect(_on_pack_release_pressed)
	col.add_child(release_btn)

	var cancel_btn := _make_dialog_button("Cancel", "PackCancelButton")
	cancel_btn.pressed.connect(_on_pack_cancel_pressed)
	col.add_child(cancel_btn)


func show_pack_dialog() -> void:
	if _pack_dialog == null:
		return
	_pack_dialog.visible = true
	_pack_dialog_open = true
	var stash := _pack_dialog.find_child("PackStashButton", true, false) as Button
	var release := _pack_dialog.find_child("PackReleaseButton", true, false) as Button
	var prompt := _pack_dialog.find_child("PackPrompt", true, false) as Label
	var icon := _pack_dialog.find_child("PackIcon", true, false) as TextureRect
	var can_stash: bool = _is_pet_lizard_alive() and not _lizard_in_pack
	if stash:
		stash.visible = can_stash
	if release:
		release.visible = _lizard_in_pack
	if icon:
		icon.texture = _load_texture_any(TEX_FANNYPACK_LIZARD_ICON if _lizard_in_pack else TEX_FANNYPACK_ICON)
	if prompt:
		if _lizard_in_pack:
			prompt.text = "There is a lizard in here." + _armed_lizard_note()
		elif can_stash:
			prompt.text = "The lizard would fit in here."
		else:
			prompt.text = "Just a fanny pack. Still cool."
	var focus_btn: Button = release if _lizard_in_pack else (stash if can_stash else _pack_dialog.find_child("PackCancelButton", true, false) as Button)
	if focus_btn and focus_btn.visible:
		focus_btn.grab_focus()


func hide_pack_dialog() -> void:
	if _pack_dialog == null:
		return
	_pack_dialog.visible = false
	_pack_dialog_open = false


func _on_pack_stash_pressed() -> void:
	_pending_inv_entry = {}
	hide_pack_dialog()
	if not _is_pet_lizard_alive() or _lizard_in_pack:
		return
	var lizard := _get_lizard()
	if lizard and lizard.has_method("enter_fannypack"):
		lizard.call("enter_fannypack")
	_lizard_in_pack = true
	_refresh_pack_icon()
	set_status_message("The lizard is in the fanny pack. It seems fine with this.")


func _on_pack_release_pressed() -> void:
	_pending_inv_entry = {}
	hide_pack_dialog()
	if not _lizard_in_pack:
		return
	var lizard := _get_lizard()
	var drop: Vector2 = Vector2.ZERO
	var p2: Node2D = _get_player2_body() as Node2D
	if p2:
		drop = p2.global_position + Vector2(18.0, 10.0)
	if lizard and lizard.has_method("exit_fannypack"):
		lizard.call("exit_fannypack", drop)
	_lizard_in_pack = false
	_refresh_pack_icon()
	set_status_message("The lizard is back on the floor, gear and all.")


func _on_pack_cancel_pressed() -> void:
	_pending_inv_entry = {}
	hide_pack_dialog()


func _on_pack_dim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_pack_cancel_pressed()


## Appended wherever the packed lizard is described. A lizard that went into
## the bag holding a handgun is still holding it, and that is worth saying out
## loud every single time.
func _armed_lizard_note() -> String:
	if not _lizard_in_pack:
		return ""
	var lizard: Node = _get_lizard()
	if lizard == null or not lizard.has_method("has_gun") or not bool(lizard.call("has_gun")):
		return ""
	return "\nHe has a gun. He's not giving it back."


## Swap the bag icon so you can see the lizard is inside.
func _refresh_pack_icon() -> void:
	var entry: Dictionary = _find_inv_entry(ITEM_FANNYPACK)
	if entry.is_empty():
		return
	var icon: TextureRect = entry.get("icon") as TextureRect
	if icon and is_instance_valid(icon):
		icon.texture = _load_texture_any(TEX_FANNYPACK_LIZARD_ICON if _lizard_in_pack else TEX_FANNYPACK_ICON)
	var slot: Control = entry.get("slot") as Control
	if slot and is_instance_valid(slot):
		slot.tooltip_text = get_inventory_tooltip(ITEM_FANNYPACK, {})


## --- Download trap popup ---

func show_download_trap_popup(duration: float = 2.5) -> void:
	if _download_dialog == null:
		return
	_download_dialog.visible = true
	var steps := [".", "..", "..."]
	var step_t := duration / float(steps.size())
	for i in steps.size():
		if _download_dots_label:
			_download_dots_label.text = steps[i]
		await get_tree().create_timer(step_t).timeout
	if is_instance_valid(_download_dialog):
		_download_dialog.visible = false


func _build_download_dialog() -> void:
	if _hud_layer == null:
		return
	var root := Control.new()
	root.name = "DownloadTrapDialog"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	_hud_layer.add_child(root)
	_download_dialog = root

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.02, 0.05, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var outer := PanelContainer.new()
	outer.name = "OuterFrame"
	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = INV_PURPLE
	outer_style.border_color = INV_PURPLE.lightened(0.15)
	outer_style.set_border_width_all(3)
	outer_style.set_corner_radius_all(8)
	outer_style.set_content_margin_all(6)
	outer.add_theme_stylebox_override("panel", outer_style)
	center.add_child(outer)

	var panel := PanelContainer.new()
	panel.name = "DialogPanel"
	var panel_style := _gold_panel_style(20)
	panel_style.bg_color = Color(0.12, 0.08, 0.10, 0.96)
	panel.add_theme_stylebox_override("panel", panel_style)
	outer.add_child(panel)

	var col := VBoxContainer.new()
	col.name = "Content"
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(420, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)

	var white := Color(1.0, 1.0, 1.0, 1.0)
	const DL_FONT := 16

	var line1 := Label.new()
	line1.name = "Line1"
	line1.text = "DOWNLOADING HIGHLY"
	line1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _pixel_font != null:
		line1.add_theme_font_override("font", _pixel_font)
	line1.add_theme_font_size_override("font_size", DL_FONT)
	line1.add_theme_color_override("font_color", white)
	col.add_child(line1)

	var row2 := HBoxContainer.new()
	row2.name = "Line2Row"
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 0)
	col.add_child(row2)

	var line2 := Label.new()
	line2.name = "Line2Base"
	line2.text = "ILLEGAL MATERIAL"
	if _pixel_font != null:
		line2.add_theme_font_override("font", _pixel_font)
	line2.add_theme_font_size_override("font_size", DL_FONT)
	line2.add_theme_color_override("font_color", white)
	row2.add_child(line2)

	var dots := Label.new()
	dots.name = "Line2Dots"
	dots.text = "."
	dots.custom_minimum_size = Vector2(54, 0)
	if _pixel_font != null:
		dots.add_theme_font_override("font", _pixel_font)
	dots.add_theme_font_size_override("font_size", DL_FONT)
	dots.add_theme_color_override("font_color", white)
	row2.add_child(dots)
	_download_dots_label = dots


func hide_pills_dialog() -> void:
	if _pills_dialog == null:
		return
	_pills_dialog.visible = false
	_pills_dialog_open = false


func is_pills_dialog_open() -> bool:
	return _pills_dialog_open


## --- Stairs leave zone + bobbing arrow + "Leave Apartment?" dialog ---

func _ensure_leave_zone() -> void:
	if _leave_zone != null and is_instance_valid(_leave_zone):
		return
	var scene = get_tree().current_scene
	if scene == null:
		scene = get_parent()
	if scene == null:
		return

	var zone := Area2D.new()
	zone.name = "LeaveStairZone"
	zone.monitoring = false
	zone.monitorable = false
	zone.collision_layer = 0
	zone.collision_mask = 1
	zone.visible = false
	scene.add_child(zone)
	_leave_zone = zone

	var size := LEAVE_ZONE_MAX - LEAVE_ZONE_MIN
	var center := (LEAVE_ZONE_MIN + LEAVE_ZONE_MAX) * 0.5

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	col.position = center
	zone.add_child(col)

	_leave_arrow = _make_stairs_arrow()
	_leave_arrow.visible = false
	_leave_arrow.position = STAIRS_ARROW_POS
	scene.add_child(_leave_arrow)

	zone.body_entered.connect(_on_leave_zone_body_entered)
	zone.body_exited.connect(_on_leave_zone_body_exited)


func _make_stairs_arrow() -> Node2D:
	var root := Node2D.new()
	root.name = "StairsLeaveArrow"
	root.z_index = 20

	var outline := Polygon2D.new()
	outline.name = "Outline"
	outline.color = Color(0.08, 0.06, 0.04, 0.95)
	outline.polygon = PackedVector2Array([
		Vector2(0, 34),
		Vector2(-18, 10),
		Vector2(-8, 10),
		Vector2(-8, -24),
		Vector2(8, -24),
		Vector2(8, 10),
		Vector2(18, 10),
	])
	root.add_child(outline)

	var fill := Polygon2D.new()
	fill.name = "Fill"
	fill.color = Color(1.0, 0.86, 0.28, 1.0)
	fill.polygon = PackedVector2Array([
		Vector2(0, 30),
		Vector2(-14, 10),
		Vector2(-6, 10),
		Vector2(-6, -20),
		Vector2(6, -20),
		Vector2(6, 10),
		Vector2(14, 10),
	])
	root.add_child(fill)

	return root


func _on_leave_zone_body_entered(body: Node) -> void:
	if not leave_available:
		return
	if evaluation_active and leave_intent != "next_map":
		return
	if body != player2 and body != _get_player2_body():
		return
	_in_leave_zone = true
	if _leave_prompt_blocked or _leave_dialog_open:
		return
	show_leave_apartment_dialog()


func _on_leave_zone_body_exited(body: Node) -> void:
	if body != player2 and body != _get_player2_body():
		return
	_in_leave_zone = false
	_leave_prompt_blocked = false
	if _leave_dialog_open:
		hide_leave_apartment_dialog()


func _build_leave_apartment_dialog() -> void:
	if _hud_layer == null:
		return
	var built := _build_modal_shell("LeaveApartmentDialog", MSG_LEAVE_PROMPT, 320)
	_leave_dialog = built["root"]
	var col: VBoxContainer = built["col"]

	var btn_row := HBoxContainer.new()
	btn_row.name = "Buttons"
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 14)
	col.add_child(btn_row)

	var yes_btn := _make_dialog_button("Yes", "YesButton")
	yes_btn.pressed.connect(_on_leave_yes_pressed)
	btn_row.add_child(yes_btn)

	var no_btn := _make_dialog_button("No", "NoButton")
	no_btn.pressed.connect(_on_leave_no_pressed)
	btn_row.add_child(no_btn)


func show_leave_apartment_dialog() -> void:
	if _leave_dialog == null or not leave_available:
		return
	# First leave is blocked once evaluation starts; next-map leave is allowed.
	if evaluation_active and leave_intent != "next_map":
		return
	if _leave_dialog_open:
		return
	_leave_dialog.visible = true
	_leave_dialog_open = true
	var yes_btn := _leave_dialog.find_child("YesButton", true, false) as Button
	if yes_btn:
		yes_btn.grab_focus()


func hide_leave_apartment_dialog() -> void:
	if _leave_dialog == null:
		return
	_leave_dialog.visible = false
	_leave_dialog_open = false


func _on_leave_yes_pressed() -> void:
	hide_leave_apartment_dialog()
	if leave_intent == "next_map":
		start_next_map_round()
	else:
		begin_end_of_round_evaluation()


func _on_leave_no_pressed() -> void:
	_leave_prompt_blocked = true
	hide_leave_apartment_dialog()


## ============================================================================
## Round / map transition
## ============================================================================

## After Yes on post-encounter stairs: swap map, reset traps, hand control to P1.
func start_next_map_round() -> void:
	leave_available = false
	leave_intent = "end_round"
	if _leave_arrow:
		_leave_arrow.visible = false
	if _leave_zone:
		_leave_zone.monitoring = false

	# Anxiety "next round" re-prices (e.g. fent pills).
	begin_next_round()

	round_index += 1
	var to_office: bool = round_index >= 2
	if to_office:
		_set_background_map(MAP_OFFICE)
		_apply_map_layout("office")
	else:
		_set_background_map(MAP_BEDROOM)
		_apply_map_layout("bedroom")

	# Clear end-of-round encounter state.
	evaluation_active = false
	pipe_bomb_detonated = false
	illegal_download = false
	_npc_flees = false
	_npc_name = "NPC"
	if _fireman != null and is_instance_valid(_fireman):
		_fireman.queue_free()
	_fireman = null
	# Drop any leftover smoke / eject FX from the bedroom round.
	_clear_transient_fx()

	# Trap / use budgets for a fresh setup phase.
	traps_left = TRAPS_MAX
	p2_items_used = 0
	p2_inspects_left = P2_INSPECTS_MAX
	if to_office:
		# Bedroom props are gone — do not re-arm them.
		_clear_held_inventory()
	else:
		_reset_props_for_new_round()
		UsableShimmer.reset_all_for_new_round()

	# P1 places traps again (office currently has no interactables until wired).
	current_turn = "Player1"
	if is_instance_valid(player1):
		player1.set_active(true)
	if is_instance_valid(player2):
		player2.set_active(false)
	UsableShimmer.on_turn_changed("Player1")
	_update_hud()
	_update_held_items_visibility()
	if to_office:
		set_status_message("New office. Walk around — traps for this floor come next.")
	else:
		set_status_message("New location. Set your booby traps.")
	print("[ROUND] Started round ", round_index, " map=", MAP_OFFICE if to_office else MAP_BEDROOM)


func _set_background_map(path: String) -> void:
	var bg := get_node_or_null("/root/Main/Background") as Sprite2D
	if bg == null:
		var scene = get_tree().current_scene
		if scene:
			bg = scene.get_node_or_null("Background") as Sprite2D
	if bg == null:
		push_error("[MAP] Background node not found")
		return
	var tex: Texture2D = _load_texture_any(path)
	if tex == null:
		push_error("[MAP] Failed to load ", path)
		return
	bg.texture = tex
	# Room art is always 1390×1640 displayed at 0.4 in Stick Figure 4.
	bg.scale = Vector2(0.4, 0.4)
	print("[MAP] Background set to ", path)


## Bedroom props/colliders live in Stick Figure 4.tscn. Office uses only the
## painted background + outer walls/stairs until dedicated office props exist.
const BEDROOM_PROP_NODES := [
	"Plant", "Lamp", "LaptopCutOut", "PillBottle", "DresserProp",
	"Roomate", "HatRack", "Bookshelf", "MeditationPillow",
	"LizardOnlyBlocker", "LizardOnlyBlocker2", "LizardOnlyBlocker3",
	"LizardOnlyBlocker4", "LizardOnlyBlocker5", "LizardOnlyBlocker6",
	"LizardOnlyBlocker7",
]
## Furniture blockers that match bedroom layout (not outer walls / stairs).
const BEDROOM_BOUNDARY_SHAPES := [
	"Dresser", "Bed", "Table", "Chest",
]


func _main_scene() -> Node:
	var scene = get_tree().current_scene
	if scene:
		return scene
	return get_parent()


func _apply_map_layout(layout: String) -> void:
	var main: Node = _main_scene()
	if main == null:
		return
	var show_bedroom: bool = layout == "bedroom"
	for name in BEDROOM_PROP_NODES:
		var n: Node = main.get_node_or_null(String(name))
		if n == null:
			continue
		_set_node_active_for_map(n, show_bedroom)
	var bounds: Node = main.get_node_or_null("RoomBoundaries")
	if bounds:
		for name in BEDROOM_BOUNDARY_SHAPES:
			var col: Node = bounds.get_node_or_null(String(name))
			if col is CollisionShape2D:
				(col as CollisionShape2D).disabled = not show_bedroom
			elif col is CollisionPolygon2D:
				(col as CollisionPolygon2D).disabled = not show_bedroom
			elif col is Node2D:
				(col as Node2D).visible = show_bedroom
	print("[MAP] layout=", layout, " bedroom_props_visible=", show_bedroom)


func _set_node_active_for_map(n: Node, active: bool) -> void:
	if n is CanvasItem:
		(n as CanvasItem).visible = active
	# Disable areas / bodies so hidden props cannot be used or block movement.
	if n is Area2D:
		(n as Area2D).monitoring = active
		(n as Area2D).monitorable = active
	if n is CollisionObject2D:
		# Keep layer/mask; disable shapes under it.
		pass
	for c in n.get_children():
		if c is CollisionShape2D:
			(c as CollisionShape2D).disabled = not active
		elif c is CollisionPolygon2D:
			(c as CollisionPolygon2D).disabled = not active
		elif c is Area2D:
			(c as Area2D).monitoring = active
			(c as Area2D).monitorable = active
			for cc in c.get_children():
				if cc is CollisionShape2D:
					(cc as CollisionShape2D).disabled = not active
		elif c is StaticBody2D or c is CharacterBody2D:
			for cc in c.get_children():
				if cc is CollisionShape2D:
					(cc as CollisionShape2D).disabled = not active
				elif cc is CollisionPolygon2D:
					(cc as CollisionPolygon2D).disabled = not active
		elif c is CanvasItem and c is not Label:
			# Nested sprites (open dresser etc.) follow parent visibility.
			pass


func _clear_held_inventory() -> void:
	for e in _inv.duplicate():
		var slot: Control = e.get("slot") as Control
		if slot and is_instance_valid(slot):
			slot.queue_free()
	_inv.clear()
	_pending_inv_entry = {}
	_update_held_items_visibility()


func _clear_transient_fx() -> void:
	var main: Node = _main_scene()
	if main == null:
		return
	for child in main.get_children():
		# Runtime-only FX / ejects from round 1 (not permanent scene props).
		var nm: String = String(child.name)
		if nm.begins_with("PlantSmoke") or nm.begins_with("GunEject") \
				or nm.begins_with("PipeBomb") or nm.begins_with("MeditationDemon") \
				or nm == "PlantSmokeGIF":
			child.queue_free()


func _reset_props_for_new_round() -> void:
	for p in _all_trappable_props():
		if p.get("is_booby_trapped") != null:
			p.set("is_booby_trapped", false)
		# Optional per-prop hook (dresser texture, pill bottle restore, etc.).
		if p.has_method("reset_for_new_round"):
			p.call("reset_for_new_round")
		elif p.has_method("reset_round"):
			p.call("reset_round")


## --- Gun lesson dialog (after failed fireman check) ---

func _build_gun_lesson_dialog() -> void:
	if _hud_layer == null:
		return
	var built := _build_modal_shell("GunLessonDialog", MSG_GUN_PROMPT % _npc_name, 360)
	_gun_lesson_dialog = built["root"]
	var col: VBoxContainer = built["col"]
	var title := _gun_lesson_dialog.find_child("Title", true, false) as Label
	if title:
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.custom_minimum_size = Vector2(320, 0)
		title.add_theme_font_size_override("font_size", 12)

	var gun_tex: Texture2D = _load_texture_any("res://handgun.png")
	if gun_tex:
		var icon_row := CenterContainer.new()
		col.add_child(icon_row)
		var icon := TextureRect.new()
		icon.texture = gun_tex
		icon.custom_minimum_size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_row.add_child(icon)

	var warn := Label.new()
	_apply_hud_label(warn)
	warn.text = "85% they back off (-10 anxiety, and whatever they just did to you is undone). 15% it goes off."
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.custom_minimum_size = Vector2(320, 0)
	warn.add_theme_font_size_override("font_size", 8)
	warn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45, 1.0))
	col.add_child(warn)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 14)
	col.add_child(btn_row)

	var yes_btn := _make_dialog_button("Wave gun menacingly", "GunYesButton")
	yes_btn.custom_minimum_size = Vector2(210, 28)
	yes_btn.pressed.connect(_on_gun_lesson_yes)
	btn_row.add_child(yes_btn)

	var no_btn := _make_dialog_button("Keep it holstered", "GunNoButton")
	no_btn.custom_minimum_size = Vector2(160, 28)
	no_btn.pressed.connect(_on_gun_lesson_no)
	btn_row.add_child(no_btn)


func show_gun_lesson_dialog() -> bool:
	if _gun_lesson_dialog == null:
		_build_gun_lesson_dialog()
	if _gun_lesson_dialog == null:
		return false
	# Retitle for whoever is actually standing there.
	var title := _gun_lesson_dialog.find_child("Title", true, false) as Label
	if title:
		title.text = MSG_GUN_PROMPT % _npc_name
	_gun_lesson_choice = -1
	_gun_lesson_waiting = true
	_gun_lesson_dialog_open = true
	_gun_lesson_dialog.visible = true
	var yes_btn := _gun_lesson_dialog.find_child("GunYesButton", true, false) as Button
	if yes_btn:
		yes_btn.grab_focus()
	while _gun_lesson_waiting and is_instance_valid(self):
		await get_tree().process_frame
	_gun_lesson_dialog_open = false
	if is_instance_valid(_gun_lesson_dialog):
		_gun_lesson_dialog.visible = false
	return _gun_lesson_choice == 1


func _on_gun_lesson_yes() -> void:
	_gun_lesson_choice = 1
	_gun_lesson_waiting = false


func _on_gun_lesson_no() -> void:
	_gun_lesson_choice = 0
	_gun_lesson_waiting = false


## --- End-of-round evaluation popup ---

func _build_evaluation_dialog() -> void:
	if _hud_layer == null:
		return
	var built := _build_modal_shell("EvaluationDialog", "END OF ROUND", 400)
	_eval_dialog = built["root"]
	var col: VBoxContainer = built["col"]
	_eval_title = _eval_dialog.find_child("Title", true, false) as Label

	_eval_label = Label.new()
	_eval_label.name = "EvalText"
	_eval_label.text = ""
	_eval_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_eval_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_eval_label.custom_minimum_size = Vector2(360, 0)
	if _pixel_font != null:
		_eval_label.add_theme_font_override("font", _pixel_font)
	_eval_label.add_theme_font_size_override("font_size", 12)
	_eval_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	col.add_child(_eval_label)


## Show evaluation popup; type full_text onto the Label, then hold.
func show_evaluation_popup(full_text: String) -> void:
	if _eval_dialog == null or _eval_label == null:
		return
	_eval_label.text = ""
	_eval_dialog.visible = true
	var delay: float = 1.0 / maxf(EVAL_TYPE_CPS, 1.0)
	for i in range(full_text.length()):
		_eval_label.text = full_text.substr(0, i + 1)
		await get_tree().create_timer(delay).timeout
	await get_tree().create_timer(EVAL_HOLD_AFTER_TEXT_SEC).timeout
	if is_instance_valid(_eval_dialog):
		_eval_dialog.visible = false
		_eval_label.text = ""


func _on_pills_take_pressed() -> void:
	var entry: Dictionary = _pending_inv_entry
	_pending_inv_entry = {}
	hide_pills_dialog()
	pills_take_pressed.emit()
	if not entry.is_empty():
		_consume_inv_entry(entry)


func _on_pills_give_lizard_pressed() -> void:
	var entry: Dictionary = _pending_inv_entry
	_pending_inv_entry = {}
	hide_pills_dialog()
	if entry.is_empty():
		return
	if not _is_pet_lizard_alive():
		_consume_inv_entry(entry)
		return
	_give_pills_to_lizard(entry)


## Handing the pills away costs and gains nothing — but it makes the lizard
## yours, which is what Mourning keys off if it dies.
func _give_pills_to_lizard(entry: Dictionary) -> void:
	entry = _rebind_entry(entry)
	if entry.is_empty():
		return
	_inv.erase(entry)
	var slot: Control = entry.get("slot") as Control
	if slot and is_instance_valid(slot):
		slot.queue_free()
	_update_held_items_visibility()

	_lizard_adopted = true
	var trapped: bool = bool(entry.get("trapped", false))
	var lizard := _get_lizard()
	if lizard and lizard.has_method("give_pills"):
		lizard.call("give_pills", trapped)
	if trapped:
		set_status_message(
			"You reached into the pack and gave it the bad pills..." if _lizard_in_pack
			else "You gave the bad pills to the pet lizard..."
		)
	else:
		set_status_message(
			"The lizard takes the clean pills without leaving the pack." if _lizard_in_pack
			else "The pet lizard zooms on clean pills!"
		)


func _on_pills_cancel_pressed() -> void:
	_pending_inv_entry = {}
	hide_pills_dialog()
	pills_dialog_cancelled.emit()


func _on_pills_dim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_pills_cancel_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if _gun_lesson_dialog_open:
		if event.keycode == KEY_ESCAPE:
			_on_gun_lesson_no()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_on_gun_lesson_yes()
			get_viewport().set_input_as_handled()
		return
	if _leave_dialog_open:
		if event.keycode == KEY_ESCAPE:
			_on_leave_no_pressed()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_on_leave_yes_pressed()
			get_viewport().set_input_as_handled()
		return
	if _pack_dialog_open:
		if event.keycode == KEY_ESCAPE:
			_on_pack_cancel_pressed()
			get_viewport().set_input_as_handled()
		return
	if _gun_give_dialog_open:
		if event.keycode == KEY_ESCAPE:
			_on_gun_give_cancel_pressed()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if _is_pet_lizard_alive():
				_on_gun_give_lizard_pressed()
			else:
				_on_gun_give_cancel_pressed()
			get_viewport().set_input_as_handled()
		return
	if not _pills_dialog_open:
		return
	if event.keycode == KEY_ESCAPE:
		_on_pills_cancel_pressed()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		_on_pills_take_pressed()
		get_viewport().set_input_as_handled()


func _gold_panel_style(content_margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = HUD_BG
	style.border_color = HUD_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(content_margin)
	return style


func _apply_hud_label(label: Label) -> void:
	if _pixel_font != null:
		label.add_theme_font_override("font", _pixel_font)
	label.add_theme_font_size_override("font_size", HUD_FONT_SIZE)
	label.add_theme_color_override("font_color", HUD_TEXT)


func _update_held_items_visibility() -> void:
	if _inv_panel == null:
		return
	var p2_phase: bool = (current_turn == "Player2" or current_turn == "Evaluation")
	_inv_panel.visible = p2_phase and _inv.size() > 0


func _refresh_visuals() -> void:
	var shimmer_turn: String = current_turn
	if shimmer_turn == "Evaluation":
		shimmer_turn = "Player2"
	UsableShimmer.on_turn_changed(shimmer_turn)
	_update_hud()
	_update_held_items_visibility()


func _update_hud() -> void:
	if _hud_label == null or _hud_layer == null:
		return
	var is_p2: bool = current_turn == "Player2" or current_turn == "Evaluation"
	if current_turn == "Evaluation":
		if _fireman != null and is_instance_valid(_fireman):
			match _npc_kind():
				"police":
					_hud_label.text = "Police arrived"
				"landlord":
					_hud_label.text = "Landlord arrived"
				_:
					_hud_label.text = "Fire Department arrived"
		else:
			_hud_label.text = "End of Round..."
	elif is_p2 and leave_available:
		_hud_label.text = "Items: %d/%d — Leave via stairs" % [p2_items_used, P2_USES_MAX]
	elif is_p2:
		_hud_label.text = "Items Used: %d/%d   Inspects: %d/%d" % [
			p2_items_used, P2_USES_MAX, p2_inspects_left, P2_INSPECTS_MAX
		]
	else:
		_hud_label.text = "Booby Traps: %d/%d" % [traps_left, TRAPS_MAX]
	# P1 sets traps and has no anxiety of their own — bar is P2 only.
	if _anxiety_bar:
		_anxiety_bar.visible = is_p2
	_hud_layer.visible = true
	_refresh_anxiety_bar()
