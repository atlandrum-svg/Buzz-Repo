extends Sprite2D
## Office worker NPC. Walks randomly (or stands idle). Optional trap/use/inspect like a prop.

const UsableShimmer = preload("res://usable_shimmer.gd")
const ItemPrompts = preload("res://item_prompts.gd")

@export var walk_enabled: bool = true
@export var trappable: bool = true
@export var sheet_path: String = "res://office_worker_walk_sheet.png"
@export var prop_name: String = "Office Worker"
@export var clean_message: String = ""
@export var trap_message: String = ""
@export var clean_anxiety_id: String = ""
@export var trap_anxiety_id: String = ""

const HFRAMES := 4
const VFRAMES := 4
const ANIM_SPEED := 0.12
const WALK_SPEED := 42.0
## Match player-ish on-screen size (64px cell @ ~1.15 ≈ P2 presence).
const DRAW_SCALE := 1.2
const ROW_DOWN := 0
const ROW_RIGHT := 1
const ROW_LEFT := 2
const ROW_UP := 3
const ROOM_MIN := Vector2(-200.0, -150.0)
const ROOM_MAX := Vector2(200.0, 230.0)
const HIT_SIZE := Vector2(14.0, 14.0)
const WALL_MASK := 1

var is_booby_trapped: bool = false
var player_inside = null
var _busy: bool = false
var _anim_frame: int = 0
var _anim_t: float = 0.0
var _facing_row: int = ROW_DOWN
var _dir: Vector2 = Vector2.RIGHT
var _dir_t: float = 0.0
var _pause_t: float = 0.0
var _probe: RectangleShape2D
var _area: Area2D
var _label: Label

@onready var player1_body = $/root/Main/Player1/Player1Body
@onready var player2_body = $/root/Main/Player2/Player2Body
@onready var turn_manager = $/root/Main/TurnManager


func _ready() -> void:
	visible = true
	modulate = Color.WHITE
	self_modulate = Color.WHITE
	z_index = 6
	z_as_relative = true
	centered = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Load + key pure black like other NPC sheets so cells read cleanly.
	var tex: Texture2D = _load_sheet(sheet_path)
	if tex != null:
		texture = tex
	elif texture == null:
		push_error("[OfficeWorker] missing texture: ", sheet_path)
	hframes = HFRAMES
	vframes = VFRAMES
	frame = 0
	scale = Vector2(DRAW_SCALE, DRAW_SCALE)
	_probe = RectangleShape2D.new()
	_probe.size = HIT_SIZE
	_ensure_interaction_nodes()
	_apply_frame()
	if trappable:
		# Defer shimmer so the first draw is a solid sprite (avoids blank first frames).
		call_deferred("_attach_shimmer")
	if walk_enabled:
		_pick_dir()
		_pause_t = randf_range(0.2, 0.8)
	else:
		_facing_row = ROW_DOWN
		_anim_frame = 0
		_apply_frame()
	set_process(true)
	print("[OfficeWorker] ready name=", name, " pos=", global_position, " tex=", texture != null, " frame=", frame)


func _attach_shimmer() -> void:
	if is_instance_valid(self):
		UsableShimmer.attach(self)


