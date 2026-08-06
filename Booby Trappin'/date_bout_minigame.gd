extends Control
## THE BOUT — Level 3 (The Date), minigame round 2: SURVIVE IT.
##
## Round 1 decided what you managed to hide. This round is everything you did
## not. She works through your exposed traits one at a time, and each one is an
## attack you have to read and answer before the window shuts.
##
## Modelled on Punch-Out!!, played as a conversation. Every attack has a TELL —
## a bubble whose COLOUR is the whole read — and a short window to respond:
##
##   Probe  (gold)   small talk drifting toward it   -> A, deflect
##   Dig    (orange) she has heard something         -> D, turn it around
##   Direct (red)    she just asks                   -> S, own it
##
## Direct is the keystone. It cannot be dodged, only confessed, and a clean
## confession is worth more than any smooth counter — vulnerability lands. Own
## it late and it is the hardest hit in the game. That single rule is what stops
## this being three-way whack-a-mole and makes it a conversation.
##
## Read a Probe or a Dig correctly and she is briefly off balance: that is your
## OPENING, and W turns it into charm. Skipping the counter is a legitimate
## defensive style — you survive and never win her over.
##
## Two bars:
##   COMPOSURE     starts at 100 - anxiety. This is how the whole run's dread
##                 finally cashes out: arrive wrecked and you fight with a
##                 sliver. Zero means a public meltdown.
##   HER INTEREST  starts at 50, and where it lands at the final bell is the
##                 ending.
##
## What anxiety does NOT do is randomise your input. Punishing execution you
## performed correctly reads as a bug. It attacks your READING instead: the
## tells get shorter, and the bubble lies about its colour for longer before it
## settles. Fair, thematic, and still brutal.
##
## Public API:
##   run_pressure_phase(exposed) -> Dictionary    Player 1's setup turn
##   show_and_play(exposed, anxiety, pressure) -> Dictionary
##
## Art: date_bout_minigame/*.png, from _src_magenta/gen_art.py, which imports
## the lob's palette and Canvas verbatim so the two rooms cannot drift apart.

signal minigame_finished(result: Dictionary)

# ------------------------------------------------------------------ art ------
const ART_DIR := "res://date_bout_minigame/"
const BACKDROP_PNG := ART_DIR + "db_backdrop.png"
const DATE_PNG := ART_DIR + "db_date.png"
const TABLE_PNG := ART_DIR + "db_table.png"
const BUBBLE_PNG := ART_DIR + "db_bubble.png"
const IMPACT_PNG := ART_DIR + "db_impact.png"

const PLAYER_SHEET := "res://julian assange sprite sheet black.png"
const PLAYER_SHEET_FALLBACK := "res://julian assange sprite sheet.png"
const PLAYER_FRAME_RIGHT := 8
const PLAYER_SHEET_COLS := 4
const PLAYER_SHEET_ROWS := 4
const PLAYER_ZOOM := 2

## Board geometry — MUST match gen_art.py exactly. Same 548x256 board at 2x as
## the lob: round 1 and round 2 are the same evening and sit at the same scale.
const BOARD_W := 548
const BOARD_H := 256
const SCALE := 2.0

const TABLE_X0 := 130
const TABLE_PLATE_Y := 132
const TABLE_CELL_W := 304
const TABLE_CELL_H := 72

const P2_CELL_X := 150
const P2_CELL_Y := 112

const DATE_CELL_W := 86
const DATE_CELL_H := 78
const DATE_X := 344
const DATE_Y := 96

const BUBBLE_CELL_W := 104
const BUBBLE_CELL_H := 66
const BUBBLE_X := 246
const BUBBLE_Y := 22
## The tail eats the bottom of the plate; the body is what text goes in.
const BUBBLE_BODY_H := 53

const IMPACT_CELL := 30

## Trait icons, in the anxiety bar's own slot chrome. 2x the bar's size here so
## they read from across the table — an integer multiple, so still crisp.
const SLOT_PX := 26
const ICON_PX := 20
const BUBBLE_SLOT_PX := 52
const BUBBLE_ICON_PX := 40

# --------------------------------------------------------------- palette -----
const C_INK := Color("#1B1020")
const C_PLATE := Color("#42204A")
const C_MAROON := Color("#8C2E48")
const C_RED := Color("#E36956")
const C_ORANGE := Color("#EFA660")
const C_ORANGE_LT := Color("#FFD07A")
const C_CREAM := Color("#FFFFEB")
const C_GOLD := Color("#FFE478")
const C_GREEN := Color("#3CA370")
const C_GREY := Color("#6E6A80")
const C_GREY_LT := Color("#C6C3D6")

# ------------------------------------------------------------- the fight -----
## tell / window in seconds, dmg in composure. `key` is the only correct answer.
const ATTACKS := {
	"probe": {
		"label": "PROBE", "frame": 0, "colour": C_GOLD,
		"tell": 0.55, "window": 0.70, "dmg": 5, "answer": "deflect",
	},
	"dig": {
		"label": "DIG", "frame": 1, "colour": C_ORANGE,
		"tell": 0.95, "window": 0.58, "dmg": 9, "answer": "turn",
	},
	"direct": {
		"label": "DIRECT", "frame": 2, "colour": C_RED,
		"tell": 1.40, "window": 0.48, "dmg": 14, "answer": "own",
	},
}
const KIND_ORDER := ["probe", "dig", "direct"]

const OPENING_SEC := 0.80
const COUNTER_INTEREST := 9
## A clean confession beats any amount of charm. That is the point of Direct.
const OWNED_INTEREST := 16
const HIT_INTEREST := -7

