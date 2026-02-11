extends Node2D
## Main game scene controller.
## Wires together the map, units, buildings, HUD, build menu, fog of war, and AI.

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
	BuildingData.BuildingType.LUMBER_CAMP: preload("res://scenes/buildings/lumber_camp.tscn"),
	BuildingData.BuildingType.MINING_CAMP: preload("res://scenes/buildings/mining_camp.tscn"),
	BuildingData.BuildingType.SIEGE_WORKSHOP: preload("res://scenes/buildings/siege_workshop.tscn"),
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


func _ready() -> void:
	# Wait for map generation to finish.
	game_map.map_ready.connect(_on_map_ready)


func _on_map_ready(map_gen: MapGenerator) -> void:
	# Initialize game state for 2 players.
	GameManager.initialize_game(2)
	ResourceManager.initialize_player(0)
	ResourceManager.initialize_player(1)

	# Connect resource changes to HUD.
	ResourceManager.resources_changed.connect(_on_resource_changed)

	# Place starting Town Centers and Villagers.
	_setup_player_start(0, map_gen.spawn_positions[0])
	_setup_player_start(1, map_gen.spawn_positions[1])

	# Connect selection manager signals.
	var selection_mgr: Node = game_map.selection_mgr
	selection_mgr.move_command.connect(_on_move_command)
	selection_mgr.attack_command.connect(_on_attack_command)
	selection_mgr.selection_changed.connect(_on_selection_changed)

	# Wire up HUD.
	_setup_hud()

	# Wire up AI.
	_setup_ai(map_gen)

	# Update initial HUD state.
	_refresh_hud_resources(0)
	_update_population_display()


# =========================================================================
#  PLAYER START SETUP
# =========================================================================

func _setup_player_start(player_id: int, spawn_tile: Vector2i) -> void:
	# Place Town Center.
	var tc := _spawn_building(BuildingData.BuildingType.TOWN_CENTER, player_id, spawn_tile)
	tc.complete_instantly()
	GameManager.increase_population_cap(player_id, tc.pop_provided)

	# Connect the TC's production queue.
	var pq := tc.get_production_queue()
	if pq:
		pq.unit_trained.connect(_on_unit_trained.bind(player_id))

	# Place 3 starting villagers nearby.
	var offsets: Array[Vector2i] = [Vector2i(1, 2), Vector2i(-1, 2), Vector2i(0, 3)]
	for offset in offsets:
		var vill_tile := spawn_tile + offset
		var vill_pos := game_map.tile_to_world(vill_tile)
		_spawn_unit(UnitData.UnitType.VILLAGER, player_id, vill_pos)


# =========================================================================
#  UNIT SPAWNING
# =========================================================================

func _spawn_unit(unit_type: int, player_id: int, world_pos: Vector2) -> UnitBase:
	var scene: PackedScene = _unit_scenes.get(unit_type)
	if scene == null:
		push_warning("No scene for unit type %d" % unit_type)
		return null

	var unit: UnitBase = scene.instantiate()
	unit.player_owner = player_id
	unit.unit_type = unit_type
	unit.global_position = world_pos
	unit.set_team_color(TEAM_COLORS[player_id])

	game_map.get_node("UnitsContainer").add_child(unit)
	_player_units[player_id].append(unit)
	GameManager.add_population(player_id, UnitData.UNITS.get(unit_type, {}).get("pop_cost", 1))

	# Track unit death.
	unit.unit_died.connect(_on_unit_died.bind(player_id))

	# Register with AI if it's the AI's unit.
	if player_id == ai_controller.player_id:
		ai_controller.register_unit(unit)

	return unit


func _on_unit_trained(unit_type: int, spawn_pos: Vector2, player_id: int) -> void:
	_spawn_unit(unit_type, player_id, spawn_pos)
	_update_population_display()


func _on_unit_died(unit: UnitBase, player_id: int) -> void:
	_player_units[player_id].erase(unit)
	var pop_cost: int = UnitData.UNITS.get(unit.unit_type, {}).get("pop_cost", 1)
	GameManager.remove_population(player_id, pop_cost)
	_update_population_display()


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

	# Mark pathfinding obstacle.
	game_map.place_building_obstacle(tile_pos, building.footprint)

	# Connect building signals.
	building.construction_complete.connect(_on_building_constructed.bind(player_id))
	building.building_destroyed.connect(_on_building_destroyed.bind(player_id, tile_pos))

	# Connect production queue if it has one.
	var pq := building.get_production_queue()
	if pq:
		pq.unit_trained.connect(_on_unit_trained.bind(player_id))

	# Register with AI.
	if player_id == ai_controller.player_id:
		ai_controller.register_building(building)

	return building


func _on_building_constructed(building: BuildingBase, player_id: int) -> void:
	if building.pop_provided > 0:
		GameManager.increase_population_cap(player_id, building.pop_provided)
		_update_population_display()


