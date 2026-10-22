#!/usr/bin/env python3
"""Original 32px field-company glyph masters, with native SVG source assets."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/ui/icons"
BONE = "#e8e5db"
TEAL = "#88b7ad"
INK = "#171c1d"
RUST = "#d69477"


def p(d, fill="bone", stroke=None, width=2):
    attrs = f'fill="{fill}"'
    if stroke:
        attrs += f' stroke="{stroke}" stroke-width="{width}" stroke-linecap="square" stroke-linejoin="miter"'
    return f'<path d="{d}" {attrs}/>'


def line(d, color="bone", width=2):
    return p(d, "none", color, width)


def circle(x, y, r, fill="bone", stroke=None, width=2):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}"' + (f' stroke="{stroke}" stroke-width="{width}"' if stroke else '') + '/>'


ICONS = {
    # Company equipment: deliberately solid, cut silhouettes at the small size.
    "army": p("M6 3h2v17H6zM24 3h2v17h-2zM4 7l3-5 3 5zM22 7l3-5 3 5z") + p("M10 9l6-3 6 3v10l-6 9-6-9z") + p("M13 11h6v7l-3 5-3-5z", "teal") + line("M16 10v9", "ink", 2),
    "base": p("M4 11h4V6h3v5h3V4h4v7h3V6h3v5h4v17H4z") + p("M13 28V19l3-3 3 3v9z", "teal") + line("M6 15h5m10 0h5M6 23h4m12 0h4", "ink", 2),
    "economy": p("M6 8l15-3 5 4v20H6z") + p("M8 6l13-3 3 3-16 3z", "teal") + line("M11 14h10m-10 5h10m-10 5h5", "ink", 2) + p("M23 13h5v10l-2.5 3-2.5-3z", "teal"),
    "build": p("M6 5l5-3 9 7-4 5-3-2-8 15-4-3 9-14z") + p("M20 4l6 2 2 6-3 4-5-1-4-5z", "teal") + p("M19 19l3-3 7 9-4 3z") + line("M21 21l3 4", "ink", 1.5),
    "food": line("M16 27V10M11 26l5-6 5 6", "teal", 2.5) + p("M16 2l3 4-3 5-3-5zM7 7l6 2 2 6-6-2zM25 7l-6 2-2 6 6-2zM6 15l7 1 2 6-7-2zM26 15l-7 1-2 6 7-2z") + p("M11 23h10v4H11z", "teal"),
    "wood": p("M6 17L19 4l8 4L14 22z") + p("M14 22L27 8v7L16 27z", "teal") + p("M3 18l5-3 7 4 1 6-5 4-7-4z") + p("M6 20l3-2 4 3v3l-3 2-4-3z", "ink") + p("M8 21l2-1 2 2-2 2-2-1z", "teal") + line("M15 14l8-8", "ink", 1.5),
    "gold": p("M11 4h10l4 8H7zM4 16h10l4 10H0zM20 16h8l4 10H16z") + p("M21 4l4 8-3 3H10l-3-3h18M14 16l4 10-3 3H3l-3-3h18M28 16l4 10-3 3H19l-3-3h16", "teal") + line("M12 7h6M5 19h5m11 0h4", "ink", 1.5),
    "population": circle(16, 8, 4) + p("M8 28v-9l5-5h6l5 5v9z") + p("M13 15l3 4 3-4v13h-6z", "teal") + circle(5, 12, 3, "teal") + circle(27, 12, 3, "teal") + p("M0 27v-8l3-3h4l2 2-3 4v5zM32 27v-8l-3-3h-4l-2 2 3 4v5z", "teal"),
    "move": p("M4 12h14V5l11 11-11 11v-7H4z") + p("M4 14h9v4H4z", "teal") + p("M19 11l5 5-5 5z", "ink"),
    "attack": p("M19 3l9-1-1 9-13 13-6-6z") + p("M19 7l5-2-2 5-11 11-2-2z", "teal") + p("M5 15l12 12-3 3L2 18zM7 23l3 3-5 5-3-3z") + line("M5 5l3 3m-5 4h4m5-9v4", "teal", 2),
    "stance": p("M5 6l11-4 11 4v10L16 30 5 16z") + p("M16 5l8 3v7l-8 11z", "teal") + p("M14 8h4v13h-4z") + p("M10 14h12v3H10z", "ink"),
    "patrol": line("M7 8h15v4M25 23H10v-4", "bone", 3) + p("M18 7l5 5 5-5zM14 25l-5-5-5 5z") + p("M12 13h8v10h-8z", "teal") + p("M14 10h4v5h-4z", "teal") + line("M5 13v4m22-2v4", "teal", 2),
    "rally": p("M6 3h3v25H6zM9 4h18l-5 7 5 7H9z") + p("M11 7h10l-3 4 3 4H11z", "teal") + p("M3 29l4-5 5 5z", "teal"),
    "queue": p("M3 4h18v3H6v17H3z", "teal") + p("M8 9h20v20H8z") + p("M11 12h14v4H11z", "teal") + line("M12 20h3m4 0h4m-11 4h3m4 0h4", "ink", 2),
    "repeat": line("M5 15V9l5-5h12l5 5v4M27 18v5l-5 5H10l-5-5v-3", "bone", 2.5) + p("M22 11l5 6 5-6zM0 21l5-6 5 6z") + p("M13 10h6v12h-6z", "teal") + line("M14 13h4m-4 5h4", "ink", 1.5),
    "farm": p("M2 16L16 7l14 9-14 10z", "none", "bone", 2.5) + line("M8 17l9-6m-4 10l9-6m-4 7l7-5", "teal", 2.5) + p("M15 4l2-3 2 3-2 3z"),
    "sacred": p("M12 4l4-3 4 3 3 19-7 5-7-5z") + p("M16 5l2 2 2 15-4 3z", "teal") + p("M14 10h4v4h-4z", "ink") + line("M5 23l-3 3 14 5 14-5-3-3", "teal", 2),
    "age_up": p("M5 29V16l4-4 4 4v13zM19 29V16l4-4 4 4v13z") + p("M12 18h8v11h-8z", "teal") + p("M16 2L6 10h7v5h6v-5h7z"),
    "idle": p("M8 3h16v4H8zM8 25h16v4H8z") + line("M10 7v3l12 12v3M22 7v3L10 22v3", "bone", 2.5) + p("M11 22l5-5 5 5z", "teal") + p("M12 9h8l-4 4z", "teal"),
    # Navigation and view equipment retain conventional action meaning.
    "pause": p("M6 4h7v24l-3.5-3L6 28zM19 4h7v24l-3.5-3-3.5 3z") + p("M8 6h3v12H8zM21 6h3v12h-3z", "teal"),
    "resume": p("M6 4l22 12L6 28z") + p("M9 9l12 7-12 7z", "teal") + p("M9 13l5 3-5 3z", "ink"),
    "play": p("M5 3h3v26H5zM10 4l19 12-19 12z") + p("M13 10l10 6-10 6z", "teal") + p("M3 28h8v3H3z", "teal"),
    "online": p("M2 7h3V4h3v3h3v10H2zM21 15h3v-3h3v3h3v11h-9z") + line("M11 12h9l4-5M8 25l4-5h9", "teal", 2.5) + p("M6 10h3v7H6zM24 19h3v7h-3z", "ink") + p("M22 4h6v6z", "teal") + p("M4 22h6v6z", "teal"),
    "settings": p("M12 2h8v5l4 2 4-2 4 7-4 3v4l-4 7-5-2h-6l-5 2-4-7v-4l-4-3 4-7 4 2 4-2z") + circle(16, 17, 7, "ink") + circle(16, 17, 4, "teal") + line("M16 15v3h3", "ink", 1.5),
    "view": p("M1 16l7-8h16l7 8-7 8H8z") + p("M5 16l5-5h12l5 5-5 5H10z", "ink") + p("M13 10h6l3 6-3 6h-6l-3-6z", "teal") + circle(16, 16, 2, "ink"),
    "select_area": p("M3 3h9v3H6v6H3zM20 3h9v9h-3V6h-6zM3 20h3v6h6v3H3zM26 20h3v9h-9v-3h6z") + p("M12 11l11 8-6 1-3 5z", "teal"),
    "clear": p("M4 21L18 5l11 10-13 14H11z") + p("M18 5l11 10-7 7-11-10z", "teal") + line("M8 25h20", "ink", 2) + line("M20 29h8", "bone", 2),
    "more": p("M3 16l4-4 4 4-4 4zM12 16l4-4 4 4-4 4zM21 16l4-4 4 4-4 4z") + p("M14 16l2-2 2 2-2 2z", "teal"),
    "back": p("M13 4L1 16l12 12v-8h16v-8H13z") + p("M16 14h10v4H16z", "teal"),
    "stop": p("M8 3h16l5 5v16l-5 5H8l-5-5V8z") + p("M10 10h12v12H10z", "teal") + line("M12 16h8", "ink", 2),
    "center": p("M16 1l4 6h-8zM16 31l-4-6h8zM1 16l6-4v8zM31 16l-6 4v-8z") + p("M16 9l7 7-7 7-7-7z", "teal") + p("M16 13l3 3-3 3-3-3z", "ink"),
    "find": p("M10 2h10l6 6v10l-6 6H10l-6-6V8z") + p("M11 6h8l3 3v8l-3 3h-8l-3-3V9z", "ink") + p("M13 8h4v3h-4z", "teal") + p("M21 21l3-3 8 10-4 4z", "teal"),
    "info": p("M10 2h12l6 6v16l-6 6H10l-6-6V8z", "none", "bone", 2.5) + p("M14 7h4v4h-4zM12 14h6v10h3v3H11v-3h3v-7h-2z", "teal"),
    "close": p("M5 3l11 10L27 3l3 3-10 10 10 10-3 3-11-10L5 29l-3-3 10-10L2 6z") + p("M7 5l9 9-2 2-9-9z", "teal"),
    "check": p("M2 16l5-5 7 8L27 4l4 4-17 22z") + p("M5 16l9 10 3-3-10-9z", "teal"),
    "undo": p("M12 3L1 12l11 9v-6h8l5 4v8h5V17l-8-7H12z") + p("M16 12h5l6 6v6h-2v-5l-5-4h-4z", "teal"),
    "reset": line("M25 8l-7-5H9l-6 7v12l7 7h12l7-7v-7", "bone", 3) + p("M21 4l7 7 2-11z", "teal") + p("M12 12h8v8h-8z", "teal"),
    "group_save": p("M5 3h20v22l-10-4-10 4z") + p("M8 6h14v10H8z", "teal") + line("M11 8v5m4-5v5m4-5v5", "ink", 2) + p("M24 18h3v6h5l-6.5 8L19 24h5z"),
    "group_recall": p("M5 3h20v22l-10-4-10 4z") + p("M8 6h14v10H8z", "teal") + line("M11 8v5m4-5v5m4-5v5", "ink", 2) + p("M24 19l-8 6 8 6v-4h8v-4h-8z"),
    "map_0": line("M3 9h26M3 16h26M3 23h26", "teal", 2) + p("M4 4l3 3-3 3-3-3zM25 22l3 3-3 3-3-3z") + p("M16 10l4 6-4 6-4-6z"),
    "map_1": line("M14 2l4 6-4 8 4 8-4 6M18 2l4 6-4 8 4 8-4 6", "teal", 2) + p("M4 6h23v4H4zM4 14h23v4H4zM4 22h23v4H4z") + line("M8 6v4m15-4v4M8 14v4m15-4v4M8 22v4m15-4v4", "ink", 1.5),
    "map_2": p("M7 2l6 10H1zM25 18l6 10H19z") + line("M7 12v4m18 12v3", "bone", 2) + line("M4 27L27 4M4 21L21 4M11 28L28 11", "teal", 2.5),
}

for name, sign in (("zoom_in", True), ("zoom_out", False)):
    ICONS[name] = p("M8 3h12l7 7v10l-7 7H8l-6-7V10z", "none", "bone", 3) + line("M9 15h11" + ("m-5-5v10" if sign else ""), "teal", 3)

for name, body in ICONS.items():
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">\n'
           f'  <title>Field company — {name.replace("_", " ")}</title>\n  {body}\n</svg>\n')
    for token, value in (("bone", BONE), ("teal", TEAL), ("ink", INK)):
        svg = svg.replace(f'"{token}"', f'"{value}"')
    (OUT / f"{name}.svg").write_text(svg)
    if name == "play":
        (OUT / "play_dark.svg").write_text(svg.replace(BONE, INK).replace(TEAL, RUST))
print(f"Wrote {len(ICONS) + 1} original icon masters.")