const INTEREST_START := 50
## Anxiety 100 would otherwise mean a zero-length health bar, and one Direct
## would end the evening before it started. 35 is solved, not picked: it is the
## point where a maxed-out run melts down roughly half the time instead of
## always.
const COMPOSURE_FLOOR := 35

## Three rounds, boxing style. Round 1 teaches the tells, round 3 has teeth.
const ROUNDS := [
	{"name": "DRINKS", "exchanges": 3, "kinds": ["probe"]},
	{"name": "DINNER", "exchanges": 4, "kinds": ["probe", "dig"]},
	{"name": "THE WALK HOME", "exchanges": 4, "kinds": ["probe", "dig", "direct"]},
]
## Composure you get back in the corner, before the anxiety penalty.
const CORNER_RECOVERY := 18

## --- anxiety, in the same 25-point tiers the lob uses --------------------
## An exchange runs: bubble appears -> TELL (wind-up, colour may be lying) ->
## WINDOW opens with the true colour -> deadline. You may answer at any point,
## but answering while it is still lying is a guess.
##
## The WINDOW is the real difficulty knob and these numbers are solved, not
## guessed: against a 280ms +/-70ms reaction time they produce roughly
## 100 / 96 / 71 / 47 / 27 percent across the tiers. The first pass had windows
## nearly three times this wide and simulated at 100% everywhere - the squeeze
## simply never happened.
const WINDOW_SCALE_BY_TIER := [1.00, 0.55, 0.44, 0.36, 0.30]
## The wind-up also shortens, which is pacing rather than difficulty.
const TELL_SCALE_BY_TIER := [1.00, 0.90, 0.78, 0.66, 0.55]
## Fraction of the TELL the bubble spends lying about its colour. At tier 0 it
## is honest immediately, so a calm player can answer early and bank the whole
## wind-up as extra time. From tier 2 up it lies right until the window opens
## and that bonus is gone.
const FLICKER_BY_TIER := [0.00, 0.90, 1.00, 1.00, 1.00]
const FLICKER_HZ := 11.0
const CORNER_PENALTY_BY_TIER := [0.0, 0.12, 0.26, 0.42, 0.58]

## --- Player 1's setup turn -----------------------------------------------
## Same budget as TRAPS_MAX, so the mental model carries over from the traps.
const PRESSURE_POINTS := 3
## 2 points shortens her tell on that trait; 3 upgrades the attack a tier.
const PRESSURE_TELL_SCALE := 0.80
const PRESSURE_DMG_SCALE := 1.25

const ENDINGS := [
	{"min": 75, "outcome": "second_date", "title": "SECOND DATE",
		"line": "She is already picking the place.", "colour": C_GREEN},
	{"min": 45, "outcome": "thinking", "title": "SHE IS THINKING ABOUT IT",
		"line": "Left on read, but not deleted.", "colour": C_GOLD},
	{"min": 0, "outcome": "ghosted", "title": "GHOSTED",
		"line": "Politely, and completely.", "colour": C_RED},
]

const INPUT_GATE_FRAMES := 12

# ---------------------------------------------------------------- copy -------
## The icon carries which trait it is, so the line only has to carry the tone.
const LINES := {
	"probe": [
		"\"So what do you do\nwith your evenings?\"",
		"\"Tell me something\nnobody knows.\"",
		"\"You seem like you\nhave a story.\"",
		"\"What's the worst\njob you ever had?\"",
	],
	"dig": [
		"\"Wait — weren't you\nat that thing?\"",
		"\"My friend says she\nknows you, actually.\"",
		"\"Someone mentioned\nsomething about you.\"",
		"\"You went quiet.\nWhy did you go quiet?\"",
	],
	"direct": [
		"\"Okay. %s.\nExplain that to me.\"",
		"\"I'm going to ask,\nand you're going to\nanswer. %s.\"",
		"\"Let's just do this.\n%s. Go.\"",
	],
}

enum Beat { IDLE, TELL, WINDOW, OPENING, RESOLVE }

# ----------------------------------------------------------------- state -----
var _built := false
var _pixel_font: Font

var _tex_backdrop: Texture2D
var _tex_date: Texture2D
var _tex_table: Texture2D
var _tex_bubble: Texture2D
var _tex_impact: Texture2D
var _tex_player: Texture2D

var _dim: ColorRect
var _outer: PanelContainer
var _title_label: Label
var _round_label: Label
var _stage: Control
var _stage_inner: Control
var _date_rect: TextureRect
var _bubble_root: Control
var _bubble_rect: TextureRect
var _bubble_slot: PanelContainer
var _bubble_icon: TextureRect
var _bubble_text: Label
var _window_track: PanelContainer
var _window_fill: ColorRect
var _tab_panel: PanelContainer
var _tab_label: Label
var _impact_rect: TextureRect
var _call_label: Label
var _flash: ColorRect

var _comp_fill: ColorRect
var _comp_track: PanelContainer
var _comp_label: Label
var _int_fill: ColorRect
var _int_track: PanelContainer
var _int_label: Label

var _pressure_panel: PanelContainer
var _pressure_rows: VBoxContainer
var _pressure_hint: Label

var _summary: PanelContainer
var _summary_rows: VBoxContainer

## run state
var _exposed: Array = []
var _pressure: Dictionary = {}
var _anxiety := 25
var _tier := 1
var _composure_max := 75
var _composure := 75
var _interest := INTEREST_START
var _beat: int = Beat.IDLE
var _log: Array = []
var _running := false
var _abort_requested := false
var _input_gate_frame := 0
## Set by _input(), consumed by the exchange loop. Events give clean edges;
## polling would need its own debounce and the windows are tight enough already.
var _pending := ""
var _shake := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if ResourceLoader.exists("res://PressStart2P-Regular.ttf"):
		_pixel_font = load("res://PressStart2P-Regular.ttf")
	_load_art()
	_build_ui()


