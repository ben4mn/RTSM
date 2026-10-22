#!/usr/bin/env python3
"""Run isolated ordinary-spending AI matches and summarize actual combat cadence."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--project', type=Path, default=ROOT, help='Frozen runtime project for source-consistent evidence')
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--case', action='append', default=[], help='archetype:seed:opponent difficulty; repeat for a matrix')
parser.add_argument('--duration', type=float, default=900)
parser.add_argument('--jobs', type=int, default=2)
parser.add_argument('--wall-timeout', type=float, default=1200)
parser.add_argument('--human-difficulty', type=int, default=1)
args = parser.parse_args()
args.output = args.output.resolve()
args.output.mkdir(parents=True, exist_ok=True)
cases = [tuple(map(int, case.split(':'))) for case in args.case] or [(a, seed, 1) for a in range(3) for seed in (101, 424242)]
if any(len(case) != 3 for case in cases):
    parser.error('--case must be archetype:seed:difficulty')
godot = os.environ.get('GODOT_BIN', '/Applications/Godot.app/Contents/MacOS/Godot')


def run_case(case):
    archetype, seed, difficulty = case
    name = f'map{archetype}-seed{seed}-difficulty{difficulty}'
    report = args.output / f'{name}.json'
    log = args.output / f'{name}.log'
    command = [godot, '--headless', '--fixed-fps', '60', '--path', str(args.project.resolve()),
               'res://tools/probe_ai_compact_paid_match.tscn', '--', '--pop=30',
               f'--seed={seed}', f'--difficulty={difficulty}', f'--human-difficulty={args.human_difficulty}',
               f'--duration={args.duration}', f'--archetype={archetype}', f'--output={report}']
    started = time.monotonic()
    environment = os.environ.copy()
    environment.update(AOEM_AI_DIFFICULTY=str(difficulty), AOEM_MAP_ARCHETYPE=str(archetype), AOEM_SIM_TIME_SCALE='1')
    with log.open('w') as stream:
        try:
            result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, timeout=args.wall_timeout, env=environment)
        except subprocess.TimeoutExpired:
            return {'case': name, 'error': 'wall timeout', 'log': str(log)}
    text = log.read_text()
    if result.returncode or 'SCRIPT ERROR' in text or 'ERROR:' in text or not report.exists():
        return {'case': name, 'error': f'process failed ({result.returncode})', 'log': str(log)}
    data = json.loads(report.read_text())
    if int(data.get('actual_map_archetype', 0)) != archetype:
        return {'case': name, 'error': 'requested archetype does not match generated map', 'log': str(log)}
    if float(data.get('simulation', {}).get('time_scale', 0)) != 1:
        return {'case': name, 'error': 'unexpected simulation time scale', 'log': str(log)}
    cadence = data.get('cadence', {})
    first = float(data.get('first_contact', -1))
    elapsed = float(data['time'])
    return {'case': name, 'map': archetype, 'seed': seed, 'difficulty': difficulty,
            'wall_seconds': round(time.monotonic() - started, 2), 'simulation_seconds': round(elapsed, 2),
            'outcome': data['victory_reason'], 'first_contact': round(first, 2),
            'first_attack': data['first_attack'], 'attacks': data['attacks'],
            'damage_active_seconds': cadence.get('damage_active_seconds', 0),
            'damage_fraction_after_contact': round(cadence.get('damage_active_seconds', 0) / max(1, elapsed-first), 3) if first >= 0 else 0,
            'longest_quiet_gap': round(cadence.get('longest_quiet_gap_after_contact', 0), 2),
            'gaps_over_45_seconds': [gap for gap in cadence.get('quiet_gaps_over_15_seconds', []) if gap['seconds'] > 45],
            'worker_raid_hits': cadence.get('worker_raid_hits'), 'victim_role_hits': cadence.get('victim_role_hits'),
            'counter_hits_by_role': data.get('counter_hits_by_role'), 'decision_seconds': cadence.get('decision_seconds'),
            'kills': data['kills'], 'peak_troops': data['peak_troops'], 'peak_workers': data['peak_workers'],
            'ages': data['ages'], 'deposits': data['deposited_by_resource'],
            'runtime_source_hashes': data['runtime_source_hashes'], 'report': str(report), 'log': str(log)}


results = []
with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as executor:
    futures = {executor.submit(run_case, case): case for case in cases}
    for future in as_completed(futures):
        row = future.result()
        results.append(row)
        (args.output / 'summary.json').write_text(json.dumps({'scope': 'Automated paid AI policy versus AI; 60Hz fixed simulation, no resource grants or free units. Not human input or rendered performance evidence.', 'cases': results}, indent=2)+'\n')
        print(json.dumps({key: value for key, value in row.items() if key not in ('runtime_source_hashes', 'decision_seconds', 'gaps_over_45_seconds')}), flush=True)

lines = ['# Paid AI cadence matrix', '', 'Automated paid policies on both sides, normal resources and 30 population. Damage cadence is measured from actual HP-loss signals. This is not human play or a rendered FPS benchmark.', '', '| Case | End (s) | First damage (s) | Damage-active seconds | Longest quiet gap (s) | Worker raid hits | Outcome |', '|---|---:|---:|---:|---:|---|---|']
for row in sorted(results, key=lambda item: item['case']):
    if 'error' in row:
        lines.append(f"| {row['case']} | — | — | — | — | — | {row['error']} |")
    else:
        lines.append(f"| {row['case']} | {row['simulation_seconds']} | {row['first_contact']} | {row['damage_active_seconds']} | {row['longest_quiet_gap']} | {row['worker_raid_hits']} | {row['outcome']} |")
(args.output / 'summary.md').write_text('\n'.join(lines)+'\n')
raise SystemExit(1 if any('error' in row for row in results) else 0)
