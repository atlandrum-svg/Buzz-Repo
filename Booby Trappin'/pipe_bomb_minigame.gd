extends Control
## PIPE BOMB — DETONATOR WIRING minigame.
##
## Runs when Player 1 tries to booby-trap the dresser with the pipe bomb.
## Skill: a clamp head sweeps the terminal rail; you must clamp the held wire
## onto the terminal whose collar matches its colour, within a tight window.
## Luck: terminal order reshuffles every attempt, contacts can come up LOOSE,
## and the board throws random power SURGES that yank the clamp faster.
##
## Public API:
##   show_and_play(forced_difficulty := -1) -> Dictionary
##     { outcome, difficulty, difficulty_name, clean, strikes, loose, time_left }
##     outcome: "success" | "failed" | "cancel"
##
## An armed bomb ALWAYS detonates — wiring it is pass/fail, nothing else.
## `difficulty`, `clean`, `strikes`, `loose` and `time_left` ride along in the
## result purely so per-difficulty impacts can be wired on top of this later.
##
## Art: pipe_bomb_minigame/*.png — 16-bit chunky pixels, thick #272736 outlines,
## warm room palette, authored on pure-magenta chroma key then keyed to alpha.

signal minigame_finished(result: Dictionary)

# ------------------------------------------------------------------ art ------
const ART_DIR := "res://pipe_bomb_minigame/"
const BOARD_PNG := ART_DIR + "pb_board.png"
const TERMINALS_PNG := ART_DIR + "pb_terminals.png"
const CLAMP_PNG := ART_DIR + "pb_clamp.png"
const WIRESTUB_PNG := ART_DIR + "pb_wirestub.png"
const SPARK_PNG := ART_DIR + "pb_spark.png"
const FLAME_PNG := ART_DIR + "pb_flame.png"
const BOMB_ICON_PNG := ART_DIR + "pb_bomb_icon.png"

## Board-space geometry (matches gen_art.py exactly).
const BOARD_W := 176
const BOARD_H := 152
const RAIL_CX := 119        ## terminal centre column, board px
const RAIL_TOP := 16.0      ## clamp travel top, board px
const RAIL_BOT := 136.0     ## clamp travel bottom, board px
const TERM_CELL := 24       ## terminal sprite cell (square)
const CLAMP_CELL_W := 52
const CLAMP_CELL_H := 30
const CLAMP_TIP_X := 48     ## contact point inside the clamp sprite
const CLAMP_TIP_Y := 15
const STUB_CELL_W := 26
const STUB_CELL_H := 14
const SPARK_CELL := 30
const FLAME_CELL_W := 16
const FLAME_CELL_H := 18

const SCALE := 3.0          ## integer upscale so pixels stay crisp

# --------------------------------------------------------------- palette -----
const C_OUTLINE := Color("#272736")
const C_PLATE := Color("#57294B")
const C_PLATE_DK := Color("#322947")
const C_MAROON := Color("#8C3F5D")
const C_RUST := Color("#BA6156")
const C_RED := Color("#E36956")
const C_ORANGE := Color("#F2A65E")
const C_ORANGE_LT := Color("#FFB570")
const C_CREAM := Color("#FFFFEB")
const C_GOLD := Color("#FFE478")
const C_GREEN := Color("#3CA370")
const C_GREY := Color("#7E7E8F")
const C_GREY_LT := Color("#C2C2D1")

## Wire colours — order MUST match the WIRES table in gen_art.py.
const WIRE_NAMES := ["RED", "BLUE", "YELLOW", "GREEN", "WHITE", "PINK"]
const WIRE_COLORS := [
	Color("#E36956"), Color("#4DA6FF"), Color("#FFE478"),
	Color("#3CA370"), Color("#C2C2D1"), Color("#B0305C"),
]

# ------------------------------------------------------------ difficulty -----
enum Difficulty { EASY, MEDIUM, HARD }

