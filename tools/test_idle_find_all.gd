extends Node
## G1: Find idle selects the next idle worker; a second press right after
## selects every idle worker, so a crew left idle by a finished berry patch
## takes one order. A slow second press keeps cycling one at a time.

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	GameManager.guided_opening_enabled = false
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	var map: Node = main.get_node("GameMap")
	var selection: SelectionManager = map.get("selection_mgr")
	main.set_process(false)
	main.get_node("AIController").set_process(false)
	var villagers: Array[Villager] = []
	for unit: Variant in main.get("_player_units")[0]:
		if is_instance_valid(unit) and unit is Villager:
			(unit as Villager).command_stop()
			villagers.append(unit as Villager)
	await get_tree().process_frame
	var idle: int = 0
	for villager: Villager in villagers:
		if villager.current_state == UnitBase.State.IDLE:
			idle += 1
	_expect(idle >= 3, "fixture: at least three idle workers (got %d)" % idle)

	main.call("_on_idle_villager_pressed")
	_expect(selection.selected.size() == 1 and selection.selected[0] is Villager, "first Find idle selects one worker")
	main.call("_on_idle_villager_pressed")
	_expect(selection.selected.size() == idle, "second quick Find idle selects all %d idle workers (got %d)" % [idle, selection.selected.size()])
	# The window resets: the next press cycles a single worker again.
	main.call("_on_idle_villager_pressed")
	_expect(selection.selected.size() == 1, "after selecting all, the next press cycles one worker")
	main.set("_idle_find_last_msec", Time.get_ticks_msec() - 5000)
	main.call("_on_idle_villager_pressed")
	_expect(selection.selected.size() == 1, "a slow second press keeps cycling one worker")

	main.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("[PASS] idle_find_all: Find idle cycles one worker; a quick second press selects every idle worker")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] idle_find_all: %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
