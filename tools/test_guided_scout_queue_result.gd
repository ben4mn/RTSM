extends SceneTree
## Guided Scout queue truthfulness plus complete, observable Select Military behavior.

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const PLAYER_ID := 0
const UNIT_VILLAGER := 0
const UNIT_INFANTRY := 1
const UNIT_SCOUT := 4
const GUIDED_STAGE_TRAIN_SCOUT := 2
const GAME_STATE_PLAYING := 2
const READY_FRAME_LIMIT := 900

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var audio_manager: Node = root.get_node("AudioManager")
	audio_manager.call("set_all_enabled", false)
	var game_manager: Node = root.get_node("GameManager")
	var resource_manager: Node = root.get_node("ResourceManager")
	game_manager.set("guided_opening_enabled", true)

	var main_scene: PackedScene = load(MAIN_SCENE_PATH)
	var match_scene: Node = main_scene.instantiate()
	root.add_child(match_scene)
	current_scene = match_scene
	if not await _wait_for(func() -> bool:
		var buildings_by_player: Array = match_scene.get("_player_buildings") as Array
		return (
			int(game_manager.get("current_state")) == GAME_STATE_PLAYING
			and not (buildings_by_player[PLAYER_ID] as Array).is_empty()
		)
	):
		_expect(false, "main scene did not reach PLAYING with a player building")
		_finish(match_scene)
		return

	var town_center: Node = null
	var player_buildings: Array = (match_scene.get("_player_buildings") as Array)[PLAYER_ID]
	for building: Node in player_buildings:
		if int(building.get("building_type")) == 0:
			town_center = building
			break
	if town_center == null:
		_expect(false, "player Town Center is unavailable")
		_finish(match_scene)
		return

	resource_manager.call("add_resource", PLAYER_ID, "food", 500)
	resource_manager.call("add_resource", PLAYER_ID, "gold", 500)
	var queue: Node = town_center.call("get_production_queue")
	_expect(bool(queue.call("enqueue_unit", UNIT_VILLAGER)), "setup Villager occupies the queue head")
	_arm_guided_scout_step(match_scene)
	match_scene.call("_on_train_unit_requested", town_center, UNIT_SCOUT)
	_expect_eq(queue.get("queue"), [UNIT_VILLAGER, UNIT_SCOUT], "Scout remains queued behind the existing Villager")
	_expect_eq(match_scene.get("_last_train_request_result"), "queued", "successful enqueue keeps the queued result")
	_expect_eq(match_scene.get("_last_train_feedback"), "", "queued Scout has no failure feedback")

	# The same onboarding shortcut still completes immediately when Scout is the head.
	_expect(bool(queue.call("cancel_unit", 1)), "queued Scout cleanup succeeds")
	_expect(bool(queue.call("cancel_unit", 0)), "queued Villager cleanup succeeds")
	var player_units: Array = (match_scene.get("_player_units") as Array)[PLAYER_ID]
	var units_before: int = player_units.size()
	_arm_guided_scout_step(match_scene)
	match_scene.call("_on_train_unit_requested", town_center, UNIT_SCOUT)
	_expect_eq(match_scene.get("_last_train_request_result"), "fast_track_completed", "head Scout still fast-tracks")
	_expect_eq(queue.call("get_queue_size"), 0, "fast-tracked Scout leaves no queue entry")
	_expect_eq(player_units.size(), units_before + 1, "fast-tracked Scout spawns exactly once")

	# The guided Scout is auto-selected. The Select Military shortcut must still
	# execute, replace that partial selection with the complete army, and retain
	# durable evidence for touch-only runtime validation.
	var scout: Node2D = player_units.back() as Node2D
	var infantry: Node2D = match_scene.call(
		"_spawn_unit",
		UNIT_INFANTRY,
		PLAYER_ID,
		scout.global_position + Vector2(24.0, 0.0)
	) as Node2D
	_expect(infantry != null, "military shortcut fixture Infantry spawns")
	if infantry != null:
		var selection_manager: Node = match_scene.get_node("GameMap/SelectionManager")
		selection_manager.call("select_single", scout)
		var shortcut_before: Dictionary = match_scene.get("first_session_diagnostics") as Dictionary
		match_scene.call("_select_all_military")
		var shortcut_after: Dictionary = match_scene.get("first_session_diagnostics") as Dictionary
		_expect_eq(
			int(shortcut_after.get("military_shortcut_invocation_count", 0)),
			int(shortcut_before.get("military_shortcut_invocation_count", 0)) + 1,
			"Select Military records one fresh invocation"
		)
		_expect(
			int(shortcut_after.get("military_shortcut_last_timestamp_ms", 0))
			> int(shortcut_before.get("military_shortcut_last_timestamp_ms", 0)),
			"Select Military records a fresh monotonic timestamp"
		)
		_expect_eq(
			int(shortcut_after.get("military_shortcut_selected_count", 0)),
			2,
			"Select Military replaces an existing Scout selection with the complete army"
		)
		var selected_paths: Array = shortcut_after.get("military_shortcut_selected_paths", []) as Array
		_expect(selected_paths.has(str(scout.get_path())), "shortcut evidence includes the guided Scout")
		_expect(selected_paths.has(str(infantry.get_path())), "shortcut evidence includes the Infantry")

	_finish(match_scene)


func _arm_guided_scout_step(match_scene: Node) -> void:
	match_scene.set("_guided_opening_active", true)
	match_scene.set("_guided_stage", GUIDED_STAGE_TRAIN_SCOUT)
	match_scene.set("_opening_scout_queued", false)


func _wait_for(predicate: Callable) -> bool:
	for _frame in READY_FRAME_LIMIT:
		if predicate.call():
			return true
		await process_frame
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("[FAIL] guided_scout_queue_result: %s" % message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


func _finish(match_scene: Node) -> void:
	if is_instance_valid(match_scene):
		match_scene.free()
	current_scene = null
	if _failures.is_empty():
		print("[PASS] guided_scout_queue_result: queue truthfulness and observable full-army shortcut")
		quit(0)
	else:
		quit(1)
