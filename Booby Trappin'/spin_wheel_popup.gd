extends Control
## The end-of-round encounter UI.
##
## The old behaviour — a wheel that spun and TOLD you what you were about to do
## — is gone. You now choose: Attack, Seduce or Schmooze, each showing the
## success odds that your anxiety has earned you.
##
## The wheel still exists, but only the demon gets to use it. If you are
## possessed, picking an option halts everything: the possession icon floats in,
## a purple wheel appears, and the demon decides. Anxiety has no influence
## there on purpose — once it takes over, you are a passenger.
##
##   show_action_choice(title, anxiety, options) -> {id, label, odds}
##   show_possession_wheel(segments, demon_tex)  -> {id, label, weights}

signal spin_finished(result: Dictionary)
signal action_chosen(result: Dictionary)

const WHEEL_R := 112.0
const HUB_R := 16.0
const RIM := 6.0
const PANEL_H := 360.0
const SIDE_W := 190.0
const DIALOG_W := 210.0

## Spin tuning (unchanged feel from the original fate wheel).
const SPIN_VEL_MIN := 980.0
const SPIN_VEL_MAX := 1380.0
const FRICTION_START := 60.0
const FRICTION_END := 210.0
const STOP_VEL := 12.0
const MIN_SPIN_SEC := 5.6
const MAX_SPIN_SEC := 13.0

const INV_PURPLE := Color(0.48, 0.30, 0.62, 0.98)
const HUD_BORDER := Color(0.95, 0.78, 0.28, 0.95)
const HUD_TEXT := Color(1.0, 0.92, 0.55, 1.0)
const DEMON_PURPLE := Color(0.62, 0.24, 0.82, 1.0)
## Matches dev_panel.gd so both dev surfaces read as one thing.
const DEV_ACCENT := Color(0.42, 0.82, 0.95, 1.0)

## Anxiety readout colours (mirrors anxiety_bar.gd).
const ANX_TRACK := Color(0.16, 0.07, 0.08, 0.98)
const ANX_LOW := Color(0.66, 0.13, 0.14, 1.0)
const ANX_HIGH := Color(1.0, 0.24, 0.15, 1.0)

## Purple wheel palette, by outcome id.
const SEG_COLORS := {
	"murder": Color(0.58, 0.06, 0.14, 1.0),
	"possess_person": Color(0.60, 0.22, 0.80, 1.0),
	"possess_lizard": Color(0.34, 0.62, 0.36, 1.0),
	"lizard_murder": Color(0.44, 0.62, 0.20, 1.0),
	"bravado": Color(0.22, 0.55, 0.40, 1.0),
	"nothing": Color(0.32, 0.26, 0.42, 1.0),
}

var _pixel_font: Font
var _wheel_rot_deg: float = 0.0
var _built: bool = false

## Ordered segment data for the purple wheel: {id, label, short, color, weight}
var _segs: Array = []

# --- action choice page ---
var _choice_root: Control
var _choice_title: Label
var _choice_anx_value: Label
var _choice_anx_bar: Control
var _choice_anx: int = 25
var _choice_desc: Label
var _choice_rows: VBoxContainer
var _choice_waiting: bool = false
var _choice_result: Dictionary = {}

# --- wheel page ---
var _wheel_root: Control
var _title_label: Label
var _result_label: Label
var _dialog_label: Label
var _start_btn: Button
var _wheel_host: Control
var _needle: Control
var _stage: Control
var _float_layer: Control
var _odds_legend: Label

