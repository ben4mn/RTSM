#!/usr/bin/env python3
"""Read retained public-browser evidence without changing any raw receipt."""
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit
from beta2_browser_evidence import PROFILE as BETA2_PROFILE, beta2_gates
from march_browser_evidence import march_gates


def read(path, default=None):
    return json.loads(path.read_text()) if path.exists() else default


def lines(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()] if path.exists() else []


def valid_digest(value):
    return isinstance(value, str) and re.fullmatch(r'[a-f0-9]{64}', value) is not None


def known_body_mismatch(bodies, expected):
    return any(row.get('file') in expected and (
        not valid_digest(expected[row['file']]) or row.get('expected') != expected[row['file']]
        or row.get('sha256') != expected[row['file']] or row.get('bytes', 0) <= 0
        or row.get('match') is False) for row in bodies)


CIVILIZATIONS = {0: 'Crownlands', 1: 'Verdant League', 2: 'Sunstride Clans'}


def image_matches(folder, image):
    name = image.get('name') if isinstance(image, dict) else None
    return (isinstance(name, str) and Path(name).name == name and (folder / name).is_file()
            and hashlib.sha256((folder / name).read_bytes()).hexdigest() == image.get('sha256'))


def counter_lesson(packet, slot):
    """Expected visible text derives only from this recipient's authority facts."""
    ids, rows = packet.get('civilizations'), packet.get('battle', {}).get('losses_by_matchup')
    if not isinstance(ids, list) or len(ids) != 2 or any(type(i) is not int or i not in CIVILIZATIONS for i in ids):
        return None
    if slot not in (0, 1) or not isinstance(rows, list) or len(rows) > 9:
        return None
    seen, eligible = set(), []
    for row in rows:
        if (not isinstance(row, list) or len(row) != 3 or any(type(i) is not int for i in row)
                or row[0] not in (1, 2, 3) or row[1] not in (1, 2, 3) or not 0 < row[2] <= 9999 or tuple(row[:2]) in seen):
            return None
        seen.add(tuple(row[:2]))
        if row[2] >= 3 and {1: 2, 2: 3, 3: 1}[row[0]] == row[1]:
            eligible.append(row)
    if not eligible:
        return {'status': 'none', 'text': '', 'eligible': []}
    victim, attacker, count = max(eligible, key=lambda row: row[2])
    def plural(unit, civ):
        return 'Warriors' if unit == 1 else ('Longbows' if civ == 1 else 'Archers') if unit == 2 else ('Outriders' if civ == 2 else 'Horsemen')
    text = (f'Enemy {plural(attacker, ids[1-slot])} landed final blows on {count} of your {plural(victim, ids[slot])}. '
            f'Add {plural({1: 2, 2: 3, 3: 1}[attacker], ids[slot])} to counter them; regroup before your next fight.')
    return {'status': 'counter_lesson', 'text': text, 'eligible': eligible}


