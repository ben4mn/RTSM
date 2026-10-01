#!/usr/bin/env python3
"""Fail-closed, non-disclosing verification for Pocket Kingdoms Web artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
import zipfile
from html.parser import HTMLParser
from pathlib import Path

from package_mobile_web_pwa import png_dimensions


MANIFEST_LINE = re.compile(r"^([0-9a-f]{64})  \./(.+)$")
URL_PATTERN = re.compile(rb"https?://[^\x00-\x20\"'<>\\]+", re.IGNORECASE)
ALLOWED_URL_PREFIXES = (
    b"http://www.w3.org/",
    b"https://www.w3.org/",
    b"https://kenney.nl/",
    b"https://developer.mozilla.org/",
    b"https://emscripten.org/",
    b"https://godotengine.org/",
)
ALLOWED_EXACT_URLS = (b"https://godotengine.org",)
ABSOLUTE_PATH_PATTERN = re.compile(rb"(?:file://)?/Users/|[A-Z]:\\\\Users\\\\", re.IGNORECASE)
LOCAL_URL_PATTERN = re.compile(
    rb"https?://(?:localhost|127(?:\.[0-9]{1,3}){3}|\[::1\]|0\.0\.0\.0)(?::[0-9]+)?(?:/|$)",
    re.IGNORECASE,
)
TUNNEL_URL_PATTERN = re.compile(
    rb"https?://(?:[^/@\s]+@)?(?:[^/\s.]+\.)?"
    rb"(?:ngrok\.io|ngrok-free\.app|trycloudflare\.com|loca\.lt|"
    rb"localtunnel\.me|localhost\.run|serveo\.net|tunnelto\.dev|"
    rb"pinggy\.io|bore\.pub)(?::[0-9]+)?(?:/|$)",
    re.IGNORECASE,
)
CREDENTIAL_PATTERN = re.compile(
    rb"(?:api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|"
    rb"private[_-]?key|password|passwd)\s*[:=]\s*[\"']?[A-Za-z0-9_./+=:-]{8,}"
    rb"|authorization\s*:\s*(?:basic|bearer)\s+[A-Za-z0-9._~+/-]{8,}"
    rb"|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|gh[pousr]_[A-Za-z0-9]{20,}"
    rb"|glpat-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}"
    rb"|sk_live_[A-Za-z0-9]{16,}|sk-[A-Za-z0-9]{20,}",
    re.IGNORECASE,
)
PEM_HEADER_PATTERN = re.compile(rb"-----BEGIN[ ]+[A-Z0-9 ]*PRIVATE[ ]KEY-----", re.IGNORECASE)
PEM_KEY_BLOCK_PATTERN = re.compile(
    rb"-----BEGIN[ ]+([A-Z0-9 ]*PRIVATE[ ]KEY)-----\r?\n"
    rb"(?:[A-Za-z0-9+/=]{16,}\r?\n)+"
    rb"-----END[ ]+\1-----",
    re.IGNORECASE,
)
DEV_SYMBOL_PATTERN = re.compile(
    rb"res://(?:addons/godot_mcp|tools|tests|docs|reports|output|build|"
    rb"\.playwright-cli|\.tmp_phone_test|\.godot-mcp)(?:/|$)"
    rb"|godot_mcp|mcp_game_bridge|debug_bootstrap\.gd|debug_panel\.gd",
    re.IGNORECASE,
)
SOURCEMAP_MARKER_PATTERN = re.compile(rb"(?:sourceMappingURL|sourceURL)\s*=", re.IGNORECASE)
SENSITIVE_NAME_PATTERNS = (
    re.compile(r"^\.env(?:\..*)?$", re.IGNORECASE),
    re.compile(r"^\.(?:npmrc|pypirc|netrc)$", re.IGNORECASE),
    re.compile(r"^id_(?:rsa|ed25519)$", re.IGNORECASE),
    re.compile(r".*\.(?:pem|key|p12|pfx|jks|keystore|mobileprovision|map)$", re.IGNORECASE),
    re.compile(r"^(?:google-services\.json|GoogleService-Info\.plist)$", re.IGNORECASE),
    re.compile(r".*(?:credential|credentials|secret).*", re.IGNORECASE),
)


class VerificationError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def regular_files(root: Path) -> list[Path]:
    return sorted(path for path in root.rglob("*") if path.is_file() and not path.is_symlink())


def inspect_tree(root: Path) -> dict[str, int]:
    if not root.is_dir():
        raise VerificationError(f"missing artifact root: {root}")
    counts = {"symlinks": 0, "special": 0, "sensitive_names": 0, "sourcemap_files": 0}
    for path in root.rglob("*"):
        mode = path.lstat().st_mode
        if stat.S_ISLNK(mode):
            counts["symlinks"] += 1
            continue
        if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
            counts["special"] += 1
        if stat.S_ISREG(mode):
            if any(pattern.fullmatch(path.name) for pattern in SENSITIVE_NAME_PATTERNS):
                counts["sensitive_names"] += 1
            if path.suffix.lower() == ".map":
                counts["sourcemap_files"] += 1
    return counts


def verify_manifest(root: Path) -> tuple[int, str]:
    manifest = root / "SHA256SUMS.txt"
    entries: dict[str, str] = {}
    for line in manifest.read_text(encoding="utf-8").splitlines():
        match = MANIFEST_LINE.fullmatch(line)
        if match is None:
            raise VerificationError("malformed checksum manifest")
        relative = match.group(2)
        if relative in entries or relative == "SHA256SUMS.txt" or Path(relative).is_absolute() or ".." in Path(relative).parts:
            raise VerificationError("unsafe or duplicate checksum entry")
        entries[relative] = match.group(1)
    actual = {
        path.relative_to(root).as_posix()
        for path in regular_files(root)
        if path.name != "SHA256SUMS.txt"
    }
    if set(entries) != actual:
        raise VerificationError("checksum manifest does not close over artifact files")
    for relative, expected in entries.items():
        if sha256(root / relative) != expected:
            raise VerificationError("checksum mismatch")
    return len(entries), sha256(manifest)


def installed_template_wasm_sha(root: Path) -> str:
    version = json.loads((root / "version.json").read_text(encoding="utf-8"))
    template_version = str(version["godot"]).split(".official", 1)[0]
    archive = (
        Path.home()
        / "Library"
        / "Application Support"
        / "Godot"
        / "export_templates"
        / template_version
        / "web_nothreads_release.zip"
    )
    with zipfile.ZipFile(archive) as handle, handle.open("godot.wasm") as wasm:
        digest = hashlib.sha256()
        for chunk in iter(lambda: wasm.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def scan_content(root: Path) -> dict[str, int]:
    corpus = b""
    pem_header_non_wasm = 0
    unexpected_urls: set[bytes] = set()
    dev_symbols = 0
    stock_wasm_template_match = int(sha256(root / "index.wasm") == installed_template_wasm_sha(root))
    for path in regular_files(root):
        payload = path.read_bytes()
        corpus += payload + b"\n"
        if path.name != "index.wasm":
            pem_header_non_wasm += len(PEM_HEADER_PATTERN.findall(payload))
        if path.name != "index.wasm" or not stock_wasm_template_match:
            unexpected_urls.update(
                url
                for url in URL_PATTERN.findall(payload)
                if url.lower() not in ALLOWED_EXACT_URLS
                and not any(url.lower().startswith(prefix.lower()) for prefix in ALLOWED_URL_PREFIXES)
            )
        if path.name not in {"CONTENT_AUDIT.txt", "SOURCE_SHA256SUMS.txt", "SHA256SUMS.txt"}:
            dev_symbols += len(DEV_SYMBOL_PATTERN.findall(payload))
    return {
        "absolute_paths": len(ABSOLUTE_PATH_PATTERN.findall(corpus)),
        "credentials": len(CREDENTIAL_PATTERN.findall(corpus)),
        "localhost_urls": len(LOCAL_URL_PATTERN.findall(corpus)),
        "tunnel_urls": len(TUNNEL_URL_PATTERN.findall(corpus)),
        "unexpected_urls": len(unexpected_urls),
        "dev_symbols": dev_symbols,
        "sourcemap_markers": len(SOURCEMAP_MARKER_PATTERN.findall(corpus)),
        "pem_key_blocks": len(PEM_KEY_BLOCK_PATTERN.findall(corpus)),
        "pem_header_non_wasm": pem_header_non_wasm,
        "pem_header_literals": len(PEM_HEADER_PATTERN.findall(corpus)),
        "stock_wasm_template_match": stock_wasm_template_match,
    }


def verify_service_worker(root: Path) -> None:
    html = (root / "index.html").read_text(encoding="utf-8")
    worker = (root / "index.service.worker.js").read_text(encoding="utf-8")
    if "index.service.worker.js" not in html:
        raise VerificationError("HTML does not register the relative service worker")
    for required in ("index.pck", "index.wasm"):
        if required not in worker:
            raise VerificationError(f"service worker omits {required}")
    worker_bytes = worker.encode()
    if ABSOLUTE_PATH_PATTERN.search(worker_bytes) or LOCAL_URL_PATTERN.search(worker_bytes) or TUNNEL_URL_PATTERN.search(worker_bytes):
        raise VerificationError("service worker contains a forbidden absolute/local/tunnel reference")
    manifest_name = "index.manifest.json"
    if not (root / manifest_name).is_file() or manifest_name not in html:
        raise VerificationError("HTML-linked Web manifest missing")
    manifest = json.loads((root / manifest_name).read_text(encoding="utf-8"))
    if manifest.get("display") not in {"standalone", "fullscreen"}:
        raise VerificationError("Web manifest does not request an app window")
    if manifest.get("orientation") != "landscape":
        raise VerificationError("Web manifest omits landscape preference")
    if manifest.get("start_url") != "./index.html":
        raise VerificationError("Web manifest entrypoint must remain relative")
    icons = manifest.get("icons", [])
    if not isinstance(icons, list):
        raise VerificationError("Web manifest icons must be a list")
    for size in (192, 512):
        expected_name = f"index.{size}x{size}.png"
        matching = [entry for entry in icons if isinstance(entry, dict) and entry.get("sizes") == f"{size}x{size}"
                    and entry.get("src") == expected_name and entry.get("type") == "image/png"]
        if len(matching) != 1:
            raise VerificationError(f"Web manifest needs one {size}-pixel PNG icon")
        try:
            actual_size = png_dimensions(root / expected_name)
        except (OSError, ValueError) as exc:
            raise VerificationError(f"Web manifest {size}-pixel icon is missing or invalid") from exc
        if actual_size != (size, size):
            raise VerificationError(f"Web manifest {size}-pixel icon has incorrect dimensions")


class ShellMetadata(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.meta: dict[str, str] = {}
        self.ids: set[str] = set()

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        if tag == "meta":
            self.meta[str(attributes.get("name", ""))] = str(attributes.get("content", ""))
        if attributes.get("id"):
            self.ids.add(str(attributes["id"]))


def verify_web_shell(root: Path) -> None:
    html = (root / "index.html").read_text(encoding="utf-8")
    metadata = ShellMetadata()
    metadata.feed(html)
    if "viewport-fit=cover" not in metadata.meta.get("viewport", ""):
        raise VerificationError("Web shell omits safe-area viewport support")
    if metadata.meta.get("apple-mobile-web-app-capable") != "yes":
        raise VerificationError("Web shell omits Apple standalone support")
    required_ids = {"canvas", "pocket-game", "pocket-screen-control", "pocket-screen-help", "pocket-web-shell-script"}
    if not required_ids.issubset(metadata.ids) or "PocketWebShell" not in html:
        raise VerificationError("Export did not retain the source-controlled screen shell")
    config_match = re.search(r"const GODOT_CONFIG = (\{[^\n]+\});", html)
    if config_match is None or json.loads(config_match.group(1)).get("canvasResizePolicy") != 0:
        raise VerificationError("Web shell needs external canvas resize ownership")
    if not re.search(r"const GODOT_THREADS_ENABLED = false;", html):
        raise VerificationError("Mobile Web export must remain single-threaded")


def normalized_version(root: Path) -> dict[str, object]:
    payload = json.loads((root / "version.json").read_text(encoding="utf-8"))
    payload.pop("built_at_utc", None)
    return payload


def normalized_worker(root: Path) -> str:
    worker = (root / "index.service.worker.js").read_text(encoding="utf-8")
    return re.sub(r"^const CACHE_VERSION = .+;$", "const CACHE_VERSION = <normalized>;", worker, flags=re.MULTILINE)


def verify_reproducibility(canonical: Path, reproduced: Path) -> None:
    allowed = {"SHA256SUMS.txt", "version.json", "index.service.worker.js"}
    canonical_files = {path.relative_to(canonical).as_posix() for path in regular_files(canonical)}
    reproduced_files = {path.relative_to(reproduced).as_posix() for path in regular_files(reproduced)}
    if canonical_files != reproduced_files:
        raise VerificationError("artifact file sets differ")
    for relative in sorted(canonical_files - allowed):
        if sha256(canonical / relative) != sha256(reproduced / relative):
            raise VerificationError("unexpected substantive artifact difference")
    if (canonical / "SOURCE_SHA256SUMS.txt").read_bytes() != (reproduced / "SOURCE_SHA256SUMS.txt").read_bytes():
        raise VerificationError("staged source manifests differ")
    if normalized_version(canonical) != normalized_version(reproduced):
        raise VerificationError("version metadata has an unexpected difference")
    if normalized_worker(canonical) != normalized_worker(reproduced):
        raise VerificationError("service worker has an unexpected difference")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("canonical", type=Path)
    parser.add_argument("reproduced", type=Path)
    args = parser.parse_args()
    roots = (("artifact-canonical", args.canonical.resolve()), ("artifact-repro-b", args.reproduced.resolve()))
    try:
        summaries: dict[str, dict[str, int]] = {}
        manifest_counts: dict[str, int] = {}
        for label, root in roots:
            tree = inspect_tree(root)
            manifest_counts[label], _ = verify_manifest(root)
            content = scan_content(root)
            verify_service_worker(root)
            verify_web_shell(root)
            summaries[label] = tree | content
            if summaries[label]["stock_wasm_template_match"] != 1:
                raise VerificationError(f"{label} WebAssembly does not match the installed release template")
            informational = {"pem_header_literals", "stock_wasm_template_match"}
            if any(value for key, value in summaries[label].items() if key not in informational):
                raise VerificationError(f"{label} sensitive-material count is nonzero")
        verify_reproducibility(args.canonical.resolve(), args.reproduced.resolve())
        version = json.loads((args.canonical / "version.json").read_text(encoding="utf-8"))
        print("AOEM_SENSITIVE_MATERIAL_SCAN format=1 date=2026-09-13")
        print(f"source_revision={version['source_revision']}")
        print(f"source_dirty={str(version['source_dirty']).lower()}")
        print(f"source_tree_sha256={version['source_tree_sha256']}")
        for label, _ in roots:
            values = summaries[label]
            joined = " ".join(f"{key}={value}" for key, value in values.items())
            print(f"[PASS] {label} manifest_entries={manifest_counts[label]} {joined}")
            print(f"[INFO] {label} pem_header_literals are stock WebAssembly format constants; pem_key_blocks=0")
            print(f"[PASS] {label} stock_wasm_template_match=true")
            print(f"[PASS] {label} checksum_closure=PASS service_worker_static=PASS")
            print(f"[PASS] {label} fullscreen_shell=PASS standalone_manifest=PASS safe_area_resize=PASS")
        print("[PASS] reproducibility substantive_files_equal=true source_manifest_equal=true")
        print("[PASS] reproducibility version_allowed_delta_only=true service_worker_allowed_delta_only=true")
        print("RESULT=PASS")
        return 0
    except (OSError, UnicodeError, json.JSONDecodeError, VerificationError) as exc:
        print(f"[FAIL] verification category={type(exc).__name__}")
        print("RESULT=FAIL")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
