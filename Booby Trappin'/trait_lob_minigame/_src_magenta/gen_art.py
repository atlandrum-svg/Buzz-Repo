#!/usr/bin/env python3
"""
Trait Lob Minigame (Level 3 - The Date) - pixel art generator.

Look we are going for: Worms W.M.D. Painterly depth, soft light falloff, real
colour ramps, organic silhouettes - but authored as honest pixel art so it sits
next to "Room Cleaned 1.png" instead of fighting it. The rules that get us
there and away from the flat-rectangle look:

  * every material gets a 4-6 step ramp, never a single flat fill
  * transitions are Bayer-dithered, not hard-banded
  * one warm key light (the pendant lamps) - everything shades away from it
  * silhouettes wobble; nothing that should be organic is a clean rectangle
  * thick #1B1020 outlines on foreground objects, thinner further back
  * three depth planes, each hazed toward the wall colour

Authored on PURE MAGENTA (#FF00FF) chroma key, keyed to alpha on export.

Outputs:
  out/keyed/*.png      -> game-ready (magenta keyed to alpha)
  out/magenta/*.png    -> source plates on the chroma key
  out/preview.png      -> composited mock of the play field, for eyeballing

Board geometry constants below MUST stay in sync with trait_lob_minigame.gd.
"""
import math
import os
from PIL import Image

# ---------------------------------------------------------------- palette ----
KEY = (255, 0, 255, 255)


