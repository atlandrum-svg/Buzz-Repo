extends Node2D
## Fireman NPC — 4×4 sheet: row0 down, row1 right, row2 left, row3 up.
## Possessed: zombie follow. Fent gun miss: crawl sheet, random crawl, then die.

const TEX_PATH := "res://fireman_sprite_sheet.png"
const TEX_ZOMBIE_PATH := "res://fireman_zombie_sprite_sheet.png"
const TEX_HEADLESS_PATH := "res://fireman_headless.png"
const TEX_CRAWL_PATH := "res://fireman_crawl_sheet.png"
const HFRAMES := 4
const VFRAMES := 4
const ANIM_SPEED := 0.12
const WALK_SPEED := 72.0
const FOLLOW_SPEED_MULT := 0.5
const FOLLOW_STOP_DIST := 28.0
const CRAWL_SPEED := 28.0
## Active thrashing crawl, then he stops (still bleeding out until death timer).
const CRAWL_ACTIVE_SEC := 15.0
## Hard stop / death (also driven by TurnManager at 120s).
const CRAWL_DIE_SEC := 120.0
## Always freeze on this pose when crawl movement ends (front row, frame 0 of sheet).
## Avoids random mid-crawl frames that look broken (e.g. on the pillow).
const CRAWL_END_ROW := 0 ## ROW_DOWN — facing camera, defeated crouch
const CRAWL_END_COL := 0

const ROW_DOWN := 0
const ROW_RIGHT := 1
const ROW_LEFT := 2
const ROW_UP := 3

const SPAWN_POS := Vector2(-156.0, 235.0)
const STAND_POS := Vector2(-160.0, 35.0)
## Loose room bounds so random crawl stays on the floor art.
const ROOM_MIN := Vector2(-200.0, -160.0)
const ROOM_MAX := Vector2(200.0, 240.0)

var _sprite: Sprite2D
var _anim_frame: int = 0
var _anim_t: float = 0.0
var _facing_row: int = ROW_UP
var _walking: bool = false
var _possessed: bool = false
var _dead: bool = false
var _crawling: bool = false
var _crawl_elapsed: float = 0.0
var _crawl_dir: Vector2 = Vector2.LEFT
var _crawl_dir_t: float = 0.0
var _follow_target: Node2D = null
var _walk_speed: float = WALK_SPEED
## Crawl sheet uses same row order as normal (not zombie-mirrored).
var _use_zombie_lr: bool = false


func _ready() -> void:
	# Below players (z=5) so P2 draws on top of fireman / zombie / corpse.
	z_index = 4
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite2D"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.hframes = HFRAMES
	_sprite.vframes = VFRAMES
	_sprite.centered = true
	add_child(_sprite)
	var tex := _load_texture(TEX_PATH)
	if tex:
		_sprite.texture = tex
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if _dead:
		return
	if _crawling:
		_process_crawl(delta)
		return
	if _possessed:
		_process_follow(delta)
		return
	if not _walking or _sprite == null:
		return
	_anim_t += delta
	if _anim_t >= ANIM_SPEED:
		_anim_t = 0.0
		_anim_frame = (_anim_frame + 1) % HFRAMES
		_apply_frame()


func _process_crawl(delta: float) -> void:
	_crawl_elapsed += delta
	# After active crawl window: always hold the dedicated end pose (not a mid-cycle frame).
	if _crawl_elapsed >= CRAWL_ACTIVE_SEC:
		_snap_to_crawl_end_pose()
		if _crawl_elapsed >= CRAWL_DIE_SEC:
			die_in_place()
		return

	_crawl_dir_t -= delta
	if _crawl_dir_t <= 0.0:
		_pick_random_crawl_dir()

	var step: float = CRAWL_SPEED * delta
	var next: Vector2 = global_position + _crawl_dir * step
	# Bounce off soft room bounds.
	if next.x < ROOM_MIN.x or next.x > ROOM_MAX.x:
		_crawl_dir.x *= -1.0
		next.x = clampf(next.x, ROOM_MIN.x, ROOM_MAX.x)
		_facing_row = _row_for_move_dir(_crawl_dir)
	if next.y < ROOM_MIN.y or next.y > ROOM_MAX.y:
		_crawl_dir.y *= -1.0
		next.y = clampf(next.y, ROOM_MIN.y, ROOM_MAX.y)
		_facing_row = _row_for_move_dir(_crawl_dir)
	global_position = next
	_walking = true
	_anim_t += delta
	if _anim_t >= ANIM_SPEED * 1.2:
		_anim_t = 0.0
		_anim_frame = (_anim_frame + 1) % HFRAMES
	_apply_frame()


