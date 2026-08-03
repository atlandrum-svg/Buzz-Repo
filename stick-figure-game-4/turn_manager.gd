extends Node

const UsableShimmer = preload("res://usable_shimmer.gd")

@onready var player1 = $/root/Main/Player1/Player1Body
@onready var player2 = $/root/Main/Player2/Player2Body
var current_turn = "Player1"

const TRAPS_MAX := 3
const P2_USES_MAX := 3
var traps_left := TRAPS_MAX
var p2_items_used := 0

# HUD / dialog styling (matches Fizz PR art language)
const HUD_BG := Color(0.08, 0.08, 0.12, 0.82)
const HUD_BORDER := Color(0.95, 0.78, 0.28, 0.95)
const HUD_TEXT := Color(1.0, 0.92, 0.55, 1.0)
const HUD_FONT_SIZE := 14
const INV_PURPLE := Color(0.48, 0.30, 0.62, 0.98)

const ITEM_PILLS := "pills"

## Emitted when the player confirms Take on the Pills dialog.
signal pills_take_pressed
## Emitted when the player cancels / closes the Pills dialog.
signal pills_dialog_cancelled

var _hud_layer: CanvasLayer
var _hud_label: Label
var _hud_panel: PanelContainer
var _inv_panel: PanelContainer
var _inv_grid: HBoxContainer
## { "id": String, "trapped": bool, "slot": Control }
var _inv: Array = []

var _pixel_font: Font
var _pills_dialog: Control
var _pills_dialog_open: bool = false
## Inventory entry waiting on dialog confirm (Take).
var _pending_inv_entry: Dictionary = {}


func _ready():
	player1.set_active(true)
	player2.set_active(false)
	set_process_input(true)
	set_process_unhandled_input(true)
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

	var entry := {"id": ITEM_PILLS, "trapped": trapped, "slot": slot}
	_inv.append(entry)
	_inv_grid.add_child(slot)
	_update_inventory_visibility()


## Global mouse hit-test for inventory slots (does not rely on Button signals).
func _input(event: InputEvent) -> void:
	if _pills_dialog_open:
		return
	if _inv.is_empty():
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var mouse: Vector2 = get_viewport().get_mouse_position()
	for e in _inv.duplicate():
		var slot: Control = e.get("slot") as Control
		if slot == null or not is_instance_valid(slot):
			continue
		if not slot.is_visible_in_tree():
			continue
		var rect: Rect2 = slot.get_global_rect()
		if rect.has_point(mouse):
			_on_inventory_slot_selected(e)
			get_viewport().set_input_as_handled()
			return


func _on_inventory_slot_selected(entry: Dictionary) -> void:
	var id: String = String(entry.get("id", ""))
	if id == ITEM_PILLS or id == "pill":
		_pending_inv_entry = entry
		show_pills_dialog()
		return
	# Unknown items: no-op for now


func _consume_inv_entry(entry: Dictionary) -> void:
	if not _inv.has(entry):
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

	# Clean → ADHD boost. Booby-trapped → permanent drowsy (half speed + stooped sheet).
	var was_trapped: bool = bool(entry.get("trapped", false))
	if was_trapped:
		_apply_p2_drowsy_debuff()
	else:
		_apply_p2_speed_boost()
	_update_inventory_visibility()


func _get_player2_body() -> Node:
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
	return p2


func _apply_p2_speed_boost() -> void:
	var p2: Node = _get_player2_body()
	if p2 == null:
		push_error("ADHD boost FAILED: Player2Body not found")
		return
	if p2.has_method("apply_adhd_boost"):
		p2.call("apply_adhd_boost")
	else:
		p2.set("speed_mult", 2.5)
		p2.set("speed", 200.0)
		p2.set("anim_speed", 0.07)
	print("ADHD boost applied to ", p2, " speed=", p2.get("speed"), " mult=", p2.get("speed_mult"))


func _apply_p2_drowsy_debuff() -> void:
	var p2: Node = _get_player2_body()
	if p2 == null:
		push_error("Drowsy debuff FAILED: Player2Body not found")
		return
	if p2.has_method("apply_drowsy_debuff"):
		p2.call("apply_drowsy_debuff")
	else:
		p2.set("speed_mult", 1.0)
		p2.set("speed", 50.0)
		p2.set("anim_speed", 0.28)
	print("Drowsy debuff applied to ", p2, " speed=", p2.get("speed"), " mult=", p2.get("speed_mult"))


func _build_hud() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		scene = get_parent()
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "GameHUD"
	_hud_layer.layer = 100
	_hud_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	scene.add_child(_hud_layer)

	if ResourceLoader.exists("res://PressStart2P-Regular.ttf"):
		_pixel_font = load("res://PressStart2P-Regular.ttf")

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_TOP_LEFT)
	vbox.offset_left = 16
	vbox.offset_top = 16
	vbox.add_theme_constant_override("separation", 10)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(vbox)

	_hud_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = HUD_BG
	style.border_color = HUD_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	_hud_panel.add_theme_stylebox_override("panel", style)
	_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_hud_panel)

	_hud_label = Label.new()
	_apply_hud_label(_hud_label)
	_hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_panel.add_child(_hud_label)

	_inv_panel = PanelContainer.new()
	var inv_style := StyleBoxFlat.new()
	inv_style.bg_color = HUD_BG
	inv_style.border_color = HUD_BORDER
	inv_style.set_border_width_all(2)
	inv_style.set_corner_radius_all(6)
	inv_style.set_content_margin_all(10)
	_inv_panel.add_theme_stylebox_override("panel", inv_style)
	_inv_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_child(_inv_panel)

	var inv_vbox := VBoxContainer.new()
	inv_vbox.add_theme_constant_override("separation", 8)
	inv_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inv_panel.add_child(inv_vbox)

	var inv_title := Label.new()
	inv_title.text = "Inventory"
	_apply_hud_label(inv_title)
	inv_title.add_theme_font_size_override("font_size", 12)
	inv_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inv_vbox.add_child(inv_title)

	_inv_grid = HBoxContainer.new()
	_inv_grid.add_theme_constant_override("separation", 8)
	_inv_grid.custom_minimum_size = Vector2(180, 64)
	_inv_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inv_vbox.add_child(_inv_grid)

	_build_pills_dialog()
	_update_hud()
	_update_inventory_visibility()


