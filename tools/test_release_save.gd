extends Node
## 0.4.0 release save gate.
## 1. A checkpoint left by an older version (schema 1 = beta 33 live, schema 2 =
##    pre-rebalance joy pass) is refused without a crash: no Resume, a friendly
##    menu note, and a new solo start clears it.
## 2. A checkpoint taken mid-match with this release's systems all busy at
##    once (garrisoned villagers and the bell, research in progress, a fallow
##    Farm, a drained Sacred clock, wildlife with an opened carcass) resumes
##    through the real Main lifecycle with every one of them intact.
const STATE = preload("res://scripts/main/solo_match_state.gd")

var checks: int = 0
var failures: Array[String] = []
var main: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _wait_main() -> bool:
	main = null
	for frame: int in 900:
		await get_tree().process_frame
		var scene: Node = get_tree().current_scene
		if scene != null and scene.get("_building_placement") != null:
			main = scene
			await get_tree().process_frame
			main.process_mode = Node.PROCESS_MODE_DISABLED
			return true
	check(false, "Main initialized within bounded frames")
	return false


func _finish() -> void:
	print(JSON.stringify({"test": "release_save", "checks": checks, "failures": failures}))
	SoloSave.discard_save("release_save_fixture")
	if is_instance_valid(main):
		main.queue_free()
		await get_tree().process_frame
	for failure: String in failures:
		push_error("[FAIL] release_save: " + failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func _write_slots(payload: String) -> void:
	for path: String in SoloSave.SLOTS:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(payload)
		file.close()


func _run() -> void:
	get_tree().current_scene = null
	AudioManager.set_all_enabled(false)
	SoloSave.set_process(false)
	SoloSave.discard_save("release_save_fixture")
	GameManager.selected_map_seed = 515151
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	GameManager.guided_opening_enabled = false
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	if not await _wait_main():
		await _finish()
		return
	var map: Node2D = main.game_map
	var tc: BuildingBase = main._player_town_center
	for owner: int in 2:
		ResourceManager._player_resources[owner] = {"food": 3000, "wood": 3000, "gold": 3000}

	# --- 1. Old-version checkpoints ------------------------------------------
	var current: Dictionary = STATE.new().capture(main)
	check(STATE.validate(current).is_empty(), "a current capture validates: " + STATE.validate(current))
	for old_schema: int in [1, 2]:
		var old: Dictionary = current.duplicate(true)
		old.schema = old_schema
		check(STATE.validate(old) == "This save belongs to a different game version.", "schema %d is refused with the version message" % old_schema)
		_write_slots(SoloSave._envelope(old, 7))
		SoloSave.reload_save()
		check(not SoloSave.has_save() and SoloSave.has_outdated_save(), "schema %d: no Resume, marked as an older version" % old_schema)
		check(not SoloSave.resume_match(), "schema %d: resume is refused, not attempted" % old_schema)
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	var note: Label = menu.get("_home_note") as Label
	check(note != null and note.visible and note.text.contains("older version"), "the menu explains the old save (%s)" % (note.text if note != null else "no note"))
	check(not (menu.get("_resume_button") as Button).visible, "the menu offers no Resume for it")
	menu.queue_free()
	await get_tree().process_frame
	# The menu returns the global state to MENU; this match is still running.
	GameManager.set_state(GameManager.GameState.PLAYING)
	_write_slots("{not json")
	SoloSave.reload_save()
	check(not SoloSave.has_save() and not SoloSave.has_outdated_save(), "a corrupt file is not called an older version")
	_write_slots(SoloSave._envelope(current.merged({"schema": 2}, true), 7))
	SoloSave.reload_save()
	SoloSave.discard_save("new_match")
	check(not SoloSave.has_outdated_save() and not FileAccess.file_exists(SoloSave.SLOTS[0]) and not FileAccess.file_exists(SoloSave.SLOTS[1]), "starting a new solo match clears the old checkpoint")

	# --- 2. Busy mid-match checkpoint -----------------------------------------
	# Discarding forgot the match, as a real new start would before attach.
	SoloSave._main_ref = weakref(main)
	var villagers: Array = main._player_units[0].filter(func(unit: Node) -> bool: return unit is Villager)
	check(villagers.size() >= 3, "starting villagers present")
	# Bell and garrison: two villagers inside the Town Center.
	check(Garrison.ring(tc), "town bell rings")
	var inside_ids: Array[int] = []
	for worker: Villager in villagers.slice(0, 2):
		if Garrison.enter(tc, worker):
			inside_ids.append(worker.get_instance_id())
	check(Garrison.count(tc) == 2, "two villagers are garrisoned (%d)" % Garrison.count(tc))
	# Research in progress at the Town Center.
	var loom_blocked: String = GameManager.get_research_failure_reason(0, tc, "loom")
	check(GameManager.try_start_research(0, tc, "loom"), "Loom starts (%s)" % loom_blocked)
	tc.research_progress = 6.5
	var research_duration: float = tc.research_duration
	# A fallow Farm, and a growing one with a part-eaten field.
	var spot: Vector2i = map.world_to_tile(tc.global_position)
	var fallow: BuildingBase = null
	var growing: BuildingBase = null
	for offset: Vector2i in [Vector2i(-6, 4), Vector2i(6, 4), Vector2i(-6, -5), Vector2i(6, -5), Vector2i(0, 7), Vector2i(0, -7)]:
		var position: Vector2 = map.tile_to_world(spot + offset)
		if growing != null:
			break
		if main._building_placement.revalidate_confirmation(BuildingData.BuildingType.FARM, position, 0):
			var farm: BuildingBase = main._spawn_building(BuildingData.BuildingType.FARM, 0, spot + offset)
			farm.complete_instantly()
			FarmPlots.ensure_sown(farm)
			if fallow == null:
				fallow = farm
			else:
				growing = farm
	check(fallow != null and growing != null, "two Farms placed")
	if fallow == null or growing == null:
		await _finish()
		return
	FarmPlots.take(fallow, fallow.farm_food_remaining)
	check(fallow.farm_fallow and fallow.farm_food_remaining == 0, "the first Farm is fallow")
	FarmPlots.take(growing, 41)
	var growing_food: int = growing.farm_food_remaining
	# A drained Sacred clock: held, then left, part of the time drained away.
	var site: Node = map.sacred_site
	site.state = site.SiteState.CAPTURED
	site.owning_player = 0
	site.victory_timer = 97.25
	site.control_banks.assign([97.25, 14.5])
	site.clock_ticking = false
	site.garrison_paused = false
	# Wildlife: an opened home carcass.
	var director: WildlifeDirector = WildlifeDirector.of(main)
	var carcass: WildlifeNode = null
	for node: WildlifeNode in director.nodes:
		if node.owner_id == 0 and node.kind == WildlifeData.SHEEP:
			carcass = node
			break
	check(carcass != null, "a home sheep exists")
	carcass.harvest(11)
	var carcass_id: int = carcass.wildlife_id
	var carcass_left: int = carcass.remaining
	var animals: int = director.nodes.size()
	GameManager.game_time = 431.0
	var expected: Dictionary = {
		"bank": ResourceManager._player_resources[0].duplicate(true), "population": int(GameManager.players[0].population),
		"cap": int(GameManager.players[0].population_cap), "units": main._player_units[0].size(), "buildings": main._player_buildings[0].size(),
	}
	var data: Dictionary = STATE.new().capture(main)
	check(STATE.validate(data).is_empty(), "the busy capture validates: " + STATE.validate(data))
	check(SoloSave.save_current("release_save"), "the busy checkpoint is written")
	check(SoloSave.has_save() and not SoloSave.has_outdated_save(), "the new checkpoint replaces any old-version note")
	var tc_tile: Vector2i = map.world_to_tile(tc.global_position)
	var fallow_tile: Vector2i = map.world_to_tile(fallow.global_position)
	var growing_tile: Vector2i = map.world_to_tile(growing.global_position)
	check(SoloSave.resume_match(), "the checkpoint resumes through Main")
	if not await _wait_main():
		await _finish()
		return

	map = main.game_map
	var restored_tc: BuildingBase = main._player_town_center
	check(is_instance_valid(restored_tc) and map.world_to_tile(restored_tc.global_position) == tc_tile, "Town Center restored")
	check(is_equal_approx(GameManager.game_time, 431.0), "clock restored")
	check(ResourceManager._player_resources[0] == expected.bank, "bank exact, nothing re-bought")
	check(int(GameManager.players[0].population) == expected.population and int(GameManager.players[0].population_cap) == expected.cap, "population and housing exact")
	check(main._player_units[0].size() == expected.units and main._player_buildings[0].size() == expected.buildings, "no unit or building lost or duplicated")
	check(restored_tc.bell_active and Garrison.count(restored_tc) == 2, "bell still ringing with both villagers inside (%d)" % Garrison.count(restored_tc))
	check(restored_tc.research_id == "loom" and is_equal_approx(restored_tc.research_progress, 6.5) and is_equal_approx(restored_tc.research_duration, research_duration), "Loom progress restored (%s %.2f)" % [restored_tc.research_id, restored_tc.research_progress])
	var restored_fallow: BuildingBase = null
	var restored_growing: BuildingBase = null
	for building: BuildingBase in main._player_buildings[0]:
		if building.building_type == BuildingData.BuildingType.FARM:
			var tile: Vector2i = map.world_to_tile(building.global_position)
			if tile == fallow_tile:
				restored_fallow = building
			elif tile == growing_tile:
				restored_growing = building
	check(restored_fallow != null and restored_fallow.farm_fallow and restored_fallow.farm_food_remaining == 0, "fallow Farm stays fallow")
	check(restored_growing != null and not restored_growing.farm_fallow and restored_growing.farm_food_remaining == growing_food, "growing Farm keeps its food (%d)" % (restored_growing.farm_food_remaining if restored_growing != null else -1))
	if restored_fallow != null:
		var wood: int = ResourceManager.get_resource(0, "wood")
		check(FarmPlots.reseed(restored_fallow, false).is_empty() and not restored_fallow.farm_fallow and restored_fallow.farm_food_remaining > 0, "restored fallow Farm can be reseeded")
		check(ResourceManager.get_resource(0, "wood") == wood - int(FarmPlots.reseed_cost(restored_fallow).get("wood", 0)), "reseed charged once")
	site = map.sacred_site
	check(site.state == site.SiteState.CAPTURED and site.owning_player == 0 and is_equal_approx(site.victory_timer, 97.25) and site.control_banks.size() == 2 and is_equal_approx(float(site.control_banks[1]), 14.5) and not site.clock_ticking, "drained Sacred clock restored")
	director = WildlifeDirector.of(main)
	check(director != null and director.nodes.size() == animals, "every animal restored once")
	var restored_carcass: WildlifeNode = director.by_id.get(carcass_id) as WildlifeNode if director != null else null
	check(restored_carcass != null and restored_carcass.remaining == carcass_left and restored_carcass.phase == WildlifeNode.Phase.CARCASS, "opened carcass keeps its stock")
	# The restored world keeps running: Loom finishes exactly once.
	GameManager.set_paused(false)
	var hp_before: float = 0.0
	for unit: Node in main._player_units[0]:
		if unit is Villager and unit.current_state != UnitBase.State.GARRISONED:
			hp_before = (unit as Villager).max_hp
			break
	main.process_mode = Node.PROCESS_MODE_INHERIT
	Engine.time_scale = 3.0
	var deadline: int = Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and not "loom" in GameManager.researched_upgrades.get(0, []):
		await get_tree().process_frame
	Engine.time_scale = 1.0
	main.process_mode = Node.PROCESS_MODE_DISABLED
	check("loom" in GameManager.researched_upgrades.get(0, []), "restored Loom completes")
	var hp_after: Array = []
	for unit: Node in main._player_units[0]:
		if unit is Villager:
			hp_after.append((unit as Villager).max_hp)
	check(not hp_after.is_empty() and hp_after.all(func(value: float) -> bool: return is_equal_approx(value, hp_before + 10.0)), "Loom applies once to every restored villager, inside or out (%.0f -> %s)" % [hp_before, hp_after])
	await _finish()
