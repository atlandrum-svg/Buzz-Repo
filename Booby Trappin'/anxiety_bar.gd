extends PanelContainer
## The anxiety bar — the single HUD readout that replaced Agility / Charisma /
## Intelligence. Everything is drawn by hand in _draw_bar() so the fill, the
## permanent murder segment and the tick marks stay pixel-crisp at any value.
##
## Behaviour that makes it feel alive:
##   * the fill eases toward the target instead of snapping
##   * the red gets hotter as the value climbs
##   * it breathes above CALM_MAX and jitters above PANIC_MIN
##   * a modifier landing flashes the whole bar white for a beat
##
## The buff/debuff sidebar is gone. Its icons live here now and only appear
## while the mouse is over the bar.
##
## Usage: add under the HUD sidebar, then bind(anxiety_system, pixel_font).

const HUD_BG := Color(0.08, 0.08, 0.12, 0.82)
const HUD_BORDER := Color(0.95, 0.78, 0.28, 0.95)
const HUD_TEXT := Color(1.0, 0.92, 0.55, 1.0)

const BAR_W := 148.0
const BAR_H := 18.0
## Bar geometry
const TRACK_BG := Color(0.16, 0.07, 0.08, 0.98)
const TRACK_EDGE := Color(0.42, 0.12, 0.12, 1.0)
## Fill ramps from smouldering to hot as anxiety climbs.
const FILL_LOW := Color(0.66, 0.13, 0.14, 1.0)
const FILL_HIGH := Color(1.0, 0.24, 0.15, 1.0)
const FILL_SHINE := Color(1.0, 0.62, 0.48, 0.55)
## Permanent murder anxiety — darker, drawn over the fill at the left end.
const LOCKED_FILL := Color(0.36, 0.03, 0.05, 1.0)
const LOCKED_EDGE := Color(0.62, 0.10, 0.10, 1.0)
const TICK := Color(0.05, 0.02, 0.03, 0.55)

## Above this the bar breathes; above PANIC_MIN it also shakes.
const CALM_MAX := 60
const PANIC_MIN := 85
const EASE_SPEED := 6.0
const FLASH_SEC := 0.35

const ROW_ICON_PX := 26

var _sys: Node = null
var _font: Font = null

var _bar: Control
var _title: Label
var _value_label: Label
var _hover_panel: PanelContainer
var _hover_rows: VBoxContainer

## Eased display value (0..100) chasing the real one.
var _shown: float = 25.0
var _target: float = 25.0
var _pulse_t: float = 0.0
var _flash_t: float = 0.0
var _hovering: bool = false
## Panic jitter, applied to the fill only. Never move the panel itself — it
## lives in a VBoxContainer, and writing `position` snaps it to (0,0) on top
## of the trap counter above it.
var _shake: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


## Wire to the AnxietySystem node. Safe to call once, after the HUD exists.
func bind(system: Node, pixel_font: Font) -> void:
	_sys = system
	_font = pixel_font
	_build()
	if _sys:
		if not _sys.anxiety_changed.is_connected(_on_anxiety_changed):
			_sys.anxiety_changed.connect(_on_anxiety_changed)
		if not _sys.modifier_applied.is_connected(_on_modifier_applied):
			_sys.modifier_applied.connect(_on_modifier_applied)
		_shown = float(_sys.value())
		_target = _shown
	refresh()


func _build() -> void:
	add_theme_stylebox_override("panel", _panel_style(8))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(col)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(header)

	_title = Label.new()
	_title.text = "ANXIETY"
	_style(_title, 10, HUD_TEXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_title)

	_value_label = Label.new()
	_value_label.text = "25"
	_style(_value_label, 10, HUD_TEXT)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_value_label)

	_bar = Control.new()
	_bar.name = "AnxietyTrack"
	_bar.custom_minimum_size = Vector2(BAR_W, BAR_H)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# STOP so the icon list can hang off hover.
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.mouse_default_cursor_shape = Control.CURSOR_HELP
	_bar.draw.connect(_draw_bar)
	_bar.mouse_entered.connect(_on_bar_hover_start)
	_bar.mouse_exited.connect(_on_bar_hover_end)
	col.add_child(_bar)

	_build_hover_panel()


func _build_hover_panel() -> void:
	var p := PanelContainer.new()
	p.name = "AnxietyHoverPanel"
	p.top_level = true # position freely, ignore the sidebar layout
	p.visible = false
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.z_index = 50
	var st := _panel_style(8)
	st.bg_color = Color(0.10, 0.05, 0.06, 0.97)
	st.border_color = Color(0.85, 0.28, 0.26, 0.95)
	p.add_theme_stylebox_override("panel", st)
	add_child(p)
	_hover_panel = p

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(col)
	_hover_rows = col


