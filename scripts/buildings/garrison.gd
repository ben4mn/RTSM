class_name Garrison
extends Node
## Round 2 D1: town bell, garrison, repair and healing at home.
##
## The static functions are the rules (callable from the AI, tests and the
## network authority). One instance per match (`install(main)`) ticks them:
## units walking to a shelter go in, garrisons heal, the bell stands down when
## the raid is over, extra arrows fly, and the small world badges are drawn.
##
## A garrisoned unit is taken out of the scene tree (`State.GARRISONED`). That
## removes it from the `units` group, the spatial index, targeting, drawing and
## processing in one step; `main._player_units` still holds it, so it is saved
## as a normal actor and still counts toward population.

# --- Data constants (tune here) ----------------------------------------------
const CAPACITY: Dictionary = {
	BuildingData.BuildingType.TOWN_CENTER: 15,
	BuildingData.BuildingType.WATCH_TOWER: 5,
}
## Radii are MAP tiles measured from the centre of the footprint (the Town
## Center sees 13), not the 16-unit "range tiles" of weapon data.
## Villagers this close to a Town Center answer its bell.
const BELL_RADIUS_TILES: float = 14.0
## The bell stands down after this long with no visible armed enemy inside
## ALL_CLEAR_RADIUS_TILES of the Town Center.
const ALL_CLEAR_SECONDS: float = 12.0
const ALL_CLEAR_RADIUS_TILES: float = 10.0
## One extra arrow of the building's own arrow damage per garrisoned villager
## or ranged soldier, so a later Town Center retune carries over.
const MAX_BONUS_ARROWS: int = 8
const BONUS_ARROW_STAGGER: float = 0.07
const GARRISON_HEAL_PER_SECOND: float = 3.0
const HOME_HEAL_PER_SECOND: float = 1.0
const HOME_HEAL_RADIUS_TILES: float = 5.0
const HOME_HEAL_CALM_SECONDS: float = 6.0
## Per villager. 1 wood buys REPAIR_HP_PER_WOOD hit points; no wood, no work.
const REPAIR_HP_PER_SECOND: float = 30.0
const REPAIR_HP_PER_WOOD: float = 20.0
## Footprint distance at which a unit walking to shelter steps inside.
const ENTER_DISTANCE: float = 56.0
const WORK_DISTANCE: float = 40.0
const TICK_SECONDS: float = 0.25
## A rival who watched a unit walk in keeps its replica this long (online).
const ENEMY_REVEAL_GRACE: float = 0.35
const RAID_PROMPT_COOLDOWN: float = 25.0
const HEAL_PULSE_INTERVAL: float = 1.0
const MAX_HEAL_MARKS: int = 24

const ACTION_BELL: String = "garrison:bell"
const ACTION_RELEASE: String = "garrison:release"
const ICON_BELL: String = "res://assets/ui/icons/bell.svg"
const ICON_GARRISON: String = "res://assets/ui/icons/garrison.svg"
const ICON_REPAIR: String = "res://assets/ui/icons/repair.svg"
const TEXT_BELL: String = "Town bell — villagers take shelter"
const TEXT_ALL_CLEAR: String = "All clear"

enum Repair { DONE, WORKING, PAUSED }

static var _director_ref: WeakRef = null
static var _icon_cache: Dictionary = {}

var main: Node = null
var _tick: float = 0.0
var _pending_arrows: Array[Dictionary] = []
var _calm: Dictionary = {}  # unit instance id -> {"hp": float, "quiet": float}
var _next_pulse: Dictionary = {}  # instance id -> game time of the next "+"
var _replica_hp: Dictionary = {}  # client only: instance id -> last seen hp
var _marks: Array[HealMark] = []
var _raid_prompt_ready_at: float = 0.0
var _selection_hooked: bool = false


# =============================================================================
#  Installation (one line in main._register_match_extensions)
# =============================================================================

static func install(match_main: Node) -> void:
	BuildingBase.register_context_provider("garrison", _context_actions, _perform_context_action)
	var director := Garrison.new()
	director.name = "GarrisonDirector"
	director.main = match_main
	match_main.add_child(director)
	_director_ref = weakref(director)
	var extensions: RefCounted = match_main.get("ext") as RefCounted
	if extensions == null:
		return
	var has_target: Callable = func(packet: Dictionary) -> bool: return packet.has("target")
	var has_units_and_target: Callable = func(packet: Dictionary) -> bool: return packet.has("target") and packet.get("ids") is Array and not packet.ids.is_empty()
	extensions.register_command("bell", _command_bell, has_target)
	extensions.register_command("ungarrison", _command_ungarrison, has_target)
	extensions.register_command("garrison", _command_garrison, has_units_and_target)
	extensions.register_command("repair", _command_repair, has_units_and_target)
	extensions.register_snapshot("garrison", director._snapshot_rows, director._apply_snapshot_rows)
	extensions.register_save("garrison", director._capture_save, director._restore_save, director._finalize_save)


static func get_director() -> Garrison:
	var director: Garrison = _director_ref.get_ref() as Garrison if _director_ref != null else null
	return director if is_instance_valid(director) else null


# =============================================================================
#  Queries
# =============================================================================

static func capacity_of(building: BuildingBase) -> int:
	return int(CAPACITY.get(building.building_type, 0)) if is_instance_valid(building) else 0


static func garrisoned_units(building: BuildingBase) -> Array[UnitBase]:
	## Living units inside. Stale ids (a unit freed while inside) are dropped.
	var units: Array[UnitBase] = []
	for index: int in range(building.garrisoned_ids.size() - 1, -1, -1):
		var unit: UnitBase = instance_from_id(building.garrisoned_ids[index]) as UnitBase
		if is_instance_valid(unit) and unit.current_state == UnitBase.State.GARRISONED and unit._garrison_target == building:
			units.append(unit)
		else:
			building.garrisoned_ids.remove_at(index)
	units.reverse()
	return units


static func count(building: BuildingBase) -> int:
	## Also correct on a client replica, which only knows the replicated number.
	if not is_instance_valid(building):
		return 0
	if building.has_meta("network_garrison"):
		return int(building.get_meta("network_garrison"))
	return garrisoned_units(building).size()


static func accepts(building: Variant) -> bool:
	## An own, finished shelter. Room is checked per order.
	return is_instance_valid(building) and building is BuildingBase \
		and (building as BuildingBase).state == BuildingBase.State.ACTIVE and (building as BuildingBase).hp > 0 \
		and capacity_of(building as BuildingBase) > 0


