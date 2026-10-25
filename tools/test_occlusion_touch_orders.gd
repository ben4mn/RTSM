extends Node
## Real InputEventScreenTouch dispatch on staged illustrated occlusion, followed
## by paid-world unit command routing. Positions/fog are fixture-controlled;
## this is not physical-device or natural battle performance evidence.

var _failures: Array[String] = []
var _checks: int = 0
var _main: Node
var _map: Node2D
var _selection: SelectionManager
var _overlay: Node
var _profile: String
var _contact_id: int = 20

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	Input.emulate_touch_from_mouse = true
	GameManager.selected_population_limit = 100
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	for civ: int in CivilizationData.ORDERED_IDS:
		GameManager.selected_civilization = civ
		GameManager.selected_opponent_civilization = civ
		GameManager.set_state(GameManager.GameState.MENU)
		_main = load("res://scenes/main/main.tscn").instantiate()
		add_child(_main)
		for frame: int in 900:
			if _main.get("_building_placement") != null: break
			await get_tree().process_frame
		_main.set_process(false)
		_main.ai_controller.set_process(false)
		_main.ai_controller.get("_decision_timer").stop()
		_map = _main.game_map
		_map.fog_of_war.set_process(false)
		_map.fog_of_war.reveal_all()
		_map.camera.set_process(false)
		_selection = _map.selection_mgr
		_overlay = _map.get_node("UnitOcclusionOverlay")
		_overlay.set("allow_headless_fixture",true)
		_overlay.set_process(false)
		for unit: Node in get_tree().get_nodes_in_group("units"): unit.set_process(false)
		var worker: UnitBase = _main.get("_player_units")[0][0]
		var tc: BuildingBase = _main.get("_player_buildings")[0][0]
		var tree: ResourceNode
		var tree_distance: float = INF
		for resource: ResourceNode in _map.resource_nodes.values():
			if resource.resource_type == "wood" and resource.global_position.distance_to(tc.global_position) < tree_distance:
				tree=resource
				tree_distance=resource.global_position.distance_to(tc.global_position)
		tree.visible=true
		var front: UnitBase = _main.call("_spawn_unit",UnitData.UnitType.CAVALRY,1,tc.global_position+Vector2(200,0))
		var fighter: UnitBase = _main.call("_spawn_unit",UnitData.UnitType.INFANTRY,0,tc.global_position+Vector2(150,0))
		front.set_process(false)
		fighter.set_process(false)
		for physical: Vector2i in [Vector2i(844,390),Vector2i(1280,720)]:
			get_window().size=physical
			get_window().content_scale_size=physical
			get_window().content_scale_factor=1.15 if physical.x==844 else 1.0
			for zoom: float in [0.85,1.3]:
				_profile="civ%d %s zoom%.2f" % [civ,physical,zoom]
				_map.camera.zoom=Vector2.ONE*zoom
				front.position=tc.global_position+Vector2(200,0)
				fighter.position=tc.global_position+Vector2(150,0)
				for occluder: String in ["building","tree","enemy"]:
					if occluder=="building": worker.position=tc.get("_sprite").global_position+Vector2(0,-8)
					elif occluder=="tree": worker.position=tree.global_position+Vector2(0,-5)
					else:
						worker.position=_map.tile_to_world(Vector2i(36,36))
						front.position=worker.position+Vector2(0,6)
					await _center(worker.global_position)
					_overlay.call("_process",0.11)
					var echo: Sprite2D = worker.get_node_or_null("OccludedUnitEcho")
					_expect(echo!=null and echo.visible,occluder+" silhouette visible")
					for band: Vector2 in [Vector2(0.12,0.35),Vector2(0.40,0.65)]:
						_selection.deselect_all()
						_selection.set("_last_tap_time",0.0)
						var point: Vector2 = _opaque_point(worker.get("_sprite"),band)
						await _tap(get_viewport().get_canvas_transform()*point)
						_expect(_selection.selected.size()==1 and _selection.selected[0]==worker,"touch intended "+occluder+" silhouette band"+str(band))
				# Real touch routes: select a body, arm Move/Attack through the HUD,
				# then issue destination and direct-enemy orders through world input.
				front.position=tc.global_position+Vector2(220,0)
				var origin: Vector2=_find_walkable_near(tc.global_position)
				fighter.position=origin
				worker.position=origin+Vector2(200,0)
				await _center(origin)
				_overlay.call("_process",0.11)
				_selection.deselect_all()
				_selection.set("_last_tap_time",0.0)
				await _tap(get_viewport().get_canvas_transform()*_opaque_point(fighter.get("_sprite"),Vector2(0.3,0.6)))
				_expect(_selection.selected.size()==1 and _selection.selected[0]==fighter,"select fighter before orders")
				var ground: Vector2=_empty_ground(fighter)
				_expect(ground!=Vector2.ZERO,"reachable visible destination")
				await _tap(_main.hud.get("_unit_move_button").get_global_rect().get_center())
				_expect(bool(_main.get("_move_command_armed")),"tap Move arms")
				await _tap(ground)
				_expect(not bool(_main.get("_move_command_armed")) and fighter.current_state==UnitBase.State.MOVING and bool(fighter.get("_force_move_active")),"tap destination moves")
				fighter.command_stop()
				await _tap(_main.hud.get("_unit_attack_move_button").get_global_rect().get_center())
				_expect(bool(_main.get("_attack_move_command_armed")),"tap Attack arms")
				await _tap(ground)
				_expect(fighter.attack_move and not bool(_main.get("_attack_move_command_armed")),"tap destination attack-moves")
				fighter.command_stop()
				front.position=tc.get("_sprite").global_position+Vector2(0,-8)
				await _center(front.global_position)
				_overlay.call("_process",0.11)
				var enemy_point: Vector2=_opaque_point(front.get("_sprite"),Vector2(0.2,0.5))
				await _tap(get_viewport().get_canvas_transform()*enemy_point)
				_expect(fighter.attack_target==front,"tap visible enemy silhouette attacks directly")
				fighter.command_stop()
				var tile: Vector2i=_map.world_to_tile(front.global_position)
				for fog_state: int in [MapData.FogState.EXPLORED,MapData.FogState.UNEXPLORED]:
					_map.fog_of_war.fog_grid[tile.y][tile.x]=fog_state
					_overlay.call("_process",0.0)
					_selection.set("_last_tap_time",0.0)
					await _tap(get_viewport().get_canvas_transform()*enemy_point)
					_expect(fighter.attack_target!=front and front not in _selection.selected,"hidden enemy cannot be targeted")
				_map.fog_of_war.fog_grid[tile.y][tile.x]=MapData.FogState.VISIBLE
		_main.free()
		await get_tree().process_frame
	for failure: String in _failures: push_error("[FAIL] occlusion_touch_orders: "+failure)
	if _failures.is_empty(): print("[PASS] occlusion_touch_orders: %d checks;3civilizations,phone115%%/desktop,2camera scales,opaque head/body behind roofs/trees/enemy units,actualScreenTouch Move/Attack/direct enemy and fog gating" % _checks)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _center(world: Vector2) -> void:
	_map.camera.position=world
	_map.camera.reset_smoothing()
	_map.camera.force_update_scroll()
	await _frames(3)

