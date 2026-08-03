extends Node
## Debug-only jump bookmarks + F1 menu + CLI launch.
## Instantiated only when OS.is_debug_build() — completely absent in release.

const DevBookmarks = preload("res://dev_bookmarks.gd")

const PROP_PATHS := {
	"plant": "/root/Main/Plant/PlantArea",
	"dresser": "/root/Main/DresserProp/DresserArea",
	"laptop": "/root/Main/LaptopCutOut/LaptopArea",
	"pill": "/root/Main/PillBottle/PillBottleArea",
}

var _tm: Node
var _menu: CanvasLayer
var _menu_open := false
var _status: Label
var _list: VBoxContainer
var _pending_bookmark: String = ""
var _capture_path: String = ""
var _quit_after_capture := false


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	_tm = get_parent()
	if _tm == null or not _tm.has_method("switch_turn"):
		_tm = get_node_or_null("/root/Main/TurnManager")
	_parse_cli()
	set_process_unhandled_input(true)
	call_deferred("_deferred_boot")


func _deferred_boot() -> void:
	# Wait a few frames so Area2D/prop scripts finish _ready.
	for i in 4:
		await get_tree().process_frame
	_build_menu()
	if not _pending_bookmark.is_empty():
		var ok: bool = await apply_bookmark(_pending_bookmark)
		print("[DEV] CLI bookmark=", _pending_bookmark, " ok=", ok)
		if ok and not _capture_path.is_empty():
			await _do_capture(_capture_path)
		if _quit_after_capture:
			get_tree().quit(0 if ok else 1)
	else:
		print("[DEV] Dev mode ready. F1 = debug menu. Bookmarks: ", DevBookmarks.names())


func _parse_cli() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	# Also scan full cmdline so --bookmark works if someone omits the second --
	var all_args: PackedStringArray = OS.get_cmdline_args()
	for a in all_args:
		if not args.has(a) and (a.begins_with("--bookmark") or a.begins_with("--dev-")):
			args.append(a)
	for a in args:
		if a.begins_with("--bookmark="):
			_pending_bookmark = a.substr("--bookmark=".length())
		elif a == "--bookmark" or a == "-b":
			pass  # next token handled below
		elif a.begins_with("--dev-capture="):
			_capture_path = a.substr("--dev-capture=".length())
			_quit_after_capture = true
		elif a == "--dev-quit" or a == "--dev-quit=1":
			_quit_after_capture = true
	# positional: --bookmark NAME
	for i in range(args.size()):
		if args[i] == "--bookmark" or args[i] == "-b":
			if i + 1 < args.size():
				_pending_bookmark = args[i + 1]


