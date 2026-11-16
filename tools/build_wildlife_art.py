#!/usr/bin/env python3
"""Author the wildlife sprites (sheep, deer, boar, carcass) as SVG.

Original work for Pocket Kingdoms, drawn to sit beside the painted chibi
units: thick warm-brown ink, soft cream/tan fills, dot eyes. Every sprite is a
128px canvas with the feet on y104 (the unit foot anchor) and faces right.

    python3 tools/build_wildlife_art.py assets/resources [contact_sheet.html]
"""
import os
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/resources"
INK = "#3d2e27"
SHADOW = '<ellipse cx="{cx}" cy="104" rx="{rx}" ry="{ry}" fill="#273e35" opacity=".18"/>'


def svg(body):
    return '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">\n' + body.strip() + "\n</svg>\n"


def union(circles, fill, stroke=INK, width=6.4):
    """An outline pass under a fill pass gives one clean scalloped silhouette."""
    shapes = "".join('<circle cx="%s" cy="%s" r="%s"/>' % c for c in circles)
    return '<g fill="%s" stroke="%s" stroke-width="%s">%s</g><g fill="%s">%s</g>' % (stroke, stroke, width, shapes, fill, shapes)


def sheep(walk):
    wool = [(42, 78, 13), (52, 68, 14), (66, 65, 15), (79, 70, 13), (83, 80, 11), (72, 86, 13), (57, 88, 13), (44, 86, 11)]
    if walk:
        legs = """<g fill="#6b5347" stroke="%s" stroke-width="3" stroke-linejoin="round">
<rect x="43" y="88" width="7" height="17" rx="3" transform="rotate(22 46 90)"/>
<rect x="53" y="88" width="7" height="15" rx="3" transform="rotate(-18 56 90)"/>
<rect x="69" y="88" width="7" height="15" rx="3" transform="rotate(20 72 90)"/>
<rect x="78" y="88" width="7" height="17" rx="3" transform="rotate(-24 81 90)"/></g>""" % INK
        lift = -2
    else:
        legs = """<g fill="#6b5347" stroke="%s" stroke-width="3" stroke-linejoin="round">
<rect x="44" y="88" width="7" height="16" rx="3"/><rect x="54" y="89" width="7" height="15" rx="3"/>
<rect x="69" y="89" width="7" height="15" rx="3"/><rect x="78" y="88" width="7" height="16" rx="3"/></g>""" % INK
        lift = 0
    body = """%s
%s
<g transform="translate(0 %d)">
<circle cx="31" cy="76" r="6.5" fill="#efe6d2" stroke="%s" stroke-width="3"/>
%s
<path d="M36 86c6 10 22 13 36 11 9-1 16-6 20-13-8 6-17 8-28 8-11 0-21-2-28-6Z" fill="#d6c9ad" opacity=".85"/>
<path d="M46 66c3-6 9-10 16-11" fill="none" stroke="#fffaf0" stroke-width="3" stroke-linecap="round" opacity=".8"/>
<ellipse cx="86" cy="60" rx="6" ry="3.6" transform="rotate(-28 86 60)" fill="#b89478" stroke="%s" stroke-width="2.6"/>
<ellipse cx="97" cy="71" rx="11.5" ry="12.5" fill="#cfae8f" stroke="%s" stroke-width="3.2"/>
<ellipse cx="106" cy="63" rx="6" ry="3.6" transform="rotate(24 106 63)" fill="#b89478" stroke="%s" stroke-width="2.6"/>
<path d="M90 80c3 4 10 5 14 1" fill="#e6cdb4" opacity=".9"/>
<circle cx="92" cy="59" r="7" fill="#f3ead8" stroke="%s" stroke-width="2.8"/>
<circle cx="99" cy="58" r="5.5" fill="#f3ead8" stroke="%s" stroke-width="2.8"/>
<circle cx="95" cy="59" r="5.5" fill="#f3ead8"/>
<circle cx="94.5" cy="70" r="2.5" fill="#2a201c"/><circle cx="103" cy="70" r="2.5" fill="#2a201c"/>
<circle cx="93.8" cy="69.2" r=".8" fill="#fff"/><circle cx="102.3" cy="69.2" r=".8" fill="#fff"/>
<ellipse cx="99" cy="77.5" rx="2.6" ry="1.6" fill="#7a5a4c"/>
</g>""" % (SHADOW.format(cx=64, rx=30, ry=5.5), legs, lift, INK, union(wool, "#f3ead8"), INK, INK, INK, INK, INK)
    return svg(body)


