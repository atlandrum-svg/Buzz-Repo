extends Sprite2D
## Pet lizard (skitterscale). Random walk. Pipe bomb → blood/burn remnant (no chunks).
## Avoids LizardOnlyBlocker (collision_layer 2) — players ignore that layer.

const TEX_PATH := "res://skitterscale-sheet.png"
const TEX_GUN_PATH := "res://skitterscale_gun_sheet.png"
const TEX_REMNANT := "res://skitterscale_remnant.png"
const TEX_HANDGUN := "res://handgun.png"
const HFRAMES := 4
const VFRAMES := 4
const ANIM_SPEED := 0.11
const WALK_SPEED := 38.0
const ROW_DOWN := 0
const ROW_LEFT := 1
const ROW_RIGHT := 2
const ROW_UP := 3
const ROOM_MIN_X := -200.0
const X_MAX := -25.0
const Y_LINE := -125.0
const Y_FLOOR := 240.0
const START_POS := Vector2(-82.0, -100.0)
const DRAW_SCALE := 0.675
const PILL_SPEED_MULT := 5.0
## Matches StaticBody2D LizardOnlyBlocker.collision_layer in the main scene.
const LIZARD_BLOCK_MASK := 2
const HIT_SIZE := Vector2(14.0, 12.0)
const CORPSE_GUN_RANGE := 36.0
const CORPSE_GUN_PROMPT := "Press E to pick up gun"

var _anim_frame: int = 0
var _anim_t: float = 0.0
var _facing_row: int = ROW_LEFT
var _dir: Vector2 = Vector2.LEFT
var _dir_t: float = 0.0
var _pause_t: float = 0.0
var _gibbed: bool = false
## Dead from booby-trapped pills (upside-down start pose). Bomb gib still works after.
var _dead_from_pills: bool = false
var _has_gun: bool = false
var _speed_mult: float = 1.0
var _probe: RectangleShape2D
var _gun_prompt: Label
var _player2_near: bool = false
## Gun dropped on ground after bomb gibs a lizard that still held it.
var _ground_gun: Sprite2D
var _ground_gun_near: bool = false


func _ready() -> void:
	visible = true
	z_index = 4
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tex: Texture2D = load(TEX_PATH) as Texture2D
	if tex != null:
		texture = tex
	hframes = HFRAMES
	vframes = VFRAMES
	scale = Vector2(DRAW_SCALE, DRAW_SCALE)
	flip_v = false
	_disable_collision()
	_probe = RectangleShape2D.new()
	_probe.size = HIT_SIZE
	position = START_POS
	_facing_row = ROW_LEFT
	_anim_frame = 0
	_apply_frame()
	_pick_dir()
	_pause_t = randf_range(0.2, 0.8)
	set_process(true)


func is_alive() -> bool:
	return not _gibbed and not _dead_from_pills


## Clean pills → 5× roam (zippy). Booby-trapped → die upside-down, frozen.
func give_pills(trapped: bool) -> void:
	if not is_alive():
		return
	if trapped:
		_die_from_pills()
	else:
		_speed_mult = PILL_SPEED_MULT


## Equips gun sheet (tail holds handgun). Keeps current facing/walk.
func give_gun() -> void:
	if not is_alive():
		return
	_has_gun = true
	var tex: Texture2D = load(TEX_GUN_PATH) as Texture2D
	if tex == null:
		tex = load(TEX_PATH) as Texture2D
	if tex != null:
		texture = tex
	hframes = HFRAMES
	vframes = VFRAMES
	flip_v = false
	scale = Vector2(DRAW_SCALE, DRAW_SCALE)
	_apply_frame()


func _die_from_pills() -> void:
	_dead_from_pills = true
	_speed_mult = 1.0
	# Keep process only if gun can be reclaimed from the corpse.
	set_process(_has_gun)
	# Sheet: first column, second row (row1/col0 → frame 4), upside down (legs in air).
	# Prefer gun sheet if equipped so death pose still matches.
	var path: String = TEX_GUN_PATH if _has_gun else TEX_PATH
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		tex = load(TEX_PATH) as Texture2D
	if tex != null:
		texture = tex
	hframes = HFRAMES
	vframes = VFRAMES
	_facing_row = ROW_LEFT
	_anim_frame = 0
	frame = ROW_LEFT * HFRAMES + 0 # frame 4
	flip_v = true
	scale = Vector2(DRAW_SCALE, DRAW_SCALE)
	if _has_gun:
		_ensure_gun_prompt()