# ------------------------------------------------------------------ helpers --
func _load_tex(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		var t := load(path) as Texture2D
		if t != null:
			return t
	var img := Image.new()
	if img.load(path) == OK:
		return ImageTexture.create_from_image(img)
	push_warning("[Bout] missing art: %s" % path)
	return null


func _load_art() -> void:
	_tex_backdrop = _load_tex(BACKDROP_PNG)
	_tex_date = _load_tex(DATE_PNG)
	_tex_table = _load_tex(TABLE_PNG)
	_tex_bubble = _load_tex(BUBBLE_PNG)
	_tex_impact = _load_tex(IMPACT_PNG)
	_tex_player = _load_tex(PLAYER_SHEET)
	if _tex_player == null:
		_tex_player = _load_tex(PLAYER_SHEET_FALLBACK)


func _atlas(tex: Texture2D, index: int, cell_w: int, cell_h: int) -> Texture2D:
	if tex == null:
		return null
	var a := AtlasTexture.new()
	a.atlas = tex
	a.region = Rect2(index * cell_w, 0, cell_w, cell_h)
	a.filter_clip = true
	return a


func _atlas_grid(tex: Texture2D, frame: int, cols: int, rows: int) -> Texture2D:
	if tex == null:
		return null
	var cw: int = int(tex.get_width() / float(cols))
	var ch: int = int(tex.get_height() / float(rows))
	var a := AtlasTexture.new()
	a.atlas = tex
	a.region = Rect2((frame % cols) * cw, (frame / cols) * ch, cw, ch)
	a.filter_clip = true
	return a


func _pixel_rect(tex: Texture2D, w: float, h: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.custom_minimum_size = Vector2(w, h)
	r.size = Vector2(w, h)
	return r


func _style_label(lab: Label, size: int, color: Color) -> void:
	if _pixel_font:
		lab.add_theme_font_override("font", _pixel_font)
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", color)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _panel_style(bg: Color, border: Color, width: int = 2, radius: int = 4,
		margin: int = 8) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(width)
	st.set_corner_radius_all(radius)
	st.set_content_margin_all(margin)
	return st


func _px(v: float) -> float:
	return v * SCALE


## The anxiety bar's slot, rebuilt. `size` lets the bubble show a 2x version
## without breaking pixel alignment.
func _make_icon_square(tex: Texture2D, amount: int, locked: bool,
		border_override = null, size: int = SLOT_PX) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(size, size)
	slot.size = Vector2(size, size)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border: Color = C_GREEN if amount < 0 else C_RED
	if locked:
		border = Color(0.62, 0.10, 0.10, 1.0)
	if border_override != null:
		border = border_override
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.10, 0.07, 0.06, 0.96)
	st.border_color = border
	st.set_border_width_all(2 if size <= SLOT_PX else 3)
	st.set_corner_radius_all(2)
	st.set_content_margin_all(2 if size <= SLOT_PX else 4)
	slot.add_theme_stylebox_override("panel", st)

	var ic := TextureRect.new()
	ic.name = "Icon"
	ic.texture = tex
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var inner: int = ICON_PX if size <= SLOT_PX else BUBBLE_ICON_PX
	ic.custom_minimum_size = Vector2(inner, inner)
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(ic)
	return slot


func _tier_of(anxiety: int) -> int:
	return clampi(int(anxiety / 25), 0, TELL_SCALE_BY_TIER.size() - 1)


# ----------------------------------------------------------------- build -----
func _build_ui() -> void:
	if _built:
		return
	_built = true

	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.01, 0.04, 0.88)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_outer = PanelContainer.new()
	_outer.add_theme_stylebox_override("panel", _panel_style(C_PLATE, C_INK, 3, 8, 6))
	_outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_outer)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outer.add_child(col)

	col.add_child(_build_header())
	col.add_child(_build_stage())
	col.add_child(_build_legend())

	_build_pressure_panel()
	_build_summary()


func _build_header() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel",
		_panel_style(Color(0.06, 0.04, 0.08, 0.95), C_GOLD, 2, 4, 6))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(row)

	_title_label = Label.new()
	_title_label.text = "THE DATE  —  ROUND 2:  THE BOUT"
	_style_label(_title_label, 11, C_GOLD)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_title_label)

	_round_label = Label.new()
	_round_label.text = ""
	_style_label(_round_label, 9, C_GREY_LT)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_round_label)
	return bar


