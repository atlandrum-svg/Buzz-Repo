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
var _inv_panel: PanelContainer
var _inv_grid: HBoxContainer
## { "id": String, "trapped": bool, "slot": Control }
var _inv: Array = []


func _ready():
	player1.set_active(true)
	player2.set_active(false)
	set_process_input(true)
	call_deferred("_build_hud")


func switch_turn():
	if current_turn == "Player1":
		current_turn = "Player2"
		player1.set_active(false)
		player2.set_active(true)
	else:
		current_turn = "Player1"
		player1.set_active(true)
		player2.set_active(false)
	UsableShimmer.on_turn_changed(current_turn)
	call_deferred("_refresh_visuals")
	_update_inventory_visibility()


func consume_trap() -> bool:
	if current_turn != "Player1" or traps_left <= 0:
		return false
	traps_left -= 1
	_update_hud()
	if traps_left <= 0:
		switch_turn()
	return true


func consume_p2_use() -> bool:
	if current_turn != "Player2" or p2_items_used >= P2_USES_MAX:
		return false
	p2_items_used += 1
	_update_hud()
	if p2_items_used >= P2_USES_MAX:
		switch_turn()
	return true


func add_inventory_pill(trapped: bool) -> void:
	if _inv_grid == null:
		call_deferred("add_inventory_pill", trapped)
		return
	var tex: Texture2D = load("res://pill_bottle.png")

	# Plain Panel + icon — clicks handled in _input via global rect hit-test
	# (TextureButton was unreliable with game Input + camera zoom)
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(64, 64)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.focus_mode = Control.FOCUS_NONE
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var slot_style := StyleBoxFlat.new()
	slot_style.bg_color = Color(0.12, 0.1, 0.08, 0.9)
	slot_style.border_color = Color(0.95, 0.78, 0.28, 0.8)
	slot_style.set_border_width_all(2)
	slot_style.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("panel", slot_style)

	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 4
	icon.offset_top = 4
	icon.offset_right = -4
	icon.offset_bottom = -4
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.focus_mode = Control.FOCUS_NONE
	if tex:
		icon.texture = tex
	slot.add_child(icon)

	var entry := {"id": "pill", "trapped": trapped, "slot": slot}
	_inv.append(entry)
	_inv_grid.add_child(slot)
	_update_inventory_visibility()


## Global mouse hit-test for inventory slots (does not rely on Button signals).
func _input(event: InputEvent) -> void:
	if _inv.is_empty():
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var mouse: Vector2 = get_viewport().get_mouse_position()
	# Copy list so we can mutate during iterate
	for e in _inv.duplicate():
		var slot: Control = e.get("slot") as Control
		if slot == null or not is_instance_valid(slot):
			continue
		if not slot.is_visible_in_tree():
			continue
		var rect: Rect2 = slot.get_global_rect()
		if rect.has_point(mouse):
			_consume_inv_entry(e)
			get_viewport().set_input_as_handled()
			return


func _consume_inv_entry(entry: Dictionary) -> void:
	if not _inv.has(entry):
		# match by slot ref if dict identity differs
		var matched: Dictionary = {}
		var ok := false
		for e in _inv:
			if e.get("slot") == entry.get("slot"):
				matched = e
				ok = true
				break
		if not ok:
			return
		entry = matched
	_inv.erase(entry)
	var slot: Control = entry.get("slot") as Control
	if slot and is_instance_valid(slot):
		slot.queue_free()

	# Always apply clean speed boost for now (trap side-effect later).
	# If trapped, still remove from inv but skip boost.
	var was_trapped: bool = bool(entry.get("trapped", false))
	if not was_trapped:
		_apply_p2_speed_boost()
	else:
		# Still no trap effect — but show we consumed
		pass
	_update_inventory_visibility()


func _apply_p2_speed_boost() -> void:
	var p2: Node = null
	if is_instance_valid(player2):
		p2 = player2
	if p2 == null:
		p2 = get_node_or_null("/root/Main/Player2/Player2Body")
	if p2 == null:
		for b in get_tree().get_nodes_in_group("player_bodies"):
			if b.name == "Player2Body":
				p2 = b
				break
	if p2 == null:
		push_error("ADHD boost FAILED: Player2Body not found")
		return
	if p2.has_method("apply_adhd_boost"):
		p2.call("apply_adhd_boost")
	else:
		p2.set("speed_mult", 2.5)
		p2.set("speed", 200.0)
		p2.set("anim_speed", 0.07)
	# Confirm values stuck
	print("ADHD boost applied to ", p2, " speed=", p2.get("speed"), " mult=", p2.get("speed_mult"))


func _build_hud() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		scene = get_parent()
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "GameHUD"
	_hud_layer.layer = 100
	_hud_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	scene.add_child(_hud_layer)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_TOP_LEFT)
	vbox.offset_left = 16
	vbox.offset_top = 16
	vbox.add_theme_constant_override("separation", 10)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(vbox)

	_hud_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.82)
	style.border_color = Color(0.95, 0.78, 0.28, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	_hud_panel.add_theme_stylebox_override("panel", style)
	_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_hud_panel)

	_hud_label = Label.new()
	if ResourceLoader.exists("res://PressStart2P-Regular.ttf"):
		_hud_label.add_theme_font_override("font", load("res://PressStart2P-Regular.ttf"))
	_hud_label.add_theme_font_size_override("font_size", 14)
	_hud_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))
	_hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_panel.add_child(_hud_label)

	_inv_panel = PanelContainer.new()
	var inv_style := StyleBoxFlat.new()
	inv_style.bg_color = Color(0.08, 0.08, 0.12, 0.82)
	inv_style.border_color = Color(0.95, 0.78, 0.28, 0.95)
	inv_style.set_border_width_all(2)
	inv_style.set_corner_radius_all(6)
	inv_style.set_content_margin_all(10)
	_inv_panel.add_theme_stylebox_override("panel", inv_style)
	# Panel itself ignores so only slots catch clicks... actually panel can stop
	_inv_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_child(_inv_panel)

	var inv_vbox := VBoxContainer.new()
	inv_vbox.add_theme_constant_override("separation", 8)
	inv_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inv_panel.add_child(inv_vbox)

	var inv_title := Label.new()
	inv_title.text = "Inventory"
	if ResourceLoader.exists("res://PressStart2P-Regular.ttf"):
		inv_title.add_theme_font_override("font", load("res://PressStart2P-Regular.ttf"))
	inv_title.add_theme_font_size_override("font_size", 12)
	inv_title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))
	inv_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inv_vbox.add_child(inv_title)

	_inv_grid = HBoxContainer.new()
	_inv_grid.add_theme_constant_override("separation", 8)
	_inv_grid.custom_minimum_size = Vector2(180, 64)
	_inv_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inv_vbox.add_child(_inv_grid)

	_update_hud()
	_update_inventory_visibility()


func _update_inventory_visibility() -> void:
	if _inv_panel == null:
		return
	_inv_panel.visible = (current_turn == "Player2") or _inv.size() > 0


func _refresh_visuals() -> void:
	UsableShimmer.on_turn_changed(current_turn)
	_update_hud()
	_update_inventory_visibility()


func _update_hud() -> void:
	if _hud_label == null or _hud_layer == null:
		return
	if current_turn == "Player1":
		_hud_label.text = "Booby Traps: %d/%d" % [traps_left, TRAPS_MAX]
	else:
		_hud_label.text = "Items Used: %d/%d" % [p2_items_used, P2_USES_MAX]
	_hud_layer.visible = true
