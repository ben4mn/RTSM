'use strict';
// Test infrastructure only: real Chromium input and passive wire receipts.
// No game object, resource, visibility, clock, or terminal mutation.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const checks = require('./live_browser_beta2_receipts.cjs');

async function nativeTap(cdp, point, purpose, viewport) {
  assert(point && Number.isFinite(point.x) && Number.isFinite(point.y) && point.x >= 0 && point.y >= 0 && point.x < viewport.width && point.y < viewport.height, 'Use observed canvas coordinates');
  const dispatches=[];
  // Deliberately reuse contact 0 after each completed release. Unique IDs alone
  // would miss the browser-to-Godot contact reuse boundary under test.
  for(const [type,touchPoints] of [['touchStart',[{id:0,x:point.x,y:point.y,radiusX:1,radiusY:1,force:1}]],['touchEnd',[]]]) {
    const started=Date.now();await cdp.send('Input.dispatchTouchEvent',{type,touchPoints});
    dispatches.push({type,touchPoints,started_unix:started,acknowledged_unix:Date.now(),acknowledged:true});
  }
  return {id:crypto.randomUUID(),unix:Date.now(),kind:'tap',purpose,x:point.x,y:point.y,native_api:'CDP.Input.dispatchTouchEvent',contact_id:0,dispatches};
}

