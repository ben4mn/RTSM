extends Node
## Focused headless regression for the canonical attack/armor damage contract.

const UNIT_SCENES: Dictionary = {
	UnitData.UnitType.INFANTRY: preload("res://scenes/units/infantry.tscn"),
	UnitData.UnitType.ARCHER: preload("res://scenes/units/archer.tscn"),
	UnitData.UnitType.SIEGE: preload("res://scenes/units/siege.tscn"),
}
const HOUSE_SCENE: PackedScene = preload("res://scenes/buildings/house.tscn")
const TOWER_SCENE: PackedScene = preload("res://scenes/buildings/watch_tower.tscn")

var _failures: Array[String] = []
var _game_manager: Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_game_manager = get_node("/root/GameManager")
	get_node("/root/AudioManager").call("set_all_enabled", false)
	# Keep exact HP assertions free from transient VFX/tween nodes.
	get_tree().current_scene = null
	_test_base_unit_damage_is_mitigated_once()
	_test_counter_multiplier_precedes_armor()
	_test_upgrades_apply_once_to_existing_and_new_units()
	_test_minimum_damage()
	_test_unit_to_building_damage()
	_test_tower_armor_contract()
	_finish()


func _test_base_unit_damage_is_mitigated_once() -> void:
	_reset_upgrades()
	var attacker := _make_unit(UnitData.UnitType.INFANTRY, 0)
	var defender := _make_unit(UnitData.UnitType.INFANTRY, 1)
	_expect_float(Combat.calculate_unit_damage(attacker, defender), 6.0, "infantry 8 vs armor 2 calculates 6")
	var hp_before: float = defender.hp
	Combat.deal_damage(attacker, defender)
	_expect_float(hp_before - defender.hp, 6.0, "infantry 8 vs armor 2 removes exactly 6 HP")
	_free_nodes([attacker, defender])


func _test_counter_multiplier_precedes_armor() -> void:
	_reset_upgrades()
	var attacker := _make_unit(UnitData.UnitType.ARCHER, 0)
	var defender := _make_unit(UnitData.UnitType.INFANTRY, 1)
	_expect_float(Combat.calculate_unit_damage(attacker, defender), 12.0, "Archer counter is 7 * 2.0 - 2 = 12")
	var hp_before: float = defender.hp
	Combat.deal_damage(attacker, defender)
	_expect_float(hp_before - defender.hp, 12.0, "Archer counter removes exactly 12 HP")
	_free_nodes([attacker, defender])


func _test_upgrades_apply_once_to_existing_and_new_units() -> void:
	_reset_upgrades()
	var existing_attacker := _make_unit(UnitData.UnitType.INFANTRY, 0)
	var existing_defender := _make_unit(UnitData.UnitType.INFANTRY, 1)
	_game_manager.call("apply_attack_upgrade", 0, 2)
	_game_manager.call("apply_armor_upgrade", 1, 1)
	var new_attacker := _make_unit(UnitData.UnitType.INFANTRY, 0)
	var new_defender := _make_unit(UnitData.UnitType.INFANTRY, 1)

	_expect_float(existing_attacker.damage, 8.0, "existing unit keeps base attack after research")
	_expect_float(new_attacker.damage, 8.0, "new unit keeps base attack after research")
	_expect_float(existing_defender.armor, 2.0, "existing unit keeps base armor after research")
	_expect_float(new_defender.armor, 2.0, "new unit keeps base armor after research")
	_expect_float(Combat.get_effective_attack(existing_attacker), 10.0, "existing unit exposes +2 effective attack")
	_expect_float(Combat.get_effective_attack(new_attacker), 10.0, "new unit exposes +2 effective attack")
	_expect_float(Combat.get_effective_armor(existing_defender), 3.0, "existing unit exposes +1 effective armor")
	_expect_float(Combat.get_effective_armor(new_defender), 3.0, "new unit exposes +1 effective armor")
	_expect_float(Combat.calculate_unit_damage(existing_attacker, existing_defender), 7.0, "existing units apply each upgrade once")
	_expect_float(Combat.calculate_unit_damage(new_attacker, new_defender), 7.0, "new units apply each upgrade once")
	var existing_hp_before: float = existing_defender.hp
	Combat.deal_damage(existing_attacker, existing_defender)
	_expect_float(existing_hp_before - existing_defender.hp, 7.0, "existing units lose upgraded damage exactly once")
	var new_hp_before: float = new_defender.hp
	Combat.deal_damage(new_attacker, new_defender)
	_expect_float(new_hp_before - new_defender.hp, 7.0, "new units lose upgraded damage exactly once")
	_free_nodes([existing_attacker, existing_defender, new_attacker, new_defender])


