extends Object
## Shared prompt copy. Screen size matched to Laptop (font 48 @ laptop scale ~0.18).

const FONT_SIZE := 48
## LaptopCutOut scale used as reference for on-screen text size
const REF_SCALE := 0.18009868

const TRAP := "Press E to Booby Trap"
const INSPECT_OR_USE := "Press I to Inspect or E to Use"
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


static func used_nothing(item_name: String) -> String:
	return USED_NOTHING % item_name
