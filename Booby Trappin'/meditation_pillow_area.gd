extends Area2D

const UsableShimmer = preload("res://usable_shimmer.gd")
const ItemPrompts = preload("res://item_prompts.gd")

@onready var pillow: Sprite2D = get_parent() as Sprite2D
@onready var label = $/root/Main/Level/MeditationPillow/Label
@onready var player1_body = $/root/Main/Player1/Player1Body
@onready var player2_body = $/root/Main/Player2/Player2Body
@onready var turn_manager = $/root/Main/TurnManager
var player_inside = null
var is_booby_trapped = false
var _busy := false

const DEMON_SCALE := 0.11
## 2× slower than original 0.85s approach.
const DEMON_FLOAT_SEC := 1.7
## Start far off-screen left of the sitter.
const DEMON_START_X := -280.0
const DEMON_SHRINK_SEC := 0.32
const POP_LIFE_SEC := 0.4
const CLEAN_SIT_SEC := 1.0
## Visual center of sit pose on the cushion (pillow origin = texture center).
const SIT_OFFSET := Vector2(0, -4)


func _ready():
	label.visible = false
	ItemPrompts.apply_font(label)
	UsableShimmer.attach(pillow)


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
		if not _busy:
			label.visible = false


func _input(event):
	if _busy or player_inside == null:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if player_inside == player1_body and turn_manager.current_turn == "Player1" and event.keycode == KEY_E:
		if is_booby_trapped:
			return
		if not turn_manager.consume_trap():
			return
		is_booby_trapped = true
		label.visible = false
		UsableShimmer.mark_trapped_p1(pillow)
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
			await _p2_use_mat()


func _p2_use_mat() -> void:
	_busy = true
	UsableShimmer.mark_used_p2(pillow)
	var trapped: bool = is_booby_trapped
	if trapped:
		is_booby_trapped = false
		label.text = ItemPrompts.TRAP_TRIGGERED
		label.visible = true
	else:
		label.visible = false

	# Instant snap to exact mat center + meditation pose (any approach angle).
	var sit_pos: Vector2 = _mat_sit_global()
	player2_body.set_movement_locked(true)
	if player2_body.has_method("begin_meditate_pose"):
		player2_body.begin_meditate_pose()
	if player2_body.has_method("place_at_global"):
		player2_body.place_at_global(sit_pos)
	else:
		player2_body.global_position = sit_pos
	# Re-assert after a frame in case anything else moved us.
	await get_tree().physics_frame
	if player2_body.has_method("place_at_global"):
		player2_body.place_at_global(sit_pos)
	else:
		player2_body.global_position = sit_pos

	if trapped:
		await _play_demon_attack(player2_body)
		# Possession: +5 anxiety now, and it hijacks the fireman encounter later.
		if turn_manager and turn_manager.has_method("apply_anxiety"):
			turn_manager.apply_anxiety("vishnu_demon")
		if turn_manager and turn_manager.has_method("set_status_message"):
			turn_manager.set_status_message(
				"You have been possessed by a 4 dimensional demon..."
			)
	else:
		await get_tree().create_timer(CLEAN_SIT_SEC).timeout
		# A clean sit is the single best thing in the apartment. -20 anxiety.
		if turn_manager and turn_manager.has_method("apply_anxiety"):
			turn_manager.apply_anxiety("zen")
		if turn_manager and turn_manager.has_method("set_status_message"):
			turn_manager.set_status_message(
				"You sat on the mat and nothing came out of the walls."
			)

	# Resume walking from the mat center (not where collision might have shoved us).
	sit_pos = _mat_sit_global()
	_snap_p2(sit_pos)
	if player2_body.has_method("end_meditate_pose"):
		player2_body.end_meditate_pose()
	_snap_p2(sit_pos)
	player2_body.set_movement_locked(false)
	label.visible = false
	turn_manager.consume_p2_use()
	_busy = false


func _mat_sit_global() -> Vector2:
	# Pillow Sprite2D origin is the texture center (= visual center of the mat).
	return pillow.global_position + SIT_OFFSET


func _snap_p2(pos: Vector2) -> void:
	if player2_body.has_method("place_at_global"):
		player2_body.place_at_global(pos)
	else:
		player2_body.global_position = pos
		player2_body.velocity = Vector2.ZERO


