extends Node
## Funded Castle fixture; all buildings and units use paid Main transactions.
## Synthetic elapsed queue completion isolates finishing policy from balance.
var failures: Array[String] = []
var main: Node
var ai: AIController
@export var easy_cap_fixture: bool = false
var evidence: Dictionary = {"scope": "funded Castle policy fixture; normal payment/construction/reservations; synthetic queue elapsed; not match pacing"}

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_population_limit = 20 if easy_cap_fixture else 30
	GameManager.selected_difficulty = 0 if easy_cap_fixture else 1
	GameManager.selected_map_seed = 42
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in range(900):
		if main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	ai = main.ai_controller
	ai.set_process(false)
	ai._decision_timer.stop()
	ai._game_time = 1200.0
	GameManager.players[1]["age"] = 3
	GameManager.increase_population_cap(1, 30)
	ResourceManager.initialize_player(1, {"food": 10000, "wood": 10000, "gold": 10000})
	var tc: BuildingBase = ai._find_trainable_building_of_type(BuildingData.BuildingType.TOWN_CENTER)
	for index: int in range(4 if easy_cap_fixture else 6):
		_expect(tc.get_production_queue().enqueue_unit(UnitData.UnitType.VILLAGER), "paid workforce trains")
		tc.get_production_queue().advance(17.0)
	_expect(tc.get_production_queue().enqueue_unit(UnitData.UnitType.SCOUT), "paid reconnaissance trains")
	tc.get_production_queue().advance(9.0)
	for kind: int in [BuildingData.BuildingType.BARRACKS, BuildingData.BuildingType.ARCHERY_RANGE, BuildingData.BuildingType.STABLE]:
		await _build_paid(kind)
	var barracks: BuildingBase = ai._find_trainable_building_of_type(BuildingData.BuildingType.BARRACKS)
	if barracks != null:
		for index: int in range(6 if easy_cap_fixture else 3):
			_expect(barracks.get_production_queue().enqueue_unit(UnitData.UnitType.INFANTRY), "paid escort trains")
			barracks.get_production_queue().advance(13.0)
	ai._update_ai_state()
	var targets: Dictionary = ai._get_target_building_counts(3)
	var plan: Array = ai._get_military_training_plan(ResourceManager.get_all_resources(1))
	evidence["before_workshop_targets"] = targets
	evidence["before_workshop_plan"] = plan
	_expect(int(targets.get(BuildingData.BuildingType.SIEGE_WORKSHOP, 0)) == 1, "mature Castle army enables exactly one workshop")
	_expect(BuildingData.BuildingType.SIEGE_WORKSHOP in ai._get_build_order(3), "compact construction can reach the workshop")
	var workshop: BuildingBase = await _build_paid(BuildingData.BuildingType.SIEGE_WORKSHOP)
	if workshop != null:
		var bank: Dictionary = ResourceManager.get_all_resources(1)
		var reserved: int = GameManager.get_committed_population(1)
		ai._check_military_production()
		var queue: ProductionQueue = workshop.get_production_queue()
		_expect(queue.get_queue_size() == 1 and queue.queue[0] == UnitData.UnitType.SIEGE, "policy buys a real Siege Engine ahead of more escorts")
		if queue.get_queue_size() > 0:
			_expect(ResourceManager.get_resource(1, "wood") == int(bank["wood"]) - 150 and ResourceManager.get_resource(1, "gold") == int(bank["gold"]) - 100, "siege pays exact shared cost")
			_expect(GameManager.get_committed_population(1) == reserved + 3, "siege reserves three population slots")
			queue.advance(36.0)
			evidence["paid_siege"] = ai._count_queued_unit(UnitData.UnitType.SIEGE)
			var living: int = 0
			for unit: UnitBase in ai._get_fighting_units():
				living += int(unit.unit_type == UnitData.UnitType.SIEGE)
			_expect(living == 1, "paid reservation converts to one living Siege Engine")
			ai._check_military_production()
			_expect(queue.get_queue_size() == 0, "living siege cannot monopolize the small population budget")
			for unit: UnitBase in ai._get_fighting_units():
				if unit.unit_type == UnitData.UnitType.SIEGE:
					unit.take_damage(unit.hp + 100.0)
			# Synthetic capacity fixture: less than three free slots must leave
			# the full bank intact rather than buying an unusable replacement.
			GameManager.players[1]["population"] = int(GameManager.players[1]["population_cap"]) - 2
			var blocked_bank: Dictionary = ResourceManager.get_all_resources(1)
			ai._check_military_production()
			_expect(queue.get_queue_size() == 0 and ResourceManager.get_all_resources(1) == blocked_bank, "insufficient siege slots cannot spend or oversubscribe population")
	GameManager.players[1]["age"] = 2
	_expect(int(ai._get_target_building_counts(2).get(BuildingData.BuildingType.SIEGE_WORKSHOP, 0)) == 0, "Feudal never unlocks a Castle workshop")
	evidence["failures"] = failures
	evidence["ai_source"] = load("res://scripts/ai/ai_controller.gd").get_source_code().sha256_text()
	evidence["easy_cap_fixture"] = easy_cap_fixture
	var output_path: String = "res://output/evolution/siege-before.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
	FileAccess.open(output_path, FileAccess.WRITE).store_string(JSON.stringify(evidence, "\t"))
	Engine.time_scale = 1.0
	main.free()
	for failure: String in failures:
		push_error(failure)
	print("[PASS] compact_siege_endgame" if failures.is_empty() else "[FAIL] compact_siege_endgame")
	get_tree().quit(0 if failures.is_empty() else 1)

func _build_paid(kind: int) -> BuildingBase:
	for unit: UnitBase in ai._get_villagers():
		unit.command_stop()
	var tile: Vector2i = ai._find_build_location(kind)
	_expect(tile != Vector2i(-1, -1), "visible legal paid build site exists for %d" % kind)
	if tile == Vector2i(-1, -1):
		return null
	main._on_ai_wants_to_build(kind, tile, false)
	var building: BuildingBase = ai._find_building_of_type(kind)
	_expect(building != null, "normal Main payment creates foundation %d" % kind)
	if building == null:
		return null
	Engine.time_scale = 4.0
	var deadline: float = GameManager.game_time + 120.0
	while building.state == BuildingBase.State.CONSTRUCTING and GameManager.game_time < deadline:
		await get_tree().process_frame
	_expect(building.state == BuildingBase.State.ACTIVE, "actual worker completes paid foundation %d" % kind)
	return building

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
