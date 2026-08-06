Flamethrower flame VFX sprite sheet
=====================================
Pixel-art long horizontal fire jet (no flamethrower weapon).
Transparent background (chroma keyed).

Frames: 7 left-to-right loop
Main sheet: flamethrower_flame_sheet.png
  cell=246x128  sheet=1722x128
Compact: flamethrower_flame_sheet_compact.png
  cell=186x96  sheet=1302x96
Individual: frames/flame_00.png .. flame_06.png

Intended playback: 10-12 fps, loop
Godot: Texture2D, filter=Nearest; AnimatedSprite2D AtlasTextures
  region width = cell width above.
