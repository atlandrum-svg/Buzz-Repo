extends Control
## Dev tools panel — right side, F3 to toggle.
##
## Two jobs:
##   1. OVERRIDES. Every random or conditional branch in the end-of-round
##      encounter can be pinned to a specific outcome, so you can walk any path
##      on demand instead of re-rolling until it happens. Anything left on
##      "Auto" behaves exactly as it does in a real game.
##   2. SETUP. One-click state: hand yourself items, move anxiety, trap or
##      untrap every prop, feed/arm/possess the lizard, jump straight to the
##      end of the round.
##
## Nothing here is consulted unless an override is set away from Auto, so this
## file is safe to leave in. Flip ENABLED to false (or delete the node) to ship.
##
## Read by turn_manager via get_override(); it never reaches into game state
## on its own except through TurnManager's public API.

const ENABLED := true
const TOGGLE_KEY := KEY_F3

const HUD_BORDER := Color(0.95, 0.78, 0.28, 0.95)
const HUD_TEXT := Color(1.0, 0.92, 0.55, 1.0)
const DEV_ACCENT := Color(0.42, 0.82, 0.95, 1.0)
const PANEL_W := 246.0

## Pinned outcomes. "auto" = let the game decide.
##   arrival : auto | fireman | police | landlord
##   action  : auto | win | fail
##   demon   : auto | murder | possess_person | possess_lizard | nothing
##   lizard  : auto | lizard_murder | nothing
##   gunwave : auto | bravado | murder
var overrides: Dictionary = {
	"arrival": "auto",
	"action": "auto",
	"demon": "auto",
	"lizard": "auto",
	"gunwave": "auto",
}

var _tm: Node = null
var _font: Font = null
var _body: VBoxContainer
var _readout: Label
var _rows: Dictionary = {} ## key -> {value: Array[Button]}
var _refresh_t: float = 0.0


func setup(turn_manager: Node, pixel_font: Font) -> void:
	_tm = turn_manager
	_font = pixel_font
	_build()
	visible = false
	set_process(true)
	set_process_unhandled_input(true)
	print("[DEV] panel ready — press F3")


func get_override(key: String) -> String:
	return String(overrides.get(key, "auto"))


func _unhandled_input(event: InputEvent) -> void:
	if not ENABLED:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == TOGGLE_KEY:
		visible = not visible
		if visible:
			_refresh_readout()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_t += delta
	if _refresh_t < 0.25:
		return
	_refresh_t = 0.0
	_refresh_readout()


## ============================================================================
## UI
## ============================================================================

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -(PANEL_W + 12.0)
	offset_right = -12.0
	offset_top = 12.0
	offset_bottom = -12.0
	mouse_filter = Control.MOUSE_FILTER_PASS

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.07, 0.10, 0.95)
	st.border_color = DEV_ACCENT.darkened(0.25)
	st.set_border_width_all(2)
	st.set_corner_radius_all(6)
	st.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", st)
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	_body.custom_minimum_size = Vector2(PANEL_W - 34.0, 0)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)

	var title := Label.new()
	title.text = "DEV TOOLS  (F3)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(title, 10, DEV_ACCENT)
	_body.add_child(title)

	_readout = Label.new()
	_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_readout.custom_minimum_size = Vector2(PANEL_W - 44.0, 0)
	_style(_readout, 7, Color(0.85, 0.90, 0.95, 1.0))
	_body.add_child(_readout)

	# --- overrides ---
	_header("FORCE OUTCOMES")
	_choice_row("arrival", "Arrival", [
		["auto", "Auto"], ["fireman", "Fire"], ["police", "Cop"], ["landlord", "Lord"],
	])
	_choice_row("action", "Action roll", [
		["auto", "Auto"], ["win", "Win"], ["fail", "Fail"],
	])
	_choice_row("demon", "Demon wheel", [
		["auto", "Auto"], ["murder", "Murder"], ["possess_person", "Poss NPC"],
		["possess_lizard", "Poss Liz"], ["nothing", "Nothing"],
	])
	_choice_row("lizard", "Lizard wheel", [
		["auto", "Auto"], ["lizard_murder", "Murder"], ["nothing", "Nothing"],
	])
	_choice_row("gunwave", "Gun wave", [
		["auto", "Auto"], ["bravado", "Back off"], ["murder", "Goes off"],
	])

	# --- setup ---
	_header("ANXIETY")
	_button_grid([
		["-10", func(): _nudge_anxiety(-10)],
		["-5", func(): _nudge_anxiety(-5)],
		["+5", func(): _nudge_anxiety(5)],
		["+10", func(): _nudge_anxiety(10)],
		["Reset", func(): _call_tm("cheat_reset_anxiety")],
	])

	_header("GIVE ITEMS")
	_button_grid([
		["Gun", func(): _call_tm("add_inventory_gun")],
		["Pills", func(): _call_tm("add_inventory_pill", [false])],
		["Bad pills", func(): _call_tm("add_inventory_pill", [true])],
		["Fanny pack", func(): _call_tm("add_inventory_fannypack")],
	])

	_header("PROPS")
	_button_grid([
		["Trap all", func(): _set_all_traps(true)],
		["Untrap all", func(): _set_all_traps(false)],
	])
	# The realistic setup: jump to P2 blind. Deliberately reveals nothing.
	_button_grid([
		["START P2 — 3 RANDOM TRAPS", func(): _call_tm("dev_start_p2_with_random_traps", [3])],
	])

	_header("LIZARD")
	_button_grid([
		["Clean pills", func(): _lizard_call("give_pills", [false])],
		["Bad pills", func(): _lizard_call("give_pills", [true])],
		["Give gun", func(): _lizard_call("give_gun")],
		["Possess", func(): _possess_lizard()],
	])

	_header("JUMP TO")
	_button_grid([
		["Spawn arrival", func(): _spawn_arrival()],
		["Run encounter", func(): _run_encounter()],
		["End round", func(): _call_tm("begin_end_of_round_evaluation")],
		["P2 free roam", func(): _call_tm("cheat_p2_eval_roam")],
	])


