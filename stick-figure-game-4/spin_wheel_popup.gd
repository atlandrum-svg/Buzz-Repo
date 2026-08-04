extends Control
## Fate wheel: stock 3-slice wheel, then buffs → debuffs animate onto it and
## reshape weights. Left = Buffs/Debuffs strip, center = wheel, right = dialog.
##
## show_and_spin(title, effects) -> { index, id, label, weights }

signal spin_finished(result: Dictionary)

const ID_ATTACK := "attack"
const ID_SCHMOOZE := "schmooze"
const ID_SEDUCE := "seduce"
const ID_POSSESS := "possess"

const LABEL_ATTACK := "Attack Fireman"
const LABEL_SCHMOOZE := "Smooze Fireman"
const LABEL_SEDUCE := "Seduce Fireman"
const LABEL_POSSESS := "Possess Fireman"

const SHORT_ATTACK := "ATTACK"
const SHORT_SCHMOOZE := "SMOOZE"
const SHORT_SEDUCE := "SEDUCE"
const SHORT_POSSESS := "POSSESS"

const COLOR_ATTACK := Color(0.85, 0.28, 0.28, 1.0)
const COLOR_SCHMOOZE := Color(0.95, 0.72, 0.22, 1.0)
const COLOR_SEDUCE := Color(0.45, 0.35, 0.85, 1.0)
const COLOR_POSSESS := Color(0.55, 0.18, 0.70, 1.0)

const WHEEL_R := 112.0
const HUB_R := 16.0
const RIM := 6.0
const PANEL_H := 360.0
const SIDE_W := 168.0
const DIALOG_W := 200.0

## Spin ~2× longer than the original tune (min ~5.6s, cap ~13s).
const SPIN_VEL_MIN := 980.0
const SPIN_VEL_MAX := 1380.0
const FRICTION_START := 60.0 ## deg/s² early (half prior → longer coast)
const FRICTION_END := 210.0 ## deg/s² near stop
const STOP_VEL := 12.0
const MIN_SPIN_SEC := 5.6
const MAX_SPIN_SEC := 13.0

const INV_PURPLE := Color(0.48, 0.30, 0.62, 0.98)
const HUD_BORDER := Color(0.95, 0.78, 0.28, 0.95)
const HUD_TEXT := Color(1.0, 0.92, 0.55, 1.0)
const BUFF_BORDER := Color(0.35, 0.75, 0.40, 0.95)
const DEBUFF_BORDER := Color(0.85, 0.30, 0.35, 0.95)
const EFFECT_SLOT_PX := 32
const EFFECT_SLOT_BG := Color(0.10, 0.07, 0.06, 0.96)

## Known effect ids from turn_manager
const EFF_ADHD := "adhd_boost"
const EFF_DROWSY := "drowsy"
const EFF_VISHNU := "vishnu_demon"

var _pixel_font: Font
var _wheel_rot_deg: float = 0.0
var _spinning: bool = false
var _built: bool = false

## Ordered segment data: {id, label, short, color, weight}
var _segs: Array = []
var _title_label: Label
var _result_label: Label
var _dialog_label: Label
var _start_btn: Button
var _wheel_host: Control
var _needle: Control
var _stage: Control
var _buffs_row: HBoxContainer
var _debuffs_row: HBoxContainer
var _buffs_empty: Label
var _debuffs_empty: Label
var _perm_slots: Dictionary = {} ## id -> Control (permanent icons in left panel)
var _float_layer: Control
var _center_row: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists("res://PressStart2P-Regular.ttf"):
		_pixel_font = load("res://PressStart2P-Regular.ttf")
	_build_ui()


func _stock_segments() -> Array:
	var w := 1.0 / 3.0
	return [
		{"id": ID_ATTACK, "label": LABEL_ATTACK, "short": SHORT_ATTACK, "color": COLOR_ATTACK, "weight": w},
		{"id": ID_SCHMOOZE, "label": LABEL_SCHMOOZE, "short": SHORT_SCHMOOZE, "color": COLOR_SCHMOOZE, "weight": w},
		{"id": ID_SEDUCE, "label": LABEL_SEDUCE, "short": SHORT_SEDUCE, "color": COLOR_SEDUCE, "weight": w},
	]


