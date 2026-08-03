extends Node

const UsableShimmer = preload("res://usable_shimmer.gd")

@onready var player1 = $/root/Main/Player1/Player1Body
@onready var player2 = $/root/Main/Player2/Player2Body
var current_turn = "Player1"

const TRAPS_MAX := 3
const P2_USES_MAX := 3
var traps_left := TRAPS_MAX
var p2_items_used := 0

var _hud_layer: CanvasLayer
var _hud_label: Label
var _hud_panel: PanelContainer

var _transition_layer: CanvasLayer
var _transition_label: Label
var _is_transitioning := false


func _ready():
	player1.set_active(true)
	player2.set_active(false)
	call_deferred("_build_hud")
	call_deferred("_build_transition_ui")


## True while the 3-2-1 handoff overlay is showing. Props/input should no-op.
func is_handoff_active() -> bool:
	return _is_transitioning


func switch_turn():
	if _is_transitioning:
		return
	var incoming_player := "Player 2" if current_turn == "Player1" else "Player 1"
	_is_transitioning = true
	# Freeze movement for both players during the handoff countdown.
	# Keep current player visible; only block physics + trap/use consumption.
	player1.set_physics_process(false)
	player2.set_physics_process(false)
	await _play_handoff_countdown(incoming_player)
	_is_transitioning = false

	if current_turn == "Player1":
		current_turn = "Player2"
		player1.set_active(false)
		player2.set_active(true)
	else:
		current_turn = "Player1"
		player1.set_active(true)
		player2.set_active(false)
	UsableShimmer.on_turn_changed(current_turn)
	# Deferred re-apply so deferred UsableShimmer children are ready; clears P1 red for P2
	call_deferred("_refresh_visuals")


func _play_handoff_countdown(incoming_player_label: String) -> void:
	if _transition_layer == null:
		_build_transition_ui()
	var prefix := "Switching to %s in " % incoming_player_label
	var counted := ""
	_transition_layer.visible = true
	for count in [3, 2, 1]:
		counted += "%d... " % count
		_transition_label.text = prefix + counted.strip_edges()
		await get_tree().create_timer(1.0).timeout
	_transition_layer.visible = false


## P1 places one trap. Switches to P2 only after all traps spent (not each placement).
func consume_trap() -> bool:
	if _is_transitioning or current_turn != "Player1" or traps_left <= 0:
		return false
	traps_left -= 1
	_update_hud()
	if traps_left <= 0:
		switch_turn()
	return true


## P2 uses/inspects one item. Switches turn only after 3 items used.
func consume_p2_use() -> bool:
	if _is_transitioning or current_turn != "Player2" or p2_items_used >= P2_USES_MAX:
		return false
	p2_items_used += 1
	_update_hud()
	if p2_items_used >= P2_USES_MAX:
		switch_turn()
	return true


func _build_hud() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		scene = get_parent()
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "GameHUD"
	_hud_layer.layer = 20
	scene.add_child(_hud_layer)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.offset_left = 16
	margin.offset_top = 16
	_hud_layer.add_child(margin)

	_hud_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.82)
	style.border_color = Color(0.95, 0.78, 0.28, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	_hud_panel.add_theme_stylebox_override("panel", style)
	margin.add_child(_hud_panel)

	_hud_label = Label.new()
	if ResourceLoader.exists("res://PressStart2P-Regular.ttf"):
		_hud_label.add_theme_font_override("font", load("res://PressStart2P-Regular.ttf"))
	_hud_label.add_theme_font_size_override("font_size", 14)
	_hud_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))
	_hud_panel.add_child(_hud_label)
	_update_hud()


func _build_transition_ui() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		scene = get_parent()
	_transition_layer = CanvasLayer.new()
	_transition_layer.name = "HandoffTransition"
	_transition_layer.layer = 30
	_transition_layer.visible = false
	scene.add_child(_transition_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_layer.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.92)
	style.border_color = Color(0.95, 0.78, 0.28, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	_transition_label = Label.new()
	if ResourceLoader.exists("res://PressStart2P-Regular.ttf"):
		_transition_label.add_theme_font_override("font", load("res://PressStart2P-Regular.ttf"))
	_transition_label.add_theme_font_size_override("font_size", 14)
	_transition_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))
	_transition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_transition_label)


func _refresh_visuals() -> void:
	UsableShimmer.on_turn_changed(current_turn)
	_update_hud()


func _update_hud() -> void:
	if _hud_label == null or _hud_layer == null:
		return
	if current_turn == "Player1":
		_hud_label.text = "Booby Traps: %d/%d" % [traps_left, TRAPS_MAX]
	else:
		_hud_label.text = "Items Used: %d/%d" % [p2_items_used, P2_USES_MAX]
	_hud_layer.visible = true
