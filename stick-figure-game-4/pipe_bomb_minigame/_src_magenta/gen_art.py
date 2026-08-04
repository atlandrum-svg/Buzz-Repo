#!/usr/bin/env python3
"""
Pipe Bomb Wiring Minigame - pixel art generator.

Style contract (matches "Room Cleaned 1.png"):
  * 16-bit chunky pixels, minimum 2px features
  * thick #272736 outlines on every silhouette
  * warm room palette (extracted from Room Cleaned 1.png)
  * authored on PURE MAGENTA (#FF00FF) chroma key, then keyed to alpha on export

Outputs:
  out/keyed/*.png      -> game-ready (magenta keyed to alpha)
  out/magenta/*.png    -> source plates on the chroma key
"""
import os
from PIL import Image

# ---------------------------------------------------------------- palette ----
KEY   = (255, 0, 255, 255)          # pure magenta chroma key

OUT   = (0x27, 0x27, 0x36, 255)     # outline / darkest
DARK  = (0x32, 0x29, 0x47, 255)
PUR   = (0x47, 0x3B, 0x78, 255)
WINE  = (0x57, 0x29, 0x4B, 255)
WINE2 = (0x73, 0x27, 0x5C, 255)
MAR   = (0x8C, 0x3F, 0x5D, 255)
MAR2  = (0x96, 0x42, 0x53, 255)
PINK  = (0xB0, 0x30, 0x5C, 255)
RUST  = (0xBA, 0x61, 0x56, 255)
RED   = (0xE3, 0x69, 0x56, 255)
ORA   = (0xF2, 0xA6, 0x5E, 255)
ORA2  = (0xFF, 0xB5, 0x70, 255)
CREAM = (0xFF, 0xFF, 0xEB, 255)
GOLD  = (0xFF, 0xE4, 0x78, 255)
GRN   = (0x3C, 0xA3, 0x70, 255)
TEAL  = (0x3D, 0x6E, 0x70, 255)
BLU   = (0x4B, 0x5B, 0xAB, 255)
BLU2  = (0x4D, 0xA6, 0xFF, 255)
CYA   = (0x66, 0xFF, 0xE3, 255)
GRY   = (0x7E, 0x7E, 0x8F, 255)
GRY2  = (0xC2, 0xC2, 0xD1, 255)

# Wire colours: (bright, shade). Order MUST match WIRE_COLORS in the GDScript.
WIRES = [
    (RED,   RUST),    # 0 RED
    (BLU2,  BLU),     # 1 BLUE
    (GOLD,  ORA),     # 2 YELLOW
    (GRN,   TEAL),    # 3 GREEN
    (GRY2,  GRY),     # 4 WHITE
    (PINK,  WINE2),   # 5 PINK
]

OUT_DIR = "out"


# ------------------------------------------------------------- primitives ----
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
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
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
        for y in range(cy - r - 1, cy + r + 2):
            for x in range(cx - r - 1, cx + r + 2):
                if (x - cx) ** 2 + (y - cy) ** 2 <= rr:
                    self.set(x, y, c)

    def ring(self, cx, cy, r, t, c):
        outer = (r + 0.35) ** 2
        inner = (r - t + 0.35) ** 2
        for y in range(cy - r - 1, cy + r + 2):
            for x in range(cx - r - 1, cx + r + 2):
                d = (x - cx) ** 2 + (y - cy) ** 2
                if inner < d <= outer:
                    self.set(x, y, c)

    def notch_corners(self, x0, y0, x1, y1, n=2):
        """Chunky pixel-art corner cut: knock the sharp corners back to KEY."""
        for i in range(n):
            for j in range(n - i):
                self.set(x0 + i, y0 + j, KEY)
                self.set(x1 - i, y0 + j, KEY)
                self.set(x0 + i, y1 - j, KEY)
                self.set(x1 - i, y1 - j, KEY)

    def outline_silhouette(self, c=OUT):
        """Wrap every non-key pixel cluster in a 1px outline (chunky look)."""
        src = [row[:] for row in self.px]
        for y in range(self.h):
            for x in range(self.w):
                if src[y][x] != KEY:
                    continue
                touch = False
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.w and 0 <= ny < self.h and src[ny][nx] != KEY:
                        touch = True
                        break
                if touch:
                    self.px[y][x] = c

    def image(self):
        im = Image.new("RGBA", (self.w, self.h))
        im.putdata([self.px[y][x] for y in range(self.h) for x in range(self.w)])
        return im


def keyed(im):
    """Magenta chroma key -> transparent."""
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


def sheet(frames):
    w = sum(f.w for f in frames)
    h = max(f.h for f in frames)
    im = Image.new("RGBA", (w, h), KEY)
    x = 0
    for f in frames:
        im.paste(f.image(), (x, 0))
        x += f.w
    return im


