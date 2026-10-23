#!/usr/bin/env python3
"""Frozen real WebSocket authority plus two independent native-rendered clients.

Scripted paid commands are gameplay automation, not manual UI play. The runner
preserves logs, source receipt, viewport PNGs, same-tick authority packets, and
replica checks. No accelerated clock, simulated network, or fixture state grants.
--headless is an explicitly separate tuning mode and never native evidence.
"""
from __future__ import annotations
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import shlex
import signal
import socket
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
GODOT = Path('/Applications/Godot.app/Contents/MacOS/Godot')
APP = Path('/Applications/Godot.app')


def save(path, obj):
    path.write_text(json.dumps(obj, indent=2) + '\n')


def hashes(folder):
    return {str(p.relative_to(folder)): hashlib.sha256(p.read_bytes()).hexdigest()
            for name in ('scripts', 'scenes', 'assets', 'tools')
            for p in sorted((folder / name).rglob('*'))
            if p.is_file() and '__pycache__' not in p.parts and p.suffix != '.import'}


def hash_delta(before, after):
    return {'added': sorted(after.keys() - before.keys()),
            'removed': sorted(before.keys() - after.keys()),
            'changed': sorted(key for key in before.keys() & after.keys() if before[key] != after[key])}


def owned_game_processes(project_paths, rows=None):
    """Match the full executable and exact private --path, never a substring."""
    if rows is None:
        rows = subprocess.check_output(['ps', '-axo', 'pid=,args='], text=True).splitlines()
    permitted = {str(Path(path).resolve()) for path in project_paths}
    matches = []
    for row in rows:
        parts = row.strip().split(None, 1)
        if len(parts) != 2: continue
        try:
            tokens = shlex.split(parts[1])
            if not tokens or Path(tokens[0]).resolve() != GODOT.resolve(): continue
            path = str(Path(tokens[tokens.index('--path') + 1]).resolve())
            if path in permitted: matches.append({'pid': int(parts[0]), 'project': path})
        except (ValueError, IndexError):
            continue
    return matches


def freeze(source, out):
    stage = Path(tempfile.mkdtemp(prefix='aoem-multiplayer-native-'))
    common = stage / 'common'
    common.mkdir()
    for name in ('.godot', 'addons', 'assets', 'resources', 'scenes', 'scripts', 'tools'):
        if (source / name).exists():
            shutil.copytree(source / name, common / name, ignore=shutil.ignore_patterns('__pycache__'))
    for name in ('project.godot', 'default_bus_layout.tres', 'icon.svg', 'icon.svg.import'):
        if (source / name).exists(): shutil.copy2(source / name, common / name)
    pre_import_manifest = hashes(common)
    original_config = (common / 'project.godot').read_text()
    with (out / 'import.log').open('w') as log:
        result = subprocess.run([str(GODOT), '--headless', '--editor', '--path', str(common), '--quit'], stdout=log, stderr=subprocess.STDOUT, timeout=120)
    (common / 'project.godot').write_text(original_config)
    import_text = (out / 'import.log').read_text()
    if result.returncode or any(x in import_text for x in ('SCRIPT ERROR', 'Parse Error', 'ERROR:')):
        raise RuntimeError('Frozen import failed; inspect import.log')
    manifest = hashes(common)
    import_delta = hash_delta(pre_import_manifest, manifest)
    import_audit = {'pre_import_source_hashes': pre_import_manifest,
                    'post_import_source_hashes': manifest, 'delta': import_delta,
                    'only_generated_uid_additions': not import_delta['removed'] and not import_delta['changed']
                    and all(path.endswith('.gd.uid') for path in import_delta['added'])}
    save(out / 'import-source-audit.json', import_audit)
    if not import_audit['only_generated_uid_additions']:
        raise RuntimeError('Import changed source beyond generated script UID additions; inspect import-source-audit.json')
    projects = {}
    user_dirs = {}
    for label in ('server', 'host', 'guest'):
        project = stage / label
        project.mkdir()
        for entry in common.iterdir():
            if entry.name != 'project.godot':
                (project / entry.name).symlink_to(entry, target_is_directory=entry.is_dir())
        private = f'aoem-multiplayer-native/{uuid.uuid4().hex}/{label}'
        config = '\n'.join(line for line in original_config.splitlines() if not line.startswith(('config/use_custom_user_dir=', 'config/custom_user_dir_name=')))
        config = config.replace('[application]', f'[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="{private}"', 1)
        (project / 'project.godot').write_text(config + '\n')
        projects[label] = str(project)
        user_dirs[label] = private
    receipt = {'stage': str(stage), 'source_project': str(source), 'projects': projects, 'private_user_dirs': user_dirs, 'source_hashes': manifest, 'source_hash_baseline': 'After successful import, before launching authority or clients; pre-import audit retained in import-source-audit.json', 'scope': 'Frozen current checkout including uncommitted work; shared immutable runtime, separate private preferences'}
    save(out / 'source.json', receipt)
    return receipt


