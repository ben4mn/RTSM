#!/usr/bin/env python3
"""Keep cloth variants and the SVG company fallback tied to battle art.

Neutral materials stay identical. Re-run after editing a primary unit SVG.
The fallback intentionally overlaps three personalities and crops their lower
legs; each face/helmet/hat and signature gear remains shared with the game.
The primary illustrated field_company.png is a separate asset and is not changed.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UNITS = ROOT / "assets/units"
PALETTE = {"#406861": "#855949", "#6E9C94": "#BD8067", "#A9C7BB": "#DFB498"}

for name in ("worker", "warrior", "archer", "cavalry", "scout", "siege"):
    source = (UNITS / f"{name}.svg").read_text()
    for base, alternate in PALETTE.items():
        source = source.replace(base, alternate)
    (UNITS / f"{name}_enemy.svg").write_text(source)


def figure(name: str, transform: str) -> str:
    svg = (UNITS / f"{name}.svg").read_text()
    body = svg[svg.index(">") + 1:svg.rindex("</svg>")]
    return f'<g transform="{transform}">{body}</g>'


company = '''<svg xmlns="http://www.w3.org/2000/svg" width="420" height="228" viewBox="0 0 420 228">
<!-- The field company: a practical builder, a steadfast guard and a watchful archer.
     Original role artwork, shared with the actual units; transparent atlas overlay. -->
<defs><clipPath id="company-crop"><rect x="0" y="0" width="420" height="228"/></clipPath></defs>
<g clip-path="url(#company-crop)">
'''
company += figure("worker", "translate(-38 19) scale(2.14)")
company += figure("archer", "translate(194 28) scale(1.94)")
company += figure("warrior", "translate(78 -3) scale(2.28)")
company += "</g></svg>\n"
(ROOT / "assets/ui/field_company.svg").write_text(company)
