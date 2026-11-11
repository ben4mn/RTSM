class_name TouchEconomy
extends Node2D
## Workstream H: running a 40-villager economy by touch without bookkeeping.
##
## One node per match (installed from `main._register_match_extensions()`):
## - Job memory (authority): what each human-controlled villager last worked
##   on, so "Back to work" can send raid-scattered or idled crews back with one
##   tap. Never saved; a restored match simply starts with an empty memory.
## - "Back to work" offer (local player): a tappable toast when two or more
##   unselected villagers stand idle but still have a job to return to.
## - Housing warning (local player): two population slots before being housed,
##   a tappable "House" toast that places a House beside the existing ones
##   (nearest free worker builds it) with an Undo toast in solo.
## - Town Center idle mark (local player): a small hourglass ring above an own
##   Town Center that is neither training nor researching.
## - Farm ring: `place_farm_for(worker)` puts a Farm on a tidy ring around the
##   nearest Town Center / Mill for the "+ Food" button when no food is left.
## - Auto-reseed is on by default for the human seat (Farms are finite).
##
## Network: one ext command `back_to_work {ids}` (authority runs the same
## function). House and Farm placement reuse the built-in `place` command.

const POLL_SECONDS: float = 0.5
const JOB_POLL_SECONDS: float = 1.0
const OFFER_MIN_IDLE: int = 2
const OFFER_COOLDOWN_MSEC: int = 25000
const OFFER_SETTLE_SECONDS: float = 2.5
const HOUSE_WARNING_SLOTS: int = 2
const HOUSE_WARNING_GRACE_SECONDS: float = 20.0
const HOUSE_REPEAT_MSEC: int = 15000
const TC_IDLE_GRACE_SECONDS: float = 2.0
const SITE_SEARCH_RADIUS: int = 7
const FARM_RING_RADIUS: int = 6
const UNDO_SECONDS: float = 7.0
const FARM_AFTER_WORK_SECONDS: float = 30.0
## No automatic Farm while this much food is already banked (wood is scarcer).
const FARM_FOOD_BANK_LIMIT: int = 800
const BACK_TO_WORK_TEXT: String = "Back to work · %d · tap"
const INK := Color("1d2b2c")
const AMBER := Color("e8bf77")
const TRACK := Color("4a5c58")

var main: Node = null
## instance id -> {"kind", "resource", "target": WeakRef, "position", "build": WeakRef}
var _jobs: Dictionary = {}
var _poll: float = 0.0
var _job_poll: float = 0.0
var _offer_text: String = ""
var _offer_count: int = 0
var _offer_msec: int = -OFFER_COOLDOWN_MSEC
var _offer_pending_seconds: float = 0.0
var _house_warned_cap: int = -1
var _house_toast: String = ""
var _house_toast_until_msec: int = 0
var _undo_toast: String = ""
var _idle_centers: Array[BuildingBase] = []
var _tc_busy_at: Dictionary = {}  # instance id -> game_time last seen busy
var _auto_reseed_applied: bool = false
var _selection_hooked: bool = false
var _lures: Array[Dictionary] = []  # {"worker": WeakRef, "boar": WeakRef, "until": game seconds}
var _lure_poll: float = 0.0
const LURE_SECONDS: float = 25.0
const LURE_REENGAGE_TILES: float = 3.0


static func install(match_main: Node) -> void:
	var node := TouchEconomy.new()
	node.name = "TouchEconomy"
	node.main = match_main
	node.z_index = 89
	node.process_mode = Node.PROCESS_MODE_PAUSABLE
	match_main.add_child(node)
	match_main.ext.register_command("back_to_work", node._command_back_to_work, func(p: Dictionary) -> bool: return p.get("ids") is Array)
	match_main.ext.register_command("dropoff", node._command_dropoff, func(p: Dictionary) -> bool: return p.get("ids") is Array and p.has("target"))
	match_main.ext.register_command("lure", node._command_lure, func(p: Dictionary) -> bool: return p.get("ids") is Array and p.has("target"))


static func of(match_main: Node) -> TouchEconomy:
	return match_main.get_node_or_null("TouchEconomy") as TouchEconomy if is_instance_valid(match_main) else null


