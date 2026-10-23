#!/usr/bin/env python3
"""Read retained public-browser evidence without changing any raw receipt."""
import argparse
import hashlib
import json
import sys
from pathlib import Path


def read(path, default=None):
    return json.loads(path.read_text()) if path.exists() else default


def lines(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()] if path.exists() else []


def analyze(folder):
    failures, mismatches, clients, records = [], [], {}, {}
    invocation = read(folder / 'invocation.json', {})
    scenario = invocation.get('scenario', 'full')
    states = read(folder / 'controller-state.json', {})
    for role in ('host', 'guest'):
        terminal = read(folder / f'{role}-terminal.json', {})
        snapshots = lines(folder / f'{role}-snapshots.jsonl')
        records[role] = {row['packet']['tick']: row['packet'] for row in snapshots}
        slot = terminal.get('matched', {}).get('slot')
        matched = terminal.get('matched') or states.get(role, {}).get('matched') or {}
        if slot is None:
            slot = matched.get('slot')
        coverage = {'max_age': 0, 'research': [], 'unit_hp_decreases': 0, 'visible_enemies': 0,
                    'buildings': {}, 'units': {}, 'worker_statuses': {}, 'cargo_observations': 0,
                    'farm_peak': 0, 'snapshot_samples': len(snapshots)}
        previous_units = {}
        for row in snapshots:
            packet = row['packet']
            coverage['max_age'] = max(coverage['max_age'], packet.get('player', {}).get('age', 0))
            coverage['research'] = sorted(set(coverage['research']) | set(packet.get('research', [])))
            own_farms = 0
            for actor in packet.get('actors', []):
                if actor['kind'] == 'unit':
                    previous_hp = previous_units.get(actor['id'])
                    coverage['unit_hp_decreases'] += previous_hp is not None and actor['hp'] < previous_hp
                    previous_units[actor['id']] = actor['hp']
                coverage['visible_enemies'] += actor['owner'] != slot
                if actor['owner'] != slot:
                    continue
                kinds = coverage['buildings' if actor['kind'] == 'building' else 'units']
                kinds[str(actor['type'])] = kinds.get(str(actor['type']), 0) + 1
                own_farms += actor['kind'] == 'building' and actor['type'] == 5 and actor['state'] == 2
                if actor['kind'] == 'unit' and actor['type'] == 0:
                    status = actor.get('work_status', '')
                    coverage['worker_statuses'][status] = coverage['worker_statuses'].get(status, 0) + 1
                    coverage['cargo_observations'] += sum(actor.get('cargo_manifest', {}).values()) > 0
            coverage['farm_peak'] = max(coverage['farm_peak'], own_farms)
        console = lines(folder / f'{role}-console.jsonl')
        errors = [row for row in console if row.get('type') in ('error', 'pageerror')]
        transport = lines(folder / f'{role}-transport.jsonl')
        errors += [row for row in transport if row.get('event') == 'error']
        sent = lines(folder / f'{role}-sent.jsonl')
        commands = [row['packet'] for row in sent if row['packet'].get('op') == 'command']
        sequences = [row.get('sequence', -1) for row in commands]
        monotonic = bool(sequences) and all(a < b for a, b in zip(sequences, sequences[1:]))
        forbidden = [row for row in sent if row['packet'].get('op') == 'command' and row['packet'].get('command') in ('surrender', 'cheat', 'grant', 'speed')]
        latest = terminal.get('last') or (snapshots[-1]['packet'] if snapshots else {})
        stats = latest.get('stats', {})
        request_failures = lines(folder / f'{role}-request-failures.jsonl')
        assets = lines(folder / f'{role}-assets.jsonl')
        finished_assets = lines(folder / f'{role}-asset-finished.jsonl')
        request_recovery = []
        for request in request_failures:
            success = [asset for asset in assets if asset['url'] == request['url'] and asset['status'] == 200]
            later_finish = any(asset['url'] == request['url'] and asset['unix'] > request['unix'] for asset in finished_assets)
            request_recovery.append({'request': request, 'same_url_successful_response': bool(success),
                                     'same_url_later_completed_request': later_finish,
                                     'actual_client_loaded_and_playing': bool(snapshots),
                                     'classified': 'startup_cancellation_with_successful_loaded_asset' if request.get('error', {}).get('errorText') == 'net::ERR_ABORTED' and success and snapshots and request['unix'] < snapshots[0]['unix'] else 'unrecovered_or_unclassified',
                                     'timing_limit': None if later_finish else 'No later requestfinished receipt was recorded; precise response/header arrival order relative to cancellation is not independently asserted.'})
        ui = states.get(role, {}).get('uiChecks', [])
        inputs = lines(folder / f'{role}-browser-input.jsonl')
        gates = {'terminal_received': bool(terminal.get('ended')), 'command_sequence_monotonic': monotonic,
                 'own_match_identity': matched.get('match') is not None and terminal.get('ended', {}).get('match') == matched.get('match') and all(row['packet'].get('match') == matched.get('match') for row in snapshots),
                 'no_forced_result_or_resource_command': not forbidden,
                 'gathered': stats.get('resources_gathered', 0) > 0,
                 'trained': stats.get('units_trained', 0) >= 2,
                 'built': stats.get('buildings_built', 0) >= 2,
                 'damage': coverage['unit_hp_decreases'] > 0, 'enemy_visible': coverage['visible_enemies'] > 0,
                 'age_progression': coverage['max_age'] >= 2, 'research': len(coverage['research']) >= 2,
                 'unit_destruction': stats.get('units_lost', 0) > 0,
                 'building_destruction_including_paid_demolition': stats.get('buildings_lost', 0) > 0,
                 'actual_keyboard_q': any(row.get('kind') == 'press' and row.get('key', '').lower() == 'q' for row in inputs),
                 'actual_keyboard_b': any(row.get('kind') == 'press' and row.get('key', '').lower() == 'b' for row in inputs),
                 'keyboard_ui_operator_verified': all(any(row.get('check') == key and row.get('passed') is True for row in ui) for key in ('q_trained', 'b_menu_open')),
                 'menu_return_operator_verified': any(row.get('check') == 'menu_return' and row.get('passed') is True for row in ui),
                 'no_console_or_socket_errors': not errors,
                 'no_http_errors': not lines(folder / f'{role}-http-errors.jsonl'),
                 'no_unrecovered_required_requests': all(row['classified'] != 'unrecovered_or_unclassified' for row in request_recovery)}
        if scenario == 'objective':
            for key in ('built', 'damage', 'enemy_visible', 'age_progression', 'research', 'unit_destruction', 'building_destruction_including_paid_demolition'):
                gates.pop(key)
            gates['paid_scout_observed'] = '4' in coverage['units']
        failures.extend(f'{role}: {key}' for key, value in gates.items() if not value)
        clients[role] = {'matched': matched, 'ended': terminal.get('ended'),
                         'last_game_seconds': latest.get('time'),
                         'coverage': coverage, 'stats': stats, 'gates': gates, 'errors': errors,
                         'warnings': [row for row in console if row.get('type') == 'warning'],
                         'http_errors': lines(folder / f'{role}-http-errors.jsonl'),
                         'request_failures': request_failures, 'request_recovery': request_recovery,
                         'rejections': [row for row in transport if row.get('packet', {}).get('op') == 'rejected'],
                         'ui_checks': ui, 'commands_sent': len(commands)}
    host, guest = clients['host'], clients['guest']
    agreement = {}
    for key in ('match', 'seed', 'map_archetype'):
        a, b = (client.get('matched') or {} for client in (host, guest))
        agreement[key] = a.get(key) is not None and b.get(key) is not None and a[key] == b[key]
    agreement['opposite_slots'] = {(c.get('matched') or {}).get('slot') for c in clients.values()} == {0, 1}
    for key in ('match', 'winner', 'reason'):
        a, b = (client.get('ended') or {} for client in (host, guest))
        agreement['terminal_' + key] = a.get(key) is not None and b.get(key) is not None and a[key] == b[key]
    agreement['natural_sacred_result'] = all('Sacred' in (c.get('ended') or {}).get('reason', '') for c in clients.values())
    counters = {'same_tick_samples': 0, 'shared_actor_fields': 0, 'shared_resource_tiles': 0}
    for tick in sorted(records['host'].keys() & records['guest'].keys()):
        a, b = records['host'][tick], records['guest'][tick]
        counters['same_tick_samples'] += 1
        if a['time'] != b['time'] or a['site'] != b['site']:
            mismatches.append([tick, 'time_or_site'])
        actors_a, actors_b = ({row['id']: row for row in packet['actors']} for packet in (a, b))
        for identity in actors_a.keys() & actors_b.keys():
            for field in ('owner', 'x', 'y', 'hp', 'max_hp', 'kind', 'type', 'state'):
                counters['shared_actor_fields'] += 1
                if actors_a[identity][field] != actors_b[identity][field]:
                    mismatches.append([tick, identity, field])
        resources_a, resources_b = ({tuple(row[:2]): row[2] for row in packet['resources']} for packet in (a, b))
        for cell in resources_a.keys() & resources_b.keys():
            counters['shared_resource_tiles'] += 1
            if resources_a[cell] != resources_b[cell]:
                mismatches.append([tick, cell, 'resource_remaining'])
    failures.extend('agreement: ' + key for key, value in agreement.items() if not value)
    if not counters['same_tick_samples']:
        failures.append('no same-tick samples')
    if mismatches:
        failures.append('public world disagreement')
    controller_errors = lines(folder / 'controller-errors.jsonl')
    if controller_errors:
        failures.append('controller errors recorded')
    report = {'passed': not failures, 'failures': failures, 'scenario': scenario, 'identity_and_result_agreement': agreement,
              'same_tick_comparison': counters, 'same_tick_mismatches': mismatches[:100], 'clients': clients,
              'controller_errors': controller_errors,
              'scope': 'Two actual deployed browser contexts. UI lobby and recorded keyboard actions; test-only ordinary paid WebSocket gameplay policy. Evidence is passive transport, rendered screenshots and operator UI checks. No direct browser-replica inspection, physical phone test or performance claim.',
              'private_state_scope': 'Each owner bank/player/research is retained from that client authority packet; opposite private banks are not expected to match. Farm claims, exact worker resource/dropoff target IDs and physical spacing are not exposed by this protocol.'}
    report['raw_evidence_sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(folder.iterdir()) if p.is_file() and p.name != 'analysis.json'}
    (folder / 'analysis.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = analyze(args.output)
    print(json.dumps({key: result[key] for key in ('passed', 'failures', 'identity_and_result_agreement', 'same_tick_comparison')}, indent=2))
    sys.exit(0 if result['passed'] else 1)
