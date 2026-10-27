#!/usr/bin/env python3
"""Freeze and run bounded, paid pacing simulations with partial receipts.

At 1x, fixed60 keeps 1/60-second game steps. Adaptive mode checks throughput
after 120 game seconds. A slow first run is retained as a pilot, then ALL
requested cases use 3x/50ms game steps. No case receives free resources,
extra actors, altered AI policies or a forced outcome. Save persistence alone
is replaced by a runner-only inert autoload; it has its own regression suite.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import uuid
import zipfile

from run_focused_tests import freeze_project, terminate_process_tree

ROOT = Path(__file__).resolve().parents[1]
OBSERVER_FILES = (
    "tools/probe_late_economy_pacing.gd",
    "tools/probe_late_economy_pacing.tscn",
    "tools/fixtures/pacing_solo_save.gd",
    "tools/run_late_economy_pacing.py",
)
DEFAULT_CASES = ((1, 424242, 1, 1), (4, 7, 1, 1))


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_json(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        # Godot writes the partial observer file synchronously; a poll may see
        # it between truncate and close. Retry on the next bounded poll.
        return None


def parse_case(value: str) -> tuple[int, int, int, int]:
    try:
        parts = tuple(int(part) for part in value.split(":"))
    except ValueError as error:
        raise argparse.ArgumentTypeError("Use style:seed or style:seed:player0_difficulty:player1_difficulty") from error
    if len(parts) == 2:
        parts += (1, 1)
    if len(parts) != 4 or not 0 <= parts[0] <= 4 or parts[1] <= 0 or any(d not in (0, 1, 2) for d in parts[2:]):
        raise argparse.ArgumentTypeError("Expected style 0-4, positive seed and difficulties 0-2")
    return parts


def run_case(project: Path, base_config: str, args: argparse.Namespace,
             style: int, seed: int, human_difficulty: int, enemy_difficulty: int,
             scale: int, adaptive_probe: bool) -> dict:
    name = f"map{style}-seed{seed}-fixed60-scale{scale}"
    if (human_difficulty, enemy_difficulty) != (1, 1):
        name += f"-difficulty{human_difficulty}v{enemy_difficulty}"
    report = args.output / (name + ".json")
    log = args.output / (name + ".log")
    partial = Path(str(report) + ".partial.json")
    user_dir = "pocket-pacing/" + uuid.uuid4().hex
    config = base_config.replace(
        "[application]", '[application]\nconfig/use_custom_user_dir=true\n'
        f'config/custom_user_dir_name="{user_dir}"', 1,
    )
    (project / "project.godot").write_text(config + "\n", encoding="utf-8")
    command = [str(args.godot), "--headless", "--disable-render-loop",
               "--fixed-fps", "60", "--max-fps", "0", "--path", str(project),
               "res://tools/probe_late_economy_pacing.tscn", "--", "--mode=0",
               "--pop=100", f"--difficulty={enemy_difficulty}", f"--human-difficulty={human_difficulty}",
               f"--archetype={style}", f"--seed={seed}",
               f"--duration={args.duration}", f"--output={report}"]
    environment = os.environ.copy()
    environment.update(AOEM_AI_DIFFICULTY=str(enemy_difficulty), AOEM_MAP_ARCHETYPE=str(style),
                       AOEM_SIM_TIME_SCALE=str(scale), GODOT_AUDIO_DRIVER="Dummy")
    started = time.monotonic()
    result = {"case": name, "style": style, "seed": seed, "scale": scale,
              "difficulty_player0": human_difficulty, "difficulty_player1": enemy_difficulty,
              "game_step_seconds": scale / 60, "command": command,
              "user_dir": user_dir, "report": str(report), "log": str(log),
              "partial": str(partial), "status": "running"}
    print("START " + name, flush=True)
    latest: dict | None = None
    probe_checked = not adaptive_probe
    with log.open("w", encoding="utf-8") as stream:
        process = subprocess.Popen(command, cwd=project, env=environment,
                                   stdout=stream, stderr=subprocess.STDOUT,
                                   start_new_session=os.name != "nt")
        while process.poll() is None:
            time.sleep(2)
            latest = read_json(partial) or latest
            elapsed = time.monotonic() - started
            log_text = log.read_text(encoding="utf-8", errors="replace")
            if "Parse Error:" in log_text or "Failed to load script" in log_text:
                result["status"] = "script_load_error"
                terminate_process_tree(process)
                break
            if not probe_checked and latest and float(latest.get("time", 0)) >= 120:
                performance = latest["late_economy"]["performance"]
                game_seconds = float(performance["game_seconds"])
                wall_seconds = float(performance["wall_seconds"])
                ratio = game_seconds / max(0.001, wall_seconds)
                result["first120_throughput"] = {
                    "game_seconds": game_seconds, "wall_seconds": wall_seconds,
                    "game_per_wall_second": ratio,
                    "measure_observer_wall_fraction": float(performance["observer_usec"]) / max(1, wall_seconds * 1e6),
                }
                print("THROUGHPUT " + json.dumps(result["first120_throughput"]), flush=True)
                probe_checked = True
                if ratio < 1.0:
                    result["status"] = "pilot_stopped_for_slow_throughput"
                    terminate_process_tree(process)
                    break
            if elapsed >= args.wall_timeout:
                result["status"] = "wall_timeout"
                terminate_process_tree(process)
                break
        result["exit"] = process.wait(timeout=15)
    result["wall_seconds"] = round(time.monotonic() - started, 3)
    final = read_json(report)
    latest = read_json(partial) or latest
    log_text = log.read_text(encoding="utf-8", errors="replace")
    result["diagnostics"] = [line for line in log_text.splitlines()
                             if line.startswith(("SCRIPT ERROR", "ERROR:", "WARNING:"))]
    result["log_sha256"] = digest(log.read_bytes())
    if final:
        result["status"] = "natural_completed" if final["end"] == "game over" else "game_time_cap"
        result.update(game_seconds=final["time"], winner=final["winner"],
                      victory_reason=final["victory_reason"], age_times=final["age_times"],
                      first_contact=final["first_contact"],
                      late_totals=final["late_economy"]["totals"],
                      final_stock=final["late_economy"]["samples"][-1]["whole_map_remaining_audit_only"],
                      report_sha256=digest(report.read_bytes()))
        expected = (final["actual_map_archetype"] == style and
                    final["late_economy"]["actual_map_seed"] == seed and
                    final["late_economy"]["starting_workers"] == 3 and
                    final["population_limit"] == 100 and
                    final["match_mode"] == 0 and
                    final["human_difficulty"] == human_difficulty and
                    final["difficulty"] == enemy_difficulty and
                    final["late_economy"]["autosave_disabled_for_pacing"] and
                    final["simulation"]["time_scale"] == scale)
        if not expected:
            result["status"] = "setup_mismatch"
    elif result["status"] == "running":
        result["status"] = "missing_final_report"
    if latest:
        result["last_persisted_game_seconds"] = latest["time"]
        result["observer_performance"] = latest["late_economy"]["performance"]
    print("RESULT " + json.dumps(result), flush=True)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=Path(os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot")))
    parser.add_argument("--ref", default="9d1d05b", help="Frozen Git revision for runtime scripts/scenes/project")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--duration", type=float, default=1800)
    parser.add_argument("--wall-timeout", type=float, default=1800)
    parser.add_argument("--scale", choices=("adaptive", "1", "3"), default="adaptive")
    parser.add_argument("--case", type=parse_case, action="append", help="Repeatable style:seed[:player0_difficulty:player1_difficulty]; defaults River424242 and Golden7, Medium both")
    args = parser.parse_args()
    args.output = args.output.resolve()
    if (args.output / "receipt.json").exists():
        parser.error("Output already contains a receipt; choose a fresh directory to preserve earlier evidence")
    args.output.mkdir(parents=True, exist_ok=True)
    if not 0 < args.duration <= 1800 or not 0 < args.wall_timeout <= 1800:
        parser.error("Each case is bounded to at most 1800 game and 1800 wall seconds")
    if not args.godot.is_file():
        parser.error("Godot executable not found")
    revision = subprocess.check_output(["git", "rev-parse", args.ref], cwd=ROOT, text=True).strip()
    cases = args.case or list(DEFAULT_CASES)
    if len(cases) != len(set(cases)) or len(cases) > 3:
        parser.error("Request at most three distinct cases per bounded invocation")
    observer = {name: (ROOT / name).read_bytes() for name in OBSERVER_FILES}
    receipt = {"runtime_revision": revision, "observer_sha256": {name: digest(data) for name, data in observer.items()},
               "scope": "Sequential paid Standard 100 simulations, three starting workers, Crownlands both; difficulties listed per case and natural victory enabled. Headless/no render. Autosave disabled only by runner autoload override; not persistence, human or phone evidence.",
               "requested_cases": cases,
               "game_seconds_cap": args.duration, "wall_seconds_cap": args.wall_timeout,
               "runs": []}
    def save_receipt() -> None:
        (args.output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    save_receipt()
    with tempfile.TemporaryDirectory(prefix="pocket-pacing-frozen-", dir=args.output) as temporary:
        project = Path(temporary)
        assert project.resolve().is_relative_to(args.output)
        freeze_project(project)
        archive_data = subprocess.check_output(
            ["git", "archive", "--format=zip", revision, "scripts", "scenes", "project.godot", "tools/probe_ai_compact_paid_match.gd"], cwd=ROOT,
        )
        with zipfile.ZipFile(io.BytesIO(archive_data)) as archive:
            archive.extractall(project)
        for name, data in observer.items():
            (project / name).parent.mkdir(parents=True, exist_ok=True)
            (project / name).write_bytes(data)
        config = (project / "project.godot").read_text(encoding="utf-8")
        config = "\n".join(line for line in config.splitlines() if not line.startswith(("config/use_custom_user_dir=", "config/custom_user_dir_name=")))
        original = 'SoloSave="*res://scripts/managers/solo_save.gd"'
        if config.count(original) != 1:
            raise RuntimeError("Expected exactly one ordinary SoloSave autoload")
        config = config.replace(original, 'SoloSave="*res://tools/fixtures/pacing_solo_save.gd"')
        receipt["project_config_sha256_before_private_user_dir"] = digest(config.encode())
        scale = 1 if args.scale == "adaptive" else int(args.scale)
        first = run_case(project, config, args, *cases[0], scale, args.scale == "adaptive")
        receipt["runs"].append(first)
        save_receipt()
        if first["status"] == "pilot_stopped_for_slow_throughput":
            scale = 3
            first = run_case(project, config, args, *cases[0], scale, False)
            receipt["runs"].append(first)
            save_receipt()
        if first["status"] not in ("natural_completed", "game_time_cap") or first["diagnostics"]:
            return 1
        for case in cases[1:]:
            result = run_case(project, config, args, *case, scale, False)
            receipt["runs"].append(result)
            save_receipt()
            if result["status"] not in ("natural_completed", "game_time_cap") or result["diagnostics"]:
                return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
