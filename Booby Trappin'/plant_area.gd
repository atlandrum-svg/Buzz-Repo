extends Area2D

const UsableShimmer = preload("res://usable_shimmer.gd")
const ItemPrompts = preload("res://item_prompts.gd")

@onready var label = $/root/Main/Plant/Label
@onready var player1_body = $/root/Main/Player1/Player1Body
@onready var player2_body = $/root/Main/Player2/Player2Body
@onready var turn_manager = $/root/Main/TurnManager
@onready var animation_player = $"../AnimationPlayer"
@onready var plant_sprite: Sprite2D = $".."

const GIF_FRAMES := 22
const GIF_FPS := 12.0

## Extra nudge if needed (usually leave 0 so smoke matches Plant exactly).
@export var smoke_offset := Vector2.ZERO

var player_inside = null
var is_booby_trapped = false
var smoking := false
var _gif_tex: Array = []
var _gif_i := 0
var _gif_t := 0.0
var _smoke_sprite: Sprite2D # separate node — never the multi-frame Plant sheet
var _tex_gun: Texture2D
var _gun_sprite: Sprite2D
var _gun_looted := false


func _ready():
	label.visible = false
	ItemPrompts.apply_font(label)
	UsableShimmer.attach(plant_sprite)
	_tex_gun = load("res://handgun.png")
	for i in GIF_FRAMES:
		_gif_tex.append(load("res://gif_smoke/g_%02d.png" % i))
	if animation_player:
		animation_player.play("normal")


func _process(delta: float) -> void:
	if not smoking or _smoke_sprite == null:
		return
	_gif_t += delta
	var step := 1.0 / GIF_FPS
	while _gif_t >= step:
		_gif_t -= step
		_gif_i = (_gif_i + 1) % GIF_FRAMES
		_smoke_sprite.texture = _gif_tex[_gif_i]


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
		label.visible = false


func _input(event):
	if player_inside and event is InputEventKey and event.pressed:
		if player_inside == player1_body and turn_manager.current_turn == "Player1" and event.keycode == KEY_E:
			if is_booby_trapped:
				return
			if not turn_manager.consume_trap():
				return
			is_booby_trapped = true
			label.visible = false
			UsableShimmer.mark_trapped_p1(plant_sprite)
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
				UsableShimmer.mark_used_p2(plant_sprite)
				if is_booby_trapped:
					label.visible = false
					player2_body.set_movement_locked(true)
					# 1) Full original plant (monster) anim
					plant_sprite.self_modulate = Color.WHITE
					if animation_player:
						animation_player.active = true
						animation_player.play("monster")
						await animation_player.animation_finished
					# 2) 1s pause
					await get_tree().create_timer(1.0).timeout
					# 3) Smoke + censor — stay locked through first full smoke loop
					_start_smoke()
					var first_smoke := float(GIF_FRAMES) / GIF_FPS
					var t0 := Time.get_ticks_msec()
					await _show_censor(2.0)
					var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
					if elapsed < first_smoke:
						await get_tree().create_timer(first_smoke - elapsed).timeout
					# Whatever that was, you are not telling anyone. +10 anxiety.
					if turn_manager and turn_manager.has_method("apply_anxiety"):
						turn_manager.apply_anxiety("emasculation")
						turn_manager.set_status_message(
							"The plant did something to you. You will not be describing it."
						)
					player2_body.set_movement_locked(false)
				else:
					if not _gun_looted:
						label.visible = false
						player2_body.set_movement_locked(true)
						await _eject_gun_to_inventory()
						player2_body.set_movement_locked(false)
					else:
						label.text = ItemPrompts.used_nothing("Plant")
						await get_tree().create_timer(1.0).timeout
						label.visible = false
				turn_manager.consume_p2_use()


## World-space feet under the plant (PlantArea collider sits on the pot base).
func _plant_feet() -> Vector2:
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col:
		return col.global_position
	# Fallback: PlantMonster cell feet ~ local y 257
	return plant_sprite.to_global(Vector2(0.0, 257.0))