static func can_garrison_unit(unit: Variant, building: BuildingBase) -> bool:
	if not is_instance_valid(unit) or not unit is UnitBase or not accepts(building):
		return false
	var candidate := unit as UnitBase
	return candidate.player_owner == building.player_owner \
		and candidate.current_state != UnitBase.State.DEAD and candidate.current_state != UnitBase.State.GARRISONED \
		and candidate.unit_type not in [UnitData.UnitType.SIEGE, UnitData.UnitType.TRADER]


static func bonus_arrows(building: BuildingBase) -> int:
	if not accepts(building) or building.tower_attack_damage <= 0:
		return 0
	var archers: int = 0
	for unit: UnitBase in garrisoned_units(building):
		if unit is Villager or unit.is_ranged:
			archers += 1
	return mini(MAX_BONUS_ARROWS, archers)


static func needs_repair(building: Variant) -> bool:
	## Farms are replanted by working them, not repaired.
	if not is_instance_valid(building) or not building is BuildingBase:
		return false
	var site := building as BuildingBase
	return site.state == BuildingBase.State.ACTIVE and site.hp > 0 and site.hp < site.max_hp and not site.provides_food


static func is_being_repaired(building: BuildingBase) -> bool:
	return is_instance_valid(building) and float(building.get_meta("repair_until", -1.0)) > GameManager.game_time


static func hidden_from_enemy(node: Variant) -> bool:
	## network_match: a garrisoned unit never reaches the rival's snapshot,
	## after the short grace in which they saw it step inside.
	return node is UnitBase and (node as UnitBase).current_state == UnitBase.State.GARRISONED \
		and GameManager.game_time - float((node as UnitBase).get_meta("garrisoned_at", -100.0)) >= ENEMY_REVEAL_GRACE


static func footprint_center(building: BuildingBase) -> Vector2:
	return building.global_position + building._footprint_center


static func tile_distance(building: BuildingBase, world_position: Vector2) -> float:
	## Map tiles between `world_position` and the centre of the footprint.
	var map: Node2D = _map_of(building)
	if map == null:
		return world_position.distance_to(footprint_center(building)) / float(MapData.TILE_HEIGHT)
	var origin: Vector2i = map.call("world_to_tile", building.global_position)
	var centre := Vector2(origin) + Vector2(building.footprint - Vector2i.ONE) * 0.5
	var tile: Vector2i = map.call("world_to_tile", world_position)
	return Vector2(tile).distance_to(centre)


static func _map_of(node: Node) -> Node2D:
	var ancestor: Node = node.get_parent() if is_instance_valid(node) else null
	while ancestor != null:
		if ancestor is Node2D and ancestor.has_method("tile_to_world"):
			return ancestor as Node2D
		ancestor = ancestor.get_parent()
	return null


static func _own_units(building: BuildingBase) -> Array[UnitBase]:
	## Units of the building's owner that are on the field (garrisoned ones are
	## out of the tree and therefore not in the group).
	var units: Array[UnitBase] = []
	if not building.is_inside_tree():
		return units
	var map: Node2D = _map_of(building)
	for node: Node in building.get_tree().get_nodes_in_group("player_%d" % building.player_owner):
		if node is UnitBase and (node as UnitBase).current_state != UnitBase.State.DEAD and (map == null or map.is_ancestor_of(node)):
			units.append(node as UnitBase)
	return units


static func _inbound_count(building: BuildingBase) -> int:
	var inbound: int = 0
	for unit: UnitBase in _own_units(building):
		if unit._garrison_target == building:
			inbound += 1
	return inbound


static func free_slots(building: BuildingBase) -> int:
	return maxi(0, capacity_of(building) - garrisoned_units(building).size() - _inbound_count(building))


static func _work_distance(map: Node2D, from: Vector2, building: BuildingBase) -> float:
	if map != null and map.has_method("get_building_work_distance"):
		return float(map.call("get_building_work_distance", from, building.global_position, building.footprint))
	return from.distance_to(building.global_position)


# =============================================================================
#  Garrison: orders, entering, leaving
# =============================================================================

static func order_garrison(units: Array, building: BuildingBase) -> int:
	## Send `units` to shelter in `building`. Returns how many accepted.
	if not accepts(building):
		return 0
	var room: int = free_slots(building)
	var accepted: int = 0
	for entry: Variant in units:
		if accepted >= room:
			break
		if not can_garrison_unit(entry, building) or (entry as UnitBase)._garrison_target == building:
			continue
		var ordered: bool = (entry as Villager).command_garrison(building) if entry is Villager else _order_soldier(entry as UnitBase, building)
		if ordered:
			accepted += 1
	return accepted


static func _order_soldier(unit: UnitBase, building: BuildingBase) -> bool:
	var map: Node2D = unit._get_navigation_map()
	var route := PackedVector2Array()
	if map != null and map.has_method("get_building_work_world_path"):
		route = map.call("get_building_work_world_path", unit.global_position, building.global_position, building.footprint, WORK_DISTANCE)
	if route.is_empty():
		if _work_distance(map, unit.global_position, building) > ENTER_DISTANCE:
			return false
		unit.command_stop()
	else:
		unit.command_move_path(route)
	unit._garrison_target = building
	return true


static func enter(building: BuildingBase, unit: UnitBase) -> bool:
	## Put `unit` inside now. Callers decide whether it has arrived.
	if not can_garrison_unit(unit, building) or garrisoned_units(building).size() >= capacity_of(building):
		return false
	var parent: Node = unit.get_parent()
	if parent == null:
		return false
	_deselect(unit)
	unit._cancel_attack_windup()
	unit._reset_navigation()
	unit.attack_target = null
	unit.attack_building_target = null
	unit.attack_move = false
	unit.queued_orders.clear()
	unit._garrison_target = building
	unit.set_state(UnitBase.State.GARRISONED)
	unit.set_meta("garrisoned_at", GameManager.game_time)
	building.garrisoned_ids.append(unit.get_instance_id())
	_stow(unit)
	_watch(building)
	_refresh_badge(building)
	return true


static func _stow(unit: UnitBase) -> void:
	var parent: Node = unit.get_parent()
	if parent == null:
		return
	unit.set_meta("garrison_parent", weakref(parent))
	parent.remove_child(unit)


