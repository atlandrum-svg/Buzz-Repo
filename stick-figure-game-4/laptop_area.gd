extends Area2D

@onready var label = $/root/Main/LaptopCutOut/Label
@onready var player1_body = $/root/Main/Player1/Player1Body
@onready var player2_body = $/root/Main/Player2/Player2Body
@onready var turn_manager = $/root/Main/TurnManager
var player_inside = null
var is_booby_trapped = false


func _ready():
	label.visible = false


func _on_body_entered(body):
	if body == player1_body or body == player2_body:
		player_inside = body
		if body == player1_body and turn_manager.current_turn == "Player1":
			label.text = "Press E to booby trap"
			label.visible = true
		elif body == player2_body and turn_manager.current_turn == "Player2":
			label.text = "Press I to inspect or E to use"
			label.visible = true


func _on_body_exited(body):
	if body == player_inside:
		player_inside = null
		label.visible = false


func _input(event):
	if player_inside and event is InputEventKey and event.pressed:
		if player_inside == player1_body and turn_manager.current_turn == "Player1" and event.keycode == KEY_E:
			is_booby_trapped = true
			label.visible = false
			turn_manager.switch_turn()
			print("Laptop booby trap set!")
		elif player_inside == player2_body and turn_manager.current_turn == "Player2":
			if event.keycode == KEY_I:
				if is_booby_trapped:
					label.text = "Trap found!"
					is_booby_trapped = false
					await get_tree().create_timer(1.0).timeout
					label.visible = false
				else:
					label.text = "No trap found."
					await get_tree().create_timer(1.0).timeout
					label.visible = false
				turn_manager.switch_turn()
			elif event.keycode == KEY_E:
				if is_booby_trapped:
					label.text = "Trap triggered!"
					await get_tree().create_timer(1.0).timeout
					label.visible = false
					print("Laptop trap triggered (no plant anim)!")
				else:
					label.text = "Used laptop, nothing happened."
					await get_tree().create_timer(1.0).timeout
					label.visible = false
				turn_manager.switch_turn()
