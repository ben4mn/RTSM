"""Optional source-bound paid march witness. Retained packets and native input only."""
import hashlib
import json
import re
from pathlib import Path
from beta2_browser_evidence import (beta2_gates, lines, integer, number, vector, distance,
    tile, own, units, ids, interval, paid, quiet, route, native_tap, validate_fact, FIGHTERS)

ACTIONS=('warrior_train','warrior_birth','regroup','settled','attack','move')
PURPOSES={'warrior_train':['march_barracks_select','march_warrior_train'],'warrior_birth':[],
          'regroup':['march_army_open','march_groups_open','march_select_fighters','march_regroup_move','march_regroup_ground'],
          'settled':[],'attack':['march_attack_hud','march_attack_ground'],'move':['march_release_move_hud','march_release_ground']}


def fighters(packet,slot):
    return [u for u in units(packet,slot) if u['type'] in FIGHTERS]


def pair(packet,slot,warrior,siege):
    return [next(u for u in units(packet,slot) if u['id']==identity and u['type']==kind) for identity,kind in ((warrior,1),(siege,5))]


def accepted(before,after,slot,evidence,operation,marching):
    interval(before,after);command=evidence['packet'];target=tile(command['position'])
    assert evidence['source']=='game_ui_or_engine' and integer(evidence['serial'],1) and command['op']=='command' and command['match']==before['match'] and command['command']==operation and integer(command['sequence'],1)
    old,current=fighters(before,slot),fighters(after,slot)
    assert len(command['ids'])>=2 and all(integer(i,1) for i in command['ids']) and len(command['ids'])==len(set(command['ids'])) and sorted(command['ids'])==ids(old)==ids(current)
    for u in current:
        previous=next(a for a in old if a['id']==u['id']);route(u);end=tile(u['destination'])
        assert u['attack_move'] is (operation=='attack_move') and u['marching'] is marching and all(abs(a-b)<=6 for a,b in zip(end,target))
        assert not vector(previous.get('destination')) or distance(previous['destination'],u['destination'])>1
    return ids(current)


def derive_paid_siege(base,match,slot):
    birth=next(r for r in reversed(base) if r.get('action')=='siege_birth' and r.get('passed') is True and r.get('match')==match and r.get('slot')==slot)
    train=next(r for r in base if r.get('id')==birth.get('parent') and r.get('action')=='siege_train' and r.get('passed') is True and r.get('match')==match and r.get('slot')==slot)
    producer=train['evidence']['packet']['target']
    verified_train=validate_fact(train,{'workshop_complete':{'verified':{'building_id':producer}}})
    verified_birth=validate_fact(birth,{'siege_train':{**train,'verified':verified_train}})
    return {**birth,'verified':verified_birth}