## wires      : how many wires must be landed
## terminals  : posts on the rail (extra posts are decoys)
## speed      : clamp sweep speed, board px / sec
## tol        : clamp tolerance, board px from terminal centre
## fuse       : seconds on the clock
## strikes    : wrong clamps allowed before the board dies
## loose      : per-connection chance a good clamp comes up LOOSE (redo it)
## surge      : per-second chance of a speed surge
const CONFIG := [
	{
		"name": "EASY", "blurb": "Slow sweep, fat window, 3 wires.",
		"wires": 3, "terminals": 4, "speed": 60.0, "tol": 12.0,
		"fuse": 34.0, "strikes": 3, "loose": 0.05, "surge": 0.00,
	},
	{
		"name": "MEDIUM", "blurb": "Quicker sweep, 4 wires, loose contacts.",
		"wires": 4, "terminals": 5, "speed": 100.0, "tol": 8.0,
		"fuse": 28.0, "strikes": 2, "loose": 0.13, "surge": 0.10,
	},
	{
		"name": "HARD", "blurb": "Fast sweep, 5 wires, surges + bad contacts.",
		"wires": 5, "terminals": 6, "speed": 130.0, "tol": 6.0,
		"fuse": 22.0, "strikes": 2, "loose": 0.22, "surge": 0.22,
	},
]

## A run is flagged CLEAN with zero strikes and at most this many loose contacts.
## Purely informational today — reported in the result for later balancing.
const CLEAN_MAX_LOOSE := 1

## Ignore keys for this many frames after the popup opens (see _input_gate_frame).
const INPUT_GATE_FRAMES := 12

const SURGE_MULT := 2.1
const SURGE_SEC := 0.65
## Fuse seconds burned by a mistake.
const PENALTY_STRIKE_SEC := 3.0
const PENALTY_LOOSE_SEC := 1.5

# --------------------------------------------------------------- runtime -----
var _built := false
var _pixel_font: Font

var _tex_board: Texture2D
var _tex_terminals: Texture2D
var _tex_clamp: Texture2D
var _tex_stub: Texture2D
var _tex_spark: Texture2D
var _tex_flame: Texture2D
var _tex_bomb: Texture2D

# UI nodes
var _picker: Control
var _picker_rows: Array = []
var _picker_index := 1
var _game_root: Control
var _stage: Control
var _board_rect: TextureRect
var _clamp_rect: TextureRect
var _title_label: Label
var _diff_label: Label
var _holding_rect: TextureRect
var _holding_name: Label
var _queue_row: HBoxContainer
var _strike_row: HBoxContainer
var _fuse_fill: ColorRect
var _fuse_flame: TextureRect
var _fuse_label: Label
var _call_label: Label
var _hint_label: Label
var _flash: ColorRect

# Round state
var _cfg: Dictionary = {}
var _difficulty := Difficulty.MEDIUM
var _term_colors: Array = []      ## colour index per terminal, top -> bottom
var _term_nodes: Array = []       ## TextureRect per terminal
var _term_y: Array = []           ## board-space centre y per terminal
var _term_done: Array = []        ## bool per terminal
var _queue: Array = []            ## colour indices still to land
var _clamp_y := RAIL_TOP
var _clamp_dir := 1.0
var _speed := 100.0
var _surge_left := 0.0
var _fuse_left := 0.0
var _fuse_total := 0.0
var _strikes := 0
var _loose_count := 0
var _flame_t := 0.0
var _running := false
var _clamp_requested := false
var _abort_requested := false
var _picker_confirm := 0          ## 0 = pending, 1 = start, -1 = cancel
## Keys are ignored until this process frame — stops the E press that opened the
## minigame from also confirming the difficulty picker on the same frame.
var _input_gate_frame := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if ResourceLoader.exists("res://PressStart2P-Regular.ttf"):
		_pixel_font = load("res://PressStart2P-Regular.ttf")
	_load_art()
	_build_ui()


## Textures import normally when Godot scans the project; the raw-image fallback
## keeps the minigame alive on the very first launch after the files are dropped in.
func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var t := load(path) as Texture2D
		if t != null:
			return t
	var img := Image.new()
	if img.load(path) == OK:
		return ImageTexture.create_from_image(img)
	push_warning("[PipeBombMinigame] missing art: %s" % path)
	return null


func _load_art() -> void:
	_tex_board = _load_tex(BOARD_PNG)
	_tex_terminals = _load_tex(TERMINALS_PNG)
	_tex_clamp = _load_tex(CLAMP_PNG)
	_tex_stub = _load_tex(WIRESTUB_PNG)
	_tex_spark = _load_tex(SPARK_PNG)
	_tex_flame = _load_tex(FLAME_PNG)
	_tex_bomb = _load_tex(BOMB_ICON_PNG)


