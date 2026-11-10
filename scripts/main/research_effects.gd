class_name ResearchEffects
extends RefCounted
## Round 2 workstream B: how finished research reaches the world.
##
## GameManager owns the rules (timed slots, payments, the modifier registry);
## this file turns registry values into unit and building stats, keeps the
## tier chevrons and age dressing in step, and carries research state through
## the Phase-0 seams (network snapshot section + command, save finalize).
## Everything is static; `install(main)` is the one line main calls.

const SECTION: String = "research"
const TIER_BADGE_NAME: String = "TierBadge"
const AGE_CEREMONY_SCRIPT: Script = preload("res://scripts/ui/age_ceremony.gd")


static func install(main: Node) -> void:
	main.ext.register_command("cancel_research", _cancel_command, func(packet: Dictionary) -> bool: return packet.has("target"))
	main.ext.register_snapshot(SECTION, _snapshot_for.bind(main), _apply_snapshot.bind(main))
	main.ext.register_save(SECTION, _capture, _restore, _finalize_restore.bind(main))


# --- Stats from the registry -------------------------------------------------

static func gather_multiplier(player_id: int, resource_type: String, target: Node) -> float:
	## Research factor for one villager gather tick (civilization is separate).
	var total: float = 1.0 + GameManager.get_modifier(player_id, "gather_all")
	if resource_type == "wood":
		total += GameManager.get_modifier(player_id, "gather_wood")
	elif resource_type == "gold":
		total += GameManager.get_modifier(player_id, "gather_gold")
	elif resource_type == "food" and target is BuildingBase:
		total += GameManager.get_modifier(player_id, "gather_food_farm")
	return maxf(0.0, total)


static func villager_carry_capacity(player_id: int) -> int:
	return int(round(float(UnitData.VILLAGER_CARRY_CAPACITY) * GameManager.get_modifier_multiplier(player_id, "carry")))


static func apply_unit_bonuses(unit: UnitBase) -> void:
	## Called once when a unit loads its data stats (spawn and replicas):
	## adds what research already bought. Attack and armor stay dynamic in Combat.
	var owner: int = unit.player_owner
	if unit.unit_type == UnitData.UnitType.VILLAGER:
		unit.max_hp += GameManager.get_modifier(owner, "villager_hp")
		unit.hp = unit.max_hp
		unit.speed *= GameManager.get_modifier_multiplier(owner, "villager_speed")
		unit.set("carry_capacity", villager_carry_capacity(owner))
	elif unit.unit_type == UnitData.UnitType.ARCHER:
		unit.attack_range += MapData.range_tiles_to_world(GameManager.get_modifier(owner, "range_ranged"))
	refresh_tier_badge(unit)


static func apply_building_bonuses(building: BuildingBase) -> void:
	## Called once when a building loads its data stats.
	var owner: int = building.player_owner
	if building.tower_attack_damage > 0:
		building.tower_attack_range += MapData.range_tiles_to_world(GameManager.get_modifier(owner, "range_ranged"))
	if building.building_type == BuildingData.BuildingType.WATCH_TOWER:
		building.max_hp += int(GameManager.get_modifier(owner, "tower_hp"))
		building.tower_attack_damage += int(GameManager.get_modifier(owner, "tower_damage"))
	if GameManager.get_player_age(owner) > 1:
		building.set_age_dressing.call_deferred(GameManager.get_player_age(owner))


