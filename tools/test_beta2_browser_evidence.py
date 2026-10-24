"""Synthetic retained-file counterexamples, not a browser playthrough."""
import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from beta2_browser_evidence import ACTIONS, PURPOSES, beta2_gates, validate_fact, native_tap


def fixture(folder, slot):
    files={}; role='host' if slot==0 else 'guest'; clock=100000
    def add(name,row): files.setdefault(name,[]).append(copy.deepcopy(row))
    def packet():
        return {'match':7,'tick':1,'time':10,'bank':{'food':1000,'wood':1000,'gold':1000},'stats':{'resources_gathered':1000},'player':{'age':3,'population':3,'population_reserved':0,'population_cap':30},'actors':[
            {'id':100,'kind':'building','owner':slot,'type':0,'state':2,'hp':100,'queue':{'items':[],'repeat':False}},
            *[{'id':i,'kind':'unit','owner':slot,'type':t,'state':0,'hp':100,'x':x,'y':1152,'destination':[x,1152],'attack_move':False,'path':[]} for i,t,x in [(10,0,-1700),(11,1,-1600),(12,2,-1550)]],
            {'id':900,'kind':'unit','owner':1-slot,'type':1,'state':0,'hp':100,'x':0,'y':1000}]}
    current=packet(); rows=[]; prior={}; serial=0
    def actor(p,identity):return next(a for a in p['actors'] if a['id']==identity)
    for action in ACTIONS:
        clock+=10000; before=copy.deepcopy(current); after=copy.deepcopy(before);after['tick']+=1;after['time']+=.5
        command=None; parent=None
        if action in ('scout_train','siege_train'):
            siege=action=='siege_train';kind,target,pop,duration=(5,200,3,25) if siege else (4,100,1,8)
            command={'command':'train','type':kind,'target':target}
            after['bank']['food']-=0 if siege else 40;after['bank']['wood']-=150 if siege else 0;after['bank']['gold']-=100 if siege else 10
            after['player']['population_reserved']+=pop;actor(after,target)['queue']={'items':[kind],'repeat':False,'training':True,'time':duration}
            parent=prior['workshop_complete']['id'] if siege else None
        elif action in ('scout_birth','siege_birth'):
            siege=action=='siege_birth';kind,target,identity,pop,duration=(5,200,300,3,25) if siege else (4,100,13,1,8)
            after['time']+=duration;after['player']['population_reserved']-=pop;after['player']['population']+=pop;actor(after,target)['queue']={'items':[],'repeat':False}
            after['actors'].append({'id':identity,'kind':'unit','owner':slot,'type':kind,'state':0,'hp':100,'x':-1000 if kind==4 else -1500,'y':1152,'destination':[640,1152],'attack_move':False,'path':[]})
            parent=prior['siege_train' if siege else 'scout_train']['id']
        elif action=='workshop_place':
            command={'command':'place','type':8,'ids':[10],'position':[256,128]};after['bank']['wood']-=300;after['bank']['gold']-=100
            after['actors'].append({'id':200,'kind':'building','owner':slot,'type':8,'state':1,'progress':.001,'hp':100,'x':256,'y':128,'queue':{'items':[],'repeat':False}});parent=prior['workshop_open']['id']
        elif action=='workshop_complete':
            after['time']+=28;actor(after,200).update(state=2,progress=1);parent=prior['workshop_place']['id']
        elif action=='scout_move':
            command={'command':'move','ids':[13],'position':[768,1152]};actor(after,13).update(state=1,x=-990,destination=[768,1152],path=[[-990,1152],[768,1152]])
            parent=prior['scout_birth']['id']
        elif action in ('fighter_select','fighter_find'):
            actor(after,13)['x']+=10;parent=prior['scout_move' if action=='fighter_select' else 'fighter_select']['id']
        elif action=='fighter_attack':
            command={'command':'attack_move','ids':[11,12,300],'position':[0,1152]};actor(after,13)['x']+=50
            for identity in (11,12,300):
                unit=actor(after,identity);unit['x']+=10;unit.update(state=1,attack_move=True,destination=[0,1152],path=[[unit['x'],1152],[0,1152]])
            parent=prior['fighter_find']['id']
        row={'id':action,'action':action,'match':7,'slot':slot,'started_unix':clock,'finished_unix':clock+900,'start_serial':serial,'before':before,'after':after,'passed':True,'policy_held':True,'rejections_before':0,'rejections_after':0,'commands':[],'inputs':[],'captures':[],'parent':parent,'evidence':None}
        if command:
            serial+=1;command.update(op='command',match=7,sequence=serial);evidence={'source':'game_ui_or_engine','serial':serial,'packet':command};row['commands']=[evidence];row['evidence']=evidence
            add(role+'-sent.jsonl',{'unix':clock+400,'packet':command});add(role+'-command_origin.jsonl',evidence)
        if action=='fighter_attack':row['recon']=prior['scout_move']['id']
        for index,purpose in enumerate(PURPOSES[action]):
            start=clock+100+index*50;item={'id':action+str(index),'unix':start+3,'kind':'tap','purpose':purpose,'x':50,'y':60,'native_api':'CDP.Input.dispatchTouchEvent','contact_id':0,'dispatches':[
                {'type':'touchStart','touchPoints':[{'id':0,'x':50,'y':60}],'started_unix':start,'acknowledged_unix':start+1,'acknowledged':True},
                {'type':'touchEnd','touchPoints':[],'started_unix':start+2,'acknowledged_unix':start+3,'acknowledged':True}]}
            row['inputs'].append(item);add(role+'-browser-input.jsonl',item)
        for index in range(2):
            name=action+str(index)+'.png';payload=b'SYNTHETIC IMAGE FIXTURE, NOT A SCREENSHOT';(folder/name).write_bytes(payload)
            image={'name':name,'sha256':hashlib.sha256(payload).hexdigest(),'unix':clock+50+index*800};row['captures'].append(image);add(role+'-captures.jsonl',image)
        for p,when in ((before,clock),(after,clock+500)):add(role+'-authority-full.jsonl',{'unix':when,'packet':p})
        row['verified']=validate_fact(row,prior);prior[action]=row;row['proof']=row['verified'];rows.append(row);current=after
    rows.append({'id':'review','action':'review','match':7,'passed':True,'reviewed':True,'slot':slot,'unix':clock+1000,'attempts':[prior[a]['id'] for a in ACTIONS],'observed':{'workshop':'Siege Workshop','workshop_cost':{'wood':300,'gold':100},'siege':'Siege Engine','siege_cost':{'wood':150,'gold':100},'queue_count':1,'population_before':4,'population_queued':7,'scout':'Scout','scout_cost':{'food':40,'gold':10},'select_caption':'Select fighters','fighter_count':3,'find_frames_fighters':True,'scout_excluded_from_selection':True}})
    files[role+'-terminal.json']={'matched':{'match':7,'slot':slot},'ended':{'match':7},'last':current}
    files[role+'-beta2-ui.jsonl']=rows
    files['policy-starts.jsonl']=[{'unix':1,'reason':'Start ordinary paid gathering policy'}]
    files['policy-pauses.jsonl']=[{'unix':2,'reason':'Hold both scripts for native UI purchase and route proof'}]
    files['beta2-policy-phases.jsonl']=[{'unix':1,'role':role,'phase':'saving-for-touch-workshop-and-siege'}]
    invocation={'acceptance_profile':'beta2-mobile','protocol':2,'input_mode':'touch','scenario':'full','beta2_tool_sha256':{'live_browser_beta2_ui.cjs':'a'*64,'live_browser_beta2_receipts.cjs':'b'*64}}
    return files,invocation,role


