extends Node
## Full scene pointer journey with ordinary paid actions and exact GUI routing.
## AI/economy processing pauses only to make banks and queue refunds deterministic.

var _failures: Array[String] = []
var _receipts: Array[Dictionary] = []
var _main: Node
var _map: Node2D
var _hud: CanvasLayer
var _selection: SelectionManager
var _profile: String
var _orders: int = 0
var _contact_id: int = 120
var _synthetic_notch: bool = false

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	for phone: Vector2i in [Vector2i(844,390), Vector2i(932,430)]:
		for interface_scale: float in [1.0,1.075,1.15]:
			for notched: bool in [false,true]:
				await _journey(phone,interface_scale,notched)
	var folder: String = OS.get_environment("AOEM_CAPTURE_UX_DIR")
	if not folder.is_empty():
		FileAccess.open(folder.path_join("input-receipt.json"),FileAccess.WRITE).store_string(JSON.stringify({"scope":"Actual engine ScreenTouch GUI/world dispatch, normal starting resources, isolated Main processing for deterministic costs/refunds. Twelve phone/scale/safe profiles, no human/physical device claim.","profiles":_receipts,"failures":_failures},"  "))
	for failure: String in _failures:
		push_error("[FAIL] ux_redesign_journey: " + failure)
	if _failures.is_empty():
		print("[PASS] ux_redesign_journey: paid Train/Repeat/queue Clear refunds, Home/Back/Build/Cancel/Place, actual unit selection/Move/Attack destination/keyboard and touch Center, minimap and live resize; twelve profiles, no GUI world-order leakage")
	get_tree().quit(0 if _failures.is_empty() else 1)

