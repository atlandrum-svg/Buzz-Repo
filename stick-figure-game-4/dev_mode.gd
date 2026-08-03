extends Node
## Debug-only jump bookmarks + F1 menu + CLI launch.
## Instantiated only when OS.is_debug_build() — completely inert in release builds
## (DevMode node is never created; CLI/F1 hooks do not run).

const DevBookmarks = preload("res://dev_bookmarks.gd")
const UsableShimmer = preload("res://usable_shimmer.gd")

const PROP_PATHS := {
	"plant": "/root/Main/Plant/PlantArea",
	"dresser": "/root/Main/DresserProp/DresserArea",
	"laptop": "/root/Main/LaptopCutOut/LaptopArea",
	"pill": "/root/Main/PillBottle/PillBottleArea",
}

const POS_EPS := 2.5

var _tm: Node
var _menu: CanvasLayer
var _menu_open := false
var _status: Label
var _live_label: Label
var _pending_bookmark: String = ""
var _capture_path: String = ""
var _quit_after := false
var _assert_after := false
var _last_apply_ok := false


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
	for i in 6:
		await get_tree().process_frame
	_build_menu()
	var exit_code := 0
	var auto := _assert_after or _quit_after or not _capture_path.is_empty()
	if not _pending_bookmark.is_empty():
		# Assert path restores state without one-shot triggers (blast/FX would fail equality).
		# Interactive / capture path runs the bookmark's trigger after state is solid.
		var with_trigger := not _assert_after
		_last_apply_ok = await apply_bookmark(_pending_bookmark, with_trigger)
		print("[DEV] CLI bookmark=", _pending_bookmark, " ok=", _last_apply_ok, " trigger=", with_trigger)
		if not _last_apply_ok:
			exit_code = 1
		# Idempotence: second full restore of same bookmark must still match.
		if exit_code == 0 and _assert_after:
			var again: bool = await apply_bookmark(_pending_bookmark, false)
			if not again:
				exit_code = 1
			var assert_ok := assert_matches_bookmark(_pending_bookmark)
			print("[DEV] assert (after 2x apply) bookmark=", _pending_bookmark, " ok=", assert_ok)
			if not assert_ok:
				exit_code = 1
			# Optional: fire trigger once after assert so capture can show anim
			if exit_code == 0 and not _capture_path.is_empty():
				var bm: Dictionary = DevBookmarks.get_bookmark(_pending_bookmark)
				var trig := String(bm.get("trigger", ""))
				if not trig.is_empty():
					var main := get_node_or_null("/root/Main")
					var p1 = main.get_node_or_null("Player1/Player1Body") if main else null
					var p2 = main.get_node_or_null("Player2/Player2Body") if main else null
					await _run_trigger(trig, p1, p2)
		elif exit_code == 0 and not _assert_after and not with_trigger:
			pass
		if exit_code == 0 and not _capture_path.is_empty():
			var cap_ok: bool = await _do_capture(_capture_path)
			print("[DEV] capture ok=", cap_ok)
			if not cap_ok:
				exit_code = 1
		if auto:
			print("[DEV] automation exit_code=", exit_code)
			get_tree().quit(exit_code)
			return
	else:
		print("[DEV] Dev mode ready. F1 = debug menu. Bookmarks: ", DevBookmarks.names())
		print("[DEV] Automation: godot --path . -- --bookmark=NAME --dev-assert --dev-quit")


func _parse_cli() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var all_args: PackedStringArray = OS.get_cmdline_args()
	for a in all_args:
		if not args.has(a) and (a.begins_with("--bookmark") or a.begins_with("--dev-") or a == "-b"):
			args.append(a)
	for i in range(args.size()):
		var a: String = args[i]
		if a.begins_with("--bookmark="):
			_pending_bookmark = a.substr("--bookmark=".length())
		elif a == "--bookmark" or a == "-b":
			if i + 1 < args.size() and not String(args[i + 1]).begins_with("-"):
				_pending_bookmark = args[i + 1]
		elif a.begins_with("--dev-capture="):
			_capture_path = a.substr("--dev-capture=".length())
		elif a == "--dev-quit" or a == "--dev-quit=1":
			_quit_after = true
		elif a == "--dev-assert" or a == "--dev-assert=1":
			_assert_after = true


