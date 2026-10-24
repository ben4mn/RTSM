extends Node
## Real Main/Map regression for the owned-building lane rule. A bounded synthetic
## grass/vision patch isolates geometry; economy and final placement are real.

const ANCHOR := Vector2i(28, 28)
const HOUSE := BuildingData.BuildingType.HOUSE
const CLEARANCE_REASON := "Leave 1 tile between buildings for a path"
var _main: Node2D
var _map: Node2D
var _placement: BuildingPlacement
var _workers: Array[Villager] = []
var _previous: Dictionary = {}
var _preferences_before: PackedByteArray
var _had_preferences: bool
var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for property: String in ["selected_map_seed", "selected_map_archetype", "selected_population_limit", "selected_difficulty", "selected_match_mode", "guided_opening_enabled", "audio_enabled"]:
		_previous[property] = GameManager.get(property)
	_had_preferences = FileAccess.file_exists(GameManager.PREFERENCES_PATH)
	if _had_preferences:
		_preferences_before = FileAccess.get_file_as_bytes(GameManager.PREFERENCES_PATH)
	AudioManager.set_all_enabled(false)
	GameManager.audio_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	GameManager.selected_population_limit = 30
	GameManager.selected_difficulty = AIController.Difficulty.EASY
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	GameManager.guided_opening_enabled = false
	GameManager.set_state(GameManager.GameState.MENU)
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for frame: int in 900:
		if _main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	_expect(_main.get("_building_placement") != null, "actual Main initializes")
	if _main.get("_building_placement") == null:
		_finish()
		return
	_main.set_process(false)
	_main.get_node("AIController").process_mode = Node.PROCESS_MODE_DISABLED
	(_main.get_node("AIController").get("_decision_timer") as Timer).stop()
	_main.get_node("StrategyController").set_process(false)
	_map = _main.get_node("GameMap")
	_map.set_process(false)
	_placement = _main.get("_building_placement")
	await _measure_generated_find_space()
	for side: Array in _main.get("_player_units"):
		for unit: UnitBase in side:
			unit.command_stop()
			unit.set_process(false)
			unit.set_physics_process(false)
			if unit is Villager and unit.player_owner == 0:
				_workers.append(unit as Villager)
	for side: Array in _main.get("_player_buildings"):
		for building: BuildingBase in side:
			building.set_process(false)
	_expect(_workers.size() >= 2, "real opening supplies workers with orders to preserve")
	if _workers.size() < 2:
		_finish()
		return
	# Harvest cargo through real work before any synthetic terrain is prepared.
	var worker: Villager = _workers[0]
	var wood: Node2D = _map.get_nearest_reachable_resource_node("wood", worker.global_position, 0, {}, worker)
	_expect(wood != null and worker.command_gather(wood), "real worker accepts visible natural wood")
	for step: int in 3600:
		_main.call("_update_fog_of_war")
		worker._process(1.0 / 30.0)
		if worker.carried_amount > 0:
			break
	_expect(worker.carried_amount > 0 and worker.get_carried_resources().has("wood"), "old cargo was actually harvested")
	_workers[1].command_move(_map.tile_to_world(_map.map_generator.spawn_positions[0] + Vector2i(5, -2)))
	_map.selection_mgr.select_single(worker)
	(_map.fog_of_war as FogManager).set_process(false)
	_prepare_patch()
	var existing: BuildingBase = _main.call("_spawn_building", HOUSE, 0, ANCHOR)
	existing.set_process(false)
	existing.complete_instantly()
	_expect(existing.state == BuildingBase.State.ACTIVE, "real existing House starts active")
	_expect(BuildingData.BUILDING_CLEARANCE_TILES == 1, "placement and AI share a one-tile lane policy")
	_main.call("_on_building_selected_for_placement", HOUSE)
	_check_touching_edges_and_corners()
	_check_legal_lanes()
	var touching: Vector2i = ANCHOR + Vector2i(2, 0)
	existing.start_construction()
	_expect(not _preview(touching), "an unfinished foundation reserves the same path space")
	_expect(_placement.get_invalid_reason() == CLEARANCE_REASON, "foundation conflict explains the missing path")
	existing.state = BuildingBase.State.ACTIVE

	# Other owners do not get a protected human lane, but their actual footprint
	# remains solid. Destroyed buildings likewise stop reserving adjacent ground.
	existing.player_owner = 1
	_expect(_preview(touching), "a foreign building does not reserve adjacent path space")
	_expect(not _preview(ANCHOR), "foreign occupied ground still cannot be purchased")
	existing.player_owner = 0
	existing.state = BuildingBase.State.DESTROYED
	_expect(_preview(touching), "a destroyed building does not reserve adjacent path space")
	existing.state = BuildingBase.State.ACTIVE
	_check_hidden_footprint(touching)

	# The first rejection exercises the user-facing Place action. The second
	# exercises Main's final transaction guard after a previously valid preview.
	var accounts: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	var orders: Array[Dictionary] = _snapshot_orders()
	var count_before: int = (_main.get("_player_buildings")[0] as Array).size()
	_expect(not _preview(touching), "touching preview is red before Place")
	_expect(not _placement.confirm_preview() and _placement.active, "Place rejects red preview while allowing correction")
	_expect(str(_main.get("_last_placement_feedback")).contains(CLEARANCE_REASON), "actual Main feedback explains clearance rejection")
	_expect(_snapshot_orders() == orders and ResourceManager.get_all_resources(0) == accounts, "rejected preview keeps every worker order and real cargo without charging")
	# Make the old building temporarily foreign, then restore ownership between
	# green preview and the authoritative purchase callback (no delayed timer).
	existing.player_owner = 1
	_expect(_preview(touching), "race starts with an actually legal green preview")
	existing.player_owner = 0
	_main.call("_on_placement_confirmed", HOUSE, _map.tile_to_world(touching))
	_expect(ResourceManager.get_all_resources(0) == accounts, "final clearance revalidation spends no resources")
	_expect((_main.get("_player_buildings")[0] as Array).size() == count_before, "final clearance revalidation creates no foundation")
	_expect(_snapshot_orders() == orders, "final clearance rejection preserves gathering, movement, idle orders and exact cargo")
	_expect(str(_main.get("_last_placement_feedback")).contains(CLEARANCE_REASON), "final rejection reports the actual lane conflict")

	# A full open row is accepted by the real paid transaction, proving that the
	# exclusion ring does not accidentally require two or more spare rows.
	var legal: Vector2i = ANCHOR + Vector2i(3, 0)
	var cost: int = int(BuildingData.get_building_cost(HOUSE).wood)
	_main.call("_on_placement_confirmed", HOUSE, _map.tile_to_world(legal))
	_expect(ResourceManager.get_resource(0, "wood") == int(accounts.wood) - cost, "exactly one open tile permits one normal paid House")
	_expect((_main.get("_player_buildings")[0] as Array).size() == count_before + 1, "legal lane creates exactly one actual foundation")
	var placed: BuildingBase = (_main.get("_player_buildings")[0] as Array).back()
	_expect(placed.state == BuildingBase.State.CONSTRUCTING and _map.world_to_tile(placed.global_position) == legal, "accepted foundation occupies exactly the preview origin")
	for dy: int in 2:
		_expect(_map.is_tile_walkable(ANCHOR + Vector2i(2, dy)), "full separating lane remains walkable after purchase")
	# Exercise movement through the exact legal corridor between the two actual
	# footprints, with the same worker navigation used in play. Teleport only the
	# test actor to the approach; the crossing itself is an ordinary move order.
	var crossing_worker: Villager = _workers[1]
	crossing_worker.command_stop()
	crossing_worker.global_position = _map.tile_to_world(ANCHOR + Vector2i(2, -2))
	var destination: Vector2 = _map.tile_to_world(ANCHOR + Vector2i(2, 3))
	crossing_worker.command_move(destination)
	var crossed_lane := false
	for step: int in 900:
		crossing_worker._process(1.0 / 30.0)
		var tile: Vector2i = _map.world_to_tile(crossing_worker.global_position)
		crossed_lane = crossed_lane or tile in [ANCHOR + Vector2i(2, 0), ANCHOR + Vector2i(2, 1)]
		if crossing_worker.global_position.distance_to(destination) <= UnitBase.NAVIGATION_POINT_TOLERANCE:
			break
	_expect(crossed_lane and crossing_worker.global_position.distance_to(destination) <= UnitBase.NAVIGATION_POINT_TOLERANCE, "real worker crosses the legal one-tile corridor between existing House and new foundation")
	_main.call("_on_building_selected_for_placement", HOUSE)
	var far_corner: Vector2i = ANCHOR - Vector2i(2, 2)
	_expect(not _preview(far_corner), "living House still blocks its opposite corner")
	existing.take_damage(existing.hp)
	_expect(existing.state == BuildingBase.State.DESTROYED and _preview(far_corner), "real destruction releases clearance before the fading building is freed")
	_expect(_map.is_tile_buildable(ANCHOR), "real destruction releases the original occupied footprint")
	await _check_find_space_transaction()
	_finish()


