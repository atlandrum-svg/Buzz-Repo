extends "res://arrival_npc.gd"
## Officer Bramm. Arrives when the booby-trapped laptop pulled illegal material
## down onto your machine. Outranks every other arrival: if the cops are coming,
## nobody else gets to be the problem this round.
## Walks in faster than the fireman — he knows exactly which door he wants.


func _ready() -> void:
	tex_normal = "res://police.png"
	tex_zombie = "res://police_zombie_sheet.png"
	tex_headless = "res://police_headless.png"
	tex_crawl = "res://police_crawl_sheet.png"
	walk_speed_base = 80.0
	super._ready()