# --- dev strip (Ctrl+P) ---
## The F3 dev panel sits under this popup's full-screen dim, so it cannot be
## clicked while an encounter is up. This strip lives INSIDE the popup instead:
## Ctrl+P reveals a column on the right of whichever page is showing, and every
## button on it resolves that step instantly — actions succeed outright, wheel
## slices are taken without spinning.
var _dev_mode: bool = false
var _dev_choice_strip: PanelContainer
var _dev_choice_rows: VBoxContainer
var _dev_wheel_strip: PanelContainer
var _dev_wheel_rows: VBoxContainer
## Set by a dev button to short-circuit the spin.
var _forced_pick: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists("res://PressStart2P-Regular.ttf"):
		_pixel_font = load("res://PressStart2P-Regular.ttf")
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_P and event.ctrl_pressed:
		_dev_mode = not _dev_mode
		_apply_dev_visibility()
		print("[DEV] instant-resolve strip %s" % ("ON" if _dev_mode else "OFF"))
		get_viewport().set_input_as_handled()


func _apply_dev_visibility() -> void:
	if _dev_choice_strip:
		_dev_choice_strip.visible = _dev_mode
	if _dev_wheel_strip:
		_dev_wheel_strip.visible = _dev_mode


## Column of "just do it" buttons pinned to the right edge of a page.
func _make_dev_strip(hint: String) -> Array:
	var p := PanelContainer.new()
	p.name = "DevStrip"
	p.visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.07, 0.10, 0.96)
	st.border_color = DEV_ACCENT.darkened(0.2)
	st.set_border_width_all(2)
	st.set_corner_radius_all(6)
	st.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", st)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.custom_minimum_size = Vector2(150, 0)
	p.add_child(col)

	var t := Label.new()
	t.text = "DEV  (Ctrl+P)"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(t, 8, DEV_ACCENT)
	col.add_child(t)

	var h := Label.new()
	h.text = hint
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.custom_minimum_size = Vector2(140, 0)
	_style_label(h, 7, Color(0.72, 0.80, 0.88, 1.0))
	col.add_child(h)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	col.add_child(rows)
	return [p, rows]


func _dev_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(140, 22)
	if _pixel_font:
		b.add_theme_font_override("font", _pixel_font)
	b.add_theme_font_size_override("font_size", 7)
	b.add_theme_color_override("font_color", Color(0.06, 0.09, 0.12, 1.0))
	b.add_theme_color_override("font_hover_color", Color(0, 0, 0, 1))
	var n := StyleBoxFlat.new()
	n.bg_color = DEV_ACCENT
	n.border_color = DEV_ACCENT.darkened(0.35)
	n.set_border_width_all(1)
	n.set_corner_radius_all(3)
	n.set_content_margin_all(4)
	var hv := n.duplicate() as StyleBoxFlat
	hv.bg_color = Color(0.66, 0.93, 1.0, 1.0)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	return b


func _build_ui() -> void:
	if _built:
		return
	_built = true

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.68)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_build_choice_page()
	_build_wheel_page()

	# Floating icons draw above both pages.
	_float_layer = Control.new()
	_float_layer.name = "FloatLayer"
	_float_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_float_layer)


## ============================================================================
## Page 1 — choose an action
## ============================================================================

