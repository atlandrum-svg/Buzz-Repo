extends SceneTree
## Headless/agent proof: load main scene, apply a bookmark, print state, optional quit.
##
## Example:
##   godot --headless --path . --script res://_dev_bookmark_capture.gd -- --bookmark=mid_game
##
## With screenshot (windowed; headless may lack a real viewport image):
##   godot --path . -- --bookmark=plant_monster --dev-capture=user://dev_proof.png --dev-quit


const MAIN_SCENE := "res://Stick Figure 4.tscn"
const FAIL := 1
const PASS := 0


func _initialize() -> void:
	call_deferred("_run")


func _parse_bookmark() -> String:
	var name := "start"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in OS.get_cmdline_args():
		if not args.has(a):
			args.append(a)
	for i in range(args.size()):
		var a: String = args[i]
		if a.begins_with("--bookmark="):
			return a.substr("--bookmark=".length())
		if (a == "--bookmark" or a == "-b") and i + 1 < args.size():
			return args[i + 1]
	return name


func _run() -> void:
	if not OS.is_debug_build():
		push_error("[DEV-CAPTURE] FAIL: not a debug build — dev mode inert")
		quit(FAIL)
		return

	var bm_name := _parse_bookmark()
	print("[DEV-CAPTURE] bookmark=", bm_name)

	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		push_error("[DEV-CAPTURE] FAIL: load scene")
		quit(FAIL)
		return
	var main: Node = packed.instantiate()
	root.add_child(main)

	# Wait for TurnManager + DevMode boot
	var tm: Node = null
	var dev: Node = null
	for i in 60:
		await process_frame
		tm = main.get_node_or_null("TurnManager")
		if tm:
			dev = tm.get_node_or_null("DevMode")
			if dev:
				break
	if tm == null or dev == null:
		push_error("[DEV-CAPTURE] FAIL: TurnManager/DevMode missing (debug build?)")
		quit(FAIL)
		return

	# DevMode may already apply CLI bookmark; force apply for this script path.
	var ok: bool = await dev.apply_bookmark(bm_name)
	if not ok:
		push_error("[DEV-CAPTURE] FAIL: apply_bookmark")
		quit(FAIL)
		return

	await process_frame
	await process_frame

	var p1: Node = main.get_node_or_null("Player1/Player1Body")
	var p2: Node = main.get_node_or_null("Player2/Player2Body")
	print("[DEV-CAPTURE] turn=", tm.current_turn)
	print("[DEV-CAPTURE] traps_left=", tm.traps_left, " p2_items_used=", tm.p2_items_used)
	print("[DEV-CAPTURE] inv_size=", tm._inv.size() if "_inv" in tm else -1)
	if p1:
		print("[DEV-CAPTURE] p1_pos=", p1.global_position)
	if p2:
		print("[DEV-CAPTURE] p2_pos=", p2.global_position)

	var plant = main.get_node_or_null("Plant/PlantArea")
	if plant:
		print("[DEV-CAPTURE] plant_trapped=", plant.is_booby_trapped)

	# State proof file (always)
	var proof := "user://dev_bookmark_proof.txt"
	var f := FileAccess.open(proof, FileAccess.WRITE)
	if f:
		f.store_string("bookmark=%s\n" % bm_name)
		f.store_string("turn=%s\n" % tm.current_turn)
		f.store_string("traps_left=%s\n" % tm.traps_left)
		if p2:
			f.store_string("p2_pos=%s\n" % p2.global_position)
		f.close()
		print("[DEV-CAPTURE] proof=", ProjectSettings.globalize_path(proof))

	# Screenshot attempt
	var cap := "user://dev_bookmark_capture.png"
	for i in 8:
		await process_frame
	var vp := root.get_viewport()
	var img: Image = null
	if vp and vp.get_texture():
		img = vp.get_texture().get_image()
	if img:
		var err := img.save_png(cap)
		print("[DEV-CAPTURE] screenshot err=", err, " path=", ProjectSettings.globalize_path(cap),
			" size=", img.get_width(), "x", img.get_height())
	else:
		print("[DEV-CAPTURE] screenshot skipped (no viewport image — use windowed --dev-capture)")

	print("[DEV-CAPTURE] PASS")
	quit(PASS)
