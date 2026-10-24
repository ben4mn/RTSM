'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {CONTRACT, workshopPlacement, workshopCompletion, siegeRecruitment, siegeBirth, scoutMove, fighterSelection} = require('./live_browser_beta2_receipts.cjs');

function fixture(slot) {
  const unit = (id, type, x = 0, owner = slot) => ({id, type, kind: 'unit', owner, x, y: 0, hp: 100, state: 0});
  const empty = () => ({repeat: false, items: [], training: false, time: 0});
  const before = {match: 7, tick: 10, time: 10, bank: {food: 1000, wood: 1000, gold: 1000}, stats: {resources_gathered: 1000}, player: {age: 3, population: 4, population_reserved: 0, population_cap: 30}, actors: [{id: 100, type: 0, kind: 'building', owner: slot, state: 2, queue: empty()}, unit(10, 0), unit(11, 1), unit(12, 2, 50), {...unit(13, 4, 1000), state: 1, destination: [3000, 0], attack_move: false, path: [[1000, 0], [3000, 0]]}, unit(900, 1, 300, 1 - slot)]};
  const command = (operation, extra = {}) => ({source: 'game_ui_or_engine', serial: 1, packet: {op: 'command', command: operation, match: 7, sequence: 1, ...extra}});
  const place = command('place', {type: 8, ids: [10], position: [256, 128]});
  const foundation = structuredClone(before); foundation.tick++; foundation.time += 0.2; foundation.bank.wood -= 300; foundation.bank.gold -= 100;
  foundation.actors.push({id: 200, type: 8, kind: 'building', owner: slot, state: 1, hp: 100, progress: 0.001, x: 256, y: 128, queue: empty()});
  const completed = structuredClone(foundation); completed.tick += 28; completed.time += 28; Object.assign(completed.actors.at(-1), {state: 2, progress: 1});
  const train = command('train', {type: 5, target: 200});
  const queued = structuredClone(completed); queued.tick++; queued.time += 0.2; queued.bank.wood -= 150; queued.bank.gold -= 100; queued.player.population_reserved = 3;
  queued.actors.at(-1).queue = {repeat: false, items: [5], training: true, time: 25, progress: 0.1};
  const born = structuredClone(queued); born.tick += 25; born.time += 25; born.player.population_reserved = 0; born.player.population += 3; born.actors.at(-1).queue = empty(); born.actors.push(unit(300, 5, 260));
  return {slot, before, place, foundation, completed, train, queued, born};
}

