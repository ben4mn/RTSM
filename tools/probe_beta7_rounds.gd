extends "res://tools/probe_civilization_paid_match.gd"
## Bounded ordinary-cost rounds with read-only housing receipts. No grants,
## teleports, direct spawning, timing shortcuts or altered combat rules.

var _last_population_sample: float = -20.0
var _last_partial_sample: float = -120.0


func _measure() -> void:
	super._measure()
	if GameManager.game_time - _last_population_sample < 20.0:
		return
	_last_population_sample = GameManager.game_time
	if not stats.has("population_observations"):
		stats["population_observations"] = []
	var row: Dictionary = {"time": GameManager.game_time, "players": []}
	for owner: int in 2:
		var houses: int = 0
		for building: BuildingBase in match_scene._player_buildings[owner]:
			if is_instance_valid(building) and building.building_type == BuildingData.BuildingType.HOUSE and building.state == BuildingBase.State.ACTIVE:
				houses += 1
		row.players.append({"owner": owner, "living": int(GameManager.players[owner].population), "reserved": GameManager.get_reserved_population(owner), "housing": int(GameManager.players[owner].population_cap), "match_limit": GameManager.get_player_population_limit(owner), "active_houses": houses})
	stats.population_observations.append(row)
	print("[ROUND_SAMPLE] ", JSON.stringify(row))
	if GameManager.game_time - _last_partial_sample >= 120.0:
		_last_partial_sample = GameManager.game_time
		var partial: Dictionary = stats.duplicate(true)
		partial["partial"] = true
		partial["time"] = GameManager.game_time
		partial["live_stats"] = match_scene.get("_stats").duplicate(true)
		partial["ages"] = [GameManager.get_player_age(0), GameManager.get_player_age(1)]
		partial["age_times"] = match_scene.get("_age_reached_at").duplicate(true)
		partial["deposited_by_resource"] = deposited_by_resource.duplicate(true)
		partial["housing_blocked_seconds"] = housing_blocked_seconds.duplicate()
		partial["damage_events"] = damage_events
		var file := FileAccess.open(result_path + ".partial.json", FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(partial, "\t"))