func _build_ui() -> void:
	if _built:
		return
	_built = true

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.68)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# Floating icons draw above panels.
	_float_layer = Control.new()
	_float_layer.name = "FloatLayer"
	_float_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_float_layer)

	var outer := PanelContainer.new()
	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = INV_PURPLE
	outer_style.border_color = INV_PURPLE.lightened(0.15)
	outer_style.set_border_width_all(3)
	outer_style.set_corner_radius_all(8)
	outer_style.set_content_margin_all(6)
	outer.add_theme_stylebox_override("panel", outer_style)
	center.add_child(outer)

	var body := PanelContainer.new()
	var body_style := StyleBoxFlat.new()
	body_style.bg_color = Color(0.12, 0.08, 0.10, 0.96)
	body_style.border_color = HUD_BORDER
	body_style.set_border_width_all(2)
	body_style.set_corner_radius_all(6)
	body_style.set_content_margin_all(12)
	body.add_theme_stylebox_override("panel", body_style)
	outer.add_child(body)

	var root_col := VBoxContainer.new()
	root_col.add_theme_constant_override("separation", 10)
	body.add_child(root_col)

	_title_label = Label.new()
	_title_label.text = "FATE WHEEL"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(_title_label, 13, HUD_TEXT)
	root_col.add_child(_title_label)

	_center_row = HBoxContainer.new()
	_center_row.add_theme_constant_override("separation", 10)
	_center_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root_col.add_child(_center_row)

	# --- Left: Buffs & Debuffs (same height as wheel column) ---
	var left := _make_side_panel("StatusPanel")
	left.custom_minimum_size = Vector2(SIDE_W, PANEL_H)
	_center_row.add_child(left)
	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 8)
	left.add_child(left_col)

	var st := Label.new()
	st.text = "Buffs & Debuffs"
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(st, 9, HUD_TEXT)
	left_col.add_child(st)

	var bl := Label.new()
	bl.text = "Buffs"
	_style_label(bl, 8, BUFF_BORDER)
	left_col.add_child(bl)
	_buffs_row = HBoxContainer.new()
	_buffs_row.add_theme_constant_override("separation", 4)
	_buffs_row.custom_minimum_size = Vector2(SIDE_W - 24, EFFECT_SLOT_PX + 4)
	left_col.add_child(_buffs_row)
	_buffs_empty = Label.new()
	_buffs_empty.text = "—"
	_style_label(_buffs_empty, 8, Color(0.55, 0.5, 0.4, 0.85))
	_buffs_row.add_child(_buffs_empty)

	var dl := Label.new()
	dl.text = "Debuffs"
	_style_label(dl, 8, DEBUFF_BORDER)
	left_col.add_child(dl)
	_debuffs_row = HBoxContainer.new()
	_debuffs_row.add_theme_constant_override("separation", 4)
	_debuffs_row.custom_minimum_size = Vector2(SIDE_W - 24, EFFECT_SLOT_PX + 4)
	left_col.add_child(_debuffs_row)
	_debuffs_empty = Label.new()
	_debuffs_empty.text = "—"
	_style_label(_debuffs_empty, 8, Color(0.55, 0.5, 0.4, 0.85))
	_debuffs_row.add_child(_debuffs_empty)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(spacer)

	var legend := Label.new()
	legend.name = "WeightLegend"
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.custom_minimum_size = Vector2(SIDE_W - 28, 0)
	_style_label(legend, 7, Color(0.9, 0.88, 0.8, 0.95))
	left_col.add_child(legend)

	# --- Center: wheel ---
	var mid := _make_side_panel("WheelPanel")
	mid.custom_minimum_size = Vector2(PANEL_H - 40.0, PANEL_H)
	_center_row.add_child(mid)
	var mid_col := VBoxContainer.new()
	mid_col.add_theme_constant_override("separation", 8)
	mid_col.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_child(mid_col)

	_stage = Control.new()
	_stage.custom_minimum_size = Vector2(280, 280)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid_col.add_child(_stage)

	_wheel_host = Control.new()
	_wheel_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wheel_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel_host.draw.connect(_draw_wheel)
	_stage.add_child(_wheel_host)

	_needle = Control.new()
	_needle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_needle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_needle.draw.connect(_draw_needle)
	_stage.add_child(_needle)

	_result_label = Label.new()
	_result_label.text = ""
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.custom_minimum_size = Vector2(260, 0)
	_style_label(_result_label, 10, Color(1, 1, 1, 1))
	mid_col.add_child(_result_label)

	_start_btn = Button.new()
	_start_btn.text = "START"
	_start_btn.custom_minimum_size = Vector2(140, 32)
	_start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_start_button(_start_btn)
	_start_btn.visible = false
	_start_btn.disabled = true
	mid_col.add_child(_start_btn)

	# --- Right: dialog ---
	var right := _make_side_panel("DialogPanel")
	right.custom_minimum_size = Vector2(DIALOG_W, PANEL_H)
	_center_row.add_child(right)
	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 8)
	right.add_child(right_col)

	var rt := Label.new()
	rt.text = "What is happening"
	rt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(rt, 9, HUD_TEXT)
	right_col.add_child(rt)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(DIALOG_W - 20, PANEL_H - 50)
	right_col.add_child(scroll)

	_dialog_label = Label.new()
	_dialog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_label.custom_minimum_size = Vector2(DIALOG_W - 36, 0)
	_style_label(_dialog_label, 9, Color(1, 1, 1, 1))
	scroll.add_child(_dialog_label)


