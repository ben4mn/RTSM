extends SceneTree
## Enemy buildings are inspect-only: neither Main nor HUD may expose or mutate
## their production queue, auto-queue setting, resources, population, or research.

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const BLACKSMITH_SCENE_PATH := "res://scenes/buildings/blacksmith.tscn"
const PLAYER_HUMAN := 0
const PLAYER_AI := 1
const BUILDING_TOWN_CENTER := 0
const UNIT_VILLAGER := 0
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
	game_manager.set("guided_opening_enabled", false)

	var packed_main: PackedScene = load(MAIN_SCENE_PATH)
	var match_scene: Node = packed_main.instantiate()
	root.add_child(match_scene)
	current_scene = match_scene
	if not await _wait_for(func() -> bool:
		var buildings_by_player: Array = match_scene.get("_player_buildings") as Array
		return (
			int(game_manager.get("current_state")) == GAME_STATE_PLAYING
			and not (buildings_by_player[PLAYER_HUMAN] as Array).is_empty()
			and not (buildings_by_player[PLAYER_AI] as Array).is_empty()
		)
	):
		_expect(false, "main scene did not reach PLAYING with both players' buildings")
		_finish(match_scene)
		return

	# Freeze autonomous simulation so every before/after snapshot measures only
	# the command being exercised.
	paused = true
	match_scene.set_process(false)
	match_scene.set_physics_process(false)
	var ai_controller: Node = match_scene.get_node("AIController")
	ai_controller.set_process(false)
	ai_controller.set_physics_process(false)

	var human_tc: Node2D = _find_town_center(match_scene, PLAYER_HUMAN)
	var enemy_tc: Node2D = _find_town_center(match_scene, PLAYER_AI)
	_expect(human_tc != null, "human Town Center fixture exists")
	_expect(enemy_tc != null, "enemy Town Center fixture exists")
	if human_tc == null or enemy_tc == null:
		_finish(match_scene)
		return

	var human_queue: Node = human_tc.call("get_production_queue")
	var enemy_queue: Node = enemy_tc.call("get_production_queue")
	_expect(human_queue != null, "human Town Center has a production queue")
	_expect(enemy_queue != null, "enemy Town Center has a production queue")
	if human_queue == null or enemy_queue == null:
		_finish(match_scene)
		return

	resource_manager.call("add_resource", PLAYER_HUMAN, "food", 2000)
	resource_manager.call("add_resource", PLAYER_HUMAN, "gold", 2000)
	resource_manager.call("add_resource", PLAYER_AI, "food", 2000)
	resource_manager.call("add_resource", PLAYER_AI, "gold", 2000)
	game_manager.call("increase_population_cap", PLAYER_HUMAN, 20)
	game_manager.call("increase_population_cap", PLAYER_AI, 20)
	_clear_queue(human_queue)
	_clear_queue(enemy_queue)
	enemy_queue.set("auto_queue_enabled", false)
	_expect(enemy_queue.call("enqueue_unit", UNIT_VILLAGER), "enemy queue setup succeeds through its legitimate owner path")

	var hud: CanvasLayer = match_scene.get_node("HUD") as CanvasLayer
	# Main deliberately withholds private queue/train data. HUD independently
	# sanitizes even deliberately hostile input, which protects future callers.
	var enemy_selection: Array[Node2D] = [enemy_tc]
	match_scene.call("_on_selection_changed", enemy_selection)
	hud.call(
		"show_building_selection",
		enemy_tc.get("building_name"),
		enemy_tc.get("hp"),
		enemy_tc.get("max_hp"),
		enemy_queue.call("get_queue_info"),
		enemy_tc.get("trainable_units"),
		enemy_tc
	)
	await process_frame
	_assert_enemy_production_controls_hidden(hud)

	var hostile_before: Dictionary = _snapshot_player_state(game_manager, resource_manager, enemy_queue, PLAYER_AI)
	match_scene.call("_on_train_unit_requested", enemy_tc, UNIT_VILLAGER)
	_expect_eq(match_scene.get("_last_train_request_result"), "not_owned", "Main rejects enemy training explicitly")
	_assert_player_state_unchanged(hostile_before, game_manager, resource_manager, enemy_queue, PLAYER_AI, "enemy Main train")

	match_scene.call("_on_cancel_queue_requested", enemy_tc, 0)
	_assert_player_state_unchanged(hostile_before, game_manager, resource_manager, enemy_queue, PLAYER_AI, "enemy Main queue cancel")

	# Direct HUD callbacks are guarded too, including Auto Queue's historical
	# direct write to ProductionQueue.
	hud.call("_on_train_button_pressed", UNIT_VILLAGER)
	hud.call("_on_cancel_queue_pressed", 0)
	hud.call("_on_clear_all_queue_pressed")
	hud.call("_on_auto_queue_toggled", true)
	_assert_player_state_unchanged(hostile_before, game_manager, resource_manager, enemy_queue, PLAYER_AI, "enemy HUD production actions")
	_expect(not bool(enemy_queue.get("auto_queue_enabled")), "enemy HUD Auto Queue toggle is a no-op")
	var train_diag: Dictionary = hud.get("train_action_diagnostics") as Dictionary
	_expect(not bool(train_diag.get("request_emitted", true)), "enemy HUD Train does not emit a request")

	var enemy_blacksmith: Node2D = _make_blacksmith(match_scene, PLAYER_AI)
	_expect(enemy_blacksmith != null, "enemy Blacksmith fixture exists")
	if enemy_blacksmith != null:
		hud.call(
			"show_building_selection",
			enemy_blacksmith.get("building_name"),
			enemy_blacksmith.get("hp"),
			enemy_blacksmith.get("max_hp"),
			[],
			[],
			enemy_blacksmith
		)
		await process_frame
		var research_container: HBoxContainer = hud.get("_research_container") as HBoxContainer
		_expect(research_container == null or not research_container.visible, "enemy Blacksmith exposes no research controls")
		var research_before: Dictionary = _snapshot_player_state(game_manager, resource_manager, enemy_queue, PLAYER_AI)
		match_scene.call("_on_research_requested", enemy_blacksmith, "forging")
		hud.call("_on_research_pressed", "forging")
		_assert_player_state_unchanged(research_before, game_manager, resource_manager, enemy_queue, PLAYER_AI, "enemy research")
		_expect(not game_manager.call("has_research", PLAYER_AI, "forging"), "enemy forging remains incomplete")

	# Friendly production still spends/reserves, cancel still refunds/releases,
	# Auto Queue still toggles, and a valid Blacksmith can still research.
	var friendly_before: Dictionary = _snapshot_player_state(game_manager, resource_manager, human_queue, PLAYER_HUMAN)
	match_scene.call("_on_train_unit_requested", human_tc, UNIT_VILLAGER)
	_expect_eq(human_queue.call("get_queue_size"), int((friendly_before["queue"] as Array).size()) + 1, "friendly Train queues one unit")
	_expect(
		int(game_manager.call("get_reserved_population", PLAYER_HUMAN)) > int(friendly_before["reserved_population"]),
		"friendly Train reserves population"
	)
	_expect(
		int(resource_manager.call("get_resource", PLAYER_HUMAN, "food")) < int((friendly_before["resources"] as Dictionary)["food"]),
		"friendly Train spends resources"
	)
	match_scene.call("_on_cancel_queue_requested", human_tc, int(human_queue.call("get_queue_size")) - 1)
	_assert_player_state_unchanged(friendly_before, game_manager, resource_manager, human_queue, PLAYER_HUMAN, "friendly train then cancel")

	hud.call("show_building_selection", human_tc.get("building_name"), human_tc.get("hp"), human_tc.get("max_hp"), [], human_tc.get("trainable_units"), human_tc)
	hud.call("_on_auto_queue_toggled", true)
	_expect(bool(human_queue.get("auto_queue_enabled")), "friendly HUD Auto Queue remains functional")
	hud.call("_on_auto_queue_toggled", false)

	var human_blacksmith: Node2D = _make_blacksmith(match_scene, PLAYER_HUMAN)
	_expect(human_blacksmith != null, "human Blacksmith fixture exists")
	if human_blacksmith != null:
		var human_food_before: int = int(resource_manager.call("get_resource", PLAYER_HUMAN, "food"))
		var human_gold_before: int = int(resource_manager.call("get_resource", PLAYER_HUMAN, "gold"))
		var attack_before: int = int((game_manager.get("player_upgrades") as Dictionary)[PLAYER_HUMAN]["attack_bonus"])
		match_scene.call("_on_research_requested", human_blacksmith, "forging")
		_expect(game_manager.call("has_research", PLAYER_HUMAN, "forging"), "friendly Blacksmith research remains functional")
		_expect_eq(int(resource_manager.call("get_resource", PLAYER_HUMAN, "food")), human_food_before - 100, "friendly research spends food")
		_expect_eq(int(resource_manager.call("get_resource", PLAYER_HUMAN, "gold")), human_gold_before - 50, "friendly research spends gold")
		_expect_eq(
			int((game_manager.get("player_upgrades") as Dictionary)[PLAYER_HUMAN]["attack_bonus"]),
			attack_before + 2,
			"friendly research applies its upgrade"
		)

	_finish(match_scene)


