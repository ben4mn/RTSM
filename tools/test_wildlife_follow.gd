extends "res://tools/wildlife_test_world.gd"
## L1 herding: a sheep claimed by a Scout follows it in a staggered little
## flock, slightly slower than the Scout; near its owner's Town Center the
## flock is handed over and walks to graze there on its own. A fallen or
## garrisoned leader leaves its sheep idle (still owned) until another own
## unit comes by. Manual herding and a butchering villager take precedence,
## and the follow state survives a save round trip.

const STATE := preload("res://scripts/main/solo_match_state.gd")

var _extra: Array[UnitBase] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	build_world()
	var home := Vector2i(20, 60)
	building(BuildingData.BuildingType.TOWN_CENTER, home, 0)
	building(BuildingData.BuildingType.TOWN_CENTER, Vector2i(60, 20), 1)
	_follow_and_deliver(home)
	_leader_lost(home)
	_herd_and_butcher_override(home)
	_save_round_trip(home)
	_snapshot_flag(home)
	finish("wildlife_follow")


func _scout(tile: Vector2i, owner: int = 0) -> UnitBase:
	var unit: UnitBase = load("res://scenes/units/scout.tscn").instantiate()
	unit.player_owner = owner
	unit.position = world.tile_to_world(tile)
	world.get_node("UnitsContainer").add_child(unit)
	unit.set_process(false)
	_extra.append(unit)
	return unit


## Step the extra (non-villager) units together with the fixture.
func run(seconds: float, until: Callable = Callable()) -> float:
	var elapsed: float = 0.0
	while elapsed < seconds:
		for unit: UnitBase in _extra:
			if is_instance_valid(unit) and unit.is_inside_tree() and unit.current_state != UnitBase.State.DEAD:
				unit._process(STEP)
		elapsed += step(STEP)
		if until.is_valid() and until.call():
			break
	return elapsed


func _clear_extra() -> void:
	for unit: UnitBase in _extra:
		if is_instance_valid(unit):
			unit.free()
	_extra.clear()