func _build_stage() -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _panel_style(C_INK, C_MAROON, 2, 4, 2))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_stage = Control.new()
	_stage.custom_minimum_size = Vector2(_px(BOARD_W), _px(BOARD_H))
	_stage.clip_contents = true
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_stage)

	# Everything that should shake on a hit lives under here.
	_stage_inner = Control.new()
	_stage_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_stage_inner)

	_stage_inner.add_child(_pixel_rect(_tex_backdrop, _px(BOARD_W), _px(BOARD_H)))

	# --- the date: a backlit silhouette, three poses ----------------------
	_date_rect = _pixel_rect(_atlas(_tex_date, 0, DATE_CELL_W, DATE_CELL_H),
		_px(DATE_CELL_W), _px(DATE_CELL_H))
	_date_rect.position = Vector2(_px(DATE_X), _px(DATE_Y))
	_stage_inner.add_child(_date_rect)

	# --- Player 2: the real sprite ----------------------------------------
	var pw := 0.0
	var ph := 0.0
	if _tex_player != null:
		pw = (_tex_player.get_width() / float(PLAYER_SHEET_COLS)) * float(PLAYER_ZOOM)
		ph = (_tex_player.get_height() / float(PLAYER_SHEET_ROWS)) * float(PLAYER_ZOOM)
	var p2 := _pixel_rect(
		_atlas_grid(_tex_player, PLAYER_FRAME_RIGHT, PLAYER_SHEET_COLS, PLAYER_SHEET_ROWS),
		pw, ph)
	p2.position = Vector2(_px(P2_CELL_X), _px(P2_CELL_Y))
	_stage_inner.add_child(p2)

	# --- the table, drawn OVER both of them so they read as seated --------
	var table := _pixel_rect(_tex_table, _px(TABLE_CELL_W), _px(TABLE_CELL_H))
	table.position = Vector2(_px(TABLE_X0), _px(TABLE_PLATE_Y))
	_stage_inner.add_child(table)

	_impact_rect = _pixel_rect(_atlas(_tex_impact, 0, IMPACT_CELL, IMPACT_CELL),
		_px(IMPACT_CELL), _px(IMPACT_CELL))
	_impact_rect.visible = false
	_stage_inner.add_child(_impact_rect)

	_build_bubble()
	_build_bars()

	_call_label = Label.new()
	_call_label.text = ""
	_style_label(_call_label, 20, C_CREAM)
	_call_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_call_label.position = Vector2(0.0, _px(BOARD_H) * 0.62)
	_call_label.custom_minimum_size = Vector2(_px(BOARD_W), 0)
	_call_label.size = Vector2(_px(BOARD_W), 28)
	_stage.add_child(_call_label)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_flash)
	return frame


func _build_bubble() -> void:
	_bubble_root = Control.new()
	_bubble_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_root.position = Vector2(_px(BUBBLE_X), _px(BUBBLE_Y))
	_bubble_root.visible = false
	_stage.add_child(_bubble_root)

	_bubble_rect = _pixel_rect(_atlas(_tex_bubble, 0, BUBBLE_CELL_W, BUBBLE_CELL_H),
		_px(BUBBLE_CELL_W), _px(BUBBLE_CELL_H))
	_bubble_root.add_child(_bubble_rect)

	_bubble_slot = _make_icon_square(null, 1, false, C_GOLD, BUBBLE_SLOT_PX)
	_bubble_slot.position = Vector2(14, 20)
	_bubble_root.add_child(_bubble_slot)
	_bubble_icon = _bubble_slot.get_node("Icon") as TextureRect

	_bubble_text = Label.new()
	_bubble_text.text = ""
	_style_label(_bubble_text, 8, C_CREAM)
	_bubble_text.position = Vector2(76, 20)
	_bubble_text.custom_minimum_size = Vector2(_px(BUBBLE_CELL_W) - 92, 0)
	_bubble_text.size = Vector2(_px(BUBBLE_CELL_W) - 92, 60)
	_bubble_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_root.add_child(_bubble_text)

	# The window, draining along the bottom of the bubble.
	_window_track = PanelContainer.new()
	_window_track.add_theme_stylebox_override("panel",
		_panel_style(Color(0.08, 0.05, 0.09, 1.0), C_INK, 2, 2, 2))
	_window_track.position = Vector2(14, _px(BUBBLE_BODY_H) - 22)
	_window_track.custom_minimum_size = Vector2(_px(BUBBLE_CELL_W) - 28, 14)
	_window_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_root.add_child(_window_track)

	var holder := Control.new()
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window_track.add_child(holder)

	_window_fill = ColorRect.new()
	_window_fill.color = C_GOLD
	_window_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window_fill.position = Vector2.ZERO
	_window_fill.size = Vector2(0, 10)
	holder.add_child(_window_fill)

	# Attack-type tab, so the colour is also spelled out in words.
	_tab_panel = PanelContainer.new()
	_tab_panel.add_theme_stylebox_override("panel",
		_panel_style(Color(0.16, 0.09, 0.07, 0.96), C_GOLD, 2, 3, 4))
	_tab_panel.position = Vector2(_px(BUBBLE_CELL_W) - 96, -22)
	_tab_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_root.add_child(_tab_panel)

	_tab_label = Label.new()
	_tab_label.text = "PROBE"
	_style_label(_tab_label, 9, C_GOLD)
	_tab_panel.add_child(_tab_label)


func _build_bars() -> void:
	var made := _make_bar(C_GREEN, "COMPOSURE")
	_comp_track = made["track"]
	_comp_fill = made["fill"]
	_comp_label = made["value"]
	(made["root"] as Control).position = Vector2(22, 44)
	_stage.add_child(made["root"])

	made = _make_bar(C_RED, "HER INTEREST")
	_int_track = made["track"]
	_int_fill = made["fill"]
	_int_label = made["value"]
	(made["root"] as Control).position = Vector2(_px(BOARD_W) - 312, 44)
	_stage.add_child(made["root"])


func _make_bar(colour: Color, label_text: String) -> Dictionary:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 2)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.custom_minimum_size = Vector2(290, 0)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)

	var name_lab := Label.new()
	name_lab.text = label_text
	_style_label(name_lab, 8, colour)
	name_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_lab)

	var value := Label.new()
	value.text = "0"
	_style_label(value, 8, C_CREAM)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.custom_minimum_size = Vector2(34, 0)
	top.add_child(value)

	var track := PanelContainer.new()
	track.add_theme_stylebox_override("panel",
		_panel_style(Color(0.08, 0.05, 0.09, 0.92), C_INK, 2, 2, 2))
	track.custom_minimum_size = Vector2(290, 20)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(track)

	var holder := Control.new()
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(holder)

	var fill := ColorRect.new()
	fill.color = colour
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.position = Vector2.ZERO
	fill.size = Vector2(0, 16)
	holder.add_child(fill)

	return {"root": root, "track": track, "fill": fill, "value": value}


