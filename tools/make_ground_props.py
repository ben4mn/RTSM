"""Authoring helper for assets/terrain/ground_props.svg (8x4 cells of 64px).

Each prop is drawn in cell-local coordinates with its ground contact at
(32, 56). Run: python tools/make_ground_props.py assets/terrain/ground_props.svg
Cell indices are referenced by scripts/map/world_dressing.gd.
"""
import random
import sys

CELL = 64
COLS, ROWS = 8, 4
BASE = 56
cells = {}


def blade(x0, xt, yt, w, fill, bend=0.0):
    mx = (x0 + xt) / 2.0
    my = (BASE + yt) / 2.0
    return '<path d="M%.1f %d Q%.1f %.1f %.1f %.1f Q%.1f %.1f %.1f %dZ" fill="%s"/>' % (
        x0, BASE, mx - bend, my, xt, yt, mx + w + bend * 0.3, my + 2, x0 + w, BASE, fill)


def tuft(seed, n, spread, height, colors, cx=32, lean=0.0):
    r = random.Random(seed)
    out = []
    for i in range(n):
        f = (i / max(1, n - 1)) * 2 - 1
        x0 = cx + f * spread * 0.45 + r.uniform(-1, 1)
        xt = cx + f * spread + r.uniform(-2, 2) + lean
        yt = BASE - height * (1.0 - 0.45 * abs(f)) - r.uniform(0, 3)
        out.append(blade(x0, xt, yt, r.uniform(2.2, 3.2), colors[i % len(colors)], bend=f * 2.5))
    return out


def shadow(rx, ry=2.2, cx=32, o=0.10):
    return '<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="#273e35" opacity="%s"/>' % (cx, BASE + 0.5, rx, ry, o)


def flower(x, y, petal, heart, r=2.6):
    return ('<circle cx="%s" cy="%s" r="%s" fill="%s" stroke="#5c6d4c" stroke-width=".6"/>'
            '<circle cx="%s" cy="%s" r="%s" fill="%s"/>') % (x, y, r, petal, x, y, r * 0.42, heart)


def stem(x0, x1, y1, c="#6b8a54"):
    return '<path d="M%s %s Q%s %s %s %s" stroke="%s" stroke-width="1.3" fill="none" stroke-linecap="round"/>' % (
        x0, BASE, (x0 + x1) / 2.0 + 1.5, (BASE + y1) / 2.0, x1, y1, c)


G1, G2, G3, G4 = "#7b9a5c", "#8caa66", "#a3b976", "#6d8d56"
D1, D2, D3 = "#a9a36c", "#bdb67d", "#8f8a5b"

# 0-2 green tufts, 3 dry tuft
cells[0] = [shadow(9, 1.8, o=.07)] + tuft(1, 5, 9, 14, [G1, G2, G3])
cells[1] = [shadow(11, 1.8, o=.07)] + tuft(2, 6, 11, 11, [G2, G1, G3, G4])
cells[2] = [shadow(8, 1.8, o=.07)] + tuft(3, 7, 8, 21, [G4, G1, G2, G3], lean=2)
cells[3] = [shadow(10, 1.8, o=.06)] + tuft(4, 6, 10, 15, [D1, D2, D3])


# 4 daisies, 5 buttercups, 6 poppies, 7 cornflowers
def flowers(seed, petal, heart, n=4, r=2.6):
    rr = random.Random(seed)
    out = [shadow(11, 1.8, o=.06)] + tuft(seed + 40, 4, 10, 8, [G1, G2, G3])
    pts = []
    for i in range(n):
        x = 32 + (i - (n - 1) / 2.0) * 7 + rr.uniform(-1.5, 1.5)
        y = BASE - rr.uniform(9, 17)
        pts.append((x, y))
        out.append(stem(32 + (i - (n - 1) / 2.0) * 3, x, y))
    for x, y in pts:
        out.append(flower(round(x, 1), round(y, 1), petal, heart, r))
    return out


cells[4] = flowers(11, "#efe9d6", "#d9b662")
cells[5] = flowers(12, "#e0c26c", "#b98f4a", n=5, r=2.2)
cells[6] = flowers(13, "#c7755e", "#6b4a3c", n=3, r=3.0)
cells[7] = flowers(14, "#93a3c6", "#e9e2c8", n=4, r=2.4)

# 8 clover patch (ground hugging)
rr = random.Random(21)
cl = []
for i in range(11):
    x = 32 + rr.uniform(-13, 13)
    y = BASE - rr.uniform(-1, 6)
    cl.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"/>' % (x, y, rr.uniform(1.8, 2.8), rr.choice([G1, G2, G4])))
cl.append(flower(27, 51, "#e9dfe0", "#d7a9b0", 1.8))
cl.append(flower(38, 54, "#e9dfe0", "#d7a9b0", 1.6))
cells[8] = cl

