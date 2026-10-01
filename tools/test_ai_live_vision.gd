extends Node
## Regression for viewer-agnostic live vision and AI target continuity.

const GAME_MAP_SCENE: PackedScene = preload("res://scenes/map/game_map.tscn")
const INFANTRY_SCENE: PackedScene = preload("res://scenes/units/infantry.tscn")
const HOUSE_SCENE: PackedScene = preload("res://scenes/buildings/house.tscn")
const TOWER_SCENE: PackedScene = preload("res://scenes/buildings/watch_tower.tscn")

const PLAYER_HUMAN := 0
const PLAYER_AI := 1

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	var game_map: Node2D = GAME_MAP_SCENE.instantiate() as Node2D
	game_map.set("map_seed", 101)
	add_child(game_map)
	await get_tree().process_frame
	game_map.set_process(false)

	var ai := AIController.new()
	ai.player_id = PLAYER_AI
	ai.enemy_id = PLAYER_HUMAN
	game_map.add_child(ai)
	ai.game_map = game_map

	var ai_unit := _spawn_unit(game_map, PLAYER_AI, Vector2i(10, 10))
	var enemy := _spawn_unit(game_map, PLAYER_HUMAN, Vector2i(13, 10))
	ai.register_unit(ai_unit)

	# Real GameMap tile-circle vision is the single answer used by the controller
	# and UnitBase. A target inside the AI unit's radius can be acquired.
	_expect(bool(game_map.call("is_entity_visible_to_player", enemy, PLAYER_AI)), "AI unit vision did not reveal an in-radius target")
	_expect(_contains_identity(ai.call("_get_visible_enemies"), enemy), "AI controller disagreed with GameMap on a visible unit")
	ai.set("_game_time", 20.0)
	ai.call("_update_enemy_memory")
	var last_seen_position: Vector2 = enemy.global_position
	ai_unit.command_attack(enemy)
	_expect(ai_unit.attack_target == enemy, "AI unit could not acquire a canonically visible target")
	ai.call("_begin_attack_wave", [ai_unit], last_seen_position, enemy)
	var last_seen_hp: float = float(ai.get("_attack_wave_best_target_hp"))

	# The target then leaves every AI vision source. Hidden movement and HP must
	# not update either UnitBase's live target or attack-wave bookkeeping.
	ai_unit.global_position = game_map.call("tile_to_world", Vector2i(10, 10)) as Vector2
	enemy.global_position = game_map.call("tile_to_world", Vector2i(30, 30)) as Vector2
	enemy.hp -= 20.0
	_expect(not bool(game_map.call("is_entity_visible_to_player", enemy, PLAYER_AI)), "far target remained visible without an AI source")
	_expect(not _contains_identity(ai.call("_get_visible_enemies"), enemy), "AI controller retained a hidden unit")
	var wave_active: bool = bool(ai.call("_refresh_attack_wave_lifecycle"))
	_expect(wave_active, "position-only attack wave was discarded immediately after sight loss")
	_expect(ai.get("_attack_wave_target_ref") == null, "attack wave retained a hidden live target reference")
	_expect_vector(ai.get("_attack_wave_target_position"), last_seen_position, "attack wave read a hidden target position")
	_expect_float(float(ai.get("_attack_wave_best_target_hp")), last_seen_hp, "attack wave read hidden target HP")
	ai_unit.call("_process_attacking", 0.1)
	_expect(ai_unit.attack_target == null, "UnitBase kept chasing a target outside all AI vision")
	var memory_target: Dictionary = ai.call("_find_enemy_target_selection")
	_expect_eq(str(memory_target.get("source", "")), "memory", "lost target did not fall back to sighting memory")
	_expect(memory_target.get("node") == null, "sighting memory exposed a hidden live node")
	_expect_vector(memory_target.get("position", Vector2.ZERO), last_seen_position, "memory changed after hidden movement")

	# Non-destroyed AI buildings are canonical vision sources even when no AI
	# unit can see the target; destroyed buildings stop contributing immediately.
	ai_unit.global_position = game_map.call("tile_to_world", Vector2i(35, 35)) as Vector2
	var house := _spawn_building(game_map, HOUSE_SCENE, PLAYER_AI, Vector2i(20, 20))
	enemy.global_position = game_map.call("tile_to_world", Vector2i(23, 20)) as Vector2
	_expect(bool(game_map.call("is_entity_visible_to_player", enemy, PLAYER_AI)), "AI building vision did not reveal an in-radius unit")
	_expect(_contains_identity(ai.call("_get_visible_enemies"), enemy), "controller omitted a unit revealed only by a building")
	house.state = BuildingBase.State.DESTROYED
	_expect(not bool(game_map.call("is_entity_visible_to_player", enemy, PLAYER_AI)), "destroyed AI building continued to provide vision")
	_expect(not _contains_identity(ai.call("_get_visible_enemies"), enemy), "controller saw through a destroyed building")

	# Tower target checks share the same API, and enemy buildings are visible if
	# any footprint tile intersects a live source's tile circle.
	var tower := _spawn_building(game_map, TOWER_SCENE, PLAYER_AI, Vector2i(20, 20))
	enemy.global_position = game_map.call("tile_to_world", Vector2i(26, 20)) as Vector2
	_expect(bool(game_map.call("is_entity_visible_to_player", enemy, PLAYER_AI)), "tower vision did not reveal a target inside its tile circle")
	_expect(bool(tower.call("_is_tower_target_visible", enemy)), "tower disagreed with canonical visible target")
	enemy.global_position = game_map.call("tile_to_world", Vector2i(29, 20)) as Vector2
	_expect(not bool(game_map.call("is_entity_visible_to_player", enemy, PLAYER_AI)), "tower vision exceeded its configured tile radius")
	_expect(not bool(tower.call("_is_tower_target_visible", enemy)), "tower admitted a canonically hidden target")

	var enemy_house := _spawn_building(game_map, HOUSE_SCENE, PLAYER_HUMAN, Vector2i(11, 20))
	_expect(not bool(game_map.call("is_tile_visible_to_player", Vector2i(11, 20), PLAYER_AI)), "enemy building origin unexpectedly entered tower vision")
	_expect(bool(game_map.call("is_entity_visible_to_player", enemy_house, PLAYER_AI)), "visible edge of enemy footprint did not reveal the building")
	_expect(_contains_identity(ai.call("_get_visible_enemy_buildings"), enemy_house), "controller disagreed on footprint-visible building")
	_expect(bool(tower.call("_is_tower_target_visible", enemy_house)), "tower disagreed on footprint-visible building")
	tower.state = BuildingBase.State.DESTROYED
	_expect(not bool(game_map.call("is_entity_visible_to_player", enemy_house, PLAYER_AI)), "destroyed tower continued to reveal an enemy footprint")
	_expect(not _contains_identity(ai.call("_get_visible_enemy_buildings"), enemy_house), "controller retained a building after all AI vision was lost")

	game_map.free()
	_finish()