func _atlas(tex: Texture2D, index: int, cell_w: int, cell_h: int) -> Texture2D:
	if tex == null:
		return null
	var a := AtlasTexture.new()
	a.atlas = tex
	a.region = Rect2(index * cell_w, 0, cell_w, cell_h)
	a.filter_clip = true
	return a


func _make_pixel_rect(tex: Texture2D, scale: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex != null:
		var s := tex.get_size() * scale
		r.custom_minimum_size = s
		r.size = s
	return r


func _style_label(lab: Label, size: int, color: Color) -> void:
	if _pixel_font:
		lab.add_theme_font_override("font", _pixel_font)
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", color)


func _panel(margin: int = 10, border: Color = C_GOLD) -> PanelContainer:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.06, 0.08, 0.94)
	st.border_color = border
	st.set_border_width_all(2)
	st.set_corner_radius_all(6)
	st.set_content_margin_all(margin)
	p.add_theme_stylebox_override("panel", st)
	return p


# ---------------------------------------------------------------- build ------
func _build_ui() -> void:
	if _built:
		return
	_built = true

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var outer := PanelContainer.new()
	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = C_PLATE
	outer_style.border_color = C_OUTLINE
	outer_style.set_border_width_all(3)
	outer_style.set_corner_radius_all(8)
	outer_style.set_content_margin_all(6)
	outer.add_theme_stylebox_override("panel", outer_style)
	center.add_child(outer)

	var body := _panel(10)
	outer.add_child(body)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	body.add_child(col)

	# ---- header ---------------------------------------------------------
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(header)
	if _tex_bomb:
		header.add_child(_make_pixel_rect(_tex_bomb, 1.6))
	_title_label = Label.new()
	_title_label.text = "PIPE BOMB  —  DETONATOR WIRING"
	_style_label(_title_label, 13, C_GOLD)
	header.add_child(_title_label)
	_diff_label = Label.new()
	_diff_label.text = ""
	_style_label(_diff_label, 10, C_ORANGE_LT)
	header.add_child(_diff_label)

	# ---- game row (left readout + board stage) --------------------------
	_game_root = VBoxContainer.new()
	_game_root.add_theme_constant_override("separation", 8)
	col.add_child(_game_root)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_game_root.add_child(row)

	row.add_child(_build_readout_panel())

	var stage_panel := _panel(6, C_MAROON)
	row.add_child(stage_panel)
	_stage = Control.new()
	_stage.custom_minimum_size = Vector2(BOARD_W, BOARD_H) * SCALE
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.clip_contents = true
	stage_panel.add_child(_stage)

	_board_rect = _make_pixel_rect(_tex_board, SCALE)
	_board_rect.position = Vector2.ZERO
	_stage.add_child(_board_rect)

	_clamp_rect = _make_pixel_rect(_atlas(_tex_clamp, 0, CLAMP_CELL_W, CLAMP_CELL_H), SCALE)
	_stage.add_child(_clamp_rect)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_flash)

	_call_label = Label.new()
	_call_label.text = ""
	_call_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_call_label.custom_minimum_size = Vector2(BOARD_W * SCALE, 0)
	_style_label(_call_label, 16, C_CREAM)
	_call_label.add_theme_color_override("font_outline_color", C_OUTLINE)
	_call_label.add_theme_constant_override("outline_size", 8)
	_call_label.position = Vector2(0, BOARD_H * SCALE * 0.36)
	_call_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_call_label)

	_hint_label = Label.new()
	_hint_label.text = "SPACE / E = CLAMP     ESC = BACK OUT"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(_hint_label, 8, Color(0.85, 0.80, 0.72, 0.9))
	_game_root.add_child(_hint_label)

	# ---- difficulty picker (overlays the game row) ----------------------
	_build_picker(col)


