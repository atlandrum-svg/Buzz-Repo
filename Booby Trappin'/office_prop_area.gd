extends Area2D
## Generic office prop: same trap / inspect / use + shimmer as bedroom items.
## Parent must be a Sprite2D with a child Label for prompts.

const UsableShimmer = preload("res://usable_shimmer.gd")
const ItemPrompts = preload("res://item_prompts.gd")

@export var prop_name: String = "Prop"
@export var clean_message: String = "Nothing interesting."
@export var trap_message: String = "Trap triggered!"
## Optional anxiety id from anxiety_system (empty = no bar change).
@export var trap_anxiety_id: String = ""
@export var clean_anxiety_id: String = ""

@onready var prop_sprite: Sprite2D = get_parent() as Sprite2D
@onready var label: Label = get_parent().get_node_or_null("Label") as Label
@onready var player1_body = $/root/Main/Player1/Player1Body
@onready var player2_body = $/root/Main/Player2/Player2Body
@onready var turn_manager = $/root/Main/TurnManager

var player_inside = null
var is_booby_trapped: bool = false
var _busy: bool = false
## Once Player 2 has used (or inspected past) this prop, it stops offering
## Inspect/Use again — previously it kept re-prompting for as long as the
## round's shared 3-use budget had anything left, letting you "use" the same
## prop over and over.
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
		if turn_manager and turn_manager.has_method("show_evaluation_popup"):
			await turn_manager.show_evaluation_popup(trap_message)
		elif label:
			label.text = trap_message
			label.visible = true
			await get_tree().create_timer(1.5).timeout
			label.visible = false
		if trap_anxiety_id != "" and turn_manager and turn_manager.has_method("apply_anxiety"):
			turn_manager.apply_anxiety(trap_anxiety_id)
		if turn_manager and turn_manager.has_method("set_status_message"):
			turn_manager.set_status_message(trap_message)
	else:
		if turn_manager and turn_manager.has_method("show_evaluation_popup"):
			await turn_manager.show_evaluation_popup(clean_message)
		elif label:
			label.text = ItemPrompts.used_nothing(prop_name)
			label.visible = true
			await get_tree().create_timer(1.0).timeout
			label.visible = false
		if clean_anxiety_id != "" and turn_manager and turn_manager.has_method("apply_anxiety"):
			turn_manager.apply_anxiety(clean_anxiety_id)
		if turn_manager and turn_manager.has_method("set_status_message"):
			turn_manager.set_status_message(clean_message)
	turn_manager.consume_p2_use()
	_busy = false
	_used = true
	if label:
		label.visible = false