func _on_bar_hover_start() -> void:
	_hovering = true
	_rebuild_hover_rows()
	if _hover_panel:
		_hover_panel.visible = true
		_position_hover_panel()


func _on_bar_hover_end() -> void:
	_hovering = false
	if _hover_panel:
		_hover_panel.visible = false


func _position_hover_panel() -> void:
	if _hover_panel == null or _bar == null:
		return
	# Sit just right of the bar, top-aligned with it. Nudge back on-screen if
	# the list would run off the right edge.
	var bar_rect: Rect2 = _bar.get_global_rect()
	var vp: Vector2 = get_viewport_rect().size
	var want: Vector2 = Vector2(bar_rect.end.x + 10.0, bar_rect.position.y - 4.0)
	var w: float = maxf(_hover_panel.size.x, 190.0)
	if want.x + w > vp.x - 8.0:
		want.x = maxf(8.0, bar_rect.position.x - w - 10.0)
	_hover_panel.global_position = want


func _rebuild_hover_rows() -> void:
	if _hover_rows == null:
		return
	for c in _hover_rows.get_children():
		c.queue_free()

	var head := Label.new()
	head.text = "TRAITS"
	_style(head, 8, Color(1.0, 0.72, 0.58, 1.0))
	_hover_rows.add_child(head)

	var listing: Array = []
	if _sys and _sys.has_method("listing"):
		listing = _sys.listing()

	if listing.is_empty():
		var none := Label.new()
		none.text = "No traits yet. Baseline dread only."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size = Vector2(180, 0)
		_style(none, 8, Color(0.72, 0.66, 0.60, 0.95))
		_hover_rows.add_child(none)
		return

	for e in listing:
		_hover_rows.add_child(_make_hover_row(e))

	# Warn about anything that flips on us next round (booby-trapped pills).
	var pending: Array = []
	if _sys and _sys.has_method("pending_next_round"):
		pending = _sys.pending_next_round()
	for p in pending:
		var warn := Label.new()
		warn.text = "! %s becomes %+d next round" % [String(p["label"]), int(p["to"])]
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.custom_minimum_size = Vector2(180, 0)
		_style(warn, 7, Color(1.0, 0.60, 0.35, 1.0))
		_hover_rows.add_child(warn)


func _make_hover_row(e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(ROW_ICON_PX, ROW_ICON_PX)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var amount: int = int(e.get("amount", 0))
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.10, 0.07, 0.06, 0.96)
	# Green border = it is helping you, red = it is not.
	st.border_color = Color(0.35, 0.75, 0.40, 0.95) if amount < 0 else Color(0.85, 0.30, 0.35, 0.95)
	if bool(e.get("locked", false)):
		st.border_color = Color(0.62, 0.10, 0.10, 1.0)
	st.set_border_width_all(2)
	st.set_corner_radius_all(2)
	st.set_content_margin_all(2)
	slot.add_theme_stylebox_override("panel", st)
	row.add_child(slot)

	var tex: Texture2D = _load_tex(String(e.get("tex", "")))
	if tex != null:
		var ic := TextureRect.new()
		ic.texture = tex
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(ROW_ICON_PX - 6, ROW_ICON_PX - 6)
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(ic)
	else:
		var fb := Label.new()
		fb.text = String(e.get("label", "?")).left(2).to_upper()
		_style(fb, 8, HUD_TEXT)
		fb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(fb)

	var name_label := Label.new()
	name_label.text = String(e.get("label", ""))
	name_label.custom_minimum_size = Vector2(132, 0)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style(name_label, 8, Color(0.98, 0.94, 0.88, 1.0))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)

	var amt := Label.new()
	amt.text = "%+d" % amount
	_style(amt, 9, Color(0.55, 0.90, 0.58, 1.0) if amount < 0 else Color(1.0, 0.45, 0.40, 1.0))
	amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amt.custom_minimum_size = Vector2(28, 0)
	amt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(amt)

	# Full flavour text still lives on hover-over-the-row.
	row.tooltip_text = String(e.get("tip", ""))
	return row


func refresh() -> void:
	if _sys == null:
		return
	_target = float(_sys.value())
	if _value_label:
		_value_label.text = "%d" % int(round(_target))
	if _bar:
		_bar.queue_redraw()
	if _hovering:
		_rebuild_hover_rows()
		_position_hover_panel()


func _on_anxiety_changed(_value: int, _previous: int) -> void:
	refresh()


