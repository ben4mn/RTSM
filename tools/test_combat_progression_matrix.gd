extends Node
## Paid age/research transactions and exact combat values for both owners.
## Synthetic resource funding isolates the rules; no balance/win-rate claim.

const SCENES: Array[PackedScene] = [
	preload("res://scenes/units/villager.tscn"),
	preload("res://scenes/units/infantry.tscn"),
	preload("res://scenes/units/archer.tscn"),
	preload("res://scenes/units/cavalry.tscn"),
	preload("res://scenes/units/scout.tscn"),
	preload("res://scenes/units/siege.tscn"),
]
const BLACKSMITH: PackedScene = preload("res://scenes/buildings/blacksmith.tscn")
const HOUSE: PackedScene = preload("res://scenes/buildings/house.tscn")
const TOWER: PackedScene = preload("res://scenes/buildings/watch_tower.tscn")
const TC: PackedScene = preload("res://scenes/buildings/town_center.tscn")
const BASE_HP: Array[float] = [25.0, 60.0, 35.0, 80.0, 45.0, 100.0]
const BASE_ATTACK: Array[float] = [3.0, 8.0, 7.0, 10.0, 0.0, 30.0]
const BASE_ARMOR: Array[float] = [0.0, 2.0, 0.0, 1.0, 0.0, 3.0]
const BASE_COUNTERS: Dictionary = {Vector2i(1, 3): 2.0, Vector2i(2, 1): 2.0, Vector2i(3, 2): 1.5}
var failures: Array[String] = []
var checks: int = 0
var damage_cells: int = 0
var report: Dictionary = {"scope": "Synthetic funded transactions, exact damage equations and unchanged age stats. No hands-on/balance/physical-device claim.", "states": [], "examples": []}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	get_tree().current_scene = null
	for age: int in range(1, 4):
		for first_mask: int in 4:
			for second_mask: int in 4:
				_test_state(age, [first_mask, second_mask])
	_test_prospective_loom_and_immutable_data()
	_test_minimum_damage_and_release_snapshot()
	report["checks"] = checks
	report["damage_cells"] = damage_cells
	report["failures"] = failures
	report["source_hashes"] = {}
	for source: String in ["scripts/units/combat.gd", "scripts/units/unit_base.gd", "scripts/data/unit_data.gd", "scripts/data/tech_data.gd", "scripts/managers/game_manager.gd"]:
		report.source_hashes[source] = FileAccess.get_file_as_string("res://" + source).sha256_text()
	DirAccess.make_dir_recursive_absolute("res://output/polish-combat-stats-2026-10-22")
	var file := FileAccess.open("res://output/polish-combat-stats-2026-10-22/matrix.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	for failure: String in failures:
		push_error("[FAIL] combat_progression_matrix: " + failure)
	if failures.is_empty():
		print("[PASS] combat_progression_matrix: %d checks, %d damage cells, 48 paid progression states" % [checks, damage_cells])
	get_tree().quit(0 if failures.is_empty() else 1)


func _unit(parent: Node, kind: int, owner: int) -> UnitBase:
	var unit := SCENES[kind].instantiate() as UnitBase
	unit.player_owner = owner
	parent.add_child(unit)
	unit.set_process(false)
	return unit


func _building(parent: Node, scene: PackedScene, owner: int) -> BuildingBase:
	var building := scene.instantiate() as BuildingBase
	building.player_owner = owner
	parent.add_child(building)
	building.complete_instantly()
	building.set_process(false)
	return building


func _test_state(age: int, masks: Array[int]) -> void:
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	GameManager.selected_population_limit = 30
	GameManager.initialize_game(2)
	var arena := Node2D.new()
	add_child(arena)
	var existing: Array = [[], []]
	var trained: Array = [[], []]
	for owner: int in 2:
		ResourceManager.initialize_player(owner, {"food": 10000, "wood": 10000, "gold": 10000})
		for kind: int in 6:
			existing[owner].append(_unit(arena, kind, owner))
		for advance: int in range(1, age):
			_expect(GameManager.try_advance_age(owner), "owner %d exact age transaction to %d succeeds" % [owner, advance + 1])
		var forge: BuildingBase = _building(arena, BLACKSMITH, owner)
		var before: Dictionary = ResourceManager.get_all_resources(owner)
		var research_count: int = 0
		for technology: String in ["forging", "scale_mail"]:
			var bit: int = 1 if technology == "forging" else 2
			if masks[owner] & bit:
				_expect(GameManager.try_research(owner, forge, technology), "owned active Blacksmith accepts %s at age %d" % [technology, age])
				research_count += 1
				var paid: Dictionary = ResourceManager.get_all_resources(owner)
				_expect(not GameManager.try_research(owner, forge, technology), "duplicate %s cannot stack" % technology)
				_expect(ResourceManager.get_all_resources(owner) == paid, "duplicate research cannot spend")
		var after: Dictionary = ResourceManager.get_all_resources(owner)
		_expect(int(before.food) - int(after.food) == research_count * 100 and int(before.gold) - int(after.gold) == research_count * 50, "research uses exact shared costs")
		for kind: int in 6:
			trained[owner].append(_unit(arena, kind, owner))
		for collection: Array in [existing[owner], trained[owner]]:
			for kind: int in 6:
				var unit: UnitBase = collection[kind]
				_expect(unit.hp == BASE_HP[kind] and unit.max_hp == BASE_HP[kind], "age %d retains role %d HP" % [age, kind])
				_expect(unit.damage == BASE_ATTACK[kind] and unit.armor == BASE_ARMOR[kind], "base fields do not bake in age or Blacksmith bonuses")
				var expected_attack: float = BASE_ATTACK[kind] + (2.0 if masks[owner] & 1 else 0.0) if BASE_ATTACK[kind] > 0.0 else 0.0
				_expect(Combat.get_effective_attack(unit) == expected_attack, "role %d owner %d effective attack is %.0f at age %d mask %d" % [kind, owner, expected_attack, age, masks[owner]])
				_expect(Combat.get_effective_armor(unit) == BASE_ARMOR[kind] + (1.0 if masks[owner] & 2 else 0.0), "effective armor applies once to existing and new units")
				var preview: Dictionary = Combat.get_effective_unit_type_stats(kind, owner)
				_expect(float(preview.hp) == unit.max_hp and float(preview.damage) == Combat.get_effective_attack(unit) and float(preview.armor) == Combat.get_effective_armor(unit), "recruit preview agrees with actual existing/new role %d owner %d age %d mask %d" % [kind, owner, age, masks[owner]])
	for owner: int in 2:
		var enemy: int = 1 - owner
		for attackers: Array in [existing[owner], trained[owner]]:
			for defenders: Array in [existing[enemy], trained[enemy]]:
				for attacker_kind: int in [0, 1, 2, 3, 5]:
					for defender_kind: int in 6:
						var attacker: UnitBase = attackers[attacker_kind]
						var defender: UnitBase = defenders[defender_kind]
						var expected: float = maxf(1.0, (BASE_ATTACK[attacker_kind] + (2.0 if masks[owner] & 1 else 0.0)) * float(BASE_COUNTERS.get(Vector2i(attacker_kind, defender_kind), 1.0)) - BASE_ARMOR[defender_kind] - (1.0 if masks[enemy] & 2 else 0.0))
						_expect(Combat.calculate_unit_damage(attacker, defender) == expected, "age %d masks %s owner %d role %d vs %d expected %.1f impact" % [age, masks, owner, attacker_kind, defender_kind, expected])
						damage_cells += 1
						if defender_kind == UnitData.UnitType.INFANTRY:
							defender.hp = defender.max_hp
							Combat.deal_damage(attacker, defender)
							_expect(defender.max_hp - defender.hp == expected, "actual HP dispatch matches canonical damage once")
		var house: BuildingBase = _building(arena, HOUSE, enemy)
		var tower: BuildingBase = _building(arena, TOWER, owner)
		var tc: BuildingBase = _building(arena, TC, owner)
		for kind: int in [0, 1, 2, 3, 5]:
			var attacker: UnitBase = existing[owner][kind]
			var expected: int = int((BASE_ATTACK[kind] + (2.0 if masks[owner] & 1 else 0.0)) * (3.0 if kind == 5 else 1.0))
			house.hp = house.max_hp
			Combat.deal_damage_to_building(attacker, house)
			_expect(house.max_hp - house.hp == expected, "unit-to-building impact has attack bonus, siege multiplier and no armor")
		for kind: int in 6:
			var target: UnitBase = existing[enemy][kind]
			var expected: float = maxf(1.0, 6.0 - BASE_ARMOR[kind] - (1.0 if masks[enemy] & 2 else 0.0))
			_expect(Combat.calculate_tower_damage(tower, target) == expected and Combat.calculate_tower_damage(tc, target) == expected, "tower and TC respect live unit armor but ignore attacker Forge")
			target.hp = target.max_hp
			Combat.deal_tower_damage(tower, target)
			_expect(target.max_hp - target.hp == expected, "tower HP dispatch mitigates armor once")
			target.hp = target.max_hp
			Combat.deal_tower_damage(tc, target)
			_expect(target.max_hp - target.hp == expected, "Town Center HP dispatch mitigates armor once")
		var scout: UnitBase = existing[owner][UnitData.UnitType.SCOUT]
		scout.command_attack(existing[enemy][UnitData.UnitType.INFANTRY])
		scout.command_attack_building(house)
		_expect(scout.attack_target == null and scout.attack_building_target == null, "Forge cannot arm a Scout through explicit orders")
	if age == 1 and masks[0] in [0, 1] and masks[1] in [0, 2]:
		for pair: Vector2i in [Vector2i(1, 1), Vector2i(1, 3), Vector2i(2, 1), Vector2i(3, 2), Vector2i(2, 3)]:
			report.examples.append({"attacker": UnitData.get_unit_name(pair.x), "defender": UnitData.get_unit_name(pair.y), "attacker_forge": bool(masks[0] & 1), "defender_mail": bool(masks[1] & 2), "impact_damage": Combat.calculate_unit_damage(existing[0][pair.x], existing[1][pair.y])})
	report.states.append({"age": age, "owner0_tech_mask": masks[0], "owner1_tech_mask": masks[1]})
	arena.free()


func _test_prospective_loom_and_immutable_data() -> void:
	GameManager.initialize_game(2)
	ResourceManager.initialize_player(0, {"food": 1000, "wood": 1000, "gold": 1000})
	var arena := Node2D.new()
	add_child(arena)
	var forge: BuildingBase = _building(arena, BLACKSMITH, 0)
	for technology: String in ["forging", "scale_mail", "loom"]:
		_expect(GameManager.try_research(0, forge, technology), "preview setup pays for " + technology)
	var worker: Dictionary = Combat.get_effective_unit_type_stats(UnitData.UnitType.VILLAGER, 0)
	_expect(int(worker.hp) == 40 and float(worker.damage) == 5.0 and float(worker.armor) == 1.0, "prospective Villager combines Loom, Forge and Mail exactly once")
	for kind: int in 6:
		var own: Dictionary = Combat.get_effective_unit_type_stats(kind, 0)
		var enemy: Dictionary = Combat.get_effective_unit_type_stats(kind, 1)
		_expect(float(own.hp) == BASE_HP[kind] + (15.0 if kind == 0 else 0.0), "Loom preview applies only to Villagers")
		_expect(float(enemy.hp) == BASE_HP[kind] and float(enemy.damage) == BASE_ATTACK[kind] and float(enemy.armor) == BASE_ARMOR[kind], "preview research never leaks to the other owner")
	worker["damage"] = 999.0
	worker.cost["food"] = 999
	_expect(float(UnitData.UNITS[0].damage) == 3.0 and int(UnitData.UNITS[0].cost.food) == 50, "preview mutation cannot change canonical nested UnitData")
	_expect(Combat.get_effective_unit_type_stats(-1, 0).is_empty(), "unknown unit has no invented preview")
	arena.free()


func _test_minimum_damage_and_release_snapshot() -> void:
	GameManager.initialize_game(2)
	var arena := Node2D.new()
	add_child(arena)
	var worker: UnitBase = _unit(arena, UnitData.UnitType.VILLAGER, 0)
	var warrior: UnitBase = _unit(arena, UnitData.UnitType.INFANTRY, 1)
	warrior.armor = 100.0
	Combat.deal_damage(worker, warrior)
	_expect(warrior.max_hp - warrior.hp == 1.0, "armed attacks retain one minimum damage under extreme armor")
	warrior.armor = 2.0
	warrior.hp = warrior.max_hp
	var archer: UnitBase = _unit(arena, UnitData.UnitType.ARCHER, 0)
	archer.position = Vector2(-70.0, 0.0)
	Combat.launch_ranged_attack(archer, warrior)
	GameManager.apply_attack_upgrade(0, 2)
	GameManager.apply_armor_upgrade(1, 1)
	for child: Node in arena.get_children():
		if child.has_method("advance_projectile"):
			child.call("advance_projectile", 0.5)
			child.free()
	_expect(warrior.max_hp - warrior.hp == 12.0, "already released arrow retains release-time damage despite later research")
	_expect(Combat.calculate_unit_damage(archer, warrior) == 15.0, "next released shot sees both new upgrades")
	GameManager.initialize_game(2)
	warrior.hp = warrior.max_hp
	var infantry: UnitBase = _unit(arena, UnitData.UnitType.INFANTRY, 0)
	Combat.queue_melee_attack(infantry, warrior)
	GameManager.apply_attack_upgrade(0, 2)
	GameManager.apply_armor_upgrade(1, 1)
	for child: Node in arena.get_children():
		if child.has_method("advance_committed_hit"):
			child.call("advance_committed_hit")
			child.free()
	_expect(warrior.max_hp - warrior.hp == 6.0, "committed melee retains release-time damage despite later research")
	_expect(Combat.calculate_unit_damage(infantry, warrior) == 7.0, "next committed melee sees both new upgrades")
	arena.free()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition and not failures.has(message): failures.append(message)
