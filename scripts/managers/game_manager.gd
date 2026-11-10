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

# --- Round 2 contract signals (docs/round2_contracts.md) ---
# Presentation (VFX/audio/HUD) consumes only these plus `age_advanced` and
# `research_completed` above. All fire on the simulation authority (solo and
# the match server); online clients are driven by snapshots instead.
# `duration` is in game seconds; 0.0 means the effect lands in the same frame,
# which is how every research and age-up behaves until timed research ships.
@warning_ignore("unused_signal")
signal research_started(player_id: int, building: Node2D, research_id: String, duration: float)
@warning_ignore("unused_signal")
signal research_cancelled(player_id: int, building: Node2D, research_id: String)
@warning_ignore("unused_signal")
signal age_advance_started(player_id: int, target_age: int, duration: float)
@warning_ignore("unused_signal")
signal age_advance_cancelled(player_id: int)
## Town bell rung (`active` true) or all-clear (`active` false) at one Town Center.
@warning_ignore("unused_signal")
signal town_bell_changed(player_id: int, town_center: Node2D, active: bool)
## A stray wildlife node (sheep) now belongs to `player_id`.
@warning_ignore("unused_signal")
signal wildlife_claimed(player_id: int, node: Node2D)
## A boar became a carcass; `player_id` owns the killing blow (-1 if nobody).
@warning_ignore("unused_signal")
signal boar_felled(player_id: int, world_pos: Vector2)
## A unit line reached a new tier (1 = base). `unit_type` is UnitData.UnitType.
@warning_ignore("unused_signal")
signal unit_tier_changed(player_id: int, unit_type: int, tier: int)

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
const MIN_SCREEN_TOUCH_SIZE := 44.0
const AUTHORED_TOUCH_SIZE := 48.0

var current_state: GameState = GameState.MENU
var players: Dictionary = {}  # player_id -> PlayerData dict
var game_time: float = 0.0
var game_speed: float = 1.0
var selected_difficulty: int = 0  # Fresh beta installs start on the onboarding-safe Easy profile.
var selected_map_seed: int = -1
var selected_map_archetype: int = MapData.MapArchetype.OPEN_PLAINS
var selected_population_limit: int = SkirmishData.DEFAULT_POPULATION_LIMIT
var population_limit_migrated: bool = false
var selected_match_mode: int = SkirmishData.MatchMode.STANDARD
var selected_civilization: int = CivilizationData.Civilization.CROWNLANDS
var selected_opponent_civilization: int = CivilizationData.Civilization.CROWNLANDS
var _match_mode: int = SkirmishData.MatchMode.STANDARD
var _match_civilizations: Array[int] = []
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
var _display_window_size: Vector2i = Vector2i.ZERO
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


# --- Modifier registry (docs/round2_contracts.md) ---
# player_id -> { key: float }. One additive number per key and player; every
# research, tier and civilization effect reads and writes through
# get_modifier/add_modifier/set_modifier below instead of a bespoke field.
var player_modifiers: Dictionary = {}
## Legacy names of the four original upgrade fields and their registry keys.
const LEGACY_UPGRADE_KEYS: Dictionary = {"attack_bonus": "attack", "armor_bonus": "armor", "gather_bonus": "gather_all", "villager_hp_bonus": "villager_hp"}
## Read-only legacy alias of `player_modifiers` in the pre-registry shape
## (player_id -> {"attack_bonus": int, "armor_bonus": int, "gather_bonus":
## float, "villager_hp_bonus": int}). It is rebuilt on every read, so writing
## into the returned dictionaries changes nothing; assigning a whole dictionary
## in that shape imports it.
var player_upgrades: Dictionary:
	get = _get_legacy_player_upgrades, set = _set_legacy_player_upgrades
var researched_upgrades: Dictionary = {}  # player_id -> Array of completed research IDs
var _research_transactions: Dictionary = {}  # player_id -> in-flight purchase
var _age_transactions: Dictionary = {}  # player_id -> in-flight purchase


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_preferences()
	get_window().size_changed.connect(_on_display_window_resized)
	_apply_display_preferences()
	var seed_override: String = OS.get_environment("AOEM_MAP_SEED").strip_edges()
	if seed_override.is_valid_int():
		selected_map_seed = int(seed_override)
	var archetype_override: String = OS.get_environment("AOEM_MAP_ARCHETYPE").strip_edges()
	if archetype_override.is_valid_int():
		selected_map_archetype = MapData.normalize_archetype(int(archetype_override))
	var population_override: String = OS.get_environment("AOEM_POPULATION_LIMIT").strip_edges()
	if population_override.is_valid_int():
		selected_population_limit = SkirmishData.normalize_population_limit(int(population_override))
		population_limit_migrated = false


