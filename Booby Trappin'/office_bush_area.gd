extends Area2D
## Office bush — booby trap spawns a widow-fang spider that leaps out and stalks the player.

const UsableShimmer = preload("res://usable_shimmer.gd")
const ItemPrompts = preload("res://item_prompts.gd")
const SpiderNpc = preload("res://spider_npc.gd")

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
var _spider: Node = null


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
	player_inside = null
	if is_instance_valid(_spider):
		_spider.queue_free()
	_spider = null
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
			if turn_manager.can_p2_use_world_item():
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
		await _run_spider_trap_sequence()
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
	if player_inside == player2_body and turn_manager.can_p2_use_world_item() and label:
		label.text = ItemPrompts.prompt_for(turn_manager)
		label.visible = true
	elif label:
		label.visible = false


## 1) Spider leaps out of the bush (jump + bounce, same shape as the cabinet monkey)
## 2) It scurries straight to wherever the player currently is
## 3) It pauses right beside them, then the bite message pops up.
func _run_spider_trap_sequence() -> void:
	var main: Node = get_tree().current_scene
	if main == null:
		main = get_node_or_null("/root/Main")
	if main == null:
		return

	var p2: Node2D = player2_body as Node2D
	if p2 == null:
		p2 = get_node_or_null("/root/Main/Player2/Player2Body") as Node2D

	var bush_pos: Vector2 = prop_sprite.global_position if prop_sprite else Vector2.ZERO
	var start: Vector2 = bush_pos + Vector2(0.0, -10.0)
	var land: Vector2 = _spider_eject_land(bush_pos, p2)

	var spider: Node = SpiderNpc.new()
	spider.name = "OfficeSpider"
	main.add_child(spider)
	if spider is Node2D:
		(spider as Node2D).global_position = start
	if spider.has_method("idle_in_place"):
		spider.call("idle_in_place")
	_spider = spider

	# Little leap out of the bush with a bounce on landing.
	if is_instance_valid(spider) and spider.has_method("eject_arc"):
		await spider.call("eject_arc", start, land)

	# Scurry straight to the player, wherever they are, and stop beside them.
	if is_instance_valid(spider) and spider.has_method("walk_to_beside") and p2:
		await spider.call("walk_to_beside", p2)

	# Bite lands only once the spider has caught up and settled next to them.
	if turn_manager and turn_manager.has_method("show_evaluation_popup"):
		await turn_manager.show_evaluation_popup(trap_message)
	if trap_anxiety_id != "" and turn_manager and turn_manager.has_method("apply_anxiety"):
		turn_manager.apply_anxiety(trap_anxiety_id)
	if turn_manager and turn_manager.has_method("set_status_message"):
		turn_manager.set_status_message(trap_message)

	if is_instance_valid(spider):
		if spider.has_method("vanish"):
			spider.call("vanish")
		else:
			spider.queue_free()
	_spider = null


## Floor spot just outside the bush, biased toward wherever the player is.
func _spider_eject_land(bush_pos: Vector2, p2: Node2D) -> Vector2:
	var toward: Vector2 = Vector2.RIGHT
	if p2 != null and is_instance_valid(p2):
		var d: Vector2 = p2.global_position - bush_pos
		if d.length_squared() > 4.0:
			toward = d.normalized()
	return bush_pos + toward * 36.0 + Vector2(0.0, 18.0)
