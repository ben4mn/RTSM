extends Node
## Round 2 workstream B on the real Main scene: unit line tiers on the same
## UnitType. Data ratios (today's stats and the planned halved scale), names,
## living units upgrading with their HP ratio, chevrons, new recruits, the
## requirement chain, civilization-named lines, combat using the new stats,
## and the client presentation of an opponent's visible tier.

var checks: int = 0
var failures: Array[String] = []
var main: Node
var _tier_events: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)


func _wait_main() -> bool:
	for frame: int in 900:
		await get_tree().process_frame
		var scene: Node = get_tree().current_scene
		if scene != null and scene.get("_building_placement") != null:
			main = scene
			main.process_mode = Node.PROCESS_MODE_DISABLED
			return true
	check(false, "Main initialized within bounded frames")
	return false


func _building(building_type: int, offset: Vector2i) -> BuildingBase:
	var building: BuildingBase = main._spawn_building(building_type, 0, main.game_map.map_generator.get_expansion_pocket_centers()[0] + offset)
	building.complete_instantly()
	return building


func _unit(unit_type: int, owner: int, offset: Vector2) -> UnitBase:
	return main._spawn_unit(unit_type, owner, main._player_units[owner][0].global_position + offset)


func _stats(unit_type: int, owner: int, tier: int = -1) -> Array:
	var stats: Dictionary = UnitData.get_unit_stats(unit_type, owner, tier)
	return [int(stats.hp), int(stats.damage), int(stats.armor)]


func _scaled(base: Array, overlay: Dictionary) -> Array:
	return [int(round(base[0] * float(overlay.get("hp_mult", 1.0)))), int(round(base[1] * float(overlay.get("damage_mult", 1.0)))), int(round(base[2] * float(overlay.get("armor_mult", 1.0))))]


func _run() -> void:
	get_tree().current_scene = null
	AudioManager.set_all_enabled(false)
	SoloSave.set_process(false)
	GameManager.selected_map_seed = 424242
	GameManager.selected_map_archetype = 0
	GameManager.guided_opening_enabled = false
	GameManager.selected_civilization = CivilizationData.Civilization.CROWNLANDS
	GameManager.selected_opponent_civilization = CivilizationData.Civilization.VERDANT_LEAGUE
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	if not await _wait_main():
		await _finish()
		return
	GameManager.increase_population_cap(0, 40)
	GameManager.increase_population_cap(1, 40)
	GameManager.unit_tier_changed.connect(func(player_id: int, unit_type: int, tier: int) -> void: _tier_events.append([player_id, unit_type, tier]))
	_check_data()
	_check_upgrade()
	_check_civilization_and_client()
	await _finish()


func _check_data() -> void:
	var infantry: int = UnitData.UnitType.INFANTRY
	var archer: int = UnitData.UnitType.ARCHER
	var cavalry: int = UnitData.UnitType.CAVALRY
	var base_infantry: Dictionary = UnitData.UNITS[infantry]
	check(_stats(infantry, 0) == [int(base_infantry.hp), int(base_infantry.damage), int(base_infantry.armor)] and UnitData.get_unit_name(infantry, 0) == "Warrior" and not UnitData.get_unit_stats(infantry, 0).has("tier"), "an unresearched line reads its base data")
	# Ratios relative to the base line, so the spec numbers hold at either scale.
	for entry: Array in [[infantry, 2, [120, 16, 4], [150, 19, 5], [60, 8, 2], [75, 10, 3]], [infantry, 3, [120, 16, 4], [190, 23, 6], [60, 8, 2], [95, 12, 3]], [archer, 2, [70, 14, 0], [85, 17, 0], [35, 7, 0], [43, 9, 0]], [cavalry, 2, [160, 20, 2], [210, 25, 4], [80, 10, 1], [105, 13, 2]]]:
		var overlay: Dictionary = UnitData.UNIT_TIERS[entry[0]][entry[1]]
		check(_scaled(entry[2], overlay) == entry[3], "%s matches the revision 1 stats at the current scale: %s" % [overlay.name, str(_scaled(entry[2], overlay))])
		check(_scaled(entry[4], overlay) == entry[5], "%s matches the revision 2 stats at the halved scale: %s" % [overlay.name, str(_scaled(entry[4], overlay))])
		var base: Dictionary = UnitData.UNITS[entry[0]]
		check(_stats(entry[0], 0, entry[1]) == _scaled([int(base.hp), int(base.damage), int(base.armor)], overlay), "%s preview derives from today's base unit" % overlay.name)
		check(str(UnitData.get_unit_stats(entry[0], 0, entry[1]).name) == str(overlay.name), "tier preview is named " + str(overlay.name))
	check(UnitData.get_max_tier(infantry) == 3 and UnitData.get_max_tier(archer) == 2 and UnitData.get_max_tier(UnitData.UnitType.VILLAGER) == 1, "lines know their top tier")
	for tier: int in UnitData.TIER_ICONS:
		check(ResourceLoader.exists(str(UnitData.TIER_ICONS[tier])), "tier %d chevron is authored" % tier)
	var speed_same: bool = UnitData.get_unit_stats(infantry, 0, 3).speed == base_infantry.speed and UnitData.get_unit_stats(infantry, 0, 3).cost == base_infantry.cost
	check(speed_same, "a tier changes HP, attack and armor only")