## Gun pops from plant, small air arc + bounce (same motion as pipe bomb), rests 1s, then inventory.
func _eject_gun_to_inventory() -> void:
	if _tex_gun == null:
		if turn_manager and turn_manager.has_method("add_inventory_gun"):
			turn_manager.add_inventory_gun()
		_gun_looted = true
		return
	if _gun_sprite and is_instance_valid(_gun_sprite):
		_gun_sprite.queue_free()

	# Fixed world land spot (Joshua: x=175, y=-25).
	var feet := _plant_feet()
	var land := Vector2(175.0, -25.0)
	var start := feet + Vector2(-8.0, -40.0)
	var apex := Vector2((start.x + land.x) * 0.5, minf(start.y, land.y) - 36.0)

	var gun := Sprite2D.new()
	gun.name = "GunEject"
	gun.texture = _tex_gun
	gun.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	gun.z_index = plant_sprite.z_index + 2
	var tex_w := float(_tex_gun.get_width())
	gun.scale = Vector2.ONE * (48.0 * 0.7 / maxf(tex_w, 1.0))
	gun.global_position = start
	gun.rotation = -0.3
	plant_sprite.get_parent().add_child(gun)
	_gun_sprite = gun

	var bounce := land + Vector2(-8.0, -14.0)
	var rest := land + Vector2(-10.0, 0.0)
	var tw := create_tween()
	tw.tween_property(gun, "global_position", apex, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(gun, "global_position", land, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(gun, "global_position", bounce, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(gun, "global_position", rest, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(gun, "rotation", 0.45, 0.14)
	await tw.finished

	# Stay on ground 1s, then vanish into inventory
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(gun):
		gun.queue_free()
	_gun_sprite = null
	_gun_looted = true
	if turn_manager and turn_manager.has_method("add_inventory_gun"):
		turn_manager.add_inventory_gun()


func _start_smoke() -> void:
	if smoking:
		return
	smoking = true

	# Freeze original Plant multi-frame anim (keep node for transform reference).
	if animation_player:
		animation_player.stop()
		animation_player.active = false
	# Hide plant art only — do NOT set visible=false (would hide children / break pairing).
	plant_sprite.self_modulate = Color(1, 1, 1, 0)

	# Smoke sits on Main at the same world transform as Plant (same spot as idle anim).
	var main = plant_sprite.get_parent()
	_smoke_sprite = main.get_node_or_null("PlantSmokeGIF") as Sprite2D
	if _smoke_sprite == null:
		_smoke_sprite = Sprite2D.new()
		_smoke_sprite.name = "PlantSmokeGIF"
		_smoke_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		main.add_child(_smoke_sprite)

	# PlantMonster cell = 358x508; GIF frame = 480x640 — scale so one pose matches on screen.
	const PLANT_FW := 358.0
	const PLANT_FH := 508.0
	const GIF_W := 480.0
	const GIF_H := 640.0
	_smoke_sprite.z_index = plant_sprite.z_index
	_smoke_sprite.centered = plant_sprite.centered
	_smoke_sprite.offset = plant_sprite.offset
	_smoke_sprite.global_position = plant_sprite.global_position + smoke_offset
	_smoke_sprite.global_rotation = plant_sprite.global_rotation
	_smoke_sprite.scale = Vector2(
		plant_sprite.global_scale.x * (PLANT_FW / GIF_W),
		plant_sprite.global_scale.y * (PLANT_FH / GIF_H)
	)
	_smoke_sprite.visible = true
	_gif_i = 0
	_gif_t = 0.0
	_smoke_sprite.texture = _gif_tex[0]


func _show_censor(duration: float) -> void:
	var plant_pos: Vector2 = plant_sprite.global_position
	var player_pos: Vector2 = plant_pos
	if player_inside != null:
		player_pos = player_inside.global_position
	var center: Vector2 = (plant_pos + player_pos) * 0.5
	# Rectangular censor (wider than tall), larger than the last square version
	var half_w := maxf(absf(plant_pos.x - player_pos.x) * 0.5 + 90.0, 85.0)
	var half_h := maxf(absf(plant_pos.y - player_pos.y) * 0.5 + 55.0, 50.0)
	var root := Node2D.new()
	root.z_index = 100
	root.global_position = center
	get_tree().current_scene.add_child(root)
	var box := Polygon2D.new()
	box.color = Color.BLACK
	box.polygon = PackedVector2Array([
		Vector2(-half_w, -half_h), Vector2(half_w, -half_h),
		Vector2(half_w, half_h), Vector2(-half_w, half_h),
	])
	root.add_child(box)
	var lab := Label.new()
	lab.text = "CENSORED"
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ResourceLoader.exists("res://PressStart2P-Regular.ttf"):
		lab.add_theme_font_override("font", load("res://PressStart2P-Regular.ttf"))
	lab.add_theme_font_size_override("font_size", 14)
	lab.add_theme_color_override("font_color", Color.WHITE)
	lab.rotation = deg_to_rad(-35.0)
	lab.size = Vector2(half_w * 1.6, 28)
	lab.position = Vector2(-lab.size.x * 0.5, -14)
	root.add_child(lab)
	var t := 0.0
	var base: Vector2 = root.position
	while t < duration:
		await get_tree().process_frame
		t += get_process_delta_time()
		root.position = base + Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
	root.queue_free()