def analyze(out, native, scenario, minimum_wall):
    reports = {role: json.loads((out / f'{role}-report.json').read_text()) for role in ('host', 'guest')}
    failures = []
    for role, report in reports.items():
        failures.extend(f'{role}: {v}' for v in report['failures'])
        if bool(report['native']) != native: failures.append(f'{role}: wrong rendering mode')
    shared_fields = ('match', 'seed', 'map', 'grid_hash')
    agreement = {field: reports['host'].get(field) is not None and reports['guest'].get(field) is not None
                 and reports['host'][field] == reports['guest'][field] for field in shared_fields}
    agreement['opposite_slots'] = {reports['host'].get('slot'), reports['guest'].get('slot')} == {0, 1}
    if scenario != 'interrupt':
        for field in ('winner', 'reason'):
            agreement[field] = reports['host'].get(field) is not None and reports['guest'].get(field) is not None and reports['host'][field] == reports['guest'][field]
    if any(not value for value in agreement.values()): failures.append('client match identity/result mismatch')
    records = {}
    for role in reports:
        records[role] = {}
        for line in (out / f'{role}-snapshots.jsonl').read_text().splitlines():
            record = json.loads(line)
            records[role][int(record['packet']['tick'])] = record
    counters = {'same_tick_samples': 0, 'shared_actor_checks': 0, 'shared_resource_checks': 0}
    mismatches = []
    for tick in sorted(records['host'].keys() & records['guest'].keys()):
        a, b = (records[role][tick]['packet'] for role in ('host', 'guest'))
        counters['same_tick_samples'] += 1
        if a['time'] != b['time'] or a['site'] != b['site']: mismatches.append([tick, 'clock_or_site'])
        actors_a, actors_b = ({int(row['id']): row for row in item['actors']} for item in (a, b))
        for entity_id in actors_a.keys() & actors_b.keys():
            first, second = actors_a[entity_id], actors_b[entity_id]
            for field in ('owner', 'x', 'y', 'hp', 'max_hp', 'kind', 'type', 'state'):
                counters['shared_actor_checks'] += 1
                if first[field] != second[field]: mismatches.append([tick, entity_id, field])
        resources_a, resources_b = ({(row[0], row[1]): row[2] for row in item['resources']} for item in (a, b))
        for tile in resources_a.keys() & resources_b.keys():
            counters['shared_resource_checks'] += 1
            if resources_a[tile] != resources_b[tile]: mismatches.append([tick, list(tile), 'resource_remaining'])
    if mismatches: failures.append('same-tick public world disagreement')
    if counters['same_tick_samples'] == 0: failures.append('no overlapping authoritative snapshots')
    for role, report in reports.items():
        if scenario in ('match', 'sustained'):
            coverage = report['coverage']
            stats = report['final_snapshot'].get('stats', {})
            gates = {'gathered': stats.get('resources_gathered', 0) > 0,
                     'trained': stats.get('units_trained', 0) >= 2,
                     'built': stats.get('buildings_built', 0) >= 2,
                     'damage': coverage['damage_observations'] > 0,
                     'enemy_visible': coverage['visible_enemies'] > 0,
                     'age_progression': coverage['max_age'] >= 2,
                     'research': len(coverage['research']) >= 2,
                     'unit_destruction': stats.get('units_lost', 0) > 0,
                     'building_destruction': stats.get('buildings_lost', 0) > 0,
                     'menu_return': report.get('menu_return_verified', False)}
            report['coverage_gates'] = gates
            failures.extend(f'{role}: coverage {key}' for key, value in gates.items() if not value)
            if scenario == 'sustained' and report.get('match_wall_seconds', 0) < minimum_wall:
                failures.append(f'{role}: less than requested real-time duration')
    result = {'passed': not failures, 'failures': failures, 'native': native, 'scenario': scenario,
              'scope': 'Real local WebSocket server and two separate Godot client processes. Scripted normal paid commands; native rendering only when native=true. No performance benchmark or physical phone claim.',
              'identity_and_result_agreement': agreement, 'same_tick_comparison': counters,
              'same_tick_mismatches': mismatches[:100],
              'private_state_scope': 'Each owner bank, age, HP, owner mapping, and disabled simulation checked against that client\'s authority payload on every received snapshot. Opponent banks are private and are not falsely expected to equal one another.',
              'clients': reports}
    save(out / 'report.json', result)
    for role in reports:
        raw = out / f'{role}-snapshots.jsonl'
        with raw.open('rb') as src, gzip.open(str(raw) + '.gz', 'wb') as dst: shutil.copyfileobj(src, dst)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--headless', action='store_true')
    parser.add_argument('--tune-speed', type=int, choices=(1, 2, 3), default=1, help='Headless policy tuning only; never sustained/native evidence')
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--prepared', action='store_true', help='Use an existing output/source.json frozen candidate')
    parser.add_argument('--queue', action='store_true', help='Baseline legacy matchmaking; map is random')
    parser.add_argument('--map', type=int, choices=range(3), default=0)
    parser.add_argument('--scenario', choices=('match', 'sustained', 'interrupt'), default='match')
    parser.add_argument('--minimum-wall', type=float, default=1800.0)
    parser.add_argument('--timeout', type=float, default=3600)
    args = parser.parse_args()
    if args.tune_speed != 1 and (not args.headless or args.scenario == 'sustained'):
        parser.error('--tune-speed requires headless non-sustained policy tuning')
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    if (out / 'source.json').exists() and not args.prepared: parser.error('Use a new output directory or --prepared')
    if (out / 'report.json').exists(): parser.error('Completed evidence exists; use another directory')
    receipt = json.loads((out / 'source.json').read_text()) if args.prepared else freeze(args.project.resolve(), out)
    if args.prepare_only:
        print(json.dumps({'prepared': receipt['stage'], 'output': str(out)}), flush=True)
        return
    processes = []
    logs = []
    env = os.environ.copy()
    env.update({'AOEM_SIM_TIME_SCALE': str(args.tune_speed), 'AOEM_AI_DIFFICULTY': '', 'AOEM_MAP_SEED': '', 'AOEM_MAP_ARCHETYPE': '', 'AOEM_POPULATION_LIMIT': ''})
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        port = probe.getsockname()[1]
    env.update({'AOEM_MATCH_PORT': str(port), 'AOEM_MATCH_URL': f'ws://127.0.0.1:{port}'})
    commands = {}
    try:
        server_log = (out / 'server.log').open('w')
        logs.append(server_log)
        server_command = [str(GODOT), '--headless', '--path', receipt['projects']['server'], 'res://scenes/network/server_lobby.tscn', '--', '--aoem-server']
        commands['server'] = server_command
        server = subprocess.Popen(server_command, env=env, stdout=server_log, stderr=subprocess.STDOUT)
        processes.append(server)
        deadline = time.monotonic() + 20
        while 'AOEM_MATCH_SERVER_READY' not in (out / 'server.log').read_text():
            if server.poll() is not None or time.monotonic() > deadline: raise RuntimeError('Authority failed to start')
            time.sleep(.1)
        clients = {}
        for role in ('host', 'guest'):
            arguments = ['--path', receipt['projects'][role], '--log-file', str(out / f'{role}-engine.log'), '--script', 'res://tools/probe_multiplayer_client.gd', '--', f'--output-dir={out}', f'--role={role}', f'--map={args.map}', f'--scenario={args.scenario}', f'--minimum-wall={args.minimum_wall}', f'--timeout={args.timeout-10}', f'--expected-scale={args.tune_speed}']
            if args.queue: arguments.append('--queue')
            if args.headless:
                command = [str(GODOT), '--headless', *arguments]
            else:
                command = ['open', '-n', '-W', '-a', str(APP)]
                for key, value in env.items():
                    if key.startswith('AOEM_'): command += ['--env', key + '=' + value]
                command += ['--args', *arguments]
            commands[role] = command
            log = (out / f'{role}-launcher.log').open('w')
            logs.append(log)
            clients[role] = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)
            processes.append(clients[role])
        save(out / 'invocation.json', {'native': not args.headless, 'endpoint': env['AOEM_MATCH_URL'], 'commands': commands, 'started_unix': time.time(), 'map': args.map, 'scenario': args.scenario, 'tuning_speed': args.tune_speed})
        deadline = time.monotonic() + args.timeout
        while any(p.poll() is None for p in clients.values()):
            if server.poll() is not None: raise RuntimeError('Authority exited during the match')
            if time.monotonic() > deadline: raise RuntimeError('Pair timeout')
            for role, process in clients.items():
                if process.poll() not in (None, 0): raise RuntimeError(f'{role} exited {process.returncode}')
            time.sleep(1)
        for role in clients:
            if not (out / f'{role}-report.json').exists(): raise RuntimeError(f'{role} did not produce a report')
        result = analyze(out, not args.headless, args.scenario, args.minimum_wall)
        engine_errors = {}
        for path in [out / 'server.log', out / 'host-engine.log', out / 'guest-engine.log']:
            messages = [line for line in path.read_text().splitlines() if any(s in line for s in ('SCRIPT ERROR', 'ERROR:', 'WARNING:'))]
            if messages: engine_errors[path.name] = messages
        result['engine_messages'] = engine_errors
        result['source_unchanged'] = hashes(Path(receipt['stage']) / 'common') == receipt['source_hashes']
        if engine_errors or not result['source_unchanged']: result['passed'] = False
        save(out / 'report.json', result)
        print(json.dumps({'passed': result['passed'], 'failures': result['failures'], 'engine_messages': engine_errors, 'evidence': str(out)}), flush=True)
        if not result['passed']: raise SystemExit(1)
    except BaseException as error:
        save(out / 'runner-status.json', {'completed': False, 'error': str(error), 'commands': commands})
        raise
    finally:
        cleanup = {'started_unix': time.time(), 'signals': []}
        for process in processes:
            if process.poll() is None:
                process.terminate()
                cleanup['signals'].append({'pid': process.pid, 'signal': 'SIGTERM', 'kind': 'owned_launcher_or_server', 'unix': time.time()})
        # LaunchServices owns native processes. Kill only this run's exact path.
        for match in owned_game_processes(receipt['projects'].values()):
            try:
                os.kill(match['pid'], signal.SIGTERM)
                cleanup['signals'].append({**match, 'signal': 'SIGTERM', 'kind': 'exact_private_project', 'unix': time.time()})
            except ProcessLookupError: pass
        save(out / 'cleanup.json', cleanup)
        for log in logs: log.close()

if __name__ == '__main__':
    main()
