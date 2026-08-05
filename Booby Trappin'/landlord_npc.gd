extends "res://arrival_npc.gd"
## The landlord. Shows up on a quiet round — no explosion, no illegal download,
## so nobody official was called and he is here about the rent on his own time.
## Slower than the others: he is in no hurry and he is not fit.


func _ready() -> void:
	tex_normal = "res://landlord.png"
	tex_zombie = "res://landlord_zombie_sheet.png"
	tex_headless = "res://landlord_headless.png"
	tex_crawl = "res://landlord_crawl_sheet.png"
	walk_speed_base = 62.0
	super._ready()
