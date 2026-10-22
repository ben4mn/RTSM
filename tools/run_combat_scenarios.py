#!/usr/bin/env python3
"""Run the real Godot tactical fixtures and summarize reproducible receipts.

Example: python3 tools/run_combat_scenarios.py --seeds 101 424242 20261021
These are free-army fixtures, not paid matches or measured human APM.
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import shutil
import statistics
import subprocess


def summarize(paths: list[Path], output: Path) -> dict:
    reports = [json.loads(path.read_text()) for path in paths]
    cases = [case for report in reports for case in report["results"]]
    fields = [
        "map", "seed", "scenario", "policy", "duration_seconds", "end_reason",
        "first_hit_seconds", "largest_hit_gap_seconds", "final_quiet_seconds",
        "winner", "survivors", "remaining_hp", "damage", "kills",
        "friendly_overlap_pair_seconds", "enemy_overlap_pair_seconds",
        "navigation_stall_unit_seconds", "navigation_failures",
        "idle_near_enemy_seconds", "intervention_orders", "intervention_orders_per_minute",
        "command_response_p95_ms", "command_unanswered", "target_changes",
        "unit_update_cpu_ms_p50", "unit_update_cpu_ms_p95", "unit_update_cpu_ms_max",
        "command_cpu_ms",
    ]
    summary = {
        "method": reports[0]["method"],
        "unit_base_sha256": sorted({report.get("unit_base_sha256", "unrecorded") for report in reports}),
        "probe_sha256": sorted({report.get("probe_sha256", "unrecorded") for report in reports}),
        "case_count": len(cases),
        "missing_contact": sum(case["first_hit_seconds"] < 0 for case in cases),
        "navigation_failures": sum(case["navigation_failures"] for case in cases),
        "navigation_stall_unit_seconds": sum(case["navigation_stall_unit_seconds"] for case in cases),
        "command_unanswered": sum(case["command_unanswered"] for case in cases),
        "first_hit_range_seconds": [min(case["first_hit_seconds"] for case in cases), max(case["first_hit_seconds"] for case in cases)],
        "median_case_p95_unit_update_cpu_ms": statistics.median(case["unit_update_cpu_ms_p95"] for case in cases),
        "cases": [{field: case.get(field) for field in fields} for case in cases],
    }
    output.mkdir(parents=True, exist_ok=True)
    (output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    with (output / "summary.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(summary["cases"])
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot")
    parser.add_argument("--seeds", nargs="+", type=int, default=[101, 424242, 20261021])
    parser.add_argument("--maps", nargs="+", type=int, choices=[0, 1, 2], default=[0, 1, 2])
    parser.add_argument("--output", type=Path, default=Path("output/combat-scenarios"))
    parser.add_argument("--prefix", default="battle")
    parser.add_argument("--summarize-only", action="store_true")
    parser.add_argument("--timeout", type=int, default=120)
    args = parser.parse_args()
    project = Path(__file__).resolve().parent.parent
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    paths = []
    for archetype in args.maps:
        for seed in args.seeds:
            report = output / f"{args.prefix}-{seed}-{archetype}.json"
            paths.append(report)
            if args.summarize_only:
                continue
            command = [args.godot, "--headless", "--path", str(project),
                       "tools/probe_combat_scenarios.tscn", "--", f"--seed={seed}",
                       f"--map={archetype}", f"--output={report}"]
            with report.with_suffix(".log").open("w") as log:
                subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                               check=True, timeout=args.timeout)
            data = json.loads(report.read_text())
            if len(data["results"]) != 8:
                raise RuntimeError(f"Expected eight scenario/policy results in {report}")
            print(f"completed seed={seed} map={archetype}", flush=True)
    summary = summarize(paths, output)
    print(json.dumps({key: value for key, value in summary.items() if key not in {"method", "cases"}}, indent=2))


if __name__ == "__main__":
    main()
