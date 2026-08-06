DATE BOUT MINIGAME — ART SOURCE  (Level 3, round 2)
====================================================

../db_*.png are the game-ready sprites: pure magenta (#FF00FF) keyed to alpha.

  python gen_art.py

writes out/magenta/, out/keyed/, out/preview_raw.png and out/icons/. Copy
out/keyed/*.png over ../db_*.png, and out/icons/*.png into res:// root.

_lib.py is a VERBATIM copy of the palette table and Canvas class from
trait_lob_minigame/_src_magenta/gen_art.py. It is imported rather than
duplicated so the two minigames physically cannot drift apart. If you retune
the palette, do it in the lob's generator and re-copy that block here.

THE ONE ART RULE: no faces are drawn procedurally.
  * Player 2 is the real in-game sprite (julian assange sheet, frame 8).
  * The date is a BACKLIT SILHOUETTE lit from the doorway behind her - one flat
    shape, a warm rim, no interior detail. Three poses: neutral, leaning in,
    rocked back. What makes a silhouette read as a person is the NECK and the
    SHOULDER LINE, not the outline of a face.
  * Everything else is architecture, furniture and light.

Drop-in replacement: any db_*.png can be swapped for hand-drawn or commissioned
art without touching the GDScript, as long as the cell sizes below hold. The
loader falls back to a raw Image.load() if a file has not been imported yet.

SHEET LAYOUT (frames laid out horizontally, cell sizes fixed)
--------------------------------------------------------------
  db_backdrop.png   548 x 256   single frame, the room behind everything
  db_date.png        86 x  78   3 frames: neutral, leaning in, faltered
  db_table.png      304 x  72   single frame, drawn OVER both characters
  db_bubble.png     104 x  66   3 frames: probe (gold), dig (orange), direct (red)
  db_impact.png      30 x  30   4 frames, hit burst

BOARD GEOMETRY - must match date_bout_minigame.gd exactly
----------------------------------------------------------
  BOARD          548 x 256, drawn at SCALE 2 (1096 x 512 on screen)
  CEILING_Y       12      FLOOR_Y        196
  TABLE_TOP      166      TABLE_X0..X1   130..434
  TABLE_PLATE_Y  132      (table plate starts above the top, so the candle and
                           glasses have headroom to stand in)
  P2 cell at     (150, 112)
  DATE cell at   (344,  96)
  BUBBLE cell at (246,  22), body height 53 (the rest is the tail)

ENDING ICONS
------------
out/icons/*.png are authored at 16x16 and nearest-upscaled to 64, which is how
the chunky existing icon_*.png files are built. They belong in res:// root
alongside the other trait icons, not in this folder.
