"""Small deterministic packaging checks; no engine export or browser required."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from package_mobile_web_pwa import package_update_worker


class PackageUpdatesTest(unittest.TestCase):
    def make_payload(self, root):
        for name in ["index.js", "index.wasm", "index.pck", "pocket_updates.js", "playtest_diagnostics.js", "index.offline.html", "release_notes.json"]:
            (root / name).write_text(name)
        (root / "index.html").write_text("<script>window.POCKET_RELEASE = /*POCKET_RELEASE*/null;</script>")
        version = {"source_revision": "abcdefabcdef", "source_tree_sha256": "a" * 64, "built_at_utc": "first"}
        (root / "version.json").write_text(json.dumps(version))
        return version

    def test_hashes_and_reproducibility(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            version = self.make_payload(root)
            template = Path(__file__).resolve().parent.parent / "web" / "pocket_service_worker.js"
            package_update_worker(root, template)
            worker = (root / "index.service.worker.js").read_bytes()
            html = (root / "index.html").read_bytes()
            manifest = json.loads((root / "pocket-cache-manifest.json").read_text())
            self.assertNotIn("version.json", manifest["files"])
            self.assertNotIn("index.service.worker.js", manifest["files"])
            self.assertNotIn("index.pck", manifest["shell"])
            self.assertNotIn("built_at_utc", html.decode())
            for name, digest in manifest["files"].items():
                self.assertEqual(hashlib.sha256((root / name).read_bytes()).hexdigest(), digest)
            version["built_at_utc"] = "second"
            (root / "version.json").write_text(json.dumps(version))
            package_update_worker(root, template)
            self.assertEqual(worker, (root / "index.service.worker.js").read_bytes())
            self.assertEqual(html, (root / "index.html").read_bytes())

    def test_rejects_incomplete_payload_and_unknown_directories(self):
        for defect in ["missing", "directory", "symlink", "revision"]:
            with self.subTest(defect=defect), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                version = self.make_payload(root)
                if defect == "missing":
                    (root / "index.pck").unlink()
                elif defect == "directory":
                    (root / "untracked").mkdir()
                elif defect == "symlink":
                    (root / "alias").symlink_to(root / "index.js")
                else:
                    version["source_revision"] = "unknown"
                    (root / "version.json").write_text(json.dumps(version))
                with self.assertRaises(ValueError):
                    package_update_worker(root)


if __name__ == "__main__":
    unittest.main()
