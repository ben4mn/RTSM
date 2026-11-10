extends "res://tools/wildlife_test_world.gd"
## Sheep rules on the production nodes: claim by proximity, steal, the
## walk-home assist, manual herding, owner-only butchering, the wildlife gather
## bonus, spoilage of an untended carcass, and nearest-food preference.

var _claims: Array = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	build_world()
	GameManager.wildlife_claimed.connect(func(player_id: int, node: Node2D) -> void: _claims.append([player_id, node]))
	var home := Vector2i(20, 60)
	var rival_home := Vector2i(60, 20)
	building(BuildingData.BuildingType.TOWN_CENTER, home, 0)
	building(BuildingData.BuildingType.TOWN_CENTER, rival_home, 1)
	_claim_and_walk_home(home)
	_owner_only_harvest(home)
	_steal_rules(home)
	_herding()
	_gather_bonus_and_spoilage(home)
	_food_preference(home)
	_network_replicas(home)
	finish("wildlife_claim")


func _claim_and_walk_home(home: Vector2i) -> void:
	var stray: WildlifeNode = animal(1, WildlifeData.SHEEP, home + Vector2i(18, 0))
	var mate: WildlifeNode = animal(2, WildlifeData.SHEEP, home + Vector2i(18, 1))
	step(1.0)
	expect(stray.owner_id == -1 and not stray.is_harvestable_by(0) and not stray.is_harvestable_by(1), "an unclaimed stray belongs to nobody and cannot be butchered")
	var scout: Villager = worker(home + Vector2i(14, 0), 0)
	step(1.0)
	expect(stray.owner_id == -1, "a unit four tiles away does not claim")
	scout.position = world.tile_to_world(home + Vector2i(16, 0))
	step(0.6)
	expect(stray.owner_id == 0 and mate.owner_id == 0, "the first unit within three tiles claims the pair")
	expect(_claims.size() == 2 and _claims[0][0] == 0 and (_claims[0][1] == stray or _claims[0][1] == mate), "wildlife_claimed fires once per sheep for the claimer: " + str(_claims.size()))
	expect(stray.has_goal and stray.pasture_owner == 0 and not stray.manual_stay, "a claimed sheep starts walking home by itself")
	expect(world.get_wildlife_for_player(0).size() == 2 and world.get_wildlife_for_player(1).is_empty(), "get_wildlife_for_player lists the owner's flock")
	var start: Vector2 = stray.global_position
	step(2.0)
	var speed: float = start.distance_to(stray.global_position) / 2.0
	expect(speed > 20.0 and speed <= WildlifeData.SHEEP_SPEED + 0.5, "sheep trot at their own speed: %.1f" % speed)
	step(120.0, func() -> bool: return not stray.has_goal and not mate.has_goal)
	for sheep: WildlifeNode in [stray, mate]:
		var ring: int = WildlifePlacement._ring_from_town_center(world.world_to_tile(sheep.global_position), home)
		expect(not sheep.has_goal and ring >= WildlifeData.HOME_RING_MIN and ring <= WildlifeData.HOME_RING_MAX + 2, "the sheep arrives in the Town Center pasture ring: ring %d" % ring)
	expect(world.world_to_tile(stray.global_position) != world.world_to_tile(mate.global_position), "two sheep take two pasture slots")
	var rested: Vector2 = stray.global_position
	step(3.0)
	expect(stray.global_position == rested, "a pastured sheep stays put")
	clear_workers()
	clear_animals()
	_claims.clear()


func _owner_only_harvest(home: Vector2i) -> void:
	var sheep: WildlifeNode = animal(10, WildlifeData.SHEEP, home + Vector2i(6, 1), 0)
	var deer: WildlifeNode = animal(11, WildlifeData.DEER, home + Vector2i(8, 6))
	var owner_worker: Villager = worker(home + Vector2i(5, 3), 0)
	var rival_worker: Villager = worker(home + Vector2i(7, 3), 1)
	expect(sheep.is_harvestable_by(0) and not sheep.is_harvestable_by(1), "only the owner may butcher a sheep")
	expect(not rival_worker.command_gather(sheep), "a rival villager's gather order on the sheep is refused")
	expect(world.get_nearest_resource_node("food", rival_worker.global_position, 1, rival_worker) == deer, "the rival's nearest food skips the sheep it does not own")
	expect(rival_worker.command_gather(deer) and owner_worker.command_gather(deer), "deer are neutral: either player may hunt them")
	expect(owner_worker.command_gather(sheep), "the owner's gather order is accepted")
	step(10.0, func() -> bool: return sheep.phase == WildlifeNode.Phase.CARCASS)
	expect(sheep.phase == WildlifeNode.Phase.CARCASS and sheep.remaining < sheep.total_amount, "the first harvest opens the carcass")
	expect(not sheep.is_herdable_by(0), "an opened carcass can no longer be herded")
	step(60.0, func() -> bool: return deer.phase == WildlifeNode.Phase.CARCASS)
	expect(deer.phase == WildlifeNode.Phase.CARCASS, "a hunted deer becomes a carcass too")
	clear_workers()
	clear_animals()