func _header(text: String) -> void:
	var sep := HSeparator.new()
	_body.add_child(sep)
	var l := Label.new()
	l.text = text
	_style(l, 8, HUD_TEXT)
	_body.add_child(l)


## A label plus a wrapped row of mutually exclusive buttons; the active one lights up.
func _choice_row(key: String, label: String, options: Array) -> void:
	var l := Label.new()
	l.text = label
	_style(l, 7, Color(0.75, 0.80, 0.86, 1.0))
	_body.add_child(l)

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 3)
	flow.add_theme_constant_override("v_separation", 3)
	_body.add_child(flow)

	var buttons: Array = []
	for o in options:
		var value: String = String(o[0])
		var btn := _small_button(String(o[1]))
		btn.pressed.connect(func(): _set_override(key, value))
		flow.add_child(btn)
		buttons.append({"value": value, "button": btn})
	_rows[key] = buttons
	_paint_row(key)


func _set_override(key: String, value: String) -> void:
	overrides[key] = value
	_paint_row(key)
	print("[DEV] %s = %s" % [key, value])


func _paint_row(key: String) -> void:
	var active: String = get_override(key)
	for entry in _rows.get(key, []):
		var btn: Button = entry["button"]
		var on: bool = String(entry["value"]) == active
		btn.add_theme_stylebox_override("normal", _btn_style(on, false))
		btn.add_theme_stylebox_override("hover", _btn_style(on, true))
		btn.add_theme_color_override("font_color", Color(0.06, 0.09, 0.12, 1.0) if on else HUD_TEXT)


func _button_grid(items: Array) -> void:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 3)
	flow.add_theme_constant_override("v_separation", 3)
	_body.add_child(flow)
	for it in items:
		var btn := _small_button(String(it[0]))
		btn.pressed.connect(it[1])
		flow.add_child(btn)


func _small_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 20)
	if _font:
		btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 7)
	btn.add_theme_color_override("font_color", HUD_TEXT)
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn.add_theme_stylebox_override("normal", _btn_style(false, false))
	btn.add_theme_stylebox_override("hover", _btn_style(false, true))
	btn.add_theme_stylebox_override("pressed", _btn_style(true, false))
	return btn


func _btn_style(active: bool, hover: bool) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	if active:
		st.bg_color = DEV_ACCENT
	elif hover:
		st.bg_color = Color(0.16, 0.22, 0.28, 1.0)
	else:
		st.bg_color = Color(0.09, 0.12, 0.16, 1.0)
	st.border_color = DEV_ACCENT.darkened(0.3)
	st.set_border_width_all(1)
	st.set_corner_radius_all(3)
	st.set_content_margin_all(4)
	return st