func _build_readout_panel() -> Control:
	var p := _panel(10, C_MAROON)
	p.custom_minimum_size = Vector2(212, BOARD_H * SCALE)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)

	var h1 := Label.new()
	h1.text = "HOLDING"
	_style_label(h1, 9, C_GOLD)
	v.add_child(h1)

	var hold_box := CenterContainer.new()
	hold_box.custom_minimum_size = Vector2(0, STUB_CELL_H * 3)
	v.add_child(hold_box)
	_holding_rect = _make_pixel_rect(_atlas(_tex_stub, 0, STUB_CELL_W, STUB_CELL_H), 3.0)
	hold_box.add_child(_holding_rect)

	_holding_name = Label.new()
	_holding_name.text = "—"
	_holding_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(_holding_name, 14, C_CREAM)
	v.add_child(_holding_name)

	v.add_child(_divider())

	var h2 := Label.new()
	h2.text = "STILL TO WIRE"
	_style_label(h2, 8, C_GOLD)
	v.add_child(h2)
	_queue_row = HBoxContainer.new()
	_queue_row.add_theme_constant_override("separation", 3)
	_queue_row.custom_minimum_size = Vector2(0, STUB_CELL_H * 2 + 4)
	v.add_child(_queue_row)

	v.add_child(_divider())

	var h3 := Label.new()
	h3.text = "FUSE"
	_style_label(h3, 8, C_GOLD)
	v.add_child(h3)

	var fuse_holder := Control.new()
	fuse_holder.custom_minimum_size = Vector2(188, 26)
	v.add_child(fuse_holder)

	var fuse_bg := ColorRect.new()
	fuse_bg.color = C_PLATE_DK
	fuse_bg.position = Vector2(0, 7)
	fuse_bg.size = Vector2(188, 12)
	fuse_holder.add_child(fuse_bg)

	_fuse_fill = ColorRect.new()
	_fuse_fill.color = C_ORANGE
	_fuse_fill.position = Vector2(0, 7)
	_fuse_fill.size = Vector2(188, 12)
	fuse_holder.add_child(_fuse_fill)

	_fuse_flame = _make_pixel_rect(_atlas(_tex_flame, 0, FLAME_CELL_W, FLAME_CELL_H), 1.5)
	fuse_holder.add_child(_fuse_flame)

	_fuse_label = Label.new()
	_fuse_label.text = "0.0s"
	_fuse_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(_fuse_label, 11, C_ORANGE_LT)
	v.add_child(_fuse_label)

	v.add_child(_divider())

	var h4 := Label.new()
	h4.text = "STRIKES"
	_style_label(h4, 8, C_GOLD)
	v.add_child(h4)
	_strike_row = HBoxContainer.new()
	_strike_row.add_theme_constant_override("separation", 6)
	v.add_child(_strike_row)

	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grow)

	var note := Label.new()
	note.text = "Match the wire to the post\nof the SAME colour."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(188, 0)
	_style_label(note, 7, Color(0.86, 0.82, 0.74, 0.92))
	v.add_child(note)
	return p


func _divider() -> Control:
	var d := ColorRect.new()
	d.color = C_MAROON
	d.custom_minimum_size = Vector2(0, 2)
	return d


func _build_picker(parent: Control) -> void:
	_picker = VBoxContainer.new()
	_picker.add_theme_constant_override("separation", 8)
	parent.add_child(_picker)

	var lead := Label.new()
	lead.text = "How careful do you want to be?"
	lead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(lead, 11, C_CREAM)
	_picker.add_child(lead)

	_picker_rows.clear()
	for i in CONFIG.size():
		var cfg: Dictionary = CONFIG[i]
		var p := _panel(10, C_MAROON)
		p.custom_minimum_size = Vector2(520, 0)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		p.add_child(hb)

		var caret := Label.new()
		caret.text = ">"
		caret.custom_minimum_size = Vector2(20, 0)
		_style_label(caret, 14, C_GOLD)
		hb.add_child(caret)

		var name_lab := Label.new()
		name_lab.text = String(cfg["name"])
		name_lab.custom_minimum_size = Vector2(110, 0)
		_style_label(name_lab, 13, C_GOLD)
		hb.add_child(name_lab)

		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 3)
		hb.add_child(vb)
		var blurb := Label.new()
		blurb.text = String(cfg["blurb"])
		_style_label(blurb, 8, C_CREAM)
		vb.add_child(blurb)
		var stats := Label.new()
		stats.text = "%d WIRES   %d POSTS   %ds FUSE   %d STRIKES" % [
			int(cfg["wires"]), int(cfg["terminals"]),
			int(cfg["fuse"]), int(cfg["strikes"]),
		]
		_style_label(stats, 8, C_ORANGE_LT)
		vb.add_child(stats)

		_picker.add_child(p)
		_picker_rows.append({"panel": p, "caret": caret, "name": name_lab, "blurb": blurb, "stats": stats})

	var foot := Label.new()
	foot.text = "W / S  choose      SPACE / E  start      ESC  cancel"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(foot, 8, Color(0.85, 0.80, 0.72, 0.9))
	_picker.add_child(foot)


