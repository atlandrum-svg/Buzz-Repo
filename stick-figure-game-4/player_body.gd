extends CharacterBody2D

@export var speed = 100.0
@onready var sprite = $Sprite2D
var anim_frame = 0
var anim_timer = 0.0
@export var anim_speed = 0.15
var is_active = false
var player_name = ""

func _ready():
	$Camera2D.enabled = false
	if name == "Player1Body":
		player_name = "Player1"
	elif name == "Player2Body":
		player_name = "Player2"

func set_active(active: bool):
	is_active = active
	$Camera2D.enabled = active
	visible = active
	# Inactive players must not block the active one
	$CollisionShape2D.disabled = not active
	collision_layer = 1 if active else 0
	collision_mask = 1 if active else 0
	set_physics_process(active)

func _physics_process(delta):
	if not is_active:
		return

	var direction = Vector2.ZERO
	if Input.is_action_pressed("ui_up"):
		direction.y -= 1
	elif Input.is_action_pressed("ui_down"):
		direction.y += 1
	elif Input.is_action_pressed("ui_left"):
		direction.x -= 1
	elif Input.is_action_pressed("ui_right"):
		direction.x += 1

	if direction.length() > 0:
		direction = direction.normalized()
		anim_timer += delta
		if anim_timer >= anim_speed:
			anim_timer = 0.0
			anim_frame = (anim_frame + 1) % 4
	else:
		anim_frame = 0

	if direction.y < 0:
		sprite.frame = 12 + anim_frame
	elif direction.y > 0:
		sprite.frame = 0 + anim_frame
	elif direction.x < 0:
		sprite.frame = 4 + anim_frame
	elif direction.x > 0:
		sprite.frame = 8 + anim_frame
	else:
		if sprite.frame >= 12:
			sprite.frame = 12
		elif sprite.frame >= 8:
			sprite.frame = 8
		elif sprite.frame >= 4:
			sprite.frame = 4
		else:
			sprite.frame = 0

	velocity = direction * speed
	move_and_slide()
