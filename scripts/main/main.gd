extends Node2D
## Main game scene controller.
## Wires together the map, units, buildings, HUD, build menu, fog of war, and AI.

const WEB_SHELL_BRIDGE := preload("res://scripts/ui/web_shell_bridge.gd")

# --- Unit scenes ---
var _unit_scenes: Dictionary = {
	UnitData.UnitType.VILLAGER: preload("res://scenes/units/villager.tscn"),
	UnitData.UnitType.INFANTRY: preload("res://scenes/units/infantry.tscn"),
	UnitData.UnitType.ARCHER: preload("res://scenes/units/archer.tscn"),
	UnitData.UnitType.CAVALRY: preload("res://scenes/units/cavalry.tscn"),
	UnitData.UnitType.SCOUT: preload("res://scenes/units/scout.tscn"),
	UnitData.UnitType.SIEGE: preload("res://scenes/units/siege.tscn"),
}

# --- Building scenes ---
var _building_scenes: Dictionary = {
	BuildingData.BuildingType.TOWN_CENTER: preload("res://scenes/buildings/town_center.tscn"),
	BuildingData.BuildingType.HOUSE: preload("res://scenes/buildings/house.tscn"),
	BuildingData.BuildingType.BARRACKS: preload("res://scenes/buildings/barracks.tscn"),
	BuildingData.BuildingType.ARCHERY_RANGE: preload("res://scenes/buildings/archery_range.tscn"),
	BuildingData.BuildingType.STABLE: preload("res://scenes/buildings/stable.tscn"),
	BuildingData.BuildingType.FARM: preload("res://scenes/buildings/farm.tscn"),
	BuildingData.BuildingType.MILL: preload("res://scenes/buildings/mill.tscn"),
	BuildingData.BuildingType.LUMBER_CAMP: preload("res://scenes/buildings/lumber_camp.tscn"),
	BuildingData.BuildingType.MINING_CAMP: preload("res://scenes/buildings/mining_camp.tscn"),
	BuildingData.BuildingType.SIEGE_WORKSHOP: preload("res://scenes/buildings/siege_workshop.tscn"),
	BuildingData.BuildingType.BLACKSMITH: preload("res://scenes/buildings/blacksmith.tscn"),
	BuildingData.BuildingType.WATCH_TOWER: preload("res://scenes/buildings/watch_tower.tscn"),
}

# --- Team colors ---
const TEAM_COLORS: Array[Color] = [
	Color(0.2, 0.5, 1.0),  # Player 0 — blue
	Color(1.0, 0.25, 0.2),  # Player 1 — red
]

# --- Node references ---
@onready var game_map: Node2D = $GameMap
@onready var hud: CanvasLayer = $HUD
@onready var ai_controller: AIController = $AIController

# --- Build menu / placement state ---
var _build_menu: Node = null
var _building_placement: Node = null
var _placement_active: bool = false
var _placement_type: int = -1

# --- Player buildings/units tracking ---
var _player_buildings: Array[Array] = [[], []]  # [player_0_buildings, player_1_buildings]
var _player_units: Array[Array] = [[], []]
var _player_town_center: BuildingBase = null

# --- Idle villager cycling ---
var _idle_villager_index: int = 0
var _patrol_command_armed: bool = false
var _move_command_armed: bool = false
var _attack_move_command_armed: bool = false

# --- Under-attack notification cooldown ---
var _under_attack_cooldown: float = 0.0
const UNDER_ATTACK_COOLDOWN_TIME: float = 10.0
const PRODUCTION_EGRESS_MAX_RING_TILES: int = 3
const PRODUCTION_EGRESS_MAX_CANDIDATES: int = 48
const PRODUCTION_RALLY_ARRIVAL_RADIUS: float = 4.0
const PRODUCTION_RALLY_SLOT_RADIUS_TILES: int = 2
const PRODUCTION_RALLY_SLOT_CLEARANCE_WORLD: float = 30.0
const AI_CONSTRUCTION_APPROACH_RADIUS: float = 40.0
const AI_CONSTRUCTION_RECOVERY_INTERVAL: float = 0.5
const AI_CONSTRUCTION_MAX_ROUTE_CANDIDATES: int = 12
const AI_CONSTRUCTION_MAX_FAILED_RECOVERY_TICKS: int = 4
const AI_CONSTRUCTION_MAX_REASSIGNMENTS: int = 3
var _ai_construction_jobs: Dictionary = {}
var _ai_construction_recovery_elapsed: float = 0.0

# --- Game stats (indexed by player_id) ---
var _stats: Array[Dictionary] = [
	{"units_trained": 0, "army_trained": 0, "units_killed": 0, "units_lost": 0, "buildings_built": 0, "buildings_lost": 0, "resources_gathered": 0},
	{"units_trained": 0, "army_trained": 0, "units_killed": 0, "units_lost": 0, "buildings_built": 0, "buildings_lost": 0, "resources_gathered": 0},
]

# --- Match conclusion evidence ---
var _victory_reason: String = "Landmark destroyed"
var _game_over_shown: bool = false
var _age_reached_at: Array[Dictionary] = [{1: 0.0}, {1: 0.0}]
var _sacred_control_seconds: Array[float] = [0.0, 0.0]
var _sacred_control_owner: int = -1
var _sacred_last_remaining: float = -1.0
@export var match_summary_diagnostics: Dictionary = {}

# --- Control groups (Ctrl+1-9 save, 1-9 recall) ---
var _control_groups: Array = [[], [], [], [], [], [], [], [], [], []]
var _last_group_tap: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
const GROUP_DOUBLE_TAP_TIME: float = 0.35

# --- Sacred site victory tracking ---
var _sacred_site_victory_notified: bool = false

# --- Early game hints ---
enum GuidedOpeningStage {
	GATHER_FOOD,
	BUILD_HOUSE,
	TRAIN_SCOUT,
	MOVE_MILITARY,
	FREE_PLAY,
}

var _hint_timer: float = 0.0
var _hints_shown: int = 0
var _guided_opening_active: bool = true
var _guided_stage: GuidedOpeningStage = GuidedOpeningStage.GATHER_FOOD
const HINTS: Array = [
	{"time": 14.0, "text": "Pause any time from the top-right button if you need to stop and reorient.", "color": Color(0.95, 0.86, 0.56)},
	{"time": 42.0, "text": "Drag on open terrain to pan camera. Tap the minimap to jump view.", "color": Color(0.7, 0.8, 1.0)},
	{"time": 75.0, "text": "Tap a unit to switch selection. Tap ground to move; More opens battle orders.", "color": Color(0.65, 0.82, 1.0)},
	{"time": 105.0, "text": "Train a scout from your Town Center to reveal more map quickly.", "color": Color(0.7, 0.8, 1.0)},
	{"time": 180.0, "text": "Sacred Site is at map center. Hold it for 10:00 to win, or destroy the enemy Town Center.", "color": Color(0.85, 0.7, 1.0)},
]
var _milestone_first_house: bool = false
var _milestone_first_military_building: bool = false
var _milestone_first_age_up: bool = false
var _opening_gather_complete: bool = false
var _opening_house_complete: bool = false
var _opening_scout_queued: bool = false
var _opening_military_move_complete: bool = false
var _guidance_dismissed_in_match: bool = false
var _pause_open_count: int = 0
var _last_invalid_placement_reason: String = ""
var _invalid_placement_count: int = 0
var _first_session_hint_text: String = ""
var _first_session_focus_target: String = ""
var _first_session_hint_emphasis: bool = false
var _production_tick_counter: int = 0
var _production_active_queue_count: int = 0
var _production_latest_progress: float = 0.0
var _last_train_request_result: String = "none"
var _last_train_request_unit_type: int = -1
var _last_train_feedback: String = ""
var _last_placement_feedback: String = ""
var _military_shortcut_invocation_count: int = 0
var _military_shortcut_last_timestamp_ms: int = 0
var _military_shortcut_selected_count: int = 0
var _military_shortcut_selected_paths: Array[String] = []

# --- First-session telemetry (read via MCP node.get_properties on /root/Main) ---
@export var first_session_diagnostics: Dictionary = {}

# --- Balance telemetry (read via MCP node.get_properties on /root/Main) ---
@export var balance_ai_difficulty: int = 1
@export var balance_elapsed_seconds: float = 0.0
@export var balance_ai_age: int = 1
@export var balance_ai_feudal_time: float = -1.0
@export var balance_ai_castle_time: float = -1.0
@export var balance_ai_imperial_time: float = -1.0
@export var balance_ai_food: int = 0
@export var balance_ai_wood: int = 0
@export var balance_ai_gold: int = 0
@export var balance_ai_population: int = 0
@export var balance_ai_population_cap: int = 0
@export var balance_ai_villagers: int = 0
@export var balance_ai_military: int = 0
@export var balance_ai_buildings: int = 0
@export var balance_ai_town_centers: int = 0
@export var balance_ai_barracks: int = 0
@export var balance_ai_archery_ranges: int = 0
@export var balance_ai_stables: int = 0
@export var balance_ai_siege_workshops: int = 0
@export var balance_ai_under_pressure: bool = false
@export var balance_ai_saving_for_age_up: bool = false
@export var balance_ai_state: int = -1
@export var balance_ai_idle_villagers: int = 0
@export var balance_ai_idle_production_buildings: int = 0
@export var balance_ai_resource_float: int = 0
@export var balance_ai_resources_gathered: int = 0
@export var balance_ai_peak_military: int = 0
@export var balance_ai_peak_villagers: int = 0
@export var balance_ai_attack_count: int = 0
@export var balance_ai_first_attack_time: float = -1.0
@export var balance_ai_objective_mode: String = "none"
@export var balance_ai_objective_unit_count: int = 0
@export var balance_ai_enemy_memory_count: int = 0
@export var balance_ai_rebuild_request_count: int = 0
@export var balance_ai_last_decision: String = ""
@export var balance_ai_economic_bonus_active: bool = false
@export var balance_ai_sacred_control_seconds: float = 0.0
var _balance_snapshot_timer: float = 0.0
const BALANCE_SNAPSHOT_INTERVAL: float = 1.0


func _ready() -> void:
	# The match root is the process boundary for every gameplay descendant.
	# HUD and GameOverScreen opt into ALWAYS independently so their paused-state
	# controls remain actionable while units, buildings, AI, and the map freeze.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	WEB_SHELL_BRIDGE.set_controls_visible(false)
	GameManager.game_state_changed.connect(_on_game_state_changed)
	# Wait for map generation to finish.
	game_map.map_ready.connect(_on_map_ready)


func _on_game_state_changed(state: int) -> void:
	var is_modal: bool = state == GameManager.GameState.PAUSED or state == GameManager.GameState.GAME_OVER or state == GameManager.GameState.MENU
	WEB_SHELL_BRIDGE.set_controls_visible(is_modal)
	if is_modal:
		game_map.cancel_camera_touch_gesture()
		if game_map.selection_mgr != null:
			game_map.selection_mgr.cancel_touch_gesture()
		if _building_placement != null:
			_building_placement.cancel_touch_gesture()


func _resolve_ai_difficulty() -> int:
	if not OS.has_feature("production"):
		var env_override: String = OS.get_environment("AOEM_AI_DIFFICULTY").strip_edges()
		if env_override != "" and env_override.is_valid_int():
			return clampi(int(env_override), AIController.Difficulty.EASY, AIController.Difficulty.HARD)
	return clampi(GameManager.selected_difficulty, AIController.Difficulty.EASY, AIController.Difficulty.HARD)


func _reset_balance_snapshot() -> void:
	balance_elapsed_seconds = 0.0
	balance_ai_age = 1
	balance_ai_feudal_time = -1.0
	balance_ai_castle_time = -1.0
	balance_ai_imperial_time = -1.0
	balance_ai_food = 0
	balance_ai_wood = 0
	balance_ai_gold = 0
	balance_ai_population = 0
	balance_ai_population_cap = 0
	balance_ai_villagers = 0
	balance_ai_military = 0
	balance_ai_buildings = 0
	balance_ai_town_centers = 0
	balance_ai_barracks = 0
	balance_ai_archery_ranges = 0
	balance_ai_stables = 0
	balance_ai_siege_workshops = 0
	balance_ai_under_pressure = false
	balance_ai_saving_for_age_up = false
	balance_ai_state = -1
	balance_ai_idle_villagers = 0
	balance_ai_idle_production_buildings = 0
	balance_ai_resource_float = 0
	balance_ai_resources_gathered = 0
	balance_ai_peak_military = 0
	balance_ai_peak_villagers = 0
	balance_ai_attack_count = 0
	balance_ai_first_attack_time = -1.0
	balance_ai_objective_mode = "none"
	balance_ai_objective_unit_count = 0
	balance_ai_enemy_memory_count = 0
	balance_ai_rebuild_request_count = 0
	balance_ai_last_decision = ""
	balance_ai_economic_bonus_active = false
	balance_ai_sacred_control_seconds = 0.0
	_balance_snapshot_timer = 0.0


func _update_balance_snapshot() -> void:
	var ai_id: int = ai_controller.player_id
	balance_elapsed_seconds = GameManager.game_time
	balance_ai_difficulty = ai_controller.difficulty
	balance_ai_age = GameManager.get_player_age(ai_id)
	if balance_ai_age >= 2 and balance_ai_feudal_time < 0.0:
		balance_ai_feudal_time = balance_elapsed_seconds
	if balance_ai_age >= 3 and balance_ai_castle_time < 0.0:
		balance_ai_castle_time = balance_elapsed_seconds
	if balance_ai_age >= 4 and balance_ai_imperial_time < 0.0:
		balance_ai_imperial_time = balance_elapsed_seconds

	var ai_resources: Dictionary = ResourceManager.get_all_resources(ai_id)
	balance_ai_food = ai_resources.get("food", 0)
	balance_ai_wood = ai_resources.get("wood", 0)
	balance_ai_gold = ai_resources.get("gold", 0)
	balance_ai_resource_float = balance_ai_food + balance_ai_wood + balance_ai_gold
	balance_ai_resources_gathered = int(_stats[ai_id].get("resources_gathered", 0))

	var ai_player: Dictionary = GameManager.players.get(ai_id, {})
	balance_ai_population = ai_player.get("population", 0)
	balance_ai_population_cap = ai_player.get("population_cap", 0)

	balance_ai_villagers = 0
	balance_ai_military = 0
	balance_ai_idle_villagers = 0
	for unit in _player_units[ai_id]:
		if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEAD:
			continue
		if unit is Villager:
			balance_ai_villagers += 1
			if unit.current_state == UnitBase.State.IDLE:
				balance_ai_idle_villagers += 1
		else:
			balance_ai_military += 1
	balance_ai_peak_villagers = maxi(balance_ai_peak_villagers, balance_ai_villagers)
	balance_ai_peak_military = maxi(balance_ai_peak_military, balance_ai_military)

	balance_ai_buildings = 0
	balance_ai_town_centers = 0
	balance_ai_barracks = 0
	balance_ai_archery_ranges = 0
	balance_ai_stables = 0
	balance_ai_siege_workshops = 0
	balance_ai_idle_production_buildings = 0
	for building in _player_buildings[ai_id]:
		if not is_instance_valid(building) or building.state == BuildingBase.State.DESTROYED:
			continue
		balance_ai_buildings += 1
		if building.trainable_units.size() > 0 and building.state == BuildingBase.State.ACTIVE:
			var pq: Node = building.get_production_queue()
			if pq and pq.has_method("get_queue_size") and int(pq.get_queue_size()) == 0:
				balance_ai_idle_production_buildings += 1
		match building.building_type:
			BuildingData.BuildingType.TOWN_CENTER:
				balance_ai_town_centers += 1
			BuildingData.BuildingType.BARRACKS:
				balance_ai_barracks += 1
			BuildingData.BuildingType.ARCHERY_RANGE:
				balance_ai_archery_ranges += 1
			BuildingData.BuildingType.STABLE:
				balance_ai_stables += 1
			BuildingData.BuildingType.SIEGE_WORKSHOP:
				balance_ai_siege_workshops += 1

	balance_ai_under_pressure = bool(ai_controller.get("_is_under_pressure"))
	balance_ai_saving_for_age_up = bool(ai_controller.get("_saving_for_age_up"))
	balance_ai_state = int(ai_controller.get("_ai_state"))
	var strategy: Dictionary = ai_controller.get_strategy_snapshot()
	balance_ai_objective_mode = str(strategy.get("objective_mode", "none"))
	balance_ai_objective_unit_count = int(strategy.get("objective_unit_count", 0))
	balance_ai_enemy_memory_count = int(strategy.get("enemy_memory_count", 0))
	balance_ai_rebuild_request_count = strategy.get("rebuild_requests", []).size()
	balance_ai_last_decision = str(strategy.get("last_decision", ""))
	var economic_modifiers: Dictionary = strategy.get("economic_modifiers", {})
	balance_ai_economic_bonus_active = economic_modifiers.values().any(func(value: Variant) -> bool:
		return not is_zero_approx(float(value))
	)
	balance_ai_sacred_control_seconds = _sacred_control_seconds[ai_id]


