extends Node
## Global game state manager. Autoloaded as GameManager.
##
## Manages overall game state, player data, age progression, and win conditions.

signal game_state_changed(new_state: int)
signal age_advanced(player_id: int, new_age: int)
signal player_defeated(player_id: int)
signal game_over(winner_id: int)
signal research_completed(player_id: int, research_id: String)
signal preferences_changed()

enum GameState {
	MENU,
	LOADING,
	PLAYING,
	PAUSED,
	GAME_OVER
}

enum WinCondition {
	LANDMARK_DESTRUCTION,
	WONDER_VICTORY,
	SURRENDER
}

const MAX_PLAYERS: int = 2
const MAX_AGE: int = SkirmishData.MAX_AGE
const AGE_NAMES: Array[String] = SkirmishData.AGE_NAMES
const PREFERENCES_PATH: String = "user://preferences.cfg"

var current_state: GameState = GameState.MENU
var players: Dictionary = {}  # player_id -> PlayerData dict
var game_time: float = 0.0
var game_speed: float = 1.0
var selected_difficulty: int = 0  # Fresh beta installs start on the onboarding-safe Easy profile.
var selected_map_seed: int = -1
var selected_population_limit: int = SkirmishData.DEFAULT_POPULATION_LIMIT
var selected_match_mode: int = SkirmishData.MatchMode.STANDARD
var _match_mode: int = SkirmishData.MatchMode.STANDARD
var guided_opening_enabled: bool = true
var audio_enabled: bool = true
var master_volume: float = 0.8
var sfx_volume: float = 0.75
var sfx_muted: bool = false
var ui_alert_muted: bool = false
var ui_alert_volume: float = 0.9
var zoom_sensitivity_scale: float = 1.0
var reduced_motion: bool = false
var reduced_flashes: bool = false
var clearer_player_markers: bool = true
var camera_speed_scale: float = 1.0
var ui_scale: float = 1.0
var hold_shortcuts_enabled: bool = true
var _match_population_limit: int = SkirmishData.DEFAULT_POPULATION_LIMIT

# Population committed to production queues. Reservations are tracked by an
# opaque id so a cancelled/destroyed queue can only release its own slots.
var _population_reservations: Dictionary = {}  # reservation_id -> {player_id, amount}
var _next_population_reservation_id: int = 1
# Unowned/base capacity is tracked separately from buildings so the effective
# cap can always be derived from the complete set of active providers.
var _base_population_caps: Dictionary = {}  # player_id -> nominal amount
# Providers (currently Town Centers and Houses) retain their nominal amount,
# even while the effective cap is clamped. This lets a provider completed at
# max population fill headroom later when another provider is destroyed.
var _population_cap_grants: Dictionary = {}  # provider_id -> {player_id, nominal_amount}


# --- Upgrade tracking per player ---
# Keys: "attack_bonus", "armor_bonus" — global military buffs
var player_upgrades: Dictionary = {}  # player_id -> { "attack_bonus": int, "armor_bonus": int }
var researched_upgrades: Dictionary = {}  # player_id -> Array of completed research IDs
var _research_transactions: Dictionary = {}  # player_id -> in-flight purchase
var _age_transactions: Dictionary = {}  # player_id -> in-flight purchase


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_preferences()
	var seed_override: String = OS.get_environment("AOEM_MAP_SEED").strip_edges()
	if seed_override.is_valid_int():
		selected_map_seed = int(seed_override)
	var population_override: String = OS.get_environment("AOEM_POPULATION_LIMIT").strip_edges()
	if population_override.is_valid_int():
		selected_population_limit = SkirmishData.normalize_population_limit(int(population_override))


