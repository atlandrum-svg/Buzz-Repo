extends Node

const UsableShimmer = preload("res://usable_shimmer.gd")
const FiremanNpc = preload("res://fireman_npc.gd")
const SpinWheelPopup = preload("res://spin_wheel_popup.gd")

@onready var player1 = $/root/Main/Player1/Player1Body
@onready var player2 = $/root/Main/Player2/Player2Body
var current_turn = "Player1"

const TRAPS_MAX := 3
const P2_USES_MAX := 3
var traps_left := TRAPS_MAX
var p2_items_used := 0

## --- Character stats (real system, not cosmetic) ---
const STAT_MAX := 100
const STAT_CHECK_THRESHOLD := 50

## P2 archetype. Only TECH_BRO is playable for now; others reserved.
enum Archetype { TECH_BRO, GYM_BRO, FINANCE_BRO }
const ARCHETYPE_BASE := {
	Archetype.TECH_BRO: {"agility": 25, "charisma": 25, "intelligence": 75},
	Archetype.GYM_BRO: {"agility": 75, "charisma": 25, "intelligence": 25},
	Archetype.FINANCE_BRO: {"agility": 25, "charisma": 75, "intelligence": 25},
}
var p2_archetype: int = Archetype.TECH_BRO
## Base from archetype (reset on archetype change).
var base_agility: int = 25
var base_charisma: int = 25
var base_intelligence: int = 75
## Permanent deltas from wheel outcomes / story events.
var delta_agility: int = 0
var delta_charisma: int = 0
var delta_intelligence: int = 0
## Effective stats shown on HUD (base + status mods + deltas), clamped 0..STAT_MAX.
var agility: int = 25
var charisma: int = 25
var intelligence: int = 75

# HUD / dialog styling (matches Fizz PR art language)
const HUD_BG := Color(0.08, 0.08, 0.12, 0.82)
const HUD_BORDER := Color(0.95, 0.78, 0.28, 0.95)
const HUD_TEXT := Color(1.0, 0.92, 0.55, 1.0)
const HUD_FONT_SIZE := 14
const BAR_FILL := Color(0.95, 0.78, 0.28, 1.0)
const BAR_EMPTY := Color(0.18, 0.16, 0.14, 0.95)
const INV_PURPLE := Color(0.48, 0.30, 0.62, 0.98)
const EFFECT_SLOT_PX := 28
const EFFECT_SLOT_BG := Color(0.10, 0.07, 0.06, 0.96)
const EFFECT_SLOT_BORDER := Color(0.22, 0.14, 0.10, 1.0)
const BUFF_BORDER := Color(0.35, 0.75, 0.40, 0.95)
const DEBUFF_BORDER := Color(0.85, 0.30, 0.35, 0.95)

const ITEM_PILLS := "pills"
const ITEM_GUN := "gun"
const EFFECT_ADHD := "adhd_boost"
const EFFECT_DROWSY := "drowsy"
const EFFECT_VISHNU := "vishnu_demon"
const EFFECT_MURDERER := "murderer"
const EFFECT_ATTEMPTED_MURDER := "attempted_murder"

const MSG_GUN_PROMPT := "You have a gun. Teach this Fireman a lesson?"
const MSG_GUN_SHOT := "You have shot the Fireman's head smoove off!"
const MSG_GUN_FENT_LEG := "You tried to shoot the Fireman, but your aim was bad due to being on fent. You have blown off his leg..."
## After fent gun miss: Attempted Murder lasts this long, then upgrades to Murderer.
const ATTEMPTED_MURDER_UPGRADE_SEC := 15.0
## Fireman bleeds out / stops for good after this (even mid-crawl or later rounds).
const FIREMAN_CRAWL_DEATH_SEC := 120.0

## Sidebar status dialog (scrollable). Replaced by set_status_message().
const MSG_P2_DEFAULT := "Use (3) Items Before You Can Proceed!"
const MSG_VISHNU_POSSESS := "You have been possessed by a 4 dimensional demon..."
const MSG_FENT_PILLS := "You have taken fent..."
## End-of-round evaluation lines (set on Label in Godot — not baked art).
## Played in order via _build_eval_message_queue() when the player leaves.
const MSG_EVAL_FIRE_DEPT := "The Fire Department was called because an explosion was heard!"
const MSG_EVAL_ILLEGAL_DOWNLOAD := "You have downloaded illegal material onto your laptop! The cops have been called!"
const STATUS_DIALOG_H := 88.0
const STATUS_DIALOG_W := 168.0
const STATUS_FONT_SIZE := 10

## Stairs leave zone (world AABB: x -240..-140, y 100..225). Invisible trigger only.
const LEAVE_ZONE_MIN := Vector2(-240.0, 100.0)
const LEAVE_ZONE_MAX := Vector2(-140.0, 225.0)
## World position of the "go downstairs" arrow (above the stair collider).
const STAIRS_ARROW_POS := Vector2(-156.0, 95.0)
const ARROW_BOB_AMP := 7.0
const ARROW_BOB_SPEED := 3.2
const MSG_LEAVE_READY := "Leave the apartment via the stairs when ready."
const MSG_LEAVE_PROMPT := "Leave Apartment?"
const EVAL_TYPE_CPS := 32.0 ## characters per second for evaluation popup typewriter
const EVAL_HOLD_AFTER_TEXT_SEC := 2.5
const EVAL_GAP_BETWEEN_MSGS_SEC := 0.35
## After any arrival NPC finishes walking in, wait this long then open the fate wheel.
const NPC_ARRIVAL_WHEEL_DELAY_SEC := 2.0

## Emitted when the player confirms Take on the Pills dialog.
signal pills_take_pressed
## Emitted when the player cancels / closes the Pills dialog.
signal pills_dialog_cancelled
## Emitted after end-of-round evaluation sequence finishes (popup closed).
signal end_of_round_evaluation_finished

var _hud_layer: CanvasLayer
var _hud_label: Label
var _hud_panel: PanelContainer
var _sidebar: VBoxContainer
var _stats_panel: PanelContainer
var _stat_bars: Dictionary = {} # name -> {fill: ColorRect, value_label: Label}
## Held consumables (gameplay bag — not a permanent empty inventory grid).
## { "id": String, "trapped": bool, "slot": Control }
var _inv: Array = []
var _inv_panel: PanelContainer
var _inv_grid: HBoxContainer

## Active buff/debuff icons: id -> { kind, texture, label, slot }
var _effects: Dictionary = {}
var _effects_panel: PanelContainer
var _buffs_row: HBoxContainer
var _debuffs_row: HBoxContainer
var _buffs_empty: Label
var _debuffs_empty: Label

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
## Inventory entry waiting on dialog confirm (Take).
var _pending_inv_entry: Dictionary = {}
## Booby-trapped laptop "downloading" popup (centered, timed).
var _download_dialog: Control
var _download_dots_label: Label
## "You have a gun. Teach this Fireman a lesson?" Yes/No after a failed social check.
var _gun_lesson_dialog: Control
var _gun_lesson_dialog_open: bool = false
var _gun_lesson_waiting: bool = false
var _gun_lesson_choice: int = -1 ## -1 pending, 0 no, 1 yes

