extends "res://tools/probe_civilization_paid_match.gd"
## Bounded ordinary-cost rounds with read-only housing receipts. No grants,
## teleports, direct spawning, timing shortcuts or altered combat rules.

var _last_population_sample: float = -20.0


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
