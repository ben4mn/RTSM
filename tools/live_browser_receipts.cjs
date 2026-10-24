'use strict';
// Receipt expectations only. Never writes a game object or emits a command.
const assert=require('node:assert/strict');
const CIVILIZATIONS=[
  {id:0,key:'crownlands',name:'Crownlands'},
  {id:1,key:'verdant-league',name:'Verdant League'},
  {id:2,key:'sunstride-clans',name:'Sunstride Clans'},
];
function civilization(value) {
  const key=String(value).trim().toLowerCase().replace(/[ _]+/g,'-');
  const found=CIVILIZATIONS.find(c=>String(c.id)===key||c.key===key);
  assert(found,'Use Crownlands, Verdant League or Sunstride Clans (IDs0–2)');
  return {...found};
}
function counterLesson(snapshot,slot) {
  assert([0,1].includes(slot));
  const ids=snapshot?.civilizations;
  assert(Array.isArray(ids)&&ids.length===2&&ids.every(id=>Number.isInteger(id)&&id>=0&&id<=2),'Missing valid public civilization identity');
  const records=snapshot?.battle?.losses_by_matchup;
  assert(Array.isArray(records)&&records.length<=9,'Missing bounded authority battle receipts');
  const seen=new Set(),eligible=[];
  for(const row of records) {
    assert(Array.isArray(row)&&row.length===3&&row.every(Number.isInteger)&&[1,2,3].includes(row[0])&&[1,2,3].includes(row[1])&&row[2]>0&&row[2]<=9999&&!seen.has(row[0]*10+row[1]),'Malformed authority battle receipt');
    seen.add(row[0]*10+row[1]);
    if(row[2]>=3&&({1:2,2:3,3:1})[row[0]]===row[1])eligible.push({victim:row[0],attacker:row[1],count:row[2]});
  }
  let selected=null;
  for(const row of eligible)if(!selected||row.count>selected.count)selected=row;
  const plural=(type,civ)=>type===1?'Warriors':type===2?(civ===1?'Longbows':'Archers'):(civ===2?'Outriders':'Horsemen');
  let text='';
  if(selected){const recommendation=({1:2,2:3,3:1})[selected.attacker];text=`Enemy ${plural(selected.attacker,ids[1-slot])} landed final blows on ${selected.count} of your ${plural(selected.victim,ids[slot])}. Add ${plural(recommendation,ids[slot])} to counter them; regroup before your next fight.`;}
  return {eligible,selected,text,status:selected?'counter_lesson':'none'};
}
function resultExpectation(client) {
  assert(client.ended&&client.matched&&client.last,'Wait for actual authority terminal and final snapshot');
  const {slot}=client.matched;
  assert(client.ended.match===client.matched.match&&client.last.match===client.matched.match,'Terminal snapshot match differs');
  const lesson=counterLesson(client.last,slot);
  const counts={};
  for(const [label,key] of Object.entries({'Army Produced':'army_trained','Units Lost':'units_lost','Buildings Lost':'buildings_lost','Resources Gathered':'resources_gathered'})) {
    const value=client.last.stats?.[key];assert(Number.isInteger(value)&&value>=0,'Missing final own '+key);counts[label]=value;
  }
  return {result:client.ended.winner<0?'MATCH ENDED':client.ended.winner===slot?'VICTORY':'DEFEAT',reason:client.ended.reason,counts,lesson};
}
function paidVillagerRecruitment(before,after,slot,evidence) {
  assert([0,1].includes(slot)&&before&&after,'Missing own authority snapshots');
  const command=evidence?.packet;
  assert(evidence?.source==='game_ui_or_engine'&&command?.op==='command'&&command.command==='train'&&command.type===0,'Recruitment must originate in the game UI');
  assert(before.match===command.match&&after.match===command.match&&Number.isInteger(before.tick)&&after.tick>before.tick,'Recruitment needs successive snapshots from the same match');
  assert(Number.isFinite(before.time)&&after.time>=before.time&&after.time-before.time<=5,'Recruitment snapshots must bound one short input');
  const producer=packet=>packet.actors?.find(a=>a.id===command.target&&a.kind==='building'&&a.type===0&&a.owner===slot&&a.state===2);
  const previous=producer(before),current=producer(after);
  assert(previous&&current,'Recruitment must use this recipient’s completed Town Center');
  assert(previous.queue?.repeat===false&&current.queue?.repeat===false&&previous.queue?.items?.length===0&&JSON.stringify(current.queue?.items)==='[0]','Need one new paid Villager in an initially empty non-repeat queue');
  assert(Number.isInteger(before.player?.population_reserved)&&after.player?.population_reserved===before.player.population_reserved+1,'Paid Villager must reserve one population slot');
  const bank=packet=>{const values=['food','wood','gold'].map(k=>packet.bank?.[k]);assert(values.every(v=>Number.isInteger(v)&&v>=0),'Missing integer own bank');return values.reduce((a,b)=>a+b,0);};
  assert(before.bank?.food>=50,'Villager purchase must be affordable at ordinary50F cost');
  const deposited=after.stats?.resources_gathered-before.stats?.resources_gathered;
  assert(Number.isInteger(before.stats?.resources_gathered)&&before.stats.resources_gathered>=0&&Number.isInteger(after.stats?.resources_gathered)&&deposited>=0,'Missing normal deposit accounting');
  const netSpent=bank(before)+deposited-bank(after);
  assert.equal(netSpent,50,'Own bank plus actual deposits must account for exactly50 spent');
  const depositsByResource=Object.fromEntries(['food','wood','gold'].map(key=>[key,after.bank[key]-before.bank[key]+(key==='food'?50:0)]));
  assert(Object.values(depositsByResource).every(value=>value>=0),'A50F Villager cannot spend wood or gold or imply negative deposits');
  assert.equal(Object.values(depositsByResource).reduce((sum,value)=>sum+value,0),deposited,'Per-resource deposits must match the observed gathered total');
  return {unit:'Villager',unit_type:0,producer:command.target,cost:{food:50},bank_before:before.bank,bank_after:after.bank,normal_deposits:deposited,normal_deposits_by_resource:depositsByResource,net_spent:netSpent,queue_before:previous.queue.items,queue_after:current.queue.items,reserved_before:before.player.population_reserved,reserved_after:after.player.population_reserved};
}
module.exports={CIVILIZATIONS,civilization,counterLesson,resultExpectation,paidVillagerRecruitment};