def civilization_gates(folder, invocation, role):
    expected = invocation.get('civilization_expectations', {})
    declared = expected.get(role, {})
    expected_ids = [expected.get(key, {}).get('id') for key in ('host', 'guest')]
    valid_declared = all(type(i) is int and i in CIVILIZATIONS for i in expected_ids) and declared.get('name') == CIVILIZATIONS.get(declared.get('id'))
    terminal = read(folder / f'{role}-terminal.json', {})
    matched, last = terminal.get('matched', {}), terminal.get('last', {})
    slot = matched.get('slot')
    wire = [row.get('packet', {}) for row in lines(folder / f'{role}-sent.jsonl')]
    requests = [p for p in wire if p.get('op') in ('host', 'join', 'search', 'room_civilization')]
    handshakes = [p for p in requests if p.get('op') in ('host', 'join', 'search')]
    rooms = [row.get('packet', {}) for row in lines(folder / f'{role}-transport.jsonl') if row.get('packet', {}).get('op') == 'room' and row['packet'].get('players') == 2]
    snapshots = [row.get('packet', {}) for row in lines(folder / f'{role}-snapshots.jsonl')] + [last]
    selections = lines(folder / f'{role}-civilization-ui.jsonl')
    reviews = lines(folder / f'{role}-civilization-identity.jsonl')
    kind = 'tap' if invocation.get('input_mode') == 'touch' else 'click'
    inputs = lines(folder / f'{role}-browser-input.jsonl')
    picker = any(row.get('performed') is True and row.get('selected') == declared and len(row.get('captures', [])) == 3
                 and all(image_matches(folder, image) for image in row['captures']) for row in selections)
    reviewed = any(row.get('passed') is True and row.get('reviewed') is True and row.get('observed_name') == declared.get('name')
                   and row.get('selected') == declared and row.get('matched') == matched for row in reviews)
    clicks = all(any(row.get('kind') == kind and row.get('purpose') == purpose for row in inputs)
                 for purpose in ('civilization_picker_open', 'civilization_picker_choice', 'civilization_picker_confirm'))
    return {
        'reviewed_picker_matches_received_civilization': valid_declared and picker and reviewed and clicks,
        'protocol2_actual_civilization_request': valid_declared and invocation.get('protocol') == 2 and bool(handshakes) and all(p.get('protocol') == 2 for p in handshakes) and requests[-1].get('civilization') == declared.get('id'),
        'civilization_identity_stable_through_terminal': valid_declared and slot in (0, 1) and matched.get('civilizations') == expected_ids and expected_ids[slot] == declared.get('id') and bool(rooms) and rooms[-1].get('civilizations') == expected_ids and bool(snapshots) and all(p.get('civilizations') == expected_ids and p.get('player', {}).get('civilization') == declared.get('id') for p in snapshots),
    }


def screen_gates(folder, role):
    terminal = read(folder / f'{role}-terminal.json', {})
    matched, ended, last = terminal.get('matched', {}), terminal.get('ended', {}), terminal.get('last', {})
    lesson = counter_lesson(last, matched.get('slot'))
    counts = {label: last.get('stats', {}).get(key) for label, key in {'Army Produced': 'army_trained', 'Units Lost': 'units_lost', 'Buildings Lost': 'buildings_lost', 'Resources Gathered': 'resources_gathered'}.items()}
    outcome = 'MATCH ENDED' if ended.get('winner', -1) < 0 else 'VICTORY' if ended.get('winner') == matched.get('slot') else 'DEFEAT'
    reviews = lines(folder / f'{role}-screen-reviews.jsonl')
    captures = lines(folder / f'{role}-captures.jsonl')
    def captured(review):
        image = review.get('image', {})
        return image_matches(folder, image) and image in captures and type(terminal.get('received_unix')) is int and image.get('unix', -1) >= terminal['received_unix']
    result = any(row.get('check') == 'result_review' and row.get('passed') is True and captured(row)
                 and row.get('observed', {}).get('result') == outcome and row['observed'].get('reason') == ended.get('reason')
                 and row['observed'].get('counts') == counts and all(type(n) is int and n >= 0 for n in counts.values())
                 and lesson is not None and row['observed'].get('lesson_status') == lesson['status']
                 and ' '.join(row['observed'].get('lesson_text', '').split()) == lesson['text'] for row in reviews)
    menu = any(row.get('check') == 'menu_return' and row.get('passed') is True and captured(row)
               and {'New Game', 'Join a friend'} <= set(row.get('observed', {}).get('actions', [])) for row in reviews)
    return {'reviewed_result_counts_and_eligible_lesson': result, 'reviewed_visible_menu_return': menu}