func _follow_and_deliver(home: Vector2i) -> void:
	var flock: Array[WildlifeNode] = [
		animal(1, WildlifeData.SHEEP, home + Vector2i(22, 0)),
		animal(2, WildlifeData.SHEEP, home + Vector2i(22, 1)),
		animal(3, WildlifeData.SHEEP, home + Vector2i(23, 0)),
	]
	var scout: UnitBase = _scout(home + Vector2i(27, 0))
	expect(scout.unit_type == UnitData.UnitType.SCOUT, "the fixture Scout is a Scout")
	run(1.0)
	expect(flock[0].owner_id == -1, "a Scout four tiles away does not claim")
	scout.position = world.tile_to_world(home + Vector2i(24, 0))
	run(0.6)
	var slots: Dictionary = {}
	for sheep: WildlifeNode in flock:
		expect(sheep.owner_id == 0 and sheep.is_following() and sheep.get_leader() == scout, "a claimed sheep follows the Scout that found it")
		slots[sheep.follow_slot] = true
	expect(slots.size() == 3 and slots.has(0) and slots.has(2), "the flock takes staggered places 0, 1, 2 behind the Scout: %s" % str(slots.keys()))
	expect(flock[0].pasture_owner == -1 and not flock[0].manual_stay, "a following sheep is not pastured yet")

	# Lead the flock along, away from home.
	var starts: Array[Vector2] = []
	for sheep: WildlifeNode in flock:
		starts.append(sheep.global_position)
	scout.command_move(world.tile_to_world(home + Vector2i(34, -8)))
	var sample_from: Vector2 = flock[0].global_position
	run(1.5)
	var sheep_speed: float = sample_from.distance_to(flock[0].global_position) / 1.5
	metrics["follow_speed"] = snappedf(sheep_speed, 0.1)
	expect(sheep_speed <= scout.get_movement_speed() * WildlifeData.FOLLOW_SPEED_FACTOR + 1.0 and sheep_speed > WildlifeData.SHEEP_SPEED * 0.8, "following sheep walk a little slower than the Scout: %.1f vs %.1f" % [sheep_speed, scout.get_movement_speed()])
	run(25.0, func() -> bool: return scout.current_state == UnitBase.State.IDLE)
	run(6.0)
	for index: int in flock.size():
		var sheep: WildlifeNode = flock[index]
		var behind: float = WildlifeData.tile_distance(sheep.global_position, scout.global_position)
		expect(sheep.is_following() and behind < 3.5, "sheep %d caught up with the stopped Scout: %.1f tiles" % [index, behind])
		expect(starts[index].distance_to(sheep.global_position) > 200.0, "sheep %d travelled with the Scout" % index)
		expect(sheep.global_position.distance_to(scout.global_position) >= WildlifeData.FOLLOW_TRAIL_WORLD - 6.0, "sheep %d keeps a little distance from the Scout" % index)
	for a: int in flock.size():
		for b: int in range(a + 1, flock.size()):
			expect(flock[a].global_position.distance_to(flock[b].global_position) > 6.0, "followers %d and %d do not stack" % [a, b])
	metrics["flock_spread"] = snappedf(flock[0].global_position.distance_to(flock[2].global_position), 0.1)

	# Bring them home: inside the radius the flock leaves the Scout and grazes.
	scout.command_move(world.tile_to_world(home + Vector2i(9, 1)))
	run(60.0, func() -> bool:
		for sheep: WildlifeNode in flock:
			if sheep.is_following() or sheep.has_goal:
				return false
		return true)
	var tiles: Dictionary = {}
	for index: int in flock.size():
		var sheep: WildlifeNode = flock[index]
		var ring: int = WildlifePlacement._ring_from_town_center(world.world_to_tile(sheep.global_position), home)
		expect(not sheep.is_following() and not sheep.has_goal and sheep.pasture_owner == 0, "sheep %d left the Scout at home and settled" % index)
		expect(ring >= WildlifeData.HOME_RING_MIN and ring <= WildlifeData.HOME_RING_MAX + 2, "sheep %d grazes in the Town Center pasture ring: ring %d" % [index, ring])
		tiles[world.world_to_tile(sheep.global_position)] = true
	expect(tiles.size() == 3, "the flock spreads over three pasture tiles")
	var rested: Vector2 = flock[1].global_position
	scout.command_move(world.tile_to_world(home + Vector2i(30, 0)))
	run(6.0)
	expect(flock[1].global_position == rested and not flock[1].is_following(), "a pastured sheep stays when the Scout rides off again")
	_clear_extra()
	clear_workers()
	clear_animals()


func _leader_lost(home: Vector2i) -> void:
	var field: Vector2i = home + Vector2i(26, -16)
	var sheep: WildlifeNode = animal(10, WildlifeData.SHEEP, field)
	var scout: UnitBase = _scout(field + Vector2i(2, 0))
	run(0.6)
	expect(sheep.get_leader() == scout, "the second Scout picks up a sheep")
	scout.command_move(world.tile_to_world(field + Vector2i(6, 4)))
	run(1.5)
	scout.die()
	run(1.0)
	expect(sheep.owner_id == 0 and not sheep.is_following(), "a fallen leader leaves its sheep, still owned")
	var resting: Vector2 = sheep.global_position
	run(3.0)
	expect(sheep.global_position == resting and not sheep.has_goal, "the sheep idles where it stopped")
	var shepherd: Villager = worker(world.world_to_tile(sheep.global_position) + Vector2i(2, 1), 0)
	run(0.6)
	expect(sheep.is_following() and sheep.get_leader() == shepherd, "any own unit that comes by resumes the follow")
	# Garrisoned units leave the scene tree (garrison.gd).
	var container: Node = shepherd.get_parent()
	container.remove_child(shepherd)
	run(1.0)
	expect(not sheep.is_following() and sheep.owner_id == 0, "a garrisoned leader also leaves its sheep")
	container.add_child(shepherd)
	run(0.6)
	expect(sheep.get_leader() == shepherd, "out again, the villager picks the sheep back up")
	_clear_extra()
	clear_workers()
	clear_animals()