func _guided_stage_name(stage: int = -1) -> String:
	var stage_value: int = _guided_stage if stage < 0 else stage
	match stage_value:
		GuidedOpeningStage.GATHER_FOOD:
			return "gather_food"
		GuidedOpeningStage.BUILD_HOUSE:
			return "build_house"
		GuidedOpeningStage.TRAIN_SCOUT:
			return "train_scout"
		GuidedOpeningStage.MOVE_MILITARY:
			return "move_military"
		GuidedOpeningStage.FREE_PLAY:
			return "free_play"
	return "unknown"


func _apply_primary_guidance(
	text: String,
	focus_target: String = "",
	unit_type: int = -1,
	building_type: int = -1,
	emphasis: bool = true
) -> void:
	_first_session_hint_text = text.strip_edges()
	_first_session_focus_target = focus_target
	_first_session_hint_emphasis = emphasis
	hud.set_primary_action(text, focus_target, unit_type, building_type, emphasis)
	_refresh_first_session_diagnostics()


func _apply_progression_guidance(text: String, emphasis: bool = false) -> void:
	_first_session_hint_text = text.strip_edges()
	_first_session_focus_target = ""
	_first_session_hint_emphasis = emphasis
	hud.clear_primary_action()
	hud.set_progression_hint(text, emphasis)
	_refresh_first_session_diagnostics()


func _clear_guidance_state(clear_hint_text: bool = false) -> void:
	_first_session_hint_text = ""
	_first_session_focus_target = ""
	_first_session_hint_emphasis = false
	hud.clear_primary_action()
	if clear_hint_text:
		hud.set_progression_hint("")
	_refresh_first_session_diagnostics()


func _refresh_first_session_diagnostics() -> void:
	# MCP/editor evidence only. Keep the production build's hot paths free of
	# diagnostic collection and path-string allocation.
	if OS.has_feature("production"):
		return
	var military_count: int = 0
	for unit in _player_units[0]:
		if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEAD:
			continue
		if unit.unit_type != UnitData.UnitType.VILLAGER:
			military_count += 1
	first_session_diagnostics = {
		"guided_opening_enabled": bool(GameManager.guided_opening_enabled),
		"guided_opening_active": _guided_opening_active,
		"guided_stage": _guided_stage,
		"guided_stage_name": _guided_stage_name(),
		"gather_complete": _opening_gather_complete,
		"house_complete": _opening_house_complete,
		"scout_queued": _opening_scout_queued,
		"military_move_complete": _opening_military_move_complete,
		"opening_loop_complete": _opening_gather_complete and _opening_house_complete and _opening_scout_queued and _opening_military_move_complete,
		"guidance_dismissed": _guidance_dismissed_in_match,
		"military_count": military_count,
		"pause_open_count": _pause_open_count,
		"placement_active": _placement_active,
		"placement_type": _placement_type,
		"build_menu_open": hud != null and hud.is_build_menu_open(),
		"placement_cancel_visible": hud != null and hud.is_placement_cancel_visible(),
		"last_invalid_placement_reason": _last_invalid_placement_reason,
		"invalid_placement_count": _invalid_placement_count,
		"guidance_hint_text": _first_session_hint_text,
		"guidance_focus_target": _first_session_focus_target,
		"guidance_emphasis": _first_session_hint_emphasis,
		"production_tick_counter": _production_tick_counter,
		"production_active_queue_count": _production_active_queue_count,
		"production_latest_progress": _production_latest_progress,
		"player_building_count": _player_buildings[0].size(),
		"last_train_request_result": _last_train_request_result,
		"last_train_request_unit_type": _last_train_request_unit_type,
		"last_train_feedback": _last_train_feedback,
		"last_placement_feedback": _last_placement_feedback,
		"military_shortcut_invocation_count": _military_shortcut_invocation_count,
		"military_shortcut_last_timestamp_ms": _military_shortcut_last_timestamp_ms,
		"military_shortcut_selected_count": _military_shortcut_selected_count,
		"military_shortcut_selected_paths": _military_shortcut_selected_paths.duplicate(),
	}


func _on_map_ready(map_gen: MapGenerator) -> void:
	# Initialize game state for 2 players.
	Engine.time_scale = 1.0
	if not OS.has_feature("production"):
		var simulation_speed: String = OS.get_environment("AOEM_SIM_TIME_SCALE").strip_edges()
		if simulation_speed.is_valid_float():
			Engine.time_scale = clampf(float(simulation_speed), 1.0, 3.0)
	GameManager.initialize_game(2)
	ResourceManager.initialize_player(0)
	ResourceManager.initialize_player(1)
	if not GameManager.age_advanced.is_connected(_on_age_advanced_for_summary):
		GameManager.age_advanced.connect(_on_age_advanced_for_summary)
	_age_reached_at = [{1: 0.0}, {1: 0.0}]
	_sacred_control_seconds = [0.0, 0.0]
	_sacred_control_owner = -1
	_sacred_last_remaining = -1.0
	_guided_opening_active = bool(GameManager.guided_opening_enabled)
	_guided_stage = GuidedOpeningStage.GATHER_FOOD
	_opening_gather_complete = false
	_opening_house_complete = false
	_opening_scout_queued = false
	_opening_military_move_complete = false
	_pause_open_count = 0
	_last_invalid_placement_reason = ""
	_invalid_placement_count = 0
	_first_session_hint_text = ""
	_first_session_focus_target = ""
	_first_session_hint_emphasis = false
	_production_tick_counter = 0
	_production_active_queue_count = 0
	_production_latest_progress = 0.0

	# Connect resource changes to HUD.
	ResourceManager.resources_changed.connect(_on_resource_changed)

	# Place starting Town Centers and Villagers.
	_setup_player_start(0, map_gen.spawn_positions[0])
	_setup_player_start(1, map_gen.spawn_positions[1])
	# Establish real current vision before camera framing and deferred economy
	# assignment query fog-aware resource discovery for the first time.
	if game_map.fog_of_war != null:
		# Main owns the update order during a match: sources, fog grid, then entity
		# visibility in one frame, without a one-frame hidden-state exposure.
		game_map.fog_of_war.set_process(false)
	_update_fog_of_war()
	_update_fog_entity_visibility()

	# Connect selection manager signals.
	var selection_mgr: Node = game_map.selection_mgr
	selection_mgr.move_command.connect(_on_move_command)
	selection_mgr.attack_command.connect(_on_attack_command)
	selection_mgr.gather_command.connect(_on_gather_command)
	selection_mgr.build_command.connect(_on_build_command)
	selection_mgr.selection_changed.connect(_on_selection_changed)

	# Connect sacred site signals.
	if game_map.sacred_site:
		# The economy must have time to turn into armies and reinforcements.
		# Keep the small standalone site fixture independent of match pacing.
		game_map.sacred_site.victory_hold_time = SkirmishData.SACRED_VICTORY_HOLD_SECONDS
		game_map.sacred_site.captured.connect(_on_sacred_site_captured)
		game_map.sacred_site.neutralized.connect(_on_sacred_site_neutralized)
		game_map.sacred_site.victory_timer_tick.connect(_on_sacred_site_timer_tick)

	# Wire up HUD.
	_setup_hud()

	# Wire up AI.
	_setup_ai(map_gen)
	if not OS.has_feature("production"):
		_reset_balance_snapshot()
		_update_balance_snapshot()

	# Center camera on player's starting base.
	var player_spawn: Vector2 = game_map.tile_to_world(map_gen.spawn_positions[0])
	game_map.camera.position = _get_initial_camera_focus(player_spawn)
	game_map._clamp_camera()

	# Update initial HUD state.
	_refresh_hud_resources(0)
	_update_population_display()
	_milestone_first_house = false
	_milestone_first_military_building = false
	_milestone_first_age_up = false
	_refresh_first_session_diagnostics()
	_bootstrap_opening_guidance()


func _bootstrap_opening_guidance() -> void:
	hud.set_early_game_ui_state(_guided_opening_active)
	hud.set_guided_military_shortcuts_visible(false)
	hud.set_pending_military_shortcut(false)
	# The camera outline needs a visible explanation outside the map drawing.
	hud.set_minimap_hint("Map · tap to view")
	if _guided_opening_active:
		call_deferred("_update_progression_hint")
	else:
		hud.clear_primary_action()
		_update_progression_hint()


func _set_guided_stage(new_stage: GuidedOpeningStage) -> void:
	if _guided_stage == new_stage:
		return
	_guided_stage = new_stage
	hud.set_guided_military_shortcuts_visible(new_stage == GuidedOpeningStage.MOVE_MILITARY)
	hud.set_pending_military_shortcut(false)
	match new_stage:
		GuidedOpeningStage.BUILD_HOUSE:
			hud.show_notification("Objective complete: Villagers are gathering. Next: place a House.", Color(0.95, 0.86, 0.42))
		GuidedOpeningStage.TRAIN_SCOUT:
			hud.show_notification("Objective complete: House placed. Next: train a Scout.", Color(0.95, 0.86, 0.42))
			call_deferred("_select_town_center")
		GuidedOpeningStage.MOVE_MILITARY:
			hud.show_notification("Objective complete: Scout queued. Next: move it onto the map.", Color(0.95, 0.86, 0.42))
		GuidedOpeningStage.FREE_PLAY:
			_guided_opening_active = false
			hud.set_early_game_ui_state(false)
			hud.set_guided_military_shortcuts_visible(false)
			hud.set_pending_military_shortcut(false)
			hud.show_notification("Opening complete. Grow, age up, and contest the Sacred Site.", Color(0.68, 0.86, 1.0))
	_refresh_first_session_diagnostics()
	_update_progression_hint()


func _on_age_advanced_for_summary(player_id: int, new_age: int) -> void:
	if player_id < 0 or player_id >= _age_reached_at.size():
		return
	if not _age_reached_at[player_id].has(new_age):
		_age_reached_at[player_id][new_age] = GameManager.game_time


func _has_player_building_started(player_id: int, building_type: int) -> bool:
	for building in _player_buildings[player_id]:
		if not is_instance_valid(building):
			continue
		if building.state == BuildingBase.State.DESTROYED:
			continue
		if building.building_type == building_type:
			return true
	return false


func _has_queued_unit(building_type: int, unit_type: int) -> bool:
	for building in _player_buildings[0]:
		if not is_instance_valid(building):
			continue
		if building.building_type != building_type:
			continue
		var pq: Node = building.get_production_queue()
		if pq == null or not pq.has_method("get_queue_info"):
			continue
		for item in pq.get_queue_info():
			if item is Dictionary and int(item.get("unit_type", -1)) == unit_type:
				return true
	return false


func _refresh_guided_opening_stage() -> void:
	if not _guided_opening_active:
		if not OS.has_feature("production"):
			_refresh_first_session_diagnostics()
		return
	match _guided_stage:
		GuidedOpeningStage.GATHER_FOOD:
			if _opening_gather_complete:
				_set_guided_stage(GuidedOpeningStage.BUILD_HOUSE)
		GuidedOpeningStage.BUILD_HOUSE:
			if _opening_house_complete or _has_player_building_started(0, BuildingData.BuildingType.HOUSE):
				_opening_house_complete = true
				_set_guided_stage(GuidedOpeningStage.TRAIN_SCOUT)
		GuidedOpeningStage.TRAIN_SCOUT:
			if _opening_scout_queued or _has_queued_unit(BuildingData.BuildingType.TOWN_CENTER, UnitData.UnitType.SCOUT):
				_opening_scout_queued = true
				_set_guided_stage(GuidedOpeningStage.MOVE_MILITARY)
		GuidedOpeningStage.MOVE_MILITARY:
			if _opening_military_move_complete:
				_set_guided_stage(GuidedOpeningStage.FREE_PLAY)
	_refresh_first_session_diagnostics()


# =========================================================================
#  SACRED SITE
# =========================================================================

func _on_sacred_site_captured(player_id: int) -> void:
	_sacred_control_owner = player_id
	# A same-owner recapture after a contested interval resumes the site's
	# existing victory timer.  Use that authoritative timer as the telemetry
	# baseline so elapsed control time recorded before the contest is not counted
	# again on the next tick.
	if game_map.sacred_site:
		var hold_time: float = float(game_map.sacred_site.victory_hold_time)
		var elapsed_time: float = float(game_map.sacred_site.victory_timer)
		_sacred_last_remaining = clampf(hold_time - elapsed_time, 0.0, hold_time)
	else:
		_sacred_last_remaining = -1.0
	if player_id == 0:
		var remaining_seconds: int = ceili(_sacred_last_remaining if _sacred_last_remaining >= 0.0 else SkirmishData.SACRED_VICTORY_HOLD_SECONDS)
		var remaining_text: String = "%d:%02d" % [int(remaining_seconds / 60.0), remaining_seconds % 60]
		hud.show_notification("Sacred Site secured! Hold %s more to win." % remaining_text, Color(0.9, 0.8, 0.2))
	else:
		hud.show_notification("Enemy captured the Sacred Site!", Color(1.0, 0.4, 0.2))


func _on_sacred_site_neutralized() -> void:
	_sacred_control_owner = -1
	_sacred_last_remaining = -1.0
	hud.show_notification("Sacred Site neutralized", Color(0.7, 0.7, 0.7))
	_sacred_site_victory_notified = false
	hud.update_sacred_site_timer(-1, 0.0, 0.0)


func _on_sacred_site_timer_tick(player_id: int, remaining: float, total: float) -> void:
	if player_id == _sacred_control_owner and _sacred_last_remaining >= remaining:
		_sacred_control_seconds[player_id] += _sacred_last_remaining - remaining
	_sacred_control_owner = player_id
	_sacred_last_remaining = remaining
	hud.update_sacred_site_timer(player_id, remaining, total)
	# Check for victory
	if remaining <= 0.0:
		_conclude_match(player_id, "Sacred Site held for %s" % _format_duration_seconds(total))
	# Warn at 60 seconds remaining
	elif remaining <= 60.0 and not _sacred_site_victory_notified:
		_sacred_site_victory_notified = true
		if player_id == 0:
			hud.show_notification("Sacred Site victory in 1 minute!", Color(0.9, 0.8, 0.2))
		else:
			hud.show_notification("Enemy Sacred Site victory in 1 minute!", Color(1.0, 0.3, 0.2))


# =========================================================================
#  KEYBOARD INPUT
# =========================================================================

func _unhandled_input(event: InputEvent) -> void:
	# Handle input-action-based gameplay shortcuts
	if not event.is_pressed() or event.is_echo():
		return
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	if event.is_action("cancel"):
		_handle_escape()
		get_viewport().set_input_as_handled()
	elif event.is_action("center_selection"):
		_center_camera_on_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action("idle_villager"):
		_on_idle_villager_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action("train_unit"):
		_handle_production_hotkey()
		get_viewport().set_input_as_handled()
	elif event.is_action("toggle_build_menu"):
		_on_build_menu_pressed_hotkey()
		get_viewport().set_input_as_handled()
	elif event.is_action("select_tc"):
		_select_town_center()
		get_viewport().set_input_as_handled()
	elif event.is_action("select_all_military"):
		_select_all_military()
		get_viewport().set_input_as_handled()
	elif event.is_action("find_army"):
		_find_army()
		get_viewport().set_input_as_handled()
	elif event.is_action("toggle_stance"):
		_toggle_stance()
		get_viewport().set_input_as_handled()
	elif event.is_action("patrol_command"):
		_arm_patrol_command()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		# Ctrl+A: select all own units
		if key_event.keycode == KEY_A and key_event.ctrl_pressed:
			game_map.selection_mgr.select_all_own_units()
			get_viewport().set_input_as_handled()
		# +/= key: increase game speed
		elif key_event.keycode == KEY_EQUAL or key_event.keycode == KEY_KP_ADD:
			_cycle_game_speed(1)
			get_viewport().set_input_as_handled()
		# - key: decrease game speed
		elif key_event.keycode == KEY_MINUS or key_event.keycode == KEY_KP_SUBTRACT:
			_cycle_game_speed(-1)
			get_viewport().set_input_as_handled()
		# T key: stop selected units
		elif key_event.keycode == KEY_T:
			_stop_selected_units()
			get_viewport().set_input_as_handled()
		# Delete key: destroy own selected building
		elif key_event.keycode == KEY_DELETE:
			_delete_selected_building()
			get_viewport().set_input_as_handled()
		# Control groups: Ctrl+0-9 save, 0-9 recall
		elif key_event.keycode >= KEY_0 and key_event.keycode <= KEY_9:
			var group_idx: int = key_event.keycode - KEY_0
			if key_event.ctrl_pressed:
				_save_control_group(group_idx)
			else:
				_recall_control_group(group_idx)
			get_viewport().set_input_as_handled()


