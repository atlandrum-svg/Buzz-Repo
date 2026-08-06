#!/usr/bin/env python3
"""
Date Bout Minigame (Level 3, round 2) - pixel art generator.

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

Board geometry constants below MUST stay in sync with date_bout_minigame.gd.

Forked from trait_lob_minigame's generator: the palette table and the whole
Canvas class are copied verbatim, so the two minigames cannot drift apart.
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