func _steal_rules(home: Vector2i) -> void:
	director.set_walk_home(0, false)
	director.set_walk_home(1, false)
	var field: Vector2i = home + Vector2i(20, -6)
	var sheep: WildlifeNode = animal(20, WildlifeData.SHEEP, field, 0)
	var guard: Villager = worker(field + Vector2i(3, 0), 0)
	var thief: Villager = worker(field + Vector2i(1, 0), 1)
	step(1.0)
	expect(sheep.owner_id == 0, "a sheep is safe while its owner has a unit within four tiles")
	guard.position = world.tile_to_world(field + Vector2i(7, 0))
	thief.position = world.tile_to_world(field + Vector2i(3, 0))
	step(1.0)
	expect(sheep.owner_id == 0, "a rival three tiles away is too far to steal")
	thief.position = world.tile_to_world(field + Vector2i(1, 1))
	step(1.0)
	expect(sheep.owner_id == 1 and _claims.size() == 1 and _claims[0][0] == 1, "an unguarded sheep is stolen by a rival unit within two tiles")
	expect(sheep.is_harvestable_by(1) and not sheep.is_harvestable_by(0), "the thief now owns the butchering rights")
	expect(not sheep.has_goal, "with the assist off a claimed sheep waits where it stands")
	var pastured: WildlifeNode = animal(21, WildlifeData.SHEEP, home + Vector2i(-2, 1), 0)
	thief.position = world.tile_to_world(home + Vector2i(-3, 1))
	step(1.0)
	expect(pastured.owner_id == 0, "a sheep grazing beside its owner's Town Center cannot be stolen")
	director.set_walk_home(1, true)
	step(0.6)
	expect(sheep.has_goal and sheep.pasture_owner == 1, "turning the assist on sends the waiting sheep to its new owner's Town Center")
	director.set_walk_home(0, true)
	clear_workers()
	clear_animals()
	_claims.clear()


func _herding() -> void:
	var meadow := Vector2i(40, 60)
	var leader: WildlifeNode = animal(30, WildlifeData.SHEEP, meadow, 0)
	var follower: WildlifeNode = animal(31, WildlifeData.SHEEP, meadow + Vector2i(1, 0), 0)
	var distant: WildlifeNode = animal(32, WildlifeData.SHEEP, meadow + Vector2i(8, 0), 0)
	for sheep: WildlifeNode in [leader, follower, distant]:
		sheep.pasture_owner = 0
	var goal: Vector2 = world.tile_to_world(meadow + Vector2i(0, -6))
	expect(not director.order_herd(1, [leader], goal), "a rival cannot herd your sheep")
	expect(director.order_herd(0, [leader], goal), "the owner's herd order is accepted")
	expect(leader.has_goal and follower.has_goal and not distant.has_goal, "the sheep beside the leader follow; distant ones do not")
	step(60.0, func() -> bool: return not leader.has_goal and not follower.has_goal)
	expect(leader.global_position.distance_to(goal) < 2.0 and follower.global_position.distance_to(goal) < 40.0 and follower.global_position.distance_to(leader.global_position) > 8.0, "the flock arrives together without stacking")
	step(3.0)
	expect(leader.manual_stay and not leader.has_goal and leader.global_position.distance_to(goal) < 2.0, "a hand-herded sheep stays where it was sent; the assist leaves it alone")
	expect(not director.order_herd(0, [leader], Vector2(-9000.0, -9000.0)), "an order outside the map is refused")
	var packet_result: String = director._command_herd(0, {"sheep": [30], "position": [goal.x + 64.0, goal.y]}, [], null, goal + Vector2(64.0, 0.0))
	expect(packet_result == "" and leader.has_goal, "the `herd` extension command drives the same order")
	expect(director._command_herd(1, {"sheep": [30], "position": [goal.x, goal.y]}, [], null, goal) != "", "the `herd` command re-checks ownership on the authority")
	expect(WildlifeDirector._valid_herd({"sheep": [30], "position": [1.0, 2.0]}) and not WildlifeDirector._valid_herd({"position": [1.0, 2.0]}) and not WildlifeDirector._valid_herd({"sheep": [], "position": [1.0, 2.0]}), "the herd packet validator requires sheep ids and a position")
	clear_animals()


