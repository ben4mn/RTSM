#!/usr/bin/env python3
"""Build the audited mobile Web payload without Unix-only shell utilities.

By default, runtime inputs come exclusively from one Git commit, even if the
checkout is being edited. --working-tree is an explicit local-playtest mode and
marks the payload dirty. Output directories are immutable and must be direct
children of build/. This script does not deploy or change the Git checkout.
"""

from __future__ import annotations

import argparse
import datetime as dt
import fnmatch
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path, PurePosixPath

from package_mobile_web_pwa import package_pwa, package_update_worker
from verify_mobile_web_artifacts import (
    VerificationError, inspect_tree, scan_content, sha256, verify_manifest,
    verify_service_worker, verify_web_shell,
)


SOURCE_ROOTS = (
    "assets", "scenes", "scripts", "web", "default_bus_layout.tres",
    "export_presets.cfg", "icon.svg", "icon.svg.import", "project.godot",
)
DEBUG_NAMES = {"debug_bootstrap.gd", "debug_bootstrap.gd.uid", "debug_panel.gd", "debug_panel.gd.uid"}
DEV_PATTERNS = ("*.log", "*.md", "*.py", "*.pyc", "*.pyo", "*.bak", "*.tmp", "*.orig", "*.rej", "test_*.gd", "test_*.tscn", "*_test.gd", "*_test.tscn")
WEB_ASSETS = ("playtest_diagnostics.js", "pocket_updates.js", "pocket_launch.js", "pocket_launch.css", "field_atlas.svg", "release_notes.json")
FONTS = ("Barlow-Regular.ttf", "Barlow-Medium.ttf", "BarlowCondensed-SemiBold.ttf", "barlow-OFL.txt", "barlowcondensed-OFL.txt")


class BuildError(RuntimeError):
    pass


def git(root: Path, *arguments: str) -> bytes:
    return subprocess.check_output(["git", "-C", str(root), *arguments], stderr=subprocess.PIPE)


def network_protocol(root: Path) -> int:
    """Read one literal protocol from the frozen runtime, never the checkout."""
    path = root / "scripts/network/network_session.gd"
    if path.is_symlink() or not path.is_file():
        raise BuildError("Frozen network protocol source is missing or special")
    source = path.read_text(encoding="utf-8")
    declarations = re.findall(r"^[ \t]*const[ \t]+PROTOCOL\b[^\r\n]*$", source, re.MULTILINE)
    if len(declarations) != 1:
        raise BuildError("Expected one frozen network protocol declaration")
    match = re.fullmatch(r"const\s+PROTOCOL\s*(?::\s*int\s*=|:=|=)\s*([1-9][0-9]*)\s*(?:#[^\r\n]*)?", declarations[0])
    if not match or int(match.group(1)) > 9007199254740991:
        raise BuildError("Frozen network protocol must be a positive exact JSON integer literal")
    return int(match.group(1))


def allowed_source(relative: str) -> bool:
    path = PurePosixPath(relative)
    if path.is_absolute() or ".." in path.parts or "\\" in relative:
        return False
    if not path.parts or path.parts[0] not in SOURCE_ROOTS:
        return False
    if relative.startswith("scripts/ui/") and path.name in DEBUG_NAMES:
        return False
    if any(part.startswith(".env") or part in (".DS_Store", "Thumbs.db", "desktop.ini") or part.startswith("._") for part in path.parts):
        return False
    return True


def stage_committed_source(root: Path, commit: str, stage: Path, helper: Path) -> None:
    # Ignore host checkout conversion so one commit yields the same bytes on
    # Windows, macOS and Linux even when core.autocrlf is enabled locally.
    payload = git(root, "-c", "core.autocrlf=false", "-c", "core.eol=lf", "archive", "--format=tar", commit, *SOURCE_ROOTS, "tools/render_pwa_icon.gd")
    with tarfile.open(fileobj=io.BytesIO(payload), mode="r:") as archive:
        for member in archive:
            if member.isdir():
                continue
            if not member.isfile():
                raise BuildError("Committed runtime contains a symlink or special entry")
            if member.name == "tools/render_pwa_icon.gd":
                destination = helper
            elif allowed_source(member.name):
                destination = stage.joinpath(*PurePosixPath(member.name).parts)
            else:
                continue
            handle = archive.extractfile(member)
            if handle is None:
                raise BuildError("Cannot read committed source")
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(handle.read())


