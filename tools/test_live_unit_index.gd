extends Node
var _map: Node2D
var _checks: int = 0
var _failures: Array[String] = []
var _units: Array[UnitBase] = []

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	_map = load("res://scenes/map/game_map.tscn").instantiate()
	_map.set("map_seed", 101)
	add_child(_map)
	await get_tree().process_frame
	_map.process_mode = Node.PROCESS_MODE_DISABLED
	var rng := RandomNumberGenerator.new()
	rng.seed = 194701
	for index: int in 80:
		var unit: UnitBase = load("res://scenes/units/infantry.tscn").instantiate()
		unit.player_owner = index % 2
		unit.position = Vector2(rng.randf_range(-700, 700), rng.randf_range(-300, 600))
		_map.get_node("UnitsContainer").add_child(unit)
		_units.append(unit)
		_check_near(unit.global_position, 64.0, "immediate spawn")
	for index: int in 80:
		var unit: UnitBase = _units[index]
		unit.global_position = Vector2(rng.randf_range(-700, 700), rng.randf_range(-300, 600))
		_check_near(unit.global_position, 80.0, "same-frame teleport")
		_check_near(Vector2(-64, -64), 64.0, "negative cell/range edge")
		unit.vision_radius = MapData.range_tiles_to_world(float(index % 9))
		_check_vision(_map.world_to_tile(unit.global_position) + Vector2i(index % 9, 0), 1)
		_check_vision(_map.world_to_tile(unit.global_position) + Vector2i(index % 9 + 1, 0), 1)
		unit.player_owner = 1 - unit.player_owner
		_check_vision(_map.world_to_tile(unit.global_position), 1)
		unit.current_state = UnitBase.State.DEAD
		_check_near(unit.global_position, 80.0, "same-frame death")
		_check_vision(_map.world_to_tile(unit.global_position), 1)
		unit.current_state = UnitBase.State.IDLE
	var edge: UnitBase = _units[0]
	edge.global_position = Vector2(-64, 0)
	_check_near(Vector2.ZERO, 64.0, "exact circle edge")
	edge.global_position.x -= 0.01
	_check_near(Vector2.ZERO, 64.0, "outside circle edge")
	_map.get_node("UnitsContainer").move_child(_units[60], 0)
	_check_near(Vector2.ZERO, 2000.0, "scene reorder retains original group order")
	var subtree := Node2D.new()
	_map.add_child(subtree)
	_units[10].reparent(subtree)
	_units[11].reparent(subtree)
	_check_near(Vector2.ZERO, 2000.0, "prime ranks with separate ancestor")
	_map.move_child(subtree, 0)
	_check_near(Vector2.ZERO, 2000.0, "same-frame ancestor reorder refreshes ranks")
	_units[10].reparent(_map.get_node("UnitsContainer"))
	_units[11].reparent(_map.get_node("UnitsContainer"))
	subtree.free()
	var parent := Node2D.new()
	_map.add_child(parent)
	edge.reparent(parent)
	edge.global_position = Vector2.ZERO
	_check_near(Vector2.ZERO, 1.0, "reparent registration")
	parent.position = Vector2(400, 0)
	_check_near(Vector2(400, 0), 1.0, "same-frame parent transform")
	parent.free()
	_units.remove_at(0)
	_check_near(Vector2(400, 0), 100.0, "parent subtree removal")
	for unit: UnitBase in _units: unit.free()
	_check_near(Vector2.ZERO, 2000.0, "all units freed")
	_check_scout_vision()
	_check_cached_parent_vision()
	_map.free()
	for failure: String in _failures: push_error("[FAIL] live_unit_index: " + failure)
	print("[LIVE UNIT INDEX] checks=%d failures=%s" % [_checks, str(_failures)])
	get_tree().quit(0 if _failures.is_empty() else 1)

