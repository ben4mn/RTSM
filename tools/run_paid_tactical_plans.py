#!/usr/bin/env python3
"""Run paid tactical plan probes in isolated projects, preserving source hashes."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import json
import os
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--project', type=Path, default=ROOT)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--maps', type=int, nargs='+', default=[0, 1, 2])
parser.add_argument('--seed', type=int, default=101)
parser.add_argument('--plans', nargs='+', default=['infantry_pressure', 'ranged_screen', 'mounted_flank', 'mounted_direct', 'mounted_staged'])
parser.add_argument('--jobs', type=int, default=2)
parser.add_argument('--timeout', type=float, default=900)
parser.add_argument('--render', action='store_true', help='Native captures after the ordinary paid opening; no FPS measurement')
args = parser.parse_args()
args.output = args.output.resolve()
args.output.mkdir(parents=True, exist_ok=True)
godot = os.environ.get('GODOT_BIN', '/Applications/Godot.app/Contents/MacOS/Godot')


def validate_paid_fixture(data, archetype):
    errors = []
    if data.get('map') != archetype or data.get('economic_bonus_active'):
        errors.append('wrong map or economic bonus')
    if data.get('initial_resources') != [{'food': 250, 'wood': 250, 'gold': 100}] * 2 or data.get('ages') != [2, 2]:
        errors.append('ordinary starting banks/paid ages differ')
    if any(stats['units_trained'] - stats['army_trained'] != 6 for stats in data.get('opening_stats', [])):
        errors.append('worker purchases differ from six per owner')
    actual = [{}, {}]
    for unit in data.get('initial_tactical_units', {}).get('units', []):
        if unit['hp'] != unit['max_hp']:
            errors.append('tactical unit starts wounded')
        owner, role = unit['owner'], str(unit['role'])
        actual[owner][role] = actual[owner].get(role, 0) + 1
    plan = data.get('plan')
    expected = {'1': 6} if plan == 'infantry_pressure' else ({'1': 2, '2': 4} if plan == 'ranged_screen' else {'1': 2, '3': 3})
    if actual != [expected, {'1': 3, '2': 3}]:
        errors.append('completed roster differs from declared paid plan')
    if data.get('failures'):
        errors.extend(data['failures'])
    return errors


def run_case(case):
    archetype, plan = case
    name = f'map{archetype}-seed{args.seed}-{plan}'
    report, log = args.output / f'{name}.json', args.output / f'{name}.log'
    if report.exists():
        report.unlink()
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix='aoem-paid-tactic-') as temporary:
        project = Path(temporary)
        for entry in args.project.resolve().iterdir():
            if entry.name not in ('project.godot', 'override.cfg', '.git', 'output', 'builds'):
                (project / entry.name).symlink_to(entry, target_is_directory=entry.is_dir())
        text = (args.project / 'project.godot').read_text()
        text = '\n'.join(line for line in text.splitlines() if not line.startswith(('config/use_custom_user_dir=', 'config/custom_user_dir_name=')))
        text = text.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="aoem-tactical-probes/' + uuid.uuid4().hex + '"', 1)
        (project / 'project.godot').write_text(text + '\n')
        command = [godot, *([] if args.render else ['--headless']), '--fixed-fps', '60', '--path', str(project),
                   'res://tools/probe_paid_tactical_plans.tscn', '--', f'--seed={args.seed}',
                   f'--map={archetype}', f'--plan={plan}', f'--output={report}']
        if args.render:
            command.append(f'--capture={args.output / name}')
        environment = os.environ.copy()
        environment.update(AOEM_AI_DIFFICULTY='1', AOEM_MAP_ARCHETYPE=str(archetype), AOEM_SIM_TIME_SCALE='1')
        with log.open('w') as output:
            try:
                status = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, env=environment, timeout=args.timeout)
            except subprocess.TimeoutExpired:
                return {'case': name, 'error': 'wall timeout', 'log': str(log)}
    log_text = log.read_text()
    if status.returncode or 'SCRIPT ERROR' in log_text or 'ERROR:' in log_text or not report.exists():
        return {'case': name, 'error': f'process failure ({status.returncode})', 'log': str(log)}
    data = json.loads(report.read_text())
    validation_errors = validate_paid_fixture(data, archetype)
    if validation_errors:
        return {'case': name, 'error': '; '.join(validation_errors), 'log': str(log)}
    return {'case': name, 'wall_seconds': round(time.monotonic() - started, 2), 'report': str(report),
            **{key: data[key] for key in ['plan', 'map', 'paid_ready_at', 'opening_seconds', 'first_hit', 'tactical_seconds', 'end', 'survivors', 'remaining_hp', 'navigation_failures', 'navigation_stall_unit_seconds', 'severe_friendly_overlap_pair_seconds', 'group_orders_per_minute', 'failures']}}


results = []
with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as executor:
    futures = [executor.submit(run_case, case) for case in [(m, p) for m in args.maps for p in args.plans]]
    for future in as_completed(futures):
        result = future.result()
        results.append(result)
        (args.output / 'summary.json').write_text(json.dumps({'cases': results}, indent=2) + '\n')
        print(json.dumps(result), flush=True)
raise SystemExit(1 if any('error' in row for row in results) else 0)
