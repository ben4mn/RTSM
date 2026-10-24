'use strict';
// Passive authority receipt checks only. Never sends commands or changes state.
const assert = require('node:assert/strict');
const PROFILE = 'beta2-mobile';
const CONTRACT = Object.freeze({workshop: {type: 8, cost: {food: 0, wood: 300, gold: 100}, build_seconds: 28}, siege: {type: 5, cost: {food: 0, wood: 150, gold: 100}, train_seconds: 25, population: 3}});
const RESOURCES = ['food', 'wood', 'gold'];
const FIGHTERS = [1, 2, 3, 5];
const integer = (value, minimum = 0) => Number.isInteger(value) && value >= minimum;
const vector = value => Array.isArray(value) && value.length === 2 && value.every(Number.isFinite);
const distance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
function worldTile(point) {
  assert(vector(point), 'Missing finite world destination');
  const tile = [point[0] / 64 + point[1] / 32, point[1] / 32 - point[0] / 64];
  assert(tile.every(value => Math.abs(value - Math.round(value)) < 1e-6 && value >= 0 && value < 72), 'Require a canonical in-map ground command');
  return tile;
}
function acceptedRoute(unit) {
  assert(unit?.state === 1 && vector(unit.destination) && Array.isArray(unit.path) && unit.path.length >= 2 && unit.path.every(vector) && distance(unit.path[0], [unit.x, unit.y]) <= 0.01, 'Need a current authoritative moving route');
}

