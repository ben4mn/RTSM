class_name FarmPlots
extends Node
## Round 2 E: finite Farms.
##
## A sown Farm holds BuildingData "farm_food" (plus the researched `farm_food`
## registry bonus, Horse Collar). When the last food is taken it lies fallow:
## it yields nothing, its farmer delivers what he carries and stands idle, and
## the field shows stubble and a reseed prompt. Reseeding costs BuildingData
## "reseed_cost" (a kingdom's Farm discount applies) and recalls that farmer.
##
##   Player:  give a Villager the fallow Farm as a gather order (the order
##            reseeds it), or select the Farm and tap "Reseed".
##   Assist:  "Auto-reseed" on any Farm's row, off by default. While on, a
##            Farm that runs out is replanted at once from the bank; if the
##            bank is short it waits fallow and is replanted when wood arrives.
##   AI:      FarmPlots.reseed(farm) / set_auto_reseed(player, true).
##
## State is four plain BuildingBase fields (saved through BUILDING_FIELDS):
## `farm_food_total`, `farm_food_remaining`, `farm_fallow`, `_farm_last_worker_ref`.
## The toggle is the registry key `farm_auto_reseed` (saved, and replicated to
## its owner with the other modifiers). Clients receive the ext snapshot
## section `farms`. Everything else here is static rules; the one node per
## match retries prepaid reseeds and listens for Horse Collar.

const ACTION_RESEED: String = "farm:reseed"
const ACTION_AUTO: String = "farm:auto"
const AUTO_KEY: String = "farm_auto_reseed"
const BONUS_KEY: String = "farm_food"
const SECTION: String = "farms"
const ICON_RESEED: String = "res://assets/ui/icons/reseed.svg"
const ICON_AUTO: String = "res://assets/ui/icons/reseed_auto.svg"
const OVERLAY_TEXTURE: String = "res://assets/buildings/farm_fallow.svg"
const OVERLAY_NAME: String = "FallowOverlay"
const PROMPT_NAME: String = "ReseedPrompt"
## The painted field dries out under the stubble overlay.
const FALLOW_TINT: Color = Color(0.84, 0.76, 0.62)
## World size of the overlay: the Farm's 2x2 ground diamond.
const OVERLAY_SIZE: Vector2 = Vector2(MapData.TILE_WIDTH * 2.0, MapData.TILE_HEIGHT * 2.0) * 0.9
## How often a prepaid reseed that could not be afforded is tried again.
const RETRY_SECONDS: float = 2.0

static var _director_ref: WeakRef = null
static var _texture_cache: Dictionary = {}

var main: Node = null
var _retry: float = 0.0
var _hint_shown: bool = false


# =============================================================================
#  Installation (one line in main._register_match_extensions)
# =============================================================================

static func install(match_main: Node) -> void:
	BuildingBase.register_context_provider("farm", _context_actions, _perform_context_action)
	var director := FarmPlots.new()
	director.name = "FarmPlotsDirector"
	director.main = match_main
	match_main.add_child(director)
	_director_ref = weakref(director)
	if not GameManager.research_completed.is_connected(director._on_research_completed):
		GameManager.research_completed.connect(director._on_research_completed)
	var extensions: RefCounted = match_main.get("ext") as RefCounted
	if extensions == null:
		return
	extensions.register_snapshot(SECTION, director._snapshot_rows, director._apply_snapshot_rows)
	extensions.register_save(SECTION, director._capture_save, director._restore_save, director._finalize_save)


static func get_director() -> FarmPlots:
	var director: FarmPlots = _director_ref.get_ref() as FarmPlots if _director_ref != null else null
	return director if is_instance_valid(director) else null


# =============================================================================
#  Rules
# =============================================================================

static func is_farm(node: Variant) -> bool:
	return is_instance_valid(node) and node is BuildingBase and (node as BuildingBase).building_type == BuildingData.BuildingType.FARM


static func is_fallow(node: Variant) -> bool:
	return is_farm(node) and (node as BuildingBase).farm_fallow