func _build_choice_page() -> void:
	_choice_root = Control.new()
	_choice_root.name = "ChoicePage"
	_choice_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_choice_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_root.visible = false
	add_child(_choice_root)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_root.add_child(center)

	var outer := _frame()
	center.add_child(outer)
	var body := _body_panel()
	outer.add_child(body)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	body.add_child(col)

	_choice_title = Label.new()
	_choice_title.text = "FIREMAN"
	_choice_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(_choice_title, 13, HUD_TEXT)
	col.add_child(_choice_title)

	# --- anxiety readout: the odds below come straight off this number ---
	var anx_panel := _side_panel("AnxietyReadout")
	col.add_child(anx_panel)
	var anx_col := VBoxContainer.new()
	anx_col.add_theme_constant_override("separation", 4)
	anx_panel.add_child(anx_col)

	var anx_head := HBoxContainer.new()
	anx_head.add_theme_constant_override("separation", 6)
	anx_col.add_child(anx_head)
	var anx_label := Label.new()
	anx_label.text = "ANXIETY"
	anx_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_label(anx_label, 9, HUD_TEXT)
	anx_head.add_child(anx_label)
	_choice_anx_value = Label.new()
	_choice_anx_value.text = "25"
	_choice_anx_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style_label(_choice_anx_value, 9, HUD_TEXT)
	anx_head.add_child(_choice_anx_value)

	_choice_anx_bar = Control.new()
	_choice_anx_bar.custom_minimum_size = Vector2(SIDE_W + DIALOG_W, 14)
	_choice_anx_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choice_anx_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_anx_bar.draw.connect(_draw_choice_anx_bar)
	anx_col.add_child(_choice_anx_bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)

	# --- left: the three options ---
	var left := _side_panel("OptionsPanel")
	left.custom_minimum_size = Vector2(SIDE_W + 60.0, 0)
	row.add_child(left)
	_choice_rows = VBoxContainer.new()
	_choice_rows.add_theme_constant_override("separation", 8)
	left.add_child(_choice_rows)

	# --- right: flavour for whatever is hovered ---
	var right := _side_panel("ChoiceDialogPanel")
	right.custom_minimum_size = Vector2(DIALOG_W, 0)
	row.add_child(right)
	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 8)
	right.add_child(right_col)

	var rt := Label.new()
	rt.text = "What is happening"
	rt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(rt, 9, HUD_TEXT)
	right_col.add_child(rt)

	_choice_desc = Label.new()
	_choice_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_choice_desc.custom_minimum_size = Vector2(DIALOG_W - 36, 190)
	_choice_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_style_label(_choice_desc, 9, Color(1, 1, 1, 1))
	right_col.add_child(_choice_desc)

	var strip := _make_dev_strip("Pick one — it succeeds outright, no roll.")
	_dev_choice_strip = strip[0]
	_dev_choice_rows = strip[1]
	row.add_child(_dev_choice_strip)


func _draw_choice_anx_bar() -> void:
	if _choice_anx_bar == null:
		return
	var w: float = _choice_anx_bar.size.x
	var h: float = _choice_anx_bar.size.y
	_choice_anx_bar.draw_rect(Rect2(0, 0, w, h), Color(0.42, 0.12, 0.12, 1.0), true)
	var inner := Rect2(1, 1, w - 2, h - 2)
	_choice_anx_bar.draw_rect(inner, ANX_TRACK, true)
	var pct: float = clampf(float(_choice_anx) / 100.0, 0.0, 1.0)
	if pct > 0.0:
		var col: Color = ANX_LOW.lerp(ANX_HIGH, pct)
		_choice_anx_bar.draw_rect(Rect2(inner.position, Vector2(inner.size.x * pct, inner.size.y)), col, true)
	for i in range(1, 10):
		var x: float = inner.position.x + inner.size.x * (float(i) / 10.0)
		_choice_anx_bar.draw_rect(Rect2(Vector2(x, inner.position.y), Vector2(1.0, inner.size.y)), Color(0.05, 0.02, 0.03, 0.5), true)


## options: [{id, label, odds, desc}]
func show_action_choice(title: String, anxiety_value: int, options: Array) -> Dictionary:
	if not _built:
		_build_ui()
	_choice_anx = clampi(anxiety_value, 0, 100)
	if _choice_title:
		_choice_title.text = title
	if _choice_anx_value:
		_choice_anx_value.text = "%d / 100" % _choice_anx
	if _choice_anx_bar:
		_choice_anx_bar.queue_redraw()
	if _choice_desc:
		_choice_desc.text = "He is standing in your apartment.\n\nPick your play. The odds under each option are what your anxiety has left you."

	for c in _choice_rows.get_children():
		c.queue_free()

	var first_btn: Button = null
	for o in options:
		var entry := _make_option_row(o)
		_choice_rows.add_child(entry["row"])
		if first_btn == null:
			first_btn = entry["button"]

	for c in _dev_choice_rows.get_children():
		c.queue_free()
	for o in options:
		var oid: String = String(o.get("id", ""))
		var olabel: String = String(o.get("label", oid.to_upper()))
		var b := _dev_button("%s — WIN" % olabel)
		b.pressed.connect(_on_dev_action.bind(oid, olabel))
		_dev_choice_rows.add_child(b)
	_apply_dev_visibility()

	_choice_result = {}
	_choice_waiting = true
	_wheel_root.visible = false
	_choice_root.visible = true
	visible = true
	await get_tree().process_frame
	if first_btn:
		first_btn.grab_focus()

	while _choice_waiting and is_instance_valid(self):
		await get_tree().process_frame

	_choice_root.visible = false
	# The dim ColorRect belongs to the ROOT, not the page — leaving the root up
	# left a permanent dark sheet over the game on any non-possessed round.
	visible = false
	action_chosen.emit(_choice_result)
	return _choice_result