## --- Pills confirm dialog (from Fizz PR #4 — surgically ported) ---

func _build_pills_dialog() -> void:
	var root := Control.new()
	root.name = "PillsDialog"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	_hud_layer.add_child(root)
	_pills_dialog = root

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.02, 0.05, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_pills_dim_gui_input)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	# Outer purple frame + inner gold panel
	var outer := PanelContainer.new()
	outer.name = "OuterFrame"
	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = INV_PURPLE
	outer_style.border_color = INV_PURPLE.lightened(0.15)
	outer_style.set_border_width_all(2)
	outer_style.set_corner_radius_all(6)
	outer_style.set_content_margin_all(4)
	outer.add_theme_stylebox_override("panel", outer_style)
	center.add_child(outer)

	var panel := PanelContainer.new()
	panel.name = "DialogPanel"
	var panel_style := _gold_panel_style(14)
	panel_style.bg_color = Color(0.12, 0.08, 0.10, 0.96)
	panel.add_theme_stylebox_override("panel", panel_style)
	outer.add_child(panel)

	var col := VBoxContainer.new()
	col.name = "Content"
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(220, 0)
	panel.add_child(col)

	var title := Label.new()
	_apply_hud_label(title)
	title.name = "Title"
	title.text = "Pills"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var icon_row := CenterContainer.new()
	col.add_child(icon_row)
	if ResourceLoader.exists("res://pill_bottle.png"):
		var icon := TextureRect.new()
		icon.texture = load("res://pill_bottle.png")
		icon.custom_minimum_size = Vector2(40, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_row.add_child(icon)

	var prompt := Label.new()
	_apply_hud_label(prompt)
	prompt.name = "Prompt"
	prompt.text = "Take pills?"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 10)
	col.add_child(prompt)

	var btn_row := HBoxContainer.new()
	btn_row.name = "Buttons"
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 10)
	col.add_child(btn_row)

	var take_btn := _make_dialog_button("Take", "TakeButton")
	take_btn.pressed.connect(_on_pills_take_pressed)
	btn_row.add_child(take_btn)

	var cancel_btn := _make_dialog_button("Cancel", "CancelButton")
	cancel_btn.pressed.connect(_on_pills_cancel_pressed)
	btn_row.add_child(cancel_btn)


func _make_dialog_button(text: String, node_name: String) -> Button:
	var btn := Button.new()
	btn.name = node_name
	btn.text = text
	btn.custom_minimum_size = Vector2(84, 28)
	btn.focus_mode = Control.FOCUS_ALL
	if _pixel_font != null:
		btn.add_theme_font_override("font", _pixel_font)
	btn.add_theme_font_size_override("font_size", 10)
	btn.add_theme_color_override("font_color", HUD_TEXT)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.75, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.72, 0.35, 1.0))
	btn.add_theme_stylebox_override("normal", _dialog_button_style(false, false))
	btn.add_theme_stylebox_override("hover", _dialog_button_style(true, false))
	btn.add_theme_stylebox_override("pressed", _dialog_button_style(false, true))
	btn.add_theme_stylebox_override("focus", _dialog_button_style(true, false))
	return btn


func _dialog_button_style(hover: bool, pressed: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if pressed:
		style.bg_color = Color(0.22, 0.14, 0.08, 0.98)
	elif hover:
		style.bg_color = Color(0.20, 0.14, 0.18, 0.96)
	else:
		style.bg_color = Color(0.10, 0.08, 0.12, 0.96)
	style.border_color = HUD_BORDER if (hover or pressed) else HUD_BORDER.darkened(0.15)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	return style


func show_pills_dialog() -> void:
	if _pills_dialog == null:
		return
	_pills_dialog.visible = true
	_pills_dialog_open = true
	var take_btn := _pills_dialog.find_child("TakeButton", true, false) as Button
	if take_btn:
		take_btn.grab_focus()


func hide_pills_dialog() -> void:
	if _pills_dialog == null:
		return
	_pills_dialog.visible = false
	_pills_dialog_open = false


func is_pills_dialog_open() -> bool:
	return _pills_dialog_open


func _on_pills_take_pressed() -> void:
	var entry: Dictionary = _pending_inv_entry
	_pending_inv_entry = {}
	hide_pills_dialog()
	pills_take_pressed.emit()
	if not entry.is_empty():
		_consume_inv_entry(entry)


func _on_pills_cancel_pressed() -> void:
	_pending_inv_entry = {}
	hide_pills_dialog()
	pills_dialog_cancelled.emit()


func _on_pills_dim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_pills_cancel_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if not _pills_dialog_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_pills_cancel_pressed()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_on_pills_take_pressed()
			get_viewport().set_input_as_handled()


func _gold_panel_style(content_margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = HUD_BG
	style.border_color = HUD_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(content_margin)
	return style


func _apply_hud_label(label: Label) -> void:
	if _pixel_font != null:
		label.add_theme_font_override("font", _pixel_font)
	label.add_theme_font_size_override("font_size", HUD_FONT_SIZE)
	label.add_theme_color_override("font_color", HUD_TEXT)


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