function createBeta2Controller({clients,capture,input,append,policyBusy}) {
  const state=new Map();
  const history=c=>{const key=c.role+':'+c.matched?.match;if(!state.has(key))state.set(key,[]);return state.get(key);};
  const previous=(c,action)=>history(c).findLast(row=>row.action===action && row.passed===true);
  const snapshot=c=>structuredClone(c.last);
  const commandSerial=c=>c.page.evaluate(()=>window.__aoemLiveWitness.state.commandSerial);
  const commandsAfter=(c,serial)=>c.page.evaluate(start=>window.__aoemLiveWitness.state.sends.filter(row=>row.serial>start),serial);
  const held=()=>assert(!policyBusy() && Object.values(clients).every(c=>!c.policy), 'Stop both policies and wait for their in-flight send loop before native UI proof');
  async function handle(c,data) {
    held();assert(c.beta2 && c.matched && c.last && !c.ended,'Need a live --beta2 match');
    const slot=c.matched.slot,action=data.action,id=crypto.randomUUID();
    assert(typeof action==='string');
    if(action==='review') {
      const required=['scout_train','scout_birth','workshop_open','workshop_place','workshop_complete','siege_train','siege_birth','scout_move','fighter_select','fighter_find','fighter_attack'];
      const rows=required.map(name=>{const row=previous(c,name);assert(row,'Missing successful '+name);return row;});
      assert(data.reviewed===true,'Inspect every referenced capture before reviewing');
      for(const row of rows)for(const image of row.captures)assert.equal(crypto.createHash('sha256').update(fs.readFileSync(image.path)).digest('hex'),image.sha256,'Capture changed');
      const observed=data.observed||{},fighter=previous(c,'fighter_attack');
      assert.equal(observed.workshop,'Siege Workshop');assert.deepEqual(observed.workshop_cost,{wood:300,gold:100});
      assert.equal(observed.siege,'Siege Engine');assert.deepEqual(observed.siege_cost,{wood:150,gold:100});
      const paidSiege=previous(c,'siege_train');
      assert.equal(observed.queue_count,1);
      assert.equal(observed.population_before,paidSiege.before.player.population+paidSiege.before.player.population_reserved);
      assert.equal(observed.population_queued,paidSiege.after.player.population+paidSiege.after.player.population_reserved);
      assert.equal(observed.scout,'Scout');assert.deepEqual(observed.scout_cost,{food:40,gold:10});
      assert.equal(observed.select_caption,'Select fighters');assert.equal(observed.fighter_count,fighter.proof.fighter_count);
      assert.equal(observed.find_frames_fighters,true);assert.equal(observed.scout_excluded_from_selection,true);
      const row={id,action,match:c.matched.match,passed:true,reviewed:true,slot,unix:Date.now(),attempts:rows.map(row=>row.id),observed,scope:'Operator inspected captured pixels; authority movement/ownership/payment assertions are separate machine checks'};
      history(c).push(row);append(c.role+'-beta2-ui.jsonl',row);c.beta2Reviewed=true;return row;
    }
    const before=snapshot(c),serial=await commandSerial(c),rejections=c.rejections.length;
    assert.equal(c.last.match,c.matched.match,'Latest authority snapshot must belong to this match');
    const row={id,action,match:c.matched.match,slot,started_unix:Date.now(),start_serial:serial,rejections_before:rejections,before,captures:[],inputs:[],passed:false,policy_held:true};
    const tap=async(key,purpose)=>{row.inputs.push(await input(c,data[key],purpose));await c.page.waitForTimeout(120);};
    const image=async(label)=>row.captures.push(await capture(c,'beta2-'+id+'-'+label));
    let validate=null,expectedCommands=0;
    try {
      await image('before');
      if(action==='workshop_open') {
        assert(!previous(c,'workshop_place'),'Workshop already witnessed');
        await tap('build','beta2_build_open');await tap('army','beta2_army_build_category');await image('army-cards');
        await tap('workshop','beta2_workshop_card');await image('placement-preview');
      } else if(action==='workshop_place') {
        row.parent=previous(c,'workshop_open')?.id;assert(row.parent,'Open the actual Workshop card first');
        await tap('ground','beta2_workshop_ground');await image('placed-preview');
        // Preview selection spends nothing; bind the bank immediately before Place.
        assert.equal((await commandsAfter(c,serial)).length,0,'Ground preview unexpectedly sent a gameplay order');
        row.before=snapshot(c);row.purchase_unix=Date.now();
        await tap('place','beta2_workshop_place');expectedCommands=1;
        validate=(after,evidence)=>checks.workshopPlacement(row.before,after,slot,evidence);
      } else if(action==='workshop_complete') {
        const placement=previous(c,'workshop_place');assert(placement,'Need paid foundation');row.parent=placement.id;
        validate=after=>checks.workshopCompletion(placement.after,after,slot,placement.proof.building_id);
      } else if(action==='siege_train') {
        const complete=previous(c,'workshop_complete');assert(complete,'Wait for actual Workshop labor');row.parent=complete.id;
        await tap('producer','beta2_workshop_select');await image('siege-train-button');
        assert.equal((await commandsAfter(c,serial)).length,0,'Producer selection sent an unrelated gameplay order');
        row.before=snapshot(c);row.purchase_unix=Date.now();await tap('train','beta2_siege_train');expectedCommands=1;
        validate=(after,evidence)=>checks.siegeRecruitment(row.before,after,slot,evidence,complete.proof.building_id);
      } else if(action==='siege_birth') {
        const train=previous(c,'siege_train');assert(train,'Need paid Siege queue');row.parent=train.id;
        validate=after=>checks.siegeBirth(train.before,train.after,after,slot,train.proof.building_id);
      } else if(action==='scout_train') {
        await tap('producer','beta2_town_select');await image('scout-train-button');
        assert.equal((await commandsAfter(c,serial)).length,0,'Town selection sent an unrelated gameplay order');
        row.before=snapshot(c);row.purchase_unix=Date.now();await tap('train','beta2_scout_train');expectedCommands=1;
        validate=(after,evidence)=>checks.scoutRecruitment(row.before,after,slot,evidence);
      } else if(action==='scout_birth') {
        const train=previous(c,'scout_train');assert(train,'Need paid Scout queue');row.parent=train.id;
        validate=after=>checks.scoutBirth(train.before,train.after,after,slot,train.proof.building_id);
      } else if(action==='scout_move') {
        const born=previous(c,'scout_birth');assert(born,'Need normal paid Scout birth');row.parent=born.id;
        await tap('scout','beta2_scout_select');await tap('move','beta2_scout_move_button');await image('move-armed');
        await tap('ground','beta2_scout_move_ground');expectedCommands=1;
        validate=(after,evidence)=>{const proof=checks.scoutMove(row.before,after,slot,evidence);assert.equal(proof.scout_id,born.proof.unit_id);return proof;};
      } else if(action==='fighter_select') {
        const recon=previous(c,'scout_move');assert(recon,'Need accepted recon route');row.parent=recon.id;
        await tap('army','beta2_army_open');await tap('groups','beta2_groups_open');await image('groups');
        await tap('select','beta2_select_fighters');
      } else if(action==='fighter_find') {
        const selected=previous(c,'fighter_select');assert(selected,'Select fighters first');row.parent=selected.id;
        // Select fighters closes the management sheet; reopen its Groups page.
        await tap('army','beta2_find_army_open');await tap('groups','beta2_find_groups_open');await image('find-button');
        await tap('find','beta2_find_fighters');
      } else if(action==='fighter_attack') {
        const found=previous(c,'fighter_find'),recon=previous(c,'scout_move');assert(found&&recon,'Use Select fighters and Find first');row.parent=found.id;row.recon=recon.id;
        await tap('attack','observed_attack_hud_button');await image('attack-armed');
        await tap('ground','attack_move_ground_destination');expectedCommands=1;
        validate=(after,evidence)=>checks.fighterSelection(previous(c,'fighter_select').before,after,slot,evidence,recon.proof);
      } else throw Error('Unknown beta2 action');
      let lastError;
      for(let retry=0;retry<60;retry++) {
        held();row.commands=await commandsAfter(c,serial);row.after=snapshot(c);
        assert.equal(c.rejections.length,rejections,'Authority rejected an order during this isolated UI window');
        assert(row.commands.length<=expectedCommands,'Concurrent command makes the receipt ambiguous');
        try {assert.equal(row.commands.length,expectedCommands);row.proof=validate?validate(row.after,row.commands[0]):{no_gameplay_order:true};lastError=null;break;}catch(error){lastError=error;}
        await c.page.waitForTimeout(80);
      }
      if(lastError)throw lastError;
      // Check again after capture: events racing a successful sample remain evidence.
      await image('after');row.commands=await commandsAfter(c,serial);assert.equal(row.commands.length,expectedCommands);assert.equal(c.rejections.length,rejections);
      row.evidence=row.commands[0]||null;row.passed=true;
      if(action==='siege_birth')c.beta2SiegeDone=true;
      if(action==='fighter_attack')append(c.role+'-attack-ui.jsonl',{check:'attack_hud',passed:true,unix:Date.now(),input_mode:'touch',evidence:row.evidence,screenshots:row.captures.map(item=>item.name),beta2_attempt:id,scope:'Actual native touch Attack plus accepted moving fighter routes; Scout preserved'});
    } catch(error) {row.error=String(error.message);throw error;}
    finally {row.finished_unix=Date.now();row.rejections_after=c.rejections.length;history(c).push(row);append(c.role+'-beta2-ui.jsonl',row);}
    return row;
  }
  return {handle};
}
module.exports={nativeTap,createBeta2Controller};