func _process(delta: float) -> void:
	if not is_instance_valid(main) or GameManager.current_state != GameManager.GameState.PLAYING:
		return
	if not _selection_hooked:
		_hook_selection()
	if _is_authority():
		_job_poll -= delta
		if _job_poll <= 0.0:
			_job_poll = JOB_POLL_SECONDS
			_remember_jobs()
		if not _lures.is_empty():
			_lure_poll -= delta
			if _lure_poll <= 0.0:
				_lure_poll = 0.25
				_advance_lures()
		if not _auto_reseed_applied:
			_auto_reseed_applied = true
			if GameManager.game_time < 5.0:
				for player_id: int in _human_seats():
					FarmPlots.set_auto_reseed(player_id, true)
	if _headless():
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL_SECONDS
	_refresh_idle_centers()
	_refresh_back_to_work_offer(POLL_SECONDS)
	_refresh_house_warning()


func _headless() -> bool:
	return NetworkSession.server_mode or main.get("hud") == null


func _is_authority() -> bool:
	return not NetworkSession.is_client()


func _human_seats() -> Array[int]:
	var seats: Array[int] = []
	for player_id: int in [0, 1]:
		if NetworkSession.server_mode or player_id == 0:
			if main.has_method("_ai_for") and main.call("_ai_for", player_id) != null and not NetworkSession.server_mode:
				continue
			seats.append(player_id)
	return seats


func _units_of(player_id: int) -> Array:
	var rosters: Variant = main.get("_player_units")
	if rosters is Array and player_id < (rosters as Array).size():
		return rosters[player_id]
	return []


func _buildings_of(player_id: int) -> Array:
	var rosters: Variant = main.get("_player_buildings")
	if rosters is Array and player_id < (rosters as Array).size():
		return rosters[player_id]
	return []


func _map() -> Node2D:
	return main.get("game_map") as Node2D


# =============================================================================
#  Job memory and Back to work (authority)
# =============================================================================

func _remember_jobs() -> void:
	var alive: Dictionary = {}
	for player_id: int in _human_seats():
		for entry: Variant in _units_of(player_id):
			if not is_instance_valid(entry) or not entry is Villager:
				continue
			var worker := entry as Villager
			var id: int = worker.get_instance_id()
			alive[id] = true
			if worker.current_state == UnitBase.State.DEAD:
				continue
			var job: Dictionary = _jobs.get(id, {})
			if worker.current_state == UnitBase.State.BUILDING and is_instance_valid(worker.build_target):
				job["build"] = weakref(worker.build_target)
			elif worker.current_state == UnitBase.State.GATHERING and worker.has_active_gather_order() and worker.carried_resource_type in ["food", "wood", "gold"]:
				job.erase("build")
				job["resource"] = worker.carried_resource_type
				job["target"] = weakref(worker.gather_target) if is_instance_valid(worker.gather_target) else null
				job["position"] = worker.gather_target.global_position if is_instance_valid(worker.gather_target) else worker.global_position
				job["worked_at"] = GameManager.game_time
			else:
				if worker.current_state == UnitBase.State.IDLE and not job.is_empty():
					_maybe_found_farm(worker, job)
				continue
			_jobs[id] = job
	for id: Variant in _jobs.keys():
		if not alive.has(id):
			_jobs.erase(id)


## A food worker whose last berries, animal or Farm ran out (and nothing else
## is in reach) founds a Farm by the nearest Town Center / Mill when wood
## allows, instead of standing idle. Only right after the work ended, so a
## villager the player deliberately parked is left alone.
func _maybe_found_farm(worker: Villager, job: Dictionary) -> void:
	# The walk home with the last load can take a while; a worker idle for
	# longer than this since the work ended is somebody's deliberate choice.
	var worked_at: float = float(job.get("worked_at", -100.0))
	if str(job.get("resource", "")) != "food" or worked_at < 0.0 or GameManager.game_time - worked_at > FARM_AFTER_WORK_SECONDS:
		return
	if worker.is_selected or worker.is_auto_recovering() or not worker.queued_orders.is_empty() or worker.carried_amount > 0:
		return
	var last_target: Variant = (job["target"] as WeakRef).get_ref() if job.get("target") is WeakRef else null
	if FarmPlots.is_fallow(last_target):
		job["worked_at"] = -100.0
		return  # Reseeding (FarmPlots) owns a fallow Farm's farmer.
	if not resumable_job(worker).is_empty():
		return
	if ResourceManager.get_resource(worker.player_owner, "food") >= FARM_FOOD_BANK_LIMIT:
		job["worked_at"] = -100.0
		return  # Food is floating: the wood is better spent; this one waits as idle.
	if not ResourceManager.can_afford(worker.player_owner, BuildingData.get_building_cost(BuildingData.BuildingType.FARM, worker.player_owner)):
		return  # Retried each second while wood may still arrive.
	job["worked_at"] = -100.0
	if worker.player_owner == 0:
		place_farm_for(worker)
	else:
		_place_for_seat(worker)


