extends RefCounted
## Optional match lessons and receipt-based human telemetry. No resources, units,
## damage, orders or visibility are changed by this observer.

var active: bool = false
var lesson: String = "army"
var paid_army: int = 0
var first_army_seconds: float = -1.0
var paid_roles: Dictionary = {}
var army_losses: int = 0
var worker_losses: int = 0
var army_replacements: int = 0
var worker_replacements: int = 0
var retreats_completed: int = 0
var objective_contests: int = 0
var objective_captures: int = 0
var deposits: Dictionary = {"food": 0, "wood": 0, "gold": 0}
var visible_enemy_roles: Dictionary = {}
var _recent_damage: Dictionary = {}
var _retreat_orders: Dictionary = {}
var _paid_unit_ids: Dictionary = {}
var _contesting: bool = false
var _counter_demonstrated: bool = false
var _injured_army: bool = false


func start() -> void:
	active = true


func stop() -> void:
	active = false


func observe_training(unit: UnitBase, elapsed: float) -> void:
	if unit.unit_type == UnitData.UnitType.VILLAGER:
		if worker_replacements < worker_losses:
			worker_replacements += 1
		return
	if int(UnitData.UNITS.get(unit.unit_type, {}).get("damage", 0)) <= 0:
		return  # A paid Scout is reconnaissance, not a fighting army.
	paid_army += 1
	_paid_unit_ids[unit.get_instance_id()] = unit.unit_type
	paid_roles[unit.unit_type] = int(paid_roles.get(unit.unit_type, 0)) + 1
	if first_army_seconds < 0.0:
		first_army_seconds = elapsed
	if army_replacements < army_losses:
		army_replacements += 1


func observe_loss(unit: UnitBase) -> void:
	if unit.unit_type == UnitData.UnitType.VILLAGER:
		worker_losses += 1
	elif int(UnitData.UNITS.get(unit.unit_type, {}).get("damage", 0)) > 0:
		army_losses += 1
	_recent_damage.erase(unit.get_instance_id())
	_retreat_orders.erase(unit.get_instance_id())
	_paid_unit_ids.erase(unit.get_instance_id())


func observe_damage(unit: UnitBase, elapsed: float) -> void:
	_recent_damage[unit.get_instance_id()] = elapsed


func observe_deposit(resource: String, amount: int) -> void:
	deposits[resource] = int(deposits.get(resource, 0)) + amount


func observe_retreat_order(unit: UnitBase, destination: Vector2, elapsed: float, visible_enemies: Array) -> void:
	if unit.unit_type == UnitData.UnitType.VILLAGER or unit.unit_type == UnitData.UnitType.SCOUT:
		return
	var id: int = unit.get_instance_id()
	if elapsed - float(_recent_damage.get(id, -1000.0)) > 15.0:
		return
	var nearest_enemy: UnitBase = null
	var nearest_distance: float = INF
	for node in visible_enemies:
		if not is_instance_valid(node) or not node is UnitBase or node.current_state == UnitBase.State.DEAD:
			continue
		var distance: float = unit.global_position.distance_to(node.global_position)
		if distance < nearest_distance:
			nearest_enemy = node
			nearest_distance = distance
	if nearest_enemy == null or destination.distance_to(nearest_enemy.global_position) < nearest_distance + 48.0:
		return
	_retreat_orders[id] = {"unit": weakref(unit), "start": unit.global_position, "destination": destination, "time": elapsed}


func observe_state(units: Array, enemies: Array, buildings: Array, site: Node2D, elapsed: float) -> Dictionary:
	visible_enemy_roles.clear()
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy is UnitBase and enemy.current_state != UnitBase.State.DEAD:
			visible_enemy_roles[enemy.unit_type] = true
	_injured_army = false
	var living_paid_roles: Dictionary = {}
	for unit in units:
		if not is_instance_valid(unit) or not unit is UnitBase or unit.current_state == UnitBase.State.DEAD:
			continue
		var id: int = unit.get_instance_id()
		if _paid_unit_ids.has(id):
			living_paid_roles[unit.unit_type] = true
		if int(UnitData.UNITS.get(unit.unit_type, {}).get("damage", 0)) > 0 and unit.unit_type != UnitData.UnitType.VILLAGER:
			_injured_army = _injured_army or (unit.hp < unit.max_hp * 0.7 and elapsed - float(_recent_damage.get(id, -1000.0)) <= 15.0)
	for role: int in living_paid_roles:
		for enemy_role: int in visible_enemy_roles:
			if float(UnitData.COUNTER_BONUSES.get(role, {}).get(enemy_role, 1.0)) > 1.0:
				_counter_demonstrated = true
	# Two living, paid core roles also demonstrate the mix before a first fight.
	var core_roles: int = 0
	for role: int in living_paid_roles:
		if role in [UnitData.UnitType.INFANTRY, UnitData.UnitType.ARCHER, UnitData.UnitType.CAVALRY]:
			core_roles += 1
	_counter_demonstrated = _counter_demonstrated or core_roles >= 2
	for id: int in _retreat_orders.keys():
		var receipt: Dictionary = _retreat_orders[id]
		var unit: UnitBase = receipt["unit"].get_ref() as UnitBase
		if unit == null or unit.current_state == UnitBase.State.DEAD or elapsed - float(receipt["time"]) > 30.0:
			_retreat_orders.erase(id)
			continue
		if unit.global_position.distance_to(receipt["destination"]) <= 40.0 and unit.global_position.distance_to(receipt["start"]) >= 48.0 and unit.current_state != UnitBase.State.ATTACKING:
			retreats_completed += 1
			_retreat_orders.erase(id)
	var status: Dictionary = site.get_status() if is_instance_valid(site) else {}
	var human_in_ring: bool = false
	if is_instance_valid(site):
		for unit in units:
			if is_instance_valid(unit) and unit is UnitBase and unit.current_state != UnitBase.State.DEAD and unit.global_position.distance_to(site.global_position) <= site.get_capture_radius_world():
				human_in_ring = true
	var contesting: bool = human_in_ring and str(status.get("phase", "")) == "contested"
	if contesting and not _contesting:
		objective_contests += 1
	_contesting = contesting
	return _choose_lesson(buildings, status)