func _make_option_row(o: Dictionary) -> Dictionary:
	var id: String = String(o.get("id", ""))
	var label: String = String(o.get("label", id.to_upper()))
	var odds: int = int(o.get("odds", 50))
	var desc: String = String(o.get("desc", ""))

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var btn := Button.new()
	btn.name = "Option_%s" % id
	btn.text = "%s   %d%%" % [label, odds]
	btn.custom_minimum_size = Vector2(SIDE_W + 36.0, 34)
	btn.focus_mode = Control.FOCUS_ALL
	_style_option_button(btn, odds)
	btn.pressed.connect(_on_option_pressed.bind(id, label, odds))
	# Hovering (or tabbing to) an option explains it on the right.
	btn.mouse_entered.connect(func(): _set_choice_desc(desc))
	btn.focus_entered.connect(func(): _set_choice_desc(desc))
	row.add_child(btn)

	# A small odds meter so the numbers read at a glance.
	var meter := Control.new()
	meter.custom_minimum_size = Vector2(SIDE_W + 36.0, 6)
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.draw.connect(_draw_odds_meter.bind(meter, odds))
	row.add_child(meter)

	return {"row": row, "button": btn}


func _draw_odds_meter(host: Control, odds: int) -> void:
	var w: float = host.size.x
	var h: float = host.size.y
	host.draw_rect(Rect2(0, 0, w, h), Color(0.12, 0.10, 0.12, 1.0), true)
	var pct: float = clampf(float(odds) / 100.0, 0.0, 1.0)
	# Green when the odds are good, amber-to-red as they rot.
	var col: Color = Color(0.85, 0.25, 0.25, 1.0).lerp(Color(0.40, 0.80, 0.42, 1.0), pct)
	host.draw_rect(Rect2(Vector2(1, 1), Vector2((w - 2.0) * pct, h - 2.0)), col, true)


func _set_choice_desc(text: String) -> void:
	if _choice_desc:
		_choice_desc.text = text


func _on_option_pressed(id: String, label: String, odds: int) -> void:
	if not _choice_waiting:
		return
	_choice_result = {"id": id, "label": label, "odds": odds, "force_win": false}
	_choice_waiting = false


## Dev: take this action and succeed, whatever the odds said.
func _on_dev_action(id: String, label: String) -> void:
	if not _choice_waiting:
		return
	print("[DEV] forcing %s to succeed" % id)
	_choice_result = {"id": id, "label": label, "odds": 100, "force_win": true}
	_choice_waiting = false


func _style_option_button(btn: Button, odds: int) -> void:
	if _pixel_font:
		btn.add_theme_font_override("font", _pixel_font)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", HUD_TEXT)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.78, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.72, 0.35, 1.0))
	var accent: Color = Color(0.85, 0.30, 0.28, 1.0).lerp(Color(0.42, 0.78, 0.44, 1.0), clampf(float(odds) / 100.0, 0.0, 1.0))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.08, 0.12, 0.96)
	normal.border_color = accent.darkened(0.25)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(4)
	normal.set_content_margin_all(6)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.20, 0.14, 0.18, 0.98)
	hover.border_color = accent
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.24, 0.16, 0.10, 0.98)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)