func _on_building_destroyed(building: BuildingBase, player_id: int, tile_pos: Vector2i) -> void:
	_player_buildings[player_id].erase(building)
	game_map.remove_building_obstacle(tile_pos, building.footprint)

	if building.pop_provided > 0:
		# Don't reduce cap below current population (units don't instantly die).
		pass

	# Check win condition: Town Center destroyed.
	if building.building_type == BuildingData.BuildingType.TOWN_CENTER:
		var has_tc := false
		for b in _player_buildings[player_id]:
			if is_instance_valid(b) and b.building_type == BuildingData.BuildingType.TOWN_CENTER:
				has_tc = true
				break
		if not has_tc:
			GameManager.defeat_player(player_id)
			_show_game_over()


# =========================================================================
#  SELECTION + COMMANDS
# =========================================================================

func _on_selection_changed(selected_units: Array[Node2D]) -> void:
	if selected_units.is_empty():
		hud.clear_selection()
		return

	var first: Node2D = selected_units[0]
	if first is UnitBase:
		var u: UnitBase = first as UnitBase
		var action_text := UnitBase.State.keys()[u.current_state]
		hud.show_unit_selection(UnitData.get_unit_name(u.unit_type), int(u.hp), int(u.max_hp), action_text)
	elif first is BuildingBase:
		var b: BuildingBase = first as BuildingBase
		var queue_info: Array = []
		var pq := b.get_production_queue()
		if pq:
			queue_info = pq.get_queue_info()
		hud.show_building_selection(b.building_name, b.hp, b.max_hp, queue_info)


func _on_move_command(target_tile: Vector2i) -> void:
	var selected: Array = game_map.selection_mgr.selected
	for node in selected:
		if node is UnitBase and node.player_owner == 0:
			var world_pos := game_map.tile_to_world(target_tile)
			# Get pathfinding path.
			var unit_tile := game_map.world_to_tile(node.global_position)
			var tile_path: Array[Vector2i] = game_map.get_movement_path(unit_tile, target_tile)
			if tile_path.size() > 1:
				var world_path := PackedVector2Array()
				for tp in tile_path:
					world_path.append(game_map.tile_to_world(tp))
				node.command_move_path(world_path)
			else:
				node.command_move(world_pos)


func _on_attack_command(target: Node2D) -> void:
	var selected: Array = game_map.selection_mgr.selected
	for node in selected:
		if node is UnitBase and node.player_owner == 0:
			if target is UnitBase:
				node.command_attack(target as UnitBase)
			elif target is BuildingBase:
				# Move to attack building.
				node.command_move(target.global_position)


# =========================================================================
#  HUD + BUILD MENU WIRING
# =========================================================================

func _setup_hud() -> void:
	# Find the build menu inside the HUD (if nested) or create reference.
	_build_menu = hud.get_node_or_null("BuildMenu")
	if _build_menu == null:
		# Build menu might be a separate scene - instantiate it.
		var build_menu_scene := preload("res://scenes/ui/build_menu.tscn")
		_build_menu = build_menu_scene.instantiate()
		hud.add_child(_build_menu)

	hud.build_menu_toggled.connect(_on_build_menu_toggled)
	hud.age_up_requested.connect(_on_age_up_requested)
	_build_menu.building_selected.connect(_on_building_selected_for_placement)
	_build_menu.cancel_placement.connect(_on_cancel_placement)

	# Set up building placement ghost.
	_building_placement = BuildingPlacement.new()
	game_map.add_child(_building_placement)
	_building_placement.placement_confirmed.connect(_on_placement_confirmed)
	_building_placement.placement_cancelled.connect(_on_cancel_placement)


func _on_build_menu_toggled(is_open: bool) -> void:
	if is_open:
		_build_menu.open_menu()
	else:
		_build_menu.close_menu()
		_cancel_placement()


func _on_building_selected_for_placement(building_type: int) -> void:
	_placement_active = true
	_placement_type = building_type
	_building_placement.start_placement(building_type, 0)


func _on_cancel_placement() -> void:
	_cancel_placement()


func _cancel_placement() -> void:
	_placement_active = false
	_placement_type = -1
	if _building_placement.active:
		_building_placement.cancel_placement()
	if _build_menu:
		_build_menu.set_placement_mode(false)


func _on_age_up_requested() -> void:
	var age: int = GameManager.get_player_age(0)
	var cost: Dictionary
	if age == 1:
		cost = {"food": 400, "gold": 200}
	elif age == 2:
		cost = {"food": 1200, "gold": 600}
	else:
		return

	if ResourceManager.try_spend(0, cost):
		GameManager.advance_age(0)
		_update_population_display()


# =========================================================================
#  BUILDING PLACEMENT (PLAYER)
# =========================================================================

