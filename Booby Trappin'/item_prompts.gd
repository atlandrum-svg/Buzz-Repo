extends Object
## Shared prompt copy. Screen size matched to Laptop (font 48 @ laptop scale ~0.18).

const FONT_SIZE := 48
## LaptopCutOut scale used as reference for on-screen text size
const REF_SCALE := 0.18009868

const TRAP := "Press E to Booby Trap"
const INSPECT_OR_USE := "Press I to Inspect or E to Use"
## Shown once the round's single inspect has been spent.
const USE_ONLY := "Press E to Use"
const TRAP_FOUND := "Trap Found!"
const NO_TRAP := "No Trap Found."
const TRAP_TRIGGERED := "Trap Triggered!"
const USED_NOTHING := "Used %s, Nothing Happened."


static func apply_font(label: Label) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.modulate = Color.WHITE
	label.self_modulate = Color.WHITE
	label.add_theme_color_override("font_color", Color.WHITE)
	# Cancel parent Sprite2D scale so all prompts match laptop on-screen size
	var p = label.get_parent()
	if p is Node2D:
		var s: Vector2 = (p as Node2D).scale
		if absf(s.x) > 0.001 and absf(s.y) > 0.001:
			label.scale = Vector2(REF_SCALE / s.x, REF_SCALE / s.y)


## P2 gets ONE inspect for the whole round. Once it is gone every prop drops
## to a use-only prompt, so the HUD never implies an inspect that is not there.
static func prompt_for(turn_manager) -> String:
	if turn_manager != null and turn_manager.has_method("can_p2_inspect"):
		if not turn_manager.call("can_p2_inspect"):
			return USE_ONLY
	return INSPECT_OR_USE


static func used_nothing(item_name: String) -> String:
	return USED_NOTHING % item_name
