extends Node
## Focused FOG-001 regression.
## Run through: Godot --headless --path . tools/test_fog_command_legality.tscn

const INFANTRY_SCENE: PackedScene = preload("res://scenes/units/infantry.tscn")

var _failures: Array[String] = []


class FakeVisibilityMap extends Node2D:
	var visible_entities: Dictionary = {}
	var selection_mgr: SelectionManager = null
	var camera: Camera2D = null
	var clamp_count: int = 0

	func set_entity_visible(entity: Node2D, is_visible: bool) -> void:
		visible_entities[entity.get_instance_id()] = is_visible

	func is_entity_visible_to_player(entity: Node2D, viewer_player_id: int = 0) -> bool:
		if entity is UnitBase and (entity as UnitBase).player_owner == viewer_player_id:
			return true
		return bool(visible_entities.get(entity.get_instance_id(), false))

	func get_navigation_world_path(
		from_world: Vector2,
		target_world: Vector2,
		_arrival_radius_world: float = 4.0,
		_max_goal_radius_tiles: int = 6
	) -> PackedVector2Array:
		return PackedVector2Array([from_world, target_world])

	func world_to_tile(world_position: Vector2) -> Vector2i:
		return Vector2i(roundi(world_position.x / 16.0), roundi(world_position.y / 16.0))

	func is_tile_walkable(_tile: Vector2i) -> bool:
		return true

	func _clamp_camera() -> void:
		clamp_count += 1


class FakeHud extends CanvasLayer:
	var notification_count: int = 0

	func show_notification(_text: String, _color: Color = Color.WHITE) -> void:
		notification_count += 1


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager != null:
		audio_manager.call("set_all_enabled", false)
	_test_fog_grid_transition()
	_test_unexplored_fog_is_opaque()
	_test_hidden_targets_are_not_live_inputs()
	_finish()


func _test_fog_grid_transition() -> void:
	var fog := FogManager.new()
	add_child(fog)
	fog.set_vision_sources([{
		"position": Vector2i(4, 4),
		"vision_radius": 2,
		"is_scout": false,
	}])
	fog._update_visibility()
	_expect(fog.is_tile_visible(Vector2i(4, 4)), "registered vision makes a tile visible")
	fog.clear_vision_sources()
	fog._update_visibility()
	_expect(not fog.is_tile_visible(Vector2i(4, 4)), "tile stops being currently visible when vision leaves")
	_expect(fog.is_explored(Vector2i(4, 4)), "lost vision retains explored terrain state")
	fog.free()


func _test_unexplored_fog_is_opaque() -> void:
	var atlas: Image = TilesetBuilder._create_fog_atlas()
	var unexplored_center := Vector2i(MapData.TILE_WIDTH / 2, MapData.TILE_HEIGHT / 2)
	var explored_center := Vector2i(
		MapData.TILE_WIDTH + MapData.TILE_WIDTH / 2,
		MapData.TILE_HEIGHT / 2
	)
	_expect(
		is_equal_approx(atlas.get_pixelv(unexplored_center).a, 1.0),
		"unexplored fog is fully opaque and cannot reveal terrain silhouettes"
	)
	_expect(
		atlas.get_pixelv(explored_center).a < 1.0,
		"explored fog remains visually distinct from unexplored terrain"
	)