## End-of-round evaluation (after P2 confirms leave at stairs).
var evaluation_active: bool = false
## True once P2 has used 3 items — stairs arrow + leave prompt available.
var leave_available: bool = false
## Round outcome flags (set by prop scripts during P2 turn). Queued in fixed order at leave.
var pipe_bomb_detonated: bool = false
var illegal_download: bool = false
## Persisted P2 status (re-asserted after evaluation so HUD + speed never drop).
var p2_adhd_active: bool = false
var p2_drowsy_active: bool = false
var p2_vishnu_active: bool = false
var p2_murderer_active: bool = false
var p2_attempted_murder_active: bool = false
## Durable countdown (seconds left). Survives free-roam / later rounds while TurnManager lives.
var _attempted_murder_timer: float = -1.0
var _fireman_death_timer: float = -1.0
## Post-eval NPC (fireman after pipe bomb). Policeman later.
var _fireman: Node2D = null
## Shared fate wheel popup (fireman, cop, …). Built once under the HUD layer.
var _spin_wheel: Control = null
var _eval_dialog: Control
var _eval_label: Label
var _eval_title: Label
## Stairs leave interaction (invisible zone + bobbing arrow + Yes/No dialog).
var _leave_zone: Area2D
var _leave_arrow: Node2D
var _leave_dialog: Control
var _leave_dialog_open: bool = false
var _in_leave_zone: bool = false
## After "No", suppress re-prompt until player exits and re-enters the zone.
var _leave_prompt_blocked: bool = false
var _arrow_bob_t: float = 0.0


func _ready():
	player1.set_active(true)
	player2.set_active(false)
	set_process_input(true)
	set_process_unhandled_input(true)
	set_process(true)
	_init_p2_archetype(Archetype.TECH_BRO)
	call_deferred("_build_hud")
	call_deferred("_ensure_debug_cheats")


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
	# Gentle vertical bob so the "exit here" cue is readable.
	var bob: float = sin(_arrow_bob_t * ARROW_BOB_SPEED) * ARROW_BOB_AMP
	_leave_arrow.position = STAIRS_ARROW_POS + Vector2(0.0, bob)


## Attempted Murder → Murderer at 15s; legless fireman dies at 120s. Always runs.
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
		# Cap reached: kill all prop shimmers; inventory still OK until leave.
		UsableShimmer.set_p2_world_uses_exhausted(true)
		call_deferred("enable_leave_exit")
	return true


## P2 may inspect/use a world prop only while uses remain (inventory is separate).
func can_p2_use_world_item() -> bool:
	if evaluation_active or _leave_dialog_open:
		return false
	if current_turn != "Player2":
		return false
	return p2_items_used < P2_USES_MAX


## Call from dresser when the pipe bomb actually explodes.
func mark_pipe_bomb_detonated() -> void:
	pipe_bomb_detonated = true


## Call from laptop when P2 uses a booby-trapped laptop (download trap).
func mark_illegal_download() -> void:
	illegal_download = true


## True while props / inventory should ignore the player (forced walk + popups).
func can_player_interact() -> bool:
	if evaluation_active or _leave_dialog_open:
		return false
	return current_turn == "Player1" or current_turn == "Player2"


## After 3 P2 item uses: show stairs arrow + leave zone. Player chooses when to leave.
func enable_leave_exit() -> void:
	if leave_available or evaluation_active:
		return
	leave_available = true
	# Ensure no leftover gold shimmer on unused props.
	UsableShimmer.set_p2_world_uses_exhausted(true)
	_ensure_leave_zone()
	if _leave_zone:
		_leave_zone.monitoring = true
		_leave_zone.visible = true
	if _leave_arrow:
		_leave_arrow.visible = true
		_arrow_bob_t = 0.0
		_leave_arrow.position = STAIRS_ARROW_POS
	set_status_message(MSG_LEAVE_READY)
	_update_hud()
	_update_held_items_visibility()
	# If already standing in the zone when the 3rd use completes, prompt now.
	call_deferred("_prompt_leave_if_overlapping")


func _prompt_leave_if_overlapping() -> void:
	if evaluation_active or not leave_available or _leave_zone == null:
		return
	for b in _leave_zone.get_overlapping_bodies():
		_on_leave_zone_body_entered(b)


## Ordered list of evaluation strings for this round (empty if nothing bad triggered).
## Add new outcomes here in the order they should appear.
func _build_eval_message_queue() -> Array:
	var queue: Array = []
	if pipe_bomb_detonated:
		queue.append(MSG_EVAL_FIRE_DEPT)
	if illegal_download:
		queue.append(MSG_EVAL_ILLEGAL_DOWNLOAD)
	return queue


## Player confirmed leave at stairs → lock control and run evaluations.
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

	# Keep P2 on screen but strip control / prop interactions.
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

	# Play every triggered outcome message, one at a time (typewriter + 2.5s hold each).
	var messages: Array = _build_eval_message_queue()
	for i in messages.size():
		await show_evaluation_popup(String(messages[i]))
		if i < messages.size() - 1:
			await get_tree().create_timer(EVAL_GAP_BETWEEN_MSGS_SEC).timeout

	# Messages done: free P2 to walk the room (props stay locked).
	_unlock_player_after_evaluation()

	# Pipe bomb → fire department arrives: fireman walks up from stairs, faces forward.
	if pipe_bomb_detonated:
		await _spawn_fireman_from_stairs()
		# Any arrival NPC: 2s later, fate wheel (same path cop will use later).
		await _on_npc_arrived_for_wheel("Fireman")

	end_of_round_evaluation_finished.emit()
	_update_held_items_visibility()


## Let P2 move freely after eval popups; world props stay non-interactive.
func _unlock_player_after_evaluation() -> void:
	var p2: Node = _get_player2_body()
	if p2 == null:
		return
	if p2.has_method("set_active"):
		p2.set_active(true)
	if p2.has_method("set_movement_locked"):
		p2.set_movement_locked(false)
	# Re-apply pill speed + HUD icons (must survive fireman arrival / eval lock).
	_reassert_p2_status()
	set_status_message("")
	_update_hud()
	_update_held_items_visibility()


## Keep ADHD / drowsy (and any other sticky effects) after end-of-round sequence.
func _reassert_p2_status() -> void:
	var p2: Node = _get_player2_body()
	if p2 and p2.has_method("reassert_status"):
		p2.call("reassert_status")
	elif p2:
		if p2_adhd_active and p2.has_method("apply_adhd_boost"):
			p2.call("apply_adhd_boost")
		elif p2_drowsy_active and p2.has_method("apply_drowsy_debuff"):
			p2.call("apply_drowsy_debuff")

	var pill_tex: Texture2D = null
	if ResourceLoader.exists("res://pill_bottle.png"):
		pill_tex = load("res://pill_bottle.png")
	if p2_adhd_active and not has_status_effect(EFFECT_ADHD):
		add_status_effect(EFFECT_ADHD, "buff", pill_tex, "ADHD")
	if p2_drowsy_active and not has_status_effect(EFFECT_DROWSY):
		add_status_effect(EFFECT_DROWSY, "debuff", pill_tex, "Drowsy")
	if p2_vishnu_active and not has_status_effect(EFFECT_VISHNU):
		add_status_effect(EFFECT_VISHNU, "debuff")
	if p2_murderer_active and not has_status_effect(EFFECT_MURDERER):
		add_status_effect(EFFECT_MURDERER, "debuff")
	if p2_attempted_murder_active and not has_status_effect(EFFECT_ATTEMPTED_MURDER):
		add_status_effect(EFFECT_ATTEMPTED_MURDER, "debuff")
	recompute_stats()


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
	# After fireman settles, re-assert again in case anything touched the player mid-walk.
	_reassert_p2_status()
	_update_hud()


