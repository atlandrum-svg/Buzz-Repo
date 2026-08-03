extends SceneTree
## Headless: load main scene, open Pills dialog, validate UI nodes, quit.
## godot --headless --path . --script res://_capture_pills_dialog.gd


const MAIN_SCENE := "res://Stick Figure 4.tscn"
const FAIL := 1
const PASS := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		push_error("[PILLS] FAIL: load scene")
		quit(FAIL)
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	for i in 10:
		await process_frame

	var tm: Node = main.get_node_or_null("TurnManager")
	if tm == null:
		push_error("[PILLS] FAIL: TurnManager missing")
		quit(FAIL)
		return

	# Inventory should seed pills in slot 0
	if tm._inv_item_ids.is_empty() or String(tm._inv_item_ids[0]) != "pills":
		push_error("[PILLS] FAIL: expected pills item_id in slot 0, got %s" % str(tm._inv_item_ids))
		quit(FAIL)
		return
	print("[PILLS] inv slot0 id=", tm._inv_item_ids[0], " slots=", tm._inv_slots.size())

	if tm.is_pills_dialog_open():
		push_error("[PILLS] FAIL: dialog open before show")
		quit(FAIL)
		return

	tm.show_pills_dialog()
	await process_frame
	if not tm.is_pills_dialog_open():
		push_error("[PILLS] FAIL: show_pills_dialog did not open")
		quit(FAIL)
		return

	var dialog: Control = tm._pills_dialog
	if dialog == null or not dialog.visible:
		push_error("[PILLS] FAIL: PillsDialog missing/invisible")
		quit(FAIL)
		return

	var title := dialog.find_child("Title", true, false) as Label
	var take_btn := dialog.find_child("TakeButton", true, false) as Button
	var cancel_btn := dialog.find_child("CancelButton", true, false) as Button
	if title == null or title.text != "Pills":
		push_error("[PILLS] FAIL: title expected 'Pills', got %s" % (title.text if title else "null"))
		quit(FAIL)
		return
	if take_btn == null or take_btn.text != "Take":
		push_error("[PILLS] FAIL: Take button missing")
		quit(FAIL)
		return
	if cancel_btn == null or cancel_btn.text != "Cancel":
		push_error("[PILLS] FAIL: Cancel button missing")
		quit(FAIL)
		return
	print("[PILLS] dialog title=", title.text, " buttons=", take_btn.text, "/", cancel_btn.text)

	# Cancel closes
	tm._on_pills_cancel_pressed()
	await process_frame
	if tm.is_pills_dialog_open():
		push_error("[PILLS] FAIL: cancel did not close dialog")
		quit(FAIL)
		return

	# Take closes + signal path (re-open then take)
	tm.show_pills_dialog()
	await process_frame
	var take_hits := [0]
	tm.pills_take_pressed.connect(func(): take_hits[0] += 1)
	tm._on_pills_take_pressed()
	await process_frame
	if tm.is_pills_dialog_open():
		push_error("[PILLS] FAIL: take did not close dialog")
		quit(FAIL)
		return
	if take_hits[0] != 1:
		push_error("[PILLS] FAIL: pills_take_pressed signal not emitted")
		quit(FAIL)
		return

	print("[PILLS] LAYOUT: centered modal — purple outer frame, gold/dark panel, PressStart2P")
	print("[PILLS]   Title: Pills | icon | Take pills? | [Take] [Cancel]")
	print("[PILLS]   Opens on inventory slot click when item_id == pills")
	print("[PILLS] PASS")
	quit(PASS)