func apply_bookmark(name: String) -> bool:
	if not OS.is_debug_build():
		return false
	var bm: Dictionary = DevBookmarks.get_bookmark(name)
	if bm.is_empty():
		push_error("[DEV] Unknown bookmark: %s (known: %s)" % [name, ", ".join(DevBookmarks.names())])
		_set_status("Unknown bookmark: %s" % name)
		return false
	var main := get_node_or_null("/root/Main")
	if main == null:
		push_error("[DEV] /root/Main missing")
		return false
	var p1: Node = main.get_node_or_null("Player1/Player1Body")
	var p2: Node = main.get_node_or_null("Player2/Player2Body")
	if p1 == null or p2 == null:
		push_error("[DEV] players missing")
		return false

	# Game counters
	if _tm:
		_tm.traps_left = int(bm.get("traps_left", 3))
		_tm.p2_items_used = int(bm.get("p2_items_used", 0))
		_clear_inventory()
		var inv: Array = bm.get("inventory_pills", [])
		for trapped in inv:
			if _tm.has_method("add_inventory_pill"):
				_tm.add_inventory_pill(bool(trapped))

	# Prop trap flags + visual marks
	var prop_traps: Dictionary = bm.get("prop_traps", {})
	for key in PROP_PATHS.keys():
		var area: Node = get_node_or_null(String(PROP_PATHS[key]))
		if area == null:
			continue
		var want: bool = bool(prop_traps.get(key, false))
		if "is_booby_trapped" in area:
			area.is_booby_trapped = want
		var sprite: CanvasItem = area.get_parent() as CanvasItem
		if sprite:
			var UsableShimmer = load("res://usable_shimmer.gd")
			if want:
				UsableShimmer.mark_trapped_p1(sprite)
			# leave used state alone

	# Positions
	if bm.has("p1_pos"):
		p1.global_position = bm["p1_pos"]
		p1.velocity = Vector2.ZERO
	if bm.has("p2_pos"):
		p2.global_position = bm["p2_pos"]
		p2.velocity = Vector2.ZERO

	# Turn / visibility
	var turn: String = String(bm.get("turn", "Player1"))
	_force_turn(turn, p1, p2)

	if _tm and _tm.has_method("_update_hud"):
		_tm._update_hud()
	if _tm and _tm.has_method("_update_inventory_visibility"):
		_tm._update_inventory_visibility()

	var trigger: String = String(bm.get("trigger", ""))
	if not trigger.is_empty():
		await _run_trigger(trigger, p1, p2)

	_set_status("Bookmark: %s — %s" % [name, String(bm.get("label", ""))])
	print("[DEV] Applied bookmark=", name, " turn=", turn, " traps_left=", _tm.traps_left if _tm else "?", " trigger=", trigger)
	return true


func _force_turn(turn: String, p1: Node, p2: Node) -> void:
	if _tm:
		_tm.current_turn = turn
	if turn == "Player1":
		if p1.has_method("set_active"):
			p1.set_active(true)
		if p2.has_method("set_active"):
			p2.set_active(false)
	else:
		if p1.has_method("set_active"):
			p1.set_active(false)
		if p2.has_method("set_active"):
			p2.set_active(true)
	var UsableShimmer = load("res://usable_shimmer.gd")
	UsableShimmer.on_turn_changed(turn)


func _clear_inventory() -> void:
	if _tm == null:
		return
	if not "_inv" in _tm:
		return
	var inv: Array = _tm._inv
	for e in inv.duplicate():
		var slot = e.get("slot")
		if slot and is_instance_valid(slot):
			slot.queue_free()
	_tm._inv.clear()


func _run_trigger(trigger: String, p1: Node, p2: Node) -> void:
	match trigger:
		"plant_monster":
			var plant: Sprite2D = get_node_or_null("/root/Main/Plant") as Sprite2D
			var ap: AnimationPlayer = get_node_or_null("/root/Main/Plant/AnimationPlayer") as AnimationPlayer
			if plant:
				plant.self_modulate = Color.WHITE
			if ap:
				ap.active = true
				ap.play("monster")
				# Don't await forever in capture — leave anim running
		"dresser_bomb":
			var area: Node = get_node_or_null("/root/Main/DresserProp/DresserArea")
			if area and area.has_method("_eject_pipe_bomb"):
				area.call("_eject_pipe_bomb")
			elif area and area.has_method("_show_open_drawer"):
				area.call("_show_open_drawer")
				if area.has_method("_eject_pipe_bomb"):
					area.call("_eject_pipe_bomb")
		"p2_cartwheel":
			if p2 and p2.has_method("play_blast_cartwheel"):
				# Blast away from a fake explosion near player
				var from: Vector2 = p2.global_position + Vector2(-40, 0)
				p2.call("play_blast_cartwheel", from)
		_:
			push_warning("[DEV] Unknown trigger: %s" % trigger)