func _measure_generated_find_space() -> void:
	# One desktop/headless timing sample on real generated opening terrain and
	# normal starting actors. Preview is requested synthetically, not purchased.
	get_window().size = Vector2i(932, 430)
	get_window().content_scale_size = Vector2i(932, 430)
	await get_tree().process_frame
	await get_tree().process_frame
	_main.call("_on_building_selected_for_placement", BuildingData.BuildingType.ARCHERY_RANGE)
	var hud: Node = _main.get_node("HUD")
	var before: Dictionary = ResourceManager.get_all_resources(0).duplicate(true)
	var camera_before: Vector2 = _map.camera.position
	var started: int = Time.get_ticks_usec()
	(hud.get("_placement_find_space_button") as Button).pressed.emit()
	var elapsed_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	print("[MEASURE] find_space actualMain generatedPlains101 Range preview 932x430 found=%s elapsed_ms=%.3f (desktop/headless fixture, not phone FPS)" % [_placement.has_assisted_preview(), elapsed_ms])
	_expect(ResourceManager.get_all_resources(0) == before and _map.camera.position == camera_before, "generated opening search does not spend or move camera")
	_main.call("_cancel_placement")


func _check_find_space_transaction() -> void:
	# Synthetic visible grass is already prepared above; final payment, fog,
	# foundation registration and ordinary HUD signals remain the actual code.
	_map.camera.position = _map.tile_to_world(ANCHOR)
	await get_tree().process_frame
	await get_tree().process_frame
	_main.call("_on_building_selected_for_placement", HOUSE)
	var hud: Node = _main.get_node("HUD")
	var camera_before: Vector2 = _map.camera.position
	var accounts: Dictionary = ResourceManager.get_all_resources(0).duplicate(true)
	var orders: Array = _snapshot_orders()
	var count_before: int = (_main.get("_player_buildings")[0] as Array).size()
	(hud.get("_placement_find_space_button") as Button).pressed.emit()
	_expect(_placement.has_assisted_preview() and _placement.is_valid_placement, "actual Find space signal produces a legal green preview")
	_expect(_map.camera.position == camera_before, "actual assistance never moves the camera")
	_expect(ResourceManager.get_all_resources(0) == accounts and (_main.get("_player_buildings")[0] as Array).size() == count_before and _snapshot_orders() == orders, "assistance preserves real resources, workers and foundation count")
	if not _placement.is_valid_placement:
		return
	var tile: Vector2i = _map.world_to_tile(_placement.ghost_position)
	var bounds: Rect2 = _placement.call("_find_space_preview_screen_rect", tile)
	_expect((hud.call("get_placement_search_safe_rect") as Rect2).encloses(bounds), "actual suggested footprint/art fits current safe field")
	for obstacle: Rect2 in hud.call("get_world_occlusion_rects"):
		_expect(not bounds.intersects(obstacle, true), "actual suggestion avoids every rendered HUD obstruction")
	var fog_before: int = _map.fog_of_war.fog_grid[tile.y][tile.x]
	_map.fog_of_war.fog_grid[tile.y][tile.x] = MapData.FogState.EXPLORED
	(hud.get("_placement_confirm_button") as Button).pressed.emit()
	_expect(ResourceManager.get_all_resources(0) == accounts and (_main.get("_player_buildings")[0] as Array).size() == count_before, "assisted Place rechecks lost vision without purchase")
	_map.fog_of_war.fog_grid[tile.y][tile.x] = fog_before
	(hud.get("_placement_find_space_button") as Button).pressed.emit()
	_expect(_placement.is_valid_placement, "assistance recovers after vision returns")
	var accepted_position: Vector2 = _placement.ghost_position
	(hud.get("_placement_confirm_button") as Button).pressed.emit()
	_expect(ResourceManager.get_resource(0, "wood") == int(accounts.wood) - int(BuildingData.get_building_cost(HOUSE).wood), "explicit assisted Place charges exactly the normal House price")
	_expect((_main.get("_player_buildings")[0] as Array).size() == count_before + 1, "explicit assisted Place creates one real foundation")
	var placed: BuildingBase = (_main.get("_player_buildings")[0] as Array).back()
	_expect(placed.global_position == accepted_position and placed.state == BuildingBase.State.CONSTRUCTING, "paid foundation uses the suggested position and normal construction state")
	_expect(not _placement.active and not _placement.has_assisted_preview(), "paid completion clears assisted placement")


