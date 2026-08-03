extends Node
## Per-player usable-item feedback (self_modulate only — Labels stay white).
## P1 trap → red for P1. P2 turn → gold for all unused (never red). P2 use → off.

const GROUP := "usable_item"
const SHADER_PATH := "res://usable_shimmer.gdshader"

enum Mode { SHIMMER, TRAPPED_RED, OFF }

var _sprite: CanvasItem
var _mat: ShaderMaterial
var _t := 0.0
var _mode: Mode = Mode.SHIMMER
var p1_trapped := false
var p2_used := false


static func attach(sprite: CanvasItem) -> void:
	if sprite == null:
		return
	sprite.add_to_group(GROUP)
	if sprite.get_node_or_null("UsableShimmer") != null:
		return
	var node := new()
	node.name = "UsableShimmer"
	sprite.add_child.call_deferred(node)


static func _node_on(sprite: CanvasItem):
	if sprite == null:
		return null
	return sprite.get_node_or_null("UsableShimmer")


static func mark_trapped_p1(sprite: CanvasItem) -> void:
	var n = _node_on(sprite)
	if n and n.has_method("set_trapped_p1"):
		n.set_trapped_p1()


static func mark_used_p2(sprite: CanvasItem) -> void:
	var n = _node_on(sprite)
	if n and n.has_method("set_used_p2"):
		n.set_used_p2()


static func on_turn_changed(turn: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for sprite in tree.get_nodes_in_group(GROUP):
		var n = sprite.get_node_or_null("UsableShimmer")
		if n and n.has_method("apply_turn"):
			n.apply_turn(turn)


static func stop_on(sprite: CanvasItem) -> void:
	mark_used_p2(sprite)


## Full reset of every attached shimmer (dev bookmarks / test harness).
static func reset_all_to_default() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for sprite in tree.get_nodes_in_group(GROUP):
		var n = sprite.get_node_or_null("UsableShimmer")
		if n and n.has_method("reset_to_default"):
			n.reset_to_default()


## Force trap/used flags then refresh for the active turn.
static func force_state(sprite: CanvasItem, trapped: bool, used: bool, turn: String) -> void:
	var n = _node_on(sprite)
	if n and n.has_method("force_dev_state"):
		n.force_dev_state(trapped, used, turn)


func reset_to_default() -> void:
	p1_trapped = false
	p2_used = false
	_set_mode(Mode.SHIMMER)


func force_dev_state(trapped: bool, used: bool, turn: String) -> void:
	p1_trapped = trapped
	p2_used = used
	apply_turn(turn)


func _ready() -> void:
	_sprite = get_parent() as CanvasItem
	if _sprite == null:
		return
	_sprite.add_to_group(GROUP)
	_sprite.modulate = Color.WHITE
	var sh: Shader = load(SHADER_PATH)
	if sh != null:
		_mat = ShaderMaterial.new()
		_mat.shader = sh
	_set_mode(Mode.SHIMMER)


func _process(delta: float) -> void:
	if _sprite == null or _mode != Mode.SHIMMER:
		return
	_t += delta
	if _mat:
		_mat.set_shader_parameter("time", _t)
		_mat.set_shader_parameter("strength", 0.85)
	var pulse := 0.55 + 0.45 * sin(_t * 4.0)
	_sprite.self_modulate = Color(1.0, 0.88 + 0.12 * pulse, 0.45 + 0.2 * pulse, 1.0)


func set_trapped_p1() -> void:
	p1_trapped = true
	_set_mode(Mode.TRAPPED_RED)


func set_used_p2() -> void:
	p2_used = true
	_set_mode(Mode.OFF)


func apply_turn(turn: String) -> void:
	if turn == "Player2":
		# Never show red to P2 — always gold unless already used by P2
		if p2_used:
			_set_mode(Mode.OFF)
		else:
			_set_mode(Mode.SHIMMER)
	else:
		if p1_trapped:
			_set_mode(Mode.TRAPPED_RED)
		elif p2_used:
			_set_mode(Mode.OFF)
		else:
			_set_mode(Mode.SHIMMER)


func _set_mode(m: Mode) -> void:
	_mode = m
	if _sprite == null:
		return
	_sprite.modulate = Color.WHITE
	match m:
		Mode.SHIMMER:
			if _mat:
				_sprite.material = _mat
			_sprite.self_modulate = Color(1.0, 0.9, 0.5, 1.0)
			set_process(true)
		Mode.TRAPPED_RED:
			_sprite.material = null
			_sprite.self_modulate = Color(1.0, 0.35, 0.35, 1.0)
			set_process(false)
		Mode.OFF:
			_sprite.material = null
			_sprite.self_modulate = Color.WHITE
			set_process(false)