func _check_upgrade() -> void:
	var infantry: int = UnitData.UnitType.INFANTRY
	ResourceManager.initialize_player(0, {"food": 5000, "wood": 5000, "gold": 5000})
	var barracks: BuildingBase = _building(BuildingData.BuildingType.BARRACKS, Vector2i.ZERO)
	var veteran: UnitBase = _unit(infantry, 0, Vector2(40, 0))
	var wounded: UnitBase = _unit(infantry, 0, Vector2(64, 0))
	var enemy: UnitBase = _unit(infantry, 1, Vector2(40, 0))
	var base: Array = _stats(infantry, 0)
	wounded.hp = wounded.max_hp * 0.5
	check(veteran.get_node_or_null("TierBadge") == null and veteran.max_hp == float(base[0]), "a base-tier Warrior has no chevron")
	check(GameManager.get_research_failure_reason(0, barracks, "man_at_arms") == "age_required" and barracks.get_context_actions(0).map(func(action: Dictionary) -> String: return action.id) == ["research:man_at_arms"], "the Barracks offers Man-at-Arms from the Feudal Age")
	GameManager.players[0]["age"] = 2
	check(GameManager.get_research_failure_reason(0, barracks, "champion") == "age_required", "Champion is a Castle Age upgrade")
	check(GameManager.try_start_research(0, barracks, "man_at_arms"), "Man-at-Arms research starts")
	main._advance_production_queues(29.0)
	check(veteran.max_hp == float(base[0]) and UnitData.get_unit_tier(infantry, 0) == 1, "nothing changes until the research completes")
	main._advance_production_queues(1.5)
	var upgraded: Array = _stats(infantry, 0)
	check(UnitData.get_unit_tier(infantry, 0) == 2 and GameManager.get_modifier(0, "tier_%d" % infantry) == 2.0 and upgraded == _stats(infantry, 0, 2) and upgraded[0] > base[0], "the tier is stored in the modifier registry and read by get_unit_stats: " + str(upgraded))
	check(_tier_events == [[0, infantry, 2]], "unit_tier_changed fires once: " + str(_tier_events))
	check(veteran.max_hp == float(upgraded[0]) and veteran.hp == veteran.max_hp and veteran.damage == float(upgraded[1]) and veteran.armor == float(upgraded[2]), "a healthy living unit upgrades in place")
	check(wounded.max_hp == float(upgraded[0]) and is_equal_approx(wounded.hp, round(wounded.max_hp * 0.5)), "a wounded unit keeps its HP ratio (%.0f/%.0f)" % [wounded.hp, wounded.max_hp])
	var badge: Sprite2D = veteran.get_node_or_null("TierBadge") as Sprite2D
	check(badge != null and badge.visible and badge.texture != null and badge.texture.resource_path == str(UnitData.TIER_ICONS[2]), "upgraded units wear the tier-2 chevron")
	check(UnitData.get_unit_name(infantry, 0) == "Man-at-Arms" and UnitData.get_unit_name(infantry, 1) == "Warrior", "the line is renamed for its owner only")
	check(enemy.max_hp == float(_stats(infantry, 1)[0]) and enemy.get_node_or_null("TierBadge") == null and enemy.max_hp < veteran.max_hp, "the opponent's Warriors are untouched")
	var recruit: UnitBase = _unit(infantry, 0, Vector2(88, 0))
	check(recruit.max_hp == float(upgraded[0]) and recruit.hp == recruit.max_hp and recruit.damage == float(upgraded[1]) and recruit.get_node_or_null("TierBadge") != null, "new recruits arrive at the researched tier with a chevron")
	check(Combat.calculate_unit_damage(veteran, enemy) > Combat.calculate_unit_damage(enemy, veteran), "combat uses the upgraded attack and armor")
	check(barracks.get_context_actions(0).map(func(action: Dictionary) -> String: return action.id) == ["research:champion"], "Champion takes the Man-at-Arms card")
	GameManager.players[0]["age"] = 3
	wounded.hp = 1.0
	check(GameManager.try_research(0, barracks, "champion"), "Champion completes (instant fixture path)")
	check(UnitData.get_unit_tier(infantry, 0) == 3 and UnitData.get_unit_name(infantry, 0) == "Champion" and veteran.max_hp == float(_stats(infantry, 0, 3)[0]) and wounded.hp >= 1.0, "the third tier upgrades the same units again and never kills a survivor")
	check((veteran.get_node("TierBadge") as Sprite2D).texture.resource_path == str(UnitData.TIER_ICONS[3]), "and swaps in the tier-3 chevrons")
	check(_tier_events == [[0, infantry, 2], [0, infantry, 3]], "one event per tier: " + str(_tier_events))
	# The other lines.
	var archer: UnitBase = _unit(UnitData.UnitType.ARCHER, 0, Vector2(0, 40))
	var rider: UnitBase = _unit(UnitData.UnitType.CAVALRY, 0, Vector2(0, 64))
	check(GameManager.try_research(0, _building(BuildingData.BuildingType.ARCHERY_RANGE, Vector2i(8, 0)), "crossbowman") and GameManager.try_research(0, _building(BuildingData.BuildingType.STABLE, Vector2i(-8, 0)), "knight"), "Crossbowman and Knight research at their own buildings")
	check(archer.max_hp == float(_stats(UnitData.UnitType.ARCHER, 0, 2)[0]) and UnitData.get_unit_name(UnitData.UnitType.ARCHER, 0) == "Crossbowman" and rider.armor == float(_stats(UnitData.UnitType.CAVALRY, 0, 2)[2]) and UnitData.get_unit_name(UnitData.UnitType.CAVALRY, 0) == "Knight", "archers and cavalry upgrade as their own lines")
	check(not GameManager.try_research(0, barracks, "knight") and UnitData.get_unit_tier(UnitData.UnitType.SCOUT, 0) == 1, "line upgrades belong to their building and their line")