func _ensure_gun_prompt() -> void:
	if _gun_prompt != null and is_instance_valid(_gun_prompt):
		return
	var lbl := Label.new()
	lbl.name = "GunPickupPrompt"
	lbl.text = CORPSE_GUN_PROMPT
	lbl.visible = false
	lbl.z_index = 20
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(-90.0, -70.0)
	lbl.add_theme_font_size_override("font_size", 48)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	# Cancel lizard DRAW_SCALE so prompt matches world item text size.
	var s: float = maxf(absf(scale.x), 0.001)
	lbl.scale = Vector2(0.18 / s, 0.18 / s)
	add_child(lbl)
	_gun_prompt = lbl


func can_reclaim_gun() -> bool:
	return _dead_from_pills and _has_gun and not _gibbed


func has_ground_gun() -> bool:
	return _ground_gun != null and is_instance_valid(_ground_gun)


## Player recovers gun from dead lizard → inventory + original (no-gun) death pose.
func reclaim_gun() -> void:
	if not can_reclaim_gun():
		return
	_has_gun = false
	_player2_near = false
	if _gun_prompt != null and is_instance_valid(_gun_prompt):
		_gun_prompt.visible = false
	var tex: Texture2D = load(TEX_PATH) as Texture2D
	if tex != null:
		texture = tex
	hframes = HFRAMES
	vframes = VFRAMES
	_facing_row = ROW_LEFT
	_anim_frame = 0
	frame = ROW_LEFT * HFRAMES + 0
	flip_v = true
	scale = Vector2(DRAW_SCALE, DRAW_SCALE)
	_add_gun_to_inventory()
	set_process(false)


func reclaim_ground_gun() -> void:
	if not has_ground_gun():
		return
	_ground_gun_near = false
	if _gun_prompt != null and is_instance_valid(_gun_prompt):
		_gun_prompt.visible = false
		if _gun_prompt.get_parent() == _ground_gun:
			_ground_gun.remove_child(_gun_prompt)
			add_child(_gun_prompt)
	_ground_gun.queue_free()
	_ground_gun = null
	_add_gun_to_inventory()
	set_process(false)


func _add_gun_to_inventory() -> void:
	var tm := get_node_or_null("/root/Main/TurnManager")
	if tm != null and tm.has_method("add_inventory_gun"):
		tm.call("add_inventory_gun")


func _corpse_gun_tick() -> void:
	if not can_reclaim_gun():
		if _gun_prompt != null and is_instance_valid(_gun_prompt):
			_gun_prompt.visible = false
		_player2_near = false
		if not has_ground_gun():
			set_process(false)
		return
	var p2 := get_node_or_null("/root/Main/Player2/Player2Body") as Node2D
	if p2 == null:
		return
	var near: bool = global_position.distance_to(p2.global_position) <= CORPSE_GUN_RANGE
	_player2_near = near
	if _gun_prompt != null and is_instance_valid(_gun_prompt):
		_gun_prompt.visible = near


func _ground_gun_tick() -> void:
	if not has_ground_gun():
		_ground_gun_near = false
		if _gun_prompt != null and is_instance_valid(_gun_prompt):
			_gun_prompt.visible = false
		set_process(false)
		return
	var p2 := get_node_or_null("/root/Main/Player2/Player2Body") as Node2D
	if p2 == null:
		return
	var near: bool = _ground_gun.global_position.distance_to(p2.global_position) <= CORPSE_GUN_RANGE
	_ground_gun_near = near
	if _gun_prompt != null and is_instance_valid(_gun_prompt):
		_gun_prompt.visible = near


## Bomb knocks the gun free next to the remnant (handgun sprite + same Press E).
func _spawn_ground_gun() -> void:
	if has_ground_gun():
		return
	var tex: Texture2D = load(TEX_HANDGUN) as Texture2D
	if tex == null:
		return
	var gun := Sprite2D.new()
	gun.name = "LizardDroppedGun"
	gun.texture = tex
	gun.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	gun.z_index = z_index + 1
	var tex_w := float(tex.get_width())
	gun.scale = Vector2.ONE * (40.0 / maxf(tex_w, 1.0))
	gun.rotation = 0.35
	var parent_n := get_parent()
	if parent_n == null:
		return
	parent_n.add_child(gun)
	# Slightly offset from remnant so both read clearly.
	gun.global_position = global_position + Vector2(18.0, 10.0)
	_ground_gun = gun
	_ensure_gun_prompt()
	# Prompt lives on the gun so it tracks the drop spot.
	if _gun_prompt.get_parent() != gun:
		if _gun_prompt.get_parent() != null:
			_gun_prompt.get_parent().remove_child(_gun_prompt)
		gun.add_child(_gun_prompt)
	_gun_prompt.position = Vector2(-70.0, -48.0)
	var gs: float = maxf(absf(gun.scale.x), 0.001)
	_gun_prompt.scale = Vector2(0.18 / gs, 0.18 / gs)
	_gun_prompt.visible = false
	_ground_gun_near = false
	set_process(true)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if (event as InputEventKey).keycode != KEY_E:
		return
	var tm := get_node_or_null("/root/Main/TurnManager")
	if tm != null and String(tm.get("current_turn")) != "Player2":
		return
	if can_reclaim_gun() and _player2_near:
		reclaim_gun()
		get_viewport().set_input_as_handled()
		return
	if has_ground_gun() and _ground_gun_near:
		reclaim_ground_gun()
		get_viewport().set_input_as_handled()