func _place_for_seat(worker: Villager) -> void:
	# Server seats other than 0: the same transaction, paid by that seat.
	var anchors: Array = []
	for entry: Variant in _buildings_of(worker.player_owner):
		if is_instance_valid(entry) and entry is BuildingBase and (entry as BuildingBase).state == BuildingBase.State.ACTIVE \
				and (entry as BuildingBase).has_method("is_drop_off_point") and bool((entry as BuildingBase).call("is_drop_off_point", "food")):
			anchors.append(entry)
	var site: Variant = find_site(BuildingData.BuildingType.FARM, worker.player_owner, anchors)
	if site == null:
		return
	var map: Node2D = _map()
	var world: Vector2 = map.call("tile_to_world", site)
	var placement: Node = main.get("_building_placement") as Node
	if not bool(placement.call("revalidate_confirmation", BuildingData.BuildingType.FARM, world, worker.player_owner)):
		return
	var cost: Dictionary = BuildingData.get_building_cost(BuildingData.BuildingType.FARM, worker.player_owner)
	if not ResourceManager.try_spend(worker.player_owner, cost):
		return
	var building: BuildingBase = main.call("_spawn_building", BuildingData.BuildingType.FARM, worker.player_owner, site) as BuildingBase
	if building == null:
		ResourceManager.refund(worker.player_owner, cost)
		return
	building.start_construction()
	worker.command_build(building)


## The work this villager would go back to, or {} when there is none.
## {"kind": "build", "target": building} or {"kind": "gather", "target": node}.
func resumable_job(worker: Villager) -> Dictionary:
	if not is_instance_valid(worker) or worker.current_state == UnitBase.State.DEAD:
		return {}
	var job: Dictionary = _jobs.get(worker.get_instance_id(), {})
	if job.is_empty():
		return {}
	var site: Variant = (job["build"] as WeakRef).get_ref() if job.get("build") is WeakRef else null
	if is_instance_valid(site) and worker._is_build_target_valid(site):
		return {"kind": "build", "target": site}
	var resource: String = str(job.get("resource", ""))
	if resource.is_empty():
		return {}
	var target: Variant = (job["target"] as WeakRef).get_ref() if job.get("target") is WeakRef else null
	if is_instance_valid(target) and not FarmPlots.is_fallow(target) and _harvestable(target, worker):
		return {"kind": "gather", "target": target}
	var map: Node2D = _map()
	if map == null or not map.has_method("get_nearest_reachable_resource_node"):
		return {}
	var origin: Vector2 = job.get("position", worker.global_position)
	var replacement: Node2D = map.call("get_nearest_reachable_resource_node", resource, origin, worker.player_owner, {}, worker) as Node2D
	if replacement == null or replacement.global_position.distance_to(origin) > 12.0 * MapData.TILE_WIDTH:
		return {}
	return {"kind": "gather", "target": replacement}


func _harvestable(target: Node2D, worker: Villager) -> bool:
	var map: Node2D = _map()
	if map != null and map.has_method("is_resource_target_available_to_worker"):
		return bool(map.call("is_resource_target_available_to_worker", target, "", worker.player_owner, worker))
	return target.has_method("get_remaining") and int(target.call("get_remaining")) > 0


## Villagers that would answer "Back to work": idle with a job to resume,
## sheltering by hand in a quiet building, or waiting out a scare.
func is_waiting_for_work(worker: Variant) -> bool:
	if not is_instance_valid(worker) or not worker is Villager:
		return false
	var villager := worker as Villager
	if villager.current_state == UnitBase.State.DEAD:
		return false
	if villager.is_auto_recovering():
		return bool(villager.get("_recovery_waiting"))
	if villager.current_state == UnitBase.State.GARRISONED:
		var shelter: Variant = villager._garrison_target
		return is_instance_valid(shelter) and not bool((shelter as BuildingBase).bell_active) and not resumable_job(villager).is_empty()
	if villager.current_state != UnitBase.State.IDLE or not villager.queued_orders.is_empty():
		return false
	return not resumable_job(villager).is_empty()


