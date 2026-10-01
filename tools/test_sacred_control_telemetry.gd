extends SceneTree
## Regression for cumulative Sacred Site control telemetry across a contest.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const GAME_STATE_PLAYING := 2
const READY_FRAME_LIMIT := 900
const SITE_STATE_CAPTURING := 1
const SITE_STATE_CAPTURED := 2
const SITE_STATE_CONTESTED := 3
const HOLD_TIME := 600.0
const EPSILON := 0.001

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var audio_manager: Node = root.get_node("AudioManager")
	audio_manager.call("set_all_enabled", false)
	var game_manager: Node = root.get_node("GameManager")
	var packed: PackedScene = load(MAIN_SCENE)
	var match_scene: Node = packed.instantiate()
	root.add_child(match_scene)
	current_scene = match_scene

	if not await _wait_for(func() -> bool:
		var game_map: Node = match_scene.get_node("GameMap")
		return (
			int(game_manager.get("current_state")) == GAME_STATE_PLAYING
			and game_map.get("sacred_site") != null
		)
	):
		_expect(false, "match did not reach PLAYING with a Sacred Site")
		_finish(match_scene)
		return

	var game_map: Node = match_scene.get_node("GameMap")
	var sacred_site: Node = game_map.get("sacred_site") as Node
	# Keep the live scene from advancing the fixture between explicit handler
	# calls. The sequence below still exercises the SacredSite state handlers
	# and their signals wired to Main.
	sacred_site.process_mode = Node.PROCESS_MODE_DISABLED
	sacred_site.set("victory_hold_time", HOLD_TIME)
	sacred_site.set("owning_player", 0)
	sacred_site.set("capture_progress", 1.0)
	sacred_site.set("victory_timer", 0.0)
	sacred_site.set("state", SITE_STATE_CAPTURED)
	sacred_site.emit_signal("captured", 0)
	_expect_eq(_latest_notification(match_scene), "Sacred Site secured! Hold 10:00 more to win.", "capture feedback uses the actual match hold duration")
	_expect_approx(
		float(match_scene.get("_sacred_last_remaining")),
		HOLD_TIME,
		"initial capture establishes a full timer baseline"
	)

	# First uninterrupted twelve seconds of control.
	sacred_site.call("_handle_captured", 1, 0, 12.0)
	_expect_approx(_control_seconds(match_scene, 0), 12.0, "first hold interval is recorded once")
	_expect_approx(float(sacred_site.get("victory_timer")), 12.0, "site timer advances before contest")

	# Both players contest the site. Once the original owner is alone again,
	# SacredSite deliberately preserves its twelve-second victory timer and
	# emits captured for that same owner.
	sacred_site.call("_handle_captured", 1, 1, 0.5)
	_expect_eq(int(sacred_site.get("state")), SITE_STATE_CONTESTED, "both players enter contested state")
	_expect_approx(_control_seconds(match_scene, 0), 12.0, "contest adds no control time")
	sacred_site.call("_handle_contested", 1, 0, 0.5)
	_expect_eq(int(sacred_site.get("state")), SITE_STATE_CAPTURING, "same owner resumes capture")
	_expect_approx(float(sacred_site.get("victory_timer")), 12.0, "contest preserves the site victory timer")
	sacred_site.call("_handle_capturing", 1, 0, 0.0)
	_expect_eq(int(sacred_site.get("state")), SITE_STATE_CAPTURED, "same owner recaptures the site")
	_expect_approx(
		float(match_scene.get("_sacred_last_remaining")),
		HOLD_TIME - 12.0,
		"recapture baseline follows the preserved site timer"
	)
	_expect_eq(_latest_notification(match_scene), "Sacred Site secured! Hold 9:48 more to win.", "recapture feedback reports the remaining duration")

	# Five more seconds should produce seventeen cumulative seconds, not the
	# twenty-nine seconds caused by restarting telemetry at 180 on recapture.
	sacred_site.call("_handle_captured", 1, 0, 5.0)
	_expect_approx(_control_seconds(match_scene, 0), 17.0, "post-recapture hold time is not double-counted")
	_expect_approx(float(sacred_site.get("victory_timer")), 17.0, "victory mechanics continue from preserved time")
	_expect_eq(int(game_manager.get("current_state")), GAME_STATE_PLAYING, "partial hold does not conclude the match")

	# An opposing player must earn a fresh hold timer. Put the original owner one
	# second from victory so inheriting that timer would immediately end the match
	# after the takeover's first two-second tick.
	sacred_site.set("victory_timer", HOLD_TIME - 1.0)
	sacred_site.call("_handle_captured", 1, 1, 0.5)
	_expect_eq(int(sacred_site.get("state")), SITE_STATE_CONTESTED, "opposing takeover begins from contested state")
	sacred_site.call("_handle_contested", 0, 1, float(sacred_site.get("capture_time")))
	_expect_eq(int(sacred_site.get("owning_player")), 1, "opposing player takes over capture ownership")
	_expect_eq(int(sacred_site.get("state")), SITE_STATE_CAPTURING, "opposing takeover must recapture from zero")
	_expect_approx(float(sacred_site.get("victory_timer")), 0.0, "opposing takeover resets the former owner's victory timer")
	sacred_site.call("_handle_capturing", 0, 1, float(sacred_site.get("capture_time")))
	_expect_eq(int(sacred_site.get("state")), SITE_STATE_CAPTURED, "opposing player completes its fresh capture")
	_expect_approx(float(match_scene.get("_sacred_last_remaining")), HOLD_TIME, "new owner's telemetry starts from the full hold time")
	sacred_site.call("_handle_captured", 0, 1, 2.0)
	_expect_approx(float(sacred_site.get("victory_timer")), 2.0, "new owner accrues only its own hold time")
	_expect_approx(_control_seconds(match_scene, 1), 2.0, "new owner's telemetry excludes the former owner's hold")
	_expect_eq(int(game_manager.get("current_state")), GAME_STATE_PLAYING, "timer inheritance cannot grant an immediate takeover victory")

	_finish(match_scene)


func _control_seconds(match_scene: Node, player_id: int) -> float:
	var values: Array = match_scene.get("_sacred_control_seconds") as Array
	return float(values[player_id])


func _latest_notification(match_scene: Node) -> String:
	var hud: Node = match_scene.get("hud") as Node
	var feed: Node = hud.get("_notification_container") as Node
	var panel: Node = feed.get_child(feed.get_child_count() - 1)
	return (panel.get_child(0) as Label).text


func _wait_for(predicate: Callable) -> bool:
	for _frame: int in READY_FRAME_LIMIT:
		if predicate.call():
			return true
		await process_frame
	return false


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[FAIL] sacred_control_telemetry: %s" % message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


func _expect_approx(actual: float, expected: float, message: String) -> void:
	_expect(
		absf(actual - expected) <= EPSILON,
		"%s (expected %.3f, got %.3f)" % [message, expected, actual]
	)


func _finish(match_scene: Node) -> void:
	if is_instance_valid(match_scene):
		match_scene.free()
	current_scene = null
	if _failures.is_empty():
		print("[PASS] sacred_control_telemetry: same-owner recovery persists while opposing takeover resets hold time")
		quit(0)
	else:
		quit(1)