static func eject(building: BuildingBase, unit: UnitBase, resume: bool = true, used_exits: Dictionary = {}) -> void:
	## Put one garrisoned unit back on the field beside the building. Villagers
	## pick their previous job up again through the recovery path.
	if not is_instance_valid(unit):
		return
	if is_instance_valid(building):
		building.garrisoned_ids.erase(unit.get_instance_id())
	if unit.current_state != UnitBase.State.GARRISONED:
		return
	var map: Node2D = _map_of(building) if is_instance_valid(building) else null
	var parent: Node = null
	var remembered: Variant = unit.get_meta("garrison_parent") if unit.has_meta("garrison_parent") else null
	if remembered is WeakRef:
		parent = remembered.get_ref() as Node
	if not is_instance_valid(parent) and map != null:
		parent = map.get_node_or_null("UnitsContainer")
	if not is_instance_valid(parent):
		return
	var exit_point: Vector2 = unit.position
	if is_instance_valid(building) and map != null:
		exit_point = _pick_exit(building, map, unit.global_position, used_exits)
	if unit.get_parent() == null:
		parent.add_child(unit)
	unit.global_position = exit_point
	unit.remove_meta("garrison_parent")
	unit.remove_meta("garrisoned_at")
	unit._garrison_target = null
	unit._reset_navigation()
	if unit is Villager and resume and (unit as Villager)._auto_recovering:
		# Sheltering villagers are MOVING + waiting; resume from exactly there.
		unit.current_state = UnitBase.State.MOVING
		(unit as Villager)._resume_after_recovery()
	else:
		unit.current_state = UnitBase.State.MOVING
		if unit is Villager:
			(unit as Villager)._clear_recovery()
		unit.set_state(UnitBase.State.IDLE)
	unit.queue_redraw()
	if is_instance_valid(building):
		_refresh_badge(building)


static func eject_all(building: BuildingBase, villagers_only: bool = false) -> int:
	var used: Dictionary = {}
	var released: int = 0
	for unit: UnitBase in garrisoned_units(building):
		if villagers_only and not unit is Villager:
			continue
		eject(building, unit, true, used)
		released += 1
	_refresh_badge(building)
	return released


static func release_unit(unit: UnitBase) -> void:
	## UnitBase._before_new_command: an order given to a garrisoned unit first
	## brings it out; the order itself then replaces whatever it was doing.
	if unit.current_state != UnitBase.State.GARRISONED:
		return
	eject(unit._garrison_target, unit, false)


static func _pick_exit(building: BuildingBase, map: Node2D, near: Vector2, used: Dictionary) -> Vector2:
	var origin: Vector2i = map.call("world_to_tile", building.global_position)
	var best: Vector2 = near
	var best_score: float = INF
	for band: int in [1, 2]:
		for dy: int in range(-band, building.footprint.y + band):
			for dx: int in range(-band, building.footprint.x + band):
				if dx > -band and dx < building.footprint.x + band - 1 and dy > -band and dy < building.footprint.y + band - 1:
					continue
				var tile: Vector2i = origin + Vector2i(dx, dy)
				if not bool(map.call("is_tile_walkable", tile)):
					continue
				var point: Vector2 = map.call("tile_to_world", tile)
				var score: float = point.distance_to(near) + float(used.get(tile, 0)) * 48.0
				if score < best_score:
					best_score = score
					best = point
		if best_score < INF:
			break
	if best_score < INF:
		var chosen: Vector2i = map.call("world_to_tile", best)
		var crowd: int = int(used.get(chosen, 0))
		used[chosen] = crowd + 1
		# Several units leaving by one door stand in a small fan, not a stack.
		best += Vector2.from_angle(float(crowd) * 2.4) * minf(10.0, float(crowd) * 5.0)
	return best


static func _deselect(unit: UnitBase) -> void:
	if not unit.is_selected:
		return
	var map: Node2D = _map_of(unit)
	var selection: Node = map.get("selection_mgr") as Node if map != null else null
	if is_instance_valid(selection) and selection.has_method("_remove_from_selection"):
		selection.call("_remove_from_selection", unit)
	if unit.is_selected:
		unit.deselect()


static func _watch(building: BuildingBase) -> void:
	if building.has_meta("garrison_watch"):
		return
	building.set_meta("garrison_watch", true)
	building.defensive_attack_fired.connect(_on_defensive_volley.bind(building))
	building.building_destroyed.connect(_on_shelter_destroyed)


static func _on_shelter_destroyed(building: BuildingBase) -> void:
	## Everyone inside gets out alive, wherever the building stood.
	var was_ringing: bool = building.bell_active
	building.bell_active = false
	for unit: UnitBase in _own_units(building):
		if unit._garrison_target == building:
			unit._garrison_target = null
	eject_all(building)
	if was_ringing:
		GameManager.town_bell_changed.emit(building.player_owner, building, false)
	_refresh_badge(building)


# =============================================================================
#  Town bell
# =============================================================================

static func ring(town_center: BuildingBase) -> bool:
	## The AoE2 moment: every villager near this Town Center runs inside.
	if not accepts(town_center) or town_center.building_type != BuildingData.BuildingType.TOWN_CENTER:
		return false
	town_center.bell_active = true
	town_center._bell_quiet = 0.0
	_watch(town_center)
	var center: Vector2 = footprint_center(town_center)
	var nearby: Array[UnitBase] = []
	for unit: UnitBase in _own_units(town_center):
		if unit is Villager and unit._garrison_target != town_center and tile_distance(town_center, unit.global_position) <= BELL_RADIUS_TILES:
			nearby.append(unit)
	nearby.sort_custom(func(a: UnitBase, b: UnitBase) -> bool:
		return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center)
	)
	order_garrison(nearby, town_center)
	GameManager.town_bell_changed.emit(town_center.player_owner, town_center, true)
	_announce_bell(town_center, true)
	_refresh_badge(town_center)
	return true


static func release(town_center: BuildingBase) -> void:
	## All clear: sheltering villagers go back to what they were doing.
	## Soldiers garrisoned by hand stay until "Ungarrison".
	if not is_instance_valid(town_center):
		return
	var was_ringing: bool = town_center.bell_active
	town_center.bell_active = false
	town_center._bell_quiet = 0.0
	for unit: UnitBase in _own_units(town_center):
		if unit is Villager and unit._garrison_target == town_center:
			var villager := unit as Villager
			if villager._auto_recovering:
				villager._resume_after_recovery()
			villager._garrison_target = null
	eject_all(town_center, true)
	if was_ringing:
		GameManager.town_bell_changed.emit(town_center.player_owner, town_center, false)
		_announce_bell(town_center, false)
	_refresh_badge(town_center)


static func toggle(town_center: BuildingBase) -> bool:
	if not is_instance_valid(town_center):
		return false
	if town_center.bell_active:
		release(town_center)
		return true
	return ring(town_center)


