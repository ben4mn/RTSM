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

# --- Debug panel ---
var _debug_panel: DebugPanel = null

# --- Idle villager cycling ---
var _idle_villager_index: int = 0

# --- Under-attack notification cooldown ---
var _under_attack_cooldown: float = 0.0
const UNDER_ATTACK_COOLDOWN_TIME: float = 10.0

# --- Game stats ---
var _stats: Dictionary = {
	"units_trained": 0,
	"units_killed": 0,
	"units_lost": 0,
	"buildings_built": 0,
	"resources_gathered": 0,
}

# --- Early game hints ---
var _hint_timer: float = 0.0
var _hints_shown: int = 0
const HINTS: Array = [
	{"time": 3.0, "text": "Destroy the enemy Town Center to win!", "color": Color(1.0, 0.9, 0.5)},
	{"time": 8.0, "text": "Press H to select your Town Center", "color": Color(0.7, 0.8, 1.0)},
	{"time": 25.0, "text": "Train more Villagers for faster gathering [Q]", "color": Color(0.7, 0.8, 1.0)},
	{"time": 45.0, "text": "Build Houses to increase population cap [B]", "color": Color(0.7, 0.8, 1.0)},
	{"time": 75.0, "text": "Build a Barracks to train military units", "color": Color(0.7, 0.8, 1.0)},
	{"time": 120.0, "text": "Train a Scout from your TC to explore the map", "color": Color(0.7, 0.8, 1.0)},
]


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
	selection_mgr.gather_command.connect(_on_gather_command)
	selection_mgr.build_command.connect(_on_build_command)
	selection_mgr.selection_changed.connect(_on_selection_changed)

	# Wire up HUD.
	_setup_hud()

	# Wire up AI.
	_setup_ai(map_gen)

	# Set up debug panel.
	_setup_debug_panel()

	# Center camera on player's starting base.
	var player_spawn: Vector2 = game_map.tile_to_world(map_gen.spawn_positions[0])
	game_map.camera.position = player_spawn

	# Update initial HUD state.
	_refresh_hud_resources(0)
	_update_population_display()


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


func _handle_escape() -> void:
	if _placement_active:
		_cancel_placement()
		return
	if hud.is_build_menu_open():
		hud.close_build_menu()
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


func _select_all_military() -> void:
	game_map.selection_mgr.deselect_all()
	for unit in _player_units[0]:
		if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEAD:
			continue
		if unit is Villager:
			continue
		game_map.selection_mgr._add_to_selection(unit)


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


func _select_town_center() -> void:
	for building in _player_buildings[0]:
		if is_instance_valid(building) and building.building_type == BuildingData.BuildingType.TOWN_CENTER:
			game_map.selection_mgr.deselect_all()
			game_map.selection_mgr._add_to_selection(building)
			game_map.camera.position = building.global_position
			game_map._clamp_camera()
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
	var pq: Node = building.get_production_queue()
	if pq == null:
		return
	if building.trainable_units.size() > 0:
		pq.enqueue_unit(building.trainable_units[0])


# =========================================================================
#  DEBUG PANEL
# =========================================================================

func _setup_debug_panel() -> void:
	_debug_panel = DebugPanel.new()
	_debug_panel.initialize(
		ai_controller._decision_timer,
		game_map.fog_of_war,
		game_map.get_node_or_null("FogLayer")
	)
	_debug_panel.spawn_units_requested.connect(_on_debug_spawn_units)
	hud.get_node("Root").add_child(_debug_panel)
	hud.set_debug_panel(_debug_panel)


func _on_debug_spawn_units(unit_type: int, count: int) -> void:
	var cam_pos: Vector2 = game_map.camera.position
	for i in count:
		var offset := Vector2(randf_range(-50, 50), randf_range(-50, 50))
		_spawn_unit(unit_type, 0, cam_pos + offset)
	_update_population_display()


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


func _auto_explore_idle_scouts() -> void:
	for unit in _player_units[0]:
		if not is_instance_valid(unit) or unit.current_state != UnitBase.State.IDLE:
			continue
		if unit.unit_type != UnitData.UnitType.SCOUT:
			continue
		# Send to a random map position
		var random_tile := Vector2i(randi_range(2, MapData.MAP_WIDTH - 3), randi_range(2, MapData.MAP_HEIGHT - 3))
		var world_pos: Vector2 = game_map.tile_to_world(random_tile)
		unit.command_move(world_pos)