func _journey(phone: Vector2i,interface_scale: float,notched: bool) -> void:
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
	var train: HBoxContainer = _hud.get("_train_buttons_container")
	await _button(train.get_node("TrainButton_0"))
	await _button(train.get_node("TrainButton_4"))
	var queue: ProductionQueue = tc.get_production_queue()
	_expect(queue.get_queue_size() == 2,"two affordable normal units did not queue")
	var paid: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	var total_cost: Dictionary = {"food":0,"wood":0,"gold":0}
	for unit_type: int in [UnitData.UnitType.VILLAGER,UnitData.UnitType.SCOUT]:
		for resource: String in UnitData.get_unit_cost(unit_type):
			total_cost[resource] += int(UnitData.get_unit_cost(unit_type)[resource])
	for resource: String in total_cost:
		_expect(int(paid[resource]) == int(bank[resource])-int(total_cost[resource]),"Train spent incorrect " + resource)
	await _button(_hud.get("_auto_queue_button"))
	_expect(queue.auto_queue_enabled,"Repeat touch did not turn on")
	await _capture("paid-repeat")
	await _button(_hud.get("_queue_navigation_button"))
	var clear: Button = _hud.get("queue_container").get_node_or_null("QueueClearAllButton")
	await _button(clear)
	_expect(queue.get_queue_size() == 0 and not queue.auto_queue_enabled,"Clear did not cancel queue and repeat")
	_expect(ResourceManager.get_all_resources(0) == bank,"queue Clear did not fully refund actual paid units")
	await _button(_hud.get("_selection_back_button"))
	await _button(_hud.get("build_menu_button"))
	var palette: Node = _main.get("_build_menu")
	_expect(palette.visible,"Build touch did not open palette")
	await _button(palette.get("_button_map")[BuildingData.BuildingType.HOUSE])
	var placement: Node2D = _main.get("_building_placement")
	_expect(placement.active,"House touch did not enter placement")
	var buildings_before: int = _main.get("_player_buildings")[0].size()
	await _button(_hud.get("_placement_cancel_button"))
	_expect(not placement.active and ResourceManager.get_all_resources(0) == bank,"Cancel placement mutated paid economy")
	await _button(_hud.get("build_menu_button"))
	await _button(palette.get("_button_map")[BuildingData.BuildingType.HOUSE])
	var legal: Vector2 = placement.call("_find_initial_preview_position",placement.global_position)
	placement.call("update_preview_at_world",legal)
	await _frames(4)
	await _capture("placement")
	await _button(_hud.get("_placement_confirm_button"))
	_expect(not placement.active,"Place did not finish placement")
	_expect(_main.get("_player_buildings")[0].size() == buildings_before + 1,"Place did not create one paid foundation")
	_expect(int(ResourceManager.get_all_resources(0).wood) == int(bank.wood)-int(BuildingData.get_building_cost(BuildingData.BuildingType.HOUSE).wood),"Place spent incorrect wood")
	_expect(_orders == 0,"GUI production/build gesture leaked world Move")
	# Select an actual world worker through a nonzero touch identity.
	await _action("cancel")
	var worker: Villager = _main.get("_player_units")[0][0]
	worker.command_stop()
	var camera: Camera2D = _map.get("camera")
	camera.position = worker.global_position
	camera.reset_smoothing()
	camera.force_update_scroll()
	await _frames(4)
	await _tap(get_viewport().get_canvas_transform()*worker.global_position)
	_expect(_selection.selected.size() == 1 and _selection.selected[0] == worker,"actual world worker touch did not select it")
	var ground: Vector2 = _empty_ground(worker)
	_expect(ground != Vector2.ZERO,"no visible legal ground for movement")
	var unit_commands: HBoxContainer = _hud.get("_unit_command_container")
	await _button(unit_commands.get_node("UnitMoveButton"))
	_expect(bool(_main.get("_move_command_armed")),"Move touch did not arm")
	await _capture("move-armed")
	await _tap(ground)
	_expect(_orders == 1 and worker.current_state == UnitBase.State.MOVING,"Move destination did not issue exactly one order")
	worker.set_process(true)
	var start: Vector2 = worker.global_position
	await get_tree().create_timer(0.15).timeout
	_expect(start.distance_to(worker.global_position) > 7,"actual Move did not walk selected worker")
	_expect(worker.current_state == UnitBase.State.MOVING,"moving Center capture needs an actual moving worker")
	worker.set_process(false)
	_main.call("_update_fog_of_war")
	_main.call("_on_selection_changed",_selection.selected)
	_main.call("_update_minimap")
	await _frames(3)
	await _action("center_selection")
	await _capture("moving-center")
	worker.set_process(false)
	await _button(unit_commands.get_node("UnitAttackMoveButton"))
	_expect(bool(_main.get("_attack_move_command_armed")),"Attack touch did not arm")
	var attack_ground: Vector2 = _empty_ground(worker)
	await _tap(attack_ground)
	_expect(_orders == 2 and not bool(_main.get("_attack_move_command_armed")) and worker.attack_move,"Attack destination did not accept one attack-move order")
	_main.call("_on_selection_changed",_selection.selected)
	await _capture("attack-accepted")
	await _button(unit_commands.get_node("UnitAttackMoveButton"))
	await _action("cancel")
	_expect(not bool(_main.get("_attack_move_command_armed")),"cancel failed armed Attack")
	await _button(_hud.get("_camera_view_button"))
	var revision: int = _map.call("get_camera_interaction_revision")
	await _button(_hud.get("_camera_center_button"))
	_expect(int(_map.call("get_camera_interaction_revision")) == revision+1,"visible touch Center was not routed exactly once")
	await _button(_hud.get("_camera_view_button"))
	var before_map: Vector2 = camera.position
	var minimap: Control = _hud.get("minimap_rect")
	await _tap(minimap.get_global_rect().position + minimap.size*Vector2(0.7,0.55))
	_expect(camera.position.distance_to(before_map)>8,"minimap touch did not navigate camera")
	_expect(_orders == 2,"minimap/command GUI leaked additional world orders")
	await _action("center_selection")
	# Live window resize while selection stays active.
	get_window().size = Vector2i(932,430) if phone.x == 844 else Vector2i(844,390)
	await _frames(8)
	_expect((_hud.get("selection_panel") as Control).is_visible_in_tree(),"live resize lost contextual selection")
	await _capture("live-resize")
	_receipts.append({"profile":_profile,"normal_start_bank":bank,"paid_queue_bank":paid,"full_refund_bank":bank,"world_orders":_orders,"movement":start.distance_to(worker.global_position),"building_count_after":_main.get("_player_buildings")[0].size()})
	_main.free()
	await _frames(3)

