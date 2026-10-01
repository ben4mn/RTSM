extends Node
## Natural tree artwork must accept canopy clicks without broadening fog access
## or stealing a direct tap on an adjacent resource.

var _failures: Array[String] = []
var _gather_target: Node2D = null
var _attack_target: Node2D = null

class VisibleWorld extends Node2D:
	func is_resource_target_valid(target: Node2D, _kind: String = "", player: int = 0) -> bool:
		return target.visible and target.has_method("is_harvestable_by") and bool(target.call("is_harvestable_by", player))
	func is_entity_visible_to_player(target: Node2D, _player: int) -> bool:
		return target.visible
	func world_to_tile(point: Vector2) -> Vector2i:
		return Vector2i(roundi(point.x), roundi(point.y))

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	get_tree().root.size = Vector2i(844, 390)
	var world := VisibleWorld.new()
	add_child(world)
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	world.add_child(camera)
	var picker := SelectionManager.new()
	picker.game_map = world
	picker.touch_context_enabled = false
	world.add_child(picker)
	picker.gather_command.connect(func(target: Node2D) -> void: _gather_target = target)
	picker.attack_command.connect(func(target: Node2D) -> void: _attack_target = target)
	var tree := _resource(world, "wood", Vector2.ZERO)
	var worker: Villager = load("res://scenes/units/villager.tscn").instantiate() as Villager
	worker.position = Vector2(-140, 0)
	world.add_child(worker)
	worker.set_process(false)
	await get_tree().process_frame
	var sprite: Sprite2D = tree.get_node("Sprite") as Sprite2D
	var canopy: Vector2 = _opaque_canopy_point(sprite, tree.global_position)
	_expect(canopy.distance_to(tree.global_position) > 20.0, "test canopy must lie beyond the old desktop ground-anchor radius")
	for zoom: float in [0.62, 0.952, 2.2]:
		camera.zoom = Vector2(zoom, zoom)
		camera.force_update_scroll()
		await get_tree().process_frame
		_expect(picker.call("_get_resource_at", canopy, false) == tree, "desktop canopy miss at zoom %.3f" % zoom)
		_expect(picker.call("_get_resource_at", canopy, true) == tree, "touch canopy miss at zoom %.3f" % zoom)
		picker.select_single(worker)
		picker.set("_last_touch_input_msec", 0)
		_gather_target = null
		var screen: Vector2 = picker.call("_world_to_screen", canopy) as Vector2
		for pressed: bool in [true, false]:
			var click := InputEventMouseButton.new()
			click.device = 0
			click.button_index = MOUSE_BUTTON_RIGHT
			click.position = screen
			click.pressed = pressed
			Input.parse_input_event(click)
			await get_tree().process_frame
		_expect(_gather_target == tree, "actual right-click dispatch did not gather the canopy at zoom %.3f" % zoom)
	var berries := _resource(world, "food", canopy)
	_expect(picker.call("_get_resource_at", canopy, false) == berries, "overlapping tree artwork stole a direct food-ground click")
	berries.visible = false
	tree.visible = false
	_expect(picker.call("_get_resource_at", canopy, false) == null, "hidden tree canopy remained targetable")
	# A direct hostile target still owns a smart touch command when its visible
	# feet overlap tree artwork outside the resource's old ground hit radius.
	tree.visible = true
	var enemy: UnitBase = load("res://scenes/units/infantry.tscn").instantiate() as UnitBase
	enemy.player_owner = 1
	enemy.position = canopy
	world.add_child(enemy)
	enemy.set_process(false)
	await get_tree().process_frame
	picker.select_single(worker)
	picker.set("_last_tap_time", 0.0)
	_gather_target = null
	_attack_target = null
	_expect(picker.call("_get_node_at", canopy, true) == enemy, "overlapping enemy feet must remain a deliberate visible unit target")
	var enemy_screen: Vector2 = picker.call("_world_to_screen", canopy) as Vector2
	for pressed: bool in [true, false]:
		var tap := InputEventScreenTouch.new()
		tap.index = 0
		tap.position = enemy_screen
		tap.pressed = pressed
		Input.parse_input_event(tap)
		await get_tree().process_frame
	_expect(_attack_target == enemy and _gather_target == null, "actual enemy touch under a canopy must attack instead of gathering wood")
	_expect(str(picker.touch_input_diagnostics.get("action", "")) == "attack", "enemy canopy touch must record attack routing")
	# Farm artwork has the same resource protocol, and a tap on its visible
	# body must retain the worker selection and dispatch gathering.
	tree.visible = false
	enemy.visible = false
	var farm: BuildingBase = load("res://scenes/buildings/farm.tscn").instantiate() as BuildingBase
	farm.state = BuildingBase.State.ACTIVE
	world.add_child(farm)
	farm.set_process(false)
	camera.zoom = Vector2(2.2, 2.2)
	camera.force_update_scroll()
	await get_tree().process_frame
	var farm_body: Vector2 = _opaque_facade_point(picker, farm)
	_expect(farm_body.distance_to(farm.global_position) > 24.0, "Farm body fixture must exceed both ground hit radii at detail zoom")
	var farm_outer_body: Vector2 = _opaque_canopy_point(farm.get_node("BuildingSprite") as Sprite2D, farm.global_position, 30.0)
	_expect(farm_outer_body.distance_to(farm.global_position) > 28.0, "outer Farm body fixture must exceed the desktop ground hit radius")
	_expect(picker.call("_get_resource_at", farm_outer_body, false) == farm, "desktop opaque Farm artwork missed the active owned food source")
	_expect(picker.call("_get_resource_at", farm_body, true) == farm, "touch opaque Farm artwork missed the active owned food source")
	picker.select_single(worker)
	picker.set("_last_tap_time", 0.0)
	_gather_target = null
	var farm_screen: Vector2 = picker.call("_world_to_screen", farm_body) as Vector2
	for pressed: bool in [true, false]:
		var farm_tap := InputEventScreenTouch.new()
		farm_tap.index = 0
		farm_tap.position = farm_screen
		farm_tap.pressed = pressed
		Input.parse_input_event(farm_tap)
		await get_tree().process_frame
	print("[METRIC] Farm body distance=%.2f zoom=2.2 touch_action=%s gather=%s worker_selected=%s" % [farm_body.distance_to(farm.global_position), picker.touch_input_diagnostics.get("action", ""), _gather_target == farm, picker.selected.has(worker)])
	_expect(_gather_target == farm and picker.selected.has(worker), "actual Farm body touch must gather while retaining the selected worker")
	picker.select_single(worker)
	picker.set("_last_touch_input_msec", 0)
	_gather_target = null
	var farm_outer_screen: Vector2 = picker.call("_world_to_screen", farm_outer_body) as Vector2
	for pressed: bool in [true, false]:
		var farm_click := InputEventMouseButton.new()
		farm_click.device = 0
		farm_click.button_index = MOUSE_BUTTON_RIGHT
		farm_click.position = farm_outer_screen
		farm_click.pressed = pressed
		Input.parse_input_event(farm_click)
		await get_tree().process_frame
	_expect(_gather_target == farm, "actual right-click on opaque Farm artwork must gather food")
	# Body fallback must still respect visibility, ownership, activity and stock.
	farm.visible = false
	_expect(picker.call("_get_resource_at", farm_body, true) == null, "hidden Farm body remained targetable")
	farm.visible = true
	farm.player_owner = 1
	_expect(picker.call("_get_resource_at", farm_body, true) == null, "hostile Farm body became a food target")
	farm.player_owner = 0
	farm.state = BuildingBase.State.CONSTRUCTING
	_expect(picker.call("_get_resource_at", farm_body, true) == null, "unfinished Farm body became a food target")
	farm.state = BuildingBase.State.ACTIVE
	farm.farm_remaining = 0
	_expect(picker.call("_get_resource_at", farm_body, true) == null, "exhausted Farm body remained a food target")
	farm.farm_remaining = 300
	enemy.position = farm_body
	enemy.visible = true
	picker.select_single(worker)
	picker.set("_last_tap_time", 0.0)
	_gather_target = null
	_attack_target = null
	_expect(picker.call("_get_node_at", farm_body, true) == enemy, "enemy feet over Farm art must remain a deliberate unit target")
	for pressed: bool in [true, false]:
		var enemy_farm_tap := InputEventScreenTouch.new()
		enemy_farm_tap.index = 0
		enemy_farm_tap.position = farm_screen
		enemy_farm_tap.pressed = pressed
		Input.parse_input_event(enemy_farm_tap)
		await get_tree().process_frame
	_expect(_attack_target == enemy and _gather_target == null, "actual enemy touch over Farm art must attack instead of gathering food")
	world.free()
	if _failures.is_empty():
		print("[PASS] resource_visual_targeting: opaque tree/Farm input, direct food/enemy priority, Farm guards, actual touch attack, hidden rejection")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] resource_visual_targeting: %s" % failure)
		get_tree().quit(1)