func _update_idle_villager_count() -> void:
	var count: int = 0
	for unit in _player_units[0]:
		if is_instance_valid(unit) and unit is Villager and unit.current_state == UnitBase.State.IDLE:
			count += 1
	hud.update_idle_villager_count(count)


# =========================================================================
#  PLAYER START SETUP
# =========================================================================

func _setup_player_start(player_id: int, spawn_tile: Vector2i) -> void:
	# Place Town Center.
	var tc := _spawn_building(BuildingData.BuildingType.TOWN_CENTER, player_id, spawn_tile)
	tc.complete_instantly()
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
		var resource_node: Node2D = game_map.get_nearest_resource_node(res_type, v.global_position)
		if resource_node and v.has_method("command_gather"):
			v.command_gather(resource_node)


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

	# Under-attack detection for player units.
	if player_id == 0 and unit.has_signal("health_changed"):
		unit.health_changed.connect(_on_player_unit_damaged)

	# Track resource deposits for stats.
	if player_id == 0 and unit.has_signal("resource_deposited"):
		unit.resource_deposited.connect(_on_resource_deposited)

	# Register with AI if it's the AI's unit.
	if player_id == ai_controller.player_id:
		ai_controller.register_unit(unit)

	return unit


func _on_unit_trained(unit_type: int, spawn_pos: Vector2, player_id: int) -> void:
	_spawn_unit(unit_type, player_id, spawn_pos)
	_update_population_display()
	if player_id == 0:
		_stats["units_trained"] += 1
		hud.show_notification("Unit trained: %s" % UnitData.get_unit_name(unit_type), Color(0.4, 0.7, 1.0))


func _on_unit_died(unit: UnitBase, player_id: int) -> void:
	_player_units[player_id].erase(unit)
	var pop_cost: int = UnitData.UNITS.get(unit.unit_type, {}).get("pop_cost", 1)
	GameManager.remove_population(player_id, pop_cost)
	_update_population_display()
	if player_id == 0:
		_stats["units_lost"] += 1
		hud.show_notification("Unit lost!", Color(1.0, 0.3, 0.3))
	else:
		_stats["units_killed"] += 1


func _on_resource_deposited(_resource_type: String, amount: int) -> void:
	_stats["resources_gathered"] += amount


func _on_player_unit_damaged(_unit: UnitBase, _new_hp: float, _max_hp: float) -> void:
	if _under_attack_cooldown <= 0.0:
		_under_attack_cooldown = UNDER_ATTACK_COOLDOWN_TIME
		hud.show_notification("Under attack!", Color(1.0, 0.4, 0.2))


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
	var pq: Node = building.get_production_queue()
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
	if player_id == 0:
		_stats["buildings_built"] += 1
		hud.show_notification("Building complete: %s" % building.building_name, Color(0.3, 0.85, 0.3))


func _on_building_destroyed(building: BuildingBase, player_id: int, tile_pos: Vector2i) -> void:
	_player_buildings[player_id].erase(building)
	game_map.remove_building_obstacle(tile_pos, building.footprint)
	if player_id == 0:
		hud.show_notification("Building destroyed!", Color(1.0, 0.3, 0.3))

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
		var action_text: String = UnitBase.State.keys()[u.current_state]
		# Show gather details for villagers
		if u is Villager:
			var v: Villager = u as Villager
			if v.current_state == UnitBase.State.GATHERING or v.carried_amount > 0:
				var res_name: String = v.carried_resource_type.capitalize() if v.carried_resource_type != "" else "?"
				action_text = "Gathering %s (%d/%d)" % [res_name, v.carried_amount, v.carry_capacity]
		# Count selected units of same type
		var count: int = 0
		var total_hp: int = 0
		var total_max_hp: int = 0
		for node in selected_units:
			if node is UnitBase and (node as UnitBase).unit_type == u.unit_type:
				count += 1
				total_hp += int((node as UnitBase).hp)
				total_max_hp += int((node as UnitBase).max_hp)
		# For mixed selections, count all
		if count < selected_units.size():
			count = selected_units.size()
			total_hp = 0
			total_max_hp = 0
			for node in selected_units:
				if node is UnitBase:
					total_hp += int((node as UnitBase).hp)
					total_max_hp += int((node as UnitBase).max_hp)
			action_text = "Mixed (%d units)" % count
		var stats: Dictionary = {}
		if not (u is Villager):
			stats = {"damage": int(u.damage), "armor": int(u.armor), "range": int(u.attack_range / 16.0)}
		hud.show_unit_selection(UnitData.get_unit_name(u.unit_type), total_hp, total_max_hp, action_text, count, stats)
	elif first is BuildingBase:
		var b: BuildingBase = first as BuildingBase
		var queue_info: Array = []
		var pq: Node = b.get_production_queue()
		if pq:
			queue_info = pq.get_queue_info()
		hud.show_building_selection(b.building_name, b.hp, b.max_hp, queue_info, b.trainable_units, b)