## ============================================================================
## Page 2 — the purple possession wheel
## ============================================================================

func _build_wheel_page() -> void:
	_wheel_root = Control.new()
	_wheel_root.name = "WheelPage"
	_wheel_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wheel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel_root.visible = false
	add_child(_wheel_root)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wheel_root.add_child(center)

	var outer := _frame(DEMON_PURPLE)
	center.add_child(outer)
	var body := _body_panel(Color(0.11, 0.06, 0.14, 0.97), DEMON_PURPLE)
	outer.add_child(body)

	var root_col := VBoxContainer.new()
	root_col.add_theme_constant_override("separation", 10)
	body.add_child(root_col)

	_title_label = Label.new()
	_title_label.text = "THE DEMON TAKES THE WHEEL"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(_title_label, 13, Color(0.92, 0.72, 1.0, 1.0))
	root_col.add_child(_title_label)

	var center_row := HBoxContainer.new()
	center_row.name = "WheelRow"
	center_row.add_theme_constant_override("separation", 10)
	center_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root_col.add_child(center_row)

	# --- left: odds legend ---
	var left := _side_panel("OddsPanel", DEMON_PURPLE)
	left.custom_minimum_size = Vector2(SIDE_W, PANEL_H)
	center_row.add_child(left)
	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 8)
	left.add_child(left_col)

	var lt := Label.new()
	lt.text = "The Odds"
	lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(lt, 9, Color(0.92, 0.72, 1.0, 1.0))
	left_col.add_child(lt)

	_odds_legend = Label.new()
	_odds_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_odds_legend.custom_minimum_size = Vector2(SIDE_W - 28, 0)
	_style_label(_odds_legend, 8, Color(0.95, 0.92, 1.0, 0.98))
	left_col.add_child(_odds_legend)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(spacer)

	var note := Label.new()
	note.text = "Your anxiety does not matter here. It is not your hand on the wheel."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(SIDE_W - 28, 0)
	_style_label(note, 7, Color(0.78, 0.62, 0.90, 0.95))
	left_col.add_child(note)

	# --- center: wheel ---
	var mid := _side_panel("WheelPanel", DEMON_PURPLE)
	mid.custom_minimum_size = Vector2(PANEL_H - 40.0, PANEL_H)
	center_row.add_child(mid)
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
	_start_btn.text = "SPIN"
	_start_btn.custom_minimum_size = Vector2(140, 32)
	_start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_start_button(_start_btn)
	_start_btn.visible = false
	_start_btn.disabled = true
	mid_col.add_child(_start_btn)

	# --- right: dialog ---
	var right := _side_panel("DemonDialogPanel", DEMON_PURPLE)
	right.custom_minimum_size = Vector2(DIALOG_W, PANEL_H)
	center_row.add_child(right)
	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 8)
	right.add_child(right_col)

	var rt := Label.new()
	rt.text = "What is happening"
	rt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(rt, 9, Color(0.92, 0.72, 1.0, 1.0))
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

	var wstrip := _make_dev_strip("Take a slice directly — skips the spin.")
	_dev_wheel_strip = wstrip[0]
	_dev_wheel_rows = wstrip[1]
	center_row.add_child(_dev_wheel_strip)


func _seg_index(id: String) -> int:
	for i in _segs.size():
		if String(_segs[i]["id"]) == id:
			return i
	return -1


## Rotate so the needle sits in the middle of segment i. Used by the dev panel
## to pin an outcome — the wheel still spins for real, it just lands where told.
func _snap_to_segment(i: int) -> void:
	if i < 0 or i >= _segs.size():
		return
	var acc := 0.0
	for k in i:
		acc += float(_segs[k]["weight"]) * 360.0
	var span: float = float(_segs[i]["weight"]) * 360.0
	_wheel_rot_deg = fposmod(-(acc + span * 0.5), 360.0)
	if _wheel_host:
		_wheel_host.queue_redraw()