# 9 fern / low shrub
cells[9] = [shadow(12, 2.2),
            '<path d="m21 56-4-7 4-6 6 0 2-7 7-3 6 4 1 6 6 1 3 7-5 6-13 3Z" fill="#6b8d5a" stroke="#557552" stroke-width="1.6" stroke-linejoin="round"/>',
            '<path d="m22 49 6-3 4-7 5-3 5 4-3 8-6 2-5 6-6-2Z" fill="#8aa868"/>',
            '<path d="m30 42 5-4 3 1-2 4-6 3Z" fill="#aec184"/>']

# 10 pebbles a, 11 pebbles b
cells[10] = [shadow(10, 1.8, o=.08),
             '<path d="m23 56-3-3 2-4 6-1 4 3-1 4Z" fill="#a4a79a" stroke="#7d8279" stroke-width="1.2" stroke-linejoin="round"/>',
             '<path d="m24 50 4-1 2 2-5 1Z" fill="#c3c5b8"/>',
             '<path d="m35 57-2-2 2-3 5 0 2 3-2 2Z" fill="#969a8e" stroke="#7d8279" stroke-width="1.1" stroke-linejoin="round"/>',
             '<ellipse cx="43.5" cy="52" rx="2" ry="1.4" fill="#b1b4a6" stroke="#7d8279" stroke-width=".8"/>']
cells[11] = [shadow(8, 1.6, o=.08),
             '<path d="m27 57-3-3 3-5 7-1 5 4-2 5Z" fill="#aaa593" stroke="#827d6c" stroke-width="1.2" stroke-linejoin="round"/>',
             '<path d="m28 50 5-1 3 2-6 1Z" fill="#c9c4b0"/>',
             '<ellipse cx="41" cy="56" rx="2.2" ry="1.5" fill="#9b9786" stroke="#827d6c" stroke-width=".8"/>']

# 12 boulder with moss
cells[12] = [shadow(15, 2.8, o=.12),
             '<path d="m19 56-3-7 5-9 9-4 9 2 6 7 1 8-5 4-16 1Z" fill="#9a9e93" stroke="#70766e" stroke-width="1.8" stroke-linejoin="round"/>',
             '<path d="m22 44 8-6 8 1 4 5-9 1-6 5Z" fill="#bfc2b5"/>',
             '<path d="m33 46 9-1 3 9-4 3-9 0Z" fill="#868b82"/>',
             '<path d="m21 43 6-5 6-1-4 4-6 4Z" fill="#8aa868"/>'] + tuft(31, 3, 5, 7, [G1, G2], cx=17) + tuft(32, 3, 4, 6, [G2, G4], cx=46)

# 13 fallen log
cells[13] = [shadow(18, 2.6, o=.12),
             '<path d="m14 49 30-7 5 2 2 6-2 5-30 5-5-4Z" fill="#8a6c50" stroke="#5f4a3a" stroke-width="1.8" stroke-linejoin="round"/>',
             '<path d="m17 50 27-6" stroke="#a5855f" stroke-width="2" stroke-linecap="round"/>',
             '<path d="m20 56 22-4" stroke="#6f563f" stroke-width="1.2" stroke-linecap="round"/>',
             '<ellipse cx="47" cy="50" rx="3.6" ry="5.2" fill="#c8ab7f" stroke="#5f4a3a" stroke-width="1.5"/>',
             '<ellipse cx="47" cy="50" rx="1.5" ry="2.3" fill="none" stroke="#9c7f58" stroke-width=".9"/>',
             '<path d="m26 47 2-5 3 1-1 4Z" fill="#8a6c50" stroke="#5f4a3a" stroke-width="1.2" stroke-linejoin="round"/>',
             '<path d="m18 51 5-2 4 1-5 2Z" fill="#8aa868"/>'] + tuft(33, 3, 5, 7, [G1, G2], cx=13)

# 14 reeds, 15 cattails
cells[14] = [shadow(8, 1.8, o=.08)] + tuft(41, 7, 7, 27, ["#73935a", "#86a362", "#99b06e", "#688853"], lean=3)
cat = [shadow(8, 1.8, o=.08)] + tuft(42, 5, 7, 20, ["#73935a", "#86a362", "#688853"])
for x0, x1, y1 in [(30, 27, 27), (33, 35, 23), (35, 41, 30)]:
    cat.append(stem(x0, x1, y1, "#6f8a52"))
    cat.append('<rect x="%s" y="%s" width="3" height="8" rx="1.5" fill="#7a5b42" stroke="#5a4333" stroke-width=".7"/>' % (x1 - 1.5, y1 - 2))
cells[15] = cat