func _spawn_unit(game_map: Node2D, owner: int, tile_pos: Vector2i) -> UnitBase:
	var unit: UnitBase = INFANTRY_SCENE.instantiate() as UnitBase
	unit.player_owner = owner
	unit.global_position = game_map.call("tile_to_world", tile_pos) as Vector2
	game_map.get_node("UnitsContainer").add_child(unit)
	return unit


func _spawn_building(
	game_map: Node2D,
	packed_scene: PackedScene,
	owner: int,
	tile_pos: Vector2i
) -> BuildingBase:
	var building: BuildingBase = packed_scene.instantiate() as BuildingBase
	building.player_owner = owner
	building.global_position = game_map.call("tile_to_world", tile_pos) as Vector2
	game_map.get_node("BuildingsContainer").add_child(building)
	building.complete_instantly()
	return building


func _contains_identity(nodes: Array, target: Node) -> bool:
	for node: Node in nodes:
		if node == target:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected=%s actual=%s)" % [message, expected, actual])


func _expect_float(actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		_failures.append("%s (expected=%.3f actual=%.3f)" % [message, expected, actual])


func _expect_vector(actual: Variant, expected: Vector2, message: String) -> void:
	if not (actual is Vector2) or not (actual as Vector2).is_equal_approx(expected):
		_failures.append("%s (expected=%s actual=%s)" % [message, expected, actual])


func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] ai_live_vision: canonical unit/building vision drops live refs and preserves last sightings")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] ai_live_vision: %s" % failure)
	get_tree().quit(1)
