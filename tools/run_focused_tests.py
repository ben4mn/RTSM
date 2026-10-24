#!/usr/bin/env python3
"""Run every focused Godot regression with per-case isolation and timeouts."""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent
TOOLS_DIR = PROJECT_ROOT / "tools"
DEFAULT_GODOT = Path("/Applications/Godot.app/Contents/MacOS/Godot")
ENDING_SCENARIOS = ("victory_menu", "elimination_menu", "defeat_restart", "pause_quit")


def terminate_process_tree(process: subprocess.Popen) -> None:
    """Stop a live owned child tree; POSIX callers must use start_new_session."""
    if process.poll() is not None:
        return
    if os.name == "nt":
        # Kill the still-owned wrapper and descendants before the wrapper
        # disappears. subprocess.run's default timeout kills only its PID.
        terminated = subprocess.run(
            ["taskkill", "/PID", str(process.pid), "/T", "/F"],
            capture_output=True, timeout=15, check=False,
        )
        if terminated.returncode != 0 and process.poll() is None:
            raise RuntimeError("Cannot terminate owned process tree: " + str(process.pid))
    else:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def run_case(command: list[str], *, cwd: Path, env: dict[str, str], timeout: float) -> subprocess.CompletedProcess:
    """Bound one owned process tree, including Godot's Windows console child."""
    process = subprocess.Popen(
        command, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, encoding="utf-8", errors="replace", start_new_session=os.name != "nt",
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        terminate_process_tree(process)
        stdout, stderr = process.communicate(timeout=15)
        exc.output = stdout
        exc.stderr = stderr
        raise
    return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--godot",
        type=Path,
        default=Path(os.environ.get("GODOT_BIN", DEFAULT_GODOT)),
        help="Godot executable (defaults to the project-standard macOS path)",
    )
    parser.add_argument("--timeout", type=float, default=120.0, help="Per-case timeout in seconds")
    parser.add_argument("--log", type=Path, help="Optional combined evidence log")
    parser.add_argument("--only", action="append", default=[], metavar="PATTERN", help="Run matching case names (glob; repeatable). Default runs every discovered case")
    return parser.parse_args()


def discover_cases(godot: Path, project_root: Path = PROJECT_ROOT) -> list[tuple[str, list[str]]]:
    prefix = [str(godot), "--headless", "--path", str(project_root)]
    cases: list[tuple[str, list[str]]] = []
    tools_dir = project_root / "tools"

    scene_stems: set[str] = set()
    for scene in sorted(tools_dir.glob("test_*.tscn")):
        scene_stems.add(scene.stem)
        # The perimeter scene funds two Feudal economies; the raid scene walks
        # sixteen paid A/B economies; worker recovery includes two more raids.
        # Fixed60 preserves their 60Hz/4x simulation
        # while finishing within the unchanged per-case wall timeout.
        fixed_step_scenes = {"test_building_perimeter_work", "test_paid_proactive_worker_raid", "test_paid_worker_recovery"}
        case_prefix = [*prefix, "--fixed-fps", "60"] if scene.stem in fixed_step_scenes else prefix
        cases.append((scene.stem, [*case_prefix, f"res://tools/{scene.name}"]))

    for script in sorted(tools_dir.glob("test_*.gd")):
        # Online scenarios require a listening match service and two independent
        # clients; tools/run_online_tests.py owns their paired lifecycle.
        if script.name.startswith("test_online_"):
            continue
        if script.stem in scene_stems:
            continue
        resource_path = f"res://tools/{script.name}"
        if script.name == "test_match_endings.gd":
            for scenario in ENDING_SCENARIOS:
                cases.append(
                    (
                        f"{script.stem}:{scenario}",
                        [*prefix, "--script", resource_path, "--", f"--scenario={scenario}"],
                    )
                )
        else:
            cases.append((script.stem, [*prefix, "--script", resource_path]))

    return cases


def freeze_project(destination: Path) -> None:
    """Copy only runtime/test inputs; never pull build/output/private state in."""
    ignore = shutil.ignore_patterns("__pycache__", "*.pyc", "node_modules", ".DS_Store")
    for name in ("scripts", "scenes", "assets", "addons", "tools", "web"):
        if (PROJECT_ROOT / name).is_dir():
            shutil.copytree(PROJECT_ROOT / name, destination / name, ignore=ignore)
    for name in ("project.godot", "icon.svg", "icon.svg.import"):
        if (PROJECT_ROOT / name).is_file():
            shutil.copy2(PROJECT_ROOT / name, destination / name)
    cache = PROJECT_ROOT / ".godot"
    if cache.is_dir():
        (destination / ".godot").mkdir()
        for name in ("global_script_class_cache.cfg", "uid_cache.bin"):
            if (cache / name).is_file():
                shutil.copy2(cache / name, destination / ".godot" / name)
        if (cache / "imported").is_dir():
            shutil.copytree(cache / "imported", destination / ".godot" / "imported")