static func ungarrison(building: BuildingBase) -> int:
	## The building's "Ungarrison" action: everyone out, bell off.
	if not is_instance_valid(building):
		return 0
	var inside: int = garrisoned_units(building).size()
	if building.bell_active:
		release(building)
	eject_all(building)
	return inside


static func _armed_enemy_near(building: BuildingBase, radius_tiles: float) -> bool:
	var map: Node2D = _map_of(building)
	if map == null or not map.has_method("get_visible_enemy_units_for_player"):
		return false
	for enemy: UnitBase in map.call("get_visible_enemy_units_for_player", building.player_owner):
		if not is_instance_valid(enemy) or enemy.current_state == UnitBase.State.DEAD or enemy.damage <= 0.0:
			continue
		if enemy is Villager and enemy.current_state != UnitBase.State.ATTACKING:
			continue
		if tile_distance(building, enemy.global_position) <= radius_tiles:
			return true
	return false


static func _announce_bell(town_center: BuildingBase, active: bool) -> void:
	## Local player's own bell only; the dedicated server has no audience.
	if NetworkSession.server_mode or town_center.player_owner != 0:
		return
	if active:
		AudioManager.play_town_bell()
	var director: Garrison = get_director()
	var hud: Node = director.main.get("hud") as Node if director != null and is_instance_valid(director.main) else null
	if is_instance_valid(hud) and hud.has_method("show_notification"):
		hud.call("show_notification", TEXT_BELL if active else TEXT_ALL_CLEAR, KingdomTheme.GOLD if active else KingdomTheme.TEAL)


# =============================================================================
#  Extra arrows
# =============================================================================

static func _on_defensive_volley(target: Node2D, building: BuildingBase) -> void:
	var extra: int = bonus_arrows(building)
	if extra <= 0 or not is_instance_valid(target):
		return
	var targets: Array[Node2D] = [target]
	if target is UnitBase:
		var map: Node2D = _map_of(building)
		if map != null and map.has_method("get_units_near"):
			var others: Array[Node2D] = []
			for unit: UnitBase in map.call("get_units_near", building.global_position, building.tower_attack_range):
				if unit == target or unit.player_owner == building.player_owner or unit.current_state == UnitBase.State.DEAD:
					continue
				if building.global_position.distance_to(unit.global_position) <= building.tower_attack_range and building._is_tower_target_visible(unit):
					others.append(unit)
			others.sort_custom(func(a: Node2D, b: Node2D) -> bool:
				return building.global_position.distance_squared_to(a.global_position) < building.global_position.distance_squared_to(b.global_position)
			)
			targets.append_array(others)
	var director: Garrison = get_director()
	for index: int in extra:
		# The volley walks down the line of raiders, then doubles up.
		var chosen: Node2D = targets[(index + 1) % targets.size()]
		if director != null:
			director._pending_arrows.append({"building": weakref(building), "target": weakref(chosen), "delay": float(index + 1) * BONUS_ARROW_STAGGER})
		else:
			_fire_bonus_arrow(building, chosen)


static func _fire_bonus_arrow(building: BuildingBase, target: Node2D) -> void:
	if not is_instance_valid(building) or building.state != BuildingBase.State.ACTIVE or not is_instance_valid(target):
		return
	if target is UnitBase:
		var unit := target as UnitBase
		if unit.current_state == UnitBase.State.DEAD or unit.current_state == UnitBase.State.GARRISONED:
			return
		if building.tower_attack_projectile_speed > 0.0:
			building._launch_defensive_arrow(unit)
		else:
			Combat.deal_tower_damage(building, unit)
	elif target is BuildingBase and (target as BuildingBase).state != BuildingBase.State.DESTROYED:
		Combat.deal_tower_damage_to_building(building, target as BuildingBase)


# =============================================================================
#  Repair
# =============================================================================

static func order_repair(villagers: Array, building: BuildingBase) -> int:
	if not needs_repair(building):
		return 0
	var accepted: int = 0
	for entry: Variant in villagers:
		if not is_instance_valid(entry) or not entry is Villager or (entry as Villager).player_owner != building.player_owner:
			continue
		var villager := entry as Villager
		if villager.current_state == UnitBase.State.DEAD or villager.current_state == UnitBase.State.GARRISONED:
			continue
		villager.command_build(building)
		if villager.build_target == building and villager.current_state == UnitBase.State.BUILDING:
			accepted += 1
	return accepted


static func repair_step(building: BuildingBase, delta: float) -> int:
	## One villager's work for `delta` seconds, called from Villager while it
	## stands at the wall. Wood is bought one unit at a time, in advance.
	if not needs_repair(building):
		return Repair.DONE
	# Never pay for more than the damage that is left.
	var missing: float = maxf(0.0, float(building.max_hp - building.hp) - building._repair_fraction)
	var gain: float = minf(REPAIR_HP_PER_SECOND * maxf(0.0, delta), missing)
	while building.repair_credit + 0.0001 < gain:
		if not ResourceManager.try_spend(building.player_owner, {"wood": 1}):
			# Use up what was already paid for, then wait for wood.
			gain = building.repair_credit
			break
		building.repair_credit += REPAIR_HP_PER_WOOD
	if gain <= 0.0001 and missing > 0.0001:
		return Repair.PAUSED
	building.repair_credit = maxf(0.0, building.repair_credit - gain)
	building._repair_fraction += gain
	var whole: int = floori(building._repair_fraction + 0.0001)
	if whole > 0:
		building._repair_fraction = maxf(0.0, building._repair_fraction - float(whole))
		building.hp = mini(building.max_hp, building.hp + whole)
		building.health_changed.emit(building.hp, building.max_hp)
		building._update_sprite_appearance()
		building.queue_redraw()
	building.set_meta("repair_until", GameManager.game_time + 0.6)
	AudioManager.play_world("construction_work", building)
	_refresh_badge(building)
	if building.hp >= building.max_hp:
		building._repair_fraction = 0.0
		return Repair.DONE
	return Repair.WORKING


# =============================================================================
#  Building context actions (HUD cards) and player requests
# =============================================================================

