"""Regression guards for exported mobile Web entrypoints and app manifests."""

import json
import re
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

from package_mobile_web_pwa import package_pwa, package_update_worker
from verify_mobile_web_artifacts import VerificationError, verify_service_worker, verify_web_shell


def fixture_png(size: int) -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    pixels = (b"\0" + b"\x13\x22\x2c\xff" * size) * size
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b"")


class MobileShellArtifactTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        source = (Path(__file__).resolve().parents[1] / "web/pocket_shell.html").read_text()
        self.html = source.replace("$GODOT_CONFIG", '{"canvasResizePolicy":0}').replace("$GODOT_THREADS_ENABLED", "false")
        self.html = self.html.replace("$GODOT_HEAD_INCLUDE", '<link rel="manifest" href="index.manifest.json">')
        self.html = self.html.replace("$GODOT_URL", "index.js")
        self.html += '<!-- index.service.worker.js -->'
        (self.root / "index.html").write_text(self.html)
        for name in ("index.js", "index.wasm", "index.pck", "index.offline.html"):
            (self.root / name).write_text("fixture")
        for name in ("playtest_diagnostics.js", "pocket_launch.js", "pocket_launch.css", "pocket_updates.js", "field_atlas.svg", "release_notes.json"):
            (self.root / name).write_bytes((Path(__file__).resolve().parents[1] / "web" / name).read_bytes())
        for name in ("Barlow-Regular.ttf", "Barlow-Medium.ttf", "BarlowCondensed-SemiBold.ttf", "barlow-OFL.txt", "barlowcondensed-OFL.txt"):
            (self.root / name).write_bytes((Path(__file__).resolve().parents[1] / "assets/fonts" / name).read_bytes())
        assets = Path(__file__).resolve().parents[1] / "assets/ui"
        for source in [assets / "kingdom_company_v2.png", assets / "icons/play_dark.svg"] + [assets / "plates" / f"{kind}_{state}.svg" for kind in ("primary", "secondary") for state in ("normal", "hover", "pressed")]:
            (self.root / source.name).write_bytes(source.read_bytes())
        (self.root / "version.json").write_text(json.dumps({"source_revision": "abcdef012345", "source_tree_sha256": "a" * 64, "source_dirty": False, "version": "test"}))
        self.manifest = {"display": "standalone", "orientation": "landscape", "start_url": "./index.html", "icons": []}
        for size in (192, 512):
            name = f"index.{size}x{size}.png"
            (self.root / name).write_bytes(fixture_png(size))
            self.manifest["icons"].append({"sizes": f"{size}x{size}", "src": name, "type": "image/png"})
        self.write_manifest()
        package_pwa(self.root)
        package_update_worker(self.root)
        self.html = (self.root / "index.html").read_text()

    def write_manifest(self) -> None:
        (self.root / "index.manifest.json").write_text(json.dumps(self.manifest))

    def test_source_shell_and_app_manifest_are_valid(self) -> None:
        verify_web_shell(self.root)
        verify_service_worker(self.root)

    def test_stock_shell_fallback_is_rejected(self) -> None:
        (self.root / "index.html").write_text(self.html.replace('id="pocket-web-shell-script"', 'id="old-shell"'))
        with self.assertRaises(VerificationError):
            verify_web_shell(self.root)

    def test_engine_cannot_take_over_safe_viewport_size(self) -> None:
        (self.root / "index.html").write_text(self.html.replace('"canvasResizePolicy":0', '"canvasResizePolicy":2'))
        with self.assertRaises(VerificationError):
            verify_web_shell(self.root)

    def test_render_surface_fills_viewport_without_safe_area_crop(self) -> None:
        rule = re.search(r"#pocket-game\s*\{([^}]+)\}", self.html)
        self.assertIsNotNone(rule)
        declarations = rule.group(1)
        self.assertRegex(declarations, r"inset:\s*0\s*;")
        self.assertNotIn("safe-area", declarations)
        self.assertNotRegex(declarations, r"(?:padding|margin)(?:-\w+)?:")

    def test_safe_area_probe_and_listener_contract_are_exported(self) -> None:
        self.assertIn('id="pocket-safe-area"', self.html)
        for side in ("left", "top", "right", "bottom"):
            self.assertIn(f"--pocket-safe-{side}: env(safe-area-inset-{side}, 0px)", self.html)
            self.assertIn(f"padding-{side}: var(--pocket-safe-{side})", self.html)
        for method in ("getSafeArea", "getMenuTopClearance", "addSafeAreaListener", "removeSafeAreaListener"):
            self.assertIn(method + ": function", self.html)
        self.assertIn(".observe(safeAreaProbe)", self.html)

    def test_threaded_mobile_export_is_rejected(self) -> None:
        (self.root / "index.html").write_text(self.html.replace('const GODOT_THREADS_ENABLED = false;', 'const GODOT_THREADS_ENABLED = true;'))
        with self.assertRaises(VerificationError):
            verify_web_shell(self.root)

    def test_browser_bookmark_manifest_is_rejected(self) -> None:
        self.manifest["display"] = "browser"
        self.write_manifest()
        with self.assertRaises(VerificationError):
            verify_service_worker(self.root)

    def test_absolute_app_entrypoint_is_rejected(self) -> None:
        self.manifest["start_url"] = "https://example.test/index.html"
        self.write_manifest()
        with self.assertRaises(VerificationError):
            verify_service_worker(self.root)

    def test_missing_landscape_preference_is_rejected(self) -> None:
        self.manifest.pop("orientation")
        self.write_manifest()
        with self.assertRaises(VerificationError):
            verify_service_worker(self.root)

    def test_missing_chromium_icon_is_rejected(self) -> None:
        self.manifest["icons"] = self.manifest["icons"][1:]
        self.write_manifest()
        with self.assertRaises(VerificationError):
            verify_service_worker(self.root)

    def test_wrong_icon_dimensions_are_rejected(self) -> None:
        (self.root / "index.192x192.png").write_bytes(fixture_png(180))
        with self.assertRaises(VerificationError):
            verify_service_worker(self.root)

    def test_missing_icon_file_is_rejected(self) -> None:
        (self.root / "index.192x192.png").unlink()
        with self.assertRaises(VerificationError):
            verify_service_worker(self.root)

    def test_corrupt_icon_is_rejected(self) -> None:
        (self.root / "index.192x192.png").write_bytes(b"not a PNG")
        with self.assertRaises(VerificationError):
            verify_service_worker(self.root)

    def test_icon_packaging_is_idempotent_and_keeps_other_icons(self) -> None:
        self.manifest["icons"] = self.manifest["icons"][1:]
        self.write_manifest()
        package_pwa(self.root)
        once = (self.root / "index.manifest.json").read_bytes()
        package_pwa(self.root)
        self.assertEqual(once, (self.root / "index.manifest.json").read_bytes())
        verify_service_worker(self.root)

    def test_packaging_rejects_wrong_192_bitmap(self) -> None:
        (self.root / "index.192x192.png").write_bytes(fixture_png(180))
        with self.assertRaises(ValueError):
            package_pwa(self.root)

    def test_update_payload_tampering_is_rejected(self) -> None:
        (self.root / "pocket_launch.js").write_text("changed after packaging")
        with self.assertRaises(VerificationError):
            verify_service_worker(self.root)

    def test_missing_welcome_art_is_rejected(self) -> None:
        (self.root / "field_atlas.svg").unlink()
        with self.assertRaises(VerificationError):
            verify_service_worker(self.root)

    def test_manifest_identity_and_complete_shell_are_required(self) -> None:
        original = json.loads((self.root / "pocket-cache-manifest.json").read_text())
        worker = (self.root / "index.service.worker.js").read_text()
        for key, value in [("id", "wrong-release"), ("revision", "eeeeeeeeeeee"), ("sourceTreeSha256", "b" * 64), ("shell", ["index.html"])]:
            with self.subTest(key=key):
                changed = dict(original, **{key: value})
                serialized = json.dumps(changed, sort_keys=True, separators=(",", ":"))
                (self.root / "pocket-cache-manifest.json").write_text(serialized)
                changed_worker = re.sub(r"const POCKET_SW_RELEASE = /\*POCKET_SW_RELEASE\*/\{[^\n]+\};", "const POCKET_SW_RELEASE = /*POCKET_SW_RELEASE*/" + serialized + ";", worker)
                (self.root / "index.service.worker.js").write_text(changed_worker)
                with self.assertRaises(VerificationError):
                    verify_service_worker(self.root)

    def test_stock_worker_cannot_replace_update_protocol(self) -> None:
        (self.root / "index.service.worker.js").write_text('const FILES=["index.pck","index.wasm"];')
        with self.assertRaises(VerificationError):
            verify_service_worker(self.root)


if __name__ == "__main__":
    unittest.main()
