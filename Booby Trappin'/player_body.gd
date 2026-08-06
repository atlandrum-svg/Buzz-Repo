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
## Persisted inventory status — survives evaluation lock/unlock.
var status_adhd: bool = false
var status_drowsy: bool = false
const BASE_SPEED := 100.0
const BASE_ANIM_SPEED := 0.15
## Trap cutscenes: freeze position/input without deactivating the player.
var movement_locked := false
## Scripted path (end-of-round walk): ignores WASD, walks toward a target.
var _scripted_walk := false
var _walk_target := Vector2.ZERO
var _walk_arrive_dist := 10.0
var _walk_done := false
var _walk_stuck_t := 0.0

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
## Debounces the anxiety "bump" report — without this, resting against a wall
## while sliding would fire a bump every single physics frame instead of once
## per distinct hit.
const BUMP_ANXIETY_COOLDOWN := 0.12
var _bump_cooldown_t := 0.0
var _turn_manager: Node = null
var _cart_prev_tex: Texture2D
var _cart_prev_h: int = 4
var _cart_prev_v: int = 4
var _cart_prev_f: int = 0

## Meditation sit pose (pillow use) — restore walk sheet after.
var _meditating := false
var _med_prev_tex: Texture2D
var _med_prev_h: int = 4
var _med_prev_v: int = 4
var _med_prev_f: int = 0
var _med_prev_scale: Vector2 = Vector2.ONE


func _ready():
	$Camera2D.enabled = false
	if name == "Player1Body":
		player_name = "Player1"
	elif name == "Player2Body":
		player_name = "Player2"
	add_to_group("player_bodies")


## Permanent walk boost (inventory ADHD meds — clean bottle).
func apply_adhd_boost() -> void:
	status_adhd = true
	status_drowsy = false
	_apply_status_movement()
	print("Player ", name, " ADHD boost ON: speed=", speed, " mult=", speed_mult, " effective=", speed * speed_mult)


## Permanent drowsy state (booby-trapped pills from inventory): half speed + stooped walk sheet.
func apply_drowsy_debuff() -> void:
	status_drowsy = true
	status_adhd = false
	_apply_status_movement()
	var tex: Texture2D = _load_walk_texture("res://p2_walk_drowsy.png")
	if tex == null:
		tex = _load_walk_texture("res://julian assange sprite sheet black drowsy.png")
	if sprite == null:
		sprite = get_node_or_null("Sprite2D") as Sprite2D
	if tex and sprite:
		sprite.texture = tex
		sprite.hframes = 4
		sprite.vframes = 4
		sprite.frame = mini(sprite.frame, 15)
		print("Player ", name, " DROWSY sheet applied: ", tex.resource_path)
	else:
		push_error("DROWSY sheet FAILED tex=%s sprite=%s" % [tex, sprite])
	print("Player ", name, " DROWSY ON: speed=", speed, " mult=", speed_mult)


## Re-apply movement modifiers from persisted status flags (safe after lock/unlock).
func _apply_status_movement() -> void:
	if status_adhd:
		speed_mult = 2.5
		speed = 200.0
		anim_speed = 0.07
	elif status_drowsy:
		speed_mult = 1.0
		speed = 50.0
		anim_speed = 0.28
	else:
		speed_mult = 1.0
		speed = BASE_SPEED
		anim_speed = BASE_ANIM_SPEED


func reassert_status() -> void:
	_apply_status_movement()
	if status_drowsy:
		# Keep drowsy sheet if still drowsy.
		var tex: Texture2D = _load_walk_texture("res://p2_walk_drowsy.png")
		if tex == null:
			tex = _load_walk_texture("res://julian assange sprite sheet black drowsy.png")
		if sprite == null:
			sprite = get_node_or_null("Sprite2D") as Sprite2D
		if tex and sprite:
			sprite.texture = tex
			sprite.hframes = 4
			sprite.vframes = 4


func _load_walk_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var t: Variant = load(path)
		if t is Texture2D:
			return t as Texture2D
	# Runtime decode if import missing
	var abs_path: String = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img:
			return ImageTexture.create_from_image(img)
	return null


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
	else:
		# Never lose pill boosts when re-activated after cutscenes / evaluation.
		_apply_status_movement()


func set_movement_locked(locked: bool) -> void:
	movement_locked = locked
	if locked and not _blast_active:
		velocity = Vector2.ZERO
		_scripted_walk = false
		_walk_done = true
	if not locked:
		_apply_status_movement()


## Walk to a world position with walk anim. Ignores player input until arrived or cancelled.
## Snaps if stuck against collision for ~1.2s.
func walk_to(target: Vector2, arrive_dist: float = 10.0) -> void:
	if not is_active:
		return
	_scripted_walk = true
	_walk_target = target
	_walk_arrive_dist = arrive_dist
	_walk_done = false
	_walk_stuck_t = 0.0
	movement_locked = false
	_meditating = false
	while _scripted_walk and not _walk_done and is_instance_valid(self):
		await get_tree().physics_frame
	_scripted_walk = false
	velocity = Vector2.ZERO
	if is_instance_valid(self) and global_position.distance_to(target) > arrive_dist:
		# Final snap if path was blocked
		global_position = target
		if has_method("reset_physics_interpolation"):
			reset_physics_interpolation()