def validate(row,prior,siege):
    before,after,slot,action=(row[k] for k in ('before','after','slot','action'))
    if action=='warrior_train':
        interval(before,after);evidence=row['evidence'];command=evidence['packet']
        assert evidence['source']=='game_ui_or_engine' and integer(evidence['serial'],1) and command['op']=='command' and command['match']==before['match'] and command['command']=='train' and command['type']==1 and integer(command['sequence'],1)
        quiet(before,slot);quiet(after,slot,command['target'])
        old,current=(next(a for a in own(p,slot,'building') if a['id']==command['target'] and a['type']==2 and a['state']==2) for p in (before,after))
        assert old['queue']['items']==[] and current['queue']['items']==[1] and current['queue']['training'] is True and current['queue']['repeat'] is False and current['queue']['time']==10
        bp,ap=before['player'],after['player'];assert all(integer(p[k]) for p in (bp,ap) for k in ('population','population_reserved','population_cap'))
        assert ap['population']==bp['population'] and ap['population_reserved']==bp['population_reserved']+1 and bp['population']+bp['population_reserved']+1<=bp['population_cap']
        assert ids(units(before,slot))==ids(units(after,slot));paid(before,after,{'food':50,'wood':20})
        return {'producer_id':command['target']}
    if action=='warrior_birth':
        train=prior['warrior_train'];initial=train['before'];interval(train['after'],after,90);quiet(after,slot);assert after['time']-train['after']['time']>=9
        producer=next(a for a in own(after,slot,'building') if a['id']==train['verified']['producer_id'] and a['type']==2 and a['state']==2);assert producer['queue']['items']==[]
        old,current=units(initial,slot),units(after,slot);fresh=[u for u in current if u['id'] not in ids(old)]
        assert len(fresh)==1 and fresh[0]['type']==1 and len(current)==len(old)+1 and set(ids(old))<=set(ids(current))
        assert after['player']['population']==initial['player']['population']+1 and after['player']['population_reserved']==initial['player']['population_reserved']
        return {'warrior_id':fresh[0]['id']}
    warrior=prior['warrior_birth']['verified']['warrior_id'];siege_id=siege['verified']['unit_id']
    pair(before,slot,warrior,siege_id)
    if action=='regroup':
        return {'fighter_ids':accepted(before,after,slot,row['evidence'],'move',False)}
    if action=='settled':
        regroup=prior['regroup'];interval(regroup['after'],after,150);current=fighters(after,slot);assert ids(current)==regroup['verified']['fighter_ids']
        for u in current:
            assigned=next(p for p in regroup['after']['actors'] if p['id']==u['id']);assert u['state']==0 and u['attack_move'] is False and u['marching'] is False
            assert distance(u['destination'],assigned['destination'])<=.01 and distance([u['x'],u['y']],assigned['destination'])<=4.01
        diameter=max(distance([a['x'],a['y']],[b['x'],b['y']]) for a in current for b in current);assert diameter<=128
        return {'fighter_ids':ids(current),'diameter':diameter}
    assert action in ('attack','move');series=row['series'];assert len(series)>=3
    marching=action=='attack';operation='attack_move' if marching else 'move';first,last=series[0],series[-1]
    selected=accepted(before,first,slot,row['evidence'],operation,marching);interval(first,last,4);assert last['time']-first['time']>=1
    paid_pair=pair(before,slot,warrior,siege_id)
    if marching:assert all(distance([u['x'],u['y']],row['evidence']['packet']['position'])>=512 for u in paid_pair)
    else:assert all(u['marching'] is True for u in paid_pair)
    for index,packet in enumerate(series):
        if index:interval(series[index-1],packet,4)
        assert ids(fighters(packet,slot))==selected
        for u in pair(packet,slot,warrior,siege_id):
            original=next(a for a in first['actors'] if a['id']==u['id']);assert u['state']==1 and u['attack_move'] is marching and u['marching'] is marching and distance(u['destination'],original['destination'])<=.01
    for u in pair(last,slot,warrior,siege_id):
        original=next(a for a in first['actors'] if a['id']==u['id']);assert distance([u['x'],u['y']],[original['x'],original['y']])>.5
    assert after==last
    return {'fighter_ids':selected,'warrior_id':warrior,'siege_id':siege_id,'native_speeds':{'warrior':55,'siege':30},'observed_game_seconds':last['time']-first['time'],'marching':marching}


