"""Fail-closed beta2 mobile receipts. Pure retained-file analysis; no browser control."""
import hashlib
import json
import math
import re
from pathlib import Path
from protocol_evidence import protocol_declared

PROFILE = 'beta2-mobile'
FIGHTERS = (1, 2, 3, 5)
RESOURCES = ('food', 'wood', 'gold')
ACTIONS = ('scout_train', 'scout_birth', 'workshop_open', 'workshop_place', 'workshop_complete', 'siege_train', 'siege_birth', 'scout_move', 'fighter_select', 'fighter_find', 'fighter_attack')
PURPOSES = {
    'scout_train': ['beta2_town_select', 'beta2_scout_train'], 'scout_birth': [],
    'workshop_open': ['beta2_build_open', 'beta2_army_build_category', 'beta2_workshop_card'],
    'workshop_place': ['beta2_workshop_ground', 'beta2_workshop_place'], 'workshop_complete': [],
    'siege_train': ['beta2_workshop_select', 'beta2_siege_train'], 'siege_birth': [],
    'scout_move': ['beta2_scout_select', 'beta2_scout_move_button', 'beta2_scout_move_ground'],
    'fighter_select': ['beta2_army_open', 'beta2_groups_open', 'beta2_select_fighters'],
    'fighter_find': ['beta2_find_army_open', 'beta2_find_groups_open', 'beta2_find_fighters'],
    'fighter_attack': ['observed_attack_hud_button', 'attack_move_ground_destination']}


def lines(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()] if path.exists() else []


def integer(value, minimum=0):
    return type(value) is int and value >= minimum


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def vector(value):
    return isinstance(value, list) and len(value) == 2 and all(number(v) for v in value)


def distance(a, b):
    assert vector(a) and vector(b)
    return math.dist(a, b)


def tile(point):
    assert vector(point)
    result = [point[0] / 64 + point[1] / 32, point[1] / 32 - point[0] / 64]
    assert all(abs(v-round(v)) < 1e-6 and 0 <= v < 72 for v in result)
    return result


def own(packet, slot, kind=None):
    assert type(slot) is int and slot in (0, 1)
    rows = packet['actors']
    ids = [row['id'] for row in rows]
    assert all(integer(i, 1) for i in ids) and len(ids) == len(set(ids))
    return [row for row in rows if row.get('owner') == slot and (kind is None or row.get('kind') == kind)]


def units(packet, slot):
    return [u for u in own(packet, slot, 'unit') if integer(u.get('type')) and u['type'] <= 5 and number(u.get('hp')) and u['hp'] > 0 and u.get('state') != 5]


def ids(rows):
    return sorted(row['id'] for row in rows)


def interval(before, after, maximum=6):
    assert integer(before.get('match'), 1) and before['match'] == after['match']
    assert integer(before.get('tick')) and integer(after.get('tick')) and before['tick'] < after['tick']
    assert number(before.get('time')) and number(after.get('time')) and 0 < after['time'] - before['time'] <= maximum


def paid(before, after, cost):
    assert all(integer(p.get('bank', {}).get(k)) for p in (before, after) for k in RESOURCES)
    assert all(before['bank'][k] >= cost.get(k, 0) for k in RESOURCES)
    prior, later = (p['stats']['resources_gathered'] for p in (before, after))
    assert integer(prior) and integer(later) and later >= prior
    deposits = [after['bank'][k] - before['bank'][k] + cost.get(k, 0) for k in RESOURCES]
    assert all(n >= 0 for n in deposits) and sum(deposits) == later - prior


def quiet(packet, slot, exception=None):
    for actor in own(packet, slot, 'building'):
        if 'queue' in actor:
            queue = actor['queue']
            assert queue['repeat'] is False and isinstance(queue['items'], list)
            assert actor['id'] == exception or queue['items'] == []


def route(unit):
    assert unit['state'] == 1 and vector(unit['destination'])
    assert isinstance(unit['path'], list) and len(unit['path']) >= 2 and all(vector(p) for p in unit['path'])
    assert distance(unit['path'][0], [unit['x'], unit['y']]) <= .01


