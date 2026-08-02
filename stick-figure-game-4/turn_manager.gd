extends Node

@onready var player1 = $/root/Main/Player1/Player1Body
@onready var player2 = $/root/Main/Player2/Player2Body
var current_turn = "Player1"

func _ready():
	player1.set_active(true)
	player2.set_active(false)

func switch_turn():
	if current_turn == "Player1":
		current_turn = "Player2"
		player1.set_active(false)
		player2.set_active(true)
	else:
		current_turn = "Player1"
		player1.set_active(true)
		player2.set_active(false)
