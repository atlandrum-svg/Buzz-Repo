extends Area2D
## Office filing cabinet — blackmail (clean) or monkey attack (trapped).

const UsableShimmer = preload("res://usable_shimmer.gd")
const ItemPrompts = preload("res://item_prompts.gd")
const MonkeyNpc = preload("res://monkey_npc.gd")

const MSG_BLACKMAIL := "You have found blackmail on the boss! This may give you an edge in the interview"
const MSG_MONKEY := "A monkey has emerged from the cabinet, attacking you."

@onready var prop_sprite: Sprite2D = get_parent() as Sprite2D
@onready var label: Label = get_parent().get_node_or_null("Label") as Label
@onready var player1_body = $/root/Main/Player1/Player1Body
@onready var player2_body = $/root/Main/Player2/Player2Body
@onready var turn_manager = $/root/Main/TurnManager

var player_inside = null
var is_booby_trapped: bool = false
var _busy: bool = false
var _monkey_spawned: bool = false
## Once Player 2 has used (or inspected past) the cabinet, it stops offering
## Inspect/Use again — previously the blackmail path had no guard at all, so
## the label kept re-prompting (and would replay the blackmail message) for
## as long as the round's shared 3-use budget had anything left.
var _used: bool = false


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	if label:
		label.visible = false
		ItemPrompts.apply_font(label)
	if prop_sprite:
		UsableShimmer.attach(prop_sprite)


func reset_for_new_round() -> void:
	is_booby_trapped = false
	_busy = false
	_monkey_spawned = false
	_used = false
	player_inside = null
	if label:
		label.visible = false
	if prop_sprite:
		prop_sprite.visible = true
		prop_sprite.material = null
		prop_sprite.self_modulate = Color.WHITE
		prop_sprite.modulate = Color.WHITE


func _on_body_entered(body) -> void:
	if _busy:
		return
	if body == player1_body or body == player2_body:
		player_inside = body
		if body == player1_body and turn_manager.current_turn == "Player1":
			label.text = ItemPrompts.TRAP
			label.visible = true
		elif body == player2_body and turn_manager.current_turn == "Player2":
			if not _used and turn_manager.can_p2_use_world_item():
				label.text = ItemPrompts.prompt_for(turn_manager)
				label.visible = true
			else:
				label.visible = false


func _on_body_exited(body) -> void:
	if body == player_inside:
		player_inside = null
		if not _busy and label:
			label.visible = false


func _input(event) -> void:
	if player_inside == null or _busy:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if player_inside == player1_body and turn_manager.current_turn == "Player1" and event.keycode == KEY_E:
		if is_booby_trapped:
			return
		if not turn_manager.consume_trap():
			return
		is_booby_trapped = true
		if label:
			label.visible = false
		UsableShimmer.mark_trapped_p1(prop_sprite)
	elif player_inside == player2_body and turn_manager.current_turn == "Player2":
		if _used:
			return
		if not turn_manager.can_p2_use_world_item():
			return
		if event.keycode == KEY_I:
			if not turn_manager.consume_p2_inspect():
				return
			if is_booby_trapped:
				label.text = ItemPrompts.TRAP_FOUND
				is_booby_trapped = false
			else:
				label.text = ItemPrompts.NO_TRAP
			label.visible = true
			await get_tree().create_timer(1.0).timeout
			if player_inside == player2_body and turn_manager.can_p2_use_world_item():
				label.text = ItemPrompts.USE_ONLY
				label.visible = true
			else:
				label.visible = false
		elif event.keycode == KEY_E:
			await _use_prop()


func _use_prop() -> void:
	_busy = true
	UsableShimmer.mark_used_p2(prop_sprite)
	if label:
		label.visible = false
	if is_booby_trapped:
		is_booby_trapped = false
		await _run_monkey_trap_sequence()
	else:
		if turn_manager and turn_manager.has_method("show_evaluation_popup"):
			await turn_manager.show_evaluation_popup(MSG_BLACKMAIL)
		if turn_manager and turn_manager.has_method("apply_anxiety"):
			turn_manager.apply_anxiety("sleuth")
		if turn_manager and turn_manager.has_method("set_status_message"):
			turn_manager.set_status_message(MSG_BLACKMAIL)
	turn_manager.consume_p2_use()
	_busy = false
	_used = true
	if label:
		label.visible = false