func _find_town_center(match_scene: Node, player_id: int) -> Node2D:
	var buildings_by_player: Array = match_scene.get("_player_buildings") as Array
	for candidate: Node in buildings_by_player[player_id] as Array:
		if candidate is Node2D and int(candidate.get("building_type")) == BUILDING_TOWN_CENTER:
			return candidate as Node2D
	return null


func _make_blacksmith(match_scene: Node, player_id: int) -> Node2D:
	var packed_blacksmith: PackedScene = load(BLACKSMITH_SCENE_PATH)
	var blacksmith: Node2D = packed_blacksmith.instantiate() as Node2D
	blacksmith.set("player_owner", player_id)
	blacksmith.set("state", 2)
	match_scene.get_node("GameMap/BuildingsContainer").add_child(blacksmith)
	return blacksmith


func _clear_queue(queue: Node) -> void:
	queue.set("auto_queue_enabled", false)
	for index in range(int(queue.call("get_queue_size")) - 1, -1, -1):
		queue.call("cancel_unit", index)


func _snapshot_player_state(game_manager: Node, resource_manager: Node, queue: Node, player_id: int) -> Dictionary:
	var players: Dictionary = game_manager.get("players") as Dictionary
	var upgrades: Dictionary = game_manager.get("player_upgrades") as Dictionary
	var researched: Dictionary = game_manager.get("researched_upgrades") as Dictionary
	return {
		"resources": resource_manager.call("get_all_resources", player_id),
		"population": int((players[player_id] as Dictionary).get("population", 0)),
		"reserved_population": int(game_manager.call("get_reserved_population", player_id)),
		"population_cap": int((players[player_id] as Dictionary).get("population_cap", 0)),
		"upgrades": (upgrades.get(player_id, {}) as Dictionary).duplicate(true),
		"researched": (researched.get(player_id, []) as Array).duplicate(),
		"queue": (queue.get("queue") as Array).duplicate(),
	}


