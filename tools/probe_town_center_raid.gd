extends Node
## Seeded real-map raid fixture. The army is synthetic, not paid production.
## Run: Godot --headless --fixed-fps 60 --path . tools/probe_town_center_raid.tscn -- --count=8 --type=1 --duration=150

var _count: int = 1
var _type: int = UnitData.UnitType.INFANTRY
var _duration: float = 150.0
var _seed: int = 101
var _approach: String = "north"
var _capture_directory: String = ""
var _audit_refuges: bool = false
var _refuge_audit: Dictionary = {}
var _shots: int = 0
var _main: Node2D
var _attackers: Array[UnitBase] = []
var _samples: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--count="):
			_count = int(argument.trim_prefix("--count="))
		elif argument.begins_with("--type="):
			_type = int(argument.trim_prefix("--type="))
		elif argument.begins_with("--duration="):
			_duration = float(argument.trim_prefix("--duration="))
		elif argument.begins_with("--seed="):
			_seed = int(argument.trim_prefix("--seed="))
		elif argument.begins_with("--approach="):
			_approach = argument.trim_prefix("--approach=")
		elif argument.begins_with("--capture-dir="):
			_capture_directory = argument.trim_prefix("--capture-dir=")
		elif argument == "--audit-refuges":
			_audit_refuges = true
	call_deferred("_run")


func _run() -> void:
	GameManager.selected_map_seed = _seed
	GameManager.selected_population_limit = 40
	GameManager.guided_opening_enabled = false
	AudioManager.set_all_enabled(false)
	_main = preload("res://scenes/main/main.tscn").instantiate() as Node2D
	add_child(_main)
	for _frame: int in range(900):
		if GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	if GameManager.current_state != GameManager.GameState.PLAYING:
		push_error("TC raid failed to load a real match")
		get_tree().quit(1)
		return
	_main.get_node("AIController").process_mode = Node.PROCESS_MODE_DISABLED
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.process_mode = Node.PROCESS_MODE_DISABLED
	var town_center: BuildingBase = null
	for building: Node in get_tree().get_nodes_in_group("player_0_buildings"):
		if building is BuildingBase and building.building_type == BuildingData.BuildingType.TOWN_CENTER:
			town_center = building as BuildingBase
			break
	if town_center == null:
		push_error("TC raid fixture had no Town Center")
		get_tree().quit(1)
		return
	if town_center.has_signal("defensive_attack_fired"):
		town_center.connect("defensive_attack_fired", func(_target: Node2D) -> void: _shots += 1)
	var game_map: Node2D = _main.get_node("GameMap") as Node2D
	var spawn: Vector2i = game_map.world_to_tile(town_center.global_position)
	if _audit_refuges:
		_audit_refuge_endpoints(game_map, town_center, spawn)
	if not _capture_directory.is_empty():
		DisplayServer.window_set_size(Vector2i(844, 390))
		game_map.camera.global_position = town_center.global_position
		game_map.selection_mgr.select_single(town_center)
		await _capture("selected-town-center-range")
	var scene_paths: Dictionary = {
		UnitData.UnitType.INFANTRY: "res://scenes/units/infantry.tscn",
		UnitData.UnitType.ARCHER: "res://scenes/units/archer.tscn",
		UnitData.UnitType.CAVALRY: "res://scenes/units/cavalry.tscn",
	}
	var attacker_scene: PackedScene = load(scene_paths[_type]) as PackedScene
	for index: int in range(_count):
		var unit: UnitBase = attacker_scene.instantiate() as UnitBase
		unit.player_owner = 1
		var approach_offsets: Dictionary = {
			"north": Vector2i(-3, -2), "east": Vector2i(6, -2),
			"south": Vector2i(5, 5), "west": Vector2i(-2, 6),
		}
		var offset: Vector2i = approach_offsets.get(_approach, Vector2i(-3, -2))
		var tile: Vector2i = spawn + offset + Vector2i(-index % 3, -index / 3)
		if not game_map.is_tile_walkable(tile):
			var nearby: Array[Vector2i] = game_map.pathfinding.get_walkable_tiles_near(tile, 4, 1)
			if not nearby.is_empty():
				tile = nearby[0]
		unit.global_position = game_map.tile_to_world(tile)
		game_map.get_node("UnitsContainer").add_child(unit)
		_attackers.append(unit)
		unit.command_attack_building(town_center)
	var start_time: float = GameManager.game_time
	var last_sample: float = -10.0
	var captured_arrow: bool = false
	for _frame: int in range(ceili((_duration + 5.0) * 60.0)):
		var elapsed: float = GameManager.game_time - start_time
		if elapsed - last_sample >= 10.0:
			_samples.append(_sample(town_center, elapsed))
			last_sample = elapsed
		if not captured_arrow and not _capture_directory.is_empty():
			for node: Node in get_tree().get_nodes_in_group("defensive_projectiles"):
				if float(node.get("elapsed")) > 0.08 and not bool(node.get("finished")):
					captured_arrow = true
					await _capture("town-center-arrow-in-flight")
					break
		if elapsed >= _duration or not is_instance_valid(town_center) or town_center.state == BuildingBase.State.DESTROYED or _living_attackers() == 0:
			break
		await get_tree().process_frame
	_samples.append(_sample(town_center, GameManager.game_time - start_time))
	var summary: Dictionary = {
		"fixture": "Synthetic army, real seeded map/navigation/combat/TC; starting workers and strategic AI frozen",
		"seed": _seed, "type": UnitData.get_unit_name(_type), "count": _count, "approach": _approach,
		"attack_damage": town_center.tower_attack_damage if is_instance_valid(town_center) else -1,
		"attack_range_world": town_center.tower_attack_range if is_instance_valid(town_center) else -1,
		"samples": _samples, "refuge_audit": _refuge_audit,
	}
	var output_path: String = OS.get_environment("AOEM_TC_RAID_OUTPUT")
	if not output_path.is_empty():
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(summary, "\t"))
	print("[TC_RAID] %s" % JSON.stringify(summary))
	get_tree().paused = false
	_main.free()
	get_tree().quit(0)


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(_capture_directory)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_capture_directory.path_join(label + ".png"))