func _make_side_panel(panel_name: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = panel_name
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.06, 0.08, 0.94)
	st.border_color = HUD_BORDER.darkened(0.1)
	st.set_border_width_all(2)
	st.set_corner_radius_all(6)
	st.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", st)
	return p


func _style_label(lab: Label, size: int, color: Color) -> void:
	if _pixel_font:
		lab.add_theme_font_override("font", _pixel_font)
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", color)


func _style_start_button(btn: Button) -> void:
	if _pixel_font:
		btn.add_theme_font_override("font", _pixel_font)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(0.05, 0.04, 0.02, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.12, 0.08, 0.04, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.35, 0.3, 0.22, 0.7))
	var normal := StyleBoxFlat.new()
	normal.bg_color = HUD_BORDER
	normal.border_color = Color(0.55, 0.4, 0.12, 1.0)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(4)
	normal.set_content_margin_all(8)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1.0, 0.88, 0.4, 1.0)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.75, 0.58, 0.18, 1.0)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.35, 0.3, 0.2, 0.75)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus", hover)


func _set_dialog(text: String) -> void:
	if _dialog_label:
		_dialog_label.text = text


## Shows START and waits until the player presses it (so they can read first).
func _wait_for_start(prompt: String = "Press START when ready.") -> void:
	if _start_btn == null:
		return
	if _result_label:
		_result_label.text = prompt
	_start_btn.visible = true
	_start_btn.disabled = false
	_start_btn.grab_focus()
	await _start_btn.pressed
	_start_btn.disabled = true
	_start_btn.visible = false


func _weights_summary() -> String:
	var lines: PackedStringArray = []
	for s in _segs:
		var pct: int = int(round(float(s["weight"]) * 100.0))
		lines.append("%s %d%%" % [String(s["short"]), pct])
	return "\n".join(lines)


func _refresh_legend() -> void:
	var legend := _center_row.find_child("WeightLegend", true, false) as Label
	if legend:
		legend.text = _weights_summary()
	if _wheel_host:
		_wheel_host.queue_redraw()
	if _needle:
		_needle.queue_redraw()


func _seg_index(id: String) -> int:
	for i in _segs.size():
		if String(_segs[i]["id"]) == id:
			return i
	return -1


func _get_weight(id: String) -> float:
	var i := _seg_index(id)
	if i < 0:
		return 0.0
	return float(_segs[i]["weight"])


func _set_weight(id: String, w: float) -> void:
	var i := _seg_index(id)
	if i < 0:
		return
	_segs[i]["weight"] = maxf(w, 0.0)


func _normalize_weights() -> void:
	var total := 0.0
	for s in _segs:
		total += float(s["weight"])
	if total <= 0.0001:
		var eq := 1.0 / float(_segs.size())
		for s in _segs:
			s["weight"] = eq
		return
	for s in _segs:
		s["weight"] = float(s["weight"]) / total


