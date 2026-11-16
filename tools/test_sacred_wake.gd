extends SceneTree
## Standard's Sacred clock opens at SkirmishData.SACRED_VICTORY_WAKE_SECONDS:
## an earlier hold pays gold but cannot advance a victory. Round 2 E2: an open
## clock drains while unguarded or contested and resets when the site is lost.
## Control race keeps its immediate clock and pauses when contested.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_manager: Node = root.get_node("GameManager")
	var resource_manager: Node = root.get_node("ResourceManager")
	var site: Node = (load("res://scenes/map/sacred_site.tscn") as PackedScene).instantiate()
	root.add_child(site)
	site.set_process(false)
	site.call("configure_match_mode", SkirmishData.MatchMode.STANDARD)
	resource_manager.call("initialize_player", 0, {"food": 0, "wood": 0, "gold": 0})
	site.set("state", 2)  # CAPTURED
	site.set("owning_player", 0)
	site.set("capture_progress", 1.0)
	var wake: float = SkirmishData.SACRED_VICTORY_WAKE_SECONDS

	game_manager.set("game_time", 100.0)
	for step: int in 20:
		site.call("_handle_captured", 1, 0, 1.0, 1)
	_expect(is_zero_approx(float(site.get("victory_timer"))), "the clock must not run before it wakes")
	_expect(int(resource_manager.call("get_resource", 0, "gold")) >= 30, "an early hold still pays gold")
	var early: Dictionary = site.call("get_status")
	_expect(str(early.get("phase")) == "waiting" and is_equal_approx(float(early.get("wake_remaining")), wake - 100.0), "status shows the hold waiting for the wake: %s" % str(early))

	game_manager.set("game_time", wake)
	for step: int in 10:
		site.call("_handle_captured", 1, 0, 1.0, 1)
	_expect(is_equal_approx(float(site.get("victory_timer")), 10.0), "the clock runs from the wake, got %s" % str(site.get("victory_timer")))
	_expect(str((site.call("get_status") as Dictionary).get("phase")) == "holding", "status shows holding after the wake")

	# Unguarded (no armed friendly in the ring): the held time drains.
	for step: int in 4:
		site.call("_handle_captured", 1, 0, 1.0, 0)
	_expect(is_equal_approx(float(site.get("victory_timer")), 10.0 - 4.0 * SkirmishData.SACRED_DRAIN_RATE), "an unguarded clock drains, got %s" % str(site.get("victory_timer")))
	var unguarded: Dictionary = site.call("get_status")
	_expect(str(unguarded.get("phase")) == "unguarded" and bool(unguarded.get("draining")), "status reports the drain: %s" % str(unguarded))

	# Contested (both sides inside): drains too.
	site.set("victory_timer", 10.0)
	site.set("state", 3)  # CONTESTED
	for step: int in 3:
		site.call("_handle_contested", 2, 2, 1.0)
	_expect(is_equal_approx(float(site.get("victory_timer")), 10.0 - 3.0 * SkirmishData.SACRED_DRAIN_RATE), "a contested clock drains, got %s" % str(site.get("victory_timer")))
	_expect(bool((site.call("get_status") as Dictionary).get("draining")), "a contested owned clock reports draining")

	# Losing the site resets the held time.
	site.set("state", 2)
	site.set("victory_timer", 30.0)
	site.set("capture_progress", 0.05)
	site.call("_handle_captured", 0, 3, 1.0, 0)
	_expect(int(site.get("owning_player")) == -1 and is_zero_approx(float(site.get("victory_timer"))), "a neutralized site resets its clock")

	site.call("configure_match_mode", SkirmishData.MatchMode.QUICK_CONTROL)
	site.set("state", 2)
	site.set("owning_player", 0)
	game_manager.set("game_time", 10.0)
	for step: int in 5:
		site.call("_handle_captured", 1, 0, 1.0, 1)
	_expect(float(site.get("victory_timer")) > 0.0, "Control race keeps an immediate clock")
	var banked: float = float(site.get("victory_timer"))
	site.set("state", 3)
	site.call("_handle_contested", 2, 2, 1.0)
	_expect(is_equal_approx(float(site.get("victory_timer")), banked), "Control race pauses (no drain) while contested")

	site.free()
	if _failures.is_empty():
		print("[PASS] sacred_wake: gold before the wake, clock after it, drain when unguarded/contested, reset on loss, Control race unchanged")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] sacred_wake: %s" % failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
