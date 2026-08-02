extends Area2D

@onready var label = $/root/Main/Plant/Label
@onready var player1_body = $/root/Main/Player1/Player1Body
@onready var player2_body = $/root/Main/Player2/Player2Body
@onready var turn_manager = $/root/Main/TurnManager
@onready var animation_player = $"../AnimationPlayer"
@onready var plant_sprite: Sprite2D = $".."

const SMOKE_SHEET = preload("res://plnt03-Sheet.png")
const SMOKE_FRAMES := 16
const SMOKE_FPS := 10.0
const SMOKE_FW := 66
const SMOKE_FH := 64

var player_inside = null
var is_booby_trapped = false
var smoking := false
var _smoke_anim: AnimatedSprite2D
var _orig_texture: Texture2D
var _orig_scale := Vector2.ONE
var _orig_offset := Vector2.ZERO
var _orig_hframes := 10


func _ready():
	label.visible = false
	_orig_texture = plant_sprite.texture
	_orig_scale = plant_sprite.scale
	_orig_offset = plant_sprite.offset
	_orig_hframes = plant_sprite.hframes
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


func _start_smoke() -> void:
	if smoking:
		return
	smoking = true

	# Kill the old monster AnimationPlayer completely so it cannot drive frames.
	if animation_player:
		animation_player.stop()
		animation_player.active = false
		animation_player.process_mode = Node.PROCESS_MODE_DISABLED

	# Hide the multi-frame Sprite2D (this is what was showing the full strip).
	plant_sprite.texture = null
	plant_sprite.hframes = 1
	plant_sprite.vframes = 1
	plant_sprite.frame = 0
	plant_sprite.region_enabled = false
	plant_sprite.offset = Vector2.ZERO

	# One cell per AtlasTexture → AnimatedSprite2D.play (same idea as working plant anim).
	if _smoke_anim == null:
		_smoke_anim = AnimatedSprite2D.new()
		_smoke_anim.name = "SmokeAnim"
		_smoke_anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_smoke_anim.centered = true
		plant_sprite.add_child(_smoke_anim)

		var frames := SpriteFrames.new()
		frames.add_animation("smoke")
		frames.set_animation_loop("smoke", true)
		frames.set_animation_speed("smoke", SMOKE_FPS)
		for i in SMOKE_FRAMES:
			var at := AtlasTexture.new()
			at.atlas = SMOKE_SHEET
			at.region = Rect2(i * SMOKE_FW, 0, SMOKE_FW, SMOKE_FH)
			at.filter_clip = true
			frames.add_frame("smoke", at)
		_smoke_anim.sprite_frames = frames

	# Parent Plant already scaled for huge monster frames; counter-scale child so one cell is room-sized.
	# Display target ~ old monster width on screen: 358 * 0.32 ≈ 114px; cell is 66px → scale ≈ 1.73 on root.
	# Root scale stays _orig_scale; child scale compensates sheet cell vs old frame.
	var cell_scale := (358.0 / float(SMOKE_FW))
	_smoke_anim.scale = Vector2(cell_scale, cell_scale)
	_smoke_anim.visible = true
	_smoke_anim.play("smoke")


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