func _build_legend() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel",
		_panel_style(Color(0.06, 0.04, 0.08, 0.95), C_PLATE, 2, 4, 6))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(row)

	for entry in [["A", "DEFLECT", C_GOLD], ["D", "TURN IT AROUND", C_ORANGE],
			["S", "OWN IT", C_RED], ["W", "CHARM", C_GREEN]]:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var key := PanelContainer.new()
		key.add_theme_stylebox_override("panel",
			_panel_style(Color(0.12, 0.07, 0.13, 1.0), entry[2], 2, 2, 3))
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var kl := Label.new()
		kl.text = String(entry[0])
		_style_label(kl, 8, entry[2])
		key.add_child(kl)
		cell.add_child(key)
		var dl := Label.new()
		dl.text = String(entry[1])
		_style_label(dl, 8, C_GREY_LT)
		dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(dl)
		row.add_child(cell)
	return bar


func _build_pressure_panel() -> void:
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)

	_pressure_panel = PanelContainer.new()
	_pressure_panel.add_theme_stylebox_override("panel",
		_panel_style(Color(0.04, 0.02, 0.05, 0.98), C_GOLD, 3, 6, 16))
	_pressure_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pressure_panel.visible = false
	holder.add_child(_pressure_panel)

	_pressure_rows = VBoxContainer.new()
	_pressure_rows.add_theme_constant_override("separation", 6)
	_pressure_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pressure_panel.add_child(_pressure_rows)

	_pressure_hint = Label.new()
	_pressure_hint.text = ""
	_style_label(_pressure_hint, 8, C_GREY_LT)


func _build_summary() -> void:
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)

	_summary = PanelContainer.new()
	_summary.add_theme_stylebox_override("panel",
		_panel_style(Color(0.04, 0.02, 0.05, 0.98), C_GOLD, 3, 6, 18))
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary.visible = false
	holder.add_child(_summary)

	_summary_rows = VBoxContainer.new()
	_summary_rows.add_theme_constant_override("separation", 8)
	_summary_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary.add_child(_summary_rows)


# ================================================== Player 1's setup turn =====
## 3 points across her repertoire. Spend them and she presses harder: 2 points
## shortens her tell on that trait, 3 upgrades its attacks a whole tier. Same
## budget as TRAPS_MAX so it reads as the trap phase wearing a different hat.
func run_pressure_phase(exposed: Array) -> Dictionary:
	if not _built:
		_load_art()
		_build_ui()
	var pool: Array = _prepare(exposed)
	if pool.is_empty():
		return {}

	var spend: Dictionary = {}
	for t in pool:
		spend[String(t["id"])] = 0
	var left: int = PRESSURE_POINTS
	var sel: int = 0

	visible = true
	_running = true
	get_tree().paused = true
	_input_gate_frame = Engine.get_process_frames() + INPUT_GATE_FRAMES
	_pressure_panel.visible = true
	_title_label.text = "PLAYER 1  —  BRIEF HER"
	_round_label.text = ""

	while _running:
		_render_pressure(pool, spend, left, sel)
		var dt: float = await _tick()
		if dt < 0.0:
			break
		if not _gate_open():
			continue
		var k := _take_pending()
		match k:
			"up":
				sel = posmod(sel - 1, pool.size())
			"down":
				sel = posmod(sel + 1, pool.size())
			"confirm":
				if left > 0:
					var id := String(pool[sel]["id"])
					spend[id] = int(spend[id]) + 1
					left -= 1
			"undo":
				var id2 := String(pool[sel]["id"])
				if int(spend[id2]) > 0:
					spend[id2] = int(spend[id2]) - 1
					left += 1
			"done":
				break
		if left <= 0:
			await _wait(0.45)
			break

	_render_pressure(pool, spend, left, sel)
	await _wait(0.6)
	_pressure_panel.visible = false
	_title_label.text = "THE DATE  —  ROUND 2:  THE BOUT"
	_running = false
	visible = false
	get_tree().paused = false
	return spend


