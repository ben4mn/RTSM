'use strict';
// Optional post-purchase ordinary UI witness. Reads recipient packets only.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {scoutRecruitment,scoutBirth,scoutMove}=require('./live_browser_beta2_receipts.cjs');
const {accepted,warriorTrain,warriorBirth,derivePaidSiege}=require('./live_browser_march.cjs');
const ACTIONS=['scout_move','paused','fighters_move','ticking'];
const PURPOSES={scout_move:['garrison_scout_select','garrison_scout_site_view','garrison_scout_move','garrison_scout_ground'],paused:[],fighters_move:['garrison_army_open','garrison_groups_open','garrison_select_fighters','garrison_fighters_site_view','garrison_fighters_move','garrison_fighters_ground'],ticking:[]};
// Sealed72x72 map center and actual SacredSite.capture_radius3 * TILE_WIDTH64.
const CENTER=[0,1152],RADIUS=192,FIGHTERS=[1,2,3,5];
const inside=u=>Number.isFinite(u.x)&&Number.isFinite(u.y)&&Math.hypot(u.x-CENTER[0],u.y-CENTER[1])<=RADIUS;
const own=(p,s)=>p.actors.filter(a=>a.kind==='unit'&&a.owner===s&&a.hp>0&&a.state!==5);
function derivePaidScout(rows,match,slot){
  const birth=rows.findLast(r=>r.action==='scout_birth'&&r.passed===true&&r.match===match&&r.slot===slot);assert(birth);
  const train=rows.find(r=>r.id===birth.parent&&r.action==='scout_train'&&r.passed===true&&r.match===match&&r.slot===slot);assert(train);
  scoutRecruitment(train.before,train.after,slot,train.evidence);
  return {...birth,verified:scoutBirth(train.before,train.after,birth.after,slot,train.evidence.packet.target)};
}
function derivePaidFighters(base,march,match,slot){
  const birth=march.findLast(r=>r.action==='warrior_birth'&&r.passed===true&&r.match===match&&r.slot===slot);assert(birth);
  const train=march.find(r=>r.id===birth.parent&&r.action==='warrior_train'&&r.passed===true&&r.match===match&&r.slot===slot);assert(train);
  const verified=warriorTrain(train.before,train.after,slot,train.evidence);
  return [warriorBirth({...train,proof:verified},birth.after,slot).warrior_id,derivePaidSiege(base,match,slot).verified.unit_id];
}
function clockSeries(series,role,slot,scoutId,mode,fighterIds=[]){
  assert(['paused','ticking'].includes(mode)&&series.length>=3);
  const first=series[0][role],last=series.at(-1)[role];
  assert(last.time-first.time>=2&&last.time-first.time<=5);
  for(let i=0;i<series.length;i++){
    const sample=series[i],p=sample[role],other=sample[role==='host'?'guest':'host'];
    assert(Number.isInteger(p.match)&&p.match>0&&p.match===first.match&&p.match===other.match&&p.tick===other.tick&&p.time===other.time);
    if(i)assert(p.tick>series[i-1][role].tick&&p.time>series[i-1][role].time);
    assert.deepEqual(p.site,other.site,'Both recipient slots must receive the same public Site facts');
    const site=p.site;assert(site.state===2&&site.owner===slot&&site.hold===180&&site.capture===1&&site.neutralizing===false&&site.garrison_paused===(mode==='paused')&&site.clock_ticking===(mode==='ticking'));
    assert(Number.isFinite(site.timer)&&site.timer>=0&&site.timer<site.hold);
    const units=own(p,slot),scout=units.find(u=>u.id===scoutId&&u.type===4);assert(scout&&inside(scout),'The witnessed paid Scout must actually occupy the ring');
    if(mode==='paused'){
      assert(!units.some(u=>FIGHTERS.includes(u.type)&&inside(u)));
      assert(Math.abs(site.timer-first.site.timer)<1e-6,'Paused hold must remain fixed while game time advances');
    }else{
      assert(units.some(u=>fighterIds.includes(u.id)&&FIGHTERS.includes(u.type)&&inside(u)),'An explicitly ordered owned fighter must enter the ring');
      assert(Math.abs((site.timer-first.site.timer)-(p.time-first.time))<.08,'Guarded clock must advance with actual game time');
    }
  }
  return {mode,owner:slot,scout_id:scoutId,first_tick:first.tick,last_tick:last.tick,game_seconds:last.time-first.time,timer_before:first.site.timer,timer_after:last.site.timer};
}
function createGarrisonController({clients,capture,input,append,policyBusy,output}){
  const histories=new Map(),history=c=>{const key=c.role+':'+c.matched?.match;if(!histories.has(key))histories.set(key,[]);return histories.get(key);};
  const prior=(c,a)=>history(c).findLast(r=>r.action===a&&r.passed);
  const rows=(c,name)=>fs.readFileSync(path.join(output,c.role+'-'+name+'.jsonl'),'utf8').trim().split('\n').map(JSON.parse);
  const held=()=>assert(!policyBusy()&&Object.values(clients).every(c=>!c.policy),'Hold both scripts; gathering and game time continue');
  async function handle(c,data){
    held();assert(!c.ended&&Object.values(clients).every(p=>p.beta2Reviewed&&p.matched?.match===c.matched?.match));
    // Do every strict purchase and mixed-march proof before Site income starts.
    for(const peer of Object.values(clients))assert(rows(peer,'march-ui').some(r=>r.action==='review'&&r.passed&&r.reviewed&&r.match===c.matched.match));
    const slot=c.matched.slot,action=data.action,id=crypto.randomUUID(),scout=derivePaidScout(rows(c,'beta2-ui'),c.matched.match,slot),paidFighters=derivePaidFighters(rows(c,'beta2-ui'),rows(c,'march-ui'),c.matched.match,slot);
    if(action==='review'){
      const completed=ACTIONS.map(a=>{const r=prior(c,a);assert(r);return r;});assert(data.reviewed===true);
      for(const row of completed)for(const image of row.captures)assert.equal(crypto.createHash('sha256').update(fs.readFileSync(image.path)).digest('hex'),image.sha256);
      for(const mode of ['paused','ticking'])for(const role of ['host','guest']){
        const text=data.observed?.[mode]?.[role],owner=clients[role].matched.slot===slot?'You':'Enemy';assert(text&&typeof text.title==='string'&&typeof text.clock==='string');
        if(mode==='paused'){
          assert.equal(text.title,owner==='You'?'Held · bring a fighter':'Enemy held · unguarded');
          assert(new RegExp('^'+owner+' \\d+:\\d{2} paused$').test(text.clock));
        }else{assert.equal(text.title,'Sacred Site · tap to view');assert(new RegExp('^'+owner+' win in \\d+:\\d{2}$').test(text.clock));}
      }
      const row={id,action,match:c.matched.match,slot,passed:true,reviewed:true,unix:Date.now(),attempts:completed.map(r=>r.id),observed:data.observed};history(c).push(row);append(c.role+'-garrison-ui.jsonl',row);return row;
    }
    assert(ACTIONS.includes(action));const index=ACTIONS.indexOf(action),parent=index?prior(c,ACTIONS[index-1]):null;if(index)assert(parent);
    const serial=await c.page.evaluate(()=>window.__aoemLiveWitness.state.commandSerial),rejections=Object.fromEntries(Object.values(clients).map(p=>[p.role,p.rejections.length]));
    const row={id,action,match:c.matched.match,slot,started_unix:Date.now(),before:structuredClone(c.last),after:null,start_serial:serial,inputs:[],captures:[],series:[],commands:[],passed:false,policy_held:true,parent:parent?.id||null,beta2_scout_birth:scout.id,rejections_before:rejections};
    const image=async label=>{for(const peer of Object.values(clients))row.captures.push({...await capture(peer,'garrison-'+id+'-'+label),role:peer.role});};
    const tap=async(key,purpose)=>{row.inputs.push(await input(c,data[key],purpose));await c.page.waitForTimeout(120);};
    const commands=()=>c.page.evaluate(start=>window.__aoemLiveWitness.state.sends.filter(r=>r.serial>start),serial);
    try{
      await image('before');
      if(action==='scout_move'){
        await tap('scout',PURPOSES[action][0]);await tap('site',PURPOSES[action][1]);await tap('move',PURPOSES[action][2]);await image('armed');row.before=structuredClone(c.last);
        assert(!(row.before.site.state===2&&row.before.site.owner===slot),'Begin before this owner has fully captured the Site');
        assert(own(row.before,slot).some(u=>u.id===scout.verified.unit_id&&!inside(u)),'Paid Scout begins outside the ring');
        await tap('ground',PURPOSES[action][3]);
      }else if(action==='fighters_move'){
        for(const [key,purpose] of ['army','groups','select','site','move'].map((key,i)=>[key,PURPOSES[action][i]]))await tap(key,purpose);
        await image('armed');row.before=structuredClone(c.last);row.command_prepared_unix=Date.now();
        assert(row.before.site.state===2&&row.before.site.owner===slot&&row.before.site.garrison_paused===true&&row.before.site.clock_ticking===false&&row.before.site.neutralizing===false);
        assert(!own(row.before,slot).some(u=>FIGHTERS.includes(u.type)&&inside(u)),'Do not credit a prior route entering the ring to the new Move');
        await tap('ground',PURPOSES[action][5]);
      }
      let failure;
      for(let retry=0;retry<(PURPOSES[action].length?80:1000);retry++){
        held();assert.deepEqual(Object.fromEntries(Object.values(clients).map(p=>[p.role,p.rejections.length])),rejections);row.commands=await commands();assert(row.commands.length<=(PURPOSES[action].length?1:0));row.after=structuredClone(c.last);
        try{
          if(action==='scout_move'){
            assert.equal(row.commands.length,1);row.proof=scoutMove(row.before,row.after,slot,row.commands[0]);assert.equal(row.proof.scout_id,scout.verified.unit_id);assert(Math.hypot(row.proof.destination[0]-CENTER[0],row.proof.destination[1]-CENTER[1])<=RADIUS/2);
          }else if(action==='fighters_move'){
            assert.equal(row.commands.length,1);row.proof=accepted(row.before,row.after,slot,row.commands[0],'move',false);assert(Math.hypot(row.proof.destination[0]-CENTER[0],row.proof.destination[1]-CENTER[1])<=RADIUS/2);
          }else{
            const sample=Object.fromEntries(Object.values(clients).map(p=>[p.role,structuredClone(p.last)]));
            const p=sample[c.role],other=sample[c.role==='host'?'guest':'host'];assert(p.tick===other.tick);
            if(!row.series.length){
              assert(p.site.state===2&&p.site.owner===slot&&p.site.neutralizing===false&&p.site.garrison_paused===(action==='paused')&&p.site.clock_ticking===(action==='ticking'));
              const roster=own(p,slot);assert(roster.some(u=>u.id===scout.verified.unit_id&&u.type===4&&inside(u)));
              assert(action==='paused'?!roster.some(u=>FIGHTERS.includes(u.type)&&inside(u)):roster.some(u=>paidFighters.includes(u.id)&&prior(c,'fighters_move').proof.fighter_ids.includes(u.id)&&inside(u)));
            }
            if(!row.series.some(s=>s[c.role].tick===p.tick))row.series.push(sample);
            row.proof=clockSeries(row.series,c.role,slot,scout.verified.unit_id,action,paidFighters.filter(id=>prior(c,'fighters_move')?.proof.fighter_ids.includes(id)));
          }
          failure=null;break;
        }catch(error){failure=error;}
        await c.page.waitForTimeout(100);
      }
      if(failure)throw failure;
      await image('after');row.commands=await commands();assert.equal(row.commands.length,PURPOSES[action].length?1:0);row.evidence=row.commands[0]||null;row.passed=true;
    }catch(error){row.error=String(error.message);throw error;}
    finally{row.finished_unix=Date.now();row.rejections_after=Object.fromEntries(Object.values(clients).map(p=>[p.role,p.rejections.length]));history(c).push(row);append(c.role+'-garrison-ui.jsonl',row);}
    return row;
  }
  return {handle};
}
module.exports={ACTIONS,PURPOSES,derivePaidScout,derivePaidFighters,clockSeries,createGarrisonController};
