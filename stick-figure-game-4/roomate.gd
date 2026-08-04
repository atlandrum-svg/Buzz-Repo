extends Sprite2D
## Pet lizard (skitterscale). Random walk. Pipe bomb → blood/burn remnant (no chunks).
## Avoids LizardOnlyBlocker (collision_layer 2) — players ignore that layer.

const TEX_PATH := "res://skitterscale-sheet.png"
const TEX_REMNANT := "res://skitterscale_remnant.png"
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
## Matches StaticBody2D LizardOnlyBlocker.collision_layer in the main scene.
const LIZARD_BLOCK_MASK := 2
const HIT_SIZE := Vector2(14.0, 12.0)

var _anim_frame: int = 0
var _anim_t: float = 0.0
var _facing_row: int = ROW_LEFT
var _dir: Vector2 = Vector2.LEFT
var _dir_t: float = 0.0
var _pause_t: float = 0.0
var _gibbed: bool = false
var _probe: RectangleShape2D


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

	var step: float = WALK_SPEED * delta
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

	_anim_t += delta
	if _anim_t >= ANIM_SPEED:
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


## boom_global unused (no chunks); kept for dresser_area call site.
func gib_from_blast(_boom_global: Vector2) -> void:
	if _gibbed:
		return
	_gibbed = true
	set_process(false)

	var rem: Texture2D = load(TEX_REMNANT) as Texture2D
	if rem != null:
		texture = rem
	hframes = 1
	vframes = 1
	frame = 0
	scale = Vector2(DRAW_SCALE * 1.15, DRAW_SCALE * 1.15)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func stop_for_gib() -> void:
	if _gibbed:
		return
	_gibbed = true
	set_process(false)


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