func _render_pressure(pool: Array, spend: Dictionary, left: int, sel: int) -> void:
	for c in _pressure_rows.get_children():
		c.queue_free()

	var head := Label.new()
	head.text = "SHE HAS ALREADY SEEN THESE"
	_style_label(head, 12, C_GOLD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pressure_rows.add_child(head)

	var sub := Label.new()
	sub.text = "Spend %d to make her press harder.   POINTS LEFT: %d" % [PRESSURE_POINTS, left]
	_style_label(sub, 8, C_GREY_LT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pressure_rows.add_child(sub)

	for i in range(pool.size()):
		var t: Dictionary = pool[i]
		var id := String(t["id"])
		var n: int = int(spend.get(id, 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var caret := Label.new()
		caret.text = ">" if i == sel else " "
		_style_label(caret, 10, C_GOLD)
		caret.custom_minimum_size = Vector2(14, 0)
		row.add_child(caret)

		row.add_child(_make_icon_square(_load_tex(String(t.get("tex", ""))),
			int(t.get("amount", 1)), bool(t.get("locked", false)),
			C_GOLD if i == sel else C_GREY))

		var name_lab := Label.new()
		name_lab.text = String(t.get("label", id))
		_style_label(name_lab, 9, C_CREAM if i == sel else C_GREY_LT)
		name_lab.custom_minimum_size = Vector2(190, 0)
		row.add_child(name_lab)

		var pips := Label.new()
		pips.text = "*".repeat(n) + ".".repeat(PRESSURE_POINTS - n)
		_style_label(pips, 11, C_RED if n > 0 else C_GREY)
		pips.custom_minimum_size = Vector2(46, 0)
		row.add_child(pips)

		var eff := Label.new()
		eff.text = ["", "SHE WILL ASK", "SHORTER TELL", "HARDER ATTACK"][clampi(n, 0, 3)]
		_style_label(eff, 8, C_ORANGE)
		eff.custom_minimum_size = Vector2(140, 0)
		row.add_child(eff)

		_pressure_rows.add_child(row)

	var foot := Label.new()
	foot.text = "W / S  SELECT      E  SPEND      BACKSPACE  TAKE BACK      ENTER  DONE"
	_style_label(foot, 8, C_GREY_LT)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pressure_rows.add_child(foot)


# ============================================================= public API =====
func show_and_play(exposed: Array, anxiety: int, pressure: Dictionary) -> Dictionary:
	if not _built:
		_load_art()
		_build_ui()

	_exposed = _prepare(exposed)
	_pressure = pressure if pressure != null else {}
	_anxiety = clampi(anxiety, 0, 100)
	_tier = _tier_of(_anxiety)
	_composure_max = maxi(COMPOSURE_FLOOR, 100 - _anxiety)
	_composure = _composure_max
	_interest = INTEREST_START
	_log.clear()
	_abort_requested = false
	_summary.visible = false
	_bubble_root.visible = false
	_call_label.text = ""
	_flash.color = Color(1, 1, 1, 0)
	_set_date_frame(0)

	if _exposed.is_empty():
		return await _play_empty()

	visible = true
	_running = true
	get_tree().paused = true
	_input_gate_frame = Engine.get_process_frames() + INPUT_GATE_FRAMES
	_refresh_bars()

	_call_label.text = "SHE ALREADY KNOWS %d THINGS" % _exposed.size()
	_round_label.text = "ANXIETY %d   COMPOSURE %d" % [_anxiety, _composure_max]
	await _wait(1.4)
	_call_label.text = ""

	var melted := false
	for r in range(ROUNDS.size()):
		if _abort_requested or melted:
			break
		var cfg: Dictionary = ROUNDS[r]
		_round_label.text = "ROUND %d/%d   %s" % [r + 1, ROUNDS.size(), String(cfg["name"])]
		_call_out("ROUND %d — %s" % [r + 1, String(cfg["name"])], C_GOLD)
		await _wait(1.2)
		_call_label.text = ""

		var bag: Array = _build_bag(cfg)
		for e in range(bag.size()):
			if _abort_requested:
				break
			await _play_exchange(bag[e])
			if _composure <= 0:
				melted = true
				break

		if melted or _abort_requested:
			break
		if r < ROUNDS.size() - 1:
			await _corner()

	_bubble_root.visible = false
	var result: Dictionary = _finish(melted)
	await _show_summary(result)

	_running = false
	visible = false
	get_tree().paused = false
	minigame_finished.emit(result)
	return result


func hide_popup() -> void:
	_running = false
	visible = false
	if get_tree():
		get_tree().paused = false


# ------------------------------------------------------------------ setup ----
func _prepare(exposed: Array) -> Array:
	var out: Array = []
	for t in exposed:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var id: String = String(t.get("id", ""))
		if id.is_empty():
			continue
		out.append({
			"id": id,
			"label": String(t.get("label", id)),
			"amount": int(t.get("amount", 0)),
			"tex": String(t.get("tex", "")),
			"locked": bool(t.get("locked", false)),
		})
	out.sort_custom(func(a, b): return int(a["amount"]) > int(b["amount"]))
	return out.slice(0, 5)


## One round's worth of exchanges. Traits P1 paid for come up more often, and
## at 3 points their attack is upgraded a whole tier.
func _build_bag(cfg: Dictionary) -> Array:
	var kinds: Array = cfg["kinds"]
	var want: int = int(cfg["exchanges"])
	var weighted: Array = []
	for t in _exposed:
		weighted.append(t)
		for _i in range(int(_pressure.get(String(t["id"]), 0))):
			weighted.append(t)
	weighted.shuffle()

	var bag: Array = []
	for i in range(want):
		var t: Dictionary = weighted[i % weighted.size()]
		var kind: String = String(kinds[randi() % kinds.size()])
		if int(_pressure.get(String(t["id"]), 0)) >= 3:
			var up: int = KIND_ORDER.find(kind) + 1
			kind = String(KIND_ORDER[mini(up, KIND_ORDER.size() - 1)])
		bag.append({"trait": t, "kind": kind})
	return bag


# --------------------------------------------------------------- exchange ----
func _play_exchange(entry: Dictionary) -> void:
	var t: Dictionary = entry["trait"]
	var kind: String = String(entry["kind"])
	var cfg: Dictionary = ATTACKS[kind]
	var press: int = int(_pressure.get(String(t["id"]), 0))

	var tell: float = float(cfg["tell"]) * float(TELL_SCALE_BY_TIER[_tier])
	if press >= 2:
		tell *= PRESSURE_TELL_SCALE
	var window: float = float(cfg["window"]) * float(WINDOW_SCALE_BY_TIER[_tier])
	var deadline: float = tell + window
	var flicker: float = tell * float(FLICKER_BY_TIER[_tier])

	_show_bubble(t, kind)
	_set_date_frame(1)
	_take_pending()

	var elapsed := 0.0
	var answered := ""
	_beat = Beat.TELL
	while elapsed < deadline and _running and not _abort_requested:
		var dt: float = await _tick()
		if dt < 0.0:
			break
		elapsed += dt
		# The bubble lies about its colour while flickering, then settles.
		if elapsed < flicker:
			var fake: String = String(KIND_ORDER[int(elapsed * FLICKER_HZ) % KIND_ORDER.size()])
			_paint_bubble(fake)
		else:
			_paint_bubble(kind)
			_beat = Beat.WINDOW
		_set_window(1.0 - clampf(elapsed / deadline, 0.0, 1.0), Color(cfg["colour"]))
		var k := _take_pending()
		if k in ["deflect", "turn", "own"]:
			answered = k
			break

	var correct: bool = answered == String(cfg["answer"])
	var dmg: int = int(round(float(cfg["dmg"]) * (PRESSURE_DMG_SCALE if press >= 1 else 1.0)))

	if correct and kind == "direct":
		# Confession, timed right. Worth more than any counter.
		_interest += OWNED_INTEREST
		_set_date_frame(2)
		_call_out("OWNED IT", C_GREEN)
		_flash_stage(Color(0.42, 0.85, 0.55, 0.26))
		_log.append({"id": t["id"], "kind": kind, "result": "owned"})
	elif correct:
		_set_date_frame(2)
		_call_out("SHE FALTERS", C_GOLD)
		_bubble_root.visible = false
		var charmed: bool = await _opening()
		if charmed:
			_interest += COUNTER_INTEREST
			_call_out("CHARMED", C_GREEN)
			_flash_stage(Color(0.42, 0.85, 0.55, 0.22))
			_log.append({"id": t["id"], "kind": kind, "result": "charmed"})
		else:
			_call_out("SAFE", C_GREY_LT)
			_log.append({"id": t["id"], "kind": kind, "result": "safe"})
	else:
		_composure -= dmg
		_interest += HIT_INTEREST
		_set_date_frame(0)
		_impact_at(Vector2(P2_CELL_X + 22, P2_CELL_Y + 18))
		_call_out("SHE SAW IT" if answered.is_empty() else "WRONG ANSWER", C_RED)
		_flash_stage(Color(0.90, 0.30, 0.28, 0.30))
		_shake = 1.0
		_log.append({"id": t["id"], "kind": kind, "result": "hit", "dmg": dmg})

	_interest = clampi(_interest, 0, 100)
	_refresh_bars()
	_bubble_root.visible = false
	await _wait(0.85)
	_call_label.text = ""
	_set_date_frame(0)
	_beat = Beat.IDLE


## Her guard is down. W turns that into charm; doing nothing is merely safe.
func _opening() -> bool:
	_beat = Beat.OPENING
	_take_pending()
	var t := 0.0
	while t < OPENING_SEC and _running and not _abort_requested:
		var dt: float = await _tick()
		if dt < 0.0:
			break
		t += dt
		_set_window(1.0 - t / OPENING_SEC, C_GREEN)
		if _take_pending() == "charm":
			return true
	return false


func _corner() -> void:
	var back: int = int(round(CORNER_RECOVERY
		* (1.0 - float(CORNER_PENALTY_BY_TIER[_tier]))))
	_composure = mini(_composure_max, _composure + back)
	_refresh_bars()
	_call_out("+%d COMPOSURE" % back, C_GREEN)
	await _wait(1.3)
	_call_label.text = ""


func _finish(melted: bool) -> Dictionary:
	var outcome := "ghosted"
	if melted or _composure <= 0:
		outcome = "meltdown"
	else:
		for e in ENDINGS:
			if _interest >= int(e["min"]):
				outcome = String(e["outcome"])
				break
	return {
		"outcome": outcome,
		"interest": _interest,
		"composure": maxi(_composure, 0),
		"anxiety": _anxiety,
		"log": _log.duplicate(),
	}


func _play_empty() -> Dictionary:
	visible = true
	_interest = 85
	_refresh_bars()
	_call_out("SHE HAS NOTHING TO GO ON", C_GREEN)
	await _wait(2.0)
	visible = false
	var result := {
		"outcome": "second_date", "interest": _interest,
		"composure": _composure_max, "anxiety": _anxiety, "log": [],
	}
	minigame_finished.emit(result)
	return result


# ----------------------------------------------------------- presentation ----
func _show_bubble(t: Dictionary, kind: String) -> void:
	if _bubble_icon:
		_bubble_icon.texture = _load_tex(String(t.get("tex", "")))
	var pool: Array = LINES[kind]
	var line: String = String(pool[randi() % pool.size()])
	if line.contains("%s"):
		line = line % String(t.get("label", "")).to_upper()
	_bubble_text.text = line
	_paint_bubble(kind)
	_bubble_root.visible = true


func _paint_bubble(kind: String) -> void:
	var cfg: Dictionary = ATTACKS[kind]
	_bubble_rect.texture = _atlas(_tex_bubble, int(cfg["frame"]),
		BUBBLE_CELL_W, BUBBLE_CELL_H)
	var col: Color = cfg["colour"]
	_tab_label.text = String(cfg["label"])
	_tab_label.add_theme_color_override("font_color", col)
	_tab_panel.add_theme_stylebox_override("panel",
		_panel_style(Color(0.16, 0.09, 0.07, 0.96), col, 2, 3, 4))
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.10, 0.07, 0.06, 0.96)
	st.border_color = col
	st.set_border_width_all(3)
	st.set_corner_radius_all(2)
	st.set_content_margin_all(4)
	_bubble_slot.add_theme_stylebox_override("panel", st)


func _set_window(frac: float, col: Color) -> void:
	var w: float = maxf(_window_track.size.x, _window_track.custom_minimum_size.x) - 4.0
	_window_fill.size = Vector2(maxf(w, 1.0) * clampf(frac, 0.0, 1.0), 10.0)
	_window_fill.color = col


func _set_date_frame(frame: int) -> void:
	if _date_rect:
		_date_rect.texture = _atlas(_tex_date, frame, DATE_CELL_W, DATE_CELL_H)


func _refresh_bars() -> void:
	var cw: float = maxf(_comp_track.size.x, _comp_track.custom_minimum_size.x) - 4.0
	_comp_fill.size = Vector2(maxf(cw, 1.0)
		* clampf(float(_composure) / float(_composure_max), 0.0, 1.0), 16.0)
	_comp_fill.color = C_GREEN.lerp(C_RED,
		1.0 - clampf(float(_composure) / float(_composure_max), 0.0, 1.0))
	_comp_label.text = "%d" % maxi(_composure, 0)

	var iw: float = maxf(_int_track.size.x, _int_track.custom_minimum_size.x) - 4.0
	_int_fill.size = Vector2(maxf(iw, 1.0) * clampf(_interest / 100.0, 0.0, 1.0), 16.0)
	_int_fill.color = C_RED.lerp(C_GREEN, clampf(_interest / 100.0, 0.0, 1.0))
	_int_label.text = "%d" % _interest


func _call_out(text: String, colour: Color) -> void:
	_call_label.text = text
	_call_label.add_theme_color_override("font_color", colour)


func _flash_stage(colour: Color) -> void:
	if _flash == null:
		return
	_flash.color = colour
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_flash, "color",
		Color(colour.r, colour.g, colour.b, 0.0), 0.35)


func _impact_at(board_pos: Vector2) -> void:
	if _impact_rect == null:
		return
	_impact_rect.position = Vector2(_px(board_pos.x) - _px(IMPACT_CELL) * 0.5,
		_px(board_pos.y) - _px(IMPACT_CELL) * 0.5)
	_impact_rect.visible = true
	_animate_impact()


func _animate_impact() -> void:
	for i in range(4):
		if not is_instance_valid(_impact_rect):
			return
		_impact_rect.texture = _atlas(_tex_impact, i, IMPACT_CELL, IMPACT_CELL)
		await _wait(0.07)
	if is_instance_valid(_impact_rect):
		_impact_rect.visible = false


# ----------------------------------------------------------------- summary ---
func _show_summary(result: Dictionary) -> void:
	for c in _summary_rows.get_children():
		c.queue_free()

	var outcome := String(result.get("outcome", "ghosted"))
	var title := "PUBLIC MELTDOWN"
	var line := "You did not make it to dessert."
	var colour := C_RED
	for e in ENDINGS:
		if String(e["outcome"]) == outcome:
			title = String(e["title"])
			line = String(e["line"])
			colour = e["colour"]
			break

	var head := Label.new()
	head.text = title
	_style_label(head, 16, colour)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_rows.add_child(head)

	var sub := Label.new()
	sub.text = line
	_style_label(sub, 9, C_CREAM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_rows.add_child(sub)

	var stats := Label.new()
	stats.text = "HER INTEREST  %d        COMPOSURE LEFT  %d" % [
		int(result.get("interest", 0)), int(result.get("composure", 0))]
	_style_label(stats, 9, C_GREY_LT)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_rows.add_child(stats)

	var owned := 0
	var charmed := 0
	var hits := 0
	for l in _log:
		match String(l.get("result", "")):
			"owned": owned += 1
			"charmed": charmed += 1
			"hit": hits += 1
	var tally := Label.new()
	tally.text = "OWNED %d    CHARMED %d    TAKEN %d" % [owned, charmed, hits]
	_style_label(tally, 8, C_GREY_LT)
	tally.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_rows.add_child(tally)

	_summary.visible = true
	await _wait(3.0)
	_summary.visible = false


# ------------------------------------------------------------------ input ----
func _take_pending() -> String:
	var p := _pending
	_pending = ""
	return p


func _gate_open() -> bool:
	return Engine.get_process_frames() >= _input_gate_frame


func _input(event: InputEvent) -> void:
	if not visible or not _running:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: int = (event as InputEventKey).keycode
	match key:
		KEY_A, KEY_LEFT: _pending = "deflect"
		KEY_D, KEY_RIGHT: _pending = "turn"
		KEY_S: _pending = "own"
		KEY_W: _pending = "charm"
		KEY_E, KEY_SPACE: _pending = "confirm"
		KEY_BACKSPACE: _pending = "undo"
		KEY_ENTER, KEY_KP_ENTER: _pending = "done"
		KEY_ESCAPE:
			_abort_requested = true
			get_viewport().set_input_as_handled()
			return
		_:
			return
	# The pressure picker re-reads W/S as menu movement.
	if _pressure_panel != null and _pressure_panel.visible:
		if key == KEY_W or key == KEY_UP:
			_pending = "up"
		elif key == KEY_S or key == KEY_DOWN:
			_pending = "down"
	get_viewport().set_input_as_handled()


# ------------------------------------------------------------------- ticks ---
func _tick() -> float:
	if get_tree() == null:
		return -1.0
	await get_tree().process_frame
	var dt: float = get_process_delta_time()
	if _shake > 0.001 and _stage_inner:
		_shake = maxf(0.0, _shake - dt * 4.0)
		_stage_inner.position = Vector2(
			randf_range(-6.0, 6.0) * _shake, randf_range(-4.0, 4.0) * _shake)
	elif _stage_inner:
		_stage_inner.position = Vector2.ZERO
	return minf(dt, 1.0 / 20.0)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout
