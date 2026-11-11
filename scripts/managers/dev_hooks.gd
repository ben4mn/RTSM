extends Node
## Developer playtest harness (see docs/dev_playtest_harness.md).
##
## Browser: inert unless the page is served from localhost/127.0.0.1 AND the URL
## carries ?dev=1. Only then is `window.PocketDev` installed and autostart read.
## Headless: tools/probe_joy_match.gd instantiates this node directly to reuse
## the same snapshot and event log. It observes a match through signals and the
## match's public collections; it never changes simulation unless a tester
## explicitly calls a command.

const MATCH_SCENE_PATH: String = "res://scenes/main/main.tscn"
const WEB_SHELL_BRIDGE := preload("res://scripts/ui/web_shell_bridge.gd")
const CIVILIZATION_IDS: Dictionary = {"french": 0, "english": 1, "mongols": 2}
const DIFFICULTY_IDS: Dictionary = {"easy": 0, "medium": 1, "hard": 2}
const MAP_IDS: Dictionary = {"open_plains": 0, "river_crossings": 1, "woodland_flanks": 2}
const RESOURCES: Array[String] = ["food", "wood", "gold"]
const UNDER_ATTACK_COOLDOWN: float = 10.0
const COMMANDS: Array[String] = ["camera_to", "set_speed", "pause", "reveal_map", "give", "spawn", "age", "build", "screenshot_safe_ui"]

static var _dev_checked: bool = false
static var _dev_enabled: bool = false
static var _params: Dictionary = {}
static var _autostart_done: bool = false
static var _js_callback: JavaScriptObject = null
static var _active: Node = null

var match_scene: Node = null
var events: Array[Dictionary] = []
var totals: Array[Dictionary] = []
var first_combat_time: float = -1.0
var first_building_lost_time: float = -1.0
var winner: int = -1
var _seen_units: Dictionary = {}
var _seen_buildings: Dictionary = {}
var _last_attacker: Dictionary = {}
var _dev_spawned: Dictionary = {}
var _under_attack_at: Array[float] = [-1000.0, -1000.0]
var _reveal_map: bool = false


# ---------------------------------------------------------------------------
#  Session gating + entry points called by main_menu.gd / main.gd
# ---------------------------------------------------------------------------

static func is_dev_session() -> bool:
	if not _dev_checked:
		_dev_checked = true
		if OS.has_feature("web"):
			var encoded: Variant = JavaScriptBridge.eval(
				"(function(){try{var h=location.hostname;if(h!=='localhost'&&h!=='127.0.0.1')return '';"
				+ "var p=Object.fromEntries(new URLSearchParams(location.search));return p.dev==='1'?JSON.stringify(p):'';}catch(e){return '';}})()", true
			)
			var parsed: Variant = JSON.parse_string(encoded) if encoded is String and encoded != "" else null
			if parsed is Dictionary:
				_params = parsed
				_dev_enabled = true
	return _dev_enabled


static func menu_ready(menu: Node) -> void:
	if not is_dev_session():
		return
	_install_js()
	if _autostart_done or str(_params.get("autostart", "")) != "1":
		return
	_autostart_done = true
	if not WEB_SHELL_BRIDGE.begin_match():
		return
	var seed_text: String = str(_params.get("seed", ""))
	GameManager.selected_civilization = int(CIVILIZATION_IDS.get(str(_params.get("civ", "")).to_lower(), GameManager.selected_civilization))
	GameManager.selected_difficulty = int(DIFFICULTY_IDS.get(str(_params.get("difficulty", "")).to_lower(), GameManager.selected_difficulty))
	GameManager.selected_map_archetype = int(MAP_IDS.get(str(_params.get("map", "")).to_lower(), GameManager.selected_map_archetype))
	GameManager.selected_map_seed = maxi(-1, int(seed_text)) if seed_text.is_valid_int() else -1
	if str(_params.get("pop", "")).is_valid_int():
		GameManager.selected_population_limit = SkirmishData.normalize_population_limit(int(_params["pop"]))
	if str(_params.get("skip_tutorial", "")) == "1":
		GameManager.guided_opening_enabled = false
	if CIVILIZATION_IDS.has(str(_params.get("opp", "")).to_lower()):
		GameManager.selected_opponent_civilization = int(CIVILIZATION_IDS[str(_params["opp"]).to_lower()])
	else:
		GameManager.set_meta("auto_solo_opponent", true)
	menu.get_tree().call_deferred("change_scene_to_file", MATCH_SCENE_PATH)


static func attach(target_match: Node) -> void:
	if not is_dev_session():
		return
	_install_js()
	var hooks: Node = (load("res://scripts/managers/dev_hooks.gd") as GDScript).new()
	hooks.name = "DevHooks"
	target_match.add_child(hooks)
	hooks.bind(target_match)
	_active = hooks
	var speed: float = float(str(_params.get("speed", "1")))
	if speed > 1.0 and not NetworkSession.is_network_match():
		hooks._cmd_set_speed([speed])


static func _install_js() -> void:
	if _js_callback != null:
		return
	_js_callback = JavaScriptBridge.create_callback(func(arguments: Array) -> void: _on_js_call(arguments))
	var window: JavaScriptObject = JavaScriptBridge.get_interface("window")
	window.__pocketDevCall = _js_callback
	JavaScriptBridge.eval(
		"(function(){var call=function(op,arg){var h={};window.__pocketDevCall(op,JSON.stringify(arg===undefined?null:arg),h);"
		+ "return h.ret===undefined?null:JSON.parse(h.ret);};"
		+ "window.PocketDev=Object.freeze({state:function(){return call('state');},events:function(since){return call('events',since||0);},"
		+ "cmd:function(name){return call('cmd',[name,Array.prototype.slice.call(arguments,1)]);},help:function(){return call('help');}});})()", true
	)


static func _on_js_call(arguments: Array) -> void:
	if arguments.size() < 3:
		return
	var payload: Variant = JSON.parse_string(str(arguments[1]))
	var result: Variant = {"error": "no active match"}
	var op: String = str(arguments[0])
	if op == "help":
		result = {"commands": COMMANDS, "params": ["dev", "autostart", "civ", "opp", "map", "difficulty", "seed", "speed", "pop", "skip_tutorial"]}
	elif is_instance_valid(_active):
		match op:
			"state": result = _active.snapshot()
			"events": result = _active.events_since(int(payload) if payload is float else 0)
			"cmd": result = _active.run_command(str(payload[0]), payload[1] as Array) if payload is Array and payload.size() == 2 else {"error": "bad call"}
	var holder: Variant = arguments[2]
	holder.ret = JSON.stringify(result)


# ---------------------------------------------------------------------------
#  Observation
# ---------------------------------------------------------------------------

func bind(target_match: Node) -> void:
	match_scene = target_match
	for player_id: int in [0, 1]:
		totals.append({"trained": {}, "lost": {}, "buildings_built": {}, "buildings_lost": {}, "gathered": {"food": 0, "wood": 0, "gold": 0},
			"first_military_time": -1.0, "peak_army": 0, "researched": [], "attacks_launched": 0})
	# Autoload signals use methods so the connections end with this node.
	GameManager.age_advanced.connect(_on_age_advanced)
	GameManager.research_completed.connect(_on_research_completed)
	GameManager.game_over.connect(_on_game_over)
	var site: Node2D = match_scene.game_map.sacred_site
	if site != null:
		site.captured.connect(func(player_id: int) -> void: log_event("sacred_captured", {"player": player_id}))
		site.contested.connect(func() -> void: log_event("sacred_contested", {"owner": site.owning_player}))
		site.neutralized.connect(func() -> void: log_event("sacred_neutralized", {}))
	watch_ai(match_scene.ai_controller, 1)
	_scan_entities()


func watch_ai(controller: AIController, player_id: int) -> void:
	controller.ai_attack_launched.connect(func(units: Array, target: Vector2) -> void:
		totals[player_id].attacks_launched += 1
		log_event("attack_started", {"player": player_id, "units": units.size(), "tile": _tile_of(target)})
	)


func log_event(type: String, data: Dictionary) -> void:
	data["i"] = events.size()
	data["t"] = snappedf(GameManager.game_time, 0.1)
	data["type"] = type
	events.append(data)


func events_since(index: int) -> Dictionary:
	return {"next": events.size(), "events": events.slice(clampi(index, 0, events.size()))}


func _process(_delta: float) -> void:
	if not is_instance_valid(match_scene):
		return
	_scan_entities()
	if _reveal_map:
		_apply_reveal()


func _scan_entities() -> void:
	for player_id: int in [0, 1]:
		var army: int = 0
		for unit: UnitBase in match_scene._player_units[player_id]:
			if not is_instance_valid(unit):
				continue
			if not unit is Villager and unit.unit_type != UnitData.UnitType.SCOUT and unit.current_state != UnitBase.State.DEAD:
				army += 1
			if not _seen_units.has(unit.get_instance_id()):
				_register_unit(unit, player_id)
		totals[player_id].peak_army = maxi(int(totals[player_id].peak_army), army)
		for building: BuildingBase in match_scene._player_buildings[player_id]:
			if is_instance_valid(building) and not _seen_buildings.has(building.get_instance_id()):
				_register_building(building, player_id)


func _register_unit(unit: UnitBase, player_id: int) -> void:
	var id: int = unit.get_instance_id()
	_seen_units[id] = true
	unit.unit_died.connect(_on_unit_died.bind(player_id))
	unit.attack_landed.connect(_on_attack_landed)
	unit.damage_received.connect(_on_damage.bind(player_id))
	if unit is Villager:
		(unit as Villager).resource_deposited.connect(func(resource: String, amount: int) -> void:
			totals[player_id].gathered[resource] = int(totals[player_id].gathered.get(resource, 0)) + amount
		)
	# Starting units and tester spawns are not production; everything else is.
	if GameManager.game_time <= 0.0 or _dev_spawned.has(id):
		return
	var type_name: String = unit_name(unit.unit_type)
	_bump(totals[player_id].trained, type_name)
	if not unit is Villager and unit.unit_type != UnitData.UnitType.SCOUT and float(totals[player_id].first_military_time) < 0.0:
		totals[player_id].first_military_time = GameManager.game_time
	log_event("unit_trained", {"player": player_id, "unit": type_name})


func _register_building(building: BuildingBase, player_id: int) -> void:
	_seen_buildings[building.get_instance_id()] = building.state == BuildingBase.State.ACTIVE
	building.damage_received.connect(_on_damage.bind(player_id))
	building.building_destroyed.connect(_on_building_destroyed.bind(player_id))
	building.defensive_attack_fired.connect(func(target: Node2D) -> void:
		if is_instance_valid(target):
			_last_attacker[target.get_instance_id()] = building_name(building.building_type)
	)
	if building.state == BuildingBase.State.ACTIVE:
		return
	building.construction_complete.connect(_on_building_complete.bind(player_id))
	log_event("building_placed", {"player": player_id, "building": building_name(building.building_type), "tile": _tile_of(building.global_position)})


func _on_attack_landed(attacker: UnitBase, defender: UnitBase, _hp_loss: float, _counter_bonus: float) -> void:
	if is_instance_valid(attacker) and is_instance_valid(defender):
		_last_attacker[defender.get_instance_id()] = unit_name(attacker.unit_type)


func _on_damage(victim: Node2D, _hp_loss: Variant, player_id: int) -> void:
	var now: float = GameManager.game_time
	if first_combat_time < 0.0:
		first_combat_time = now
	if now - _under_attack_at[player_id] >= UNDER_ATTACK_COOLDOWN:
		log_event("under_attack", {"player": player_id, "victim": _entity_name(victim), "tile": _tile_of(victim.global_position)})
	_under_attack_at[player_id] = now