## segments: [{id, label, weight}] — raw weights, normalised here.
## force_id pins the result (dev panel); empty means a real spin decides.
## `title` retitles the page — the same wheel is used for the demon and for
## waving a gun around, and those are not the same event.
func show_possession_wheel(segments: Array, demon_tex: Texture2D = null, force_id: String = "", title: String = "THE DEMON TAKES THE WHEEL") -> Dictionary:
	if not _built:
		_build_ui()

	_segs.clear()
	for s in segments:
		var id: String = String(s.get("id", ""))
		var lab: String = String(s.get("label", id.to_upper()))
		_segs.append({
			"id": id,
			"label": lab,
			"short": String(s.get("short", lab.split(" ")[0])),
			"color": SEG_COLORS.get(id, Color(0.45, 0.30, 0.60, 1.0)),
			"weight": maxf(float(s.get("weight", 1.0)), 0.0),
		})
	_normalize_weights()
	_wheel_rot_deg = 0.0

	_forced_pick = ""
	for c in _dev_wheel_rows.get_children():
		c.queue_free()
	for seg in _segs:
		var sid: String = String(seg["id"])
		var b := _dev_button(String(seg["label"]))
		b.pressed.connect(_on_dev_slice.bind(sid))
		_dev_wheel_rows.add_child(b)
	_apply_dev_visibility()

	if _title_label:
		_title_label.text = title
	_choice_root.visible = false
	_wheel_root.visible = true
	visible = true
	_set_dialog(
		"Something else moves first.\n\n"
		+ "The demon inside you does not care what you decided. It has its own list.\n\n"
		+ "Press SPIN when you can face it."
	)
	_refresh_legend()
	await get_tree().process_frame
	await get_tree().process_frame

	# The possession icon floats in over the wheel, exactly as it used to.
	if demon_tex != null and _forced_pick.is_empty():
		await _animate_demon_icon(demon_tex)

	_refresh_legend()
	await _wait_for_start("Press SPIN.")

	var landed: int = 0
	if not _forced_pick.is_empty():
		# Dev strip: take the slice outright, no spin.
		landed = maxi(_seg_index(_forced_pick), 0)
		_snap_to_segment(landed)
		await get_tree().process_frame
	else:
		_set_dialog("The wheel turns.\n\n%s" % _weights_summary())
		if _result_label:
			_result_label.text = "Spinning..."
		landed = await _run_spin()
		if not force_id.is_empty():
			var forced: int = _seg_index(force_id)
			if forced >= 0:
				landed = forced
				_snap_to_segment(forced)
				await get_tree().process_frame

	var landed_id := ""
	var landed_label := ""
	if landed >= 0 and landed < _segs.size():
		landed_id = String(_segs[landed]["id"])
		landed_label = String(_segs[landed]["label"])
	if _result_label:
		_result_label.text = "Landed: %s" % landed_label
	_set_dialog("The wheel stops on:\n\n%s" % landed_label)

	await get_tree().create_timer(1.4).timeout
	visible = false
	_wheel_root.visible = false

	var result := {
		"index": landed,
		"id": landed_id,
		"label": landed_label,
		"weights": _weights_snapshot(),
	}
	spin_finished.emit(result)
	return result