static func capacity_for(player_id: int) -> int:
	## Food a Farm sown now by this player holds.
	var base: int = int(BuildingData.BUILDINGS[BuildingData.BuildingType.FARM].get("farm_food", 0))
	return maxi(1, base + int(GameManager.get_modifier(player_id, BONUS_KEY)))


static func reseed_cost(farm: BuildingBase) -> Dictionary:
	return BuildingData.get_reseed_cost(BuildingData.BuildingType.FARM, farm.player_owner)


static func is_auto_reseed(player_id: int) -> bool:
	return GameManager.get_modifier(player_id, AUTO_KEY) >= 0.5


static func set_auto_reseed(player_id: int, enabled: bool) -> void:
	GameManager.set_modifier(player_id, AUTO_KEY, 1.0 if enabled else 0.0)
	if enabled:
		_reseed_waiting_farms(player_id)


static func ensure_sown(farm: BuildingBase) -> void:
	## A finished Farm is sown the first time anything asks about its food.
	if farm.farm_food_total <= 0 and not farm.farm_fallow:
		sow(farm)


static func sow(farm: BuildingBase) -> void:
	farm.farm_food_total = capacity_for(farm.player_owner)
	farm.farm_food_remaining = farm.farm_food_total
	farm.farm_fallow = false
	refresh_look(farm)


static func take(farm: BuildingBase, amount: int, worker: UnitBase = null) -> int:
	## The Farm's side of a harvest tick: hands out what is left and goes
	## fallow (or is replanted at once by a prepaid Auto-reseed) at zero.
	if amount <= 0 or farm.farm_fallow:
		return 0
	ensure_sown(farm)
	var taken: int = mini(amount, farm.farm_food_remaining)
	farm.farm_food_remaining -= taken
	if farm.farm_food_remaining <= 0:
		_exhaust(farm, worker)
	return taken


static func _exhaust(farm: BuildingBase, worker: UnitBase) -> void:
	farm.farm_food_remaining = 0
	farm.farm_fallow = true
	farm._farm_last_worker_ref = weakref(worker) if is_instance_valid(worker) else null
	if is_auto_reseed(farm.player_owner) and reseed(farm, false).is_empty():
		return  # Prepaid: the farmer never stops.
	refresh_look(farm)
	var director: FarmPlots = get_director()
	if director != null:
		director._announce_fallow(farm)


static func reseed(farm: BuildingBase, recall_farmer: bool = true) -> String:
	## Authority side. "" on success, otherwise a short player-facing reason.
	if not is_farm(farm) or farm.state != BuildingBase.State.ACTIVE:
		return "Farm unavailable"
	if not farm.farm_fallow:
		return "This Farm is still growing"
	var cost: Dictionary = reseed_cost(farm)
	if not ResourceManager.try_spend(farm.player_owner, cost):
		return _missing_text(farm.player_owner, cost)
	sow(farm)
	if recall_farmer:
		_recall_farmer(farm)
	return ""


static func _missing_text(player_id: int, cost: Dictionary) -> String:
	var missing: Dictionary = ResourceManager.get_missing_resources(player_id, cost)
	for resource: String in ["wood", "food", "gold"]:
		if int(missing.get(resource, 0)) > 0:
			return "Need %d %s to reseed" % [int(cost.get(resource, 0)), resource]
	return "Cannot reseed yet"


static func _recall_farmer(farm: BuildingBase) -> void:
	## The farmer who emptied the field goes back to it if he is still idle.
	var worker: Villager = farm._farm_last_worker_ref.get_ref() as Villager if farm._farm_last_worker_ref != null else null
	farm._farm_last_worker_ref = null
	if not is_instance_valid(worker) or worker.player_owner != farm.player_owner or not worker.is_inside_tree():
		return
	if worker.current_state == UnitBase.State.IDLE and farm.is_available_to_worker(worker):
		worker.command_gather(farm)


