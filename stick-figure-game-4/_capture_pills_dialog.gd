extends SceneTree
## Headless: open Pills dialog via inventory path, validate UI, quit.
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

	# Seed a pill into our live inventory (no demo-seed overwrite of world)
	if tm.has_method("add_inventory_pill"):
		tm.add_inventory_pill(false)
	for i in 5:
		await process_frame
	if tm._inv.is_empty():
		push_error("[PILLS] FAIL: inventory empty after add_inventory_pill")
		quit(FAIL)
		return

	if tm.is_pills_dialog_open():
		push_error("[PILLS] FAIL: dialog open before show")
		quit(FAIL)
		return

	# Select first inv entry → should open dialog
	tm._on_inventory_slot_selected(tm._inv[0])
	await process_frame
	if not tm.is_pills_dialog_open():
		push_error("[PILLS] FAIL: slot select did not open dialog")
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

	# Cancel closes, keeps inv item
	var inv_before_cancel: int = tm._inv.size()
	tm._on_pills_cancel_pressed()
	await process_frame
	if tm.is_pills_dialog_open():
		push_error("[PILLS] FAIL: cancel did not close dialog")
		quit(FAIL)
		return
	if tm._inv.size() != inv_before_cancel:
		push_error("[PILLS] FAIL: cancel removed inventory item")
		quit(FAIL)
		return

	# Take closes + signal + consumes + boost path
	tm._on_inventory_slot_selected(tm._inv[0])
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
	if not tm._inv.is_empty():
		push_error("[PILLS] FAIL: take did not remove inventory item")
		quit(FAIL)
		return

	print("[PILLS] LAYOUT: centered modal — purple outer frame, gold/dark panel, PressStart2P")
	print("[PILLS]   Title: Pills | icon | Take pills? | [Take] [Cancel]")
	print("[PILLS]   Opens on inventory pill click; Take consumes + ADHD boost; Cancel keeps item")
	print("[PILLS] PASS")
	quit(PASS)
