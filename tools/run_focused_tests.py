#!/usr/bin/env python3
"""Run every focused Godot regression with per-case isolation and timeouts."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent
TOOLS_DIR = PROJECT_ROOT / "tools"
DEFAULT_GODOT = Path("/Applications/Godot.app/Contents/MacOS/Godot")
ENDING_SCENARIOS = ("victory_menu", "elimination_menu", "defeat_restart", "pause_quit")


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
    return parser.parse_args()


def discover_cases(godot: Path) -> list[tuple[str, list[str]]]:
    prefix = [str(godot), "--headless", "--path", str(PROJECT_ROOT)]
    cases: list[tuple[str, list[str]]] = []

    scene_stems: set[str] = set()
    for scene in sorted(TOOLS_DIR.glob("test_*.tscn")):
        scene_stems.add(scene.stem)
        # The perimeter scene funds two Feudal economies; the raid scene walks
        # sixteen paid A/B economies. Fixed60 preserves their 60Hz/4x simulation
        # while finishing within the unchanged per-case wall timeout.
        fixed_step_scenes = {"test_building_perimeter_work", "test_paid_proactive_worker_raid"}
        case_prefix = [*prefix, "--fixed-fps", "60"] if scene.stem in fixed_step_scenes else prefix
        cases.append((scene.stem, [*case_prefix, f"res://tools/{scene.name}"]))

    for script in sorted(TOOLS_DIR.glob("test_*.gd")):
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


def main() -> int:
    args = parse_args()
    if not args.godot.is_file() or not os.access(args.godot, os.X_OK):
        print(f"Godot executable is unavailable: {args.godot}", file=sys.stderr)
        return 2

    cases = discover_cases(args.godot)
    transcript: list[str] = []
    failures: list[str] = []
    environment = os.environ.copy()
    environment["GODOT_AUDIO_DRIVER"] = "Dummy"

    for index, (name, command) in enumerate(cases, start=1):
        header = f"=== [{index}/{len(cases)}] {name} ==="
        print(header, flush=True)
        transcript.append(header)
        try:
            result = subprocess.run(
                command,
                cwd=PROJECT_ROOT,
                env=environment,
                capture_output=True,
                text=True,
                timeout=args.timeout,
                check=False,
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

    summary = f"FOCUSED_SUITE: {len(cases) - len(failures)}/{len(cases)} passed"
    if failures:
        summary += f"; failed: {', '.join(failures)}"
    print(summary)
    transcript.append(summary)

    if args.log:
        log_path = args.log if args.log.is_absolute() else PROJECT_ROOT / args.log
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text("\n".join(transcript) + "\n", encoding="utf-8")
        print(f"Saved log: {log_path}")

    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