static func _reseed_waiting_farms(player_id: int) -> void:
	var director: FarmPlots = get_director()
	if director == null or NetworkSession.is_client():
		return
	for farm: BuildingBase in director._farms_of(player_id):
		if farm.farm_fallow and farm.state == BuildingBase.State.ACTIVE and not reseed(farm).is_empty():
			return  # The bank is short; the rest wait too.


static func prepare_player_gather(match_main: Node, node: Variant) -> bool:
	## The one call from main._on_gather_command: ordering a Villager onto a
	## fallow Farm reseeds it first. False = the order cannot go ahead (the
	## reason is already on screen).
	if not is_fallow(node) or (node as BuildingBase).player_owner != 0:
		return true
	var farm := node as BuildingBase
	var selection: Variant = match_main.get("game_map").selection_mgr.selected if is_instance_valid(match_main.get("game_map")) else []
	var has_villager: bool = false
	for entry: Variant in selection:
		if is_instance_valid(entry) and entry is Villager and (entry as Villager).player_owner == 0:
			has_villager = true
			break
	if not has_villager:
		return true
	if NetworkSession.is_client():
		NetworkSession.send_command("building_action", {"target": NetworkSession.entity_id(farm), "action": ACTION_RESEED})
		return true
	var reason: String = reseed(farm, false)
	if reason.is_empty():
		return true
	var hud: Node = match_main.get("hud") as Node
	if is_instance_valid(hud) and hud.has_method("show_notification"):
		hud.call("show_notification", reason, KingdomTheme.RUST)
	return false


# =============================================================================
#  HUD copy and cards
# =============================================================================

static func summary(farm: BuildingBase, show_stock: bool) -> String:
	## First line of the selection card. Stock is the owner's knowledge.
	if farm.farm_fallow:
		return "Fallow"
	if not show_stock:
		return "Farm"
	ensure_sown(farm)
	return "%d / %d food" % [farm.farm_food_remaining, farm.farm_food_total]


static func information(farm: BuildingBase) -> String:
	var wood: int = int(reseed_cost(farm).get("wood", 0))
	var body: String = "A Farm holds %d food for 1 worker at a time, then lies fallow.\nReseed a fallow Farm for %d wood: send a Villager to it or tap Reseed. Auto-reseed pays from your bank as soon as a Farm runs out.\nFood must be carried to a Town Center or Resource Camp." % [capacity_for(farm.player_owner), wood]
	if farm.farm_fallow:
		body += "\nThis Farm is fallow."
	return body


static func _context_actions(building: BuildingBase, player_id: int) -> Array:
	var actions: Array = []
	if not is_farm(building) or building.state != BuildingBase.State.ACTIVE:
		return actions
	var cost: Dictionary = reseed_cost(building)
	var wood: int = int(cost.get("wood", 0))
	if building.farm_fallow:
		var short_of: bool = not ResourceManager.can_afford(player_id, cost)
		actions.append({
			"id": ACTION_RESEED, "label": "Reseed Farm", "short": "Reseed", "icon": ICON_RESEED, "cost": cost, "time": 0.0,
			"progress": -1.0, "disabled_reason": "Need %d wood" % wood if short_of else "",
			"desc": "+%d food" % capacity_for(player_id),
			"details": "Replant this fallow Farm with %d food for %d wood. Its farmer returns to work if he is still idle." % [capacity_for(player_id), wood],
		})
	var auto_on: bool = is_auto_reseed(player_id)
	actions.append({
		"id": ACTION_AUTO, "label": "Auto-reseed", "short": "Auto-reseed", "icon": ICON_AUTO, "cost": {}, "time": 0.0,
		"progress": -1.0, "disabled_reason": "", "desc": "On · %d wood" % wood if auto_on else "Off",
		"details": "Optional assist for all your Farms, off by default. While on, a Farm that runs out is replanted at once for %d wood from your bank. If the bank is short it waits fallow and is replanted when the wood arrives." % wood,
	})
	return actions


static func _perform_context_action(building: BuildingBase, player_id: int, action_id: String) -> String:
	match action_id:
		ACTION_RESEED:
			return reseed(building)
		ACTION_AUTO:
			set_auto_reseed(player_id, not is_auto_reseed(player_id))
			return ""
	return "Action unavailable"