func _prepare_patch() -> void:
	# The patch is explicit test setup, never presented as ordinary map evidence.
	# All production conversion, terrain validation, occupancy and fog APIs remain
	# real. Removing these test resources avoids unrelated random terrain failures.
	for x: int in range(ANCHOR.x - 5, ANCHOR.x + 8):
		for y: int in range(ANCHOR.y - 5, ANCHOR.y + 8):
			var tile := Vector2i(x, y)
			var resource: Node2D = _map.resource_nodes.get(tile, null)
			if is_instance_valid(resource):
				_map.resource_nodes.erase(tile)
				resource.free()
			_map.map_generator.grid[y][x] = MapData.TileType.GRASS
			_map.pathfinding.update_tile(tile, MapData.TileType.GRASS)
			_map.fog_of_war.fog_grid[y][x] = MapData.FogState.VISIBLE


func _check_touching_edges_and_corners() -> void:
	for offset: Vector2i in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		var candidate: Vector2i = ANCHOR + offset
		_expect(not _preview(candidate), "edge-touching House is invalid at " + str(offset))
		var expected: Array[Vector2i] = []
		for dx: int in 2:
			for dy: int in 2:
				var tile: Vector2i = candidate + Vector2i(dx, dy)
				if tile.x >= ANCHOR.x - 1 and tile.x <= ANCHOR.x + 2 and tile.y >= ANCHOR.y - 1 and tile.y <= ANCHOR.y + 2:
					expected.append(tile)
		_expect(expected.size() == 2 and _same_cells(_placement.get("_invalid_tiles"), expected), "only the two cells adjacent to the existing edge are red")
		_expect(_placement.get_invalid_reason() == CLEARANCE_REASON, "edge conflict gives actionable path reason")
		_expect(str((_main.get_node("HUD").get("_placement_status_label") as Label).text).contains(CLEARANCE_REASON), "actual placement HUD shows the path reason")
	for offset: Vector2i in [Vector2i(2, 2), Vector2i(-2, 2), Vector2i(2, -2), Vector2i(-2, -2)]:
		var candidate: Vector2i = ANCHOR + offset
		_expect(not _preview(candidate), "corner-touching House is invalid at " + str(offset))
		var conflict: Vector2i = ANCHOR + Vector2i(2 if offset.x > 0 else -1, 2 if offset.y > 0 else -1)
		_expect(_same_cells(_placement.get("_invalid_tiles"), [conflict]), "only the shared corner clearance square is red")