func _on_placement_confirmed(building_type: int, world_pos: Vector2) -> void:
	var tile_pos := game_map.world_to_tile(world_pos)

	var cost: Dictionary = BuildingData.get_building_cost(building_type)
	if not ResourceManager.try_spend(0, cost):
		return

	var building := _spawn_building(building_type, 0, tile_pos)
	building.start_construction()

	# Send nearest idle villager to build it.
	_send_villager_to_build(building)
	_cancel_placement()


func _send_villager_to_build(building: BuildingBase) -> void:
	var closest_villager: Villager = null
	var closest_dist: float = INF
	for unit in _player_units[0]:
		if unit is Villager and is_instance_valid(unit) and unit.current_state == UnitBase.State.IDLE:
			var dist: float = unit.global_position.distance_to(building.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest_villager = unit as Villager
	if closest_villager:
		closest_villager.command_build(building)


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var canvas_transform := get_viewport().get_canvas_transform()
	return canvas_transform.affine_inverse() * screen_pos


# =========================================================================
#  AI WIRING
# =========================================================================

func _setup_ai(map_gen: MapGenerator) -> void:
	ai_controller.map_generator = map_gen
	ai_controller.pathfinding = game_map.pathfinding

	# Connect AI signals.
	ai_controller.ai_wants_to_build.connect(_on_ai_wants_to_build)
	ai_controller.ai_wants_to_train.connect(_on_ai_wants_to_train)
	ai_controller.ai_wants_to_age_up.connect(_on_ai_wants_to_age_up)

	# Start AI with its base position.
	var ai_spawn: Vector2i = map_gen.spawn_positions[1]
	var ai_world_pos: Vector2 = game_map.tile_to_world(ai_spawn)
	ai_controller.start_ai(ai_spawn, ai_world_pos)


func _on_ai_wants_to_build(building_type: int, tile_pos: Vector2i) -> void:
	var cost: Dictionary = BuildingData.get_building_cost(building_type)
	if not ResourceManager.try_spend(ai_controller.player_id, cost):
		return
	var building := _spawn_building(building_type, ai_controller.player_id, tile_pos)
	# AI buildings construct faster (simulated — instant for prototype).
	building.start_construction()
	# Simulate villager building by adding progress over time.
	_auto_construct(building)


func _auto_construct(building: BuildingBase) -> void:
	# For AI buildings, auto-advance construction over build_time using a tween.
	var tween := create_tween()
	tween.tween_method(building.add_build_progress, 0.0, building.build_time, building.build_time)


func _on_ai_wants_to_train(building: Node, unit_type: int) -> void:
	if not is_instance_valid(building):
		return
	var pq: ProductionQueue = building.get_production_queue()
	if pq:
		pq.enqueue_unit(unit_type)


func _on_ai_wants_to_age_up() -> void:
	var age: int = GameManager.get_player_age(ai_controller.player_id)
	var cost: Dictionary
	if age == 1:
		cost = {"food": 400, "gold": 200}
	elif age == 2:
		cost = {"food": 1200, "gold": 600}
	else:
		return
	if ResourceManager.try_spend(ai_controller.player_id, cost):
		GameManager.advance_age(ai_controller.player_id)


# =========================================================================
#  FOG OF WAR UPDATE
# =========================================================================

func _process(_delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	_update_fog_of_war()
	_update_population_display()


func _update_fog_of_war() -> void:
	var fog: FogManager = game_map.fog_of_war
	if fog == null:
		return

	fog.clear_vision_sources()

	# Register all player 0 units as vision sources.
	for unit in _player_units[0]:
		if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEAD:
			continue
		var tile_pos := game_map.world_to_tile(unit.global_position)
		var vision_tiles: int = int(unit.vision_radius / 16.0)  # Convert pixel radius back to tiles
		var is_scout: bool = unit.unit_type == UnitData.UnitType.SCOUT
		fog.register_vision_source(tile_pos, vision_tiles, is_scout)

	# Also register buildings as vision sources.
	for building in _player_buildings[0]:
		if not is_instance_valid(building):
			continue
		var tile_pos := game_map.world_to_tile(building.global_position)
		fog.register_vision_source(tile_pos, 3, false)


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
	var pop: int = GameManager.players[0].get("population", 0)
	var cap: int = GameManager.players[0].get("population_cap", 5)
	hud.update_population(pop, cap)


# =========================================================================
#  GAME OVER
# =========================================================================

func _show_game_over() -> void:
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
		"game_time": GameManager.get_formatted_time(),
		"units_killed": 0,
		"units_trained": 0,
		"resources_gathered": 0,
		"buildings_built": _player_buildings[0].size() if is_victory else _player_buildings[1].size(),
	}
	if is_victory:
		game_over.show_victory(stats)
	else:
		game_over.show_defeat(stats)

	# Connect restart.
	if game_over.has_signal("restart_requested"):
		game_over.restart_requested.connect(_on_restart)


func _on_restart() -> void:
	get_tree().reload_current_scene()
