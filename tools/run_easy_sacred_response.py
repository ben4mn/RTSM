#!/usr/bin/env python3
"""Run natural, paid Easy Sacred openings in frozen projects/private user data.

Examples:
  python3 tools/run_easy_sacred_response.py --revision 6cf0cda --output output/sacred/baseline
  python3 tools/run_easy_sacred_response.py --output output/sacred/candidate --baseline output/sacred/baseline
  python3 tools/run_easy_sacred_response.py --maps 0 1 2 --seeds 101 --scenarios delayed reinforced --output output/sacred/extra

No free units, grants, relocation, fog reveal or disabled simulation. These are
scripted transaction/order policies, not measurements of player skill or FPS.
"""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ['scripts/ai/ai_controller.gd', 'scripts/data/skirmish_data.gd', 'scripts/main/main.gd',
           'scripts/units/unit_base.gd', 'scripts/map/map_generator.gd', 'scripts/map/game_map.gd',
           'scripts/map/sacred_site.gd', 'scripts/data/unit_data.gd', 'scripts/buildings/production_queue.gd',
           'scripts/managers/resource_manager.gd', 'scripts/managers/fog_manager.gd']
METRICS = ['seed', 'map', 'scenario', 'scout_produced_at', 'first_ring_entry', 'claim_at', 'ended_at',
           'winner', 'victory_reason', 'first_ai_ring_entry', 'first_contest_at', 'first_ai_objective_order_at',
           'first_scout_damage_at', 'first_ai_field_attack_at', 'first_ai_fighter_at',
           'first_site_visible_to_ai', 'first_scout_visible_to_ai', 'first_home_damage_at',
           'first_ai_capture_at', 'max_ai_objective_fighters', 'reinforcement_queued', 'reinforcement_orders']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate(data, case, hashes):
    archetype, seed, scenario = case
    errors = list(data.get('failures', []))
    if data['actual_ai_difficulty'] != 0 or data['actual_map'] != archetype or data['seed'] != seed or data['scenario'] != scenario:
        errors.append('requested mode differs from actual match')
    if data['actual_guided_opening'] or data['economic_bonus_active']:
        errors.append('guided opening or free economy bonus active')
    if data['initial_banks'] != [{'food': 250, 'wood': 250, 'gold': 100}] * 2:
        errors.append('ordinary starting banks differ')
    if data['bank_immediately_after_train'] != {'food': 210, 'wood': 250, 'gold': 90}:
        errors.append('Scout payment differs')
    if not 7.99 <= data['scout_produced_at'] - data['train_requested_at'] <= 8.05:
        errors.append('normal paid Scout training duration differs')
    if not data.get('move_is_passive'):
        errors.append('Scout ground move did not preserve passive intent')
    if scenario == 'delayed' and not 180.0 <= data.get('move_order_at', -1) <= 180.05:
        errors.append('delayed command timestamp differs')
    queued = [x['unit_type'] for x in data['queue_ledger'] if x['owner'] == 0 and x['operation'] == 'queued']
    if sorted(queued) != ([1, 1, 4] if scenario == 'reinforced' else [4]):
        errors.append('human paid queue differs from declared policy')
    spending = {resource: -sum(x['delta'] for x in data['bank_ledger'] if x['owner'] == 0 and x['resource'] == resource and x['delta'] < 0) for resource in ['food', 'wood', 'gold']}
    if spending != ({'food': 140, 'wood': 160, 'gold': 10} if scenario == 'reinforced' else {'food': 40, 'wood': 0, 'gold': 10}):
        errors.append(f'human spending differs: {spending}')
    for owner in [0, 1]:
        for resource in ['food', 'wood', 'gold']:
            amount = data['initial_banks'][owner][resource] + sum(x['delta'] for x in data['bank_ledger'] if x['owner'] == owner and x['resource'] == resource)
            if amount != data['final_banks'][owner][resource]:
                errors.append(f'bank ledger mismatch {owner}:{resource}')
    routes = [route for route in data['scout_routes'] if route['tiles']]
    if not routes or not all(route['waypoints_walkable'] for route in routes):
        errors.append('Scout route absent or nonwalkable')
    if data['runtime_source_hashes'] != hashes:
        errors.append('runtime source does not match frozen project')
    if 0 <= data['first_ai_field_attack_at'] < 299.99:
        errors.append('ordinary field attack starts before300s')
    if 0 <= data['first_home_damage_at'] < 299.99:
        errors.append('AI damages quiet human home before300s')
    if data['max_ai_objective_fighters'] > 3:
        errors.append('objective exceeds pre480s Easy three-fighter cap')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--project', type=Path, default=ROOT)
    parser.add_argument('--revision', help='Freeze this Git revision instead of the working tree')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--baseline', type=Path, help='Optional existing raw results for matched event comparison')
    parser.add_argument('--maps', type=int, nargs='+', default=[0, 1, 2])
    parser.add_argument('--seeds', type=int, nargs='+', default=[101, 424242, 20261021])
    parser.add_argument('--scenarios', choices=['earliest', 'delayed', 'reinforced'], nargs='+', default=['earliest'])
    parser.add_argument('--extra-scenarios', choices=['delayed', 'reinforced'], nargs='*', default=[], help='Append these policies for the first selected seed only')
    parser.add_argument('--jobs', type=int, default=3)
    parser.add_argument('--duration', type=float, default=420.0)
    parser.add_argument('--timeout', type=float, default=900.0)
    parser.add_argument('--expect-response', action='store_true', help='Assert earliest rush is contested after150s and before its natural solo victory')
    args = parser.parse_args()
    args.project = args.project.resolve()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    if args.duration > 480:
        parser.error('This probe validates the pre480s three-fighter cap; use duration<=480')
    workspace = Path(tempfile.mkdtemp(prefix='aoem-sacred-response-'))
    frozen = workspace / 'source'
    frozen.mkdir()
    if args.revision:
        archive = workspace / 'source.tar'
        with archive.open('wb') as handle:
            subprocess.run(['git', 'archive', '--format=tar', args.revision], cwd=args.project, stdout=handle, check=True)
        subprocess.run(['tar', '-xf', str(archive), '-C', str(frozen)], check=True)
        archive.unlink()
        shutil.copytree(args.project / '.godot', frozen / '.godot')
        identity = subprocess.check_output(['git', 'rev-parse', args.revision], cwd=args.project, text=True).strip()
    else:
        for entry in args.project.iterdir():
            if entry.name in {'.git', 'output', 'build', 'builds', '.DS_Store'}:
                continue
            if entry.is_dir():
                shutil.copytree(entry, frozen / entry.name)
            else:
                shutil.copy2(entry, frozen / entry.name)
        identity = 'working tree snapshot'
    for filename in ['probe_easy_sacred_response.gd', 'probe_easy_sacred_response.gd.uid', 'probe_easy_sacred_response.tscn']:
        shutil.copy2(ROOT / 'tools' / filename, frozen / 'tools' / filename)
    hashes = {path: digest(frozen / path) for path in RUNTIME}
    metadata = {'identity': identity, 'stage': str(workspace), 'runtime_source_hashes': hashes,
                'probe_sha256': digest(frozen / 'tools/probe_easy_sacred_response.gd'),
                'runner_sha256': digest(Path(__file__)), 'duration': args.duration}
    (args.output / 'source.json').write_text(json.dumps(metadata, indent=2) + '\n')

    def run_case(case):
        archetype, seed, scenario = case
        name = f'map{archetype}-seed{seed}-{scenario}'
        stage = workspace / name
        stage.mkdir()
        for entry in frozen.iterdir():
            if entry.name == 'project.godot':
                continue
            if entry.name == '.godot':
                shutil.copytree(entry, stage / entry.name)
            else:
                (stage / entry.name).symlink_to(entry, target_is_directory=entry.is_dir())
        text = (frozen / 'project.godot').read_text()
        text = '\n'.join(line for line in text.splitlines() if not line.startswith(('config/use_custom_user_dir=', 'config/custom_user_dir_name=')))
        text = text.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="aoem-sacred-response/' + uuid.uuid4().hex + '"', 1)
        (stage / 'project.godot').write_text(text + '\n')
        log, report = args.output / f'{name}.log', args.output / f'{name}.json'
        if report.exists():
            report.unlink()
        environment = os.environ.copy()
        environment.update(AOEM_AI_DIFFICULTY='0', AOEM_MAP_ARCHETYPE=str(archetype), AOEM_MAP_SEED=str(seed), AOEM_POPULATION_LIMIT='30', AOEM_SIM_TIME_SCALE='1')
        started = time.monotonic()
        with log.open('w') as handle:
            try:
                result = subprocess.run([os.environ.get('GODOT_BIN', '/Applications/Godot.app/Contents/MacOS/Godot'), '--headless', '--fixed-fps', '60', '--path', str(stage), 'res://tools/probe_easy_sacred_response.tscn', '--', f'--map={archetype}', f'--seed={seed}', f'--scenario={scenario}', f'--duration={args.duration}', f'--output={report}'], env=environment, stdout=handle, stderr=subprocess.STDOUT, timeout=args.timeout)
            except subprocess.TimeoutExpired:
                return {'case': name, 'errors': ['process wall timeout'], 'log': str(log)}
        if result.returncode or 'SCRIPT ERROR' in log.read_text() or 'ERROR:' in log.read_text() or not report.exists():
            return {'case': name, 'errors': ['process error'], 'returncode': result.returncode, 'log': str(log)}
        data = json.loads(report.read_text())
        errors = validate(data, case, hashes)
        if args.expect_response and scenario == 'earliest':
            solo_win = data['claim_at'] + data['site']['hold_seconds']
            if not 149.99 <= data['first_ai_objective_order_at'] < solo_win or not 0 <= data['first_contest_at'] < solo_win:
                errors.append('earliest paid rush not contested before natural solo win')
            if data['winner'] == 0:
                errors.append('unreinforced Scout wins despite reactive response')
        row = {'case': name, 'wall_seconds': round(time.monotonic() - started, 2), 'report': str(report), 'errors': errors, **{key: data[key] for key in METRICS}}
        row['site_events'] = [event for event in data['events'] if event['kind'] in ['captured', 'neutralized', 'contested']]
        for event in row['site_events']:
            event['detail'] = {key: value for key, value in event['detail'].items() if key != 'units' and key != 'ai_strategy'}
        if args.baseline:
            before_path = args.baseline / report.name
            if before_path.exists():
                before = json.loads(before_path.read_text())
                row['baseline'] = {key: before[key] for key in METRICS if key in before}
                row['opening_identical'] = all(before[key] == data[key] for key in ['scout_produced_at', 'move_order_at', 'first_ring_entry'])
                if before['terrain'] != data['terrain']:
                    errors.append('matched terrain/path fixture differs')
        return row

    cases = [(m, seed, scenario) for scenario in args.scenarios for seed in args.seeds for m in args.maps]
    cases += [(m, args.seeds[0], scenario) for scenario in args.extra_scenarios if scenario not in args.scenarios for m in args.maps]
    results = []
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        futures = [pool.submit(run_case, case) for case in cases]
        for future in as_completed(futures):
            row = future.result()
            results.append(row)
            (args.output / 'summary.json').write_text(json.dumps({'source': metadata, 'cases': sorted(results, key=lambda item: item['case'])}, indent=2) + '\n')
            print(json.dumps({key: value for key, value in row.items() if key not in ['baseline', 'site_events']}), flush=True)
    return 1 if any(row['errors'] for row in results) else 0


if __name__ == '__main__':
    raise SystemExit(main())