const GAME_SPEEDS: Array[float] = [0.5, 1.0, 2.0, 3.0]

func _cycle_game_speed(direction: int) -> void:
	var current_speed: float = Engine.time_scale
	var current_idx: int = 1  # default to 1x
	for i in GAME_SPEEDS.size():
		if absf(GAME_SPEEDS[i] - current_speed) < 0.01:
			current_idx = i
			break
	var new_idx: int = clampi(current_idx + direction, 0, GAME_SPEEDS.size() - 1)
	Engine.time_scale = GAME_SPEEDS[new_idx]
	hud.sync_speed_display(GAME_SPEEDS[new_idx])
	hud.show_notification("Speed: %.1fx" % GAME_SPEEDS[new_idx], Color(0.8, 0.8, 0.8))


func _handle_escape() -> void:
	if _placement_active:
		_cancel_placement()
		return
	if hud.is_build_menu_open():
		hud.close_build_menu()
		return
	if _patrol_command_armed:
		_clear_armed_unit_commands()
		hud.show_notification("Command mode canceled", Color(0.75, 0.7, 0.55))
		return
	if _move_command_armed or _attack_move_command_armed:
		_clear_armed_unit_commands()
		hud.show_notification("Command mode canceled", Color(0.75, 0.7, 0.55))
		return
	game_map.selection_mgr.deselect_all()


func _center_camera_on_selection() -> void:
	var selected: Array = game_map.selection_mgr.selected
	if selected.is_empty():
		return
	var center := Vector2.ZERO
	var count: int = 0
	for node in selected:
		if is_instance_valid(node):
			center += node.global_position
			count += 1
	if count > 0:
		game_map.camera.position = center / float(count)
		game_map._clamp_camera()


func _on_build_menu_pressed_hotkey() -> void:
	hud._on_build_menu_pressed()


func _on_pause_requested() -> void:
	if GameManager.current_state == GameManager.GameState.PAUSED:
		return
	if hud.is_build_menu_open():
		hud.close_build_menu()
	_cancel_placement()
	_pause_open_count += 1
	GameManager.set_paused(true)
	_sync_hud_modal_state()
	_refresh_first_session_diagnostics()


func _on_resume_requested() -> void:
	if GameManager.current_state != GameManager.GameState.PAUSED:
		return
	GameManager.set_paused(false)
	_sync_hud_modal_state()
	_refresh_first_session_diagnostics()


func _on_quit_to_menu_requested() -> void:
	Engine.time_scale = 1.0
	GameManager.set_paused(false)
	GameManager.set_state(GameManager.GameState.MENU)
	# Touch Buttons finish release dispatch after their pressed signal returns.
	# Keep the current scene alive until that dispatch has fully unwound.
	get_tree().call_deferred("change_scene_to_file", "res://scenes/ui/main_menu.tscn")


func _select_all_military() -> void:
	var military_units: Array[Node2D] = []
	for unit in _player_units[0]:
		if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEAD:
			continue
		if unit is Villager:
			continue
		military_units.append(unit)
	game_map.selection_mgr.select_many(military_units)
	_military_shortcut_invocation_count += 1
	_military_shortcut_last_timestamp_ms = maxi(
		Time.get_ticks_msec(),
		_military_shortcut_last_timestamp_ms + 1
	)
	_military_shortcut_selected_count = game_map.selection_mgr.selected.size()
	_military_shortcut_selected_paths.clear()
	for unit in game_map.selection_mgr.selected:
		_military_shortcut_selected_paths.append(str(unit.get_path()))
	_refresh_first_session_diagnostics()


func _find_army() -> void:
	var center := Vector2.ZERO
	var count: int = 0
	for unit in _player_units[0]:
		if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEAD:
			continue
		if unit is Villager:
			continue
		center += unit.global_position
		count += 1
	if count > 0:
		game_map.camera.position = center / float(count)
		game_map._clamp_camera()


# =========================================================================
#  CONTROL GROUPS
# =========================================================================

func _save_control_group(index: int) -> void:
	var owned: Array[Node2D] = []
	for entry: Variant in game_map.selection_mgr.selected:
		if not _is_own_control_group_entry(entry):
			continue
		var node := entry as Node2D
		if not bool(game_map.selection_mgr.call("_is_current_selection_entry", node)):
			continue
		owned.append(node)
	_control_groups[index] = owned
	if owned.size() > 0:
		hud.show_notification("Group %d: %d units" % [index, owned.size()], Color(0.7, 0.8, 0.7))


func _recall_control_group(index: int) -> void:
	var group: Array = _control_groups[index]
	# Control groups are ownership-only. Reject enemy/neutral entries before any
	# mutable state or position read so a stale or injected group cannot become a
	# live fog-of-war tracker.
	var valid: Array[Node2D] = []
	for entry: Variant in group:
		if not _is_own_control_group_entry(entry):
			continue
		var node := entry as Node2D
		if not bool(game_map.selection_mgr.call("_is_current_selection_entry", node)):
			continue
		valid.append(node)

	# SelectionManager performs the final canonical validation. Persist and use
	# only what it actually accepted, rather than the pre-validation candidates.
	game_map.selection_mgr.select_many(valid)
	var recalled: Array[Node2D] = game_map.selection_mgr.selected.duplicate()
	_control_groups[index] = recalled

	if recalled.is_empty():
		return

	# Double-tap detection: center camera on group
	var now: float = Time.get_ticks_msec() / 1000.0
	var is_double: bool = (
		_last_group_tap[index] > 0.0
		and now - _last_group_tap[index] < GROUP_DOUBLE_TAP_TIME
	)
	_last_group_tap[index] = now

	# Center camera on double-tap
	if is_double:
		var center := Vector2.ZERO
		for node in recalled:
			center += node.global_position
		center /= float(recalled.size())
		game_map.camera.position = center
		game_map._clamp_camera()


func _is_own_control_group_entry(entry: Variant) -> bool:
	if not is_instance_valid(entry) or not entry is Node2D:
		return false
	if entry is UnitBase:
		return (entry as UnitBase).player_owner == 0
	if entry is BuildingBase:
		return (entry as BuildingBase).player_owner == 0
	return false


func _stop_selected_units() -> void:
	_clear_armed_unit_commands(false)
	var selected: Array = game_map.selection_mgr.selected
	var stopped: int = 0
	for node in selected:
		if node is UnitBase and node.player_owner == 0:
			node.command_stop()
			stopped += 1
	if stopped > 0:
		hud.show_notification("Units stopped", Color(0.7, 0.7, 0.7))
	_refresh_unit_command_hud()


func _delete_selected_building() -> void:
	var selected: Array = game_map.selection_mgr.selected
	if selected.size() != 1:
		return
	var first: Node2D = selected[0]
	if not (first is BuildingBase):
		return
	var b: BuildingBase = first as BuildingBase
	if b.player_owner != 0:
		return
	# Don't allow deleting the Town Center
	if b.building_type == BuildingData.BuildingType.TOWN_CENTER:
		hud.show_notification("Cannot delete Town Center!", Color(1.0, 0.4, 0.3))
		return
	# Refund 50% of building cost
	var cost: Dictionary = BuildingData.get_building_cost(b.building_type)
	for res_type in cost:
		ResourceManager.add_resource(0, res_type, int(cost[res_type] * 0.5))
	hud.show_notification("Building demolished (50%% refund)", Color(0.8, 0.7, 0.5))
	game_map.selection_mgr.deselect_all()
	b.take_damage(b.max_hp + 1)  # Destroy it


func _toggle_stance() -> void:
	var selected: Array = game_map.selection_mgr.selected
	if selected.is_empty():
		return
	var toggled: int = 0
	for node in selected:
		if node is UnitBase and node.player_owner == 0:
			var u: UnitBase = node as UnitBase
			if u.stance == UnitBase.Stance.AGGRESSIVE:
				u.stance = UnitBase.Stance.STAND_GROUND
			else:
				u.stance = UnitBase.Stance.AGGRESSIVE
			u.queue_redraw()
			toggled += 1
	if toggled > 0:
		var first_unit: UnitBase = null
		for node in selected:
			if node is UnitBase:
				first_unit = node as UnitBase
				break
		if first_unit:
			var stance_name: String = "Stand Ground" if first_unit.stance == UnitBase.Stance.STAND_GROUND else "Aggressive"
			hud.show_notification("Stance: %s" % stance_name, Color(0.8, 0.7, 0.5))
	_refresh_unit_command_hud()


func _arm_move_command() -> void:
	if not _has_selected_owned_units():
		hud.show_notification("Select your units first", Color(1.0, 0.55, 0.35))
		return
	_move_command_armed = true
	_attack_move_command_armed = false
	_patrol_command_armed = false
	_sync_selection_command_mode()
	hud.show_notification("Move armed: tap a destination", Color(0.55, 0.82, 1.0))
	_refresh_unit_command_hud()


func _arm_attack_move_command() -> void:
	if not _has_selected_owned_units():
		hud.show_notification("Select your units first", Color(1.0, 0.55, 0.35))
		return
	_move_command_armed = false
	_attack_move_command_armed = true
	_patrol_command_armed = false
	_sync_selection_command_mode()
	hud.show_notification("Attack-move armed: tap ground or a target", Color(1.0, 0.58, 0.36))
	_refresh_unit_command_hud()


func _has_selected_owned_units() -> bool:
	for node in game_map.selection_mgr.selected:
		if is_instance_valid(node) and node is UnitBase and (node as UnitBase).player_owner == 0:
			return true
	return false


func _clear_armed_unit_commands(refresh_hud: bool = true) -> void:
	_move_command_armed = false
	_attack_move_command_armed = false
	_patrol_command_armed = false
	_sync_selection_command_mode()
	if refresh_hud:
		_refresh_unit_command_hud()


func _sync_selection_command_mode() -> void:
	if game_map == null or game_map.selection_mgr == null:
		return
	game_map.selection_mgr.set_unit_command_armed(
		_move_command_armed or _attack_move_command_armed or _patrol_command_armed
	)


func _current_unit_command_mode() -> String:
	if _move_command_armed:
		return "move"
	if _attack_move_command_armed:
		return "attack_move"
	if _patrol_command_armed:
		return "patrol"
	return "smart"


func _refresh_unit_command_hud() -> void:
	if hud == null or game_map == null or game_map.selection_mgr == null:
		return
	var authorized: bool = false
	var has_military: bool = false
	var stance_name: String = "Aggressive"
	var stance_set: bool = false
	for node in game_map.selection_mgr.selected:
		if not is_instance_valid(node) or not node is UnitBase:
			continue
		var unit := node as UnitBase
		if unit.player_owner != 0:
			continue
		authorized = true
		if unit.unit_type != UnitData.UnitType.VILLAGER:
			has_military = true
		if not stance_set:
			stance_name = "Stand Ground" if unit.stance == UnitBase.Stance.STAND_GROUND else "Aggressive"
			stance_set = true
	hud.configure_unit_commands(authorized, has_military, stance_name, _current_unit_command_mode())


func _deselect_from_hud() -> void:
	_clear_armed_unit_commands(false)
	game_map.selection_mgr.deselect_all()


func _arm_patrol_command() -> void:
	var selected: Array = game_map.selection_mgr.selected
	if selected.is_empty():
		return
	var has_military: bool = false
	for node in selected:
		if node is UnitBase and node.player_owner == 0 and node.unit_type != UnitData.UnitType.VILLAGER:
			has_military = true
			break
	if not has_military:
		hud.show_notification("Patrol requires military units", Color(1.0, 0.55, 0.35))
		return
	_move_command_armed = false
	_attack_move_command_armed = false
	_patrol_command_armed = true
	_sync_selection_command_mode()
	hud.show_notification("Patrol armed: issue move command", Color(0.9, 0.75, 0.35))
	_refresh_unit_command_hud()


func _select_town_center() -> void:
	if is_instance_valid(_player_town_center):
		game_map.selection_mgr.select_single(_player_town_center)
		if _guided_opening_active and _guided_stage <= GuidedOpeningStage.TRAIN_SCOUT:
			game_map.camera.position = _get_initial_camera_focus(_player_town_center.global_position)
		else:
			game_map.camera.position = _player_town_center.global_position
		game_map._clamp_camera()
		_update_progression_hint()
		return
	for building in _player_buildings[0]:
		if is_instance_valid(building) and building.building_type == BuildingData.BuildingType.TOWN_CENTER:
			_player_town_center = building
			game_map.selection_mgr.select_single(building)
			if _guided_opening_active and _guided_stage <= GuidedOpeningStage.TRAIN_SCOUT:
				game_map.camera.position = _get_initial_camera_focus(building.global_position)
			else:
				game_map.camera.position = building.global_position
			game_map._clamp_camera()
			_update_progression_hint()
			return


func _handle_production_hotkey() -> void:
	var selected: Array = game_map.selection_mgr.selected
	if selected.is_empty():
		return
	var first: Node2D = selected[0]
	if not (first is BuildingBase):
		return
	var building: BuildingBase = first as BuildingBase
	if not building.can_train():
		return
	if building.trainable_units.size() > 0:
		_on_train_unit_requested(building, building.trainable_units[0])


# =========================================================================
#  IDLE VILLAGER CYCLING
# =========================================================================

func _on_idle_villager_pressed() -> void:
	var idle_villagers: Array = []
	for unit in _player_units[0]:
		if is_instance_valid(unit) and unit is Villager and unit.current_state == UnitBase.State.IDLE:
			idle_villagers.append(unit)
	if idle_villagers.is_empty():
		return
	_idle_villager_index = _idle_villager_index % idle_villagers.size()
	var target: UnitBase = idle_villagers[_idle_villager_index]
	_idle_villager_index = (_idle_villager_index + 1) % idle_villagers.size()
	game_map.selection_mgr.deselect_all()
	game_map.selection_mgr._add_to_selection(target)
	game_map.camera.position = target.global_position


func _update_idle_villager_count() -> void:
	var idle_count: int = 0
	var military_count: int = 0
	var vill_food: int = 0
	var vill_wood: int = 0
	var vill_gold: int = 0
	var vill_build: int = 0
	for unit in _player_units[0]:
		if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEAD:
			continue
		if unit is Villager:
			var v: Villager = unit as Villager
			if v.current_state == UnitBase.State.IDLE:
				idle_count += 1
			# A carried resource type is cargo, not evidence of an active job.
			match v.get_economy_task():
				"food": vill_food += 1
				"wood": vill_wood += 1
				"gold": vill_gold += 1
				"build": vill_build += 1
		else:
			military_count += 1
	hud.update_idle_villager_count(idle_count)
	hud.update_military_count(military_count)
	hud.update_villager_tasks(vill_food, vill_wood, vill_gold, vill_build)


# =========================================================================
#  PLAYER START SETUP
# =========================================================================