## Defeated crouch facing camera (crawl sheet row 0, col 0).
func _snap_to_crawl_end_pose() -> void:
	_walking = false
	_facing_row = CRAWL_END_ROW
	_anim_frame = CRAWL_END_COL
	_anim_t = 0.0
	if _sprite:
		_sprite.hframes = HFRAMES
		_sprite.vframes = VFRAMES
	_apply_frame()


func _pick_random_crawl_dir() -> void:
	var dirs: Array = [
		Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN,
		Vector2(-1, -1).normalized(), Vector2(1, -1).normalized(),
		Vector2(-1, 1).normalized(), Vector2(1, 1).normalized(),
	]
	_crawl_dir = dirs[randi() % dirs.size()]
	_crawl_dir_t = randf_range(0.55, 1.4)
	_facing_row = _row_for_move_dir(_crawl_dir)


func _process_follow(delta: float) -> void:
	if _follow_target == null or not is_instance_valid(_follow_target):
		_walking = false
		_anim_frame = 0
		_apply_frame()
		return
	var target_pos: Vector2 = _follow_target.global_position
	var to: Vector2 = target_pos - global_position
	var dist: float = to.length()
	if dist <= FOLLOW_STOP_DIST:
		_walking = false
		_anim_frame = 0
		_apply_frame()
		return
	_walking = true
	var dir: Vector2 = to.normalized()
	_facing_row = _row_for_move_dir(dir)
	var step: float = _walk_speed * FOLLOW_SPEED_MULT * delta
	if dist <= step:
		global_position = target_pos
	else:
		global_position += dir * step
	_anim_t += delta
	var anim_spd: float = ANIM_SPEED / FOLLOW_SPEED_MULT
	if _anim_t >= anim_spd:
		_anim_t = 0.0
		_anim_frame = (_anim_frame + 1) % HFRAMES
		_apply_frame()
	else:
		_apply_frame()


func _apply_frame() -> void:
	if _sprite == null:
		return
	_sprite.frame = _facing_row * HFRAMES + _anim_frame


func face_row(row: int) -> void:
	_facing_row = clampi(row, 0, VFRAMES - 1)
	_anim_frame = 0
	_anim_t = 0.0
	_apply_frame()


func arrive_from_stairs() -> void:
	global_position = SPAWN_POS
	visible = true
	face_row(ROW_UP)
	await walk_to(STAND_POS)
	_walking = false
	set_process(false)
	face_row(ROW_DOWN)
	if _sprite:
		_sprite.flip_h = false
		_sprite.frame = ROW_DOWN * HFRAMES


func place_at_stand() -> void:
	global_position = STAND_POS
	visible = true
	_walking = false
	_possessed = false
	_dead = false
	_crawling = false
	_use_zombie_lr = false
	_follow_target = null
	if _sprite:
		_sprite.scale = Vector2.ONE
	var tex := _load_texture(TEX_PATH)
	if tex and _sprite:
		_sprite.texture = tex
		_sprite.hframes = HFRAMES
		_sprite.vframes = VFRAMES
	face_row(ROW_DOWN)
	set_process(false)


func _row_for_move_dir(dir: Vector2) -> int:
	if absf(dir.y) >= absf(dir.x):
		return ROW_UP if dir.y < 0.0 else ROW_DOWN
	if _use_zombie_lr:
		return ROW_LEFT if dir.x > 0.0 else ROW_RIGHT
	return ROW_RIGHT if dir.x > 0.0 else ROW_LEFT