static func on_research_completed(main: Node, player_id: int, research_id: String) -> void:
	## Authority: bring living units and standing buildings up to date.
	if player_id < 0 or player_id >= main._player_units.size():
		return
	var definition: Dictionary = TechData.get_research_definition(research_id)
	var effects: Dictionary = definition.get("effects", {})
	var tier: Dictionary = definition.get("tier", {})
	for unit: Variant in main._player_units[player_id]:
		if not is_instance_valid(unit) or unit.current_state == UnitBase.State.DEAD:
			continue
		if unit.unit_type == UnitData.UnitType.VILLAGER:
			var hp_bonus: float = float(effects.get("villager_hp", 0.0))
			unit.max_hp += hp_bonus
			unit.hp += hp_bonus
			if effects.has("carry"):
				unit.set("carry_capacity", villager_carry_capacity(player_id))
			if effects.has("villager_speed"):
				unit.speed = float(UnitData.get_unit_stats(unit.unit_type, player_id).get("speed", unit.speed)) * GameManager.get_modifier_multiplier(player_id, "villager_speed")
		elif unit.unit_type == UnitData.UnitType.ARCHER and effects.has("range_ranged"):
			unit.attack_range += MapData.range_tiles_to_world(float(effects["range_ranged"]))
		if not tier.is_empty() and unit.unit_type == int(tier["unit_type"]):
			upgrade_unit_tier(unit)
	for building: Variant in main._player_buildings[player_id]:
		if not is_instance_valid(building) or building.state == BuildingBase.State.DESTROYED:
			continue
		if effects.has("range_ranged") and building.tower_attack_damage > 0:
			building.tower_attack_range += MapData.range_tiles_to_world(float(effects["range_ranged"]))
		if building.building_type == BuildingData.BuildingType.WATCH_TOWER:
			var hp_bonus: int = int(effects.get("tower_hp", 0.0))
			if hp_bonus != 0:
				building.max_hp += hp_bonus
				# A foundation's HP follows its build progress; give it the same share.
				building.hp += hp_bonus if building.state == BuildingBase.State.ACTIVE else int(hp_bonus * building.build_progress)
			building.tower_attack_damage += int(effects.get("tower_damage", 0.0))
			building.queue_redraw()
	if player_id == 0 and main.get("hud") != null:
		main.hud.show_notification("Research complete: %s" % str(definition.get("name", research_id)), Color(0.5, 0.8, 1.0))


static func upgrade_unit_tier(unit: UnitBase) -> void:
	## Re-reads the line's (now higher tier) data stats, keeping the HP ratio.
	var stats: Dictionary = UnitData.get_unit_stats(unit.unit_type, unit.player_owner)
	var ratio: float = clampf(unit.hp / unit.max_hp, 0.0, 1.0) if unit.max_hp > 0.0 else 1.0
	unit.max_hp = float(stats.get("hp", unit.max_hp))
	unit.hp = maxf(1.0, round(unit.max_hp * ratio)) if ratio > 0.0 else 0.0
	unit.damage = float(stats.get("damage", unit.damage))
	unit.armor = float(stats.get("armor", unit.armor))
	refresh_tier_badge(unit)
	unit.queue_redraw()


# --- Presentation: tier chevrons and age dressing ---------------------------

static func refresh_tier_badge(unit: UnitBase) -> void:
	var tier: int = UnitData.get_unit_tier(unit.unit_type, unit.player_owner)
	var badge: Sprite2D = unit.get_node_or_null(TIER_BADGE_NAME) as Sprite2D
	var icon_path: String = str(UnitData.TIER_ICONS.get(tier, ""))
	if tier <= 1 or icon_path.is_empty() or not ResourceLoader.exists(icon_path):
		if badge != null:
			badge.visible = false
		return
	if badge == null:
		badge = Sprite2D.new()
		badge.name = TIER_BADGE_NAME
		badge.z_index = 1
		# Beside the feet on the unit's right, clear of the health bar and body.
		badge.position = Vector2(float(UnitBase.UNIT_SIZES.get(unit.unit_type, 10.0)) + 1.0, -5.0)
		badge.scale = Vector2(0.5, 0.5)
		unit.add_child(badge)
	badge.texture = load(icon_path)
	badge.visible = true


static func refresh_presentation(main: Node) -> void:
	## Re-derives every chevron and banner from current state (after a save is
	## restored, or when a client learns new tiers or ages).
	for player_id: int in main._player_units.size():
		for unit: Variant in main._player_units[player_id]:
			if is_instance_valid(unit):
				refresh_tier_badge(unit)
	for player_id: int in main._player_buildings.size():
		for building: Variant in main._player_buildings[player_id]:
			if is_instance_valid(building):
				building.set_age_dressing(GameManager.get_player_age(player_id))


static func on_age_advanced(main: Node, player_id: int, new_age: int) -> void:
	## The age-up moment: banners and a brief golden glow on that player's
	## buildings; the local player also gets the on-screen banner.
	if player_id < 0 or player_id >= main._player_buildings.size():
		return
	for building: Variant in main._player_buildings[player_id]:
		if is_instance_valid(building) and building.visible:
			building.set_age_dressing(new_age, true)
		elif is_instance_valid(building):
			building.set_age_dressing(new_age)
	if player_id == 0 and main.get("hud") != null:
		AGE_CEREMONY_SCRIPT.play(main.hud, new_age)


# --- Network seam -----------------------------------------------------------

static func _cancel_command(owner: int, _packet: Dictionary, _units: Array, target: Node2D, _position: Vector2) -> String:
	if not target is BuildingBase or target.player_owner != owner:
		return "Select your building"
	return "" if GameManager.cancel_research(owner, target) else "Nothing to cancel"


