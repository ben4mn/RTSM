"""Complete Godot's generated PWA manifest before the release is checksummed."""

from __future__ import annotations

import json
import hashlib
import re
import struct
import zlib
from pathlib import Path


def png_dimensions(path: Path) -> tuple[int, int]:
    header = path.read_bytes()[:33]
    if len(header) != 33 or header[:16] != b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR":
        raise ValueError("invalid PNG header")
    if zlib.crc32(header[12:29]) != struct.unpack(">I", header[29:33])[0]:
        raise ValueError("invalid PNG header checksum")
    return struct.unpack(">II", header[16:24])


def package_pwa(root: Path) -> None:
    icon_name = "index.192x192.png"
    if png_dimensions(root / icon_name) != (192, 192):
        raise ValueError("PWA icon must be 192 by 192 pixels")
    manifest_path = root / "index.manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    icons = manifest.get("icons")
    if not isinstance(icons, list):
        raise ValueError("PWA manifest must contain icons")
    manifest["icons"] = [entry for entry in icons if entry.get("src") != icon_name]
    manifest["icons"].append({"sizes": "192x192", "src": icon_name, "type": "image/png"})
    manifest_path.write_text(json.dumps(manifest, separators=(",", ":")) + "\n", encoding="utf-8")


def package_update_worker(root: Path, template_path: Path | None = None) -> None:
    """Bind the worker to one complete release, after version.json is written.

    The worker itself cannot be part of its own hash map. The outer release
    SHA256SUMS still covers it, the cache manifest, and every public payload.
    """
    template_path = template_path or Path(__file__).resolve().parent.parent / "web" / "pocket_service_worker.js"
    version = json.loads((root / "version.json").read_text(encoding="utf-8"))
    if not re.fullmatch(r"[0-9a-f]{12}", str(version.get("source_revision", ""))):
        raise ValueError("update payload requires a concrete runtime revision")
    if not re.fullmatch(r"[0-9a-f]{64}", str(version.get("source_tree_sha256", ""))):
        raise ValueError("update payload requires a source fingerprint")
    html_path = root / "index.html"
    html = html_path.read_text(encoding="utf-8")
    marker = re.compile(r"window\.POCKET_RELEASE\s*=\s*/\*POCKET_RELEASE\*/(?:null|.*?/\*END_POCKET_RELEASE\*/)\s*;", re.DOTALL)
    loaded_version = {key: value for key, value in version.items() if key != "built_at_utc"}
    replacement = "window.POCKET_RELEASE = /*POCKET_RELEASE*/" + json.dumps(loaded_version, sort_keys=True, separators=(",", ":")) + "/*END_POCKET_RELEASE*/;"
    html, count = marker.subn(lambda _: replacement, html)
    if count != 1:
        raise ValueError("shell must have exactly one POCKET_RELEASE injection marker")
    html_path.write_text(html, encoding="utf-8")
    # version.json is deliberately network-only: its timestamp describes the
    # served export, while the inline deterministic metadata describes this page.
    excluded = {"index.service.worker.js", "pocket-cache-manifest.json", "version.json", "SHA256SUMS.txt", "SOURCE_SHA256SUMS.txt", "CONTENT_AUDIT.txt"}
    files = {}
    for path in sorted(root.iterdir()):
        if path.is_symlink() or not path.is_file():
            raise ValueError("update payload contains unsupported entries")
        if path.is_file() and path.name not in excluded:
            files[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    required = {"index.html", "index.js", "index.wasm", "index.pck", "pocket_updates.js", "pocket_launch.js", "pocket_launch.css", "playtest_diagnostics.js", "index.offline.html"}
    if not required.issubset(files):
        raise ValueError("update payload is missing required runtime files")
    identity = hashlib.sha256(json.dumps(files, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    release = {
        "id": version["source_revision"] + "-" + identity[:20],
        "revision": version["source_revision"],
        "sourceTreeSha256": version["source_tree_sha256"],
        "files": files,
        "shell": [name for name in files if name not in {"index.js", "index.wasm", "index.pck"}],
    }
    serialized = json.dumps(release, sort_keys=True, separators=(",", ":"))
    (root / "pocket-cache-manifest.json").write_text(serialized + "\n", encoding="utf-8")
    template = template_path.read_text(encoding="utf-8")
    if template.count("/*POCKET_SW_RELEASE*/null") != 1:
        raise ValueError("worker must have exactly one release injection marker")
    (root / "index.service.worker.js").write_text(template.replace("/*POCKET_SW_RELEASE*/null", "/*POCKET_SW_RELEASE*/" + serialized), encoding="utf-8")
