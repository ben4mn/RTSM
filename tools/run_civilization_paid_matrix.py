#!/usr/bin/env python3
"""Run source-selected, isolated paid matches with civilization/investment receipts."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import uuid

from run_focused_tests import terminate_process_tree

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--project', type=Path, default=ROOT)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--case', action='append', required=True,
                    help='map:seed:difficulty:human civilization:opponent civilization')
parser.add_argument('--duration', type=float, default=1200)
parser.add_argument('--jobs', type=int, default=1)
parser.add_argument('--wall-timeout', type=float, default=3600)
args = parser.parse_args()
args.output = args.output.resolve()
args.output.mkdir(parents=True, exist_ok=True)
cases = [tuple(map(int, item.split(':'))) for item in args.case]
if any(len(case) != 5 for case in cases):
    parser.error('--case requires five colon-separated integers')
godot = os.environ.get('GODOT_BIN', '/Applications/Godot.app/Contents/MacOS/Godot')


def run_case(case):
    archetype, seed, difficulty, civilization, opponent = case
    name = f'map{archetype}-seed{seed}-d{difficulty}-c{civilization}v{opponent}'
    report = args.output / f'{name}.json'
    log = args.output / f'{name}.log'
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix='pocket-civilization-paid-') as temp:
        project = Path(temp)
        for entry in args.project.resolve().iterdir():
            if entry.name not in ('project.godot', 'override.cfg', '.git', 'output', 'builds'):
                (project / entry.name).symlink_to(entry, target_is_directory=entry.is_dir())
        config = '\n'.join(line for line in (args.project / 'project.godot').read_text(encoding='utf-8').splitlines()
                           if not line.startswith(('config/use_custom_user_dir=', 'config/custom_user_dir_name=')))
        config = config.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="pocket-civilization-probes/' + uuid.uuid4().hex + '"', 1)
        (project / 'project.godot').write_text(config + '\n', encoding='utf-8')
        command = [godot, '--headless', '--fixed-fps', '60', '--path', str(project),
                   'res://tools/probe_civilization_paid_match.tscn', '--', '--pop=30',
                   f'--seed={seed}', f'--difficulty={difficulty}', '--human-difficulty=1',
                   f'--archetype={archetype}', f'--duration={args.duration}',
                   f'--civilization={civilization}', f'--opponent-civilization={opponent}',
                   f'--output={report}']
        environment = os.environ.copy()
        environment.update(AOEM_AI_DIFFICULTY=str(difficulty), AOEM_MAP_ARCHETYPE=str(archetype), AOEM_SIM_TIME_SCALE='1')
        with log.open('w', encoding='utf-8') as stream:
            process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT,
                                       env=environment, start_new_session=os.name != 'nt')
            try:
                returncode = process.wait(timeout=args.wall_timeout)
            except subprocess.TimeoutExpired:
                terminate_process_tree(process)
                process.wait(timeout=15)
                return {'case': name, 'error': 'wall timeout', 'log': str(log)}
    text = log.read_text(encoding='utf-8', errors='replace')
    if returncode or 'SCRIPT ERROR' in text or 'ERROR:' in text or not report.exists():
        return {'case': name, 'error': f'process failed ({returncode})', 'log': str(log)}
    data = json.loads(report.read_text(encoding='utf-8'))
    if data.get('actual_map_archetype') != archetype or data.get('civilization_choices') != [civilization, opponent] or data.get('actual_civilizations', [0, 0]) != [civilization, opponent]:
        return {'case': name, 'error': 'requested setup mismatch', 'report': str(report)}
    investments = data['economic_investments']
    return {'case': name, 'wall_seconds': round(time.monotonic() - started, 2),
            'simulation_seconds': round(data['time'], 2), 'winner': data['winner'],
            'outcome': data['victory_reason'], 'age_times': data['age_times'],
            'first_contact': data['first_contact'],
            'longest_quiet_gap': data['cadence']['longest_quiet_gap_after_contact'],
            'deposits': data['deposited_by_resource'], 'kills': data['kills'],
            'research': investments['research_events'], 'camps': investments['camp_events'],
            'report': str(report), 'log': str(log)}


results = []
with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
    for future in as_completed([pool.submit(run_case, case) for case in cases]):
        row = future.result()
        results.append(row)
        print(json.dumps(row), flush=True)
        (args.output / 'summary.json').write_text(json.dumps({
            'scope': 'Ordinary-cost automated policy matches; fixed 60Hz/time scale 1. Not human play, phone or rendered performance evidence.',
            'project': str(args.project.resolve()), 'cases': results}, indent=2) + '\n', encoding='utf-8')
raise SystemExit(1 if any('error' in row for row in results) else 0)
