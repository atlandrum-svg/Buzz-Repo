#!/usr/bin/env python3
"""
Date Bout Minigame (Level 3, round 2) - pixel art generator.

Forked from trait_lob_minigame's generator. The palette table and the entire
Canvas class are imported from _lib.py, which is a verbatim copy of the lob's
shared block - the two minigames physically cannot drift apart.

Art direction, and the one rule that matters here: I DO NOT DRAW FACES.
Every previous attempt at a character out of rect()/ellipse() calls read badly
and got cut. So:

  * Player 2 is the real in-game sprite, same as the lob's thrower.
  * The date is a BACKLIT SILHOUETTE - a filled shape with a warm rim, lit from
    a doorway behind her. No interior detail, no face, no expression frames.
    That is a deliberate art choice as much as a capability one: she reads as
    something being judged by, and every scrap of information lives in the
    speech bubble instead.
  * Everything else is architecture, furniture and light, which is what the
    same toolset already did well in the bar.

Outputs:
  out/keyed/*.png      -> game-ready (magenta keyed to alpha)
  out/magenta/*.png    -> source plates on the chroma key
  out/preview.png      -> composited mock of the whole screen

Board geometry below MUST stay in sync with date_bout_minigame.gd.
"""
import math
import os
from PIL import Image

from _lib import (KEY, C, INK, INK2, WALL0, WALL1, WALL2, WALL3, WALL4,
                  GLOW0, GLOW1, GLOW2, GLOW3, GLOW4, GLOW5, CREAM,
                  WOOD0, WOOD1, WOOD2, WOOD3, WOOD4, WOOD5,
                  MET0, MET1, MET2, MET3, MET4, MET5,
                  WINE, WINE2, RED, GOLD, GREEN,
                  Canvas, keyed, sheet, BAYER)

OUT_DIR = "out"
SCALE = 2
DEBUG_GUIDES = False

# ------------------------------------------------- board geometry (board px) --
# Same 548x256 board at 2x as the lob, on purpose: round 1 and round 2 are the
# same evening in the same building and should sit at the same scale.
BOARD_W, BOARD_H = 548, 256

CEILING_Y = 12
FLOOR_Y = 196

# The table is drawn OVER the characters, so both of them read as seated behind
# it. That is why it is a separate plate and not part of the backdrop. Kept
# deliberately shallow - a bistro table, not the bar counter it turned into on
# the first pass.
TABLE_TOP = 166
TABLE_X0, TABLE_X1 = 130, 434
# The plate starts ABOVE the table top so the candle and glasses have somewhere
# to live, and stops well short of the bottom of the screen - the first pass ran
# it to the floor and it read as a bar counter.
TABLE_HEADROOM = 34
TABLE_PLATE_Y = TABLE_TOP - TABLE_HEADROOM
TABLE_PLATE_H = 72

# Player 2: the real sprite at 1:1 board scale, cropped by the table edge.
P2_CELL_X, P2_CELL_Y = 150, 112

# The date, across the table, backlit by the doorway behind her.
DATE_CELL_W, DATE_CELL_H = 86, 78
DATE_X, DATE_Y = 344, 96

# Speech bubble: fixed spot, centred high. A timing game must never make you
# hunt for the thing you are reading.
BUBBLE_CELL_W, BUBBLE_CELL_H = 104, 66
BUBBLE_X, BUBBLE_Y = 246, 22

IMPACT_CELL = 30


# ============================================================== helpers =======
def save(canvas_or_im, name):
    im = canvas_or_im.image() if isinstance(canvas_or_im, Canvas) else canvas_or_im
    os.makedirs(f"{OUT_DIR}/magenta", exist_ok=True)
    os.makedirs(f"{OUT_DIR}/keyed", exist_ok=True)
    im.save(f"{OUT_DIR}/magenta/{name}")
    keyed(im).save(f"{OUT_DIR}/keyed/{name}")
    print(f"  {name}  {im.size[0]}x{im.size[1]}")
    return im


def bottle(c, x, y_base, h, col_a, col_b):
    c.rect(x - 2, y_base - h, x + 2, y_base, col_a)
    c.rect(x - 2, y_base - h, x - 2, y_base, col_b)
    c.rect(x - 1, y_base - h - 3, x, y_base - h, col_b)