func _load_sheet(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var img: Image = null
	var abs_path: String = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		img = Image.load_from_file(abs_path)
	elif ResourceLoader.exists(path):
		var t: Variant = load(path)
		if t is Texture2D:
			img = (t as Texture2D).get_image()
	if img == null:
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	# Key pure black cell backgrounds (not dark navy suit pixels — those have blue).
	var w: int = img.get_width()
	var h: int = img.get_height()
	for y in h:
		for x in w:
			var c: Color = img.get_pixel(x, y)
			if c.r <= 0.02 and c.g <= 0.02 and c.b <= 0.02:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


func reset_for_new_round() -> void:
	is_booby_trapped = false
	_busy = false
	player_inside = null
	if _label:
		_label.visible = false
	material = null
	self_modulate = Color.WHITE
	modulate = Color.WHITE


func _ensure_interaction_nodes() -> void:
	_label = get_node_or_null("Label") as Label
	if _label == null:
		_label = Label.new()
		_label.name = "Label"
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.offset_left = -250.0
		_label.offset_top = -120.0
		_label.offset_right = 250.0
		_label.offset_bottom = -40.0
		_label.add_theme_font_size_override("font_size", 48)
		_label.text = ItemPrompts.TRAP
		add_child(_label)
	_label.visible = false
	ItemPrompts.apply_font(_label)

	_area = get_node_or_null("InteractArea") as Area2D
	if _area == null:
		_area = Area2D.new()
		_area.name = "InteractArea"
		_area.collision_layer = 0
		_area.collision_mask = 1
		_area.monitoring = true
		_area.monitorable = false
		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 28.0
		col.shape = shape
		_area.add_child(col)
		add_child(_area)
	if not _area.body_entered.is_connected(_on_body_entered):
		_area.body_entered.connect(_on_body_entered)
	if not _area.body_exited.is_connected(_on_body_exited):
		_area.body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if not walk_enabled:
		return
	if _busy:
		return
	if _pause_t > 0.0:
		_pause_t -= delta
		_anim_frame = 0
		_apply_frame()
		return
	_dir_t -= delta
	if _dir_t <= 0.0:
		if randf() < 0.30:
			_pause_t = randf_range(0.4, 1.2)
			_pick_dir()
			return
		_pick_dir()
	var step: float = WALK_SPEED * delta
	var next: Vector2 = global_position + _dir * step
	next.x = clampf(next.x, ROOM_MIN.x, ROOM_MAX.x)
	next.y = clampf(next.y, ROOM_MIN.y, ROOM_MAX.y)
	if next.x <= ROOM_MIN.x or next.x >= ROOM_MAX.x:
		_dir.x *= -1.0
		_facing_row = _row_for_dir(_dir)
	if next.y <= ROOM_MIN.y or next.y >= ROOM_MAX.y:
		_dir.y *= -1.0
		_facing_row = _row_for_dir(_dir)
	if _blocked_at(next):
		_dir = -_dir
		_facing_row = _row_for_dir(_dir)
		next = global_position + _dir * step
		if _blocked_at(next):
			next = global_position
	global_position = next
	_anim_t += delta
	if _anim_t >= ANIM_SPEED:
		_anim_t = 0.0
		_anim_frame = (_anim_frame + 1) % HFRAMES
	_apply_frame()


func _pick_dir() -> void:
	var dirs: Array = [
		Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN,
		Vector2(-1, -1).normalized(), Vector2(1, -1).normalized(),
		Vector2(-1, 1).normalized(), Vector2(1, 1).normalized(),
	]
	_dir = dirs[randi() % dirs.size()]
	_dir_t = randf_range(0.7, 1.8)
	_facing_row = _row_for_dir(_dir)


func _row_for_dir(d: Vector2) -> int:
	if absf(d.x) >= absf(d.y):
		return ROW_RIGHT if d.x > 0.0 else ROW_LEFT
	return ROW_DOWN if d.y > 0.0 else ROW_UP


func _apply_frame() -> void:
	frame = _facing_row * HFRAMES + _anim_frame


func _blocked_at(world_pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state if get_world_2d() else null
	if space == null or _probe == null:
		return false
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = _probe
	q.transform = Transform2D(0.0, world_pos)
	q.collision_mask = WALL_MASK
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var exclude: Array[RID] = []
	for p in [player1_body, player2_body]:
		if p is CollisionObject2D:
			exclude.append((p as CollisionObject2D).get_rid())
	q.exclude = exclude
	return not space.intersect_shape(q, 1).is_empty()


func _on_body_entered(body) -> void:
	if not trappable or _busy:
		return
	if body == player1_body or body == player2_body:
		player_inside = body
		if body == player1_body and turn_manager and turn_manager.current_turn == "Player1":
			_label.text = ItemPrompts.TRAP
			_label.visible = true
		elif body == player2_body and turn_manager and turn_manager.current_turn == "Player2":
			if turn_manager.can_p2_use_world_item():
				_label.text = ItemPrompts.prompt_for(turn_manager)
				_label.visible = true
			else:
				_label.visible = false


func _on_body_exited(body) -> void:
	if body == player_inside:
		player_inside = null
		if not _busy and _label:
			_label.visible = false


func _input(event) -> void:
	if not trappable or player_inside == null or _busy:
		return
	if turn_manager == null:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if player_inside == player1_body and turn_manager.current_turn == "Player1" and event.keycode == KEY_E:
		if is_booby_trapped:
			return
		if not turn_manager.consume_trap():
			return
		is_booby_trapped = true
		_label.visible = false
		UsableShimmer.mark_trapped_p1(self)
	elif player_inside == player2_body and turn_manager.current_turn == "Player2":
		if not turn_manager.can_p2_use_world_item():
			return
		if event.keycode == KEY_I:
			if not turn_manager.consume_p2_inspect():
				return
			if is_booby_trapped:
				_label.text = ItemPrompts.TRAP_FOUND
				is_booby_trapped = false
			else:
				_label.text = ItemPrompts.NO_TRAP
			_label.visible = true
			await get_tree().create_timer(1.0).timeout
			if player_inside == player2_body and turn_manager.can_p2_use_world_item():
				_label.text = ItemPrompts.USE_ONLY
				_label.visible = true
			else:
				_label.visible = false
		elif event.keycode == KEY_E:
			await _use_worker()


func _use_worker() -> void:
	_busy = true
	UsableShimmer.mark_used_p2(self)
	if _label:
		_label.visible = false
	# Pause roam while conversing.
	var was_walk := walk_enabled
	walk_enabled = false
	_anim_frame = 0
	_apply_frame()
	if is_booby_trapped:
		is_booby_trapped = false
		var msg: String = trap_message
		if turn_manager and turn_manager.has_method("show_evaluation_popup"):
			await turn_manager.show_evaluation_popup(msg)
		if trap_anxiety_id != "" and turn_manager and turn_manager.has_method("apply_anxiety"):
			turn_manager.apply_anxiety(trap_anxiety_id)
		if turn_manager and turn_manager.has_method("set_status_message"):
			turn_manager.set_status_message(msg)
	else:
		var msg2: String = clean_message
		if turn_manager and turn_manager.has_method("show_evaluation_popup"):
			await turn_manager.show_evaluation_popup(msg2)
		if clean_anxiety_id != "" and turn_manager and turn_manager.has_method("apply_anxiety"):
			turn_manager.apply_anxiety(clean_anxiety_id)
		if turn_manager and turn_manager.has_method("set_status_message"):
			turn_manager.set_status_message(msg2)
	if turn_manager:
		turn_manager.consume_p2_use()
	walk_enabled = was_walk
	_busy = false
	if player_inside == player2_body and turn_manager and turn_manager.can_p2_use_world_item() and _label:
		_label.text = ItemPrompts.prompt_for(turn_manager)
		_label.visible = true
	elif _label:
		_label.visible = false