func _herd_and_butcher_override(home: Vector2i) -> void:
	var field: Vector2i = home + Vector2i(26, -16)
	var herded: WildlifeNode = animal(20, WildlifeData.SHEEP, field)
	var butchered: WildlifeNode = animal(21, WildlifeData.SHEEP, field + Vector2i(1, 1))
	var scout: UnitBase = _scout(field + Vector2i(2, 0))
	run(0.6)
	expect(herded.is_following() and butchered.is_following(), "both sheep follow the Scout")
	var meadow: Vector2 = world.tile_to_world(field + Vector2i(-4, 0))
	expect(director.order_herd(0, [herded], meadow), "a hand herd order is accepted")
	expect(not herded.is_following() and herded.manual_stay, "a hand-herded sheep leaves the follow and stays where it is sent")
	var butcher: Villager = worker(field + Vector2i(0, 3), 0)
	expect(butcher.command_gather(butchered), "the owner's villager may butcher a following sheep")
	run(0.6)
	expect(not butchered.is_following(), "a sheep a villager is coming to butcher stands still for them")
	scout.command_move(world.tile_to_world(field + Vector2i(8, 0)))
	run(4.0)
	expect(not herded.is_following() and herded.manual_stay, "the Scout riding past does not pull a hand-herded sheep along")
	_clear_extra()
	clear_workers()
	clear_animals()


func _save_round_trip(home: Vector2i) -> void:
	var field: Vector2i = home + Vector2i(26, -16)
	var first: WildlifeNode = animal(30, WildlifeData.SHEEP, field)
	var second: WildlifeNode = animal(31, WildlifeData.SHEEP, field + Vector2i(1, 0))
	var scout: UnitBase = _scout(field + Vector2i(2, 1))
	run(0.6)
	expect(first.get_leader() == scout and second.get_leader() == scout, "two sheep follow before the save")
	var slot_first: int = first.follow_slot
	var slot_second: int = second.follow_slot
	var codec: RefCounted = STATE.new()
	var scout_id: int = codec.track(scout)
	var saved: Dictionary = director._capture(codec)
	clear_animals()
	var restore_codec: RefCounted = STATE.new()
	restore_codec.bind(scout_id, scout)
	director._restore(saved, restore_codec)
	for node: WildlifeNode in director.nodes:
		node.set_process(false)
	var again_first: WildlifeNode = director.by_id.get(30) as WildlifeNode
	var again_second: WildlifeNode = director.by_id.get(31) as WildlifeNode
	expect(again_first != null and again_second != null, "both sheep are restored")
	if again_first != null and again_second != null:
		expect(again_first.get_leader() == scout and again_second.get_leader() == scout, "the restored sheep still follow the Scout")
		expect(again_first.follow_slot == slot_first and again_second.follow_slot == slot_second, "flock places round-trip")
		expect(again_first.pasture_owner == -1 and again_first.owner_id == 0, "a restored follower is owned and not pastured")
		scout.command_move(world.tile_to_world(field + Vector2i(8, 2)))
		run(8.0)
		expect(WildlifeData.tile_distance(again_first.global_position, scout.global_position) < 3.5, "after the restore the flock keeps following")
	_clear_extra()
	clear_workers()
	clear_animals()


func _snapshot_flag(home: Vector2i) -> void:
	var field: Vector2i = home + Vector2i(26, -16)
	animal(40, WildlifeData.SHEEP, field)
	_scout(field + Vector2i(2, 0))
	run(0.6)
	var wire: Variant = JSON.parse_string(JSON.stringify(director._snapshot_rows(0)))
	expect(wire is Dictionary and wire.rows.size() == 1 and wire.rows[0].size() == 12 and int(wire.rows[0][11]) == 1, "the wildlife row carries the follow flag")
	clear_animals()
	NetworkSession.online = true
	NetworkSession.server_mode = false
	NetworkSession.player_slot = 0
	director._apply_snapshot_rows(wire)
	var replica: WildlifeNode = director.by_id.get(40) as WildlifeNode
	expect(replica != null and replica.replica and replica.is_following() and replica.get_leader() == null, "a client replica shows the server's follow state")
	NetworkSession.online = false
	_clear_extra()
	clear_workers()
	clear_animals()