# =============================================================================
#  Look: stubble overlay, dry tint, reseed prompt
# =============================================================================

static func field_tint(building: BuildingBase) -> Color:
	## Multiplied into the Farm sprite by BuildingBase._update_sprite_appearance.
	return FALLOW_TINT if building.farm_fallow and building.building_type == BuildingData.BuildingType.FARM else Color.WHITE


static func refresh_look(farm: BuildingBase) -> void:
	if not is_instance_valid(farm) or not farm.is_inside_tree() or NetworkSession.server_mode:
		return
	var fallow: bool = farm.farm_fallow and farm.state == BuildingBase.State.ACTIVE
	var overlay: Sprite2D = farm.get_node_or_null(OVERLAY_NAME) as Sprite2D
	if fallow and overlay == null:
		var texture: Texture2D = _texture(OVERLAY_TEXTURE)
		if texture != null:
			overlay = Sprite2D.new()
			overlay.name = OVERLAY_NAME
			overlay.texture = texture
			overlay.scale = OVERLAY_SIZE / texture.get_size()
			overlay.position = farm._footprint_center
			farm.add_child(overlay)
	if overlay != null:
		overlay.visible = fallow
	var prompt: Prompt = farm.get_node_or_null(PROMPT_NAME) as Prompt
	var wants_prompt: bool = fallow and farm.player_owner == 0
	if wants_prompt and prompt == null:
		prompt = Prompt.new()
		prompt.name = PROMPT_NAME
		prompt.farm = farm
		prompt.z_index = 2
		farm.add_child(prompt)
	if prompt != null:
		prompt.visible = wants_prompt
	if farm._sprite != null:
		farm._update_sprite_appearance()