## Call after any arrival NPC (fireman, cop, …) finishes entering.
## Waits NPC_ARRIVAL_WHEEL_DELAY_SEC then runs the spin wheel popup.
func _on_npc_arrived_for_wheel(npc_name: String = "NPC") -> void:
	await get_tree().create_timer(NPC_ARRIVAL_WHEEL_DELAY_SEC).timeout
	# Lock movement while the wheel is up so the player watches.
	var p2: Node = _get_player2_body()
	if p2 and p2.has_method("set_movement_locked"):
		p2.set_movement_locked(true)
	var title: String = "%s — FATE WHEEL" % npc_name.to_upper()
	var result: Dictionary = await show_spin_wheel(title)
	print(
		"Fate wheel for ", npc_name,
		" landed: ", result.get("label", "?"),
		" id=", result.get("id", ""),
		" weights=", result.get("weights", {})
	)
	# Fireman wheel → stat checks + narrative (stats already include buff/debuff mods).
	if npc_name.to_lower().contains("fire"):
		await resolve_fireman_wheel_outcome(result)
	if p2 and p2.has_method("set_movement_locked"):
		p2.set_movement_locked(false)
	_reassert_p2_status()
	recompute_stats()


func _ensure_spin_wheel() -> void:
	if _spin_wheel != null and is_instance_valid(_spin_wheel):
		return
	if _hud_layer == null:
		return
	var wheel: Control = SpinWheelPopup.new()
	wheel.name = "SpinWheelPopup"
	_hud_layer.add_child(wheel)
	_spin_wheel = wheel


## Snapshot of active buffs/debuffs for the fate wheel (textures + ids).
func get_effects_for_wheel() -> Array:
	var out: Array = []
	for id in _effects.keys():
		var entry: Dictionary = _effects[id]
		var slot: Control = entry.get("slot") as Control
		if slot == null or not is_instance_valid(slot):
			continue
		out.append({
			"id": String(id),
			"kind": String(entry.get("kind", "buff")),
			"texture": entry.get("texture") as Texture2D,
			"label": String(entry.get("label", id)),
		})
	return out


## Show fate wheel with current effects applied before the spin.
## Returns {index, id, label, weights}.
func show_spin_wheel(title: String = "FATE WHEEL") -> Dictionary:
	_ensure_spin_wheel()
	if _spin_wheel == null:
		return {"index": 0, "id": "", "label": "", "weights": {}}
	var effects: Array = get_effects_for_wheel()
	if _spin_wheel.has_method("show_and_spin"):
		return await _spin_wheel.show_and_spin(title, effects)
	return {"index": 0, "id": "", "label": "", "weights": {}}


## --- Stat API (base archetype + status mods + permanent deltas) ---

func _init_p2_archetype(arch: int) -> void:
	p2_archetype = arch
	var b: Dictionary = ARCHETYPE_BASE.get(arch, ARCHETYPE_BASE[Archetype.TECH_BRO])
	base_agility = int(b.get("agility", 25))
	base_charisma = int(b.get("charisma", 25))
	base_intelligence = int(b.get("intelligence", 75))
	delta_agility = 0
	delta_charisma = 0
	delta_intelligence = 0
	recompute_stats()


## Status-driven modifiers while the effect is active on P2.
## ADHD (pill buff, after consume): INT+20 CHA+15
## Drowsy (pill debuff, after consume): INT-50 CHA-10 AGI-20
## Vishnu demon: CHA+15
## Murderer (gun kill): INT-15 CHA+25
func _status_stat_mods() -> Dictionary:
	var agi := 0
	var cha := 0
	var intel := 0
	if p2_adhd_active:
		intel += 20
		cha += 15
	if p2_drowsy_active:
		intel -= 50
		cha -= 10
		agi -= 20
	if p2_vishnu_active:
		cha += 15
	if p2_attempted_murder_active:
		# Still in denial / adrenaline — milder hit than full Murderer.
		intel -= 5
		cha -= 10
		agi -= 5
	if p2_murderer_active:
		intel -= 15
		cha += 25
	return {"agility": agi, "charisma": cha, "intelligence": intel}


## Recompute effective stats and refresh HUD bars.
func recompute_stats() -> void:
	var m: Dictionary = _status_stat_mods()
	agility = clampi(base_agility + delta_agility + int(m["agility"]), 0, STAT_MAX)
	charisma = clampi(base_charisma + delta_charisma + int(m["charisma"]), 0, STAT_MAX)
	intelligence = clampi(base_intelligence + delta_intelligence + int(m["intelligence"]), 0, STAT_MAX)
	_refresh_stat_bar("Agility", agility)
	_refresh_stat_bar("Charisma", charisma)
	_refresh_stat_bar("Intelligence", intelligence)


func set_agility(value: int) -> void:
	# Direct set adjusts permanent delta so effective matches request as closely as possible.
	var m: Dictionary = _status_stat_mods()
	delta_agility = value - base_agility - int(m["agility"])
	recompute_stats()


func set_charisma(value: int) -> void:
	var m: Dictionary = _status_stat_mods()
	delta_charisma = value - base_charisma - int(m["charisma"])
	recompute_stats()


func set_intelligence(value: int) -> void:
	var m: Dictionary = _status_stat_mods()
	delta_intelligence = value - base_intelligence - int(m["intelligence"])
	recompute_stats()


func set_stats(agi: int, cha: int, intel: int) -> void:
	set_agility(agi)
	set_charisma(cha)
	set_intelligence(intel)


func adjust_charisma(amount: int) -> void:
	delta_charisma += amount
	recompute_stats()


func adjust_agility(amount: int) -> void:
	delta_agility += amount
	recompute_stats()


func adjust_intelligence(amount: int) -> void:
	delta_intelligence += amount
	recompute_stats()


## After fireman fate wheel lands: stat check + message + CHA delta.
## On failed seduce / attack / schmooze, if P2 has a gun → offer to shoot.
func resolve_fireman_wheel_outcome(result: Dictionary) -> void:
	var id: String = String(result.get("id", ""))
	var msg := ""
	var failed_social := false
	# Recompute so checks use current buff/debuff-modified stats.
	recompute_stats()
	match id:
		"seduce":
			if charisma < STAT_CHECK_THRESHOLD:
				msg = "You tried to seduced the Fireman. It failed, and he whooped your ass."
				adjust_charisma(-10)
				failed_social = true
			else:
				msg = "You have seduced the Fireman, heretofore a heterosexual man. He leaves highly confused and limping."
				adjust_charisma(10)
		"attack":
			if agility < STAT_CHECK_THRESHOLD:
				msg = "You tried to attack the Fireman. He whooped your ass, and posted a video of it to social media."
				adjust_charisma(-10)
				failed_social = true
			else:
				msg = "You attacked the Fireman. He leaves, too embarrassed to tell anyone about this encounter."
				adjust_charisma(15)
		"schmooze":
			# Success only if strictly over 50 (as specified).
			if charisma > STAT_CHECK_THRESHOLD:
				msg = "You have schmoozed the Fireman. He leaves without causing a scene."
			else:
				msg = "You tried to schmooze the Fireman. It did not work, and he called you dusty before taking a dump on your floor."
				adjust_charisma(-10)
				failed_social = true
		"possess":
			msg = "The demon rips free of you and seizes the Fireman. He rises as a shambling thrall."
			_possess_fireman()
		_:
			msg = "The fate wheel settles. Nothing further happens."
	if not msg.is_empty():
		await show_evaluation_popup(msg)
	set_status_message(msg)
	recompute_stats()

	# Failed social check + gun in bag → second choice.
	if failed_social and has_inventory_item(ITEM_GUN):
		var use_gun: bool = await show_gun_lesson_dialog()
		if use_gun:
			await _execute_gun_kill_fireman()


