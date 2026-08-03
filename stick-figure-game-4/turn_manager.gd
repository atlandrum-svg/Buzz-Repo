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

## Compact sidebar inventory (visual language from TRAPS menu design — not full 4×4 modal).
## 6 slots = 3 cols × 2 rows (matches gameplay inventory size).
const INV_COLS := 3
const INV_ROWS := 2
const INV_SLOT_PX := 28

# HUD shared styling (trap counter panel)
const HUD_BG := Color(0.08, 0.08, 0.12, 0.82)
const HUD_BORDER := Color(0.95, 0.78, 0.28, 0.95)
const HUD_TEXT := Color(1.0, 0.92, 0.55, 1.0)
const HUD_FONT_SIZE := 14
const BAR_FILL := Color(0.95, 0.78, 0.28, 1.0)
const BAR_EMPTY := Color(0.18, 0.16, 0.14, 0.95)

# Inventory panel (wood + purple frame from approved TRAPS mockup)
const INV_WOOD := Color(0.36, 0.22, 0.12, 0.94)
const INV_PURPLE := Color(0.48, 0.30, 0.62, 0.98)
const INV_SLOT_BG := Color(0.10, 0.07, 0.06, 0.96)
const INV_SLOT_BORDER := Color(0.22, 0.14, 0.10, 1.0)

var _hud_layer: CanvasLayer
var _hud_label: Label
var _hud_panel: PanelContainer
var _sidebar: VBoxContainer
var _stat_bars: Dictionary = {} # name -> {fill: ColorRect, value_label: Label}
var _inv_slots: Array = [] # Array of PanelContainer
var _pixel_font: Font


func _ready():
	player1.set_active(true)
	player2.set_active(false)
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
	# Deferred re-apply so deferred UsableShimmer children are ready; clears P1 red for P2
	call_deferred("_refresh_visuals")


## P1 places one trap. Switches to P2 only after all traps spent.
func consume_trap() -> bool:
	if current_turn != "Player1" or traps_left <= 0:
		return false
	traps_left -= 1
	_update_hud()
	if traps_left <= 0:
		switch_turn()
	return true


## P2 uses/inspects one item. Switches turn only after 3 items used.
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


func _build_hud() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		scene = get_parent()
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "GameHUD"
	_hud_layer.layer = 20
	scene.add_child(_hud_layer)

	if ResourceLoader.exists("res://PressStart2P-Regular.ttf"):
		_pixel_font = load("res://PressStart2P-Regular.ttf")

	var margin := MarginContainer.new()
	margin.name = "SidebarMargin"
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.offset_left = 16
	margin.offset_top = 16
	_hud_layer.add_child(margin)

	# Single column under the trap counter — stats + inventory share this HUD root.
	_sidebar = VBoxContainer.new()
	_sidebar.name = "SidebarColumn"
	_sidebar.add_theme_constant_override("separation", 6)
	margin.add_child(_sidebar)

	_build_trap_counter_panel()
	_build_stats_panel()
	_build_inventory_panel()
	_update_hud()


func _build_trap_counter_panel() -> void:
	_hud_panel = PanelContainer.new()
	_hud_panel.name = "TrapCounterPanel"
	_hud_panel.add_theme_stylebox_override("panel", _gold_panel_style(12))
	_sidebar.add_child(_hud_panel)

	_hud_label = Label.new()
	_apply_hud_label(_hud_label)
	_hud_panel.add_child(_hud_label)


func _build_stats_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "StatsPanel"
	panel.add_theme_stylebox_override("panel", _gold_panel_style(10))
	_sidebar.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
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

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	row.add_child(header)

	var name_label := Label.new()
	_apply_hud_label(name_label)
	name_label.text = stat_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	var value_label := Label.new()
	_apply_hud_label(value_label)
	value_label.text = str(value)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(value_label)

	# Manual track + fill ColorRects (pixel-clear fill width; no ProgressBar theme quirks).
	const BAR_W := 148.0
	const BAR_H := 12.0
	var track := Control.new()
	track.name = "BarTrack"
	track.custom_minimum_size = Vector2(BAR_W, BAR_H)
	track.clip_contents = true
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(track)

	var border := ColorRect.new()
	border.color = HUD_BORDER.darkened(0.35)
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.add_child(border)

	var bg := ColorRect.new()
	bg.color = BAR_EMPTY
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.offset_left = 1
	bg.offset_top = 1
	bg.offset_right = -1
	bg.offset_bottom = -1
	track.add_child(bg)

	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.color = BAR_FILL
	fill.position = Vector2(1, 1)
	fill.size = Vector2(0, BAR_H - 2)
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


func _build_inventory_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "InventoryPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = INV_WOOD
	style.border_color = INV_PURPLE
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	_sidebar.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	var title := Label.new()
	_apply_hud_label(title)
	title.text = "INVENTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var grid_wrap := CenterContainer.new()
	grid_wrap.name = "SlotGridWrap"
	col.add_child(grid_wrap)

	var grid := GridContainer.new()
	grid.name = "SlotGrid"
	grid.columns = INV_COLS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid_wrap.add_child(grid)

	_inv_slots.clear()
	for i in range(INV_COLS * INV_ROWS):
		var slot := _make_inventory_slot(i)
		grid.add_child(slot)
		_inv_slots.append(slot)


func _make_inventory_slot(index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.name = "Slot%d" % index
	slot.custom_minimum_size = Vector2(INV_SLOT_PX, INV_SLOT_PX)
	var style := StyleBoxFlat.new()
	style.bg_color = INV_SLOT_BG
	style.border_color = INV_SLOT_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(2)
	slot.add_theme_stylebox_override("panel", style)
	# Empty recessed cell (icons/qty wired later via set_inventory_slot).
	var pad := ColorRect.new()
	pad.color = Color(0, 0, 0, 0)
	pad.custom_minimum_size = Vector2(INV_SLOT_PX - 6, INV_SLOT_PX - 6)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(pad)
	return slot


## Optional later hook: put an icon texture into a compact sidebar slot.
func set_inventory_slot(index: int, texture: Texture2D = null, qty: int = 0) -> void:
	if index < 0 or index >= _inv_slots.size():
		return
	var slot: PanelContainer = _inv_slots[index]
	for child in slot.get_children():
		child.queue_free()
	if texture == null:
		var pad := ColorRect.new()
		pad.color = Color(0, 0, 0, 0)
		pad.custom_minimum_size = Vector2(INV_SLOT_PX - 6, INV_SLOT_PX - 6)
		slot.add_child(pad)
		return
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(INV_SLOT_PX - 4, INV_SLOT_PX - 4)
	slot.add_child(holder)
	var icon := TextureRect.new()
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	holder.add_child(icon)
	if qty > 0:
		var qty_label := Label.new()
		_apply_hud_label(qty_label)
		qty_label.add_theme_font_size_override("font_size", 8)
		qty_label.text = "x%d" % qty
		qty_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		qty_label.offset_left = -20
		qty_label.offset_top = -12
		holder.add_child(qty_label)


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
	# Same visibility rule as before: whole GameHUD layer (counter + stats + inventory).
	_hud_layer.visible = true
	# Bars may need a layout pass after first frame when track sizes settle.
	_refresh_stat_bar("Agility", agility)
	_refresh_stat_bar("Charisma", charisma)
	_refresh_stat_bar("Intelligence", intelligence)
