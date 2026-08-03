extends SceneTree
## DEPRECATED as a test entrypoint.
##
## Karen review: automation must use the normal game CLI boot path, not a
## script that re-applies bookmarks. Use instead:
##
##   godot --headless --path . -- --bookmark=mid_game --dev-assert --dev-quit
##   godot --path . -- --bookmark=plant_monster --dev-capture=PATH --dev-quit
##
## This file exits 1 if invoked, so it cannot false-pass.


func _initialize() -> void:
	push_error("[DEV] _dev_bookmark_capture.gd is retired. Use normal boot:")
	push_error("[DEV]   godot --path . -- --bookmark=NAME --dev-assert --dev-quit")
	quit(1)
