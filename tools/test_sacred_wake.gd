extends SceneTree
## Standard's Sacred clock opens at 8:00: an earlier hold pays gold but cannot
## advance a victory. Control race keeps its immediate clock.

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

	game_manager.set("game_time", 100.0)
	for step: int in 20:
		site.call("_handle_captured", 1, 0, 1.0, 1)
	_expect(is_zero_approx(float(site.get("victory_timer"))), "the clock must not run before 8:00")
	_expect(int(resource_manager.call("get_resource", 0, "gold")) >= 30, "an early hold still pays gold")
	var early: Dictionary = site.call("get_status")
	_expect(str(early.get("phase")) == "waiting" and is_equal_approx(float(early.get("wake_remaining")), 380.0), "status shows the hold waiting for 8:00: %s" % str(early))

	game_manager.set("game_time", 480.0)
	for step: int in 10:
		site.call("_handle_captured", 1, 0, 1.0, 1)
	_expect(is_equal_approx(float(site.get("victory_timer")), 10.0), "the clock runs from 8:00, got %s" % str(site.get("victory_timer")))
	_expect(str((site.call("get_status") as Dictionary).get("phase")) == "holding", "status shows holding after 8:00")

	site.call("configure_match_mode", SkirmishData.MatchMode.QUICK_CONTROL)
	site.set("state", 2)
	site.set("owning_player", 0)
	game_manager.set("game_time", 10.0)
	for step: int in 5:
		site.call("_handle_captured", 1, 0, 1.0, 1)
	_expect(float(site.get("victory_timer")) > 0.0, "Control race keeps an immediate clock")

	site.free()
	if _failures.is_empty():
		print("[PASS] sacred_wake: gold before 8:00, clock from 8:00, Control race unchanged")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] sacred_wake: %s" % failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
