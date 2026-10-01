extends Node
## Real engine mouse→touch emulation must not suppress a native right command.
## Synthetic Range fixture; this is input/rally evidence, not a paid match.
var _failures: Array[String] = []
var _events: Array[Dictionary] = []
var _profiles: Array[Dictionary] = []
var _world_orders: int = 0

func _ready() -> void:
	call_deferred("_run")

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		_events.append({"class":event.get_class(),"device":event.device,"pressed":event.pressed,"button":event.button_index if event is InputEventMouseButton else 0})

func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_touch_from_mouse = true
	Input.emulate_mouse_from_touch = true
	for phone: Vector2i in [Vector2i(844,390),Vector2i(932,430)]:
		for scale_factor: float in [1.0,1.075]:
			await _profile(phone,scale_factor)
	for failure: String in _failures:
		push_error("[FAIL] mouse_right_after_emulated_touch: "+failure)
	var evidence := FileAccess.open("res://output/rts-iteration-2026-09-30/mouse-right-emulation-evidence.json",FileAccess.WRITE)
	evidence.store_string(JSON.stringify({"fixture":"Production Main with synthetic Range, actual Input.parse native mouse through engine mouse→touch emulation. Not physical hardware or paid match.","selection_sha256":FileAccess.get_sha256("res://scripts/managers/selection_manager.gd"),"profiles":_profiles,"failures":_failures},"  "))
	if _failures.is_empty():
		print("[PASS] mouse_right_after_emulated_touch: four actual Window profiles; engine-generated device-1 touches from native left select; immediate native right rally once; generated mouse duplicates/HUD touch guarded")
	get_tree().quit(0 if _failures.is_empty() else 1)

func _profile(phone: Vector2i,scale_factor: float) -> void:
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844,390)
	get_window().content_scale_factor = scale_factor
	GameManager.guided_opening_enabled = false
	GameManager.selected_population_limit = 30
	GameManager.selected_map_seed = 101
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement")!=null and GameManager.current_state==GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	var map: Node2D = main.get_node("GameMap")
	var selection: SelectionManager = map.get_node("SelectionManager")
	var hud: CanvasLayer = main.get_node("HUD")
	var range_tile: Vector2i = map.map_generator.spawn_positions[0]+Vector2i(5,5)
	var producer: BuildingBase = main.call("_spawn_building",BuildingData.BuildingType.ARCHERY_RANGE,0,range_tile)
	producer.state = BuildingBase.State.ACTIVE
	map.camera.position = producer.global_position
	map.camera.reset_smoothing()
	map.camera.force_update_scroll()
	main.call("_update_fog_of_war")
	selection.move_command.connect(func(_tile: Vector2i) -> void: _world_orders+=1)
	await _settle()
	var profile := "%s scale%.3f" % [phone,scale_factor]
	var target_tile: Vector2i = range_tile+Vector2i(3,-1)
	_expect(map.is_tile_walkable(target_tile),profile+" target fixture is blocked")
	var select_screen: Vector2 = selection.call("_world_to_screen",producer.global_position)
	var target_screen: Vector2 = selection.call("_world_to_screen",map.tile_to_world(target_tile))
	_expect(get_viewport().get_visible_rect().has_point(target_screen),profile+" target is outside Window")
	_events.clear()
	var before: int = _world_orders
	await _mouse(select_screen,MOUSE_BUTTON_LEFT,0)
	_expect(selection.selected.size()==1 and selection.selected[0]==producer,profile+" native left did not select Range")
	var generated_touches: int = 0
	for event: Dictionary in _events:
		if event["class"]=="InputEventScreenTouch" and event["device"]==InputEvent.DEVICE_ID_EMULATION:
			generated_touches+=1
	_expect(generated_touches==2,profile+" did not receive engine-generated left→touch press/release")
	_expect(Time.get_ticks_msec()-int(selection.get("_last_touch_input_msec"))<1500,profile+" does not test recent-touch interval")
	await _mouse(target_screen,MOUSE_BUTTON_RIGHT,0)
	var immediate: bool = producer.has_custom_rally_point() and producer.rally_point.is_equal_approx(map.tile_to_world(target_tile))
	_expect(immediate,profile+" immediate native right was lost after emulated left selection")
	_expect(_world_orders==before+1,profile+" immediate right command must dispatch exactly once")
	# If reproducing the old regression, establish that the same target works
	# after its timer rather than mistaking target legality for input suppression.
	if not immediate:
		await get_tree().create_timer(1.6).timeout
		await _mouse(target_screen,MOUSE_BUTTON_RIGHT,0)
		_expect(producer.has_custom_rally_point(),profile+" delayed control right-click also failed")
	var post_native: int = _world_orders
	await _mouse(target_screen,MOUSE_BUTTON_RIGHT,InputEvent.DEVICE_ID_EMULATION)
	_expect(_world_orders==post_native,profile+" synthesized right mouse duplicate ordered world")
	# Natural ScreenTouch creates a left-mouse duplicate. A GUI-owned touch
	# must not become an order or a selection change at its generated release.
	before = _world_orders
	var back: Button = hud.get("_selection_back_button")
	await _touch(back.get_global_rect().get_center())
	_expect(selection.selected.is_empty(),profile+" HUD Back touch did not clear")
	_expect(_world_orders==before,profile+" GUI touch/generated mouse ordered world")
	# A native ScreenTouch also produces real engine left-mouse emulation.
	# It must move a selected worker once and retain that selection.
	var worker: Villager = main.get("_player_units")[0][0]
	selection.select_single(worker)
	await _settle()
	before = _world_orders
	await _touch(target_screen)
	_expect(_world_orders==before+1,profile+" natural touch/generated left mouse did not order exactly once")
	_expect(selection.selected.size()==1 and selection.selected[0]==worker,profile+" generated left mouse changed world selection")
	_profiles.append({"phone":str(phone),"scale":scale_factor,"logical_viewport":str(get_viewport().get_visible_rect().size),"engine_generated_left_to_touch_events":generated_touches,"immediate_native_right_rally":immediate,"input_event_devices":_events.duplicate(true)})
	print("Mouse emulation profile: ",profile," actual events=",JSON.stringify(_events)," immediate_rally=",immediate," orders=",post_native)
	main.free()
	await get_tree().process_frame

func _mouse(logical: Vector2,button: int,device_id: int) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.device = device_id
		event.position = get_viewport().get_final_transform()*logical
		event.global_position = event.position
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
	await _settle()

func _touch(logical: Vector2) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventScreenTouch.new()
		event.position = get_viewport().get_final_transform()*logical
		event.index = 0
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
	await _settle()

func _settle() -> void:
	for frame: int in 4:
		await get_tree().process_frame

func _expect(condition: bool,message: String) -> void:
	if not condition:
		_failures.append(message)
