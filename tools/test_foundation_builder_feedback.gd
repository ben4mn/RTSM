extends Node
## Production Main/HUD, paid placement, natural construction travel/progress and
## explicit replacement commands. Only builder damage is diagnostic; no worker
## positions, build progress or completion states are injected.

var _failures: Array[String] = []
var _main: Node
var _hud: CanvasLayer
var _map: Node2D
var _selection: SelectionManager
var _workers: Array[Villager] = []
var _foundation: BuildingBase
var _records: Array[Dictionary] = []
var _capture_dir: String = ""
var _profile_name: String = ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			_capture_dir = argument.trim_prefix("--capture-dir=")
	if not _capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_capture_dir)
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for scale_factor: float in [1.0, 1.075]:
			await _profile(phone, scale_factor)
	Engine.time_scale = 1.0
	if not _capture_dir.is_empty():
		var file := FileAccess.open(_capture_dir + "/manifest.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"evidence":"Native production Main/HUD from a real paid Barracks, natural walking/build progress, explicit Move/Stop/replacement Build. One diagnostic nonlethal damage triggers protective recovery; lethal damage removes the original builder. Other units/AI are frozen to isolate feedback. Enemy privacy guards use explicit query fixtures. No progress/completion/worker-position injection.", "profiles": _records}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] foundation_builder_feedback: " + failure)
	if _failures.is_empty():
		print("[PASS] foundation_builder_feedback: four phone profiles, paid en-route/build/recovery/resume, Move/Stop/dead builder needs replacement, explicit Main replacement completes naturally, hidden enemy assignment unchanged")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _profile(phone: Vector2i, scale_factor: float) -> void:
	_profile_name = "%dx%d-%s" % [phone.x, phone.y, "large" if scale_factor > 1.0 else "standard"]
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = scale_factor
	GameManager.set_state(GameManager.GameState.MENU)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 424242
	GameManager.selected_population_limit = 30
	_main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	for frame: int in range(900):
		if _main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	_expect(_main.get("_building_placement") != null, "Main did not initialize")
	Engine.time_scale = 4.0
	_main.get("ai_controller").set_process(false)
	_hud = _main.get("hud")
	_map = _main.get("game_map")
	_selection = _map.get("selection_mgr")
	_workers.clear()
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
		if unit is Villager and (unit as Villager).player_owner == 0:
			var worker: Villager = unit as Villager
			worker.command_stop()
			_workers.append(worker)
	var wood_before: int = ResourceManager.get_resource(0, "wood")
	_foundation = _place_barracks()
	if _foundation == null:
		_main.free()
		return
	_expect(wood_before - ResourceManager.get_resource(0, "wood") == 150, "foundation must use the real 150 Wood placement transaction")
	var builder: Villager = _find_builder()
	_expect(builder != null, "paid placement has no accepted builder")
	if builder == null:
		_main.free()
		return
	_expect(builder.current_state == UnitBase.State.BUILDING and is_zero_approx(_foundation.build_progress), "initial build travel must be accepted before any progress")
	_expect(float(_map.call("get_building_work_distance", builder.global_position, _foundation.global_position, _foundation.footprint)) > Villager.BUILD_APPROACH_DISTANCE, "en-route fixture is already at the work perimeter")
	_selection.select_single(_foundation)
	_map.get("camera").position = _foundation.global_position
	await _capture("enroute", "Building 0%")
	builder.set_process(true)
	await _wait_for_progress(0.03)
	builder.set_process(false)
	_expect(_foundation.build_progress >= 0.03 and _foundation.state == BuildingBase.State.CONSTRUCTING, "natural worker never began the paid foundation")
	await _capture("working", _percent_text())
	# Natural recovery preserves the accepted build order while State is MOVING.
	builder.take_damage(1.0)
	_expect(builder.is_auto_recovering() and builder.build_target == _foundation and builder.current_state == UnitBase.State.MOVING, "diagnostic hit did not preserve Build while retreating")
	_expect(builder.has_active_build_order() and bool(_main.call("_is_ai_builder_working_on", builder, _foundation)), "Main must retain an actually recovering Build order")
	await _capture("retreat", _percent_text())
	builder.set_process(true)
	await _wait_for_recovery(builder)
	builder.set_process(false)
	_expect(not builder.is_auto_recovering() and builder.current_state == UnitBase.State.BUILDING and builder.build_target == _foundation, "safe recovery did not resume the accepted Build")
	await _capture("resumed", _percent_text())
	# Target memory outlives manual cancellation. It must not imply active labor.
	builder.command_move((_main.get("_player_town_center") as BuildingBase).global_position)
	_expect(builder.build_target == _foundation and not builder.is_auto_recovering(), "manual Move fixture needs canceled stale target memory")
	await _capture("manual-move", "Needs builder")
	builder.command_stop()
	await _capture("stopped", "Needs builder")
	# A later hit on the now-idle worker retains stale target memory, but its
	# protective recovery no longer owns the canceled construction job.
	builder.take_damage(1.0)
	_expect(builder.is_auto_recovering() and int(builder.get("_recovery_work_state")) == UnitBase.State.IDLE and builder.build_target == _foundation, "canceled-build hit must create unrelated idle recovery")
	_expect(not builder.has_active_build_order() and not bool(_main.call("_is_ai_builder_working_on", builder, _foundation)), "Main must reject stale canceled Build memory during idle recovery")
	await _capture("canceled-retreat", "Needs builder")
	_expect(_workers.filter(func(worker: Villager) -> bool: return worker.current_state == UnitBase.State.BUILDING).is_empty(), "feedback changed another worker's order")
	_test_private_query_guards()
	builder.command_build(_foundation)
	builder.set_process(true)
	await _wait_for_progress(_foundation.build_progress + 0.03)
	builder.set_process(false)
	var progress_at_death: float = _foundation.build_progress
	builder.take_damage(builder.max_hp)
	_expect(is_instance_valid(builder) and builder.current_state == UnitBase.State.DEAD, "lethal damage must enter normal death before cleanup")
	_expect(str(_hud.call("_building_purpose", _foundation)) == "Needs builder", "fading dead builder still claims active construction")
	await _capture("dead-builder", "Needs builder")
	_expect(_foundation.build_progress == progress_at_death, "feedback progressed an unstaffed building")
	var replacement: Villager = null
	for worker: Villager in _workers:
		if is_instance_valid(worker) and worker != builder and worker.current_state != UnitBase.State.DEAD:
			replacement = worker
			break
	_expect(replacement != null and replacement.current_state == UnitBase.State.IDLE, "no free replacement or feedback stole idle labor")
	if replacement != null:
		_selection.select_single(replacement)
		_main.call("_on_build_command", _foundation)
		_expect(replacement.current_state == UnitBase.State.BUILDING and replacement.build_target == _foundation, "explicit selected-worker Main Build command failed")
		_selection.select_single(_foundation)
		await _capture("replacement-enroute", _percent_text())
		replacement.set_process(true)
		await _wait_for_progress(1.0)
		replacement.set_process(false)
		_expect(_foundation.state == BuildingBase.State.ACTIVE, "explicit replacement did not naturally complete the paid Barracks")
		await _capture("complete", "Trains Warriors")
	print("FOUNDATION_PROFILE ", JSON.stringify({"profile":_profile_name, "wood_paid":wood_before - ResourceManager.get_resource(0,"wood"), "natural_progress_before_death":progress_at_death, "completed":_foundation.state == BuildingBase.State.ACTIVE}))
	_main.free()
	await get_tree().process_frame


