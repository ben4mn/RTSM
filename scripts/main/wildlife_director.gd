class_name WildlifeDirector
extends Node
## Owns the opening wildlife of one match: spawns the planned animals, runs
## the sheep rules (claim, steal, walk home, herd), decides when a boar turns
## on a villager, and carries all of it through the Round 2 seams (ext save
## section, ext snapshot rows, `herd` and `hunt` ext commands, one Town Center
## context action). Lives as `GameMap/WildlifeDirector`.
##
## Animals themselves are WildlifeNode harvestables (scripts/map/wildlife_node.gd);
## numbers are in scripts/data/wildlife_data.gd.

const NODE_NAME: String = "WildlifeDirector"
const GROUP: String = "wildlife_director"
const THINK_SECONDS: float = 0.25
const ACTION_WALK_HOME: String = "wildlife:walk_home"
const TEAM_COLORS: Array[Color] = [Color("88b7ad"), Color("d69477")]
const HERD_OFFSETS: Array[Vector2] = [Vector2.ZERO, Vector2(26, 9), Vector2(-26, 9), Vector2(0, 19), Vector2(27, -10), Vector2(-27, -10), Vector2(52, 0), Vector2(-52, 0)]
const KIND_CODES: Array[String] = [WildlifeData.SHEEP, WildlifeData.DEER, WildlifeData.BOAR]

var main: Node = null
var game_map: Node2D = null
var nodes: Array[WildlifeNode] = []
var by_id: Dictionary = {}
## The "Sheep walk home" assist, per player (index 0 is the local player on a client).
var walk_home: Array[bool] = [true, true]

var _think: float = 0.0
var _clock: float = 0.0
var _home_retry: Dictionary = {}
var _boar_warned_at: Dictionary = {}
var _last_claim_toast: float = -100.0
var _ping_layer: Control = null


# --- Setup ----------------------------------------------------------------------

## The one registration line: `WildlifeDirector.install(self)` in
## main._register_match_extensions(). Safe on the authority, on clients and
## while a solo save is being restored.
static func install(match_main: Node) -> WildlifeDirector:
	var map: Node2D = match_main.get("game_map") as Node2D
	if map == null:
		return null
	var director: WildlifeDirector = attach(map, match_main)
	var extensions: RefCounted = match_main.get("ext") as RefCounted
	if extensions != null:
		extensions.call("register_command", "herd", director._command_herd, _valid_herd)
		extensions.call("register_command", "hunt", director._command_hunt, _valid_hunt)
		extensions.call("register_snapshot", "wildlife", director._snapshot_rows, director._apply_snapshot_rows)
		extensions.call("register_save", "wildlife", director._capture, director._restore)
	BuildingBase.register_context_provider("wildlife", _context_actions, _context_perform)
	if not NetworkSession.is_client() and not SoloSave.is_restoring():
		director.spawn_planned()
	return director


static func attach(map: Node2D, match_main: Node = null) -> WildlifeDirector:
	var existing: WildlifeDirector = map.get_node_or_null(NODE_NAME) as WildlifeDirector
	if existing != null:
		return existing
	var director := WildlifeDirector.new()
	director.name = NODE_NAME
	director.main = match_main
	director.game_map = map
	map.add_child(director)
	return director


static func of(node: Node) -> WildlifeDirector:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group(GROUP) as WildlifeDirector


func _ready() -> void:
	add_to_group(GROUP)


func spawn_planned() -> void:
	var rows: Array[Dictionary] = WildlifePlacement.plan(game_map.map_generator, int(game_map.get("map_seed")))
	for index: int in rows.size():
		var row: Dictionary = rows[index]
		spawn(index, str(row.kind), game_map.tile_to_world(row.tile), int(row.owner))


func spawn(wildlife_id: int, kind: String, world_position: Vector2, owner_id: int = -1, as_replica: bool = false) -> WildlifeNode:
	var node := WildlifeNode.new()
	node.name = "Wildlife%d" % wildlife_id
	node.kind = kind
	node.wildlife_id = wildlife_id
	node.total_amount = int(WildlifeData.FOOD.get(kind, 100))
	node.game_map = game_map
	node.replica = as_replica
	node.owner_id = owner_id
	node.pasture_owner = owner_id
	node.team_color = _team_color(owner_id)
	node.position = world_position
	node.home_position = world_position
	node.tile_position = game_map.world_to_tile(world_position)
	# Fog decides on the first think; nothing shows through it for a frame.
	node.visible = as_replica or NetworkSession.server_mode or owner_id == 0
	var container: Node = game_map.get_node_or_null("ResourcesContainer")
	(container if container != null else game_map).add_child(node)
	game_map.register_harvestable(node)
	nodes.append(node)
	by_id[wildlife_id] = node
	node.depleted.connect(_on_depleted)
	node.enraged.connect(_on_enraged)
	node.felled.connect(_on_felled)
	return node