def validate_fact(row, prior):
    """Independent payment/roster/route validation, ignoring the recorded passed/proof claim."""
    action, before, after, slot = (row[k] for k in ('action', 'before', 'after', 'slot'))
    evidence = row.get('evidence') or {}
    command = evidence.get('packet', {})
    command_actions = {'workshop_place': 'place', 'siege_train': 'train', 'scout_train': 'train', 'scout_move': 'move', 'fighter_attack': 'attack_move'}
    if action in command_actions:
        assert evidence.get('source') == 'game_ui_or_engine' and integer(evidence.get('serial'), 1)
        assert command.get('op') == 'command' and command.get('command') == command_actions[action] and command.get('match') == before['match'] and integer(command.get('sequence'), 1)
    if action in ('workshop_open', 'fighter_select', 'fighter_find'):
        assert row.get('commands') == []
        return {}
    if action == 'workshop_place':
        interval(before, after); quiet(before, slot); quiet(after, slot)
        assert command['type'] == 8 and before['player']['age'] == after['player']['age'] == 3
        assert integer(before['stats']['resources_gathered']) and before['stats']['resources_gathered'] >= 650
        old, current = own(before, slot, 'building'), own(after, slot, 'building')
        fresh = [a for a in current if a['id'] not in ids(old)]
        assert not any(a['type'] == 8 for a in old) and len(fresh) == 1 and len(current) == len(old)+1 and set(ids(old)) <= set(ids(current))
        foundation = fresh[0]
        assert foundation['type'] == 8 and foundation['state'] == 1 and number(foundation['progress']) and 0 <= foundation['progress'] < 1 and foundation['hp'] > 0
        assert distance([foundation['x'], foundation['y']], command['position']) <= .01
        workers = [u['id'] for u in units(before, slot) if u['type'] == 0]
        assert workers and isinstance(command.get('ids', []), list) and all(i in workers for i in command.get('ids', []))
        assert ids(units(before, slot)) == ids(units(after, slot))
        paid(before, after, {'wood': 300, 'gold': 100})
        return {'building_id': foundation['id']}
    if action == 'workshop_complete':
        placement = prior['workshop_place']; interval(placement['after'], after, 150)
        building_id = placement['verified']['building_id']
        building = next(a for a in own(after, slot, 'building') if a['id'] == building_id)
        assert building['type'] == 8 and building['state'] == 2 and building['progress'] == 1 and building['hp'] > 0
        assert after['time'] - placement['after']['time'] >= 27
        return {'building_id': building_id}
    if action in ('siege_train', 'scout_train'):
        siege = action == 'siege_train'; unit_type, building_type, duration, pop = (5, 8, 25, 3) if siege else (4, 0, 8, 1)
        interval(before, after); quiet(before, slot); quiet(after, slot, command['target'])
        assert command['type'] == unit_type
        if siege:
            assert command['target'] == prior['workshop_complete']['verified']['building_id'] and before['player']['age'] == after['player']['age'] == 3
        old, current = (next(a for a in own(p, slot, 'building') if a['id'] == command['target'] and a['type'] == building_type and a['state'] == 2) for p in (before, after))
        assert old['queue']['items'] == [] and current['queue']['items'] == [unit_type] and current['queue']['repeat'] is False and current['queue']['training'] is True and current['queue']['time'] == duration
        bp, ap = before['player'], after['player']
        assert all(integer(p[key]) for p in (bp,ap) for key in ('population','population_reserved','population_cap')) and ap['population'] == bp['population'] and ap['population_reserved'] == bp['population_reserved'] + pop
        assert bp['population'] + bp['population_reserved'] + pop <= bp['population_cap']
        assert ids(units(before, slot)) == ids(units(after, slot))
        paid(before, after, {'wood':150,'gold':100} if siege else {'food':40,'gold':10})
        return {'building_id': command['target'], 'unit_type': unit_type, 'population_cost': pop}
    if action in ('siege_birth', 'scout_birth'):
        siege = action == 'siege_birth'; train = prior['siege_train' if siege else 'scout_train']
        initial, queued = train['before'], train['after']; unit_type, duration, pop = (5,25,3) if siege else (4,8,1)
        interval(queued, after, 90 if siege else 60); quiet(after, slot)
        assert after['time']-queued['time'] >= duration-1
        producer = next(a for a in own(after, slot, 'building') if a['id'] == train['verified']['building_id'])
        assert producer['state'] == 2 and producer['type'] == (8 if siege else 0) and producer['queue']['items'] == []
        old, current = units(initial, slot), units(after, slot); fresh = [u for u in current if u['id'] not in ids(old)]
        assert len(fresh) == 1 and fresh[0]['type'] == unit_type and len(current) == len(old)+1 and set(ids(old)) <= set(ids(current))
        assert after['player']['population'] == initial['player']['population'] + pop and after['player']['population_reserved'] == initial['player']['population_reserved']
        return {'unit_id': fresh[0]['id']}
    if action == 'scout_move':
        interval(before, after); tile(command['position'])
        assert all(integer(identity,1) for identity in command['ids']) and command['ids'] == [prior['scout_birth']['verified']['unit_id']]
        old, current = (next(u for u in units(p, slot) if u['id'] == command['ids'][0] and u['type'] == 4) for p in (before, after))
        route(current); assert current['attack_move'] is False
        assert distance(current['destination'],command['position']) <= .01 and (not vector(old.get('destination')) or distance(old['destination'],current['destination']) > 1)
        return {'scout_id': current['id'], 'destination': current['destination']}
    if action == 'fighter_attack':
        before = prior['fighter_select']['before']; interval(before, after, 45); target = tile(command['position'])
        old, current = ([u for u in units(p, slot) if u['type'] in FIGHTERS] for p in (before, after))
        assert len(old) >= 2 and all(integer(identity,1) for identity in command['ids']) and len(command['ids']) == len(set(command['ids'])) and sorted(command['ids']) == ids(old) == ids(current)
        for unit in current:
            route(unit); destination = tile(unit['destination']); previous = next(u for u in old if u['id'] == unit['id'])
            assert unit['attack_move'] is True and all(abs(a-b) <= 6 for a,b in zip(destination,target))
            assert not vector(previous.get('destination')) or distance(previous['destination'],unit['destination']) > 1
            assert distance([unit['x'],unit['y']],[previous['x'],previous['y']]) > .5
        recon = prior['scout_move']['verified']
        scout, later = (next(u for u in units(p, slot) if u['id'] == recon['scout_id'] and u['type'] == 4) for p in (before, after))
        assert scout['state'] == later['state'] == 1 and scout['attack_move'] is False and later['attack_move'] is False
        assert scout['destination'] == later['destination'] == recon['destination'] and distance([scout['x'],scout['y']],[later['x'],later['y']]) > .5
        centroid = [sum(u[key] for u in old)/len(old) for key in ('x','y')]
        assert distance([scout['x'],scout['y']],centroid) >= 200
        return {'fighter_ids': ids(old), 'fighter_count': len(old), 'scout_id': scout['id']}
    raise AssertionError('Unknown receipt action')