func _load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(PREFERENCES_PATH) != OK:
		return
	selected_match_mode = SkirmishData.normalize_match_mode(int(config.get_value("skirmish", "match_mode", selected_match_mode)))
	selected_civilization = CivilizationData.normalize(int(config.get_value("skirmish", "civilization", selected_civilization)))
	selected_opponent_civilization = CivilizationData.normalize(int(config.get_value("skirmish", "opponent_civilization", selected_opponent_civilization)))
	selected_map_seed = maxi(-1, int(config.get_value("skirmish", "map_seed", selected_map_seed)))
	selected_map_archetype = MapData.normalize_archetype(int(config.get_value("skirmish", "map_archetype", selected_map_archetype)))
	selected_difficulty = clampi(int(config.get_value("skirmish", "difficulty", selected_difficulty)), 0, 2)
	var saved_population_limit: int = int(config.get_value("skirmish", "population_limit", selected_population_limit))
	var population_preference_version: int = int(config.get_value("skirmish", "population_preference_version", 0))
	selected_population_limit = SkirmishData.restore_population_limit(saved_population_limit, population_preference_version)
	population_limit_migrated = saved_population_limit != selected_population_limit and saved_population_limit == 30
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
	config.set_value("skirmish", "civilization", CivilizationData.normalize(selected_civilization))
	config.set_value("skirmish", "opponent_civilization", CivilizationData.normalize(selected_opponent_civilization))
	config.set_value("skirmish", "map_seed", selected_map_seed)
	config.set_value("skirmish", "map_archetype", MapData.normalize_archetype(selected_map_archetype))
	config.set_value("skirmish", "difficulty", clampi(selected_difficulty, 0, 2))
	config.set_value("skirmish", "population_limit", SkirmishData.normalize_population_limit(selected_population_limit))
	config.set_value("skirmish", "population_preference_version", SkirmishData.POPULATION_PREFERENCE_VERSION)
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
	selected_civilization = CivilizationData.Civilization.CROWNLANDS
	selected_opponent_civilization = CivilizationData.Civilization.CROWNLANDS
	selected_map_seed = -1
	selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	selected_population_limit = SkirmishData.DEFAULT_POPULATION_LIMIT
	population_limit_migrated = false
	apply_preferences()
	save_preferences()


func _apply_display_preferences() -> void:
	var window: Window = get_window()
	if window != null:
		_display_window_size = window.size
		ui_scale = clampf(ui_scale, 1.0, 1.15)
		# Importers and headless simulations have no physical screen. Their
		# dummy window dimensions must not change authored viewport geometry.
		if DisplayServer.get_name() == "headless":
			window.content_scale_factor = ui_scale
			return
		var screen_size := Vector2(window.size)
		if OS.has_feature("web"):
			# Use the full CSS canvas for physical touch sizing. UI layout applies
			# safe insets separately; Retina backing pixels are not extra space.
			var dimensions: Variant = JavaScriptBridge.eval("JSON.stringify((function(){var g=document.getElementById('pocket-game');var r=g&&g.getBoundingClientRect();return r?[r.width,r.height]:[0,0];})())")
			if dimensions is String:
				var parsed: Variant = JSON.parse_string(dimensions)
				if parsed is Array and parsed.size() == 2 and float(parsed[0]) > 0 and float(parsed[1]) > 0:
					screen_size = Vector2(float(parsed[0]), float(parsed[1]))
		var factor: float = display_scale_for_screen(screen_size, Vector2(window.content_scale_size), ui_scale)
		if not is_equal_approx(window.content_scale_factor, factor):
			window.content_scale_factor = factor


func _on_display_window_resized() -> void:
	# Changing content scale also emits size_changed. Only a new backing size
	# needs another calculation; preferences apply explicitly above.
	if get_window().size != _display_window_size:
		_apply_display_preferences()