## Demon icon drifts in from the left, swells over the wheel, then pops.
func _animate_demon_icon(texture: Texture2D) -> void:
	if _float_layer == null:
		return
	var floater := TextureRect.new()
	floater.texture = texture
	floater.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	floater.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	floater.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	floater.custom_minimum_size = Vector2(56, 56)
	floater.size = Vector2(56, 56)
	floater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_float_layer.add_child(floater)

	var target: Vector2 = _wheel_center_global() - floater.size * 0.5
	var start: Vector2 = target + Vector2(-260.0, -40.0)
	floater.global_position = start
	floater.modulate = Color(1, 1, 1, 0)

	if _result_label:
		_result_label.text = "The demon stirs..."

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(floater, "global_position", target, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(floater, "scale", Vector2(1.5, 1.5), 0.85)
	tw.tween_property(floater, "modulate:a", 1.0, 0.35)
	await tw.finished

	var tw2 := create_tween()
	tw2.tween_property(floater, "scale", Vector2(2.1, 2.1), 0.14)
	tw2.tween_property(floater, "modulate:a", 0.0, 0.14)
	await tw2.finished
	if is_instance_valid(floater):
		floater.queue_free()


func _wheel_center_global() -> Vector2:
	if _stage == null:
		return get_viewport().get_visible_rect().size * 0.5
	return _stage.get_global_rect().get_center()


## Waits for SPIN, but a dev slice click also releases it.
func _wait_for_start(prompt: String = "Press SPIN.") -> void:
	if _start_btn == null:
		return
	if _result_label:
		_result_label.text = prompt
	_start_btn.visible = true
	_start_btn.disabled = false
	_start_btn.grab_focus()
	var pressed := [false]
	var cb := func(): pressed[0] = true
	_start_btn.pressed.connect(cb)
	while not pressed[0] and _forced_pick.is_empty() and is_instance_valid(self):
		await get_tree().process_frame
	if _start_btn.pressed.is_connected(cb):
		_start_btn.pressed.disconnect(cb)
	_start_btn.disabled = true
	_start_btn.visible = false


## Dev: resolve the wheel to this slice immediately.
func _on_dev_slice(id: String) -> void:
	print("[DEV] taking wheel slice %s" % id)
	_forced_pick = id


func _weights_summary() -> String:
	var lines: PackedStringArray = []
	for s in _segs:
		var pct: int = int(round(float(s["weight"]) * 100.0))
		lines.append("%s  %d%%" % [String(s["label"]), pct])
	return "\n".join(lines)


func _set_dialog(text: String) -> void:
	if _dialog_label:
		_dialog_label.text = text


func _refresh_legend() -> void:
	if _odds_legend:
		_odds_legend.text = _weights_summary()
	if _wheel_host:
		_wheel_host.queue_redraw()
	if _needle:
		_needle.queue_redraw()


func _normalize_weights() -> void:
	var total := 0.0
	for s in _segs:
		total += float(s["weight"])
	if total <= 0.0001:
		var eq := 1.0 / maxf(float(_segs.size()), 1.0)
		for s in _segs:
			s["weight"] = eq
		return
	for s in _segs:
		s["weight"] = float(s["weight"]) / total


func _weights_snapshot() -> Dictionary:
	var d := {}
	for s in _segs:
		d[String(s["id"])] = float(s["weight"])
	return d


func hide_popup() -> void:
	visible = false
	if _wheel_root:
		_wheel_root.visible = false
	if _choice_root:
		_choice_root.visible = false
	_choice_waiting = false


## ============================================================================
## Wheel drawing + spin
## ============================================================================

func _draw_wheel() -> void:
	if _wheel_host == null or _segs.is_empty():
		return
	var c: Vector2 = _wheel_host.size * 0.5
	var r: float = WHEEL_R
	_wheel_host.draw_circle(c, r + RIM, Color(0.10, 0.04, 0.14, 1.0))
	_wheel_host.draw_circle(c, r + RIM - 2.0, DEMON_PURPLE.darkened(0.2))

	var cursor: float = _wheel_rot_deg - 90.0
	for s in _segs:
		var span: float = float(s["weight"]) * 360.0
		var start_deg: float = cursor
		var end_deg: float = cursor + span
		_draw_slice(_wheel_host, c, r, start_deg, end_deg, s["color"])
		var mid: float = deg_to_rad((start_deg + end_deg) * 0.5)
		var lp: Vector2 = c + Vector2(cos(mid), sin(mid)) * (r * 0.55)
		_draw_centered_text(_wheel_host, lp, String(s["short"]), Color(1.0, 0.98, 0.95, 1.0), 8)
		cursor = end_deg

	_wheel_host.draw_circle(c, HUB_R + 3.0, Color(0.08, 0.04, 0.10, 1.0))
	_wheel_host.draw_circle(c, HUB_R, DEMON_PURPLE)
	_wheel_host.draw_circle(c, HUB_R - 5.0, Color(0.16, 0.08, 0.20, 1.0))


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
	_needle.draw_colored_polygon(pts, Color(0.06, 0.03, 0.08, 1.0))
	var inset := PackedVector2Array([
		Vector2(c.x, tip_y + 24.0),
		Vector2(c.x - 11.0, tip_y - 4.0),
		Vector2(c.x - 3.5, tip_y - 4.0),
		Vector2(c.x - 3.5, tip_y - 18.0),
		Vector2(c.x + 3.5, tip_y - 18.0),
		Vector2(c.x + 3.5, tip_y - 4.0),
		Vector2(c.x + 11.0, tip_y - 4.0),
	])
	_needle.draw_colored_polygon(inset, Color(0.86, 0.60, 1.0, 1.0))
	_needle.draw_circle(Vector2(c.x, tip_y - 14.0), 4.0, Color(0.14, 0.06, 0.18, 1.0))
	_needle.draw_circle(Vector2(c.x, tip_y - 14.0), 2.5, DEMON_PURPLE)


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
	host.draw_line(center, center + Vector2(cos(a0), sin(a0)) * radius, Color(0.06, 0.03, 0.08, 0.85), 2.5)


func _draw_centered_text(host: Control, pos: Vector2, text: String, color: Color, fs: int = 10) -> void:
	var font: Font = _pixel_font
	if font == null:
		font = ThemeDB.fallback_font
		fs = maxi(fs, 12)
	var sz: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	host.draw_string(font, pos - sz * 0.5 + Vector2(0, sz.y * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


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
		if not _forced_pick.is_empty():
			break
	if not _forced_pick.is_empty():
		return maxi(_seg_index(_forced_pick), 0)
	for _i in 8:
		await get_tree().process_frame
		_wheel_rot_deg = fposmod(_wheel_rot_deg + vel * get_process_delta_time() * 0.4, 360.0)
		vel *= 0.55
		if _wheel_host:
			_wheel_host.queue_redraw()
	return _segment_under_needle()


func _segment_under_needle() -> int:
	var local_top: float = fposmod(-_wheel_rot_deg, 360.0)
	var acc := 0.0
	for i in _segs.size():
		var span: float = float(_segs[i]["weight"]) * 360.0
		if local_top < acc + span or i == _segs.size() - 1:
			return i
		acc += span
	return 0


## ============================================================================
## Shared chrome
## ============================================================================

func _frame(border: Color = INV_PURPLE) -> PanelContainer:
	var outer := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = border
	st.border_color = border.lightened(0.15)
	st.set_border_width_all(3)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(6)
	outer.add_theme_stylebox_override("panel", st)
	return outer


func _body_panel(bg: Color = Color(0.12, 0.08, 0.10, 0.96), border: Color = HUD_BORDER) -> PanelContainer:
	var body := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(2)
	st.set_corner_radius_all(6)
	st.set_content_margin_all(12)
	body.add_theme_stylebox_override("panel", st)
	return body


func _side_panel(panel_name: String, border: Color = HUD_BORDER) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = panel_name
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.06, 0.08, 0.94)
	st.border_color = border.darkened(0.1)
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
	btn.add_theme_color_override("font_color", Color(0.10, 0.04, 0.12, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(0.06, 0.02, 0.08, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.35, 0.30, 0.38, 0.7))
	var normal := StyleBoxFlat.new()
	normal.bg_color = DEMON_PURPLE
	normal.border_color = DEMON_PURPLE.darkened(0.35)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(4)
	normal.set_content_margin_all(8)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.78, 0.42, 0.96, 1.0)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.44, 0.16, 0.60, 1.0)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.32, 0.24, 0.36, 0.75)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus", hover)
