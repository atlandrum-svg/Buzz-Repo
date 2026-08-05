extends Area2D

const UsableShimmer = preload("res://usable_shimmer.gd")
const ItemPrompts = preload("res://item_prompts.gd")

@onready var bottle: Sprite2D = get_parent() as Sprite2D
@onready var label = $/root/Main/PillBottle/Label
@onready var player1_body = $/root/Main/Player1/Player1Body
@onready var player2_body = $/root/Main/Player2/Player2Body
@onready var turn_manager = $/root/Main/TurnManager
var player_inside = null
var is_booby_trapped = false
var _picked_up := false


func _ready():
	monitoring = true
	collision_mask = 1
	collision_layer = 0
	label.visible = false
	ItemPrompts.apply_font(label)
	# Original closed texture only
	var tex: Texture2D = load("res://pill_bottle.png")
	if tex and bottle:
		bottle.texture = tex
		bottle.visible = true
		bottle.material = null
		bottle.self_modulate = Color.WHITE
		bottle.modulate = Color.WHITE
	UsableShimmer.attach(bottle)
	# Ensure collision shape is enabled
	for c in get_children():
		if c is CollisionShape2D:
			c.disabled = false


func _on_body_entered(body):
	if _picked_up:
		return
	if body == player1_body or body == player2_body:
		player_inside = body
		if body == player1_body and turn_manager.current_turn == "Player1":
			label.text = ItemPrompts.TRAP
			label.visible = true
		elif body == player2_body and turn_manager.current_turn == "Player2":
			if turn_manager.can_p2_use_world_item():
				label.text = ItemPrompts.prompt_for(turn_manager)
				label.visible = true
			else:
				label.visible = false


func _on_body_exited(body):
	if body == player_inside:
		player_inside = null
		label.visible = false


func _input(event):
	if _picked_up:
		return
	if player_inside == null:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if player_inside == player1_body and turn_manager.current_turn == "Player1" and event.keycode == KEY_E:
		if is_booby_trapped:
			return
		if not turn_manager.consume_trap():
			return
		is_booby_trapped = true
		label.visible = false
		UsableShimmer.mark_trapped_p1(bottle)
	elif player_inside == player2_body and turn_manager.current_turn == "Player2":
		if not turn_manager.can_p2_use_world_item():
			return
		if event.keycode == KEY_I:
			# One inspect per round. It costs the inspect, NOT one of the 3 uses,
			# and never marks the prop used — it stays usable either way.
			if not turn_manager.consume_p2_inspect():
				return
			if is_booby_trapped:
				label.text = ItemPrompts.TRAP_FOUND
				is_booby_trapped = false
			else:
				label.text = ItemPrompts.NO_TRAP
			await get_tree().create_timer(1.0).timeout
			# Straight back to a use prompt if we are still standing here.
			if player_inside == player2_body and turn_manager.can_p2_use_world_item():
				label.text = ItemPrompts.USE_ONLY
				label.visible = true
			else:
				label.visible = false
		elif event.keycode == KEY_E:
			_pickup_to_inventory()


func reset_for_new_round() -> void:
	_picked_up = false
	is_booby_trapped = false
	if bottle:
		bottle.visible = true
		var tex: Texture2D = load("res://pill_bottle.png")
		if tex:
			bottle.texture = tex
		bottle.material = null
		bottle.self_modulate = Color.WHITE
		bottle.modulate = Color.WHITE
	monitoring = true
	for c in get_children():
		if c is CollisionShape2D:
			c.disabled = false


func _pickup_to_inventory() -> void:
	if _picked_up:
		return
	_picked_up = true
	var trapped: bool = is_booby_trapped
	label.visible = false

	UsableShimmer.mark_used_p2(bottle)
	# Remove from world
	bottle.visible = false
	monitoring = false
	for c in get_children():
		if c is CollisionShape2D:
			c.disabled = true
	# Inventory + use count
	if turn_manager and turn_manager.has_method("add_inventory_pill"):
		turn_manager.add_inventory_pill(trapped)
	turn_manager.consume_p2_use()
