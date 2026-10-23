#!/usr/bin/env python3
"""Actual WebSocket server + two independent Godot clients, or a public WSS URL."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--project', type=Path, default=ROOT, help='Frozen runtime project; each subprocess gets private preferences')
parser.add_argument('--url', help='Public WSS endpoint; otherwise start a local authoritative server')
parser.add_argument('--combat', action='store_true', help='Also buy armies and verify replicated combat')
parser.add_argument('--stand-ground-combat', action='store_true', help='Also verify replicated Stand Ground before paid attack-move combat')
parser.add_argument('--combat-only', action='store_true', help='Run just the two paid combat clients')
parser.add_argument('--strategy-only', action='store_true', help='Only exercise real Strategy controls on two clients')
parser.add_argument('--rooms-only', action='store_true', help='Only exercise host/join lobby, map agreement, cancellation and recovery')
parser.add_argument('--maps-only', action='store_true', help='Only exercise legacy/mixed/current map catalog pairs')
parser.add_argument('--output', default=str(ROOT / 'output' / 'online-tests'))
args = parser.parse_args()
godot = os.environ.get('GODOT_BIN', '/Applications/Godot.app/Contents/MacOS/Godot')
output = Path(args.output)
output.mkdir(parents=True, exist_ok=True)
server = None
handles = []
processes = []
isolated_projects = []
source = args.project.resolve()


def source_hashes():
    paths = [source / 'project.godot']
    for folder, pattern in [('scripts', '*.gd'), ('scenes', '*.tscn'), ('tools', 'test_online_*.gd')]:
        paths.extend((source / folder).rglob(pattern))
    return {str(path.relative_to(source)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(paths)}


initial_hashes = source_hashes()
private_user_dirs = {}

def launch(label, script=None, extra=(), env=None):
    handle = (output / f'{label}.log').open('w')
    handles.append(handle)
    isolated = tempfile.TemporaryDirectory(prefix='aoem-online-case-')
    isolated_projects.append(isolated)
    project = Path(isolated.name)
    for entry in source.iterdir():
        if entry.name not in ('project.godot', 'override.cfg', '.git', 'output', 'builds'):
            (project / entry.name).symlink_to(entry, target_is_directory=entry.is_dir())
    config = (source / 'project.godot').read_text()
    config = '\n'.join(line for line in config.splitlines() if not line.startswith(('config/use_custom_user_dir=', 'config/custom_user_dir_name=')))
    user_dir = f'aoem-online-probes/{uuid.uuid4().hex}'
    private_user_dirs[label] = user_dir
    config = config.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + user_dir + '"', 1)
    (project / 'project.godot').write_text(config + '\n')
    command = [godot, '--headless', '--path', str(project)]
    if script:
        command += ['--script', f'res://tools/{script}.gd']
    command += list(extra)
    process = subprocess.Popen(command, cwd=project, env=env, stdout=handle, stderr=subprocess.STDOUT)
    processes.append(process)
    return process

def check(label, process, timeout):
    result = process.wait(timeout=timeout)
    text = (output / f'{label}.log').read_text()
    if result or 'SCRIPT ERROR' in text or 'ERROR:' in text:
        raise RuntimeError(f'{label} failed (exit {result}); see {output / (label + ".log")}')
    print(f'PASS {label}', flush=True)

try:
    env = os.environ.copy()
    if args.url:
        env['AOEM_MATCH_URL'] = args.url
    else:
        with socket.socket() as probe:
            probe.bind(('127.0.0.1', 0))
            port = probe.getsockname()[1]
        env['AOEM_MATCH_PORT'] = str(port)
        env['AOEM_MATCH_URL'] = f'ws://127.0.0.1:{port}'
        server = launch('server', extra=('res://scenes/network/server_lobby.tscn', '--', '--aoem-server'), env=env)
        for _ in range(100):
            if 'AOEM_MATCH_SERVER_READY' in (output / 'server.log').read_text():
                break
            if server.poll() is not None:
                raise RuntimeError('Server exited before listening')
            time.sleep(0.1)
        else:
            raise RuntimeError('Server did not listen')
    if args.combat_only:
        pass
    elif args.rooms_only:
        rooms = launch('rooms', 'test_online_rooms', env=env)
        check('rooms', rooms, 50)
    elif args.maps_only:
        maps = launch('map-catalog', 'test_online_maps', env=env)
        check('map-catalog', maps, 40)
    else:
        first = launch('strategy-one', 'test_online_strategy', env=env)
        second = launch('strategy-two', 'test_online_strategy', env=env)
        check('strategy-one', first, 50)
        check('strategy-two', second, 50)
    if not args.strategy_only and not args.maps_only and not args.rooms_only and not args.combat_only:
        unavailable = launch('connection-failure', 'test_online_connection_failure', env=env)
        check('connection-failure', unavailable, 20)
        delayed_end = launch('loading-ended', 'test_online_loading_terminal', env=env)
        check('loading-ended', delayed_end, 20)
        delayed_failure = launch('loading-failure', 'test_online_loading_terminal', extra=('--', '--connection-failure'), env=env)
        check('loading-failure', delayed_failure, 20)
        delayed_poll = launch('delayed-poll', 'test_online_delayed_poll', env=env)
        check('delayed-poll', delayed_poll, 20)
        delayed_result = launch('delayed-result', 'test_online_delayed_result', env=env)
        check('delayed-result', delayed_result, 25)
        lifetime = launch('reference-lifetime', 'test_network_reference_lifetime', env=env)
        check('reference-lifetime', lifetime, 20)
        lifecycle = launch('lifecycle', 'test_online_lifecycle', env=env)
        check('lifecycle', lifecycle, 50)
        first = launch('client-one', 'test_online_client', env=env)
        second = launch('client-two', 'test_online_client', env=env)
        check('client-one', first, 100)
        check('client-two', second, 100)
    if args.combat or args.stand_ground_combat or args.combat_only:
        combat_args = ('--', '--stand-ground') if args.stand_ground_combat else ()
        first = launch('combat-one', 'test_online_combat', extra=combat_args, env=env)
        second = launch('combat-two', 'test_online_combat', extra=combat_args, env=env)
        check('combat-one', first, 160)
        check('combat-two', second, 160)
    if server and 'ERROR:' in (output / 'server.log').read_text():
        raise RuntimeError('Server runtime errors; inspect server.log')
    final_hashes = source_hashes()
    if initial_hashes != final_hashes:
        raise RuntimeError('Runtime/test source changed during the online suite')
    (output / 'source-receipt.json').write_text(json.dumps({
        'scope': 'Local authoritative server and independent clients' if server else 'Client-side source only; remote server source is not verified by this runner',
        'source_project': str(source), 'source_hashes': initial_hashes,
        'source_unchanged': True, 'private_user_dirs': private_user_dirs,
        'unique_user_dirs': len(private_user_dirs) == len(set(private_user_dirs.values())),
        'checks': [label for label in private_user_dirs if label != 'server'],
    }, indent=2) + '\n')
    print(f'Online integration passed: {env["AOEM_MATCH_URL"]}\nEvidence: {output}')
finally:
    for process in processes:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
    for handle in handles:
        handle.close()
    for isolated in isolated_projects:
        isolated.cleanup()