func has_inventory_item(item_id: String) -> bool:
	for e in _inv:
		if String(e.get("id", "")) == item_id:
			return true
	return false


## Remove first matching held item from bag UI + data.
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


## Swap fireman to zombie sheet and have him follow P2 at half speed.
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


## Shoot fireman. Clean shot → headless + Murderer. On fent → leg shot + crawl + Attempted Murder.
func _execute_gun_kill_fireman() -> void:
	remove_inventory_item(ITEM_GUN)
	if p2_drowsy_active:
		await _execute_gun_fent_leg_shot()
	else:
		await _execute_gun_clean_headshot()


func _execute_gun_clean_headshot() -> void:
	if _fireman and is_instance_valid(_fireman) and _fireman.has_method("become_headless_corpse"):
		_fireman.call("become_headless_corpse")
	# Cancel any pending attempted-murder path.
	_attempted_murder_timer = -1.0
	_fireman_death_timer = -1.0
	p2_attempted_murder_active = false
	if has_status_effect(EFFECT_ATTEMPTED_MURDER):
		remove_status_effect(EFFECT_ATTEMPTED_MURDER)
	p2_murderer_active = true
	var skull: Texture2D = _load_texture_any("res://murderer_skull_icon.png")
	add_status_effect(EFFECT_MURDERER, "debuff", skull, "Murderer")
	await show_evaluation_popup(MSG_GUN_SHOT)
	set_status_message(MSG_GUN_SHOT)
	recompute_stats()


func _execute_gun_fent_leg_shot() -> void:
	if _fireman and is_instance_valid(_fireman) and _fireman.has_method("become_legless_crawl"):
		_fireman.call("become_legless_crawl")
	# Attempted Murder now; real Murderer after 15s (even if you leave the room / later rounds).
	p2_murderer_active = false
	if has_status_effect(EFFECT_MURDERER):
		remove_status_effect(EFFECT_MURDERER)
	p2_attempted_murder_active = true
	var fist: Texture2D = _load_texture_any("res://attempted_murder_fist_icon.png")
	add_status_effect(EFFECT_ATTEMPTED_MURDER, "debuff", fist, "Attempted Murder")
	_attempted_murder_timer = ATTEMPTED_MURDER_UPGRADE_SEC
	_fireman_death_timer = FIREMAN_CRAWL_DEATH_SEC
	await show_evaluation_popup(MSG_GUN_FENT_LEG)
	set_status_message(MSG_GUN_FENT_LEG)
	recompute_stats()


func _upgrade_attempted_murder_to_murderer() -> void:
	if not p2_attempted_murder_active and not has_status_effect(EFFECT_ATTEMPTED_MURDER):
		return
	p2_attempted_murder_active = false
	if has_status_effect(EFFECT_ATTEMPTED_MURDER):
		remove_status_effect(EFFECT_ATTEMPTED_MURDER)
	p2_murderer_active = true
	var skull: Texture2D = _load_texture_any("res://murderer_skull_icon.png")
	add_status_effect(EFFECT_MURDERER, "debuff", skull, "Murderer")
	set_status_message("The Fireman isn't getting up. You're a Murderer now.")
	recompute_stats()
	print("[MURDER] Attempted Murder → Murderer after 15s")


func _finish_fireman_crawl_death() -> void:
	if _fireman == null or not is_instance_valid(_fireman):
		return
	if _fireman.has_method("is_dead") and _fireman.call("is_dead"):
		return
	if _fireman.has_method("die_in_place"):
		_fireman.call("die_in_place")
	elif _fireman.has_method("become_headless_corpse"):
		_fireman.call("become_headless_corpse")
	# Ensure murderer status if upgrade somehow missed.
	if p2_attempted_murder_active or has_status_effect(EFFECT_ATTEMPTED_MURDER):
		_upgrade_attempted_murder_to_murderer()
	print("[MURDER] Fireman crawl death at 2 minutes")


## ========== DEBUG CHEATS (called from debug_cheats.gd) ==========
## Add new jumps here, then register the method name in debug_cheats._register_cheats().

func cheat_toast(text: String) -> void:
	set_status_message(text)


func cheat_help() -> void:
	set_status_message("Cheats: F5 P2 roam | F6 fireman | F7 possess | F8 wheel→possess | F9 demon+ADHD | F10 reset stats | F1 list")


## P2 controllable in end-of-round state (props locked, free walk).
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
	recompute_stats()
	_update_hud()
	_update_held_items_visibility()
	set_status_message("CHEAT: P2 free roam (end-of-round)")


## Ensure a fireman exists at the stand pose (normal sheet).
func cheat_spawn_fireman() -> void:
	cheat_p2_eval_roam()
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
		# Fallback: full walk-in
		fm.call("arrive_from_stairs")
	set_status_message("CHEAT: Fireman spawned")


## Jump straight to possessed zombie fireman following P2 (skips wheel UI).
func cheat_possess_fireman() -> void:
	cheat_spawn_fireman()
	# Demon flag so other systems know possess path was used.
	p2_vishnu_active = true
	if not has_status_effect(EFFECT_VISHNU):
		add_status_effect(EFFECT_VISHNU, "debuff")
	_possess_fireman()
	set_status_message("CHEAT: Fireman possessed — zombie follows you")
	print("[CHEAT] possess fireman — walk around to test follow")


## Runs the real outcome resolver as if the wheel landed on Possess (message + zombie).
func cheat_wheel_land_possess() -> void:
	cheat_spawn_fireman()
	p2_vishnu_active = true
	if not has_status_effect(EFFECT_VISHNU):
		add_status_effect(EFFECT_VISHNU, "debuff")
	# Call real resolve path so narrative + possess stay in sync with production.
	resolve_fireman_wheel_outcome({
		"index": 3,
		"id": "possess",
		"label": "Possess Fireman",
		"weights": {},
	})


func cheat_give_demon_and_adhd() -> void:
	p2_adhd_active = true
	p2_drowsy_active = false
	p2_vishnu_active = true
	var pill_tex: Texture2D = null
	if ResourceLoader.exists("res://pill_bottle.png"):
		pill_tex = load("res://pill_bottle.png")
	add_status_effect(EFFECT_ADHD, "buff", pill_tex, "ADHD")
	add_status_effect(EFFECT_VISHNU, "debuff")
	_apply_p2_speed_boost()
	recompute_stats()
	set_status_message("CHEAT: ADHD + Demon applied")


func cheat_reset_tech_stats() -> void:
	_init_p2_archetype(Archetype.TECH_BRO)
	set_status_message("CHEAT: Tech bro stats reset (25/25/75)")


## Spawn fireman, give gun, force failed attack outcome (triggers gun prompt if gun held).
func cheat_gun_fail_then_offer() -> void:
	cheat_spawn_fireman()
	if not has_inventory_item(ITEM_GUN):
		add_inventory_gun()
	# Ensure fail: keep AGI low
	delta_agility = -100
	recompute_stats()
	resolve_fireman_wheel_outcome({
		"index": 0,
		"id": "attack",
		"label": "Attack Fireman",
		"weights": {},
	})