def deer():
    body = """%s
<g stroke="%s" stroke-width="3" stroke-linejoin="round" fill="#a8774a">
<rect x="38" y="76" width="6" height="28" rx="3"/><rect x="48" y="78" width="6" height="26" rx="3"/>
<rect x="68" y="78" width="6" height="26" rx="3"/><rect x="77" y="76" width="6" height="28" rx="3"/></g>
<g fill="#4a372d"><rect x="37" y="99" width="8" height="5.5" rx="2"/><rect x="47" y="99" width="8" height="5.5" rx="2"/><rect x="67" y="99" width="8" height="5.5" rx="2"/><rect x="76" y="99" width="8" height="5.5" rx="2"/></g>
<path d="M33 70c0-9 9-15 22-15h14c7 0 11-6 13-13l12 3c1 12-1 22-6 30-4 7-12 10-22 10H50c-10 0-17-6-17-15Z" fill="#c8935e" stroke="%s" stroke-width="3.4" stroke-linejoin="round"/>
<path d="M38 78c5 5 12 7 22 7 12 0 22-2 28-9-3 8-11 11-22 11H52c-7 0-12-3-14-9Z" fill="#f1e4cb"/>
<path d="M30 66c-3-3-4-7-2-10 4 1 7 4 8 8Z" fill="#f6eede" stroke="%s" stroke-width="2.6" stroke-linejoin="round"/>
<g fill="#f3e3c6" opacity=".9"><circle cx="46" cy="63" r="2.4"/><circle cx="55" cy="60" r="2.2"/><circle cx="64" cy="62" r="2.4"/><circle cx="52" cy="68" r="2"/></g>
<g fill="none" stroke="%s" stroke-width="5.2" stroke-linecap="round" stroke-linejoin="round"><path d="M86 30c-2-7-1-13 3-18M87 21l-7-4M93 30c2-6 6-10 11-12M97 22l1-8"/></g>
<g fill="none" stroke="#eadfc6" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M86 30c-2-7-1-13 3-18M87 21l-7-4M93 30c2-6 6-10 11-12M97 22l1-8"/></g>
<ellipse cx="80" cy="32" rx="7" ry="3.8" transform="rotate(-30 80 32)" fill="#b98352" stroke="%s" stroke-width="2.6"/>
<path d="M82 40c0-7 6-12 13-12 6 0 10 3 13 8l5 6c1 3-1 6-5 6h-9c-9 0-17-2-17-8Z" fill="#c8935e" stroke="%s" stroke-width="3.2" stroke-linejoin="round"/>
<path d="M100 47c4 1 9 1 12 0 1-2 1-3 0-5-4 0-9 1-12 5Z" fill="#f1e4cb"/>
<circle cx="97" cy="37.5" r="2.6" fill="#2a201c"/><circle cx="96.3" cy="36.7" r=".8" fill="#fff"/>
<ellipse cx="111.5" cy="42.5" rx="2.6" ry="2" fill="#3a2b25"/>
""" % (SHADOW.format(cx=60, rx=30, ry=5), INK, INK, INK, INK, INK, INK)
    return svg(body)


def boar(charge):
    if charge:
        legs = """<g fill="#4f3a30" stroke="%s" stroke-width="3" stroke-linejoin="round">
<rect x="32" y="84" width="9" height="19" rx="3.5" transform="rotate(34 36 86)"/>
<rect x="44" y="86" width="9" height="16" rx="3.5" transform="rotate(18 48 88)"/>
<rect x="72" y="86" width="9" height="16" rx="3.5" transform="rotate(-30 76 88)"/>
<rect x="83" y="84" width="9" height="19" rx="3.5" transform="rotate(-44 87 86)"/></g>""" % INK
        group = '<g transform="translate(2 4) rotate(7 64 80)">'
        brow = '<path d="M88 63l11 5" stroke="%s" stroke-width="3.4" stroke-linecap="round"/>' % INK
        extra = '<g stroke="#f4ecd8" stroke-width="2.6" stroke-linecap="round" opacity=".85"><path d="M8 70h14M4 82h16M12 94h12"/></g>'
        shadow = SHADOW.format(cx=64, rx=38, ry=5.5)
    else:
        legs = """<g fill="#4f3a30" stroke="%s" stroke-width="3" stroke-linejoin="round">
<rect x="34" y="86" width="9" height="18" rx="3.5"/><rect x="46" y="87" width="9" height="17" rx="3.5"/>
<rect x="70" y="87" width="9" height="17" rx="3.5"/><rect x="81" y="86" width="9" height="18" rx="3.5"/></g>""" % INK
        group = "<g>"
        brow = '<path d="M88 65l10 3" stroke="%s" stroke-width="3.2" stroke-linecap="round"/>' % INK
        extra = ""
        shadow = SHADOW.format(cx=64, rx=35, ry=6)
    body = """%s
%s
%s
%s
<path d="M20 74c2 3 2 7-1 10" fill="none" stroke="%s" stroke-width="3.4" stroke-linecap="round"/>
<path d="M24 78c0-14 12-25 30-27l20-1c10 0 18 3 24 9l14 12c4 4 4 9 0 12l-8 6c-5 4-12 6-20 6H46c-13 0-22-7-22-17Z" fill="#7b5846" stroke="%s" stroke-width="3.6" stroke-linejoin="round"/>
<path d="M30 60l5-10 6 7 5-10 6 8 6-10 6 9 7-9 4 9 8-6 2 9-12 3H34Z" fill="#4a362d" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
<path d="M30 84c6 7 16 9 30 9 12 0 22-2 30-8-4 9-14 12-26 12H48c-9 0-16-4-18-13Z" fill="#5f4437"/>
<path d="M38 64c8-5 18-7 30-7" fill="none" stroke="#9a7560" stroke-width="3" stroke-linecap="round" opacity=".9"/>
<path d="M78 52l4-9 6 9Z" fill="#6a4a3b" stroke="%s" stroke-width="2.8" stroke-linejoin="round"/>
<path d="M96 70l14 10c3 3 3 8-1 10l-5 3c-5 2-10 1-13-3Z" fill="#c99684" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
<ellipse cx="108.5" cy="83" rx="2" ry="2.6" fill="#6a4338"/><ellipse cx="103.5" cy="87" rx="1.8" ry="2.4" fill="#6a4338"/>
<path d="M95 86c1-6 4-10 8-12-1 5-2 9-1 13Z" fill="#fbf5e4" stroke="%s" stroke-width="2.4" stroke-linejoin="round"/>
<circle cx="92" cy="71" r="2.8" fill="#201815"/><circle cx="91.3" cy="70.2" r=".8" fill="#fff"/>
%s
</g>""" % (shadow, extra, legs, group, INK, INK, INK, INK, INK, INK, brow)
    return svg(body)