func _resource(world: Node2D, kind: String, point: Vector2) -> ResourceNode:
	var result: ResourceNode = load("res://scenes/map/resource_node.tscn").instantiate() as ResourceNode
	result.resource_type = kind
	result.position = point
	world.add_child(result)
	return result

func _opaque_canopy_point(sprite: Sprite2D, anchor: Vector2, minimum_radius: float = 24.0) -> Vector2:
	var rect: Rect2 = sprite.get_rect()
	for y: int in range(int(rect.position.y), int(rect.end.y), 4):
		for x: int in range(int(rect.position.x), int(rect.end.x), 4):
			var local := Vector2(x, y)
			var point: Vector2 = sprite.to_global(local)
			if sprite.is_pixel_opaque(local) and point.distance_to(anchor) > minimum_radius:
				return point
	return anchor

func _opaque_facade_point(picker: SelectionManager, building: BuildingBase) -> Vector2:
	var sprite: Sprite2D = building.get_node("BuildingSprite") as Sprite2D
	var rect: Rect2 = sprite.get_rect()
	for y: int in range(int(rect.position.y), int(rect.end.y), 2):
		for x: int in range(int(rect.position.x), int(rect.end.x), 2):
			var local := Vector2(x, y)
			var point: Vector2 = sprite.to_global(local)
			if sprite.is_pixel_opaque(local) and point.distance_to(building.global_position) > 24.0 and bool(picker.call("_is_touch_on_building_facade", building, point)):
				return point
	return building.global_position

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
