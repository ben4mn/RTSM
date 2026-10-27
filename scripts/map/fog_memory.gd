extends Node2D
## Immutable last observations, rendered without actors, collision or activity.
## One record per observed resource tile/building; art is lazy and reused.
var game_map: Node2D
var resources: Dictionary = {}
var buildings: Dictionary = {}
const MEMORY_TINT := Color(0.76, 0.80, 0.87, 1.0)

func observe_resource(source: ResourceNode) -> void:
	remember_resource(source.tile_position, source.resource_type, source.remaining)

func remember_resource(tile: Vector2i, kind: String, amount: int) -> void:
	if amount <= 0: return
	if resources.has(tile):
		resources[tile].remaining = amount
		return
	resources[tile] = {"tile": tile, "footprint": Vector2i.ONE, "remaining": amount, "resource_type": kind, "visual": null}

func observe_building(source: BuildingBase) -> void:
	if source.player_owner == 0 or source.state == BuildingBase.State.DESTROYED: return
	var id: int = int(source.get_meta("network_id", source.get_instance_id()))
	remember_building({"id": id, "owner": source.player_owner, "type": source.building_type, "state": source.state, "progress": source.build_progress, "hp": source.hp, "x": source.global_position.x, "y": source.global_position.y, "source_id": source.get_instance_id()})

func remember_building(data: Dictionary) -> void:
	var id: int = int(data.id)
	var signature: Array = [int(data.owner), int(data.type), int(data.state), float(data.progress)]
	if buildings.has(id) and buildings[id].signature == signature:
		buildings[id].hp = int(data.hp)
		return
	var record: Dictionary = buildings.get(id, {"visual": null, "material": null})
	record.merge(data, true)
	record.signature = signature
	record.tile = game_map.world_to_tile(Vector2(float(data.x), float(data.y)))
	record.footprint = BuildingData.get_building_stats(int(data.type)).get("footprint", Vector2i(2, 2))
	buildings[id] = record
	if is_instance_valid(record.visual): _draw_building(record)

func _new_visual(record: Dictionary) -> Node2D:
	var visual := Node2D.new()
	visual.name = "LastSeen"
	visual.process_mode = Node.PROCESS_MODE_DISABLED
	visual.modulate = MEMORY_TINT
	visual.y_sort_enabled = true
	visual.position = game_map.tile_to_world(record.tile)
	add_child(visual)
	var sprite := Sprite2D.new()
	sprite.name = "Artwork"
	visual.add_child(sprite)
	record.visual = visual
	return visual

func _draw_resource(record: Dictionary) -> void:
	var visual: Node2D = _new_visual(record)
	var sprite: Sprite2D = visual.get_node("Artwork")
	var kind: String = record.resource_type
	var tile: Vector2i = record.tile
	var path: String = ResourceNode.WOOD_SPRITES[posmod(tile.x * 7 + tile.y * 11, ResourceNode.WOOD_SPRITES.size())] if kind == "wood" else ResourceNode.RESOURCE_SPRITES.get(kind, ResourceNode.RESOURCE_SPRITES.stone)
	sprite.texture = load(path)
	sprite.scale = ResourceNode.RESOURCE_SCALES.get(kind, Vector2.ONE)
	sprite.offset = ResourceNode.RESOURCE_OFFSETS.get(kind, Vector2.ZERO)