# 16 mushrooms
def shroom(x, y, s, cap="#c2705a"):
    return ('<path d="M%.1f %.1f v%.1f h%.1f v%.1fz" fill="#e6dcc3" stroke="#8e826b" stroke-width=".8"/>'
            '<path d="M%.1f %.1f q%.1f %.1f %.1f 0z" fill="%s" stroke="#7d4b3d" stroke-width="1" stroke-linejoin="round"/>'
            '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="#efe6cf"/>') % (
        x - s * 0.22, y - s * 0.55, s * 0.55, s * 0.44, -s * 0.55,
        x - s * 0.62, y - s * 0.5, s * 0.62, -s * 1.0, s * 1.24, cap,
        x - s * 0.15, y - s * 0.78, s * 0.14)


cells[16] = [shadow(10, 1.8, o=.07)] + tuft(51, 3, 9, 6, [G1, G4]) + [shroom(26, 56, 8), shroom(35, 57, 6), shroom(41, 55, 4.5, "#c98a5c")]

# 17 twigs and leaf litter (forest floor)
cells[17] = ['<path d="m19 54 14-4 9 2" stroke="#7b624a" stroke-width="1.6" fill="none" stroke-linecap="round"/>',
             '<path d="m30 51 4-5" stroke="#7b624a" stroke-width="1.3" stroke-linecap="round"/>',
             '<path d="m23 57 3-2 3 2-3 2Z" fill="#b48d5a"/>', '<path d="m38 56 3-2 3 1-2 3Z" fill="#a9774f"/>',
             '<path d="m44 51 2-2 3 1-2 2Z" fill="#c0a465"/>', '<path d="m15 51 2-2 3 1-2 2Z" fill="#9c8a55"/>']

# 18 stump
cells[18] = [shadow(11, 2.4, o=.12),
             '<path d="m23 55 1-9 16 0 1 9-4 2-10 0Z" fill="#84664b" stroke="#5f4a3a" stroke-width="1.6" stroke-linejoin="round"/>',
             '<ellipse cx="32" cy="46" rx="8" ry="3.4" fill="#cdb287" stroke="#5f4a3a" stroke-width="1.4"/>',
             '<ellipse cx="32" cy="46" rx="4" ry="1.6" fill="none" stroke="#a48a61" stroke-width=".9"/>',
             '<path d="m22 55-4 2m24-2 4 2" stroke="#5f4a3a" stroke-width="1.6" stroke-linecap="round"/>'] + tuft(61, 3, 4, 6, [G1, G2], cx=20)

# 19 lily pads (float on water: no shadow)
cells[19] = ['<path d="M22 52a8 3.6 0 1 0 8-3.6l0 3.6z" fill="#6f9a66" stroke="#527a54" stroke-width="1"/>',
             '<path d="M37 56a6 2.7 0 1 0 6-2.7l0 2.7z" fill="#7da56f" stroke="#527a54" stroke-width=".9"/>',
             '<circle cx="27" cy="50.5" r="2" fill="#efe3e1"/><circle cx="27" cy="50.5" r=".8" fill="#d9b662"/>']


# 20 butterfly pale, 21 butterfly amber (drawn around the cell centre)
def butterfly(c1, c2):
    return ['<path d="m32 32-9-7-3 5 5 5Zm0 0 9-7 3 5-5 5Z" fill="%s" stroke="%s" stroke-width=".9" stroke-linejoin="round"/>' % (c1, c2),
            '<path d="m32 33-6 2 1 5Zm0 0 6 2-1 5Z" fill="%s" stroke="%s" stroke-width=".8" stroke-linejoin="round"/>' % (c1, c2),
            '<path d="m32 29v9" stroke="#4a4038" stroke-width="1.3" stroke-linecap="round"/>']


cells[20] = butterfly("#f1ead6", "#b9ad8c")
cells[21] = butterfly("#e2a85e", "#8d5f3a")

# 22 tall dry grass, 23 small blossom bush
cells[22] = [shadow(8, 1.8, o=.06)] + tuft(71, 7, 9, 22, [D1, D2, D3, "#c8c08a"], lean=-2)
cells[23] = [shadow(11, 2.2),
             '<path d="m22 56-4-6 4-6 7-1 3-5 7 0 4 5 5 3 0 7-6 4-12 1Z" fill="#6e9060" stroke="#587855" stroke-width="1.6" stroke-linejoin="round"/>',
             '<path d="m24 48 6-3 4-5 5 1 2 5-6 3-5 5-6-1Z" fill="#90ad6c"/>',
             flower(27, 46, "#efe9d6", "#d9b662", 1.9), flower(37, 42, "#efe9d6", "#d9b662", 1.9), flower(41, 50, "#efe9d6", "#d9b662", 1.7)]

out = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % (CELL * COLS, CELL * ROWS, CELL * COLS, CELL * ROWS)]
for index in sorted(cells):
    out.append('<g transform="translate(%d %d)">' % ((index % COLS) * CELL, (index // COLS) * CELL))
    out.extend(cells[index])
    out.append('</g>')
out.append('</svg>')
open(sys.argv[1], 'w', encoding='utf-8', newline='\n').write("\n".join(out) + "\n")
print("cells", len(cells))