## Demon appears far left of P2, bobs while floating onto them, holds 0.2s, vanishes.
func _play_demon_attack(p2: Node2D) -> void:
	var tex: Texture2D = null
	if ResourceLoader.exists("res://meditation_demon.png"):
		tex = load("res://meditation_demon.png")
	if tex == null:
		var abs_path := ProjectSettings.globalize_path("res://meditation_demon.png")
		if FileAccess.file_exists(abs_path):
			var img := Image.load_from_file(abs_path)
			if img:
				tex = ImageTexture.create_from_image(img)
	if tex == null:
		await get_tree().create_timer(0.5).timeout
		return

	var demon := Sprite2D.new()
	demon.name = "MeditationDemon"
	demon.texture = tex
	demon.z_index = 30
	demon.centered = true
	demon.scale = Vector2(DEMON_SCALE, DEMON_SCALE)
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_parent().get_parent()
	host.add_child(demon)

	# Anchor on mat center so path is stable even if body drifts.
	var sit: Vector2 = _mat_sit_global()
	var target: Vector2 = sit + Vector2(0, -18)
	var start: Vector2 = sit + Vector2(DEMON_START_X, -18)
	demon.global_position = start

	var t := 0.0
	while t < DEMON_FLOAT_SEC:
		await get_tree().process_frame
		var dt: float = get_process_delta_time()
		t += dt
		var u: float = clampf(t / DEMON_FLOAT_SEC, 0.0, 1.0)
		# ease-in-out
		var s: float = u * u * (3.0 - 2.0 * u)
		var base: Vector2 = start.lerp(target, s)
		# Slower path → keep same bob cycles over longer duration
		var bob: float = sin(u * TAU * 2.0) * 10.0
		demon.global_position = base + Vector2(0, bob)
		# Keep P2 parked on mat center during the approach.
		_snap_p2(sit)

	demon.global_position = target
	_snap_p2(sit)
	# On top of player: shrink → shiny plink pop
	await _demon_shrink_and_pop(demon, target)
	_snap_p2(sit)


## Shrink demon to a point, then a little shiny *plink* pop.
func _demon_shrink_and_pop(demon: Sprite2D, at: Vector2) -> void:
	if not is_instance_valid(demon):
		return
	var start_scale: Vector2 = demon.scale
	var t := 0.0
	while t < DEMON_SHRINK_SEC and is_instance_valid(demon):
		await get_tree().process_frame
		t += get_process_delta_time()
		var u: float = clampf(t / DEMON_SHRINK_SEC, 0.0, 1.0)
		# ease-in shrink
		var s: float = 1.0 - u * u
		demon.scale = start_scale * maxf(s, 0.02)
		demon.modulate = Color(1.0, 1.0 - 0.2 * u, 1.0 - 0.4 * u, 1.0 - 0.15 * u)
		# slight spin for juice
		demon.rotation = u * 0.6

	var pop_pos: Vector2 = at
	if is_instance_valid(demon):
		pop_pos = demon.global_position
		demon.queue_free()

	await _shiny_plink_pop(pop_pos)


func _shiny_plink_pop(at: Vector2) -> void:
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_parent().get_parent()

	# Bright core flash
	var flash := Polygon2D.new()
	flash.name = "DemonPlink"
	flash.color = Color(1.0, 0.98, 0.7, 1.0)
	flash.polygon = PackedVector2Array([
		Vector2(0, -10), Vector2(3, -3), Vector2(10, 0), Vector2(3, 3),
		Vector2(0, 10), Vector2(-3, 3), Vector2(-10, 0), Vector2(-3, -3),
	])
	flash.z_index = 40
	host.add_child(flash)
	flash.global_position = at

	# Spark burst
	var parts := CPUParticles2D.new()
	parts.one_shot = true
	parts.explosiveness = 1.0
	parts.amount = 16
	parts.lifetime = 0.35
	parts.emitting = true
	parts.direction = Vector2(0, -1)
	parts.spread = 180.0
	parts.initial_velocity_min = 50.0
	parts.initial_velocity_max = 110.0
	parts.gravity = Vector2(0, 120)
	parts.scale_amount_min = 1.5
	parts.scale_amount_max = 3.5
	parts.color = Color(1.0, 0.95, 0.55, 1.0)
	parts.z_index = 41
	host.add_child(parts)
	parts.global_position = at

	# Flash expand + fade (= visual *plink*)
	var t := 0.0
	while t < POP_LIFE_SEC:
		await get_tree().process_frame
		t += get_process_delta_time()
		var u: float = clampf(t / POP_LIFE_SEC, 0.0, 1.0)
		if is_instance_valid(flash):
			flash.scale = Vector2.ONE * (1.0 + u * 2.2)
			flash.modulate.a = 1.0 - u
			flash.rotation = u * 1.2

	if is_instance_valid(flash):
		flash.queue_free()
	if is_instance_valid(parts):
		parts.queue_free()
