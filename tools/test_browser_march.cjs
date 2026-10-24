'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {warriorTrain,warriorBirth,accepted,settled,marchSeries,SPEEDS}=require('./live_browser_march.cjs');
const copy=x=>structuredClone(x),empty=()=>({items:[],repeat:false});
function fixture(slot){
  const unit=(id,type,x)=>({id,kind:'unit',owner:slot,type,hp:100,state:0,x,y:1152,destination:[-1200,1152],path:[],attack_move:false,marching:false});
  const before={match:7,tick:1,time:10,bank:{food:1000,wood:1000,gold:1000},stats:{resources_gathered:1000},player:{population:4,population_reserved:0,population_cap:30},actors:[{id:200,kind:'building',type:2,owner:slot,state:2,queue:empty()},unit(10,0,-950),unit(300,5,-900)]};
  const evidence=(command,extra)=>({source:'game_ui_or_engine',serial:1,packet:{op:'command',command,sequence:1,match:7,...extra}});
  const buy=evidence('train',{target:200,type:1}),queued=copy(before);queued.tick++;queued.time+=.2;queued.bank.food-=50;queued.bank.wood-=20;queued.player.population_reserved=1;queued.actors[0].queue={items:[1],repeat:false,training:true,time:10};
  const train={before,after:queued,proof:warriorTrain(before,queued,slot,buy)};
  const birth=copy(queued);birth.tick++;birth.time+=10;birth.player.population++;birth.player.population_reserved=0;birth.actors[0].queue=empty();birth.actors.push(unit(400,1,-1000));
  const regroup=evidence('move',{ids:[300,400],position:[-640,1152]}),moving=copy(birth);moving.tick++;moving.time+=.2;
  for(const [id,x,dest] of [[300,-880,[-640,1152]],[400,-970,[-608,1168]]])Object.assign(moving.actors.find(u=>u.id===id),{state:1,x,destination:dest,path:[[x,1152],dest]});
  const group={before:birth,after:moving,proof:accepted(birth,moving,slot,regroup,'move',false)};
  const ready=copy(moving);ready.tick++;ready.time+=12;for(const u of ready.actors.filter(u=>[300,400].includes(u.id))){u.x=u.destination[0];u.y=u.destination[1];u.path=[];u.state=0;}
  const attack=evidence('attack_move',{ids:[300,400],position:[256,1152]});
  const buildSeries=(start,marching,target)=>Array.from({length:3},(_,i)=>{const p=copy(start);p.tick+=i+1;p.time+=.2+i*.6;for(const u of p.actors.filter(u=>[300,400].includes(u.id))){const original=start.actors.find(v=>v.id===u.id);u.x=original.x+(marching?1:-1)*(3+18*i);u.destination=u.id===300?target:[target[0]+32,target[1]+16];u.path=[[u.x,u.y],u.destination];u.state=1;u.attack_move=marching;u.marching=marching;}return p;});
  const marching=buildSeries(ready,true,[256,1152]),move=evidence('move',{ids:[300,400],position:[-1024,1152]}),released=buildSeries(marching.at(-1),false,[-1024,1152]);
  return {slot,before,buy,queued,train,birth,regroup,moving,group,ready,attack,marching,move,released};
}
for(const slot of [0,1]){
  test(`slot${slot}: paid30/55 pair settles, marches over1second, then explicit Move clears and advances`,()=>{
    const f=fixture(slot);assert.equal(warriorBirth(f.train,f.birth,slot).warrior_id,400);assert(settled(f.group,f.ready,slot).diameter<=128);
    assert.equal(marchSeries(f.ready,f.marching,slot,f.attack,400,300,'attack_move').marching,true);
    assert.equal(marchSeries(f.marching.at(-1),f.released,slot,f.move,400,300,'move').marching,false);
  });
  test(`slot${slot}: unpaid, foreign, stale, short, transient and non-moving march evidence rejects`,()=>{
    const f=fixture(slot);
    const wrong=copy(f.queued);wrong.bank.food+=20;wrong.bank.gold-=20;assert.throws(()=>warriorTrain(f.before,wrong,slot,f.buy));
    const early=copy(f.birth);early.time=f.queued.time+1;assert.throws(()=>warriorBirth(f.train,early,slot));
    const badAssembly=copy(f.ready);badAssembly.actors.find(u=>u.id===400).x+=20;assert.throws(()=>settled(f.group,badAssembly,slot));
    assert.throws(()=>marchSeries(f.ready,f.marching,1-slot,f.attack,400,300,'attack_move'));
    assert.throws(()=>marchSeries(f.ready,f.marching.slice(0,1),slot,f.attack,400,300,'attack_move'));
    for(const mutate of [s=>s[1].actors.find(u=>u.id===400).marching=false,s=>s[1].actors.find(u=>u.id===400).marching=1,s=>s[1].actors.find(u=>u.id===400).owner=1-slot,s=>s[1].match=8,s=>s[1].tick=s[0].tick,s=>s.at(-1).actors.find(u=>u.id===400).x=s[0].actors.find(u=>u.id===400).x]){const bad=copy(f.marching);mutate(bad);assert.throws(()=>marchSeries(f.ready,bad,slot,f.attack,400,300,'attack_move'));}
    const short={...f.attack,packet:{...f.attack.packet,position:[-576,1152]}};assert.throws(()=>marchSeries(f.ready,f.marching,slot,short,400,300,'attack_move'));
    const stale=copy(f.ready);for(const u of stale.actors.filter(u=>[300,400].includes(u.id)))u.destination=f.marching[0].actors.find(v=>v.id===u.id).destination;assert.throws(()=>marchSeries(stale,f.marching,slot,f.attack,400,300,'attack_move'));
    const retained=copy(f.released);retained[1].actors.find(u=>u.id===300).marching=true;assert.throws(()=>marchSeries(f.marching.at(-1),retained,slot,f.move,400,300,'move'));
    const alreadyReleased=copy(f.marching.at(-1));alreadyReleased.actors.find(u=>u.id===300).marching=false;assert.throws(()=>marchSeries(alreadyReleased,f.released,slot,f.move,400,300,'move'));
  });
}
test('nominal native speeds are ordinary sealed data, not measured wall-clock rates',()=>assert.deepEqual(SPEEDS,{1:55,5:30}));
test('paid Siege bridge rederives actual birth instead of trusting a recorded summary ID',()=>{
  const {derivePaidSiege}=require('./live_browser_march.cjs');
  for(const slot of [0,1]){
    const f=fixture(slot),before=copy(f.before);before.actors=before.actors.filter(a=>a.id!==300);before.actors[0].type=8;before.player.age=3;before.player.population=1;
    const queued=copy(before);queued.tick++;queued.time+=.2;queued.bank.wood-=150;queued.bank.gold-=100;queued.player.population_reserved=3;queued.actors[0].queue={items:[5],repeat:false,time:25,training:true};
    const born=copy(queued);born.tick++;born.time+=25;born.player.population_reserved=0;born.player.population=4;born.actors[0].queue=empty();born.actors.push({id:300,type:5,kind:'unit',owner:slot,hp:100,state:0,x:0,y:1152});
    const train={id:'train',action:'siege_train',passed:true,match:7,slot,before,after:queued,evidence:{source:'game_ui_or_engine',serial:1,packet:{op:'command',command:'train',match:7,sequence:1,target:200,type:5}}};
    const birth={id:'birth',action:'siege_birth',passed:true,match:7,slot,parent:'train',after:born,proof:{unit_id:301}};
    assert.equal(derivePaidSiege([train,birth],7,slot).verified.unit_id,300);
    assert.throws(()=>derivePaidSiege([train,birth],99,slot));
  }
});