func _remove(node: WildlifeNode) -> void:
	nodes.erase(node)
	if by_id.get(node.wildlife_id) == node:
		by_id.erase(node.wildlife_id)
	if is_instance_valid(game_map):
		game_map.unregister_harvestable(node)


func _on_depleted(node: ResourceNode) -> void:
	if node is WildlifeNode:
		_remove(node as WildlifeNode)


func _team_color(owner_id: int) -> Color:
	return TEAM_COLORS[owner_id] if owner_id >= 0 and owner_id < TEAM_COLORS.size() else Color.WHITE


# --- Queries (AI and HUD surface, via game_map.get_wildlife_*) ----------------------

func get_nodes(kind: String = "") -> Array[WildlifeNode]:
	var result: Array[WildlifeNode] = []
	for node: WildlifeNode in nodes:
		if is_instance_valid(node) and node.remaining > 0 and (kind == "" or node.kind == kind):
			result.append(node)
	return result


func get_owned_nodes(player_id: int) -> Array[WildlifeNode]:
	var result: Array[WildlifeNode] = []
	for node: WildlifeNode in nodes:
		if is_instance_valid(node) and node.remaining > 0 and node.kind == WildlifeData.SHEEP and node.owner_id == player_id:
			result.append(node)
	return result


func is_walk_home_enabled(player_id: int) -> bool:
	return player_id >= 0 and player_id < walk_home.size() and walk_home[player_id]


func set_walk_home(player_id: int, enabled: bool) -> void:
	if player_id < 0 or player_id >= walk_home.size():
		return
	walk_home[player_id] = enabled
	if enabled:
		_home_retry.clear()
		return
	for node: WildlifeNode in get_owned_nodes(player_id):
		if node.is_walking() and not node.manual_stay:
			node._stop()


# --- Authority simulation -----------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	if NetworkSession.is_client():
		return
	_think -= delta
	if _think > 0.0:
		return
	var elapsed: float = THINK_SECONDS - _think
	_think = THINK_SECONDS
	think(elapsed)


## One rules pass. Public so regressions can step it without waiting a frame.
func think(elapsed: float = THINK_SECONDS) -> void:
	for index: int in range(nodes.size() - 1, -1, -1):
		if not is_instance_valid(nodes[index]) or nodes[index].is_queued_for_deletion():
			nodes.remove_at(index)
	var workers: Dictionary = _workers_by_animal()
	var town_centers: Array = _town_center_tiles()
	for node: WildlifeNode in nodes.duplicate():
		if node.remaining <= 0:
			continue
		var assigned: Array = workers.get(node.get_instance_id(), [])
		node.tended = not assigned.is_empty()
		if node.phase == WildlifeNode.Phase.CARCASS:
			node.spoil(elapsed)
		elif node.kind == WildlifeData.SHEEP:
			_think_sheep(node, town_centers)
		elif node.kind == WildlifeData.BOAR and node.mood != WildlifeNode.Mood.ENRAGED:
			for villager: Villager in assigned:
				if villager.global_position.distance_to(node.global_position) <= WildlifeData.BOAR_AGGRO_RANGE:
					node.enrage(villager)
					break
	_refresh_local_visibility()


## animal instance id -> villagers whose current job is that animal.
func _workers_by_animal() -> Dictionary:
	var result: Dictionary = {}
	if not is_inside_tree():
		return result
	for entry: Node in get_tree().get_nodes_in_group("villagers"):
		var villager := entry as Villager
		if villager == null or villager.current_state == UnitBase.State.DEAD or not is_instance_valid(villager.gather_target):
			continue
		if not villager.gather_target is WildlifeNode or not villager.has_active_gather_order():
			continue
		var id: int = villager.gather_target.get_instance_id()
		if not result.has(id):
			result[id] = []
		result[id].append(villager)
	return result


func _town_center_tiles() -> Array:
	var result: Array = [[], []]
	if not is_inside_tree():
		return result
	for entry: Node in get_tree().get_nodes_in_group("buildings"):
		var building := entry as BuildingBase
		if building == null or building.building_type != BuildingData.BuildingType.TOWN_CENTER or building.state != BuildingBase.State.ACTIVE:
			continue
		if building.player_owner in [0, 1]:
			result[building.player_owner].append(game_map.world_to_tile(building.global_position))
	return result


func _think_sheep(sheep: WildlifeNode, town_centers: Array) -> void:
	var nearest: Array[float] = [INF, INF]
	var bound: float = WildlifeData.tiles_to_world_bound(WildlifeData.STEAL_GUARD_RADIUS_TILES)
	for unit: UnitBase in game_map.get_units_near(sheep.global_position, bound):
		if unit.player_owner < 0 or unit.player_owner > 1 or unit.current_state == UnitBase.State.DEAD:
			continue
		var distance: float = WildlifeData.tile_distance(sheep.global_position, unit.global_position)
		nearest[unit.player_owner] = minf(nearest[unit.player_owner], distance)
	if sheep.owner_id < 0:
		var claimer: int = 0 if nearest[0] <= nearest[1] else 1
		if nearest[claimer] <= WildlifeData.CLAIM_RADIUS_TILES:
			_claim(sheep, claimer)
	else:
		var rival: int = 1 - sheep.owner_id
		if nearest[rival] <= WildlifeData.STEAL_RADIUS_TILES and nearest[sheep.owner_id] > WildlifeData.STEAL_GUARD_RADIUS_TILES and not _guarded_by_town_center(sheep, town_centers[sheep.owner_id]):
			_claim(sheep, rival)
	if sheep.owner_id < 0 or not walk_home[sheep.owner_id] or sheep.manual_stay or sheep.has_goal or sheep.tended:
		return
	# Not pastured yet, or a blocked route left it short of its slot.
	if sheep.pasture_owner != sheep.owner_id or sheep.global_position.distance_to(sheep.home_position) > 8.0:
		_send_home(sheep, town_centers[sheep.owner_id])


func _guarded_by_town_center(sheep: WildlifeNode, centers: Array) -> bool:
	var tile: Vector2i = game_map.world_to_tile(sheep.global_position)
	for origin: Vector2i in centers:
		if WildlifePlacement._ring_from_town_center(tile, origin) <= int(WildlifeData.STEAL_GUARD_RADIUS_TILES):
			return true
	return false


func _claim(sheep: WildlifeNode, new_owner: int) -> void:
	var previous: int = sheep.owner_id
	sheep.manual_stay = false
	sheep.pasture_owner = -1
	sheep._stop()
	sheep.set_owner_id(new_owner, _team_color(new_owner))
	_home_retry.erase(sheep.get_instance_id())
	GameManager.wildlife_claimed.emit(new_owner, sheep)
	_present_claim(sheep, previous, new_owner)


func _send_home(sheep: WildlifeNode, centers: Array) -> void:
	var id: int = sheep.get_instance_id()
	if _clock < float(_home_retry.get(id, 0.0)):
		return
	_home_retry[id] = _clock + 2.0
	var slot: Vector2i = _pasture_slot(sheep, centers)
	if slot.x < 0:
		return
	var goal: Vector2 = game_map.tile_to_world(slot)
	if sheep.global_position.distance_to(goal) < 6.0 or sheep.walk_to(goal):
		sheep.home_position = goal
		sheep.pasture_owner = sheep.owner_id


## A free tile in the grazing ring of the owner's nearest Town Center, as close
## as possible to the sheep already pastured there so the flock stays together.
func _pasture_slot(sheep: WildlifeNode, centers: Array) -> Vector2i:
	if centers.is_empty():
		return Vector2i(-1, -1)
	var sheep_tile: Vector2i = game_map.world_to_tile(sheep.global_position)
	var origin: Vector2i = centers[0]
	for candidate: Vector2i in centers:
		if Vector2(candidate - sheep_tile).length_squared() < Vector2(origin - sheep_tile).length_squared():
			origin = candidate
	var reserved: Dictionary = {}
	var anchor := Vector2.ZERO
	var flock: int = 0
	for other: WildlifeNode in nodes:
		if other == sheep or not is_instance_valid(other) or other.remaining <= 0:
			continue
		var home_tile: Vector2i = game_map.world_to_tile(other.home_position)
		reserved[home_tile] = true
		reserved[game_map.world_to_tile(other.global_position)] = true
		if other.kind == WildlifeData.SHEEP and other.owner_id == sheep.owner_id and other.pasture_owner == sheep.owner_id and WildlifePlacement._ring_from_town_center(home_tile, origin) <= WildlifeData.HOME_RING_MAX + 2:
			anchor += Vector2(home_tile)
			flock += 1
	anchor = anchor / float(flock) if flock > 0 else Vector2(sheep_tile)
	var best := Vector2i(-1, -1)
	var best_score: float = INF
	for ring_max: int in [WildlifeData.HOME_RING_MAX, WildlifeData.HOME_RING_MAX + 2]:
		for dy: int in range(-ring_max, WildlifePlacement.TOWN_CENTER_SIZE + ring_max):
			for dx: int in range(-ring_max, WildlifePlacement.TOWN_CENTER_SIZE + ring_max):
				var tile: Vector2i = origin + Vector2i(dx, dy)
				var ring: int = WildlifePlacement._ring_from_town_center(tile, origin)
				if ring < WildlifeData.HOME_RING_MIN or ring > ring_max or reserved.has(tile) or not game_map.is_tile_buildable(tile):
					continue
				var score: float = (Vector2(tile) - anchor).length_squared()
				if score < best_score:
					best_score = score
					best = tile
		if best.x >= 0:
			break
	return best


## Manual herding: the chosen sheep, and the owner's other loose sheep right
## beside them, walk to `world_position` and stay there.
func order_herd(owner_id: int, leaders: Array, world_position: Vector2) -> bool:
	var tile: Vector2i = game_map.world_to_tile(world_position)
	if tile.x < 0 or tile.y < 0 or tile.x >= MapData.MAP_WIDTH or tile.y >= MapData.MAP_HEIGHT:
		return false
	if game_map.is_tile_visible_to_player(tile, owner_id) and not game_map.is_tile_walkable(tile):
		return false
	var flock: Array[WildlifeNode] = []
	for entry: Variant in leaders:
		if is_instance_valid(entry) and entry is WildlifeNode and (entry as WildlifeNode).is_herdable_by(owner_id) and entry not in flock:
			flock.append(entry)
	if flock.is_empty():
		return false
	for leader: WildlifeNode in flock.duplicate():
		for other: WildlifeNode in nodes:
			if other in flock or not is_instance_valid(other) or not other.is_herdable_by(owner_id) or other.tended:
				continue
			if WildlifeData.tile_distance(leader.global_position, other.global_position) <= WildlifeData.FLOCK_RADIUS_TILES:
				flock.append(other)
	var moved: bool = false
	for index: int in flock.size():
		var sheep: WildlifeNode = flock[index]
		var goal: Vector2 = world_position + HERD_OFFSETS[index % HERD_OFFSETS.size()]
		if not game_map.is_tile_walkable(game_map.world_to_tile(goal)):
			goal = world_position
		if sheep.walk_to(goal):
			sheep.manual_stay = true
			sheep.pasture_owner = -1
			sheep.home_position = goal
			moved = true
	return moved


# --- Local input (called from main.gd) ----------------------------------------------

## A ground tap with own sheep selected. Returns true when it was a herd order.
static func try_herd_selection(match_main: Node, target_tile: Vector2i) -> bool:
	var director: WildlifeDirector = of(match_main)
	if director == null:
		return false
	var sheep: Array = []
	var ids: Array = []
	for entry: Variant in director.game_map.selection_mgr.selected:
		if is_instance_valid(entry) and entry is WildlifeNode and (entry as WildlifeNode).is_herdable_by(0):
			sheep.append(entry)
			ids.append((entry as WildlifeNode).wildlife_id)
	if sheep.is_empty():
		return false
	var world: Vector2 = director.game_map.tile_to_world(target_tile)
	var accepted: bool = true
	if NetworkSession.is_client():
		NetworkSession.send_command("herd", {"sheep": ids, "position": [world.x, world.y]})
	else:
		accepted = director.order_herd(0, sheep, world)
	if accepted:
		VFX.move_indicator(director.get_tree(), world)
		AudioManager.play_ui("command_move")
	elif is_instance_valid(match_main.get("hud")):
		match_main.hud.show_notification("Sheep can't reach that spot", KingdomTheme.RUST)
	return true


