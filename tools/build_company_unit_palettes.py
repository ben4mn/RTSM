#!/usr/bin/env python3
"""Refresh the company miniatures' cloth-only opponent variants.

Skin, straw, hair, bone, metal, leather and wood keep their base material colors.
Geometry and alpha are identical. Scout and menu art are untouched.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PALETTE = {"#406861": "#855949", "#6E9C94": "#BD8067", "#A9C7BB": "#DFB498"}


def main() -> None:
    for name in ("worker", "warrior", "archer", "cavalry", "siege", "longbow", "outrider"):
        path = ROOT / "assets/units" / f"{name}.svg"
        source = path.read_text(encoding="utf-8")
        for base, alternate in PALETTE.items():
            source = source.replace(base, alternate)
        path.with_name(f"{name}_enemy.svg").write_text(source, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