func _on_unit_died(unit: UnitBase, player_id: int) -> void:
	var type_name: String = unit_name(unit.unit_type)
	_bump(totals[player_id].lost, type_name)
	log_event("unit_died", {"player": player_id, "unit": type_name, "killer": str(_last_attacker.get(unit.get_instance_id(), "unknown")), "tile": _tile_of(unit.global_position)})
	_last_attacker.erase(unit.get_instance_id())


func _on_building_complete(building: BuildingBase, player_id: int) -> void:
	_seen_buildings[building.get_instance_id()] = true
	_bump(totals[player_id].buildings_built, building_name(building.building_type))
	log_event("building_completed", {"player": player_id, "building": building_name(building.building_type)})


func _on_building_destroyed(building: BuildingBase, player_id: int) -> void:
	if first_building_lost_time < 0.0:
		first_building_lost_time = GameManager.game_time
	_bump(totals[player_id].buildings_lost, building_name(building.building_type))
	log_event("building_destroyed", {"player": player_id, "building": building_name(building.building_type), "was_complete": bool(_seen_buildings.get(building.get_instance_id(), false)), "tile": _tile_of(building.global_position)})


func _on_age_advanced(player_id: int, new_age: int) -> void:
	log_event("age_up", {"player": player_id, "age": new_age})


func _on_research_completed(player_id: int, research_id: String) -> void:
	if player_id >= 0 and player_id < totals.size():
		totals[player_id].researched.append(research_id)
	log_event("tech_researched", {"player": player_id, "tech": research_id})


func _on_game_over(winner_id: int) -> void:
	winner = winner_id
	# Main records the reason just before the defeat that emits this signal.
	log_event("game_over", {"winner": winner_id, "reason": str(match_scene.get("_victory_reason"))})


# ---------------------------------------------------------------------------
#  Snapshot
# ---------------------------------------------------------------------------

func snapshot() -> Dictionary:
	var game_map: Node2D = match_scene.game_map
	var state: Dictionary = {
		"time": snappedf(GameManager.game_time, 0.01), "speed": Engine.time_scale,
		"paused": GameManager.current_state == GameManager.GameState.PAUSED,
		"online": NetworkSession.is_network_match(), "fps": Engine.get_frames_per_second(),
		"difficulty": GameManager.selected_difficulty, "map": MAP_IDS.find_key(int(game_map.map_generator.archetype)),
		"seed": int(game_map.map_seed), "population_limit": GameManager.get_match_population_limit(),
		"first_combat_time": first_combat_time, "first_building_lost_time": first_building_lost_time,
		"event_count": events.size(), "players": [], "result": null,
	}
	for player_id: int in [0, 1]:
		state.players.append(_player_snapshot(player_id))
	var site: Node2D = game_map.sacred_site
	if site != null:
		state["sacred_site"] = site.get_status()
		state["sacred_site"]["tile"] = _tile_of(site.global_position)
	var selected: Array = game_map.selection_mgr.selected
	var selection: Dictionary = {}
	for node: Node2D in selected:
		if is_instance_valid(node):
			_bump(selection, _entity_name(node))
	state["selection"] = {"count": selected.size(), "types": selection}
	var camera: Camera2D = game_map.camera
	state["camera"] = {"tile": _tile_of(camera.position), "world": [camera.position.x, camera.position.y], "zoom": camera.zoom.x}
	state["dev"] = {"reveal_map": _reveal_map, "hud_hidden": not match_scene.hud.visible}
	if GameManager.current_state == GameManager.GameState.GAME_OVER:
		state["result"] = {"winner": winner, "reason": str(match_scene.get("_victory_reason"))}
	return state