def stage_working_source(root: Path, stage: Path, helper: Path) -> None:
    for name in SOURCE_ROOTS:
        source = root / name
        paths = [source] if source.is_file() else source.rglob("*")
        for path in paths:
            if path.is_symlink():
                raise BuildError("Working runtime contains a symlink")
            if not path.is_file():
                continue
            relative = path.relative_to(root).as_posix()
            if allowed_source(relative):
                destination = stage / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, destination)
    shutil.copyfile(root / "tools/render_pwa_icon.gd", helper)


def sanitize_project(text: str, revision: str) -> str:
    result = []
    section = ""
    for line in text.splitlines():
        if re.fullmatch(r"\[[^\]]+\]", line):
            section = line
        if section in {"[editor_plugins]", "[godot_mcp]"}:
            continue
        if re.match(r"\s*[A-Za-z_][A-Za-z0-9_]*\.debug\s*=", line) and section == "[autoload]":
            continue
        if line.startswith(("config/playtest_revision=", "export/convert_text_resources_to_binary=")):
            continue
        result.append(line)
        if line == "[application]":
            result.append(f'config/playtest_revision="{revision}"')
    # Match the established shell pipeline exactly, including a final section.
    return "\n".join(result) + "\n\n[editor]\nexport/convert_text_resources_to_binary=false\n"


def verify_stage(stage: Path) -> None:
    for path in stage.rglob("*"):
        relative = path.relative_to(stage).as_posix()
        if path.is_symlink():
            raise BuildError("Production stage contains a symlink")
        if relative == ".godot" or relative.startswith(".godot/"):
            continue
        if not path.is_file():
            continue
        if not allowed_source(relative) or any(fnmatch.fnmatchcase(path.name, pattern) for pattern in DEV_PATTERNS):
            raise BuildError(f"Developer-only file reached production stage: {relative}")
    text = (stage / "project.godot").read_text(encoding="utf-8")
    if re.search(r"\.debug\s*=|^\[editor_plugins\]$|^\[godot_mcp\]$|addons/godot_mcp|scripts/ui/debug_(bootstrap|panel)\.gd", text, re.MULTILINE):
        raise BuildError("Production project retains developer configuration")
    for marker in ('MCPGameBridge="res://scripts/managers/runtime_game_bridge.gd"', "export/convert_text_resources_to_binary=false"):
        if text.splitlines().count(marker) != 1:
            raise BuildError("Production project has invalid runtime configuration")
    options = (stage / "export_presets.cfg").read_text(encoding="utf-8").split("[preset.1.options]", 1)[1]
    if 'html/custom_html_shell="res://web/pocket_shell.html"' not in options or 'html/canvas_resize_policy=0' not in options:
        raise BuildError("Mobile preset must use the custom shell and shell-owned resizing")
    tree = inspect_tree(stage)
    if any(tree.values()):
        raise BuildError("Production stage contains sensitive or unsupported file names")


def write_manifest(root: Path, destination: Path, *, skip_cache: bool = False) -> None:
    files = []
    for path in root.rglob("*"):
        relative = path.relative_to(root)
        if skip_cache and relative.parts[0] == ".godot":
            continue
        if path.is_file() and path != destination:
            files.append((relative.as_posix(), path))
    destination.write_text("".join(f"{sha256(path)}  ./{relative}\n" for relative, path in sorted(files)), encoding="utf-8", newline="\n")


def output_directory(root: Path, requested: str) -> Path:
    build = root / "build"
    if build.is_symlink():
        raise BuildError("Refusing symlink build root")
    build.mkdir(exist_ok=True)
    build = build.resolve()
    marker = build / ".gdignore"
    if marker.is_symlink():
        raise BuildError("Refusing symlink Godot ignore marker")
    marker.touch()
    raw = Path(requested)
    if ".." in raw.parts:
        raise BuildError("Refusing output traversal")
    output = raw if raw.is_absolute() else root / raw
    if output.is_symlink() or output.parent.resolve() != build or output.name in {"", ".", ".gdignore"}:
        raise BuildError("Output must be a direct child of build")
    if output.exists():
        raise BuildError("Output already exists; choose a new immutable build name")
    return output