func _setup_player_start(player_id: int, spawn_tile: Vector2i) -> void:
	# Place Town Center.
	var tc := _spawn_building(BuildingData.BuildingType.TOWN_CENTER, player_id, spawn_tile)
	tc.complete_instantly()
	if player_id == 0:
		_player_town_center = tc
	# Note: pop cap is already handled by _on_building_constructed via complete_instantly()

	# Note: TC production queue is already connected in _spawn_building().

	# Place 4 starting villagers nearby and auto-assign to gather.
	var offsets: Array[Vector2i] = [Vector2i(1, 2), Vector2i(-1, 2), Vector2i(0, 3), Vector2i(2, 1)]
	var villagers: Array[UnitBase] = []
	for offset in offsets:
		var vill_tile: Vector2i = spawn_tile + offset
		var vill_pos: Vector2 = game_map.tile_to_world(vill_tile)
		var v := _spawn_unit(UnitData.UnitType.VILLAGER, player_id, vill_pos)
		if v:
			villagers.append(v)

	# Auto-assign: food, wood, gold, food (4 villagers).
	# Use call_deferred so resource nodes are spawned first.
	call_deferred("_auto_assign_starting_villagers", villagers)


func _auto_assign_starting_villagers(villagers: Array) -> void:
	var assignments: Array[String] = ["food", "wood", "gold", "food"]
	for i in villagers.size():
		var v: UnitBase = villagers[i] as UnitBase
		if not is_instance_valid(v):
			continue
		var res_type: String = assignments[i] if i < assignments.size() else "food"
		var resource_node: Node2D = game_map.get_nearest_resource_node(res_type, v.global_position, v.player_owner)
		if resource_node and v.has_method("command_gather"):
			v.command_gather(resource_node)


# =========================================================================
#  UNIT SPAWNING
# =========================================================================

func _spawn_unit(
	unit_type: int,
	player_id: int,
	world_pos: Vector2,
	source_queue: ProductionQueue = null
) -> UnitBase:
	var pop_cost: int = int(UnitData.UNITS.get(unit_type, {}).get("pop_cost", 1))
	var scene: PackedScene = _unit_scenes.get(unit_type)
	if scene == null:
		push_warning("No scene for unit type %d" % unit_type)
		return null

	var instance: Node = scene.instantiate()
	if instance == null or not instance is UnitBase:
		if instance != null:
			instance.free()
		push_warning("Unit scene for type %d did not instantiate UnitBase" % unit_type)
		return null
	var unit: UnitBase = instance as UnitBase
	var population_committed: bool = false
	if source_queue == null:
		if not GameManager.add_population(player_id, pop_cost):
			unit.free()
			push_warning("No population room to spawn unit type %d for player %d" % [unit_type, player_id])
			return null
		population_committed = true
	var units_container: Node = game_map.get_node_or_null("UnitsContainer") if game_map != null else null
	if units_container == null:
		if population_committed:
			GameManager.remove_population(player_id, pop_cost)
		unit.free()
		push_warning("Cannot spawn unit type %d without UnitsContainer" % unit_type)
		return null
	if source_queue != null:
		if not source_queue.consume_completed_population_reservation():
			unit.free()
			push_warning("Cannot spawn unit type %d without its population reservation" % unit_type)
			return null
	unit.player_owner = player_id
	unit.unit_type = unit_type
	unit.global_position = world_pos
	unit.set_team_color(TEAM_COLORS[player_id])

	units_container.add_child(unit)
	_player_units[player_id].append(unit)

	# Economic/villager upgrades alter the live unit. Combat attack and armor
	# upgrades remain dynamic base-stat modifiers in Combat for every unit.
	if unit is Villager:
		var gather_bonus: float = GameManager.get_gather_bonus(player_id)
		var hp_bonus: int = GameManager.get_villager_hp_bonus(player_id)
		if gather_bonus > 0.0:
			(unit as Villager).gather_rate += gather_bonus
		if hp_bonus > 0:
			unit.max_hp += hp_bonus
			unit.hp += hp_bonus

	# Track unit death.
	unit.unit_died.connect(_on_unit_died.bind(player_id))

	# Under-attack detection for player units.
	if player_id == 0 and unit.has_signal("health_changed"):
		unit.health_changed.connect(_on_player_unit_damaged)

	# Track resource deposits for stats.
	if unit.has_signal("resource_deposited"):
		unit.resource_deposited.connect(_on_resource_deposited.bind(player_id))

	# Register with AI if it's the AI's unit.
	if player_id == ai_controller.player_id:
		ai_controller.register_unit(unit)

	return unit


func _on_unit_trained(unit_type: int, player_id: int, source_queue: ProductionQueue) -> void:
	var producer: BuildingBase = source_queue.get_producing_building()
	var spawn_result: Dictionary = _resolve_production_egress(producer)
	if not bool(spawn_result.get("valid", false)):
		source_queue.reject_completed_unit()
		_update_population_display()
		push_warning("Training completed but no bounded walkable egress exists for unit type %d (player %d)" % [unit_type, player_id])
		return
	var spawn_pos: Vector2 = spawn_result.get("world_position", Vector2.ZERO)
	var unit: UnitBase = _spawn_unit(unit_type, player_id, spawn_pos, source_queue)
	if unit == null:
		source_queue.reject_completed_unit()
		_update_population_display()
		push_warning("Training completed but unit type %d could not spawn for player %d" % [unit_type, player_id])
		return
	_update_population_display()
	_stats[player_id]["units_trained"] += 1
	if unit_type != UnitData.UnitType.VILLAGER:
		_stats[player_id]["army_trained"] += 1
	var use_default_villager_assignment: bool = (
		player_id == 0
		and unit is Villager
		and not producer.has_custom_rally_point()
	)
	if not use_default_villager_assignment:
		_issue_production_rally(unit, producer.rally_point)
	if player_id == 0:
		_update_idle_villager_count()
		_on_selection_changed(game_map.selection_mgr.selected)
		AudioManager.play_sfx("unit_trained")
		hud.show_notification("Unit trained: %s" % UnitData.get_unit_name(unit_type), Color(0.4, 0.7, 1.0))
		if (
			unit != null
			and unit_type == UnitData.UnitType.SCOUT
			and _guided_opening_active
			and _guided_stage == GuidedOpeningStage.MOVE_MILITARY
		):
			game_map.selection_mgr.select_single(unit)
			game_map.camera.position = unit.global_position
			game_map.camera.reset_smoothing()
			hud.show_notification("Scout ready: tap Military, then tap open ground.", Color(0.95, 0.86, 0.42))
			_update_progression_hint()
		# Auto-assign new villagers to gather the most needed resource
		if unit and unit_type == UnitData.UnitType.VILLAGER and use_default_villager_assignment:
			_auto_assign_new_villager(unit)
		# Warn when population is near cap
		var player_data: Dictionary = GameManager.players.get(0, {})
		var pop: int = player_data.get("population", 0)
		var cap: int = player_data.get("population_cap", 5)
		if pop >= cap:
			var message: String = "Population cap reached! Build more Houses."
			if cap >= GameManager.get_player_population_limit(0):
				message = "Maximum population reached (%d). Workers and troops share this limit." % cap
			hud.show_notification(message, Color(1.0, 0.5, 0.2))
		elif pop >= cap - 2:
			hud.show_notification("Population almost full (%d/%d)" % [pop, cap], Color(1.0, 0.7, 0.3))


func _resolve_production_egress(producer: BuildingBase) -> Dictionary:
	## Select the nearest legal perimeter ring and stop after a hard three-tile
	## fallback. A sealed producer fails safely instead of spawning at its rally.
	if not is_instance_valid(producer) or game_map == null:
		return {"valid": false}
	var origin: Vector2i = game_map.world_to_tile(producer.global_position)
	for ring: int in range(1, PRODUCTION_EGRESS_MAX_RING_TILES + 1):
		var candidates: Array[Vector2i] = []
		var min_x: int = origin.x - ring
		var max_x: int = origin.x + producer.footprint.x - 1 + ring
		var min_y: int = origin.y - ring
		var max_y: int = origin.y + producer.footprint.y - 1 + ring
		for y: int in range(min_y, max_y + 1):
			for x: int in range(min_x, max_x + 1):
				if x != min_x and x != max_x and y != min_y and y != max_y:
					continue
				var tile := Vector2i(x, y)
				if game_map.is_tile_walkable(tile):
					candidates.append(tile)
		if candidates.is_empty():
			continue
		candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var a_world: Vector2 = game_map.tile_to_world(a)
			var b_world: Vector2 = game_map.tile_to_world(b)
			var a_rally_distance: float = a_world.distance_squared_to(producer.rally_point)
			var b_rally_distance: float = b_world.distance_squared_to(producer.rally_point)
			if not is_equal_approx(a_rally_distance, b_rally_distance):
				return a_rally_distance < b_rally_distance
			if a.y != b.y:
				return a.y < b.y
			return a.x < b.x
		)
		if candidates.size() > PRODUCTION_EGRESS_MAX_CANDIDATES:
			candidates.resize(PRODUCTION_EGRESS_MAX_CANDIDATES)
		var chosen_tile: Vector2i = candidates[0]
		return {
			"valid": true,
			"tile": chosen_tile,
			"world_position": game_map.tile_to_world(chosen_tile),
			"ring": ring,
		}
	return {"valid": false}


func _issue_production_rally(unit: UnitBase, requested_rally: Vector2) -> bool:
	if not is_instance_valid(unit) or game_map == null:
		return false
	var route: PackedVector2Array = game_map.get_navigation_world_path(
		unit.global_position,
		requested_rally,
		PRODUCTION_RALLY_ARRIVAL_RADIUS
	)
	if route.is_empty():
		return false
	if unit.unit_type != UnitData.UnitType.VILLAGER:
		route = _get_unoccupied_production_rally_path(unit, route)
	var valid_destination: Vector2 = route[route.size() - 1]
	if unit.global_position.distance_to(valid_destination) <= PRODUCTION_RALLY_ARRIVAL_RADIUS:
		return false
	unit.command_move_path(route)
	return true


func _get_unoccupied_production_rally_path(unit: UnitBase, original_route: PackedVector2Array) -> PackedVector2Array:
	# Repeated births must not finish on the same idle sprite. Keep the public
	# marker intact and spread only military arrivals over a bounded nearby area.
	var rally_tile: Vector2i = game_map.world_to_tile(original_route[original_route.size() - 1])
	var candidates: Array[Vector2i] = []
	for dy: int in range(-PRODUCTION_RALLY_SLOT_RADIUS_TILES, PRODUCTION_RALLY_SLOT_RADIUS_TILES + 1):
		for dx: int in range(-PRODUCTION_RALLY_SLOT_RADIUS_TILES, PRODUCTION_RALLY_SLOT_RADIUS_TILES + 1):
			var tile := rally_tile + Vector2i(dx, dy)
			if game_map.is_tile_walkable(tile):
				candidates.append(tile)
	var rally_world: Vector2 = game_map.tile_to_world(rally_tile)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_distance: float = game_map.tile_to_world(a).distance_squared_to(rally_world)
		var b_distance: float = game_map.tile_to_world(b).distance_squared_to(rally_world)
		if not is_equal_approx(a_distance, b_distance):
			return a_distance < b_distance
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	for candidate: Vector2i in candidates:
		var destination: Vector2 = game_map.tile_to_world(candidate)
		if not _is_production_rally_slot_free(unit, destination):
			continue
		var route: PackedVector2Array = original_route
		if destination.distance_to(original_route[original_route.size() - 1]) > PRODUCTION_RALLY_ARRIVAL_RADIUS:
			route = game_map.get_navigation_world_path(unit.global_position, destination, PRODUCTION_RALLY_ARRIVAL_RADIUS)
		if not route.is_empty() and route[route.size() - 1].distance_to(destination) <= PRODUCTION_RALLY_ARRIVAL_RADIUS:
			return route
	# A crowded or sealed local area must not reject an already paid birth.
	return original_route


func _is_production_rally_slot_free(unit: UnitBase, destination: Vector2) -> bool:
	# Own positions and own issued movement destinations are public knowledge.
	# Hostile units, fog state, and hostile orders never influence slot choice.
	for entry: Variant in _player_units[unit.player_owner]:
		if not is_instance_valid(entry) or not entry is UnitBase or entry == unit:
			continue
		var other := entry as UnitBase
		if other.current_state == UnitBase.State.DEAD:
			continue
		if other.global_position.distance_to(destination) < PRODUCTION_RALLY_SLOT_CLEARANCE_WORLD:
			return false
		if other.current_state == UnitBase.State.MOVING and other.move_target.distance_to(destination) < PRODUCTION_RALLY_SLOT_CLEARANCE_WORLD:
			return false
	return true


func _on_unit_died(unit: UnitBase, player_id: int) -> void:
	_player_units[player_id].erase(unit)
	var pop_cost: int = UnitData.UNITS.get(unit.unit_type, {}).get("pop_cost", 1)
	GameManager.remove_population(player_id, pop_cost)
	_update_population_display()
	_stats[player_id]["units_lost"] += 1
	# The opposing player gets a kill credit
	var enemy_id: int = 1 if player_id == 0 else 0
	_stats[enemy_id]["units_killed"] += 1
	if player_id == 0:
		hud.show_notification("Unit lost!", Color(1.0, 0.3, 0.3))


func _on_resource_deposited(_resource_type: String, amount: int, player_id: int = 0) -> void:
	_stats[player_id]["resources_gathered"] += amount


func _auto_assign_new_villager(villager: UnitBase) -> void:
	# A purchase can empty the wood bank without changing long-term labor
	# needs. Assign only the newborn; preserve every existing player order.
	var counts: Dictionary = {"food": 0, "wood": 0, "gold": 0}
	var total_workers: int = 1
	for unit: Node in _player_units[0]:
		if not is_instance_valid(unit) or not unit is Villager or unit == villager or unit.current_state == UnitBase.State.DEAD:
			continue
		total_workers += 1
		match (unit as Villager).gather_type:
			Villager.GatherType.FOOD: counts["food"] += 1
			Villager.GatherType.WOOD: counts["wood"] += 1
			Villager.GatherType.GOLD: counts["gold"] += 1
	var weights: Dictionary = SkirmishData.get_new_worker_weights(GameManager.get_player_age(0))
	var priority: Array[String] = ["food", "wood", "gold"]
	var ranks: Dictionary = {"food": 0, "wood": 1, "gold": 2}
	priority.sort_custom(func(a: String, b: String) -> bool:
		var deficit_a: float = float(weights[a]) * total_workers - int(counts[a])
		var deficit_b: float = float(weights[b]) * total_workers - int(counts[b])
		return int(ranks[a]) < int(ranks[b]) if is_equal_approx(deficit_a, deficit_b) else deficit_a > deficit_b
	)
	for res_type in priority:
		var node: Node2D = game_map.get_nearest_reachable_resource_node(res_type, villager.global_position, villager.player_owner)
		if node != null and bool(villager.call("command_gather", node)):
			return


func _on_player_unit_damaged(_unit: UnitBase, _new_hp: float, _max_hp: float) -> void:
	if _under_attack_cooldown <= 0.0:
		_under_attack_cooldown = UNDER_ATTACK_COOLDOWN_TIME
		hud.show_notification("Under attack!", Color(1.0, 0.4, 0.2))
		AudioManager.play_sfx("under_attack")


# =========================================================================
#  BUILDING SPAWNING
# =========================================================================

func _spawn_building(building_type: int, player_id: int, tile_pos: Vector2i) -> BuildingBase:
	var scene: PackedScene = _building_scenes.get(building_type)
	if scene == null:
		push_warning("No scene for building type %d" % building_type)
		return null

	var building: BuildingBase = scene.instantiate()
	building.player_owner = player_id
	building.building_type = building_type
	building.global_position = game_map.tile_to_world(tile_pos)

	game_map.get_node("BuildingsContainer").add_child(building)
	_player_buildings[player_id].append(building)
	if building.provides_food:
		game_map.register_harvestable(building)

	# Mark pathfinding obstacle.
	game_map.place_building_obstacle(tile_pos, building.footprint)

	# Connect building signals.
	building.construction_complete.connect(_on_building_constructed.bind(player_id))
	building.building_destroyed.connect(_on_building_destroyed.bind(player_id, tile_pos))

	# Connect production queue if it has one.
	var pq: Node = building.get_production_queue()
	if pq == null:
		pq = building.get_node_or_null("ProductionQueue")
		if pq != null:
			building.set_production_queue(pq)
	if pq:
		var unit_trained_callback := Callable(self, "_on_unit_trained").bind(player_id, pq)
		if not pq.is_connected("unit_trained", unit_trained_callback):
			pq.connect("unit_trained", unit_trained_callback)
		if player_id == 0 and not pq.is_connected("queue_changed", _update_population_display):
			pq.connect("queue_changed", _update_population_display)

	# Register with AI.
	if player_id == ai_controller.player_id:
		ai_controller.register_building(building)

	return building


