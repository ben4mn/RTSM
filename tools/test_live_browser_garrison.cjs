'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {clockSeries}=require('./live_browser_garrison.cjs');
function fixture(slot,mode){
  const role=slot===0?'host':'guest',other=slot===0?'guest':'host';
  return {role,series:[0,1,2].map(i=>{
    const packet={match:7,tick:10+i,time:500+i,site:{state:2,owner:slot,capture:1,timer:mode==='paused'?0:i,hold:180,clock_ticking:mode==='ticking',garrison_paused:mode==='paused',neutralizing:false},actors:[{id:13,kind:'unit',type:4,owner:slot,hp:40,state:0,x:0,y:1152},{id:11,kind:'unit',type:1,owner:slot,hp:60,state:0,x:mode==='paused'?-800:0,y:1152}]};
    return {[role]:packet,[other]:{...structuredClone(packet),actors:[]}};
  })};
}
test('both remapped owners require advancing game time and matching recipient public facts',()=>{
  for(const slot of [0,1])for(const mode of ['paused','ticking']){
    const {role,series}=fixture(slot,mode);const proof=clockSeries(series,role,slot,13,mode,[11]);assert.equal(proof.game_seconds,2);assert.equal(proof.owner,slot);
  }
});
test('paused flag cannot hide a changing timer or an armed occupant',()=>{
  for(const slot of [0,1])for(const mutate of [p=>p.site.timer=1,p=>p.actors[1].x=0,p=>p.site.garrison_paused=1,p=>p.site.neutralizing=true,p=>p.site.hold=240]){
    const {role,series}=fixture(slot,'paused');mutate(series[1][role]);series[1][role==='host'?'guest':'host'].site=structuredClone(series[1][role].site);assert.throws(()=>clockSeries(series,role,slot,13,'paused'));
  }
});
test('ticking needs the ordered fighter and a genuinely advancing clock',()=>{
  for(const slot of [0,1]){
    const {role,series}=fixture(slot,'ticking');assert.throws(()=>clockSeries(series,role,slot,13,'ticking',[999]));
    for(const sample of series)for(const packet of Object.values(sample))packet.site.timer=0;
    assert.throws(()=>clockSeries(series,role,slot,13,'ticking',[11]));
  }
});
test('prior match, other recipient disagreement, missing paid Scout and subsecond windows reject',()=>{
  for(const slot of [0,1])for(const mutate of [s=>s[1][slot===0?'guest':'host'].match=99,s=>s[1][slot===0?'guest':'host'].site.owner=1-slot,s=>s[1][slot===0?'host':'guest'].actors[0].id=999,s=>Object.values(s[2]).forEach(p=>p.time=501.1)]){
    const {role,series}=fixture(slot,'paused');mutate(series);assert.throws(()=>clockSeries(series,role,slot,13,'paused'));
  }
});
