"""Bounded loopback frozen-protocol2/current sockets; private source copies."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import time
import uuid
import websocket

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def network_constant(root, name):
    source = (root / 'scripts/network/network_session.gd').read_text(encoding='utf-8')
    match = re.search(r'^const\s+' + re.escape(name) + r'\s*(?::\s*int\s*)?(?::=|=)\s*(\d+)\b', source, re.MULTILINE)
    if match is None:
        raise ValueError('Missing integer network constant: ' + name)
    return int(match.group(1))


def load_runner(root):
    spec = importlib.util.spec_from_file_location('protocol_compat_runner', root / 'tools/run_focused_tests.py')
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    module.PROJECT_ROOT = root
    return module


def port():
    with socket.socket() as connection:
        connection.bind(('127.0.0.1', 0))
        return connection.getsockname()[1]


def private_copy(source, destination, cache=None):
    runner = load_runner(source)
    destination.mkdir()
    runner.freeze_project(destination)
    if cache is not None and not (destination / '.godot').exists():
        assert (cache / 'global_script_class_cache.cfg').is_file()
        (destination / '.godot').mkdir()
        for name in ('global_script_class_cache.cfg', 'uid_cache.bin'):
            if (cache / name).is_file():
                shutil.copy2(cache / name, destination / '.godot' / name)
        if (cache / 'imported').is_dir():
            shutil.copytree(cache / 'imported', destination / '.godot/imported')
    project = destination / 'project.godot'
    lines = [line for line in project.read_text(encoding='utf-8').splitlines() if not line.startswith(('config/use_custom_user_dir=', 'config/custom_user_dir_name='))]
    text = '\n'.join(lines).replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="protocol3-compat/' + uuid.uuid4().hex + '"') + '\n'
    project.write_text(text, encoding='utf-8', newline='\n')
    return runner.runtime_hashes(destination)


def main(args):
    current_protocol = network_constant(ROOT, 'PROTOCOL')
    current_catalog = network_constant(ROOT, 'MAP_CATALOG_VERSION')
    current_label = f'new{current_protocol}'
    output = args.output.resolve()
    output.mkdir(exist_ok=False)
    runner = load_runner(ROOT)
    original = runner.runtime_hashes(ROOT)
    old_original = runner.runtime_hashes(args.old_root)
    contexts = {}
    processes = []
    streams = []
    connections = []
    events = []
    report = {'status': 'RUNNING', 'scope': 'Actual owned loopback sockets and real current Godot client; no paid gameplay/browser/public connection.', 'current_protocol': current_protocol, 'current_map_catalog': current_catalog, 'source_sha256': original, 'old_source_sha256': old_original, 'events': events}
    def connect(url):
        assert re.fullmatch(r'ws://127\.0\.0\.1:\d+/match', url)
        connection = websocket.create_connection(url, timeout=4, http_proxy_host=None)
        connections.append(connection)
        return connection
    def send(connection, packet, label):
        connection.send(json.dumps(packet, allow_nan=False))
        events.append({'label': label, 'direction': 'sent', 'packet': packet, 'wall': time.time()})
    def receive(connection, label, operations):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            packet = json.loads(connection.recv())
            events.append({'label': label, 'direction': 'received', 'packet': packet, 'wall': time.time()})
            if packet.get('op') in operations:
                return packet
        raise AssertionError('No expected packet: ' + label)
    try:
        for label, source, protocol in [(current_label, ROOT, current_protocol), ('old2', args.old_root, 2)]:
            folder = output / label
            hashes = private_copy(source, folder, args.import_cache)
            contexts[label] = {'directory': str(folder), 'sha256': hashes}
            assigned = port()
            log_path = output / (label + '-server.log')
            stream = log_path.open('w', encoding='utf-8')
            streams.append(stream)
            env = dict(os.environ, AOEM_MATCH_PORT=str(assigned), GODOT_AUDIO_DRIVER='Dummy')
            process = subprocess.Popen([str(args.godot), '--headless', '--path', str(folder), 'res://scenes/network/server_lobby.tscn', '--', '--aoem-server'], stdout=stream, stderr=subprocess.STDOUT, env=env, start_new_session=os.name != 'nt')
            processes.append(process)
            contexts[label].update(pid=process.pid, endpoint=f'ws://127.0.0.1:{assigned}/match')
            deadline = time.monotonic() + 20
            expected = f'AOEM_MATCH_SERVER_READY port={assigned} protocol={protocol}'
            while expected not in log_path.read_text(encoding='utf-8'):
                assert process.poll() is None, 'Server exited: ' + label
                assert time.monotonic() < deadline, 'Server startup timed out: ' + label
                time.sleep(.1)
        url = contexts[current_label]['endpoint']
        host = connect(url)
        send(host, {'op': 'host', 'protocol': float(current_protocol), 'map_catalog': current_catalog, 'map_archetype': 0, 'civilization': 1}, 'current-host')
        room = receive(host, 'current-host', ['room', 'error'])
        assert room.get('protocol') == current_protocol and room.get('players') == 1
        for operation in ('search', 'host', 'join'):
            peer = connect(url)
            send(peer, {'op': operation, 'protocol': 2, 'map_catalog': 2, 'map_archetype': 0, 'civilization': 2, 'code': room['code']}, 'old2-' + operation)
            rejected = receive(peer, 'old2-' + operation, ['error', 'room', 'queued', 'matched'])
            assert rejected.get('op') == 'error' and 'reload' in rejected.get('reason', '').lower()
            # Same live peer must recover without disconnect-driven cleanup.
            send(peer, {'op': 'host', 'protocol': current_protocol, 'map_catalog': current_catalog, 'map_archetype': 0, 'civilization': 2}, 'old2-' + operation + '-recover-current')
            recovered = receive(peer, 'old2-' + operation + '-recover-current', ['room', 'queued', 'matched', 'error'])
            assert recovered.get('op') == 'room' and recovered.get('protocol') == current_protocol and recovered.get('players') == 1 and recovered.get('code') != room['code']
            send(host, {'op': 'room_map', 'map_archetype': 0}, 'protected-during-' + operation)
            protected = receive(host, 'protected-during-' + operation, ['room', 'error'])
            assert protected.get('players') == 1 and protected.get('code') == room['code']
            peer.close()
        for invalid in (None, current_protocol + 0.5, str(current_protocol), True, current_protocol + 1):
            peer = connect(url)
            packet = {'op': 'host', 'map_catalog': current_catalog, 'map_archetype': 0, 'civilization': 0}
            if invalid is not None:
                packet['protocol'] = invalid
            send(peer, packet, 'invalid-protocol')
            # Malformed numeric types are intentionally ignored by existing
            # parser; ping proves connection live without room/queue admission.
            send(peer, {'op': 'ping'}, 'invalid-protocol-ping')
            response = receive(peer, 'invalid-protocol', ['error', 'pong', 'room', 'queued'])
            assert response.get('op') in ('error', 'pong')
            peer.close()
        send(host, {'op': 'room_map', 'map_archetype': 0}, 'host-survives-rejections')
        protected = receive(host, 'host-survives-rejections', ['room'])
        assert protected.get('players') == 1 and protected.get('code') == room['code'] and protected.get('protocol') == current_protocol
        guest = connect(url)
        send(guest, {'op': 'join', 'protocol': current_protocol, 'map_catalog': current_catalog, 'code': room['code'], 'civilization': 2}, 'current-guest')
        for peer, label in [(host, 'current-host'), (guest, 'current-guest')]:
            joined = receive(peer, label, ['room', 'error'])
            assert joined.get('protocol') == current_protocol and joined.get('players') == 2
        send(host, {'op': 'room_start'}, 'current-start')
        starts = [receive(peer, label, ['matched', 'error']) for peer, label in [(host, 'current-host'), (guest, 'current-guest')]]
        assert {item.get('slot') for item in starts} == {0, 1}
        assert all(item.get('protocol') == current_protocol and item.get('civilizations') == [1, 2] for item in starts)
        assert starts[0]['match'] == starts[1]['match']
        for peer, label in [(host, 'current-host'), (guest, 'current-guest')]:
            send(peer, {'op': 'ready', 'match': starts[0]['match']}, label + '-ready')
        for peer, label in [(host, 'current-host'), (guest, 'current-guest')]:
            begun = receive(peer, label, ['started', 'error'])
            assert begun.get('op') == 'started' and begun.get('match') == starts[0]['match']
            snapshot = receive(peer, label, ['snapshot', 'error'])
            assert snapshot.get('op') == 'snapshot' and snapshot.get('match') == starts[0]['match'] and snapshot.get('actors')
        client_root = output / (current_label + '-client')
        contexts['client'] = {'directory': str(client_root), 'sha256': private_copy(ROOT, client_root, args.import_cache)}
        command = [str(args.godot), '--headless', '--path', str(client_root), '--script', 'res://tools/test_online_protocol3_client_compatibility.gd', '--', '--old-url=' + contexts['old2']['endpoint']]
        client_process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=dict(os.environ, GODOT_AUDIO_DRIVER='Dummy'), start_new_session=os.name != 'nt')
        processes.append(client_process)
        try:
            stdout, _ = client_process.communicate(timeout=18)
        except subprocess.TimeoutExpired:
            runner.terminate_process_tree(client_process)
            stdout, _ = client_process.communicate(timeout=8)
            (output / (current_label + '-client.log')).write_text(stdout, encoding='utf-8')
            raise
        (output / (current_label + '-client.log')).write_text(stdout, encoding='utf-8')
        assert client_process.returncode == 0 and 'PROTOCOL3_CLIENT_COMPATIBILITY' in stdout
        assert not re.search(r'(SCRIPT ERROR|ERROR:|Parse Error)', stdout)
        for label in (current_label, 'old2'):
            assert not re.search(r'(SCRIPT ERROR|ERROR:|Parse Error)', (output / (label + '-server.log')).read_text(encoding='utf-8'))
        report['status'] = 'PASS'
    except Exception as error:
        report['status'] = 'FAIL'
        report['failure'] = repr(error)
    finally:
        cleanup_errors = []
        for connection in connections:
            try:
                connection.close()
            except Exception as error:
                cleanup_errors.append({'socket': repr(error)})
        for process in processes:
            try:
                runner.terminate_process_tree(process)
                process.wait(timeout=8)
            except Exception as error:
                cleanup_errors.append({'pid': process.pid, 'error': repr(error)})
        for stream in streams:
            try:
                stream.close()
            except Exception as error:
                cleanup_errors.append({'stream': str(stream.name), 'error': repr(error)})
        report['cleanup_errors'] = cleanup_errors
        report['contexts'] = contexts
        try:
            report['original_source_unchanged'] = runner.runtime_hashes(ROOT) == original
            report['old_source_unchanged'] = runner.runtime_hashes(args.old_root) == old_original
            report['private_sources_unchanged'] = all(runner.runtime_hashes(Path(item['directory'])) == item['sha256'] for item in contexts.values())
        except Exception as error:
            cleanup_errors.append({'source_audit': repr(error)})
        report['owned_processes_exited'] = all(process.poll() is not None for process in processes)
        if cleanup_errors or not report['owned_processes_exited']:
            report['status'] = 'FAIL'
        (output / 'receipt.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: report.get(key) for key in ('status', 'failure', 'original_source_unchanged', 'old_source_unchanged', 'private_sources_unchanged', 'owned_processes_exited')}))
    return 0 if report['status'] == 'PASS' and all(report.get(key) for key in ('original_source_unchanged', 'old_source_unchanged', 'private_sources_unchanged', 'owned_processes_exited')) and not report['cleanup_errors'] else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--old-root', type=Path, required=True)
    parser.add_argument('--import-cache', type=Path, required=True, help='Existing Godot import derivatives from matching unchanged assets; copied only into private runtime folders')
    parser.add_argument('--output', type=Path, required=True)
    raise SystemExit(main(parser.parse_args()))
