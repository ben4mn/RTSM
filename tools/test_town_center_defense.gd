extends Node
## Defensive weapons: legal targeting, arrow timing, armor and pause boundary.

const TC_SCENE: PackedScene = preload("res://scenes/buildings/town_center.tscn")
const WARRIOR_SCENE: PackedScene = preload("res://scenes/units/infantry.tscn")
const SCOUT_SCENE: PackedScene = preload("res://scenes/units/scout.tscn")

var _failures: Array[String] = []
var _checks: int = 0


class VisibilityMap extends Node2D:
	var hidden_entities: Array[int] = []
	var hide_human_projectiles: bool = false
	var last_target_viewer: int = -1

	func is_entity_visible_to_player(entity: Node2D, viewer: int = 0) -> bool:
		if entity is UnitBase:
			last_target_viewer = viewer
		if entity is BuildingBase.DefensiveArrow and viewer == 0:
			return not hide_human_projectiles
		return not hidden_entities.has(entity.get_instance_id())


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	get_tree().current_scene = null
	_test_data_foundation_and_armor()
	_test_owner_visibility_and_projectile_fog()
	_test_military_priority_and_range()
	_test_cooldown_and_no_building_fire()
	await _test_pause_and_game_over_boundary()
	if _failures.is_empty():
		print("[PASS] town_center_defense: %d checks; foundations, armor, owners/fog, threat priority, exact range, cooldown, pause/game-over" % _checks)
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] town_center_defense: %s" % failure)
		get_tree().quit(1)


func _test_data_foundation_and_armor() -> void:
	var world := _world()
	var tc := _town_center(world, 0)
	var warrior := _warrior(world, 1, Vector2(60.0, 0.0))
	_expect(tc.tower_attack_damage == 6, "TC arrow damage comes from building data")
	_expect(is_equal_approx(tc.tower_attack_range, MapData.range_tiles_to_world(8.0)), "TC range uses canonical conversion")
	_expect(is_equal_approx(tc.tower_attack_interval, 2.0), "TC fires once per two seconds")
	_expect(not tc.tower_attack_buildings, "TC cannot fire at enemy foundations or buildings")
	tc.start_construction()
	_expect(not tc._tower_try_attack(), "foundation cannot fire")
	_expect(_arrows().is_empty(), "foundation creates no committed arrows")
	tc.complete_instantly()
	_expect(tc._tower_try_attack(), "completion enables defense")
	_expect(is_equal_approx(warrior.hp, 60.0), "release causes no instant HP loss")
	var arrow := _arrows()[0] as BuildingBase.DefensiveArrow
	arrow.advance_projectile(0.1)
	_expect(is_equal_approx(warrior.hp, 60.0), "arrow must travel before hitting")
	arrow.advance_projectile(1.0)
	_expect(is_equal_approx(warrior.hp, 56.0), "base armor subtracts once at arrow release")
	arrow.advance_projectile(1.0)
	_expect(is_equal_approx(warrior.hp, 56.0), "finished arrow cannot damage twice")
	GameManager.apply_attack_upgrade(0, 3)
	GameManager.apply_armor_upgrade(1, 1)
	tc._tower_try_attack()
	var upgraded_arrow := _arrows()[1] as BuildingBase.DefensiveArrow
	GameManager.apply_armor_upgrade(1, 2)
	upgraded_arrow.advance_projectile(1.0)
	_expect(is_equal_approx(warrior.hp, 53.0), "building arrow ignores unit attack upgrade and snapshots effective armor once")
	GameManager.initialize_game(2)
	world.free()


func _test_owner_visibility_and_projectile_fog() -> void:
	for owner: int in [0, 1]:
		var world := _world()
		var tc := _town_center(world, owner)
		var enemy := _warrior(world, 1 - owner, Vector2(60.0, 0.0))
		world.hidden_entities.append(enemy.get_instance_id())
		_expect(not tc._tower_try_attack(), "owner %d cannot acquire a hidden raider" % owner)
		_expect(world.last_target_viewer == owner, "owner %d uses its own visibility" % owner)
		world.hidden_entities.clear()
		_expect(tc._tower_try_attack(), "owner %d fires when the raider becomes visible" % owner)
		var arrow := _arrows()[0] as BuildingBase.DefensiveArrow
		world.hidden_entities.append(enemy.get_instance_id())
		world.hide_human_projectiles = true
		arrow.advance_projectile(0.05)
		_expect(not arrow.visible, "owner %d flight rendering respects human fog" % owner)
		arrow.advance_projectile(1.0)
		_expect(is_equal_approx(enemy.hp, 56.0), "owner %d committed arrow can finish after vision loss" % owner)
		world.free()