## Online clients name wildlife by its own id; resources are tile-keyed there.
static func send_network_gather(match_main: Node, target: Node2D) -> bool:
	if not target is WildlifeNode or not NetworkSession.is_client():
		return false
	match_main.call("_send_network_selection", "hunt", {"wid": (target as WildlifeNode).wildlife_id})
	VFX.gather_indicator(match_main.get_tree(), target.global_position)
	return true


## All opening villagers start on the same home sheep (butcher one at a time).
static func assign_opening_villagers(match_main: Node, villagers: Array) -> bool:
	var director: WildlifeDirector = of(match_main)
	if director == null or villagers.is_empty():
		return false
	var assigned: bool = false
	var first_sheep: Dictionary = {}
	for entry: Variant in villagers:
		if not is_instance_valid(entry) or not entry is Villager:
			continue
		var villager := entry as Villager
		var sheep: WildlifeNode = first_sheep.get(villager.player_owner) as WildlifeNode
		if sheep == null:
			var best: float = INF
			for candidate: WildlifeNode in director.get_owned_nodes(villager.player_owner):
				var distance: float = candidate.global_position.distance_to(villager.global_position)
				if distance < best:
					best = distance
					sheep = candidate
			first_sheep[villager.player_owner] = sheep
		if sheep != null and villager.command_gather(sheep):
			assigned = true
	return assigned


## The selection card for an animal, built from the stock resource card.
static func show_selection(hud: Node, node: WildlifeNode) -> void:
	var percent: int = int(float(node.remaining) / float(maxi(1, node.total_amount)) * 100.0)
	hud.call("show_resource_info", "Food", node.remaining, node.total_amount, percent)
	var title: String = node.get_display_name()
	if node.kind == WildlifeData.SHEEP and node.phase == WildlifeNode.Phase.ALIVE:
		title = "Your Sheep" if node.owner_id == 0 else ("Rival Sheep" if node.owner_id == 1 else "Stray Sheep")
	hud.set("_selection_full_name", title)
	var name_label: Label = hud.get("selection_name") as Label
	if name_label != null:
		name_label.text = title
	var portrait: String = node.get_presentation_texture_path()
	if ResourceLoader.exists(portrait):
		hud.set("_selection_portrait", load(portrait))
	var details: String = "%d / %d food" % [node.remaining, node.total_amount]
	if node.is_fighting():
		details = "HP %d / %d · %d food\nDangerous: lure it to your Town Center" % [ceili(node.hp), int(node.max_hp), node.remaining]
		if hud.has_method("_set_selection_meter"):
			hud.call("_set_selection_meter", node.hp, node.max_hp, "HP %d" % ceili(node.hp), "Boar health: %d / %d" % [ceili(node.hp), int(node.max_hp)])
	elif node.phase == WildlifeNode.Phase.CARCASS:
		details += "\nSpoils while nobody gathers it"
	elif node.kind == WildlifeData.SHEEP and node.owner_id == 0:
		details += "\nTap ground to herd"
	var details_label: Label = hud.get("selection_details") as Label
	if details_label != null:
		details_label.text = details


# --- Presentation (local player only) -------------------------------------------------

func _local_hud() -> Node:
	if NetworkSession.server_mode or not is_instance_valid(main):
		return null
	var hud: Node = main.get("hud") as Node
	return hud if is_instance_valid(hud) else null


func _refresh_local_visibility() -> void:
	if NetworkSession.server_mode:
		return
	for node: WildlifeNode in nodes:
		if is_instance_valid(node):
			node.visible = game_map.is_entity_visible_to_player(node, 0)


func _present_claim(sheep: WildlifeNode, previous_owner: int, new_owner: int) -> void:
	var hud: Node = _local_hud()
	if hud == null or (new_owner != 0 and previous_owner != 0):
		return
	if _clock - _last_claim_toast < 1.5:
		return
	_last_claim_toast = _clock
	var focus: Vector2 = sheep.global_position
	var jump := func() -> void:
		if is_instance_valid(game_map):
			game_map.note_camera_interaction()
			game_map.camera.position = game_map.get_clamped_camera_focus(focus)
	if new_owner == 0:
		var text: String = "Sheep found" if previous_owner < 0 else "Sheep stolen from your rival"
		if walk_home[0]:
			text += " · walking home"
		hud.call("show_notification", text, Color(0.80, 0.92, 0.70), 4.0, jump)
		VFX.gather_indicator(get_tree(), sheep.global_position)
	else:
		hud.call("show_notification", "A rival scout stole your sheep", KingdomTheme.RUST, 4.0, jump)
	_ping(sheep.global_position, new_owner == 0)