static func _context_actions(building: BuildingBase, _player_id: int) -> Array:
	var actions: Array = []
	if building.state != BuildingBase.State.ACTIVE or capacity_of(building) <= 0:
		return actions
	var inside: int = count(building)
	if building.building_type == BuildingData.BuildingType.TOWN_CENTER:
		actions.append({
			"id": ACTION_BELL, "label": "Town Bell", "icon": ICON_BELL, "cost": {}, "time": 0.0, "progress": -1.0,
			"disabled_reason": "",
			# The card is narrow beside the Town Center's train buttons.
			"short": "All clear" if building.bell_active else "Bell",
			"desc": "Release" if building.bell_active else "Shelter",
			"details": "Villagers within %d tiles run inside the Town Center (up to %d). Each one adds an arrow to its volley and heals. The bell stands down by itself %d seconds after the last raider leaves." % [int(BELL_RADIUS_TILES), capacity_of(building), int(ALL_CLEAR_SECONDS)],
		})
	if inside > 0:
		actions.append({
			"id": ACTION_RELEASE, "label": "Ungarrison", "icon": ICON_GARRISON, "cost": {}, "time": 0.0, "progress": -1.0,
			"disabled_reason": "", "short": "Ungarrison", "desc": "%d inside" % inside,
			"details": "Send everyone inside back out. Villagers return to their previous work.",
		})
	return actions


static func _perform_context_action(building: BuildingBase, _player_id: int, action_id: String) -> String:
	match action_id:
		ACTION_BELL:
			return "" if toggle(building) else "Bell unavailable"
		ACTION_RELEASE:
			return "" if ungarrison(building) > 0 else "Nobody inside"
	return "Action unavailable"


static func request_bell(match_main: Node, town_center: BuildingBase) -> void:
	## One-tap shortcut (raid toast). Same route as the building card.
	if not is_instance_valid(town_center) or town_center.player_owner != 0:
		return
	if NetworkSession.is_client():
		NetworkSession.send_command("building_action", {"target": NetworkSession.entity_id(town_center), "action": ACTION_BELL})
	elif not town_center.bell_active and GameManager.current_state == GameManager.GameState.PLAYING:
		ring(town_center)
	if is_instance_valid(match_main) and match_main.has_method("_on_selection_changed") and is_instance_valid(match_main.get("game_map")):
		match_main.call("_on_selection_changed", match_main.game_map.selection_mgr.selected)


func _on_player_garrison_command(building: Node2D) -> void:
	## SelectionManager "Garrison" (hold an own Town Center / Watch Tower with
	## units selected).
	if not is_instance_valid(main) or GameManager.current_state != GameManager.GameState.PLAYING:
		return
	if not building is BuildingBase or (building as BuildingBase).player_owner != 0:
		return
	var selected: Array = main.game_map.selection_mgr.selected
	if NetworkSession.is_client():
		main.call("_send_network_selection", "garrison", {"target": NetworkSession.entity_id(building)})
		return
	var own: Array = []
	for entry: Variant in selected:
		if is_instance_valid(entry) and entry is UnitBase and (entry as UnitBase).player_owner == 0:
			own.append(entry)
	var accepted: int = order_garrison(own, building as BuildingBase)
	var hud: Node = main.get("hud") as Node
	if accepted > 0:
		AudioManager.play_ui("command_move")
	elif is_instance_valid(hud):
		var reason: String = "%s is full" % (building as BuildingBase).building_name if free_slots(building as BuildingBase) <= 0 else "Cannot garrison there"
		hud.call("show_notification", reason, KingdomTheme.RUST)


# --- Network commands (authority) ---------------------------------------------

static func _command_bell(owner: int, _packet: Dictionary, _units: Array, target: Node2D, _position: Vector2) -> String:
	if not target is BuildingBase or (target as BuildingBase).player_owner != owner or not accepts(target) \
			or (target as BuildingBase).building_type != BuildingData.BuildingType.TOWN_CENTER:
		return "Select your Town Center"
	return "" if toggle(target as BuildingBase) else "Bell unavailable"


static func _command_ungarrison(owner: int, _packet: Dictionary, _units: Array, target: Node2D, _position: Vector2) -> String:
	if not target is BuildingBase or (target as BuildingBase).player_owner != owner or capacity_of(target as BuildingBase) <= 0:
		return "Select your building"
	return "" if ungarrison(target as BuildingBase) > 0 else "Nobody inside"


static func _command_garrison(owner: int, _packet: Dictionary, units: Array, target: Node2D, _position: Vector2) -> String:
	if not target is BuildingBase or (target as BuildingBase).player_owner != owner or not accepts(target):
		return "Cannot garrison there"
	if units.is_empty():
		return "Select your units"
	if order_garrison(units, target as BuildingBase) > 0:
		return ""
	return "%s is full" % (target as BuildingBase).building_name if free_slots(target as BuildingBase) <= 0 else "Cannot garrison there"


static func _command_repair(owner: int, _packet: Dictionary, units: Array, target: Node2D, _position: Vector2) -> String:
	if not target is BuildingBase or (target as BuildingBase).player_owner != owner:
		return "Select your building"
	if not needs_repair(target):
		return "Nothing to repair"
	return "" if order_repair(units, target as BuildingBase) > 0 else "Select villagers"


# =============================================================================
#  Director: the per-match tick
# =============================================================================

func _exit_tree() -> void:
	# Garrisoned units are outside the tree and would outlive the match.
	if not is_instance_valid(main):
		return
	var rosters: Variant = main.get("_player_units")
	if not rosters is Array:
		return
	for roster: Variant in rosters:
		if not roster is Array:
			continue
		for unit: Variant in roster:
			if is_instance_valid(unit) and unit is UnitBase and not (unit as UnitBase).is_inside_tree() and (unit as UnitBase).current_state == UnitBase.State.GARRISONED:
				(unit as UnitBase).free()


func _process(delta: float) -> void:
	if not is_instance_valid(main) or GameManager.current_state != GameManager.GameState.PLAYING:
		return
	_hook_selection()
	if not _pending_arrows.is_empty():
		_advance_pending_arrows(delta)
	_tick += delta
	if _tick < TICK_SECONDS:
		return
	var step: float = _tick
	_tick = 0.0
	if NetworkSession.is_client():
		_present_replica_healing()
	else:
		_simulate(step)
	if not NetworkSession.server_mode:
		_offer_raid_prompt()


func _hook_selection() -> void:
	if _selection_hooked:
		return
	var map: Node = main.get("game_map") as Node
	var selection: Node = map.get("selection_mgr") as Node if is_instance_valid(map) else null
	if not is_instance_valid(selection) or not selection.has_signal("garrison_command"):
		return
	_selection_hooked = true
	selection.connect("garrison_command", _on_player_garrison_command)


