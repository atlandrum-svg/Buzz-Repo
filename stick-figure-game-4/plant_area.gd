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


func _ready():
	label.visible = false
	ItemPrompts.apply_font(label)
	UsableShimmer.attach(plant_sprite)
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
			label.text = ItemPrompts.INSPECT_OR_USE
			label.visible = true


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
			if event.keycode == KEY_I:
				UsableShimmer.mark_used_p2(plant_sprite)
				if is_booby_trapped:
					label.text = ItemPrompts.TRAP_FOUND
					is_booby_trapped = false
					await get_tree().create_timer(1.0).timeout
					label.visible = false
				else:
					label.text = ItemPrompts.NO_TRAP
					await get_tree().create_timer(1.0).timeout
					label.visible = false
				turn_manager.consume_p2_use()
			elif event.keycode == KEY_E:
				UsableShimmer.mark_used_p2(plant_sprite)
				if is_booby_trapped:
					label.visible = false
					# 1) Full original plant (monster) anim
					plant_sprite.self_modulate = Color.WHITE
					if animation_player:
						animation_player.active = true
						animation_player.play("monster")
						await animation_player.animation_finished
					# 2) 1s pause
					await get_tree().create_timer(1.0).timeout
					# 3) Smoke + censor box
					_start_smoke()
					await _show_censor(2.0)
				else:
					label.text = ItemPrompts.used_nothing("Plant")
					await get_tree().create_timer(1.0).timeout
					label.visible = false
				turn_manager.consume_p2_use()


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