func _place_barracks() -> BuildingBase:
	var placement: BuildingPlacement = _main.get("_building_placement")
	var spawn: Vector2i = _map.get("map_generator").spawn_positions[0]
	var footprint: Vector2i = BuildingData.get_building_stats(BuildingData.BuildingType.BARRACKS).get("footprint", Vector2i(3, 3))
	var site := Vector2i(-1, -1)
	for radius: int in range(3, 10):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var candidate: Vector2i = spawn + Vector2i(dx, dy)
				var position: Vector2 = _map.call("tile_to_world", candidate)
				if not placement.revalidate_confirmation(BuildingData.BuildingType.BARRACKS, position, 0):
					continue
				var far_enough: bool = true
				for worker: Villager in _workers:
					if float(_map.call("get_building_work_distance", worker.global_position, position, footprint)) <= Villager.BUILD_APPROACH_DISTANCE + 16.0:
						far_enough = false
				if far_enough:
					site = candidate
					break
			if site.x >= 0:
				break
		if site.x >= 0:
			break
	_expect(site.x >= 0, "no legal visible paid Barracks site beyond the builder work perimeter")
	if site.x < 0:
		return null
	var count_before: int = (_main.get("_player_buildings")[0] as Array).size()
	_main.call("_on_placement_confirmed", BuildingData.BuildingType.BARRACKS, _map.call("tile_to_world", site))
	var buildings: Array = _main.get("_player_buildings")[0]
	_expect(buildings.size() == count_before + 1, "real paid Barracks placement failed")
	return buildings.back() as BuildingBase if buildings.size() == count_before + 1 else null


func _find_builder() -> Villager:
	for worker: Villager in _workers:
		if worker.build_target == _foundation and worker.current_state == UnitBase.State.BUILDING:
			return worker
	return null