static func display_scale_for_screen(screen_size: Vector2, base_size: Vector2, preference: float) -> float:
	if screen_size.x <= 0 or screen_size.y <= 0 or base_size.x <= 0 or base_size.y <= 0:
		return preference
	var stretch: float = minf(screen_size.x / base_size.x, screen_size.y / base_size.y)
	return preference * maxf(1.0, MIN_SCREEN_TOUCH_SIZE / (AUTHORED_TOUCH_SIZE * stretch))


func _process(delta: float) -> void:
	var session: Node = get_node_or_null("/root/NetworkSession")
	if session != null and bool(session.call("is_network_match")):
		game_speed = 1.0
		# Clients use the authoritative snapshot clock. The server must not count
		# its paused loading barrier as elapsed gameplay.
		if bool(session.call("is_client")) or str(session.get("state")) != "playing":
			return
	if current_state == GameState.PLAYING:
		game_time += delta * game_speed


func initialize_game(num_players: int = 2) -> void:
	_match_mode = SkirmishData.normalize_match_mode(selected_match_mode)
	_match_civilizations.assign([CivilizationData.normalize(selected_civilization), CivilizationData.normalize(selected_opponent_civilization)])
	var session: Node = get_node_or_null("/root/NetworkSession")
	if session != null and bool(session.call("is_network_match")) and session.has_method("get_local_civilizations"):
		_match_civilizations.assign(session.call("get_local_civilizations"))
	_match_population_limit = SkirmishData.normalize_population_limit(selected_population_limit)
	_population_reservations.clear()
	_base_population_caps.clear()
	_population_cap_grants.clear()
	players.clear()
	player_modifiers.clear()
	researched_upgrades.clear()
	_research_transactions.clear()
	_age_transactions.clear()
	game_time = 0.0

	for i in range(num_players):
		var player_data: Dictionary = _create_player_data(i)
		players[i] = player_data
		_base_population_caps[i] = int(player_data.get("population_cap", 0))
		player_modifiers[i] = {}
		researched_upgrades[i] = []

	set_state(GameState.PLAYING)