def native_tap(row):
    assert row.get('kind') == 'tap' and row.get('native_api') == 'CDP.Input.dispatchTouchEvent' and row.get('contact_id') == 0
    assert isinstance(row.get('id'), str) and row['id']
    start, end = row['dispatches']; assert start['type'] == 'touchStart' and end['type'] == 'touchEnd' and end['touchPoints'] == []
    assert len(start['touchPoints']) == 1 and start['touchPoints'][0]['id'] == 0 and start['touchPoints'][0]['x'] == row['x'] and start['touchPoints'][0]['y'] == row['y']
    assert 0 <= row['x'] < 844 and 0 <= row['y'] < 390
    for event in (start,end):
        assert event.get('acknowledged') is True and integer(event.get('started_unix'),1) and integer(event.get('acknowledged_unix'),1) and event['started_unix'] <= event['acknowledged_unix']
    assert start['acknowledged_unix'] <= end['started_unix'] <= end['acknowledged_unix'] <= row['unix']
    return True


def beta2_gates(folder, invocation, role, slot):
    gates = {'beta2_profile_declared': invocation.get('acceptance_profile') == PROFILE and invocation.get('input_mode') == 'touch' and protocol_declared(invocation) and invocation.get('scenario') == 'full',
             'beta2_tool_identity_recorded': all(isinstance(invocation.get('beta2_tool_sha256',{}).get(name),str) and re.fullmatch('[a-f0-9]{64}',invocation['beta2_tool_sha256'][name]) for name in ('live_browser_beta2_ui.cjs','live_browser_beta2_receipts.cjs')),
             'beta2_paid_workshop_labor_siege_three_pop':False,'beta2_paid_scout_fighter_route_preserved':False,'beta2_native_reused_contact_and_isolated_windows':False,'beta2_captures_reviewed':False,'beta2_policy_pauses_disclosed':False}
    try:
        terminal=json.loads((folder/f'{role}-terminal.json').read_text(encoding='utf-8'))
        match=terminal['matched']['match']
        assert integer(match,1) and terminal['matched']['slot']==slot and terminal['ended']['match']==terminal['last']['match']==match
        rows=lines(folder/f'{role}-beta2-ui.jsonl'); inputs=lines(folder/f'{role}-browser-input.jsonl'); wire=lines(folder/f'{role}-sent.jsonl')
        origins=lines(folder/f'{role}-command_origin.jsonl'); full=lines(folder/f'{role}-authority-full.jsonl'); transport=lines(folder/f'{role}-transport.jsonl'); captures=lines(folder/f'{role}-captures.jsonl')
        pauses=lines(folder/'policy-pauses.jsonl'); starts=lines(folder/'policy-starts.jsonl'); prior={}
        successful=[row for row in rows if row.get('passed') is True and row.get('action') in ACTIONS]
        assert successful
        for row in successful:
            assert row['slot'] == slot and row['match']==match and row['before']['match']==row['after']['match']==match and row['policy_held'] is True and integer(row['started_unix'],1) and row['finished_unix'] >= row['started_unix']
            assert row['rejections_before'] == row['rejections_after'] and integer(row['rejections_before'])
            for packet in (row['before'],row['after']):
                assert any(item['packet'] == packet and item['unix'] <= row['finished_unix'] and item['unix'] >= row['started_unix']-2000 for item in full)
            actual=[item for item in wire if row['started_unix'] <= item['unix'] <= row['finished_unix'] and item['packet'].get('op') == 'command']
            assert len(actual) == len(row['commands']) and [item['packet'] for item in actual] == [item['packet'] for item in row['commands']]
            assert not any(row['started_unix'] <= item['unix'] <= row['finished_unix'] and item.get('packet',{}).get('op') == 'rejected' for item in transport)
            for command in row['commands']:
                assert any(item.get('serial') == command['serial'] and item.get('packet') == command['packet'] and item.get('source') == 'game_ui_or_engine' for item in origins)
            assert row['evidence'] == (row['commands'][0] if row['commands'] else None)
            assert [item['purpose'] for item in row['inputs']] == PURPOSES[row['action']]
            for item in row['inputs']:
                assert item in inputs and row['started_unix'] <= item['unix'] <= row['finished_unix']; native_tap(item)
            assert len(row['captures']) >= 2
            for image in row['captures']:
                assert image in captures and Path(image['name']).name == image['name'] and row['started_unix'] <= image['unix'] <= row['finished_unix']
                assert hashlib.sha256((folder/image['name']).read_bytes()).hexdigest() == image['sha256']
            prior[row['action']]={**row,'verified':validate_fact(row,prior)}
        assert set(prior) == set(ACTIONS)
        parents={'scout_birth':'scout_train','workshop_place':'workshop_open','workshop_complete':'workshop_place','siege_train':'workshop_complete','siege_birth':'siege_train','scout_move':'scout_birth','fighter_select':'scout_move','fighter_find':'fighter_select','fighter_attack':'fighter_find'}
        for child,parent in parents.items():
            assert prior[child]['parent'] == prior[parent]['id'] and prior[child]['started_unix'] >= prior[parent]['finished_unix']
        assert prior['fighter_attack']['recon'] == prior['scout_move']['id']
        # No hidden correction/order between payment and birth, or selection and Attack.
        for first,last,allowed in [('scout_train','scout_birth','train'),('siege_train','siege_birth','train'),('fighter_select','fighter_attack','attack_move')]:
            orders=[item['packet'] for item in wire if prior[first]['started_unix'] <= item['unix'] <= prior[last]['finished_unix'] and item['packet'].get('op') == 'command']
            assert len(orders) == 1 and orders[0]['command'] == allowed
            assert not any(prior[first]['started_unix'] <= item['unix'] <= prior[last]['finished_unix'] and item.get('packet',{}).get('op') == 'rejected' for item in transport)
            allowed_inputs=[item for action in ACTIONS for item in prior[action]['inputs'] if prior[first]['started_unix'] <= item['unix'] <= prior[last]['finished_unix']]
            actual_inputs=[item for item in inputs if prior[first]['started_unix'] <= item['unix'] <= prior[last]['finished_unix']]
            assert actual_inputs == allowed_inputs, 'An unrecorded correction or selection change invalidates this isolated proof'
        gates['beta2_paid_workshop_labor_siege_three_pop']=True; gates['beta2_paid_scout_fighter_route_preserved']=True
        taps=[item for row in prior.values() for item in row['inputs']]
        assert len({item['id'] for item in taps}) == len(taps)
        taps.sort(key=lambda item:item['dispatches'][0]['started_unix'])
        assert len(taps)>=2 and all(a['dispatches'][-1]['acknowledged_unix'] <= b['dispatches'][0]['started_unix'] for a,b in zip(taps,taps[1:]))
        gates['beta2_native_reused_contact_and_isolated_windows']=True
        review=next(row for row in reversed(rows) if row.get('action')=='review' and row.get('reviewed') is True and row.get('passed') is True)
        assert review['slot']==slot and review['match']==match and review['attempts']==[prior[action]['id'] for action in ACTIONS] and review['unix']>=max(row['finished_unix'] for row in prior.values())
        observed=review['observed']
        assert observed['workshop']=='Siege Workshop' and observed['workshop_cost']=={'wood':300,'gold':100} and observed['siege']=='Siege Engine' and observed['siege_cost']=={'wood':150,'gold':100}
        paid_siege=prior['siege_train']
        assert observed['queue_count']==1 and observed['population_before']==paid_siege['before']['player']['population']+paid_siege['before']['player']['population_reserved']
        assert observed['population_queued']==paid_siege['after']['player']['population']+paid_siege['after']['player']['population_reserved'] and observed['scout']=='Scout' and observed['scout_cost']=={'food':40,'gold':10}
        assert observed['select_caption']=='Select fighters' and observed['fighter_count']==prior['fighter_attack']['verified']['fighter_count'] and observed['find_frames_fighters'] is True and observed['scout_excluded_from_selection'] is True
        gates['beta2_captures_reviewed']=True
        assert pauses and starts and all(isinstance(row.get('reason'),str) and len(row['reason'].strip())>=12 for row in pauses+starts)
        for row in prior.values():
            earlier=[event for event in pauses if event['unix']<=row['started_unix']]
            assert earlier and not any(max(event['unix'] for event in earlier)<event['unix']<=row['finished_unix'] for event in starts)
        phases=lines(folder/'beta2-policy-phases.jsonl')
        assert any(row.get('role')==role and row.get('phase')=='saving-for-touch-workshop-and-siege' for row in phases)
        gates['beta2_policy_pauses_disclosed']=True
    except (AssertionError,KeyError,TypeError,ValueError,StopIteration,OSError):
        pass
    return gates
