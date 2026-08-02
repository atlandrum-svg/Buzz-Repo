extends Button

func _ready():
	pressed.connect(_on_pressed)

func _on_pressed():
	get_tree().current_scene.remove_child(get_parent())  # Remove Cutscene