def pendant(c, x, shade_w, top=0):
    """Same lamp as the bar, so the two rooms share a light source."""
    c.rect(x - 1, top, x, top + 14, INK)
    c.rect(x, top, x, top + 14, MET2)
    for i in range(10):
        w = 3 + int(shade_w * (i / 9.0) ** 0.8)
        y = top + 14 + i
        c.rect(x - w, y, x + w, y, MET1 if i < 3 else MET2)
        c.set(x - w, y, INK)
        c.set(x + w, y, INK)
    inner = top + 23
    c.rect(x - shade_w, inner, x + shade_w, inner + 1, INK)
    c.ellipse(x, inner + 2, max(3, shade_w // 2), 3, GLOW4)
    c.ellipse(x, inner + 2, max(2, shade_w // 3), 2, GLOW5)
    c.glow(x, inner + 8, shade_w * 3 + 14, GLOW0, 0.55, 2.4)
    c.glow(x, inner + 5, shade_w * 2 + 6, GLOW2, 0.45, 2.2)
    c.glow(x, inner + 3, shade_w + 4, GLOW4, 0.55, 2.0)


# ============================================================== backdrop ======
def build_backdrop():
    """The room behind everything. Characters sit in front of this plate."""
    c = Canvas(BOARD_W, BOARD_H)

    c.vgrad(0, BOARD_W - 1, CEILING_Y, 96, WALL0, WALL2, noise=5)
    c.vgrad(0, BOARD_W - 1, 96, FLOOR_Y - 1, WALL2, WALL3, noise=5)

    # ceiling
    c.vgrad(0, BOARD_W - 1, 0, CEILING_Y - 2, INK, INK2)
    c.hline(0, BOARD_W - 1, CEILING_Y - 2, WOOD1, 2)
    c.hline(0, BOARD_W - 1, CEILING_Y, INK, 1)
    for bx in range(24, BOARD_W, 104):
        c.rect(bx, 0, bx + 6, CEILING_Y - 1, WOOD1)
        c.vline(bx, 0, CEILING_Y - 1, WOOD3, 1)
        c.vline(bx + 6, 0, CEILING_Y - 1, INK, 1)
    c.shade(0, BOARD_W - 1, CEILING_Y + 1, CEILING_Y + 8, INK, 0.22)

    # --- far left: window onto the night, for depth --------------------
    wx0, wy0, wx1, wy1 = 16, 40, 84, 120
    c.vgrad(wx0, wx1, wy0, wy1, C("1A1836"), C("2C2450"))
    for (lx, ly) in ((10, 52), (24, 30), (40, 62), (52, 22), (18, 70),
                     (60, 44), (34, 14), (46, 76)):
        c.rect(wx0 + lx, wy0 + ly, wx0 + lx + 1, wy0 + ly + 1, GOLD)
    c.vline((wx0 + wx1) // 2, wy0, wy1, C("241E42"), 3)
    c.hline(wx0, wx1, (wy0 + wy1) // 2, C("241E42"), 3)
    c.border(wx0, wy0, wx1, wy1, WOOD2, 3)
    c.hline(wx0, wx1, wy0, WOOD4, 1)
    c.border(wx0 - 1, wy0 - 1, wx1 + 1, wy1 + 1, INK, 1)
    c.rect(wx0 - 4, wy1 + 2, wx1 + 4, wy1 + 6, WOOD2)
    c.hline(wx0 - 4, wx1 + 4, wy1 + 2, WOOD4, 1)

    # --- the doorway behind her: this is what makes the silhouette work ---
    dx0, dx1, dy0 = 388, 452, 26
    c.vgrad(dx0, dx1, dy0, FLOOR_Y - 1, GLOW2, GLOW0)
    c.glow((dx0 + dx1) // 2, dy0 + 54, 62, GLOW4, 0.55, 1.7)
    c.glow((dx0 + dx1) // 2, dy0 + 30, 40, GLOW5, 0.40, 1.9)
    c.border(dx0 - 4, dy0 - 4, dx1 + 4, FLOOR_Y - 1, WOOD2, 4)
    c.vline(dx0 - 4, dy0 - 4, FLOOR_Y - 1, WOOD4, 1)
    c.hline(dx0 - 4, dx1 + 4, dy0 - 4, WOOD4, 1)
    c.border(dx0 - 5, dy0 - 5, dx1 + 5, FLOOR_Y - 1, INK, 1)
    # light spilling out of it onto the wall and floor
    c.glow(dx0 - 10, 120, 74, GLOW1, 0.26, 2.2)
    c.glow(dx1 + 12, 130, 60, GLOW1, 0.20, 2.2)

    # --- banquette along the back wall ------------------------------------
    bx0, bx1 = 84, 356
    seat_y = FLOOR_Y - 8
    back_y = FLOOR_Y - 58
    for x in range(bx0, bx1 + 1):
        wob = int(round(0.9 * math.sin((x - bx0) * 0.12)))
        top = back_y + wob
        c.vgrad(x, x, top, seat_y, WINE2, WINE, noise=5)
        c.rect(x, top, x, top + 2, WINE2)
        c.set(x, top - 1, INK)
    c.shade(bx0, bx1, back_y - 2, seat_y, INK, 0.34)
    for ty in range(back_y + 10, seat_y - 10, 11):
        for tx in range(bx0 + 10, bx1 - 6, 14):
            c.set(tx, ty, INK2)
            c.set(tx + 1, ty, WINE2)
    c.vgrad(bx0 - 4, bx1 + 4, seat_y, seat_y + 8, WINE, INK, noise=4)
    c.hline(bx0 - 4, bx1 + 4, seat_y, WINE2, 2)
    c.hline(bx0 - 4, bx1 + 4, seat_y + 8, INK, 2)

    # --- key light straight over the table --------------------------------
    pendant(c, 186, 12, top=CEILING_Y)

    # --- floor -------------------------------------------------------------
    c.vgrad(0, BOARD_W - 1, FLOOR_Y, BOARD_H - 1, WOOD1, WOOD3, noise=6)
    c.hline(0, BOARD_W - 1, FLOOR_Y, INK, 2)
    y, step = FLOOR_Y + 8, 8
    while y < BOARD_H:
        c.hline(0, BOARD_W - 1, int(y), WOOD1, 1)
        off = 0 if int(y) % 2 == 0 else 52
        for x in range(off, BOARD_W, 112):
            c.vline(x, int(y) - step + 2, int(y) - 1, WOOD1, 1)
        y += step
        step += 3
    c.glow(186, FLOOR_Y + 8, 70, GLOW2, 0.30, 2.2)
    c.glow(420, FLOOR_Y + 6, 54, GLOW3, 0.26, 2.2)

    # --- vignette ----------------------------------------------------------
    for yy in range(BOARD_H):
        for xx in range(BOARD_W):
            dxn = (xx - BOARD_W * 0.46) / (BOARD_W * 0.66)
            dyn = (yy - BOARD_H * 0.46) / (BOARD_H * 0.80)
            d = dxn * dxn + dyn * dyn
            if d > 1.0:
                c.blend(xx, yy, INK, min(0.52, (d - 1.0) * 0.72))
    return c


# ================================================================== date ======
def _date_silhouette(c, lean, tilt):
    """One flat shape. What makes a silhouette read as a person is the NECK and
    the SHOULDER LINE - the first pass had neither and came out a peanut. So:
    a clear horizontal shoulder line, a thin neck with daylight either side of
    it, and a nose bump, which is the single strongest cue for which way a head
    is facing."""
    ox = -lean
    base = DATE_CELL_H - 1
    cx = 46 + ox

    # --- torso: shoulders wide, waist narrower, hidden below the table -----
    for i in range(30):
        y = base - i
        w = 23 - int(i * 0.30)
        c.rect(cx - w, y, cx + w, y, INK2)
    # shoulder slope
    for i in range(9):
        y = base - 30 - i
        w = 21 - i * 2
        c.rect(cx - w, y, cx + w, y, INK2)

    # --- arm forward onto the table ---------------------------------------
    for i in range(15):
        c.rect(cx - 26 - i // 2, base - 24 + i // 3,
               cx - 16 - i // 3, base - 16 + i // 3, INK2)

    # --- neck: thin, and the gap either side is what sells the head --------
    neck_y = base - 39
    c.rect(cx - 5, neck_y - 6, cx + 5, neck_y + 2, INK2)

    # --- head -------------------------------------------------------------
    hx = cx - tilt
    hy = neck_y - 18
    c.disc(hx, hy, 12, INK2)
    c.ellipse(hx, hy + 6, 10, 8, INK2)
    # nose + chin, on the left, because she is facing the player
    c.rect(hx - 13, hy + 1, hx - 10, hy + 3, INK2)
    c.ellipse(hx - 8, hy + 9, 5, 4, INK2)
    # hair: a mass behind and below, breaking the circle
    c.ellipse(hx + 3, hy - 4, 15, 13, INK2)
    for i in range(26):
        yy = hy - 4 + i
        w = 7 + int(5 * math.sin(i * 0.12)) - max(0, i - 20)
        if w > 0:
            c.rect(hx + 6, yy, hx + 6 + w, yy, INK2)
    # a loose strand at the front so the outline is not a clean arc
    c.rect(hx - 11, hy - 6, hx - 8, hy + 6, INK2)

    for y in range(c.h):
        for x in range(c.w):
            if c.get(x, y) != KEY:
                c.set(x, y, INK)


def _rim_light(c):
    """Warm edge where the doorway behind her catches her outline."""
    for y in range(c.h):
        run = None
        for x in range(c.w):
            solid = c.get(x, y) != KEY
            if solid and run is None:
                run = x
            if (not solid or x == c.w - 1) and run is not None:
                end = x - 1 if not solid else x
                # right edge = toward the light
                c.set(end, y, GLOW3)
                if end - 1 >= run:
                    c.set(end - 1, y, GLOW1)
                if end - 2 >= run:
                    c.blend(end - 2, y, GLOW0, 0.55)
                # left edge picks up a cold bounce off the window
                c.blend(run, y, C("4B4270"), 0.55)
                run = None
    # a little top light from the pendant
    for x in range(c.w):
        for y in range(c.h):
            if c.get(x, y) != KEY:
                c.blend(x, y, GLOW1, 0.30)
                c.blend(x, y + 1, GLOW0, 0.16)
                break


def build_date():
    """frame 0 neutral, 1 leaning in, 2 rocked back (she faltered)."""
    frames = []
    for (lean, tilt) in ((0, 0), (7, 2), (-5, -3)):
        c = Canvas(DATE_CELL_W, DATE_CELL_H)
        _date_silhouette(c, lean, tilt)
        _rim_light(c)
        frames.append(c)
    return sheet(frames)


# ================================================================= table ======
TABLE_CELL_W = TABLE_X1 - TABLE_X0
TABLE_CELL_H = TABLE_PLATE_H


def build_table():
    """Drawn OVER the characters so they read as seated behind it. All local
    coordinates: `top` is where the table surface sits inside the plate, and
    everything above it is the headroom the candle and glasses stand in."""
    c = Canvas(TABLE_CELL_W, TABLE_CELL_H)
    w = TABLE_CELL_W - 1
    top = TABLE_HEADROOM
    slab = top + 11
    hem = TABLE_CELL_H - 1
    cx = w // 2

    # --- candle, standing on the table -----------------------------------
    c.rect(cx - 3, top - 20, cx + 3, top + 1, C("E4DCBE"))
    c.rect(cx - 3, top - 20, cx - 2, top + 1, CREAM)
    c.rect(cx + 2, top - 20, cx + 3, top + 1, C("9E9478"))
    c.rect(cx - 5, top - 2, cx + 5, top + 1, C("6A5A52"))
    c.rect(cx, top - 23, cx, top - 21, C("6A5A52"))
    c.ellipse(cx, top - 27, 3, 5, GLOW3)
    c.ellipse(cx, top - 28, 2, 4, GLOW4)
    c.ellipse(cx, top - 29, 1, 2, CREAM)

    # --- wine glasses ------------------------------------------------------
    for gx in (cx - 78, cx + 74):
        c.rect(gx - 6, top - 22, gx + 6, top - 20, C("CFE4EA"))
        for i in range(10):
            c.rect(gx - 6 + i // 2, top - 21 + i, gx + 6 - i // 2, top - 21 + i,
                   WINE2 if 3 <= i < 7 else C("9FC0CB"))
        c.rect(gx - 1, top - 11, gx + 1, top - 3, C("CFE4EA"))
        c.rect(gx - 5, top - 3, gx + 5, top + 1, C("9FC0CB"))
        c.set(gx - 5, top - 20, CREAM)
        c.set(gx - 4, top - 19, CREAM)

    c.outline_silhouette(INK)

    # --- the table itself, drawn last so it sits in front of the stems -----
    c.vgrad(0, w, top, slab, C("F4E8C8"), C("BFAC8C"))
    c.hline(0, w, top, CREAM, 1)
    c.hline(0, w, slab, C("6A5A52"), 2)
    c.hline(0, w, slab + 2, INK, 2)
    for i in range(9):
        for y in range(top, slab + 3):
            if (8 - i) > (y - top):
                c.set(i, y, KEY)
                c.set(w - i, y, KEY)

    # cloth, hanging a short way and stopping above the floor line
    c.vgrad(7, w - 7, slab + 4, hem, C("C9B994"), C("4A3C3A"), noise=6)
    for x in range(10, w - 8, 21):
        c.vline(x, slab + 5, hem, C("4A3C3A"), 1)
        c.vline(x + 1, slab + 5, hem, C("D8C9A8"), 1)
    c.shade(7, w - 7, slab + 4, hem, INK, 0.16)
    c.hline(7, w - 7, hem, INK, 1)
    c.vline(7, slab + 4, hem, INK, 1)
    c.vline(w - 7, slab + 4, hem, INK, 1)

    # warm pool from the pendant, on the cloth as well as the top
    c.glow(cx, top + 4, 108, GLOW4, 0.30, 1.9)
    c.glow(cx, top + 3, 56, GLOW5, 0.22, 2.1)
    c.glow(cx, top - 22, 34, GLOW3, 0.34, 1.7)
    return c


# ================================================================ bubble ======
def _bubble_plate(fill, tint):
    """The attack type is communicated by COLOUR, so the plate is tinted right
    through - a near-black bubble with a coloured pinstripe (the first pass)
    is unreadable at speed."""
    c = Canvas(BUBBLE_CELL_W, BUBBLE_CELL_H)
    w, h = BUBBLE_CELL_W - 1, BUBBLE_CELL_H - 1
    body_h = h - 13

    # body, tinted toward the attack colour
    c.vgrad(3, w - 3, 0, body_h, tint, INK)
    c.rect(0, 5, w, body_h - 5, tint)
    c.vgrad(1, w - 1, 5, body_h - 5, tint, INK2)

    # tail hard right and slanting further right, because she is over there
    for i in range(13):
        x0 = w - 26 + i
        c.rect(x0, body_h, x0 + 11 - i, body_h + i, tint)

    c.outline_silhouette(INK)

    # thick coloured frame + bright inner keyline: readable in one glance
    c.border(1, 1, w - 1, body_h - 1, fill, 2)
    c.border(3, 3, w - 3, body_h - 3, INK, 1)
    c.hline(4, w - 4, 4, fill, 1)
    c.hline(4, w - 4, body_h - 5, fill, 1)
    c.glow(w // 2, body_h // 2, 46, fill, 0.16, 1.8)
    return c


def build_bubble():
    """One frame per attack type. Colour IS the read, so it is the loudest
    thing on the plate."""
    frames = []
    for (fill, tint) in ((GOLD, C("4A3A18")), (GLOW3, C("50301C")), (RED, C("4A1C20"))):
        frames.append(_bubble_plate(fill, tint))
    return sheet(frames)


# ================================================================ impact ======
def build_impact():
    frames = []
    for i in range(4):
        c = Canvas(IMPACT_CELL, IMPACT_CELL)
        r = 3 + i * 5
        col = (GLOW5, GLOW3, RED, WINE2)[i]
        c.ring(15, 15, r, 3, col)
        if i < 2:
            c.disc(15, 15, max(1, 3 - i * 2), CREAM)
        for (ax, ay) in ((0, -1), (1, 0), (0, 1), (-1, 0), (1, 1), (-1, -1),
                         (1, -1), (-1, 1)):
            c.rect(15 + ax * (r + 2), 15 + ay * (r + 2),
                   15 + ax * (r + 2) + 1, 15 + ay * (r + 2) + 1, col)
        frames.append(c)
    return sheet(frames)


# =============================================================== preview ======
def build_preview(pieces, player_sheet):
    board = Image.new("RGBA", (BOARD_W, BOARD_H), (0, 0, 0, 255))
    board.alpha_composite(keyed(pieces["db_backdrop.png"]).convert("RGBA"))

    def blit(name, cw, ch, frame, x, y):
        im = keyed(pieces[name]).convert("RGBA")
        board.alpha_composite(im.crop((frame * cw, 0, (frame + 1) * cw, ch)), (x, y))

    blit("db_date.png", DATE_CELL_W, DATE_CELL_H, 1, DATE_X, DATE_Y)

    if player_sheet and os.path.exists(player_sheet):
        ps = Image.open(player_sheet).convert("RGBA")
        cw, ch = ps.size[0] // 4, ps.size[1] // 4
        cell = ps.crop((0, ch * 2, cw, ch * 3))
        board.alpha_composite(cell, (P2_CELL_X, P2_CELL_Y))

    board.alpha_composite(keyed(pieces["db_table.png"]).convert("RGBA"),
                          (TABLE_X0, TABLE_PLATE_Y))
    blit("db_bubble.png", BUBBLE_CELL_W, BUBBLE_CELL_H, 1, BUBBLE_X, BUBBLE_Y)

    big = board.resize((BOARD_W * SCALE, BOARD_H * SCALE), Image.NEAREST)
    os.makedirs(OUT_DIR, exist_ok=True)
    big.save(f"{OUT_DIR}/preview_raw.png")
    print(f"  preview_raw.png  {big.size[0]}x{big.size[1]}")
    return big


def main():
    with open(".gdignore", "w"):
        pass
    print("Date Bout art:")
    pieces = {}
    pieces["db_backdrop.png"] = save(build_backdrop(), "db_backdrop.png")
    pieces["db_date.png"] = save(build_date(), "db_date.png")
    pieces["db_table.png"] = save(build_table(), "db_table.png")
    pieces["db_bubble.png"] = save(build_bubble(), "db_bubble.png")
    pieces["db_impact.png"] = save(build_impact(), "db_impact.png")
    build_preview(pieces, "../../julian assange sprite sheet black.png")
    print("done -> out/keyed/*.png")


if __name__ == "__main__":
    main()


# ========================================================== ending icons ======
# Authored at 16x16 and nearest-upscaled to 64, which is exactly how the chunky
# existing icon_*.png files are built. These land in res:// alongside them.
def _ic(draw_fn):
    c = Canvas(16, 16)
    draw_fn(c)
    return c.image().resize((64, 64), Image.NEAREST)


def _icon_second_date(c):
    for (ox, oy, col) in ((1, 1, C("8C2E48")), (0, 0, RED)):
        for (hx, hy) in ((5, 5), (10, 5)):
            c.disc(hx + ox, hy + oy, 3, col)
        for i in range(7):
            c.rect(4 + i // 2 + ox, 8 + i + oy, 11 - i // 2 + ox, 8 + i + oy, col)
    c.rect(6, 4, 7, 5, C("FFB0C0"))
    c.rect(2, 2, 3, 3, GOLD)
    c.rect(12, 3, 13, 4, GOLD)


def _icon_left_on_read(c):
    c.rect(4, 1, 11, 14, C("4E4A5C"))
    c.rect(5, 3, 10, 11, C("9FC0CB"))
    c.rect(5, 3, 10, 4, C("CFE4EA"))
    c.rect(4, 1, 11, 2, C("35323F"))
    c.rect(4, 12, 11, 14, C("35323F"))
    for x in (6, 8, 10):
        c.rect(x - 1, 7, x, 8, C("35323F"))
    c.rect(12, 4, 14, 5, GREY) if False else None
    c.rect(2, 5, 3, 6, C("6E6A80"))


def _icon_ghosted(c):
    c.disc(8, 6, 5, C("C6C3D6"))
    c.rect(3, 6, 13, 12, C("C6C3D6"))
    for i, x in enumerate(range(3, 14, 3)):
        c.rect(x, 12, x + 1, 14 - (i % 2) * 2, C("C6C3D6"))
    c.rect(6, 5, 7, 7, INK)
    c.rect(10, 5, 11, 7, INK)
    c.rect(7, 9, 9, 10, INK)
    c.rect(4, 3, 5, 4, C("F0EEF8"))


def _icon_meltdown(c):
    c.disc(8, 8, 6, C("EFA660"))
    c.rect(5, 5, 6, 7, INK)
    c.rect(10, 5, 11, 7, INK)
    c.ellipse(8, 11, 3, 2, INK)
    for (x, y) in ((2, 2), (13, 2), (1, 8), (14, 8), (3, 13), (12, 13)):
        c.rect(x, y, x + 1, y + 1, RED)
    c.rect(7, 0, 8, 2, C("A5545C"))


ENDING_ICONS = {
    "icon_second_date.png": _icon_second_date,
    "icon_left_on_read.png": _icon_left_on_read,
    "icon_ghosted.png": _icon_ghosted,
    "icon_meltdown.png": _icon_meltdown,
}


def build_ending_icons():
    os.makedirs(f"{OUT_DIR}/icons", exist_ok=True)
    for name, fn in ENDING_ICONS.items():
        im = keyed(_ic(fn))
        im.save(f"{OUT_DIR}/icons/{name}")
        print(f"  {name}  {im.size[0]}x{im.size[1]}  (-> res:// root)")
