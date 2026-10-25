extends "res://tools/test_fighter_shortcuts.gd"
## Bounded active-world interaction audit. Synthetic funded armies/positions;
## live unit processing, normal input routing and ordinary production costs.
var _samples: Array[Dictionary] = []
var _world_records: Array[Dictionary] = []
var _output: String = ""
var _audit_checks: int = 0

func _run() -> void:
	_output=OS.get_environment("AOEM_MULTIFRONT_OUTPUT")
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch=true
	GameManager.guided_opening_enabled=false
	GameManager.selected_population_limit=100
	GameManager.selected_map_seed=101
	for physical: Vector2i in [Vector2i(844,390),Vector2i(1280,720)]:
		await _audit(physical)
	var report: Dictionary={"scope":"Headless active staged Main, two fronts and normal starting economy; real ScreenTouch and keyboard dispatch. Synthetic units/cap/funding; not paid match pacing, rendering FPS, device input or network latency.","checks":_audit_checks,"failures":_failures,"response_samples":_samples,"world":_world_records}
	if not _output.is_empty():
		DirAccess.make_dir_recursive_absolute(_output)
		FileAccess.open(_output.path_join("multifront-interaction.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("[MULTIFRONT] "+JSON.stringify(report))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _apply_profile_layout() -> void:
	pass

func _expect(condition: bool, message: String) -> void:
	_audit_checks+=1
	super._expect(condition,message)

func _audit(physical: Vector2i) -> void:
	_profile="phone115" if physical.x==844 else "desktop"
	get_window().size=physical
	get_window().content_scale_size=physical
	get_window().content_scale_factor=1.15 if physical.x==844 else 1.0
	GameManager.ui_scale=get_window().content_scale_factor
	GameManager.set_state(GameManager.GameState.MENU)
	_main=load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for frame: int in 900:
		if _main.get("_building_placement")!=null: break
		await get_tree().process_frame
	_map=_main.game_map
	_hud=_main.hud
	_selection=_map.selection_mgr
	_main.ai_controller.set_process(false)
	_main.ai_controller.get("_decision_timer").stop()
	GameManager.grant_population_cap(0,900000,100)
	GameManager.grant_population_cap(1,900001,100)
	ResourceManager.initialize_player(0,{"food":2000,"wood":2000,"gold":1000})
	var leaders: Array[UnitBase]=[]
	var armies: Array[UnitBase]=[]
	for front: int in 2:
		var origin:=Vector2i(25+front*29,25+front*29)
		leaders.append(_main.call("_spawn_unit",UnitData.UnitType.CAVALRY,0,_walkable_near(origin+Vector2i(-8,0))))
		leaders.back().stance=UnitBase.Stance.STAND_GROUND
		for owner: int in 2:
			for index: int in 6:
				var tile:=origin+Vector2i(index%3+owner*8,index/3)
				var actor: UnitBase=_main.call("_spawn_unit",UnitData.UnitType.INFANTRY if index<4 else UnitData.UnitType.ARCHER,owner,_walkable_near(tile))
				armies.append(actor)
				actor.command_attack_move(_walkable_near(origin+Vector2i(4,0)))
	var initial_positions: Array[Vector2]=[]
	for actor: UnitBase in armies: initial_positions.append(actor.global_position)
	_main.call("_update_fog_of_war")
	var overview: StrategyOverview=_hud.get("_strategy_overview")
	var controller: Node=_main.get_node("StrategyController")
	var tc: BuildingBase=_main.get("_player_buildings")[0][0]
	var workers: Array=(_main.get("_player_units")[0] as Array).filter(func(actor: UnitBase)->bool:return actor is Villager)
	var worker_jobs: Array=[]
	for worker: Villager in workers: worker_jobs.append(worker.current_state)
	var start_game_time: float=GameManager.game_time
	for group: int in 2:
		_map.note_camera_interaction()
		_map.set("_user_zoom_override",true)
		_map.camera.zoom=Vector2(0.85,0.85)
		_map.camera.position=leaders[group].global_position
		_map.camera.reset_smoothing()
		_map.camera.force_update_scroll()
		_selection.deselect_all()
		await _frames(3)
		await _measured_tap("select unit",get_viewport().get_canvas_transform()*leaders[group].global_position,func()->bool:return _selection.selected==[leaders[group]])
		await _measured_tap("Move armed",_hud.get("_unit_move_button").get_global_rect().get_center(),func()->bool:return bool(_main.get("_move_command_armed")))
		var destination: Vector2=_audit_ground(leaders[group])
		_expect(destination!=Vector2.ZERO,"reachable Move destination")
		await _measured_tap("Move accepted",destination,func()->bool:return not bool(_main.get("_move_command_armed")) and leaders[group].current_state==UnitBase.State.MOVING)
		await _measured_tap("Attack armed",_hud.get("_unit_attack_move_button").get_global_rect().get_center(),func()->bool:return bool(_main.get("_attack_move_command_armed")))
		await _measured_tap("Attack accepted",destination,func()->bool:return leaders[group].attack_move and not bool(_main.get("_attack_move_command_armed")))
		await _button(overview.rail.get_node("ArmyButton"))
		if bool(overview.get("_army_recruit_page")): await _button(overview.get("_groups_tab"))
		await _overview_button(overview,overview.get("_group_rows")[group+1].save)
		_expect(_main.get("_control_groups")[group+1]==[leaders[group]],"actual Save retains selected front")
		await _button(overview.rail.get_node("ArmyButton"))
	var last_goals: Array[Vector2]=[leaders[0].move_target,leaders[1].move_target]
	for repeat: int in 3:
		controller.call("_refresh")
		var selected_before: Array=_selection.selected.duplicate()
		await _measured_tap("Economy open",overview.rail.get_node("EconomyButton").get_global_rect().get_center(),func()->bool:return _hud.call("get_secondary_surface_name")=="economy")
		_expect(_selection.selected==selected_before,"Economy preserves front selection")
		if not bool(overview.get("_production_page")):
			await _button(overview.get("_production_tab"))
		else:
			await _frames(1)
		var row: Dictionary=overview.get("_producer_rows")[tc.get_instance_id()]
		await _overview_button(overview,row.train[UnitData.UnitType.VILLAGER])
		_expect(_selection.selected==selected_before,"paid remote recruitment preserves front selection")
		await _button(overview.rail.get_node("EconomyButton"))
		await _measured_tap("Army open",overview.rail.get_node("ArmyButton").get_global_rect().get_center(),func()->bool:return _hud.call("get_secondary_surface_name")=="army")
		if bool(overview.get("_army_recruit_page")): await _button(overview.get("_groups_tab"))
		var group: int=1+repeat%2
		await _measured_tap("Group recall",overview.get("_group_rows")[group].recall.get_global_rect().get_center(),func()->bool:return _selection.selected==[leaders[group-1]] and _hud.call("get_secondary_surface_name")=="none")
		var camera_before: Vector2=_map.camera.position
		var minimap: Control=_hud.get("minimap_rect")
		var map_point: Vector2=minimap.get_global_rect().position+minimap.size*Vector2(0.65 if repeat%2==0 else 0.25,0.65 if repeat%2==0 else 0.25)
		await _measured_tap("Minimap jump",map_point,func()->bool:return _map.camera.position.distance_to(camera_before)>20)
		await _measured_tap("Base select",overview.rail.get_node("BaseButton").get_global_rect().get_center(),func()->bool:return tc in _selection.selected)
		if physical.x>=1000:
			await _measured_key("Keyboard group",KEY_1,func()->bool:return _selection.selected==[leaders[0]])
			await _action("select_all_military")
			_expect(_selection.selected.size()>1,"M selects current fighters")
			await _action("find_army")
		for index: int in 2:
			_expect(leaders[index].move_target.is_equal_approx(last_goals[index]),"navigation preserves accepted front destination")
		await get_tree().create_timer(0.7).timeout
	var moved: int=0
	var hurt: int=0
	for index: int in armies.size():
		var actor: UnitBase=armies[index]
		if not is_instance_valid(actor):
			hurt+=1
			continue
		if actor.global_position.distance_to(initial_positions[index])>10:moved+=1
		if actor.hp<actor.max_hp:hurt+=1
	_expect(moved>0,"unselected fronts continue moving")
	var switching: Array[Dictionary]=[]
	for iteration: int in 10:
		for target: Node2D in [leaders[0],tc]:
			var start: int=Time.get_ticks_usec()
			_selection.select_single(target)
			switching.append({"context":"base" if target==tc else "unit","synchronous_ms":float(Time.get_ticks_usec()-start)/1000.0})
	var methods: Array[Dictionary]=[]
	for entry: Array in [[_hud,"_refresh_command_icons",[]],[_hud,"_apply_mobile_layout_for_current_viewport",[]],[_hud,"_refresh_touch_target_diagnostics",[]],[_hud,"_refresh_primary_action_visuals",[]],[_main,"_on_selection_changed",[_selection.selected]],[_main,"_update_progression_hint",[]],[_main,"_refresh_unit_command_hud",[]],[_hud,"_update_train_buttons",[tc.trainable_units]],[_hud,"_update_research_buttons",[tc]],[_hud,"_update_queue_display",[tc.get_production_queue().get_queue_info()]],[_hud,"_refresh_auto_queue_button",[tc.get_production_queue()]],[_hud,"_hide_unit_commands",[]],[_hud,"_refresh_unit_selection_details",[]]]:
		var timings: Array[float]=[]
		for iteration: int in 5:
			var start: int=Time.get_ticks_usec()
			entry[0].callv(entry[1],entry[2])
			timings.append(float(Time.get_ticks_usec()-start)/1000.0)
		methods.append({"method":entry[1],"ms":timings})
	_world_records.append({"profile":_profile,"fronts":2,"staged_fighters":armies.size()+leaders.size(),"elapsed_sim_seconds":GameManager.game_time-start_game_time,"moved_units":moved,"damaged_or_dead":hurt,"town_queue":tc.get_production_queue().get_queue_size(),"queued_workers_paid":3,"initial_worker_jobs":worker_jobs,"live_worker_states":workers.map(func(worker:Villager)->int:return worker.current_state),"selection_context_microprobe":switching,"method_microprobe":methods,"local_process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0})
	_main.free()
	_main=null
	_hud=null
	GameManager.set_state(GameManager.GameState.MENU)
	await _frames(2)

func _audit_ground(unit: UnitBase) -> Vector2:
	var origin: Vector2i=_map.world_to_tile(unit.global_position)
	var safe: Rect2=_hud.call("get_world_safe_rect")
	var obstacles: Array=_hud.call("get_world_occlusion_rects")
	for radius: int in range(2,8):
		for y: int in range(-radius,radius+1):
			for x: int in range(-radius,radius+1):
				var tile:=origin+Vector2i(x,y)
				if not _map.is_tile_walkable(tile) or not _map.is_tile_visible_to_player(tile,0):continue
				var world: Vector2=_map.tile_to_world(tile)
				var screen: Vector2=get_viewport().get_canvas_transform()*world
				var blocked: bool=not safe.has_point(screen)
				for obstacle: Rect2 in obstacles:
					if obstacle.grow(3).has_point(screen):blocked=true
				if not blocked and world.distance_to(unit.global_position)>40 and not _map.get_navigation_world_path(unit.global_position,world).is_empty():return screen
	return Vector2.ZERO

func _measured_tap(label: String,point: Vector2,accepted: Callable) -> void:
	_contact_id+=1
	var event:=InputEventScreenTouch.new()
	event.index=_contact_id
	event.position=get_viewport().get_final_transform()*point
	event.pressed=true
	var down: int=Time.get_ticks_usec()
	Input.parse_input_event(event)
	await _frames(1)
	event=event.duplicate()
	event.pressed=false
	var released: int=Time.get_ticks_usec()
	Input.parse_input_event(event)
	var frames: int=0
	while not accepted.call() and frames<12:
		await _frames(1)
		frames+=1
	_samples.append({"profile":_profile,"action":label,"accepted":bool(accepted.call()),"release_to_accept_ms":float(Time.get_ticks_usec()-released)/1000.0,"total_contact_ms":float(Time.get_ticks_usec()-down)/1000.0,"frames_after_release":frames})
	_expect(bool(accepted.call()),label+" accepted within12frames")
	await _frames(2)

func _measured_key(label: String,keycode: int,accepted: Callable) -> void:
	var event:=InputEventKey.new()
	event.keycode=keycode
	event.pressed=true
	var began: int=Time.get_ticks_usec()
	Input.parse_input_event(event)
	var frames: int=0
	while not accepted.call() and frames<12:
		await _frames(1)
		frames+=1
	_samples.append({"profile":_profile,"action":label,"accepted":bool(accepted.call()),"release_to_accept_ms":float(Time.get_ticks_usec()-began)/1000.0,"frames_after_release":frames})
	event=event.duplicate()
	event.pressed=false
	Input.parse_input_event(event)
	_expect(bool(accepted.call()),label+" accepted")
