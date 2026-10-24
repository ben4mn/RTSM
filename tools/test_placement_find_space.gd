extends Node
## Bounded, fog-safe preview search. Synthetic map policy; no pacing claims.

var _failures: Array[String] = []
var _checks: int = 0
var _confirmations: int = 0

class SearchMap extends Node2D:
	var visibility: int = 0 # 0visible, 1hidden, 2checkerboard
	var buildable: Dictionary = {}
	var allow_all: bool = false
	var terrain_queries: Array[Vector2i] = []
	func world_to_tile(pos: Vector2) -> Vector2i:
		return Vector2i(roundi((pos.x / 32.0 + pos.y / 16.0) * 0.5), roundi((pos.y / 16.0 - pos.x / 32.0) * 0.5))
	func tile_to_world(tile: Vector2i) -> Vector2:
		return Vector2((tile.x - tile.y) * 32.0, (tile.x + tile.y) * 16.0)
	func is_tile_visible_to_player(tile: Vector2i, _owner: int = 0) -> bool:
		return visibility == 0 or (visibility == 2 and (tile.x + tile.y) % 2 == 0)
	func is_tile_buildable(tile: Vector2i) -> bool:
		terrain_queries.append(tile)
		return allow_all or buildable.has(tile)
	func allow_house(origin: Vector2i) -> void:
		for x: int in 2:
			for y: int in 2:
				buildable[origin + Vector2i(x, y)] = true

