extends "res://tools/test_ux_redesign_journey.gd"
## Paid real ScreenTouch journey for hold inspection, chooser and disclosure.

func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	GameManager.hold_shortcuts_enabled = true
	for phone: Vector2i in [Vector2i(844,390), Vector2i(932,430)]:
		for interface_scale: float in [1.0,1.075,1.15]:
			for notched: bool in [false,true]:
				await _hold_journey(phone,interface_scale,notched)
	_expect(_receipts.size()==12,"all twelve profiles must complete the full paid journey")
	var folder: String = OS.get_environment("AOEM_CAPTURE_UX_DIR")
	if not folder.is_empty():
		FileAccess.open(folder.path_join("hold-input-receipt.json"),FileAccess.WRITE).store_string(JSON.stringify({"scope":"Actual ScreenTouch dispatch and paid initial bank; twelve phone/scale/safe profiles. No physical device claim.","profiles":_receipts,"failures":_failures},"  "))
	for failure: String in _failures:
		push_error("[FAIL] mobile_hold_journey: " + failure)
	if _failures.is_empty():
		print("[PASS] mobile_hold_journey: twelve profiles, inspection without spending, normal paid taps, contextual chooser cancellation and commands, deterministic collapse, no world leakage")
	get_tree().quit(0 if _failures.is_empty() else 1)

