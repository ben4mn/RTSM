extends "res://tools/garrison_fixture.gd"
## Healing at home and inside, manual garrison of soldiers, Watch Tower
## capacity, and which garrisoned units add arrows.


func run_cases() -> void:
	case_name = "garrison_heal"
	await step(0.5)

	# --- Home regeneration: 1 HP/s after six calm seconds within five tiles.
	var home: UnitBase = spawn(UnitData.UnitType.INFANTRY, 0, Vector2i(5, 1))
	var away: UnitBase = spawn_at(UnitData.UnitType.INFANTRY, 0, free_tile(tc_tile() + Vector2i(13, 13)))
	for soldier: UnitBase in [home, away]:
		soldier.hp = soldier.max_hp * 0.5
	expect(Garrison.tile_distance(tc, home.global_position) <= Garrison.HOME_HEAL_RADIUS_TILES, "fixture soldier stands within the home radius")
	expect(Garrison.tile_distance(tc, away.global_position) > Garrison.HOME_HEAL_RADIUS_TILES, "second soldier stands outside it")
	away.stance = UnitBase.Stance.STAND_GROUND
	await step(0.6)
	home.take_damage(4.0)
	var wounded_hp: float = home.hp
	await step(4.0)
	expect(is_equal_approx(home.hp, wounded_hp), "no healing within six seconds of the last hit")
	await step(3.0)
	var start_hp: float = home.hp
	await step(5.0)
	var gained: float = home.hp - start_hp
	expect(gained > 3.5 and gained < 6.5, "home regeneration is about 1 HP/s (gained %.2f in 5 s)" % gained)
	expect(is_equal_approx(away.hp, away.max_hp * 0.5), "a soldier away from home does not regenerate")

	# --- Garrisoned: 3 HP/s, hidden, and a fresh order brings the unit out.
	expect(Garrison.order_garrison([home], tc) == 1, "soldier accepts a garrison order")
	var inside: bool = await step_until(func() -> bool: return home.current_state == UnitBase.State.GARRISONED, 20.0)
	expect(inside and not home.is_inside_tree() and Garrison.count(tc) == 1, "soldier walks in and is off the field")
	expect(Garrison.bonus_arrows(tc) == 0, "a melee soldier adds no arrows")
	home.hp = 20.0
	await step(4.0)
	gained = home.hp - 20.0
	expect(gained > 10.0 and gained < 14.5, "garrison heals about 3 HP/s (gained %.2f in 4 s)" % gained)
	await step(60.0)
	expect(is_equal_approx(home.hp, home.max_hp), "healing stops at full health")
	expect(not tc.bell_active and Garrison.count(tc) == 1, "a hand-garrisoned soldier stays in without a bell")
	home.command_move(home.global_position + Vector2(120.0, 60.0))
	expect(home.is_inside_tree() and home.current_state == UnitBase.State.MOVING and Garrison.count(tc) == 0, "an order to a garrisoned unit brings it out and is obeyed")
	expect(home.visible and get_tree().get_nodes_in_group("units").has(home), "released soldier is a normal unit again")

	# --- Ungarrison action and the ext command.
	# --- Touch flow: hold an own shelter with soldiers selected -> "Garrison".
	var selection: Node = map.selection_mgr
	var label_of: Callable = func(offered: Dictionary) -> String: return str(offered.label)
	var worker: Villager = own_villagers()[0]
	selection.select_single(worker)
	expect(selection._build_touch_context_actions(tc, null).map(label_of) == ["Queue drop-off"], "villagers alone keep the one-step Queue drop-off on the Town Center")
	var mixed: Array[Node2D] = [home, worker]
	selection.select_many(mixed)
	expect(selection._build_touch_context_actions(tc, null).map(label_of) == ["Queue drop-off", "Garrison"], "a mixed selection is offered both")
	selection.select_single(home)
	var soldier_menu: Array = selection._build_touch_context_actions(tc, null).map(label_of)
	expect(soldier_menu.has("Garrison") and soldier_menu.has("Select"), "soldiers are offered Garrison beside Select: " + str(soldier_menu))
	expect(not selection._build_touch_context_actions(main._player_buildings[1][0], null).map(label_of).has("Garrison"), "never on a rival building")
	selection._context_target = tc
	selection._execute_touch_context_action(selection.TouchContextAction.GARRISON)
	expect(home._garrison_target == tc, "choosing Garrison sends the selected soldier to the Town Center")
	await step_until(func() -> bool: return home.current_state == UnitBase.State.GARRISONED, 20.0)
	# HUD pass: the row is paged by CommandRow, so the bell stays and "Out" joins it.
	expect(tc.get_context_actions(0).filter(func(a: Dictionary) -> bool: return str(a.id).begins_with("garrison:")).map(func(a: Dictionary) -> String: return str(a.id)) == [Garrison.ACTION_BELL, Garrison.ACTION_RELEASE], "with soldiers inside and no bell the Town Center offers the bell and Ungarrison")
	expect(tc.perform_context_action(0, Garrison.ACTION_RELEASE) == "", "Ungarrison action accepted")
	expect(str(tc.get_context_actions(0).filter(func(a: Dictionary) -> bool: return str(a.id).begins_with("garrison:"))[0].id) == Garrison.ACTION_BELL, "an empty Town Center offers the bell again")
	expect(home.is_inside_tree() and home.current_state == UnitBase.State.IDLE, "Ungarrison puts the soldier outside, idle")
	expect(main.ext.run_command("ungarrison", 0, {"target": 1}, [], tc, Vector2.ZERO) == "Nobody inside", "ungarrison on an empty building explains itself")
	expect(main.ext.run_command("garrison", 1, {"target": 1, "ids": [1]}, [home], tc, Vector2.ZERO) == "Cannot garrison there", "the rival cannot use this Town Center")
	expect(main.ext.run_command("garrison", 0, {"target": 1}, [home], tc, Vector2.ZERO) == "Invalid order", "garrison without units is malformed")

	# --- Watch Tower: five beds; archers and villagers shoot, warriors do not.
	var tower: BuildingBase = main._spawn_building(BuildingData.BuildingType.WATCH_TOWER, 0, free_tile(tc_tile() + Vector2i(8, 2)))
	tower.complete_instantly()
	expect(Garrison.capacity_of(tower) == 5, "Watch Tower holds five")
	expect(tower.get_context_actions(0).is_empty(), "an empty tower offers no bell and no Ungarrison")
	var archers: Array = []
	for index: int in 6:
		archers.append(spawn_at(UnitData.UnitType.ARCHER, 0, free_tile(map.world_to_tile(tower.global_position) + Vector2i(2, 2), index)))
	await step(0.3)
	expect(Garrison.order_garrison(archers, tower) == 5, "a sixth archer is refused the order")
	await step_until(func() -> bool: return Garrison.count(tower) == 5, 25.0)
	expect(Garrison.count(tower) == 5 and Garrison.bonus_arrows(tower) == 5, "five archers inside add five arrows")
	expect(str(tower.get_context_actions(0)[0].id) == Garrison.ACTION_RELEASE, "a manned tower offers Ungarrison")
	expect(Garrison.ungarrison(tower) == 5 and Garrison.count(tower) == 0, "tower empties on Ungarrison")
	for archer: UnitBase in archers:
		expect(archer.is_inside_tree() and archer.current_state != UnitBase.State.GARRISONED, "archer is back outside")

	# --- Siege never garrisons.
	var ram: UnitBase = spawn_at(UnitData.UnitType.SIEGE, 0, free_tile(tc_tile() + Vector2i(6, 2)))
	expect(Garrison.order_garrison([ram], tc) == 0, "siege cannot garrison")
