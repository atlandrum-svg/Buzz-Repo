extends Node
## Durable debug jump points for Stick Figure Game 4.
##
## How to add a new cheat:
##   1. Add a public `cheat_*` method on TurnManager (or here) that sets real game state.
##   2. Register it in `_register_cheats()` with a key + short description.
##   3. Prefer calling the same code paths production uses (spawn, resolve, possess).
##
## Keys (default): hold nothing — just press the function key while the game has focus.
## Toggle master switch: DEBUG_CHEATS_ENABLED

const DEBUG_CHEATS_ENABLED := true

## Toast time for "CHEAT: ..." status line.
const TOAST_SEC := 2.2

var _tm: Node = null
var _cheats: Array = [] ## {id, key, label, method}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_unhandled_input(true)
	call_deferred("_bind_turn_manager")


func _bind_turn_manager() -> void:
	_tm = get_node_or_null("/root/Main/TurnManager")
	if _tm == null:
		_tm = get_parent()
	_register_cheats()
	print("[CHEATS] ready — press F1 for list (enabled=", DEBUG_CHEATS_ENABLED, ")")


func _register_cheats() -> void:
	_cheats.clear()
	# id, Key, human label, TurnManager method name
	_add("help", KEY_F1, "List cheats", "cheat_help")
	_add("p2_roam", KEY_F5, "P2 free roam (end-of-round state)", "cheat_p2_eval_roam")
	_add("fireman", KEY_F6, "Spawn fireman at stand (normal)", "cheat_spawn_fireman")
	_add("possess", KEY_F7, "Possess fireman (zombie follows P2)", "cheat_possess_fireman")
	_add("encounter", KEY_F8, "Run the full fireman encounter (options + demon wheel)", "cheat_run_encounter")
	_add("landlord", KEY_F4, "Run the full landlord encounter (quiet round)", "cheat_run_landlord_encounter")
	_add("police", KEY_F2, "Run the full police encounter (cyber crime round)", "cheat_run_police_encounter")
	_add("give_demon", KEY_F9, "Give possession + ADHD meds", "cheat_give_demon_and_adhd")
	_add("reset_anx", KEY_F10, "Reset anxiety to the round-start baseline", "cheat_reset_anxiety")
	_add("gun_fail", KEY_F11, "Gun + fail attack → shoot choice", "cheat_gun_fail_then_offer")
	_add("gun_fent", KEY_F12, "Fent + gun leg shot / crawl", "cheat_gun_fent_leg")


func _add(id: String, keycode: Key, label: String, method: String) -> void:
	_cheats.append({"id": id, "key": keycode, "label": label, "method": method})


func _unhandled_input(event: InputEvent) -> void:
	if not DEBUG_CHEATS_ENABLED:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: Key = event.keycode
	for c in _cheats:
		if int(c["key"]) == int(k):
			_run_cheat(String(c["id"]), String(c["label"]), String(c["method"]))
			get_viewport().set_input_as_handled()
			return


func _run_cheat(id: String, label: String, method: String) -> void:
	if _tm == null or not is_instance_valid(_tm):
		_tm = get_node_or_null("/root/Main/TurnManager")
	if _tm == null:
		push_error("[CHEATS] TurnManager not found")
		return
	print("[CHEATS] ", id, " — ", label)
	if _tm.has_method("cheat_toast"):
		_tm.call("cheat_toast", "CHEAT: %s" % label)
	if method == "cheat_help":
		_print_help()
		if _tm.has_method("cheat_help"):
			_tm.call("cheat_help")
		return
	if _tm.has_method(method):
		_tm.call(method)
	else:
		push_error("[CHEATS] missing method on TurnManager: %s" % method)


func _print_help() -> void:
	print("========== DEBUG CHEATS ==========")
	for c in _cheats:
		var key_name: String = OS.get_keycode_string(c["key"] as Key)
		print("  ", key_name, "  ", c["label"], "  (", c["id"], ")")
	print("==================================")