## Authority: send `units` (or every waiting villager of `owner`) back to their
## last jobs. Returns how many went.
func back_to_work(owner: int, units: Array = []) -> int:
	var pool: Array = units if not units.is_empty() else _units_of(owner)
	var sent: int = 0
	for entry: Variant in pool:
		if not is_instance_valid(entry) or not entry is Villager or (entry as Villager).player_owner != owner:
			continue
		var worker := entry as Villager
		if not is_waiting_for_work(worker):
			continue
		if worker.is_auto_recovering():
			worker._resume_after_recovery()
			sent += 1
			continue
		var job: Dictionary = resumable_job(worker)
		if job.is_empty():
			continue
		if worker.current_state == UnitBase.State.GARRISONED:
			Garrison.release_unit(worker)
		if job.kind == "build":
			worker.command_build(job.target)
		else:
			worker.command_gather(job.target)
		sent += 1
	return sent


func _command_back_to_work(owner: int, _packet: Dictionary, units: Array, _target: Node2D, _position: Vector2) -> String:
	return "" if back_to_work(owner, units) > 0 else "Nobody to send back"


func _waiting_workers() -> Array[Villager]:
	var waiting: Array[Villager] = []
	var selection: Array = []
	var map: Node2D = _map()
	if map != null and map.get("selection_mgr") != null:
		selection = map.selection_mgr.selected
	for entry: Variant in _units_of(0):
		if not is_instance_valid(entry) or not entry is Villager or entry in selection:
			continue
		if NetworkSession.is_client():
			# Replicas carry no job memory: an idle villager is a candidate and
			# the authority decides who really goes.
			if (entry as Villager).current_state == UnitBase.State.IDLE:
				waiting.append(entry as Villager)
		elif is_waiting_for_work(entry):
			waiting.append(entry as Villager)
	return waiting


func _refresh_back_to_work_offer(step: float) -> void:
	var hud: Node = main.get("hud") as Node
	var count: int = _waiting_workers().size()
	if count < OFFER_MIN_IDLE:
		_offer_pending_seconds = 0.0
		_offer_count = 0
		_retire_offer(hud)
		return
	_offer_pending_seconds += step
	if _offer_pending_seconds < OFFER_SETTLE_SECONDS:
		return
	var now: int = Time.get_ticks_msec()
	if count == _offer_count and not _offer_text.is_empty():
		return
	if count <= _offer_count and now - _offer_msec < OFFER_COOLDOWN_MSEC:
		return
	_retire_offer(hud)
	_offer_count = count
	_offer_msec = now
	_offer_text = BACK_TO_WORK_TEXT % count
	hud.call("show_notification", _offer_text, KingdomTheme.GOLD, 8.0, request_back_to_work, 2)


func _retire_offer(hud: Node) -> void:
	if not _offer_text.is_empty() and is_instance_valid(hud):
		hud.call("dismiss_notification", _offer_text)
	_offer_text = ""


## Local player: one tap. Online the authority picks who has a job.
func request_back_to_work() -> int:
	_offer_text = ""
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return 0
	var hud: Node = main.get("hud") as Node
	var sent: int = 0
	if NetworkSession.is_client():
		var ids: Array = []
		for worker: Villager in _waiting_workers():
			ids.append(NetworkSession.entity_id(worker))
		if ids.is_empty():
			return 0
		NetworkSession.send_command("back_to_work", {"ids": ids.slice(0, 64)})
		sent = ids.size()
	else:
		sent = back_to_work(0)
	if sent > 0 and is_instance_valid(hud):
		hud.call("show_notification", "%d back to work" % sent, Color(0.62, 0.86, 0.6), 2.0)
		AudioManager.play_ui("command_move")
	return sent


# =============================================================================
#  Tapping an own Town Center / drop-off with villagers selected
# =============================================================================

func _hook_selection() -> void:
	var map: Node2D = _map()
	if map == null or map.get("selection_mgr") == null:
		return
	var selection: Node = map.selection_mgr
	_selection_hooked = true
	if selection.has_signal("dropoff_command"):
		selection.connect("dropoff_command", _on_player_dropoff)
		selection.connect("lure_command", _on_player_lure)


func _selected_own_villagers() -> Array:
	var villagers: Array = []
	for entry: Variant in _map().selection_mgr.selected:
		if is_instance_valid(entry) and entry is Villager and (entry as Villager).player_owner == 0:
			villagers.append(entry)
	return villagers


