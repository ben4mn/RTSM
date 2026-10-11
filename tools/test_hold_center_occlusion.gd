extends "res://tools/test_center_selection_occlusion.gd"
## Keyboard Center must frame complete subjects around actual held/tapped cards.
## Native capture is optional through AOEM_CAPTURE_HOLD_CENTER_DIR.
const HOLD_OUTPUT := "res://output/evolution/mobile-interaction-20261011/hold-center"
var _safe_rect := Rect2()
var _active_hud: CanvasLayer
var _contact_id := 7200
var _world_orders := 0


func _run() -> void:
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	GameManager.guided_opening_enabled = false
	GameManager.hold_shortcuts_enabled = true
	_capture_dir = OS.get_environment("AOEM_CAPTURE_HOLD_CENTER_DIR")
	if not _capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_capture_dir)
	for phone: Vector2i in [Vector2i(844,390), Vector2i(932,430)]:
		await _test_hold_phone(phone)
	_expect(_records.size()==36,"all twelve profiles must complete three real Center cases")
	GameManager.ui_scale = 1.0
	GameManager.apply_preferences()
	DirAccess.make_dir_recursive_absolute(HOLD_OUTPUT)
	var hashes: Dictionary = {}
	for path: String in ["scripts/ui/hud_hold_control.gd", "scripts/ui/modal_dismiss_shield.gd", "scripts/ui/hud.gd", "scripts/main/main.gd", "scripts/map/game_map.gd", "scripts/managers/selection_manager.gd", "tools/test_hold_center_occlusion.gd", "tools/test_center_selection_occlusion.gd"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	var receipt := FileAccess.open(HOLD_OUTPUT.path_join("native-receipt.json" if not _capture_dir.is_empty() else "headless-receipt.json"),FileAccess.WRITE)
	receipt.store_string(JSON.stringify({"scope":"Real Main/HUD, actual ScreenTouch ownership and keyboard Space. Train inspection/More chooser/persistent Info across both phones, three UI scales and ordinary/synthetic-notch safe areas. Independent rendered sprite/ring/HP bounds and constructive zoom-preservation witness. No physical-device claim.","source_sha256":hashes,"records":_records,"failures":_failures},"  "))
	for failure: String in _failures:
		push_error("[FAIL] hold_center_occlusion: " + failure)
	if _failures.is_empty():
		print("[PASS] hold_center_occlusion: %d actual keyboard Center cases; held Info/chooser and persistent Info, complete artwork clearance, feasible manual zoom and unchanged gesture ownership" % _records.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _test_hold_phone(phone: Vector2i) -> void:
	get_window().size = phone
	GameManager.ui_scale = 1.0
	GameManager.apply_preferences()
	GameManager.set_state(GameManager.GameState.MENU)
	GameManager.selected_map_seed = 101
	GameManager.selected_population_limit = 30
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in range(900):
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	var game_map: Node2D = main.get("game_map")
	var camera: Camera2D = game_map.get("camera")
	var selection: SelectionManager = game_map.get("selection_mgr")
	var hud: CanvasLayer = main.get("hud")
	_active_hud = hud
	main.set_process(false)
	game_map.set_process(false)
	game_map.set("_touch_input_detected",true)
	(main.get("ai_controller") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	var tc: BuildingBase = main.get("_player_town_center")
	var worker: Villager = main.get("_player_units")[0][0]
	var soldier: UnitBase = load("res://scenes/units/infantry.tscn").instantiate()
	soldier.player_owner = 0
	main.add_child(soldier)
	soldier.global_position = worker.global_position + Vector2(35,0)
	soldier.set_process(false)
	main.call("_update_fog_of_war")
	main.call("_update_fog_entity_visibility")
	_world_orders = 0
	selection.move_command.connect(func(_tile: Vector2i) -> void: _world_orders += 1)
	for scale_value: float in [1.0,1.075,1.15]:
		GameManager.ui_scale = scale_value
		GameManager.apply_preferences()
		await _hold_frames(4)
		for notched: bool in [false,true]:
			var logical: Vector2 = get_viewport().get_visible_rect().size
			var pixel_scale: float = get_viewport().get_final_transform().x.length()
			var inset: float = 44.0/pixel_scale if notched else 0.0
			var bottom: float = 18.0/pixel_scale if notched else 0.0
			_safe_rect = Rect2(Vector2(inset,0),logical-Vector2(inset*2,bottom))
			await _hold_frames(4)
			var prefix: String = "%dx%d-scale%.3f-%s" % [phone.x,phone.y,scale_value,"notch" if notched else "full"]
			selection.select_single(tc)
			await _hold_frames(4)
			var train: Button = hud.get("_train_buttons_container").get_node("TrainButton_0")
			var queue: ProductionQueue = tc.get_production_queue()
			var bank: Dictionary = ResourceManager.get_all_resources(0).duplicate()
			await _held_center(main,tc,train,prefix+"-held-info")
			_expect(queue.get_queue_size()==0 and ResourceManager.get_all_resources(0)==bank,prefix+" held Train Center does not spend or queue")
			selection.select_single(soldier)
			await _hold_frames(4)
			await _held_center(main,soldier,hud.get("_unit_more_button"),prefix+"-held-chooser")
			var info_button: Button = hud.get("_selection_info_button")
			await _hold_tap(info_button)
			await _hold_frames(4)
			var info: Control = hud.get("_info_panel")
			_expect(info.is_visible_in_tree() and hud.call("get_secondary_surface_name")=="info",prefix+" persistent tap Info opens")
			var obstacle: Rect2 = info.get_global_rect()
			_assert_visible_obstacles(hud,[obstacle],prefix+" persistent Info")
			game_map.call("_set_zoom_anchored",2.0,Vector2(-1,-1),Vector2(-1,-1),true)
			var preserve: bool = _has_preservation_witness(main,[soldier],2.0)
			var old_selection: Array[Node2D] = selection.selected.duplicate()
			var old_target: Vector2 = soldier.move_target
			var before_orders: int = _world_orders
			camera.position = Vector2.ZERO
			game_map.call("_clamp_camera")
			get_viewport().gui_release_focus()
			await _center_and_check(main,[soldier],prefix+"-persistent-info",true,null,true)
			_expect(info.is_visible_in_tree() and hud.call("get_secondary_surface_name")=="info",prefix+" keyboard Center preserves persistent Info")
			_expect(info.get_global_rect().is_equal_approx(obstacle),prefix+" persistent Info stays in its actual position")
			_expect(selection.selected==old_selection and soldier.move_target==old_target and _world_orders==before_orders,prefix+" persistent Info Center preserves selection and orders")
			if preserve:
				_expect(absf(camera.zoom.x-2.0)<0.001,prefix+" persistent Info retains feasible manual2x")
			await _hold_tap(info.find_child("InfoCloseButton",true,false) as Button)
			_expect(hud.call("get_secondary_surface_name")=="none",prefix+" persistent Info closes through real Close tap")
	_active_hud = null
	main.free()
	GameManager.set_state(GameManager.GameState.MENU)
	await get_tree().process_frame


func _held_center(main: Node,subject: Node2D,button: Button,prefix: String) -> void:
	var hud: CanvasLayer = main.get("hud")
	var game_map: Node2D = main.get("game_map")
	var camera: Camera2D = game_map.get("camera")
	var selection: SelectionManager = game_map.get("selection_mgr")
	var component: Node = button.get_meta("hud_hold_control")
	var position: Vector2 = button.get_global_rect().get_center()
	_contact_id += 1
	await _hold_touch(position,true,_contact_id)
	await _hold_wait(510)
	var held_rects: Array[Rect2] = component.get_visible_bounds()
	_expect(not held_rects.is_empty(),prefix+" real held card opens")
	_assert_visible_obstacles(hud,held_rects,prefix)
	var old_contact: int = component.get("_contact")
	var old_surface: String = hud.call("get_secondary_surface_name")
	var old_selection: Array[Node2D] = selection.selected.duplicate()
	var old_target: Vector2 = subject.get("move_target") if subject is UnitBase else Vector2.ZERO
	var before_orders: int = _world_orders
	game_map.call("_set_zoom_anchored",2.0,Vector2(-1,-1),Vector2(-1,-1),true)
	var preserve: bool = _has_preservation_witness(main,[subject],2.0)
	camera.position = Vector2.ZERO
	game_map.call("_clamp_camera")
	get_viewport().gui_release_focus()
	await _center_and_check(main,[subject],prefix,true,null,true)
	_expect(component.get("_contact")==old_contact and old_contact==_contact_id and not bool(component.get("_canceled")),prefix+" Center preserves owning hold")
	_expect(component.get_visible_bounds()==held_rects and hud.call("get_secondary_surface_name")==old_surface,prefix+" Center preserves actual held surface bounds")
	_expect(selection.selected==old_selection and _world_orders==before_orders,prefix+" held Center preserves selection and issues no world command")
	if subject is UnitBase:
		_expect(subject.get("move_target")==old_target,prefix+" Center leaves destination unchanged")
	if preserve:
		_expect(absf(camera.zoom.x-2.0)<0.001,prefix+" held surface retains feasible manual2x")
	else:
		_expect(camera.zoom.x<=2.001,prefix+" fallback only reduces zoom")
	await _hold_touch(position,false,_contact_id)
	_expect(not bool(component.call("is_gesture_active")) and component.get_visible_bounds().is_empty(),prefix+" owning release drains and closes held card")
	_expect(_world_orders==before_orders,prefix+" neutral owning release issues no command")


func _assert_visible_obstacles(hud: CanvasLayer,rects: Array[Rect2],prefix: String) -> void:
	var obstacles: Array[Rect2] = hud.call("get_world_occlusion_rects")
	for rect: Rect2 in rects:
		var present := false
		for obstacle: Rect2 in obstacles:
			if obstacle.is_equal_approx(rect):
				present = true
		_expect(present,prefix+" exposes each actual visible card/preview rectangle")


func _hold_tap(button: Button) -> void:
	await _hold_frames(3)
	_expect(button.is_visible_in_tree() and not button.disabled,"tap target reachable: "+str(button.name))
	_contact_id += 1
	var position: Vector2 = button.get_global_rect().get_center()
	await _hold_touch(position,true,_contact_id)
	await _hold_touch(position,false,_contact_id)


func _hold_touch(position: Vector2,pressed: bool,index: int) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.position = get_viewport().get_final_transform()*position
	touch.pressed = pressed
	Input.parse_input_event(touch)
	Input.flush_buffered_events()
	await _hold_frames(3)


func _hold_wait(milliseconds: int) -> void:
	var deadline: int = Time.get_ticks_msec()+milliseconds
	while Time.get_ticks_msec()<deadline:
		await _hold_frames(1)


func _hold_frames(count: int) -> void:
	for frame: int in range(count):
		await get_tree().process_frame
		if is_instance_valid(_active_hud) and _safe_rect.has_area():
			_active_hud.call("apply_mobile_layout",get_viewport().get_visible_rect().size,_safe_rect)