for (const slot of [0, 1]) {
  test(`slot${slot}: actual authority Workshop payment, labor, Siege queue and three-pop birth`, () => {
    const f = fixture(slot);
    assert.equal(workshopPlacement(f.before, f.foundation, slot, f.place).building_id, 200);
    assert(Math.abs(workshopCompletion(f.foundation, f.completed, slot, 200).elapsed_game_seconds - 28) < 1e-9);
    assert.equal(siegeRecruitment(f.completed, f.queued, slot, f.train, 200).population_cost, 3);
    assert.equal(siegeBirth(f.completed, f.queued, f.born, slot, 200).unit_id, 300);
  });
  test(`slot${slot}: payment proof rejects wrong owner/origin/cost/foundation and concurrent production`, () => {
    const f = fixture(slot);
    assert.throws(() => workshopPlacement(f.before, f.foundation, 1 - slot, f.place));
    assert.throws(() => workshopPlacement(f.before, f.foundation, slot, {...f.place, source: 'paid_policy'}));
    for (const mutate of [x => x.bank.food--, x => {x.bank.wood += 50; x.bank.gold -= 50;}, x => x.actors.at(-1).owner = 1 - slot, x => x.actors.at(-1).state = 2, x => x.actors.at(-1).x++, x => x.actors.at(-1).id = 100, x => x.actors[0].queue.items = [0], x => x.tick = 10, x => x.match = 8, x => x.time += 10]) {
      const bad = structuredClone(f.foundation); mutate(bad); assert.throws(() => workshopPlacement(f.before, bad, slot, f.place));
    }
    const deposit = structuredClone(f.foundation); deposit.bank.food += 3; deposit.bank.wood += 4; deposit.bank.gold += 2; deposit.stats.resources_gathered += 9;
    assert.deepEqual(workshopPlacement(f.before, deposit, slot, f.place).normal_deposits_by_resource, {food: 3, wood: 4, gold: 2});
    const poor = structuredClone(f.before); poor.stats.resources_gathered = 0;
    assert.throws(() => workshopPlacement(poor, f.foundation, slot, f.place));
  });
  test(`slot${slot}: Siege queue and birth reject missing/forged reservations, early/free/foreign units`, () => {
    const f = fixture(slot);
    for (const mutate of [x => x.player.population_reserved = 2, x => x.player.population++, x => x.actors.at(-1).queue.items = [], x => x.actors.at(-1).queue.repeat = true, x => x.actors.at(-1).queue.time = 1, x => x.actors.at(-1).owner = 1 - slot, x => {x.bank.wood += 50; x.bank.gold -= 50;}]) {
      const bad = structuredClone(f.queued); mutate(bad); assert.throws(() => siegeRecruitment(f.completed, bad, slot, f.train, 200));
    }
    for (const mutate of [x => x.player.population_reserved = 3, x => x.player.population--, x => x.time = f.queued.time + 1, x => x.actors.at(-1).owner = 1 - slot, x => x.actors.at(-1).type = 3, x => x.actors.at(-1).id = 11, x => x.actors.splice(1, 1), x => x.actors.find(a => a.id === 200).queue.items = [5]]) {
      const bad = structuredClone(f.born); mutate(bad); assert.throws(() => siegeBirth(f.completed, f.queued, bad, slot, 200));
    }
    const early = structuredClone(f.completed); early.time = f.foundation.time + 1;
    assert.throws(() => workshopCompletion(f.foundation, early, slot, 200));
  });
  test(`slot${slot}: fighter command IDs exclude separated Scout while its accepted recon route advances`, () => {
    const f = fixture(slot);
    for (const unit of f.before.actors.filter(a => a.kind === 'unit' && a.owner === slot)) {unit.x = unit.id === 13 ? -1000 : -1700 + (unit.id - 10) * 50; unit.y = 1152;}
    f.before.actors.find(a => a.id === 13).destination = [640, 1152];
    const moved = structuredClone(f.before); moved.tick++; moved.time += 0.2;
    Object.assign(moved.actors.find(a => a.id === 13), {x: -990, destination: [768, 1152], path: [[-990, 1152], [768, 1152]]});
    const move = {source: 'game_ui_or_engine', serial: 2, packet: {op: 'command', command: 'move', match: 7, sequence: 2, ids: [13], position: [768, 1152]}};
    const recon = scoutMove(f.before, moved, slot, move);
    const after = structuredClone(moved); after.tick++; after.time++; after.actors.find(a => a.id === 13).x += 100;
    for (const id of [11, 12]) {const unit = after.actors.find(a => a.id === id);unit.x+=10;Object.assign(unit, {state: 1, attack_move: true, destination: [0, 1152], path: [[unit.x, unit.y], [0, 1152]]});}
    const attack = {source: 'game_ui_or_engine', serial: 3, packet: {op: 'command', command: 'attack_move', match: 7, sequence: 3, ids: [11, 12], position: [0, 1152]}};
    assert.deepEqual(fighterSelection(moved, after, slot, attack, recon).fighter_ids, [11, 12]);
    for (const ids of [[11, 12, 13], [11, 12, 900], [11], [11, 12, 11]]) assert.throws(() => fighterSelection(moved, after, slot, {...attack, packet: {...attack.packet, ids}}, recon));
    for (const mutate of [x => x.actors.find(a => a.id === 13).destination = [500, 0], x => x.actors.find(a => a.id === 13).x = moved.actors.find(a => a.id === 13).x, x => x.actors.find(a => a.id === 13).state = 0, x => x.actors.find(a => a.id === 11).owner = 1 - slot]) {
      const bad = structuredClone(after); mutate(bad); assert.throws(() => fighterSelection(moved, bad, slot, attack, recon));
    }
    assert.throws(() => fighterSelection(moved, after, 1 - slot, attack, recon));
    assert.throws(() => scoutMove(f.before, moved, slot, {...move, packet: {...move.packet, position: [-999999, -999999]}}));
    const unchanged = structuredClone(f.before); unchanged.tick++; unchanged.time++; unchanged.actors.find(a => a.id === 13).path = [[-1000, 1152], [640, 1152]];
    assert.throws(() => scoutMove(f.before, unchanged, slot, {...move, packet: {...move.packet, position: [640, 1152]}}));
    assert.throws(() => fighterSelection(moved, after, slot, {...attack, packet: {...attack.packet, position: [-999999, -999999]}}, recon));
    const idle = structuredClone(after); for (const id of [11, 12]) idle.actors.find(a => a.id === id).state = 0;
    assert.throws(() => fighterSelection(moved, idle, slot, attack, recon));
    const preexisting = structuredClone(moved); for (const id of [11, 12]) Object.assign(preexisting.actors.find(a => a.id === id), {state: 1, attack_move: true, destination: [0, 1152]});
    assert.throws(() => fighterSelection(preexisting, after, slot, attack, recon));
  });
}
test('shared contract matches current normal Workshop and Siege costs and timings', () => {
  assert.deepEqual(CONTRACT.workshop, {type: 8, cost: {food: 0, wood: 300, gold: 100}, build_seconds: 28});
  assert.deepEqual(CONTRACT.siege, {type: 5, cost: {food: 0, wood: 150, gold: 100}, train_seconds: 25, population: 3});
});