func _on_enraged(boar: WildlifeNode, target: Node2D) -> void:
	var hud: Node = _local_hud()
	if hud == null or not target is UnitBase or (target as UnitBase).player_owner != 0:
		return
	_present_boar_warning(boar, hud)


func _present_boar_warning(boar: WildlifeNode, hud: Node) -> void:
	var id: int = boar.get_instance_id()
	if _clock - float(_boar_warned_at.get(id, -100.0)) < 20.0:
		return
	var helpers: int = 0
	for unit: UnitBase in game_map.get_units_near(boar.global_position, WildlifeData.tiles_to_world_bound(WildlifeData.BOAR_RETARGET_RADIUS_TILES)):
		if unit is Villager and unit.player_owner == 0 and WildlifeData.tile_distance(unit.global_position, boar.global_position) <= WildlifeData.BOAR_RETARGET_RADIUS_TILES:
			helpers += 1
	if helpers >= WildlifeData.BOAR_SAFE_VILLAGERS:
		return
	_boar_warned_at[id] = _clock
	hud.call("show_notification", "Boar is dangerous — lure it to your Town Center", KingdomTheme.RUST, 5.0)


func _on_felled(boar: WildlifeNode) -> void:
	if NetworkSession.server_mode:
		return
	_present_felled(boar, boar.last_striker_owner == 0)


func _present_felled(boar: WildlifeNode, by_local_player: bool) -> void:
	var fx: BattleFX = BattleFX.get_fx()
	if fx != null and boar.visible:
		fx.dust(boar.global_position, 7, 1.2)
		BattleFX.shake(0.22, boar.global_position)
	var hud: Node = _local_hud()
	if hud != null and by_local_player:
		hud.call("show_notification", "Boar felled · %d food" % boar.remaining, Color(0.95, 0.86, 0.55), 4.0)


## A short ring on the minimap; no permanent HUD element is added.
func _ping(world_position: Vector2, friendly: bool) -> void:
	var hud: Node = _local_hud()
	if hud == null:
		return
	var rect: Control = hud.get("minimap_rect") as Control
	if rect == null:
		return
	if not is_instance_valid(_ping_layer):
		_ping_layer = MinimapPings.new()
		_ping_layer.name = "WildlifePings"
		_ping_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ping_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.add_child(_ping_layer)
	var tile: Vector2i = game_map.world_to_tile(world_position)
	(_ping_layer as MinimapPings).add(Vector2(float(tile.x) / MapData.MAP_WIDTH, float(tile.y) / MapData.MAP_HEIGHT), Color("f3e7b0") if friendly else Color("e58a6a"))


class MinimapPings extends Control:
	var _pings: Array[Dictionary] = []

	func add(normalized: Vector2, color: Color) -> void:
		_pings.append({"at": normalized, "color": color, "age": 0.0})
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		for index: int in range(_pings.size() - 1, -1, -1):
			_pings[index].age = float(_pings[index].age) + delta
			if float(_pings[index].age) > 2.4:
				_pings.remove_at(index)
		if _pings.is_empty():
			set_process(false)
		queue_redraw()

	func _draw() -> void:
		for ping: Dictionary in _pings:
			var point: Vector2 = (ping.at as Vector2) * size
			var phase: float = fposmod(float(ping.age), 0.8) / 0.8
			var fade: float = 1.0 - clampf(float(ping.age) / 2.4, 0.0, 1.0)
			draw_arc(point, 3.0 + phase * 9.0, 0.0, TAU, 20, Color(ping.color as Color, fade * (1.0 - phase * 0.6)), 1.6, true)
			draw_circle(point, 2.0, Color(ping.color as Color, fade))


# --- Town Center context action --------------------------------------------------------

