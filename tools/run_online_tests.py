#!/usr/bin/env python3
"""Actual WebSocket server + two independent Godot clients, or a public WSS URL."""
import argparse
import os
from pathlib import Path
import socket
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--url', help='Public WSS endpoint; otherwise start a local authoritative server')
parser.add_argument('--combat', action='store_true', help='Also buy armies and verify replicated combat')
parser.add_argument('--strategy-only', action='store_true', help='Only exercise real Strategy controls on two clients')
parser.add_argument('--output', default=str(ROOT / 'output' / 'online-tests'))
args = parser.parse_args()
godot = os.environ.get('GODOT_BIN', '/Applications/Godot.app/Contents/MacOS/Godot')
output = Path(args.output)
output.mkdir(parents=True, exist_ok=True)
server = None
handles = []
processes = []

def launch(label, script=None, extra=(), env=None):
    handle = (output / f'{label}.log').open('w')
    handles.append(handle)
    command = [godot, '--headless', '--path', str(ROOT)]
    if script:
        command += ['--script', f'res://tools/{script}.gd']
    command += list(extra)
    process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=handle, stderr=subprocess.STDOUT)
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
    first = launch('strategy-one', 'test_online_strategy', env=env)
    second = launch('strategy-two', 'test_online_strategy', env=env)
    check('strategy-one', first, 50)
    check('strategy-two', second, 50)
    if not args.strategy_only:
        unavailable = launch('connection-failure', 'test_online_connection_failure', env=env)
        check('connection-failure', unavailable, 20)
        delayed_end = launch('loading-ended', 'test_online_loading_terminal', env=env)
        check('loading-ended', delayed_end, 20)
        delayed_failure = launch('loading-failure', 'test_online_loading_terminal', extra=('--', '--connection-failure'), env=env)
        check('loading-failure', delayed_failure, 20)
        lifecycle = launch('lifecycle', 'test_online_lifecycle', env=env)
        check('lifecycle', lifecycle, 50)
        first = launch('client-one', 'test_online_client', env=env)
        second = launch('client-two', 'test_online_client', env=env)
        check('client-one', first, 100)
        check('client-two', second, 100)
    if args.combat:
        first = launch('combat-one', 'test_online_combat', env=env)
        second = launch('combat-two', 'test_online_combat', env=env)
        check('combat-one', first, 160)
        check('combat-two', second, 160)
    if server and 'ERROR:' in (output / 'server.log').read_text():
        raise RuntimeError('Server runtime errors; inspect server.log')
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
