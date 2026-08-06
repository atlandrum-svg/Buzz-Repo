TRAIT LOB MINIGAME — ART SOURCE  (Level 3, the date)
====================================================

The PNGs one folder up (../tl_*.png) are the game-ready sprites: pure magenta
(#FF00FF) already keyed out to alpha.

The PNGs in THIS folder are the un-keyed source plates, still sitting on the
chroma key, matching the project's art contract:

  * 16-bit chunky pixels, 2px minimum feature size
  * thick #272736 outlines on every silhouette
  * warm room palette lifted straight out of "Room Cleaned 1.png"
  * authored on pure magenta, keyed on export

gen_art.py regenerates everything:

    python gen_art.py          # writes out/magenta/, out/keyed/, out/preview.png

out/preview.png composites the whole play field at 3x with the zone hit rects
drawn in, plus the solved trajectory for zone A. Look at that before opening
Godot — it catches layout mistakes in seconds.

Edit the palette table or the build_* functions to retune the art, then copy
out/keyed/*.png back over ../tl_*.png.

Both this folder and the parent contain a .gdignore, so Godot skips the source
plates entirely.

SPRITE SHEET LAYOUT (frames laid out horizontally, cell sizes fixed)
--------------------------------------------------------------------
  tl_backdrop.png     304 x 168   single frame, the venue
  tl_launcher.png      44 x  52   3 frames: idle, wound back, released
  tl_zone_bag.png      46 x  32   2 frames: open, stuffed        (zone A)
  tl_zone_plant.png    46 x  32   2 frames: normal, something buried in it (zone B)
  tl_bucket.png        62 x  38   2 frames: empty, overflowing
  tl_date.png          38 x  48   2 frames: idle, blink
  tl_dot.png            6 x   6   2 frames: bright, dim (trajectory preview)
  tl_puff.png          26 x  26   4 frames, landing puff

BOARD GEOMETRY — must match trait_lob_minigame.gd exactly
---------------------------------------------------------
  BOARD          304 x 168, drawn at SCALE 3 (912 x 504 on screen)
  FLOOR_Y        140
  LAUNCH         (30, 120)     release point, also LAUNCH_TIP in the sprite
  SHELF          x 176..302, top surface y 64, underside y 72
  ZONE A (bag)   x 186, y 36, 42 x 28
  ZONE B (plant) x 248, y 36, 42 x 28
  BUCKET         x 118, y 106, 58 x 34
  DATE           x 258, y  94

Trait icons are the project's existing 64x64 icon_*.png files, drawn 1:1 in
flight so they stay pixel-crisp.
