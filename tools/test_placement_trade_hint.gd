extends Node
## Real placement component and BuildingBase Town Centers, with a bounded map
## policy. Geometry hints must never query routes or become purchase rules.
var checks: int = 0
var failures: Array[String] = []
var changes: int = 0
var confirmations: int = 0
var world: PreviewWorld
var placement: BuildingPlacement
const ANCHOR := Vector2i(20, 20)

class PreviewWorld extends Node2D:
	var terrain := TileMapLayer.new()
	var sight_hidden: bool = false
	var blocked: Dictionary = {}
	var terrain_queries: int = 0
	var route_queries: int = 0
	func _ready() -> void:
		terrain.name = "TerrainLayer"
		terrain.tile_set = TilesetBuilder.build_terrain_tileset()
		add_child(terrain)
	func tile_to_world(tile: Vector2i) -> Vector2: return terrain.map_to_local(tile)
	func world_to_tile(point: Vector2) -> Vector2i: return terrain.local_to_map(point)
	func is_tile_visible_to_player(_tile: Vector2i, _owner: int = 0) -> bool: return not sight_hidden
	func is_tile_buildable(tile: Vector2i) -> bool:
		terrain_queries += 1
		return not blocked.has(tile)
	func get_building_dropoff_world_path(_from: Vector2, _to: Vector2, _size: Vector2i, _radius: float) -> PackedVector2Array:
		route_queries += 1
		return PackedVector2Array()

func _ready() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _town(parent: Node, tile: Vector2i, owner: int, complete: bool) -> BuildingBase:
	var town := BuildingBase.new()
	town.building_type = BuildingData.BuildingType.TOWN_CENTER
	town.player_owner = owner
	town.position = world.tile_to_world(tile)
	parent.add_child(town)
	town.set_process(false)
	if complete: town.complete_instantly()
	else: town.start_construction()
	return town
func _start(type: int = BuildingData.BuildingType.TRADE_POST) -> void:
	placement.start_placement(type, 0)
	placement.set_process(false)
	placement.update_preview_at_world(world.tile_to_world(ANCHOR))
func _refresh() -> void: placement._process(0.13)
func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	ResourceManager.reset()
	ResourceManager.initialize_player(0, {"food": 400, "wood": 600, "gold": 200})
	var bank: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	world = PreviewWorld.new()
	add_child(world)
	placement = BuildingPlacement.new()
	world.add_child(placement)
	placement.preview_changed.connect(func(_valid: bool, _reason: String) -> void: changes += 1)
	placement.placement_confirmed.connect(func(_type: int, _position: Vector2) -> void: confirmations += 1)
	var close_town: BuildingBase = _town(world, Vector2i(15, 15), 0, true)
	var far_town: BuildingBase = _town(world, Vector2i(40, 40), 0, false)
	_town(world, Vector2i(80, 80), 1, true)
	var outside := Node2D.new()
	add_child(outside)
	_town(outside, Vector2i(70, 70), 0, true)
	await get_tree().process_frame
	_start()
	check(placement.is_valid_placement, "close post still fits physically")
	check(placement.get_preview_state_label() == "Too near town" and placement.get_preview_hint() == "Move farther from town", "nearby TC warns before200wood purchase")
	check(ResourceManager.get_all_resources(0) == bank, "preview does not spend")
	check(placement.confirm_preview() and confirmations == 1, "distance warning permits an otherwise legal placement request")
	check(ResourceManager.get_all_resources(0) == bank, "confirmation component only emits a request and never spends itself")
	_start()
	var previous: int = changes
	far_town.complete_instantly()
	_refresh()
	check(placement.get_preview_state_label() == "Up to 25 gold" and placement.get_preview_hint() == "Up to 25 gold / trip · clear road needed", "completed owned TC makes provisional income discoverable")
	check(changes > previous, "TC completion refreshes listeners with stationary ghost")
	previous = changes
	far_town.position = world.tile_to_world(Vector2i(50, 50))
	_refresh()
	check(placement.get_preview_state_label() == "Up to 38 gold" and placement.get_preview_hint().begins_with("Up to 38 gold / trip"), "moved own TC updates payout geometry")
	check(changes > previous, "TC move refreshes listeners with stationary ghost")
	previous = changes
	far_town.state = BuildingBase.State.DESTROYED
	_refresh()
	check(placement.get_preview_state_label() == "Too near town", "destroyed distant TC no longer offers income")
	check(changes > previous, "TC destruction refreshes listeners")
	close_town.state = BuildingBase.State.DESTROYED
	_refresh()
	check(placement.get_preview_state_label() == "Needs town" and placement.get_preview_hint() == "Needs a Town Center", "enemy and other-world TCs cannot satisfy missing home")
	var cap_town: BuildingBase = _town(world, Vector2i(70, 70), 0, false)
	_refresh()
	check(placement.get_preview_hint() == "Needs a Town Center", "unfinished own TC cannot promise trade")
	cap_town.complete_instantly()
	_refresh()
	check(placement.get_preview_state_label() == "Up to 60 gold", "placement respects shared60gold cap")
	world.blocked[ANCHOR] = true
	_refresh()
	check(not placement.is_valid_placement and placement.get_preview_state_label() == "Blocked", "physical collision takes precedence over payout")
	check(placement.get_preview_hint() == placement.get_invalid_reason() and not placement.get_preview_hint().contains("gold"), "invalid footprint exposes only physical reason")
	world.sight_hidden = true
	world.terrain_queries = 0
	_refresh()
	check(not placement.is_valid_placement and placement.get_preview_state_label() == "Needs sight", "fog takes precedence over physical and trade feedback")
	check(placement.get_preview_hint() == BuildingPlacement.FOG_INVALID_REASON and world.terrain_queries == 0, "hidden footprint is rejected before detailed terrain queries")
	world.sight_hidden = false
	world.blocked.clear()
	_refresh()
	check(placement.get_preview_hint() == "Up to 60 gold / trip · clear road needed" and world.route_queries == 0, "blocked or unknown routes are never queried or promised")
	placement.cancel_placement()
	_start(BuildingData.BuildingType.HOUSE)
	check(placement.is_valid_placement and placement.get_preview_state_label() == "Fits" and placement.get_preview_hint().is_empty(), "ordinary building presentation is unchanged")
	check(ResourceManager.get_all_resources(0) == bank, "all planning and TC transitions leave bank unchanged")
	placement.cancel_placement()
	world.queue_free()
	outside.queue_free()
	await get_tree().process_frame
	print(JSON.stringify({"test": "placement_trade_hint", "checks": checks, "failures": failures, "scope": "actual native placement component and Town Centers; no route or income simulation"}))
	get_tree().quit(0 if failures.is_empty() else 1)
