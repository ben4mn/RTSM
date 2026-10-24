"""Optional post-purchase garrison witness: actual packets, native taps and reviewed pixels."""
import hashlib
import json
import math
from pathlib import Path
import re

from beta2_browser_evidence import lines, integer, number, distance, units, native_tap, validate_fact, beta2_gates, FIGHTERS
from march_browser_evidence import accepted, march_gates, derive_paid_siege, validate as validate_march

ACTIONS = ('scout_move', 'paused', 'fighters_move', 'ticking')
PURPOSES = {
    'scout_move': ['garrison_scout_select', 'garrison_scout_site_view', 'garrison_scout_move', 'garrison_scout_ground'],
    'paused': [],
    'fighters_move': ['garrison_army_open', 'garrison_groups_open', 'garrison_select_fighters', 'garrison_fighters_site_view', 'garrison_fighters_move', 'garrison_fighters_ground'],
    'ticking': [],
}
CENTER, RADIUS = [0, 1152], 192  # Source-bound72x72 map, actual3tile radius.


def inside(unit):
    return distance([unit['x'], unit['y']], CENTER) <= RADIUS


def derive_paid_scout(rows, match, slot):
    birth = next(row for row in reversed(rows) if row.get('action') == 'scout_birth' and row.get('passed') is True and row.get('match') == match and row.get('slot') == slot)
    train = next(row for row in rows if row.get('id') == birth.get('parent') and row.get('action') == 'scout_train' and row.get('passed') is True and row.get('match') == match and row.get('slot') == slot)
    verified = validate_fact(train, {})
    return {**birth, 'verified': validate_fact(birth, {'scout_train': {**train, 'verified': verified}})}


def derive_paid_fighters(base, march, match, slot):
    siege = derive_paid_siege(base, match, slot)
    birth = next(row for row in reversed(march) if row.get('action') == 'warrior_birth' and row.get('passed') is True and row.get('match') == match and row.get('slot') == slot)
    train = next(row for row in march if row.get('id') == birth.get('parent') and row.get('action') == 'warrior_train' and row.get('passed') is True and row.get('match') == match and row.get('slot') == slot)
    verified = validate_march(train, {}, siege)
    warrior = validate_march(birth, {'warrior_train': {**train, 'verified': verified}}, siege)
    return [warrior['warrior_id'], siege['verified']['unit_id']]


def clock_series(series, role, slot, scout_id, mode, fighter_ids=()):
    assert mode in ('paused', 'ticking') and len(series) >= 3
    first, last = series[0][role], series[-1][role]
    assert number(first['time']) and number(last['time']) and 2 <= last['time'] - first['time'] <= 5
    for index, sample in enumerate(series):
        packet, other = sample[role], sample['guest' if role == 'host' else 'host']
        assert integer(packet['match'], 1) and packet['match'] == first['match'] == other['match'] and packet['tick'] == other['tick'] and packet['time'] == other['time']
        if index:
            assert packet['tick'] > series[index-1][role]['tick'] and packet['time'] > series[index-1][role]['time']
        site = packet['site']
        assert site == other['site']
        assert type(site['state']) is int and site['state'] == 2 and type(site['owner']) is int and site['owner'] == slot
        assert site['hold'] == 180 and site['capture'] == 1 and site['neutralizing'] is False
        assert site['garrison_paused'] is (mode == 'paused') and site['clock_ticking'] is (mode == 'ticking')
        assert number(site['timer']) and 0 <= site['timer'] < site['hold']
        roster = units(packet, slot)
        scout = next(unit for unit in roster if unit['id'] == scout_id and unit['type'] == 4)
        assert inside(scout)
        if mode == 'paused':
            assert not any(unit['type'] in FIGHTERS and inside(unit) for unit in roster)
            assert abs(site['timer'] - first['site']['timer']) < 1e-6
        else:
            assert any(unit['id'] in fighter_ids and unit['type'] in FIGHTERS and inside(unit) for unit in roster)
            assert abs((site['timer'] - first['site']['timer']) - (packet['time'] - first['time'])) < .08
    return {'owner': slot, 'scout_id': scout_id, 'first_tick': first['tick'], 'last_tick': last['tick'], 'game_seconds': last['time'] - first['time']}