func _test_hidden_targets_are_not_live_inputs() -> void:
	var visibility_map := FakeVisibilityMap.new()
	add_child(visibility_map)
	var selection := SelectionManager.new()
	selection.game_map = visibility_map
	visibility_map.add_child(selection)
	visibility_map.selection_mgr = selection
	var camera := Camera2D.new()
	visibility_map.add_child(camera)
	visibility_map.camera = camera
	var container := Node2D.new()
	visibility_map.add_child(container)

	var friendly: UnitBase = INFANTRY_SCENE.instantiate() as UnitBase
	friendly.player_owner = 0
	friendly.global_position = Vector2(0.0, 0.0)
	container.add_child(friendly)
	var enemy: UnitBase = INFANTRY_SCENE.instantiate() as UnitBase
	enemy.player_owner = 1
	enemy.global_position = Vector2(120.0, 0.0)
	container.add_child(enemy)
	visibility_map.set_entity_visible(enemy, false)
	var enemy_building := BuildingBase.new()
	enemy_building.player_owner = 1
	enemy_building.state = BuildingBase.State.ACTIVE
	enemy_building.global_position = Vector2(220.0, 0.0)
	container.add_child(enemy_building)
	visibility_map.set_entity_visible(enemy_building, false)
	var resource := ResourceNode.new()
	resource.global_position = Vector2(320.0, 0.0)
	container.add_child(resource)
	visibility_map.set_entity_visible(resource, false)
	var tower := BuildingBase.new()
	tower.player_owner = 0
	tower.state = BuildingBase.State.ACTIVE
	tower.global_position = Vector2(40.0, 0.0)
	container.add_child(tower)
	tower.tower_attack_damage = 10
	tower.tower_attack_range = 200.0

	var hidden_hit: Node2D = selection.call("_get_node_at", enemy.global_position, false)
	_expect(hidden_hit == null, "hidden enemy is absent from pointer hit testing")
	var hidden_building_hit: Node2D = selection.call("_get_node_at", enemy_building.global_position, false)
	_expect(hidden_building_hit == null, "hidden enemy building is absent from pointer hit testing")
	var hidden_resource_hit: Node2D = selection.call("_get_resource_at", resource.global_position, false)
	_expect(hidden_resource_hit == null, "hidden neutral resource is absent from pointer hit testing")
	selection.select_single(enemy)
	_expect(selection.selected.is_empty(), "hidden enemy cannot be selected programmatically")
	selection.select_single(enemy_building)
	_expect(selection.selected.is_empty(), "hidden enemy building cannot be selected programmatically")
	selection.select_single(resource)
	_expect(selection.selected.is_empty(), "hidden neutral resource cannot be selected programmatically")
	var enemy_hp_before_hidden_tower: float = enemy.hp
	tower.call("_tower_try_attack")
	_expect(is_equal_approx(enemy.hp, enemy_hp_before_hidden_tower), "friendly tower cannot damage a hidden enemy")

	visibility_map.set_entity_visible(enemy, true)
	visibility_map.set_entity_visible(enemy_building, true)
	visibility_map.set_entity_visible(resource, true)
	var visible_hit: Node2D = selection.call("_get_node_at", enemy.global_position, false)
	_expect(visible_hit == enemy, "visible enemy remains targetable")
	var visible_building_hit: Node2D = selection.call("_get_node_at", enemy_building.global_position, false)
	_expect(visible_building_hit == enemy_building, "visible enemy building remains targetable")
	var visible_resource_hit: Node2D = selection.call("_get_resource_at", resource.global_position, false)
	_expect(visible_resource_hit == resource, "visible neutral resource remains targetable")
	tower.call("_tower_try_attack")
	_expect(enemy.hp < enemy_hp_before_hidden_tower, "friendly tower can damage the enemy after it enters vision")
	selection.select_single(enemy)
	_expect(selection.selected.size() == 1, "visible enemy can be selected for inspection")
	visibility_map.set_entity_visible(enemy, false)
	selection.call("_prune_stale_selection")
	_expect(selection.selected.is_empty(), "selected enemy is pruned immediately after leaving vision")
	_test_control_groups_reject_hidden_enemy_tracking(
		visibility_map,
		selection,
		friendly,
		tower,
		enemy,
		enemy_building
	)

	selection.select_single(friendly)
	var emitted_attacks: Array[Node2D] = []
	selection.attack_command.connect(func(target: Node2D) -> void: emitted_attacks.append(target))
	selection.set("_context_target", enemy)
	selection.call("_execute_touch_context_action", SelectionManager.TouchContextAction.ATTACK)
	_expect(emitted_attacks.is_empty(), "stale touch context cannot command an attack on a hidden enemy")

	visibility_map.set_entity_visible(enemy, true)
	friendly.command_attack(enemy)
	_expect(friendly.attack_target == enemy, "visible target can be tracked by a commanded unit")
	visibility_map.set_entity_visible(enemy, false)
	friendly._process_attacking(0.1)
	_expect(friendly.attack_target == null, "unit drops a tracked enemy as soon as it leaves local vision")
	_expect(friendly.current_state == UnitBase.State.IDLE, "unit returns idle after losing a non-attack-move target")

	friendly.free()
	enemy.free()
	enemy_building.free()
	resource.free()
	tower.free()
	visibility_map.free()