const {nativeTap} = require('./live_browser_beta2_ui.cjs');
test('native adapter completes two distinct CDP touch sequences reusing actual contact0', async()=>{
  const sent=[],cdp={send:async(method,payload)=>{sent.push({method,payload});}};
  const first=await nativeTap(cdp,{x:50,y:60},'first',{width:844,height:390});
  const second=await nativeTap(cdp,{x:70,y:80},'second',{width:844,height:390});
  assert.notEqual(first.id,second.id);assert.equal(sent.length,4);
  assert.deepEqual(sent.map(row=>row.payload.type),['touchStart','touchEnd','touchStart','touchEnd']);
  assert.deepEqual(sent.filter(row=>row.payload.type==='touchStart').map(row=>row.payload.touchPoints[0].id),[0,0]);
  assert(first.dispatches.every(row=>row.acknowledged===true));
  await assert.rejects(nativeTap(cdp,{x:844,y:1},'outside',{width:844,height:390}));
});
test('ordinary paid Scout proof rejects free/early/foreign births and wrong resource substitution',()=>{
  const {scoutRecruitment,scoutBirth}=require('./live_browser_beta2_receipts.cjs');
  for(const slot of [0,1]) {
    const f=fixture(slot),before=f.before;before.actors=before.actors.filter(a=>a.id!==13);
    const queued=structuredClone(before);queued.tick++;queued.time+=.2;queued.bank.food-=40;queued.bank.gold-=10;queued.player.population_reserved++;
    queued.actors[0].queue={repeat:false,items:[4],training:true,time:8};
    const evidence={source:'game_ui_or_engine',serial:1,packet:{op:'command',command:'train',match:7,sequence:1,target:100,type:4}};
    assert.equal(scoutRecruitment(before,queued,slot,evidence).population_cost,1);
    const born=structuredClone(queued);born.tick++;born.time+=8;born.player.population++;born.player.population_reserved--;born.actors[0].queue={repeat:false,items:[]};born.actors.push({id:13,owner:slot,kind:'unit',type:4,state:0,hp:45,x:0,y:1152});
    assert.equal(scoutBirth(before,queued,born,slot,100).unit_id,13);
    for(const mutate of [p=>p.actors.at(-1).owner=1-slot,p=>p.time=queued.time+1,p=>p.player.population_reserved++,p=>p.actors.at(-1).id=11]){const bad=structuredClone(born);mutate(bad);assert.throws(()=>scoutBirth(before,queued,bad,slot,100));}
    const wrong=structuredClone(queued);wrong.bank.food+=10;wrong.bank.wood-=10;assert.throws(()=>scoutRecruitment(before,wrong,slot,evidence));
  }
});
test('beta2 saving policy leaves Workshop/Siege to actual touch and never retasks Scouts',()=>{
  const {planPolicy}=require('./run_live_browser_multiplayer.cjs');
  for(const slot of [0,1]) {
    const own=[{id:100,kind:'building',type:0,owner:slot,state:2,x:0,y:1152,queue:{items:[]}}];
    let id=101;for(const type of [1,1,2,3,4,9,5,5,5,5,5])own.push({id:id++,kind:'building',type,owner:slot,state:2,x:id*5,y:1000,queue:{items:[]}});
    for(let i=0;i<12;i++)own.push({id:id++,kind:'unit',type:0,owner:slot,work:i<4?'wood':i<7?'gold':'food'});
    own.push({id:500,kind:'unit',type:1,owner:slot},{id:501,kind:'unit',type:4,owner:slot});
    const client={role:slot===0?'host':'guest',beta2:true,beta2SiegeDone:false,policy:true,matched:{slot},lastBuild:-10,lastArmy:-60,demolished:true,rejectedPlacements:new Set(),last:{time:400,actors:own,bank:{food:2000,wood:2000,gold:2000},player:{age:3,population:14,population_reserved:0,population_cap:30},research:[],resources:[]}};
    const commands=planPolicy(client);
    assert(!commands.some(row=>row.command==='research'||row.command==='train'||row.command==='place'&&row.payload.type===8));
    assert.deepEqual(commands.find(row=>row.command==='attack_move').payload.ids,[500]);
    client.beta2SiegeDone=true;client.lastArmy=-60;
    assert(planPolicy(client).some(row=>row.command==='train'&&row.payload.type===1));
  }
});
test('UI stage failure is retained and cannot run while a policy sender is active',async()=>{
  const {createBeta2Controller}=require('./live_browser_beta2_ui.cjs');
  const logs=[],f=fixture(0),c={role:'host',beta2:true,matched:{slot:0,match:7},last:f.before,rejections:[],policy:false,page:{evaluate:async()=>0,waitForTimeout:async()=>{}}};
  const options={clients:{host:c},capture:async(_c,label)=>({name:label+'.png'}),input:async()=>{throw Error('Unexpected input');},append:(name,row)=>logs.push({name,row}),policyBusy:()=>false};
  await assert.rejects(createBeta2Controller(options).handle(c,{action:'siege_train'}),/Workshop labor/);
  assert.equal(logs.length,1);assert.equal(logs[0].row.passed,false);assert.match(logs[0].row.error,/Workshop labor/);
  await assert.rejects(createBeta2Controller({...options,policyBusy:()=>true}).handle(c,{action:'workshop_open'}),/in-flight/);
});
test('UI stage history cannot reuse a prior match Workshop selection',async()=>{
  const {createBeta2Controller}=require('./live_browser_beta2_ui.cjs');
  const logs=[],f=fixture(0),c={role:'host',beta2:true,matched:{slot:0,match:7},last:f.before,rejections:[],policy:false,page:{evaluate:async(_fn,arg)=>arg===undefined?0:[],waitForTimeout:async()=>{}}};
  const controller=createBeta2Controller({clients:{host:c},capture:async(_c,label)=>({name:label+'.png'}),input:async(_c,_point,purpose)=>({purpose}),append:(name,row)=>logs.push({name,row}),policyBusy:()=>false});
  assert((await controller.handle(c,{action:'workshop_open'})).passed);
  c.matched.match=99;c.last={...c.last,match:99};
  await assert.rejects(controller.handle(c,{action:'workshop_place'}),/actual Workshop card first/);
  assert.equal(logs.at(-1).row.match,99);assert.equal(logs.at(-1).row.passed,false);
});