func _on_building_constructed(building: BuildingBase, player_id: int) -> void:
	if player_id == ai_controller.player_id:
		_ai_construction_jobs.erase(building.get_instance_id())
	if building.pop_provided > 0:
		GameManager.grant_population_cap(player_id, building.get_instance_id(), building.pop_provided)
		_update_population_display()
	_stats[player_id]["buildings_built"] += 1
	if player_id == 0:
		AudioManager.play_sfx("building_complete")
		hud.show_notification("Building complete: %s" % building.building_name, Color(0.3, 0.85, 0.3))
		if building.building_type == BuildingData.BuildingType.HOUSE and not _milestone_first_house:
			_milestone_first_house = true
			hud.show_notification("Milestone: First House complete.", Color(0.92, 0.84, 0.38))
		if building.building_type in [
			BuildingData.BuildingType.BARRACKS,
			BuildingData.BuildingType.ARCHERY_RANGE,
			BuildingData.BuildingType.STABLE,
		] and not _milestone_first_military_building:
			_milestone_first_military_building = true
			hud.show_notification("Milestone: Military production unlocked.", Color(0.82, 0.72, 1.0))
		_refresh_guided_opening_stage()
		_update_progression_hint()


func _on_building_destroyed(building: BuildingBase, player_id: int, tile_pos: Vector2i) -> void:
	if player_id == ai_controller.player_id:
		# Combat destruction is a real loss (and AIController records a rebuild),
		# so stop recovery without refunding this construction transaction.
		_ai_construction_jobs.erase(building.get_instance_id())
	_player_buildings[player_id].erase(building)
	if building.provides_food:
		game_map.unregister_harvestable(building)
	_stats[player_id]["buildings_lost"] += 1
	game_map.remove_building_obstacle(tile_pos, building.footprint)
	if player_id == 0:
		hud.show_notification("Building destroyed!", Color(1.0, 0.3, 0.3))

	if building.pop_provided > 0:
		# Existing units and reservations survive an over-cap state. The cap ledger
		# removes this provider's nominal contribution and rebalances every survivor.
		GameManager.revoke_population_cap(building.get_instance_id())
		_update_population_display()

	# Check win condition: Town Center destroyed.
	if building.building_type == BuildingData.BuildingType.TOWN_CENTER:
		var has_tc := false
		for b in _player_buildings[player_id]:
			if is_instance_valid(b) and b.building_type == BuildingData.BuildingType.TOWN_CENTER:
				has_tc = true
				break
		if not has_tc:
			var winner_id: int = 1 if player_id == 0 else 0
			_conclude_match(winner_id, "%s destroyed" % building.building_name)


# =========================================================================
#  SELECTION + COMMANDS
# =========================================================================

func _on_selection_changed(selected_units: Array[Node2D]) -> void:
	if selected_units.is_empty():
		_clear_armed_unit_commands(false)
		hud.clear_selection()
		_update_progression_hint()
		return

	var first: Node2D = selected_units[0]
	if first is ResourceNode:
		_clear_armed_unit_commands(false)
		var r: ResourceNode = first as ResourceNode
		var type_name: String = r.resource_type.capitalize()
		var pct: int = int(float(r.remaining) / float(r.total_amount) * 100.0)
		hud.show_resource_info(type_name, r.remaining, r.total_amount, pct)
		_update_progression_hint()
		return
	if first is UnitBase:
		var u: UnitBase = first as UnitBase
		var action_text: String = UnitBase.State.keys()[u.current_state]
		# The worker owns its work intent; cargo never substitutes for status.
		if u is Villager:
			var v: Villager = u as Villager
			action_text = v.get_work_status()
		# Count selected units of same type
		var count: int = 0
		var total_hp: int = 0
		var total_max_hp: int = 0
		for node in selected_units:
			if node is UnitBase and (node as UnitBase).unit_type == u.unit_type:
				count += 1
				total_hp += int((node as UnitBase).hp)
				total_max_hp += int((node as UnitBase).max_hp)
		# A mixed army must describe the whole selection rather than claiming
		# every soldier has the first unit's type, damage and armor.
		var mixed_selection: bool = count < selected_units.size()
		var selection_title: String = UnitData.get_unit_name(u.unit_type)
		if mixed_selection:
			count = selected_units.size()
			total_hp = 0
			total_max_hp = 0
			var includes_workers: bool = false
			for node in selected_units:
				if node is UnitBase:
					total_hp += int((node as UnitBase).hp)
					total_max_hp += int((node as UnitBase).max_hp)
					includes_workers = includes_workers or node is Villager
			selection_title = "Units" if includes_workers else "Army"
			action_text = "Mixed (%d units)" % count
		var stats: Dictionary = {"unit_type": u.unit_type}
		if not mixed_selection and u is Villager:
			var worker_statuses: Dictionary = {}
			var cargo_types: Dictionary = {}
			var cargo_amount: int = 0
			var cargo_capacity: int = 0
			for node in selected_units:
				if node is Villager:
					var worker: Villager = node as Villager
					var status: String = worker.get_work_status()
					worker_statuses[status] = int(worker_statuses.get(status, 0)) + 1
					cargo_amount += worker.carried_amount
					cargo_capacity += worker.carry_capacity
					if worker.carried_amount > 0:
						cargo_types[worker.carried_resource_type] = true
			if worker_statuses.size() > 1:
				action_text = "Mixed tasks"
			stats["cargo_amount"] = cargo_amount
			stats["cargo_capacity"] = cargo_capacity
			stats["cargo_resource"] = str(cargo_types.keys()[0]) if cargo_types.size() == 1 else "mixed"
		if mixed_selection:
			var role_counts: Dictionary = {}
			for node in selected_units:
				if node is UnitBase:
					var role_type: int = (node as UnitBase).unit_type
					role_counts[role_type] = int(role_counts.get(role_type, 0)) + 1
			stats["role_counts"] = role_counts
		if not mixed_selection and not (u is Villager):
			stats = {
				"unit_type": u.unit_type,
				"damage": int(Combat.get_effective_attack(u)),
				"armor": int(Combat.get_effective_armor(u)),
				"range": int(round(MapData.world_to_range_tiles(u.attack_range))),
			}
			var stance_name: String = "Stand Ground" if u.stance == UnitBase.Stance.STAND_GROUND else "Aggressive"
			stats["stance"] = stance_name
		hud.show_unit_selection(selection_title, total_hp, total_max_hp, action_text, count, stats)
		_refresh_unit_command_hud()
	elif first is BuildingBase:
		_clear_armed_unit_commands(false)
		var b: BuildingBase = first as BuildingBase
		var queue_info: Array = []
		var trainable_units: Array = []
		# Enemy structures remain inspectable, but their production state and
		# command surface are private to their owner.
		if b.player_owner == 0:
			var pq: Node = b.get_production_queue()
			if pq:
				queue_info = pq.get_queue_info()
			trainable_units = b.trainable_units
		hud.show_building_selection(b.building_name, b.hp, b.max_hp, queue_info, trainable_units, b)
	_update_progression_hint()


func _on_move_command(target_tile: Vector2i) -> void:
	var selected: Array = game_map.selection_mgr.selected
	var issue_patrol: bool = _patrol_command_armed
	var issue_force_move: bool = _move_command_armed
	var issue_attack_move: bool = _attack_move_command_armed
	_clear_armed_unit_commands(false)

	# Check if a production building is selected — set rally point
	if selected.size() == 1 and selected[0] is BuildingBase:
		var b: BuildingBase = selected[0] as BuildingBase
		if b.player_owner == 0 and b.trainable_units.size() > 0:
			var target_in_bounds: bool = (
				target_tile.x >= 0
				and target_tile.x < MapData.MAP_WIDTH
				and target_tile.y >= 0
				and target_tile.y < MapData.MAP_HEIGHT
			)
			if not target_in_bounds:
				hud.show_notification("Rally point unavailable. Choose another location.", Color(1.0, 0.62, 0.32))
				return
			# Only reject a blocker the player can currently see. Hidden tiles accept
			# the same rally interaction regardless of their private walkability, and
			# produced units later resolve a legal endpoint through normal navigation.
			if (
				game_map.is_tile_visible_to_player(target_tile, 0)
				and not game_map.is_tile_walkable(target_tile)
			):
				hud.show_notification("Rally point unavailable. Choose another location.", Color(1.0, 0.62, 0.32))
				return
			var rally_world: Vector2 = game_map.tile_to_world(target_tile)
			b.set_rally_point(rally_world)
			VFX.move_indicator(get_tree(), rally_world)
			hud.show_notification("Rally point set: %s" % b.building_name, Color(0.58, 0.82, 1.0))
			return

	# Collect moveable units
	var moveable: Array[UnitBase] = []
	var has_military: bool = false
	for node in selected:
		if node is UnitBase and node.player_owner == 0:
			var unit: UnitBase = node as UnitBase
			moveable.append(unit)
			if unit.unit_type != UnitData.UnitType.VILLAGER:
				has_military = true
	if moveable.is_empty():
		return
	if issue_patrol and not has_military:
		issue_patrol = false
	if has_military and _guided_opening_active and _guided_stage == GuidedOpeningStage.MOVE_MILITARY:
		_opening_military_move_complete = true
		call_deferred("_refresh_guided_opening_stage")

	# Generate formation offsets so units spread out around the target
	var offsets := _get_formation_offsets(moveable.size())

	for i in moveable.size():
		var unit: UnitBase = moveable[i]
		var dest_tile: Vector2i = target_tile + offsets[i]
		# Clamp to map bounds
		dest_tile.x = clampi(dest_tile.x, 0, MapData.MAP_WIDTH - 1)
		dest_tile.y = clampi(dest_tile.y, 0, MapData.MAP_HEIGHT - 1)
		var world_pos: Vector2 = game_map.tile_to_world(dest_tile)
		var unit_tile: Vector2i = game_map.world_to_tile(unit.global_position)
		var tile_path: Array[Vector2i] = game_map.get_movement_path(unit_tile, dest_tile)
		# Military units use smart attack-move by default. Explicit Move suppresses
		# engagement for every selected unit; A-Move makes the intent visible and
		# available to villagers as well.
		var is_military: bool = unit.unit_type != UnitData.UnitType.VILLAGER
		if tile_path.size() > 1:
			var world_path := PackedVector2Array()
			for tp in tile_path:
				world_path.append(game_map.tile_to_world(tp))
			if issue_patrol and is_military:
				unit.command_patrol(world_pos)
			elif issue_force_move:
				unit.command_move_path(world_path)
			elif is_military or issue_attack_move:
				unit.command_attack_move_path(world_path)
			else:
				unit.command_move_path(world_path)
		else:
			if issue_patrol and is_military:
				unit.command_patrol(world_pos)
			elif issue_force_move:
				unit.command_move(world_pos)
			elif is_military or issue_attack_move:
				unit.command_attack_move(world_pos)
			else:
				unit.command_move(world_pos)

	if issue_patrol:
		VFX.move_indicator(get_tree(), game_map.tile_to_world(target_tile))
		hud.show_notification("Patrol route set", Color(0.95, 0.8, 0.4))
	# Show green indicator for regular move, red for attack-move
	elif not issue_force_move and (has_military or issue_attack_move):
		VFX.attack_move_indicator(get_tree(), game_map.tile_to_world(target_tile))
	else:
		VFX.move_indicator(get_tree(), game_map.tile_to_world(target_tile))
	AudioManager.play_sfx("command_move")
	_refresh_unit_command_hud()