func _on_player_dropoff(building: Node2D) -> void:
	var villagers: Array = _selected_own_villagers()
	if villagers.is_empty() or not building is BuildingBase:
		return
	if NetworkSession.is_client():
		NetworkSession.send_command("dropoff", {"ids": NetworkSession.selection_ids(villagers), "target": NetworkSession.entity_id(building)})
		VFX.move_indicator(get_tree(), building.global_position)
		return
	if deliver(0, villagers, building as BuildingBase) > 0:
		VFX.move_indicator(get_tree(), building.global_position)
		AudioManager.play_ui("command_move")


## Authority: villagers with cargo walk it to `building` now (and then resume
## their gathering); empty-handed ones simply keep working.
func deliver(owner: int, villagers: Array, building: BuildingBase) -> int:
	var sent: int = 0
	for entry: Variant in villagers:
		if is_instance_valid(entry) and entry is Villager and (entry as Villager).player_owner == owner and (entry as Villager).carried_amount > 0:
			if (entry as Villager).command_dropoff(building):
				sent += 1
	return sent


func _command_dropoff(owner: int, _packet: Dictionary, units: Array, target: Node2D, _position: Vector2) -> String:
	if not target is BuildingBase or (target as BuildingBase).player_owner != owner:
		return "Select your building"
	return "" if deliver(owner, units, target as BuildingBase) > 0 else "Nothing to deliver"


func _on_player_lure(building: Node2D) -> void:
	var villagers: Array = _selected_own_villagers()
	if villagers.is_empty() or not building is BuildingBase:
		return
	if NetworkSession.is_client():
		NetworkSession.send_command("lure", {"ids": NetworkSession.selection_ids(villagers), "target": NetworkSession.entity_id(building)})
		VFX.move_indicator(get_tree(), building.global_position)
		return
	if lure(0, villagers, building as BuildingBase) > 0:
		VFX.move_indicator(get_tree(), building.global_position)
		AudioManager.play_ui("command_move")


## Authority: villagers fighting a boar run to the Town Center's doorstep; the
## boar follows its attacker. Once it is close again they strike it there.
func lure(owner: int, villagers: Array, town_center: BuildingBase) -> int:
	var map: Node2D = _map()
	var sent: int = 0
	for entry: Variant in villagers:
		if not is_instance_valid(entry) or not entry is Villager or (entry as Villager).player_owner != owner:
			continue
		var worker := entry as Villager
		var boar: Variant = worker.gather_target
		var doorstep: Vector2 = Garrison._pick_exit(town_center, map, worker.global_position, {})
		worker.command_move(doorstep)
		if is_instance_valid(boar) and boar is WildlifeNode:
			_lures.append({"worker": weakref(worker), "boar": weakref(boar), "until": GameManager.game_time + LURE_SECONDS})
		sent += 1
	return sent


func _command_lure(owner: int, _packet: Dictionary, units: Array, target: Node2D, _position: Vector2) -> String:
	if not target is BuildingBase or (target as BuildingBase).player_owner != owner:
		return "Select your Town Center"
	return "" if lure(owner, units, target as BuildingBase) > 0 else "Nobody to send"


func _advance_lures() -> void:
	var now: float = GameManager.game_time
	for index: int in range(_lures.size() - 1, -1, -1):
		var entry: Dictionary = _lures[index]
		var worker: Villager = (entry.worker as WeakRef).get_ref() as Villager
		var boar: WildlifeNode = (entry.boar as WeakRef).get_ref() as WildlifeNode
		if worker == null or boar == null or now > float(entry.until) or worker.current_state == UnitBase.State.DEAD \
				or boar.remaining <= 0 or (worker.current_state != UnitBase.State.MOVING and worker.current_state != UnitBase.State.IDLE):
			_lures.remove_at(index)
			continue
		if worker.current_state == UnitBase.State.IDLE and worker.global_position.distance_to(boar.global_position) <= LURE_REENGAGE_TILES * MapData.TILE_WIDTH:
			worker.command_gather(boar)
			_lures.remove_at(index)


# =============================================================================
#  Housing warning and one-tap House
# =============================================================================