def touch_gates(folder, invocation, role):
    """Touch acceptance is native browser input plus passive paid authority facts."""
    if invocation.get('input_mode') != 'touch':
        return {}
    inputs = lines(folder / f'{role}-browser-input.jsonl')
    wire = lines(folder / f'{role}-sent.jsonl')
    origins = lines(folder / f'{role}-command_origin.jsonl')
    captures = lines(folder / f'{role}-captures.jsonl')
    attempts = lines(folder / f'{role}-recruit-ui.jsonl')
    reviews = lines(folder / f'{role}-recruit-reviews.jsonl')
    snapshots = lines(folder / f'{role}-recruit-snapshots.jsonl')
    starts = lines(folder / 'policy-starts.jsonl')
    first_policy = min((row.get('unix', 0) for row in starts), default=0)
    valid_purchase = False
    for attempt in attempts:
        before, after = attempt.get('before', {}), attempt.get('after', {})
        evidence = attempt.get('evidence') or {}
        command = evidence.get('packet', {})
        slot = attempt.get('slot')
        images = attempt.get('captures', [])
        bank_before, bank_after = before.get('bank', {}), after.get('bank', {})
        def town(packet):
            return next((actor for actor in packet.get('actors', []) if actor.get('id') == command.get('target') and actor.get('kind') == 'building' and actor.get('type') == 0 and actor.get('owner') == slot and actor.get('state') == 2), {})
        previous, current = town(before), town(after)
        deposits_before, deposits_after = before.get('stats', {}).get('resources_gathered'), after.get('stats', {}).get('resources_gathered')
        bank_valid = all(type(bank.get(key)) is int and bank[key] >= 0 for bank in (bank_before, bank_after) for key in ('food', 'wood', 'gold'))
        deposits_valid = type(deposits_before) is int and type(deposits_after) is int and 0 <= deposits_before <= deposits_after
        implied_deposits = {key: bank_after[key] - bank_before[key] + (50 if key == 'food' else 0) for key in ('food', 'wood', 'gold')} if bank_valid else {}
        cost_valid = bank_valid and deposits_valid and bank_before['food'] >= 50 and all(value >= 0 for value in implied_deposits.values()) and sum(implied_deposits.values()) == deposits_after - deposits_before
        reserved_before, reserved_after = before.get('player', {}).get('population_reserved'), after.get('player', {}).get('population_reserved')
        reservation_valid = type(reserved_before) is int and type(reserved_after) is int and reserved_after == reserved_before + 1
        queue_valid = previous.get('queue', {}).get('items') == [] and current.get('queue', {}).get('items') == [0] and previous.get('queue', {}).get('repeat') is False and current.get('queue', {}).get('repeat') is False
        timing_valid = (type(before.get('tick')) is int and type(after.get('tick')) is int and after['tick'] > before['tick']
                        and type(before.get('time')) in (int, float) and type(after.get('time')) in (int, float) and 0 <= after['time'] - before['time'] <= 5)
        matching_transport = (evidence.get('source') == 'game_ui_or_engine' and command.get('op') == 'command' and command.get('command') == 'train' and command.get('type') == 0
                              and command.get('match') is not None and before.get('match') == command['match'] == after.get('match')
                              and any(row.get('packet') == command for row in wire)
                              and any(row.get('serial') == evidence.get('serial') and row.get('packet') == command and row.get('source') == 'game_ui_or_engine' for row in origins))
        actual_tap = (attempt.get('input') in inputs and attempt.get('input', {}).get('kind') == 'tap' and attempt.get('input', {}).get('purpose') == 'paid_recruit_villager')
        exact_snapshots = all(any(row.get('attempt') == attempt.get('attempt') and row.get('stage') == stage and row.get('packet') == packet for row in snapshots) for stage, packet in (('before', before), ('after', after)))
        reviewed = any(row.get('attempt') == attempt.get('attempt') and row.get('passed') is True and row.get('reviewed') is True and row.get('input_mode') == 'touch'
                       and 0 < row.get('unix', 0) < first_policy and row.get('captures') == images
                       and row.get('observed', {}).get('unit') == 'Villager' and row['observed'].get('cost_food') == 50 and row['observed'].get('queue_count') == 1
                       and row['observed'].get('before_bank') == bank_before and row['observed'].get('after_bank') == bank_after for row in reviews)
        images_valid = len(images) == 2 and all(image in captures and image_matches(folder, image) for image in images)
        valid_purchase |= (slot in (0, 1) and attempt.get('passed') is True and attempt.get('input_mode') == 'touch' and attempt.get('policy_ever') is False
                           and cost_valid and reservation_valid and queue_valid and timing_valid and matching_transport and actual_tap and exact_snapshots and reviewed and images_valid)
    lobby = [('lobby_create', 'host'), ('lobby_start', 'room_start')] if role == 'host' else [('lobby_join', 'join')]
    lobby_taps = all(any(row.get('kind') == 'tap' and row.get('purpose') == purpose and any(sent.get('packet', {}).get('op') == op and abs(sent.get('unix', 0)-row.get('unix', -10000)) <= 5000 for sent in wire) for row in inputs) for purpose, op in lobby)
    terminal = read(folder / f'{role}-terminal.json', {})
    terminal_at = terminal.get('received_unix')
    menus = [row for row in lines(folder / f'{role}-screen-reviews.jsonl') if row.get('check') == 'menu_return' and row.get('passed') is True]
    menu_tap = type(terminal_at) is int and any(row.get('kind') == 'tap' and row.get('purpose') == 'result_main_menu' and terminal_at <= row.get('unix', 0) and any(row['unix'] <= menu.get('image', {}).get('unix', -1) for menu in menus) for row in inputs)
    capabilities = read(folder / f'{role}-browser-capabilities.json', {})
    return {'native_touch_844x390_context': capabilities.get('width') == 844 and capabilities.get('height') == 390 and capabilities.get('max_touch_points', 0) > 0 and capabilities.get('coarse_pointer') is True,
            'no_mouse_pointer_fallback': not any(row.get('kind') in ('click', 'scroll') for row in inputs),
            'actual_tap_paid_recruitment_reviewed_before_policy': valid_purchase,
            'actual_tap_lobby_protocol_actions': lobby_taps,
            'actual_tap_terminal_menu_return': menu_tap}