func _refresh_picker() -> void:
	for i in _picker_rows.size():
		var row: Dictionary = _picker_rows[i]
		var sel: bool = (i == _picker_index)
		var p: PanelContainer = row["panel"]
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.16, 0.09, 0.12, 0.98) if sel else Color(0.08, 0.06, 0.08, 0.94)
		st.border_color = C_GOLD if sel else C_MAROON
		st.set_border_width_all(3 if sel else 2)
		st.set_corner_radius_all(6)
		st.set_content_margin_all(10)
		p.add_theme_stylebox_override("panel", st)
		(row["caret"] as Label).modulate.a = 1.0 if sel else 0.0
		(row["name"] as Label).add_theme_color_override("font_color", C_CREAM if sel else C_GOLD)


# ----------------------------------------------------------------- input -----
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if Engine.get_process_frames() < _input_gate_frame:
		get_viewport().set_input_as_handled()
		return
	var k: int = (event as InputEventKey).keycode
	var confirm := (k == KEY_SPACE or k == KEY_E or k == KEY_ENTER or k == KEY_KP_ENTER)

	if _picker != null and _picker.visible:
		if k == KEY_W or k == KEY_UP:
			_picker_index = wrapi(_picker_index - 1, 0, CONFIG.size())
			_refresh_picker()
		elif k == KEY_S or k == KEY_DOWN:
			_picker_index = wrapi(_picker_index + 1, 0, CONFIG.size())
			_refresh_picker()
		elif k == KEY_1 or k == KEY_2 or k == KEY_3:
			_picker_index = k - KEY_1
			_refresh_picker()
			_picker_confirm = 1
		elif confirm:
			_picker_confirm = 1
		elif k == KEY_ESCAPE:
			_picker_confirm = -1
		get_viewport().set_input_as_handled()
		return

	if _running:
		if confirm:
			_clamp_requested = true
		elif k == KEY_ESCAPE:
			_abort_requested = true
	get_viewport().set_input_as_handled()


# ------------------------------------------------------------ public API -----
## Runs the whole minigame and returns the result dictionary.
func show_and_play(forced_difficulty: int = -1) -> Dictionary:
	if not _built:
		_load_art()
		_build_ui()

	visible = true
	_input_gate_frame = Engine.get_process_frames() + INPUT_GATE_FRAMES
	_call_label.text = ""
	_flash.color = Color(1, 1, 1, 0)

	# --- difficulty pick -------------------------------------------------
	var chosen := forced_difficulty
	if chosen < 0 or chosen >= CONFIG.size():
		_game_root.visible = false
		_picker.visible = true
		_picker_index = clampi(_picker_index, 0, CONFIG.size() - 1)
		_picker_confirm = 0
		_refresh_picker()
		while _picker_confirm == 0:
			await get_tree().process_frame
		if _picker_confirm < 0:
			_picker.visible = false
			visible = false
			var cancelled := {"outcome": "cancel", "difficulty": -1, "difficulty_name": "",
				"clean": false, "strikes": 0, "loose": 0, "time_left": 0.0}
			minigame_finished.emit(cancelled)
			return cancelled
		chosen = _picker_index
	_picker.visible = false
	_game_root.visible = true
	_input_gate_frame = Engine.get_process_frames() + INPUT_GATE_FRAMES

	_setup_round(chosen)

	# --- brief arm-up so the board is readable before it moves ------------
	_call_label.text = "READY"
	_hint_label.text = "SPACE / E = CLAMP     ESC = BACK OUT"
	await get_tree().create_timer(0.9).timeout
	_call_label.text = ""

	var outcome: String = await _run_loop()
	var was_clean: bool = (_strikes == 0 and _loose_count <= CLEAN_MAX_LOOSE)

	# --- verdict ----------------------------------------------------------
	if outcome == "success":
		_call_label.add_theme_color_override("font_color", C_GREEN)
		_call_label.text = "CIRCUIT LIVE"
		_hint_label.text = "Pipe bomb armed."
	elif outcome == "cancel":
		_call_label.add_theme_color_override("font_color", C_GREY_LT)
		_call_label.text = "BACKED OUT"
		_hint_label.text = "Pipe bomb back in the bag."
	else:
		_call_label.add_theme_color_override("font_color", C_RED)
		_call_label.text = "WIRING FAILED"
		_hint_label.text = "Pipe bomb wasted."

	await get_tree().create_timer(1.5 if outcome != "cancel" else 0.7).timeout
	visible = false
	_call_label.add_theme_color_override("font_color", C_CREAM)

	var result := {
		"outcome": outcome,
		"difficulty": _difficulty,
		"difficulty_name": String(_cfg.get("name", "")),
		"clean": was_clean,
		"strikes": _strikes,
		"loose": _loose_count,
		"time_left": maxf(_fuse_left, 0.0),
	}
	minigame_finished.emit(result)
	return result