func _gather_bonus_and_spoilage(home: Vector2i) -> void:
	var sheep: WildlifeNode = animal(40, WildlifeData.SHEEP, home + Vector2i(7, 0), 0)
	sheep.total_amount = 5000
	sheep.remaining = 5000
	var bush: ResourceNode = berries(home + Vector2i(7, 8), 5000)
	var shepherd: Villager = worker(home + Vector2i(7, 1), 0)
	var forager: Villager = worker(home + Vector2i(7, 9), 0)
	for unit: Villager in [shepherd, forager]:
		unit.carry_capacity = 100000
	expect(shepherd.command_gather(sheep) and forager.command_gather(bush), "both workers accept their food source")
	step(4.0)
	var sheep_before: int = shepherd.carried_amount
	var bush_before: int = forager.carried_amount
	step(60.0)
	var ratio: float = float(shepherd.carried_amount - sheep_before) / float(maxi(1, forager.carried_amount - bush_before))
	metrics["wildlife_gather_ratio"] = snappedf(ratio, 0.001)
	expect(absf(ratio - WildlifeData.GATHER_MULTIPLIER) < 0.04, "wildlife is gathered at 1.3x the berry rate: %.3f" % ratio)
	expect(sheep.tended, "a carcass with a worker assigned counts as tended")
	var stock: int = sheep.remaining
	step(20.0)
	expect(sheep.remaining < stock and shepherd.carried_amount > 0, "the tended carcass only loses what is gathered")
	shepherd.command_stop()
	step(0.5)
	stock = sheep.remaining
	step(20.0)
	expect(not sheep.tended and stock - sheep.remaining == 5, "an untended carcass spoils 0.25 food per second: lost %d in 20 s" % (stock - sheep.remaining))
	var live: WildlifeNode = animal(41, WildlifeData.SHEEP, home + Vector2i(9, 0), 0)
	step(20.0)
	expect(live.remaining == live.total_amount, "a living sheep never spoils")
	sheep.remaining = 2
	step(12.0)
	expect(not is_instance_valid(sheep) or sheep.remaining <= 0, "a carcass can spoil away completely")
	expect(sheep not in director.nodes and not world.get_wildlife_nodes().has(sheep), "a spent carcass leaves the registry")
	world.resource_nodes.erase(bush.tile_position)
	bush.free()
	clear_workers()
	clear_animals()


func _food_preference(home: Vector2i) -> void:
	var from: Vector2 = world.tile_to_world(home + Vector2i(6, 6))
	var bush: ResourceNode = berries(home + Vector2i(6, 7))
	var sheep: WildlifeNode = animal(50, WildlifeData.SHEEP, home + Vector2i(1, 7), 0)
	var second: WildlifeNode = animal(51, WildlifeData.SHEEP, home + Vector2i(5, 9), 0)
	var seeker: Villager = worker(home + Vector2i(6, 6), 0)
	expect(world.get_nearest_resource_node("food", from, 0, seeker) == second, "nearest food prefers an owned sheep over a closer berry bush")
	expect(world.get_nearest_reachable_resource_node("food", from, 0, {}, seeker) == second, "the reachable lookup has the same preference")
	sheep.harvest(1)
	expect(world.get_nearest_resource_node("food", from, 0, seeker) == sheep, "an opened carcass is preferred over a fresh sheep (butcher one at a time)")
	expect(world.get_nearest_resource_node("food", from, 1, seeker) == bush, "the rival's lookup ignores another player's flock")
	expect(world.get_nearest_resource_node("food", from, -1, seeker) == bush, "the neutral lookup keeps plain distance ordering")
	var opening: Array = [seeker, worker(home + Vector2i(5, 6), 0), worker(home + Vector2i(4, 6), 0)]
	expect(WildlifeDirector.assign_opening_villagers(self, opening), "opening villagers are assigned to the flock")
	var targets: Dictionary = {}
	for unit: Villager in opening:
		targets[unit.gather_target] = true
		expect(unit.get_economy_task() == "food", "every opening villager starts on food")
	expect(targets.size() == 1 and targets.keys()[0] is WildlifeNode, "all opening villagers share one sheep")