def local_gates(folder, invocation, role):
    """Local claims require actual routing, artifact bytes and rendered input receipts."""
    initial = read(folder / 'local-source-initial.json', {})
    final = read(folder / 'local-source-final.json', {})
    ready = read(folder / 'local-authority-ready.json', {})
    endpoint = invocation.get('match_url')
    try:
        parsed_endpoint = urlsplit(endpoint or '')
        loopback_endpoint = parsed_endpoint.scheme == 'ws' and parsed_endpoint.hostname == '127.0.0.1' and parsed_endpoint.port is not None and parsed_endpoint.path == '/match' and not (parsed_endpoint.username or parsed_endpoint.password or parsed_endpoint.query or parsed_endpoint.fragment)
    except (TypeError, ValueError):
        loopback_endpoint = False
    routes = lines(folder / f'{role}-socket_route.jsonl')
    guards = lines(folder / f'{role}-endpoint-guard.jsonl')
    bodies = lines(folder / f'{role}-asset-bytes.jsonl')
    expected = initial.get('artifact', {}).get('files', {})
    verified_files = {row.get('file') for row in bodies if isinstance(expected.get(row.get('file')), str) and len(expected[row['file']]) == 64 and row.get('expected') == expected[row['file']] and row.get('sha256') == expected[row['file']] and row.get('bytes', 0) > 0}
    for response in lines(folder / f'{role}-asset-server-proof.jsonl'):
        name = response.get('file')
        if name not in expected or not valid_digest(expected[name]) or response.get('sha256') != expected[name] or response.get('status') != 200 or response.get('bytes', 0) <= 0:
            continue
        if any(row.get('request_id') == response.get('request_id') and row.get('method') == 'GET' and row.get('file') == name and row.get('sha256') == response['sha256'] and row.get('bytes') == response['bytes'] for row in final.get('served', [])):
            verified_files.add(name)
    attacks = lines(folder / f'{role}-attack-ui.jsonl')
    origins = lines(folder / f'{role}-command_origin.jsonl')
    wire = lines(folder / f'{role}-sent.jsonl')
    inputs = lines(folder / f'{role}-browser-input.jsonl')
    valid_attack = False
    for check in attacks:
        evidence = check.get('evidence') or {}
        command = evidence.get('packet', {})
        if not (check.get('passed') is True and evidence.get('source') == 'game_ui_or_engine' and command.get('command') == 'attack_move' and command.get('ids')):
            continue
        matching_origin = any(row.get('serial') == evidence.get('serial') and row.get('packet') == command and row.get('source') == 'game_ui_or_engine' for row in origins)
        matching_wire = any(row.get('packet') == command for row in wire)
        screenshots = check.get('screenshots', [])
        safe_screenshots = len(screenshots) == 3 and all(isinstance(name, str) and Path(name).name == name and (folder / name).is_file() for name in screenshots)
        actual_clicks = all(any(row.get('kind') == ('tap' if invocation.get('input_mode') == 'touch' else 'click') and row.get('purpose') == purpose for row in inputs) for purpose in ('observed_attack_hud_button', 'attack_move_ground_destination'))
        valid_attack |= matching_origin and matching_wire and safe_screenshots and actual_clicks
    return {
        'sealed_local_source_unchanged': final.get('completed') is True and final.get('production_artifacts_unchanged') is True and final.get('private_runtime_unchanged') is True,
        'owned_authority_endpoint': loopback_endpoint and ready.get('protocol') == 2 and ready.get('match_url') == endpoint and ready.get('source_revision') == initial.get('authority', {}).get('source_revision') and ready.get('pid') == initial.get('server_pid'),
        'no_owned_artifact_server_failure': final.get('artifact_failures') == [],
        'exact_endpoint_redirection': bool(routes) and all(row.get('blocked') is False and row.get('resolved') == endpoint and row.get('requested') in ('wss://game.4mn.org/match', endpoint) for row in routes),
        'no_unapproved_socket_reached_browser_transport': bool(guards) and all(row.get('allowed') is True and row.get('url') == endpoint for row in guards),
        'loaded_engine_bytes_match_sealed_export': not known_body_mismatch(bodies, expected) and {'index.js', 'index.wasm', 'index.pck'} <= verified_files,
        'actual_attack_hud_generated_attack_move': valid_attack,
    }