## 1) Monkey pops out  2) player cartwheels (no explosion)
## 3) freeze  4) message  5) monkey walks beside player  6) pills / lizard
func _run_monkey_trap_sequence() -> void:
	if _monkey_spawned:
		return
	_monkey_spawned = true

	var main: Node = get_tree().current_scene
	if main == null:
		main = get_node_or_null("/root/Main")
	if main == null:
		return

	var p2: Node2D = player2_body as Node2D
	if p2 == null:
		p2 = get_node_or_null("/root/Main/Player2/Player2Body") as Node2D

	var boom_pos: Vector2 = prop_sprite.global_position if prop_sprite else Vector2.ZERO
	var start: Vector2 = boom_pos + Vector2(0.0, -12.0)
	# Land clear of the cabinet solid (same style as dresser pipe-bomb eject).
	var land: Vector2 = _monkey_eject_land(boom_pos, p2)

	var monkey: Node = MonkeyNpc.new()
	monkey.name = "OfficeMonkey"
	main.add_child(monkey)
	if monkey is Node2D:
		(monkey as Node2D).global_position = start
	if monkey.has_method("idle_in_place"):
		monkey.call("idle_in_place")
	if turn_manager and turn_manager.has_method("register_office_monkey"):
		turn_manager.call("register_office_monkey", monkey)

	# Jump out of the cabinet at the same moment as the knockback cartwheel.
	# Start eject without awaiting so both run in parallel.
	if is_instance_valid(monkey) and monkey.has_method("eject_arc"):
		monkey.call("eject_arc", start, land)

	# Same knockback cartwheel as the pipe bomb — no explosion FX.
	# Origin is the cabinet so the shove hits as the monkey bursts out.
	if p2 and p2.has_method("play_blast_cartwheel"):
		if p2.has_method("set_active"):
			p2.call("set_active", true)
		await p2.call("play_blast_cartwheel", boom_pos)

	# Cartwheel is longer than the eject arc; brief settle if eject still finishing.
	await get_tree().process_frame

	# Freeze wherever momentum left them.
	if p2 and p2.has_method("set_movement_locked"):
		p2.call("set_movement_locked", true)
	if p2 is CharacterBody2D:
		(p2 as CharacterBody2D).velocity = Vector2.ZERO

	# Message only after they stop.
	if turn_manager and turn_manager.has_method("show_evaluation_popup"):
		await turn_manager.show_evaluation_popup(MSG_MONKEY)
	if turn_manager and turn_manager.has_method("set_status_message"):
		turn_manager.set_status_message(MSG_MONKEY)

	# Message gone — monkey walks over and stands beside the player.
	if is_instance_valid(monkey) and monkey.has_method("walk_to_beside") and p2:
		await monkey.call("walk_to_beside", p2)

	# Pills dialog / lizard walk / idle.
	if turn_manager and turn_manager.has_method("on_monkey_reached_player"):
		await turn_manager.call("on_monkey_reached_player", monkey)


## Floor spot just outside the cabinet body, biased toward the player if possible.
func _monkey_eject_land(cabinet_pos: Vector2, p2: Node2D) -> Vector2:
	var half: Vector2 = _cabinet_half()
	var toward: Vector2 = Vector2.RIGHT
	if p2 != null and is_instance_valid(p2):
		var d: Vector2 = p2.global_position - cabinet_pos
		if d.length_squared() > 4.0:
			toward = d.normalized()
	# Prefer a clear side (right of cabinet if player is right, else left).
	var side: float = half.x + 48.0
	if toward.x < 0.0:
		side = -(half.x + 48.0)
	var land := cabinet_pos + Vector2(side, half.y * 0.55)
	# Nudge further toward the player so the walk starts free of the solid.
	land += toward * 18.0
	return land


func _cabinet_half() -> Vector2:
	if prop_sprite == null:
		return Vector2(40.0, 50.0)
	var tex: Texture2D = prop_sprite.texture
	if tex == null:
		return Vector2(40.0, 50.0)
	var sx: float = absf(prop_sprite.scale.x)
	var sy: float = absf(prop_sprite.scale.y)
	return Vector2(tex.get_width() * sx * 0.5, tex.get_height() * sy * 0.5)