func _refresh_house_warning() -> void:
	var hud: Node = main.get("hud") as Node
	if not GameManager.players.has(0):
		return
	var cap: int = int(GameManager.players[0].get("population_cap", 0))
	var limit: int = GameManager.get_player_population_limit(0)
	var committed: int = GameManager.get_committed_population(0)
	var now: int = Time.get_ticks_msec()
	var live: bool = not _house_toast.is_empty() and now < _house_toast_until_msec
	# Houses going up count as room already; a big queue can still outrun one.
	var incoming: int = _houses_under_construction() * int(BuildingData.get_building_stats(BuildingData.BuildingType.HOUSE).get("pop_provided", 10))
	if GameManager.game_time < HOUSE_WARNING_GRACE_SECONDS or cap >= limit or committed < cap + incoming - HOUSE_WARNING_SLOTS:
		if live:
			hud.call("dismiss_notification", _house_toast)
		_house_toast = ""
		if committed < cap - HOUSE_WARNING_SLOTS - 1:
			_house_warned_cap = -1
		return
	var housed: bool = committed >= cap + incoming
	var showing_housed: bool = _house_toast.begins_with("Housed")
	if live and housed == showing_housed:
		return
	# Near the cap: once per cap. Housed: again every so often until fixed.
	if not housed and _house_warned_cap == cap + incoming:
		return
	if housed and not live and now - _house_toast_until_msec < HOUSE_REPEAT_MSEC and _house_warned_cap == cap + incoming and showing_housed:
		return
	_house_warned_cap = cap + incoming
	if live:
		hud.call("dismiss_notification", _house_toast)
	var house_cost: Dictionary = BuildingData.get_building_cost(BuildingData.BuildingType.HOUSE, 0)
	var room: int = maxi(0, cap + incoming - committed)
	var housing: String = "Housed" if room == 0 else "%d room left" % room
	var duration: float = 14.0 if housed else 9.0
	if ResourceManager.can_afford(0, house_cost):
		_house_toast = "%s · tap: House" % housing
		hud.call("show_notification", _house_toast, KingdomTheme.AMBER, duration, request_auto_house, 2)
	else:
		var missing: Dictionary = ResourceManager.get_missing_resources(0, house_cost)
		_house_toast = "%s · House needs %dW more" % [housing, int(missing.get("wood", 0))]
		duration = 5.0
		hud.call("show_notification", _house_toast, KingdomTheme.AMBER, duration, Callable(), 1)
	_house_toast_until_msec = now + int(duration * 1000.0)


func _houses_under_construction() -> int:
	var count: int = 0
	for entry: Variant in _buildings_of(0):
		if is_instance_valid(entry) and entry is BuildingBase and (entry as BuildingBase).building_type == BuildingData.BuildingType.HOUSE \
				and (entry as BuildingBase).state == BuildingBase.State.CONSTRUCTING:
			count += 1
	return count


## One tap: a House on the nearest good spot beside the other Houses.
func request_auto_house() -> bool:
	_house_toast = ""
	var hud: Node = main.get("hud") as Node
	if GameManager.current_state != GameManager.GameState.PLAYING or bool(main.get("_placement_active")):
		return false
	var site: Variant = find_site(BuildingData.BuildingType.HOUSE, 0)
	if site == null:
		hud.call("show_notification", "No open ground near your Houses", Color(1.0, 0.62, 0.32))
		return false
	return place_at(BuildingData.BuildingType.HOUSE, site as Vector2i, null, true)


## Pays for and founds `building_type` at `tile` like a confirmed placement.
## `builder` (optional) is the one villager sent to build it; otherwise Main's
## usual choice (selected villagers, else the nearest free one) applies.
func place_at(building_type: int, tile: Vector2i, builder: Villager = null, offer_undo: bool = false) -> bool:
	var map: Node2D = _map()
	var world: Vector2 = map.call("tile_to_world", tile)
	var hud: Node = main.get("hud") as Node
	if NetworkSession.is_client():
		var payload: Dictionary = {"type": building_type, "position": [world.x, world.y]}
		if builder != null:
			payload["ids"] = [NetworkSession.entity_id(builder)]
			return NetworkSession.send_command("place", payload)
		return bool(main.call("_send_network_selection", "place", payload))
	var placement: Node = main.get("_building_placement") as Node
	if placement == null or not bool(placement.call("revalidate_confirmation", building_type, world, 0)):
		return false
	var cost: Dictionary = BuildingData.get_building_cost(building_type, 0)
	if not ResourceManager.try_spend(0, cost):
		if hud != null: hud.call("show_notification", "Need %s" % main.call("_format_missing_resources", ResourceManager.get_missing_resources(0, cost)), Color(1.0, 0.45, 0.35))
		return false
	var building: BuildingBase = main.call("_spawn_building", building_type, 0, tile) as BuildingBase
	if building == null:
		ResourceManager.refund(0, cost)
		return false
	building.start_construction()
	if builder != null and is_instance_valid(builder):
		builder.command_build(building)
	else:
		main.call("_send_villager_to_build", building)
	VFX.move_indicator(get_tree(), building.global_position)
	AudioManager.play_ui("button_click")
	if offer_undo and hud != null:
		_undo_toast = "%s placed · tap to undo" % BuildingData.get_building_name(building_type)
		hud.call("show_notification", _undo_toast, Color(0.62, 0.86, 0.6), UNDO_SECONDS, _undo_placement.bind(weakref(building), tile, cost), 2)
	return true