def C(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


INK = C("1B1020")
INK2 = C("271A33")
WALL0 = C("241430")
WALL1 = C("32193C")
WALL2 = C("42204A")
WALL3 = C("552A56")
WALL4 = C("6B3663")
GLOW0 = C("7A3F5E")
GLOW1 = C("A5545C")
GLOW2 = C("C87A55")
GLOW3 = C("EFA660")
GLOW4 = C("FFD07A")
GLOW5 = C("FFF0C0")
CREAM = C("FFFFEB")
WOOD0 = C("2A1620")
WOOD1 = C("40222A")
WOOD2 = C("5C3229")
WOOD3 = C("7C4830")
WOOD4 = C("9E6238")
WOOD5 = C("C08A55")
MET0 = C("1F1C2C")
MET1 = C("35323F")
MET2 = C("4E4A5C")
MET3 = C("6E6A80")
MET4 = C("9A97AC")
MET5 = C("C6C3D6")
WINE = C("6A1F3A")
WINE2 = C("8C2E48")
RED = C("E36956")
GOLD = C("FFE478")
GREEN = C("3CA370")

OUT_DIR = "out"
SCALE = 2
# Draw the holder hit rects over the preview. Off for judging the art.
DEBUG_GUIDES = False

# ------------------------------------------------- board geometry (board px) --
# Mirrored as constants in trait_lob_minigame.gd. Change both together.
# A long, low room: nearly 2.2:1, so the lob has real distance to cover.
BOARD_W, BOARD_H = 548, 256

CEILING_Y = 14                # SOLID - a lob that climbs too high bounces off
FLOOR_Y = 208                 # top surface of the floor, where misses settle

LAUNCH_X, LAUNCH_Y = 54, 176  # the point a trait leaves the thrower's hand

# ONE square socket, set flush into the very top-right corner. You do not lob
# into this from above - you stick it, flat and fast, like an arrow. The
# interior is exactly one icon square (13 units = 26 screen px), so a hit fills
# it perfectly.
SOCKET_OUTER = 15
SOCKET_RIM = 1
SOCKET_X, SOCKET_Y = 526, 20  # 7 units off the right wall, 6 below the ceiling

# The socket RELOCATES every throw, so it carries its own bevel and drop shadow
# and nothing about it is baked into the wall. This is the box it may appear in
# - the bottom edge stops short of the mirror so it never sits on top of it.
ROAM_X0, ROAM_X1 = 396, 528
ROAM_Y0, ROAM_Y1 = 18, 66

# The rack is gone; a mirror fills the wall where it used to hang.
MIRROR_X0, MIRROR_X1 = 300, 430
MIRROR_Y0, MIRROR_Y1 = 84, 148

STAND_X = 50                  # where the player sprite stands


# ------------------------------------------------------------- primitives ----
BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[KEY for _ in range(w)] for _ in range(h)]

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[y][x]
        return KEY

    def rect(self, x0, y0, x1, y1, c):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self.set(x, y, c)

    def hline(self, x0, x1, y, c, t=1):
        for i in range(t):
            self.rect(x0, y + i, x1, y + i, c)

    def vline(self, x, y0, y1, c, t=1):
        for i in range(t):
            self.rect(x + i, y0, x + i, y1, c)

    def border(self, x0, y0, x1, y1, c, t=2):
        for i in range(t):
            self.hline(x0 + i, x1 - i, y0 + i, c)
            self.hline(x0 + i, x1 - i, y1 - i, c)
            self.vline(x0 + i, y0 + i, y1 - i, c)
            self.vline(x1 - i, y0 + i, y1 - i, c)

    def disc(self, cx, cy, r, c):
        rr = (r + 0.35) ** 2
        for y in range(int(cy - r - 1), int(cy + r + 2)):
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                if (x - cx) ** 2 + (y - cy) ** 2 <= rr:
                    self.set(x, y, c)

    def ring(self, cx, cy, r, t, c):
        outer = (r + 0.35) ** 2
        inner = (r - t + 0.35) ** 2
        for y in range(int(cy - r - 1), int(cy + r + 2)):
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                d = (x - cx) ** 2 + (y - cy) ** 2
                if inner < d <= outer:
                    self.set(x, y, c)

    def ellipse(self, cx, cy, rx, ry, c):
        if rx <= 0 or ry <= 0:
            return
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.08:
                    self.set(x, y, c)

    # ---- shading: real colour blending, dither only as fine texture -------
    def blend(self, x, y, c, a):
        """Alpha-blend c over whatever is already there. a in 0..1."""
        if a <= 0.0:
            return
        cur = self.get(x, y)
        if cur == KEY:
            return   # never light up transparency - it will not key out
        a = min(1.0, a)
        r, g, b, _ = cur
        self.set(x, y, (int(r + (c[0] - r) * a),
                        int(g + (c[1] - g) * a),
                        int(b + (c[2] - b) * a), 255))

    def vgrad(self, x0, x1, y0, y1, c_from, c_to, noise=0.0):
        """Smooth vertical ramp. `noise` adds a faint Bayer grain, not banding."""
        span = max(1, y1 - y0)
        for y in range(int(y0), int(y1) + 1):
            t = (y - y0) / span
            base = tuple(int(c_from[i] + (c_to[i] - c_from[i]) * t) for i in range(3))
            for x in range(int(x0), int(x1) + 1):
                if noise > 0.0:
                    n = ((BAYER[y % 4][x % 4] / 15.0) - 0.5) * noise
                    col = tuple(max(0, min(255, int(base[i] + n))) for i in range(3))
                else:
                    col = base
                self.set(x, y, (col[0], col[1], col[2], 255))

    def glow(self, cx, cy, r, c, strength=1.0, falloff=2.0):
        """Soft radial light. Blended, so no halftone screen-door."""
        for y in range(int(cy - r - 1), int(cy + r + 2)):
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                d = math.hypot(x - cx, y - cy) / max(1e-5, r)
                if d >= 1.0:
                    continue
                self.blend(x, y, c, strength * (1.0 - d) ** falloff)

    def shade(self, x0, x1, y0, y1, c, a):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self.blend(x, y, c, a)

    def outline_silhouette(self, c=INK):
        src = [row[:] for row in self.px]
        for y in range(self.h):
            for x in range(self.w):
                if src[y][x] != KEY:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.w and 0 <= ny < self.h and src[ny][nx] != KEY:
                        self.px[y][x] = c
                        break

    def image(self):
        im = Image.new("RGBA", (self.w, self.h))
        im.putdata([self.px[y][x] for y in range(self.h) for x in range(self.w)])
        return im


