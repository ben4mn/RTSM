extends Node
## Regression for frame-rate-independent sacred-site resource income.

const SACRED_SITE_SCENE := preload("res://scenes/map/sacred_site.tscn")
const INFANTRY_SCENE := preload("res://scenes/units/infantry.tscn")
const PLAYER_ZERO: int = 0
const PLAYER_ONE: int = 1

var _failures: Array[String] = []


func _ready() -> void:
	AudioManager.set_all_enabled(false)
	_test_fixed_rate(30)
	_test_fixed_rate(60)
	_test_variable_rate()
	_test_owner_change_discards_fraction()
	_test_inactive_states_award_nothing()
	_test_dead_units_do_not_capture_or_contest()
	if _failures.is_empty():
		print("[PASS] sacred_income: exact awards, owner isolation, and dead-unit exclusion")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] sacred_income: %s" % failure)
	get_tree().quit(1)


func _test_fixed_rate(fps: int) -> void:
	_reset_resources()
	var site: Node = _make_site()
	for _frame in fps * 10:
		site.call("_generate_gold", 1.0 / float(fps))
	_expect_gold(PLAYER_ZERO, 20, "%d FPS over ten seconds" % fps)
	site.free()


func _test_variable_rate() -> void:
	_reset_resources()
	var site: Node = _make_site()
	var pattern: Array[float] = [0.016, 0.041, 0.117, 0.25, 0.033]
	var elapsed: float = 0.0
	var index: int = 0
	while elapsed < 10.0:
		var delta: float = minf(pattern[index % pattern.size()], 10.0 - elapsed)
		site.call("_generate_gold", delta)
		elapsed += delta
		index += 1
	_expect_gold(PLAYER_ZERO, 20, "variable frame steps over ten seconds")
	site.free()


func _test_owner_change_discards_fraction() -> void:
	_reset_resources()
	var site: Node = _make_site()
	site.call("_generate_gold", 0.3) # 0.6 gold remains fractional.
	site.set("owning_player", PLAYER_ONE)
	site.call("_generate_gold", 0.2) # New owner starts at 0.4, not 1.0.
	_expect_gold(PLAYER_ZERO, 0, "old owner fractional remainder")
	_expect_gold(PLAYER_ONE, 0, "new owner cannot inherit the old remainder")
	site.call("_generate_gold", 0.3)
	_expect_gold(PLAYER_ONE, 1, "new owner earns its own complete resource")
	site.free()


func _test_inactive_states_award_nothing() -> void:
	_reset_resources()
	var site: Node = _make_site()
	site.set("state", 0) # NEUTRAL
	site.call("_process", 5.0)
	_expect_gold(PLAYER_ZERO, 0, "neutral site")
	site.set("state", 3) # CONTESTED
	site.set("owning_player", PLAYER_ZERO)
	site.call("_process", 5.0)
	_expect_gold(PLAYER_ZERO, 0, "contested site")
	site.free()


func _test_dead_units_do_not_capture_or_contest() -> void:
	var site: Node2D = _make_site() as Node2D
	site.set("state", 0) # NEUTRAL
	var live_unit: UnitBase = INFANTRY_SCENE.instantiate() as UnitBase
	live_unit.player_owner = PLAYER_ZERO
	live_unit.global_position = site.global_position
	add_child(live_unit)
	live_unit.set_process(false)
	var dead_unit: UnitBase = INFANTRY_SCENE.instantiate() as UnitBase
	dead_unit.player_owner = PLAYER_ONE
	dead_unit.global_position = site.global_position
	add_child(dead_unit)
	dead_unit.set_process(false)
	dead_unit.set_state(UnitBase.State.DEAD)
	var counts: Array[int] = site.call("_count_nearby_players") as Array[int]
	if counts != [1, 0]:
		_failures.append("dead fade unit affected capture counts (expected [1, 0], got %s)" % str(counts))
	live_unit.free()
	dead_unit.free()
	site.free()


func _make_site() -> Node:
	var site: Node = SACRED_SITE_SCENE.instantiate()
	add_child(site)
	site.set_process(false)
	site.set("state", 2) # CAPTURED
	site.set("owning_player", PLAYER_ZERO)
	site.set("gold_per_second", 2.0)
	return site


func _reset_resources() -> void:
	ResourceManager.reset()
	ResourceManager.initialize_player(PLAYER_ZERO, {"food": 0, "wood": 0, "gold": 0})
	ResourceManager.initialize_player(PLAYER_ONE, {"food": 0, "wood": 0, "gold": 0})


func _expect_gold(player_id: int, expected: int, label: String) -> void:
	var actual: int = ResourceManager.get_resource(player_id, "gold")
	if actual == expected:
		return
	_failures.append("%s expected %d gold, got %d" % [label, expected, actual])
