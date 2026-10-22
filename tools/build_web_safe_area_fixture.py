#!/usr/bin/env python3
"""Build a browser fixture from the real shell CSS, DOM and safe-area script.

This omits the Godot engine and launch lifecycle so CSS geometry can be tested
independently. Open the generated index.html in a real browser and await
window.PocketSafeAreaFixture.run(). The fixture does not imitate game UI.
"""
from pathlib import Path
import argparse
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]


def build(destination: Path) -> None:
    source = (ROOT / "web/pocket_shell.html").read_text()
    script = re.search(r'<script id="pocket-web-shell-script">(.*?)</script>', source, re.S)
    if script is None:
        raise RuntimeError("Source-controlled shell script is missing")
    # Retain actual CSS and DOM. Only executable engine/launch scripts and
    # unresolved Godot template placeholders are removed from this fixture.
    html = re.sub(r"<script\b[^>]*>.*?</script>", "", source, flags=re.S)
    html = re.sub(r"\$GODOT_[A-Z_]+", "", html)
    html = re.sub(r'<img\b[^>]*src="index.192x192.png"[^>]*>', "", html)
    setup = """<script>
    window.PocketLaunch = {
        setControlsVisible(visible) {document.getElementById('pocket-shell-links').hidden = !visible;},
        setUpdateSafe() {return true;}
    };
    // The actual diagnostics UI is exercised with transport disabled. Nothing
    // from this isolated geometry fixture is sent to a diagnostics service.
    window.fetch = async () => new Response('{}', {status: 200, headers: {'Content-Type': 'application/json'}});
    Object.defineProperty(navigator, 'sendBeacon', {value: () => true});
    document.body.classList.remove('pocket-welcome');
    document.getElementById('pocket-welcome').hidden = true;
    </script>"""
    harness = (ROOT / "tools/web_safe_area_fixture.js").read_text()
    diagnostics = (ROOT / "web/playtest_diagnostics.js").read_text()
    html = html.replace("</body>", setup + "<script>" + diagnostics + "</script><script>" + script.group(1) + "</script><script>" + harness + "</script></body>")
    html = html.replace("</head>", '<link rel="icon" href="data:,"></head>')
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "index.html").write_text(html)
    for name in ["pocket_launch.css", "field_atlas.svg"]:
        shutil.copy2(ROOT / "web" / name, destination / name)
    for font in (ROOT / "assets/fonts").glob("*.ttf"):
        shutil.copy2(font, destination / font.name)
    shutil.copy2(ROOT / "assets/ui/field_company.png", destination / "field_company.png")
    shutil.copy2(ROOT / "assets/ui/icons/play_dark.svg", destination / "play_dark.svg")
    for plate in (ROOT / "assets/ui/plates").glob("*.svg"):
        shutil.copy2(plate, destination / plate.name)
    print(destination / "index.html")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "output/playwright/safe-area-fixture")
    build(parser.parse_args().output)