def keyed(im):
    out = im.copy()
    d = list(out.getdata())
    d = [(0, 0, 0, 0) if (p[0] == 255 and p[1] == 0 and p[2] == 255) else p for p in d]
    out.putdata(d)
    return out


def save(canvas_or_im, name):
    im = canvas_or_im.image() if isinstance(canvas_or_im, Canvas) else canvas_or_im
    os.makedirs(f"{OUT_DIR}/magenta", exist_ok=True)
    os.makedirs(f"{OUT_DIR}/keyed", exist_ok=True)
    im.save(f"{OUT_DIR}/magenta/{name}")
    keyed(im).save(f"{OUT_DIR}/keyed/{name}")
    print(f"  {name}  {im.size[0]}x{im.size[1]}")
    return im


def sheet(frames):
    w = sum(f.w for f in frames)
    h = max(f.h for f in frames)
    im = Image.new("RGBA", (w, h), KEY)
    x = 0
    for f in frames:
        im.paste(f.image(), (x, 0))
        x += f.w
    return im


# =============================================================== backdrop =====
def pendant(c, x, shade_w, top=0):
    """Hanging lamp: cord, shade, bulb, and the light pool it throws."""
    c.rect(x - 1, top, x, top + 16, INK)
    c.rect(x, top, x, top + 16, MET2)
    for i in range(10):
        w = 3 + int(shade_w * (i / 9.0) ** 0.8)
        y = top + 16 + i
        c.rect(x - w, y, x + w, y, MET1 if i < 3 else MET2)
        c.set(x - w, y, INK)
        c.set(x + w, y, INK)
    inner_y = top + 25
    c.rect(x - shade_w, inner_y, x + shade_w, inner_y + 1, INK)
    c.ellipse(x, inner_y + 2, max(3, shade_w // 2), 3, GLOW4)
    c.ellipse(x, inner_y + 2, max(2, shade_w // 3), 2, GLOW5)
    c.glow(x, inner_y + 8, shade_w * 3 + 14, GLOW0, 0.55, 2.4)
    c.glow(x, inner_y + 5, shade_w * 2 + 6, GLOW2, 0.45, 2.2)
    c.glow(x, inner_y + 3, shade_w + 4, GLOW4, 0.55, 2.0)


def bottle(c, x, y_base, h, col_a, col_b):
    """Back-bar bottle. Deliberately small and hazy - it is set dressing."""
    w = 2
    c.rect(x - w, y_base - h, x + w, y_base, col_a)
    c.rect(x - w, y_base - h, x - w, y_base, col_b)
    c.rect(x - 1, y_base - h - 3, x, y_base - h, col_b)
    c.set(x + w, y_base - h, INK2)


def build_backdrop():
    """A long, dim cocktail bar. Same language as before - three depth planes,
    one warm key light, real ramps - just laid out for a room twice as wide,
    with a hard ceiling the lob can actually hit."""
    c = Canvas(BOARD_W, BOARD_H)

    # ---- plane 1: back wall ---------------------------------------------
    c.vgrad(0, BOARD_W - 1, CEILING_Y, 110, WALL0, WALL2, noise=5)
    c.vgrad(0, BOARD_W - 1, 110, FLOOR_Y - 1, WALL2, WALL3, noise=5)

    # ---- the ceiling: solid, and it needs to LOOK solid ------------------
    c.vgrad(0, BOARD_W - 1, 0, CEILING_Y - 3, INK, INK2)
    c.hline(0, BOARD_W - 1, CEILING_Y - 3, WOOD1, 2)
    c.hline(0, BOARD_W - 1, CEILING_Y - 1, WOOD3, 1)
    c.hline(0, BOARD_W - 1, CEILING_Y, INK, 1)
    # cross beams, so the ceiling reads as a surface rather than a border
    for bx in range(30, BOARD_W, 96):
        c.rect(bx, 0, bx + 7, CEILING_Y - 1, WOOD1)
        c.vline(bx, 0, CEILING_Y - 1, WOOD3, 1)
        c.vline(bx + 7, 0, CEILING_Y - 1, INK, 1)
    c.shade(0, BOARD_W - 1, CEILING_Y + 1, CEILING_Y + 9, INK, 0.22)

    # ---- plane 1: dado rail ----------------------------------------------
    rail = FLOOR_Y - 18
    c.rect(0, rail, BOARD_W - 1, rail + 5, WOOD2)
    c.hline(0, BOARD_W - 1, rail, WOOD4, 1)
    c.hline(0, BOARD_W - 1, rail + 5, INK2, 2)

    # ---- plane 2: back bar, left of centre --------------------------------
    bar_x0, bar_x1 = 150, 300
    bar_y = 152
    c.shade(bar_x0, bar_x1, bar_y - 46, bar_y, INK, 0.20)
    c.hline(bar_x0, bar_x1, bar_y - 46, WALL3, 2)
    for i, bx in enumerate(range(bar_x0 + 9, bar_x1 - 6, 11)):
        bottle(c, bx, bar_y - 26, 10 + (i % 3) * 4, WALL2, WALL3)
    c.hline(bar_x0, bar_x1, bar_y - 24, WALL4, 1)
    for i, bx in enumerate(range(bar_x0 + 14, bar_x1 - 6, 12)):
        bottle(c, bx, bar_y - 3, 8 + (i % 4) * 3, WALL2, WALL3)
    c.vgrad(bar_x0, bar_x1, bar_y, bar_y + 7, WOOD3, WOOD1)
    c.hline(bar_x0, bar_x1, bar_y, WOOD5, 1)
    c.hline(bar_x0, bar_x1, bar_y + 7, INK2, 2)

    # ---- key light: pendants hanging off the ceiling ----------------------
    pendant(c, 92, 13, top=CEILING_Y)
    pendant(c, 214, 9, top=CEILING_Y)
    pendant(c, 436, 8, top=CEILING_Y)

    # ---- plane 2: banquette booth, right of the bar -----------------------
    bx0, bx1 = 320, 500
    seat_y = FLOOR_Y - 6
    back_y = FLOOR_Y - 42
    for x in range(bx0, bx1 + 1):
        wob = int(round(0.9 * math.sin((x - bx0) * 0.13)))
        top = back_y + wob
        c.vgrad(x, x, top, seat_y, WINE2, WINE, noise=5)
        c.rect(x, top, x, top + 2, WINE2)
        c.set(x, top - 1, INK)
    c.shade(bx0, bx1, back_y - 2, seat_y, INK, 0.30)
    for i in range(24):
        c.shade(bx1 - i, bx1 - i, back_y - 2, seat_y + 8, INK, 0.018 * (24 - i))
    for ty in range(back_y + 9, seat_y - 10, 10):
        for tx in range(bx0 + 9, bx1 - 6, 13):
            c.set(tx, ty, INK2)
            c.set(tx + 1, ty, WINE2)
    c.vgrad(bx0 - 4, bx1 + 4, seat_y, seat_y + 8, WINE, INK, noise=4)
    c.hline(bx0 - 4, bx1 + 4, seat_y, WINE2, 2)
    c.hline(bx0 - 4, bx1 + 4, seat_y + 8, INK, 2)
    c.vline(bx0 - 4, seat_y, seat_y + 8, INK, 2)
    c.vline(bx1 + 4, seat_y, seat_y + 8, INK, 2)

    # ---- far right: a doorway, for depth ----------------------------------
    dx0, dx1, dy0 = 500, 534, 120
    c.vgrad(dx0, dx1, dy0, FLOOR_Y - 1, INK2, INK)
    c.border(dx0 - 3, dy0 - 3, dx1 + 3, FLOOR_Y - 1, WOOD2, 3)
    c.vline(dx0 - 3, dy0 - 3, FLOOR_Y - 1, WOOD4, 1)
    c.glow(int((dx0 + dx1) * 0.5), dy0 + 18, 26, GLOW1, 0.30, 2.0)

    # ---- plane 3: floor ---------------------------------------------------
    c.vgrad(0, BOARD_W - 1, FLOOR_Y, BOARD_H - 1, WOOD1, WOOD3, noise=6)
    c.hline(0, BOARD_W - 1, FLOOR_Y, INK, 2)
    y = FLOOR_Y + 8
    step = 8
    while y < BOARD_H:
        c.hline(0, BOARD_W - 1, int(y), WOOD1, 1)
        off = 0 if int(y) % 2 == 0 else 52
        for x in range(off, BOARD_W, 112):
            c.vline(x, int(y) - step + 2, int(y) - 1, WOOD1, 1)
        y += step
        step += 3
    c.glow(92, FLOOR_Y + 12, 84, GLOW2, 0.34, 2.2)
    c.glow(214, FLOOR_Y + 10, 56, GLOW2, 0.24, 2.4)
    c.glow(436, FLOOR_Y + 10, 48, GLOW2, 0.20, 2.4)
    c.glow(92, FLOOR_Y + 7, 40, GLOW3, 0.26, 2.6)

    # ---- vignette ---------------------------------------------------------
    for yy in range(BOARD_H):
        for xx in range(BOARD_W):
            dxn = (xx - BOARD_W * 0.40) / (BOARD_W * 0.66)
            dyn = (yy - BOARD_H * 0.48) / (BOARD_H * 0.80)
            d = dxn * dxn + dyn * dyn
            if d <= 1.0:
                continue
            c.blend(xx, yy, INK, min(0.50, (d - 1.0) * 0.70))

    # ---- a mirror where the rack used to hang -------------------------
    c.vgrad(MIRROR_X0, MIRROR_X1, MIRROR_Y0, MIRROR_Y1, WALL1, WALL0, noise=4)
    # a couple of soft reflections so it does not read as a flat hole
    c.glow(MIRROR_X0 + 34, MIRROR_Y0 + 20, 26, GLOW1, 0.24, 2.2)
    c.glow(MIRROR_X1 - 30, MIRROR_Y0 + 40, 22, GLOW1, 0.16, 2.2)
    c.glow(MIRROR_X0 + 60, MIRROR_Y1 - 16, 30, WALL4, 0.20, 2.0)
    for i in range(5):
        c.shade(MIRROR_X0 + 10 + i * 3, MIRROR_X0 + 12 + i * 3,
                MIRROR_Y0 + 6, MIRROR_Y1 - 6, GLOW5, 0.05)
    c.border(MIRROR_X0, MIRROR_Y0, MIRROR_X1, MIRROR_Y1, WOOD3, 4)
    c.border(MIRROR_X0, MIRROR_Y0, MIRROR_X1, MIRROR_Y1, WOOD5, 1)
    c.border(MIRROR_X0 + 4, MIRROR_Y0 + 4, MIRROR_X1 - 4, MIRROR_Y1 - 4, INK, 1)
    c.border(MIRROR_X0 - 1, MIRROR_Y0 - 1, MIRROR_X1 + 1, MIRROR_Y1 + 1, INK, 1)
    c.rect(MIRROR_X0 + 3, MIRROR_Y1 + 2, MIRROR_X1 + 3, MIRROR_Y1 + 4, WALL0)

    return c


# ================================================================ holders =====
SOCKET_CELL_W, SOCKET_CELL_H = SOCKET_OUTER, SOCKET_OUTER + 2


def build_socket():
    """A square recess in the plaque, exactly one icon wide.

    Not a bin you drop into - a slot you stick into, so it is lit like a
    recess: shadow on the inner top and left, a lit lip on the inner bottom
    and right. frame 0 = empty, frame 1 = something just went in.
    """
    frames = []
    o = SOCKET_OUTER - 1
    r = SOCKET_RIM
    for lit in (False, True):
        c = Canvas(SOCKET_CELL_W, SOCKET_CELL_H)
        # recessed interior
        c.vgrad(r, o - r, r, o - r, INK, INK2)
        # inner shadow, top + left (the light is up and to the left, so the
        # near lip casts into the hole)
        c.hline(r, o - r, r, INK, 2)
        c.vline(r, r, o - r, INK, 2)
        # lit inner lip, bottom + right
        c.hline(r, o - r, o - r - 1, WOOD4, 1)
        c.vline(o - r - 1, r, o - r, WOOD3, 1)
        # outer bevel
        c.border(0, 0, o, o, WOOD3, 1)
        c.hline(0, o, 0, WOOD5, 1)
        c.vline(0, 0, o, WOOD5, 1)
        c.hline(0, o, o, INK, 1)
        c.vline(o, 0, o, INK, 1)
        # shadow onto the plaque
        c.rect(1, o + 1, o, o + 1, INK)
        if lit:
            c.border(0, 0, o, o, GOLD, 1)
            c.shade(r, o - r, r, o - r, GLOW3, 0.35)
        frames.append(c)
    return sheet(frames)


# ============================================================ aim + effects ===
DOT_CELL = 5


def build_dot():
    """Short trajectory trace. frame 0 = bright, frame 1 = fading."""
    frames = []
    for bright in (True, False):
        c = Canvas(DOT_CELL, DOT_CELL)
        col = GOLD if bright else GLOW2
        edge = INK if bright else INK2
        c.rect(1, 1, 3, 3, col)
        c.rect(2, 0, 2, 4, col)
        c.rect(0, 2, 4, 2, col)
        c.set(0, 1, edge)
        c.set(4, 1, edge)
        c.set(0, 3, edge)
        c.set(4, 3, edge)
        frames.append(c)
    return sheet(frames)


PUFF_CELL = 26


def build_puff():
    """Impact puff, 4 frames, warm to cold as it dissipates."""
    frames = []
    for i in range(4):
        c = Canvas(PUFF_CELL, PUFF_CELL)
        r = 3 + i * 4
        col = (GLOW5, GLOW3, MET4, MET2)[i]
        c.ring(13, 13, r, 3, col)
        if i < 2:
            c.disc(13, 13, max(1, 3 - i * 2), CREAM)
        for (ax, ay) in ((0, -1), (1, 0), (0, 1), (-1, 0), (1, 1), (-1, -1)):
            c.rect(13 + ax * (r + 2), 13 + ay * (r + 2),
                   13 + ax * (r + 2) + 1, 13 + ay * (r + 2) + 1, col)
        frames.append(c)
    return sheet(frames)


# ================================================================ preview =====
def build_preview(pieces, player_sheet=None):
    bg = keyed(pieces["tl_backdrop.png"]).convert("RGBA")
    board = Image.new("RGBA", (BOARD_W, BOARD_H), (0, 0, 0, 255))
    board.alpha_composite(bg)

    def blit(name, cw, ch, frame, x, y):
        im = keyed(pieces[name]).convert("RGBA")
        board.alpha_composite(im.crop((frame * cw, 0, (frame + 1) * cw, ch)), (x, y))

    for (sx, sy) in ((ROAM_X0 + 8, ROAM_Y0 + 6), (SOCKET_X, SOCKET_Y),
                     (ROAM_X0 + 62, ROAM_Y1 - 4)):
        blit("tl_socket.png", SOCKET_CELL_W, SOCKET_CELL_H,
             1 if (sx, sy) == (SOCKET_X, SOCKET_Y) else 0, sx, sy)

    # the real player sprite, right-facing idle (frame 8 of the 4x4 sheet)
    if player_sheet and os.path.exists(player_sheet):
        ps = Image.open(player_sheet).convert("RGBA")
        cw, ch = ps.size[0] // 4, ps.size[1] // 4
        cell = ps.crop((0, ch * 2, cw, ch * 3))
        cell = cell.resize((cw * 2 // 3, ch * 2 // 3), Image.NEAREST)
        board.alpha_composite(cell,
                              (STAND_X - cell.size[0] // 2, FLOOR_Y - cell.size[1] + 2))

    # first 20% of the arc + the strength arrow, as the GDScript draws them
    ang = math.radians(23.0)
    dots = keyed(pieces["tl_dot.png"]).convert("RGBA").crop((0, 0, DOT_CELL, DOT_CELL))
    spd, g = 855.0 + 620.0 * 0.47, 500.0   # the solved corner shot
    flight = []
    x, y = float(LAUNCH_X), float(LAUNCH_Y)
    vx, vy = math.cos(ang) * spd, -math.sin(ang) * spd
    for _ in range(3000):
        vy += g / 240.0
        x += vx / 240.0
        y += vy / 240.0
        if y <= CEILING_Y:
            y = CEILING_Y + 0.5
            vy = abs(vy) * 0.45
        flight.append((x, y))
        if y > FLOOR_Y or x > BOARD_W:
            break
    show = flight[: max(1, int(len(flight) * 0.20))]
    for i in range(0, len(show), 9):
        px, py = show[i]
        board.alpha_composite(dots, (int(px) - 2, int(py) - 2))

    arrow_len = 16.0 + (74.0 - 16.0) * 0.47
    ax, ay = math.cos(ang), -math.sin(ang)
    nx, ny = -ay, ax
    dr = Image.new("RGBA", (BOARD_W, BOARD_H), (0, 0, 0, 0))
    for t in range(int(arrow_len)):
        for w in range(-2, 3):
            xx = int(LAUNCH_X + ax * t + nx * w)
            yy = int(LAUNCH_Y + ay * t + ny * w)
            if 0 <= xx < BOARD_W and 0 <= yy < BOARD_H:
                dr.putpixel((xx, yy), GOLD if abs(w) < 2 else INK)
    for k in range(9):
        hw = 6 - k * 0.7
        for w in range(int(-hw), int(hw) + 1):
            xx = int(LAUNCH_X + ax * (arrow_len + k) + nx * w)
            yy = int(LAUNCH_Y + ay * (arrow_len + k) + ny * w)
            if 0 <= xx < BOARD_W and 0 <= yy < BOARD_H:
                dr.putpixel((xx, yy), GOLD if abs(w) < hw - 1 else INK)
    board.alpha_composite(dr)

    # holder interiors as debug guides
    dbg = Image.new("RGBA", (BOARD_W, BOARD_H), (0, 0, 0, 0))
    cx, cy = SOCKET_X + SOCKET_OUTER // 2, SOCKET_Y + SOCKET_OUTER // 2
    CAP = 13
    for x in range(cx - CAP, cx + CAP + 1):
        for yy in (cy - CAP, cy + CAP):
            if 0 <= x < BOARD_W and 0 <= yy < BOARD_H:
                dbg.putpixel((x, yy), (102, 255, 227, 190))
    for y in range(cy - CAP, cy + CAP + 1):
        for xx in (cx - CAP, cx + CAP):
            if 0 <= xx < BOARD_W and 0 <= y < BOARD_H:
                dbg.putpixel((xx, y), (102, 255, 227, 190))
    if DEBUG_GUIDES:
        board.alpha_composite(dbg)

    big = board.resize((BOARD_W * SCALE, BOARD_H * SCALE), Image.NEAREST)
    os.makedirs(OUT_DIR, exist_ok=True)
    big.save(f"{OUT_DIR}/preview.png")
    print(f"  preview.png  {big.size[0]}x{big.size[1]}")


# =================================================================== main =====
def main():
    with open(".gdignore", "w"):
        pass

    print("Trait Lob minigame art:")
    pieces = {}
    pieces["tl_backdrop.png"] = save(build_backdrop(), "tl_backdrop.png")
    pieces["tl_socket.png"] = save(build_socket(), "tl_socket.png")
    pieces["tl_dot.png"] = save(build_dot(), "tl_dot.png")
    pieces["tl_puff.png"] = save(build_puff(), "tl_puff.png")
    build_preview(pieces, "../../julian assange sprite sheet black.png")
    print("done -> out/keyed/*.png  (copy over ../tl_*.png)")


if __name__ == "__main__":
    main()