static func _context_actions(building: BuildingBase, player_id: int) -> Array:
	if building.building_type != BuildingData.BuildingType.TOWN_CENTER or building.state != BuildingBase.State.ACTIVE:
		return []
	var director: WildlifeDirector = of(building)
	if director == null or not player_id in [0, 1]:
		return []
	var enabled: bool = director.walk_home[player_id]
	return [{
		"id": ACTION_WALK_HOME,
		"label": "Sheep walk home",
		"short": "Sheep home",
		"icon": "res://assets/resources/sheep.svg",
		"cost": {},
		"time": 0.0,
		"progress": -1.0,
		"disabled_reason": "",
		"desc": "On · tap to herd by hand" if enabled else "Off · tap to turn on",
		"details": "Claimed sheep walk to this Town Center by themselves. Turn it off to herd every sheep by hand: select a sheep, then tap the ground.",
	}]


static func _context_perform(building: BuildingBase, player_id: int, action_id: String) -> String:
	var director: WildlifeDirector = of(building)
	if director == null or action_id != ACTION_WALK_HOME or not player_id in [0, 1]:
		return "Action unavailable"
	director.set_walk_home(player_id, not director.walk_home[player_id])
	return ""


# --- Network seam (docs/round2_contracts.md section 3) ----------------------------------

static func _valid_herd(packet: Dictionary) -> bool:
	return packet.get("position") is Array and packet.get("sheep") is Array and not (packet.sheep as Array).is_empty() and (packet.sheep as Array).size() <= 16


static func _valid_hunt(packet: Dictionary) -> bool:
	return typeof(packet.get("wid")) in [TYPE_INT, TYPE_FLOAT] and packet.get("ids") is Array


func _command_herd(owner_id: int, packet: Dictionary, _units: Array, _target: Node2D, world_position: Vector2) -> String:
	var leaders: Array = []
	for id: Variant in packet.sheep:
		var node: WildlifeNode = by_id.get(int(id)) as WildlifeNode
		if is_instance_valid(node):
			leaders.append(node)
	return "" if order_herd(owner_id, leaders, world_position) else "Sheep can't go there"


func _command_hunt(owner_id: int, packet: Dictionary, units: Array, _target: Node2D, _position: Vector2) -> String:
	var node: WildlifeNode = by_id.get(int(packet.wid)) as WildlifeNode
	if not is_instance_valid(node) or not game_map.is_resource_target_valid(node, "", owner_id) or not game_map.is_resource_target_visible_to_player(node, owner_id):
		return "Resource no longer available"
	var accepted: bool = false
	for unit: Variant in units:
		if unit is Villager and (unit as Villager).command_gather(node):
			accepted = true
	return "" if accepted else "Select your villagers"


## Server, per recipient: only animals that player can currently see.
func _snapshot_rows(slot: int) -> Variant:
	var rows: Array = []
	for node: WildlifeNode in nodes:
		if not is_instance_valid(node) or node.remaining <= 0 or not game_map.is_entity_visible_to_player(node, slot):
			continue
		rows.append([node.wildlife_id, KIND_CODES.find(node.kind), snappedf(node.global_position.x, 0.1), snappedf(node.global_position.y, 0.1), node.remaining, node.total_amount, node.owner_id, node.phase, node.mood, ceili(node.hp), int(node.max_hp)])
	return {"rows": rows, "walk_home": walk_home[slot] if slot >= 0 and slot < walk_home.size() else true}


## Client, every snapshot: create, update and retire inert replicas.
func _apply_snapshot_rows(data: Variant) -> void:
	if not data is Dictionary or not data.get("rows") is Array:
		return
	walk_home[0] = bool(data.get("walk_home", true))
	var seen: Dictionary = {}
	for row: Variant in data.rows:
		if not row is Array or row.size() < 11:
			continue
		var id: int = int(row[0])
		var kind_code: int = int(row[1])
		if kind_code < 0 or kind_code >= KIND_CODES.size():
			continue
		seen[id] = true
		var world := Vector2(float(row[2]), float(row[3]))
		var server_owner: int = int(row[6])
		var local_owner: int = server_owner if server_owner < 0 else (0 if server_owner == NetworkSession.player_slot else 1)
		var node: WildlifeNode = by_id.get(id) as WildlifeNode
		var created: bool = not is_instance_valid(node)
		if created:
			node = spawn(id, KIND_CODES[kind_code], world, local_owner, true)
		node.net_position = world
		node.total_amount = int(row[5])
		node.remaining = int(row[4])
		node.max_hp = float(row[10])
		if float(row[9]) < node.hp and not created:
			node._flash = 0.14
		node.hp = float(row[9])
		var was_enraged: bool = node.mood == WildlifeNode.Mood.ENRAGED
		node.mood = int(row[8])
		if int(row[7]) != node.phase:
			var was_boar: bool = node.is_fighting()
			node.phase = int(row[7])
			node._refresh_texture()
			if was_boar and not created:
				_present_felled(node, false)
		if node.owner_id != local_owner:
			var previous: int = node.owner_id
			node.set_owner_id(local_owner, _team_color(local_owner))
			if not created:
				_present_claim(node, previous, local_owner)
		if node.mood == WildlifeNode.Mood.ENRAGED and not was_enraged and not created:
			var hud: Node = _local_hud()
			if hud != null:
				_present_boar_warning(node, hud)
		node.queue_redraw()
	for id: Variant in by_id.keys():
		if seen.has(id):
			continue
		var gone: WildlifeNode = by_id[id] as WildlifeNode
		by_id.erase(id)
		if is_instance_valid(gone):
			_remove(gone)
			gone.queue_free()


