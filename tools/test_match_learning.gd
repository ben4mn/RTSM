extends Node
## Ordinary paid queues under controlled main-scene fixtures. Synthetic funds,
## completed production buildings and damage are labeled; this is behavior QA.

@onready var root: Window = get_tree().root
var failures: Array[String] = []
var evidence: Dictionary = {"scope": "Deterministic main scene with paid production; injected completed buildings/funds and damage; no human/device enjoyment claim", "checks": []}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var gm: Node = root.get_node("GameManager")
	root.get_node("AudioManager").set_all_enabled(false)
	gm.set("guided_opening_enabled", false)
	gm.set("selected_map_seed", 42)
	gm.set("selected_population_limit", 30)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	get_tree().current_scene = main
	for _i in range(900):
		if main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	main.set_process(false)
	main.get_node("AIController").set_process(false)
	var hud: Node = main.get_node("HUD")
	var coach: RefCounted = main.get("_match_learning")
	# Public kingdom choices name the recruit and the actually observed enemy.
	# These isolated copy checks do not create actors or reveal enemy locations.
	var names_coach: RefCounted = load("res://scripts/main/match_learning.gd").new()
	names_coach.paid_army = 1
	var own_civilization: int = int(gm.players[0].get("civilization", 0))
	var enemy_civilization: int = int(gm.players[1].get("civilization", 0))
	gm.players[0]["civilization"] = CivilizationData.Civilization.VERDANT_LEAGUE
	gm.players[1]["civilization"] = CivilizationData.Civilization.SUNSTRIDE_CLANS
	var unscouted_lesson: Dictionary = names_coach.call("_choose_lesson", [], {})
	_expect("Add Longbows" in str(unscouted_lesson.text), "Unscouted counter lesson names the local kingdom recruit")
	names_coach.visible_enemy_roles = {UnitData.UnitType.CAVALRY: true}
	var cavalry_lesson: Dictionary = names_coach.call("_choose_lesson", [], {})
	_expect("Enemy Outrider: recruit Warrior" in str(cavalry_lesson.text), "Observed cavalry lesson names the public rival signature")
	names_coach.visible_enemy_roles = {UnitData.UnitType.INFANTRY: true}
	var infantry_lesson: Dictionary = names_coach.call("_choose_lesson", [], {})
	_expect("Enemy Warrior: recruit Longbow" in str(infantry_lesson.text), "Observed infantry lesson names the local signature counter")
	gm.players[0]["civilization"] = own_civilization
	gm.players[1]["civilization"] = enemy_civilization
	_expect(not coach.active and not hud.get("_progression_hint_panel").visible, "Free play starts without lessons")
	main.call("_on_pause_requested")
	await get_tree().process_frame
	var learn_button: Button = hud.get("_match_learning_button")
	_expect(learn_button != null and learn_button.size.y >= 48.0, "Pause offers a reachable 48px Learn full match action")
	learn_button.pressed.emit()
	await get_tree().process_frame
	_expect(coach.active and gm.get("current_state") == 2, "Learn action opts in and resumes match")
	_expect(not hud.get("_early_game_ui_active"), "Battle lessons preserve full controls")
	var rm: Node = root.get_node("ResourceManager")
	for resource in ["food", "wood", "gold"]:
		rm.add_resource(0, resource, 2500)
	gm.players[0]["population_cap"] = 30
	var tc: BuildingBase = main.get("_player_town_center")
	main.call("_on_train_unit_requested", tc, UnitData.UnitType.SCOUT)
	main.call("_advance_production_queues", 8.1)
	_expect(coach.paid_army == 0, "Paid reconnaissance Scout never counts as a fighting army")
	var barracks: BuildingBase = main.call("_spawn_building", BuildingData.BuildingType.BARRACKS, 0, Vector2i(10, 10))
	barracks.call("_complete_construction")
	var queue: ProductionQueue = barracks.get_production_queue()
	var before_food: int = rm.get_resource(0, "food")
	main.call("_on_train_unit_requested", barracks, UnitData.UnitType.INFANTRY)
	_expect(rm.get_resource(0, "food") == before_food - 50, "Warrior uses normal paid cost")
	main.call("_update_progression_hint")
	_expect(coach.paid_army == 0 and coach.lesson == "army", "Queued troop does not complete army lesson")
	queue.cancel_all()
	_expect(coach.paid_army == 0, "Canceled recruitment earns no lesson credit")
	main.call("_on_train_unit_requested", barracks, UnitData.UnitType.INFANTRY)
	main.call("_advance_production_queues", 12.1)
	main.call("_update_progression_hint")
	_expect(coach.paid_army == 1 and coach.lesson == "counters", "Real paid Warrior birth advances into counters")
	var warrior: UnitBase = null
	for unit in main.get("_player_units")[0]:
		if unit.unit_type == UnitData.UnitType.INFANTRY:
			warrior = unit
	var range_building: BuildingBase = main.call("_spawn_building", BuildingData.BuildingType.ARCHERY_RANGE, 0, Vector2i(14, 10))
	range_building.call("_complete_construction")
	main.call("_on_train_unit_requested", range_building, UnitData.UnitType.ARCHER)
	main.call("_advance_production_queues", 16.1)
	main.call("_update_progression_hint")
	_expect(coach.paid_army == 2 and coach.lesson == "objective", "Two living paid combat roles advance into objective guidance")
	_expect(bool(coach.get_summary()["counter_demonstrated"]), "Counter mix is based on fielded paid roles")
	var custom_status_hint: Dictionary = coach.call("_choose_lesson", [], {"phase": "holding", "owner": 0, "match_mode": SkirmishData.MatchMode.STANDARD, "total": 360.0})
	_expect(String(custom_status_hint.get("text", "")).begins_with("Sacred · Hold for 6:00."), "Objective lesson formats the supplied 360-second site target instead of a fixed ten minutes")
	warrior.take_damage(30)
	main.call("_update_progression_hint")
	_expect(coach.lesson == "retreat", "Real damage prioritizes deliberate retreat guidance")
	warrior.take_damage(1000)
	main.call("_update_progression_hint")
	_expect(coach.lesson == "recovery" and coach.army_losses == 1, "Actual army loss prioritizes paid replacement")
	main.call("_on_train_unit_requested", barracks, UnitData.UnitType.INFANTRY)
	_expect(coach.army_replacements == 0, "Queued replacement does not earn recovery credit")
	main.call("_advance_production_queues", 12.1)
	main.call("_update_progression_hint")
	_expect(coach.army_replacements == 1 and coach.lesson == "objective", "Paid replacement birth completes recovery")
	var worker: UnitBase = main.get("_player_units")[0][0]
	worker.take_damage(1000)
	main.call("_update_progression_hint")
	_expect(coach.worker_losses == 1 and coach.lesson == "recovery", "Real worker loss prioritizes economy recovery")
	main.call("_on_train_unit_requested", tc, UnitData.UnitType.VILLAGER)
	_expect(coach.worker_replacements == 0, "Queued worker does not complete economy recovery")
	main.call("_advance_production_queues", 16.1)
	main.call("_update_progression_hint")
	_expect(coach.worker_replacements == 1 and coach.lesson == "objective", "Actual paid worker restores economy recovery lesson")
	hud.get("_guidance_dismiss_button").pressed.emit()
	_expect(not coach.active and not hud.get("_progression_hint_panel").visible and not hud.get("_guidance_dismiss_button").visible, "Skip clears optional lessons and action targets")
	main.call("_update_progression_hint")
	_expect(not hud.get("_progression_hint_panel").visible, "Refresh leaves free play clean")
	main.call("_conclude_match", 1, "Sacred Site held for 10:00")
	var summary: Dictionary = main.get("match_summary_diagnostics")
	_expect(summary.has("learning") and summary["learning"]["paid_army"] == 3 and summary["learning"]["army_replacements"] == 1, "Match conclusion preserves actual paid training/replacement receipts")
	get_tree().paused = false
	evidence["match_summary"] = summary
	evidence["summary"] = coach.get_summary()
	_write_evidence()
	main.free()
	get_tree().current_scene = null
	await get_tree().process_frame
	if failures.is_empty():
		print("[PASS] match_learning: optional entry, paid completion, counters, damage, replacements and clean Skip")
		get_tree().quit(0)
	else:
		get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	evidence["checks"].append({"pass": condition, "message": message})
	if not condition:
		failures.append(message)
		push_error("[FAIL] match_learning: " + message)


func _write_evidence() -> void:
	DirAccess.make_dir_recursive_absolute("res://output/evolution/learning-20261010-battle-lessons")
	var output := FileAccess.open("res://output/evolution/learning-20261010-battle-lessons/paid-lesson-behavior.json", FileAccess.WRITE)
	if output:
		output.store_string(JSON.stringify(evidence, "\t"))
