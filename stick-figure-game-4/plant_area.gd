extends Area2D

@onready var label = $/root/Main/Plant/Label
@onready var player1_body = $/root/Main/Player1/Player1Body
@onready var player2_body = $/root/Main/Player2/Player2Body
@onready var turn_manager = $/root/Main/TurnManager
@onready var animation_player = $"../AnimationPlayer"
@onready var plant_sprite: Sprite2D = $".."

const GIF_FRAMES := 22
const GIF_FPS := 12.0

var player_inside = null
var is_booby_trapped = false
var smoking := false
var _gif_tex: Array = []
var _gif_i := 0
var _gif_t := 0.0
var _smoke_sprite: Sprite2D # separate node — never the multi-frame Plant sheet


func _ready():
	label.visible = false
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
			label.text = "Press E to booby trap"
			label.visible = true
		elif body == player2_body and turn_manager.current_turn == "Player2":
			label.text = "Press I to inspect or E to use"
			label.visible = true


func _on_body_exited(body):
	if body == player_inside:
		player_inside = null
		label.visible = false


func _input(event):
	if player_inside and event is InputEventKey and event.pressed:
		if player_inside == player1_body and turn_manager.current_turn == "Player1" and event.keycode == KEY_E:
			is_booby_trapped = true
			label.visible = false
			turn_manager.switch_turn()
		elif player_inside == player2_body and turn_manager.current_turn == "Player2":
			if event.keycode == KEY_I:
				if is_booby_trapped:
					label.text = "Trap found!"
					is_booby_trapped = false
					await get_tree().create_timer(1.0).timeout
					label.visible = false
				else:
					label.text = "No trap found."
					await get_tree().create_timer(1.0).timeout
					label.visible = false
				turn_manager.switch_turn()
			elif event.keycode == KEY_E:
				if is_booby_trapped:
					label.visible = false
					_start_smoke()
					await _show_censor(2.0)
				else:
					label.text = "Used plant, nothing happened."
					await get_tree().create_timer(1.0).timeout
					label.visible = false
				turn_manager.switch_turn()


func _start_smoke() -> void:
	if smoking:
		return
	smoking = true

	# Freeze/hide original Plant multi-frame sprite + its AnimationPlayer entirely.
	if animation_player:
		animation_player.stop()
		animation_player.active = false
	plant_sprite.visible = false

	# Dedicated single-frame sprite (GIF frames are full 480x640 plant poses).
	var main = plant_sprite.get_parent()
	_smoke_sprite = main.get_node_or_null("PlantSmokeGIF") as Sprite2D
	if _smoke_sprite == null:
		_smoke_sprite = Sprite2D.new()
		_smoke_sprite.name = "PlantSmokeGIF"
		_smoke_sprite.z_index = plant_sprite.z_index
		_smoke_sprite.centered = true
		_smoke_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		main.add_child(_smoke_sprite)

	_smoke_sprite.global_position = plant_sprite.global_position
	# ~same on-screen height as old plant (508 * 0.31 ≈ 158); GIF frame h=640
	_smoke_sprite.scale = Vector2(0.28, 0.28)
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
	var half := Vector2(
		maxf(absf(plant_pos.x - player_pos.x) * 0.5 + 140.0, 100.0),
		maxf(absf(plant_pos.y - player_pos.y) * 0.5 + 160.0, 110.0)
	)
	var root := Node2D.new()
	root.z_index = 100
	root.global_position = center
	get_tree().current_scene.add_child(root)
	var box := Polygon2D.new()
	box.color = Color.BLACK
	box.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	root.add_child(box)
	var lab := Label.new()
	lab.text = "CENSORED"
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ResourceLoader.exists("res://PressStart2P-Regular.ttf"):
		lab.add_theme_font_override("font", load("res://PressStart2P-Regular.ttf"))
	lab.add_theme_font_size_override("font_size", 22)
	lab.add_theme_color_override("font_color", Color.WHITE)
	lab.rotation = deg_to_rad(-35.0)
	lab.size = Vector2(half.x * 1.6, 40)
	lab.position = Vector2(-lab.size.x * 0.5, -20)
	root.add_child(lab)
	var t := 0.0
	var base: Vector2 = root.position
	while t < duration:
		await get_tree().process_frame
		t += get_process_delta_time()
		root.position = base + Vector2(randf_range(-3.5, 3.5), randf_range(-3.5, 3.5))
	root.queue_free()