func _test_minimum_damage() -> void:
	_reset_upgrades()
	var attacker := _make_unit(UnitData.UnitType.INFANTRY, 0)
	var defender := _make_unit(UnitData.UnitType.INFANTRY, 1)
	attacker.damage = 1.0
	defender.armor = 999.0
	_expect_float(Combat.calculate_unit_damage(attacker, defender), 1.0, "armor cannot reduce an attack below 1")
	var hp_before: float = defender.hp
	Combat.deal_damage(attacker, defender)
	_expect_float(hp_before - defender.hp, 1.0, "minimum damage removes exactly 1 HP")
	_free_nodes([attacker, defender])


func _test_unit_to_building_damage() -> void:
	_reset_upgrades()
	var infantry := _make_unit(UnitData.UnitType.INFANTRY, 0)
	var siege := _make_unit(UnitData.UnitType.SIEGE, 0)
	var building := _make_building(HOUSE_SCENE, 1)
	_game_manager.call("apply_attack_upgrade", 0, 2)
	_expect_eq(Combat.calculate_building_damage(infantry), 10, "unit-to-building damage includes +2 attack")
	_expect_eq(Combat.calculate_building_damage(siege), 96, "siege damage is (30 + 2) * 3")
	var hp_before: int = building.hp
	Combat.deal_damage_to_building(siege, building)
	_expect_eq(hp_before - building.hp, 96, "siege removes the calculated 96 building HP")
	_free_nodes([infantry, siege, building])


func _test_tower_armor_contract() -> void:
	_reset_upgrades()
	var tower := _make_building(TOWER_SCENE, 0)
	var defender := _make_unit(UnitData.UnitType.INFANTRY, 1)
	_expect_float(Combat.calculate_tower_damage(tower, defender), 4.0, "tower 6 vs base armor 2 calculates 4")
	var hp_before: float = defender.hp
	Combat.deal_tower_damage(tower, defender)
	_expect_float(hp_before - defender.hp, 4.0, "tower damage is mitigated exactly once")

	_game_manager.call("apply_armor_upgrade", 1, 1)
	_game_manager.call("apply_attack_upgrade", 0, 2)
	_expect_float(Combat.calculate_tower_damage(tower, defender), 3.0, "tower respects +1 unit armor dynamically")
	_expect_float(float(tower.tower_attack_damage), 6.0, "unit attack upgrades do not change tower weapons")
	hp_before = defender.hp
	Combat.deal_tower_damage(tower, defender)
	_expect_float(hp_before - defender.hp, 3.0, "upgraded armor mitigates tower damage exactly once")
	_free_nodes([tower, defender])


func _reset_upgrades() -> void:
	_game_manager.call("initialize_game", 2)


func _make_unit(unit_type: int, player_id: int) -> UnitBase:
	var unit: UnitBase = (UNIT_SCENES[unit_type] as PackedScene).instantiate() as UnitBase
	unit.player_owner = player_id
	unit.unit_type = unit_type
	add_child(unit)
	return unit


func _make_building(scene: PackedScene, player_id: int) -> BuildingBase:
	var building: BuildingBase = scene.instantiate() as BuildingBase
	building.player_owner = player_id
	add_child(building)
	building.complete_instantly()
	return building


func _free_nodes(nodes: Array) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.free()


func _expect_float(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		_failures.append("%s (expected %.2f, got %.2f)" % [message, expected, actual])


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] combat_damage: canonical damage, upgrades, armor, counters, siege, and towers")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] combat_damage: %s" % failure)
	get_tree().quit(1)
