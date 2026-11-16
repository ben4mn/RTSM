extends Node2D
## Scripted presentation fixture for BattleFX / UnitPuppet. Proves the combat
## presentation is pooled, bounded and never changes simulated outcomes.

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("[FAIL] battle_presentation: " + message)


func _unit(scene: String, owner_id: int, at: Vector2) -> UnitBase:
	var unit: UnitBase = load("res://scenes/units/%s.tscn" % scene).instantiate() as UnitBase
	unit.player_owner = owner_id
	unit.position = at
	add_child(unit)
	unit.set_process(false)
	return unit


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	GameManager.reduced_motion = false
	GameManager.reduced_flashes = false
	# Keep every fixture actor inside the 844x390 view BattleFX culls against.
	position = Vector2(420, 200)
	var fx := BattleFX.new()
	add_child(fx)
	await get_tree().process_frame
	_check(BattleFX.get_fx() == fx, "One live instance is discoverable without a GameMap")
	var fx_children: int = fx.get_child_count()

	# --- canonical damage with and without presentation ----------------------
	var attacker: UnitBase = _unit("infantry", 0, Vector2(0, 0))
	var defender: UnitBase = _unit("cavalry", 1, Vector2(30, 0))
	var expected: float = Combat.calculate_unit_damage(attacker, defender)
	var hp_before: float = defender.hp
	var position_before: Vector2 = defender.position
	Combat.deal_damage(attacker, defender)
	_check(is_equal_approx(hp_before - defender.hp, expected), "Presentation leaves canonical HP loss unchanged")
	_check(defender.position == position_before, "Flinch never moves the simulated unit")
	_check(fx._t_live == 1 and fx._t_text[0].begins_with("-") and fx._t_bonus[0] > 1.0, "Counter hit shows one merged, marked figure")
	_check(fx._p_live > 0, "Weapon impact uses pooled particles")
	_check(fx.get_child_count() == fx_children, "A hit allocates no nodes")
	defender._update_sprite_motion(0.016)
	_check(defender._sprite.material == BattleFX.flash_material(), "Struck unit takes the shared flash material")
	_check(defender._sprite.position.x > 0.0, "Flinch leans away from the attacker")
	for frame: int in 18:
		defender._update_sprite_motion(0.016)
	_check(defender._sprite.material == null and defender._sprite.position.is_zero_approx() and defender._sprite.scale == defender._sprite_rest_scale, "Flash and flinch settle to the exact rest pose")
	# A burst on one target merges; a crowd of targets is throttled per area.
	for hit: int in 2:
		Combat.deal_damage(attacker, defender)
	_check(fx._t_live == 1, "Rapid hits on one target merge into one figure")
	var crowd: Array[UnitBase] = []
	for index: int in 12:
		var bystander: UnitBase = _unit("archer", 1, Vector2(40 + index * 3, 10))
		crowd.append(bystander)
		Combat.deal_damage(attacker, bystander)
	_check(fx._t_live <= 4, "Floating figures are throttled per patch of ground")

	# --- death: corpse copy, unchanged unit lifetime ---------------------------
	var victim: UnitBase = crowd[0]
	var died: Array = [false]
	victim.unit_died.connect(func(_unit_ref: UnitBase) -> void: died[0] = true)
	victim.take_damage(9999.0)
	_check(died[0] and victim.current_state == UnitBase.State.DEAD, "Death still resolves immediately")
	_check(fx._c_live == 1 and not victim._sprite.visible, "A corpse copy takes over the fallen unit's artwork")
	await get_tree().create_timer(0.45).timeout
	_check(not is_instance_valid(victim), "The unit node keeps its original 0.3 s lifetime")
	_check(fx._corpses[0].visible and fx._corpses[0].material == BattleFX.corpse_material() and absf(fx._corpses[0].rotation) > 1.0, "The body falls, lies flat and is desaturated")
	for index: int in BattleFX.MAX_CORPSES + 8:
		var extra: UnitBase = _unit("infantry", 1, Vector2(index * 4, 60))
		extra.take_damage(9999.0)
	_check(fx._corpses.size() == BattleFX.MAX_CORPSES and fx._c_live == BattleFX.MAX_CORPSES, "Corpses are capped and recycled")
	fx._step_corpses(BattleFX.CORPSE_SECONDS + 1.0)
	_check(fx._c_live == 0, "Corpses expire")

	# --- projectiles ------------------------------------------------------------
	var archer: UnitBase = _unit("archer", 0, Vector2(-200, 0))
	var mark: UnitBase = _unit("infantry", 1, Vector2(-80, 0))
	var mark_hp: float = mark.hp
	Combat.launch_ranged_attack(archer, mark)
	var arrow: Combat.RangedProjectile = null
	for child: Node in get_children():
		if child is Combat.RangedProjectile:
			arrow = child
	_check(arrow != null and is_equal_approx(arrow.flight_seconds, clampf(120.0 / 300.0, 0.10, 0.40)), "Arrow flight time is the existing distance/speed rule")
	arrow.set_process(false)
	arrow.advance_projectile(arrow.flight_seconds * 0.5)
	_check(mark.hp == mark_hp and arrow._lift > 8.0, "Mid-flight: visible arc, no damage yet")
	arrow.advance_projectile(arrow.flight_seconds * 0.5 + 0.001)
	_check(mark.hp < mark_hp, "Damage lands exactly when the flight completes")
	var shots_before: int = fx._s_live
	var house := BuildingBase.new()
	house.building_type = BuildingData.BuildingType.HOUSE
	house.player_owner = 1
	house.state = BuildingBase.State.ACTIVE
	house.position = Vector2(-140, 40)
	add_child(house)
	house.set_process(false)
	var house_hp: int = house.hp
	Combat.deal_damage_to_building(archer, house)
	BattleFX.building_struck(archer, house)
	_check(house.hp == house_hp - Combat.calculate_building_damage(archer), "Building damage stays instant and canonical")
	_check(fx._s_live == shots_before + 1, "A ranged hit on a building launches one cosmetic arrow")
	fx._step_shots(1.0)
	_check(fx._s_live == 0 and fx._k_live >= 1, "The cosmetic arrow lands and sticks")

	# --- building: staged damage, collapse, rubble, original lifetime -----------
	_check(house.get_damage_tint() == Color.WHITE, "A lightly damaged building keeps clean walls")
	house.take_damage(int(house.max_hp * 0.7))
	_check(house.get_damage_tint().r < 0.95 and house._sprite.modulate.r < 0.95, "A badly damaged building is scorched")
	var destroyed: Array = [false]
	house.building_destroyed.connect(func(_building: BuildingBase) -> void: destroyed[0] = true)
	house.take_damage(house.max_hp)
	_check(destroyed[0] and house.state == BuildingBase.State.DESTROYED, "Destruction still resolves immediately")
	_check(fx._collapses.size() == 1 and not house._sprite.visible, "Collapse plays on a copy of the art")
	fx._step_collapses(BattleFX.COLLAPSE_SECONDS * 0.5)
	_check(fx._rubble.size() == 1 and fx._rubble[0].visible, "Rubble is placed during the fall")
	fx._step_collapses(BattleFX.COLLAPSE_SECONDS)
	_check(fx._collapses.is_empty(), "The collapse copy is released")
	await get_tree().create_timer(1.2).timeout
	_check(not is_instance_valid(house), "The building node keeps its original 1 s lifetime")

	# --- accessibility and shake -------------------------------------------------
	var camera := Camera2D.new()
	add_child(camera)
	camera.make_current()
	await get_tree().process_frame
	BattleFX.shake(1.0)
	fx._update_shake(0.016)
	var view: Vector2 = get_viewport_rect().size
	_check(camera.offset.length() > 0.0 and camera.offset.length() * fx._zoom <= clampf(minf(view.x, view.y) * 0.014, 2.0, 7.0) * 1.5 + 0.01, "Shake is bounded by the screen's short side")
	fx._update_shake(2.0)
	fx._update_shake(0.016)
	_check(camera.offset == Vector2.ZERO, "Shake always returns the camera exactly")
	GameManager.reduced_motion = true
	BattleFX.shake(1.0)
	fx._update_shake(0.016)
	_check(camera.offset == Vector2.ZERO and fx._trauma == 0.0, "Reduced motion disables shake")
	var live_before: int = fx._p_live
	fx.impact(Vector2.ZERO, Vector2.RIGHT, BattleFX.Weapon.BLADE)
	_check(fx._p_live == live_before, "Reduced motion emits no impact particles")
	GameManager.reduced_flashes = true
	defender._update_sprite_motion(1.0)
	Combat.deal_damage(attacker, defender)
	defender._update_sprite_motion(0.016)
	_check(defender._sprite.material == null, "Reduced flashes disables the white hit flash")
	GameManager.reduced_motion = false
	GameManager.reduced_flashes = false

	if _failures.is_empty():
		print("[PASS] battle_presentation: %d checks; canonical damage/timing, pooled hits, merged figures, capped corpses, cosmetic shots, collapse, bounded shake, accessibility" % _checks)
	get_tree().quit(0 if _failures.is_empty() else 1)