func _advance_pending_arrows(delta: float) -> void:
	for index: int in range(_pending_arrows.size() - 1, -1, -1):
		var shot: Dictionary = _pending_arrows[index]
		shot.delay = float(shot.delay) - delta
		if float(shot.delay) > 0.0:
			continue
		_pending_arrows.remove_at(index)
		var building: BuildingBase = (shot.building as WeakRef).get_ref() as BuildingBase
		var target: Node2D = (shot.target as WeakRef).get_ref() as Node2D
		if is_instance_valid(building) and is_instance_valid(target):
			_fire_bonus_arrow(building, target)


func _simulate(step: float) -> void:
	var healed: Dictionary = {}
	var calm_now: Dictionary = {}
	for owner: int in 2:
		for entry: Variant in main._player_buildings[owner]:
			if not is_instance_valid(entry) or not entry is BuildingBase:
				continue
			var building := entry as BuildingBase
			if building.state != BuildingBase.State.ACTIVE:
				continue
			if capacity_of(building) > 0:
				_watch(building)
				_heal_garrison(building, step)
				if building.bell_active:
					_tick_bell(building, step)
			if building.building_type == BuildingData.BuildingType.TOWN_CENTER:
				_heal_home(building, step, healed, calm_now)
			if building.has_meta("garrison_badge"):
				_refresh_badge(building)
		for entry: Variant in main._player_units[owner]:
			if is_instance_valid(entry) and entry is UnitBase and (entry as UnitBase)._garrison_target != null \
					and (entry as UnitBase).current_state != UnitBase.State.GARRISONED and (entry as UnitBase).current_state != UnitBase.State.DEAD:
				_try_enter(entry as UnitBase)
	_calm = calm_now


func _try_enter(unit: UnitBase) -> void:
	var building: BuildingBase = unit._garrison_target
	if not accepts(building) or building.player_owner != unit.player_owner:
		unit._garrison_target = null
		return
	if _work_distance(_map_of(building), unit.global_position, building) > ENTER_DISTANCE:
		# A soldier that stopped short (blocked, or pulled into a fight) no
		# longer has the order; a villager keeps sheltering under its recovery.
		if not unit is Villager and unit.current_state != UnitBase.State.MOVING:
			unit._garrison_target = null
		return
	if not enter(building, unit):
		unit._garrison_target = null


func _tick_bell(town_center: BuildingBase, step: float) -> void:
	if _armed_enemy_near(town_center, ALL_CLEAR_RADIUS_TILES):
		town_center._bell_quiet = 0.0
		return
	town_center._bell_quiet += step
	if town_center._bell_quiet >= ALL_CLEAR_SECONDS:
		release(town_center)


func _heal_garrison(building: BuildingBase, step: float) -> void:
	var anyone_wounded: bool = false
	for unit: UnitBase in garrisoned_units(building):
		if unit.hp < unit.max_hp:
			anyone_wounded = true
			unit.heal(GARRISON_HEAL_PER_SECOND * step)
	if anyone_wounded and building.player_owner == 0:
		_pulse(building, footprint_center(building) + Vector2(0.0, building._visual_top + 6.0))


func _heal_home(town_center: BuildingBase, step: float, healed: Dictionary, calm_now: Dictionary) -> void:
	var map: Node2D = main.game_map
	if not is_instance_valid(map) or not map.has_method("get_units_near"):
		return
	for unit: UnitBase in map.get_units_near(footprint_center(town_center), (HOME_HEAL_RADIUS_TILES + 1.0) * float(MapData.TILE_WIDTH)):
		if unit.player_owner != town_center.player_owner or unit.current_state == UnitBase.State.DEAD or unit.hp >= unit.max_hp:
			continue
		if tile_distance(town_center, unit.global_position) > HOME_HEAL_RADIUS_TILES:
			continue
		var id: int = unit.get_instance_id()
		if healed.has(id):
			continue
		healed[id] = true
		var record: Dictionary = _calm.get(id, {})
		var quiet: float = float(record.get("quiet", minf(HOME_HEAL_CALM_SECONDS, unit.get_seconds_since_hit()))) + step
		if unit.current_state == UnitBase.State.ATTACKING or unit.hp < float(record.get("hp", unit.hp)) - 0.001:
			quiet = 0.0
		if quiet >= HOME_HEAL_CALM_SECONDS:
			unit.heal(HOME_HEAL_PER_SECOND * step)
			if unit.is_visible_in_tree():
				_pulse(unit, unit.global_position + Vector2(0.0, unit.get_health_bar_y() - 6.0))
		calm_now[id] = {"hp": unit.hp, "quiet": quiet}


# --- Presentation ------------------------------------------------------------

func _present_replica_healing() -> void:
	## Clients only see hit points; a rising number on a visible replica is a
	## unit being healed.
	var seen: Dictionary = {}
	for owner: int in 2:
		for entry: Variant in main._player_units[owner]:
			if not is_instance_valid(entry) or not entry is UnitBase:
				continue
			var unit := entry as UnitBase
			var id: int = unit.get_instance_id()
			if _replica_hp.has(id) and unit.hp > float(_replica_hp[id]) + 0.001 and unit.is_visible_in_tree():
				_pulse(unit, unit.global_position + Vector2(0.0, unit.get_health_bar_y() - 6.0))
			seen[id] = unit.hp
	_replica_hp = seen


func _pulse(source: Object, world_position: Vector2) -> void:
	if NetworkSession.server_mode or DisplayServer.get_name() == "headless":
		return
	var id: int = source.get_instance_id()
	var now: float = GameManager.game_time
	if now < float(_next_pulse.get(id, 0.0)):
		return
	_next_pulse[id] = now + HEAL_PULSE_INTERVAL
	if _next_pulse.size() > 256:
		for key: int in _next_pulse.keys():
			if float(_next_pulse[key]) < now:
				_next_pulse.erase(key)
	var mark: HealMark = null
	for candidate: HealMark in _marks:
		if not candidate.visible:
			mark = candidate
			break
	if mark == null:
		if _marks.size() >= MAX_HEAL_MARKS:
			return
		mark = HealMark.new()
		mark.z_index = 90
		mark.visible = false
		main.game_map.add_child(mark)
		_marks.append(mark)
	mark.start(world_position)