# --- Save seam (docs/round2_contracts.md section 4) ------------------------------------

func _capture(codec: RefCounted) -> Dictionary:
	var rows: Array = []
	for node: WildlifeNode in nodes:
		if not is_instance_valid(node) or node.is_queued_for_deletion() or node.remaining <= 0:
			continue
		var target: UnitBase = node.get_target()
		rows.append({
			"id": codec.call("track", node), "wid": node.wildlife_id, "kind": node.kind,
			"position": node.global_position, "total": node.total_amount, "remaining": node.remaining,
			"owner": node.owner_id, "pasture_owner": node.pasture_owner, "phase": node.phase, "mood": node.mood,
			"hp": node.hp, "max_hp": node.max_hp, "home": node.home_position,
			"manual_stay": node.manual_stay, "has_goal": node.has_goal, "goal": node.move_goal,
			"target": codec.call("encode", target) if is_instance_valid(target) else null,
			"bite": node._bite_cooldown, "recoil": node._recoil, "decay": node._decay,
			"striker": node.last_striker_owner,
		})
	return {"walk_home": [walk_home[0], walk_home[1]], "rows": rows}


func _restore(saved: Dictionary, codec: RefCounted) -> void:
	for node: WildlifeNode in nodes.duplicate():
		if is_instance_valid(node):
			_remove(node)
			node.free()
	nodes.clear()
	by_id.clear()
	var saved_assist: Variant = saved.get("walk_home")
	if saved_assist is Array and saved_assist.size() == 2:
		walk_home[0] = bool(saved_assist[0])
		walk_home[1] = bool(saved_assist[1])
	var saved_rows: Variant = saved.get("rows")
	if not saved_rows is Array:
		return
	for row: Variant in saved_rows:
		if not row is Dictionary or not str(row.get("kind", "")) in KIND_CODES or not row.get("position") is Vector2:
			continue
		var node: WildlifeNode = spawn(int(row.get("wid", -1)), str(row.kind), row.position, int(row.get("owner", -1)))
		codec.call("bind", int(row.get("id", 0)), node)
		node.total_amount = maxi(1, int(row.get("total", node.total_amount)))
		node.remaining = clampi(int(row.get("remaining", node.total_amount)), 1, node.total_amount)
		node.pasture_owner = int(row.get("pasture_owner", node.owner_id))
		node.max_hp = float(row.get("max_hp", node.max_hp))
		node.hp = float(row.get("hp", node.max_hp))
		node.home_position = row.get("home", row.position)
		node.manual_stay = bool(row.get("manual_stay", false))
		node.last_striker_owner = int(row.get("striker", -1))
		node._bite_cooldown = float(row.get("bite", 0.0))
		node._recoil = float(row.get("recoil", 0.0))
		node._decay = float(row.get("decay", 0.0))
		node.phase = int(row.get("phase", WildlifeNode.Phase.ALIVE))
		node.mood = int(row.get("mood", WildlifeNode.Mood.CALM)) if node.phase == WildlifeNode.Phase.ALIVE else WildlifeNode.Mood.CALM
		var target: Variant = codec.call("decode", row.get("target"))
		if node.mood == WildlifeNode.Mood.ENRAGED and target is UnitBase:
			node._target_ref = weakref(target)
		if bool(row.get("has_goal", false)) and row.get("goal") is Vector2 and node.phase == WildlifeNode.Phase.ALIVE:
			node.walk_to(row.goal)
		node._refresh_texture()
		node.queue_redraw()
