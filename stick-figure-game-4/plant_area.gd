extends Area2D

## Plant trap interaction — smoke uses the SAME pipeline as the original monster anim:
## Sprite2D + hframes + AnimationPlayer keys on `.:frame` (see Stick Figure 4.tscn "monster").

@onready var label = $/root/Main/Plant/Label
@onready var player1_body = $/root/Main/Player1/Player1Body
@onready var player2_body = $/root/Main/Player2/Player2Body
@onready var turn_manager = $/root/Main/TurnManager
@onready var animation_player: AnimationPlayer = $"../AnimationPlayer"
@onready var plant_sprite: Sprite2D = $".."

# Pre-padded sheet: 16 cells of 358x508 (same cell size as PlantMonster.png)
const SMOKE_SHEET = preload("res://plnt03_monster_frames.png")
const SMOKE_HFRAMES := 16
const SMOKE_LENGTH := 1.6 # 16 * 0.1s, same discrete style as monster

var player_inside = null
var is_booby_trapped = false
var smoking := false

var _orig_texture: Texture2D
var _orig_hframes := 10
var _orig_scale := Vector2.ONE
var _orig_offset := Vector2.ZERO


func _ready():
	label.visible = false
	_orig_texture = plant_sprite.texture
	_orig_hframes = plant_sprite.hframes
	_orig_scale = plant_sprite.scale
	_orig_offset = plant_sprite.offset
	_ensure_smoke_animation()
	if animation_player:
		animation_player.play("normal")


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


func _ensure_smoke_animation() -> void:
	if animation_player == null:
		return
	# Library name "" is the default library in this scene
	var lib: AnimationLibrary = animation_player.get_animation_library("")
	if lib == null:
		lib = AnimationLibrary.new()
		animation_player.add_animation_library("", lib)
	if lib.has_animation("smoke"):
		return

	# Clone the structure of "monster": discrete value track on Plant.frame
	var anim := Animation.new()
	anim.resource_name = "smoke"
	anim.length = SMOKE_LENGTH
	anim.loop_mode = Animation.LOOP_LINEAR
	var track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track, NodePath(".:frame"))
	anim.value_track_set_update_mode(track, Animation.UPDATE_MODE_DISCRETE)
	var step := SMOKE_LENGTH / float(SMOKE_HFRAMES)
	for i in SMOKE_HFRAMES:
		anim.track_insert_key(track, i * step, i)
	lib.add_animation("smoke", anim)


func _start_smoke() -> void:
	if smoking:
		return
	smoking = true
	_ensure_smoke_animation()

	# Exact same Sprite2D setup as idle/monster — only swap sheet + hframes.
	plant_sprite.region_enabled = false
	plant_sprite.texture = SMOKE_SHEET
	plant_sprite.hframes = SMOKE_HFRAMES
	plant_sprite.vframes = 1
	plant_sprite.frame = 0
	plant_sprite.scale = _orig_scale
	plant_sprite.offset = _orig_offset
	plant_sprite.centered = true

	# Remove any leftover SmokeAnim child from prior attempts
	var old := plant_sprite.get_node_or_null("SmokeAnim")
	if old:
		old.queue_free()

	if animation_player:
		animation_player.process_mode = Node.PROCESS_MODE_INHERIT
		animation_player.active = true
		animation_player.play("smoke")


func _show_censor(duration: float) -> void:
	var plant_pos: Vector2 = plant_sprite.global_position
	var player_pos: Vector2 = plant_pos
	if player_inside != null:
		player_pos = player_inside.global_position
	var center: Vector2 = (plant_pos + player_pos) * 0.5
	var pad := Vector2(140, 160)
	var half := Vector2(
		maxf(absf(plant_pos.x - player_pos.x) * 0.5 + pad.x, 100.0),
		maxf(absf(plant_pos.y - player_pos.y) * 0.5 + pad.y, 110.0)
	)

	var root := Node2D.new()
	root.z_index = 100
	root.global_position = center
	get_tree().current_scene.add_child(root)

	var box := Polygon2D.new()
	box.color = Color.BLACK
	box.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	root.add_child(box)

	var lab := Label.new()
	lab.text = "CENSORED"
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