func _undo_placement(building_ref: WeakRef, tile: Vector2i, cost: Dictionary) -> void:
	_undo_toast = ""
	var building: BuildingBase = building_ref.get_ref() as BuildingBase
	if building == null or building.state != BuildingBase.State.CONSTRUCTING:
		return
	var builders: Array = []
	for entry: Variant in _units_of(0):
		if is_instance_valid(entry) and entry is Villager and (entry as Villager).build_target == building:
			builders.append(entry)
			(entry as Villager).build_target = null
			if (entry as Villager).current_state == UnitBase.State.BUILDING:
				(entry as Villager).command_stop()
	(main.get("_player_buildings")[0] as Array).erase(building)
	var map: Node2D = _map()
	map.call("remove_building_obstacle", tile, building.footprint)
	building.queue_free()
	ResourceManager.refund(0, cost)
	back_to_work(0, builders)


## Nearest valid site for `building_type`, preferring a tidy spot beside the
## same kind of building, then around the Town Center. Tiles next to trees,
## mines and bushes lose points so camps and lanes stay open.
func find_site(building_type: int, owner: int, anchors: Array = []) -> Variant:
	var map: Node2D = _map()
	var placement: Node = main.get("_building_placement") as Node
	if map == null or placement == null:
		return null
	var footprint: Vector2i = BuildingData.get_building_stats(building_type).get("footprint", Vector2i(2, 2))
	if anchors.is_empty():
		for entry: Variant in _buildings_of(owner):
			if is_instance_valid(entry) and entry is BuildingBase and (entry as BuildingBase).building_type == building_type and (entry as BuildingBase).state != BuildingBase.State.DESTROYED:
				anchors.append(entry)
		for entry: Variant in _buildings_of(owner):
			if is_instance_valid(entry) and entry is BuildingBase and (entry as BuildingBase).building_type == BuildingData.BuildingType.TOWN_CENTER and (entry as BuildingBase).state == BuildingBase.State.ACTIVE:
				anchors.append(entry)
	var best: Variant = null
	var best_score: float = INF
	var seen: Dictionary = {}
	var anchor_rank: int = 0
	for anchor: Variant in anchors:
		if not is_instance_valid(anchor):
			continue
		var origin: Vector2i = map.call("world_to_tile", (anchor as Node2D).global_position)
		var anchor_size: Vector2i = (anchor as BuildingBase).footprint if anchor is BuildingBase else Vector2i.ONE
		var rank_penalty: float = 0.0 if (anchor is BuildingBase and (anchor as BuildingBase).building_type == building_type) else 4.0
		for dy: int in range(-SITE_SEARCH_RADIUS - footprint.y, anchor_size.y + SITE_SEARCH_RADIUS + 1):
			for dx: int in range(-SITE_SEARCH_RADIUS - footprint.x, anchor_size.x + SITE_SEARCH_RADIUS + 1):
				var tile: Vector2i = origin + Vector2i(dx, dy)
				if seen.has(tile):
					continue
				seen[tile] = true
				var gap: float = _rect_gap(Rect2i(origin, anchor_size), Rect2i(tile, footprint))
				var score: float = gap + rank_penalty + float(anchor_rank) * 0.25 + _clutter_penalty(map, tile, footprint)
				if score >= best_score:
					continue
				if not bool(placement.call("revalidate_confirmation", building_type, map.call("tile_to_world", tile), owner)):
					continue
				best_score = score
				best = tile
		anchor_rank += 1
		if best != null and anchor_rank >= 4:
			break
	return best