func _player_snapshot(player_id: int) -> Dictionary:
	var units: Dictionary = {}
	var buildings: Dictionary = {}
	var constructing: Dictionary = {}
	var tasks: Dictionary = {}
	var idle_villagers: int = 0
	var military: int = 0
	for unit: UnitBase in match_scene._player_units[player_id]:
		if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEAD:
			continue
		_bump(units, unit_name(unit.unit_type))
		if unit is Villager:
			var task: String = (unit as Villager).get_economy_task()
			if unit.current_state == UnitBase.State.IDLE:
				idle_villagers += 1
			elif task != "":
				_bump(tasks, task)
		elif unit.unit_type != UnitData.UnitType.SCOUT:
			military += 1
	for building: BuildingBase in match_scene._player_buildings[player_id]:
		if is_instance_valid(building) and building.state != BuildingBase.State.DESTROYED:
			_bump(constructing if building.state == BuildingBase.State.CONSTRUCTING else buildings, building_name(building.building_type))
	var player: Dictionary = GameManager.players.get(player_id, {})
	var stats: Dictionary = match_scene._stats[player_id]
	var age_times: Dictionary = {}
	for age: Variant in match_scene._age_reached_at[player_id]:
		age_times[str(age)] = match_scene._age_reached_at[player_id][age]
	return {
		"civ": CIVILIZATION_IDS.find_key(GameManager.get_player_civilization(player_id)), "age": GameManager.get_player_age(player_id), "age_times": age_times,
		"resources": ResourceManager.get_all_resources(player_id).duplicate(),
		"pop": int(player.get("population", 0)), "pop_cap": int(player.get("population_cap", 0)),
		"units": units, "buildings": buildings, "buildings_under_construction": constructing,
		"villagers": int(units.get("villager", 0)), "idle_villagers": idle_villagers, "villager_tasks": tasks, "military": military,
		"units_lost": int(stats.units_lost), "units_killed": int(stats.units_killed),
		"buildings_lost": int(stats.buildings_lost), "buildings_destroyed": int(match_scene._stats[1 - player_id].buildings_lost),
		"resources_gathered": int(stats.resources_gathered), "totals": totals[player_id],
	}


# ---------------------------------------------------------------------------
#  Tester commands (offline dev sessions only)
# ---------------------------------------------------------------------------

func run_command(command: String, arguments: Array) -> Dictionary:
	if not is_dev_session() or _active != self:
		return {"error": "dev commands are unavailable"}
	if NetworkSession.is_network_match() or NetworkSession.server_mode:
		return {"error": "dev commands are disabled in online matches"}
	if not COMMANDS.has(command):
		return {"error": "unknown command", "commands": COMMANDS}
	# A single object argument supplies named parameters.
	var named: Dictionary = arguments[0] if arguments.size() == 1 and arguments[0] is Dictionary else {}
	var result: Dictionary = call("_cmd_" + command, arguments, named)
	log_event("dev_cmd", {"cmd": command})
	return result


func _cmd_camera_to(arguments: Array, named: Dictionary = {}) -> Dictionary:
	var game_map: Node2D = match_scene.game_map
	var tile: Vector2i = _resolve_tile(named.get("target", named if named.has("x") else (arguments[0] if not arguments.is_empty() else "home")), 0)
	var zoom: float = float(named.get("zoom", arguments[1] if arguments.size() > 1 else 0.0))
	if zoom > 0.0:
		game_map._set_zoom_anchored(zoom, game_map.NO_ZOOM_ANCHOR, game_map.NO_ZOOM_ANCHOR, true)
	game_map.camera.position = game_map.tile_to_world(tile)
	game_map._clamp_camera()
	return {"ok": true, "tile": [tile.x, tile.y], "zoom": game_map.camera.zoom.x}


func _cmd_set_speed(arguments: Array, named: Dictionary = {}) -> Dictionary:
	var speed: float = clampf(float(named.get("speed", arguments[0] if not arguments.is_empty() else 1.0)), 0.5, 3.0)
	Engine.time_scale = speed
	match_scene.hud.sync_speed_display(speed)
	return {"ok": true, "speed": speed}