## Fent + gun leg shot path (crawl + Attempted Murder timer).
func cheat_gun_fent_leg() -> void:
	cheat_spawn_fireman()
	p2_drowsy_active = true
	p2_adhd_active = false
	var pill_tex: Texture2D = _load_texture_any("res://pill_bottle.png")
	add_status_effect(EFFECT_DROWSY, "debuff", pill_tex, "Drowsy")
	if not has_inventory_item(ITEM_GUN):
		add_inventory_gun()
	_execute_gun_kill_fireman()


## --- Buff / Debuff status icons (sidebar under attributes) ---

const TEX_PILL_BOTTLE := "res://pill_bottle.png"
const TEX_VISHNU_DEMON := "res://vishnu_demon_possess.png"

## kind: "buff" or "debuff". Replaces any existing effect with the same id.
## If texture is null, known ids (vishnu_demon, adhd_boost, drowsy) load their artwork automatically.
func add_status_effect(id: String, kind: String, texture: Texture2D = null, display_name: String = "") -> void:
	if id.is_empty():
		return
	if texture == null:
		texture = _default_effect_texture(id)
	if display_name.is_empty():
		display_name = _default_effect_name(id)
	remove_status_effect(id)
	var is_buff := kind.to_lower() != "debuff"
	var row: HBoxContainer = _buffs_row if is_buff else _debuffs_row
	if row == null:
		# Still track gameplay flags if HUD not ready yet.
		_mark_status_flag(id, true)
		recompute_stats()
		return
	var slot := _make_effect_slot(id, is_buff, texture, display_name)
	row.add_child(slot)
	_effects[id] = {
		"kind": "buff" if is_buff else "debuff",
		"texture": texture,
		"label": display_name,
		"slot": slot,
	}
	_mark_status_flag(id, true)
	_refresh_effect_empty_labels()
	recompute_stats()


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
	_refresh_effect_empty_labels()


func _default_effect_texture(id: String) -> Texture2D:
	var paths: Array = []
	match id:
		EFFECT_VISHNU, "vishnu", "vishnu_demon":
			paths = [TEX_VISHNU_DEMON, "res://meditation_demon.png"]
		EFFECT_ADHD, EFFECT_DROWSY, ITEM_PILLS, "pill":
			paths = [TEX_PILL_BOTTLE]
		EFFECT_MURDERER, "murderer":
			paths = ["res://murderer_skull_icon.png"]
		EFFECT_ATTEMPTED_MURDER, "attempted_murder":
			paths = ["res://attempted_murder_fist_icon.png"]
		_:
			return null
	for path in paths:
		if path is String and not String(path).is_empty():
			var tex := _load_texture_any(String(path))
			if tex:
				return tex
	return null


## Load texture via ResourceLoader or raw Image (works before .import exists).
func _load_texture_any(path: String) -> Texture2D:
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


func _default_effect_name(id: String) -> String:
	match id:
		EFFECT_VISHNU, "vishnu", "vishnu_demon":
			return "Vishnu"
		EFFECT_ADHD:
			return "ADHD"
		EFFECT_DROWSY:
			return "Drowsy"
		EFFECT_MURDERER, "murderer":
			return "Murderer"
		EFFECT_ATTEMPTED_MURDER, "attempted_murder":
			return "Attempted Murder"
		_:
			return id


## Hover text for status icons. Stat lines match _status_stat_mods().
func get_effect_tooltip(id: String) -> String:
	match id:
		EFFECT_ADHD, "adhd", "pill":
			return (
				"You are zooted on ADHD Meds. You are more intelligent, but also a little too online.\n"
				+ "Intelligence +20\n"
				+ "Charisma +15\n"
				+ "Also: walk speed goes brrr."
			)
		EFFECT_DROWSY, "drowsy", "fent":
			return (
				"You are on fent. Everything is soft and bad decisions feel free.\n"
				+ "Intelligence -50\n"
				+ "Charisma -10\n"
				+ "Agility -20\n"
				+ "Also: you move like wet laundry. Aim optional."
			)
		EFFECT_VISHNU, "vishnu", "vishnu_demon":
			return (
				"You are possessed by a 4th dimensional demon. Your behavior is unpredictable.\n"
				+ "Charisma +15\n"
				+ "Also: may unlock Possess on the fate wheel. The demon has opinions."
			)
		EFFECT_ATTEMPTED_MURDER, "attempted_murder":
			return (
				"Attempted Murder. You shot a guy's leg off while extremely not sober.\n"
				+ "He's still crawling. That's not better.\n"
				+ "Intelligence -5\n"
				+ "Charisma -10\n"
				+ "Agility -5\n"
				+ "In 15 seconds this upgrades to Murderer whether you watch or not."
			)
		EFFECT_MURDERER, "murderer":
			return (
				"Murderer. You taught someone a lesson with a gun. HR would like a word.\n"
				+ "Intelligence -15\n"
				+ "Charisma +25\n"
				+ "People are either terrified or weirdly impressed. Maybe both."
			)
		_:
			return _default_effect_name(id)


## Hover text for held inventory items.
func get_inventory_tooltip(item_id: String, extra: Dictionary = {}) -> String:
	match item_id:
		ITEM_GUN, "gun":
			return (
				"Handgun. Found in a plant, which is already a red flag.\n"
				+ "If you botch schmooze / seduce / attack with the Fireman, "
				+ "you may get one chance to 'teach him a lesson.'\n"
				+ "Spoilers: lessons are loud and permanent."
			)
		ITEM_PILLS, "pill", "pills":
			if bool(extra.get("trapped", false)):
				return (
					"Pill bottle (looks normal). Your roommate's 'vitamins.'\n"
					+ "Take them and you might get Drowsy: Intelligence -50, Charisma -10, Agility -20.\n"
					+ "Click to consider a life choice."
				)
			return (
				"Pill bottle. Premium focus juice (allegedly).\n"
				+ "Take them for ADHD: Intelligence +20, Charisma +15, and go-fast legs.\n"
				+ "Click to Take / Cancel."
			)
		_:
			return item_id


func remove_status_effect(id: String) -> void:
	if _effects.has(id):
		var entry: Dictionary = _effects[id]
		var slot: Control = entry.get("slot") as Control
		if slot and is_instance_valid(slot):
			slot.queue_free()
		_effects.erase(id)
	_mark_status_flag(id, false)
	_refresh_effect_empty_labels()
	recompute_stats()


func clear_status_effects() -> void:
	for id in _effects.keys().duplicate():
		remove_status_effect(String(id))


func has_status_effect(id: String) -> bool:
	if not _effects.has(id):
		return false
	# Drop stale entries if the HUD slot was freed somehow.
	var slot: Control = _effects[id].get("slot") as Control
	if slot == null or not is_instance_valid(slot):
		_effects.erase(id)
		return false
	return true


## Replace sidebar dialog text (wraps; scrolls if longer than the box).
func set_status_message(text: String) -> void:
	_status_message = text
	if _status_label == null:
		return
	_status_label.text = text
	# Jump to top when message changes so new text is visible first.
	if _status_scroll:
		_status_scroll.scroll_vertical = 0


func get_status_message() -> String:
	return _status_message


func add_inventory_pill(trapped: bool) -> void:
	if _inv_grid == null:
		call_deferred("add_inventory_pill", trapped)
		return
	var tex: Texture2D = load("res://pill_bottle.png")
	_add_inventory_slot(ITEM_PILLS, tex, {"trapped": trapped})