static func _rect_gap(a: Rect2i, b: Rect2i) -> float:
	var gap_x: int = maxi(0, maxi(a.position.x - b.end.x, b.position.x - a.end.x))
	var gap_y: int = maxi(0, maxi(a.position.y - b.end.y, b.position.y - a.end.y))
	return float(gap_x + gap_y)


func _clutter_penalty(map: Node2D, tile: Vector2i, footprint: Vector2i) -> float:
	if not map.has_method("get_resource_node_at"):
		return 0.0
	var penalty: float = 0.0
	for dy: int in range(-1, footprint.y + 1):
		for dx: int in range(-1, footprint.x + 1):
			if dx >= 0 and dx < footprint.x and dy >= 0 and dy < footprint.y:
				continue
			if map.call("get_resource_node_at", tile + Vector2i(dx, dy)) != null:
				penalty += 1.5
	return penalty


# =============================================================================
#  Farm ring for "+ Food"
# =============================================================================

## Founds a Farm for `worker` on a ring around the nearest food drop-off
## (Town Center or Mill). The worker builds it and then farms it.
func place_farm_for(worker: Villager) -> bool:
	if not is_instance_valid(worker):
		return false
	var anchors: Array = []
	for entry: Variant in _buildings_of(worker.player_owner):
		if is_instance_valid(entry) and entry is BuildingBase and (entry as BuildingBase).state == BuildingBase.State.ACTIVE \
				and (entry as BuildingBase).has_method("is_drop_off_point") and bool((entry as BuildingBase).call("is_drop_off_point", "food")):
			anchors.append(entry)
	if anchors.is_empty():
		return false
	anchors.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.distance_squared_to(worker.global_position) < b.global_position.distance_squared_to(worker.global_position))
	var site: Variant = find_site(BuildingData.BuildingType.FARM, worker.player_owner, anchors.slice(0, 2))
	if site == null:
		return false
	return place_at(BuildingData.BuildingType.FARM, site as Vector2i, worker)


# =============================================================================
#  Town Center idle mark
# =============================================================================

func _refresh_idle_centers() -> void:
	var previous: int = _idle_centers.size()
	_idle_centers.clear()
	var now: float = GameManager.game_time
	for entry: Variant in _buildings_of(0):
		if not is_instance_valid(entry) or not entry is BuildingBase:
			continue
		var building := entry as BuildingBase
		if building.building_type != BuildingData.BuildingType.TOWN_CENTER or building.state != BuildingBase.State.ACTIVE:
			continue
		var id: int = building.get_instance_id()
		var queue: Node = building.get_production_queue() if building.has_method("get_production_queue") else null
		var busy: bool = not building.research_id.is_empty() or (queue != null and int(queue.call("get_queue_size")) > 0)
		if busy or not _tc_busy_at.has(id):
			_tc_busy_at[id] = now
			continue
		if now - float(_tc_busy_at[id]) >= TC_IDLE_GRACE_SECONDS:
			_idle_centers.append(building)
	if previous != _idle_centers.size() or not _idle_centers.is_empty():
		queue_redraw()
	var hud: Node = main.get("hud") as Node
	if hud != null and hud.has_method("get_base_navigation_button"):
		var base: Button = hud.call("get_base_navigation_button") as Button
		if base != null:
			CommandIcons.set_badge(base, "zz" if not _idle_centers.is_empty() else "", false)


func get_idle_town_centers() -> Array[BuildingBase]:
	return _idle_centers


func _draw() -> void:
	var pulse: float = 0.75 + 0.25 * sin(float(Time.get_ticks_msec()) / 420.0)
	for building: BuildingBase in _idle_centers:
		if not is_instance_valid(building) or not building.is_visible_in_tree():
			continue
		var center: Vector2 = to_local(ResearchPips.pip_position(building))
		draw_circle(center, ResearchPips.RADIUS + 1.5, Color(INK, 0.9))
		draw_arc(center, ResearchPips.RADIUS - 1.5, 0.0, TAU, 32, Color(AMBER, pulse), 2.5, true)
		var icon: Texture2D = CommandIcons.get_icon("idle")
		if icon != null:
			var extent: float = ResearchPips.ICON_SIZE
			draw_texture_rect(icon, Rect2(center - Vector2(extent, extent) * 0.5, Vector2(extent, extent)), false, Color(1, 1, 1, pulse))