func _wait_for_progress(minimum: float) -> void:
	var deadline: float = GameManager.game_time + 85.0
	var wall_deadline: int = Time.get_ticks_msec() + 20000
	while _foundation.build_progress < minimum and GameManager.game_time < deadline and Time.get_ticks_msec() < wall_deadline:
		await get_tree().process_frame


func _wait_for_recovery(builder: Villager) -> void:
	var deadline: float = GameManager.game_time + 45.0
	var wall_deadline: int = Time.get_ticks_msec() + 10000
	while builder.is_auto_recovering() and GameManager.game_time < deadline and Time.get_ticks_msec() < wall_deadline:
		await get_tree().process_frame


func _test_private_query_guards() -> void:
	# Deliberately inconsistent enemy assignment isolates the ownership query.
	var enemy: Villager = null
	for unit: Node in get_tree().get_nodes_in_group("units"):
		if unit is Villager and (unit as Villager).player_owner == 1:
			enemy = unit as Villager
			break
	if enemy != null:
		var old_target: Node2D = enemy.build_target
		var old_state: int = enemy.current_state
		enemy.build_target = _foundation
		enemy.set_state(UnitBase.State.BUILDING)
		_expect(str(_hud.call("_building_purpose", _foundation)) == "Needs builder", "foreign worker must not staff a human foundation")
		enemy.build_target = old_target
		enemy.set_state(old_state)
	# The enemy purpose string must not depend on hidden enemy assignments.
	var enemy_site := BuildingBase.new()
	enemy_site.building_type = BuildingData.BuildingType.BARRACKS
	enemy_site.player_owner = 1
	_main.add_child(enemy_site)
	enemy_site.start_construction()
	_expect(str(_hud.call("_building_purpose", enemy_site)) == "Building 0%", "enemy foundation leaked missing worker assignment")
	enemy_site.queue_free()
	# Even a queued-for-deletion live reference cannot accept future work.
	var departing: Villager = (load("res://scenes/units/villager.tscn") as PackedScene).instantiate()
	departing.player_owner = 0
	_main.add_child(departing)
	departing.command_build(_foundation)
	departing.queue_free()
	_expect(str(_hud.call("_building_purpose", _foundation)) == "Needs builder", "queued-free builder still claims construction")


func _percent_text() -> String:
	return "Building %d%%" % int(_foundation.build_progress * 100.0)


func _capture(state: String, expected: String) -> void:
	var label: Label = _hud.get("selection_details")
	# The normal 0.5s Main refresh follows simulation time, not a number of
	# process frames. Wait for its semantic result in either execution mode.
	var started: float = GameManager.game_time
	var wall_started: int = Time.get_ticks_msec()
	while not _caption_matches(label.text, expected) and GameManager.game_time < started + 2.0 and Time.get_ticks_msec() < wall_started + 2000:
		await get_tree().process_frame
	for frame: int in range(2):
		await get_tree().process_frame
	_expect(_caption_matches(label.text, expected), "%s caption expected %s, got %s" % [state, expected, label.text])
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	var width: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_expect(width <= minf(label.size.x, 88.0) + 0.05, "%s caption does not fit the compact 88px building column (text %.2f, column %.2f)" % [state, width, label.size.x])
	_expect(label.get_line_count() == label.get_visible_line_count(), state + " caption is vertically clipped")
	var image_name: String = _profile_name + "-" + state + ".png"
	if not _capture_dir.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		_expect(image.save_png(_capture_dir + "/" + image_name) == OK, "could not save native " + image_name)
	_records.append({"profile":_profile_name, "state":state, "text":label.text, "width":label.size.x, "text_width":width, "font_size":font_size, "height":label.size.y, "logical_rect":str(label.get_global_rect()), "image":image_name, "native_size":str(get_window().size), "native_final_transform":str(get_viewport().get_final_transform()), "refresh_wait_sim_seconds":GameManager.game_time-started, "refresh_wait_wall_ms":Time.get_ticks_msec()-wall_started})


func _caption_matches(actual: String, expected: String) -> bool:
	if not expected.begins_with("Building "):
		return actual == expected
	if not actual.begins_with("Building ") or not actual.ends_with("%"):
		return false
	var percentage: String = actual.trim_prefix("Building ").trim_suffix("%")
	if not percentage.is_valid_int():
		return false
	# A process boundary can display the immediately preceding progress tick.
	# The builder is frozen during captures; allow only a one-point rounding lag.
	return absi(int(percentage) - int(_foundation.build_progress * 100.0)) <= 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(_profile_name + ": " + message)