func _test_military_priority_and_range() -> void:
	var world := _world()
	var tc := _town_center(world, 0)
	var ally := _warrior(world, 0, Vector2(5.0, 0.0))
	var warrior := _warrior(world, 1, Vector2(tc.tower_attack_range, 0.0))
	var scout := SCOUT_SCENE.instantiate() as UnitBase
	scout.player_owner = 1
	scout.position = Vector2(20.0, 0.0)
	world.add_child(scout)
	scout.set_process(false)
	var fired_at: Array[Node2D] = []
	tc.defensive_attack_fired.connect(func(target: Node2D) -> void: fired_at.append(target))
	_expect(tc._tower_try_attack(), "target on exact range boundary is eligible")
	_expect(fired_at[0] == warrior, "military raider takes priority over nearer Scout or ally")
	(_arrows()[0] as BuildingBase.DefensiveArrow).advance_projectile(1.0)
	_expect(is_equal_approx(ally.hp, 60.0), "allied units never take defense damage")
	warrior.position.x += 0.01
	scout.position.x = tc.tower_attack_range + 0.01
	_expect(not tc._tower_try_attack(), "targets beyond exact range boundary are ineligible")
	warrior.position = Vector2(50.0, 0.0)
	warrior.current_state = UnitBase.State.DEAD
	_expect(not tc._tower_try_attack(), "dead raider cannot acquire another arrow")
	world.free()


func _test_cooldown_and_no_building_fire() -> void:
	var world := _world()
	var tc := _town_center(world, 0)
	var building := BuildingBase.new()
	building.player_owner = 1
	building.state = BuildingBase.State.ACTIVE
	building.position = Vector2(60.0, 0.0)
	world.add_child(building)
	building.set_process(false)
	_expect(not tc._tower_try_attack(), "enemy building alone cannot bait TC fire")
	var shots: Array[int] = [0]
	tc.defensive_attack_fired.connect(func(_target: Node2D) -> void: shots[0] += 1)
	tc._process(0.01)
	var warrior := _warrior(world, 1, Vector2(60.0, 0.0))
	tc._process(0.1)
	_expect(shots[0] == 0, "empty scans remain throttled")
	tc._process(0.11)
	_expect(shots[0] == 1, "new threat is acquired within short scan interval")
	tc._process(1.99)
	_expect(shots[0] == 1, "weapon cannot fire again early")
	tc._process(0.02)
	_expect(shots[0] == 2, "weapon becomes ready after data interval")
	warrior.position.x = tc.tower_attack_range + 1.0
	tc._process(2.0)
	_expect(shots[0] == 2, "escaping range prevents another release")
	tc.state = BuildingBase.State.DESTROYED
	warrior.position.x = 60.0
	_expect(not tc._tower_try_attack(), "destroyed TC cannot fire")
	world.free()


func _test_pause_and_game_over_boundary() -> void:
	var world := _world()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	var tc := _town_center(world, 0)
	var enemy := _warrior(world, 1, Vector2(100.0, 0.0))
	# A real inherited arrow processes as normal gameplay while this harness
	# stays ALWAYS, matching Main and its HUD/game-over boundary.
	tc.set_process(true)
	GameManager.set_state(GameManager.GameState.PLAYING)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(not _arrows().is_empty(), "unpaused gameplay releases an inherited arrow")
	var arrow := _arrows()[0] as BuildingBase.DefensiveArrow
	GameManager.set_state(GameManager.GameState.PAUSED)
	var elapsed: float = arrow.elapsed
	var cooldown: float = tc._tower_attack_cooldown
	var hp: float = enemy.hp
	await _frames(12)
	_expect(is_equal_approx(arrow.elapsed, elapsed), "pause freezes arrow flight")
	_expect(is_equal_approx(tc._tower_attack_cooldown, cooldown), "pause freezes weapon cooldown")
	_expect(is_equal_approx(enemy.hp, hp), "pause causes no defense damage")
	GameManager.set_state(GameManager.GameState.PLAYING)
	# Headless process frames have no fixed duration unless the caller uses
	# --fixed-fps. Wait for gameplay time so the same assertion is meaningful
	# in the ordinary full-suite runner and deterministic fixed-rate runner.
	await get_tree().create_timer(0.6, false).timeout
	_expect(enemy.hp < hp, "resume lets the committed shot finish")
	# Main explicitly freezes GAME_OVER even though the global manager keeps
	# its ALWAYS UI process; both arrow and building inherit that boundary.
	tc._tower_attack_cooldown = 0.0
	await _frames(2)
	GameManager.set_state(GameManager.GameState.GAME_OVER)
	get_tree().paused = true
	var game_over_hp: float = enemy.hp
	var game_over_cooldown: float = tc._tower_attack_cooldown
	await _frames(20)
	_expect(is_equal_approx(enemy.hp, game_over_hp), "game-over boundary prevents late arrow damage")
	_expect(is_equal_approx(tc._tower_attack_cooldown, game_over_cooldown), "game-over boundary freezes weapons")
	get_tree().paused = false
	world.free()
	GameManager.set_state(GameManager.GameState.MENU)


func _world() -> VisibilityMap:
	var world := VisibilityMap.new()
	add_child(world)
	return world


func _town_center(world: Node2D, owner: int) -> BuildingBase:
	var tc := TC_SCENE.instantiate() as BuildingBase
	tc.player_owner = owner
	tc.state = BuildingBase.State.ACTIVE
	world.add_child(tc)
	tc.set_process(false)
	return tc


func _warrior(world: Node2D, owner: int, position_world: Vector2) -> UnitBase:
	var unit := WARRIOR_SCENE.instantiate() as UnitBase
	unit.player_owner = owner
	unit.position = position_world
	world.add_child(unit)
	unit.set_process(false)
	return unit


func _arrows() -> Array[Node]:
	return get_tree().get_nodes_in_group("defensive_projectiles")


func _frames(count: int) -> void:
	for _frame: int in range(count):
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