# ------------------------------------------------------------------ board ----
BOARD_W, BOARD_H = 176, 152
RAIL_X0, RAIL_X1 = 106, 132          # recessed terminal channel
RAIL_CX = 119                        # terminal centre column
RAIL_TOP, RAIL_BOT = 16, 136         # clamp travel range (board px)


def screw(c, cx, cy):
    c.disc(cx, cy, 4, OUT)
    c.disc(cx, cy, 3, GRY)
    c.disc(cx, cy, 2, GRY2)
    c.rect(cx - 2, cy - 1, cx + 2, cy, OUT)   # flathead slot


def build_board():
    c = Canvas(BOARD_W, BOARD_H)
    x1, y1 = BOARD_W - 1, BOARD_H - 1

    # --- plate body -------------------------------------------------------
    c.rect(0, 0, x1, y1, WINE)
    c.hline(0, x1, 2, WINE2, t=4)          # top bevel light
    c.hline(0, x1, y1 - 5, DARK, t=4)      # bottom shadow
    c.vline(2, 0, y1, WINE2, t=2)
    c.vline(x1 - 3, 0, y1, DARK, t=2)

    c.border(0, 0, x1, y1, OUT, t=3)       # thick outline
    c.notch_corners(0, 0, x1, y1, n=3)
    c.border(4, 4, x1 - 4, y1 - 4, MAR, t=1)

    # --- perfboard dot field (left work area) -----------------------------
    for gy in range(14, 140, 8):
        for gx in range(12, 100, 8):
            c.rect(gx, gy, gx + 1, gy + 1, DARK)

    # --- circuit traces feeding the rail ---------------------------------
    def trace(pts, col=ORA, shade=RUST):
        for i in range(len(pts) - 1):
            (ax, ay), (bx, by) = pts[i], pts[i + 1]
            if ax == bx:
                lo, hi = sorted((ay, by))
                c.vline(ax, lo, hi, shade, t=3)
                c.vline(ax, lo, hi, col, t=2)
            else:
                lo, hi = sorted((ax, bx))
                c.hline(lo, hi, ay, shade, t=3)
                c.hline(lo, hi, ay, col, t=2)
        for (px, py) in (pts[0], pts[-1]):
            c.disc(px, py, 3, shade)
            c.disc(px, py, 2, col)

    trace([(20, 34), (62, 34), (62, 22), (100, 22)])
    trace([(20, 74), (46, 74), (46, 96), (100, 96)])
    trace([(20, 112), (78, 112), (78, 128), (100, 128)])
    trace([(34, 52), (34, 62), (100, 62)], col=GOLD, shade=ORA)

    # --- recessed rail channel -------------------------------------------
    c.rect(RAIL_X0, 8, RAIL_X1, y1 - 8, OUT)
    c.rect(RAIL_X0 + 2, 10, RAIL_X1 - 2, y1 - 10, DARK)
    c.vline(RAIL_X0 + 2, 10, y1 - 10, PUR, t=1)          # inner bevel
    c.hline(RAIL_X0 + 2, RAIL_X1 - 2, 10, PUR, t=1)
    # rail guide grooves
    c.vline(RAIL_CX - 9, 12, y1 - 12, OUT, t=1)
    c.vline(RAIL_CX + 9, 12, y1 - 12, OUT, t=1)

    # --- right nameplate + status LEDs ------------------------------------
    c.rect(138, 14, 168, 52, OUT)
    c.rect(140, 16, 166, 50, MAR2)
    c.hline(140, 166, 16, RUST, t=2)
    # screen-printed "DET" block glyphs (chunky 3x5)
    glyphs = {
        "D": ["1110", "1001", "1001", "1001", "1110"],
        "E": ["1111", "1000", "1110", "1000", "1111"],
        "T": ["1111", "0110", "0110", "0110", "0110"],
    }
    gx = 143
    for ch in "DET":
        rows = glyphs[ch]
        for ry, row in enumerate(rows):
            for rx, bit in enumerate(row):
                if bit == "1":
                    c.rect(gx + rx * 2, 22 + ry * 2, gx + rx * 2 + 1, 22 + ry * 2 + 1, CREAM)
        gx += 9
    for i, col in enumerate((RED, GOLD, GRN)):
        lx = 145 + i * 9
        c.disc(lx, 42, 3, OUT)
        c.disc(lx, 42, 2, col)
        c.set(lx - 1, 41, CREAM)

    # --- right side vent slots -------------------------------------------
    for vy in range(64, 130, 10):
        c.rect(140, vy, 166, vy + 3, OUT)
        c.rect(141, vy + 1, 165, vy + 2, DARK)

    # --- bottom-left hazard placard ---------------------------------------
    hx, hy = 26, 124
    for i in range(11):
        c.rect(hx - i, hy + i, hx + i, hy + i, OUT)
    for i in range(1, 9):
        c.rect(hx - i + 1, hy + i, hx + i - 1, hy + i, GOLD)
    c.rect(hx - 1, hy + 3, hx, hy + 6, OUT)
    c.rect(hx - 1, hy + 8, hx, hy + 8, OUT)

    # small screen-print label next to placard
    c.rect(42, 128, 92, 130, MAR)
    c.rect(42, 133, 80, 135, MAR)

    # --- corner screws -----------------------------------------------------
    for (sx, sy) in ((11, 11), (BOARD_W - 12, 11), (11, BOARD_H - 12), (BOARD_W - 12, BOARD_H - 12)):
        screw(c, sx, sy)

    return c


