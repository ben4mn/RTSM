"""Synthetic full-receipt proofs. No Chromium, Godot, or gameplay is launched."""
import copy,hashlib,json,tempfile,unittest
from pathlib import Path
from test_beta2_browser_evidence import fixture as base_fixture,write
from march_browser_evidence import ACTIONS,PURPOSES,march_gates,validate,derive_paid_siege


def fixture(folder,slot):
    files,invocation,role=base_fixture(folder,slot)
    def add_barracks(value):
        if isinstance(value,dict):
            if 'actors' in value and 'match' in value and not any(a['id']==201 for a in value['actors']):
                value['actors'].append({'id':201,'kind':'building','owner':slot,'type':2,'state':2,'hp':100,'queue':{'items':[],'repeat':False}})
            for child in value.values():add_barracks(child)
        elif isinstance(value,list):
            for child in value:add_barracks(child)
    add_barracks(files)
    invocation.update(cohesion_acceptance=True,march_tool_sha256={'live_browser_march.cjs':'c'*64})
    prior={};rows=[];clock=300000;serial=20;current=copy.deepcopy(files[role+'-terminal.json']['last'])
    siege=derive_paid_siege(files[role+'-beta2-ui.jsonl'],7,slot)
    def add(name,row):files.setdefault(name,[]).append(copy.deepcopy(row))
    def actor(packet,identity):return next(a for a in packet['actors'] if a['id']==identity)
    fighter_ids=[11,12,300,400]
    destinations={11:[-640,1152],12:[-608,1168],300:[-672,1168],400:[-640,1184]}
    for action in ACTIONS:
        clock+=10000;before=copy.deepcopy(current);after=copy.deepcopy(before);after['tick']+=1;after['time']+=.2;command=None;series=[]
        if action=='warrior_train':
            command={'command':'train','target':201,'type':1};after['bank']['food']-=50;after['bank']['wood']-=20;after['player']['population_reserved']+=1;actor(after,201)['queue']={'items':[1],'repeat':False,'training':True,'time':10}
        elif action=='warrior_birth':
            after['time']+=10;after['player']['population_reserved']-=1;after['player']['population']+=1;actor(after,201)['queue']={'items':[],'repeat':False}
            after['actors'].append({'id':400,'kind':'unit','owner':slot,'type':1,'hp':60,'state':0,'x':-1400,'y':1152,'destination':[-1400,1152],'path':[],'attack_move':False,'marching':False})
        elif action=='regroup':
            command={'command':'move','ids':fighter_ids,'position':[-640,1152]}
            for identity in fighter_ids:
                unit=actor(after,identity);unit['x']+=5;unit.update(state=1,attack_move=False,marching=False,destination=destinations[identity],path=[[unit['x'],unit['y']],destinations[identity]])
        elif action=='settled':
            after['time']+=40
            for identity in fighter_ids:
                unit=actor(after,identity);unit.update(state=0,x=unit['destination'][0],y=unit['destination'][1],path=[])
        elif action in ('attack','move'):
            marching=action=='attack';command={'command':'attack_move' if marching else 'move','ids':fighter_ids,'position':[256,1152] if marching else [-1024,1152]}
            for index in range(3):
                packet=copy.deepcopy(before);packet['tick']+=index+1;packet['time']+=.2+.6*index
                for identity in fighter_ids:
                    unit=actor(packet,identity);unit['x']+=(1 if marching else -1)*(5+18*index);destination=[command['position'][0]+destinations[identity][0]+640,destinations[identity][1]]
                    unit.update(state=1,attack_move=marching,marching=marching,destination=destination,path=[[unit['x'],unit['y']],destination])
                series.append(packet)
            after=series[-1]
        row={'id':'march-'+action,'action':action,'match':7,'slot':slot,'started_unix':clock,'finished_unix':clock+3000,'before':before,'after':after,'commands':[],'evidence':None,'inputs':[],'captures':[],'series':series,'passed':True,'policy_held':True,'rejections_before':0,'rejections_after':0,'beta2_siege_birth':siege['id']}
        if action=='move':row['command_prepared_unix']=clock+140
        if prior:row['parent']=prior[ACTIONS[ACTIONS.index(action)-1]]['id']
        if command:
            serial+=1;command.update(op='command',match=7,sequence=serial);evidence={'source':'game_ui_or_engine','serial':serial,'packet':command};row['commands']=[evidence];row['evidence']=evidence
            add(role+'-sent.jsonl',{'unix':clock+500,'packet':command});add(role+'-command_origin.jsonl',evidence)
        for index,purpose in enumerate(PURPOSES[action]):
            start=clock+100+index*50;item={'id':'march-'+action+str(index),'unix':start+3,'kind':'tap','purpose':purpose,'x':50,'y':60,'native_api':'CDP.Input.dispatchTouchEvent','contact_id':0,'dispatches':[
                {'type':'touchStart','touchPoints':[{'id':0,'x':50,'y':60}],'started_unix':start,'acknowledged_unix':start+1,'acknowledged':True},
                {'type':'touchEnd','touchPoints':[],'started_unix':start+2,'acknowledged_unix':start+3,'acknowledged':True}]}
            row['inputs'].append(item);add(role+'-browser-input.jsonl',item)
        for index in range(2):
            name='march-'+action+str(index)+'.png';payload=b'SYNTHETIC MARCH PIXEL FIXTURE; NOT A SCREENSHOT';(folder/name).write_bytes(payload)
            image={'name':name,'sha256':hashlib.sha256(payload).hexdigest(),'unix':clock+50+index*2700};row['captures'].append(image);add(role+'-captures.jsonl',image)
        for index,packet in enumerate([before,after,*series]):add(role+'-authority-full.jsonl',{'unix':clock+125 if index==0 else clock+600+index*100,'packet':packet})
        row['verified']=validate(row,prior,siege);row['proof']=row['verified'];prior[action]=row;rows.append(row);current=after
    rows.append({'id':'march-review','action':'review','match':7,'slot':slot,'unix':clock+4000,'passed':True,'reviewed':True,'attempts':[prior[a]['id'] for a in ACTIONS],'observed':{'march_status':'Group march','march_status_text':'Group march\n4/4 fighters','marching_fighters':4,'selected_fighters':4,'move_cleared_status':True,'mixed_fighters_visible':True}})
    files[role+'-march-ui.jsonl']=rows;files[role+'-terminal.json']['last']=current
    return files,invocation,role