function actors(packet, slot, kind) {
  assert([0, 1].includes(slot) && Array.isArray(packet?.actors), 'Need this recipient authority roster');
  const ids = packet.actors.map(actor => actor.id);
  assert(ids.every(id => integer(id, 1)) && new Set(ids).size === ids.length, 'Duplicate or invalid authority actor IDs');
  return packet.actors.filter(actor => actor.owner === slot && (!kind || actor.kind === kind));
}
function liveUnits(packet, slot) {
  return actors(packet, slot, 'unit').filter(actor => integer(actor.type) && actor.type <= 5 && Number.isFinite(actor.hp) && actor.hp > 0 && actor.state !== 5);
}
function ids(units) { return units.map(unit => unit.id).sort((a, b) => a - b); }
function sameMatch(before, after, maximum = 6) {
  assert(integer(before?.match, 1) && after?.match === before.match, 'Snapshots must share one real match');
  assert(integer(before.tick) && integer(after.tick) && after.tick > before.tick, 'Need successive authority ticks');
  assert(Number.isFinite(before.time) && Number.isFinite(after.time) && after.time > before.time && after.time - before.time <= maximum, 'Snapshot time interval is missing, reversed or too long');
}
function uiCommand(evidence, match, operation) {
  const command = evidence?.packet;
  assert(evidence?.source === 'game_ui_or_engine' && integer(evidence.serial, 1) && command?.op === 'command' && command.command === operation && command.match === match && integer(command.sequence, 1), 'Require a fresh game-UI command from this match');
  return command;
}
function quietQueues(packet, slot, except = null) {
  for (const producer of actors(packet, slot, 'building')) {
    if (!producer.queue) continue;
    assert(producer.queue.repeat === false && Array.isArray(producer.queue.items), 'Disable Repeat before an isolated UI purchase');
    if (producer.id !== except) assert.equal(producer.queue.items.length, 0, 'Wait for other paid queues to finish');
  }
}
function paidBank(before, after, cost) {
  assert(RESOURCES.every(key => integer(before.bank?.[key]) && integer(after.bank?.[key]) && before.bank[key] >= cost[key]), 'Missing own bank or ordinary purchase is unaffordable');
  const prior = before.stats?.resources_gathered, next = after.stats?.resources_gathered;
  assert(integer(prior) && integer(next) && next >= prior, 'Missing actual normal gather accounting');
  const deposits = Object.fromEntries(RESOURCES.map(key => [key, after.bank[key] - before.bank[key] + cost[key]]));
  assert(Object.values(deposits).every(value => value >= 0), 'Purchase implies negative deposits or spending the wrong resource');
  assert.equal(Object.values(deposits).reduce((sum, value) => sum + value, 0), next - prior, 'Cost and per-resource deposits do not match gathered total');
  return {cost: {...cost}, normal_deposits: next - prior, normal_deposits_by_resource: deposits, before_bank: before.bank, after_bank: after.bank};
}
function workshopPlacement(before, after, slot, evidence) {
  sameMatch(before, after);
  const command = uiCommand(evidence, before.match, 'place');
  assert(command.type === CONTRACT.workshop.type && vector(command.position), 'Require the actual Workshop Place command');
  assert(before.player?.age === 3 && after.player?.age === 3, 'Workshop requires actual Castle Age');
  assert(integer(before.stats?.resources_gathered) && before.stats.resources_gathered >= 650, 'Require a normally gathered budget, not only the opening bank');
  quietQueues(before, slot); quietQueues(after, slot);
  const previous = actors(before, slot, 'building'), current = actors(after, slot, 'building');
  assert(!previous.some(building => building.type === 8), 'Witness the first actual owned Workshop');
  const old = new Set(previous.map(building => building.id)), fresh = current.filter(building => !old.has(building.id));
  assert(fresh.length === 1 && current.length === previous.length + 1 && previous.every(building => current.some(other => other.id === building.id)), 'Require exactly one new owned foundation without concurrent destruction');
  const foundation = fresh[0];
  assert(foundation.type === 8 && foundation.state === 1 && Number.isFinite(foundation.progress) && foundation.progress >= 0 && foundation.progress < 1 && foundation.hp > 0, 'Need a real unfinished Workshop foundation');
  assert(distance([foundation.x, foundation.y], command.position) <= 0.01, 'Foundation differs from the accepted Place position');
  const workers = liveUnits(before, slot).filter(unit => unit.type === 0);
  assert(workers.length && (!command.ids || (Array.isArray(command.ids) && command.ids.every(id => workers.some(worker => worker.id === id)))), 'Place cannot use foreign or non-worker IDs');
  assert.deepEqual(ids(liveUnits(before, slot)), ids(liveUnits(after, slot)), 'Concurrent unit birth/death makes purchase ambiguous');
  return {...paidBank(before, after, CONTRACT.workshop.cost), building_id: foundation.id, slot, type: 8, foundation_time: after.time};
}
function workshopCompletion(foundationPacket, completed, slot, buildingId) {
  sameMatch(foundationPacket, completed, 150);
  const before = actors(foundationPacket, slot, 'building').find(building => building.id === buildingId);
  const after = actors(completed, slot, 'building').find(building => building.id === buildingId);
  assert(before?.type === 8 && before.state === 1 && before.progress < 1 && after?.type === 8 && after.state === 2 && after.progress === 1 && after.hp > 0, 'Same owned foundation must finish normally');
  assert(completed.time - foundationPacket.time >= CONTRACT.workshop.build_seconds - 1, 'Completion is too early for ordinary Workshop labor');
  return {building_id: buildingId, elapsed_game_seconds: completed.time - foundationPacket.time, state: after.state};
}
function siegeRecruitment(before, queued, slot, evidence, buildingId) {
  sameMatch(before, queued);
  const command = uiCommand(evidence, before.match, 'train');
  assert(command.type === 5 && command.target === buildingId, 'Require the actual owned Workshop Siege Train command');
  assert(before.player?.age === 3 && queued.player?.age === 3, 'Siege purchase requires Castle Age');
  quietQueues(before, slot); quietQueues(queued, slot, buildingId);
  const producer = packet => actors(packet, slot, 'building').find(building => building.id === buildingId && building.type === 8 && building.state === 2);
  const old = producer(before), current = producer(queued);
  assert(old && current && old.queue?.items?.length === 0 && current.queue?.repeat === false && JSON.stringify(current.queue.items) === '[5]' && current.queue.training === true && current.queue.time === CONTRACT.siege.train_seconds, 'Need one real paid Siege in an empty non-repeat owned queue');
  assert(integer(before.player.population_reserved) && queued.player.population_reserved === before.player.population_reserved + 3 && integer(before.player.population) && queued.player.population === before.player.population, 'Paid Siege must reserve exactly three population before birth');
  assert(before.player.population + before.player.population_reserved + 3 <= before.player.population_cap, 'Ordinary population capacity must fit Siege');
  assert.deepEqual(ids(liveUnits(before, slot)), ids(liveUnits(queued, slot)), 'Queue purchase cannot already spawn a free unit');
  return {...paidBank(before, queued, CONTRACT.siege.cost), building_id: buildingId, unit_type: 5, population_cost: 3, reserved_before: before.player.population_reserved, reserved_after: queued.player.population_reserved};
}
function siegeBirth(before, queued, after, slot, buildingId) {
  sameMatch(queued, after, 90);
  assert(before.match === queued.match && before.tick < queued.tick, 'Birth must follow the witnessed paid queue');
  const producer = actors(after, slot, 'building').find(building => building.id === buildingId && building.type === 8 && building.state === 2);
  assert(producer?.queue?.repeat === false && Array.isArray(producer.queue.items) && producer.queue.items.length === 0, 'Witnessed Siege queue must finish');
  quietQueues(after, slot);
  assert(after.time - queued.time >= CONTRACT.siege.train_seconds - 1, 'Birth is too early for the normal Siege queue');
  const old = liveUnits(before, slot), current = liveUnits(after, slot), priorIds = new Set(ids(old));
  const born = current.filter(unit => !priorIds.has(unit.id));
  assert(born.length === 1 && born[0].type === 5 && current.length === old.length + 1 && old.every(unit => current.some(other => other.id === unit.id)), 'Need exactly one new owned Siege, with no other birth/death ambiguity');
  assert(after.player?.population_reserved === before.player.population_reserved && after.player.population === before.player.population + 3, 'Birth must convert the three reserved population exactly once');
  return {unit_id: born[0].id, slot, unit_type: 5, population_cost: 3, elapsed_game_seconds: after.time - queued.time};
}
function scoutMove(before, after, slot, evidence) {
  sameMatch(before, after);
  const command = uiCommand(evidence, before.match, 'move');
  assert(Array.isArray(command.ids) && command.ids.length === 1 && vector(command.position), 'Explicit Scout Move must target exactly one selected unit');
  worldTile(command.position);
  const scout = liveUnits(before, slot).find(unit => unit.id === command.ids[0] && unit.type === 4);
  const current = liveUnits(after, slot).find(unit => unit.id === scout?.id);
  assert(scout && current && current.attack_move === false, 'Need a live own Scout on an accepted recon route');
  acceptedRoute(current);
  assert(distance(current.destination, command.position) <= 0.01 && (!vector(scout.destination) || distance(scout.destination, current.destination) > 1), 'New Scout command must change its authoritative destination to the observed clear ground');
  return {scout_id: scout.id, destination: current.destination, accepted_tick: after.tick};
}
function fighterSelection(before, after, slot, evidence, scoutProof) {
  sameMatch(before, after, 45);
  const command = uiCommand(evidence, before.match, 'attack_move');
  const targetTile = worldTile(command.position);
  const fighters = liveUnits(before, slot).filter(unit => FIGHTERS.includes(unit.type));
  const current = liveUnits(after, slot).filter(unit => FIGHTERS.includes(unit.type));
  assert(fighters.length >= 2 && Array.isArray(command.ids) && command.ids.every(id => integer(id, 1)) && new Set(command.ids).size === command.ids.length, 'Need a real multi-fighter shortcut command without duplicate IDs');
  assert.deepEqual([...command.ids].sort((a, b) => a - b), ids(fighters), 'Shortcut command must include every own fighter and exclude Scouts/workers/enemies');
  assert.deepEqual(ids(current), ids(fighters), 'Fighter roster changed during the selection witness');
  for (const unit of current) {
    acceptedRoute(unit);
    assert(unit.attack_move === true, 'Fighter command must enter authoritative attack-move');
    const destination = worldTile(unit.destination), prior = fighters.find(actor => actor.id === unit.id);
    assert(destination.every((value, index) => Math.abs(value - targetTile[index]) <= 6), 'Accepted fighter endpoint must belong to the requested planner area');
    assert(!vector(prior.destination) || distance(prior.destination, unit.destination) > 1, 'An unchanged pre-existing fighter route cannot prove accepted new input');
    assert(distance([prior.x, prior.y], [unit.x, unit.y]) > 0.5, 'Every selected fighter must actually advance on the accepted new route');
  }
  const scout = liveUnits(before, slot).find(unit => unit.id === scoutProof?.scout_id && unit.type === 4);
  const later = liveUnits(after, slot).find(unit => unit.id === scout?.id);
  assert(scout && later && scout.state === 1 && later.state === 1 && scout.attack_move === false && later.attack_move === false && vector(scout.destination) && JSON.stringify(scout.destination) === JSON.stringify(scoutProof.destination) && JSON.stringify(later.destination) === JSON.stringify(scout.destination), 'Fighter shortcut must preserve the existing Scout recon destination');
  assert(vector([scout.x, scout.y]) && vector([later.x, later.y]) && distance([scout.x, scout.y], [later.x, later.y]) > 0.5, 'Scout must continue advancing on its accepted recon route');
  const centroid = fighters.reduce((sum, unit) => [sum[0] + unit.x / fighters.length, sum[1] + unit.y / fighters.length], [0, 0]);
  assert(distance([scout.x, scout.y], centroid) >= 200, 'Scout must be separated from the fighter group for meaningful Find coverage');
  return {fighter_ids: ids(fighters), fighter_count: fighters.length, scout_id: scout.id, scout_destination: scout.destination, separation: distance([scout.x, scout.y], centroid)};
}
function scoutRecruitment(before, queued, slot, evidence) {
  sameMatch(before, queued);
  const command = uiCommand(evidence, before.match, 'train');
  assert(command.type === 4, 'Require actual Scout recruitment');
  quietQueues(before, slot); quietQueues(queued, slot, command.target);
  const producer = packet => actors(packet, slot, 'building').find(building => building.id === command.target && building.type === 0 && building.state === 2);
  const old = producer(before), current = producer(queued);
  assert(old?.queue?.items?.length === 0 && current?.queue?.repeat === false && JSON.stringify(current.queue.items) === '[4]' && current.queue.training === true && current.queue.time === 8, 'Require one paid Scout in an empty owned Town Center queue');
  assert(integer(before.player?.population_reserved) && queued.player.population_reserved === before.player.population_reserved + 1 && queued.player.population === before.player.population && before.player.population + before.player.population_reserved < before.player.population_cap, 'Scout must reserve one available population');
  assert.deepEqual(ids(liveUnits(before, slot)), ids(liveUnits(queued, slot)));
  return {...paidBank(before, queued, {food:40,wood:0,gold:10}), building_id:command.target, unit_type:4, population_cost:1};
}
function scoutBirth(before, queued, after, slot, buildingId) {
  sameMatch(queued, after, 60);
  assert(before.match === queued.match && before.tick < queued.tick && after.time - queued.time >= 7, 'Scout must finish its ordinary eight-second queue');
  quietQueues(after, slot);
  assert(actors(after, slot, 'building').some(building => building.id === buildingId && building.type === 0 && building.state === 2 && building.queue?.items?.length === 0), 'Paid Scout producer must finish');
  const old=liveUnits(before,slot), current=liveUnits(after,slot), fresh=current.filter(unit=>!old.some(prior=>prior.id===unit.id));
  assert(fresh.length === 1 && fresh[0].type === 4 && current.length === old.length + 1 && old.every(unit=>current.some(other=>other.id===unit.id)), 'Need exactly one newly born own paid Scout');
  assert(after.player.population === before.player.population + 1 && after.player.population_reserved === before.player.population_reserved, 'Scout reservation must convert once');
  return {unit_id:fresh[0].id,slot,unit_type:4,population_cost:1};
}
module.exports = {PROFILE, CONTRACT, FIGHTERS, paidBank, workshopPlacement, workshopCompletion, siegeRecruitment, siegeBirth, scoutMove, fighterSelection, scoutRecruitment, scoutBirth};