func add_inventory_gun() -> void:
	if _inv_grid == null:
		call_deferred("add_inventory_gun")
		return
	# Only one gun in bag
	for e in _inv:
		if String(e.get("id", "")) == ITEM_GUN:
			return
	var tex: Texture2D = load("res://handgun.png")
	_add_inventory_slot(ITEM_GUN, tex, {})


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
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.focus_mode = Control.FOCUS_NONE
	if tex:
		icon.texture = tex
	slot.add_child(icon)

	var entry := {"id": id, "slot": slot}
	for k in extra:
		entry[k] = extra[k]
	slot.tooltip_text = get_inventory_tooltip(id, extra)
	_inv.append(entry)
	_inv_grid.add_child(slot)
	_update_held_items_visibility()


## Global mouse hit-test for held-item slots (does not rely on Button signals).
func _input(event: InputEvent) -> void:
	# Inventory stays usable in end-of-round free roam. Only block over modal dialogs.
	if _pills_dialog_open or _gun_give_dialog_open or _leave_dialog_open or _gun_lesson_dialog_open:
		return
	if _inv.is_empty():
		return
	# Allow during Evaluation (P2 still active) and normal Player2 turn.
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
	if id == ITEM_GUN:
		_pending_inv_entry = entry
		show_gun_give_dialog()
		return
	# Unknown items: no-op for now


func _consume_inv_entry(entry: Dictionary) -> void:
	if not _inv.has(entry):
		var matched: Dictionary = {}
		var ok := false
		for e in _inv:
			if e.get("slot") == entry.get("slot"):
				matched = e
				ok = true
				break
		if not ok:
			return
		entry = matched
	_inv.erase(entry)
	var slot: Control = entry.get("slot") as Control
	if slot and is_instance_valid(slot):
		slot.queue_free()

	# Clean → ADHD boost. Booby-trapped → permanent drowsy (half speed + stooped sheet).
	var was_trapped: bool = bool(entry.get("trapped", false))
	var pill_tex: Texture2D = null
	if ResourceLoader.exists("res://pill_bottle.png"):
		pill_tex = load("res://pill_bottle.png")
	if was_trapped:
		p2_drowsy_active = true
		p2_adhd_active = false
		_apply_p2_drowsy_debuff()
		add_status_effect(EFFECT_DROWSY, "debuff", pill_tex, "Drowsy")
		set_status_message(MSG_FENT_PILLS)
	else:
		p2_adhd_active = true
		p2_drowsy_active = false
		_apply_p2_speed_boost()
		add_status_effect(EFFECT_ADHD, "buff", pill_tex, "ADHD")
	recompute_stats()
	_update_held_items_visibility()


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
	print("ADHD boost applied to ", p2, " speed=", p2.get("speed"), " mult=", p2.get("speed_mult"))


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
	print("Drowsy debuff applied to ", p2, " speed=", p2.get("speed"), " mult=", p2.get("speed_mult"))


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
	# PASS so nested icon tooltips can receive hover.
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	_hud_layer.add_child(margin)

	# Single column under the trap counter — stats + buffs/debuffs share this HUD root.
	_sidebar = VBoxContainer.new()
	_sidebar.name = "SidebarColumn"
	_sidebar.add_theme_constant_override("separation", 6)
	_sidebar.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(_sidebar)

	_build_trap_counter_panel()
	_build_stats_panel()
	_build_effects_panel()
	_build_held_items_panel()
	# Last in column: sits under trap counter for P1 (other panels hidden),
	# under full P2 HUD when stats/effects/use are visible.
	_build_status_dialog_panel()
	_build_pills_dialog()
	_build_gun_give_dialog()
	_build_download_dialog()
	_build_evaluation_dialog()
	_build_leave_apartment_dialog()
	_build_gun_lesson_dialog()
	_ensure_leave_zone()
	# Tech bro base stats (or whatever archetype was set) into the bars.
	recompute_stats()
	_update_hud()
	_update_held_items_visibility()
	# Start on P1 — empty until text is set. P2 default applied on turn switch.
	set_status_message("")


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


func _build_stats_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "StatsPanel"
	panel.add_theme_stylebox_override("panel", _gold_panel_style(10))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sidebar.add_child(panel)
	_stats_panel = panel

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)

	for entry in [
		["Agility", agility],
		["Charisma", charisma],
		["Intelligence", intelligence],
	]:
		col.add_child(_make_stat_row(String(entry[0]), int(entry[1])))


func _make_stat_row(stat_name: String, value: int) -> Control:
	var row := VBoxContainer.new()
	row.name = "%sRow" % stat_name
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(header)

	var name_label := Label.new()
	_apply_hud_label(name_label)
	name_label.text = stat_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(name_label)

	var value_label := Label.new()
	_apply_hud_label(value_label)
	value_label.text = str(value)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(value_label)

	# Manual track + fill ColorRects (pixel-clear fill width; no ProgressBar theme quirks).
	const BAR_W := 148.0
	const BAR_H := 12.0
	var track := Control.new()
	track.name = "BarTrack"
	track.custom_minimum_size = Vector2(BAR_W, BAR_H)
	track.clip_contents = true
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(track)

	var border := ColorRect.new()
	border.color = HUD_BORDER.darkened(0.35)
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(border)

	var bg := ColorRect.new()
	bg.color = BAR_EMPTY
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.offset_left = 1
	bg.offset_top = 1
	bg.offset_right = -1
	bg.offset_bottom = -1
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(bg)

	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.color = BAR_FILL
	fill.position = Vector2(1, 1)
	fill.size = Vector2(0, BAR_H - 2)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)

	_stat_bars[stat_name] = {
		"fill": fill,
		"value_label": value_label,
		"bar_w": BAR_W - 2.0,
		"bar_h": BAR_H - 2.0,
	}
	_refresh_stat_bar(stat_name, value)
	return row


func _refresh_stat_bar(stat_name: String, value: int) -> void:
	if not _stat_bars.has(stat_name):
		return
	var entry: Dictionary = _stat_bars[stat_name]
	var v := clampi(value, 0, STAT_MAX)
	var ratio := float(v) / float(STAT_MAX)
	var fill: ColorRect = entry["fill"]
	var bar_w: float = entry["bar_w"]
	var bar_h: float = entry["bar_h"]
	fill.size = Vector2(bar_w * ratio, bar_h)
	var value_label: Label = entry["value_label"]
	value_label.text = str(v)


func _build_effects_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "EffectsPanel"
	panel.add_theme_stylebox_override("panel", _gold_panel_style(8))
	# PASS so children (buff/debuff icons) can receive hover for tooltips.
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_sidebar.add_child(panel)
	_effects_panel = panel

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(col)

	var title := Label.new()
	_apply_hud_label(title)
	title.text = "Buffs & Debuffs"
	title.add_theme_font_size_override("font_size", 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)

	# Buffs row
	var buff_label := Label.new()
	_apply_hud_label(buff_label)
	buff_label.text = "Buffs"
	buff_label.add_theme_font_size_override("font_size", 8)
	buff_label.add_theme_color_override("font_color", BUFF_BORDER)
	buff_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(buff_label)

	_buffs_row = HBoxContainer.new()
	_buffs_row.name = "BuffsRow"
	_buffs_row.add_theme_constant_override("separation", 4)
	_buffs_row.custom_minimum_size = Vector2(148, EFFECT_SLOT_PX)
	_buffs_row.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(_buffs_row)

	_buffs_empty = Label.new()
	_apply_hud_label(_buffs_empty)
	_buffs_empty.name = "BuffsEmpty"
	_buffs_empty.text = "—"
	_buffs_empty.add_theme_font_size_override("font_size", 8)
	_buffs_empty.add_theme_color_override("font_color", Color(0.55, 0.50, 0.40, 0.85))
	_buffs_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buffs_row.add_child(_buffs_empty)

	# Debuffs row
	var debuff_label := Label.new()
	_apply_hud_label(debuff_label)
	debuff_label.text = "Debuffs"
	debuff_label.add_theme_font_size_override("font_size", 8)
	debuff_label.add_theme_color_override("font_color", DEBUFF_BORDER)
	debuff_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(debuff_label)

	_debuffs_row = HBoxContainer.new()
	_debuffs_row.name = "DebuffsRow"
	_debuffs_row.add_theme_constant_override("separation", 4)
	_debuffs_row.custom_minimum_size = Vector2(148, EFFECT_SLOT_PX)
	_debuffs_row.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(_debuffs_row)

	_debuffs_empty = Label.new()
	_apply_hud_label(_debuffs_empty)
	_debuffs_empty.name = "DebuffsEmpty"
	_debuffs_empty.text = "—"
	_debuffs_empty.add_theme_font_size_override("font_size", 8)
	_debuffs_empty.add_theme_color_override("font_color", Color(0.55, 0.50, 0.40, 0.85))
	_debuffs_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debuffs_row.add_child(_debuffs_empty)