func _draw_building(record: Dictionary) -> void:
	var visual: Node2D = record.visual if is_instance_valid(record.visual) else _new_visual(record)
	var sprite: Sprite2D = visual.get_node("Artwork")
	var type: int = int(record.type)
	var owner: int = int(record.owner)
	sprite.texture = load(BuildingBase.get_sprite_texture_path(type, owner))
	sprite.position = BuildingBase.get_footprint_center_offset(record.footprint, game_map)
	BuildingBase.configure_art_sprite(sprite, type, record.footprint)
	var tint := Color(1.0, 0.55, 0.55) if owner != 0 and not BuildingBase.COMPANY_ENEMY_SPRITES.has(type) and not KingdomArt.is_kingdom_texture(sprite.texture) else Color.WHITE
	var frame: Node2D = visual.get_node_or_null("Frame")
	if int(record.state) == BuildingBase.State.CONSTRUCTING:
		var progress: float = float(record.progress)
		var dark: float = lerpf(0.18, 0.0, progress)
		sprite.modulate = Color(tint.r - dark, tint.g - dark, tint.b - dark, lerpf(0.4, 1.0, progress))
		if record.material == null:
			var material := ShaderMaterial.new()
			material.shader = BuildingBase.CONSTRUCTION_REVEAL_SHADER
			var ink: Vector2 = KingdomArt.vertical_uv_range(sprite.texture)
			material.set_shader_parameter("ink_top", ink.x)
			material.set_shader_parameter("ink_bottom", ink.y)
			record.material = material
		record.material.set_shader_parameter("construction_progress", progress)
		sprite.material = record.material
		if frame == null:
			frame = BuildingBase.ConstructionFrame.new()
			frame.name = "Frame"
			visual.add_child(frame)
		frame.position = sprite.position
		frame.half_width = record.footprint.x * MapData.TILE_WIDTH * 0.34
		frame.half_depth = record.footprint.y * MapData.TILE_HEIGHT * 0.30
		var bounds: Rect2 = sprite.transform * Rect2(sprite.get_rect().position + Vector2(KingdomArt.ink_rect(sprite.texture).position), Vector2(KingdomArt.ink_rect(sprite.texture).size))
		frame.full_height = 14.0 if type == BuildingData.BuildingType.FARM else clampf(bounds.size.y * 0.65, 18.0, 100.0)
		frame.stage = 0 if progress < 0.25 else 1 if progress < 0.6 else 2
		frame.show()
		frame.queue_redraw()
	else:
		sprite.modulate = tint
		sprite.material = null
		if frame != null: frame.hide()

func refresh(viewer: int = 0) -> void:
	if viewer != 0: return
	if not NetworkSession.is_client():
		for resource: Node2D in game_map.resource_nodes.values():
			if is_instance_valid(resource) and resource is ResourceNode and game_map.is_tile_visible_to_player(resource.tile_position, viewer): observe_resource(resource)
		for building: Node in game_map.get_node("BuildingsContainer").get_children():
			if building is BuildingBase and building.player_owner != viewer and game_map.is_entity_visible_to_player(building, viewer): observe_building(building)
	for tile: Vector2i in resources.keys():
		var record: Dictionary = resources[tile]
		var in_sight: bool = _in_sight(record, viewer)
		if in_sight and game_map.get_resource_node_at(tile) == null:
			_erase(resources, tile)
			continue
		_show_memory(record, not in_sight and _explored(record), false)
	for key: int in buildings.keys():
		var record: Dictionary = buildings[key]
		var in_sight: bool = _in_sight(record, viewer)
		if in_sight and not NetworkSession.is_client():
			var source: Node = instance_from_id(int(record.get("source_id", 0)))
			if not is_instance_valid(source) or source.is_queued_for_deletion() or source.state == BuildingBase.State.DESTROYED:
				_erase(buildings, key)
				continue
		_show_memory(record, not in_sight and _explored(record), true)

func _show_memory(record: Dictionary, show_art: bool, building: bool) -> void:
	if show_art and not is_instance_valid(record.visual):
		if building: _draw_building(record)
		else: _draw_resource(record)
	if is_instance_valid(record.visual): record.visual.visible = show_art

func forget_buildings(ids: Array) -> void:
	for key: Variant in ids:
		if typeof(key) in [TYPE_INT, TYPE_FLOAT]: _erase(buildings, int(key))

func _in_sight(record: Dictionary, viewer: int) -> bool:
	for dy: int in record.footprint.y:
		for dx: int in record.footprint.x:
			if game_map.is_tile_visible_to_player(record.tile + Vector2i(dx, dy), viewer): return true
	return false

func _explored(record: Dictionary) -> bool:
	for dy: int in record.footprint.y:
		for dx: int in record.footprint.x:
			if game_map.fog_of_war.is_explored(record.tile + Vector2i(dx, dy)): return true
	return false

func _erase(records: Dictionary, key: Variant) -> void:
	if not records.has(key): return
	var visual: Node2D = records[key].visual
	if is_instance_valid(visual):
		visual.hide()
		visual.queue_free()
	records.erase(key)
