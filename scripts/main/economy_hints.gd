class_name EconomyHints
extends Node
## Workstream I2: two glanceable economy hints for the local player, each a
## tappable toast that stays while it still applies (ToastLane keep_while).
##
## - Running out: wood or gold workers are on their last local patch. The toast
##   names it ("Gold is running out · tap: next gold"); a tap jumps the camera
##   to the nearest explored patch elsewhere and, when no drop-off stands near
##   it and a Resource Camp is affordable, opens Camp placement there.
## - Bottleneck: one resource is nearly empty while another piles up. The
##   toast offers to move three workers from the full stock to the short one
##   (the Economy sheet's own allocation path, so online it is the existing
##   `allocate` command).
##
## Presentation only: reads the local player's own workers and explored
## resources; never changes the simulation on its own.

const POLL_SECONDS: float = 2.0
const LOCAL_RADIUS_TILES: float = 6.0
const CAMP_NEAR_TILES: float = 5.0
## "Running out": the worked patch holds less than this per worker on it.
const RUNNING_OUT_PER_WORKER: int = 45
const RUNNING_OUT_FLOOR: int = 120
const RUNNING_OUT_COOLDOWN_MSEC: int = 75000
const BOTTLENECK_LOW: int = 60
const BOTTLENECK_HIGH: int = 650
const BOTTLENECK_SECONDS: float = 20.0
const BOTTLENECK_COOLDOWN_MSEC: int = 90000
const BOTTLENECK_MOVE: int = 3
const HINT_START_SECONDS: float = 90.0
const RESOURCES: PackedStringArray = ["food", "wood", "gold"]

var main: Node = null
var _poll: float = 0.0
## resource -> {"text": String, "target": WeakRef}
var _running_out: Dictionary = {}
var _running_out_msec: Dictionary = {}
var _bottleneck_text: String = ""
var _bottleneck_pair: Array = []
var _bottleneck_since: float = -1.0
var _bottleneck_msec: int = -BOTTLENECK_COOLDOWN_MSEC


static func install(match_main: Node) -> void:
	var node := EconomyHints.new()
	node.name = "EconomyHints"
	node.main = match_main
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	match_main.add_child(node)


static func of(match_main: Node) -> EconomyHints:
	return match_main.get_node_or_null("EconomyHints") as EconomyHints if is_instance_valid(match_main) else null


func _process(delta: float) -> void:
	if not is_instance_valid(main) or GameManager.current_state != GameManager.GameState.PLAYING:
		return
	if NetworkSession.server_mode or main.get("hud") == null:
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL_SECONDS
	if GameManager.game_time < HINT_START_SECONDS:
		return
	refresh()


func _map() -> Node2D:
	return main.get("game_map") as Node2D


func _hud() -> Node:
	return main.get("hud") as Node


func _workers() -> Array[Villager]:
	var result: Array[Villager] = []
	var rosters: Variant = main.get("_player_units")
	if not rosters is Array or (rosters as Array).is_empty():
		return result
	for entry: Variant in (rosters as Array)[0]:
		if is_instance_valid(entry) and entry is Villager and (entry as Villager).player_owner == 0 and (entry as Villager).current_state != UnitBase.State.DEAD:
			result.append(entry as Villager)
	return result


func refresh() -> void:
	var workers: Array[Villager] = _workers()
	for resource: String in ["wood", "gold"]:
		_refresh_running_out(resource, workers)
	_refresh_bottleneck(workers)


# -----------------------------------------------------------------------------
#  Running out
# -----------------------------------------------------------------------------

func _resource_nodes(resource: String) -> Array[ResourceNode]:
	var result: Array[ResourceNode] = []
	var map: Node2D = _map()
	if map == null:
		return result
	for entry: Variant in (map.get("resource_nodes") as Dictionary).values():
		if is_instance_valid(entry) and entry is ResourceNode and (entry as ResourceNode).resource_type == resource and (entry as ResourceNode).remaining > 0:
			result.append(entry as ResourceNode)
	return result


func _known(node: ResourceNode) -> bool:
	var map: Node2D = _map()
	var fog: Node = map.get("fog_of_war") as Node
	if fog == null or not fog.has_method("is_explored"):
		return true
	return bool(fog.call("is_explored", node.tile_position))