func _check_civilization_and_client() -> void:
	# The opponent is English: Longbows keep their name and their own base stats.
	var archer: int = UnitData.UnitType.ARCHER
	var longbow: UnitBase = _unit(archer, 1, Vector2(0, 40))
	var longbow_base: Dictionary = UnitData.get_unit_stats(archer, 1)
	check(str(longbow_base.name) == "Longbow" and longbow.get_node_or_null("TierBadge") == null, "fixture: the opponent fields Longbows")
	# What a client does when the snapshot says a visible enemy line is tier 2.
	ResearchEffects._apply_snapshot({"rows": [], "tiers": [[archer, 2]], "enemy_age": 3}, main)
	var tiered: Dictionary = UnitData.get_unit_stats(archer, 1)
	check(str(tiered.name) == "Longbow II" and int(tiered.hp) == int(round(int(longbow_base.hp) * 1.22)) and int(tiered.attack_range) == int(longbow_base.attack_range), "a civilization unit keeps its name, with the tier applied on its own stats: %s %d" % [tiered.name, tiered.hp])
	check(longbow.get_node_or_null("TierBadge") != null and (longbow.get_node("TierBadge") as Sprite2D).visible, "the client shows the opponent's chevron")
	check(GameManager.get_player_age(1) == 3 and main._player_buildings[1][0].get_node_or_null("AgeBanner") != null, "and the banner of a visible enemy Town Center")
	check(UnitData.get_unit_counter_name(UnitData.UnitType.INFANTRY, 1) == "Horsemen", "counter copy stays grammatical: " + UnitData.get_unit_counter_name(UnitData.UnitType.INFANTRY, 1))
	check(UnitData.get_unit_counter_name(UnitData.UnitType.CAVALRY, 0) == "Longbows", "counter copy names the base line: " + UnitData.get_unit_counter_name(UnitData.UnitType.CAVALRY, 0))


func _finish() -> void:
	print(JSON.stringify({"test": "unit_tiers", "checks": checks, "failures": failures, "scope": "real Main scene; tier data ratios, timed and instant upgrades of living units, chevrons, recruits, civilization names, client presentation"}))
	if failures.is_empty():
		print("[PASS] unit_tiers: %d checks" % checks)
	else:
		for failure: String in failures: push_error("[FAIL] unit_tiers: " + failure)
	if is_instance_valid(main): main.queue_free()
	get_tree().paused = false
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
