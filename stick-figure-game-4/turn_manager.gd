extends Node

const UsableShimmer = preload("res://usable_shimmer.gd")

@onready var player1 = $/root/Main/Player1/Player1Body
@onready var player2 = $/root/Main/Player2/Player2Body
var current_turn = "Player1"

const TRAPS_MAX := 3
const P2_USES_MAX := 3
var traps_left := TRAPS_MAX
var p2_items_used := 0

## Placeholder character stats (0..STAT_MAX). Gameplay wires these later via setters.
const STAT_MAX := 100
var agility: int = 55
var charisma: int = 70
var intelligence: int = 40

# HUD / dialog styling (matches Fizz PR art language)
const HUD_BG := Color(0.08, 0.08, 0.12, 0.82)
const HUD_BORDER := Color(0.95, 0.78, 0.28, 0.95)
const HUD_TEXT := Color(1.0, 0.92, 0.55, 1.0)
const HUD_FONT_SIZE := 14
const BAR_FILL := Color(0.95, 0.78, 0.28, 1.0)
const BAR_EMPTY := Color(0.18, 0.16, 0.14, 0.95)
const INV_PURPLE := Color(0.48, 0.30, 0.62, 0.98)
const EFFECT_SLOT_PX := 28
const EFFECT_SLOT_BG := Color(0.10, 0.07, 0.06, 0.96)
const EFFECT_SLOT_BORDER := Color(0.22, 0.14, 0.10, 1.0)
const BUFF_BORDER := Color(0.35, 0.75, 0.40, 0.95)
const DEBUFF_BORDER := Color(0.85, 0.30, 0.35, 0.95)

const ITEM_PILLS := "pills"
const EFFECT_ADHD := "adhd_boost"
const EFFECT_DROWSY := "drowsy"
const EFFECT_VISHNU := "vishnu_demon"

## Emitted when the player confirms Take on the Pills dialog.
signal pills_take_pressed
## Emitted when the player cancels / closes the Pills dialog.
signal pills_dialog_cancelled

var _hud_layer: CanvasLayer
var _hud_label: Label
var _hud_panel: PanelContainer
var _sidebar: VBoxContainer
var _stat_bars: Dictionary = {} # name -> {fill: ColorRect, value_label: Label}
## Held consumables (gameplay bag — not a permanent empty inventory grid).
## { "id": String, "trapped": bool, "slot": Control }
var _inv: Array = []
var _inv_panel: PanelContainer
var _inv_grid: HBoxContainer

## Active buff/debuff icons: id -> { kind, texture, label, slot }
var _effects: Dictionary = {}
var _effects_panel: PanelContainer
var _buffs_row: HBoxContainer
var _debuffs_row: HBoxContainer
var _buffs_empty: Label
var _debuffs_empty: Label

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
	_update_held_items_visibility()


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


## --- Stat API (placeholder until real gameplay stats exist) ---

func set_agility(value: int) -> void:
	agility = clampi(value, 0, STAT_MAX)
	_refresh_stat_bar("Agility", agility)


func set_charisma(value: int) -> void:
	charisma = clampi(value, 0, STAT_MAX)
	_refresh_stat_bar("Charisma", charisma)


func set_intelligence(value: int) -> void:
	intelligence = clampi(value, 0, STAT_MAX)
	_refresh_stat_bar("Intelligence", intelligence)


func set_stats(agi: int, cha: int, intel: int) -> void:
	set_agility(agi)
	set_charisma(cha)
	set_intelligence(intel)


## --- Buff / Debuff status icons (sidebar under attributes) ---

## kind: "buff" or "debuff". Replaces any existing effect with the same id.
func add_status_effect(id: String, kind: String, texture: Texture2D = null, display_name: String = "") -> void:
	if id.is_empty():
		return
	remove_status_effect(id)
	var is_buff := kind.to_lower() != "debuff"
	var row: HBoxContainer = _buffs_row if is_buff else _debuffs_row
	if row == null:
		return
	var slot := _make_effect_slot(id, is_buff, texture, display_name)
	row.add_child(slot)
	_effects[id] = {
		"kind": "buff" if is_buff else "debuff",
		"texture": texture,
		"label": display_name,
		"slot": slot,
	}
	_refresh_effect_empty_labels()


func remove_status_effect(id: String) -> void:
	if not _effects.has(id):
		return
	var entry: Dictionary = _effects[id]
	var slot: Control = entry.get("slot") as Control
	if slot and is_instance_valid(slot):
		slot.queue_free()
	_effects.erase(id)
	_refresh_effect_empty_labels()


func clear_status_effects() -> void:
	for id in _effects.keys().duplicate():
		remove_status_effect(String(id))


func has_status_effect(id: String) -> bool:
	return _effects.has(id)


func add_inventory_pill(trapped: bool) -> void:
	if _inv_grid == null:
		call_deferred("add_inventory_pill", trapped)
		return
	var tex: Texture2D = load("res://pill_bottle.png")

	# Plain Panel + icon — clicks handled in _input via global rect hit-test
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(40, 40)
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
	icon.offset_left = 3
	icon.offset_top = 3
	icon.offset_right = -3
	icon.offset_bottom = -3
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
	_update_held_items_visibility()


