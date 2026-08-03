extends Area2D

const UsableShimmer = preload("res://usable_shimmer.gd")
const ItemPrompts = preload("res://item_prompts.gd")

@onready var label = $/root/Main/LaptopCutOut/Label
@onready var player1_body = $/root/Main/Player1/Player1Body
@onready var player2_body = $/root/Main/Player2/Player2Body
@onready var turn_manager = $/root/Main/TurnManager
var player_inside = null
var is_booby_trapped = false


func _ready():
	label.visible = false
	ItemPrompts.apply_font(label)
	UsableShimmer.attach(get_parent())


func _on_body_entered(body):
	if body == player1_body or body == player2_body:
		player_inside = body
		if body == player1_body and turn_manager.current_turn == "Player1":
			label.text = ItemPrompts.TRAP
			label.visible = true
		elif body == player2_body and turn_manager.current_turn == "Player2":
			label.text = ItemPrompts.INSPECT_OR_USE
			label.visible = true


func _on_body_exited(body):
	if body == player_inside:
		player_inside = null
		label.visible = false


func _input(event):
	if player_inside and event is InputEventKey and event.pressed:
		if player_inside == player1_body and turn_manager.current_turn == "Player1" and event.keycode == KEY_E:
			if is_booby_trapped:
				return # already trapped
			if not turn_manager.consume_trap():
				return
			is_booby_trapped = true
			label.visible = false
			UsableShimmer.mark_trapped_p1(get_parent())
		elif player_inside == player2_body and turn_manager.current_turn == "Player2":
			if event.keycode == KEY_I:
				UsableShimmer.mark_used_p2(get_parent())
				if is_booby_trapped:
					label.text = ItemPrompts.TRAP_FOUND
					is_booby_trapped = false
					if turn_manager.has_method("record_trap_found"):
						turn_manager.record_trap_found()
					await get_tree().create_timer(1.0).timeout
					label.visible = false
				else:
					label.text = ItemPrompts.NO_TRAP
					await get_tree().create_timer(1.0).timeout
					label.visible = false
				turn_manager.consume_p2_use()
			elif event.keycode == KEY_E:
				UsableShimmer.mark_used_p2(get_parent())
				if is_booby_trapped:
					label.text = ItemPrompts.TRAP_TRIGGERED
					if turn_manager.has_method("record_trap_sprung"):
						turn_manager.record_trap_sprung()
					await get_tree().create_timer(1.0).timeout
					label.visible = false
				else:
					label.text = ItemPrompts.used_nothing("Laptop")
					await get_tree().create_timer(1.0).timeout
					label.visible = false
				turn_manager.consume_p2_use()