func _on_move_command(target_tile: Vector2i) -> void:
	var selected: Array = game_map.selection_mgr.selected
	# Collect moveable units
	var moveable: Array[UnitBase] = []
	for node in selected:
		if node is UnitBase and node.player_owner == 0:
			moveable.append(node as UnitBase)
	if moveable.is_empty():
		return

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
		if tile_path.size() > 1:
			var world_path := PackedVector2Array()
			for tp in tile_path:
				world_path.append(game_map.tile_to_world(tp))
			unit.command_move_path(world_path)
		else:
			unit.command_move(world_pos)

	VFX.move_indicator(get_tree(), game_map.tile_to_world(target_tile))


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
	var selected: Array = game_map.selection_mgr.selected
	for node in selected:
		if node is UnitBase and node.player_owner == 0:
			if target is UnitBase:
				node.command_attack(target as UnitBase)
			elif target is BuildingBase:
				node.command_attack_building(target as BuildingBase)


func _on_gather_command(resource_node: Node2D) -> void:
	var selected: Array = game_map.selection_mgr.selected
	for node in selected:
		if node is UnitBase and node.player_owner == 0 and node.has_method("command_gather"):
			node.command_gather(resource_node)


func _on_build_command(building: Node2D) -> void:
	var selected: Array = game_map.selection_mgr.selected
	for node in selected:
		if node is Villager and node.player_owner == 0:
			node.command_build(building)


func _on_train_unit_requested(building: Node2D, unit_type: int) -> void:
	if not is_instance_valid(building) or not (building is BuildingBase):
		return
	var b: BuildingBase = building as BuildingBase
	if not b.can_train():
		return
	var pq: Node = b.get_production_queue()
	if pq:
		pq.enqueue_unit(unit_type)
		# Refresh selection display to show updated queue
		_on_selection_changed(game_map.selection_mgr.selected)


func _on_minimap_clicked(world_pos: Vector2) -> void:
	game_map.camera.position = world_pos
	game_map._clamp_camera()


func _on_cancel_queue_requested(building: Node2D, index: int) -> void:
	if not is_instance_valid(building) or not (building is BuildingBase):
		return
	var pq: Node = (building as BuildingBase).get_production_queue()
	if pq:
		pq.cancel_unit(index)
		_on_selection_changed(game_map.selection_mgr.selected)


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
	hud.idle_villager_pressed.connect(_on_idle_villager_pressed)
	hud.train_unit_requested.connect(_on_train_unit_requested)
	hud.minimap_clicked.connect(_on_minimap_clicked)
	hud.cancel_queue_requested.connect(_on_cancel_queue_requested)
	hud.select_all_military_pressed.connect(_select_all_military)
	hud.find_army_pressed.connect(_find_army)
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
		var new_age: int = GameManager.get_player_age(0)
		var age_name: String = GameManager.get_age_name(new_age)
		hud.show_notification("Advancing to %s!" % age_name, Color(1.0, 0.85, 0.2))


# =========================================================================
#  BUILDING PLACEMENT (PLAYER)
# =========================================================================