func _create_player_data(player_id: int) -> Dictionary:
	return {
		"id": player_id,
		"civilization": _match_civilizations[player_id] if player_id < _match_civilizations.size() else CivilizationData.Civilization.CROWNLANDS,
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


func get_player_civilization(player_id: int) -> int:
	## Match identities stay latched even if next-match preferences are changed.
	if players.has(player_id) and current_state in [GameState.PLAYING, GameState.PAUSED, GameState.GAME_OVER]:
		return CivilizationData.normalize(int(players[player_id].get("civilization", CivilizationData.Civilization.CROWNLANDS)))
	if player_id == 0:
		return CivilizationData.normalize(selected_civilization)
	if player_id == 1:
		return CivilizationData.normalize(selected_opponent_civilization)
	return CivilizationData.Civilization.CROWNLANDS


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
	get_tree().paused = new_state == GameState.PAUSED and not _is_online_client()


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
	## Instant paid age-up for scripted setups and fixtures: no timer and no
	## building prerequisites. Live play uses try_start_age_up (timed, in a Town
	## Center slot). A signal emitted during spending cannot buy twice.
	if current_state != GameState.PLAYING or not players.has(player_id):
		return false
	if not get_age_up_state(player_id).is_empty():
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
	# Paid and committed; today the advance lands in this same call (duration 0).
	age_advance_started.emit(player_id, get_player_age(player_id) + 1, 0.0)
	var advanced: bool = advance_age(player_id)
	if not advanced:
		resource_manager.call("refund", player_id, cost)
		age_advance_cancelled.emit(player_id)
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


# --- Modifier registry -------------------------------------------------------

func get_modifier(player_id: int, key: String, default: float = 0.0) -> float:
	## Current additive total for `key`, or `default` when nothing ever set it.
	var modifiers: Variant = player_modifiers.get(player_id)
	if modifiers is Dictionary and modifiers.has(key):
		return float(modifiers[key])
	return default


func add_modifier(player_id: int, key: String, amount: float) -> float:
	## Additive: +2 attack twice is +4. Returns the new total. Players that are
	## not part of the current match are ignored, as the old appliers did.
	## Adding zero writes nothing, so untouched keys never appear in saves.
	if not player_modifiers.has(player_id) or key.is_empty() or amount == 0.0:
		return get_modifier(player_id, key)
	var total: float = get_modifier(player_id, key) + amount
	player_modifiers[player_id][key] = total
	return total


func set_modifier(player_id: int, key: String, value: float) -> void:
	## Absolute write for level-like keys such as `tier_<unit_type>`.
	if player_modifiers.has(player_id) and not key.is_empty():
		player_modifiers[player_id][key] = value


func get_modifier_multiplier(player_id: int, key: String) -> float:
	## Percentage keys store additive fractions (+0.2 and +0.15 make 0.35);
	## this is the factor to multiply a base value by: 1.0 + the stored total.
	return 1.0 + get_modifier(player_id, key)


func _get_legacy_player_upgrades() -> Dictionary:
	var legacy: Dictionary = {}
	for player_id: Variant in player_modifiers:
		legacy[player_id] = {
			"attack_bonus": int(get_modifier(player_id, "attack")),
			"armor_bonus": int(get_modifier(player_id, "armor")),
			"gather_bonus": get_modifier(player_id, "gather_all"),
			"villager_hp_bonus": int(get_modifier(player_id, "villager_hp")),
		}
	return legacy


func _set_legacy_player_upgrades(value: Dictionary) -> void:
	for player_id: Variant in value:
		import_legacy_upgrades(int(player_id), value[player_id])


func import_legacy_upgrades(player_id: int, legacy: Variant) -> void:
	## Accepts one player's pre-registry upgrade dictionary (old snapshots/tests).
	if not legacy is Dictionary:
		return
	if not player_modifiers.has(player_id):
		player_modifiers[player_id] = {}
	for legacy_key: String in LEGACY_UPGRADE_KEYS:
		if typeof(legacy.get(legacy_key)) in [TYPE_INT, TYPE_FLOAT]:
			player_modifiers[player_id][LEGACY_UPGRADE_KEYS[legacy_key]] = float(legacy[legacy_key])


# Thin wrappers kept for existing callers (combat, villagers, AI, tests).

func get_attack_bonus(player_id: int) -> int:
	return int(get_modifier(player_id, "attack"))


func get_armor_bonus(player_id: int) -> int:
	return int(get_modifier(player_id, "armor"))


func apply_attack_upgrade(player_id: int, amount: int) -> void:
	add_modifier(player_id, "attack", float(amount))


func apply_armor_upgrade(player_id: int, amount: int) -> void:
	add_modifier(player_id, "armor", float(amount))


func apply_gather_upgrade(player_id: int, amount: float) -> void:
	add_modifier(player_id, "gather_all", amount)


func get_gather_bonus(player_id: int) -> float:
	return get_modifier(player_id, "gather_all")


func apply_villager_hp_upgrade(player_id: int, amount: int) -> void:
	add_modifier(player_id, "villager_hp", float(amount))


func get_villager_hp_bonus(player_id: int) -> int:
	return int(get_modifier(player_id, "villager_hp"))


func has_research(player_id: int, research_id: String) -> bool:
	if researched_upgrades.has(player_id):
		return research_id in researched_upgrades[player_id]
	return false


# =========================================================================
#  TIMED RESEARCH AND AGE-UP (Round 2 workstream B)
# =========================================================================
# Every research, including the age-up (`age_2`, `age_3`), occupies the single
# research slot of one building: paid at start, refunded in full on cancel or
# when the building dies, and applied through the modifier registry when the
# slot's timer completes (BuildingBase.advance_research, driven by main on the
# authority). `try_research` and `try_advance_age` remain as instant paid
# completions for scripted setups and regression fixtures; live play, the AI
# and the match server use `try_start_research` / `try_start_age_up`.

const RESEARCH_FAILURE_COPY: Dictionary = {
	"match_inactive": "Return to the match",
	"invalid_player": "Unavailable",
	"invalid_building": "Select your building",
	"not_owned": "Select your building",
	"building_incomplete": "Finish the building",
	"unknown_research": "Unavailable",
	"wrong_building": "Wrong building",
	"already_researched": "Complete",
	"in_progress": "In progress",
	"building_busy": "Building is busy",
	"purchase_in_progress": "One moment",
	"max_age": "Final age reached",
	"no_town_center": "Need a Town Center",
}


func _building_script() -> Script:
	# Load at request time, after every autoload exists. A BuildingBase type on
	# this first autoload would compile combat's AudioManager dependency early.
	return load("res://scripts/buildings/building_base.gd")


func get_player_buildings(player_id: int) -> Array[Node2D]:
	## Living buildings of one player, from the group every BuildingBase joins.
	var result: Array[Node2D] = []
	if not is_inside_tree():
		return result
	var destroyed: int = int(_building_script().State.DESTROYED)
	for node: Node in get_tree().get_nodes_in_group("player_%d_buildings" % player_id):
		if is_instance_valid(node) and not node.is_queued_for_deletion() and int(node.get("state")) != destroyed:
			result.append(node as Node2D)
	return result


func count_active_buildings(player_id: int, building_types: Array) -> int:
	var count: int = 0
	var active: int = int(_building_script().State.ACTIVE)
	for building: Node2D in get_player_buildings(player_id):
		if int(building.get("state")) == active and int(building.get("building_type")) in building_types:
			count += 1
	return count


func find_researching_building(player_id: int, research_id: String) -> Node2D:
	for building: Node2D in get_player_buildings(player_id):
		if str(building.get("research_id")) == research_id:
			return building
	return null


func get_research_definition(player_id: int, research_id: String) -> Dictionary:
	## TechData row, or a synthesized one for `age_<n>` with this player's cost.
	if not TechData.is_age_research(research_id):
		return TechData.get_research_definition(research_id)
	var target_age: int = TechData.age_research_target(research_id)
	if target_age < 2 or target_age > MAX_AGE:
		return {}
	var cost: Dictionary = get_age_up_cost(player_id, target_age)
	if cost.is_empty():
		return {}
	return {
		"id": research_id, "name": get_age_name(target_age), "short": get_age_name(target_age).trim_suffix(" Age"),
		"desc": "Advance to the next age", "details": "Unlocks the %s buildings, units and research." % get_age_name(target_age),
		"cost": cost, "time": float(TechData.AGE_UP_TIMES.get(target_age, 0.0)),
		"building_type": BuildingData.BuildingType.TOWN_CENTER, "age_required": target_age - 1,
		"icon": TechData.ICON_DIR + "age_up.svg", "target_age": target_age,
	}


func get_research_failure_reason(player_id: int, building: Node2D, research_id: String) -> String:
	## "" when `building` can start `research_id` right now, else a reason code
	## (see RESEARCH_FAILURE_COPY and describe_research_failure).
	var requirement_failure: String = _get_research_requirement_failure_reason(player_id, building, research_id)
	if not requirement_failure.is_empty():
		return requirement_failure
	if _research_transactions.has(player_id) or _age_transactions.has(player_id):
		return "purchase_in_progress"
	if not str(building.get("research_id")).is_empty():
		return "building_busy"
	var definition: Dictionary = get_research_definition(player_id, research_id)
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
	var building_script: Script = _building_script()
	if not is_instance_of(building, building_script):
		return "invalid_building"
	if int(building.get("player_owner")) != player_id:
		return "not_owned"
	if int(building.get("state")) != int(building_script.State.ACTIVE) or int(building.get("hp")) <= 0:
		return "building_incomplete"
	var definition: Dictionary = get_research_definition(player_id, research_id)
	if definition.is_empty():
		return "max_age" if TechData.is_age_research(research_id) and get_player_age(player_id) >= MAX_AGE else "unknown_research"
	if int(building.get("building_type")) != int(definition["building_type"]):
		return "wrong_building"
	if definition.has("target_age"):
		var target_age: int = int(definition["target_age"])
		if get_player_age(player_id) >= target_age:
			return "already_researched"
		if get_player_age(player_id) < target_age - 1:
			return "age_required"
	else:
		if has_research(player_id, research_id):
			return "already_researched"
		if get_player_age(player_id) < int(definition["age_required"]):
			return "age_required"
		var required: String = str(definition.get("requires", ""))
		if not required.is_empty() and not has_research(player_id, required):
			return "requires_research"
	if find_researching_building(player_id, research_id) != null:
		return "in_progress"
	if definition.has("target_age") and not is_age_requirement_met(player_id, int(definition["target_age"])):
		return "needs_building"
	return ""


func is_age_requirement_met(player_id: int, target_age: int) -> bool:
	var requirement: Dictionary = TechData.AGE_UP_REQUIREMENTS.get(target_age, {})
	return requirement.is_empty() or count_active_buildings(player_id, requirement["types"]) >= int(requirement["count"])


func describe_research_failure(player_id: int, research_id: String, reason: String) -> String:
	## Short card copy in the "Need X" style for a reason code; "" when ready.
	if reason.is_empty():
		return ""
	var definition: Dictionary = get_research_definition(player_id, research_id)
	match reason:
		"unaffordable":
			var resource_manager: Node = get_node_or_null("/root/ResourceManager")
			var parts: PackedStringArray = []
			if resource_manager != null:
				var missing: Dictionary = resource_manager.call("get_missing_resources", player_id, definition.get("cost", {}))
				for resource: String in ["food", "wood", "gold"]:
					if int(missing.get(resource, 0)) > 0:
						parts.append("%d%s" % [int(missing[resource]), resource.left(1).to_upper()])
			# A compact first shortage, as on the unit cards; Info lists them all.
			return "Need %s%s" % [parts[0], " +" if parts.size() > 1 else ""] if not parts.is_empty() else "Need resources"
		"age_required":
			return "Need %s" % get_age_name(int(definition.get("age_required", 1))) if not definition.is_empty() else "Need next age"
		"requires_research":
			return "Need %s" % TechData.get_research_name(str(definition.get("requires", "")))
		"needs_building":
			return TechData.describe_age_requirement(int(definition.get("target_age", 0)))
	return str(RESEARCH_FAILURE_COPY.get(reason, "Unavailable"))


func can_research(player_id: int, building: Node2D, research_id: String) -> bool:
	return get_research_failure_reason(player_id, building, research_id).is_empty()


func try_start_research(player_id: int, building: Node2D, research_id: String) -> bool:
	## Validate, pay and begin one timed research in `building`'s slot.
	if not can_research(player_id, building, research_id):
		return false
	var definition: Dictionary = get_research_definition(player_id, research_id)
	var cost: Dictionary = (definition["cost"] as Dictionary).duplicate()
	var resource_manager: Node = get_node_or_null("/root/ResourceManager")
	_research_transactions[player_id] = true
	if not bool(resource_manager.call("try_spend", player_id, cost)):
		_research_transactions.erase(player_id)
		return false
	# Resource notifications may synchronously end the match or destroy the
	# building. Such a cancelled purchase returns its full payment.
	if not _get_research_requirement_failure_reason(player_id, building, research_id).is_empty() or not str(building.get("research_id")).is_empty():
		resource_manager.call("refund", player_id, cost)
		_research_transactions.erase(player_id)
		return false
	_research_transactions.erase(player_id)
	var duration: float = maxf(0.0, float(definition.get("time", 0.0)))
	building.call("begin_research", research_id, duration, cost)
	research_started.emit(player_id, building, research_id, duration)
	if definition.has("target_age"):
		age_advance_started.emit(player_id, int(definition["target_age"]), duration)
	if duration <= 0.0:
		complete_building_research(building)
	return true


func cancel_research(player_id: int, building: Node2D) -> bool:
	## Stops the building's research and returns everything that was paid.
	## A destroyed building takes the same path (BuildingBase watches itself).
	if not is_instance_valid(building) or not is_instance_of(building, _building_script()) or int(building.get("player_owner")) != player_id:
		return false
	var research_id: String = str(building.get("research_id"))
	if research_id.is_empty():
		return false
	var paid: Dictionary = (building.get("research_paid_cost") as Dictionary).duplicate()
	# Clear before refunding so a resource listener cannot cancel twice.
	building.call("clear_research")
	var resource_manager: Node = get_node_or_null("/root/ResourceManager")
	if resource_manager != null and not paid.is_empty():
		resource_manager.call("refund", player_id, paid)
	research_cancelled.emit(player_id, building, research_id)
	if TechData.is_age_research(research_id):
		age_advance_cancelled.emit(player_id)
	return true


func complete_building_research(building: Node2D) -> void:
	## Called by the building when its research timer runs out.
	if not is_instance_valid(building):
		return
	var player_id: int = int(building.get("player_owner"))
	var research_id: String = str(building.get("research_id"))
	if research_id.is_empty():
		return
	building.call("clear_research")
	if TechData.is_age_research(research_id):
		if get_player_age(player_id) == TechData.age_research_target(research_id) - 1:
			advance_age(player_id)
		return
	_finish_research(player_id, research_id)


func _finish_research(player_id: int, research_id: String) -> void:
	if has_research(player_id, research_id):
		return
	var definition: Dictionary = TechData.get_research_definition(research_id)
	complete_research(player_id, research_id)
	var effects: Dictionary = definition.get("effects", {})
	for key: String in effects:
		add_modifier(player_id, key, float(effects[key]))
	var tier: Dictionary = definition.get("tier", {})
	if not tier.is_empty():
		set_modifier(player_id, UnitData.tier_modifier_key(int(tier["unit_type"])), float(tier["tier"]))
	# Listeners (main) bring living units and buildings up to the registry.
	research_completed.emit(player_id, research_id)
	if not tier.is_empty():
		unit_tier_changed.emit(player_id, int(tier["unit_type"]), int(tier["tier"]))


func try_research(player_id: int, building: Node2D, research_id: String) -> bool:
	## Instant paid completion (no timer) for scripted setups and fixtures.
	## Same validation and payment as try_start_research; ages are not accepted.
	if TechData.is_age_research(research_id) or not can_research(player_id, building, research_id):
		return false
	var definition: Dictionary = TechData.get_research_definition(research_id)
	var resource_manager: Node = get_node_or_null("/root/ResourceManager")
	_research_transactions[player_id] = true
	if not bool(resource_manager.call("try_spend", player_id, definition["cost"])):
		_research_transactions.erase(player_id)
		return false
	if not _get_research_requirement_failure_reason(player_id, building, research_id).is_empty():
		resource_manager.call("refund", player_id, definition["cost"])
		_research_transactions.erase(player_id)
		return false
	research_started.emit(player_id, building, research_id, 0.0)
	_research_transactions.erase(player_id)
	_finish_research(player_id, research_id)
	return true


func complete_research(player_id: int, research_id: String) -> void:
	if not researched_upgrades.has(player_id):
		researched_upgrades[player_id] = []
	if research_id not in researched_upgrades[player_id]:
		researched_upgrades[player_id].append(research_id)


# --- Age-up through the Town Center research slot ---

func get_age_up_state(player_id: int) -> Dictionary:
	## {} while idle, else {"building", "target_age", "progress" 0..1, "duration"}.
	for building: Node2D in get_player_buildings(player_id):
		var research_id: String = str(building.get("research_id"))
		if TechData.is_age_research(research_id):
			return {"building": building, "target_age": TechData.age_research_target(research_id), "progress": float(building.call("get_research_ratio")), "duration": float(building.get("research_duration"))}
	return {}


func get_age_up_town_center(player_id: int) -> Node2D:
	## The Town Center that would take the age-up: an idle one if any, else a
	## busy one (so the caller can say why), else null.
	var busy: Node2D = null
	var active: int = int(_building_script().State.ACTIVE)
	for building: Node2D in get_player_buildings(player_id):
		if int(building.get("building_type")) != BuildingData.BuildingType.TOWN_CENTER or int(building.get("state")) != active:
			continue
		if str(building.get("research_id")).is_empty():
			return building
		busy = building
	return busy


func get_age_up_failure_reason(player_id: int) -> String:
	## "" when the next age can start now, else a reason code.
	if get_player_age(player_id) >= MAX_AGE or get_age_up_cost(player_id, get_player_age(player_id) + 1).is_empty():
		return "max_age"
	if not get_age_up_state(player_id).is_empty():
		return "in_progress"
	var town_center: Node2D = get_age_up_town_center(player_id)
	if town_center == null:
		return "no_town_center"
	return get_research_failure_reason(player_id, town_center, TechData.age_research_id(get_player_age(player_id) + 1))


func describe_age_up_failure(player_id: int) -> String:
	return describe_research_failure(player_id, TechData.age_research_id(get_player_age(player_id) + 1), get_age_up_failure_reason(player_id))


func try_start_age_up(player_id: int) -> bool:
	## Shared human/AI/online request: pay and start the timed age-up.
	if not get_age_up_failure_reason(player_id).is_empty():
		return false
	return try_start_research(player_id, get_age_up_town_center(player_id), TechData.age_research_id(get_player_age(player_id) + 1))


func cancel_age_up(player_id: int) -> bool:
	var state: Dictionary = get_age_up_state(player_id)
	return not state.is_empty() and cancel_research(player_id, state["building"])


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


func _is_online_client() -> bool:
	var session: Node = get_node_or_null("/root/NetworkSession")
	return session != null and bool(session.call("is_client"))
