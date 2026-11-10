extends "res://tools/garrison_fixture.gd"
## Solo checkpoint taken while the bell is ringing and units are inside:
## capture, byte round trip, validation, and a restore into a fresh match.

const CODEC: GDScript = preload("res://scripts/main/solo_match_state.gd")


func run_cases() -> void:
	case_name = "garrison_save"
	await step(1.0)
	var workers: Array[Villager] = own_villagers()
	var archer: UnitBase = spawn(UnitData.UnitType.ARCHER, 0, Vector2i(5, 1))
	archer.hp = archer.max_hp * 0.5
	var house: BuildingBase = main._spawn_building(BuildingData.BuildingType.HOUSE, 0, free_tile(tc_tile() + Vector2i(7, 1)))
	house.complete_instantly()
	house.hp = house.max_hp - 120
	house.repair_credit = 7.5
	expect(Garrison.ring(tc), "bell rung")
	expect(Garrison.order_garrison([archer], tc) == 1, "archer ordered inside")
	var expected_inside: int = workers.size() + 1
	var all_in: bool = await step_until(func() -> bool: return Garrison.count(tc) == expected_inside, 40.0)
	expect(all_in, "villagers and archer are inside before the checkpoint")
	tc._bell_quiet = 3.5
	archer.hp = archer.max_hp * 0.5
	var units_before: int = main._player_units[0].size()
	var population_before: int = int(GameManager.players[0].population)
	var archer_hp: float = archer.hp

	var data: Dictionary = bytes_to_var(var_to_bytes(CODEC.new().capture(main)))
	expect(CODEC.validate(data) == "", "checkpoint with a garrison validates (%s)" % CODEC.validate(data))
	expect(data.ext.has("garrison"), "garrison section is written through the save seam")
	var garrisoned_records: int = 0
	for record: Dictionary in data.actors:
		if record.kind == "unit" and int(record.fields.current_state) == UnitBase.State.GARRISONED:
			garrisoned_records += 1
	expect(garrisoned_records == expected_inside, "garrisoned units are saved as ordinary actors")
	var broken: Dictionary = data.duplicate(true)
	for record: Dictionary in broken.actors:
		if record.kind == "building":
			record.fields.erase("garrisoned_ids")
	expect(CODEC.validate(broken) != "", "a checkpoint without the garrison fields is refused, not half-restored")

	# Leaving the match must not leak the units that are outside the tree.
	var stowed: Array[UnitBase] = Garrison.garrisoned_units(tc)
	main.free()
	await get_tree().process_frame
	expect(stowed.all(func(unit: Variant) -> bool: return not is_instance_valid(unit)), "garrisoned units are freed with their match")

	SoloSave._pending_restore = data
	expect(await boot(), "fresh match restores the checkpoint")
	expect(tc.bell_active and absf(tc._bell_quiet - 3.5) < 1.5, "bell and its quiet timer are restored (%.2f)" % tc._bell_quiet)
	expect(Garrison.count(tc) == expected_inside, "everyone is still inside (%d/%d)" % [Garrison.count(tc), expected_inside])
	expect(main._player_units[0].size() == units_before and int(GameManager.players[0].population) == population_before, "no unit or population was lost or duplicated")
	var restored_archer: UnitBase = null
	for unit: UnitBase in Garrison.garrisoned_units(tc):
		expect(unit.current_state == UnitBase.State.GARRISONED and not unit.is_inside_tree() and unit._garrison_target == tc, "restored unit is garrisoned in the restored Town Center")
		if unit.unit_type == UnitData.UnitType.ARCHER:
			restored_archer = unit
	expect(restored_archer != null and is_equal_approx(restored_archer.hp, archer_hp) or (restored_archer != null and restored_archer.hp > archer_hp), "archer and its wound are restored")
	expect(Garrison.bonus_arrows(tc) == mini(Garrison.MAX_BONUS_ARROWS, expected_inside), "restored garrison still adds its arrows")
	var restored_house: BuildingBase = null
	for building: BuildingBase in main._player_buildings[0]:
		if building.building_type == BuildingData.BuildingType.HOUSE and building.hp < building.max_hp:
			restored_house = building
	expect(restored_house != null and is_equal_approx(restored_house.repair_credit, 7.5), "prepaid repair credit is restored")
	if restored_archer != null:
		var hp_then: float = restored_archer.hp
		await step(2.0)
		expect(restored_archer.hp > hp_then + 3.0, "restored garrison keeps healing")
	# No raider anywhere: the restored bell finishes its count and stands down.
	var cleared: bool = await step_until(func() -> bool: return not tc.bell_active, 12.0)
	expect(cleared, "restored bell reaches all-clear")
	await step(1.0)
	var resumed: int = 0
	for worker: Villager in own_villagers():
		expect(worker.is_inside_tree() and worker.current_state != UnitBase.State.GARRISONED, "restored villager is released")
		if worker.has_active_gather_order() or worker.current_state == UnitBase.State.GATHERING:
			resumed += 1
	expect(resumed >= 2, "restored villagers go back to their saved jobs (%d)" % resumed)
	expect(restored_archer != null and not restored_archer.is_inside_tree() and Garrison.count(tc) == 1, "the hand-garrisoned archer stays inside after all-clear")
	expect(Garrison.ungarrison(tc) == 1 and restored_archer.is_inside_tree(), "Ungarrison releases the archer")