func _hold_journey(phone: Vector2i,interface_scale: float,notched: bool) -> void:
	_profile = "%dx%d-scale%.3f-%s" % [phone.x,phone.y,interface_scale,"notched" if notched else "ordinary"]
	_synthetic_notch = notched
	_hud = null
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844,390)
	GameManager.ui_scale = interface_scale
	get_window().content_scale_factor = GameManager.ui_scale
	GameManager.selected_map_seed = 101
	GameManager.selected_population_limit = 30
	GameManager.guided_opening_enabled = false
	await _frames(3)
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for frame: int in range(900):
		if _main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	_map = _main.get_node("GameMap")
	_hud = _main.get_node("HUD")
	_selection = _map.get("selection_mgr")
	_main.set_process(false)
	_main.get_node("AIController").set_process(false)
	_main.get_node("AIController").get("_decision_timer").stop()
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	var logical: Vector2 = get_viewport().get_visible_rect().size
	var inset: Vector2 = Vector2(44,18) * logical / Vector2(phone) if notched else Vector2.ZERO
	var safe := Rect2(Vector2(inset.x,0),logical - Vector2(inset.x*2,inset.y))
	_hud.call("apply_mobile_layout",logical,safe)
	_main.get("_build_menu").call("set_safe_area_rect",safe)
	await _frames(6)
	_main.call("_update_fog_of_war")
	_main.call("_update_minimap")
	_orders = 0
	_selection.move_command.connect(func(_tile: Vector2i) -> void: _orders += 1)
	await _button(_hud.call("get_base_navigation_button"))
	var tc: BuildingBase = _hud.get("_selected_building_ref")
	_expect(tc != null,"Home did not select owned TC")
	if tc == null:
		_main.free()
		return

	var bank: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	var train: Button = _hud.get("_train_buttons_container").get_node("TrainButton_0")
	var queue: ProductionQueue = tc.get_production_queue()
	await _hold_inspect(train,"train-info")
	_expect(queue.get_queue_size()==0 and ResourceManager.get_all_resources(0)==bank,"Train inspect spent resources")
	await _button(train)
	_expect(queue.get_queue_size()==1,"normal Train tap no longer buys a worker")
	await _button(_hud.get("_queue_navigation_button"))
	await _capture("queue-open")
	await _hold_inspect(_hud.get("queue_container").get_node("QueueClearAllButton"),"refund-info")
	_expect(queue.get_queue_size()==1,"holding refund canceled paid unit")
	await _button(_hud.get("_camera_view_button"))
	_expect(not bool(_hud.get("_queue_view_requested")),"View failed to collapse Queue")
	await _button(_hud.get("_camera_zoom_out_button"))
	_expect(bool(_hud.get("_camera_controls_expanded")),"consecutive zoom collapsed View")
	await _button(_hud.get("_camera_center_button"))
	_expect(not bool(_hud.get("_camera_controls_expanded")),"Center failed to collapse View")
	await _button(_hud.get("_queue_navigation_button"))
	await _button(_hud.get("queue_container").get_node("QueueClearAllButton"))
	_expect(queue.get_queue_size()==0 and ResourceManager.get_all_resources(0)==bank,"paid queue refund changed")
	await _button(_hud.get("_selection_back_button"))
	await _button(_hud.get("build_menu_button"))
	var palette: Node = _main.get("_build_menu")
	await _hold_inspect(palette.get("_button_map")[BuildingData.BuildingType.HOUSE],"build-info")
	_expect(not bool(_main.get("_placement_active")) and ResourceManager.get_all_resources(0)==bank,"Build inspect entered placement or spent")
	await _button(palette.get("_category_buttons")["Army"])
	var locked_card: Button = palette.get("_button_map")[BuildingData.BuildingType.STABLE]
	_expect(locked_card.disabled,"locked-card fixture should require Feudal")
	await _scroll_card_into_view(locked_card)
	await _hold_inspect(locked_card,"locked-build-info")
	_expect(not bool(_main.get("_placement_active")) and ResourceManager.get_all_resources(0)==bank,"locked Build hold mutated state")
	GameManager.hold_shortcuts_enabled = false
	await _button(palette.get("_info_button"))
	_expect(not locked_card.disabled,"tap Info mode did not make locked card inspectable")
	await _button(locked_card)
	_expect(str(_hud.call("get_secondary_surface_name"))=="info" and palette.visible,"tap Build Info failed to preserve palette")
	_expect(not bool(_main.get("_placement_active")) and ResourceManager.get_all_resources(0)==bank,"tap Build Info placed or spent")
	await _capture("tap-build-info")
	await _button(_hud.get("_info_panel").find_child("InfoCloseButton",true,false))
	_expect(str(_hud.call("get_secondary_surface_name"))=="none" and palette.visible,"Info Close dismissed Build too")
	await _button(palette.get("_info_button"))
	_expect(locked_card.disabled,"leaving tap Info mode unlocked placement")
	GameManager.hold_shortcuts_enabled = true
	# Build outside dismissal owns press, subsequent drag and release.
	var outside := Vector2(get_viewport().get_visible_rect().size.x*0.5,105)
	_contact_id += 1
	await _touch_contact(outside,true,_contact_id)
	_expect(not palette.visible,"outside press failed to dismiss Build")
	var drag := InputEventScreenDrag.new()
	drag.index = _contact_id
	drag.position = get_viewport().get_final_transform()*(outside+Vector2(40,0))
	drag.relative = Vector2(40,0)
	Input.parse_input_event(drag)
	await _touch_contact(outside+Vector2(40,0),false,_contact_id)
	_expect(_orders==0 and _selection.selected.is_empty(),"Build dismissal leaked selection/order")
	var worker: Villager = _main.get("_player_units")[0][0]
	worker.command_stop()
	var camera: Camera2D = _map.get("camera")
	camera.position = worker.global_position
	camera.reset_smoothing()
	camera.force_update_scroll()
	await _frames(4)
	await _tap(get_viewport().get_canvas_transform()*worker.global_position)
	_expect(_selection.selected.size()==1 and _selection.selected[0]==worker,"worker selection failed")
	await _button(_hud.get("_unit_more_button"))
	_main.call("_on_selection_changed",_selection.selected)
	await _frames(4)
	_expect(bool(_hud.get("_advanced_commands_open")),"routine selection refresh closed More")
	await _button(_hud.get("_camera_view_button"))
	_expect(not bool(_hud.get("_advanced_commands_open")),"View failed to close More")
	await _button(_hud.get("_unit_more_button"))
	_expect(not bool(_hud.get("_camera_controls_expanded")),"More failed to close View")
	await _action("cancel")
	_expect(not bool(_hud.get("_advanced_commands_open")) and _selection.selected.size()==1,"Escape closed selection before More")
	# An explicit military fixture exercises Patrol without changing the paid economy.
	var soldier: UnitBase = load("res://scenes/units/infantry.tscn").instantiate()
	soldier.player_owner = 0
	_main.add_child(soldier)
	soldier.global_position = worker.global_position + Vector2(35,0)
	soldier.set_process(false)
	_selection.select_single(soldier)
	await _frames(4)
	await _button(_hud.get("_selection_info_button"))
	_expect(str(_hud.call("get_secondary_surface_name"))=="info","tap Info alternative did not open")
	await _capture("tap-info")
	await _tap(Vector2(safe.position.x+8,95))
	_expect(str(_hud.call("get_secondary_surface_name"))=="none","Info outside tap failed to close surface")
	_expect(_selection.selected.size()==1 and _orders==0,"Info outside dismissal leaked selection/order")
	var more: Button = _hud.get("_unit_more_button")
	var hold: Node = more.get_meta("hud_hold_control")
	var more_position: Vector2 = more.get_global_rect().get_center()
	_contact_id += 1
	await _touch_contact(more_position,true,_contact_id)
	await _real_wait(510)
	_expect(not hold.get_visible_bounds().is_empty(),"More hold did not open chooser")
	await _capture("more-held")
	await _touch_contact(more_position,false,_contact_id)
	_expect(not bool(_main.get("_patrol_command_armed")) and _orders==0,"neutral chooser release executed command")
	_contact_id += 1
	await _frames(3)
	more_position = more.get_global_rect().get_center()
	await _touch_contact(more_position,true,_contact_id)
	await _real_wait(510)
	var choices: Array = hold.get_choice_rects()
	var patrol_rect := Rect2()
	for choice: Dictionary in choices:
		if str(choice.get("id","")).to_lower().contains("patrol"):
			patrol_rect = choice["rect"]
	_expect(patrol_rect.has_area(),"military chooser omitted Patrol target")
	if patrol_rect.has_area():
		var slide := InputEventScreenDrag.new()
		slide.index = _contact_id
		slide.position = get_viewport().get_final_transform()*patrol_rect.get_center()
		slide.relative = slide.position-get_viewport().get_final_transform()*more_position
		Input.parse_input_event(slide)
		Input.flush_buffered_events()
		await _frames(3)
		_expect(int(hold.get("_choice_index"))>=0 and not bool(_main.get("_patrol_command_armed")),"Patrol preview executed before owning release")
		await _capture("patrol-preview")
		await _touch_contact(patrol_rect.get_center(),false,_contact_id)
	else:
		await _touch_contact(more_position,false,_contact_id)
	_expect(bool(_main.get("_patrol_command_armed")) and _orders==0,"Patrol release failed to arm without issuing a destination")
	await _capture("patrol-armed")
	await _action("cancel")
	_expect(not bool(_main.get("_patrol_command_armed")),"Patrol mode cancellation failed")
	await _button(_hud.get("_selection_info_button"))
	_expect(str(_hud.call("get_secondary_surface_name"))=="info","persistent Info did not reopen before Pause")
	await _button(_hud.get("_pause_button"))
	_expect(GameManager.current_state==GameManager.GameState.PAUSED and str(_hud.call("get_secondary_surface_name"))=="none","one Pause tap did not pause and close persistent Info")
	_expect(_orders==0 and _selection.selected.size()==1 and _selection.selected[0]==soldier,"Info-to-Pause tap leaked selection or world order")
	await _capture("persistent-info-pause")
	await _button(_hud.get("_pause_overlay").get_node("PauseMenu/ResumeButton"))
	_expect(GameManager.current_state==GameManager.GameState.PLAYING and str(_hud.call("get_secondary_surface_name"))=="none" and not bool(_hud.get("_advanced_commands_open")) and not bool(_hud.get("_camera_controls_expanded")) and not bool(_hud.get("_queue_view_requested")),"Resume did not return to Playing with secondary surfaces collapsed")
	# Pass-through disclosures close on admitted world contact, which retains
	# its ordinary meaning through release. Reading surfaces remain blocking.
	_selection.select_single(worker)
	worker.command_stop()
	camera.position = worker.global_position
	camera.reset_smoothing()
	camera.force_update_scroll()
	await _frames(4)
	await _button(_hud.get("_unit_more_button"))
	var target: Vector2 = _uncovered_ground(worker)
	_expect(target!=Vector2.ZERO,"More world tap needs reachable uncovered terrain")
	var selected_before: Array[Node2D] = _selection.selected.duplicate()
	var orders_before: int = _orders
	if target!=Vector2.ZERO:
		await _tap(target)
	_expect(_orders==orders_before+1 and _selection.selected==selected_before and str(_hud.call("get_secondary_surface_name"))=="none","More world tap did not collapse and issue exactly one ordinary Move")
	var intended_move_orders: int = _orders-orders_before
	worker.command_stop()
	await _button(_hud.get("_camera_view_button"))
	var pan_start: Vector2 = _uncovered_ground(worker,Vector2(64,0))
	_expect(pan_start!=Vector2.ZERO,"View pan needs an uncovered start and endpoint")
	orders_before = _orders
	var camera_before: Vector2 = camera.position
	if pan_start!=Vector2.ZERO:
		_contact_id += 1
		await _touch_contact(pan_start,true,_contact_id)
		_expect(str(_hud.call("get_secondary_surface_name"))=="none","View did not collapse on admitted pan press")
		for step: int in range(1,5):
			var pan := InputEventScreenDrag.new()
			pan.index = _contact_id
			pan.position = get_viewport().get_final_transform()*(pan_start+Vector2(step*16,0))
			pan.relative = get_viewport().get_final_transform().basis_xform(Vector2(16,0))
			Input.parse_input_event(pan)
			Input.flush_buffered_events()
			await _frames(2)
		await _touch_contact(pan_start+Vector2(64,0),false,_contact_id)
	_expect(camera.position.distance_to(camera_before)>8 and _orders==orders_before and _selection.selected==selected_before,"View world pan failed to move camera without an order or selection change")
	await _action("select_tc")
	_expect(_selection.selected.size()==1 and _selection.selected[0]==tc,"Home keyboard action did not select the producer for rally")
	await _button(_hud.get("_train_buttons_container").get_node("TrainButton_0"))
	await _button(_hud.get("_queue_navigation_button"))
	target = _uncovered_ground(worker)
	_expect(target!=Vector2.ZERO,"Queue rally tap needs uncovered walkable terrain")
	orders_before = _orders
	if target!=Vector2.ZERO:
		_contact_id += 1
		await _touch_contact(target,true,_contact_id)
		_expect(str(_hud.call("get_secondary_surface_name"))=="none","Queue did not collapse on admitted rally hold")
		await _real_wait(390)
		_expect(_orders==orders_before+1 and _selection.selected.size()==1 and _selection.selected[0]==tc,"Queue world hold did not set exactly one rally at threshold")
		await _touch_contact(target,false,_contact_id)
	var intended_rally_orders: int = _orders-orders_before
	_expect(intended_rally_orders==1 and _selection.selected.size()==1 and _selection.selected[0]==tc and str(_hud.call("get_secondary_surface_name"))=="none","Queue rally hold release duplicated the order or replaced producer selection")
	if target!=Vector2.ZERO:
		var target_tile: Vector2i = _map.call("world_to_tile",get_viewport().get_canvas_transform().affine_inverse()*target)
		_expect(tc.rally_point.distance_to(_map.call("tile_to_world",target_tile))<0.1,"Queue hold did not set the actual held rally tile")
	await _button(_hud.get("_queue_navigation_button"))
	await _button(_hud.get("queue_container").get_node("QueueClearAllButton"))
	_expect(queue.get_queue_size()==0 and ResourceManager.get_all_resources(0)==bank,"post-rally paid queue refund changed bank")
	await _action("cancel")
	_expect(str(_hud.call("get_secondary_surface_name"))=="none" and not bool(_hud.get("_queue_view_requested")),"Queue did not collapse before leaving the match fixture")
	# Finish the real queue container's two-frame layout reconciliation before
	# removing this fixture; the next profile creates a separate match scene.
	await _frames(4)
	_receipts.append({"profile":_profile,"inspection_bank":bank,"paid_then_refunded":ResourceManager.get_all_resources(0)==bank,"world_orders":_orders,"intended_move_orders":intended_move_orders,"intended_rally_orders":intended_rally_orders,"unintended_orders":_orders-intended_move_orders-intended_rally_orders,"chooser_choices":choices.size()})
	_main.free()
	await _frames(3)