def garrison_gates(folder, invocation, role, slot):
    gates = {
        'garrison_postpurchase_profile_declared': invocation.get('garrison_acceptance') is True and invocation.get('cohesion_acceptance') is True and invocation.get('protocol') == 3 and invocation.get('input_mode') == 'touch',
        'garrison_tool_identity_recorded': isinstance(invocation.get('garrison_tool_sha256'), str) and re.fullmatch('[a-f0-9]{64}', invocation['garrison_tool_sha256']) is not None,
        'garrison_paid_prior_siege_and_march': False,
        'garrison_paid_scout_ui_and_paused_both_recipients': False,
        'garrison_fighter_ui_and_ticking_both_recipients': False,
        'garrison_native_inputs_windows_and_reviews': False,
    }
    try:
        terminals = {peer: json.loads((folder / (peer + '-terminal.json')).read_text()) for peer in ('host', 'guest')}
        match = terminals[role]['matched']['match']
        assert integer(match, 1) and terminals[role]['matched']['slot'] == slot
        assert {terminal['matched']['slot'] for terminal in terminals.values()} == {0, 1}
        for peer, terminal in terminals.items():
            assert terminal['matched']['match'] == terminal['last']['match'] == terminal['ended']['match'] == match
            assert all(beta2_gates(folder, invocation, peer, terminal['matched']['slot']).values())
            assert all(march_gates(folder, invocation, peer, terminal['matched']['slot']).values())
        gates['garrison_paid_prior_siege_and_march'] = True
        rows = lines(folder / (role + '-garrison-ui.jsonl'))
        scout = derive_paid_scout(lines(folder / (role + '-beta2-ui.jsonl')), match, slot)
        paid_fighters = derive_paid_fighters(lines(folder / (role + '-beta2-ui.jsonl')), lines(folder / (role + '-march-ui.jsonl')), match, slot)
        full = {peer: lines(folder / (peer + '-authority-full.jsonl')) for peer in terminals}
        wire = {peer: lines(folder / (peer + '-sent.jsonl')) for peer in terminals}
        origins = lines(folder / (role + '-command_origin.jsonl'))
        inputs = lines(folder / (role + '-browser-input.jsonl'))
        transport = {peer: lines(folder / (peer + '-transport.jsonl')) for peer in terminals}
        captures = {peer: lines(folder / (peer + '-captures.jsonl')) for peer in terminals}
        pauses, starts = lines(folder / 'policy-pauses.jsonl'), lines(folder / 'policy-starts.jsonl')
        prior = {}
        for row in (entry for entry in rows if entry.get('passed') is True and entry.get('action') in ACTIONS):
            action = row['action']
            assert row['match'] == row['before']['match'] == row['after']['match'] == match and row['slot'] == slot and row['beta2_scout_birth'] == scout['id']
            assert row['policy_held'] is True and integer(row['started_unix'], 1) and row['finished_unix'] >= row['started_unix'] and row['rejections_before'] == row['rejections_after']
            assert set(row['rejections_before']) == {'host', 'guest'} and all(integer(value) for value in row['rejections_before'].values())
            for packet in (row['before'], row['after']):
                assert any(item['packet'] == packet and row['started_unix'] - 2000 <= item['unix'] <= row['finished_unix'] for item in full[role])
            commands = [item['packet'] for item in wire[role] if row['started_unix'] <= item['unix'] <= row['finished_unix'] and item['packet'].get('op') == 'command']
            assert commands == [item['packet'] for item in row['commands']] and len(commands) == (1 if PURPOSES[action] else 0)
            assert row['evidence'] == (row['commands'][0] if commands else None)
            for command in row['commands']:
                assert any(item.get('serial') == command['serial'] and item.get('packet') == command['packet'] and item.get('source') == 'game_ui_or_engine' for item in origins)
            assert [item['purpose'] for item in row['inputs']] == PURPOSES[action]
            for item in row['inputs']:
                assert item in inputs and row['started_unix'] <= item['unix'] <= row['finished_unix']; native_tap(item)
            assert len(row['captures']) >= 4 and {image['role'] for image in row['captures']} == {'host', 'guest'}
            for image in row['captures']:
                raw = {key: value for key, value in image.items() if key != 'role'}
                assert raw in captures[image['role']] and Path(image['name']).name == image['name'] and row['started_unix'] <= image['unix'] <= row['finished_unix']
                assert hashlib.sha256((folder / image['name']).read_bytes()).hexdigest() == image['sha256']
            if action == 'scout_move':
                assert not (row['before']['site']['state'] == 2 and row['before']['site']['owner'] == slot)
                assert any(unit['id'] == scout['verified']['unit_id'] and not inside(unit) for unit in units(row['before'], slot))
                fact = validate_fact({**row, 'action': 'scout_move'}, {'scout_birth': scout})
                assert distance(fact['destination'], CENTER) <= RADIUS / 2
            elif action == 'fighters_move':
                sent = next(item for item in wire[role] if item['packet'] == row['evidence']['packet'])
                assert integer(row['command_prepared_unix'], 1) and row['started_unix'] <= row['command_prepared_unix'] <= sent['unix'] and sent['unix'] - row['command_prepared_unix'] <= 1000
                samples = [item for item in full[role] if item['packet'].get('match') == match and item['packet']['tick'] >= row['before']['tick'] and item['unix'] <= sent['unix']]
                assert samples and sent['unix'] - max(item['unix'] for item in samples) <= 1000
                for sample in samples:
                    site = sample['packet']['site']
                    assert site['state'] == 2 and site['owner'] == slot and site['garrison_paused'] is True and site['clock_ticking'] is False and site['neutralizing'] is False
                    assert not any(unit['type'] in FIGHTERS and inside(unit) for unit in units(sample['packet'], slot))
                fighter_ids = accepted(row['before'], row['after'], slot, row['evidence'], 'move', False)
                assert distance(row['evidence']['packet']['position'], CENTER) <= RADIUS / 2
                fact = {'fighter_ids': fighter_ids}
            else:
                paid_ordered = [identity for identity in paid_fighters if identity in prior.get('fighters_move', {}).get('verified', {}).get('fighter_ids', [])]
                fact = clock_series(row['series'], role, slot, scout['verified']['unit_id'], action, paid_ordered)
                assert row['after'] == row['series'][-1][role]
                for sample in row['series']:
                    for peer, packet in sample.items():
                        assert any(item['packet'] == packet and row['started_unix'] <= item['unix'] <= row['finished_unix'] for item in full[peer])
                # Recheck every raw packet, including omitted intermediate ticks.
                # A same-tick duplicate may repeat exact bytes, never a new state.
                raw_by_peer = {}
                for peer in terminals:
                    selected = [item for item in full[peer] if item['packet'].get('match') == match and fact['first_tick'] <= item['packet']['tick'] <= fact['last_tick']]
                    raw_by_peer[peer] = {}
                    for item in selected:
                        packet = item['packet'];tick = packet['tick']
                        assert tick not in raw_by_peer[peer] or raw_by_peer[peer][tick] == packet
                        raw_by_peer[peer][tick] = packet
                    assert raw_by_peer[peer]
                assert set(raw_by_peer['host']) == set(raw_by_peer['guest'])
                raw_series = [{peer: raw_by_peer[peer][tick] for peer in terminals} for tick in sorted(raw_by_peer['host'])]
                clock_series(raw_series, role, slot, scout['verified']['unit_id'], action, paid_ordered)
            prior[action] = {**row, 'verified': fact}
        assert set(prior) == set(ACTIONS)
        for parent, child in zip(ACTIONS, ACTIONS[1:]):
            assert prior[child]['parent'] == prior[parent]['id'] and prior[child]['started_unix'] >= prior[parent]['finished_unix']
        first, last = prior['scout_move']['started_unix'], prior['ticking']['finished_unix']
        for peer, terminal in terminals.items():
            review = next(entry for entry in reversed(lines(folder / (peer + '-march-ui.jsonl'))) if entry.get('action') == 'review' and entry.get('passed') is True and entry['match'] == match)
            assert review['unix'] <= first
            actual = [item['packet'] for item in wire[peer] if first <= item['unix'] <= last and item['packet'].get('op') == 'command']
            assert actual == ([prior[action]['evidence']['packet'] for action in ('scout_move', 'fighters_move')] if peer == role else [])
            assert not any(first <= item['unix'] <= last and item.get('packet', {}).get('op') == 'rejected' for item in transport[peer])
        expected_inputs = [item for action in ACTIONS for item in prior[action]['inputs']]
        assert [item for item in inputs if first <= item['unix'] <= last] == expected_inputs
        assert len({item['id'] for item in expected_inputs}) == len(expected_inputs)
        assert all(a['dispatches'][-1]['acknowledged_unix'] <= b['dispatches'][0]['started_unix'] for a, b in zip(expected_inputs, expected_inputs[1:]))
        earlier = [entry for entry in pauses if entry['unix'] <= first]
        assert earlier and len(earlier[-1]['reason'].strip()) >= 12 and not any(earlier[-1]['unix'] < entry['unix'] <= last for entry in starts)
        gates['garrison_paid_scout_ui_and_paused_both_recipients'] = True
        gates['garrison_fighter_ui_and_ticking_both_recipients'] = True
        review = next(entry for entry in reversed(rows) if entry.get('action') == 'review' and entry.get('passed') is True and entry.get('reviewed') is True)
        assert review['match'] == match and review['slot'] == slot and review['attempts'] == [prior[action]['id'] for action in ACTIONS] and review['unix'] >= last
        for mode in ('paused', 'ticking'):
            row = prior[mode]
            for peer, terminal in terminals.items():
                text = review['observed'][mode][peer]
                owner = 'You' if terminal['matched']['slot'] == slot else 'Enemy'
                assert text['title'] == (('Held · bring a fighter' if owner == 'You' else 'Enemy held · unguarded') if mode == 'paused' else 'Sacred Site · tap to view')
                pattern = owner + (r' (\d+):(\d{2}) paused' if mode == 'paused' else r' win in (\d+):(\d{2})')
                clock = re.fullmatch(pattern, text['clock']); assert clock
                seconds = int(clock[1]) * 60 + int(clock[2]); assert int(clock[2]) < 60
                after_capture = next(image for image in reversed(row['captures']) if image['role'] == peer)
                near = [item['packet']['site'] for item in full[peer] if abs(item['unix'] - after_capture['unix']) <= 1500 and item['packet'].get('match') == match]
                assert any(site['owner'] == slot and site['garrison_paused'] is (mode == 'paused') and site['clock_ticking'] is (mode == 'ticking') and max(0, math.ceil(site['hold'] - site['timer'])) == seconds for site in near)
        gates['garrison_native_inputs_windows_and_reviews'] = True
    except (AssertionError, KeyError, TypeError, ValueError, StopIteration, OSError):
        pass
    return gates
