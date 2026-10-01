"""Complete Godot's generated PWA manifest before the release is checksummed."""

from __future__ import annotations

import json
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