def runtime_hashes(project: Path) -> dict[str, str]:
    paths: list[Path] = []
    for name in ("scripts", "scenes", "assets", "addons", "tools", "web"):
        paths.extend(path for path in (project / name).rglob("*") if path.is_file())
    return {str(path.relative_to(project)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(paths)}


def run_suite(args: argparse.Namespace, project: Path) -> int:
    cases = discover_cases(args.godot, project)
    if args.only:
        cases = [(name, command) for name, command in cases if any(fnmatch.fnmatchcase(name, pattern) for pattern in args.only)]
        if not cases:
            print("No focused cases match --only", file=sys.stderr)
            return 2

    transcript: list[str] = []
    failures: list[str] = []
    records: list[dict] = []
    environment = os.environ.copy()
    environment["GODOT_AUDIO_DRIVER"] = "Dummy"
    source_hashes = runtime_hashes(project)
    base_config = (project / "project.godot").read_text(encoding="utf-8")
    base_config = "\n".join(line for line in base_config.splitlines() if not line.startswith(("config/use_custom_user_dir=", "config/custom_user_dir_name=")))
    private_user_dirs: dict[str, str] = {}
    log_path = args.log if args.log else PROJECT_ROOT / "output" / "focused-tests" / ("run-" + uuid.uuid4().hex[:12] + ".log")
    if not log_path.is_absolute():
        log_path = PROJECT_ROOT / log_path
    log_path.parent.mkdir(parents=True, exist_ok=True)
    artifact_path = log_path.with_suffix("").with_name(log_path.stem + "-artifacts")
    source_unchanged: bool | None = None

    def save_receipt(completed: bool = False) -> None:
        log_path.with_suffix(".receipt.json").write_text(json.dumps({
            "source_project": str(PROJECT_ROOT), "frozen_runtime_sha256": source_hashes,
            "base_project_sha256": hashlib.sha256(base_config.encode("utf-8")).hexdigest(),
            "source_unchanged": source_unchanged, "sequential": True, "completed": completed,
            "private_user_dirs": private_user_dirs,
            "unique_user_dirs": len(private_user_dirs) == len(set(private_user_dirs.values())),
            "cases": records, "failures": failures, "fixture_artifacts": str(artifact_path),
        }, indent=2) + "\n", encoding="utf-8")

    save_receipt()

    for index, (name, command) in enumerate(cases, start=1):
        # Each case starts with fresh preferences, even after a preceding test
        # intentionally saves Settings. The user's ordinary game is untouched.
        user_dir = "aoem-focused-probes/" + uuid.uuid4().hex
        private_user_dirs[name] = user_dir
        config = base_config.replace("[application]", '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + user_dir + '"', 1)
        (project / "project.godot").write_text(config + "\n", encoding="utf-8", newline="\n")
        header = f"=== [{index}/{len(cases)}] {name} ==="
        print(header, flush=True)
        transcript.append(header)
        try:
            result = run_case(
                command,
                cwd=project,
                env=environment,
                timeout=args.timeout,
            )
            output = "\n".join(part.rstrip() for part in (result.stdout, result.stderr) if part.strip())
            if output:
                print(output, flush=True)
                transcript.append(output)
            # Godot can return success after a script fails to parse. Require
            # clean engine diagnostics as well as a successful process exit.
            has_engine_error = re.search(r"^(?:SCRIPT ERROR:|ERROR:)", output, re.MULTILINE) is not None
            if result.returncode != 0:
                status = f"FAIL (exit {result.returncode})"
            elif has_engine_error:
                status = "FAIL (engine diagnostic)"
            else:
                status = "PASS"
            if result.returncode != 0 or has_engine_error:
                failures.append(name)
        except subprocess.TimeoutExpired as exc:
            captured = "\n".join(
                part.decode(errors="replace").rstrip() if isinstance(part, bytes) else part.rstrip()
                for part in (exc.stdout or "", exc.stderr or "")
                if part
            )
            if captured:
                print(captured, flush=True)
                transcript.append(captured)
            status = f"FAIL (timeout after {args.timeout:.0f}s)"
            failures.append(name)
        status_line = f"[{status}] {name}"
        print(status_line, flush=True)
        transcript.append(status_line)
        records.append({"case": name, "status": status, "user_dir": user_dir})
        # Preserve progress when a long suite is interrupted.
        log_path.write_text("\n".join(transcript) + "\n", encoding="utf-8")
        save_receipt()

    source_unchanged = runtime_hashes(project) == source_hashes
    if not source_unchanged:
        failures.append("frozen_runtime_changed")

    summary = f"FOCUSED_SUITE: {len(cases) - len(failures)}/{len(cases)} passed"
    if failures:
        summary += f"; failed: {', '.join(failures)}"
    print(summary)
    transcript.append(summary)

    log_path.write_text("\n".join(transcript) + "\n", encoding="utf-8")
    if (project / "output").is_dir():
        shutil.copytree(project / "output", artifact_path, dirs_exist_ok=True)
    save_receipt(completed=True)
    print(f"Saved log: {log_path}")

    return 0 if not failures else 1


def main() -> int:
    args = parse_args()
    if not args.godot.is_file() or not os.access(args.godot, os.X_OK):
        print(f"Godot executable is unavailable: {args.godot}", file=sys.stderr)
        return 2
    with tempfile.TemporaryDirectory(prefix="aoem-focused-frozen-") as folder:
        project = Path(folder)
        freeze_project(project)
        return run_suite(args, project)


if __name__ == "__main__":
    raise SystemExit(main())