func _hold_inspect(button: Button,state: String) -> void:
	await _frames(3)
	if not _visible_target(button):
		_expect(false,"unreachable inspection " + str(button.name if is_instance_valid(button) else "freed target"))
		return
	var hold: Node = button.get_meta("hud_hold_control",null)
	_expect(hold!=null,"missing hold inspector on " + str(button.name))
	if hold==null:
		return
	var position: Vector2 = button.get_global_rect().get_center()
	_contact_id += 1
	await _touch_contact(position,true,_contact_id)
	if state=="train-info":
		await _real_wait(250)
		_expect(not bool(hold.get("_consumed")) and is_instance_valid(hold.get("_progress")),"pending Train hold has no pre-activation progress")
		await _capture("train-hold-progress")
		await _real_wait(260)
	else:
		await _real_wait(510)
	_expect(not hold.get_visible_bounds().is_empty(),"hold info absent on " + str(button.name))
	await _capture(state)
	await _touch_contact(position,false,_contact_id)
	_expect(hold.get_visible_bounds().is_empty(),"hold info survived owning release")

func _uncovered_ground(worker: UnitBase,pan_offset: Vector2 = Vector2.ZERO) -> Vector2:
	var origin: Vector2i = _map.call("world_to_tile",worker.global_position)
	var safe: Rect2 = (_hud.call("get_world_safe_rect") as Rect2).grow(-12)
	var obstacles: Array[Rect2] = _hud.call("get_world_occlusion_rects")
	for radius: int in range(2,10):
		for dy: int in range(-radius,radius+1):
			for dx: int in range(-radius,radius+1):
				var tile: Vector2i = origin+Vector2i(dx,dy)
				if not _map.call("is_tile_walkable",tile) or not _map.call("is_tile_visible_to_player",tile,0):
					continue
				var world: Vector2 = _map.call("tile_to_world",tile)
				var screen: Vector2 = get_viewport().get_canvas_transform()*world
				if not safe.has_point(screen) or not safe.has_point(screen+pan_offset) or world.distance_to(worker.global_position)<96:
					continue
				var blocked := false
				for obstacle: Rect2 in obstacles:
					if obstacle.grow(6).has_point(screen) or obstacle.grow(6).has_point(screen+pan_offset):
						blocked = true
						break
				if blocked or _selection.call("_get_node_at",world,true)!=null or _selection.call("_get_resource_at",world,true)!=null:
					continue
				if not _map.call("get_navigation_world_path",worker.global_position,world).is_empty():
					return screen
	return Vector2.ZERO

