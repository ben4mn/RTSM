'use strict';
// Optional ordinary-input cohesion witness. No production or game state writes.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {paidBank,siegeRecruitment,siegeBirth}=require('./live_browser_beta2_receipts.cjs');
const SPEEDS=Object.freeze({1:55,5:30}); // Sealed UnitData: Warrior and Siege; no civilization overrides.
const clone=value=>structuredClone(value);
const vector=value=>Array.isArray(value)&&value.length===2&&value.every(Number.isFinite);
const distance=(a,b)=>{assert(vector(a)&&vector(b));return Math.hypot(a[0]-b[0],a[1]-b[1]);};
const ids=rows=>rows.map(row=>row.id).sort((a,b)=>a-b);
function own(packet,slot,kind) {assert([0,1].includes(slot)&&Array.isArray(packet?.actors));const all=packet.actors.map(a=>a.id);assert(all.every(i=>Number.isInteger(i)&&i>0)&&new Set(all).size===all.length);return packet.actors.filter(a=>a.owner===slot&&(!kind||a.kind===kind));}
const units=(p,s)=>own(p,s,'unit').filter(u=>Number.isFinite(u.hp)&&u.hp>0&&u.state!==5);
const fighters=(p,s)=>units(p,s).filter(u=>[1,2,3,5].includes(u.type));
function interval(a,b,maximum=6){assert(Number.isInteger(a.match)&&a.match>0&&a.match===b.match&&Number.isInteger(a.tick)&&Number.isInteger(b.tick)&&b.tick>a.tick&&Number.isFinite(a.time)&&Number.isFinite(b.time)&&b.time>a.time&&b.time-a.time<=maximum);}
function command(e,p,operation){assert(e?.source==='game_ui_or_engine'&&Number.isInteger(e.serial)&&e.serial>0&&e.packet?.op==='command'&&e.packet.command===operation&&e.packet.match===p.match&&Number.isInteger(e.packet.sequence)&&e.packet.sequence>0);return e.packet;}
function quiet(p,s,except=null){for(const b of own(p,s,'building'))if(b.queue){assert(b.queue.repeat===false&&Array.isArray(b.queue.items));assert(b.id===except||b.queue.items.length===0);}}
function tile(point){assert(vector(point));const result=[point[0]/64+point[1]/32,point[1]/32-point[0]/64];assert(result.every(v=>v>=0&&v<72&&Math.abs(v-Math.round(v))<1e-6));return result;}
function paidPair(packet,slot,warriorId,siegeId){const roster=units(packet,slot),pair=[roster.find(u=>u.id===warriorId&&u.type===1),roster.find(u=>u.id===siegeId&&u.type===5)];assert(pair.every(Boolean),'Need the same paid Warrior and Siege alive');return pair;}
function warriorTrain(before,after,slot,evidence){
  interval(before,after);const cmd=command(evidence,before,'train');assert(cmd.type===1);quiet(before,slot);quiet(after,slot,cmd.target);
  const [old,current]=[before,after].map(p=>own(p,slot,'building').find(b=>b.id===cmd.target&&b.type===2&&b.state===2));
  assert(old?.queue?.items?.length===0&&current?.queue?.repeat===false&&JSON.stringify(current.queue.items)==='[1]'&&current.queue.time===10&&current.queue.training===true);
  assert(Number.isInteger(before.player.population_reserved)&&after.player.population_reserved===before.player.population_reserved+1&&after.player.population===before.player.population&&before.player.population+before.player.population_reserved+1<=before.player.population_cap);
  assert.deepEqual(ids(units(before,slot)),ids(units(after,slot)));
  return {...paidBank(before,after,{food:50,wood:20,gold:0}),producer_id:cmd.target};
}
function warriorBirth(train,after,slot){
  const before=train.before,queued=train.after;interval(queued,after,90);quiet(after,slot);assert(after.time-queued.time>=9);
  const producer=own(after,slot,'building').find(b=>b.id===train.proof.producer_id&&b.type===2&&b.state===2);assert(producer?.queue?.items?.length===0);
  const old=units(before,slot),current=units(after,slot),fresh=current.filter(u=>!old.some(p=>p.id===u.id));assert(fresh.length===1&&fresh[0].type===1&&current.length===old.length+1&&old.every(u=>current.some(p=>p.id===u.id)));
  assert(after.player.population===before.player.population+1&&after.player.population_reserved===before.player.population_reserved);
  return {warrior_id:fresh[0].id,native_speed:SPEEDS[1]};
}
function accepted(before,after,slot,evidence,operation,marching){
  interval(before,after);const cmd=command(evidence,before,operation),target=tile(cmd.position),prior=fighters(before,slot),current=fighters(after,slot);
  assert(Array.isArray(cmd.ids)&&cmd.ids.length>=2&&cmd.ids.every(i=>Number.isInteger(i)&&i>0)&&new Set(cmd.ids).size===cmd.ids.length);assert.deepEqual([...cmd.ids].sort((a,b)=>a-b),ids(prior));assert.deepEqual(ids(prior),ids(current));
  for(const u of current){const old=prior.find(p=>p.id===u.id),end=tile(u.destination);assert(u.state===1&&u.attack_move===(operation==='attack_move')&&u.marching===marching);assert(Array.isArray(u.path)&&u.path.length>=2&&u.path.every(vector)&&distance(u.path[0],[u.x,u.y])<=.01);assert(end.every((v,i)=>Math.abs(v-target[i])<=6));assert(!vector(old.destination)||distance(old.destination,u.destination)>1);}
  return {fighter_ids:ids(current),destination:cmd.position};
}
function settled(regroup,after,slot){
  interval(regroup.after,after,150);const current=fighters(after,slot);assert.deepEqual(ids(current),regroup.proof.fighter_ids);
  for(const u of current){const assigned=regroup.after.actors.find(p=>p.id===u.id);assert(u.state===0&&u.attack_move===false&&u.marching===false&&distance(u.destination,assigned.destination)<=.01&&distance([u.x,u.y],assigned.destination)<=4.01);}
  let diameter=0;for(const a of current)for(const b of current)diameter=Math.max(diameter,distance([a.x,a.y],[b.x,b.y]));assert(diameter<=128,'Ordinary Move must actually settle a compact group');return {fighter_ids:ids(current),diameter};
}
function marchSeries(before,series,slot,evidence,warriorId,siegeId,operation){
  assert(Array.isArray(series)&&series.length>=3);const marching=operation==='attack_move',first=series[0],last=series.at(-1);
  const result=accepted(before,first,slot,evidence,operation,marching);interval(first,last,4);assert(last.time-first.time>=1,'Need continued real authority observation, not one transient tick');
  const paid=paidPair(before,slot,warriorId,siegeId);if(marching)assert(paid.every(u=>distance([u.x,u.y],evidence.packet.position)>=512),'Choose a legal long clear route');else assert(paid.every(u=>u.marching===true),'Issue explicit Move while both paid members still march');
  for(let i=0;i<series.length;i++){
    const p=series[i];if(i)interval(series[i-1],p,4);
    assert.deepEqual(ids(fighters(p,slot)),result.fighter_ids);
    for(const u of paidPair(p,slot,warriorId,siegeId)){const initial=first.actors.find(a=>a.id===u.id);assert(u.state===1&&u.attack_move===marching&&u.marching===marching&&distance(u.destination,initial.destination)<=.01);}
  }
  for(const u of paidPair(last,slot,warriorId,siegeId)){const initial=first.actors.find(a=>a.id===u.id);assert(distance([u.x,u.y],[initial.x,initial.y])>.5,'Both paid members must keep advancing');}
  return {...result,warrior_id:warriorId,siege_id:siegeId,native_speeds:{warrior:55,siege:30},observed_game_seconds:last.time-first.time,marching};
}
function derivePaidSiege(rows,match,slot){
  const birth=rows.findLast(row=>row.action==='siege_birth'&&row.passed===true&&row.match===match&&row.slot===slot);assert(birth);
  const train=rows.find(row=>row.id===birth.parent&&row.action==='siege_train'&&row.passed===true&&row.match===match&&row.slot===slot);assert(train);
  const producer=train.evidence?.packet?.target;
  siegeRecruitment(train.before,train.after,slot,train.evidence,producer);
  const verified=siegeBirth(train.before,train.after,birth.after,slot,producer);
  // Recorded proof summaries are not bridge identities; rederive from packets.
  return {...birth,verified};
}

