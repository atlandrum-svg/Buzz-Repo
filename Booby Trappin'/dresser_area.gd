extends Area2D

const UsableShimmer = preload("res://usable_shimmer.gd")
const ItemPrompts = preload("res://item_prompts.gd")

@onready var dresser: Sprite2D = get_parent() as Sprite2D
@onready var label = $/root/Main/Level/DresserProp/Label
@onready var player1_body = $/root/Main/Player1/Player1Body
@onready var player2_body = $/root/Main/Player2/Player2Body
@onready var turn_manager = $/root/Main/TurnManager
var player_inside = null
var is_booby_trapped = false
var _tex_closed: Texture2D
var _tex_open: Texture2D
var _tex_pipe: Texture2D
var _tex_explosion: Texture2D
var _tex_fannypack: Texture2D
var _bomb_sprite: Sprite2D
var _pack_sprite: Sprite2D

const EXPLOSION_HFRAMES := 8
const EXPLOSION_FPS := 12.0


func _ready():
	label.visible = false
	ItemPrompts.apply_font(label)
	UsableShimmer.attach(dresser)
	_tex_closed = dresser.texture
	_tex_open = load("res://dresser_open.png")
	_tex_pipe = load("res://pipe_bomb.png")
	_tex_explosion = load("res://explosion_strip.png")
	_tex_fannypack = _load_texture_any("res://fannypack.png")


