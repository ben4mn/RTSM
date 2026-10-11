extends Node
## Native engine ScreenTouch -> visible Move-button signal/arming timing.
## Selection is fixture setup. This excludes hardware/OS/Web input and display
## scanout; it is an engine dispatch diagnostic, not end-to-end finger latency.

var _records: Array[Dictionary] = []
var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Touch timing probe requires native rendering")
		get_tree().quit(1)
		return
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_population_limit = 30
	GameManager.selected_map_seed = 42
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for ui_scale: float in [1.0, 1.15]:
			await _profile(phone, ui_scale)
	var sources: Dictionary = {}
	for path: String in ["res://scripts/main/main.gd", "res://scripts/ui/hud.gd", "res://scripts/managers/selection_manager.gd"]:
		sources[path] = FileAccess.get_file_as_string(path).sha256_text()
	var result: Dictionary = {"scope": "Native engine synthetic ScreenTouch-to-GUI-signal and command arming. Real Main/HUD, fixture-selected natural worker, no movement order/payment; excludes hardware/OS/Web and display scanout, not physical-finger latency.", "source_sha256": sources, "profiles": _records, "failures": _failures}
	FileAccess.open("res://output/evolution/native-touch-response.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("[NATIVE_TOUCH_RESPONSE] ", JSON.stringify(result))
	get_tree().quit(0 if _failures.is_empty() else 1)


func _profile(phone: Vector2i, ui_scale: float) -> void:
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	GameManager.ui_scale = ui_scale
	get_window().content_scale_factor = ui_scale
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for _frame in range(900):
		if main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	var worker: UnitBase = main.get("_player_units")[0][0]
	main.game_map.selection_mgr.select_single(worker)
	for _frame in range(5):
		await get_tree().process_frame
	var hud: CanvasLayer = main.get("hud")
	var button: Button = hud.get("_unit_move_button")
	var record: Dictionary = {"pixels": str(phone), "ui_scale": ui_scale, "visible": button.is_visible_in_tree(), "enabled": not button.disabled, "dispatch_to_signal_us": -1, "armed_after": false}
	var begin: int = Time.get_ticks_usec()
	var callback: Callable = func() -> void: record["dispatch_to_signal_us"] = Time.get_ticks_usec() - begin
	hud.unit_move_requested.connect(callback, CONNECT_ONE_SHOT)
	var logical: Vector2 = button.get_global_rect().get_center()
	var physical: Vector2 = get_viewport().get_final_transform() * logical
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = physical
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
	record["armed_after"] = bool(main.get("_move_command_armed"))
	if not record["visible"] or not record["enabled"] or int(record["dispatch_to_signal_us"]) < 0 or not record["armed_after"]:
		_failures.append("Move input failed for %s at%.2f" % [phone, ui_scale])
	_records.append(record)
	main.free()
	await get_tree().process_frame
