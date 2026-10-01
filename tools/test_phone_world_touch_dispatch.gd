extends Node
## Actual engine touch dispatch with browser-style nonzero contact identities.
## Real Main/HUD/navigation; AI and other workers pause to isolate input.

var _failures: Array[String] = []
var _records: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _main: Node
var _map: Node2D
var _selection: SelectionManager
var _hud: CanvasLayer
var _worker: Villager
var _profile: String
var _orders: int = 0
var _consume_release_index: int = -1

func _ready() -> void:
	call_deferred("_run")

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_events.append({"index":event.index,"pressed":event.pressed,"canceled":event.canceled,"position":str(event.position)})
		if not event.pressed and event.index==_consume_release_index:
			# Explicit diagnostic consumer: real dispatch stops before unhandled
			# input, exercising cleanup when a modal/GUI owns a late release.
			get_viewport().set_input_as_handled()

func _run() -> void:
	AudioManager.set_all_enabled(false)
	for phone: Vector2i in [Vector2i(844,390),Vector2i(932,430)]:
		for interface_scale: float in [1.0,1.075]:
			for mouse_emulation: bool in [false,true]:
				await _scenario(phone,interface_scale,mouse_emulation)
	var record := FileAccess.open("res://output/phone-input-2026-10-01/selection/dispatch-evidence.json",FileAccess.WRITE)
	record.store_string(JSON.stringify({"scope":"Actual Input.parse_input_event world/HUD touch routing, real Main and natural movement; no private input handler calls or injected worker positions.","profiles":_records,"failures":_failures},"  "))
	for failure: String in _failures:
		push_error("[FAIL] phone_world_touch_dispatch: "+failure)
	if _failures.is_empty():
		print("[PASS] phone_world_touch_dispatch: eight phone/UI/emulation profiles, real nonzero selection/natural Move/HUD Move, sticky multi-contact release ownership, canceled/GUI/unknown contacts, modal cleanup and exactly-once nonzero long press")
	get_tree().quit(0 if _failures.is_empty() else 1)