func walk_to(target: Vector2) -> void:
	_walking = true
	set_process(true)
	var delta: Vector2 = target - global_position
	face_row(_row_for_move_dir(delta.normalized() if delta.length_squared() > 0.0001 else Vector2.DOWN))

	while global_position.distance_to(target) > 2.0:
		await get_tree().process_frame
		if _dead or _crawling:
			return
		var step_delta: float = get_process_delta_time()
		if step_delta <= 0.0:
			step_delta = 1.0 / 60.0
		var to: Vector2 = target - global_position
		var dist: float = to.length()
		var step: float = _walk_speed * step_delta
		if dist <= step:
			global_position = target
			break
		global_position += to.normalized() * step

	global_position = target
	_walking = false
	_anim_frame = 0
	_apply_frame()
	if not _possessed and not _crawling:
		set_process(false)


func become_possessed(follow_target: Node2D) -> void:
	if _dead or _crawling:
		return
	_possessed = true
	_use_zombie_lr = true
	_follow_target = follow_target
	var ztex := _load_texture(TEX_ZOMBIE_PATH)
	if ztex and _sprite:
		_sprite.texture = ztex
		_sprite.hframes = HFRAMES
		_sprite.vframes = VFRAMES
		_sprite.scale = Vector2.ONE
	face_row(ROW_DOWN)
	visible = true
	set_process(true)


func is_possessed() -> bool:
	return _possessed


## Fent + gun: leg blown off, thrash-crawl on crawl sheet.
func become_legless_crawl() -> void:
	if _dead:
		return
	_possessed = false
	_follow_target = null
	_crawling = true
	_use_zombie_lr = false
	_crawl_elapsed = 0.0
	_crawl_dir_t = 0.0
	var tex := _load_texture(TEX_CRAWL_PATH)
	if tex and _sprite:
		_sprite.texture = tex
		_sprite.hframes = HFRAMES
		_sprite.vframes = VFRAMES
		_sprite.scale = Vector2.ONE
	_pick_random_crawl_dir()
	visible = true
	set_process(true)


func is_crawling() -> bool:
	return _crawling and not _dead


## Stop forever (after crawl death timer). Keep the crawl end pose — no random frame.
func die_in_place() -> void:
	if _dead:
		return
	_dead = true
	_crawling = false
	_possessed = false
	_follow_target = null
	_walking = false
	_snap_to_crawl_end_pose()
	set_process(false)


func become_headless_corpse() -> void:
	_dead = true
	_possessed = false
	_crawling = false
	_follow_target = null
	_walking = false
	set_process(false)
	var tex := _load_texture(TEX_HEADLESS_PATH)
	if tex and _sprite:
		_sprite.texture = tex
		_sprite.hframes = 1
		_sprite.vframes = 1
		_sprite.frame = 0
		var th: float = float(tex.get_height())
		if th > 1.0:
			var s: float = 65.0 / th
			_sprite.scale = Vector2(s, s)
	visible = true


func is_dead() -> bool:
	return _dead


func _load_texture(path: String) -> Texture2D:
	var abs_path: String = ProjectSettings.globalize_path(path)
	var img: Image = null
	if FileAccess.file_exists(abs_path):
		img = Image.load_from_file(abs_path)
	elif ResourceLoader.exists(path):
		var t: Variant = load(path)
		if t is Texture2D:
			img = (t as Texture2D).get_image()
	if img == null:
		push_error("Fireman texture missing: %s" % path)
		return null
	_key_out_black(img)
	return ImageTexture.create_from_image(img)


func _key_out_black(img: Image) -> void:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w: int = img.get_width()
	var h: int = img.get_height()
	for y in h:
		for x in w:
			var c: Color = img.get_pixel(x, y)
			if c.r <= 0.03 and c.g <= 0.03 and c.b <= 0.03:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