## The `wildlife` snapshot section: what the server sends one recipient, and
## the inert replicas a client builds from it (owners remapped to local ids).
func _network_replicas(home: Vector2i) -> void:
	clear_workers()
	clear_animals()
	var sheep: WildlifeNode = animal(60, WildlifeData.SHEEP, home + Vector2i(6, 0), 1)
	var boar: WildlifeNode = animal(61, WildlifeData.BOAR, home + Vector2i(10, 0))
	director.walk_home[1] = false
	var authority_copy: Variant = director._snapshot_rows(1)
	director._apply_snapshot_rows(authority_copy)
	expect(not sheep.replica and director.nodes.size() == 2 and director.walk_home[0], "the authority ignores an incoming wildlife section")
	expect(authority_copy is Dictionary and authority_copy.rows.size() == 2 and authority_copy.walk_home == false, "the section lists the visible animals and the recipient's assist setting")
	var wire: Variant = JSON.parse_string(JSON.stringify(authority_copy))
	expect(wire is Dictionary and wire.rows.size() == 2 and wire.rows[0].size() == 11, "rows survive the JSON wire format")
	clear_animals()
	NetworkSession.online = true
	NetworkSession.server_mode = false
	NetworkSession.player_slot = 1
	director._apply_snapshot_rows(wire)
	var sheep_replica: WildlifeNode = director.by_id.get(60) as WildlifeNode
	var boar_replica: WildlifeNode = director.by_id.get(61) as WildlifeNode
	expect(sheep_replica != null and sheep_replica.replica and sheep_replica.owner_id == 0 and sheep_replica.is_harvestable_by(0) and not director.walk_home[0], "the client builds a replica owned by its local player 0")
	expect(boar_replica != null and boar_replica.kind == WildlifeData.BOAR and boar_replica.is_fighting() and boar_replica.hp == WildlifeData.BOAR_MAX_HP and boar_replica.remaining == int(WildlifeData.FOOD[WildlifeData.BOAR]), "the boar replica carries health and stock")
	expect(world.is_resource_target_valid(sheep_replica, "food", 0) and world.get_wildlife_for_player(0) == [sheep_replica], "replicas are registered harvestables for local input")
	var villager: Villager = worker(home + Vector2i(9, 0), 0)
	expect(not sheep_replica.walk_to(sheep_replica.global_position + Vector2(64.0, 0.0)) and not boar_replica.absorb_strike(villager) and boar_replica.hp == WildlifeData.BOAR_MAX_HP, "a replica never simulates")
	var before: Vector2 = sheep_replica.global_position
	wire.rows[0][2] = float(wire.rows[0][2]) + 64.0
	wire.rows[0][6] = 0.0
	wire.rows[1][7] = float(WildlifeNode.Phase.CARCASS)
	wire.rows[1][9] = 0.0
	wire.rows[1][4] = 300.0
	director._apply_snapshot_rows(wire)
	for tick: int in 30:
		sheep_replica._process(STEP)
	expect(sheep_replica.global_position.x > before.x + 40.0 and sheep_replica.owner_id == 1 and not sheep_replica.is_harvestable_by(0), "a replica eases to the new position and follows an ownership change")
	expect(boar_replica.phase == WildlifeNode.Phase.CARCASS and not boar_replica.is_fighting() and boar_replica.remaining == 300, "a felled boar becomes a carcass on the client")
	wire.rows.remove_at(0)
	director._apply_snapshot_rows(wire)
	expect(not director.by_id.has(60) and not world.get_wildlife_nodes().has(sheep_replica) and director.by_id.has(61), "an animal that leaves sight is retired")
	NetworkSession.online = false
	NetworkSession.player_slot = 0
	clear_workers()
	clear_animals()