## Global mouse hit-test for held-item slots (does not rely on Button signals).
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
	var pill_tex: Texture2D = null
	if ResourceLoader.exists("res://pill_bottle.png"):
		pill_tex = load("res://pill_bottle.png")
	if was_trapped:
		_apply_p2_drowsy_debuff()
		add_status_effect(EFFECT_DROWSY, "debuff", pill_tex, "Drowsy")
	else:
		_apply_p2_speed_boost()
		add_status_effect(EFFECT_ADHD, "buff", pill_tex, "ADHD")
	_update_held_items_visibility()


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

	var margin := MarginContainer.new()
	margin.name = "SidebarMargin"
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.offset_left = 16
	margin.offset_top = 16
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(margin)

	# Single column under the trap counter — stats + buffs/debuffs share this HUD root.
	_sidebar = VBoxContainer.new()
	_sidebar.name = "SidebarColumn"
	_sidebar.add_theme_constant_override("separation", 6)
	_sidebar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_sidebar)

	_build_trap_counter_panel()
	_build_stats_panel()
	_build_effects_panel()
	_build_held_items_panel()
	_build_pills_dialog()
	_update_hud()
	_update_held_items_visibility()


func _build_trap_counter_panel() -> void:
	_hud_panel = PanelContainer.new()
	_hud_panel.name = "TrapCounterPanel"
	_hud_panel.add_theme_stylebox_override("panel", _gold_panel_style(12))
	_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sidebar.add_child(_hud_panel)

	_hud_label = Label.new()
	_apply_hud_label(_hud_label)
	_hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_panel.add_child(_hud_label)


func _build_stats_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "StatsPanel"
	panel.add_theme_stylebox_override("panel", _gold_panel_style(10))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sidebar.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)

	for entry in [
		["Agility", agility],
		["Charisma", charisma],
		["Intelligence", intelligence],
	]:
		col.add_child(_make_stat_row(String(entry[0]), int(entry[1])))


func _make_stat_row(stat_name: String, value: int) -> Control:
	var row := VBoxContainer.new()
	row.name = "%sRow" % stat_name
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(header)

	var name_label := Label.new()
	_apply_hud_label(name_label)
	name_label.text = stat_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(name_label)

	var value_label := Label.new()
	_apply_hud_label(value_label)
	value_label.text = str(value)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(value_label)

	# Manual track + fill ColorRects (pixel-clear fill width; no ProgressBar theme quirks).
	const BAR_W := 148.0
	const BAR_H := 12.0
	var track := Control.new()
	track.name = "BarTrack"
	track.custom_minimum_size = Vector2(BAR_W, BAR_H)
	track.clip_contents = true
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(track)

	var border := ColorRect.new()
	border.color = HUD_BORDER.darkened(0.35)
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(border)

	var bg := ColorRect.new()
	bg.color = BAR_EMPTY
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.offset_left = 1
	bg.offset_top = 1
	bg.offset_right = -1
	bg.offset_bottom = -1
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(bg)

	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.color = BAR_FILL
	fill.position = Vector2(1, 1)
	fill.size = Vector2(0, BAR_H - 2)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)

	_stat_bars[stat_name] = {
		"fill": fill,
		"value_label": value_label,
		"bar_w": BAR_W - 2.0,
		"bar_h": BAR_H - 2.0,
	}
	_refresh_stat_bar(stat_name, value)
	return row


func _refresh_stat_bar(stat_name: String, value: int) -> void:
	if not _stat_bars.has(stat_name):
		return
	var entry: Dictionary = _stat_bars[stat_name]
	var v := clampi(value, 0, STAT_MAX)
	var ratio := float(v) / float(STAT_MAX)
	var fill: ColorRect = entry["fill"]
	var bar_w: float = entry["bar_w"]
	var bar_h: float = entry["bar_h"]
	fill.size = Vector2(bar_w * ratio, bar_h)
	var value_label: Label = entry["value_label"]
	value_label.text = str(v)


