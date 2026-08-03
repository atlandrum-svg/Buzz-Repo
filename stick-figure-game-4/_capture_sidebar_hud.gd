extends SceneTree
## Headless: load main scene, wait for HUD, screenshot sidebar, quit.
## godot --headless --path . --script res://_capture_sidebar_hud.gd


const MAIN_SCENE := "res://Stick Figure 4.tscn"
const OUT_PATH := "user://sidebar_hud_capture.png"
const FAIL := 1
const PASS := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		push_error("[CAPTURE] FAIL: load scene")
		quit(FAIL)
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame

	var tm: Node = main.get_node_or_null("TurnManager")
	if tm == null:
		push_error("[CAPTURE] FAIL: TurnManager missing")
		quit(FAIL)
		return
	var hud: CanvasLayer = tm._hud_layer
	if hud == null:
		push_error("[CAPTURE] FAIL: GameHUD missing")
		quit(FAIL)
		return
	var sidebar: VBoxContainer = hud.get_node_or_null("SidebarMargin/SidebarColumn")
	if sidebar == null:
		push_error("[CAPTURE] FAIL: SidebarColumn missing")
		quit(FAIL)
		return
	var kids: PackedStringArray = PackedStringArray()
	for c in sidebar.get_children():
		kids.append(c.name)
	print("[CAPTURE] sidebar children=", kids)
	print("[CAPTURE] stats agility=", tm.agility, " charisma=", tm.charisma, " intelligence=", tm.intelligence)

	if not sidebar.has_node("TrapCounterPanel") or not sidebar.has_node("StatsPanel") or not sidebar.has_node("EffectsPanel"):
		push_error("[CAPTURE] FAIL: expected TrapCounterPanel + StatsPanel + EffectsPanel")
		quit(FAIL)
		return
	# Permanent inventory grid must be gone
	if sidebar.has_node("InventoryPanel"):
		push_error("[CAPTURE] FAIL: InventoryPanel should be removed")
		quit(FAIL)
		return
	if tm._stat_bars.size() != 3:
		push_error("[CAPTURE] FAIL: expected 3 stat bars")
		quit(FAIL)
		return
	if not sidebar.has_node("EffectsPanel/VBox/BuffsRow") and tm._buffs_row == null:
		# Effects panel built with dynamic children; check API instead
		pass
	if tm._buffs_row == null or tm._debuffs_row == null:
		push_error("[CAPTURE] FAIL: BuffsRow / DebuffsRow missing")
		quit(FAIL)
		return

	# Setter smoke check
	tm.set_stats(10, 90, 50)
	await process_frame
	if tm.agility != 10 or tm.charisma != 90 or tm.intelligence != 50:
		push_error("[CAPTURE] FAIL: set_stats did not stick")
		quit(FAIL)
		return

	# Buff / debuff icon API smoke — uses real artwork (no letter fallbacks)
	if not ResourceLoader.exists("res://vishnu_demon_possess.png"):
		push_error("[CAPTURE] FAIL: missing res://vishnu_demon_possess.png artwork")
		quit(FAIL)
		return
	if not ResourceLoader.exists("res://pill_bottle.png"):
		push_error("[CAPTURE] FAIL: missing res://pill_bottle.png artwork")
		quit(FAIL)
		return
	tm.add_status_effect("adhd_boost", "buff")  # auto pill art
	tm.add_status_effect("vishnu_demon", "debuff")  # auto vishnu art
	await process_frame
	if not tm.has_status_effect("adhd_boost") or not tm.has_status_effect("vishnu_demon"):
		push_error("[CAPTURE] FAIL: add_status_effect did not stick")
		quit(FAIL)
		return
	if tm._effects.size() != 2:
		push_error("[CAPTURE] FAIL: expected 2 active effects")
		quit(FAIL)
		return
	var vishnu_tex: Texture2D = tm._effects["vishnu_demon"].get("texture") as Texture2D
	if vishnu_tex == null:
		push_error("[CAPTURE] FAIL: vishnu debuff must use artwork, not letter fallback")
		quit(FAIL)
		return
	print("[CAPTURE] effects=", tm._effects.keys(), " vishnu_tex=", vishnu_tex.resource_path)

	# Full viewport screenshot (640x360)
	var vp := root.get_viewport()
	await process_frame
	await process_frame
	var img: Image = vp.get_texture().get_image()
	if img == null:
		push_error("[CAPTURE] FAIL: no viewport image")
		quit(FAIL)
		return
	var err := img.save_png(OUT_PATH)
	var abs_path := ProjectSettings.globalize_path(OUT_PATH)
	print("[CAPTURE] save_png err=", err, " path=", abs_path, " size=", img.get_width(), "x", img.get_height())
	if err != OK:
		push_error("[CAPTURE] FAIL: save_png")
		quit(FAIL)
		return

	# Layout description for humans
	print("[CAPTURE] LAYOUT: top-left sidebar under trap counter")
	print("[CAPTURE]   [TrapCounterPanel] Booby Traps n/3 — gold border dark panel PressStart2P 14")
	print("[CAPTURE]   [StatsPanel] Agility / Charisma / Intelligence — label+value + gold fill bar")
	print("[CAPTURE]   [EffectsPanel] Buffs & Debuffs — icon rows for active status (pill, demon, etc.)")
	print("[CAPTURE]   no permanent InventoryPanel")
	print("[CAPTURE] PASS")
	quit(PASS)