## Textures may not be imported yet on a fresh checkout — fall back to raw load.
func _load_texture_any(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var t: Variant = load(path)
		if t is Texture2D:
			return t as Texture2D
	var abs_path: String = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img:
			return ImageTexture.create_from_image(img)
	return null


func _show_open_drawer() -> void:
	if _tex_open:
		dresser.texture = _tex_open
	dresser.self_modulate = Color.WHITE


func _dresser_half() -> Vector2:
	if dresser.texture == null:
		return Vector2(40, 60)
	return dresser.texture.get_size() * dresser.scale * 0.5


## Pipe bomb pops from open top drawer, small air arc, lands right of dresser, one bounce.
func _eject_pipe_bomb() -> void:
	if _tex_pipe == null:
		return
	if _bomb_sprite and is_instance_valid(_bomb_sprite):
		_bomb_sprite.queue_free()

	var half := _dresser_half()
	var start := dresser.global_position + Vector2(0.0, -half.y * 0.12)
	var land := dresser.global_position + Vector2(half.x + 36.0, half.y * 0.88)
	var apex := Vector2((start.x + land.x) * 0.55, minf(start.y, land.y) - 42.0)

	var bomb := Sprite2D.new()
	bomb.name = "PipeBombEject"
	bomb.texture = _tex_pipe
	bomb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bomb.z_index = dresser.z_index + 2
	var tex_w := float(_tex_pipe.get_width())
	# 30% smaller than previous prop scale
	bomb.scale = Vector2.ONE * (48.0 * 0.7 / maxf(tex_w, 1.0))
	bomb.global_position = start
	bomb.rotation = -0.3
	dresser.get_parent().add_child(bomb)
	_bomb_sprite = bomb

	var bounce := land + Vector2(10.0, -16.0)
	var rest := land + Vector2(14.0, 0.0)
	var tw := create_tween()
	# Arc out of top drawer
	tw.tween_property(bomb, "global_position", apex, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Fall to ground (right of dresser)
	tw.tween_property(bomb, "global_position", land, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Single small bounce
	tw.tween_property(bomb, "global_position", bounce, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(bomb, "global_position", rest, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(bomb, "rotation", 0.45, 0.14)
	await tw.finished

	# Hold 0.5s, then explode (bomb vanishes when explosion starts)
	await get_tree().create_timer(0.5).timeout
	var boom_pos := bomb.global_position
	if is_instance_valid(bomb):
		bomb.queue_free()
	_bomb_sprite = null
	# Round evaluation flag (fire department message after 3 uses).
	if turn_manager and turn_manager.has_method("mark_pipe_bomb_detonated"):
		turn_manager.mark_pipe_bomb_detonated()
	# Blast FX + physics cartwheel knockback away from bomb (bounce on walls)
	_gib_roomate(boom_pos)
	_play_explosion_at(boom_pos)
	await player2_body.play_blast_cartwheel(boom_pos)


## Clean dresser: a fanny pack pops out on the same arc + bounce as the pipe
## bomb, rests on the floor for a beat, then goes into the bag (-5 anxiety).
func _eject_fannypack() -> void:
	if _tex_fannypack == null:
		# No art yet — still give the item so the round does not stall.
		if turn_manager and turn_manager.has_method("add_inventory_fannypack"):
			turn_manager.add_inventory_fannypack()
		return
	if _pack_sprite and is_instance_valid(_pack_sprite):
		_pack_sprite.queue_free()

	var half := _dresser_half()
	var start := dresser.global_position + Vector2(0.0, -half.y * 0.12)
	var land := dresser.global_position + Vector2(half.x + 36.0, half.y * 0.88)
	var apex := Vector2((start.x + land.x) * 0.55, minf(start.y, land.y) - 42.0)

	var pack := Sprite2D.new()
	pack.name = "FannyPackEject"
	pack.texture = _tex_fannypack
	pack.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pack.z_index = dresser.z_index + 2
	var tex_w := float(_tex_fannypack.get_width())
	pack.scale = Vector2.ONE * (48.0 * 0.7 / maxf(tex_w, 1.0))
	pack.global_position = start
	pack.rotation = -0.3
	dresser.get_parent().add_child(pack)
	_pack_sprite = pack

	var bounce := land + Vector2(10.0, -16.0)
	var rest := land + Vector2(14.0, 0.0)
	var tw := create_tween()
	tw.tween_property(pack, "global_position", apex, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(pack, "global_position", land, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(pack, "global_position", bounce, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(pack, "global_position", rest, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(pack, "rotation", 0.45, 0.14)
	await tw.finished

	# Sits on the floor for a second so the player registers it, then bagged.
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(pack):
		pack.queue_free()
	_pack_sprite = null
	if turn_manager and turn_manager.has_method("add_inventory_fannypack"):
		turn_manager.add_inventory_fannypack()
	if turn_manager and turn_manager.has_method("set_status_message"):
		turn_manager.set_status_message("A fanny pack. Utility is its own kind of confidence.")


## Lizard remnant + green chunks flung away from boom_pos.
func _gib_roomate(boom_pos: Vector2) -> void:
	var roomate := get_node_or_null("/root/Main/Roomate") as Sprite2D
	if roomate == null:
		roomate = get_node_or_null("/root/Main/Level/Roomate") as Sprite2D
	if roomate == null:
		return
	if roomate.has_method("gib_from_blast"):
		roomate.gib_from_blast(boom_pos)
		return
	# Fallback: old roommate exploded art.
	if roomate.has_method("stop_for_gib"):
		roomate.stop_for_gib()
	var tex: Texture2D = load("res://roomate_exploded.png") as Texture2D
	if tex == null:
		return
	roomate.texture = tex
	roomate.hframes = 1
	roomate.vframes = 1
	roomate.frame = 0
	roomate.scale = Vector2.ONE
	roomate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _play_explosion_at(pos: Vector2) -> void:
	if _tex_explosion == null:
		return
	var fx := Sprite2D.new()
	fx.name = "PipeBombExplosion"
	fx.texture = _tex_explosion
	fx.hframes = EXPLOSION_HFRAMES
	fx.frame = 0
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.z_index = dresser.z_index + 3
	fx.global_position = pos
	# Frame is strip_w/8 — scale blast to ~room prop size
	var cell_w := float(_tex_explosion.get_width()) / float(EXPLOSION_HFRAMES)
	fx.scale = Vector2.ONE * (96.0 / maxf(cell_w, 1.0))
	dresser.get_parent().add_child(fx)

	var step := 1.0 / EXPLOSION_FPS
	for i in EXPLOSION_HFRAMES:
		if not is_instance_valid(fx):
			return
		fx.frame = i
		await get_tree().create_timer(step).timeout
	if is_instance_valid(fx):
		fx.queue_free()


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
			UsableShimmer.mark_trapped_p1(dresser)
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
				UsableShimmer.mark_used_p2(dresser)
				if is_booby_trapped:
					label.text = ItemPrompts.TRAP_TRIGGERED
					player2_body.set_movement_locked(true)
					_show_open_drawer()
					is_booby_trapped = false
					await _eject_pipe_bomb()
					# Hold after explosion clears
					await get_tree().create_timer(0.2).timeout
					if turn_manager and turn_manager.has_method("apply_anxiety"):
						turn_manager.apply_anxiety("ptsd")
						turn_manager.set_status_message("You keep hearing it. +10 anxiety.")
					player2_body.set_movement_locked(false)
					label.visible = false
				else:
					label.visible = false
					player2_body.set_movement_locked(true)
					_show_open_drawer()
					await _eject_fannypack()
					player2_body.set_movement_locked(false)
				turn_manager.consume_p2_use()