func _offer_raid_prompt() -> void:
	## A raid on workers offers the bell in one tap (see report: the alert card
	## itself is a single "view" button, so this uses a tappable toast).
	if GameManager.game_time < _raid_prompt_ready_at:
		return
	var hud: Node = main.get("hud") as Node
	if not is_instance_valid(hud) or not hud.has_method("show_notification"):
		return
	for entry: Variant in main._player_buildings[0]:
		if not accepts(entry) or (entry as BuildingBase).building_type != BuildingData.BuildingType.TOWN_CENTER or (entry as BuildingBase).bell_active:
			continue
		var town_center := entry as BuildingBase
		var raider_near: bool = false
		for enemy: Variant in main._player_units[1]:
			if is_instance_valid(enemy) and enemy is UnitBase and not enemy is Villager and (enemy as UnitBase).visible and (enemy as UnitBase).is_inside_tree() \
					and (enemy as UnitBase).damage > 0.0 and (enemy as UnitBase).current_state != UnitBase.State.DEAD \
					and tile_distance(town_center, (enemy as UnitBase).global_position) <= BELL_RADIUS_TILES:
				raider_near = true
				break
		if not raider_near:
			continue
		for unit: Variant in main._player_units[0]:
			if not is_instance_valid(unit) or not unit is Villager or not (unit as Villager).is_inside_tree():
				continue
			var villager := unit as Villager
			var fleeing: bool = bool(villager.get_meta("network_recovering", false)) or villager.is_retreating()
			if fleeing and tile_distance(town_center, villager.global_position) <= BELL_RADIUS_TILES:
				_raid_prompt_ready_at = GameManager.game_time + RAID_PROMPT_COOLDOWN
				hud.call("show_notification", "Raid on your villagers — tap to ring the bell", KingdomTheme.RUST, 6.0, request_bell.bind(main, town_center))
				return


static func _refresh_badge(building: BuildingBase) -> void:
	## The bell pulse, garrison count and repair hammer above a building. Only
	## the local player's own buildings show them.
	if not is_instance_valid(building) or NetworkSession.server_mode or building.player_owner != 0:
		return
	var badge: Badge = building.get_meta("garrison_badge") as Badge if building.has_meta("garrison_badge") else null
	var wanted: bool = building.state == BuildingBase.State.ACTIVE and (building.bell_active or count(building) > 0 or is_being_repaired(building))
	if not is_instance_valid(badge):
		if not wanted:
			return
		badge = Badge.new()
		badge.name = "GarrisonBadge"
		badge.building = building
		badge.z_index = 2
		# A network replica is frozen; its badge still has to pulse.
		badge.process_mode = Node.PROCESS_MODE_PAUSABLE
		building.add_child(badge)
		building.set_meta("garrison_badge", badge)
	badge.refresh()


