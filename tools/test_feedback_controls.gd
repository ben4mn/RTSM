extends Node
## Real ScreenTouch dispatch + paid ProductionQueue. Fixture economies and
## isolated transport flags: not a live network/PWA or physical-device test.
var failures: Array[String] = []
var checks: int = 0
var layer: CanvasLayer
var button: Button
var other: Button
var hold: HUDHoldControl
var other_hold: HUDHoldControl
var queue: ProductionQueue
var building: BuildingBase
var revision: int = 0
var actions: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.selected_population_limit = 100
	GameManager.initialize_game(2)
	GameManager.increase_population_cap(0, 95)
	GameManager.hold_shortcuts_enabled = true
	get_window().size = Vector2i(844,390)
	get_window().content_scale_size = Vector2i(844,390)
	Input.emulate_touch_from_mouse = false
	Input.emulate_mouse_from_touch = true
	building = BuildingBase.new()
	building.building_type = BuildingData.BuildingType.TOWN_CENTER
	building.player_owner = 0
	building.state = BuildingBase.State.ACTIVE
	add_child(building)
	building.set_process(false)
	queue = ProductionQueue.new()
	building.add_child(queue)
	layer = CanvasLayer.new()
	add_child(layer)
	button = _button("Train", Vector2(260,250))
	other = _button("Conflicting train", Vector2(440,250))
	button.pressed.connect(_buy)
	other.pressed.connect(_buy)
	hold = HUDHoldControl.attach_to(button,layer,func() -> Dictionary: return {},func() -> int: return revision)
	other_hold = HUDHoldControl.attach_to(other,layer,func() -> Dictionary: return {})
	hold.repeat_action = _buy
	other_hold.repeat_action = _buy
	await _frames(3)
	var center: Vector2 = button.get_global_rect().get_center()
	var other_center: Vector2 = other.get_global_rect().get_center()
	var cost: int = int(UnitData.get_unit_cost(UnitData.UnitType.VILLAGER).food)
	_reset(1000)
	await _touch(11,center,true)
	await _touch(11,center,false)
	_expect(queue.queue.size() == 1 and actions == 1, "short touch makes exactly one paid order with mouse emulation")
	_expect(ResourceManager.get_resource(0,"food") == 1000-cost,"short touch deducts one cost")
	_reset(1000)
	await _touch(12,center,true)
	await _wait(0.32)
	_expect(queue.queue.is_empty(),"hold waits before purchasing")
	await _wait(0.55)
	var repeated: int = queue.queue.size()
	_expect(repeated >= 2 and repeated <= 3,"hold repeatedly buys at a sensible cadence")
	_expect(_progress_count() == 1,"repeat reuses one progress indicator")
	_expect(_has_count_feedback(),"hold displays queued-count feedback")
	await _touch(12,center,false)
	await _wait(0.35)
	_expect(queue.queue.size() == repeated and actions == repeated,"release produces no extra native purchase and ends repetition")
	_expect(_progress_count() == 0,"release removes all progress indicators")
	_reset(1000)
	await _touch(13,center,true)
	await _wait(1.8)
	_expect(queue.queue.size() == ProductionQueue.MAX_QUEUE_SIZE,"held production fills only the finite queue")
	var remaining: int = ResourceManager.get_resource(0,"food")
	await _touch(13,center,false)
	_expect(remaining == 1000-cost*ProductionQueue.MAX_QUEUE_SIZE and ResourceManager.get_resource(0,"food") == remaining,"full queue rejects purchases without spending")
	_reset(cost*2)
	await _touch(14,center,true)
	await _wait(1.1)
	_expect(queue.queue.size() == 2 and ResourceManager.get_resource(0,"food") == 0,"resource exhaustion stops repeated paid purchases")
	await _touch(14,center,false)
	_reset(1000)
	await _touch(15,center,true)
	await _drag(15,center+Vector2(35,0))
	await _drag(15,center)
	await _wait(0.55)
	await _touch(15,center,false)
	_expect(actions == 0,"drag out and back cancels both hold and release purchase")
	await _touch(16,center,true)
	await _wait(0.55)
	var before: int = actions
	await _drag(16,center+Vector2(35,0))
	await _wait(0.55)
	await _touch(16,center,false)
	_expect(actions == before,"drag after activation stops repetition without release buy")
	_reset(1000)
	await _touch(17,center,true)
	await _touch(18,other_center,true)
	await _wait(0.55)
	await _touch(17,center,false)
	await _touch(19,center,true)
	await _wait(0.55)
	await _touch(19,center,false)
	await _touch(18,other_center,false)
	_expect(actions == 0 and not hold.is_gesture_active(),"second contact cancels; third cannot rearm until all contacts drain")
	_reset(1000)
	await _touch(20,center,true)
	await _touch(20,center,false,true)
	_expect(actions == 0,"OS canceled release cannot purchase")
	await _touch(21,center,true)
	revision += 1
	await _wait(0.55)
	await _touch(21,center,false)
	_expect(actions == 0,"changed selection context cancels repeat and release")
	button.disabled = true
	await _touch(22,center,true)
	await _wait(0.55)
	await _touch(22,center,false)
	_expect(actions == 0,"disabled production cannot repeat or click")
	button.disabled = false
	GameManager.hold_shortcuts_enabled = false
	await _touch(23,center,true)
	await _wait(0.6)
	_expect(actions == 0,"disabled holds never repeat")
	await _touch(23,center,false)
	_expect(actions == 1,"disabled holds retain ordinary single-click behavior")
	GameManager.hold_shortcuts_enabled = true
	_reset(1000)
	await _touch(24,center,true)
	await _wait(0.55)
	before = actions
	GameManager.hold_shortcuts_enabled = false
	await _wait(0.55)
	await _touch(24,center,false)
	_expect(before >= 1 and actions == before,"turning holds off mid-contact cancels further purchases")
	GameManager.hold_shortcuts_enabled = true
	_reset(1000)
	queue.auto_queue_enabled = true
	queue.auto_queue_unit_type = UnitData.UnitType.VILLAGER
	queue.retry_auto_queue(10.0)
	# Repeat is back (owner request): an empty repeating queue buys the next unit.
	_expect(queue.queue.size() == 1 and queue.auto_queue_enabled,"repeat restarts empty production with one paid unit")
	queue.auto_queue_enabled = false
	queue.cancel_all()
	_test_speed()
	queue.cancel_all()
	layer.free()
	building.free()
	for failure: String in failures: push_error("[FAIL] feedback_controls: "+failure)
	if failures.is_empty(): print("[PASS] feedback_controls: %d checks; real touch/emulated release, finite paid queue/resources, repeat feedback, drag/cancel/multitouch/context/disabled holds, authoritative fixed speed" % checks)
	get_tree().quit(0 if failures.is_empty() else 1)