def run_godot(binary: Path, arguments: list[str], log: Path) -> None:
    result = subprocess.run([str(binary), *arguments], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=600)
    log.write_bytes(result.stdout)
    text = result.stdout.decode("utf-8", errors="replace")
    if result.returncode != 0 or re.search(r"SCRIPT ERROR:|^ERROR:", text, re.MULTILINE):
        raise BuildError(f"Godot failed; inspect {log}")


def verify_payload(root: Path) -> None:
    verify_manifest(root)
    verify_service_worker(root)
    verify_web_shell(root)
    counts = inspect_tree(root) | scan_content(root)
    if counts["stock_wasm_template_match"] != 1 or any(value for key, value in counts.items() if key not in {"stock_wasm_template_match", "pem_header_literals"}):
        raise BuildError("Public artifact content audit failed")


def build(args: argparse.Namespace) -> Path:
    root = Path(args.project).resolve()
    output = output_directory(root, args.output)
    binary = Path(args.godot).resolve()
    engine = subprocess.check_output([str(binary), "--version"], text=True).strip()
    if not re.match(r"^4\.6(?:\.|$)", engine):
        raise BuildError("Godot 4.6 is required")
    commit = git(root, "rev-parse", "--verify", args.revision + "^{commit}").decode().strip()
    revision = commit[:12]
    work = Path(tempfile.mkdtemp(prefix=".web-build-", dir=root / "build"))
    stage, exported = work / "project", work / "export"
    stage.mkdir()
    exported.mkdir()
    helper = work / "render_pwa_icon.gd"
    print(f"Staging {'working tree (local only)' if args.working_tree else commit}", flush=True)
    try:
        if args.working_tree:
            stage_working_source(root, stage, helper)
        else:
            stage_committed_source(root, commit, stage, helper)
        protocol = network_protocol(stage)
        project = stage / "project.godot"
        project.write_text(sanitize_project(project.read_text(encoding="utf-8"), revision), encoding="utf-8", newline="\n")
        verify_stage(stage)
        run_godot(binary, ["--headless", "--path", str(stage), "--import"], work / "import.log")
        verify_stage(stage)
        write_manifest(stage, exported / "SOURCE_SHA256SUMS.txt", skip_cache=True)
        source_hash = sha256(exported / "SOURCE_SHA256SUMS.txt")
        print("Exporting Mobile Web Beta", flush=True)
        run_godot(binary, ["--headless", "--path", str(stage), "--export-release", "Mobile Web Beta", str(exported / "index.html")], work / "export.log")
        for name in WEB_ASSETS:
            shutil.copyfile(stage / "web" / name, exported / name)
        for name in FONTS:
            shutil.copyfile(stage / "assets/fonts" / name, exported / name)
        for source in [stage / "assets/ui/kingdom_company_v2.png", stage / "assets/ui/icons/play_dark.svg"] + [stage / "assets/ui/plates" / f"{kind}_{state}.svg" for kind in ("primary", "secondary") for state in ("normal", "hover", "pressed")]:
            shutil.copyfile(source, exported / source.name)
        run_godot(binary, ["--headless", "--path", str(stage), "--script", str(helper), "--", str(stage / "icon.svg"), str(exported / "index.192x192.png")], work / "icon.log")
        package_pwa(exported)
        product = re.search(r'^config/version="([^"]+)"$', project.read_text(encoding="utf-8"), re.MULTILINE)
        if not product:
            raise BuildError("Product version is missing")
        version = {
            "product": "Pocket Kingdoms", "version": product.group(1), "channel": "internal-mobile-web-beta",
            "network_protocol": protocol,
            "source_revision": revision, "source_dirty": bool(args.working_tree), "source_tree_sha256": source_hash,
            "source_manifest": "SOURCE_SHA256SUMS.txt", "built_at_utc": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "godot": engine, "entrypoint": "index.html",
        }
        (exported / "version.json").write_text(json.dumps(version, indent=2) + "\n", encoding="utf-8", newline="\n")
        pck = (exported / "index.pck").read_bytes()
        strings = re.findall(rb"[\x20-\x7e]{4,}", pck)
        forbidden = re.compile(rb"res://(?:addons/godot_mcp|tools|tests|docs|reports|output|build|\.playwright-cli|\.tmp_phone_test|\.godot-mcp)(?:/|$)|debug_(?:bootstrap|panel)\.gd|mcp_(?:game_bridge|debugger_plugin|constants|enums|log|logger|utils)\.gd|(?:^|/)test_[^/\s]*\.(?:gd|tscn|py)|(?:^|/)[^/\s]*_test\.(?:gd|tscn|py)|(?:^|/)(?:\.mcp\.json|AGENTS\.md|CLAUDE\.md|PHASED_CHANGES\.md|roadmap\.md)")
        if any(forbidden.search(item) for item in strings):
            raise BuildError("Developer resources remain in the production PCK")
        audit = {
            "audit_format": "1", "status": "PASS", "product": "Pocket Kingdoms mobile Web beta",
            "staged_source_exclusions": "PASS", "staged_project_configuration": "PASS", "deterministic_text_resources": "PASS",
            "pck_complete_resource_path_scan": "PASS", "pck_split_basename_scan": "PASS", "excluded_tools_and_tests": "PASS",
            "excluded_docs_reports_and_temporary_output": "PASS", "excluded_debug_bootstrap_and_panel": "PASS", "excluded_godot_mcp_addon": "PASS",
            "staged_source_file_count": str(len((exported / "SOURCE_SHA256SUMS.txt").read_text().splitlines())),
            "source_tree_sha256": source_hash, "pck_sha256": hashlib.sha256(pck).hexdigest(), "pck_size_bytes": str(len(pck)),
            "pck_printable_string_count": str(len(strings)), "source_manifest": "SOURCE_SHA256SUMS.txt", "runtime_bridge": "scripts/managers/runtime_game_bridge.gd",
            "scope": "staged source paths, staged project configuration, packaged resource paths, and distinctive excluded-resource basenames",
            "compiled_diagnostic_symbol_absence": "NOT_CERTIFIED",
        }
        (exported / "CONTENT_AUDIT.txt").write_text("".join(f"{key}={value}\n" for key, value in audit.items()), encoding="utf-8", newline="\n")
        package_update_worker(exported, stage / "web/pocket_service_worker.js")
        write_manifest(exported, exported / "SHA256SUMS.txt")
        verify_payload(exported)
        if output.exists() or output.is_symlink():
            raise BuildError("Output changed during build")
        exported.rename(output)
        verify_payload(output)
        receipt = {"status": "PASS", "source_commit": commit, "network_protocol": protocol, "source_mode": "working-tree-local-only" if args.working_tree else "committed-archive", "builder_sha256": sha256(Path(__file__)), "source_tree_sha256": source_hash, "payload_manifest_sha256": sha256(output / "SHA256SUMS.txt"), "output": str(output), "godot": engine}
        (work / "build-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(receipt, indent=2), flush=True)
        print(f"Build logs and receipt: {work}", flush=True)
        if not args.keep_stage:
            if stage.resolve().parent != work.resolve() or work.resolve().parent != (root / "build").resolve():
                raise BuildError("Refusing cleanup outside the verified build workspace")
            shutil.rmtree(stage)
        return output
    except Exception:
        print(f"Failed build retained for diagnosis: {work}", file=sys.stderr)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", help="New direct child of build/, e.g. build/mobile-windows-beta")
    parser.add_argument("--project", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN"), required=not bool(os.environ.get("GODOT_BIN")))
    parser.add_argument("--revision", default="HEAD", help="Committed runtime revision (default: HEAD)")
    parser.add_argument("--working-tree", action="store_true", help="Use current runtime files; local playtests only, always marked dirty")
    parser.add_argument("--keep-stage", action="store_true", help="Keep the sanitized imported project beside build logs")
    args = parser.parse_args()
    try:
        build(args)
        return 0
    except (OSError, ValueError, IndexError, subprocess.SubprocessError, VerificationError, BuildError) as exc:
        print(f"Build failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
