extends Area2D

@onready var label = $/root/Main/Laptop/Label
@onready var player_body = $/root/Main/Player/PlayerBody
@onready var inspects_label = $/root/Main/UI/InspectsLabel
var player_inside = false
var inspects = 1  # Start with 1 inspect

func _ready():
	label.visible = false
	inspects_label.text = "Inspects: " + str(inspects)
	print("Label node: ", label)
	print("PlayerBody node: ", player_body)
	print("InspectsLabel node: ", inspects_label)

func _on_body_entered(body):
	print("Body entered: ", body)
	if body == player_body:
		player_inside = true
		if inspects > 0:
			label.text = "Press I to inspect"
			label.visible = true

func _on_body_exited(body):
	print("Body exited: ", body)
	if body == player_body:
		player_inside = false
		label.visible = false

func _input(event):
	if player_inside and inspects > 0 and event is InputEventKey and event.pressed and event.keycode == KEY_I:
		print("Inspect used!")
		inspects -= 1
		inspects_label.text = "Inspects: " + str(inspects)
		label.visible = false  # Hide prompt after inspecting