# -------------------------------------------------------------- terminals ----
TERM = 24  # cell size


def build_terminal(bright, shade, lit):
    c = Canvas(TERM, TERM)
    cx = cy = TERM // 2
    # metal post body (cool purple-steel so every wire colour pops off it)
    c.disc(cx, cy, 10, OUT)
    c.disc(cx, cy, 9, PUR)
    c.ring(cx, cy, 9, 2, GRY if not lit else GRY2)   # rim highlight
    c.disc(cx, cy, 8, PUR)
    # hex nut facets (chunky)
    c.rect(cx - 8, cy - 2, cx - 6, cy + 1, GRY)
    c.rect(cx + 6, cy - 1, cx + 8, cy + 2, DARK)
    # coloured collar
    c.ring(cx, cy, 7, 1, OUT)
    c.ring(cx, cy, 6, 3, shade)
    c.ring(cx, cy, 6, 2, bright)
    c.ring(cx, cy, 4, 1, OUT)
    # centre socket
    c.disc(cx, cy, 3, OUT)
    if lit:
        c.disc(cx, cy, 2, CREAM)
        # energised ticks
        for (dx, dy) in ((0, -12), (0, 12), (-12, 0), (12, 0)):
            c.rect(cx + dx - 1, cy + dy - 1, cx + dx + 1, cy + dy + 1, GOLD)
        for (dx, dy) in ((-9, -9), (9, -9), (-9, 9), (9, 9)):
            c.rect(cx + dx, cy + dy, cx + dx + 1, cy + dy + 1, bright)
        c.ring(cx, cy, 11, 1, GOLD)
    else:
        c.disc(cx, cy, 2, DARK)
        c.set(cx - 1, cy - 1, GRY)
    return c


# ------------------------------------------------------------------ clamp ----
CLAMP_W, CLAMP_H = 52, 30
CLAMP_TIP_X, CLAMP_TIP_Y = 48, 15   # contact point in sprite-local px


def build_clamp(bright, shade):
    """Wire-feed clamp pointing right. The held wire's colour reads at BOTH ends
    (tail on the left, live tip poking through the jaws) so it is unmissable."""
    c = Canvas(CLAMP_W, CLAMP_H)
    my = 15  # mid-line

    # --- insulated wire tail coming in from the left ----------------------
    c.rect(0, my - 4, 15, my + 4, shade)
    c.rect(0, my - 4, 15, my, bright)
    for x in range(2, 15, 4):                     # rib texture
        c.rect(x, my - 4, x, my + 4, shade)

    # --- crimp ferrule -----------------------------------------------------
    c.rect(15, my - 5, 20, my + 5, GRY)
    c.rect(15, my - 5, 20, my - 2, GRY2)
    c.rect(17, my - 5, 17, my + 5, DARK)

    # --- tool body ---------------------------------------------------------
    c.rect(20, my - 9, 38, my + 9, GRY)
    c.rect(20, my - 9, 38, my - 6, GRY2)          # top highlight
    c.rect(20, my + 6, 38, my + 9, DARK)          # underside shade
    # colour-coded tag band on the tool (instant read of held wire)
    c.rect(23, my - 9, 28, my + 9, shade)
    c.rect(23, my - 9, 28, my - 3, bright)
    c.rect(29, my - 9, 29, my + 9, OUT)
    # pivot rivet
    c.disc(34, my, 4, OUT)
    c.disc(34, my, 3, GRY2)
    c.set(33, my - 1, CREAM)

    # --- jaws converging on the contact point ------------------------------
    for i in range(11):
        x = 38 + i
        spread = 7 - int(i * 0.55)
        c.rect(x, my - spread - 2, x, my - spread + 1, GRY2)   # upper jaw
        c.rect(x, my + spread - 1, x, my + spread + 2, GRY)    # lower jaw

    # --- live stripped tip held between the jaws ---------------------------
    c.rect(38, my - 1, 45, my + 1, ORA)
    c.rect(45, my - 2, CLAMP_TIP_X + 1, my + 2, bright)
    c.rect(45, my - 2, CLAMP_TIP_X + 1, my - 1, CREAM)

    c.outline_silhouette(OUT)
    return c