func _on_modifier_applied(_id: String, _amount: int) -> void:
	_flash_t = FLASH_SEC
	refresh()


func _process(delta: float) -> void:
	if _sys == null:
		return
	var moved := false
	if absf(_shown - _target) > 0.05:
		_shown = lerpf(_shown, _target, clampf(delta * EASE_SPEED, 0.0, 1.0))
		moved = true
	else:
		_shown = _target
	if _flash_t > 0.0:
		_flash_t = maxf(_flash_t - delta, 0.0)
		moved = true
	var v: int = int(round(_target))
	if v > CALM_MAX:
		_pulse_t += delta
		moved = true
		_shake = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) if v >= PANIC_MIN else Vector2.ZERO
	elif _shake != Vector2.ZERO:
		_shake = Vector2.ZERO
		moved = true
	if moved and _bar:
		_bar.queue_redraw()
	if _hovering:
		_position_hover_panel()


func _draw_bar() -> void:
	if _bar == null:
		return
	var w: float = _bar.size.x
	var h: float = _bar.size.y
	var inner := Rect2(1.0, 1.0, w - 2.0, h - 2.0)

	# Frame + empty track
	_bar.draw_rect(Rect2(0.0, 0.0, w, h), TRACK_EDGE, true)
	_bar.draw_rect(inner, TRACK_BG, true)

	var pct: float = clampf(_shown / 100.0, 0.0, 1.0)
	var fill_w: float = inner.size.x * pct

	if fill_w > 0.5:
		# Hotter red the higher it goes.
		var heat: float = clampf(_shown / 100.0, 0.0, 1.0)
		var col: Color = FILL_LOW.lerp(FILL_HIGH, heat)
		if int(round(_target)) > CALM_MAX:
			# Breathing glow — faster and stronger as it approaches 100.
			var speed: float = lerpf(3.4, 7.0, clampf((heat - 0.6) / 0.4, 0.0, 1.0))
			var amp: float = lerpf(0.06, 0.20, clampf((heat - 0.6) / 0.4, 0.0, 1.0))
			col = col.lightened(amp * (0.5 + 0.5 * sin(_pulse_t * speed)))
		if _flash_t > 0.0:
			col = col.lerp(Color(1.0, 0.95, 0.90, 1.0), (_flash_t / FLASH_SEC) * 0.8)
		var fill_rect := Rect2(inner.position + _shake, Vector2(fill_w, inner.size.y))
		_bar.draw_rect(fill_rect, col, true)
		# Top shine strip so the fill reads as a lit surface, not a flat block.
		_bar.draw_rect(
			Rect2(inner.position + Vector2(0.0, 1.0), Vector2(fill_w, 2.0)),
			FILL_SHINE, true
		)

	# Permanent murder anxiety: darker red over the left end of the fill.
	var lock_ratio: float = 0.0
	if _sys and _sys.has_method("locked_ratio"):
		lock_ratio = float(_sys.locked_ratio())
	if lock_ratio > 0.0:
		var lock_w: float = inner.size.x * lock_ratio
		_bar.draw_rect(Rect2(inner.position, Vector2(lock_w, inner.size.y)), LOCKED_FILL, true)
		_bar.draw_rect(
			Rect2(inner.position + Vector2(lock_w - 1.0, 0.0), Vector2(2.0, inner.size.y)),
			LOCKED_EDGE, true
		)

	# Pixel ticks every 10 points.
	for i in range(1, 10):
		var x: float = inner.position.x + inner.size.x * (float(i) / 10.0)
		var tall: bool = (i == 5)
		var th: float = inner.size.y if tall else inner.size.y * 0.45
		_bar.draw_rect(
			Rect2(Vector2(x, inner.position.y + inner.size.y - th), Vector2(1.0, th)),
			TICK, true
		)

	# Full bar gets a bright cap so "maxed out" is unmistakable.
	if pct >= 0.999:
		_bar.draw_rect(Rect2(0.0, 0.0, w, h), Color(1.0, 0.85, 0.55, 0.9), false, 2.0)


func _panel_style(margin: int) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = HUD_BG
	st.border_color = HUD_BORDER
	st.set_border_width_all(2)
	st.set_corner_radius_all(6)
	st.set_content_margin_all(margin)
	return st


func _style(lab: Label, size: int, color: Color) -> void:
	if _font != null:
		lab.add_theme_font_override("font", _font)
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", color)


## Textures may not be imported yet on a fresh checkout — fall back to raw load.
func _load_tex(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		var t: Variant = load(path)
		if t is Texture2D:
			return t as Texture2D
	var abs_path: String = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img:
			return ImageTexture.create_from_image(img)
	return null