func hide_popup() -> void:
	_running = false
	visible = false


# ------------------------------------------------------------ round setup ----
func _setup_round(difficulty: int) -> void:
	_difficulty = difficulty
	_cfg = CONFIG[difficulty]
	_diff_label.text = "[%s]" % String(_cfg["name"])

	var n_wires: int = int(_cfg["wires"])
	var n_terms: int = int(_cfg["terminals"])

	# Colours that must be landed, plus decoy posts drawn from what's left over.
	var pool: Array = range(WIRE_COLORS.size())
	pool.shuffle()
	var live: Array = pool.slice(0, n_wires)
	var decoys: Array = pool.slice(n_wires, n_terms)

	_queue = live.duplicate()
	_queue.shuffle()

	_term_colors = live + decoys
	_term_colors.shuffle()          # luck: post order is different every attempt

	_strikes = 0
	_loose_count = 0
	_surge_left = 0.0
	_speed = float(_cfg["speed"])
	_clamp_dir = 1.0
	_clamp_y = RAIL_TOP
	# Luck: the fuse is never quite the same length twice.
	_fuse_total = float(_cfg["fuse"]) * randf_range(0.88, 1.12)
	_fuse_left = _fuse_total
	_clamp_requested = false
	_abort_requested = false

	_build_terminals()
	_refresh_queue_ui()
	_refresh_strikes_ui()
	_refresh_fuse_ui()
	_update_clamp_sprite()
	_position_clamp()


func _build_terminals() -> void:
	for n in _term_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_term_nodes.clear()
	_term_y.clear()
	_term_done.clear()

	var n: int = _term_colors.size()
	var span: float = RAIL_BOT - RAIL_TOP
	for i in n:
		var cy: float = RAIL_TOP + span * (float(i) + 0.5) / float(n)
		_term_y.append(cy)
		_term_done.append(false)
		var color_idx: int = int(_term_colors[i])
		var rect := _make_pixel_rect(_atlas(_tex_terminals, color_idx * 2, TERM_CELL, TERM_CELL), SCALE)
		rect.position = Vector2(RAIL_CX - TERM_CELL * 0.5, cy - TERM_CELL * 0.5) * SCALE
		_stage.add_child(rect)
		_stage.move_child(rect, 1)   # above board, under clamp
		_term_nodes.append(rect)


func _set_terminal_lit(index: int, lit: bool) -> void:
	if index < 0 or index >= _term_nodes.size():
		return
	var rect: TextureRect = _term_nodes[index]
	if not is_instance_valid(rect):
		return
	var color_idx: int = int(_term_colors[index])
	rect.texture = _atlas(_tex_terminals, color_idx * 2 + (1 if lit else 0), TERM_CELL, TERM_CELL)


func _current_color() -> int:
	if _queue.is_empty():
		return -1
	return int(_queue[0])


func _update_clamp_sprite() -> void:
	var ci: int = _current_color()
	if ci < 0:
		_clamp_rect.visible = false
		return
	_clamp_rect.visible = true
	_holding_rect.visible = true
	_clamp_rect.texture = _atlas(_tex_clamp, ci, CLAMP_CELL_W, CLAMP_CELL_H)
	_holding_rect.texture = _atlas(_tex_stub, ci, STUB_CELL_W, STUB_CELL_H)
	_holding_name.text = String(WIRE_NAMES[ci])
	_holding_name.add_theme_color_override("font_color", WIRE_COLORS[ci])