func _opaque_point(sprite: Sprite2D, band: Vector2) -> Vector2:
	var ink: Rect2=KingdomArt.ink_rect(sprite.texture)
	ink.position+=sprite.get_rect().position
	for y: int in 12:
		for x: float in [0.5,0.45,0.55,0.35,0.65]:
			var point: Vector2=ink.position+ink.size*Vector2(x,lerpf(band.x,band.y,float(y)/11.0))
			if sprite.is_pixel_opaque(point): return sprite.to_global(point)
	_expect(false,"no opaque body pixel")
	return sprite.global_position

func _find_walkable_near(world: Vector2) -> Vector2:
	var origin: Vector2i=_map.world_to_tile(world)
	for radius: int in range(4,10):
		for dx: int in range(-radius,radius+1):
			var tile:=origin+Vector2i(dx,radius)
			if _map.is_tile_walkable(tile): return _map.tile_to_world(tile)
	return world

func _empty_ground(unit: UnitBase) -> Vector2:
	var origin: Vector2i=_map.world_to_tile(unit.global_position)
	var world_area:=Rect2(Vector2(150,90),get_viewport().get_visible_rect().size-Vector2(300,220))
	for radius: int in range(2,9):
		for y: int in range(-radius,radius+1):
			for x: int in range(-radius,radius+1):
				var tile:=origin+Vector2i(x,y)
				if not _map.is_tile_walkable(tile): continue
				var world: Vector2=_map.tile_to_world(tile)
				var screen: Vector2=get_viewport().get_canvas_transform()*world
				if world_area.has_point(screen) and _selection.call("_get_node_at",world,true)==null and _selection.call("_get_resource_at",world,true)==null and not _map.get_navigation_world_path(unit.global_position,world).is_empty(): return screen
	return Vector2.ZERO

func _tap(logical: Vector2) -> void:
	_contact_id+=1
	for pressed: bool in [true,false]:
		var event:=InputEventScreenTouch.new()
		event.index=_contact_id
		event.pressed=pressed
		event.position=get_viewport().get_final_transform()*logical
		Input.parse_input_event(event)
		await _frames(3)

func _frames(count: int) -> void:
	for frame: int in count: await get_tree().process_frame

func _expect(condition: bool, message: String) -> void:
	_checks+=1
	if not condition: _failures.append(_profile+" "+message)