func _test_control_groups_reject_hidden_enemy_tracking(
	visibility_map: FakeVisibilityMap,
	selection: SelectionManager,
	owned_unit: UnitBase,
	owned_building: BuildingBase,
	enemy_unit: UnitBase,
	enemy_building: BuildingBase
) -> void:
	var main_script: Script = load("res://scripts/main/main.gd") as Script
	var main_controller: Node = main_script.new() as Node
	main_controller.set("game_map", visibility_map)
	var fake_hud := FakeHud.new()
	visibility_map.add_child(fake_hud)
	main_controller.set("hud", fake_hud)

	# A visible enemy remains inspectable, but saving a group must never retain it.
	visibility_map.set_entity_visible(enemy_unit, true)
	selection.select_single(enemy_unit)
	main_controller.call("_save_control_group", 1)
	var groups: Array = main_controller.get("_control_groups") as Array
	_expect((groups[1] as Array).is_empty(), "visible enemy cannot be retained in a control group")

	# Harden recall against a stale/legacy or programmatically injected group too.
	# Moving the enemies after fog closes must not affect the camera or selection.
	groups[1] = [enemy_unit, enemy_building]
	main_controller.set("_control_groups", groups)
	visibility_map.set_entity_visible(enemy_unit, false)
	visibility_map.set_entity_visible(enemy_building, false)
	enemy_unit.global_position = Vector2(1400.0, 900.0)
	enemy_building.global_position = Vector2(1500.0, 950.0)
	visibility_map.camera.position = Vector2(17.0, 23.0)
	var camera_before := visibility_map.camera.position
	var clamps_before := visibility_map.clamp_count
	main_controller.call("_recall_control_group", 1)
	main_controller.call("_recall_control_group", 1)
	_expect(selection.selected.is_empty(), "hidden enemy group recall yields an empty selection")
	_expect_vector_approx(visibility_map.camera.position, camera_before, "hidden enemy double recall cannot track its live position")
	_expect_eq(visibility_map.clamp_count, clamps_before, "hidden enemy double recall never enters camera centering")
	groups = main_controller.get("_control_groups") as Array
	_expect((groups[1] as Array).is_empty(), "rejected enemy entries are purged from the control group")

	# Owned units and buildings still recall normally, and double recall centers on
	# the exact set SelectionManager accepted.
	owned_unit.global_position = Vector2(80.0, 40.0)
	owned_building.global_position = Vector2(160.0, 80.0)
	selection.select_many([owned_unit, owned_building])
	main_controller.call("_save_control_group", 2)
	selection.deselect_all()
	main_controller.call("_recall_control_group", 2)
	main_controller.call("_recall_control_group", 2)
	_expect_eq(selection.selected.size(), 2, "owned unit and building still recall from a control group")
	_expect_vector_approx(visibility_map.camera.position, Vector2(120.0, 60.0), "owned group double recall centers on accepted selection")
	_expect_eq(visibility_map.clamp_count, clamps_before + 1, "owned group double recall clamps the camera once")
	_expect_eq(fake_hud.notification_count, 1, "saving the owned group still acknowledges it once")

	main_controller.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


func _expect_vector_approx(actual: Vector2, expected: Vector2, message: String) -> void:
	_expect(actual.is_equal_approx(expected), "%s (expected %s, got %s)" % [message, expected, actual])


func _finish() -> void:
	if _failures.is_empty():
		print("[PASS] fog_command_legality: hidden targets and control-group camera tracking are gated")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] fog_command_legality: %s" % failure)
	get_tree().quit(1)