func _position_clamp() -> void:
	# Land the clamp tip just left of the terminal collar.
	var tip_x: float = RAIL_CX - 13.0
	_clamp_rect.position = Vector2(tip_x - CLAMP_TIP_X, _clamp_y - CLAMP_TIP_Y) * SCALE


# ------------------------------------------------------------------- HUD -----
func _refresh_queue_ui() -> void:
	for c in _queue_row.get_children():
		c.queue_free()
	for i in range(1, _queue.size()):
		var ci: int = int(_queue[i])
		var r := _make_pixel_rect(_atlas(_tex_stub, ci, STUB_CELL_W, STUB_CELL_H), 1.6)
		_queue_row.add_child(r)
	if _queue.size() <= 1:
		var lab := Label.new()
		lab.text = "LAST ONE" if _queue.size() == 1 else "—"
		_style_label(lab, 8, C_GREEN if _queue.size() == 1 else C_GREY)
		_queue_row.add_child(lab)


func _refresh_strikes_ui() -> void:
	for c in _strike_row.get_children():
		c.queue_free()
	var maxs: int = int(_cfg.get("strikes", 2))
	for i in maxs:
		var d := ColorRect.new()
		d.custom_minimum_size = Vector2(16, 16)
		d.color = C_RED if i < _strikes else C_PLATE_DK
		_strike_row.add_child(d)


func _refresh_fuse_ui() -> void:
	var frac: float = clampf(_fuse_left / maxf(_fuse_total, 0.001), 0.0, 1.0)
	var w: float = 188.0 * frac
	_fuse_fill.size = Vector2(w, 12)
	_fuse_fill.color = C_ORANGE if frac > 0.35 else C_RED
	if _fuse_flame:
		_fuse_flame.position = Vector2(w - 12.0, 0.0)
		_fuse_flame.visible = frac > 0.01
		var f: int = int(_flame_t * 12.0) % 4
		_fuse_flame.texture = _atlas(_tex_flame, f, FLAME_CELL_W, FLAME_CELL_H)
	_fuse_label.text = "%0.1fs" % maxf(_fuse_left, 0.0)
	_fuse_label.add_theme_color_override("font_color", C_ORANGE_LT if frac > 0.35 else C_RED)


# ------------------------------------------------------------- main loop -----
func _run_loop() -> String:
	_running = true

	while _running:
		await get_tree().process_frame
		var dt: float = get_process_delta_time()
		if dt <= 0.0:
			dt = 1.0 / 60.0
		dt = minf(dt, 0.05)
		_flame_t += dt

		if _abort_requested:
			_running = false
			return "cancel"

		# --- fuse ---------------------------------------------------------
		_fuse_left -= dt
		_refresh_fuse_ui()
		if _fuse_left <= 0.0:
			_running = false
			await _boom_feedback("OUT OF TIME")
			return "failed"

		# --- surges (luck) -------------------------------------------------
		var surge_chance: float = float(_cfg.get("surge", 0.0))
		if _surge_left > 0.0:
			_surge_left -= dt
			if _surge_left <= 0.0:
				_flash.color = Color(1, 1, 1, 0)
		elif surge_chance > 0.0 and randf() < surge_chance * dt:
			_surge_left = SURGE_SEC
			_flash.color = Color(1.0, 0.9, 0.4, 0.16)
			_clamp_dir *= -1.0 if randf() < 0.4 else 1.0

		# --- clamp sweep ----------------------------------------------------
		var spd: float = _speed * (SURGE_MULT if _surge_left > 0.0 else 1.0)
		_clamp_y += _clamp_dir * spd * dt
		if _clamp_y >= RAIL_BOT:
			_clamp_y = RAIL_BOT - (_clamp_y - RAIL_BOT)
			_clamp_dir = -1.0
		elif _clamp_y <= RAIL_TOP:
			_clamp_y = RAIL_TOP + (RAIL_TOP - _clamp_y)
			_clamp_dir = 1.0
		_clamp_y = clampf(_clamp_y, RAIL_TOP, RAIL_BOT)
		_position_clamp()

		# --- clamp attempt --------------------------------------------------
		if _clamp_requested:
			_clamp_requested = false
			var verdict: String = await _resolve_clamp()
			if verdict == "done":
				_running = false
				await _success_feedback()
				return "success"
			if verdict == "dead":
				_running = false
				await _boom_feedback("BOARD FRIED")
				return "failed"

	return "failed"


