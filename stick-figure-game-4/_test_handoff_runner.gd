extends SceneTree
## Headless validation: load Stick Figure 4, burn 3 traps, assert countdown then P2.
## Run: godot --headless --path . --script res://_test_handoff_runner.gd


const MAIN_SCENE := "res://Stick Figure 4.tscn"
const FAIL := 1
const PASS := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		push_error("[TEST] FAIL: could not load %s" % MAIN_SCENE)
		quit(FAIL)
		return

	var main: Node = packed.instantiate()
	root.add_child(main)
	# Wait for @onready + deferred HUD/transition UI builds.
	await process_frame
	await process_frame
	await process_frame

	var tm: Node = root.get_node_or_null("Main/TurnManager")
	if tm == null:
		# Stick Figure 4 root is named Main; if already current root child name differs:
		tm = main.get_node_or_null("TurnManager")
	if tm == null:
		push_error("[TEST] FAIL: TurnManager not found")
		quit(FAIL)
		return

	print("[TEST] initial current_turn=", tm.current_turn, " traps_left=", tm.traps_left)
	if tm.current_turn != "Player1" or tm.traps_left != 3:
		push_error("[TEST] FAIL: expected Player1 with 3 traps")
		quit(FAIL)
		return

	# Trap 1 and 2 must NOT switch turns.
	var ok1: bool = tm.consume_trap()
	print("[TEST] trap1 ok=", ok1, " traps_left=", tm.traps_left, " turn=", tm.current_turn, " handoff=", tm.is_handoff_active())
	if not ok1 or tm.traps_left != 2 or tm.current_turn != "Player1" or tm.is_handoff_active():
		push_error("[TEST] FAIL: trap1 should not switch turns")
		quit(FAIL)
		return

	var ok2: bool = tm.consume_trap()
	print("[TEST] trap2 ok=", ok2, " traps_left=", tm.traps_left, " turn=", tm.current_turn, " handoff=", tm.is_handoff_active())
	if not ok2 or tm.traps_left != 1 or tm.current_turn != "Player1" or tm.is_handoff_active():
		push_error("[TEST] FAIL: trap2 should not switch turns")
		quit(FAIL)
		return

	# Last trap starts handoff; turn must stay Player1 until countdown ends.
	var ok3: bool = tm.consume_trap()
	print("[TEST] trap3 (last) ok=", ok3, " traps_left=", tm.traps_left, " turn=", tm.current_turn, " handoff=", tm.is_handoff_active())
	if not ok3 or tm.traps_left != 0:
		push_error("[TEST] FAIL: last trap should consume")
		quit(FAIL)
		return

	# Give switch_turn one frame to set the flag and show UI.
	await process_frame
	await process_frame
	if not tm.is_handoff_active():
		push_error("[TEST] FAIL: expected is_handoff_active after last trap")
		quit(FAIL)
		return
	if tm.current_turn != "Player1":
		push_error("[TEST] FAIL: turn must stay Player1 during countdown")
		quit(FAIL)
		return
	if tm.player1.is_physics_processing() or tm.player2.is_physics_processing():
		push_error("[TEST] FAIL: physics must be frozen during handoff")
		quit(FAIL)
		return

	var layer: CanvasLayer = tm._transition_layer
	if layer == null or not layer.visible:
		push_error("[TEST] FAIL: transition layer not visible")
		quit(FAIL)
		return

	var labels_seen: Array[String] = []
	var last_label := ""
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		if layer.visible and tm._transition_label != null:
			var t: String = tm._transition_label.text
			if t != last_label:
				last_label = t
				labels_seen.append(t)
				print("[TEST] label=", t)
		if not tm.is_handoff_active() and tm.current_turn == "Player2":
			break
		await process_frame

	print("[TEST] labels_seen=", labels_seen)
	print("[TEST] FINAL turn=", tm.current_turn, " handoff=", tm.is_handoff_active(),
		" p1.active=", tm.player1.is_active, " p2.active=", tm.player2.is_active)

	var joined := " | ".join(labels_seen)
	if "Switching to Player 2" not in joined:
		push_error("[TEST] FAIL: countdown text must name Player 2")
		quit(FAIL)
		return
	if "3..." not in joined or "2..." not in joined or "1..." not in joined:
		push_error("[TEST] FAIL: expected 3... 2... 1... sequence in labels")
		quit(FAIL)
		return
	if tm.current_turn != "Player2":
		push_error("[TEST] FAIL: expected Player2 after countdown")
		quit(FAIL)
		return
	if tm.is_handoff_active():
		push_error("[TEST] FAIL: handoff should be done")
		quit(FAIL)
		return
	if not tm.player2.is_active or tm.player1.is_active:
		push_error("[TEST] FAIL: only Player2 should be active after switch")
		quit(FAIL)
		return

	print("[TEST] PASS: handoff countdown after LAST trap only; switched to Player2")
	quit(PASS)