## Full reset + restore. Applying the same bookmark twice yields identical state.
## run_trigger: when false, skip one-shot FX (for assert/idempotence).
func apply_bookmark(name: String, run_trigger: bool = true) -> bool:
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

	# --- 1) Wipe ephemeral runtime (no stale carry-over) ---
	_full_runtime_wipe(main, p1, p2)

	# --- 2) Restore counters / inventory ---
	var turn: String = String(bm.get("turn", "Player1"))
	if _tm:
		_tm.traps_left = int(bm.get("traps_left", 3))
		_tm.p2_items_used = int(bm.get("p2_items_used", 0))
		_clear_inventory()
		var inv: Array = bm.get("inventory_pills", [])
		for trapped in inv:
			if _tm.has_method("add_inventory_pill"):
				_tm.add_inventory_pill(bool(trapped))

	# --- 3) Prop traps + shimmer (trapped / used fully set) ---
	var prop_traps: Dictionary = bm.get("prop_traps", {})
	var prop_used: Dictionary = bm.get("prop_used", {})
	for key in PROP_PATHS.keys():
		var area: Node = get_node_or_null(String(PROP_PATHS[key]))
		if area == null:
			continue
		var want_trap: bool = bool(prop_traps.get(key, false))
		var want_used: bool = bool(prop_used.get(key, false))
		if "is_booby_trapped" in area:
			area.is_booby_trapped = want_trap
		# Per-prop visual reset then force shimmer state
		if area.has_method("dev_reset_visuals"):
			area.call("dev_reset_visuals")
		var sprite: CanvasItem = area.get_parent() as CanvasItem
		if sprite:
			UsableShimmer.force_state(sprite, want_trap, want_used, turn)

	# Pill world presence: default picked up when inventory has bottles
	var pill_area: Node = get_node_or_null(String(PROP_PATHS["pill"]))
	var inv_pills: Array = bm.get("inventory_pills", [])
	var pill_picked := bool(bm.get("pill_picked_up", inv_pills.size() > 0))
	if pill_area and pill_area.has_method("dev_set_picked_up"):
		pill_area.call("dev_set_picked_up", pill_picked)
		if "is_booby_trapped" in pill_area:
			pill_area.is_booby_trapped = bool(prop_traps.get("pill", false))
		var bottle: CanvasItem = pill_area.get_parent() as CanvasItem
		if bottle and not pill_picked:
			UsableShimmer.force_state(
				bottle,
				bool(prop_traps.get("pill", false)),
				bool(prop_used.get("pill", false)),
				turn
			)

	# --- 4) Player combat/speed already wiped; set positions twice to beat physics ---
	var p1_pos: Vector2 = bm.get("p1_pos", Vector2(20, 100))
	var p2_pos: Vector2 = bm.get("p2_pos", Vector2(50, 100))
	_place_player(p1, p1_pos)
	_place_player(p2, p2_pos)
	await get_tree().process_frame
	await get_tree().physics_frame
	_place_player(p1, p1_pos)
	_place_player(p2, p2_pos)

	# Optional ADHD boost restore
	if bool(bm.get("p2_adhd_boost", false)) and p2.has_method("apply_adhd_boost"):
		p2.call("apply_adhd_boost")

	# --- 5) Turn / HUD ---
	_force_turn(turn, p1, p2)
	if _tm and _tm.has_method("_update_hud"):
		_tm._update_hud()
	if _tm and _tm.has_method("_update_inventory_visibility"):
		_tm._update_inventory_visibility()

	# --- 6) Optional one-shot trigger (after state is stable) ---
	var trigger: String = String(bm.get("trigger", ""))
	if run_trigger and not trigger.is_empty():
		await _run_trigger(trigger, p1, p2)

	_set_status("Bookmark: %s — %s" % [name, String(bm.get("label", ""))])
	_refresh_live_label()
	print(
		"[DEV] Applied bookmark=", name,
		" turn=", turn,
		" traps_left=", _tm.traps_left if _tm else "?",
		" inv=", inv_pills.size(),
		" trigger=", trigger if run_trigger else "(skipped)"
	)
	return true