func _check_near(origin: Vector2, radius: float, label: String) -> void:
	var expected: Array[UnitBase] = []
	for unit: Node in get_tree().get_nodes_in_group("units"):
		if unit is UnitBase and _map.is_ancestor_of(unit) and unit.current_state != UnitBase.State.DEAD and unit.global_position.distance_to(origin) <= radius:
			expected.append(unit)
	_expect(_map.get_units_near(origin, radius) == expected, label)

func _check_vision(tile: Vector2i, owner: int) -> void:
	var expected: bool = false
	for unit: UnitBase in _units:
		if not is_instance_valid(unit) or unit.player_owner != owner or unit.current_state == UnitBase.State.DEAD: continue
		var offset: Vector2i = tile - _map.world_to_tile(unit.global_position)
		var radius: int = maxi(0, int(round(MapData.world_to_range_tiles(unit.vision_radius))))
		if offset.x * offset.x + offset.y * offset.y <= radius * radius: expected = true
	var targets: Array[Vector2i] = [tile]
	_expect(_map.call("_are_tiles_visible_from_live_sources", targets, owner) == expected, "fresh vision source/radius/owner/lifetime")

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition: _failures.append(message)


func _check_scout_vision() -> void:
	var center := Vector2i(35, 35)
	for civilization: int in CivilizationData.ORDERED_IDS:
		for owner: int in 2:
			GameManager.players[owner].civilization = civilization
			var scout: UnitBase = load("res://scenes/units/scout.tscn").instantiate()
			scout.player_owner = owner
			scout.position = _map.tile_to_world(center)
			_map.get_node("UnitsContainer").add_child(scout)
			_expect(is_equal_approx(scout.vision_radius, MapData.range_tiles_to_world(10)), "every civilization/owner Scout gets ten-tile vision")
			_expect(scout.damage == 0 and scout.max_hp == 45 and scout.speed == 100, "Scout health/speed/unarmed role remain unchanged")
			if owner == 0:
				_map.fog_of_war.clear_vision_sources()
				_map.fog_of_war.register_vision_source(center, 10, true)
				_map.fog_of_war.refresh_visibility_now()
			for offset: Vector2i in [Vector2i(10, 0), Vector2i(-10, 0), Vector2i(0, 10), Vector2i(0, -10), Vector2i(7, 7), Vector2i(11, 0), Vector2i(8, 8)]:
				var expected: bool = offset.x * offset.x + offset.y * offset.y <= 100
				_expect(_map.is_tile_visible_to_player(center + offset, owner) == expected, "ten-tile exact local/live vision circle")
			scout.free()


func _check_cached_parent_vision() -> void:
	var parent := Node2D.new()
	_map.add_child(parent)
	var scout: UnitBase = load("res://scenes/units/scout.tscn").instantiate()
	scout.player_owner = 1
	parent.add_child(scout)
	var original := Vector2i(30, 30)
	scout.global_position = _map.tile_to_world(original)
	_expect(_map.is_tile_visible_to_player(original, 1), "prime cached source visibility")
	parent.position += Vector2(1600, 0)
	var moved: Vector2i = _map.world_to_tile(scout.global_position)
	_expect(not _map.is_tile_visible_to_player(original, 1), "parent translation retires old cached vision before any near query")
	_expect(_map.is_tile_visible_to_player(moved, 1), "parent translation reveals new tile immediately")
	var second_map: Node2D = load("res://scenes/map/game_map.tscn").instantiate()
	second_map.set("map_seed", 101)
	add_child(second_map)
	second_map.process_mode = Node.PROCESS_MODE_DISABLED
	scout.reparent(second_map.get_node("UnitsContainer"))
	scout.global_position = second_map.tile_to_world(original)
	_expect(not _map.is_tile_visible_to_player(moved, 1), "cross-map reparent retires cached old-map vision")
	_expect(second_map.is_tile_visible_to_player(original, 1), "cross-map reparent registers new-map vision")
	_expect(second_map.get_units_near(scout.global_position, 1.0).has(scout), "cross-map reparent enters new neighborhood")
	second_map.free()
	parent.free()