func _make_effect_slot(id: String, is_buff: bool, texture: Texture2D, display_name: String) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.name = "Effect_%s" % id
	slot.custom_minimum_size = Vector2(EFFECT_SLOT_PX, EFFECT_SLOT_PX)
	slot.tooltip_text = get_effect_tooltip(id)
	var style := StyleBoxFlat.new()
	style.bg_color = EFFECT_SLOT_BG
	style.border_color = BUFF_BORDER if is_buff else DEBUFF_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(2)
	slot.add_theme_stylebox_override("panel", style)
	# STOP so Godot shows tooltip_text on hover.
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.mouse_default_cursor_shape = Control.CURSOR_HELP

	if texture != null:
		var icon := TextureRect.new()
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(EFFECT_SLOT_PX - 6, EFFECT_SLOT_PX - 6)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
	else:
		var fallback := Label.new()
		_apply_hud_label(fallback)
		fallback.text = display_name.left(2).to_upper() if not display_name.is_empty() else "?"
		fallback.add_theme_font_size_override("font_size", 8)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(fallback)
	return slot


func _refresh_effect_empty_labels() -> void:
	var has_buff := false
	var has_debuff := false
	for id in _effects:
		var kind: String = String(_effects[id].get("kind", ""))
		if kind == "buff":
			has_buff = true
		else:
			has_debuff = true
	if _buffs_empty and is_instance_valid(_buffs_empty):
		_buffs_empty.visible = not has_buff
	if _debuffs_empty and is_instance_valid(_debuffs_empty):
		_debuffs_empty.visible = not has_debuff


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
	# Fixed width so wrap works inside ScrollContainer.
	_status_label.custom_minimum_size = Vector2(STATUS_DIALOG_W - 28.0, 0)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_scroll.add_child(_status_label)


## Held consumables only appear while the player is carrying something.
## Not a permanent inventory grid — bag UI for use-before-effect.
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


## --- Pills confirm dialog ---

func _build_pills_dialog() -> void:
	var root := Control.new()
	root.name = "PillsDialog"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	_hud_layer.add_child(root)
	_pills_dialog = root

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.02, 0.05, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_pills_dim_gui_input)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	# Outer purple frame + inner gold panel
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
	col.custom_minimum_size = Vector2(220, 0)
	panel.add_child(col)

	var title := Label.new()
	_apply_hud_label(title)
	title.name = "Title"
	title.text = "Pills"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var icon_row := CenterContainer.new()
	col.add_child(icon_row)
	if ResourceLoader.exists("res://pill_bottle.png"):
		var icon := TextureRect.new()
		icon.texture = load("res://pill_bottle.png")
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
		give_btn.visible = _is_pet_lizard_alive()
	var take_btn := _pills_dialog.find_child("TakeButton", true, false) as Button
	if take_btn:
		take_btn.grab_focus()


func _is_pet_lizard_alive() -> bool:
	var roomate := get_node_or_null("/root/Main/Roomate")
	if roomate == null:
		return false
	if roomate.has_method("is_alive"):
		return bool(roomate.call("is_alive"))
	return is_instance_valid(roomate)


## --- Gun give dialog (inventory click) ---