func _full_runtime_wipe(main: Node, p1: Node, p2: Node) -> void:
	# Close dialogs / pending inv
	if _tm:
		if _tm.get("_pills_dialog_open"):
			if _tm.has_method("hide_pills_dialog"):
				_tm.hide_pills_dialog()
		if "_pending_inv_entry" in _tm:
			_tm._pending_inv_entry = {}
		if "_pills_dialog_open" in _tm:
			_tm._pills_dialog_open = false
		if _tm.get("_pills_dialog") and is_instance_valid(_tm._pills_dialog):
			_tm._pills_dialog.visible = false

	# Players
	if p1.has_method("dev_full_reset"):
		p1.call("dev_full_reset")
	if p2.has_method("dev_full_reset"):
		p2.call("dev_full_reset")

	# Prop-local FX
	for key in PROP_PATHS.keys():
		var area: Node = get_node_or_null(String(PROP_PATHS[key]))
		if area and area.has_method("dev_reset_visuals"):
			area.call("dev_reset_visuals")
		if area and "is_booby_trapped" in area:
			area.is_booby_trapped = false
		if area and "player_inside" in area:
			area.player_inside = null

	# All shimmers clean
	UsableShimmer.reset_all_to_default()

	# Orphan censor / bomb / smoke nodes
	for child in main.get_children():
		var n := String(child.name)
		if n.begins_with("PipeBomb") or n == "PlantSmokeGIF" or n.begins_with("Censor"):
			child.queue_free()


func _place_player(body: Node, pos: Vector2) -> void:
	body.global_position = pos
	if "velocity" in body:
		body.velocity = Vector2.ZERO
	if body.has_method("set_movement_locked"):
		# Keep unlocked for play; wipe already cleared blast
		body.set_movement_locked(false)


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
	UsableShimmer.on_turn_changed(turn)


func _clear_inventory() -> void:
	if _tm == null or not ("_inv" in _tm):
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
		"dresser_bomb":
			var area: Node = get_node_or_null("/root/Main/DresserProp/DresserArea")
			if area and area.has_method("_show_open_drawer"):
				area.call("_show_open_drawer")
			if area and area.has_method("_eject_pipe_bomb"):
				area.call("_eject_pipe_bomb")
		"p2_cartwheel":
			if p2 and p2.has_method("play_blast_cartwheel"):
				var from: Vector2 = p2.global_position + Vector2(-40, 0)
				p2.call("play_blast_cartwheel", from)
		_:
			push_warning("[DEV] Unknown trigger: %s" % trigger)