static func _snapshot_for(slot: int, main: Node) -> Variant:
	## Owner-only research slots, plus what the recipient can see of the other
	## side: the tier of unit lines with a visible unit, and the age when a
	## Town Center is in sight (for chevrons and banners only).
	var rows: Array = []
	for building: Variant in main._player_buildings[slot]:
		if is_instance_valid(building) and not building.research_id.is_empty():
			rows.append([NetworkSession.entity_id(building), building.research_id, building.research_progress, building.research_duration])
	var data: Dictionary = {"rows": rows}
	var enemy: int = 1 - slot
	var enemy_tiers: Dictionary = {}
	for unit_type: int in UnitData.UNIT_TIERS:
		if UnitData.get_unit_tier(unit_type, enemy) > 1:
			enemy_tiers[unit_type] = false
	if not enemy_tiers.is_empty():
		var pending: int = enemy_tiers.size()
		for unit: Variant in main._player_units[enemy]:
			if pending <= 0:
				break
			if is_instance_valid(unit) and enemy_tiers.get(unit.unit_type) == false and main.game_map.is_entity_visible_to_player(unit, slot):
				enemy_tiers[unit.unit_type] = true
				pending -= 1
		var seen: Array = []
		for unit_type: int in enemy_tiers:
			if enemy_tiers[unit_type]:
				seen.append([unit_type, UnitData.get_unit_tier(unit_type, enemy)])
		if not seen.is_empty():
			data["tiers"] = seen
	if GameManager.get_player_age(enemy) > 1:
		for building: Variant in main._player_buildings[enemy]:
			if is_instance_valid(building) and building.building_type == BuildingData.BuildingType.TOWN_CENTER and main.game_map.is_entity_visible_to_player(building, slot):
				data["enemy_age"] = GameManager.get_player_age(enemy)
				break
	return data


static func _apply_snapshot(data: Variant, main: Node) -> void:
	## Client: own buildings are local player 0, the opponent is local player 1.
	if not data is Dictionary:
		return
	var by_id: Dictionary = {}
	for row: Variant in data.get("rows", []):
		if row is Array and row.size() == 4:
			by_id[int(row[0])] = row
	for building: Variant in main._player_buildings[0]:
		if not is_instance_valid(building):
			continue
		var row: Variant = by_id.get(NetworkSession.entity_id(building))
		if row == null:
			if not building.research_id.is_empty():
				building.clear_research()
			continue
		building.research_id = str(row[1])
		building.research_progress = float(row[2])
		building.research_duration = float(row[3])
	for entry: Variant in data.get("tiers", []):
		if entry is Array and entry.size() == 2 and UnitData.UNIT_TIERS.has(int(entry[0])):
			GameManager.set_modifier(1, UnitData.tier_modifier_key(int(entry[0])), float(entry[1]))
	if data.has("enemy_age") and GameManager.players.has(1):
		GameManager.players[1]["age"] = clampi(int(data["enemy_age"]), 1, GameManager.MAX_AGE)
	# Clients get no authority signals: notice changes and present them here.
	var signature: Array = [GameManager.get_player_age(0), GameManager.get_player_age(1), GameManager.researched_upgrades.get(0, []).size()]
	for unit_type: int in UnitData.UNIT_TIERS:
		signature.append(UnitData.get_unit_tier(unit_type, 0))
		signature.append(UnitData.get_unit_tier(unit_type, 1))
	var previous: Variant = main.get_meta("research_presentation") if main.has_meta("research_presentation") else null
	if previous == signature:
		return
	main.set_meta("research_presentation", signature)
	if previous is Array:
		for player_id: int in 2:
			if int(signature[player_id]) > int(previous[player_id]):
				on_age_advanced(main, player_id, int(signature[player_id]))
		var researched: Array = GameManager.researched_upgrades.get(0, [])
		if int(signature[2]) > int(previous[2]) and not researched.is_empty() and main.get("hud") != null:
			main.hud.show_notification("Research complete: %s" % TechData.get_research_name(str(researched[-1])), Color(0.5, 0.8, 1.0))
	refresh_presentation(main)


# --- Save seam --------------------------------------------------------------
# The slot itself travels in BUILDING_FIELDS and tiers in the modifier registry;
# this section only re-derives presentation once everything is restored.

static func _capture(_codec: RefCounted) -> Dictionary:
	return {"version": 1}


static func _restore(_saved: Dictionary, _codec: RefCounted) -> void:
	pass


static func _finalize_restore(_saved: Dictionary, _codec: RefCounted, main: Node) -> void:
	refresh_presentation(main)
