extends Node
## Natural cargo, production Main/HUD, and actual touch dispatch. Only other
## workers/AI are stopped to isolate the employment labels from unrelated jobs.

var _failures: Array[String] = []
var _main: Node
var _worker: Villager
var _hud: CanvasLayer
var _selection: SelectionManager
var _deposited: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for scale_factor: float in [1.0, 1.075]:
			await _profile(phone, scale_factor)
	Engine.time_scale = 1.0
	for failure: String in _failures:
		push_error("[FAIL] worker_status_feedback: " + failure)
	if _failures.is_empty():
		print("[PASS] worker_status_feedback: four phone profiles, natural Wood cargo, Move/Stop employment, separate typed cargo, real touch arming, mixed jobs, natural exact delivery")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _profile(phone: Vector2i, scale_factor: float) -> void:
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = scale_factor
	GameManager.set_state(GameManager.GameState.MENU)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 424242
	GameManager.selected_population_limit = 30
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for frame: int in range(900):
		if _main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	Engine.time_scale = 4.0
	_main.get("ai_controller").set_process(false)
	_hud = _main.get("hud")
	_selection = _main.get("game_map").selection_mgr
	for unit: Node in _main.get("_player_units")[0]:
		if unit is Villager:
			(unit as Villager).command_stop()
	_worker = _main.get("_player_units")[0][0]
	var map: Node2D = _main.get("game_map")
	var wood: Node2D = map.get_nearest_reachable_resource_node("wood", _worker.global_position, 0)
	_expect(wood != null and _worker.command_gather(wood), "natural reachable Wood order")
	var deadline: float = GameManager.game_time + 80.0
	var wall_deadline: int = Time.get_ticks_msec() + 20000
	while _worker.carried_amount == 0 and GameManager.game_time < deadline and Time.get_ticks_msec() < wall_deadline:
		await get_tree().process_frame
	if _worker.carried_amount == 0:
		_expect(false, "natural worker never harvested Wood")
		_main.free()
		return
	# Freeze this naturally acquired load for the UI checks, then restore normal
	# processing to verify its exact deposit at the end of the same scenario.
	_worker.set_process(false)
	var cargo_before: int = _worker.carried_amount
	_selection.select_single(_worker)
	await _refresh()
	_expect(_details().contains("Gathering Wood") and _details().contains("Cargo Wood %d/%d" % [cargo_before, _worker.carry_capacity]), "working label and typed cargo")
	_expect(_task("Wood") == "Wood 1", "natural active job counted as Wood")
	var destination: Vector2 = map.tile_to_world(map.map_generator.spawn_positions[0] + Vector2i(7, 5))
	_worker.command_move(destination)
	await _refresh()
	_expect(_details().begins_with("Moving\nCargo Wood"), "loaded manual Move must show Moving, not Gathering")
	_expect(_task("Wood") == "Wood 0", "loaded manual Move must not count as active Wood labor")
	await _tap((_hud.get("_unit_stop_button") as Button).get_global_rect().get_center())
	await _refresh()
	_expect(_worker.current_state == UnitBase.State.IDLE and _details().begins_with("Idle\nCargo Wood"), "real Stop must show Idle plus intact cargo")
	_expect(_task("Wood") == "Wood 0" and _worker.carried_amount == cargo_before, "Stop preserves cargo without claiming employment")
	# Non-unit inspection must survive command refresh after a loaded worker.
	var town_center: BuildingBase = _main.get("_player_town_center")
	_selection.select_single(town_center)
	_main.call("_refresh_unit_command_hud")
	await _refresh()
	_expect(_details() == "Arrows + depot", "Town Center inherited loaded worker status/cargo")
	_selection.select_single(wood)
	_main.call("_refresh_unit_command_hud")
	await _refresh()
	_expect(_details().contains("remaining") and not _details().contains("Cargo"), "resource inherited loaded worker status/cargo")
	_selection.select_single(_worker)
	_expect(_worker.command_return_resources(), "partial load accepts normal Return")
	await _refresh()
	_expect(_details().begins_with("Returning Wood\nCargo Wood"), "actual delivery leg shows Returning")
	_expect(_task("Wood") == "Wood 0", "one-shot Return must not invent an ongoing Wood gathering job")
	await _tap((_hud.get("_unit_move_button") as Button).get_global_rect().get_center())
	await _refresh()
	_expect(_details().begins_with("Tap to move\nCargo Wood"), "armed Move retains cargo line")
	_text_fits(_hud.get("selection_details"), "%s/%.3f armed cargo" % [phone, scale_factor])
	# A worker group cannot claim every selected worker is doing the first job.
	var other: Villager = _main.get("_player_units")[0][1]
	var pair: Array[Node2D] = [_worker, other]
	_selection.select_many(pair)
	_main.call("_clear_armed_unit_commands", true)
	await _refresh()
	_expect(_details().begins_with("Mixed Tasks\nCargo Wood"), "mixed worker jobs and summed typed cargo: " + _details())
	_selection.select_single(_worker)
	_main.call("_clear_armed_unit_commands", true)
	await _refresh()
	_deposited = 0
	var bank_before: int = ResourceManager.get_resource(0, "wood")
	_worker.resource_deposited.connect(func(resource: String, amount: int) -> void:
		if resource == "wood":
			_deposited += amount
	)
	_worker.set_process(true)
	deadline = GameManager.game_time + 60.0
	wall_deadline = Time.get_ticks_msec() + 15000
	while _worker.carried_amount > 0 and GameManager.game_time < deadline and Time.get_ticks_msec() < wall_deadline:
		await get_tree().process_frame
	_expect(_worker.carried_amount == 0 and _deposited == cargo_before, "natural cargo deposits exactly once")
	_expect(ResourceManager.get_resource(0, "wood") - bank_before == cargo_before, "bank matches real delivery")
	print("STATUS_PROFILE ", phone, " scale=", scale_factor, " cargo=", cargo_before, " deposited=", _deposited)
	_main.free()
	await get_tree().process_frame


func _refresh() -> void:
	_main.call("_on_selection_changed", _selection.selected)
	_main.call("_update_idle_villager_count")
	for frame: int in range(4):
		await get_tree().process_frame


func _details() -> String:
	return (_hud.get("selection_details") as Label).text


func _task(task_name: String) -> String:
	return ((_hud.get("_villager_task_hbox") as HBoxContainer).get_node(task_name) as Label).text


func _tap(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.position = get_viewport().get_final_transform() * position
		touch.pressed = pressed
		Input.parse_input_event(touch)
		for frame: int in range(4):
			await get_tree().process_frame


func _text_fits(label: Label, context: String) -> void:
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	for line: String in label.text.split("\n"):
		_expect(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= label.size.x + 1.0, context + " line clipped: " + line)
	_expect(label.get_line_count() == label.get_visible_line_count(), context + " hides cargo/status line")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