## Strict state check after CLI boot path applied a bookmark (no re-apply).
func assert_matches_bookmark(name: String) -> bool:
	var bm: Dictionary = DevBookmarks.get_bookmark(name)
	if bm.is_empty():
		push_error("[DEV-ASSERT] unknown bookmark")
		return false
	var ok := true
	var main := get_node_or_null("/root/Main")
	if main == null or _tm == null:
		push_error("[DEV-ASSERT] main/tm missing")
		return false

	var turn_want := String(bm.get("turn", "Player1"))
	if String(_tm.current_turn) != turn_want:
		push_error("[DEV-ASSERT] turn want=%s got=%s" % [turn_want, _tm.current_turn])
		ok = false
	var traps_want := int(bm.get("traps_left", 3))
	if int(_tm.traps_left) != traps_want:
		push_error("[DEV-ASSERT] traps_left want=%s got=%s" % [traps_want, _tm.traps_left])
		ok = false
	var p2u_want := int(bm.get("p2_items_used", 0))
	if int(_tm.p2_items_used) != p2u_want:
		push_error("[DEV-ASSERT] p2_items_used want=%s got=%s" % [p2u_want, _tm.p2_items_used])
		ok = false

	var inv_want: Array = bm.get("inventory_pills", [])
	var inv_got: Array = _tm._inv if "_inv" in _tm else []
	if inv_got.size() != inv_want.size():
		push_error("[DEV-ASSERT] inv size want=%s got=%s" % [inv_want.size(), inv_got.size()])
		ok = false
	else:
		for i in inv_want.size():
			var want_t := bool(inv_want[i])
			var got_t := bool(inv_got[i].get("trapped", false))
			if want_t != got_t:
				push_error("[DEV-ASSERT] inv[%s] trapped want=%s got=%s" % [i, want_t, got_t])
				ok = false

	var p1: Node = main.get_node_or_null("Player1/Player1Body")
	var p2: Node = main.get_node_or_null("Player2/Player2Body")
	if p1 and bm.has("p1_pos"):
		var d1: float = p1.global_position.distance_to(bm["p1_pos"])
		if d1 > POS_EPS:
			push_error("[DEV-ASSERT] p1_pos want=%s got=%s d=%s" % [bm["p1_pos"], p1.global_position, d1])
			ok = false
	if p2 and bm.has("p2_pos"):
		var d2: float = p2.global_position.distance_to(bm["p2_pos"])
		if d2 > POS_EPS:
			push_error("[DEV-ASSERT] p2_pos want=%s got=%s d=%s" % [bm["p2_pos"], p2.global_position, d2])
			ok = false

	# Speed boost
	var want_boost := bool(bm.get("p2_adhd_boost", false))
	if p2:
		var mult: float = float(p2.get("speed_mult"))
		if want_boost and mult < 2.0:
			push_error("[DEV-ASSERT] p2_adhd_boost expected mult>=2 got=%s" % mult)
			ok = false
		if not want_boost and absf(mult - 1.0) > 0.01:
			push_error("[DEV-ASSERT] p2 speed_mult should be 1.0 got=%s" % mult)
			ok = false
		if p2.get("_blast_active") == true:
			push_error("[DEV-ASSERT] p2 still in blast state")
			ok = false

	var prop_traps: Dictionary = bm.get("prop_traps", {})
	for key in PROP_PATHS.keys():
		var area: Node = get_node_or_null(String(PROP_PATHS[key]))
		if area == null:
			continue
		var want_trap := bool(prop_traps.get(key, false))
		if "is_booby_trapped" in area and bool(area.is_booby_trapped) != want_trap:
			push_error("[DEV-ASSERT] %s trap want=%s got=%s" % [key, want_trap, area.is_booby_trapped])
			ok = false
		var sprite: CanvasItem = area.get_parent() as CanvasItem
		if sprite:
			var sh = sprite.get_node_or_null("UsableShimmer")
			if sh:
				var want_used := bool(bm.get("prop_used", {}).get(key, false))
				if bool(sh.p1_trapped) != want_trap:
					push_error("[DEV-ASSERT] %s shimmer.p1_trapped want=%s got=%s" % [key, want_trap, sh.p1_trapped])
					ok = false
				if bool(sh.p2_used) != want_used:
					push_error("[DEV-ASSERT] %s shimmer.p2_used want=%s got=%s" % [key, want_used, sh.p2_used])
					ok = false

	var inv_pills: Array = bm.get("inventory_pills", [])
	var pill_picked_want := bool(bm.get("pill_picked_up", inv_pills.size() > 0))
	var pill_area: Node = get_node_or_null(String(PROP_PATHS["pill"]))
	if pill_area and "_picked_up" in pill_area:
		if bool(pill_area._picked_up) != pill_picked_want:
			push_error("[DEV-ASSERT] pill_picked want=%s got=%s" % [pill_picked_want, pill_area._picked_up])
			ok = false

	if ok:
		print("[DEV-ASSERT] PASS bookmark=", name)
	else:
		push_error("[DEV-ASSERT] FAIL bookmark=", name)
	return ok


func _do_capture(path: String) -> bool:
	for i in 12:
		await get_tree().process_frame
	var vp := get_viewport()
	if vp == null:
		push_error("[DEV] capture FAIL: no viewport")
		return false
	await get_tree().process_frame
	var tex: ViewportTexture = vp.get_texture()
	if tex == null:
		push_error("[DEV] capture FAIL: viewport texture null (headless dummy renderer?)")
		return false
	var img: Image = tex.get_image()
	if img == null:
		push_error("[DEV] capture FAIL: get_image null")
		return false
	var out := path
	if out.is_empty():
		out = "user://dev_bookmark_capture.png"
	var err := img.save_png(out)
	var abs_path := ProjectSettings.globalize_path(out) if out.begins_with("user://") or out.begins_with("res://") else out
	print("[DEV] capture err=", err, " path=", abs_path, " size=", img.get_width(), "x", img.get_height())
	if err != OK:
		push_error("[DEV] capture FAIL: save_png err=", err)
		return false
	# Verify artifact exists and is non-empty
	if out.begins_with("user://") or out.begins_with("res://"):
		if not FileAccess.file_exists(out):
			push_error("[DEV] capture FAIL: file missing after save")
			return false
	else:
		if not FileAccess.file_exists(out):
			# absolute path
			var f := FileAccess.open(out, FileAccess.READ)
			if f == null:
				push_error("[DEV] capture FAIL: cannot re-open ", out)
				return false
			f.close()
	return true


## --- Live setters (F1 menu + callable from code) ---

