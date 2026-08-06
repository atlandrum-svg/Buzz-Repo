extends Area2D
## Player-1-only floor trap for the office round. Only visible during Player
## 1's turn — Player 2 never sees it, but the trigger stays active regardless.
## Clicking it (while visible) rotates the 8-way direction it flings Player 2
## when they step on it.

const ItemPrompts = preload("res://item_prompts.gd")

const TEX_PATH := "res://floor_trap.png"
const ARROW_TEX_PATH := "res://floor_trap_arrow.png"
const HIT_SIZE := Vector2(30.0, 30.0)
const DRAW_SCALE := 0.7
const PLAYER_MASK := 1
const HOVER_TEXT := "Click to change direction your rival will be flung"

## Clockwise from up: up, up-right, right, down-right, down, down-left, left, up-left.
## NOTE: this can't be `const` — .normalized() is a method call, not a constant
## expression, and GDScript rejects that at parse time. Populated once in
## _static_init-style fashion below via a plain var instead.
var DIRECTIONS: Array[Vector2] = [
	Vector2(0, -1),
	Vector2(1, -1).normalized(),
	Vector2(1, 0),
	Vector2(1, 1).normalized(),
	Vector2(0, 1),
	Vector2(-1, 1).normalized(),
	Vector2(-1, 0),
	Vector2(-1, -1).normalized(),
]

var _dir_index: int = 0
var _sprite: Sprite2D
var _arrow: Sprite2D
var _hover_label: Label
var _triggered: bool = false
var _turn_manager: Node


func _ready() -> void:
	z_index = 1
	monitoring = true
	monitorable = false
	# Mouse picking is a raw physics point-query, independent of `monitorable`
	# — it only finds colliders whose collision_layer overlaps the query mask.
	# A layer of 0 made this Area2D invisible to clicks entirely (rotation
	# never fired). `monitorable = false` above still keeps it invisible to
	# other Areas' own area_entered/body_entered monitoring, so this is safe.
	collision_layer = PLAYER_MASK
	collision_mask = PLAYER_MASK
	input_pickable = true
	var vp := get_viewport()
	if vp:
		vp.physics_object_picking = true

	_turn_manager = get_node_or_null("/root/Main/TurnManager")

	_sprite = Sprite2D.new()
	_sprite.name = "Sprite2D"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.texture = _load_tex(TEX_PATH)
	add_child(_sprite)

	_arrow = Sprite2D.new()
	_arrow.name = "Arrow"
	_arrow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_arrow.texture = _load_tex(ARROW_TEX_PATH)
	_arrow.z_index = 1
	add_child(_arrow)

	scale = Vector2(DRAW_SCALE, DRAW_SCALE)

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = HIT_SIZE
	col.shape = shape
	add_child(col)

	_hover_label = Label.new()
	_hover_label.name = "HoverLabel"
	_hover_label.text = HOVER_TEXT
	_hover_label.visible = false
	_hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hover_label.offset_left = -260.0
	_hover_label.offset_top = -150.0
	_hover_label.offset_right = 260.0
	_hover_label.offset_bottom = -70.0
	add_child(_hover_label)
	ItemPrompts.apply_font(_hover_label)

	body_entered.connect(_on_body_entered)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)

	_apply_direction()
	set_process(true)


func _process(_delta: float) -> void:
	var p1_turn: bool = _turn_manager != null and String(_turn_manager.get("current_turn")) == "Player1"
	visible = p1_turn
	if not p1_turn and _hover_label:
		_hover_label.visible = false


func direction() -> Vector2:
	return DIRECTIONS[_dir_index]


func _apply_direction() -> void:
	if _arrow:
		_arrow.rotation = DIRECTIONS[_dir_index].angle() + PI * 0.5


func _rotate_direction() -> void:
	_dir_index = (_dir_index + 1) % DIRECTIONS.size()
	_apply_direction()


func _on_input_event(_vp: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if not visible or _triggered:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_rotate_direction()
		get_viewport().set_input_as_handled()


func _on_mouse_entered() -> void:
	if _hover_label and visible:
		_hover_label.visible = true


func _on_mouse_exited() -> void:
	if _hover_label:
		_hover_label.visible = false


func _on_body_entered(body: Node) -> void:
	if _triggered or _turn_manager == null:
		return
	var p2_body = _turn_manager.get("player2")
	if p2_body == null or body != p2_body:
		return
	_triggered = true
	if _hover_label:
		_hover_label.visible = false
	if _turn_manager.has_method("trigger_floor_trap"):
		_turn_manager.call("trigger_floor_trap", self, direction())


func _load_tex(path: String) -> Texture2D:
	var abs_path: String = ProjectSettings.globalize_path(path)
	var img: Image = null
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
	return ImageTexture.create_from_image(img)