def carcass():
    body = """%s
<path d="M26 98c6-9 20-13 38-13s32 4 38 13c-10 6-24 8-38 8s-28-2-38-8Z" fill="#7d9463" stroke="#4d6247" stroke-width="3" stroke-linejoin="round"/>
<path d="M36 97c8-4 18-6 28-6s20 2 28 6" fill="none" stroke="#a9bd84" stroke-width="2.6" stroke-linecap="round"/>
<g transform="rotate(-14 60 84)">
<rect x="78" y="78" width="26" height="7" rx="3.5" fill="#f6efdd" stroke="%s" stroke-width="3"/>
<circle cx="105" cy="78" r="5" fill="#f6efdd" stroke="%s" stroke-width="3"/><circle cx="105" cy="85" r="5" fill="#f6efdd" stroke="%s" stroke-width="3"/>
<rect x="96" y="79.5" width="10" height="4" fill="#f6efdd"/>
<path d="M34 82c0-13 11-22 26-22 14 0 25 8 25 21 0 12-11 19-25 19-15 0-26-6-26-18Z" fill="#c9705f" stroke="%s" stroke-width="3.4" stroke-linejoin="round"/>
<path d="M40 88c5 6 13 8 22 8 9 0 16-3 20-9-2 9-10 13-22 13-10 0-17-4-20-12Z" fill="#a85749"/>
<path d="M42 76c3-6 9-10 17-10" fill="none" stroke="#f0c3ad" stroke-width="3.4" stroke-linecap="round"/>
</g>
<g transform="rotate(16 44 92)">
<path d="M26 92c0-7 7-12 16-12s16 5 16 12-7 11-16 11-16-4-16-11Z" fill="#d07a66" stroke="%s" stroke-width="3.2" stroke-linejoin="round"/>
<ellipse cx="42" cy="92" rx="5" ry="3.6" fill="#f6efdd" stroke="%s" stroke-width="2.2"/>
<path d="M30 90c2-4 6-6 11-6" fill="none" stroke="#f0c3ad" stroke-width="2.6" stroke-linecap="round"/>
</g>""" % (SHADOW.format(cx=64, rx=40, ry=6), INK, INK, INK, INK, INK, INK)
    return svg(body)


FILES = {
    "sheep.svg": sheep(False), "sheep_walk.svg": sheep(True), "deer.svg": deer(),
    "boar.svg": boar(False), "boar_charge.svg": boar(True), "carcass.svg": carcass(),
}

for name, content in FILES.items():
    with open(os.path.join(OUT, name), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(content)
if len(sys.argv) > 2:
    cells = "".join('<div style="display:inline-block;margin:10px;text-align:center;font:12px sans-serif"><div>%s</div>%s<br><span style="zoom:.4">%s</span></div>' % (n, c, c) for n, c in FILES.items())
    with open(sys.argv[2], "w", encoding="utf-8") as handle:
        handle.write('<html><body style="background:#8fae6b;margin:0;padding:20px">' + cells + "</body></html>")
print("wrote", ", ".join(FILES))