func _check_legal_lanes() -> void:
	for offset: Vector2i in [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3), Vector2i(3, 3)]:
		_expect(_preview(ANCHOR + offset), "exactly one clear tile is legal at " + str(offset))
		_expect((_placement.get("_invalid_tiles") as Array).is_empty(), "legal lane has no red cells")


func _check_hidden_footprint(origin: Vector2i) -> void:
	var hidden: Vector2i = origin + Vector2i(1, 1)
	_map.fog_of_war.fog_grid[hidden.y][hidden.x] = MapData.FogState.EXPLORED
	_expect(not _preview(origin), "one stale-vision square invalidates the whole footprint")
	var hidden_cells: Array = (_placement.get("_invalid_tiles") as Array).duplicate()
	_expect(_placement.get_invalid_reason() == BuildingPlacement.FOG_INVALID_REASON and hidden_cells.size() == 4, "hidden footprint hides the specific clearance cell and reason")
	_map.map_generator.grid[hidden.y][hidden.x] = MapData.TileType.WATER
	_map.pathfinding.update_tile(hidden, MapData.TileType.WATER)
	_expect(not _preview(origin), "hidden terrain change remains invalid")
	_expect(_placement.get_invalid_reason() == BuildingPlacement.FOG_INVALID_REASON and _same_cells(_placement.get("_invalid_tiles"), hidden_cells), "hidden blocker changes neither feedback nor per-cell disclosure")
	_map.map_generator.grid[hidden.y][hidden.x] = MapData.TileType.GRASS
	_map.pathfinding.update_tile(hidden, MapData.TileType.GRASS)
	_map.fog_of_war.fog_grid[hidden.y][hidden.x] = MapData.FogState.VISIBLE


