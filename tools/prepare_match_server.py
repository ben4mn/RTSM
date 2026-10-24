#!/usr/bin/env python3
"""Prepare an immutable, committed-source match-server Docker context.

The checkout can be dirty: runtime and Dockerfile inputs always come from the
resolved Git commit. This command imports and seals a local context; it never
builds an image, uploads files, changes a deployment, or edits the checkout.
"""

from __future__ import annotations

import argparse
import datetime as dt
import fnmatch
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tarfile

from build_mobile_web_windows import (
    BuildError, DEV_PATTERNS, allowed_source, git, output_directory, run_godot,
    sanitize_project, write_manifest,
)
from verify_mobile_web_artifacts import inspect_tree, sha256, verify_manifest


SERVER_ROOTS = (
    "assets", "scripts", "scenes", "default_bus_layout.tres", "icon.svg",
    "icon.svg.import", "project.godot", "deploy/match-server/Dockerfile",
)
DOCKERFILE_SOURCE = "deploy/match-server/Dockerfile"


def extract_committed_archive(payload: bytes, target: Path) -> dict[str, str]:
    """Extract only runtime inputs without following links or overwriting files."""
    if target.is_symlink() or not target.is_dir() or any(target.iterdir()):
        raise BuildError("Server stage must be an empty real directory")
    originals: dict[str, str] = {}
    seen: set[str] = set()
    with tarfile.open(fileobj=io.BytesIO(payload), mode="r:") as packed:
        for item in packed:
            name = PurePosixPath(item.name)
            if name.is_absolute() or ".." in name.parts or "\\" in item.name or ":" in item.name:
                raise BuildError("Unsafe path in committed server archive")
            if item.isdir():
                continue
            if not item.isfile():
                raise BuildError("Committed server source has a link or special entry")
            if item.name == DOCKERFILE_SOURCE:
                relative = "Dockerfile"
            elif allowed_source(item.name) and name.parts[0] in SERVER_ROOTS:
                if any(fnmatch.fnmatchcase(name.name, pattern) for pattern in DEV_PATTERNS):
                    raise BuildError("Developer file in committed server runtime: " + item.name)
                relative = "runtime/" + item.name
            else:
                continue
            # A Windows build must not silently overwrite case-distinct inputs.
            if relative.casefold() in seen:
                raise BuildError("Duplicate or case-colliding server source")
            seen.add(relative.casefold())
            source = packed.extractfile(item)
            if source is None:
                raise BuildError("Cannot read committed server source")
            content = source.read()
            destination = target.joinpath(*PurePosixPath(relative).parts)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(content)
            originals[relative] = hashlib.sha256(content).hexdigest()
    for required in ("Dockerfile", "runtime/project.godot", "runtime/scenes/network/server_lobby.tscn"):
        if required not in originals:
            raise BuildError("Committed server input is missing: " + required)
    return originals


def sanitize_server_project(text: str, revision: str) -> str:
    if not re.fullmatch(r"[0-9a-f]{12}", revision):
        raise BuildError("Server revision must be a twelve-character commit prefix")
    text = sanitize_project(text, revision)
    text, count = re.subn(
        r"^run/main_scene=.*$", 'run/main_scene="res://scenes/network/server_lobby.tscn"',
        text, flags=re.MULTILINE,
    )
    if count != 1 or text.count("config/playtest_revision=") != 1:
        raise BuildError("Expected one project application and entry scene")
    if re.search(r"\.debug\s*=|^\[editor_plugins\]$|^\[godot_mcp\]$|addons/godot_mcp", text, re.MULTILINE):
        raise BuildError("Server project retains developer configuration")
    if text.splitlines().count('MCPGameBridge="res://scripts/managers/runtime_game_bridge.gd"') != 1:
        raise BuildError("Server project must retain exactly one runtime bridge")
    return text


def verify_imported_sources(target: Path, originals: dict[str, str], project_hash: str) -> None:
    """Import may derive cache files, but must never rewrite an input silently."""
    for name, expected in originals.items():
        path = target / name
        if path.is_symlink() or not path.is_file():
            raise BuildError("Imported server source is missing or special: " + name)
        approved = project_hash if name == "runtime/project.godot" else expected
        if sha256(path) != approved:
            raise BuildError("Imported server source differs from committed input: " + name)
    if any(inspect_tree(target).values()):
        raise BuildError("Server context contains sensitive names or special entries")
    for path in (target / "runtime").rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(target).as_posix()
        if relative in originals or relative.startswith("runtime/.godot/"):
            continue
        # Missing source UIDs/import descriptors are generated by Godot. Extra
        # executable/runtime source, even if harmless-looking, has no provenance.
        if path.suffix not in {".uid", ".import"}:
            raise BuildError("Uncommitted runtime source appeared during import: " + relative)


def prepare(root: Path, revision: str, godot: Path, requested_output: str) -> dict:
    root = root.resolve(strict=True)
    godot = godot.resolve(strict=True)
    engine = subprocess.check_output([str(godot), "--version"], text=True).strip()
    if not re.match(r"^4\.6(?:\.|$)", engine):
        raise BuildError("Godot 4.6 is required by the server Dockerfile")
    commit = git(root, "rev-parse", "--verify", revision + "^{commit}").decode().strip()
    # Git-for-Windows defaults can otherwise apply checkout CRLF conversion to
    # archive members even though their committed blobs contain LF bytes.
    payload = git(root, "-c", "core.autocrlf=false", "-c", "core.eol=lf", "archive", "--format=tar", commit, *SERVER_ROOTS)
    target = output_directory(root, requested_output)
    target.mkdir()
    originals = extract_committed_archive(payload, target)
    runtime = target / "runtime"
    project = runtime / "project.godot"
    project.write_text(sanitize_server_project(project.read_text(encoding="utf-8"), commit[:12]), encoding="utf-8", newline="\n")
    project_hash = sha256(project)
    log = root / "build" / (target.name + "-import.log")
    run_godot(godot, ["--headless", "--path", str(runtime), "--editor", "--quit"], log)
    verify_imported_sources(target, originals, project_hash)
    receipt = {
        "format": "pocket.match-server.v1", "source_revision": commit, "source_dirty": False,
        "prepared_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source_file_count": len(originals), "all_committed_runtime_sources_match": True,
        "project_sanitization_verified": True, "staged_project_sha256": project_hash,
        "godot": engine, "committed_source_sha256": originals,
        "scope": "Committed runtime and Dockerfile plus Godot imports; project entrypoint/debug settings sanitized and runtime revision injected. No repository metadata or developer bridge.",
    }
    (target / "SERVER_SOURCE.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    write_manifest(target, target / "SHA256SUMS.txt")
    count, manifest = verify_manifest(target)
    return {"status": "PASS", "context": str(target), "source_revision": commit,
            "manifest_sha256": manifest, "context_files": count,
            "runtime_sources": len(originals), "import_log": str(log)}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--revision", default="HEAD", help="One committed Git revision (default: HEAD)")
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--output", required=True, help="New direct child of project build/")
    args = parser.parse_args(argv)
    try:
        print(json.dumps(prepare(args.project, args.revision, args.godot, args.output), indent=2))
    except (BuildError, OSError, subprocess.SubprocessError, tarfile.TarError) as exc:
        print("Server context preparation failed: " + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