func _disable_collision() -> void:
	var body := get_node_or_null("Body") as StaticBody2D
	if body == null:
		return
	body.collision_layer = 0
	body.collision_mask = 0
	var shape := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape:
		shape.disabled = true


func _process(delta: float) -> void:
	if _gibbed:
		_ground_gun_tick()
		return
	if _dead_from_pills:
		_corpse_gun_tick()
		return
	if texture == null:
		var tex: Texture2D = load(TEX_PATH) as Texture2D
		if tex != null:
			texture = tex
			hframes = HFRAMES
			vframes = VFRAMES
	if _pause_t > 0.0:
		_pause_t -= delta
		_anim_frame = 0
		_apply_frame()
		return

	_dir_t -= delta
	if _dir_t <= 0.0:
		if randf() < 0.28:
			_pause_t = randf_range(0.35, 1.1)
			_pick_dir()
			return
		_pick_dir()

	var step: float = WALK_SPEED * _speed_mult * delta
	var next: Vector2 = position + _dir * step
	if next.x < ROOM_MIN_X or next.x > X_MAX:
		_dir.x *= -1.0
		next.x = clampf(next.x, ROOM_MIN_X, X_MAX)
		_facing_row = _row_for_dir(_dir)
	if next.y < Y_LINE or next.y > Y_FLOOR:
		_dir.y *= -1.0
		next.y = clampf(next.y, Y_LINE, Y_FLOOR)
		_facing_row = _row_for_dir(_dir)
	# Soft bounce off lizard-only editor blocker (layer 2).
	if _blocked_at(next):
		_dir = -_dir
		_facing_row = _row_for_dir(_dir)
		next = position + _dir * step
		if _blocked_at(next):
			next = position
	position = next

	# Faster gait when juiced so legs keep up with the dash.
	var frame_dt: float = ANIM_SPEED / maxf(_speed_mult, 1.0)
	_anim_t += delta
	if _anim_t >= frame_dt:
		_anim_t = 0.0
		_anim_frame = (_anim_frame + 1) % HFRAMES
	_apply_frame()


func _blocked_at(world_pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	if space == null or _probe == null:
		return false
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = _probe
	q.transform = Transform2D(0.0, world_pos)
	q.collision_mask = LIZARD_BLOCK_MASK
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return not space.intersect_shape(q, 1).is_empty()


## Bomb detonation: always go to blood/burn remnant (even if already dead from pills).
## If the lizard still held the gun (e.g. pill-corpse + bomb), drop handgun on ground for Press E.
func gib_from_blast(_boom_global: Vector2) -> void:
	if _gibbed:
		return
	var drop_gun: bool = _has_gun
	_gibbed = true
	_dead_from_pills = true
	_has_gun = false
	_player2_near = false
	if _gun_prompt != null and is_instance_valid(_gun_prompt):
		_gun_prompt.visible = false
	set_process(false)
	flip_v = false

	var rem: Texture2D = load(TEX_REMNANT) as Texture2D
	if rem != null:
		texture = rem
	hframes = 1
	vframes = 1
	frame = 0
	scale = Vector2(DRAW_SCALE * 1.15, DRAW_SCALE * 1.15)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if drop_gun:
		_spawn_ground_gun()


func stop_for_gib() -> void:
	if _gibbed:
		return
	# Fallback path — prefer gib_from_blast (drops gun + remnant).
	var drop_gun: bool = _has_gun
	_gibbed = true
	_dead_from_pills = true
	_has_gun = false
	_player2_near = false
	if _gun_prompt != null and is_instance_valid(_gun_prompt):
		_gun_prompt.visible = false
	set_process(false)
	if drop_gun:
		_spawn_ground_gun()


func _pick_dir() -> void:
	var dirs: Array = [
		Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN,
		Vector2(-1, -1).normalized(), Vector2(1, -1).normalized(),
		Vector2(-1, 1).normalized(), Vector2(1, 1).normalized(),
	]
	_dir = dirs[randi() % dirs.size()]
	_dir_t = randf_range(0.6, 1.6)
	_facing_row = _row_for_dir(_dir)


func _row_for_dir(d: Vector2) -> int:
	if absf(d.x) >= absf(d.y):
		return ROW_RIGHT if d.x > 0.0 else ROW_LEFT
	return ROW_DOWN if d.y > 0.0 else ROW_UP


func _apply_frame() -> void:
	frame = _facing_row * HFRAMES + _anim_frame