func _scenario(phone: Vector2i, interface_scale: float, mouse_emulation: bool) -> void:
	_profile="%dx%d-%s-mouse%s" % [phone.x,phone.y,"large" if interface_scale>1.0 else "standard",mouse_emulation]
	get_window().size=phone
	get_window().content_scale_size=Vector2i(844,390)
	get_window().content_scale_factor=interface_scale
	Input.emulate_mouse_from_touch=mouse_emulation
	Input.emulate_touch_from_mouse=true
	GameManager.guided_opening_enabled=false
	GameManager.selected_map_seed=101
	GameManager.selected_population_limit=30
	GameManager.set_state(GameManager.GameState.MENU)
	_main=load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for frame: int in range(900):
		if _main.get("_building_placement")!=null and GameManager.current_state==GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	_map=_main.get("game_map")
	_selection=_map.get("selection_mgr")
	_hud=_main.get("hud")
	_main.get("ai_controller").set_process(false)
	_main.get("ai_controller").get("_decision_timer").stop()
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	_worker=_main.get("_player_units")[0][0] as Villager
	_worker.command_stop()
	_orders=0
	_events.clear()
	_selection.move_command.connect(func(_tile: Vector2i) -> void: _orders+=1)
	# An earlier menu/HUD gesture used another ID; web contacts need not be0.
	await _tap(7,(_hud.get("_town_center_button") as Button).get_global_rect().get_center())
	if mouse_emulation:
		_expect(_selection.selected.size()==1 and _selection.selected[0] is BuildingBase,"nonzero Home touch must select TC through GUI")
	_expect(_orders==0 and _selection.get("_active_touch_indices").is_empty(),"GUI touch leaked a world order or owned contact")
	_selection.deselect_all()
	(_map.get("camera") as Camera2D).position=_worker.global_position
	await get_tree().process_frame
	await get_tree().process_frame
	var screen: Vector2=get_viewport().get_canvas_transform()*_worker.global_position
	await _tap(8,screen)
	var selected: bool=_selection.selected.size()==1 and _selection.selected[0]==_worker
	_expect(selected,"sole world contact8 did not select actual worker after GUI contact7")
	var ground: Vector2=_find_empty_ground()
	_expect(ground!=Vector2.ZERO,"no currently visible reachable empty ground in the world area")
	var position_before: Vector2=_worker.global_position
	await _tap(19,ground)
	_expect(_orders==1 and _worker.current_state==UnitBase.State.MOVING,"nonzero ground contact must issue exactly one accepted Move")
	_worker.set_process(true)
	await _wait_sim_seconds(0.5)
	var natural_distance: float=position_before.distance_to(_worker.global_position)
	_expect(natural_distance>10.0,"routed ground Move did not naturally walk the worker")
	_worker.command_stop()
	_worker.set_process(false)
	var move_button: Button=(_hud.get("_unit_command_container") as HBoxContainer).get_node("UnitMoveButton") as Button
	var stop_button: Button=(_hud.get("_unit_command_container") as HBoxContainer).get_node("UnitStopButton") as Button
	if mouse_emulation:
		var before_hud: int=_orders
		await _tap(23,move_button.get_global_rect().get_center())
		_expect(bool(_main.get("_move_command_armed")) and _orders==before_hud,"nonzero GUI Move contact must arm without a world order")
		await _tap(27,ground)
		_expect(_orders==before_hud+1 and not bool(_main.get("_move_command_armed")) and bool(_worker.get("_force_move_active")),"nonzero destination did not consume HUD Move exactly once")
		_worker.command_stop()
	# Two genuine world contacts must suppress selection/orders regardless of
	# which identity releases first. One surviving finger never becomes a tap.
	for primary_first: bool in [true,false]:
		var before_pinch: int=_orders
		await _contact(31,ground,true)
		await _contact(44,ground+Vector2(40,0),true)
		_expect(int(_selection.get("_primary_touch_index"))==31 and bool(_selection.get("_touch_pan_gesture")),"secondary press did not latch the actual primary gesture")
		await _contact(31 if primary_first else 44,ground,false)
		_expect(bool(_selection.get("_touch_pan_gesture")),"first pinch release lost suppression while another contact remained")
		await _contact(44 if primary_first else 31,ground,false)
		_expect(_orders==before_pinch,"pinch releases issued a late world order")
		_expect_clean("pinch")
	# Real GUI-origin press/drag/release must remain GUI-owned, even off GUI.
	var before_gui: int=_orders
	await _contact(57,stop_button.get_global_rect().get_center(),true)
	await _drag(57,ground,Vector2(-80,-80))
	await _contact(57,ground,false)
	await _drag(58,ground,Vector2(20,0))
	await _contact(58,ground,false)
	_expect(_orders==before_gui,"GUI-origin or unknown drag/release issued a world order")
	_expect_clean("GUI/unknown")
	# Simulate release consumption through actual engine routing; no private
	# SelectionManager input callback is invoked by the fixture.
	for consumed_primary: bool in [true,false]:
		var before_consumed: int=_orders
		await _contact(61,ground,true)
		await _contact(72,ground+Vector2(40,0),true)
		_consume_release_index=61 if consumed_primary else 72
		await _contact(_consume_release_index,ground,false)
		_consume_release_index=-1
		_expect(bool(_selection.get("_touch_pan_gesture")),"consumed release lost the multi-touch ownership latch")
		await _contact(72 if consumed_primary else 61,ground,false)
		await _wait_sim_seconds(0.42)
		_expect(_orders==before_consumed,"consumed pinch release produced an order or delayed context")
		_expect_clean("consumed pinch release")
	var before_cancel: int=_orders
	await _contact(81,ground,true)
	await _contact(81,ground,false,true)
	await _contact(91,ground,true)
	_selection.cancel_touch_gesture()
	await _contact(91,ground,false)
	_expect(_orders==before_cancel,"OS/modal cancellation produced a world tap")
	_expect_clean("cancellation")
	# Before deferred cleanup runs, a newly admitted contact is still owned.
	for fresh_index: int in [101,103]:
		_send_contact(101,ground,true)
		_send_contact(101,ground,false,true)
		_send_contact(fresh_index,ground,true)
		await _frames(2)
		_expect(int(_selection.get("_primary_touch_index"))==fresh_index and bool(_selection.get("_touch_hold_active")),"old release cleanup canceled a fresh contact")
		await _contact(fresh_index,ground,false,true)
		_expect_clean("fresh contact")
	var context_before: int=int(_selection.get("_touch_context_execution_count"))
	var orders_before_hold: int=_orders
	await _contact(119,ground,true)
	await _wait_sim_seconds(0.42)
	_expect(_orders==orders_before_hold+1 and int(_selection.get("_touch_context_execution_count"))==context_before+1,"nonzero long press did not execute the single ground Move exactly once")
	await _contact(119,ground,false)
	_expect(_orders==orders_before_hold+1,"nonzero long-press release repeated the action")
	_expect_clean("long press")
	var orders_before_hold_pinch: int=_orders
	await _contact(127,ground,true)
	await _wait_sim_seconds(0.42)
	await _contact(139,ground+Vector2(40,0),true)
	await _contact(127,ground,false)
	_expect(bool(_selection.get("_touch_pan_gesture")),"already executed long press lost the later multi-touch latch")
	await _contact(139,ground,false)
	_expect(_orders==orders_before_hold_pinch+1,"long-press-then-pinch release repeated a world order")
	_expect_clean("long press then pinch")
	_records.append({"profile":_profile,"emulated_mouse":mouse_emulation,"screen":str(screen),"ground":str(ground),"final_transform":str(get_viewport().get_final_transform()),"selected_nonzero":selected,"natural_move_distance":natural_distance,"world_orders":_orders,"touches":_events.duplicate(true),"diagnostics":_selection.touch_input_diagnostics.duplicate(true)})
	_main.free()
	await get_tree().process_frame