## Attack *= 1.5; excess taken from other slices proportionally.
func _apply_attack_boost_50() -> void:
	var a := _get_weight(ID_ATTACK)
	var a_new := a * 1.5
	var others_total := 1.0 - a
	if others_total <= 0.0001:
		_set_weight(ID_ATTACK, 1.0)
		_normalize_weights()
		return
	var remain := 1.0 - a_new
	if remain < 0.0:
		a_new = 0.95
		remain = 0.05
	_set_weight(ID_ATTACK, a_new)
	for s in _segs:
		var id: String = String(s["id"])
		if id == ID_ATTACK:
			continue
		var share: float = float(s["weight"]) / others_total
		s["weight"] = remain * share
	_normalize_weights()


## Schmooze *= 0.5; freed weight redistributed to other non-schmooze slices.
func _apply_schmooze_cut_50() -> void:
	var s0 := _get_weight(ID_SCHMOOZE)
	var s_new := s0 * 0.5
	var freed := s0 - s_new
	_set_weight(ID_SCHMOOZE, s_new)
	var others := 0.0
	for seg in _segs:
		if String(seg["id"]) != ID_SCHMOOZE:
			others += float(seg["weight"])
	if others <= 0.0001:
		_normalize_weights()
		return
	for seg in _segs:
		if String(seg["id"]) == ID_SCHMOOZE:
			continue
		var share: float = float(seg["weight"]) / others
		seg["weight"] = float(seg["weight"]) + freed * share
	_normalize_weights()


## Possess fixed 25%; prior three keep ratios inside remaining 75%.
func _apply_possess_25() -> void:
	if _seg_index(ID_POSSESS) >= 0:
		return
	# Scale existing to 75%
	for s in _segs:
		s["weight"] = float(s["weight"]) * 0.75
	_segs.append({
		"id": ID_POSSESS,
		"label": LABEL_POSSESS,
		"short": SHORT_POSSESS,
		"color": COLOR_POSSESS,
		"weight": 0.25,
	})
	_normalize_weights()


func _draw_wheel() -> void:
	if _wheel_host == null or _segs.is_empty():
		return
	var c: Vector2 = _wheel_host.size * 0.5
	var r: float = WHEEL_R
	_wheel_host.draw_circle(c, r + RIM, Color(0.12, 0.08, 0.06, 1.0))
	_wheel_host.draw_circle(c, r + RIM - 2.0, HUD_BORDER.darkened(0.15))

	var cursor: float = _wheel_rot_deg - 90.0
	for s in _segs:
		var span: float = float(s["weight"]) * 360.0
		var start_deg: float = cursor
		var end_deg: float = cursor + span
		_draw_slice(_wheel_host, c, r, start_deg, end_deg, s["color"])
		var mid: float = deg_to_rad((start_deg + end_deg) * 0.5)
		var lp: Vector2 = c + Vector2(cos(mid), sin(mid)) * (r * 0.52)
		_draw_centered_text(_wheel_host, lp, String(s["short"]), Color(0.05, 0.04, 0.03, 1.0), 9)
		cursor = end_deg

	_wheel_host.draw_circle(c, HUB_R + 3.0, Color(0.1, 0.08, 0.06, 1.0))
	_wheel_host.draw_circle(c, HUB_R, HUD_BORDER)
	_wheel_host.draw_circle(c, HUB_R - 5.0, Color(0.18, 0.12, 0.1, 1.0))


func _draw_needle() -> void:
	if _needle == null:
		return
	var c: Vector2 = _needle.size * 0.5
	var tip_y: float = c.y - WHEEL_R - 4.0
	var pts := PackedVector2Array([
		Vector2(c.x, tip_y + 28.0),
		Vector2(c.x - 14.0, tip_y - 6.0),
		Vector2(c.x - 5.0, tip_y - 6.0),
		Vector2(c.x - 5.0, tip_y - 22.0),
		Vector2(c.x + 5.0, tip_y - 22.0),
		Vector2(c.x + 5.0, tip_y - 6.0),
		Vector2(c.x + 14.0, tip_y - 6.0),
	])
	_needle.draw_colored_polygon(pts, Color(0.08, 0.05, 0.03, 1.0))
	var inset := PackedVector2Array([
		Vector2(c.x, tip_y + 24.0),
		Vector2(c.x - 11.0, tip_y - 4.0),
		Vector2(c.x - 3.5, tip_y - 4.0),
		Vector2(c.x - 3.5, tip_y - 18.0),
		Vector2(c.x + 3.5, tip_y - 18.0),
		Vector2(c.x + 3.5, tip_y - 4.0),
		Vector2(c.x + 11.0, tip_y - 4.0),
	])
	_needle.draw_colored_polygon(inset, Color(1.0, 0.86, 0.28, 1.0))
	_needle.draw_circle(Vector2(c.x, tip_y - 14.0), 4.0, Color(0.2, 0.14, 0.08, 1.0))
	_needle.draw_circle(Vector2(c.x, tip_y - 14.0), 2.5, HUD_BORDER)