func _load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(PREFERENCES_PATH) != OK:
		return
	selected_match_mode = SkirmishData.normalize_match_mode(int(config.get_value("skirmish", "match_mode", selected_match_mode)))
	selected_map_seed = maxi(-1, int(config.get_value("skirmish", "map_seed", selected_map_seed)))
	selected_difficulty = clampi(int(config.get_value("skirmish", "difficulty", selected_difficulty)), 0, 2)
	selected_population_limit = SkirmishData.normalize_population_limit(int(config.get_value("skirmish", "population_limit", selected_population_limit)))
	guided_opening_enabled = bool(config.get_value("onboarding", "guided_opening", guided_opening_enabled))
	audio_enabled = bool(config.get_value("accessibility", "audio_enabled", audio_enabled))
	camera_speed_scale = clampf(float(config.get_value("controls", "camera_speed_scale", camera_speed_scale)), 0.75, 1.25)
	hold_shortcuts_enabled = bool(config.get_value("controls", "hold_shortcuts_enabled", hold_shortcuts_enabled))
	# Mobile controls are authored at a 48px minimum. Scaling below 100% made
	# those targets physically smaller than the interaction contract.
	ui_scale = clampf(float(config.get_value("accessibility", "ui_scale", ui_scale)), 1.0, 1.15)
	master_volume = clampf(float(config.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
	sfx_muted = bool(config.get_value("audio", "sfx_muted", sfx_muted))
	ui_alert_muted = bool(config.get_value("audio", "ui_alert_muted", ui_alert_muted))
	ui_alert_volume = clampf(float(config.get_value("audio", "ui_alert_volume", ui_alert_volume)), 0.0, 1.0)
	zoom_sensitivity_scale = clampf(float(config.get_value("controls", "zoom_sensitivity_scale", zoom_sensitivity_scale)), 0.75, 1.25)
	reduced_motion = bool(config.get_value("accessibility", "reduced_motion", reduced_motion))
	reduced_flashes = bool(config.get_value("accessibility", "reduced_flashes", reduced_flashes))
	clearer_player_markers = bool(config.get_value("accessibility", "clearer_player_markers", clearer_player_markers))
	_apply_display_preferences()


func save_preferences() -> bool:
	var config := ConfigFile.new()
	config.set_value("skirmish", "match_mode", SkirmishData.normalize_match_mode(selected_match_mode))
	config.set_value("skirmish", "map_seed", selected_map_seed)
	config.set_value("skirmish", "difficulty", clampi(selected_difficulty, 0, 2))
	config.set_value("skirmish", "population_limit", SkirmishData.normalize_population_limit(selected_population_limit))
	config.set_value("onboarding", "guided_opening", guided_opening_enabled)
	config.set_value("accessibility", "audio_enabled", audio_enabled)
	config.set_value("controls", "camera_speed_scale", camera_speed_scale)
	config.set_value("controls", "hold_shortcuts_enabled", hold_shortcuts_enabled)
	config.set_value("accessibility", "ui_scale", clampf(ui_scale, 1.0, 1.15))
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "sfx_muted", sfx_muted)
	config.set_value("audio", "ui_alert_muted", ui_alert_muted)
	config.set_value("audio", "ui_alert_volume", ui_alert_volume)
	config.set_value("controls", "zoom_sensitivity_scale", zoom_sensitivity_scale)
	config.set_value("accessibility", "reduced_motion", reduced_motion)
	config.set_value("accessibility", "reduced_flashes", reduced_flashes)
	config.set_value("accessibility", "clearer_player_markers", clearer_player_markers)
	return config.save(PREFERENCES_PATH) == OK


func apply_preferences() -> void:
	_apply_display_preferences()
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager != null and audio_manager.has_method("apply_preferences"):
		audio_manager.apply_preferences()
	preferences_changed.emit()


func reset_preferences() -> void:
	# Preferences and next-match setup only: never mutate a running match.
	audio_enabled = true
	master_volume = 0.8
	sfx_volume = 0.75
	sfx_muted = false
	ui_alert_muted = false
	ui_alert_volume = 0.9
	camera_speed_scale = 1.0
	zoom_sensitivity_scale = 1.0
	ui_scale = 1.0
	hold_shortcuts_enabled = true
	reduced_motion = false
	reduced_flashes = false
	clearer_player_markers = true
	guided_opening_enabled = true
	selected_difficulty = 0
	selected_match_mode = SkirmishData.MatchMode.STANDARD
	selected_map_seed = -1
	selected_population_limit = SkirmishData.DEFAULT_POPULATION_LIMIT
	apply_preferences()
	save_preferences()


func _apply_display_preferences() -> void:
	var window: Window = get_window()
	if window != null:
		ui_scale = clampf(ui_scale, 1.0, 1.15)
		window.content_scale_factor = ui_scale


func _process(delta: float) -> void:
	if current_state == GameState.PLAYING:
		game_time += delta * game_speed


func initialize_game(num_players: int = 2) -> void:
	_match_mode = SkirmishData.normalize_match_mode(selected_match_mode)
	_match_population_limit = SkirmishData.normalize_population_limit(selected_population_limit)
	_population_reservations.clear()
	_base_population_caps.clear()
	_population_cap_grants.clear()
	players.clear()
	player_upgrades.clear()
	researched_upgrades.clear()
	_research_transactions.clear()
	_age_transactions.clear()
	game_time = 0.0

	for i in range(num_players):
		var player_data: Dictionary = _create_player_data(i)
		players[i] = player_data
		_base_population_caps[i] = int(player_data.get("population_cap", 0))
		player_upgrades[i] = {"attack_bonus": 0, "armor_bonus": 0, "gather_bonus": 0.0, "villager_hp_bonus": 0}
		researched_upgrades[i] = []

	set_state(GameState.PLAYING)


func _create_player_data(player_id: int) -> Dictionary:
	return {
		"id": player_id,
		"age": 1,
		"population": 0,
		"population_reserved": 0,
		"population_cap": 5,
		"max_population": _match_population_limit,
		"is_defeated": false,
		"landmarks_alive": 0,
		"buildings": [],
		"units": [],
	}


func get_match_mode() -> int:
	# Match setup can be changed while paused; paid transactions keep the rules
	# latched at initialization through the result screen.
	if current_state in [GameState.PLAYING, GameState.PAUSED, GameState.GAME_OVER]:
		return _match_mode
	return SkirmishData.normalize_match_mode(selected_match_mode)


func get_match_population_limit() -> int:
	if current_state in [GameState.PLAYING, GameState.PAUSED, GameState.GAME_OVER]:
		return _match_population_limit
	return SkirmishData.normalize_population_limit(selected_population_limit)


func get_player_population_limit(player_id: int) -> int:
	if players.has(player_id):
		return maxi(0, int(players[player_id].get("max_population", _match_population_limit)))
	return get_match_population_limit()


func get_age_up_cost(player_id: int, target_age: int) -> Dictionary:
	return SkirmishData.get_age_up_cost(target_age, get_player_population_limit(player_id), get_match_mode())


func set_state(new_state: GameState) -> void:
	current_state = new_state
	game_state_changed.emit(new_state)

	# MENU/LOADING/GAME_OVER must never inherit a paused SceneTree from the
	# previous match. Treat PAUSED as the sole state that freezes processing.
	get_tree().paused = new_state == GameState.PAUSED


func advance_age(player_id: int) -> bool:
	## Completion primitive; normal player requests use the paid transaction.
	if current_state != GameState.PLAYING or not players.has(player_id):
		return false

	var player: Dictionary = players[player_id]
	if bool(player.get("is_defeated", false)) or player["age"] >= MAX_AGE:
		return false
	if get_age_up_cost(player_id, int(player["age"]) + 1).is_empty():
		return false

	player["age"] += 1
	age_advanced.emit(player_id, player["age"])
	return true


func try_advance_age(player_id: int) -> bool:
	## Shared human/AI purchase. A signal emitted during spending cannot buy twice.
	if current_state != GameState.PLAYING or not players.has(player_id):
		return false
	if bool(players[player_id].get("is_defeated", false)) or _age_transactions.has(player_id) or _research_transactions.has(player_id):
		return false
	var cost: Dictionary = get_age_up_cost(player_id, get_player_age(player_id) + 1)
	if get_player_age(player_id) >= MAX_AGE or cost.is_empty():
		return false
	var resource_manager: Node = get_node_or_null("/root/ResourceManager")
	if resource_manager == null:
		return false
	_age_transactions[player_id] = true
	if not bool(resource_manager.call("try_spend", player_id, cost)):
		_age_transactions.erase(player_id)
		return false
	var advanced: bool = advance_age(player_id)
	if not advanced:
		resource_manager.call("refund", player_id, cost)
	_age_transactions.erase(player_id)
	return advanced


func get_player_age(player_id: int) -> int:
	if players.has(player_id):
		return players[player_id]["age"]
	return 1


func get_age_name(age: int) -> String:
	if age >= 1 and age <= AGE_NAMES.size():
		return AGE_NAMES[age - 1]
	return "Unknown Age"


func add_population(player_id: int, amount: int) -> bool:
	if not players.has(player_id):
		return false
	if amount < 0:
		return false
	var player: Dictionary = players[player_id]
	var committed: int = int(player.get("population", 0)) + int(player.get("population_reserved", 0))
	if committed + amount > int(player.get("population_cap", 0)):
		return false
	player["population"] = int(player.get("population", 0)) + amount
	return true


func get_reserved_population(player_id: int) -> int:
	if not players.has(player_id):
		return 0
	return int(players[player_id].get("population_reserved", 0))


func get_committed_population(player_id: int) -> int:
	if not players.has(player_id):
		return 0
	var player: Dictionary = players[player_id]
	return int(player.get("population", 0)) + int(player.get("population_reserved", 0))


func can_reserve_population(player_id: int, amount: int) -> bool:
	if not players.has(player_id) or amount < 0:
		return false
	var player: Dictionary = players[player_id]
	return get_committed_population(player_id) + amount <= int(player.get("population_cap", 0))


func reserve_population(player_id: int, amount: int) -> int:
	## Atomically reserves queue capacity. Returns an opaque id, or -1 on failure.
	if amount <= 0 or not can_reserve_population(player_id, amount):
		return -1
	var reservation_id := _next_population_reservation_id
	_next_population_reservation_id += 1
	_population_reservations[reservation_id] = {
		"player_id": player_id,
		"amount": amount,
	}
	var player: Dictionary = players[player_id]
	player["population_reserved"] = int(player.get("population_reserved", 0)) + amount
	return reservation_id


func release_population_reservation(reservation_id: int) -> bool:
	## Releases a specific queue reservation without changing live population.
	if not _population_reservations.has(reservation_id):
		return false
	var reservation: Dictionary = _population_reservations[reservation_id]
	_population_reservations.erase(reservation_id)
	var player_id: int = int(reservation.get("player_id", -1))
	var amount: int = int(reservation.get("amount", 0))
	if players.has(player_id):
		var player: Dictionary = players[player_id]
		player["population_reserved"] = maxi(0, int(player.get("population_reserved", 0)) - amount)
	return true


func consume_population_reservation(reservation_id: int) -> bool:
	## Converts a queue reservation into live population exactly once.
	if not _population_reservations.has(reservation_id):
		return false
	var reservation: Dictionary = _population_reservations[reservation_id]
	_population_reservations.erase(reservation_id)
	var player_id: int = int(reservation.get("player_id", -1))
	var amount: int = int(reservation.get("amount", 0))
	if not players.has(player_id) or amount <= 0:
		return false
	var player: Dictionary = players[player_id]
	var reserved: int = int(player.get("population_reserved", 0))
	if reserved < amount:
		player["population_reserved"] = maxi(0, reserved)
		return false
	player["population_reserved"] = reserved - amount
	player["population"] = int(player.get("population", 0)) + amount
	return true


func remove_population(player_id: int, amount: int) -> void:
	if players.has(player_id):
		players[player_id]["population"] = max(0, players[player_id]["population"] - amount)


func increase_population_cap(player_id: int, amount: int) -> int:
	## Adds nominal unowned capacity and returns the visible effective increase.
	if not players.has(player_id) or amount <= 0:
		return 0
	var player: Dictionary = players[player_id]
	var previous_cap: int = int(player.get("population_cap", 0))
	var base_cap: int = int(_base_population_caps.get(player_id, previous_cap))
	_base_population_caps[player_id] = base_cap + amount
	var effective_cap: int = _recalculate_population_cap(player_id)
	return maxi(0, effective_cap - previous_cap)


func decrease_population_cap(player_id: int, amount: int) -> int:
	## Removes nominal unowned capacity and returns the visible effective decrease.
	## Existing units/reservations remain valid if this leaves the player over cap.
	if not players.has(player_id) or amount <= 0:
		return 0
	var player: Dictionary = players[player_id]
	var previous_cap: int = int(player.get("population_cap", 0))
	var base_cap: int = int(_base_population_caps.get(player_id, previous_cap))
	_base_population_caps[player_id] = maxi(0, base_cap - amount)
	var effective_cap: int = _recalculate_population_cap(player_id)
	return maxi(0, previous_cap - effective_cap)


func grant_population_cap(player_id: int, provider_id: int, requested_amount: int) -> int:
	## Registers a building/provider's full nominal capacity exactly once.
	## Returns only the immediate visible increase after max-population clamping;
	## the full nominal amount remains active and may fill future headroom.
	if not players.has(player_id) or provider_id <= 0 or requested_amount <= 0:
		return 0
	if _population_cap_grants.has(provider_id):
		return 0
	var previous_cap: int = int(players[player_id].get("population_cap", 0))
	_population_cap_grants[provider_id] = {
		"player_id": player_id,
		"nominal_amount": requested_amount,
	}
	var effective_cap: int = _recalculate_population_cap(player_id)
	return maxi(0, effective_cap - previous_cap)


func revoke_population_cap(provider_id: int) -> int:
	## Removes a provider exactly once and returns the visible effective decrease.
	## Other active providers are rebalanced before max-population clamping.
	if not _population_cap_grants.has(provider_id):
		return 0
	var grant: Dictionary = _population_cap_grants[provider_id]
	_population_cap_grants.erase(provider_id)
	var player_id: int = int(grant.get("player_id", -1))
	if not players.has(player_id):
		return 0
	var previous_cap: int = int(players[player_id].get("population_cap", 0))
	var effective_cap: int = _recalculate_population_cap(player_id)
	return maxi(0, previous_cap - effective_cap)


func _recalculate_population_cap(player_id: int) -> int:
	if not players.has(player_id):
		return 0
	var player: Dictionary = players[player_id]
	var base_cap: int = maxi(0, int(_base_population_caps.get(player_id, 0)))
	var provider_cap: int = 0
	for grant_value in _population_cap_grants.values():
		var grant: Dictionary = grant_value as Dictionary
		if int(grant.get("player_id", -1)) != player_id:
			continue
		provider_cap += maxi(0, int(grant.get("nominal_amount", 0)))
	var max_population: int = maxi(0, int(player.get("max_population", 0)))
	var effective_cap: int = mini(max_population, base_cap + provider_cap)
	player["population_cap"] = effective_cap
	return effective_cap


func defeat_player(player_id: int) -> void:
	if not players.has(player_id):
		return

	players[player_id]["is_defeated"] = true
	player_defeated.emit(player_id)

	# Check if only one player remains
	var alive_players: Array = []
	for pid in players:
		if not players[pid]["is_defeated"]:
			alive_players.append(pid)

	if alive_players.size() == 1:
		set_state(GameState.GAME_OVER)
		game_over.emit(alive_players[0])


func check_landmark_victory(player_id: int) -> void:
	## Call when a landmark is destroyed. Checks if the player has lost all landmarks.
	if not players.has(player_id):
		return
	if players[player_id]["landmarks_alive"] <= 0:
		defeat_player(player_id)


func get_formatted_time() -> String:
	@warning_ignore("integer_division")
	var minutes: int = int(game_time) / 60
	@warning_ignore("integer_division")
	var seconds: int = int(game_time) % 60
	return "%02d:%02d" % [minutes, seconds]


func get_attack_bonus(player_id: int) -> int:
	if player_upgrades.has(player_id):
		return player_upgrades[player_id].get("attack_bonus", 0)
	return 0


func get_armor_bonus(player_id: int) -> int:
	if player_upgrades.has(player_id):
		return player_upgrades[player_id].get("armor_bonus", 0)
	return 0


func apply_attack_upgrade(player_id: int, amount: int) -> void:
	if player_upgrades.has(player_id):
		player_upgrades[player_id]["attack_bonus"] += amount


func apply_armor_upgrade(player_id: int, amount: int) -> void:
	if player_upgrades.has(player_id):
		player_upgrades[player_id]["armor_bonus"] += amount


func apply_gather_upgrade(player_id: int, amount: float) -> void:
	if player_upgrades.has(player_id):
		player_upgrades[player_id]["gather_bonus"] += amount


func get_gather_bonus(player_id: int) -> float:
	if player_upgrades.has(player_id):
		return player_upgrades[player_id].get("gather_bonus", 0.0)
	return 0.0


func apply_villager_hp_upgrade(player_id: int, amount: int) -> void:
	if player_upgrades.has(player_id):
		player_upgrades[player_id]["villager_hp_bonus"] += amount


func get_villager_hp_bonus(player_id: int) -> int:
	if player_upgrades.has(player_id):
		return player_upgrades[player_id].get("villager_hp_bonus", 0)
	return 0


func has_research(player_id: int, research_id: String) -> bool:
	if researched_upgrades.has(player_id):
		return research_id in researched_upgrades[player_id]
	return false


func get_research_failure_reason(player_id: int, building: Node2D, research_id: String) -> String:
	var requirement_failure: String = _get_research_requirement_failure_reason(player_id, building, research_id)
	if not requirement_failure.is_empty():
		return requirement_failure
	if _research_transactions.has(player_id) or _age_transactions.has(player_id):
		return "purchase_in_progress"
	var definition: Dictionary = TechData.get_research_definition(research_id)
	var resource_manager: Node = get_node_or_null("/root/ResourceManager")
	if resource_manager == null or not bool(resource_manager.call("can_afford", player_id, definition["cost"])):
		return "unaffordable"
	return ""


func _get_research_requirement_failure_reason(player_id: int, building: Node2D, research_id: String) -> String:
	if current_state != GameState.PLAYING:
		return "match_inactive"
	if not players.has(player_id) or bool(players[player_id].get("is_defeated", false)):
		return "invalid_player"
	if not is_instance_valid(building) or building.is_queued_for_deletion() or not building.is_inside_tree():
		return "invalid_building"
	# Load at request time, after every autoload exists. A BuildingBase type on
	# this first autoload would compile combat's AudioManager dependency early.
	var building_script: Script = load("res://scripts/buildings/building_base.gd")
	if not is_instance_of(building, building_script):
		return "invalid_building"
	if int(building.get("player_owner")) != player_id:
		return "not_owned"
	if int(building.get("state")) != int(building_script.State.ACTIVE) or int(building.get("hp")) <= 0:
		return "building_incomplete"
	var definition: Dictionary = TechData.get_research_definition(research_id)
	if definition.is_empty():
		return "unknown_research"
	if int(building.get("building_type")) != int(definition["building_type"]):
		return "wrong_building"
	if get_player_age(player_id) < int(definition["age_required"]):
		return "age_required"
	if has_research(player_id, research_id):
		return "already_researched"
	return ""


func can_research(player_id: int, building: Node2D, research_id: String) -> bool:
	return get_research_failure_reason(player_id, building, research_id).is_empty()


func try_research(player_id: int, building: Node2D, research_id: String) -> bool:
	## Validate, pay and apply one technology through the same owner transaction.
	if not can_research(player_id, building, research_id):
		return false
	var definition: Dictionary = TechData.get_research_definition(research_id)
	var resource_manager: Node = get_node_or_null("/root/ResourceManager")
	_research_transactions[player_id] = true
	if not bool(resource_manager.call("try_spend", player_id, definition["cost"])):
		_research_transactions.erase(player_id)
		return false
	# Resource notifications may synchronously end the match or destroy the
	# building. Such a cancelled purchase returns its full payment.
	if not _get_research_requirement_failure_reason(player_id, building, research_id).is_empty():
		resource_manager.call("refund", player_id, definition["cost"])
		_research_transactions.erase(player_id)
		return false
	complete_research(player_id, research_id)
	apply_attack_upgrade(player_id, int(definition.get("attack_bonus", 0)))
	apply_armor_upgrade(player_id, int(definition.get("armor_bonus", 0)))
	apply_gather_upgrade(player_id, float(definition.get("gather_bonus", 0.0)))
	apply_villager_hp_upgrade(player_id, int(definition.get("villager_hp_bonus", 0)))
	_research_transactions.erase(player_id)
	research_completed.emit(player_id, research_id)
	return true


func complete_research(player_id: int, research_id: String) -> void:
	if not researched_upgrades.has(player_id):
		researched_upgrades[player_id] = []
	if research_id not in researched_upgrades[player_id]:
		researched_upgrades[player_id].append(research_id)


func toggle_pause() -> void:
	if current_state == GameState.PLAYING:
		set_paused(true)
	elif current_state == GameState.PAUSED:
		set_paused(false)


func set_paused(paused: bool) -> void:
	if paused:
		if current_state == GameState.PLAYING:
			set_state(GameState.PAUSED)
		return
	if current_state == GameState.PAUSED:
		set_state(GameState.PLAYING)