## Returns "" (continue), "done" (all wires landed) or "dead" (out of strikes).
func _resolve_clamp() -> String:
	var ci: int = _current_color()
	if ci < 0:
		return "done"

	var tol: float = float(_cfg["tol"])
	var best := -1
	var best_d: float = 1e9
	for i in _term_y.size():
		var d: float = absf(float(_term_y[i]) - _clamp_y)
		if d < best_d:
			best_d = d
			best = i

	var on_target: bool = best >= 0 and best_d <= tol
	var right_color: bool = on_target and int(_term_colors[best]) == ci and not bool(_term_done[best])

	if not on_target:
		await _strike("MISSED THE POST", _clamp_y)
		return "dead" if _strikes >= int(_cfg["strikes"]) else ""

	if not right_color:
		var why := "ALREADY WIRED" if bool(_term_done[best]) else "WRONG POST"
		await _strike(why, float(_term_y[best]))
		return "dead" if _strikes >= int(_cfg["strikes"]) else ""

	# --- good clamp; now the luck roll on contact quality -----------------
	if randf() < float(_cfg["loose"]):
		_loose_count += 1
		_fuse_left = maxf(_fuse_left - PENALTY_LOOSE_SEC, 0.0)
		await _spark_at(float(_term_y[best]), "LOOSE CONTACT")
		_refresh_fuse_ui()
		return ""

	_term_done[best] = true
	_set_terminal_lit(best, true)
	_queue.remove_at(0)
	_refresh_queue_ui()
	await _spark_at(float(_term_y[best]), "CONTACT", C_GREEN)
	if _queue.is_empty():
		_holding_rect.visible = false
		_holding_name.text = "ALL WIRED"
		_holding_name.add_theme_color_override("font_color", C_GREEN)
		return "done"
	_update_clamp_sprite()
	return ""


func _strike(reason: String, at_y: float) -> void:
	_strikes += 1
	_fuse_left = maxf(_fuse_left - PENALTY_STRIKE_SEC, 0.0)
	_refresh_strikes_ui()
	_refresh_fuse_ui()
	await _spark_at(at_y, reason, C_RED)


func _spark_at(board_y: float, text: String, color: Color = C_GOLD) -> void:
	_call_label.add_theme_color_override("font_color", color)
	_call_label.text = text

	var spark := _make_pixel_rect(_atlas(_tex_spark, 0, SPARK_CELL, SPARK_CELL), SCALE)
	spark.position = Vector2(RAIL_CX - SPARK_CELL * 0.5, board_y - SPARK_CELL * 0.5) * SCALE
	_stage.add_child(spark)

	for f in 5:
		if not is_instance_valid(spark):
			break
		spark.texture = _atlas(_tex_spark, f, SPARK_CELL, SPARK_CELL)
		await get_tree().create_timer(0.045).timeout
	if is_instance_valid(spark):
		spark.queue_free()

	await get_tree().create_timer(0.12).timeout
	if _call_label.text == text:
		_call_label.text = ""
	_call_label.add_theme_color_override("font_color", C_CREAM)


func _success_feedback() -> void:
	_flash.color = Color(0.4, 1.0, 0.6, 0.20)
	for i in _term_nodes.size():
		if bool(_term_done[i]):
			_set_terminal_lit(i, true)
	_clamp_rect.visible = false
	await get_tree().create_timer(0.35).timeout
	_flash.color = Color(1, 1, 1, 0)


func _boom_feedback(reason: String) -> void:
	_call_label.add_theme_color_override("font_color", C_RED)
	_call_label.text = reason
	_clamp_rect.visible = false
	for i in 3:
		_flash.color = Color(1.0, 0.35, 0.3, 0.34)
		await get_tree().create_timer(0.07).timeout
		_flash.color = Color(1, 1, 1, 0)
		await get_tree().create_timer(0.06).timeout
	await get_tree().create_timer(0.35).timeout
	_call_label.add_theme_color_override("font_color", C_CREAM)