func _empty_ground(worker: UnitBase) -> Vector2:
	var tile: Vector2i = _map.call("world_to_tile",worker.global_position)
	var view: Rect2 = get_viewport().get_visible_rect()
	var field := Rect2(Vector2(160,105), view.size-Vector2(300,230))
	for radius: int in range(2,9):
		for dy: int in range(-radius,radius+1):
			for dx: int in range(-radius,radius+1):
				var target: Vector2i = tile + Vector2i(dx,dy)
				if not _map.call("is_tile_walkable",target) or not _map.call("is_tile_visible_to_player",target,0):
					continue
				var world: Vector2 = _map.call("tile_to_world",target)
				var screen: Vector2 = get_viewport().get_canvas_transform()*world
				if not field.has_point(screen) or world.distance_to(worker.global_position)<96:
					continue
				if _selection.call("_get_node_at",world,true)!=null or _selection.call("_get_resource_at",world,true)!=null:
					continue
				if not _map.call("get_navigation_world_path",worker.global_position,world).is_empty():
					return screen
	return Vector2.ZERO

func _button(button: Button) -> void:
	await _frames(3)
	if button == null:
		_expect(false,"required Button missing")
		return
	_expect(button.is_visible_in_tree() and not button.disabled,"unreachable action " + str(button.name))
	_expect(button.size.x >= 47.5 and button.size.y >= 47.5,"under48px touch target " + str(button.name))
	var scroll: ScrollContainer = _hud.get("command_scroll")
	if scroll.is_ancestor_of(button):
		_expect(scroll.get_global_rect().encloses(button.get_global_rect()),"clipped action " + str(button.name))
	await _tap(button.get_global_rect().get_center())

func _tap(position: Vector2) -> void:
	_contact_id += 1
	for pressed: bool in [true,false]:
		var event := InputEventScreenTouch.new()
		event.index = _contact_id
		event.position = get_viewport().get_final_transform()*position
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(3)

func _action(action: String) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(3)

func _capture(state: String) -> void:
	await _frames(3)
	if state == "move-armed":
		var shelf: ScrollContainer = _hud.get("command_scroll")
		for action_name: String in ["UnitMoveButton","UnitAttackMoveButton","UnitMoreButton","UnitClearButton"]:
			var action: Button = _hud.get("_unit_command_container").get_node(action_name)
			_expect(shelf.get_global_rect().encloses(action.get_global_rect()),"armed worker must expose complete " + action_name)
	var folder: String = OS.get_environment("AOEM_CAPTURE_UX_DIR")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(folder)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join(_profile+"-"+state+".png"))

func _frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame
		_apply_profile_layout()

func _apply_profile_layout() -> void:
	if not is_instance_valid(_hud) or not _hud.is_inside_tree():
		return
	var logical: Vector2 = get_viewport().get_visible_rect().size
	var inset: Vector2 = Vector2(44,18)*logical/Vector2(get_window().size) if _synthetic_notch else Vector2.ZERO
	var safe := Rect2(Vector2(inset.x,0),logical-Vector2(inset.x*2,inset.y))
	_hud.call("apply_mobile_layout",logical,safe)
	if is_instance_valid(_main) and _main.get("_build_menu") != null:
		_main.get("_build_menu").call("set_safe_area_rect",safe)

func _expect(condition: bool,message: String) -> void:
	if not condition:
		_failures.append(_profile+": "+message)