## Idle, unselected villagers whose remembered job (TouchEconomy) was
## `resource`, with where that job was: a crew whose patch ran out.
func stranded(resource: String, workers: Array[Villager] = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var economy: TouchEconomy = TouchEconomy.of(main)
	if economy == null:
		return result
	if workers.is_empty():
		workers = _workers()
	for worker: Villager in workers:
		if worker.current_state != UnitBase.State.IDLE or worker.is_selected or not worker.queued_orders.is_empty() or worker.is_auto_recovering():
			continue
		var job: Dictionary = economy._jobs.get(worker.get_instance_id(), {})
		if str(job.get("resource", "")) != resource or job.get("build") is WeakRef and is_instance_valid((job["build"] as WeakRef).get_ref()):
			continue
		result.append({"worker": worker, "position": job.get("position", worker.global_position)})
	return result


## Facts for one resource: workers on it (and idle ones whose patch ran out),
## the stock left around their patches and the nearest explored patch beyond
## them (null when none is known).
func assess(resource: String, workers: Array[Villager] = []) -> Dictionary:
	if workers.is_empty():
		workers = _workers()
	var anchors: Array[Vector2] = []
	var on_it: int = 0
	var points: Array[Vector2] = []
	for worker: Villager in workers:
		if worker.get_economy_task() != resource:
			continue
		on_it += 1
		var target: Variant = worker.gather_target
		points.append((target as Node2D).global_position if is_instance_valid(target) and target is Node2D else worker.global_position)
	var idle_crew: Array[Dictionary] = stranded(resource, workers)
	for entry: Dictionary in idle_crew:
		points.append(entry.position)
	for anchor: Vector2 in points:
		var duplicate: bool = false
		for existing: Vector2 in anchors:
			if existing.distance_squared_to(anchor) < 1600.0:
				duplicate = true
				break
		if not duplicate:
			anchors.append(anchor)
	var radius: float = LOCAL_RADIUS_TILES * float(MapData.TILE_WIDTH)
	var local: int = 0
	var next_node: ResourceNode = null
	var next_distance: float = INF
	var centre: Vector2 = Vector2.ZERO
	for anchor: Vector2 in anchors:
		centre += anchor
	if not anchors.is_empty():
		centre /= float(anchors.size())
	for node: ResourceNode in _resource_nodes(resource):
		var near: bool = false
		for anchor: Vector2 in anchors:
			if node.global_position.distance_squared_to(anchor) <= radius * radius:
				near = true
				break
		if near:
			local += node.remaining
			continue
		if anchors.is_empty() or not _known(node):
			continue
		var distance: float = node.global_position.distance_squared_to(centre)
		if distance < next_distance:
			next_distance = distance
			next_node = node
	var crew: int = on_it + idle_crew.size()
	var limit: int = maxi(RUNNING_OUT_FLOOR, crew * RUNNING_OUT_PER_WORKER)
	# A lone parked villager is the player's choice; two or more idle from one
	# job is a crew whose patch ran out.
	var stranded_crew: bool = idle_crew.size() >= 2
	return {"workers": on_it, "stranded": idle_crew, "local": local, "running_out": (on_it > 0 or stranded_crew) and local < limit, "ran_out": stranded_crew and local < limit, "next": next_node}


func _refresh_running_out(resource: String, workers: Array[Villager]) -> void:
	var facts: Dictionary = assess(resource, workers)
	var hud: Node = _hud()
	var showing: Dictionary = _running_out.get(resource, {})
	if not bool(facts.running_out):
		if not showing.is_empty():
			hud.call("dismiss_notification", str(showing.text))
			_running_out.erase(resource)
		# Stock recovered (a new patch is worked): the next shortage may warn again.
		if int(facts.local) >= maxi(RUNNING_OUT_FLOOR, int(facts.workers) * RUNNING_OUT_PER_WORKER) * 2:
			_running_out_msec.erase(resource)
			_running_out_msec.erase(resource + ":out")
		return
	# A shown "running out" gives way to "ran out" once the crew stands idle.
	if not showing.is_empty() and (bool(showing.get("ran_out", false)) or not bool(facts.ran_out)):
		return
	if not showing.is_empty():
		hud.call("dismiss_notification", str(showing.text))
		_running_out.erase(resource)
	var now: int = Time.get_ticks_msec()
	var key: String = resource + (":out" if bool(facts.ran_out) else "")
	if _running_out_msec.has(key) and now - int(_running_out_msec[key]) < RUNNING_OUT_COOLDOWN_MSEC:
		return
	_running_out_msec[key] = now
	var next: ResourceNode = facts.next as ResourceNode
	var idle: int = (facts.stranded as Array).size()
	var opening: String = "%s ran out · %d idle" % [resource.capitalize(), idle] if bool(facts.ran_out) else "%s is running out" % resource.capitalize()
	var text: String
	if next == null:
		text = "%s · scout for more" % opening
		hud.call("show_notification", text, KingdomTheme.AMBER, 6.0, Callable(), 1)
		_running_out[resource] = {"text": text, "target": null, "ran_out": bool(facts.ran_out)}
		return
	text = "%s · tap: %s" % [opening, "send them to the next %s" % resource if bool(facts.ran_out) else "next %s" % resource]
	_running_out[resource] = {"text": text, "target": weakref(next), "ran_out": bool(facts.ran_out)}
	hud.call("show_notification", text, KingdomTheme.AMBER, 8.0, show_next_patch.bind(resource), 2,
		func() -> bool: return _running_out.has(resource) and str((_running_out[resource] as Dictionary).text) == text)


## Tap: camera to the next known patch; a Camp placement starts there when no
## drop-off is close and one is affordable.
func show_next_patch(resource: String) -> bool:
	var entry: Dictionary = _running_out.get(resource, {})
	_running_out.erase(resource)
	var target_ref: Variant = entry.get("target")
	var target: ResourceNode = (target_ref as WeakRef).get_ref() as ResourceNode if target_ref is WeakRef else null
	if target == null or not is_instance_valid(target):
		target = assess(resource).next as ResourceNode
	if target == null:
		return false
	if main.has_method("_on_minimap_clicked"):
		main.call("_on_minimap_clicked", target.global_position)
	# A crew whose patch ran out walks to the next one (online: selected, so the
	# player's next tap on the patch or a Camp spot is their order).
	var crew: Array[Node2D] = []
	for idle_entry: Dictionary in stranded(resource):
		crew.append(idle_entry.worker as Node2D)
	var map: Node2D = _map()
	if not crew.is_empty() and not NetworkSession.is_client():
		var in_sight: bool = map != null and bool(map.call("is_resource_target_visible_to_player", target, 0))
		for worker: Node2D in crew:
			var villager := worker as Villager
			# Out of sight the order is the fog-safe remembered one (position only).
			if not (in_sight and villager.command_gather(target)):
				villager.call("_try_remembered_resource", map, resource)
	if not crew.is_empty() and map != null and map.get("selection_mgr") != null:
		map.selection_mgr.select_many(crew)
	if needs_camp_near(target.global_position) and ResourceManager.can_afford(0, BuildingData.get_building_cost(BuildingData.BuildingType.RESOURCE_CAMP, 0)):
		var strategy: Node = main.get_node_or_null("StrategyController")
		if strategy != null and strategy.has_method("plan_building"):
			strategy.call("plan_building", BuildingData.BuildingType.RESOURCE_CAMP)
			_hud().call("show_notification", "Tap beside the %s for a Camp" % resource, KingdomTheme.PARCHMENT, 3.0)
	return true


func needs_camp_near(position: Vector2) -> bool:
	var radius: float = CAMP_NEAR_TILES * float(MapData.TILE_WIDTH)
	var rosters: Variant = main.get("_player_buildings")
	if not rosters is Array or (rosters as Array).is_empty():
		return true
	for entry: Variant in (rosters as Array)[0]:
		if not is_instance_valid(entry) or not entry is BuildingBase:
			continue
		var building := entry as BuildingBase
		if building.player_owner != 0 or building.state == BuildingBase.State.DESTROYED:
			continue
		if building.has_method("is_drop_off_point") and (building.is_drop_off_point("gold") or building.is_drop_off_point("wood")) \
				and building.global_position.distance_to(position) <= radius:
			return false
	return true


# -----------------------------------------------------------------------------
#  Bottleneck: one stock short while another floats
# -----------------------------------------------------------------------------

func _refresh_bottleneck(workers: Array[Villager]) -> void:
	var hud: Node = _hud()
	var counts: Dictionary = {"food": 0, "wood": 0, "gold": 0}
	for worker: Villager in workers:
		var task: String = worker.get_economy_task()
		if counts.has(task):
			counts[task] = int(counts[task]) + 1
	var low: String = ""
	var high: String = ""
	var high_amount: int = 0
	for resource: String in RESOURCES:
		var amount: int = ResourceManager.get_resource(0, resource)
		if amount < BOTTLENECK_LOW and low.is_empty():
			low = resource
		if amount >= BOTTLENECK_HIGH and amount > high_amount and int(counts[resource]) >= BOTTLENECK_MOVE + 1:
			high = resource
			high_amount = amount
	var pair: Array = [high, low]
	if low.is_empty() or high.is_empty() or low == high:
		_bottleneck_since = -1.0
		_retire_bottleneck(hud)
		return
	if pair != _bottleneck_pair:
		_retire_bottleneck(hud)
		_bottleneck_pair = pair
		_bottleneck_since = GameManager.game_time
		return
	if not _bottleneck_text.is_empty() or GameManager.game_time - _bottleneck_since < BOTTLENECK_SECONDS:
		return
	var now: int = Time.get_ticks_msec()
	if now - _bottleneck_msec < BOTTLENECK_COOLDOWN_MSEC:
		return
	_bottleneck_msec = now
	_bottleneck_text = "%s %d banked, %s short · tap: %d to %s" % [high.capitalize(), high_amount, low, BOTTLENECK_MOVE, low]
	var shown: String = _bottleneck_text
	hud.call("show_notification", _bottleneck_text, KingdomTheme.AMBER, 8.0, rebalance.bind(high, low), 2,
		func() -> bool: return _bottleneck_text == shown)


func _retire_bottleneck(hud: Node) -> void:
	if not _bottleneck_text.is_empty() and is_instance_valid(hud):
		hud.call("dismiss_notification", _bottleneck_text)
	_bottleneck_text = ""
	_bottleneck_pair = []


## Tap: move BOTTLENECK_MOVE workers from `source` to `destination` through
## the Economy sheet's allocation (the existing `allocate` command online).
func rebalance(source: String, destination: String) -> int:
	_bottleneck_text = ""
	var strategy: Node = main.get_node_or_null("StrategyController")
	if strategy == null or not strategy.has_method("allocate_workers"):
		return 0
	return int(strategy.call("allocate_workers", source, destination, BOTTLENECK_MOVE))