## Snap body to world position (e.g. onto meditation pillow).
func place_at_global(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	# Avoid residual slide resolution shoving us off the mat.
	if has_method("reset_physics_interpolation"):
		reset_physics_interpolation()


## Single-frame sit/meditate pose. Call end_meditate_pose() to restore walk sheet.
func begin_meditate_pose() -> void:
	if sprite == null:
		sprite = get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	if not _meditating:
		_med_prev_tex = sprite.texture
		_med_prev_h = maxi(sprite.hframes, 1)
		_med_prev_v = maxi(sprite.vframes, 1)
		_med_prev_f = sprite.frame
		_med_prev_scale = sprite.scale
	var tex: Texture2D = _load_walk_texture("res://p2_meditate.png")
	if tex == null:
		tex = _load_walk_texture("res://p2_meditate_review.png")
	if tex == null:
		push_error("Meditate pose texture missing")
		return
	_meditating = true
	# Disable body collision so pillow StaticBody2D doesn't eject us sideways.
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col:
		col.disabled = true
	sprite.texture = tex
	sprite.hframes = 1
	sprite.vframes = 1
	sprite.frame = 0
	# Match on-screen height to one walk-sheet cell (prevents giant AI frames).
	var walk_cell_h: float = 65.0
	if _med_prev_tex != null and _med_prev_v > 0:
		walk_cell_h = float(_med_prev_tex.get_height()) / float(_med_prev_v)
	var med_h: float = float(tex.get_height())
	if med_h > 1.0:
		var s: float = walk_cell_h / med_h
		sprite.scale = _med_prev_scale * s


func end_meditate_pose() -> void:
	if not _meditating:
		return
	_meditating = false
	if sprite == null:
		return
	if _med_prev_tex != null:
		sprite.texture = _med_prev_tex
		sprite.hframes = _med_prev_h
		sprite.vframes = _med_prev_v
		var max_f: int = maxi(_med_prev_h * _med_prev_v - 1, 0)
		sprite.frame = mini(_med_prev_f, max_f)
	sprite.scale = _med_prev_scale
	_med_prev_tex = null
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col:
		col.disabled = not is_active


## Knockback away from blast, cartwheel anim, bounce off walls (collision mask).
func play_blast_cartwheel(from_pos: Vector2) -> void:
	var dir: Vector2 = global_position - from_pos
	if dir.length_squared() < 16.0:
		dir = Vector2.RIGHT.rotated(randf() * TAU)
	else:
		dir = dir.normalized()
	await _run_cartwheel_blast(dir)


## Same knockback/cartwheel/bounce, but flung in an explicit direction instead
## of away from a blast origin (e.g. the office floor trap's chosen direction).
func play_directional_cartwheel(dir: Vector2) -> void:
	if dir.length_squared() < 0.0001:
		dir = Vector2.UP
	await _run_cartwheel_blast(dir.normalized())


func _run_cartwheel_blast(dir: Vector2) -> void:
	if sprite == null or _blast_active:
		return
	var tex: Texture2D = load("res://p2_cartwheel.png")
	if tex == null:
		return

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


## Tells TurnManager we bounced off something mid-flight (pipe bomb, monkey
## burst, floor trap fling — anything routed through _run_cartwheel_blast) so
## it can add the stacking "Bumped Around" anxiety hit.
func _report_flight_bump() -> void:
	if _turn_manager == null or not is_instance_valid(_turn_manager):
		_turn_manager = get_node_or_null("/root/Main/TurnManager")
	if _turn_manager and _turn_manager.has_method("register_flight_bump"):
		_turn_manager.call("register_flight_bump")


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
		if _bump_cooldown_t > 0.0:
			_bump_cooldown_t -= delta
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
		if get_slide_collision_count() > 0 and _bump_cooldown_t <= 0.0:
			_bump_cooldown_t = BUMP_ANXIETY_COOLDOWN
			_report_flight_bump()
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

	if movement_locked or _meditating:
		# Do NOT move_and_slide — overlap resolve would shove us off the mat.
		velocity = Vector2.ZERO
		return

	var direction = Vector2.ZERO
	if _scripted_walk:
		var to_target: Vector2 = _walk_target - global_position
		var dist: float = to_target.length()
		if dist <= _walk_arrive_dist:
			_walk_done = true
			_scripted_walk = false
			velocity = Vector2.ZERO
			_set_idle_frame_from_last()
			return
		direction = to_target.normalized()
	else:
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
		_set_idle_frame_from_last()

	velocity = direction * speed * speed_mult
	var before: Vector2 = global_position
	move_and_slide()

	if _scripted_walk:
		var moved: float = before.distance_to(global_position)
		if moved < 0.5:
			_walk_stuck_t += delta
			if _walk_stuck_t >= 1.2:
				global_position = _walk_target
				if has_method("reset_physics_interpolation"):
					reset_physics_interpolation()
				_walk_done = true
				_scripted_walk = false
				velocity = Vector2.ZERO
		else:
			_walk_stuck_t = 0.0


func _set_idle_frame_from_last() -> void:
	if sprite == null:
		return
	if sprite.frame >= 12:
		sprite.frame = 12
	elif sprite.frame >= 8:
		sprite.frame = 8
	elif sprite.frame >= 4:
		sprite.frame = 4
	else:
		sprite.frame = 0
