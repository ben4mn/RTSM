extends Node
## Visible production facades remain selectable beside workers and soldiers.

var _failures: Array[String] = []
var _move_count: int = 0
var _build_count: int = 0
var _gather_count: int = 0
var _attack_target: Node2D = null


class FakeGameMap extends Node2D:
	func world_to_tile(world_pos: Vector2) -> Vector2i:
		return Vector2i(roundi(world_pos.x), roundi(world_pos.y))


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	var world := FakeGameMap.new()
	add_child(world)
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	world.add_child(camera)
	var selection := SelectionManager.new()
	selection.touch_context_enabled = false
	selection.game_map = world
	world.add_child(selection)
	selection.move_command.connect(func(_tile: Vector2i) -> void: _move_count += 1)
	selection.build_command.connect(func(_building: Node2D) -> void: _build_count += 1)
	selection.attack_command.connect(func(target: Node2D) -> void: _attack_target = target)
	selection.gather_command.connect(func(_resource: Node2D) -> void: _gather_count += 1)
	var worker: UnitBase = _spawn_unit(world, "villager", 0)
	var soldier: UnitBase = _spawn_unit(world, "infantry", 0)
	var enemy: UnitBase = _spawn_unit(world, "infantry", 1)
	var previous: UnitBase = _spawn_unit(world, "infantry", 0)
	previous.position = Vector2(-250.0, 140.0)
	await get_tree().process_frame

	for building_type: String in ["town_center", "barracks"]:
		var building: BuildingBase = load("res://scenes/buildings/%s.tscn" % building_type).instantiate() as BuildingBase
		building.player_owner = 0
		building.state = BuildingBase.State.ACTIVE
		world.add_child(building)
		building.set_process(false)
		var sprite: Sprite2D = building.get_node("BuildingSprite") as Sprite2D
		# These opaque pixels are in the actual front wall/door of each asset.
		var facade_pixel: Vector2 = Vector2(64.0, 106.0) if building_type == "town_center" else Vector2(64.0, 60.0)
		var facade_world: Vector2 = sprite.to_global(sprite.get_rect().position + facade_pixel)
		_expect(sprite.texture.get_image().get_pixelv(Vector2i(facade_pixel)).a > 0.9, "%s fixture taps opaque facade art" % building_type)

		for zoom: float in [0.62, 0.952, 2.2]:
			camera.zoom = Vector2(zoom, zoom)
			camera.reset_smoothing()
			camera.force_update_scroll()
			for neighbor: UnitBase in [worker, soldier, enemy]:
				for unit: UnitBase in [worker, soldier, enemy]:
					unit.position = Vector2(250.0, 140.0)
				# Just inside desktop and touch discovery rings, but outside the
				# neighbor's actual body column. It must not steal the facade.
				neighbor.position = facade_world + Vector2(18.0, 8.0)
				for touch: bool in [true, false]:
					selection.select_single(previous)
					selection.set("_last_tap_time", 0.0)
					_attack_target = null
					var before_moves: int = _move_count
					_push_tap(selection, selection.call("_world_to_screen", facade_world), touch)
					var label: String = "%s zoom %.3f beside %s owner%d via %s" % [building_type, zoom, neighbor.name, neighbor.player_owner, "touch" if touch else "mouse"]
					_expect(selection.selected.size() == 1 and selection.selected[0] == building, "%s facade did not select building" % label)
					_expect(_move_count == before_moves and _attack_target == null, "%s facade issued a unit order" % label)

				# Put the person in front of that wall: a body tap now really
				# overlaps the building facade, and the visible person must win.
				neighbor.position = facade_world + Vector2(6.0, 12.0)
				var body_world: Vector2 = neighbor.position + Vector2(0.0, -10.0)
				for touch: bool in [true, false]:
					selection.select_single(previous)
					selection.set("_last_tap_time", 0.0)
					_attack_target = null
					_push_tap(selection, selection.call("_world_to_screen", body_world), touch)
					if neighbor.player_owner == 0:
						_expect(selection.selected.size() == 1 and selection.selected[0] == neighbor, "%s real body lost priority over facade" % building_type)
					else:
						_expect(_attack_target == neighbor, "%s visible enemy body lost attack priority over facade" % building_type)

			# Armed destinations and worker construction keep their existing
			# order semantics, even though the facade is easier to discover.
			for unit: UnitBase in [worker, soldier, enemy]:
				unit.position = Vector2(250.0, 140.0)
			selection.select_single(worker)
			selection.set_unit_command_armed(true)
			var before_moves: int = _move_count
			_push_tap(selection, selection.call("_world_to_screen", facade_world), true)
			_expect(_move_count == before_moves + 1 and selection.selected[0] == worker, "%s armed destination reselected the facade" % building_type)
			selection.set_unit_command_armed(false)
			# A one-shot destination followed by a quick production-building tap
			# is a fresh action, not a unit-type double tap on the same target.
			_push_tap(selection, selection.call("_world_to_screen", facade_world), true)
			_expect(selection.selected.size() == 1 and selection.selected[0] == building, "%s quick facade tap after an armed destination was discarded" % building_type)
			selection.select_single(worker)
			building.state = BuildingBase.State.CONSTRUCTING
			worker.position = facade_world + Vector2(18.0, 8.0)
			selection.set("_last_tap_time", 0.0)
			var before_builds: int = _build_count
			_push_tap(selection, selection.call("_world_to_screen", facade_world), true)
			_expect(_build_count == before_builds + 1 and selection.selected[0] == worker, "%s facade did not retain worker construction context" % building_type)
			building.state = BuildingBase.State.ACTIVE

		# At overview, an adjacent resource tile is also inside the generous
		# resource discovery radius. The opaque production wall is still the
		# deliberate target when a worker is selected.
		camera.zoom = Vector2(0.62, 0.62)
		camera.force_update_scroll()
		for unit: UnitBase in [worker, soldier, enemy]:
			unit.position = Vector2(250.0, 140.0)
		var adjacent_tree := ResourceNode.new()
		adjacent_tree.position = Vector2(-32.0, -16.0)
		world.add_child(adjacent_tree)
		selection.select_single(worker)
		selection.set("_last_tap_time", 0.0)
		var before_gathers: int = _gather_count
		_expect(selection.call("_get_resource_at", facade_world, true) == adjacent_tree, "adjacent-resource fixture lies in overview discovery radius")
		_push_tap(selection, selection.call("_world_to_screen", facade_world), true)
		_expect(selection.selected.size() == 1 and selection.selected[0] == building and _gather_count == before_gathers, "%s opaque facade was stolen by an adjacent resource ring" % building_type)
		adjacent_tree.free()
		building.free()

	# The explicit command boundary does not remove ordinary own-unit grouping.
	camera.zoom = Vector2(0.952, 0.952)
	camera.force_update_scroll()
	soldier.position = Vector2.ZERO
	previous.position = Vector2(60.0, 0.0)
	selection.set("_last_tap_time", 0.0)
	var soldier_body_screen: Vector2 = selection.call("_world_to_screen", Vector2(0.0, -10.0))
	_push_tap(selection, soldier_body_screen, true)
	_push_tap(selection, soldier_body_screen, true)
	_expect(selection.selected.size() == 2 and soldier in selection.selected and previous in selection.selected, "ordinary same-unit double tap no longer groups visible own soldiers")

	world.free()
	if _failures.is_empty():
		print("[PASS] building_facade_selection: TC/Barracks walls beat nearby unit/resource rings; body hits, one-shot/grouping and construction preserved via viewport touch/mouse at 3 zooms")
		get_tree().quit(0)
	else:
		for failure: String in _failures.slice(0, 8):
			push_error("[FAIL] building_facade_selection: %s" % failure)
		print("[FAIL] building_facade_selection: %d assertions failed" % _failures.size())
		get_tree().quit(1)


func _spawn_unit(world: Node2D, type: String, owner: int) -> UnitBase:
	var unit: UnitBase = load("res://scenes/units/%s.tscn" % type).instantiate() as UnitBase
	unit.player_owner = owner
	world.add_child(unit)
	unit.set_process(false)
	unit.set_physics_process(false)
	return unit


func _push_tap(selection: SelectionManager, position: Vector2, touch: bool) -> void:
	if not touch:
		selection.set("_last_touch_input_msec", -2000)
	for pressed: bool in [true, false]:
		if touch:
			var event := InputEventScreenTouch.new()
			event.index = 0
			event.position = position
			event.pressed = pressed
			get_viewport().push_input(event, true)
		else:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = position
			event.pressed = pressed
			get_viewport().push_input(event, true)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