## Generate spiral offsets around (0,0) for formation spreading.
func _get_formation_offsets(count: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = [Vector2i(0, 0)]
	if count <= 1:
		return offsets
	# Spiral outward: right, down, left, up with increasing ring size
	var directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	var pos := Vector2i(1, 0)
	var ring := 1
	var dir_idx := 0
	var steps_in_dir := 0
	var side_length := 1
	var sides_done := 0
	# Start at (1,0) and spiral
	offsets.append(pos)
	while offsets.size() < count:
		steps_in_dir += 1
		if steps_in_dir >= side_length:
			steps_in_dir = 0
			dir_idx = (dir_idx + 1) % 4
			sides_done += 1
			if sides_done >= 2:
				sides_done = 0
				side_length += 1
		pos += directions[dir_idx]
		offsets.append(pos)
	return offsets


func _on_attack_command(target: Node2D) -> void:
	if _route_armed_unit_command_to_target(target):
		return
	_clear_armed_unit_commands(false)
	var selected: Array = game_map.selection_mgr.selected
	for node in selected:
		if node is UnitBase and node.player_owner == 0:
			if target is UnitBase:
				node.command_attack(target as UnitBase)
			elif target is BuildingBase:
				node.command_attack_building(target as BuildingBase)
	_refresh_unit_command_hud()


func _on_gather_command(resource_node: Node2D) -> void:
	if _route_armed_unit_command_to_target(resource_node):
		return
	_clear_armed_unit_commands(false)
	if not game_map.is_resource_target_visible_to_player(resource_node, 0):
		return
	if not game_map.is_resource_target_valid(resource_node, "", 0):
		return
	var selected: Array = game_map.selection_mgr.selected
	var assigned_any: bool = false
	for node in selected:
		if node is UnitBase and node.player_owner == 0 and node.has_method("command_gather"):
			assigned_any = bool(node.call("command_gather", resource_node)) or assigned_any
	if assigned_any and resource_node.get_resource_type() == "food":
		_opening_gather_complete = true
	_refresh_guided_opening_stage()
	_refresh_unit_command_hud()


func _on_build_command(building: Node2D) -> void:
	if _route_armed_unit_command_to_target(building):
		return
	_clear_armed_unit_commands(false)
	var selected: Array = game_map.selection_mgr.selected
	for node in selected:
		if node is Villager and node.player_owner == 0:
			node.command_build(building)
	_refresh_unit_command_hud()


func _route_armed_unit_command_to_target(target: Node2D) -> bool:
	if not (_move_command_armed or _attack_move_command_armed or _patrol_command_armed):
		return false
	if target == null or not is_instance_valid(target):
		_clear_armed_unit_commands()
		return true
	_on_move_command(game_map.world_to_tile(target.global_position))
	return true


func _on_train_unit_requested(building: Node2D, unit_type: int) -> void:
	_last_train_request_unit_type = unit_type
	_last_train_feedback = ""
	if not is_instance_valid(building) or not (building is BuildingBase):
		_last_train_request_result = "invalid_building"
		_last_train_feedback = "Select a production building before training a unit."
		hud.show_notification(_last_train_feedback, Color(1.0, 0.4, 0.3))
		_refresh_first_session_diagnostics()
		return
	var b: BuildingBase = building as BuildingBase
	if b.player_owner != 0:
		_last_train_request_result = "not_owned"
		_last_train_feedback = "Enemy buildings can only be inspected."
		hud.show_notification(_last_train_feedback, Color(1.0, 0.55, 0.35))
		_refresh_first_session_diagnostics()
		return
	if not b.can_train():
		if b.state != BuildingBase.State.ACTIVE:
			_last_train_request_result = "building_inactive"
			_last_train_feedback = "%s must finish construction before it can train units." % b.building_name
		else:
			_last_train_request_result = "unit_unavailable"
			_last_train_feedback = "%s cannot train %s. Select a compatible production building." % [b.building_name, UnitData.get_unit_name(unit_type)]
		hud.show_notification(_last_train_feedback, Color(1.0, 0.4, 0.3))
		_refresh_first_session_diagnostics()
		return
	if unit_type not in b.trainable_units:
		_last_train_request_result = "unit_unavailable"
		_last_train_feedback = "%s cannot train %s. Select a compatible production building." % [b.building_name, UnitData.get_unit_name(unit_type)]
		hud.show_notification(_last_train_feedback, Color(1.0, 0.4, 0.3))
		_refresh_first_session_diagnostics()
		return
	# Check population room
	var pop_cost: int = UnitData.UNITS.get(unit_type, {}).get("pop_cost", 1)
	var player_data: Dictionary = GameManager.players.get(0, {})
	var pop: int = GameManager.get_committed_population(0)
	var cap: int = player_data.get("population_cap", 5)
	if pop + pop_cost > cap:
		_last_train_request_result = "population_blocked"
		if cap >= GameManager.get_player_population_limit(0):
			_last_train_feedback = "Not enough population space (%d/%d). %s needs %d slots." % [pop, cap, UnitData.get_unit_name(unit_type), pop_cost]
		else:
			_last_train_feedback = "Population full (%d/%d). Build a House before training %s." % [pop, cap, UnitData.get_unit_name(unit_type)]
		hud.show_notification(_last_train_feedback, Color(1.0, 0.6, 0.2))
		_refresh_first_session_diagnostics()
		return
	var pq: Node = b.get_production_queue()
	if pq:
		if pq is ProductionQueue and (pq as ProductionQueue).get_queue_size() >= ProductionQueue.MAX_QUEUE_SIZE:
			_last_train_request_result = "queue_full"
			_last_train_feedback = "%s queue full (%d/%d). Wait or cancel a queued unit." % [b.building_name, (pq as ProductionQueue).get_queue_size(), ProductionQueue.MAX_QUEUE_SIZE]
			hud.show_notification(_last_train_feedback, Color(1.0, 0.6, 0.2))
			_refresh_first_session_diagnostics()
			return
		var cost: Dictionary = UnitData.get_unit_cost(unit_type)
		var missing: Dictionary = ResourceManager.get_missing_resources(0, cost)
		if not missing.is_empty():
			_last_train_request_result = "resources_missing"
			_last_train_feedback = "Need %s to train %s." % [_format_missing_resources(missing), UnitData.get_unit_name(unit_type)]
			hud.show_notification(_last_train_feedback, Color(1.0, 0.4, 0.3))
			_refresh_first_session_diagnostics()
			return
		var success: bool = pq.enqueue_unit(unit_type)
		if not success:
			_last_train_request_result = "queue_rejected"
			_last_train_feedback = "%s cannot train %s right now. Check its construction and available units." % [b.building_name, UnitData.get_unit_name(unit_type)]
			hud.show_notification(_last_train_feedback, Color(1.0, 0.4, 0.3))
		else:
			_last_train_request_result = "queued"
			var guided_scout_fast_track: bool = (
				b.player_owner == 0
				and unit_type == UnitData.UnitType.SCOUT
				and _guided_opening_active
				and _guided_stage == GuidedOpeningStage.TRAIN_SCOUT
			)
			hud.show_notification("Queued: %s" % UnitData.get_unit_name(unit_type), Color(0.48, 0.78, 1.0))
			if unit_type == UnitData.UnitType.SCOUT:
				_opening_scout_queued = true
			_refresh_guided_opening_stage()
			# Guided fast-track is a best-effort onboarding convenience. A unit was
			# still queued successfully when another item is already at the head, so
			# retain the truthful `queued` result unless this Scout completes now.
			if guided_scout_fast_track and pq is ProductionQueue:
				var scout_queue: ProductionQueue = pq as ProductionQueue
				if (
					scout_queue.is_training
					and not scout_queue.queue.is_empty()
					and int(scout_queue.queue[0]) == unit_type
				):
					scout_queue._complete_current_unit()
					_last_train_request_result = "fast_track_completed"
		# Refresh selection display to show updated queue
		_on_selection_changed(game_map.selection_mgr.selected)
		_update_progression_hint()
		_refresh_first_session_diagnostics()
	else:
		_last_train_request_result = "missing_queue"
		_last_train_feedback = "%s has no production queue. Select another production building." % b.building_name
		hud.show_notification(_last_train_feedback, Color(1.0, 0.4, 0.3))
		_refresh_first_session_diagnostics()


func _format_missing_resources(missing: Dictionary) -> String:
	var parts: Array[String] = []
	for resource_type in ResourceManager.RESOURCE_NAMES:
		var amount: int = int(missing.get(resource_type, 0))
		if amount > 0:
			parts.append("%d more %s" % [amount, resource_type])
	return " and ".join(parts)


func _on_minimap_clicked(world_pos: Vector2) -> void:
	var target_tile: Vector2i = game_map.world_to_tile(world_pos)
	var snapped_world: Vector2 = game_map.tile_to_world(target_tile)
	var was_smoothing_enabled: bool = game_map.camera.position_smoothing_enabled
	if was_smoothing_enabled:
		game_map.camera.position_smoothing_enabled = false
	game_map.camera.position = snapped_world
	game_map._clamp_camera()
	game_map.camera.reset_smoothing()
	if was_smoothing_enabled:
		game_map.camera.position_smoothing_enabled = true


func _get_initial_camera_focus(player_spawn: Vector2) -> Vector2:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var short_side: float = minf(viewport_size.x, viewport_size.y)
	var phone_like: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or short_side <= 460.0
	var samples: Array[Vector2] = [player_spawn]
	for resource_type in ["food", "wood", "gold"]:
		var node: Node2D = game_map.get_nearest_resource_node(resource_type, player_spawn, 0)
		if node != null:
			samples.append(node.global_position)
	var weighted_center := Vector2.ZERO
	for sample in samples:
		weighted_center += sample
	weighted_center /= float(maxi(1, samples.size()))
	# Anchor the landmark in the playable middle of the phone screen.
	var focus: Vector2 = player_spawn.lerp(weighted_center, 0.28)
	if phone_like:
		focus.y += 14.0 / maxf(0.1, game_map.camera.zoom.y)
	return focus


func _on_cancel_queue_requested(building: Node2D, index: int) -> void:
	if not is_instance_valid(building) or not (building is BuildingBase):
		return
	var b: BuildingBase = building as BuildingBase
	if b.player_owner != 0:
		return
	var pq: Node = b.get_production_queue()
	if pq:
		pq.cancel_unit(index)
		_on_selection_changed(game_map.selection_mgr.selected)


func _on_research_requested(building: Node2D, research_id: String) -> void:
	if not is_instance_valid(building) or not (building is BuildingBase):
		return
	var b: BuildingBase = building as BuildingBase
	if (
		b.player_owner != 0
		or b.building_type != BuildingData.BuildingType.BLACKSMITH
		or b.state != BuildingBase.State.ACTIVE
	):
		return
	var gm: Node = GameManager
	if gm.has_research(b.player_owner, research_id):
		return

	# Look up cost and effect from HUD's research defs
	var cost: Dictionary = {}
	var effect_text := ""
	for rd in hud.RESEARCH_DEFS:
		if rd["id"] == research_id:
			cost = rd["cost"]
			effect_text = rd["desc"]
			break
	if cost.is_empty():
		return

	# Try to spend resources
	var rm: Node = ResourceManager
	if not rm.try_spend(b.player_owner, cost):
		hud.show_notification("Not enough resources!", Color(1.0, 0.4, 0.3))
		return

	# Apply upgrade
	gm.complete_research(b.player_owner, research_id)
	if research_id == "forging":
		gm.apply_attack_upgrade(b.player_owner, 2)
	elif research_id == "scale_mail":
		gm.apply_armor_upgrade(b.player_owner, 1)
	elif research_id == "wheelbarrow":
		gm.apply_gather_upgrade(b.player_owner, 0.5)
		# Apply to existing villagers
		for unit in _player_units[b.player_owner]:
			if is_instance_valid(unit) and unit is Villager:
				(unit as Villager).gather_rate += 0.5
	elif research_id == "loom":
		gm.apply_villager_hp_upgrade(b.player_owner, 15)
		# Apply to existing villagers
		for unit in _player_units[b.player_owner]:
			if is_instance_valid(unit) and unit is Villager:
				unit.max_hp += 15
				unit.hp += 15

	hud.show_notification("Research complete: %s" % effect_text, Color(0.5, 0.8, 1.0))

	# Refresh selection panel to show [DONE] status
	_on_selection_changed(game_map.selection_mgr.selected)


# =========================================================================
#  HUD + BUILD MENU WIRING
# =========================================================================

func _setup_hud() -> void:
	hud.set_match_population_limit(GameManager.get_player_population_limit(0))
	# Find the build menu inside the HUD (if nested) or create reference.
	_build_menu = hud.get_node_or_null("BuildMenu")
	if _build_menu == null:
		# Build menu might be a separate scene - instantiate it.
		var build_menu_scene := preload("res://scenes/ui/build_menu.tscn")
		_build_menu = build_menu_scene.instantiate()
		hud.add_child(_build_menu)

	hud.build_menu_toggled.connect(_on_build_menu_toggled)
	hud.age_up_requested.connect(_on_age_up_requested)
	hud.idle_villager_pressed.connect(_on_idle_villager_pressed)
	hud.train_unit_requested.connect(_on_train_unit_requested)
	hud.minimap_clicked.connect(_on_minimap_clicked)
	hud.cancel_queue_requested.connect(_on_cancel_queue_requested)
	hud.select_all_military_pressed.connect(_select_all_military)
	hud.find_army_pressed.connect(_find_army)
	hud.unit_move_requested.connect(_arm_move_command)
	hud.unit_attack_move_requested.connect(_arm_attack_move_command)
	hud.unit_patrol_requested.connect(_arm_patrol_command)
	hud.unit_stop_requested.connect(_stop_selected_units)
	hud.unit_stance_requested.connect(_toggle_stance)
	hud.deselect_requested.connect(_deselect_from_hud)
	hud.research_requested.connect(_on_research_requested)
	hud.placement_cancel_requested.connect(_on_cancel_placement)
	hud.placement_confirm_requested.connect(_on_confirm_placement)
	hud.town_center_pressed.connect(_select_town_center)
	hud.camera_zoom_requested.connect(_on_camera_zoom_requested)
	hud.camera_zoom_reset_requested.connect(game_map.reset_zoom)
	game_map.zoom_changed.connect(hud.update_camera_zoom)
	var zoom_state: Dictionary = game_map.get_zoom_state()
	hud.update_camera_zoom(float(zoom_state["zoom"]), float(zoom_state["min"]), float(zoom_state["max"]))
	hud.pause_requested.connect(_on_pause_requested)
	hud.resume_requested.connect(_on_resume_requested)
	hud.quit_to_menu_requested.connect(_on_quit_to_menu_requested)
	hud.guidance_dismissed.connect(_on_guidance_dismissed)
	_build_menu.building_selected.connect(_on_building_selected_for_placement)
	_build_menu.cancel_placement.connect(_on_cancel_placement)
	if _build_menu.has_signal("close_requested"):
		_build_menu.close_requested.connect(_on_build_menu_close_requested)

	# Set up building placement ghost.
	_building_placement = BuildingPlacement.new()
	game_map.add_child(_building_placement)
	_building_placement.placement_confirmed.connect(_on_placement_confirmed)
	_building_placement.placement_cancelled.connect(_on_cancel_placement)
	_building_placement.placement_invalid.connect(_on_placement_invalid)
	_building_placement.preview_changed.connect(_on_placement_preview_changed)
	_sync_hud_modal_state()


func _on_guidance_dismissed() -> void:
	if not _guided_opening_active:
		return
	_guided_opening_active = false
	_guidance_dismissed_in_match = true
	GameManager.guided_opening_enabled = false
	GameManager.save_preferences()
	hud.set_early_game_ui_state(false)
	hud.set_guided_military_shortcuts_visible(false)
	hud.set_pending_military_shortcut(false)
	hud.clear_primary_action()
	hud.show_notification("Guided opener dismissed. All controls are available.", Color(0.68, 0.86, 1.0))
	_refresh_first_session_diagnostics()
	_update_progression_hint()

func _on_build_menu_toggled(is_open: bool) -> void:
	if GameManager.current_state == GameManager.GameState.PAUSED:
		if is_open:
			hud.close_build_menu()
		else:
			_build_menu.close_menu()
			_cancel_placement()
		_sync_hud_modal_state()
		_update_progression_hint()
		return
	if is_open:
		# Reopening Build while a ghost is active is an explicit mode switch:
		# cancel the ghost first so the freshly opened menu is fully interactive.
		if _placement_active:
			_cancel_placement()
		_build_menu.open_menu()
	else:
		_build_menu.close_menu()
		_cancel_placement()
	_sync_hud_modal_state()
	_update_progression_hint()


func _on_build_menu_close_requested() -> void:
	if hud.is_build_menu_open():
		hud.close_build_menu()
	else:
		_build_menu.close_menu()
		_sync_hud_modal_state()
	_update_progression_hint()


func _on_building_selected_for_placement(building_type: int) -> void:
	_placement_active = true
	_placement_type = building_type
	_last_invalid_placement_reason = ""
	_building_placement.start_placement(building_type, 0)
	# The build grid is modal and covers most of a phone viewport.  Move to a
	# world-placement UI state without taking the normal close path, which would
	# immediately cancel the placement we just started.
	_build_menu.close_for_world_placement()
	hud.dismiss_build_menu_for_placement()
	hud.set_placement_mode(true, BuildingData.get_building_name(building_type))
	_on_placement_preview_changed(_building_placement.is_valid_placement, _building_placement.get_invalid_reason())
	_sync_hud_modal_state()
	if _guided_opening_active and _guided_stage == GuidedOpeningStage.BUILD_HOUSE and building_type == BuildingData.BuildingType.HOUSE:
		hud.show_notification("Position your House, then tap Place. Two fingers pan and zoom.", Color(0.95, 0.86, 0.42))
	_refresh_first_session_diagnostics()
	_update_progression_hint()


func _on_cancel_placement() -> void:
	_cancel_placement()


func _on_camera_zoom_requested(direction: int) -> void:
	if direction > 0:
		game_map.zoom_in()
	elif direction < 0:
		game_map.zoom_out()


func _on_confirm_placement() -> void:
	if _placement_active and _building_placement != null:
		_building_placement.confirm_preview()


func _on_placement_preview_changed(valid: bool, reason: String) -> void:
	if hud != null:
		hud.update_placement_preview(valid, reason)


func _cancel_placement() -> void:
	_placement_active = false
	_placement_type = -1
	_last_invalid_placement_reason = ""
	if _building_placement.active:
		_building_placement.cancel_placement()
	if _build_menu:
		_build_menu.set_placement_mode(false)
	hud.set_placement_mode(false)
	_refresh_first_session_diagnostics()
	_update_progression_hint()


func _sync_hud_modal_state() -> void:
	if hud == null:
		return
	if GameManager.current_state == GameManager.GameState.PAUSED:
		hud.set_ui_modal_state(hud.UIModalState.PAUSE_MENU)
	elif hud.is_build_menu_open():
		game_map.cancel_camera_touch_gesture()
		if game_map.selection_mgr != null:
			game_map.selection_mgr.cancel_touch_gesture()
		hud.set_ui_modal_state(hud.UIModalState.BUILD_MENU)
	else:
		hud.set_ui_modal_state(hud.UIModalState.NONE)


func _on_placement_invalid(reason: String) -> void:
	_last_invalid_placement_reason = reason
	_invalid_placement_count += 1
	var message: String = "Cannot place here: %s." % reason
	if _guided_opening_active and _guided_stage == GuidedOpeningStage.BUILD_HOUSE:
		message += " Try open ground near your Town Center, or tap Cancel House."
	elif _placement_active:
		message += " Try open ground, or tap Cancel Build."
	_last_placement_feedback = message
	hud.show_notification(message, Color(1.0, 0.45, 0.35))
	_refresh_first_session_diagnostics()
	_update_progression_hint()


func _on_age_up_requested() -> void:
	var age: int = GameManager.get_player_age(0)
	var cost: Dictionary = GameManager.get_age_up_cost(0, age + 1)
	if cost.is_empty():
		return

	if ResourceManager.try_spend(0, cost):
		GameManager.advance_age(0)
		_update_population_display()
		var new_age: int = GameManager.get_player_age(0)
		var age_name: String = GameManager.get_age_name(new_age)
		hud.show_notification("Advancing to %s!" % age_name, Color(1.0, 0.85, 0.2))
		if new_age >= 2 and not _milestone_first_age_up:
			_milestone_first_age_up = true
			hud.show_notification("Milestone: First Age Up reached.", Color(1.0, 0.9, 0.45))
	else:
		var resources: Dictionary = ResourceManager.get_all_resources(0)
		var need_food: int = maxi(0, cost.get("food", 0) - int(resources.get("food", 0)))
		var need_gold: int = maxi(0, cost.get("gold", 0) - int(resources.get("gold", 0)))
		hud.show_notification("Need +%d food and +%d gold to age up." % [need_food, need_gold], Color(1.0, 0.5, 0.35))
	_update_progression_hint()


# =========================================================================
#  BUILDING PLACEMENT (PLAYER)
# =========================================================================

func _on_placement_confirmed(building_type: int, world_pos: Vector2) -> void:
	var tile_pos: Vector2i = game_map.world_to_tile(world_pos)
	var cost: Dictionary = BuildingData.get_building_cost(building_type)
	# The preview owns the first confirmation check, but fog/occupancy can change
	# before this synchronous gameplay transaction begins. Revalidate against the
	# authoritative map immediately before spending or spawning.
	if not _building_placement.revalidate_confirmation(building_type, world_pos, 0):
		var invalid_reason: String = _building_placement.get_invalid_reason()
		_cancel_placement()
		_on_placement_invalid(invalid_reason)
		return
	if not ResourceManager.try_spend(0, cost):
		var missing: Dictionary = ResourceManager.get_missing_resources(0, cost)
		_last_placement_feedback = "Need %s to place %s. Gather resources, then reopen Build." % [_format_missing_resources(missing), BuildingData.get_building_name(building_type)]
		hud.show_notification(_last_placement_feedback, Color(1.0, 0.4, 0.3))
		_refresh_first_session_diagnostics()
		_cancel_placement()
		return

	var building := _spawn_building(building_type, 0, tile_pos)
	building.start_construction()
	_last_placement_feedback = ""
	if building_type == BuildingData.BuildingType.HOUSE:
		_opening_house_complete = true
	_last_invalid_placement_reason = ""
	_refresh_guided_opening_stage()

	if _send_villager_to_build(building):
		hud.show_notification("Placed: %s" % BuildingData.get_building_name(building_type), Color(0.48, 0.86, 0.52))
	else:
		_last_placement_feedback = "Placed %s. Select a free villager, then tap the foundation to build it." % BuildingData.get_building_name(building_type)
		hud.show_notification(_last_placement_feedback, Color(1.0, 0.75, 0.3))
	_cancel_placement()
	_update_progression_hint()


func _send_villager_to_build(building: BuildingBase) -> bool:
	# Opening workers often all walk to resources at once. Prefer idle labor,
	# then gathering labor, then a walking worker rather than leaving a paid
	# foundation unstaffed. Existing construction orders keep their workers.
	var idle_candidates: Array[Villager] = []
	var gathering_candidates: Array[Villager] = []
	var moving_candidates: Array[Villager] = []
	for unit in _player_units[0]:
		if not is_instance_valid(unit) or not (unit is Villager):
			continue
		var villager: Villager = unit as Villager
		if villager.is_auto_recovering():
			continue
		if is_instance_valid(villager.build_target) and villager._is_build_target_valid(villager.build_target):
			continue
		match villager.current_state:
			UnitBase.State.IDLE:
				idle_candidates.append(villager)
			UnitBase.State.GATHERING:
				gathering_candidates.append(villager)
			UnitBase.State.MOVING:
				moving_candidates.append(villager)
	for candidates: Array[Villager] in [idle_candidates, gathering_candidates, moving_candidates]:
		candidates.sort_custom(func(a: Villager, b: Villager) -> bool:
			return a.global_position.distance_squared_to(building.global_position) < b.global_position.distance_squared_to(building.global_position)
		)
		for candidate: Villager in candidates:
			# The same construction-distance route check used by AI transactions
			# applies after the human foundation becomes an obstacle too.
			if not _can_ai_builder_reach(candidate, building.global_position, building.footprint):
				continue
			candidate.command_build(building)
			if candidate.current_state == UnitBase.State.BUILDING and candidate.build_target == building:
				return true
	return false


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	return canvas_transform.affine_inverse() * screen_pos


# =========================================================================
#  AI WIRING
# =========================================================================

func _setup_ai(map_gen: MapGenerator) -> void:
	ai_controller.difficulty = _resolve_ai_difficulty()
	GameManager.selected_difficulty = ai_controller.difficulty
	ai_controller.map_generator = map_gen
	ai_controller.pathfinding = game_map.pathfinding
	ai_controller.game_map = game_map

	# Connect AI signals.
	ai_controller.ai_wants_to_build.connect(_on_ai_wants_to_build)
	ai_controller.ai_wants_to_train.connect(_on_ai_wants_to_train)
	ai_controller.ai_wants_to_age_up.connect(_on_ai_wants_to_age_up)
	ai_controller.ai_attack_launched.connect(_on_ai_attack_launched)

	# Start AI with its base position.
	var ai_spawn: Vector2i = map_gen.spawn_positions[1]
	var ai_world_pos: Vector2 = game_map.tile_to_world(ai_spawn)
	ai_controller.start_ai(ai_spawn, ai_world_pos)


func _on_ai_wants_to_build(building_type: int, tile_pos: Vector2i, is_rebuild: bool) -> void:
	var cost: Dictionary = BuildingData.get_building_cost(building_type)
	# Revalidate the AI's proposal at the transaction boundary. Bounds and the
	# complete current-vision footprint are checked before walkability, keeping
	# stale or synthetic signals from probing hidden terrain or spending.
	if not _is_ai_build_site_currently_valid(building_type, tile_pos):
		_restore_ai_rebuild_request(building_type, is_rebuild)
		return
	var build_position: Vector2 = game_map.tile_to_world(tile_pos)
	var footprint: Vector2i = BuildingData.get_building_stats(building_type).get("footprint", Vector2i.ONE)
	# Preflight before spending or spawning. This is repeated after the
	# foundation becomes a pathfinding obstacle so an optimistic route through
	# the future footprint cannot silently consume resources.
	if _find_available_ai_builder(build_position, {}, footprint) == null:
		_restore_ai_rebuild_request(building_type, is_rebuild)
		return
	if not ResourceManager.try_spend(ai_controller.player_id, cost):
		_restore_ai_rebuild_request(building_type, is_rebuild)
		return
	var building: BuildingBase = _spawn_building(building_type, ai_controller.player_id, tile_pos)
	if building == null:
		ResourceManager.refund(ai_controller.player_id, cost)
		_restore_ai_rebuild_request(building_type, is_rebuild)
		return
	building.start_construction()

	var builder: Villager = _find_available_ai_builder(building.global_position, {}, building.footprint)
	if builder == null:
		_cancel_ai_foundation(building, tile_pos, cost, building_type, is_rebuild)
		return
	builder.command_build(building)
	if not _is_ai_builder_working_on(builder, building):
		_cancel_ai_foundation(building, tile_pos, cost, building_type, is_rebuild)
		return

	_ai_construction_jobs[building.get_instance_id()] = {
		"building_ref": weakref(building),
		"builder_ref": weakref(builder),
		"tile_pos": tile_pos,
		"cost": cost.duplicate(),
		"building_type": building_type,
		"is_rebuild": is_rebuild,
		"failed_builder_ids": {},
		"failed_recovery_ticks": 0,
		"reassignments": 0,
	}


func _is_ai_build_site_currently_valid(building_type: int, tile_pos: Vector2i) -> bool:
	if game_map == null or not game_map.has_method("is_tile_visible_to_player"):
		return false
	var stats: Dictionary = BuildingData.get_building_stats(building_type)
	if stats.is_empty():
		return false
	var footprint: Vector2i = stats.get("footprint", Vector2i(2, 2))
	for dy in range(footprint.y):
		for dx in range(footprint.x):
			var check_tile := tile_pos + Vector2i(dx, dy)
			if (
				check_tile.x < 0
				or check_tile.x >= MapData.MAP_WIDTH
				or check_tile.y < 0
				or check_tile.y >= MapData.MAP_HEIGHT
			):
				return false
			if not bool(game_map.call("is_tile_visible_to_player", check_tile, ai_controller.player_id)):
				return false
	if not game_map.has_method("is_tile_buildable"):
		return false
	for dy in range(footprint.y):
		for dx in range(footprint.x):
			if not bool(game_map.call("is_tile_buildable", tile_pos + Vector2i(dx, dy))):
				return false
	return true


func _find_available_ai_builder(build_position: Vector2, excluded_ids: Dictionary = {}, footprint: Vector2i = Vector2i.ONE) -> Villager:
	var idle_candidates: Array[Villager] = []
	var gathering_candidates: Array[Villager] = []
	for unit in _player_units[ai_controller.player_id]:
		if not is_instance_valid(unit) or not (unit is Villager):
			continue
		var villager := unit as Villager
		if villager.current_state == UnitBase.State.DEAD:
			continue
		if excluded_ids.has(villager.get_instance_id()) or _is_ai_builder_reserved(villager):
			continue
		if villager.current_state == UnitBase.State.IDLE:
			idle_candidates.append(villager)
		elif villager.current_state == UnitBase.State.GATHERING:
			gathering_candidates.append(villager)

	for candidates: Array[Villager] in [idle_candidates, gathering_candidates]:
		candidates.sort_custom(func(a: Villager, b: Villager) -> bool:
			return a.global_position.distance_squared_to(build_position) < b.global_position.distance_squared_to(build_position)
		)
		var checked: int = 0
		for candidate: Villager in candidates:
			if checked >= AI_CONSTRUCTION_MAX_ROUTE_CANDIDATES:
				break
			checked += 1
			if _can_ai_builder_reach(candidate, build_position, footprint):
				return candidate
	return null


func _can_ai_builder_reach(builder: Villager, build_position: Vector2, footprint: Vector2i = Vector2i.ONE) -> bool:
	if not is_instance_valid(builder) or game_map == null:
		return false
	if game_map.has_method("get_building_work_world_path"):
		if float(game_map.call("get_building_work_distance", builder.global_position, build_position, footprint)) <= AI_CONSTRUCTION_APPROACH_RADIUS:
			return true
		var work_route: PackedVector2Array = game_map.call(
			"get_building_work_world_path", builder.global_position, build_position, footprint, AI_CONSTRUCTION_APPROACH_RADIUS
		)
		return not work_route.is_empty()
	if builder.global_position.distance_to(build_position) <= AI_CONSTRUCTION_APPROACH_RADIUS:
		return true
	if not game_map.has_method("get_navigation_world_path"):
		return false
	var route: PackedVector2Array = game_map.call(
		"get_navigation_world_path",
		builder.global_position,
		build_position,
		AI_CONSTRUCTION_APPROACH_RADIUS
	)
	if route.is_empty():
		return false
	# GameMap may expose a nearby fallback endpoint outside the interaction
	# radius. Such a path is useful for movement, but cannot start construction.
	return route[route.size() - 1].distance_to(build_position) <= AI_CONSTRUCTION_APPROACH_RADIUS + 0.5


func _is_ai_builder_reserved(builder: Villager) -> bool:
	for job_value in _ai_construction_jobs.values():
		var job: Dictionary = job_value
		var builder_ref: WeakRef = job.get("builder_ref")
		if builder_ref != null and builder_ref.get_ref() == builder:
			return true
	return false


func _is_ai_builder_working_on(builder: Villager, building: BuildingBase) -> bool:
	return (
		is_instance_valid(builder)
		and is_instance_valid(building)
		and builder.has_active_build_order()
		and builder.build_target == building
	)


func _restore_ai_rebuild_request(building_type: int, is_rebuild: bool) -> void:
	if is_rebuild and is_instance_valid(ai_controller):
		ai_controller.restore_rebuild_request(building_type)


func _cancel_ai_foundation(
	building: BuildingBase,
	tile_pos: Vector2i,
	cost: Dictionary,
	building_type: int,
	is_rebuild: bool
) -> void:
	if is_instance_valid(building):
		_ai_construction_jobs.erase(building.get_instance_id())
		for unit in _player_units[ai_controller.player_id]:
			if not is_instance_valid(unit) or not (unit is Villager):
				continue
			var builder := unit as Villager
			if builder.build_target != building:
				continue
			builder.build_target = null
			if builder.current_state == UnitBase.State.BUILDING:
				builder.command_stop()
		_player_buildings[ai_controller.player_id].erase(building)
		if building.provides_food:
			game_map.unregister_harvestable(building)
		game_map.remove_building_obstacle(tile_pos, building.footprint)
		ai_controller.unregister_building(building)
		building.queue_free()
	ResourceManager.refund(ai_controller.player_id, cost)
	_restore_ai_rebuild_request(building_type, is_rebuild)


func _process_ai_construction_recovery(delta: float) -> void:
	_ai_construction_recovery_elapsed += delta
	if _ai_construction_recovery_elapsed < AI_CONSTRUCTION_RECOVERY_INTERVAL:
		return
	_ai_construction_recovery_elapsed = 0.0
	for job_key in _ai_construction_jobs.keys():
		var job_id: int = int(job_key)
		if not _ai_construction_jobs.has(job_id):
			continue
		var job: Dictionary = _ai_construction_jobs[job_id]
		var building_ref: WeakRef = job.get("building_ref")
		var building: BuildingBase = building_ref.get_ref() as BuildingBase if building_ref != null else null
		if building == null:
			_ai_construction_jobs.erase(job_id)
			ResourceManager.refund(ai_controller.player_id, job.get("cost", {}))
			_restore_ai_rebuild_request(int(job.get("building_type", -1)), bool(job.get("is_rebuild", false)))
			continue
		if building.state == BuildingBase.State.ACTIVE or building.state == BuildingBase.State.DESTROYED:
			_ai_construction_jobs.erase(job_id)
			continue
		if building.state != BuildingBase.State.CONSTRUCTING:
			_cancel_ai_foundation(
				building,
				job.get("tile_pos", Vector2i.ZERO),
				job.get("cost", {}),
				int(job.get("building_type", -1)),
				bool(job.get("is_rebuild", false))
			)
			continue

		var builder_ref: WeakRef = job.get("builder_ref")
		var builder: Villager = builder_ref.get_ref() as Villager if builder_ref != null else null
		if _is_ai_builder_working_on(builder, building):
			job["failed_recovery_ticks"] = 0
			_ai_construction_jobs[job_id] = job
			continue

		var failed_builder_ids: Dictionary = job.get("failed_builder_ids", {})
		if builder != null and is_instance_valid(builder):
			failed_builder_ids[builder.get_instance_id()] = true
		job["failed_builder_ids"] = failed_builder_ids
		if int(job.get("reassignments", 0)) >= AI_CONSTRUCTION_MAX_REASSIGNMENTS:
			_cancel_ai_foundation(
				building,
				job.get("tile_pos", Vector2i.ZERO),
				job.get("cost", {}),
				int(job.get("building_type", -1)),
				bool(job.get("is_rebuild", false))
			)
			continue

		var replacement: Villager = _find_available_ai_builder(building.global_position, failed_builder_ids, building.footprint)
		if replacement != null:
			replacement.command_build(building)
			if _is_ai_builder_working_on(replacement, building):
				job["builder_ref"] = weakref(replacement)
				job["failed_recovery_ticks"] = 0
				job["reassignments"] = int(job.get("reassignments", 0)) + 1
				_ai_construction_jobs[job_id] = job
				continue

		job["failed_recovery_ticks"] = int(job.get("failed_recovery_ticks", 0)) + 1
		if int(job["failed_recovery_ticks"]) >= AI_CONSTRUCTION_MAX_FAILED_RECOVERY_TICKS:
			_cancel_ai_foundation(
				building,
				job.get("tile_pos", Vector2i.ZERO),
				job.get("cost", {}),
				int(job.get("building_type", -1)),
				bool(job.get("is_rebuild", false))
			)
		else:
			_ai_construction_jobs[job_id] = job


func _on_ai_wants_to_train(building: Node, unit_type: int) -> void:
	if not is_instance_valid(building):
		return
	var pq: ProductionQueue = building.get_production_queue()
	if pq:
		pq.enqueue_unit(unit_type)


func _on_ai_wants_to_age_up() -> void:
	var age: int = GameManager.get_player_age(ai_controller.player_id)
	var cost: Dictionary = GameManager.get_age_up_cost(ai_controller.player_id, age + 1)
	if cost.is_empty():
		return
	if ResourceManager.try_spend(ai_controller.player_id, cost):
		GameManager.advance_age(ai_controller.player_id)
		var new_age: int = GameManager.get_player_age(ai_controller.player_id)
		var age_name: String = GameManager.get_age_name(new_age)
		hud.show_notification("Enemy advancing to %s!" % age_name, Color(1.0, 0.4, 0.2))


func _on_ai_attack_launched(_units: Array, _target_pos: Vector2) -> void:
	if OS.has_feature("production"):
		return
	balance_ai_attack_count += 1
	if balance_ai_first_attack_time < 0.0:
		balance_ai_first_attack_time = GameManager.game_time


# =========================================================================
#  FOG OF WAR UPDATE
# =========================================================================

var _minimap_timer: float = 0.0
var _selection_refresh_timer: float = 0.0

func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	_advance_production_queues(delta)
	_process_ai_construction_recovery(delta)
	_update_fog_of_war()
	_update_fog_entity_visibility()
	# Main refreshes fog before the child SelectionManager processes. Prune now
	# so the later HUD refresh cannot read a just-hidden enemy or resource.
	game_map.selection_mgr.call("_prune_stale_selection")
	# Tick under-attack cooldown
	if _under_attack_cooldown > 0.0:
		_under_attack_cooldown -= delta
	# Early game hints
	if _hints_shown < HINTS.size():
		_hint_timer += delta
		while _hints_shown < HINTS.size() and _hint_timer >= HINTS[_hints_shown]["time"]:
			hud.show_notification(HINTS[_hints_shown]["text"], HINTS[_hints_shown]["color"])
			_hints_shown += 1
	# Update minimap, idle count, and score once per second
	_minimap_timer += delta
	if _minimap_timer >= 1.0:
		_minimap_timer = 0.0
		_update_minimap()
		_update_idle_villager_count()
		hud.update_score(_calculate_score(0), _calculate_score(1))
		_update_progression_hint()
		if not OS.has_feature("production"):
			_refresh_first_session_diagnostics()
	# Keep editor-only balance telemetry fresh for MCP polling without making
	# the production Web build scan AI collections every second.
	if not OS.has_feature("production"):
		_balance_snapshot_timer += delta
		if _balance_snapshot_timer >= BALANCE_SNAPSHOT_INTERVAL:
			_balance_snapshot_timer = 0.0
			_update_balance_snapshot()
	# Refresh selection display every 0.5s to keep gather progress / queue current
	_selection_refresh_timer += delta
	if _selection_refresh_timer >= 0.5:
		_selection_refresh_timer = 0.0
		if not game_map.selection_mgr.selected.is_empty():
			_on_selection_changed(game_map.selection_mgr.selected)


func _advance_production_queues(delta: float) -> void:
	_production_active_queue_count = 0
	_production_latest_progress = 0.0
	for player_buildings in _player_buildings:
		for building in player_buildings:
			if not is_instance_valid(building):
				continue
			if building.state != BuildingBase.State.ACTIVE:
				continue
			var pq: ProductionQueue = building.get_production_queue() as ProductionQueue
			if pq == null:
				pq = building.get_node_or_null("ProductionQueue") as ProductionQueue
				if pq != null:
					building.set_production_queue(pq)
			if pq == null:
				continue
			pq.retry_auto_queue(delta)
			if not pq.is_training or pq.queue.is_empty():
				continue
			_production_active_queue_count += 1
			pq.current_progress += delta
			_production_tick_counter += 1
			_production_latest_progress = pq.current_progress
			var progress_ratio: float = pq.current_progress / pq.current_train_time if pq.current_train_time > 0.0 else 1.0
			pq.unit_training_progress.emit(pq.queue[0], clampf(progress_ratio, 0.0, 1.0))
			if pq.current_progress >= pq.current_train_time:
				pq._complete_current_unit()


func _update_fog_of_war() -> void:
	var fog: FogManager = game_map.fog_of_war
	if fog == null:
		return

	fog.clear_vision_sources()

	# Register all player 0 units as vision sources.
	for unit in _player_units[0]:
		if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEAD:
			continue
		var tile_pos: Vector2i = game_map.world_to_tile(unit.global_position)
		var vision_tiles: int = int(round(MapData.world_to_range_tiles(unit.vision_radius)))
		var is_scout: bool = unit.unit_type == UnitData.UnitType.SCOUT
		fog.register_vision_source(tile_pos, vision_tiles, is_scout)

	# Also register buildings as vision sources.
	for building in _player_buildings[0]:
		if not is_instance_valid(building) or building.state == BuildingBase.State.DESTROYED:
			continue
		var tile_pos: Vector2i = game_map.world_to_tile(building.global_position)
		var building_stats: Dictionary = BuildingData.get_building_stats(building.building_type)
		var vision_radius: int = int(building_stats.get("vision_radius", 3))
		fog.register_vision_source(tile_pos, vision_radius, false)

	# Visibility consumers below must observe the sources from this same frame.
	fog.refresh_visibility_now()


func _update_fog_entity_visibility() -> void:
	var fog: FogManager = game_map.fog_of_war
	if fog == null:
		return
	game_map.update_resource_visibility_for_player(0)

	# Hide/show enemy units based on fog visibility.
	for unit in _player_units[1]:
		if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEAD:
			continue
		var tile_pos: Vector2i = game_map.world_to_tile(unit.global_position)
		unit.visible = fog.is_tile_visible(tile_pos)

	# Hide/show enemy buildings — visible if ANY tile in footprint is visible.
	for building in _player_buildings[1]:
		if not is_instance_valid(building):
			continue
		var origin_tile: Vector2i = game_map.world_to_tile(building.global_position)
		var any_visible := false
		for dy in range(building.footprint.y):
			for dx in range(building.footprint.x):
				if fog.is_tile_visible(origin_tile + Vector2i(dx, dy)):
					any_visible = true
					break
			if any_visible:
				break
		building.visible = any_visible


func _update_minimap() -> void:
	if game_map.map_generator == null:
		return
	# Calculate camera viewport rect in world space
	var cam_pos: Vector2 = game_map.camera.position
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size / game_map.camera.zoom
	var cam_rect := Rect2(cam_pos - viewport_size * 0.5, viewport_size)
	var minimap_grid: Array = game_map.map_generator.grid
	if game_map.has_method("get_minimap_grid_for_player"):
		minimap_grid = game_map.call("get_minimap_grid_for_player", 0) as Array
	hud.update_minimap(minimap_grid, _player_units[0], _player_units[1], _player_buildings[0], _player_buildings[1], cam_rect, game_map.fog_of_war)


# =========================================================================
#  HUD HELPERS
# =========================================================================

func _on_resource_changed(player_id: int, _resource_type: String, _new_amount: int) -> void:
	if player_id == 0:
		_refresh_hud_resources(player_id)


func _refresh_hud_resources(player_id: int) -> void:
	var resources: Dictionary = ResourceManager.get_all_resources(player_id)
	hud._update_resource_display(resources)
	if _build_menu:
		_build_menu.update_resources(resources)


func _update_population_display() -> void:
	if not GameManager.players.has(0):
		return
	var pop: int = GameManager.get_committed_population(0)
	var cap: int = GameManager.players[0].get("population_cap", 5)
	hud.update_population(pop, cap)


func _count_player_buildings_of_type(player_id: int, building_type: int) -> int:
	var count: int = 0
	for building in _player_buildings[player_id]:
		if not is_instance_valid(building):
			continue
		if building.state == BuildingBase.State.DESTROYED:
			continue
		if building.building_type == building_type:
			count += 1
	return count


func _has_player_building_of_types(player_id: int, building_types: Array[int]) -> bool:
	for building in _player_buildings[player_id]:
		if not is_instance_valid(building):
			continue
		if building.state == BuildingBase.State.DESTROYED:
			continue
		if building.building_type in building_types:
			return true
	return false


func _update_progression_hint() -> void:
	if hud == null:
		return
	if GameManager.current_state != GameManager.GameState.PLAYING:
		_clear_guidance_state(true)
		return
	_refresh_guided_opening_stage()
	hud.set_minimap_hint("Map · tap to view")

	var military: int = 0
	var has_tc_selected: bool = false
	var has_villager_selected: bool = false
	var has_selected_military: bool = false
	var selected: Array = game_map.selection_mgr.selected
	if selected.size() == 1 and selected[0] is BuildingBase:
		var selected_building: BuildingBase = selected[0] as BuildingBase
		has_tc_selected = selected_building.player_owner == 0 and selected_building.building_type == BuildingData.BuildingType.TOWN_CENTER
	for node in selected:
		if not is_instance_valid(node):
			continue
		if node is Villager and node.player_owner == 0:
			has_villager_selected = true
		elif node is UnitBase and node.player_owner == 0 and node.unit_type != UnitData.UnitType.VILLAGER:
			has_selected_military = true
	for unit in _player_units[0]:
		if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEAD:
			continue
		if not unit is Villager:
			military += 1

	if _guided_opening_active:
		match _guided_stage:
			GuidedOpeningStage.GATHER_FOOD:
				if _build_menu and _build_menu.has_method("set_recommended_building"):
					_build_menu.call("set_recommended_building", -1)
				if has_villager_selected:
					_apply_primary_guidance(
						"1 / 4 · Tap a berry bush to gather food.",
						"",
						-1
					)
				else:
					_apply_primary_guidance(
						"1 / 4 · Tap a villager, then a berry bush.",
						"idle_button",
						-1
					)
				return
			GuidedOpeningStage.BUILD_HOUSE:
				if _build_menu and _build_menu.has_method("set_recommended_building"):
					_build_menu.call("set_recommended_building", BuildingData.BuildingType.HOUSE)
				if _placement_active and _placement_type == BuildingData.BuildingType.HOUSE and _building_placement != null and bool(_building_placement.get("is_valid_placement")):
					_last_invalid_placement_reason = ""
				if _placement_active and _placement_type == BuildingData.BuildingType.HOUSE:
					if _last_invalid_placement_reason != "":
						_apply_primary_guidance(
							"2 / 4 · Move the House onto clear ground.",
							"placement_cancel",
							-1,
							BuildingData.BuildingType.HOUSE,
							true
						)
					else:
						_apply_primary_guidance(
							"2 / 4 · Position your House, then Place.",
							"",
							-1,
							BuildingData.BuildingType.HOUSE
						)
				elif hud.is_build_menu_open():
					_apply_primary_guidance("2 / 4 · Choose the House in Economy.", "", -1, BuildingData.BuildingType.HOUSE)
				else:
					_apply_primary_guidance("2 / 4 · Build a House for room to grow.", "build_button", -1, BuildingData.BuildingType.HOUSE)
				return
			GuidedOpeningStage.TRAIN_SCOUT:
				if _build_menu and _build_menu.has_method("set_recommended_building"):
					_build_menu.call("set_recommended_building", -1)
				if has_tc_selected:
					_apply_primary_guidance(
						"3 / 4 · Recruit a Scout to explore.",
						"train_unit",
						UnitData.UnitType.SCOUT
					)
				else:
					_apply_primary_guidance(
						"3 / 4 · Tap Home, then recruit a Scout.",
						"",
						UnitData.UnitType.SCOUT
					)
				return
			GuidedOpeningStage.MOVE_MILITARY:
				if _build_menu and _build_menu.has_method("set_recommended_building"):
					_build_menu.call("set_recommended_building", -1)
				if military <= 0:
					_apply_primary_guidance("4 / 4 · Your Scout is training…", "military_button", -1)
				elif has_selected_military:
					_apply_primary_guidance("4 / 4 · Tap open ground to explore.", "", -1)
				else:
					_apply_primary_guidance("4 / 4 · Tap Army, then open ground.", "military_button", -1)
				return
			GuidedOpeningStage.FREE_PLAY:
				pass

	_clear_guidance_state()
	if _build_menu and _build_menu.has_method("set_recommended_building"):
		_build_menu.call("set_recommended_building", -1)

	# Opening help ends with the optional tutorial. Persistent economy/age
	# reminders used to cover the battle and repeat after every casualty.
	# Training and construction already report actionable shortages locally.


# =========================================================================
#  GAME OVER
# =========================================================================

func _conclude_match(winner_id: int, reason: String) -> void:
	if _game_over_shown or not GameManager.players.has(winner_id):
		return
	var loser_id: int = 1 if winner_id == 0 else 0
	if not GameManager.players.has(loser_id):
		return
	_victory_reason = reason
	if not bool(GameManager.players[loser_id].get("is_defeated", false)):
		GameManager.defeat_player(loser_id)
	_show_game_over()

func _show_game_over() -> void:
	if _game_over_shown:
		return
	_game_over_shown = true
	_clear_guidance_state(true)
	var winner_id: int = -1
	for pid in GameManager.players:
		if not GameManager.players[pid]["is_defeated"]:
			winner_id = pid
			break

	var is_victory: bool = winner_id == 0
	var game_over_scene := preload("res://scenes/ui/game_over_screen.tscn")
	var game_over: CanvasLayer = game_over_scene.instantiate()
	add_child(game_over)

	var stats: Dictionary = {
		"victory_reason": _victory_reason,
		"game_time": GameManager.get_formatted_time(),
		"units_killed": _stats[0]["units_killed"],
		"units_lost": _stats[0]["units_lost"],
		"units_trained": _stats[0]["units_trained"],
		"army_trained": _stats[0]["army_trained"],
		"buildings_built": _stats[0]["buildings_built"],
		"buildings_lost": _stats[0]["buildings_lost"],
		"resources_gathered": _stats[0]["resources_gathered"],
		"score": _calculate_score(0),
		"ai_score": _calculate_score(1),
		"ai_units_killed": _stats[1]["units_killed"],
		"ai_units_lost": _stats[1]["units_lost"],
		"ai_units_trained": _stats[1]["units_trained"],
		"ai_army_trained": _stats[1]["army_trained"],
		"ai_buildings_built": _stats[1]["buildings_built"],
		"ai_buildings_lost": _stats[1]["buildings_lost"],
		"ai_resources_gathered": _stats[1]["resources_gathered"],
		"player_age": GameManager.get_player_age(0),
		"ai_age": GameManager.get_player_age(1),
		"player_feudal_seconds": float(_age_reached_at[0].get(2, -1.0)),
		"ai_feudal_seconds": float(_age_reached_at[1].get(2, -1.0)),
		"player_castle_seconds": float(_age_reached_at[0].get(3, -1.0)),
		"ai_castle_seconds": float(_age_reached_at[1].get(3, -1.0)),
		"sacred_control_seconds": int(round(_sacred_control_seconds[0])),
		"ai_sacred_control_seconds": int(round(_sacred_control_seconds[1])),
	}
	match_summary_diagnostics = stats.duplicate(true)
	match_summary_diagnostics["winner_id"] = winner_id
	match_summary_diagnostics["is_victory"] = is_victory
	if is_victory:
		game_over.show_victory(stats)
	else:
		game_over.show_defeat(stats)

	# Connect restart and main menu.
	if game_over.has_signal("restart_requested"):
		game_over.restart_requested.connect(_on_restart)
	if game_over.has_signal("main_menu_requested"):
		game_over.main_menu_requested.connect(_on_main_menu)


func _format_duration_seconds(duration: float) -> String:
	var total_seconds: int = maxi(0, int(round(duration)))
	@warning_ignore("integer_division")
	var minutes: int = total_seconds / 60
	var seconds: int = total_seconds % 60
	return "%d:%02d" % [minutes, seconds]


func _calculate_score(player_id: int = 0) -> int:
	var score: int = 0
	# Military score: 10 per living military unit
	for unit in _player_units[player_id]:
		if is_instance_valid(unit) and unit.current_state != UnitBase.State.DEAD:
			if not (unit is Villager):
				score += 10
	score += _stats[player_id]["units_killed"] * 20
	@warning_ignore("integer_division")
	score += _stats[player_id]["resources_gathered"] / 10
	# Economy: 5 per living villager
	for unit in _player_units[player_id]:
		if is_instance_valid(unit) and unit is Villager and unit.current_state != UnitBase.State.DEAD:
			score += 5
	# Buildings: 15 per standing building
	for b in _player_buildings[player_id]:
		if is_instance_valid(b) and b.state == BuildingBase.State.ACTIVE:
			score += 15
	# Technology: 25 per age beyond Dark Age, 20 per research
	var age: int = GameManager.get_player_age(player_id)
	score += (age - 1) * 25
	var researched: Array = GameManager.researched_upgrades.get(player_id, [])
	score += researched.size() * 20
	return score


func _on_restart() -> void:
	Engine.time_scale = 1.0
	get_tree().call_deferred("reload_current_scene")


func _on_main_menu() -> void:
	Engine.time_scale = 1.0
	GameManager.set_state(GameManager.GameState.MENU)
	get_tree().call_deferred("change_scene_to_file", "res://scenes/ui/main_menu.tscn")