static func _icon(path: String) -> Texture2D:
	if not _icon_cache.has(path):
		_icon_cache[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _icon_cache[path] as Texture2D


## World badge above a sheltering building.
class Badge extends Node2D:
	var building: BuildingBase = null
	var bell: bool = false
	var inside: int = 0
	var repairing: bool = false
	var _phase: float = 0.0

	func refresh() -> void:
		if not is_instance_valid(building):
			return
		var active: bool = building.state == BuildingBase.State.ACTIVE
		var now_bell: bool = active and building.bell_active
		var now_inside: int = Garrison.count(building) if active else 0
		var now_repairing: bool = active and Garrison.is_being_repaired(building)
		if now_bell != bell or now_inside != inside or now_repairing != repairing:
			bell = now_bell
			inside = now_inside
			repairing = now_repairing
			queue_redraw()
		visible = bell or inside > 0 or repairing
		set_process(visible)

	func _process(delta: float) -> void:
		if repairing and not Garrison.is_being_repaired(building):
			refresh()
		if bell or repairing:
			_phase += delta
			if not GameManager.reduced_motion:
				queue_redraw()

	func _draw() -> void:
		if not is_instance_valid(building):
			return
		# Above the health bar and the drop-off letters of a selected building.
		var anchor := Vector2(building._footprint_center.x, building._visual_top - 44.0)
		var ink := Color("1d2b2c")
		var paper := Color("e8e5db")
		if bell:
			var gold := Color("e8bf77")
			if not GameManager.reduced_motion:
				for echo: int in 2:
					var wave: float = fposmod(_phase * 0.9 + float(echo) * 0.5, 1.0)
					draw_arc(anchor, 12.0 + wave * 16.0, 0.0, TAU, 32, Color(gold, (1.0 - wave) * 0.75), 2.0, true)
			var swing: float = 0.0 if GameManager.reduced_motion else sin(_phase * 9.0) * 0.22
			draw_circle(anchor, 12.5, Color(ink, 0.92))
			draw_arc(anchor, 12.5, 0.0, TAU, 32, gold, 1.6, true)
			draw_set_transform(anchor + Vector2(0.0, -6.0), swing, Vector2.ONE)
			var texture: Texture2D = Garrison._icon(Garrison.ICON_BELL)
			if texture != null:
				draw_texture_rect(texture, Rect2(-9.0, -3.0, 18.0, 18.0), false)
			else:
				draw_colored_polygon(PackedVector2Array([Vector2(-6, 12), Vector2(-4, 2), Vector2(0, -1), Vector2(4, 2), Vector2(6, 12)]), paper)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if inside > 0:
			# A small pennant with the number of people inside.
			var pip := anchor + (Vector2(24.0, 2.0) if bell else Vector2(0.0, 2.0))
			var font: Font = ThemeDB.fallback_font
			var label: String = str(inside)
			var width: float = 27.0 + (5.0 if inside >= 10 else 0.0)
			var plate := Rect2(pip.x - width * 0.5, pip.y - 8.0, width, 16.0)
			draw_rect(plate.grow(1.0), Color(ink, 0.92))
			draw_rect(plate, Color("31494a"))
			var icon: Texture2D = Garrison._icon(Garrison.ICON_GARRISON)
			if icon != null:
				draw_texture_rect(icon, Rect2(plate.position.x + 1.0, plate.position.y + 1.0, 14.0, 14.0), false)
			else:
				draw_colored_polygon(PackedVector2Array([plate.position + Vector2(4, 3), plate.position + Vector2(12, 6), plate.position + Vector2(4, 9)]), Color("88b7ad"))
			if font != null:
				draw_string(font, Vector2(plate.position.x + 15.0, plate.position.y + 12.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, paper)
		if repairing:
			# Hammer beside the health bar, tapping while work is under way.
			var bar_width: float = float(building.footprint.x) * MapData.TILE_WIDTH * 0.6
			var spot := Vector2(building._footprint_center.x - bar_width * 0.5 - 11.0, building._visual_top - 7.0)
			var tap: float = 0.0 if GameManager.reduced_motion else absf(sin(_phase * 7.0)) * 0.5
			draw_circle(spot, 8.5, Color(ink, 0.9))
			draw_set_transform(spot, -0.6 + tap, Vector2.ONE)
			var hammer: Texture2D = Garrison._icon(Garrison.ICON_REPAIR)
			if hammer != null:
				draw_texture_rect(hammer, Rect2(-6.5, -6.5, 13.0, 13.0), false)
			else:
				draw_rect(Rect2(-5.0, -5.0, 10.0, 4.0), paper)
				draw_rect(Rect2(-1.0, -1.0, 2.0, 7.0), Color("88b7ad"))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A small green "+" that rises and fades over a healing unit. Pooled.
class HealMark extends Node2D:
	const LIFETIME: float = 0.8
	var _age: float = 0.0
	var _origin: Vector2 = Vector2.ZERO

	func start(world_position: Vector2) -> void:
		_origin = world_position
		_age = 0.0
		global_position = world_position
		modulate.a = 1.0
		visible = true
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		_age += delta
		if _age >= LIFETIME:
			visible = false
			set_process(false)
			return
		var phase: float = _age / LIFETIME
		if not GameManager.reduced_motion:
			global_position = _origin + Vector2(0.0, -12.0 * phase)
		modulate.a = 1.0 - phase * phase

	func _draw() -> void:
		var ink := Color("1d2b2c")
		var green := Color("9fd08a")
		draw_rect(Rect2(-5.5, -2.5, 11.0, 5.0), ink)
		draw_rect(Rect2(-2.5, -5.5, 5.0, 11.0), ink)
		draw_rect(Rect2(-4.5, -1.5, 9.0, 3.0), green)
		draw_rect(Rect2(-1.5, -4.5, 3.0, 9.0), green)


# =============================================================================
#  Network snapshot (owner only) and solo save
# =============================================================================

func _snapshot_rows(slot: int) -> Variant:
	## [[building network id, units inside, bell 0/1, being repaired 0/1], ...]
	## for the recipient's own buildings only.
	if not is_instance_valid(main) or slot < 0 or slot >= main._player_buildings.size():
		return null
	var rows: Array = []
	for entry: Variant in main._player_buildings[slot]:
		if not is_instance_valid(entry) or not entry is BuildingBase or (entry as BuildingBase).state != BuildingBase.State.ACTIVE:
			continue
		var building := entry as BuildingBase
		var inside: int = garrisoned_units(building).size()
		var repairing: bool = is_being_repaired(building)
		var id: int = NetworkSession.entity_id(building)
		if id > 0 and (inside > 0 or building.bell_active or repairing):
			rows.append([id, inside, 1 if building.bell_active else 0, 1 if repairing else 0])
	return rows


func _apply_snapshot_rows(rows: Variant) -> void:
	if not is_instance_valid(main) or not NetworkSession.is_client():
		return
	var adapter: Node = NetworkSession.adapter
	var entities: Dictionary = adapter.get("entities") if is_instance_valid(adapter) else {}
	var listed: Dictionary = {}
	if rows is Array:
		for row: Variant in rows:
			if not row is Array or row.size() < 4:
				continue
			var building: BuildingBase = entities.get(int(row[0])) as BuildingBase
			if is_instance_valid(building) and building.player_owner == 0:
				listed[building] = row
	for entry: Variant in main._player_buildings[0]:
		if not is_instance_valid(entry) or not entry is BuildingBase:
			continue
		var building := entry as BuildingBase
		var row: Array = listed.get(building, [0, 0, 0, 0])
		var ringing: bool = int(row[2]) == 1
		building.set_meta("network_garrison", maxi(0, int(row[1])))
		if int(row[3]) == 1:
			building.set_meta("repair_until", GameManager.game_time + 0.6)
		if ringing != building.bell_active:
			building.bell_active = ringing
			_announce_bell(building, ringing)
		if listed.has(building) or building.has_meta("garrison_badge"):
			_refresh_badge(building)
	# Own garrisoned replicas stay in the snapshot (so they do not read as
	# deaths) and are simply not shown. A rival's is only here for the grace
	# period: full health keeps its removal from playing a death.
	for entry: Variant in main._player_units[0]:
		if not is_instance_valid(entry) or not entry is UnitBase:
			continue
		var unit := entry as UnitBase
		var inside: bool = unit.current_state == UnitBase.State.GARRISONED
		if inside and unit.visible:
			_deselect(unit)
			unit.visible = false
			unit.set_meta("garrison_hidden", true)
		elif not inside and unit.has_meta("garrison_hidden"):
			unit.remove_meta("garrison_hidden")
			unit.visible = true
	for entry: Variant in main._player_units[1]:
		if is_instance_valid(entry) and entry is UnitBase and (entry as UnitBase).current_state == UnitBase.State.GARRISONED:
			(entry as UnitBase).hp = (entry as UnitBase).max_hp


func _capture_save(_codec: RefCounted) -> Dictionary:
	## Membership itself is plain fields (BuildingBase.garrisoned_ids and
	## UnitBase._garrison_target); this entry only asks for the finalize pass.
	return {"version": 1}


func _restore_save(_saved: Dictionary, _codec: RefCounted) -> void:
	pass


func _finalize_save(_saved: Dictionary, _codec: RefCounted) -> void:
	## Every actor is back on the field with its saved fields. Put the
	## garrisoned ones inside again.
	if not is_instance_valid(main):
		return
	for owner: int in 2:
		for entry: Variant in main._player_buildings[owner]:
			if not is_instance_valid(entry) or not entry is BuildingBase or capacity_of(entry as BuildingBase) <= 0:
				continue
			var building := entry as BuildingBase
			for id: int in building.garrisoned_ids.duplicate():
				var unit: UnitBase = instance_from_id(id) as UnitBase
				if is_instance_valid(unit) and unit.current_state == UnitBase.State.GARRISONED and unit._garrison_target == building:
					_stow(unit)
				else:
					building.garrisoned_ids.erase(id)
			if not building.garrisoned_ids.is_empty() or building.bell_active:
				_watch(building)
				_refresh_badge(building)
		for entry: Variant in main._player_units[owner]:
			# A unit saved as garrisoned whose shelter is gone walks free.
			if is_instance_valid(entry) and entry is UnitBase and (entry as UnitBase).current_state == UnitBase.State.GARRISONED and (entry as UnitBase).is_inside_tree():
				var unit := entry as UnitBase
				unit._garrison_target = null
				unit.current_state = UnitBase.State.MOVING
				if unit is Villager and (unit as Villager)._auto_recovering:
					(unit as Villager)._resume_after_recovery()
				else:
					unit.set_state(UnitBase.State.IDLE)
