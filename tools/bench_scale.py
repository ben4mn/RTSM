#!/usr/bin/env python3
"""Run tools/bench_scale.tscn at several body counts and print a comparison table.

Each (bodies) case runs `--repeats` times serially and keeps the best wall/game
ratio (the build box is shared, so the best run is the least disturbed one).

  GODOT_BIN=~/aoem-dev/bin/godot python3 tools/bench_scale.py --bodies 30,60,120       --seconds 30 --repeats 3 --label before --out output/bench/before.json
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('--bodies', default='30,60,120', help='comma list of bodies PER SIDE (total is double)')
parser.add_argument('--seconds', type=float, default=30.0, help='measured game seconds per run')
parser.add_argument('--repeats', type=int, default=3)
parser.add_argument('--net', type=int, default=1, help='1 = also build and encode authority snapshots at 10 Hz')
parser.add_argument('--select', type=int, default=0, help='keep this many own units selected (HUD refresh path)')
parser.add_argument('--seed', type=int, default=100)
parser.add_argument('--label', default='')
parser.add_argument('--top', type=int, default=14, help='systems to print per case')
parser.add_argument('--out', type=Path, required=True)
args = parser.parse_args()
godot = os.environ.get('GODOT_BIN', 'godot')
out = args.out if args.out.is_absolute() else ROOT / args.out
out.parent.mkdir(parents=True, exist_ok=True)
results = []
for bodies in [int(value) for value in args.bodies.split(',') if value.strip()]:
    best = None
    ratios = []
    for repeat in range(args.repeats):
        with tempfile.TemporaryDirectory(prefix='bench-scale-') as home:
            report = Path(home) / 'report.json'
            environment = os.environ.copy()
            for key in ('AOEM_AI_DIFFICULTY', 'AOEM_SIM_TIME_SCALE', 'AOEM_MAP_SEED', 'AOEM_MAP_ARCHETYPE', 'AOEM_POPULATION_LIMIT'):
                environment.pop(key, None)
            environment.update(XDG_DATA_HOME=home, XDG_CONFIG_HOME=home)
            command = [godot, '--headless', '--fixed-fps', '60', '--path', str(ROOT), 'res://tools/bench_scale.tscn', '--',
                       f'--bodies={bodies}', f'--seconds={args.seconds}', f'--seed={args.seed}', f'--net={args.net}',
                       f'--select={args.select}', f'--label={args.label}', f'--output={report}']
            completed = subprocess.run(command, capture_output=True, text=True, errors='replace', env=environment,
                                       timeout=max(600.0, args.seconds * 40))
            if not report.exists():
                print(f'[bench] bodies={bodies} repeat={repeat}: no report (exit {completed.returncode})')
                print(completed.stdout[-2000:])
                continue
            data = json.loads(report.read_text())
            data['script_errors'] = (completed.stdout + completed.stderr).count('SCRIPT ERROR')
        ratios.append(data['realtime_ratio'])
        if best is None or data['realtime_ratio'] > best['realtime_ratio']:
            best = data
    if best is None:
        continue
    best['all_ratios'] = ratios
    results.append(best)
    frame = best['frame_ms']
    print(f"
== {args.label} bodies/side={bodies} total~{best['average_living_bodies']:.0f} attacking~{best['average_attacking']:.0f} "
          f"buildings={best['buildings']} net={best['net']} ==")
    print(f"realtime x{best['realtime_ratio']:.2f} (runs {ratios})  frame ms mean {frame['mean']} p50 {frame['p50']} p95 {frame['p95']} max {frame['max']}  "
          f"snapshot {best['snapshot_bytes_mean']} B  script_errors {best['script_errors']}  unattributed {best['unattributed_share']:.1%}")
    for name, row in list(best['systems'].items())[:args.top]:
        print(f"  {name:<28} {row['ms_per_game_second']:>9.2f} ms/game-s  {row['share']:>6.1%}  calls {row['calls']}")
out.write_text(json.dumps({'label': args.label, 'results': results}, indent=1))
print(f'
wrote {out}')
