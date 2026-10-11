extends Node
## Real order dispatch, movement arrival and Sacred proximity under controlled
## paid army fixtures. Damage/opponents/buildings/funds are injected for coverage.

@onready var root: Window = get_tree().root
var failures: Array[String] = []
var evidence: Dictionary = {"scope": "Deterministic fixture, actual paid queue births, explicit Move and real unit processing/Sacred count; synthetic funds/buildings/damage/opponent placement", "checks": []}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var gm: Node = root.get_node("GameManager")
	root.get_node("AudioManager").set_all_enabled(false)
	gm.set("guided_opening_enabled", false)
	gm.set("selected_map_seed", 42)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	get_tree().current_scene = main
	for _i in range(900):
		if main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	main.set_process(false)
	main.get_node("AIController").set_process(false)
	var map: Node2D = main.get_node("GameMap")
	var selection: Node = map.get("selection_mgr")
	for resource in ["food", "wood", "gold"]:
		root.get_node("ResourceManager").add_resource(0, resource, 1000)
	gm.players[0]["population_cap"] = 30
	var barracks: BuildingBase = main.call("_spawn_building", BuildingData.BuildingType.BARRACKS, 0, Vector2i(10, 10))
	barracks.call("_complete_construction")
	main.call("_on_train_unit_requested", barracks, UnitData.UnitType.INFANTRY)
	main.call("_advance_production_queues", 12.1)
	var warrior: UnitBase = null
	for unit in main.get("_player_units")[0]:
		if unit.unit_type == UnitData.UnitType.INFANTRY:
			warrior = unit
	var coach: RefCounted = main.get("_match_learning")
	main.call("_start_match_learning")
	# Clear a small deterministic movement corridor, keeping canonical conversions.
	for x in range(19, 29):
		for y in range(19, 23):
			map.pathfinding.set_solid(Vector2i(x, y), false)
	warrior.global_position = map.tile_to_world(Vector2i(22, 21))
	warrior.command_stop()
	var enemy: UnitBase = main.call("_spawn_unit", UnitData.UnitType.INFANTRY, 1, map.tile_to_world(Vector2i(21, 21)))
	enemy.command_stop()
	enemy.set_process(false)
	main.call("_update_fog_of_war")
	main.call("_update_fog_entity_visibility")
	warrior.take_damage(20)
	gm.set("game_time", 100.0)
	coach.observe_damage(warrior, 100.0)
	selection.select_single(warrior)
	# Ordinary smart ground commands must never count as explicit retreats.
	main.call("_on_move_command", Vector2i(26, 21))
	main.call("_refresh_match_learning")
	_expect(coach.retreats_completed == 0, "Attack-move order earns no retreat credit")
	warrior.command_stop()
	main.call("_arm_move_command")
	main.call("_on_move_command", Vector2i(26, 21))
	_expect(coach.retreats_completed == 0, "Armed Move earns no credit before safe arrival")
	for _frame in range(360):
		warrior.call("_process", 1.0 / 60.0)
		gm.set("game_time", 100.0 + _frame / 60.0)
		main.call("_refresh_match_learning")
		if coach.retreats_completed > 0:
			break
	_expect(coach.retreats_completed == 1 and warrior.hp > 0.0, "Actual movement away from visible foe with survivor completes retreat")
	var site: Node2D = map.get("sacred_site")
	site.set_process(false)
	# Move real live entities into the actual capture radius. Status locator alone
	# earns no objective credit; both players' presence really pauses the clock.
	main.call("_on_sacred_site_pressed")
	main.call("_refresh_match_learning")
	_expect(coach.objective_contests == 0 and coach.objective_captures == 0, "Looking at objective earns no capture/contest credit")
	warrior.global_position = site.global_position
	enemy.global_position = site.global_position + Vector2(30, 0)
	site.set("state", 2)
	site.set("owning_player", 1)
	site.set("victory_timer", 50.0)
	site.set("capture_progress", 1.0)
	site.call("_process", 1.0)
	main.call("_refresh_match_learning")
	_expect(coach.objective_contests == 1 and site.get("victory_timer") == 50.0, "Real living proximity contests Sacred and freezes enemy clock")
	main.call("_refresh_match_learning")
	_expect(coach.objective_contests == 1, "Continued contest counts once")
	# Fog check: private hidden roles must not shape the optional lesson.
	enemy.global_position = map.tile_to_world(Vector2i(55, 55))
	enemy.unit_type = UnitData.UnitType.CAVALRY
	main.call("_update_fog_of_war")
	main.call("_refresh_match_learning")
	_expect(not coach.visible_enemy_roles.has(UnitData.UnitType.CAVALRY), "Hidden enemy role never enters learning intel")
	evidence["summary"] = coach.get_summary()
	var output := FileAccess.open("res://output/evolution/learning-20261010-battle-lessons/field-actions.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(evidence, "\t"))
	main.free()
	get_tree().current_scene = null
	await get_tree().process_frame
	if failures.is_empty():
		print("[PASS] match_learning_field_actions: explicit surviving retreat, actual Sacred contest and visibility-limited counters")
		get_tree().quit(0)
	else:
		get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	evidence["checks"].append({"pass": condition, "message": message})
	if not condition:
		failures.append(message)
		push_error("[FAIL] match_learning_field_actions: " + message)