# ------------------------------------------------------------- wire stubs ----
def build_wire_stub(bright, shade):
    c = Canvas(26, 14)
    # insulation
    c.rect(0, 4, 17, 9, shade)
    c.rect(0, 4, 17, 6, bright)
    # ribbing
    for x in range(3, 17, 4):
        c.rect(x, 4, x, 9, shade)
    # stripped copper
    c.rect(18, 5, 23, 8, ORA)
    c.rect(18, 5, 23, 6, ORA2)
    # tinned tip
    c.rect(24, 6, 25, 7, GRY2)
    c.outline_silhouette(OUT)
    return c


# ---------------------------------------------------------------- sparks ----
SPARK = 30


def build_spark(frame):
    c = Canvas(SPARK, SPARK)
    cx = cy = SPARK // 2
    grow = [3, 6, 9, 11, 13]
    r = grow[frame]
    cols = [CREAM, GOLD, GOLD, ORA, RED]
    core = [CREAM, CREAM, GOLD, ORA, RUST]
    # radial chunky bolts
    dirs = [(0, -1), (1, 0), (0, 1), (-1, 0), (1, -1), (1, 1), (-1, 1), (-1, -1)]
    for (dx, dy) in dirs:
        for step in range(1, r + 1):
            jitter = 1 if (step + frame) % 3 == 0 else 0
            x = cx + dx * step + (jitter if dy != 0 else 0)
            y = cy + dy * step + (jitter if dx != 0 else 0)
            c.rect(x, y, x + 1, y + 1, cols[frame])
    if frame < 4:
        c.disc(cx, cy, max(2, 5 - frame), core[frame])
    if frame < 2:
        c.disc(cx, cy, 2, CREAM)
    c.outline_silhouette(OUT)
    return c


# ------------------------------------------------------------- fuse flame ----
def build_flame(frame):
    c = Canvas(16, 18)
    wob = [0, 1, 0, -1][frame]
    # outer flame
    pts = [(6, 17, 9, 17), (5, 15, 10, 16), (5, 12, 10, 14), (6, 9, 9, 11),
           (6 + wob, 6, 9 + wob, 8), (7 + wob, 4, 8 + wob, 5)]
    for (x0, y0, x1, y1) in pts:
        c.rect(x0, y0, x1, y1, RED)
    c.rect(6, 13, 9, 17, ORA)
    c.rect(6, 10, 9, 12, ORA2)
    c.rect(7, 8 + (1 if wob else 0), 8, 10, GOLD)
    c.rect(7, 15, 8, 17, CREAM)
    c.outline_silhouette(OUT)
    return c


# -------------------------------------------------------------- bomb icon ----
def build_bomb_icon():
    """Small pipe-bomb glyph for the minigame header."""
    c = Canvas(34, 24)
    # pipe body
    c.rect(4, 8, 29, 19, GRY)
    c.rect(4, 8, 29, 10, GRY2)
    c.rect(4, 17, 29, 19, DARK)
    # end caps
    c.rect(2, 6, 7, 21, GRY2)
    c.rect(26, 6, 31, 21, GRY2)
    c.rect(2, 17, 7, 21, GRY)
    c.rect(26, 17, 31, 21, GRY)
    # tape band
    c.rect(13, 6, 20, 21, RUST)
    c.rect(13, 6, 20, 8, RED)
    # fuse
    c.rect(16, 2, 17, 6, ORA)
    c.rect(18, 0, 19, 3, GOLD)
    c.outline_silhouette(OUT)
    return c


# -------------------------------------------------------------------- main ---
def main():
    print("building pipe bomb minigame art (magenta-keyed, room palette)")

    save(build_board(), "pb_board.png")

    terms = []
    for (bright, shade) in WIRES:
        terms.append(build_terminal(bright, shade, False))
        terms.append(build_terminal(bright, shade, True))
    save(sheet(terms), "pb_terminals.png")

    save(sheet([build_clamp(b, s) for (b, s) in WIRES]), "pb_clamp.png")
    save(sheet([build_wire_stub(b, s) for (b, s) in WIRES]), "pb_wirestub.png")
    save(sheet([build_spark(i) for i in range(5)]), "pb_spark.png")
    save(sheet([build_flame(i) for i in range(4)]), "pb_flame.png")
    save(build_bomb_icon(), "pb_bomb_icon.png")

    print("done ->", os.path.abspath(OUT_DIR))


if __name__ == "__main__":
    main()
