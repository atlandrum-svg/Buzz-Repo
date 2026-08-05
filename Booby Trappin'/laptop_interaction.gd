extends Area2D

@onready var prompt_label = get_node("./TempLabel")  # Adjust if TempLabel isn’t under Main

func _ready():
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body):
	if body.is_in_group("player"):
		prompt_label.visible = true

func _on_body_exited(body):
	if body.is_in_group("player"):
		prompt_label.visible = false
