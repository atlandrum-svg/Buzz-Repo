extends RefCounted
## Named jump points for debug / agent testing.
## Edit BOOKMARKS below — one dict per bookmark. See DEV_MODE.md.

## Each bookmark may include:
##   turn: "Player1" | "Player2"
##   traps_left: int (P1 remaining placements, 0..3)
##   p2_items_used: int
##   p1_pos / p2_pos: Vector2 global positions
##   prop_traps: { "plant"|"dresser"|"laptop"|"pill": bool }
##   inventory_pills: Array of bool (true = trapped bottle)
##   trigger: optional anim id after apply
##     "plant_monster" | "dresser_bomb" | "p2_cartwheel" | ""

const BOOKMARKS := {
	## Fresh game — P1 full traps, players near room center.
	"start": {
		"label": "Start of game",
		"turn": "Player1",
		"traps_left": 3,
		"p2_items_used": 0,
		"p1_pos": Vector2(20, 100),
		"p2_pos": Vector2(50, 100),
		"prop_traps": {
			"plant": false,
			"dresser": false,
			"laptop": false,
			"pill": false,
		},
		"inventory_pills": [],
		"trigger": "",
	},
	## P1 mid trap-setup — one trap already on plant, 2 left, near dresser.
	"trap_placement": {
		"label": "Trap placement (plant armed)",
		"turn": "Player1",
		"traps_left": 2,
		"p2_items_used": 0,
		"p1_pos": Vector2(-140, -90),
		"p2_pos": Vector2(50, 100),
		"prop_traps": {
			"plant": true,
			"dresser": false,
			"laptop": false,
			"pill": false,
		},
		"inventory_pills": [],
		"trigger": "",
	},
	## Mid-game P2 turn — plant + dresser trapped, P2 near plant, clean pill in inv.
	"mid_game": {
		"label": "Mid-game P2 inspect",
		"turn": "Player2",
		"traps_left": 0,
		"p2_items_used": 0,
		"p1_pos": Vector2(20, 100),
		"p2_pos": Vector2(120, -160),
		"prop_traps": {
			"plant": true,
			"dresser": true,
			"laptop": false,
			"pill": false,
		},
		"inventory_pills": [false],
		"trigger": "",
	},
	## Jump next to plant and play monster animation (for anim PR screenshots).
	"plant_monster": {
		"label": "Plant monster anim",
		"turn": "Player2",
		"traps_left": 0,
		"p2_items_used": 0,
		"p1_pos": Vector2(20, 100),
		"p2_pos": Vector2(140, -180),
		"prop_traps": {
			"plant": true,
			"dresser": false,
			"laptop": false,
			"pill": false,
		},
		"inventory_pills": [],
		"trigger": "plant_monster",
	},
	## Near dresser, trigger pipe-bomb eject + explosion anim.
	"dresser_bomb": {
		"label": "Dresser pipe bomb",
		"turn": "Player2",
		"traps_left": 0,
		"p2_items_used": 1,
		"p1_pos": Vector2(20, 100),
		"p2_pos": Vector2(-150, -100),
		"prop_traps": {
			"plant": false,
			"dresser": true,
			"laptop": false,
			"pill": false,
		},
		"inventory_pills": [],
		"trigger": "dresser_bomb",
	},
	## P2 cartwheel blast (knockback anim).
	"p2_cartwheel": {
		"label": "P2 cartwheel blast",
		"turn": "Player2",
		"traps_left": 0,
		"p2_items_used": 0,
		"p1_pos": Vector2(20, 100),
		"p2_pos": Vector2(0, 80),
		"prop_traps": {
			"plant": false,
			"dresser": false,
			"laptop": false,
			"pill": false,
		},
		"inventory_pills": [],
		"trigger": "p2_cartwheel",
	},
}


static func names() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k in BOOKMARKS.keys():
		out.append(String(k))
	out.sort()
	return out


static func get_bookmark(name: String) -> Dictionary:
	if BOOKMARKS.has(name):
		return BOOKMARKS[name]
	return {}


static func has_bookmark(name: String) -> bool:
	return BOOKMARKS.has(name)