static func _texture(path: String) -> Texture2D:
	if not _texture_cache.has(path):
		_texture_cache[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _texture_cache[path] as Texture2D


## The small "reseed" plate over the local player's fallow Farm.
class Prompt extends Node2D:
	var farm: BuildingBase = null
	const DRAW_SCALE: float = 1.3

	func _init() -> void:
		scale = Vector2(DRAW_SCALE, DRAW_SCALE)

	func _draw() -> void:
		if not is_instance_valid(farm):
			return
		var anchor := Vector2(farm._footprint_center.x, farm._footprint_center.y - 26.0) / DRAW_SCALE
		var ink := Color("1d2b2c")
		var gold := Color("e8bf77")
		draw_circle(anchor + Vector2(0.0, 1.5), 11.5, Color(0.0, 0.0, 0.0, 0.25))
		draw_circle(anchor, 11.0, Color(ink, 0.94))
		draw_arc(anchor, 11.0, 0.0, TAU, 28, gold, 1.6, true)
		var texture: Texture2D = FarmPlots._texture(FarmPlots.ICON_RESEED)
		if texture != null:
			draw_texture_rect(texture, Rect2(anchor - Vector2(7.5, 7.5), Vector2(15.0, 15.0)), false)
		else:
			draw_line(anchor + Vector2(0.0, 5.0), anchor + Vector2(0.0, -4.0), Color("e8e5db"), 2.0)
			draw_line(anchor + Vector2(0.0, -1.0), anchor + Vector2(-5.0, -5.0), Color("e8e5db"), 2.0)
			draw_line(anchor + Vector2(0.0, -2.0), anchor + Vector2(5.0, -6.0), Color("e8e5db"), 2.0)


# =============================================================================
#  Director: prepaid retries, Horse Collar, first-time hint
# =============================================================================

func _farms_of(player_id: int) -> Array[BuildingBase]:
	var farms: Array[BuildingBase] = []
	var rosters: Variant = main.get("_player_buildings") if is_instance_valid(main) else null
	if not rosters is Array or player_id < 0 or player_id >= (rosters as Array).size():
		return farms
	for entry: Variant in rosters[player_id]:
		if is_farm(entry) and not (entry as BuildingBase).is_queued_for_deletion():
			farms.append(entry as BuildingBase)
	return farms


func _process(delta: float) -> void:
	if not is_instance_valid(main) or NetworkSession.is_client() or GameManager.current_state != GameManager.GameState.PLAYING:
		return
	_retry += delta
	if _retry < RETRY_SECONDS:
		return
	_retry = 0.0
	for player_id: int in 2:
		if is_auto_reseed(player_id):
			_reseed_waiting_farms(player_id)


func _on_research_completed(player_id: int, research_id: String) -> void:
	## Horse Collar: sown Farms gain the bonus on the spot; later sowings read
	## the registry.
	if NetworkSession.is_client():
		return
	var bonus: int = int((TechData.get_research_definition(research_id).get("effects", {}) as Dictionary).get(BONUS_KEY, 0))
	if bonus <= 0:
		return
	for farm: BuildingBase in _farms_of(player_id):
		if farm.state == BuildingBase.State.ACTIVE and not farm.farm_fallow and farm.farm_food_total > 0:
			farm.farm_food_total += bonus
			farm.farm_food_remaining += bonus


func _announce_fallow(farm: BuildingBase) -> void:
	## Once per match: tell the local player what the stubble means.
	if _hint_shown or farm.player_owner != 0 or NetworkSession.server_mode or not is_instance_valid(main):
		return
	var hud: Node = main.get("hud") as Node
	if not is_instance_valid(hud) or not hud.has_method("show_notification"):
		return
	_hint_shown = true
	hud.call("show_notification", "Farm fallow · send its farmer back to reseed (%d wood)" % int(reseed_cost(farm).get("wood", 0)), KingdomTheme.GOLD, 6.0)


# =============================================================================
#  Network snapshot and solo save
# =============================================================================

func _snapshot_rows(slot: int) -> Variant:
	## Own Farms: [id, fallow 0/1, remaining, total]. A rival's visible fallow
	## Farm: [id, 1] (the stubble is plain to see; its stock is not).
	if not is_instance_valid(main):
		return null
	var rows: Array = []
	var map: Node = main.get("game_map") as Node
	for owner: int in 2:
		for farm: BuildingBase in _farms_of(owner):
			if farm.state != BuildingBase.State.ACTIVE:
				continue
			var id: int = NetworkSession.entity_id(farm)
			if id <= 0:
				continue
			if owner == slot:
				ensure_sown(farm)
				rows.append([id, 1 if farm.farm_fallow else 0, farm.farm_food_remaining, farm.farm_food_total])
			elif farm.farm_fallow and is_instance_valid(map) and bool(map.call("is_entity_visible_to_player", farm, slot)):
				rows.append([id, 1])
	return rows


func _apply_snapshot_rows(rows: Variant) -> void:
	if not is_instance_valid(main) or not NetworkSession.is_client():
		return
	var adapter: Node = NetworkSession.adapter
	var entities: Dictionary = adapter.get("entities") if is_instance_valid(adapter) else {}
	var listed: Dictionary = {}
	if rows is Array:
		for row: Variant in rows:
			if row is Array and row.size() >= 2 and is_farm(entities.get(int(row[0]))):
				listed[entities.get(int(row[0]))] = row
	for owner: int in 2:
		for farm: BuildingBase in _farms_of(owner):
			var row: Array = listed.get(farm, [0, 0])
			var fallow: bool = int(row[1]) == 1
			if row.size() >= 4:
				farm.farm_food_remaining = int(row[2])
				farm.farm_food_total = int(row[3])
			if fallow != farm.farm_fallow:
				farm.farm_fallow = fallow
				refresh_look(farm)


func _capture_save(_codec: RefCounted) -> Dictionary:
	## Farm state is plain BuildingBase fields; this entry asks for the
	## finalize pass that redraws the fallow fields.
	return {"version": 1}


func _restore_save(_saved: Dictionary, _codec: RefCounted) -> void:
	pass


func _finalize_save(_saved: Dictionary, _codec: RefCounted) -> void:
	for owner: int in 2:
		for farm: BuildingBase in _farms_of(owner):
			refresh_look(farm)