function createMarchController({clients,capture,input,append,policyBusy,output}){
  const histories=new Map(),history=c=>{const key=c.role+':'+c.matched?.match;if(!histories.has(key))histories.set(key,[]);return histories.get(key);};
  const prior=(c,a)=>history(c).findLast(row=>row.action===a&&row.passed);
  const beta2=c=>fs.readFileSync(path.join(output,c.role+'-beta2-ui.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
  const held=()=>assert(!policyBusy()&&Object.values(clients).every(c=>!c.policy),'Hold both scripted policies first');
  async function handle(c,data){
    held();assert(c.beta2Reviewed&&c.last?.match===c.matched?.match&&!c.ended,'Finish the reviewed beta2 Siege/fighter journey in this match first');
    const action=data.action,slot=c.matched.slot,id=crypto.randomUUID(),siege=derivePaidSiege(beta2(c),c.matched.match,slot);
    if(action==='review'){
      const actions=['warrior_train','warrior_birth','regroup','settled','attack','move'],rows=actions.map(a=>{const r=prior(c,a);assert(r);return r;});assert(data.reviewed===true);
      for(const r of rows)for(const image of r.captures)assert.equal(crypto.createHash('sha256').update(fs.readFileSync(image.path)).digest('hex'),image.sha256);
      assert.equal(data.observed?.march_status,'Group march');assert.equal(data.observed?.move_cleared_status,true);assert.equal(data.observed?.mixed_fighters_visible,true);
      const attack=prior(c,'attack'),selected=attack.proof.fighter_ids,count=attack.after.actors.filter(u=>selected.includes(u.id)&&u.marching===true).length;
      assert.equal(data.observed.marching_fighters,count);assert.equal(data.observed.selected_fighters,selected.length);
      assert.equal(String(data.observed.march_status_text).replace(/\s+/g,' ').trim(),`Group march ${count}/${selected.length} fighters`);
      const row={id,action,match:c.matched.match,slot,passed:true,reviewed:true,unix:Date.now(),attempts:rows.map(r=>r.id),observed:data.observed};history(c).push(row);append(c.role+'-march-ui.jsonl',row);return row;
    }
    const serial=await c.page.evaluate(()=>window.__aoemLiveWitness.state.commandSerial),rejected=c.rejections.length;
    const row={id,action,match:c.matched.match,slot,started_unix:Date.now(),start_serial:serial,before:clone(c.last),inputs:[],captures:[],series:[],passed:false,policy_held:true,rejections_before:rejected,beta2_siege_birth:siege.id};
    const image=async(label)=>row.captures.push(await capture(c,'march-'+id+'-'+label));
    const tap=async(key,purpose)=>{row.inputs.push(await input(c,data[key],purpose));await c.page.waitForTimeout(120);};
    const commands=()=>c.page.evaluate(start=>window.__aoemLiveWitness.state.sends.filter(r=>r.serial>start),serial);
    let count=1,validate;
    try{
      await image('before');
      if(action==='warrior_train'){
        await tap('producer','march_barracks_select');await image('train-button');assert.equal((await commands()).length,0);row.before=clone(c.last);await tap('train','march_warrior_train');validate=(after,e)=>warriorTrain(row.before,after,slot,e);
      }else if(action==='warrior_birth'){
        const train=prior(c,'warrior_train');assert(train);row.parent=train.id;count=0;validate=after=>warriorBirth(train,after,slot);
      }else if(action==='regroup'){
        const born=prior(c,'warrior_birth');assert(born);row.parent=born.id;paidPair(row.before,slot,born.proof.warrior_id,siege.verified.unit_id);
        await tap('army','march_army_open');await tap('groups','march_groups_open');await tap('select','march_select_fighters');await tap('move','march_regroup_move');await image('move-armed');await tap('ground','march_regroup_ground');validate=(after,e)=>accepted(row.before,after,slot,e,'move',false);
      }else if(action==='settled'){
        const regroup=prior(c,'regroup');assert(regroup);row.parent=regroup.id;count=0;validate=after=>settled(regroup,after,slot);
      }else if(action==='attack'||action==='move'){
        const parent=prior(c,action==='attack'?'settled':'attack'),born=prior(c,'warrior_birth');assert(parent&&born);row.parent=parent.id;
        await tap('button',action==='attack'?'march_attack_hud':'march_release_move_hud');await image('armed');
        if(action==='move'){
          // An armed screenshot may take time. Do not credit a contact release
          // during that gap to the later explicit Move ground tap.
          row.before=clone(c.last);row.command_prepared_unix=Date.now();
          assert(paidPair(row.before,slot,born.proof.warrior_id,siege.verified.unit_id).every(u=>u.marching===true),'Paid members released before the Move ground tap');
        }
        await tap('ground',action==='attack'?'march_attack_ground':'march_release_ground');
        validate=(after,e)=>{
          const operation=action==='attack'?'attack_move':'move';
          if(!row.series.length)accepted(row.before,after,slot,e,operation,action==='attack');
          if(!row.series.some(p=>p.tick===after.tick))row.series.push(after);
          return marchSeries(row.before,row.series,slot,e,born.proof.warrior_id,siege.verified.unit_id,operation);
        };
      }else throw Error('Unknown march stage');
      let failure;
      for(let retry=0;retry<75;retry++){
        held();assert.equal(c.rejections.length,rejected);row.commands=await commands();assert(row.commands.length<=count);row.after=clone(c.last);
        try{assert.equal(row.commands.length,count);row.proof=validate(row.after,row.commands[0]);failure=null;break;}catch(error){failure=error;}
        await c.page.waitForTimeout(80);
      }
      if(failure)throw failure;
      await image('after');row.commands=await commands();assert.equal(row.commands.length,count);assert.equal(c.rejections.length,rejected);row.evidence=row.commands[0]||null;row.passed=true;
    }catch(error){row.error=String(error.message);throw error;}
    finally{row.finished_unix=Date.now();row.rejections_after=c.rejections.length;history(c).push(row);append(c.role+'-march-ui.jsonl',row);}
    return row;
  }
  return {handle};
}
module.exports={SPEEDS,warriorTrain,warriorBirth,accepted,settled,marchSeries,derivePaidSiege,createMarchController};
