extends SceneTree
## Real-scene regression for pause/game-over process isolation and live controls.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const READY_FRAME_LIMIT := 900
const GAME_STATE_MENU := 0
const GAME_STATE_PLAYING := 2
const GAME_STATE_PAUSED := 3
const GAME_STATE_GAME_OVER := 4

var _failures: Array[String] = []


class ProcessProbe extends Node:
	var ticks: int = 0

	func _process(_delta: float) -> void:
		ticks += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_manager: Node = root.get_node("GameManager")
	var audio_manager: Node = root.get_node("AudioManager")
	audio_manager.call("set_all_enabled", false)

	var match_scene: Node2D = (load(MAIN_SCENE) as PackedScene).instantiate() as Node2D
	root.add_child(match_scene)
	current_scene = match_scene
	if not await _wait_for(func() -> bool:
		var units_by_player: Array = match_scene.get("_player_units") as Array
		return (
			int(game_manager.get("current_state")) == GAME_STATE_PLAYING
			and units_by_player.size() >= 2
			and not (units_by_player[0] as Array).is_empty()
			and not (match_scene.get("_player_buildings") as Array)[0].is_empty()
			and match_scene.get_node("GameMap").get("sacred_site") != null
		)
	):
		_fail("match did not reach a populated PLAYING state")
		_finish()
		return

	var game_map: Node2D = match_scene.get_node("GameMap") as Node2D
	var hud: CanvasLayer = match_scene.get_node("HUD") as CanvasLayer
	var ai_controller: Node = match_scene.get_node("AIController")
	var selection_manager: Node = game_map.get("selection_mgr") as Node
	var sacred_site: Node2D = game_map.get("sacred_site") as Node2D
	var player_units: Array = (match_scene.get("_player_units") as Array)[0]
	var player_buildings: Array = (match_scene.get("_player_buildings") as Array)[0]
	# Keep this SceneTree harness dynamically typed for project-script instances:
	# direct class-name annotations are resolved before autoload names exist in a
	# `--script` main loop, unlike normal scene compilation.
	var moving_unit: Node2D = player_units[0] as Node2D
	var representative_building: Node2D = player_buildings[0] as Node2D
	if moving_unit == null or representative_building == null:
		_fail("real unit/building fixtures were unavailable")
		_finish()
		return

	if match_scene.process_mode != Node.PROCESS_MODE_PAUSABLE:
		_fail("Main is not the explicit PAUSABLE match boundary")
	if hud.process_mode != Node.PROCESS_MODE_ALWAYS:
		_fail("HUD did not retain its independent ALWAYS process mode")

	var probe := ProcessProbe.new()
	probe.name = "PauseBoundaryProbe"
	game_map.add_child(probe)
	await process_frame
	await process_frame
	if probe.ticks <= 0:
		_fail("inherited gameplay probe did not process before pause")

	var movement_route: PackedVector2Array = _find_long_move_route(game_map, moving_unit)
	if movement_route.is_empty():
		_fail("could not find a long reachable route for the real starting unit")
		_finish()
		return
	var movement_start: Vector2 = moving_unit.global_position
	moving_unit.call("command_move_path", movement_route)

	# Drive the real Sacred Site state machine alongside real unit movement so
	# the freeze assertion covers both inherited simulation branches.
	sacred_site.set("state", 2) # SacredSite.SiteState.CAPTURED
	sacred_site.set("owning_player", 0)
	sacred_site.set("capture_progress", 1.0)
	sacred_site.set("victory_timer", 5.0)
	sacred_site.set("victory_hold_time", 10000.0)
	if not await _wait_for(func() -> bool:
		return (
			moving_unit.global_position.distance_to(movement_start) > 0.5
			and float(sacred_site.get("victory_timer")) > 5.0
		)
	):
		_fail("real movement and Sacred Site timer did not advance before pause")
		_finish()
		return

	var pause_button: Button = hud.find_child("PauseButton", true, false) as Button
	if pause_button == null:
		_fail("HUD Pause button was unavailable")
		_finish()
		return
	pause_button.pressed.emit()
	await process_frame
	if int(game_manager.get("current_state")) != GAME_STATE_PAUSED or not paused:
		_fail("Pause button did not enter the paused SceneTree state")

	var pause_overlay: Control = hud.get_node_or_null("Root/PauseOverlay") as Control
	var resume_button: Button = hud.get_node_or_null("Root/PauseOverlay/PauseMenu/ResumeButton") as Button
	if pause_overlay == null or resume_button == null:
		_fail("pause overlay controls were not created")
		_finish()
		return
	_check_simulation_processing(false, match_scene, game_map, ai_controller, selection_manager, moving_unit, representative_building, sacred_site)
	if not hud.can_process() or not pause_overlay.can_process() or not resume_button.can_process():
		_fail("ALWAYS pause UI was not actionable while the SceneTree was paused")

	var paused_position: Vector2 = moving_unit.global_position
	var paused_site_timer: float = float(sacred_site.get("victory_timer"))
	var paused_probe_ticks: int = probe.ticks
	var paused_game_time: float = float(game_manager.get("game_time"))
	await _wait_frames(12)
	_assert_frozen("pause", moving_unit, paused_position, sacred_site, paused_site_timer, probe, paused_probe_ticks, game_manager, paused_game_time)

	resume_button.pressed.emit()
	if not await _wait_for(func() -> bool:
		return int(game_manager.get("current_state")) == GAME_STATE_PLAYING and not paused
	):
		_fail("Resume button did not return the match to PLAYING")
		_finish()
		return
	var resume_position: Vector2 = moving_unit.global_position
	var resume_site_timer: float = float(sacred_site.get("victory_timer"))
	var resume_probe_ticks: int = probe.ticks
	if not await _wait_for(func() -> bool:
		return (
			probe.ticks > resume_probe_ticks
			and moving_unit.global_position.distance_to(resume_position) > 0.5
			and float(sacred_site.get("victory_timer")) > resume_site_timer
		)
	):
		_fail("simulation did not resume after the pause UI callback")
		_finish()
		return

	match_scene.call("_conclude_match", 0, "Process boundary regression")
	await process_frame
	var game_over: CanvasLayer = match_scene.get_node_or_null("GameOverScreen") as CanvasLayer
	if game_over == null:
		_fail("game-over overlay was not created")
		_finish()
		return
	if int(game_manager.get("current_state")) != GAME_STATE_GAME_OVER or not paused:
		_fail("match conclusion did not enter paused GAME_OVER state")
	_check_simulation_processing(false, match_scene, game_map, ai_controller, selection_manager, moving_unit, representative_building, sacred_site)
	var play_again_button: Button = game_over.get_node("GameOverPanel/Margin/VBox/ButtonRow/PlayAgainButton") as Button
	var main_menu_button: Button = game_over.get_node("GameOverPanel/Margin/VBox/ButtonRow/MainMenuButton") as Button
	if game_over.process_mode != Node.PROCESS_MODE_ALWAYS:
		_fail("GameOverScreen did not retain its independent ALWAYS process mode")
	if not game_over.can_process() or not play_again_button.can_process() or not main_menu_button.can_process():
		_fail("game-over controls were not actionable while simulation was frozen")

	var game_over_position: Vector2 = moving_unit.global_position
	var game_over_site_timer: float = float(sacred_site.get("victory_timer"))
	var game_over_probe_ticks: int = probe.ticks
	var game_over_game_time: float = float(game_manager.get("game_time"))
	await _wait_frames(12)
	_assert_frozen("game over", moving_unit, game_over_position, sacred_site, game_over_site_timer, probe, game_over_probe_ticks, game_manager, game_over_game_time)

	# End on a real paused-state action, proving the ALWAYS overlay can invoke a
	# callback on the PAUSABLE Main and complete its deferred transition.
	main_menu_button.pressed.emit()
	if current_scene != match_scene or not match_scene.is_inside_tree():
		_fail("game-over Main Menu removed the focused match synchronously")
	if not main_menu_button.disabled:
		_fail("game-over Main Menu remained enabled during deferred transition")
	if not await _wait_for(func() -> bool:
		return current_scene != null and current_scene.scene_file_path == MENU_SCENE
	):
		_fail("actionable game-over control did not reach the main menu")
	elif int(game_manager.get("current_state")) != GAME_STATE_MENU:
		_fail("game-over action left GameManager outside MENU")

	_finish()