func _assert_enemy_production_controls_hidden(hud: CanvasLayer) -> void:
	var queue_container: HBoxContainer = hud.get("queue_container") as HBoxContainer
	var train_container: HBoxContainer = hud.get("_train_buttons_container") as HBoxContainer
	var auto_queue_button: BaseButton = hud.get("_auto_queue_button") as BaseButton
	_expect(not queue_container.visible, "enemy production queue is hidden")
	_expect(train_container == null or not train_container.visible, "enemy Train controls are hidden")
	_expect(auto_queue_button == null or not is_instance_valid(auto_queue_button) or not auto_queue_button.visible, "enemy Auto Queue control is hidden")


func _assert_player_state_unchanged(
	before: Dictionary,
	game_manager: Node,
	resource_manager: Node,
	queue: Node,
	player_id: int,
	context: String
) -> void:
	var after: Dictionary = _snapshot_player_state(game_manager, resource_manager, queue, player_id)
	_expect_eq(after, before, "%s leaves resources, population, upgrades, research, and queue unchanged" % context)


func _wait_for(predicate: Callable) -> bool:
	for _frame in READY_FRAME_LIMIT:
		if predicate.call():
			return true
		await process_frame
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("[FAIL] enemy_building_controls: %s" % message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


func _finish(match_scene: Node) -> void:
	paused = false
	if is_instance_valid(match_scene):
		match_scene.free()
	current_scene = null
	if _failures.is_empty():
		print("[PASS] enemy_building_controls: enemy inspect-only guards and friendly actions")
		quit(0)
	else:
		quit(1)
