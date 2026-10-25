extends Node
## Native rendering audit with synthetic armies and ordinary live combat.
## This fixture alone removes background pause so an offscreen window can run.
var output: String = ""
var samples: Array[Dictionary] = []
var frames: Array[float] = []
var process_times: Array[float] = []
var physics_times: Array[float] = []
var render_objects: Array[float] = []
var active: bool = false
var previous_usec: int = 0
var main: Node
var contact: int = 100
var responses: Array[Dictionary] = []
var observer_disabled: bool = false

func _ready() -> void:
	_run.call_deferred()

func _process(_delta: float) -> void:
	var now: int=Time.get_ticks_usec()
	if active and previous_usec>0:
		frames.append(float(now-previous_usec)/1000.0)
		process_times.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		physics_times.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		render_objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	previous_usec=now

func _run() -> void:
	output=OS.get_environment("AOEM_BUSY_OUTPUT")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch=true
	GameManager.guided_opening_enabled=false
	GameManager.selected_population_limit=100
	GameManager.selected_map_seed=101
	GameManager.selected_map_archetype=MapData.MapArchetype.OPEN_PLAINS
	GameManager.ui_scale=1.0
	Engine.time_scale=1.0
	get_window().size=Vector2i(1280,720)
	get_window().content_scale_size=Vector2i(1280,720)
	var cases: Array[int]=[50,100]
	if OS.get_environment("AOEM_BUSY_AB")=="1":cases=[100,100]
	for index: int in cases.size():
		observer_disabled=OS.get_environment("AOEM_BUSY_AB")=="1" and index==1
		await _case(cases[index])
	var report: Dictionary={"scope":"Native offscreen1280x720 Compatibility rendering, 5s warmup+20s wall per case, synthetic50+50/100+100 armies plus normal starting actors, real live movement/combat. Background lifecycle pause bypassed only by fixture. Desktop CPU/GPU evidence, not physical phone or browser/network latency.","renderer":RenderingServer.get_video_adapter_name(),"samples":samples}
	if not output.is_empty():FileAccess.open(output.path_join("native-busy-front.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("[NATIVE BUSY] "+JSON.stringify(report))
	get_tree().quit(0)

func _case(per_owner: int) -> void:
	GameManager.set_state(GameManager.GameState.MENU)
	main=load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement")!=null:break
		await get_tree().process_frame
	var guard: Node=main.get("_match_background_guard")
	if is_instance_valid(guard):
		guard.background_changed.disconnect(main._on_match_background_changed)
		guard.queue_free()
		main.set("_match_background_guard",null)
	if GameManager.current_state==GameManager.GameState.PAUSED:main.call("_on_resume_requested")
	main.ai_controller.set_process(false)
	main.ai_controller.get("_decision_timer").stop()
	var map: Node2D=main.game_map
	if observer_disabled:
		map.get_node("UnitOcclusionOverlay").queue_free()
		await get_tree().process_frame
	var actors: Array[UnitBase]=[]
	for owner: int in 2:
		GameManager.players[owner].max_population=250
		GameManager.grant_population_cap(owner,98000+owner,250)
		for index: int in per_owner:
			var tile:=Vector2i(30+owner*18+index%8,32+index/8)
			var type: int=UnitData.UnitType.INFANTRY if index%10<6 else UnitData.UnitType.ARCHER if index%10<9 else UnitData.UnitType.CAVALRY
			var unit: UnitBase=main.call("_spawn_unit",type,owner,_walkable(tile))
			actors.append(unit)
			unit.command_attack_move(_walkable(Vector2i(42,38)))
	var scout: UnitBase=main.call("_spawn_unit",UnitData.UnitType.SCOUT,0,_walkable(Vector2i(39,26)))
	main.call("_update_fog_of_war")
	map.note_camera_interaction()
	map.set("_user_zoom_override",true)
	map.camera.zoom=Vector2(0.85,0.85)
	map.camera.position=map.tile_to_world(Vector2i(41,35))
	map.camera.reset_smoothing()
	map.camera.force_update_scroll()
	await get_tree().create_timer(5.0).timeout
	frames.clear()
	process_times.clear()
	physics_times.clear()
	render_objects.clear()
	responses.clear()
	active=true
	var began: int=Time.get_ticks_msec()
	var sim_start: float=GameManager.game_time
	var observed: Array[Dictionary]=[]
	for sample_index: int in 4:
		var before: int=Time.get_ticks_msec()
		await _response(scout,sample_index)
		var alive: int=0
		var fighting: int=0
		var hurt: int=0
		for actor: UnitBase in actors:
			if not is_instance_valid(actor):continue
			if actor.current_state!=UnitBase.State.DEAD:alive+=1
			if actor.current_state==UnitBase.State.ATTACKING:fighting+=1
			if actor.hp<actor.max_hp:hurt+=1
		observed.append({"wall_seconds":float(Time.get_ticks_msec()-began)/1000.0,"alive":alive,"fighting":fighting,"hurt":hurt})
		if not output.is_empty() and sample_index==1:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(output.path_join("native-%d-vs-%d.png" % [per_owner,per_owner]))
		var remaining: float=maxf(0.0,5.0-float(Time.get_ticks_msec()-before)/1000.0)
		await get_tree().create_timer(remaining).timeout
	active=false
	samples.append({"per_owner":per_owner,"observer_disabled":observer_disabled,"sampled_wall_seconds":float(Time.get_ticks_msec()-began)/1000.0,"sim_seconds":GameManager.game_time-sim_start,"frames":_stats(frames),"process_ms":_stats(process_times),"physics_ms":_stats(physics_times),"render_object_counts":_stats(render_objects),"actor_observations":observed,"input":responses.duplicate(true)})
	main.free()
	await get_tree().process_frame

func _walkable(tile: Vector2i) -> Vector2:
	for radius: int in 8:
		for y: int in range(-radius,radius+1):
			for x: int in range(-radius,radius+1):
				var candidate:=tile+Vector2i(x,y)
				if main.game_map.is_tile_walkable(candidate):return main.game_map.tile_to_world(candidate)
	return main.game_map.tile_to_world(tile)

func _response(scout: UnitBase,index: int) -> void:
	if not is_instance_valid(scout):return
	var selection: SelectionManager=main.game_map.selection_mgr
	selection.deselect_all()
	await _tap("select",get_viewport().get_canvas_transform()*scout.global_position,func()->bool:return selection.selected==[scout])
	await _tap("Move arm",main.hud.get("_unit_move_button").get_global_rect().get_center(),func()->bool:return bool(main.get("_move_command_armed")))
	var target: Vector2=_walkable(Vector2i(39+index%2*3,26))
	await _tap("Move accept",get_viewport().get_canvas_transform()*target,func()->bool:return not bool(main.get("_move_command_armed")) and scout.current_state==UnitBase.State.MOVING)

func _tap(label: String,point: Vector2,accepted: Callable) -> void:
	contact+=1
	var event:=InputEventScreenTouch.new()
	event.index=contact
	event.position=get_viewport().get_final_transform()*point
	event.pressed=true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event=event.duplicate()
	event.pressed=false
	var start: int=Time.get_ticks_usec()
	Input.parse_input_event(event)
	var count: int=0
	while not accepted.call() and count<12:
		await get_tree().process_frame
		count+=1
	responses.append({"action":label,"accepted":bool(accepted.call()),"release_to_accept_ms":float(Time.get_ticks_usec()-start)/1000.0,"frames":count})
	for frame: int in 2:await get_tree().process_frame

func _stats(values: Array[float]) -> Dictionary:
	var sorted: Array[float]=values.duplicate()
	sorted.sort()
	if sorted.is_empty():return {}
	var total: float=0
	for value: float in sorted:total+=value
	return {"count":sorted.size(),"mean":total/sorted.size(),"p50":sorted[sorted.size()/2],"p95":sorted[mini(sorted.size()-1,int(sorted.size()*0.95))],"max":sorted.back()}