func _tap(index: int, viewport_position: Vector2) -> void:
	for pressed: bool in [true,false]:
		await _contact(index,viewport_position,pressed)

func _send_contact(index: int, viewport_position: Vector2, pressed: bool, canceled: bool=false) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index=index
	touch.position=get_viewport().get_final_transform()*viewport_position
	touch.pressed=pressed
	touch.canceled=canceled
	Input.parse_input_event(touch)

func _contact(index: int, viewport_position: Vector2, pressed: bool, canceled: bool=false) -> void:
	_send_contact(index,viewport_position,pressed,canceled)
	await _frames(2)

func _drag(index: int, viewport_position: Vector2, relative: Vector2) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index=index
	drag.position=get_viewport().get_final_transform()*viewport_position
	drag.relative=get_viewport().get_final_transform().basis_xform(relative)
	Input.parse_input_event(drag)
	await _frames(2)

func _frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame

func _wait_sim_seconds(seconds: float) -> void:
	var deadline: float=GameManager.game_time+seconds
	var wall_deadline: int=Time.get_ticks_msec()+2000
	while GameManager.game_time<deadline and Time.get_ticks_msec()<wall_deadline:
		await get_tree().process_frame
	_expect(GameManager.game_time>=deadline,"bounded input observation did not reach its simulated duration")

func _find_empty_ground() -> Vector2:
	var view: Rect2=get_viewport().get_visible_rect()
	var safe_world_area := Rect2(Vector2(150,100),view.size-Vector2(290,240))
	var tile: Vector2i=_map.world_to_tile(_worker.global_position)
	for radius: int in range(2,9):
		for dy: int in range(-radius,radius+1):
			for dx: int in range(-radius,radius+1):
				var candidate: Vector2i=tile+Vector2i(dx,dy)
				if not _map.is_tile_walkable(candidate) or not _map.is_tile_visible_to_player(candidate,0):
					continue
				var world: Vector2=_map.tile_to_world(candidate)
				var screen: Vector2=get_viewport().get_canvas_transform()*world
				if not safe_world_area.has_point(screen) or world.distance_to(_worker.global_position)<64.0:
					continue
				if _selection.call("_get_node_at",world,true)!=null or _selection.call("_get_resource_at",world,true)!=null:
					continue
				if not _map.get_navigation_world_path(_worker.global_position,world).is_empty():
					return screen
	return Vector2.ZERO

func _expect_clean(context: String) -> void:
	_expect(_selection.get("_active_touch_indices").is_empty() and _selection.get("_released_world_touch_indices").is_empty() and int(_selection.get("_primary_touch_index"))==-1 and not bool(_selection.get("_touch_hold_active")),context+" left stale owned contacts or a hold")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(_profile+": "+message)
