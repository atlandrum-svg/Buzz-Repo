extends Area2D

const UsableShimmer = preload("res://usable_shimmer.gd")
const ItemPrompts = preload("res://item_prompts.gd")

@onready var label = $/root/Main/Level/LaptopCutOut/Label
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
				UsableShimmer.mark_used_p2(get_parent())
				if is_booby_trapped:
					label.visible = false
					is_booby_trapped = false
					# End-of-round evaluation flag (cops called for illegal download).
					if turn_manager and turn_manager.has_method("mark_illegal_download"):
						turn_manager.mark_illegal_download()
					await turn_manager.show_download_trap_popup(2.5)
					if turn_manager.has_method("apply_anxiety"):
						turn_manager.apply_anxiety("cyber_crime")
						turn_manager.set_status_message(
							"There is now highly illegal material on your laptop."
						)
				else:
					# Clean laptop: a couple of hours of not thinking about it.
					label.visible = false
					if turn_manager and turn_manager.has_method("show_evaluation_popup"):
						await turn_manager.show_evaluation_popup(
							"You played video games, distracting you from your woes"
						)
					if turn_manager and turn_manager.has_method("apply_anxiety"):
						turn_manager.apply_anxiety("escapism")
						turn_manager.set_status_message(
							"You played video games, distracting you from your woes"
						)
				turn_manager.consume_p2_use()