func observe_capture(player_id: int) -> void:
	if player_id == 0:
		objective_captures += 1


func _choose_lesson(buildings: Array, site_status: Dictionary) -> Dictionary:
	var focus: String = ""
	var building_type: int = -1
	var unit_type: int = -1
	var text: String = ""
	if worker_losses > worker_replacements:
		lesson = "recovery"
		text = "Recover · Open Economy and train a Villager. Keep food staffed."
		unit_type = UnitData.UnitType.VILLAGER
	elif _injured_army and retreats_completed == 0:
		lesson = "retreat"
		text = "Retreat · Tap safe ground. Hold ground to fight on the way."
	elif paid_army == 0:
		lesson = "army"
		building_type = BuildingData.BuildingType.BARRACKS
		unit_type = UnitData.UnitType.INFANTRY
		text = "Army · Gather Food + Wood. Build a Barracks, then recruit a Warrior."
		for building in buildings:
			if is_instance_valid(building) and building.building_type == building_type and building.state != BuildingBase.State.DESTROYED:
				text = "Army · Finish your Barracks, then recruit a paid Warrior."
				if building.state == BuildingBase.State.ACTIVE:
					text = "Army · Select Barracks, then Warrior. Queued troops must finish training."
				break
	elif army_losses > army_replacements:
		lesson = "recovery"
		text = "Recover · Recruit replacement troops. Keep Food + Wood workers gathering."
	elif not _counter_demonstrated:
		lesson = "counters"
		unit_type = _recommended_counter()
		building_type = _producer_for(unit_type)
		if unit_type >= 0:
			text = "Counters · Enemy %s: recruit %s at %s." % [UnitData.get_unit_name(_countered_role(unit_type), 1), UnitData.get_unit_name(unit_type, 0), BuildingData.get_building_name(building_type)]
		else:
			building_type = BuildingData.BuildingType.ARCHERY_RANGE
			unit_type = UnitData.UnitType.ARCHER
			var ranged_name: String = UnitData.get_unit_name(unit_type, 0) + "s"
			text = "Counters · Add %s at an Archery Range. They beat Warriors; Warriors beat cavalry." % ranged_name
	else:
		lesson = "objective"
		if str(site_status.get("phase", "")) == "contested":
			text = "Sacred · Both sides are in the ring. The victory clock is paused; reinforce."
		elif int(site_status.get("owner", -1)) == 0:
			if int(site_status.get("match_mode", SkirmishData.MatchMode.STANDARD)) != SkirmishData.MatchMode.STANDARD:
				text = "Sacred · Bank control across captures. Rally paid replacements and protect your workers."
			else:
				var target_seconds: int = ceili(float(site_status.get("total", SkirmishData.SACRED_VICTORY_HOLD_SECONDS)))
				text = "Sacred · Hold for %d:%02d. Rally replacements nearby and protect your workers." % [int(target_seconds / 60.0), target_seconds % 60]
		else:
			text = "Sacred · Tap the Site locator; send your army into its ring to capture or contest."
	return {"text": text, "focus": focus, "building_type": building_type, "unit_type": unit_type, "lesson": lesson}


func _recommended_counter() -> int:
	for role: int in [UnitData.UnitType.INFANTRY, UnitData.UnitType.ARCHER, UnitData.UnitType.CAVALRY]:
		if visible_enemy_roles.has(_countered_role(role)):
			return role
	return -1


func _countered_role(role: int) -> int:
	match role:
		UnitData.UnitType.INFANTRY: return UnitData.UnitType.CAVALRY
		UnitData.UnitType.ARCHER: return UnitData.UnitType.INFANTRY
		UnitData.UnitType.CAVALRY: return UnitData.UnitType.ARCHER
	return -1


func _producer_for(role: int) -> int:
	match role:
		UnitData.UnitType.ARCHER: return BuildingData.BuildingType.ARCHERY_RANGE
		UnitData.UnitType.CAVALRY: return BuildingData.BuildingType.STABLE
	return BuildingData.BuildingType.BARRACKS


func get_summary() -> Dictionary:
	return {"active": active, "lesson": lesson, "paid_army": paid_army, "first_army_seconds": first_army_seconds, "paid_roles": paid_roles.duplicate(), "army_losses": army_losses, "worker_losses": worker_losses, "army_replacements": army_replacements, "worker_replacements": worker_replacements, "retreats_completed": retreats_completed, "objective_contests": objective_contests, "objective_captures": objective_captures, "counter_demonstrated": _counter_demonstrated, "deposits": deposits.duplicate()}
