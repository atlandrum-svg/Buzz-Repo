extends Area2D

var player_inside = false

func _ready():
	connect("body_entered", _on_body_entered)
	connect("body_exited", _on_body_exited)

func _on_body_entered(body):
	if body.name == "PlayerBody":
		player_inside = true

func _on_body_exited(body):
	if body.name == "PlayerBody":
		player_inside = false

func _process(_delta):
	if player_inside and Input.is_action_just_pressed("interact"):
		# Load cutscene scene
		var cutscene = preload("res://Cutscene.tscn").instantiate()
		get_tree().current_scene.add_child(cutscene)
