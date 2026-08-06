extends Sprite2D
## Office monkey from the booby-trapped filing cabinet.
## Emerge idle → walk beside player (collision-aware) → pills / lizard fight / frenzy.

const TEX_PATH := "res://monkey_sprite_sheet.png"
const HFRAMES := 4
const VFRAMES := 4
const ANIM_SPEED := 0.10
const CHASE_SPEED := 78.0
const FRENZY_SPEED := 220.0
const BESIDE_DIST := 30.0
const ARRIVE_EPS := 5.0
const DRAW_SCALE := 0.95
const ROW_DOWN := 0
const ROW_RIGHT := 1
const ROW_LEFT := 2
const ROW_UP := 3
const ROOM_MIN := Vector2(-200.0, -160.0)
const ROOM_MAX := Vector2(200.0, 240.0)
const HIT_SIZE := Vector2(16.0, 16.0)
## World walls / furniture (player mask layer 1).
const WALL_MASK := 1

enum State { IDLE, WALK_BESIDE, AWAIT_CHOICE, FRENZY, DEAD }

var _state: int = State.IDLE
var _anim_frame: int = 0
var _anim_t: float = 0.0
var _facing_row: int = ROW_DOWN
var _follow: Node2D = null
var _goal: Vector2 = Vector2.ZERO
var _frenzy_dir: Vector2 = Vector2.RIGHT
var _frenzy_t: float = 0.0
var _dead: bool = false
var _walk_done: bool = false
var _stuck_t: float = 0.0
var _probe: RectangleShape2D


func _ready() -> void:
	z_index = 5
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tex: Texture2D = load(TEX_PATH) as Texture2D
	if tex != null:
		texture = tex
	hframes = HFRAMES
	vframes = VFRAMES
	scale = Vector2(DRAW_SCALE, DRAW_SCALE)
	_probe = RectangleShape2D.new()
	_probe.size = HIT_SIZE
	_apply_frame()
	set_process(true)


func is_dead() -> bool:
	return _dead


## Stand still at the cabinet while the player cartwheels / message plays.
func idle_in_place() -> void:
	_state = State.IDLE
	_walk_done = false
	_dead = false
	_anim_frame = 0
	_apply_frame()
	set_process(true)