func _style(lab: Label, size: int, color: Color) -> void:
	if _font:
		lab.add_theme_font_override("font", _font)
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", color)


## ============================================================================
## Live state readout
## ============================================================================

func _refresh_readout() -> void:
	if _readout == null or _tm == null or not is_instance_valid(_tm):
		return
	var lines: PackedStringArray = []
	# str() not String() — String(null) throws if the property is missing.
	lines.append("turn %s" % str(_tm.get("current_turn")))
	if _tm.has_method("get_anxiety"):
		lines.append("anxiety %d/100" % int(_tm.call("get_anxiety")))
	lines.append("traps %s  uses %s" % [str(_tm.get("traps_left")), str(_tm.get("p2_items_used"))])
	var flags: PackedStringArray = []
	for pair in [
		["pipe_bomb_detonated", "bomb"], ["illegal_download", "cyber"],
		["p2_vishnu_active", "possessed"], ["p2_drowsy_active", "fent"],
		["p2_adhd_active", "adhd"], ["p2_murderer_active", "MURDERER"],
	]:
		if _tm_flag(String(pair[0])):
			flags.append(String(pair[1]))
	lines.append("flags: %s" % ("-" if flags.is_empty() else ", ".join(flags)))

	var liz := _lizard()
	if liz == null:
		lines.append("lizard: missing")
	else:
		var bits: PackedStringArray = []
		bits.append("alive" if _liz_bool(liz, "is_alive") else "dead")
		if _liz_bool(liz, "has_gun"):
			bits.append("gun")
		if _liz_bool(liz, "is_on_clean_pills"):
			bits.append("pills")
		if _liz_bool(liz, "is_demon_possessed"):
			bits.append("POSSESSED")
		if _liz_bool(liz, "is_in_fannypack"):
			bits.append("in pack")
		lines.append("lizard: %s" % ", ".join(bits))
	_readout.text = "\n".join(lines)


## bool(null) throws, so never hand a possibly-missing property straight to it.
func _tm_flag(prop: String) -> bool:
	var v: Variant = _tm.get(prop)
	return v != null and bool(v)


func _liz_bool(liz: Node, method: String) -> bool:
	return liz.has_method(method) and bool(liz.call(method))


## ============================================================================
## Actions
## ============================================================================

func _call_tm(method: String, args: Array = []) -> void:
	if _tm == null or not is_instance_valid(_tm) or not _tm.has_method(method):
		push_warning("[DEV] TurnManager missing %s" % method)
		return
	_tm.callv(method, args)


func _lizard() -> Node:
	return get_node_or_null("/root/Main/Roomate")


func _lizard_call(method: String, args: Array = []) -> void:
	var liz := _lizard()
	if liz == null or not liz.has_method(method):
		return
	liz.callv(method, args)


func _possess_lizard() -> void:
	var liz := _lizard()
	if liz == null or not liz.has_method("become_possessed"):
		return
	liz.call("become_possessed", get_node_or_null("/root/Main/Player2/Player2Body"))


## Anxiety has no raw setter by design (it is a sum of modifiers), so nudge it
## with a dedicated dev modifier rather than faking one of the real ones.
func _nudge_anxiety(amount: int) -> void:
	if _tm == null or not _tm.has_method("dev_nudge_anxiety"):
		return
	_tm.call("dev_nudge_anxiety", amount)


## Flip is_booby_trapped on every prop that has it.
func _set_all_traps(on: bool) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var n := 0
	for node in _walk(scene):
		if node.get("is_booby_trapped") != null:
			node.set("is_booby_trapped", on)
			n += 1
	print("[DEV] %s %d props" % ["trapped" if on else "untrapped", n])


func _walk(node: Node) -> Array:
	var out: Array = [node]
	for c in node.get_children():
		out.append_array(_walk(c))
	return out


func _arrival_choice() -> String:
	var pick: String = get_override("arrival")
	if pick != "auto":
		return pick
	if _tm_flag("illegal_download"):
		return "police"
	if _tm_flag("pipe_bomb_detonated"):
		return "fireman"
	return "landlord"


func _spawn_arrival() -> void:
	match _arrival_choice():
		"police":
			_call_tm("cheat_run_police_encounter_setup")
		"landlord":
			_call_tm("cheat_run_landlord_encounter_setup")
		_:
			_call_tm("cheat_spawn_fireman")


func _run_encounter() -> void:
	_spawn_arrival()
	_call_tm("run_fireman_encounter")