func _find_long_move_route(game_map: Node2D, unit: Node2D) -> PackedVector2Array:
	var origin: Vector2i = game_map.call("world_to_tile", unit.global_position)
	for radius: int in range(4, 13):
		for y: int in range(origin.y - radius, origin.y + radius + 1):
			for x: int in range(origin.x - radius, origin.x + radius + 1):
				if x != origin.x - radius and x != origin.x + radius and y != origin.y - radius and y != origin.y + radius:
					continue
				var tile := Vector2i(x, y)
				if not bool(game_map.call("is_tile_walkable", tile)):
					continue
				var target: Vector2 = game_map.call("tile_to_world", tile)
				var route: PackedVector2Array = game_map.call("get_navigation_world_path", unit.global_position, target, 4.0)
				if not route.is_empty() and unit.global_position.distance_to(route[route.size() - 1]) >= 96.0:
					return route
	return PackedVector2Array()


func _check_simulation_processing(
	expected: bool,
	match_scene: Node2D,
	game_map: Node2D,
	ai_controller: Node,
	selection_manager: Node,
	unit: Node2D,
	building: Node2D,
	sacred_site: Node2D
) -> void:
	var nodes: Array[Node] = [match_scene, game_map, ai_controller, selection_manager, unit, building, sacred_site]
	for node: Node in nodes:
		if node.can_process() != expected:
			_fail("%s process eligibility was %s, expected %s" % [node.name, node.can_process(), expected])


func _assert_frozen(
	label: String,
	unit: Node2D,
	expected_position: Vector2,
	sacred_site: Node2D,
	expected_site_timer: float,
	probe: ProcessProbe,
	expected_probe_ticks: int,
	game_manager: Node,
	expected_game_time: float
) -> void:
	if unit.global_position.distance_to(expected_position) > 0.001:
		_fail("real unit moved during %s" % label)
	if not is_equal_approx(float(sacred_site.get("victory_timer")), expected_site_timer):
		_fail("Sacred Site timer advanced during %s" % label)
	if probe.ticks != expected_probe_ticks:
		_fail("inherited gameplay probe processed during %s" % label)
	if not is_equal_approx(float(game_manager.get("game_time")), expected_game_time):
		_fail("GameManager time advanced during %s" % label)


func _wait_frames(frame_count: int) -> void:
	for _frame: int in frame_count:
		await process_frame


func _wait_for(predicate: Callable) -> bool:
	for _frame: int in READY_FRAME_LIMIT:
		if predicate.call():
			return true
		await process_frame
	return false


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[FAIL] match_process_boundary: %s" % message)


func _finish() -> void:
	paused = false
	Engine.time_scale = 1.0
	if is_instance_valid(current_scene):
		current_scene.free()
		current_scene = null
	if _failures.is_empty():
		print("[PASS] match_process_boundary: pause/game-over freeze and ALWAYS controls")
		quit(0)
	else:
		quit(1)