def write(folder,files):
    for name,rows in files.items():(folder/name).write_text(json.dumps(rows) if name.endswith('.json') else ''.join(json.dumps(row)+'\n' for row in rows))


class EvidenceTests(unittest.TestCase):
    def test_positive_both_remapped_slots(self):
        for slot in (0,1):
            with tempfile.TemporaryDirectory() as tmp:
                folder=Path(tmp);files,invocation,role=fixture(folder,slot);write(folder,files)
                self.assertTrue(all(beta2_gates(folder,invocation,role,slot).values()))

    def test_fail_closed_mutations(self):
        for slot in (0,1):
            with tempfile.TemporaryDirectory() as tmp:
                folder=Path(tmp);baseline,invocation,role=fixture(folder,slot)
                def row(files,action):return next(r for r in files[role+'-beta2-ui.jsonl'] if r['action']==action)
                mutations=[
                    lambda f:row(f,'siege_train')['after']['bank'].__setitem__('wood',9999),
                    lambda f:row(f,'siege_train')['after']['player'].__setitem__('population_reserved',2),
                    lambda f:row(f,'workshop_place').__setitem__('slot',1-slot),
                    lambda f:row(f,'scout_move')['evidence']['packet'].__setitem__('position',[-999999,-999999]),
                    lambda f:row(f,'fighter_attack')['evidence']['packet'].__setitem__('ids',[11,12,300,13]),
                    lambda f:row(f,'fighter_attack')['after']['actors'][1].__setitem__('owner',1-slot),
                    lambda f:f[role+'-authority-full.jsonl'].clear(),
                    lambda f:f[role+'-command_origin.jsonl'].clear(),
                    lambda f:f[role+'-sent.jsonl'].append({'unix':row(f,'siege_train')['finished_unix']+1,'packet':{'op':'command','command':'allocate'}}),
                    lambda f:f[role+'-transport.jsonl'].append({'unix':row(f,'fighter_attack')['started_unix']+500,'packet':{'op':'rejected','reason':'Outside map'}}),
                    lambda f:row(f,'fighter_find')['inputs'][0]['dispatches'][0]['touchPoints'][0].__setitem__('id',12),
                    lambda f:row(f,'workshop_open')['inputs'][0]['dispatches'][1].__setitem__('acknowledged',False),
                    lambda f:row(f,'review')['observed'].__setitem__('find_frames_fighters',False),
                    lambda f:f['policy-pauses.jsonl'].clear(),
                    lambda f:f['policy-starts.jsonl'].append({'unix':row(f,'siege_train')['started_unix']+1,'reason':'Unannounced concurrent resumption'}),
                ]
                for mutate in mutations:
                    files=copy.deepcopy(baseline);files.setdefault(role+'-transport.jsonl',[]);mutate(files);write(folder,files)
                    self.assertFalse(all(beta2_gates(folder,invocation,role,slot).values()),mutate)

    def test_missing_profile_or_tool_digest_never_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);files,invocation,role=fixture(folder,0);write(folder,files)
            for key in ('acceptance_profile','protocol','beta2_tool_sha256'):
                bad=copy.deepcopy(invocation);bad.pop(key)
                self.assertFalse(all(beta2_gates(folder,bad,role,0).values()))

    def test_independent_payment_checks_resource_substitution_even_with_consistent_raw_logs(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);files,_,role=fixture(folder,0);rows=files[role+'-beta2-ui.jsonl'];prior={}
            for row in rows:
                if row['action']=='workshop_place':
                    bad=copy.deepcopy(row);bad['after']['bank']['wood']+=50;bad['after']['bank']['gold']-=50
                    with self.assertRaises(AssertionError):validate_fact(bad,prior)
                    return
                if row['action'] in ACTIONS:prior[row['action']]={**row,'verified':validate_fact(row,prior)}

    def test_native_contact_requires_completed_start_end_and_reused_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            files,_,role=fixture(Path(tmp),0);good=files[role+'-browser-input.jsonl'][0]
            self.assertTrue(native_tap(good))
            for mutate in (lambda r:r['dispatches'][0]['touchPoints'][0].__setitem__('id',1),lambda r:r['dispatches'][1].__setitem__('acknowledged',False),lambda r:r['dispatches'][1].__setitem__('touchPoints',[{'id':0}]),lambda r:r.__setitem__('native_api','synthetic DOM dispatch')):
                bad=copy.deepcopy(good);mutate(bad)
                with self.assertRaises(AssertionError):native_tap(bad)

    def test_required_analyzer_profile_cannot_fall_back_to_legacy(self):
        from analyze_live_browser_multiplayer import analyze
        with tempfile.TemporaryDirectory() as tmp:
            report=analyze(Path(tmp),require_beta2=True)
            self.assertFalse(report['passed'])
            self.assertIn('required beta2 mobile acceptance profile missing',report['failures'])
            for role in ('host','guest'):self.assertFalse(report['clients'][role]['gates']['beta2_profile_declared'])

    def test_prior_match_bundle_and_split_branch_cannot_prove_current_terminal(self):
        for slot in (0,1):
            with tempfile.TemporaryDirectory() as tmp:
                folder=Path(tmp);files,invocation,role=fixture(folder,slot)
                stale=copy.deepcopy(files)
                for field in ('matched','ended','last'):stale[role+'-terminal.json'][field]['match']=99
                write(folder,stale)
                self.assertFalse(all(beta2_gates(folder,invocation,role,slot).values()))
                mixed=copy.deepcopy(files)
                for row in mixed[role+'-beta2-ui.jsonl']:
                    if row['action'].startswith('scout_'):
                        row['match']=99;row['before']['match']=99;row['after']['match']=99
                        if row['evidence']:row['evidence']['packet']['match']=99
                write(folder,mixed)
                self.assertFalse(all(beta2_gates(folder,invocation,role,slot).values()))


if __name__=='__main__':unittest.main()