class SearchProbe extends BuildingPlacement:
	var visited: Array[Vector2i] = []
	func _check_footprint_validity(tile: Vector2i, footprint: Vector2i, owner: int) -> bool:
		visited.append(tile)
		return super._check_footprint_validity(tile, footprint, owner)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(1)
	ResourceManager.reset()
	ResourceManager.initialize_player(0, {"food": 200, "wood": 200, "gold": 100})
	var world := SearchMap.new()
	add_child(world)
	var camera := Camera2D.new()
	camera.position = world.tile_to_world(Vector2i(20, 20))
	world.add_child(camera)
	var placement := SearchProbe.new()
	world.add_child(placement)
	placement.placement_confirmed.connect(func(_type: int, _position: Vector2) -> void: _confirmations += 1)
	await get_tree().process_frame
	placement.start_placement(BuildingData.BuildingType.HOUSE)
	placement.set_process(false)
	placement.update_preview_at_world(world.tile_to_world(Vector2i(20, 20)))
	var safe: Rect2 = get_viewport().get_visible_rect().grow(-8.0)
	var camera_before: Vector2 = camera.position
	var bank_before: Dictionary = ResourceManager.get_all_resources(0).duplicate(true)
	world.allow_house(Vector2i(17, 20))
	world.allow_house(Vector2i(20, 17))
	_expect(placement.find_visible_space(safe, []), "finds visible legal candidate")
	_expect(world.world_to_tile(placement.ghost_position) == Vector2i(17, 20), "nearest equal-distance tie is stable by tile coordinates")
	_expect(placement.is_valid_placement and placement.has_assisted_preview(), "success is a green assisted preview")
	_expect(camera.position == camera_before and ResourceManager.get_all_resources(0) == bank_before and _confirmations == 0, "search neither moves camera nor spends/confirms")
	var selected: Vector2 = placement.ghost_position
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(50.0, 50.0)
	motion.relative = Vector2(5.0, 0.0)
	placement.call("_unhandled_input", motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = motion.position
	release.pressed = false
	placement.call("_unhandled_input", release)
	_expect(placement.ghost_position == selected and placement.is_valid_placement and _confirmations == 0, "mouse motion/release cannot overwrite or buy assisted preview")
	var obstacle: Rect2 = placement.call("_find_space_preview_screen_rect", Vector2i(17, 20))
	placement.update_preview_at_world(world.tile_to_world(Vector2i(20, 20)))
	_expect(placement.find_visible_space(safe, [obstacle]), "search avoids current HUD obstacle")
	_expect(world.world_to_tile(placement.ghost_position) == Vector2i(20, 17), "occluded equal-distance candidate is skipped")
	var found_bounds: Rect2 = placement.call("_find_space_preview_screen_rect", Vector2i(20, 17))
	_expect(safe.encloses(found_bounds) and not found_bounds.intersects(obstacle, true), "full footprint/art has safe clearance")
	for visibility: int in [1, 2]:
		world.visibility = visibility
		world.terrain_queries.clear()
		placement.visited.clear()
		var old_position: Vector2 = placement.ghost_position
		var old_reason: String = placement.get_invalid_reason()
		var old_tiles: Array = placement.get("_invalid_tiles").duplicate()
		_expect(not placement.find_visible_space(safe, []), "hidden/partly hidden candidates cannot be selected")
		_expect(world.terrain_queries.is_empty(), "whole-footprint vision precedes every terrain query")
		_expect(placement.ghost_position == old_position and placement.get_invalid_reason() == old_reason and placement.get("_invalid_tiles") == old_tiles, "failed search preserves original preview and explanation")
		_expect(placement.visited.size() <= BuildingPlacement.FIND_SPACE_MAX_CANDIDATES, "search respects candidate budget")
	world.visibility = 0
	placement.visited.clear()
	world.terrain_queries.clear()
	_expect(not placement.find_visible_space(safe, [safe]), "fully covered viewport has no candidate")
	_expect(placement.visited.is_empty() and world.terrain_queries.is_empty(), "HUD bounds are rejected before world validation")
	_expect(not placement.find_visible_space(Rect2(), []), "empty safe area is rejected")
	_expect(not placement.find_visible_space(Rect2(Vector2(NAN, 0), Vector2.ONE), []), "nonfinite safe area is rejected")
	world.buildable.clear()
	camera.zoom = Vector2(0.1, 0.1)
	await get_tree().process_frame
	placement.update_preview_at_world(world.tile_to_world(Vector2i(20, 20)))
	placement.visited.clear()
	world.terrain_queries.clear()
	var worst_started: int = Time.get_ticks_usec()
	var worst_found: bool = placement.find_visible_space(safe, [])
	var worst_ms: float = float(Time.get_ticks_usec() - worst_started) / 1000.0
	print("[MEASURE] find_space synthetic625 exhausted elapsed_ms=%.3f" % worst_ms)
	_expect(not worst_found, "blocked wide view reports no nearby result")
	_expect(placement.visited.size() == 625, "wide view stops at exactly625 candidates")
	var unique: Dictionary = {}
	for tile: Vector2i in placement.visited:
		unique[tile] = true
	_expect(unique.size() == 625, "search never repeats candidates")
	_expect(world.terrain_queries.size() == 2500, "bounded full visible House checks account for every query")
	world.allow_all = true
	_expect(placement.find_visible_space(safe, []), "a later valid search recovers")
	world.visibility = 1
	_expect(not placement.confirm_preview() and _confirmations == 0, "normal confirmation rechecks fog after search")
	world.visibility = 0
	_expect(placement.find_visible_space(safe, []) and placement.confirm_preview(), "normal Place can commit later valid preview")
	_expect(_confirmations == 1 and not placement.has_assisted_preview(), "successful confirmation clears assist exactly once")
	placement.start_placement(BuildingData.BuildingType.HOUSE)
	_expect(not placement.has_assisted_preview(), "new placement does not inherit assist")
	_expect(placement.find_visible_space(safe, []), "new placement can request assistance")
	var touch := InputEventScreenTouch.new()
	touch.position = placement.get_canvas_transform() * world.tile_to_world(Vector2i(21, 20))
	touch.pressed = true
	placement.call("_unhandled_input", touch)
	touch.pressed = false
	placement.call("_unhandled_input", touch)
	_expect(not placement.has_assisted_preview() and _confirmations == 1, "explicit touch repositions without purchasing")
	placement.find_visible_space(safe, [])
	placement.cancel_placement()
	_expect(not placement.has_assisted_preview() and not placement.find_visible_space(safe, []), "cancel clears assist and disables search")
	world.free()
	if _failures.is_empty():
		print("[PASS] placement_find_space: %d checks; bounded fog-safe previews, occlusion, stable ties, persistence and normal confirmation" % _checks)
	else:
		for failure: String in _failures:
			push_error("[FAIL] placement_find_space: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
