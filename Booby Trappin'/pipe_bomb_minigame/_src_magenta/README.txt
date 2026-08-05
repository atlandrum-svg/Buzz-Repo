PIPE BOMB MINIGAME — ART SOURCE
===============================

The PNGs one folder up (../pb_*.png) are the game-ready sprites: pure magenta
(#FF00FF) already keyed out to alpha.

The PNGs in THIS folder are the un-keyed source plates, still sitting on the
chroma key, matching the project's art contract:

  * 16-bit chunky pixels, 2px minimum feature size
  * thick #272736 outlines on every silhouette
  * warm room palette lifted straight out of "Room Cleaned 1.png"
  * authored on pure magenta, keyed on export

gen_art.py regenerates both sets:

    python gen_art.py          # writes out/magenta/ and out/keyed/

Edit the palette table or the build_* functions in that file to retune the art,
then copy out/keyed/*.png back over ../pb_*.png.

This folder contains a .gdignore file, so Godot skips it entirely — the source
plates and the script never get imported as game resources.

SPRITE SHEET LAYOUT (all frames laid out horizontally, cell sizes fixed)
-----------------------------------------------------------------------
  pb_board.png      176 x 152   single frame, the detonator board backdrop
  pb_terminals.png   24 x  24   12 frames: colour*2 + (0 = dim, 1 = live)
  pb_clamp.png       52 x  30    6 frames, one per wire colour
  pb_wirestub.png    26 x  14    6 frames, one per wire colour
  pb_spark.png       30 x  30    5 frames, spark burst
  pb_flame.png       16 x  18    4 frames, fuse flame loop
  pb_bomb_icon.png   34 x  24   single frame, header glyph

Wire colour order (index 0..5) is RED, BLUE, YELLOW, GREEN, WHITE, PINK and
MUST stay in sync with WIRE_COLORS / WIRE_NAMES in pipe_bomb_minigame.gd.

Board-space geometry the script depends on (see gen_art.py constants):
  RAIL_CX  = 119   terminal centre column
  RAIL_TOP =  16   clamp travel top
  RAIL_BOT = 136   clamp travel bottom
  clamp contact point inside its sprite = (48, 15)
