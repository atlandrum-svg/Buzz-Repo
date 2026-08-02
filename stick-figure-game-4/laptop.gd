extends Node2D

func _ready():
	$InteractionLabel.visible = false

func _on_InteractionArea_body_entered(_body):
	print("Entered: ", _body)  # Debug: See what entered the area
	if _body.is_in_group("Player"):
		print("Player detected!")  # Debug: Confirm Player group
		$InteractionLabel.visible = true

func _on_InteractionArea_body_exited(_body):
	print("Exited: ", _body)  # Debug: See what exited
	if _body.is_in_group("Player"):
		print("Player left!")
		$InteractionLabel.visible = false