func set_traps_left(v: int) -> void:
	if _tm == null:
		return
	_tm.traps_left = clampi(v, 0, 3)
	if _tm.has_method("_update_hud"):
		_tm._update_hud()
	_refresh_live_label()


func set_p2_items_used(v: int) -> void:
	if _tm == null:
		return
	_tm.p2_items_used = clampi(v, 0, 3)
	if _tm.has_method("_update_hud"):
		_tm._update_hud()
	_refresh_live_label()


func set_turn(turn: String) -> void:
	var main := get_node_or_null("/root/Main")
	if main == null:
		return
	var p1: Node = main.get_node_or_null("Player1/Player1Body")
	var p2: Node = main.get_node_or_null("Player2/Player2Body")
	_force_turn(turn, p1, p2)
	if _tm and _tm.has_method("_update_hud"):
		_tm._update_hud()
	if _tm and _tm.has_method("_update_inventory_visibility"):
		_tm._update_inventory_visibility()
	_refresh_live_label()


func add_inv_pill(trapped: bool) -> void:
	if _tm and _tm.has_method("add_inventory_pill"):
		_tm.add_inventory_pill(trapped)
	_refresh_live_label()


func clear_inv() -> void:
	_clear_inventory()
	if _tm and _tm.has_method("_update_inventory_visibility"):
		_tm._update_inventory_visibility()
	_refresh_live_label()


func _refresh_live_label() -> void:
	if _live_label == null or _tm == null:
		return
	var inv_n: int = 0
	if "_inv" in _tm:
		inv_n = int(_tm._inv.size())
	_live_label.text = "turn=%s traps=%d p2use=%d inv=%d" % [
		_tm.current_turn, _tm.traps_left, _tm.p2_items_used, inv_n
	]


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
	if _menu_open:
		_refresh_live_label()


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
	panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	panel.offset_left = 12
	panel.offset_top = -170
	panel.offset_right = 420
	panel.offset_bottom = 170
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	style.border_color = Color(0.95, 0.78, 0.28, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	var title := Label.new()
	title.text = "DEV MENU (F1)"
	_style_label(title, 12)
	col.add_child(title)

	_status = Label.new()
	_status.text = "Bookmarks + live setters"
	_style_label(_status, 8)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)

	_live_label = Label.new()
	_style_label(_live_label, 8)
	col.add_child(_live_label)
	_refresh_live_label()

	# --- Live setters ---
	var set_title := Label.new()
	set_title.text = "— LIVE SETTERS —"
	_style_label(set_title, 8)
	col.add_child(set_title)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 4)
	col.add_child(row1)
	_add_btn(row1, "Traps-1", func(): set_traps_left(_tm.traps_left - 1 if _tm else 0))
	_add_btn(row1, "Traps+1", func(): set_traps_left(_tm.traps_left + 1 if _tm else 0))
	_add_btn(row1, "P2use-1", func(): set_p2_items_used(_tm.p2_items_used - 1 if _tm else 0))
	_add_btn(row1, "P2use+1", func(): set_p2_items_used(_tm.p2_items_used + 1 if _tm else 0))

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	col.add_child(row2)
	_add_btn(row2, "Turn P1", func(): set_turn("Player1"))
	_add_btn(row2, "Turn P2", func(): set_turn("Player2"))
	_add_btn(row2, "+Pill", func(): add_inv_pill(false))
	_add_btn(row2, "+TrapPill", func(): add_inv_pill(true))
	_add_btn(row2, "ClrInv", func(): clear_inv())

	var bm_title := Label.new()
	bm_title.text = "— BOOKMARKS —"
	_style_label(bm_title, 8)
	col.add_child(bm_title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 120)
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

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
		list.add_child(btn)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	col.add_child(actions)
	_add_btn(actions, "Anim:plant", func(): _run_trigger("plant_monster", null, null))
	_add_btn(actions, "Anim:bomb", func(): _run_trigger("dresser_bomb", null, null))
	_add_btn(actions, "Anim:cart", func():
		var p2 = get_node_or_null("/root/Main/Player2/Player2Body")
		_run_trigger("p2_cartwheel", null, p2)
	)

	_add_btn(col, "Close (Esc)", func(): _set_menu_visible(false))


func _add_btn(parent: Node, text: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	_style_btn(btn)
	btn.pressed.connect(cb)
	parent.add_child(btn)


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