func _on_placement_confirmed(building_type: int, world_pos: Vector2) -> void:
	var tile_pos: Vector2i = game_map.world_to_tile(world_pos)

	var cost: Dictionary = BuildingData.get_building_cost(building_type)
	if not ResourceManager.try_spend(0, cost):
		return

	var building := _spawn_building(building_type, 0, tile_pos)
	building.start_construction()

	# Send nearest idle villager to build it.
	_send_villager_to_build(building)
	_cancel_placement()


func _send_villager_to_build(building: BuildingBase) -> void:
	# Prefer IDLE villagers, fall back to GATHERING ones.
	var best_idle: Villager = null
	var best_idle_dist: float = INF
	var best_gathering: Villager = null
	var best_gathering_dist: float = INF
	for unit in _player_units[0]:
		if not (unit is Villager) or not is_instance_valid(unit):
			continue
		var dist: float = unit.global_position.distance_to(building.global_position)
		if unit.current_state == UnitBase.State.IDLE:
			if dist < best_idle_dist:
				best_idle_dist = dist
				best_idle = unit as Villager
		elif unit.current_state == UnitBase.State.GATHERING:
			if dist < best_gathering_dist:
				best_gathering_dist = dist
				best_gathering = unit as Villager
	var chosen: Villager = best_idle if best_idle else best_gathering
	if chosen:
		chosen.command_build(building)


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	return canvas_transform.affine_inverse() * screen_pos


# =========================================================================
#  AI WIRING
# =========================================================================

func _setup_ai(map_gen: MapGenerator) -> void:
	ai_controller.difficulty = GameManager.selected_difficulty
	ai_controller.map_generator = map_gen
	ai_controller.pathfinding = game_map.pathfinding
	ai_controller.game_map = game_map

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

var _minimap_timer: float = 0.0
var _selection_refresh_timer: float = 0.0

func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return
	_update_fog_of_war()
	_update_fog_entity_visibility()
	# Tick under-attack cooldown
	if _under_attack_cooldown > 0.0:
		_under_attack_cooldown -= delta
	# Early game hints
	if _hints_shown < HINTS.size():
		_hint_timer += delta
		while _hints_shown < HINTS.size() and _hint_timer >= HINTS[_hints_shown]["time"]:
			hud.show_notification(HINTS[_hints_shown]["text"], HINTS[_hints_shown]["color"])
			_hints_shown += 1
	# Update minimap and idle count once per second
	_minimap_timer += delta
	if _minimap_timer >= 1.0:
		_minimap_timer = 0.0
		_update_minimap()
		_update_idle_villager_count()
		_auto_explore_idle_scouts()
	# Refresh selection display every 0.5s to keep gather progress / queue current
	_selection_refresh_timer += delta
	if _selection_refresh_timer >= 0.5:
		_selection_refresh_timer = 0.0
		if not game_map.selection_mgr.selected.is_empty():
			_on_selection_changed(game_map.selection_mgr.selected)


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
		var vision_tiles: int = int(unit.vision_radius / 16.0)  # Convert pixel radius back to tiles
		var is_scout: bool = unit.unit_type == UnitData.UnitType.SCOUT
		fog.register_vision_source(tile_pos, vision_tiles, is_scout)

	# Also register buildings as vision sources.
	for building in _player_buildings[0]:
		if not is_instance_valid(building):
			continue
		var tile_pos: Vector2i = game_map.world_to_tile(building.global_position)
		fog.register_vision_source(tile_pos, 3, false)


func _update_fog_entity_visibility() -> void:
	var fog: FogManager = game_map.fog_of_war
	if fog == null:
		return

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
	hud.update_minimap(game_map.map_generator.grid, _player_units[0], _player_units[1], _player_buildings[0], _player_buildings[1], cam_rect)


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
		"units_killed": _stats["units_killed"],
		"units_lost": _stats["units_lost"],
		"units_trained": _stats["units_trained"],
		"buildings_built": _stats["buildings_built"],
	}
	if is_victory:
		game_over.show_victory(stats)
	else:
		game_over.show_defeat(stats)

	# Connect restart and main menu.
	if game_over.has_signal("restart_requested"):
		game_over.restart_requested.connect(_on_restart)
	if game_over.has_signal("main_menu_requested"):
		game_over.main_menu_requested.connect(_on_main_menu)


func _on_restart() -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func _on_main_menu() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