func _cmd_pause(arguments: Array, named: Dictionary = {}) -> Dictionary:
	if bool(named.get("paused", arguments[0] if not arguments.is_empty() else true)):
		match_scene._on_pause_requested()
	else:
		match_scene._on_resume_requested()
	return {"ok": true, "paused": GameManager.current_state == GameManager.GameState.PAUSED}


func _cmd_reveal_map(arguments: Array, named: Dictionary = {}) -> Dictionary:
	_reveal_map = bool(named.get("on", arguments[0] if not arguments.is_empty() else true))
	var fog: FogManager = match_scene.game_map.fog_of_war
	if fog != null and fog.fog_layer != null:
		fog.fog_layer.visible = not _reveal_map
	if not _reveal_map:
		match_scene._update_fog_entity_visibility()
	return {"ok": true, "reveal_map": _reveal_map}


func _cmd_give(arguments: Array, _named: Dictionary = {}) -> Dictionary:
	var first: Dictionary = arguments[0] if not arguments.is_empty() and arguments[0] is Dictionary else {}
	var grant: Dictionary = first.get("resources", first)
	var player_id: int = clampi(int(first.get("player", arguments[1] if arguments.size() > 1 else 0)), 0, 1)
	for resource: String in RESOURCES:
		if grant.has(resource):
			ResourceManager.add_resource(player_id, resource, int(grant[resource]))
	return {"ok": true, "player": player_id, "resources": ResourceManager.get_all_resources(player_id)}


func _cmd_spawn(arguments: Array, named: Dictionary = {}) -> Dictionary:
	var type_name: String = str(named.get("unit", arguments[0] if not arguments.is_empty() else "")).to_upper()
	if not UnitData.UnitType.has(type_name):
		return {"error": "unknown unit", "units": UnitData.UnitType.keys()}
	var unit_type: int = UnitData.UnitType[type_name]
	var count: int = clampi(int(named.get("count", arguments[1] if arguments.size() > 1 else 1)), 1, 40)
	var player_id: int = clampi(int(named.get("player", arguments[2] if arguments.size() > 2 else 0)), 0, 1)
	var center: Vector2i = _resolve_tile(named.get("near", arguments[3] if arguments.size() > 3 else "home"), player_id)
	var game_map: Node2D = match_scene.game_map
	var tiles: Array[Vector2i] = game_map.pathfinding.get_walkable_tiles_near(center, 6, count)
	var pop_cost: int = int(UnitData.UNITS.get(unit_type, {}).get("pop_cost", 1))
	var spawned: int = 0
	for tile: Vector2i in tiles:
		# Staged fights may exceed housing; add unowned room rather than fail.
		if not GameManager.can_reserve_population(player_id, pop_cost):
			GameManager.increase_population_cap(player_id, pop_cost)
			if not GameManager.can_reserve_population(player_id, pop_cost):
				# Scale staging (100 v 100) goes past the match's population limit.
				GameManager.players[player_id]["max_population"] = int(GameManager.players[player_id].get("max_population", 0)) + pop_cost
				GameManager._recalculate_population_cap(player_id)
		var unit: UnitBase = match_scene._spawn_unit(unit_type, player_id, game_map.tile_to_world(tile))
		if unit == null:
			break
		_dev_spawned[unit.get_instance_id()] = true
		spawned += 1
	return {"ok": spawned > 0, "spawned": spawned, "unit": type_name.to_lower(), "player": player_id, "tile": [center.x, center.y]}


func _cmd_age(arguments: Array, named: Dictionary = {}) -> Dictionary:
	## Advance a player to an age at once (no cost, no timer).
	var target: int = clampi(int(named.get("age", arguments[0] if not arguments.is_empty() else GameManager.MAX_AGE)), 1, GameManager.MAX_AGE)
	var player_id: int = clampi(int(named.get("player", arguments[1] if arguments.size() > 1 else 0)), 0, 1)
	while GameManager.get_player_age(player_id) < target and GameManager.advance_age(player_id):
		pass
	return {"ok": GameManager.get_player_age(player_id) >= target, "player": player_id, "age": GameManager.get_player_age(player_id)}