func _build_effects_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "EffectsPanel"
	panel.add_theme_stylebox_override("panel", _gold_panel_style(8))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sidebar.add_child(panel)
	_effects_panel = panel

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)

	var title := Label.new()
	_apply_hud_label(title)
	title.text = "Buffs & Debuffs"
	title.add_theme_font_size_override("font_size", 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)

	# Buffs row
	var buff_label := Label.new()
	_apply_hud_label(buff_label)
	buff_label.text = "Buffs"
	buff_label.add_theme_font_size_override("font_size", 8)
	buff_label.add_theme_color_override("font_color", BUFF_BORDER)
	buff_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(buff_label)

	_buffs_row = HBoxContainer.new()
	_buffs_row.name = "BuffsRow"
	_buffs_row.add_theme_constant_override("separation", 4)
	_buffs_row.custom_minimum_size = Vector2(148, EFFECT_SLOT_PX)
	_buffs_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_buffs_row)

	_buffs_empty = Label.new()
	_apply_hud_label(_buffs_empty)
	_buffs_empty.name = "BuffsEmpty"
	_buffs_empty.text = "—"
	_buffs_empty.add_theme_font_size_override("font_size", 8)
	_buffs_empty.add_theme_color_override("font_color", Color(0.55, 0.50, 0.40, 0.85))
	_buffs_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buffs_row.add_child(_buffs_empty)

	# Debuffs row
	var debuff_label := Label.new()
	_apply_hud_label(debuff_label)
	debuff_label.text = "Debuffs"
	debuff_label.add_theme_font_size_override("font_size", 8)
	debuff_label.add_theme_color_override("font_color", DEBUFF_BORDER)
	debuff_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(debuff_label)

	_debuffs_row = HBoxContainer.new()
	_debuffs_row.name = "DebuffsRow"
	_debuffs_row.add_theme_constant_override("separation", 4)
	_debuffs_row.custom_minimum_size = Vector2(148, EFFECT_SLOT_PX)
	_debuffs_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_debuffs_row)

	_debuffs_empty = Label.new()
	_apply_hud_label(_debuffs_empty)
	_debuffs_empty.name = "DebuffsEmpty"
	_debuffs_empty.text = "—"
	_debuffs_empty.add_theme_font_size_override("font_size", 8)
	_debuffs_empty.add_theme_color_override("font_color", Color(0.55, 0.50, 0.40, 0.85))
	_debuffs_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debuffs_row.add_child(_debuffs_empty)


func _make_effect_slot(id: String, is_buff: bool, texture: Texture2D, display_name: String) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.name = "Effect_%s" % id
	slot.custom_minimum_size = Vector2(EFFECT_SLOT_PX, EFFECT_SLOT_PX)
	slot.tooltip_text = display_name if not display_name.is_empty() else id
	var style := StyleBoxFlat.new()
	style.bg_color = EFFECT_SLOT_BG
	style.border_color = BUFF_BORDER if is_buff else DEBUFF_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(2)
	slot.add_theme_stylebox_override("panel", style)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if texture != null:
		var icon := TextureRect.new()
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(EFFECT_SLOT_PX - 6, EFFECT_SLOT_PX - 6)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
	else:
		var fallback := Label.new()
		_apply_hud_label(fallback)
		fallback.text = display_name.left(2).to_upper() if not display_name.is_empty() else "?"
		fallback.add_theme_font_size_override("font_size", 8)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(fallback)
	return slot


func _refresh_effect_empty_labels() -> void:
	var has_buff := false
	var has_debuff := false
	for id in _effects:
		var kind: String = String(_effects[id].get("kind", ""))
		if kind == "buff":
			has_buff = true
		else:
			has_debuff = true
	if _buffs_empty and is_instance_valid(_buffs_empty):
		_buffs_empty.visible = not has_buff
	if _debuffs_empty and is_instance_valid(_debuffs_empty):
		_debuffs_empty.visible = not has_debuff


## Held consumables only appear while the player is carrying something.
## Not a permanent inventory grid — bag UI for use-before-effect.
func _build_held_items_panel() -> void:
	_inv_panel = PanelContainer.new()
	_inv_panel.name = "HeldItemsPanel"
	_inv_panel.add_theme_stylebox_override("panel", _gold_panel_style(8))
	_inv_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_inv_panel.visible = false
	_sidebar.add_child(_inv_panel)

	var inv_vbox := VBoxContainer.new()
	inv_vbox.add_theme_constant_override("separation", 6)
	inv_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inv_panel.add_child(inv_vbox)

	var inv_title := Label.new()
	inv_title.text = "Use"
	_apply_hud_label(inv_title)
	inv_title.add_theme_font_size_override("font_size", 10)
	inv_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inv_vbox.add_child(inv_title)

	_inv_grid = HBoxContainer.new()
	_inv_grid.name = "HeldGrid"
	_inv_grid.add_theme_constant_override("separation", 6)
	_inv_grid.custom_minimum_size = Vector2(148, 40)
	_inv_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inv_vbox.add_child(_inv_grid)


## --- Pills confirm dialog ---

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


func _update_held_items_visibility() -> void:
	if _inv_panel == null:
		return
	# Only show while carrying something (no permanent empty inventory grid).
	_inv_panel.visible = _inv.size() > 0


func _refresh_visuals() -> void:
	UsableShimmer.on_turn_changed(current_turn)
	_update_hud()
	_update_held_items_visibility()


func _update_hud() -> void:
	if _hud_label == null or _hud_layer == null:
		return
	if current_turn == "Player1":
		_hud_label.text = "Booby Traps: %d/%d" % [traps_left, TRAPS_MAX]
	else:
		_hud_label.text = "Items Used: %d/%d" % [p2_items_used, P2_USES_MAX]
	# Same visibility rule as before: whole GameHUD layer (counter + stats + effects).
	_hud_layer.visible = true
	_refresh_stat_bar("Agility", agility)
	_refresh_stat_bar("Charisma", charisma)
	_refresh_stat_bar("Intelligence", intelligence)
