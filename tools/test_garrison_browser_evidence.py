"""Synthetic paired retained-file gate tests; never a browser/game witness."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from test_march_browser_evidence import fixture as march_fixture
from test_beta2_browser_evidence import write
from garrison_browser_evidence import ACTIONS, PURPOSES, garrison_gates, clock_series


def fixture(folder, slot):
    files = {}
    for peer_slot in (0, 1):
        branch, invocation, _ = march_fixture(folder, peer_slot)
        for name, value in branch.items():
            if name not in files or name.startswith(('host-', 'guest-')):
                files[name] = value
            elif isinstance(value, list):
                files[name].extend(entry for entry in value if entry not in files[name])
    invocation.update(protocol=3, expected_protocol=3, garrison_acceptance=True, garrison_tool_sha256='d'*64)
    role = 'host' if slot == 0 else 'guest'
    other = 'guest' if role == 'host' else 'host'
    current = {peer: copy.deepcopy(files[peer+'-terminal.json']['last']) for peer in ('host', 'guest')}
    rows, prior = [], {}
    clock, serial = 600000, 100
    def add(name, row): files.setdefault(name, []).append(copy.deepcopy(row))
    def actor(packet, identity): return next(a for a in packet['actors'] if a['id'] == identity)
    for packet in current.values():
        packet.update(tick=1000, time=500)
        packet['site'] = {'state':0,'owner':-1,'capture':0,'timer':0,'hold':180,'clock_ticking':False,'garrison_paused':False,'neutralizing':False}
        for unit in packet['actors']:
            if unit.get('kind') == 'unit' and unit['owner'] in (0,1): unit.update(x=-800,y=1152)
    for action in ACTIONS:
        clock += 10000
        before = copy.deepcopy(current[role]);after = copy.deepcopy(before);after['tick'] += 1;after['time'] += .2
        command,series = None,[]
        if action == 'scout_move':
            command={'command':'move','ids':[13],'position':[0,1152]}
            actor(after,13).update(x=-790,state=1,attack_move=False,destination=[0,1152],path=[[-790,1152],[0,1152]])
        elif action == 'fighters_move':
            command={'command':'move','ids':[11,12,300,400],'position':[0,1152]}
            for identity in command['ids']:
                actor(after,identity).update(x=-790,state=1,attack_move=False,marching=False,destination=[0,1152],path=[[-790,1152],[0,1152]])
        else:
            for index in range(3):
                packet=copy.deepcopy(before);packet['tick']+=index+1;packet['time']+=1+index
                packet['site']={'state':2,'owner':slot,'capture':1,'timer':0 if action=='paused' else 1+index,'hold':180,'clock_ticking':action=='ticking','garrison_paused':action=='paused','neutralizing':False}
                actor(packet,13).update(x=0,y=1152,state=0,path=[])
                if action=='ticking':actor(packet,400).update(x=0,y=1152,state=0,path=[])
                opposite=copy.deepcopy(current[other]);opposite.update(tick=packet['tick'],time=packet['time'],site=copy.deepcopy(packet['site']))
                series.append({role:packet,other:opposite})
            after=series[-1][role]
        row={'id':'garrison-'+action,'action':action,'match':7,'slot':slot,'started_unix':clock,'finished_unix':clock+6000,'before':before,'after':after,'inputs':[],'captures':[],'series':series,'commands':[],'evidence':None,'passed':True,'policy_held':True,'parent':prior[ACTIONS[ACTIONS.index(action)-1]]['id'] if prior else None,'beta2_scout_birth':'scout_birth','rejections_before':{'host':0,'guest':0},'rejections_after':{'host':0,'guest':0}}
        if action == 'fighters_move':row['command_prepared_unix'] = clock + 100
        if command:
            serial+=1;command.update(op='command',match=7,sequence=serial);evidence={'source':'game_ui_or_engine','serial':serial,'packet':command};row['commands']=[evidence];row['evidence']=evidence
            add(role+'-sent.jsonl',{'unix':clock+1000,'packet':command});add(role+'-command_origin.jsonl',evidence)
        for index,purpose in enumerate(PURPOSES[action]):
            start=clock+100+index*50;item={'id':action+str(index),'unix':start+3,'kind':'tap','purpose':purpose,'x':50,'y':60,'native_api':'CDP.Input.dispatchTouchEvent','contact_id':0,'dispatches':[{'type':'touchStart','touchPoints':[{'id':0,'x':50,'y':60}],'started_unix':start,'acknowledged_unix':start+1,'acknowledged':True},{'type':'touchEnd','touchPoints':[],'started_unix':start+2,'acknowledged_unix':start+3,'acknowledged':True}]}
            row['inputs'].append(item);add(role+'-browser-input.jsonl',item)
        for peer in ('host','guest'):
            for index in range(2):
                name=peer+'-garrison-'+action+str(index)+'.png';payload=b'SYNTHETIC GARRISON PIXEL FIXTURE, NOT A SCREENSHOT';(folder/name).write_bytes(payload)
                image={'name':name,'sha256':hashlib.sha256(payload).hexdigest(),'unix':clock+50+index*5500};row['captures'].append({**image,'role':peer});add(peer+'-captures.jsonl',image)
        add(role+'-authority-full.jsonl',{'unix':clock+50,'packet':before});add(role+'-authority-full.jsonl',{'unix':clock+5500,'packet':after})
        for index,sample in enumerate(series):
            for peer,packet in sample.items():add(peer+'-authority-full.jsonl',{'unix':clock+3000+index*1000,'packet':packet})
        prior[action]=row;rows.append(row);current[role]=after
        if series:current[other]=series[-1][other]
    observed={}
    for mode in ('paused','ticking'):
        observed[mode]={}
        for peer in ('host','guest'):
            owner='You' if peer==role else 'Enemy'
            observed[mode][peer]={'title':('Held · bring a fighter' if peer==role else 'Enemy held · unguarded') if mode=='paused' else 'Sacred Site · tap to view','clock':owner+(' 3:00 paused' if mode=='paused' else ' win in 2:57')}
    rows.append({'id':'garrison-review','action':'review','match':7,'slot':slot,'unix':clock+7000,'passed':True,'reviewed':True,'attempts':[prior[a]['id'] for a in ACTIONS],'observed':observed})
    files[role+'-garrison-ui.jsonl']=rows
    for peer in ('host','guest'):files[peer+'-terminal.json']['last']=current[peer]
    return files,invocation,role


class GarrisonEvidenceTests(unittest.TestCase):
    def test_valid_whole_bundle_both_remapped_slots(self):
        for slot in (0,1):
            with tempfile.TemporaryDirectory() as tmp:
                folder=Path(tmp);files,invocation,role=fixture(folder,slot);write(folder,files)
                gates=garrison_gates(folder,invocation,role,slot);self.assertTrue(all(gates.values()),gates)

    def test_wrong_receipt_identity_flags_order_and_clock_fail(self):
        for slot in (0,1):
            with tempfile.TemporaryDirectory() as tmp:
                folder=Path(tmp);baseline,invocation,role=fixture(folder,slot)
                def row(files,action):return next(r for r in files[role+'-garrison-ui.jsonl'] if r['action']==action)
                mutations=[lambda f:row(f,'paused').__setitem__('match',99),lambda f:row(f,'paused')['series'][1][role]['site'].__setitem__('timer',1),lambda f:row(f,'ticking')['series'][1][role]['site'].__setitem__('clock_ticking',1),lambda f:row(f,'scout_move')['evidence']['packet'].__setitem__('ids',[900]),lambda f:row(f,'fighters_move')['inputs'][0]['dispatches'][1].__setitem__('acknowledged',False),lambda f:row(f,'review')['observed']['paused'][role].__setitem__('clock','You 2:00 paused'),lambda f:f[('guest' if role=='host' else 'host')+'-sent.jsonl'].append({'unix':row(f,'paused')['started_unix']+500,'packet':{'op':'command','command':'move'}}),lambda f:f['policy-starts.jsonl'].append({'unix':row(f,'ticking')['started_unix']+500,'reason':'Premature policy restart'}),lambda f:row(f,'paused')['series'][0][role]['actors'].append({'id':999,'kind':'unit','owner':slot,'type':1,'hp':60,'state':0,'x':0,'y':1152})]
                for mutate in mutations:
                    files=copy.deepcopy(baseline);mutate(files);write(folder,files);self.assertFalse(all(garrison_gates(folder,invocation,role,slot).values()))

    def test_matching_raw_frozen_clock_mutation_still_fails(self):
        for slot in (0,1):
            with tempfile.TemporaryDirectory() as tmp:
                folder=Path(tmp);files,invocation,role=fixture(folder,slot)
                def change(value):
                    if isinstance(value,dict):
                        if value.get('clock_ticking') is True:value['timer']=3
                        for child in value.values():change(child)
                    elif isinstance(value,list):
                        for child in value:change(child)
                change(files);write(folder,files);self.assertFalse(all(garrison_gates(folder,invocation,role,slot).values()))

    def test_omitted_raw_timer_occupant_and_precommand_entry_reject(self):
        for slot in (0, 1):
            with tempfile.TemporaryDirectory() as tmp:
                folder=Path(tmp);baseline,invocation,role=fixture(folder,slot)
                for kind in ('timer', 'occupant', 'precommand'):
                    files=copy.deepcopy(baseline)
                    action='fighters_move' if kind=='precommand' else 'paused'
                    row=next(r for r in files[role+'-garrison-ui.jsonl'] if r['action']==action)
                    packet=copy.deepcopy(row['before'] if kind=='precommand' else row['series'][1][role])
                    if kind=='precommand':packet['tick']+=1;packet['time']+=.1
                    if kind=='timer':packet['site']['timer']+=1
                    else:next(a for a in packet['actors'] if a['type']==1 and a['owner']==slot).update(x=0,y=1152)
                    files[role+'-authority-full.jsonl'].append({'unix':row['started_unix']+(900 if kind=='precommand' else 4000),'packet':packet})
                    write(folder,files);self.assertFalse(all(garrison_gates(folder,invocation,role,slot).values()),kind)

    def test_required_extension_cannot_be_omitted(self):
        from analyze_live_browser_multiplayer import analyze
        with tempfile.TemporaryDirectory() as tmp:
            report=analyze(Path(tmp),require_garrison=True)
            self.assertIn('required paired garrison acceptance missing',report['failures'])

    def test_unrelated_garrison_cannot_replace_the_verified_paid_march_member(self):
        for slot in (0, 1):
            with tempfile.TemporaryDirectory() as tmp:
                folder=Path(tmp);files,invocation,role=fixture(folder,slot)
                def change(value):
                    if isinstance(value,dict):
                        if value.get('site',{}).get('clock_ticking') is True and 'actors' in value:
                            for unit in value['actors']:
                                if unit.get('owner')==slot and unit['id'] in (400,11):unit['x']=-800 if unit['id']==400 else 0
                        for child in value.values():change(child)
                    elif isinstance(value,list):
                        for child in value:change(child)
                change(files)
                for row in files[role+'-march-ui.jsonl']:
                    if row['action']=='warrior_birth':row['proof']['warrior_id']=11
                write(folder,files);self.assertFalse(all(garrison_gates(folder,invocation,role,slot).values()))


if __name__=='__main__':unittest.main()