class MarchEvidenceTests(unittest.TestCase):
    def test_whole_paid_march_and_move_receipt_both_slots(self):
        for slot in (0,1):
            with tempfile.TemporaryDirectory() as tmp:
                folder=Path(tmp);files,invocation,role=fixture(folder,slot);write(folder,files)
                gates=march_gates(folder,invocation,role,slot);self.assertTrue(all(gates.values()),gates)

    def test_privacy_is_nonvacuous_and_rejects_even_false_enemy_field(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);files,invocation,role=fixture(folder,0)
            leaked=copy.deepcopy(files)
            # Select the actual foreign actor rather than relying on roster ordering.
            for actor in leaked[role+'-authority-full.jsonl'][0]['packet']['actors']:
                if actor['owner']==1:actor['marching']=False
            write(folder,leaked);self.assertFalse(march_gates(folder,invocation,role,0)['march_no_foreign_field_with_visible_enemy_witness'])
            absent=copy.deepcopy(files)
            for row in absent[role+'-authority-full.jsonl']:row['packet']['actors']=[a for a in row['packet']['actors'] if a['owner']==0]
            foreign_old={'match':99,'tick':1,'actors':[{'id':9999,'owner':1,'kind':'unit','type':1}]}
            absent[role+'-authority-full.jsonl'].append({'unix':1,'packet':foreign_old})
            write(folder,absent);self.assertFalse(march_gates(folder,invocation,role,0)['march_no_foreign_field_with_visible_enemy_witness'])

    def test_stale_match_unpaid_pair_missing_release_and_hidden_orders_fail(self):
        for slot in (0,1):
            with tempfile.TemporaryDirectory() as tmp:
                folder=Path(tmp);baseline,invocation,role=fixture(folder,slot)
                def row(files,action):return next(r for r in files[role+'-march-ui.jsonl'] if r['action']==action)
                mutations=[lambda f:row(f,'attack').__setitem__('match',99),lambda f:row(f,'move')['series'][1]['actors'].append({'id':999,'kind':'unit','type':1,'owner':slot,'hp':10,'state':0}),
                    lambda f:row(f,'attack')['series'][1]['actors'][-1].__setitem__('marching',False),lambda f:row(f,'warrior_train')['after']['bank'].__setitem__('food',9999),
                    lambda f:row(f,'regroup')['inputs'][0]['dispatches'][1].__setitem__('acknowledged',False),lambda f:row(f,'review')['observed'].__setitem__('move_cleared_status',False),
                    lambda f:f[role+'-sent.jsonl'].append({'unix':row(f,'attack')['finished_unix']+1,'packet':{'op':'command','command':'move','match':7,'ids':[300]}}),
                    lambda f:f[role+'-browser-input.jsonl'].append({'unix':row(f,'settled')['finished_unix']+1,'kind':'tap','purpose':'hidden correction'}),
                    lambda f:f['policy-starts.jsonl'].append({'unix':row(f,'attack')['started_unix']+1,'reason':'Restart ordinary paid policy'}),
                    lambda f:f[role+'-beta2-ui.jsonl'].clear()]
                for mutate in mutations:
                    files=copy.deepcopy(baseline);mutate(files);write(folder,files);self.assertFalse(all(march_gates(folder,invocation,role,slot).values()))

    def test_required_extension_cannot_be_omitted(self):
        from analyze_live_browser_multiplayer import analyze
        with tempfile.TemporaryDirectory() as tmp:
            report=analyze(Path(tmp),require_cohesion=True);self.assertFalse(report['passed']);self.assertIn('required paired cohesion acceptance missing',report['failures'])

    def test_observed_release_before_ground_wire_cannot_be_credited_to_move(self):
        for slot in (0,1):
            with tempfile.TemporaryDirectory() as tmp:
                folder=Path(tmp);files,invocation,role=fixture(folder,slot)
                move=next(r for r in files[role+'-march-ui.jsonl'] if r['action']=='move')
                sent=next(r for r in files[role+'-sent.jsonl'] if r['packet']==move['evidence']['packet'])
                released=copy.deepcopy(move['before']);released['tick']+=1;released['time']+=.1
                for actor in released['actors']:
                    if actor['id'] in (300,400):actor['marching']=False
                files[role+'-authority-full.jsonl'].append({'unix':sent['unix']-1,'packet':released})
                write(folder,files);self.assertFalse(all(march_gates(folder,invocation,role,slot).values()))

    def test_recorded_siege_summary_is_not_an_identity_bridge(self):
        for slot in (0,1):
            with tempfile.TemporaryDirectory() as tmp:
                files,_,role=fixture(Path(tmp),slot);base=files[role+'-beta2-ui.jsonl']
                next(r for r in base if r['action']=='siege_birth')['proof']['unit_id']=301
                self.assertEqual(derive_paid_siege(base,7,slot)['verified']['unit_id'],300)

    def test_status_review_requires_actual_owned_marcher_and_selection_counts(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);files,invocation,role=fixture(folder,0)
            review=files[role+'-march-ui.jsonl'][-1];review['observed'].update(marching_fighters=3,march_status_text='Group march3/4 fighters')
            write(folder,files);self.assertFalse(march_gates(folder,invocation,role,0)['march_native_inputs_and_reviews_bound'])


if __name__=='__main__':unittest.main()