func _visible_target(button: Button) -> bool:
	if not is_instance_valid(button) or not button.is_visible_in_tree():
		return false
	var bounds: Rect2 = button.get_global_rect()
	if not get_viewport().get_visible_rect().encloses(bounds):
		return false
	var ancestor: Node = button.get_parent()
	while ancestor != null:
		if ancestor is Control and (ancestor as Control).clip_contents and not (ancestor as Control).get_global_rect().encloses(bounds):
			return false
		ancestor = ancestor.get_parent()
	return true

func _scroll_card_into_view(button: Button) -> void:
	var ancestor: Node = button.get_parent()
	while ancestor != null and not ancestor is ScrollContainer:
		ancestor = ancestor.get_parent()
	var scroll: ScrollContainer = ancestor as ScrollContainer
	_expect(scroll != null,"Build card has no scroll viewport")
	if scroll == null:
		return
	for attempt: int in range(4):
		await _frames(3)
		if _visible_target(button):
			return
		var clip: Rect2 = scroll.get_global_rect()
		var bounds: Rect2 = button.get_global_rect()
		var rightward: bool = bounds.end.x > clip.end.x
		# Begin on a fully visible card, as a finger naturally does. Movement
		# cancels its pending inspection/tap while retaining GUI scroll ownership.
		var start := Vector2.ZERO
		var found := false
		for child: Node in button.get_parent().get_children():
			if not child is Button or not _visible_target(child as Button):
				continue
			var candidate: Vector2 = (child as Button).get_global_rect().get_center()
			if clip.grow(-4.0).has_point(candidate) and (not found or (candidate.x > start.x if rightward else candidate.x < start.x)):
				start = candidate
				found = true
		_expect(found,"no fully visible Build card for scrolling")
		if not found:
			return
		var distance: float = minf(260.0, maxf(80.0, bounds.end.x - clip.end.x + 12.0 if rightward else clip.position.x - bounds.position.x + 12.0))
		var end: Vector2 = start + Vector2(-distance if rightward else distance,0.0)
		var before_scroll: int = scroll.scroll_horizontal
		_contact_id += 1
		await _touch_contact(start,true,_contact_id)
		for step: int in range(1,7):
			var previous: Vector2 = start.lerp(end,float(step-1)/6.0)
			var position: Vector2 = start.lerp(end,float(step)/6.0)
			var drag := InputEventScreenDrag.new()
			drag.index = _contact_id
			drag.position = get_viewport().get_final_transform()*position
			drag.relative = get_viewport().get_final_transform().basis_xform(position-previous)
			Input.parse_input_event(drag)
			Input.flush_buffered_events()
			await _frames(2)
		await _touch_contact(end,false,_contact_id)
		_expect(scroll.scroll_horizontal != before_scroll,"Build horizontal drag did not scroll")
	_expect(_visible_target(button),"Build scrolling did not fully expose " + str(button.name))

func _touch_contact(position: Vector2,pressed: bool,index: int) -> void:
	var event := InputEventScreenTouch.new()
	event.index=index
	event.position=get_viewport().get_final_transform()*position
	event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames(3)

func _real_wait(milliseconds: int) -> void:
	var deadline: int = Time.get_ticks_msec()+milliseconds
	while Time.get_ticks_msec()<deadline:
		await _frames(1)
