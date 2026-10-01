"""Regression guards for exported mobile Web entrypoints and app manifests."""

import json
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

from package_mobile_web_pwa import package_pwa
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
        (self.root / "index.service.worker.js").write_text('const FILES=["index.pck","index.wasm"];')
        self.manifest = {"display": "standalone", "orientation": "landscape", "start_url": "./index.html", "icons": []}
        for size in (192, 512):
            name = f"index.{size}x{size}.png"
            (self.root / name).write_bytes(fixture_png(size))
            self.manifest["icons"].append({"sizes": f"{size}x{size}", "src": name, "type": "image/png"})
        self.write_manifest()

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


if __name__ == "__main__":
    unittest.main()