func _build_gun_give_dialog() -> void:
	var root := Control.new()
	root.name = "GunGiveDialog"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	_hud_layer.add_child(root)
	_gun_give_dialog = root

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.02, 0.05, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_gun_give_dim_gui_input)
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
	col.custom_minimum_size = Vector2(220, 0)
	panel.add_child(col)

	var title := Label.new()
	_apply_hud_label(title)
	title.name = "Title"
	title.text = "Gun"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var icon_row := CenterContainer.new()
	col.add_child(icon_row)
	if ResourceLoader.exists("res://handgun.png"):
		var icon := TextureRect.new()
		icon.texture = load("res://handgun.png")
		icon.custom_minimum_size = Vector2(48, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_row.add_child(icon)

	var prompt := Label.new()
	_apply_hud_label(prompt)
	prompt.name = "Prompt"
	prompt.text = "What do you want to do?"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
		give_btn.visible = _is_pet_lizard_alive()
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
	var entry: Dictionary = _pending_inv_entry
	_pending_inv_entry = {}
	hide_gun_give_dialog()
	if entry.is_empty():
		return
	if not _is_pet_lizard_alive():
		return
	# Remove gun from inventory.
	if not _inv.has(entry):
		var matched: Dictionary = {}
		var ok := false
		for e in _inv:
			if e.get("slot") == entry.get("slot"):
				matched = e
				ok = true
				break
		if not ok:
			return
		entry = matched
	_inv.erase(entry)
	var slot: Control = entry.get("slot") as Control
	if slot and is_instance_valid(slot):
		slot.queue_free()
	_update_held_items_visibility()

	var roomate := get_node_or_null("/root/Main/Roomate")
	if roomate and roomate.has_method("give_gun"):
		roomate.call("give_gun")
	set_status_message("The pet lizard took the gun — careful where it points that tail.")


func _on_gun_give_cancel_pressed() -> void:
	_pending_inv_entry = {}
	hide_gun_give_dialog()


func _on_gun_give_dim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_gun_give_cancel_pressed()


## Centered popup: "DOWNLOADING HIGHLY / ILLEGAL MATERIAL" + animating ellipsis. 2.5s default.
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
	# ~50% larger margins/fonts than original
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
	const DL_FONT := 16  # ~50% over prior 11

	var line1 := Label.new()
	line1.name = "Line1"
	line1.text = "DOWNLOADING HIGHLY"
	line1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _pixel_font != null:
		line1.add_theme_font_override("font", _pixel_font)
	line1.add_theme_font_size_override("font_size", DL_FONT)
	line1.add_theme_color_override("font_color", white)
	col.add_child(line1)

	# Fixed "ILLEGAL MATERIAL" + separate dots so only ellipsis moves.
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
	# Reserve width for "..." so base text never shifts.
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
	zone.collision_mask = 1 # player bodies
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

	# Down-arrow cue above the stairs (no floor shimmer).
	_leave_arrow = _make_stairs_arrow()
	_leave_arrow.visible = false
	_leave_arrow.position = STAIRS_ARROW_POS
	scene.add_child(_leave_arrow)

	zone.body_entered.connect(_on_leave_zone_body_entered)
	zone.body_exited.connect(_on_leave_zone_body_exited)


## Pixel-ish gold arrow pointing down at the stairs.
func _make_stairs_arrow() -> Node2D:
	var root := Node2D.new()
	root.name = "StairsLeaveArrow"
	root.z_index = 20

	# Soft dark outline (slightly larger, behind).
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
	if evaluation_active or not leave_available:
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
	var root := Control.new()
	root.name = "LeaveApartmentDialog"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	_hud_layer.add_child(root)
	_leave_dialog = root

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
	outer_style.set_border_width_all(3)
	outer_style.set_corner_radius_all(8)
	outer_style.set_content_margin_all(6)
	outer.add_theme_stylebox_override("panel", outer_style)
	center.add_child(outer)

	var panel := PanelContainer.new()
	panel.name = "DialogPanel"
	var panel_style := _gold_panel_style(18)
	panel_style.bg_color = Color(0.12, 0.08, 0.10, 0.96)
	panel.add_theme_stylebox_override("panel", panel_style)
	outer.add_child(panel)

	var col := VBoxContainer.new()
	col.name = "Content"
	col.add_theme_constant_override("separation", 16)
	col.custom_minimum_size = Vector2(320, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)

	var title := Label.new()
	title.name = "Title"
	title.text = MSG_LEAVE_PROMPT
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _pixel_font != null:
		title.add_theme_font_override("font", _pixel_font)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", HUD_TEXT)
	col.add_child(title)

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
	if _leave_dialog == null or evaluation_active or not leave_available:
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
	begin_end_of_round_evaluation()


func _on_leave_no_pressed() -> void:
	# Dismiss until they exit the stair zone and walk back in.
	_leave_prompt_blocked = true
	hide_leave_apartment_dialog()


## --- Gun lesson dialog (after failed fireman social check) ---

func _build_gun_lesson_dialog() -> void:
	if _hud_layer == null:
		return
	var root := Control.new()
	root.name = "GunLessonDialog"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	_hud_layer.add_child(root)
	_gun_lesson_dialog = root

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var outer := PanelContainer.new()
	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = INV_PURPLE
	outer_style.border_color = INV_PURPLE.lightened(0.15)
	outer_style.set_border_width_all(3)
	outer_style.set_corner_radius_all(8)
	outer_style.set_content_margin_all(6)
	outer.add_theme_stylebox_override("panel", outer_style)
	center.add_child(outer)

	var panel := PanelContainer.new()
	var panel_style := _gold_panel_style(18)
	panel_style.bg_color = Color(0.12, 0.08, 0.10, 0.96)
	panel.add_theme_stylebox_override("panel", panel_style)
	outer.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.custom_minimum_size = Vector2(360, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)

	var title := Label.new()
	title.name = "Title"
	title.text = MSG_GUN_PROMPT
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(320, 0)
	if _pixel_font != null:
		title.add_theme_font_override("font", _pixel_font)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", HUD_TEXT)
	col.add_child(title)

	if ResourceLoader.exists("res://handgun.png"):
		var icon_row := CenterContainer.new()
		col.add_child(icon_row)
		var icon := TextureRect.new()
		icon.texture = load("res://handgun.png")
		icon.custom_minimum_size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_row.add_child(icon)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 14)
	col.add_child(btn_row)

	var yes_btn := _make_dialog_button("Yes", "GunYesButton")
	yes_btn.pressed.connect(_on_gun_lesson_yes)
	btn_row.add_child(yes_btn)

	var no_btn := _make_dialog_button("No", "GunNoButton")
	no_btn.pressed.connect(_on_gun_lesson_no)
	btn_row.add_child(no_btn)


## Returns true if player chooses Yes (shoot).
func show_gun_lesson_dialog() -> bool:
	if _gun_lesson_dialog == null:
		_build_gun_lesson_dialog()
	if _gun_lesson_dialog == null:
		return false
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
	var root := Control.new()
	root.name = "EvaluationDialog"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	_hud_layer.add_child(root)
	_eval_dialog = root

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
	outer_style.set_border_width_all(3)
	outer_style.set_corner_radius_all(8)
	outer_style.set_content_margin_all(6)
	outer.add_theme_stylebox_override("panel", outer_style)
	center.add_child(outer)

	var panel := PanelContainer.new()
	panel.name = "DialogPanel"
	var panel_style := _gold_panel_style(18)
	panel_style.bg_color = Color(0.12, 0.08, 0.10, 0.96)
	panel.add_theme_stylebox_override("panel", panel_style)
	outer.add_child(panel)

	var col := VBoxContainer.new()
	col.name = "Content"
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(400, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)

	_eval_title = Label.new()
	_eval_title.name = "Title"
	_eval_title.text = "END OF ROUND"
	_eval_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _pixel_font != null:
		_eval_title.add_theme_font_override("font", _pixel_font)
	_eval_title.add_theme_font_size_override("font_size", 14)
	_eval_title.add_theme_color_override("font_color", HUD_TEXT)
	col.add_child(_eval_title)

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


## Show evaluation popup; type full_text onto the Label in Godot, then hold 2.5s.
func show_evaluation_popup(full_text: String) -> void:
	if _eval_dialog == null or _eval_label == null:
		return
	_eval_label.text = ""
	_eval_dialog.visible = true
	# Typewriter — text is a Godot Label string, not image art.
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
		# Fall back to normal take if lizard already gone.
		_consume_inv_entry(entry)
		return
	_give_pills_to_lizard(entry)


func _give_pills_to_lizard(entry: Dictionary) -> void:
	if not _inv.has(entry):
		var matched: Dictionary = {}
		var ok := false
		for e in _inv:
			if e.get("slot") == entry.get("slot"):
				matched = e
				ok = true
				break
		if not ok:
			return
		entry = matched
	_inv.erase(entry)
	var slot: Control = entry.get("slot") as Control
	if slot and is_instance_valid(slot):
		slot.queue_free()
	_update_held_items_visibility()

	var trapped: bool = bool(entry.get("trapped", false))
	var roomate := get_node_or_null("/root/Main/Roomate")
	if roomate and roomate.has_method("give_pills"):
		roomate.call("give_pills", trapped)
	if trapped:
		set_status_message("You gave the bad pills to the pet lizard...")
	else:
		set_status_message("The pet lizard zooms on clean pills!")


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
	# Show held items whenever P2 is the active character and is carrying something.
	# Includes leave-ready and full end-of-round / Evaluation free-roam (was wrongly
	# hidden once evaluation_active flipped true and never cleared).
	var p2_phase: bool = (
		current_turn == "Player2"
		or current_turn == "Evaluation"
	)
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
		if pipe_bomb_detonated and _fireman != null:
			_hud_label.text = "Fire Department arrived"
		else:
			_hud_label.text = "End of Round..."
	elif is_p2 and leave_available:
		_hud_label.text = "Items: %d/%d — Leave via stairs" % [p2_items_used, P2_USES_MAX]
	elif is_p2:
		_hud_label.text = "Items Used: %d/%d" % [p2_items_used, P2_USES_MAX]
	else:
		_hud_label.text = "Booby Traps: %d/%d" % [traps_left, TRAPS_MAX]
	# P1: trap counter only. P2 / eval: counter + stats + buffs/debuffs.
	if _stats_panel:
		_stats_panel.visible = is_p2
	if _effects_panel:
		_effects_panel.visible = is_p2
	_hud_layer.visible = true
	if is_p2:
		_refresh_stat_bar("Agility", agility)
		_refresh_stat_bar("Charisma", charisma)
		_refresh_stat_bar("Intelligence", intelligence)