func _preview(tile: Vector2i) -> bool:
	_placement.update_preview_at_world(_map.tile_to_world(tile))
	return _placement.is_valid_placement


func _same_cells(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for cell: Vector2i in expected:
		if cell not in actual:
			return false
	return true


func _snapshot_orders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for worker: Villager in _workers:
		result.append({"state":worker.current_state, "gather":worker.gather_target, "build":worker.build_target, "move":worker.move_target, "cargo":worker.get_carried_resources().duplicate(), "position":worker.global_position})
	return result


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if is_instance_valid(_main):
		_main.free()
	for property: String in _previous:
		GameManager.set(property, _previous[property])
	AudioManager.set_all_enabled(bool(_previous.get("audio_enabled", false)))
	GameManager.set_state(GameManager.GameState.MENU)
	var preferences_unchanged: bool = FileAccess.file_exists(GameManager.PREFERENCES_PATH) == _had_preferences
	if _had_preferences:
		preferences_unchanged = preferences_unchanged and FileAccess.get_file_as_bytes(GameManager.PREFERENCES_PATH) == _preferences_before
	_expect(preferences_unchanged, "test does not write saved preferences")
	for failure: String in _failures:
		push_error("[FAIL] building_placement_clearance: " + failure)
	if _failures.is_empty():
		print("[PASS] building_placement_clearance: %d checks; real Main/Map preview cells, edge/corner/foundation spacing, exact one-tile legal lane, owner/destruction/fog, no-charge/no-order-change rejection and paid legal placement" % _checks)
	get_tree().quit(0 if _failures.is_empty() else 1)
