extends CharacterBody2D

@export var speed = 100.0
## Permanent multiplier (e.g. 2.5 after clean ADHD meds from inventory).
var speed_mult: float = 1.0
@onready var sprite = $Sprite2D
var anim_frame = 0
var anim_timer = 0.0
@export var anim_speed = 0.15
var is_active = false
var player_name = ""
## Trap cutscenes: freeze position/input without deactivating the player.
var movement_locked := false

const CARTWHEEL_FRAMES := 9
const CARTWHEEL_FPS := 18.0
const BLAST_DURATION := 2.2
const BLAST_SPEED := 720.0
const BLAST_DRAG := 40.0 ## barely slow — chaos first
const BOUNCE_GAIN := 1.35 ## each wall hit speeds up
const BOUNCE_SPIN := 0.55 ## radians of random kick on bounce
const MAX_BLAST_SPEED := 1400.0

var _blast_active := false
var _blast_time := 0.0
var _blast_frame_t := 0.0
var _cart_prev_tex: Texture2D
var _cart_prev_h: int = 4
var _cart_prev_v: int = 4
var _cart_prev_f: int = 0


func _ready():
	$Camera2D.enabled = false
	if name == "Player1Body":
		player_name = "Player1"
	elif name == "Player2Body":
		player_name = "Player2"
	add_to_group("player_bodies")


## Permanent walk boost (inventory ADHD meds — clean bottle).
func apply_adhd_boost() -> void:
	speed_mult = 2.5
	speed = 200.0
	anim_speed = 0.07
	print("Player ", name, " ADHD boost ON: speed=", speed, " mult=", speed_mult, " effective=", speed * speed_mult)


## Permanent drowsy state (booby-trapped pills from inventory): half speed + stooped walk sheet.
func apply_drowsy_debuff() -> void:
	speed_mult = 1.0
	speed = 50.0
	anim_speed = 0.28
	var tex: Texture2D = load("res://julian assange sprite sheet black drowsy.png")
	if tex and sprite:
		sprite.texture = tex
		sprite.hframes = 4
		sprite.vframes = 4
		# Keep facing frame in range
		sprite.frame = mini(sprite.frame, 15)
	print("Player ", name, " DROWSY ON: speed=", speed, " mult=", speed_mult)


func set_active(active: bool):
	is_active = active
	$Camera2D.enabled = active
	visible = active
	# Inactive players must not block the active one
	$CollisionShape2D.disabled = not active
	collision_layer = 1 if active else 0
	collision_mask = 1 if active else 0
	set_physics_process(active)
	if not active:
		movement_locked = false
		_end_blast_visual()


func set_movement_locked(locked: bool) -> void:
	movement_locked = locked
	if locked and not _blast_active:
		velocity = Vector2.ZERO


## Knockback away from blast, cartwheel anim, bounce off walls (collision mask).
func play_blast_cartwheel(from_pos: Vector2) -> void:
	if sprite == null or _blast_active:
		return
	var tex: Texture2D = load("res://p2_cartwheel.png")
	if tex == null:
		return

	var dir: Vector2 = global_position - from_pos
	if dir.length_squared() < 16.0:
		dir = Vector2.RIGHT.rotated(randf() * TAU)
	else:
		dir = dir.normalized()

	movement_locked = true
	_blast_active = true
	_blast_time = 0.0
	_blast_frame_t = 0.0
	velocity = dir * BLAST_SPEED

	_cart_prev_tex = sprite.texture
	_cart_prev_h = sprite.hframes
	_cart_prev_v = sprite.vframes
	_cart_prev_f = sprite.frame
	sprite.texture = tex
	sprite.hframes = CARTWHEEL_FRAMES
	sprite.vframes = 1
	sprite.frame = 0

	while _blast_active and _blast_time < BLAST_DURATION:
		await get_tree().physics_frame

	_end_blast_visual()
	_blast_active = false
	velocity = Vector2.ZERO


func _end_blast_visual() -> void:
	if sprite == null:
		return
	if _cart_prev_tex != null:
		sprite.texture = _cart_prev_tex
		sprite.hframes = _cart_prev_h
		sprite.vframes = _cart_prev_v
		var max_f: int = maxi(_cart_prev_h * _cart_prev_v - 1, 0)
		sprite.frame = mini(_cart_prev_f, max_f)
	_cart_prev_tex = null


func _physics_process(delta):
	if not is_active:
		return

	if _blast_active:
		_blast_time += delta
		# Progress 0→1 over flight: little drag early, strong ease-out at the end
		var t: float = clampf(_blast_time / BLAST_DURATION, 0.0, 1.0)
		var ease_out: float = t * t # quadratic ease-in of drag
		var drag: float = lerpf(BLAST_DRAG, 2200.0, ease_out)
		velocity = velocity.move_toward(Vector2.ZERO, drag * delta)
		# Soft speed ceiling that shrinks toward zero near the end
		var speed_cap: float = lerpf(MAX_BLAST_SPEED, 80.0, ease_out)
		if velocity.length() > speed_cap:
			velocity = velocity.normalized() * speed_cap
		move_and_slide()
		# Bounce off walls / furniture — each hit goes FARTHER early; taper gain near end
		for i in get_slide_collision_count():
			var col: KinematicCollision2D = get_slide_collision(i)
			var n: Vector2 = col.get_normal()
			var bounced: Vector2 = velocity.bounce(n)
			var kick: float = randf_range(-BOUNCE_SPIN, BOUNCE_SPIN) * (1.0 - ease_out * 0.7)
			bounced = bounced.rotated(kick)
			var gain: float = lerpf(BOUNCE_GAIN, 0.85, ease_out)
			var spd: float = maxf(bounced.length(), BLAST_SPEED * 0.45) * gain
			spd = minf(spd, speed_cap)
			if bounced.length_squared() < 1.0:
				bounced = n.rotated(randf_range(-0.8, 0.8))
			velocity = bounced.normalized() * spd
		# Spin frames; slow spin slightly as speed dies
		_blast_frame_t += delta
		var spin_fps: float = lerpf(CARTWHEEL_FPS, 8.0, ease_out)
		var step: float = 1.0 / spin_fps
		while _blast_frame_t >= step:
			_blast_frame_t -= step
			if sprite:
				sprite.frame = (sprite.frame + 1) % CARTWHEEL_FRAMES
		if _blast_time >= BLAST_DURATION:
			_blast_active = false
			velocity = Vector2.ZERO
		return

	if movement_locked:
		velocity = Vector2.ZERO
		move_and_slide()
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

	velocity = direction * speed * speed_mult
	move_and_slide()
