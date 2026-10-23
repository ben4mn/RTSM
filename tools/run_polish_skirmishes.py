#!/usr/bin/env python3
"""Freeze the current worktree and run three ordinary paid navigation skirmishes.

Default: fast fixed-step headless behavioral validation. --native: visible macOS
Godot through LaunchServices, no fixed FPS, with scoped process timing and PNGs.
Every run has private preferences and a preserved frozen source manifest.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import shlex
import signal
import subprocess
import tempfile
import time
import uuid


ROOT = Path(__file__).resolve().parents[1]
GODOT_APP = Path("/Applications/Godot.app")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def owned_game_processes(stage):
    """Only Godot processes launched with this run's exact private --path."""
    rows = subprocess.check_output(["ps", "-axo", "pid=,comm=,args="], text=True).splitlines()
    found = []
    for row in rows:
        parts = row.strip().split(None, 2)
        if len(parts) != 3 or Path(parts[1]).name.lower() != "godot":
            continue
        try:
            arguments = shlex.split(parts[2])
            path_index = arguments.index("--path") + 1
            if Path(arguments[path_index]).resolve() == stage.resolve():
                found.append(int(parts[0]))
        except (ValueError, IndexError):
            continue
    return found


def terminate_owned_game(stage):
    # open -W waits for the application; terminating it alone leaves Godot alive.
    # Never stop another editor/game process merely because its name is Godot.
    for pid in owned_game_processes(stage):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 3.0
    while owned_game_processes(stage) and time.monotonic() < deadline:
        time.sleep(0.1)
    for pid in owned_game_processes(stage):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass



def summarize_case(case):
    summary = {key: case.get(key) for key in [
        "name", "winner", "ending", "game_seconds", "wall_seconds",
        "menu_return_verified", "first_contact", "attack_hits", "deposits",
        "paid_units", "completed_buildings", "performance",
    ]}
    coverage = case.get("coverage", {})
    summary["coverage"] = {key: coverage.get(key) for key in [
        "required_for_scripted_case", "passed", "failures", "paid_farms_completed",
        "farm_cargo_gain_samples", "farm_associated_food_deposits",
        "gap_traversals", "max_simultaneous_deliverers",
    ]}
    for field in ["delivery_workers", "farm_delivery_workers"]:
        summary["coverage"][field + "_counts"] = [len(workers) for workers in coverage.get(field, [])]
    crowd = case.get("congestion", {})
    summary["congestion"] = {key: crowd.get(key) for key in [
        "sample_period_game_seconds", "samples", "long_episode_game_seconds",
        "long_contacts", "long_travel_stalls", "long_near_goal_stalls",
        "max_contact_seconds", "max_travel_stall_seconds", "dropped_records",
    ]}
    summary["congestion"]["gap_candidates_seen"] = len(crowd.get("gap_candidates_seen", {}))
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--native", action="store_true")
    parser.add_argument("--manual", action="store_true", help="Human controls; requires --native and one --case")
    parser.add_argument("--duration", type=float, default=900.0)
    parser.add_argument("--case", type=int, choices=[0, 1, 2])
    parser.add_argument("--timeout", type=float, default=900.0)
    args = parser.parse_args()
    if args.manual and (not args.native or args.case is None):
        parser.error("--manual requires --native and one --case")
    project, output = args.project.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if (output / "source.json").exists() or (output / "report.json").exists():
        parser.error("Use a new output directory to preserve previous evidence.")
    stage = Path(tempfile.mkdtemp(prefix="aoem-polish-skirmishes-"))
    for name in [".godot", "addons", "assets", "resources", "scenes", "scripts", "tools"]:
        if name == "resources" and not (project / name).exists():
            (stage / name).mkdir()
        else:
            shutil.copytree(project / name, stage / name)
    for name in ["project.godot", "default_bus_layout.tres", "icon.svg", "icon.svg.import"]:
        shutil.copy2(project / name, stage / name)
    project_text = (stage / "project.godot").read_text()
    project_text = "\n".join(line for line in project_text.splitlines() if not line.startswith(("config/use_custom_user_dir=", "config/custom_user_dir_name=")))
    private_user_dir = "aoem-polish-skirmishes/" + uuid.uuid4().hex
    project_text = project_text.replace("[application]", '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + private_user_dir + '"', 1)
    (stage / "project.godot").write_text(project_text + "\n")
    files = {}
    for folder in ["scripts", "scenes", "assets", "resources", "tools"]:
        for path in (stage / folder).rglob("*"):
            if path.is_file() and "__pycache__" not in path.parts:
                files[str(path.relative_to(stage))] = digest(path)
    files["project.godot"] = digest(stage / "project.godot")
    source = {"scope": "Frozen current worktree, including uncommitted changes; private user data; unchanged production runtime", "stage": str(stage), "files": files, "runner_sha256": digest(Path(__file__)), "private_user_dir": private_user_dir}
    write_json(output / "source.json", source)
    # Refresh imported SVG textures and script metadata in the frozen copy.
    # A copied .godot cache alone can silently display artwork from an older run.
    frozen_project = (stage / "project.godot").read_bytes()
    with (output / "import.log").open("w") as import_log:
        imported = subprocess.run(
            [str(GODOT_APP / "Contents/MacOS/Godot"), "--headless", "--editor", "--path", str(stage), "--quit"],
            stdout=import_log, stderr=subprocess.STDOUT, timeout=120,
        )
    if (stage / "project.godot").read_bytes() != frozen_project:
        shutil.copy2(stage / "project.godot", output / "project-after-import.godot")
        (stage / "project.godot").write_bytes(frozen_project)
    import_text = (output / "import.log").read_text()
    if imported.returncode or any(marker in import_text for marker in ["SCRIPT ERROR", "Parse Error", "ERROR:"]):
        raise RuntimeError("Frozen project import failed; inspect import.log")
    log = output / "engine.log"
    game_args = ["--path", str(stage), "--log-file", str(log), "res://tools/probe_polish_skirmishes.tscn", "--", f"--output-dir={output}", f"--duration={args.duration}"]
    if args.manual:
        game_args.append("--manual")
    if args.case is not None:
        game_args.append(f"--case={args.case}")
    environment = os.environ.copy()
    overrides = {"AOEM_SIM_TIME_SCALE": "1", "AOEM_AI_DIFFICULTY": "", "AOEM_MAP_SEED": "", "AOEM_MAP_ARCHETYPE": "", "AOEM_POPULATION_LIMIT": ""}
    environment.update(overrides)
    if args.native:
        command = ["open", "-n", "-W", "-a", str(GODOT_APP)]
        for key, value in overrides.items():
            command += ["--env", key + "=" + value]
        command += ["--args", *game_args]
    else:
        command = [str(GODOT_APP / "Contents/MacOS/Godot"), "--headless", "--fixed-fps", "60", *game_args]
    write_json(output / "launch.json", {"command": command, "native": args.native, "started_unix": time.time()})
    print(json.dumps({"phase": "launch", "native": args.native, "frozen_source": str(stage), "output": str(output)}), flush=True)
    started = time.monotonic()
    try:
        with (output / "launcher.log").open("w") as launcher:
            result = subprocess.run(command, env=environment, stdout=launcher, stderr=subprocess.STDOUT, timeout=args.timeout)
    except BaseException:
        terminate_owned_game(stage)
        raise
    if result.returncode:
        terminate_owned_game(stage)
    log_text = log.read_text() if log.exists() else ""
    errors = [line for line in log_text.splitlines() if "SCRIPT ERROR" in line or "ERROR:" in line or "Parse Error" in line]
    warnings = [line for line in log_text.splitlines() if "WARNING:" in line]
    report_path = output / "report.json"
    report = json.loads(report_path.read_text()) if report_path.exists() else {"failures": ["Missing report"]}
    errors.extend(report.get("failures", []))
    coverage_failures = report.get("coverage_failures", [])
    for case in report.get("cases", []):
        for path, expected in case.get("source_sha256", {}).items():
            if files.get(path) != expected:
                errors.append("Loaded source mismatch: " + path)
    analysis = {"returncode": result.returncode, "wall_seconds": time.monotonic() - started, "errors": errors, "warnings": warnings, "coverage_failures": coverage_failures, "congestion_scope": report.get("congestion_scope"), "cases": [summarize_case(case) for case in report.get("cases", [])]}
    write_json(output / "analysis.json", analysis)
    print(json.dumps(analysis, indent=2), flush=True)
    return 1 if errors or coverage_failures or result.returncode else 0


if __name__ == "__main__":
    raise SystemExit(main())