## Pop out of the cabinet with the same arc + bounce as the dresser pipe bomb.
## Lands clear of the cabinet solid so later pathing is free.
func eject_arc(from: Vector2, land: Vector2) -> void:
	_state = State.IDLE
	_walk_done = false
	_dead = false
	global_position = from
	rotation = -0.25
	_facing_row = ROW_RIGHT if land.x >= from.x else ROW_LEFT
	_anim_frame = 0
	_apply_frame()
	set_process(true)

	var apex := Vector2((from.x + land.x) * 0.55, minf(from.y, land.y) - 48.0)
	var bounce := land + Vector2(signf(land.x - from.x) * 10.0, -14.0)
	var rest := land

	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	# Arc up out of the drawer / cabinet face
	tw.tween_property(self, "global_position", apex, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Fall to clear floor
	tw.tween_property(self, "global_position", land, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Small bounce then rest
	tw.tween_property(self, "global_position", bounce, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "global_position", rest, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "rotation", 0.35, 0.14)
	await tw.finished
	if not is_instance_valid(self):
		return
	rotation = 0.0
	global_position = rest
	_anim_frame = 0
	_apply_frame()


## Walk to a stand point beside the target (not on top). Awaits arrival.
func walk_to_beside(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_follow = target
	_goal = _beside_point(target.global_position, global_position)
	_state = State.WALK_BESIDE
	_walk_done = false
	set_process(true)
	while not _walk_done and is_instance_valid(self) and _state == State.WALK_BESIDE:
		await get_tree().process_frame
	if is_instance_valid(self) and not _dead:
		_state = State.AWAIT_CHOICE
		_anim_frame = 0
		_apply_frame()


func hold_beside(target: Node2D) -> void:
	_follow = target
	_state = State.AWAIT_CHOICE
	if target != null and is_instance_valid(target):
		global_position = _beside_point(target.global_position, global_position)


func enter_frenzy() -> void:
	_state = State.FRENZY
	_pick_frenzy_dir()
	set_process(true)


func die_upside_down() -> void:
	_dead = true
	_state = State.DEAD
	_walk_done = true
	set_process(false)
	_facing_row = ROW_LEFT
	_anim_frame = 0
	frame = ROW_LEFT * HFRAMES + 0
	flip_v = true
	scale = Vector2(DRAW_SCALE, DRAW_SCALE)


func _process(delta: float) -> void:
	if _dead:
		return
	match _state:
		State.IDLE:
			_anim_frame = 0
			_apply_frame()
		State.WALK_BESIDE:
			_process_walk_beside(delta)
		State.AWAIT_CHOICE:
			# Stay put next to the player — do not stack on them.
			_anim_frame = 0
			_apply_frame()
		State.FRENZY:
			_process_frenzy(delta)
		_:
			pass


func _process_walk_beside(delta: float) -> void:
	if _follow != null and is_instance_valid(_follow):
		_goal = _beside_point(_follow.global_position, global_position)
	var to: Vector2 = _goal - global_position
	var dist: float = to.length()
	if dist <= ARRIVE_EPS:
		global_position = _goal
		_walk_done = true
		_anim_frame = 0
		_apply_frame()
		return
	var dir: Vector2 = to.normalized()
	_facing_row = _row_for_dir(dir)
	var step: float = minf(CHASE_SPEED * delta, dist)
	var before: Vector2 = global_position
	var next: Vector2 = _move_with_collision(global_position, dir, step)
	global_position = next
	if global_position.distance_squared_to(before) < 0.01:
		_stuck_t += delta
		if _stuck_t > 1.2:
			# Close enough / blocked — stand here next to the player path.
			_walk_done = true
	else:
		_stuck_t = 0.0
	_tick_anim(delta)


func _process_frenzy(delta: float) -> void:
	_frenzy_t -= delta
	if _frenzy_t <= 0.0:
		_pick_frenzy_dir()
	var step: float = FRENZY_SPEED * delta
	var next: Vector2 = _move_with_collision(global_position, _frenzy_dir, step)
	if next.distance_squared_to(global_position) < 0.25:
		_frenzy_dir = -_frenzy_dir
		next = _move_with_collision(global_position, _frenzy_dir, step)
	global_position = next
	global_position.x = clampf(global_position.x, ROOM_MIN.x, ROOM_MAX.x)
	global_position.y = clampf(global_position.y, ROOM_MIN.y, ROOM_MAX.y)
	_facing_row = _row_for_dir(_frenzy_dir)
	_tick_anim(delta)


## Prefer the side of the player that faces the monkey's approach.
func _beside_point(anchor: Vector2, from: Vector2) -> Vector2:
	var side: float = BESIDE_DIST
	if from.x >= anchor.x:
		side = BESIDE_DIST
	else:
		side = -BESIDE_DIST
	var cand := Vector2(anchor.x + side, anchor.y)
	if _blocked_at(cand):
		cand = Vector2(anchor.x - side, anchor.y)
	if _blocked_at(cand):
		cand = Vector2(anchor.x, anchor.y + BESIDE_DIST)
	if _blocked_at(cand):
		cand = Vector2(anchor.x, anchor.y - BESIDE_DIST)
	cand.x = clampf(cand.x, ROOM_MIN.x, ROOM_MAX.x)
	cand.y = clampf(cand.y, ROOM_MIN.y, ROOM_MAX.y)
	return cand


func _move_with_collision(from: Vector2, dir: Vector2, step: float) -> Vector2:
	if step <= 0.0:
		return from
	var full: Vector2 = from + dir * step
	if not _blocked_at(full):
		return full
	# Axis slide.
	var only_x: Vector2 = from + Vector2(dir.x * step, 0.0)
	if not _blocked_at(only_x):
		return only_x
	var only_y: Vector2 = from + Vector2(0.0, dir.y * step)
	if not _blocked_at(only_y):
		return only_y
	return from


func _blocked_at(world_pos: Vector2) -> bool:
	if world_pos.x < ROOM_MIN.x or world_pos.x > ROOM_MAX.x \
			or world_pos.y < ROOM_MIN.y or world_pos.y > ROOM_MAX.y:
		return true
	var space := get_world_2d().direct_space_state if get_world_2d() else null
	if space == null or _probe == null:
		return false
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = _probe
	q.transform = Transform2D(0.0, world_pos)
	q.collision_mask = WALL_MASK
	q.collide_with_areas = false
	q.collide_with_bodies = true
	# Ignore the player body so we can stand beside them.
	var exclude: Array[RID] = []
	var p2 := get_node_or_null("/root/Main/Player2/Player2Body")
	if p2 is CollisionObject2D:
		exclude.append((p2 as CollisionObject2D).get_rid())
	var p1 := get_node_or_null("/root/Main/Player1/Player1Body")
	if p1 is CollisionObject2D:
		exclude.append((p1 as CollisionObject2D).get_rid())
	q.exclude = exclude
	return not space.intersect_shape(q, 1).is_empty()


func _tick_anim(delta: float) -> void:
	_anim_t += delta
	if _anim_t >= ANIM_SPEED:
		_anim_t = 0.0
		_anim_frame = (_anim_frame + 1) % HFRAMES
	_apply_frame()


func _pick_frenzy_dir() -> void:
	var dirs: Array = [
		Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN,
		Vector2(-1, -1).normalized(), Vector2(1, -1).normalized(),
		Vector2(-1, 1).normalized(), Vector2(1, 1).normalized(),
	]
	_frenzy_dir = dirs[randi() % dirs.size()]
	_frenzy_t = randf_range(0.18, 0.45)


func _row_for_dir(d: Vector2) -> int:
	if absf(d.x) >= absf(d.y):
		return ROW_RIGHT if d.x > 0.0 else ROW_LEFT
	return ROW_DOWN if d.y > 0.0 else ROW_UP


func _apply_frame() -> void:
	frame = _facing_row * HFRAMES + _anim_frame
