extends Node
## Synthetic boundary pocket reproduces paid Archers stranded in seed 424242.

var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 424242
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	main.set_process(false)
	main.ai_controller.process_mode = Node.PROCESS_MODE_DISABLED
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	var map: Node2D = main.game_map
	var generator := MapGenerator.new(424242)
	generator.call("_init_grid")
	map.pathfinding = Pathfinding.new(generator)
	var producer: BuildingBase = main._spawn_building(BuildingData.BuildingType.ARCHERY_RANGE, 0, Vector2i(3, 67))
	producer.complete_instantly()
	for tile: Vector2i in [Vector2i(4, 66), Vector2i(6, 66), Vector2i(4, 65), Vector2i(6, 65), Vector2i(5, 64)]:
		map.pathfinding.set_solid(tile, true)
	var pocket := Vector2i(5, 66)
	producer.set_rally_point(map.tile_to_world(pocket))
	var egress: Dictionary = main._resolve_production_egress(producer)
	_expect(bool(egress.get("valid", false)), "boundary producer retains a legal local egress")
	if bool(egress.get("valid", false)):
		var tile: Vector2i = egress.tile
		var route: Array[Vector2i] = map.pathfinding.get_tile_path(tile, Vector2i(14, 60))
		_expect(not route.is_empty(), "egress chooses connected battlefield side instead of the nearer two-cell pocket")
		var archer: UnitBase = main._spawn_unit(UnitData.UnitType.ARCHER, 0, egress.world_position)
		archer.set_process(false)
		archer.command_move(map.tile_to_world(Vector2i(14, 60)))
		for tick: int in 900:
			archer._process(1.0 / 30.0)
			if archer.current_state == UnitBase.State.IDLE:
				break
		_expect(archer.position.distance_to(archer.move_target) <= 4.1, "trained role can actually leave its egress and reach the battlefield")
	main.free()
	for failure: String in _failures:
		push_error("[FAIL] production_egress_connectivity: " + failure)
	if _failures.is_empty():
		print("[PASS] production_egress_connectivity: boundary-pocket spawn rejected, Archer naturally reaches connected battlefield")
	get_tree().quit(0 if _failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