func _do_capture(path: String) -> void:
	# Let layout / anim settle
	for i in 12:
		await get_tree().process_frame
	var vp := get_viewport()
	if vp == null:
		push_error("[DEV] No viewport for capture")
		return
	await get_tree().process_frame
	var tex: ViewportTexture = vp.get_texture()
	if tex == null:
		push_error("[DEV] Viewport texture null (headless dummy renderer?)")
		# Still write a tiny proof file so agents have an artifact
		var f := FileAccess.open(path if path.begins_with("user://") or path.begins_with("res://") else "user://dev_capture_fallback.txt", FileAccess.WRITE)
		if f:
			f.store_string("bookmark applied; screenshot unavailable under dummy renderer\n")
			f.close()
		return
	var img: Image = tex.get_image()
	if img == null:
		push_error("[DEV] get_image null")
		return
	var out := path
	if out.is_empty():
		out = "user://dev_bookmark_capture.png"
	var err := img.save_png(out)
	var abs_path := ProjectSettings.globalize_path(out) if out.begins_with("user://") or out.begins_with("res://") else out
	print("[DEV] capture err=", err, " path=", abs_path, " size=", img.get_width(), "x", img.get_height())


## --- F1 debug menu ---

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			_toggle_menu()
			get_viewport().set_input_as_handled()
		elif _menu_open and event.keycode == KEY_ESCAPE:
			_set_menu_visible(false)
			get_viewport().set_input_as_handled()


func _toggle_menu() -> void:
	_set_menu_visible(not _menu_open)


func _set_menu_visible(v: bool) -> void:
	_menu_open = v
	if _menu:
		_menu.visible = v


func _build_menu() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		scene = get_node_or_null("/root/Main")
	_menu = CanvasLayer.new()
	_menu.name = "DevDebugMenu"
	_menu.layer = 128
	_menu.visible = false
	scene.add_child(_menu)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu.add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_set_menu_visible(false)
	)
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -200
	panel.offset_top = -150
	panel.offset_right = 200
	panel.offset_bottom = 150
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	style.border_color = Color(0.95, 0.78, 0.28, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var title := Label.new()
	title.text = "DEV MENU (F1)"
	_style_label(title, 12)
	col.add_child(title)

	_status = Label.new()
	_status.text = "Pick a bookmark"
	_style_label(_status, 8)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 160)
	col.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	for name in DevBookmarks.names():
		var bm: Dictionary = DevBookmarks.get_bookmark(name)
		var btn := Button.new()
		btn.text = "%s — %s" % [name, String(bm.get("label", ""))]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_style_btn(btn)
		var bm_name := String(name)
		btn.pressed.connect(func():
			apply_bookmark(bm_name)
			_set_menu_visible(false)
		)
		_list.add_child(btn)

	# Quick actions
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	col.add_child(actions)

	var plant_btn := Button.new()
	plant_btn.text = "Anim: plant"
	_style_btn(plant_btn)
	plant_btn.pressed.connect(func(): _run_trigger("plant_monster", null, null))
	actions.add_child(plant_btn)

	var bomb_btn := Button.new()
	bomb_btn.text = "Anim: bomb"
	_style_btn(bomb_btn)
	bomb_btn.pressed.connect(func(): _run_trigger("dresser_bomb", null, null))
	actions.add_child(bomb_btn)

	var cart_btn := Button.new()
	cart_btn.text = "Anim: cartwheel"
	_style_btn(cart_btn)
	cart_btn.pressed.connect(func():
		var p2 = get_node_or_null("/root/Main/Player2/Player2Body")
		_run_trigger("p2_cartwheel", null, p2)
	)
	actions.add_child(cart_btn)

	var close_btn := Button.new()
	close_btn.text = "Close (Esc)"
	_style_btn(close_btn)
	close_btn.pressed.connect(func(): _set_menu_visible(false))
	col.add_child(close_btn)


func _style_label(lab: Label, size: int) -> void:
	if ResourceLoader.exists("res://PressStart2P-Regular.ttf"):
		lab.add_theme_font_override("font", load("res://PressStart2P-Regular.ttf"))
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))


func _style_btn(btn: Button) -> void:
	if ResourceLoader.exists("res://PressStart2P-Regular.ttf"):
		btn.add_theme_font_override("font", load("res://PressStart2P-Regular.ttf"))
	btn.add_theme_font_size_override("font_size", 8)
	btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))


func _set_status(t: String) -> void:
	if _status:
		_status.text = t