func _cmd_build(arguments: Array, named: Dictionary = {}) -> Dictionary:
	## Place a finished building on the nearest free ground (no cost, no builder).
	var type_name: String = str(named.get("building", arguments[0] if not arguments.is_empty() else "")).to_upper()
	if not BuildingData.BuildingType.has(type_name):
		return {"error": "unknown building", "buildings": BuildingData.BuildingType.keys()}
	var building_type: int = BuildingData.BuildingType[type_name]
	var player_id: int = clampi(int(named.get("player", arguments[1] if arguments.size() > 1 else 0)), 0, 1)
	var center: Vector2i = _resolve_tile(named.get("near", arguments[2] if arguments.size() > 2 else "home"), player_id)
	var game_map: Node2D = match_scene.game_map
	var footprint: Vector2i = BuildingData.BUILDINGS[building_type].get("footprint", Vector2i.ONE)
	for radius: int in range(4, 16):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var origin: Vector2i = center + Vector2i(dx, dy)
				var free: bool = true
				# One spare tile all round keeps paths open between staged buildings.
				for fy: int in range(-1, footprint.y + 1):
					for fx: int in range(-1, footprint.x + 1):
						if not game_map.is_tile_buildable(origin + Vector2i(fx, fy)):
							free = false
				if not free:
					continue
				var building: BuildingBase = match_scene._spawn_building(building_type, player_id, origin)
				if building == null:
					return {"error": "spawn failed"}
				building.complete_instantly()
				return {"ok": true, "building": type_name.to_lower(), "player": player_id, "tile": [origin.x, origin.y]}
	return {"error": "no free ground"}


func _cmd_screenshot_safe_ui(arguments: Array, named: Dictionary = {}) -> Dictionary:
	var hide_hud: bool = bool(named.get("hide", arguments[0] if not arguments.is_empty() else true))
	match_scene.hud.visible = not hide_hud
	return {"ok": true, "hud_hidden": hide_hud}


func _apply_reveal() -> void:
	for unit: UnitBase in match_scene._player_units[1]:
		if is_instance_valid(unit) and unit.current_state != UnitBase.State.DEAD:
			unit.visible = true
	for building: BuildingBase in match_scene._player_buildings[1]:
		if is_instance_valid(building):
			building.visible = true


# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------

func _resolve_tile(target: Variant, player_id: int) -> Vector2i:
	var game_map: Node2D = match_scene.game_map
	var spawns: Array = game_map.map_generator.spawn_positions
	if target is Array and target.size() >= 2:
		return Vector2i(int(target[0]), int(target[1]))
	if target is Dictionary and target.has("x") and target.has("y"):
		return Vector2i(int(target.x), int(target.y))
	match str(target):
		"enemy": return spawns[1 - player_id]
		"sacred": return game_map.world_to_tile(game_map.sacred_site.global_position) if game_map.sacred_site != null else spawns[player_id]
		"p0": return spawns[0]
		"p1": return spawns[1]
	return spawns[player_id]


func _tile_of(world_position: Vector2) -> Array:
	var tile: Vector2i = match_scene.game_map.world_to_tile(world_position)
	return [tile.x, tile.y]


func _entity_name(node: Node2D) -> String:
	if node is UnitBase:
		return unit_name((node as UnitBase).unit_type)
	if node is BuildingBase:
		return building_name((node as BuildingBase).building_type)
	return node.get_class().to_lower() if node.get_script() == null else str(node.name).to_lower()


static func unit_name(unit_type: int) -> String:
	var key: Variant = UnitData.UnitType.find_key(unit_type)
	return str(key).to_lower() if key != null else "unit_%d" % unit_type


static func building_name(building_type: int) -> String:
	var key: Variant = BuildingData.BuildingType.find_key(building_type)
	return str(key).to_lower() if key != null else "building_%d" % building_type


static func _bump(counts: Dictionary, key: String) -> void:
	counts[key] = int(counts.get(key, 0)) + 1