def public_gates(folder, invocation, role):
    """Public proof distinguishes captured bytes from correlated deployment validators."""
    proof = read(folder / 'public-source.json', {})
    expected = proof.get('artifact', {}).get('files', {})
    postflight = proof.get('postflight', {})
    request = postflight.get('request', {})
    revision = invocation.get('source_revision')
    revision_valid = isinstance(revision, str) and re.fullmatch(r'[a-f0-9]{12,40}', revision) is not None and isinstance(request.get('source_revision'), str) and re.fullmatch(r'[a-f0-9]{40}', request['source_revision']) is not None and request['source_revision'].startswith(revision)
    bodies = lines(folder / f'{role}-asset-bytes.jsonl')
    mismatched_body = known_body_mismatch(bodies, expected)
    loaded = {row.get('file') for row in bodies if valid_digest(expected.get(row.get('file'))) and row.get('expected') == expected[row['file']] and row.get('sha256') == expected[row['file']] and row.get('bytes', 0) > 0}
    correlated = set()
    assets = lines(folder / f'{role}-assets.jsonl')
    for response in postflight.get('requests', []):
        url = response.get('url', '')
        name = url.removeprefix('https://game.4mn.org/')
        file = response.get('headers_file')
        if (name not in ('index.pck', 'index.wasm') or not isinstance(expected.get(name), str) or re.fullmatch(r'[a-f0-9]{64}', expected[name]) is None or not isinstance(file, str) or Path(file).name != file or response.get('status') != 200 or response.get('ssl_verify_result') != 0 or response.get('sha256') != expected.get(name) or response.get('bytes_decoded', 0) <= 0):
            continue
        header_path = folder / 'public-postflight-headers' / file
        if not header_path.exists():
            continue
        headers = dict(line.split(':', 1) for line in header_path.read_text().splitlines() if ':' in line)
        headers = {key.lower().strip(): value.strip() for key, value in headers.items()}
        validators = ('etag', 'last-modified', 'content-type', 'content-encoding')
        if all(headers.get(key) for key in validators) and any(row.get('url') == url and row.get('status') == 200 and all(row.get('headers', {}).get(key) == headers[key] for key in validators) for row in assets):
            correlated.add(name)
    opens = [row for row in lines(folder / f'{role}-transport.jsonl') if row.get('event') == 'open']
    return {
        'public_exact_endpoint_no_redirect': invocation.get('url') == 'https://game.4mn.org/' and invocation.get('match_url') == 'wss://game.4mn.org/match' and bool(opens) and all(row.get('url') == 'wss://game.4mn.org/match' for row in opens) and not lines(folder / f'{role}-socket_route.jsonl'),
        'public_postflight_matches_sealed_artifacts': invocation.get('protocol') == 2 and revision_valid and {'index.js', 'version.json', 'index.wasm', 'index.pck'} <= expected.keys() and all(valid_digest(value) for value in expected.values()) and request.get('protocol') == 2 and valid_digest(proof.get('artifact', {}).get('manifest_sha256')) and valid_digest(request.get('web_manifest_sha256')) and proof['artifact']['manifest_sha256'] == request['web_manifest_sha256'] and postflight.get('status') == 'PASS_READ_ONLY_POSTFLIGHT' and bool(expected) and all(postflight.get('public_files', {}).get(name, {}).get('sha256') == sha for name, sha in expected.items()),
        'public_loaded_version_and_javascript_bytes_verified': not mismatched_body and {'index.js', 'version.json'} <= loaded,
        'public_engine_response_provenance': not mismatched_body and {'index.js', 'index.wasm', 'index.pck'} <= (loaded | correlated),
    }