def march_gates(folder,invocation,role,slot):
    gates={'march_extension_declared':invocation.get('cohesion_acceptance') is True and invocation.get('acceptance_profile')=='beta2-mobile' and invocation.get('input_mode')=='touch',
           'march_tool_identity_recorded':all(isinstance(invocation.get('march_tool_sha256',{}).get(name),str) and re.fullmatch('[a-f0-9]{64}',invocation['march_tool_sha256'][name]) for name in ('live_browser_march.cjs',)),
           'march_prior_paid_siege_and_fighter_gates':all(beta2_gates(folder,invocation,role,slot).values()),
           'march_paid_mixed_members_regrouped':False,'march_own_status_and_advance_observed':False,'march_ui_move_clears_status_and_advances':False,
           'march_no_foreign_field_with_visible_enemy_witness':False,'march_native_inputs_and_reviews_bound':False}
    try:
        terminal=json.loads((folder/f'{role}-terminal.json').read_text(encoding='utf-8'));match=terminal['matched']['match'];assert integer(match,1) and terminal['matched']['slot']==slot and terminal['ended']['match']==terminal['last']['match']==match
        rows=lines(folder/f'{role}-march-ui.jsonl');base=lines(folder/f'{role}-beta2-ui.jsonl');siege=derive_paid_siege(base,match,slot)
        full=lines(folder/f'{role}-authority-full.jsonl');wire=lines(folder/f'{role}-sent.jsonl');origins=lines(folder/f'{role}-command_origin.jsonl');inputs=lines(folder/f'{role}-browser-input.jsonl');captures=lines(folder/f'{role}-captures.jsonl');transport=lines(folder/f'{role}-transport.jsonl');pauses=lines(folder/'policy-pauses.jsonl');starts=lines(folder/'policy-starts.jsonl')
        foreign=[a for r in full if r['packet'].get('match')==match for a in r['packet']['actors'] if a['owner']!=slot]
        gates['march_no_foreign_field_with_visible_enemy_witness']=bool(foreign) and any(a['kind']=='unit' for a in foreign) and not any('marching' in a for a in foreign)
        prior={}
        for row in (r for r in rows if r.get('passed') is True and r.get('action') in ACTIONS):
            assert row['match']==row['before']['match']==row['after']['match']==match and row['slot']==slot and row['beta2_siege_birth']==siege['id'] and row['policy_held'] is True
            assert integer(row['started_unix'],1) and row['finished_unix']>=row['started_unix'] and integer(row['rejections_before']) and row['rejections_after']==row['rejections_before']
            for packet in [row['before'],row['after'],*row['series']]:assert any(r['packet']==packet and row['started_unix']-2000<=r['unix']<=row['finished_unix'] for r in full)
            actual=[r['packet'] for r in wire if row['started_unix']<=r['unix']<=row['finished_unix'] and r['packet'].get('op')=='command']
            assert actual==[r['packet'] for r in row['commands']] and row['evidence']==(row['commands'][0] if row['commands'] else None)
            assert len(actual)==(0 if row['action'] in ('warrior_birth','settled') else 1)
            for command in row['commands']:assert any(r.get('serial')==command['serial'] and r.get('packet')==command['packet'] and r.get('source')=='game_ui_or_engine' for r in origins)
            if row['action']=='move':
                sent=next(r for r in wire if r['packet']==row['evidence']['packet'])
                assert integer(row['command_prepared_unix'],1) and row['started_unix']<=row['command_prepared_unix']<=sent['unix'] and sent['unix']-row['command_prepared_unix']<=1000
                samples=[r for r in full if r['packet']['match']==match and r['packet']['tick']>=row['before']['tick'] and r['unix']<=sent['unix']]
                assert samples and sent['unix']-max(r['unix'] for r in samples)<=1000
                warrior=prior['warrior_birth']['verified']['warrior_id']
                assert all(u['marching'] is True for r in samples for u in pair(r['packet'],slot,warrior,siege['verified']['unit_id'])), 'Observed natural release before Move cannot be credited to its ground tap'
            assert [r['purpose'] for r in row['inputs']]==PURPOSES[row['action']]
            for item in row['inputs']:assert item in inputs and row['started_unix']<=item['unix']<=row['finished_unix'];native_tap(item)
            assert len(row['captures'])>=2
            for image in row['captures']:
                assert image in captures and Path(image['name']).name==image['name'] and row['started_unix']<=image['unix']<=row['finished_unix'];assert hashlib.sha256((folder/image['name']).read_bytes()).hexdigest()==image['sha256']
            earlier=[r for r in pauses if r['unix']<=row['started_unix']];assert earlier and len(earlier[-1]['reason'].strip())>=12 and not any(earlier[-1]['unix']<r['unix']<=row['finished_unix'] for r in starts)
            prior[row['action']]={**row,'verified':validate(row,prior,siege)}
        assert set(prior)==set(ACTIONS)
        for parent,child in zip(ACTIONS,ACTIONS[1:]):assert prior[child]['parent']==prior[parent]['id'] and prior[child]['started_unix']>=prior[parent]['finished_unix']
        first,last=prior['warrior_train']['started_unix'],prior['move']['finished_unix']
        commands=[r['packet'] for r in wire if first<=r['unix']<=last and r['packet'].get('op')=='command']
        assert commands==[prior[a]['evidence']['packet'] for a in ('warrior_train','regroup','attack','move')]
        assert not any(first<=r['unix']<=last and r.get('packet',{}).get('op')=='rejected' for r in transport)
        expected=[item for a in ACTIONS for item in prior[a]['inputs']];actual=[r for r in inputs if first<=r['unix']<=last];assert actual==expected
        assert len({r['id'] for r in expected})==len(expected) and all(a['dispatches'][-1]['acknowledged_unix']<=b['dispatches'][0]['started_unix'] for a,b in zip(expected,expected[1:]))
        gates['march_paid_mixed_members_regrouped']=True;gates['march_own_status_and_advance_observed']=True;gates['march_ui_move_clears_status_and_advances']=True
        review=next(r for r in reversed(rows) if r.get('action')=='review' and r.get('passed') is True and r.get('reviewed') is True)
        assert review['match']==match and review['slot']==slot and review['attempts']==[prior[a]['id'] for a in ACTIONS] and review['unix']>=last
        assert review['observed']['march_status']=='Group march' and review['observed']['move_cleared_status'] is True and review['observed']['mixed_fighters_visible'] is True
        selected=prior['attack']['verified']['fighter_ids'];count=sum(a.get('marching') is True for a in prior['attack']['after']['actors'] if a['id'] in selected)
        assert review['observed']['marching_fighters']==count and review['observed']['selected_fighters']==len(selected)
        assert ' '.join(review['observed']['march_status_text'].split())==f'Group march {count}/{len(selected)} fighters'
        gates['march_native_inputs_and_reviews_bound']=True
    except (AssertionError,KeyError,TypeError,ValueError,StopIteration,OSError):pass
    return gates