func _draw_slice(host: Control, center: Vector2, radius: float, start_deg: float, end_deg: float, color: Color) -> void:
	var pts := PackedVector2Array()
	pts.append(center)
	var steps: int = maxi(12, int((end_deg - start_deg) / 4.0))
	for s in range(steps + 1):
		var t: float = float(s) / float(steps)
		var a: float = deg_to_rad(lerpf(start_deg, end_deg, t))
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	host.draw_colored_polygon(pts, color)
	var a0: float = deg_to_rad(start_deg)
	host.draw_line(center, center + Vector2(cos(a0), sin(a0)) * radius, Color(0.08, 0.05, 0.03, 0.85), 2.5)


func _draw_centered_text(host: Control, pos: Vector2, text: String, color: Color, fs: int = 10) -> void:
	var font: Font = _pixel_font
	if font == null:
		font = ThemeDB.fallback_font
		fs = maxi(fs, 12)
	var sz: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	host.draw_string(font, pos - sz * 0.5 + Vector2(0, sz.y * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _make_effect_slot(id: String, is_buff: bool, texture: Texture2D, display_name: String) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.name = "Effect_%s" % id
	slot.custom_minimum_size = Vector2(EFFECT_SLOT_PX, EFFECT_SLOT_PX)
	slot.tooltip_text = display_name
	var style := StyleBoxFlat.new()
	style.bg_color = EFFECT_SLOT_BG
	style.border_color = BUFF_BORDER if is_buff else DEBUFF_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(2)
	slot.add_theme_stylebox_override("panel", style)
	if texture != null:
		var icon := TextureRect.new()
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(EFFECT_SLOT_PX - 8, EFFECT_SLOT_PX - 8)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
	else:
		var fb := Label.new()
		fb.text = display_name.left(2).to_upper()
		_style_label(fb, 8, HUD_TEXT)
		fb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(fb)
	return slot


func _clear_status_rows() -> void:
	_perm_slots.clear()
	for row in [_buffs_row, _debuffs_row]:
		if row == null:
			continue
		for c in row.get_children():
			if c != _buffs_empty and c != _debuffs_empty:
				c.queue_free()
	if _buffs_empty:
		_buffs_empty.visible = true
	if _debuffs_empty:
		_debuffs_empty.visible = true


## effects: Array of {id, kind, texture, label}
func _populate_pending_icons(effects: Array) -> void:
	_clear_status_rows()
	var has_buff := false
	var has_debuff := false
	for e in effects:
		var id: String = String(e.get("id", ""))
		var kind: String = String(e.get("kind", "buff"))
		var tex: Texture2D = e.get("texture") as Texture2D
		var lab: String = String(e.get("label", id))
		var is_buff := kind.to_lower() != "debuff"
		var slot := _make_effect_slot(id, is_buff, tex, lab)
		# Start visible in the panel so player sees what will apply; hide during float.
		if is_buff:
			_buffs_row.add_child(slot)
			has_buff = true
		else:
			_debuffs_row.add_child(slot)
			has_debuff = true
		_perm_slots[id] = slot
	if _buffs_empty:
		_buffs_empty.visible = not has_buff
	if _debuffs_empty:
		_debuffs_empty.visible = not has_debuff


func _wheel_center_global() -> Vector2:
	if _stage == null:
		return get_viewport().get_visible_rect().size * 0.5
	return _stage.get_global_rect().get_center()


## Float icon from left panel slot → wheel, pop vanish, then restore permanent slot.
func _animate_apply_icon(id: String, texture: Texture2D) -> void:
	var slot: Control = _perm_slots.get(id) as Control
	var start: Vector2
	if slot and is_instance_valid(slot):
		start = slot.get_global_rect().get_center()
		slot.visible = false
	else:
		start = _buffs_row.get_global_rect().get_center() if _buffs_row else Vector2.ZERO

	var floater := TextureRect.new()
	floater.texture = texture
	floater.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	floater.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	floater.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	floater.custom_minimum_size = Vector2(40, 40)
	floater.size = Vector2(40, 40)
	floater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_float_layer.add_child(floater)
	floater.global_position = start - floater.size * 0.5

	var target: Vector2 = _wheel_center_global() - floater.size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(floater, "global_position", target, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(floater, "scale", Vector2(1.35, 1.35), 0.55)
	await tw.finished

	# Pop
	var tw2 := create_tween()
	tw2.tween_property(floater, "scale", Vector2(1.9, 1.9), 0.12)
	tw2.tween_property(floater, "modulate:a", 0.0, 0.12)
	await tw2.finished
	if is_instance_valid(floater):
		floater.queue_free()

	# Permanent condition reappears in the menu.
	if slot and is_instance_valid(slot):
		slot.visible = true
		slot.modulate = Color(1, 1, 1, 0)
		var tw3 := create_tween()
		tw3.tween_property(slot, "modulate:a", 1.0, 0.2)
		await tw3.finished


func _split_effects(effects: Array) -> Dictionary:
	var buffs: Array = []
	var debuffs: Array = []
	var demon: Dictionary = {}
	for e in effects:
		var id: String = String(e.get("id", ""))
		var kind: String = String(e.get("kind", "")).to_lower()
		if id == EFF_VISHNU or id == "vishnu" or id == "vishnu_demon":
			demon = e
			continue
		if kind == "debuff":
			debuffs.append(e)
		else:
			buffs.append(e)
	return {"buffs": buffs, "debuffs": debuffs, "demon": demon}


func _apply_effect_math(id: String) -> String:
	match id:
		EFF_ADHD, "adhd", "pill":
			_apply_attack_boost_50()
			return "ADHD meds kick in! Attack Fireman chance increases by 50%%, taken from the other options.\n\n%s" % _weights_summary()
		EFF_DROWSY, "drowsy", "fent":
			_apply_schmooze_cut_50()
			return "You're drowsy from the bad pills... Smooze Fireman chance drops by 50%%, and that weight goes to the other options.\n\n%s" % _weights_summary()
		EFF_VISHNU, "vishnu", "vishnu_demon":
			_apply_possess_25()
			return "The 4D demon surges into the wheel! Possess Fireman is locked in at 25%%. The other chances keep their ratios inside the remaining 75%%.\n\n%s" % _weights_summary()
		_:
			return "A status condition is applied to the wheel...\n\n%s" % _weights_summary()


## effects: [{id, kind, texture, label}, ...] from turn manager.
## Returns {index, id, label, weights}
func show_and_spin(title: String = "FATE WHEEL", effects: Array = []) -> Dictionary:
	if not _built:
		if _pixel_font == null and ResourceLoader.exists("res://PressStart2P-Regular.ttf"):
			_pixel_font = load("res://PressStart2P-Regular.ttf")
		_build_ui()

	_segs = _stock_segments()
	_wheel_rot_deg = 0.0
	if _title_label:
		_title_label.text = title
	if _result_label:
		_result_label.text = "Read the panel, then press START."
	_set_dialog(
		"Stock fate wheel loaded: equal chance for Attack, Smooze, and Seduce.\n\n"
		+ "Buffs apply next, then debuffs, then the wheel spins.\n\n"
		+ "Read this, then press START when you're ready."
	)
	_populate_pending_icons(effects)
	_refresh_legend()

	visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	_refresh_legend()

	# Player gates the sequence so they can read first.
	await _wait_for_start("Press START when ready.")

	var split: Dictionary = _split_effects(effects)
	var buffs: Array = split["buffs"]
	var debuffs: Array = split["debuffs"]
	var demon: Dictionary = split["demon"]

	# --- Buffs first ---
	for e in buffs:
		var id: String = String(e.get("id", ""))
		var tex: Texture2D = e.get("texture") as Texture2D
		var lab: String = String(e.get("label", id))
		_set_dialog("Applying buff: %s..." % lab)
		if _result_label:
			_result_label.text = "Applying buffs..."
		await _animate_apply_icon(id, tex)
		var msg: String = _apply_effect_math(id)
		_set_dialog(msg)
		_refresh_legend()
		await get_tree().create_timer(1.35).timeout

	# --- Debuffs next (non-demon) ---
	for e in debuffs:
		var id: String = String(e.get("id", ""))
		var tex: Texture2D = e.get("texture") as Texture2D
		var lab: String = String(e.get("label", id))
		_set_dialog("Applying debuff: %s..." % lab)
		if _result_label:
			_result_label.text = "Applying debuffs..."
		await _animate_apply_icon(id, tex)
		var msg: String = _apply_effect_math(id)
		_set_dialog(msg)
		_refresh_legend()
		await get_tree().create_timer(1.35).timeout

	# --- Demon last (adds 4th slice) ---
	if not demon.is_empty():
		var id: String = String(demon.get("id", EFF_VISHNU))
		var tex: Texture2D = demon.get("texture") as Texture2D
		var lab: String = String(demon.get("label", "Vishnu"))
		_set_dialog("Applying debuff: %s..." % lab)
		if _result_label:
			_result_label.text = "The demon stirs..."
		await _animate_apply_icon(id, tex)
		var msg: String = _apply_effect_math(id)
		_set_dialog(msg)
		_refresh_legend()
		await get_tree().create_timer(1.5).timeout

	_set_dialog("All conditions applied.\n\n%s\n\nPress START to spin." % _weights_summary())
	await _wait_for_start("Press START to spin.")

	_set_dialog("Spinning the fate wheel...\n\n%s" % _weights_summary())
	if _result_label:
		_result_label.text = "Spinning..."

	_spinning = true
	var landed: int = await _run_spin()
	_spinning = false

	var landed_id := ""
	var landed_label := ""
	if landed >= 0 and landed < _segs.size():
		landed_id = String(_segs[landed]["id"])
		landed_label = String(_segs[landed]["label"])
	if _result_label:
		_result_label.text = "Landed: %s" % landed_label
	_set_dialog("The wheel stops on:\n\n%s\n\n(Outcome wiring comes next.)" % landed_label)

	await get_tree().create_timer(1.4).timeout
	visible = false

	var result := {
		"index": landed,
		"id": landed_id,
		"label": landed_label,
		"weights": _weights_snapshot(),
	}
	spin_finished.emit(result)
	return result


func _weights_snapshot() -> Dictionary:
	var d := {}
	for s in _segs:
		d[String(s["id"])] = float(s["weight"])
	return d


func hide_popup() -> void:
	visible = false
	_spinning = false


func _run_spin() -> int:
	var vel: float = randf_range(SPIN_VEL_MIN, SPIN_VEL_MAX)
	if randf() < 0.15:
		vel = -vel
	var elapsed: float = 0.0
	while true:
		await get_tree().process_frame
		var dt: float = get_process_delta_time()
		if dt <= 0.0:
			dt = 1.0 / 60.0
		elapsed += dt
		var speed_ratio: float = clampf(absf(vel) / SPIN_VEL_MAX, 0.0, 1.0)
		var friction: float = lerpf(FRICTION_END, FRICTION_START, speed_ratio)
		if elapsed > MIN_SPIN_SEC:
			friction *= 1.0 + (elapsed - MIN_SPIN_SEC) * 0.35
		var sign_v: float = signf(vel)
		var mag: float = maxf(absf(vel) - friction * dt, 0.0)
		vel = mag * sign_v
		_wheel_rot_deg = fposmod(_wheel_rot_deg + vel * dt, 360.0)
		if _wheel_host:
			_wheel_host.queue_redraw()
		if mag <= STOP_VEL and elapsed >= MIN_SPIN_SEC:
			break
		if elapsed >= MAX_SPIN_SEC:
			break
	for _i in 8:
		await get_tree().process_frame
		_wheel_rot_deg = fposmod(_wheel_rot_deg + vel * get_process_delta_time() * 0.4, 360.0)
		vel *= 0.55
		if _wheel_host:
			_wheel_host.queue_redraw()
	return _segment_under_needle()


func _segment_under_needle() -> int:
	# Local angle at top (0 = top of wheel when rot=0).
	var local_top: float = fposmod(-_wheel_rot_deg, 360.0)
	var acc := 0.0
	for i in _segs.size():
		var span: float = float(_segs[i]["weight"]) * 360.0
		if local_top < acc + span or i == _segs.size() - 1:
			return i
		acc += span
	return 0