func _test_speed() -> void:
	var transport: Node = load("res://scripts/network/network_session.gd").new()
	for profile: Dictionary in [{"online":true,"server":false},{"online":false,"server":true},{"online":true,"server":true}]:
		transport.online = profile.online
		transport.server_mode = profile.server
		Engine.time_scale = 3.0
		GameManager.game_speed = 3.0
		transport._physics_process(0.01)
		_expect(Engine.time_scale == 1.0 and GameManager.game_speed == 1.0,"network physics guard forces1x for %s" % profile)
	transport.online = false
	transport.server_mode = false
	Engine.time_scale = 2.0
	transport.enforce_match_speed()
	_expect(Engine.time_scale == 2.0,"solo speed remains adjustable")
	Engine.time_scale = 1.0
	GameManager.game_speed = 1.0
	transport.free()

func _button(label: String, at: Vector2) -> Button:
	var result := Button.new()
	result.text = label
	result.position = at
	result.size = Vector2(160,64)
	layer.add_child(result)
	return result

func _reset(food: int) -> void:
	queue.cancel_all()
	ResourceManager.initialize_player(0,{"food":food,"wood":1000,"gold":1000})
	actions = 0

func _buy() -> bool:
	if not queue.enqueue_unit(UnitData.UnitType.VILLAGER): return false
	actions += 1
	return true

func _progress_count() -> int:
	var count: int = 0
	for child: Node in hold.get_children():
		if child is ProgressBar and not child.is_queued_for_deletion(): count += 1
	return count

func _has_count_feedback() -> bool:
	for child: Node in hold.get_children():
		if child is Label and child.is_visible_in_tree() and "queued" in child.text: return true
	return false

func _touch(id: int, at: Vector2, pressed: bool, canceled: bool=false) -> void:
	var event := InputEventScreenTouch.new()
	event.index=id
	event.position=get_viewport().get_final_transform()*at
	event.pressed=pressed
	event.canceled=canceled
	Input.parse_input_event(event)
	await _frames(2)

func _drag(id: int, at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index=id
	event.position=get_viewport().get_final_transform()*at
	Input.parse_input_event(event)
	await _frames(2)

func _frames(count: int) -> void:
	for frame: int in count: await get_tree().process_frame

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds,true,false,true).timeout

func _expect(condition: bool,message: String) -> void:
	checks+=1
	if not condition: failures.append(message)