func _audit_refuge_endpoints(game_map: Node2D, town_center: BuildingBase, spawn: Vector2i) -> void:
	var samples: Array[Dictionary] = []
	var rejected: Array[Dictionary] = []
	var uncovered: int = 0
	for y: int in range(-6, 10):
		for x: int in range(-6, 10):
			if abs(x) < 5 and abs(y) < 5:
				continue
			var tile: Vector2i = spawn + Vector2i(x, y)
			if not game_map.is_tile_walkable(tile):
				continue
			var worker := preload("res://scenes/units/villager.tscn").instantiate() as Villager
			worker.player_owner = 0
			worker.global_position = game_map.tile_to_world(tile)
			game_map.get_node("UnitsContainer").add_child(worker)
			worker.set_process(false)
			worker.take_damage(1.0)
			if worker.get("_recovery_refuge") == town_center:
				var radius: float = town_center.global_position.distance_to(worker.move_target)
				var protected: bool = radius <= town_center.tower_attack_range
				if not protected:
					uncovered += 1
				samples.append({"origin_offset": [x, y], "refuge_distance": snappedf(radius, 0.01), "protected": protected})
			else:
				rejected.append({"origin_offset": [x, y], "status": worker.get_work_status(), "waiting": worker.get("_recovery_waiting")})
			worker.free()
	_refuge_audit = {"seed": _seed, "uncovered": uncovered, "samples": samples, "no_tc_refuge": rejected}
	print("[TC_REFUGE_AUDIT] %s" % JSON.stringify(_refuge_audit))


func _living_attackers() -> int:
	var count: int = 0
	for unit: UnitBase in _attackers:
		if is_instance_valid(unit) and unit.current_state != UnitBase.State.DEAD:
			count += 1
	return count


func _sample(town_center: BuildingBase, elapsed: float) -> Dictionary:
	var total_attacker_hp: float = 0.0
	for unit: UnitBase in _attackers:
		if is_instance_valid(unit):
			total_attacker_hp += unit.hp
	return {"elapsed": snappedf(elapsed, 0.01), "tc_hp": town_center.hp if is_instance_valid(town_center) else 0,
		"army_alive": _living_attackers(), "army_hp": snappedf(total_attacker_hp, 0.01), "shots": _shots}