def analyze(folder, require_beta2=False, require_cohesion=False):
    require_beta2 = require_beta2 or require_cohesion
    failures, mismatches, clients, records = [], [], {}, {}
    invocation = read(folder / 'invocation.json', {})
    scenario = invocation.get('scenario', 'full')
    profile = invocation.get('acceptance_profile', 'legacy')
    if profile not in ('legacy', BETA2_PROFILE):
        failures.append('unrecognized acceptance profile')
    if require_beta2 and profile != BETA2_PROFILE:
        failures.append('required beta2 mobile acceptance profile missing')
    if require_cohesion and invocation.get('cohesion_acceptance') is not True:
        failures.append('required paired cohesion acceptance missing')
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
                    'farm_peak': 0, 'snapshot_samples': len(snapshots), 'signature_unit_ids': [], 'signature_max_hp': [], 'signature_paid_queue_observed': False}
        own_civilization = matched.get('civilizations', [0, 0])[slot] if slot in (0, 1) and isinstance(matched.get('civilizations'), list) and len(matched['civilizations']) == 2 else 0
        signature_type = 3 if own_civilization == 2 else 2
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
                if actor['kind'] == 'unit' and actor['type'] == signature_type and actor['id'] not in coverage['signature_unit_ids']:
                    coverage['signature_unit_ids'].append(actor['id'])
                    coverage['signature_max_hp'].append(actor['max_hp'])
                if actor['kind'] == 'building' and signature_type in actor.get('queue', {}).get('items', []):
                    coverage['signature_paid_queue_observed'] = True
                own_farms += actor['kind'] == 'building' and actor['type'] == 5 and actor['state'] == 2
                if actor['kind'] == 'unit' and actor['type'] == 0:
                    status = actor.get('work_status', '')
                    coverage['worker_statuses'][status] = coverage['worker_statuses'].get(status, 0) + 1
                    coverage['cargo_observations'] += sum(actor.get('cargo_manifest', {}).values()) > 0
            coverage['farm_peak'] = max(coverage['farm_peak'], own_farms)
        console = lines(folder / f'{role}-console.jsonl')
        errors = [row for row in console if row.get('type') in ('error', 'pageerror')]
        errors += [{'type': 'controller-client', 'detail': row} for row in states.get(role, {}).get('errors', [])]
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
        if invocation.get('input_mode') == 'touch':
            for key in ('actual_keyboard_q', 'actual_keyboard_b', 'keyboard_ui_operator_verified'):
                gates.pop(key)
            gates.update(touch_gates(folder, invocation, role))
        if invocation.get('mode') == 'local-sealed':
            gates.update(local_gates(folder, invocation, role))
        if invocation.get('protocol') == 2 or invocation.get('mode') == 'public':
            gates['actual_attack_hud_generated_attack_move'] = local_gates(folder, invocation, role)['actual_attack_hud_generated_attack_move']
            gates.update(civilization_gates(folder, invocation, role))
            gates.update(screen_gates(folder, role))
            if scenario != 'objective':
                cost = {2: {'food': 25, 'wood': 45}, 3: {'food': 90, 'wood': 30}}[signature_type]
                policy = lines(folder / f'{role}-policy.jsonl')
                gates['signature_paid_queue_and_completed_unit'] = coverage['signature_paid_queue_observed'] and bool(coverage['signature_unit_ids'])
                gates['signature_authority_base_health'] = bool(coverage['signature_max_hp']) and all(hp == {0: 35, 1: 30, 2: 70}.get(own_civilization) for hp in coverage['signature_max_hp'])
                gates['signature_ordinary_cost_and_affordable_request'] = any(row.get('sent') is True and row.get('command') == 'train' and row.get('payload', {}).get('type') == signature_type and row.get('expected_cost') == cost and all(row.get('bank_before', {}).get(key, -1) >= amount for key, amount in cost.items()) and any(wire.get('packet', {}).get('command') == 'train' and wire['packet'].get('type') == signature_type and wire['packet'].get('target') == row['payload'].get('target') and wire['packet'].get('match') == matched.get('match') and abs(wire.get('unix', 0) - row.get('unix', 0)) < 5000 for wire in sent) for row in policy)
        if invocation.get('mode') == 'public':
            gates.update(public_gates(folder, invocation, role))
        if require_beta2 or profile == BETA2_PROFILE:
            gates.update(beta2_gates(folder, invocation, role, slot))
        if require_cohesion or invocation.get('cohesion_acceptance') is True:
            gates.update(march_gates(folder, invocation, role, slot))
        failures.extend(f'{role}: {key}' for key, value in gates.items() if not value)
        clients[role] = {'matched': matched, 'ended': terminal.get('ended'),
                         'last_game_seconds': latest.get('time'),
                         'coverage': coverage, 'stats': stats, 'gates': gates, 'errors': errors,
                         'warnings': [row for row in console if row.get('type') == 'warning'],
                         'http_errors': lines(folder / f'{role}-http-errors.jsonl'),
                         'request_failures': request_failures, 'request_recovery': request_recovery,
                         'artifact_cdp_body_hashes': lines(folder / f'{role}-asset-bytes.jsonl'),
                         'artifact_cdp_body_failures': lines(folder / f'{role}-asset-body-failures.jsonl'),
                         'artifact_owned_server_response_proof': lines(folder / f'{role}-asset-server-proof.jsonl'),
                         'rejections': [row for row in transport if row.get('packet', {}).get('op') == 'rejected'],
                         'ui_checks': ui, 'commands_sent': len(commands)}
    if scenario != 'objective' and (invocation.get('protocol') == 2 or invocation.get('mode') == 'public'):
        for role, opposite in (('host', 'guest'), ('guest', 'host')):
            matched = clients[role].get('matched', {})
            slot = matched.get('slot')
            ids = matched.get('civilizations', [])
            unit_type = 3 if slot in (0, 1) and len(ids) == 2 and ids[slot] == 2 else 2
            last = read(folder / f'{opposite}-terminal.json', {}).get('last', {})
            battle = last.get('battle', {}).get('losses_by_matchup', [])
            valid = counter_lesson(last, clients[opposite].get('matched', {}).get('slot')) is not None
            final_blows = sum(row[2] for row in battle if row[1] == unit_type) if valid else 0
            clients[role]['coverage']['signature_final_blows_witnessed_by_opponent'] = final_blows
            clients[role]['gates']['signature_visible_combat_final_blow_receipt'] = final_blows > 0
            if not final_blows:
                failures.append(f'{role}: signature_visible_combat_final_blow_receipt')
    host, guest = clients['host'], clients['guest']
    agreement = {}
    identity_keys = ['match', 'seed', 'map_archetype']
    if invocation.get('protocol') == 2 or invocation.get('mode') == 'local-sealed':
        identity_keys.append('civilizations')
    for key in identity_keys:
        a, b = (client.get('matched') or {} for client in (host, guest))
        agreement[key] = a.get(key) is not None and b.get(key) is not None and a[key] == b[key]
    agreement['opposite_slots'] = {(c.get('matched') or {}).get('slot') for c in clients.values()} == {0, 1}
    for key in ('match', 'winner', 'reason'):
        a, b = (client.get('ended') or {} for client in (host, guest))
        agreement['terminal_' + key] = a.get(key) is not None and b.get(key) is not None and a[key] == b[key]
    agreement['natural_sacred_result'] = all('Sacred' in (c.get('ended') or {}).get('reason', '') for c in clients.values())
    if invocation.get('mode') in ('local-sealed', 'public'):
        log_path = folder / ('local-authority.log' if invocation.get('mode') == 'local-sealed' else 'public-authority.log')
        terminal_lines = re.findall(r'AOEM_MATCH_ENDED match=(\d+) winner=(-?\d+) seconds=([0-9.]+) fps=[0-9.]+ reason=([^\r\n]+)', log_path.read_text(encoding='utf-8', errors='replace') if log_path.exists() else '')
        ended = host.get('ended') or {}
        agreement['natural_terminal_in_owned_authority_log' if invocation.get('mode') == 'local-sealed' else 'natural_terminal_in_deployed_authority_log'] = any(int(match) == ended.get('match') and int(winner) == ended.get('winner') and reason == ended.get('reason') and abs(float(seconds) - (host.get('last_game_seconds') or 0)) < 0.2 for match, winner, seconds, reason in terminal_lines)
    counters = {'same_tick_samples': 0, 'shared_actor_fields': 0, 'shared_resource_tiles': 0}
    for tick in sorted(records['host'].keys() & records['guest'].keys()):
        a, b = records['host'][tick], records['guest'][tick]
        counters['same_tick_samples'] += 1
        if a['time'] != b['time'] or a['site'] != b['site'] or a.get('civilizations') != b.get('civilizations'):
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
    report = {'passed': not failures, 'failures': failures, 'scenario': scenario, 'acceptance_profile': profile, 'beta2_required': require_beta2, 'identity_and_result_agreement': agreement,
              'same_tick_comparison': counters, 'same_tick_mismatches': mismatches[:100], 'clients': clients,
              'controller_errors': controller_errors,
              'scope': invocation.get('scope', 'Two actual deployed browser contexts. UI lobby and recorded keyboard actions; test-only ordinary paid WebSocket gameplay policy. Evidence is passive transport, rendered screenshots and operator UI checks. No direct browser-replica inspection, physical phone test or performance claim.'),
              'public_provenance_limit': 'Browser version and JavaScript body SHA-256 are direct. If CDP cannot retain large WASM/PCK bodies, actual response validators are matched to independently TLS-fetched and SHA-256-verified public postflight bytes; this is correlated deployment evidence, not browser-body hashing.' if invocation.get('mode') == 'public' else None,
              'private_state_scope': 'Each owner bank/player/research is retained from that client authority packet; opposite private banks are not expected to match. Farm claims, exact worker resource/dropoff target IDs and physical spacing are not exposed by this protocol.'}
    report['raw_evidence_sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(folder.iterdir()) if p.is_file() and p.name != 'analysis.json'}
    report['public_postflight_header_sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((folder / 'public-postflight-headers').glob('*.headers'))}
    report['analyzer_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    report['beta2_evidence_helper_sha256'] = hashlib.sha256(Path(__file__).with_name('beta2_browser_evidence.py').read_bytes()).hexdigest()
    report['cohesion_required'] = require_cohesion
    report['march_evidence_helper_sha256'] = hashlib.sha256(Path(__file__).with_name('march_browser_evidence.py').read_bytes()).hexdigest()
    (folder / 'analysis.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--require-beta2', action='store_true', help='Fail unless both clients meet every paid Siege/fighter/native-touch beta2 gate')
    parser.add_argument('--require-cohesion', action='store_true', help='Also require paid mixed march, private status, and explicit Move release for both slots')
    args = parser.parse_args()
    result = analyze(args.output, require_beta2=args.require_beta2, require_cohesion=args.require_cohesion)
    print(json.dumps({key: result[key] for key in ('passed', 'failures', 'identity_and_result_agreement', 'same_tick_comparison')}, indent=2))
    sys.exit(0 if result['passed'] else 1)
