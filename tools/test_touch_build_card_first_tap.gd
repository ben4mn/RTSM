extends Node
## H (G1), L2: the first world tap right after choosing a building on the Build
## sheet must count (it used to be swallowed when it came quickly): off the
## ghost it moves it, on the ghost it builds.
## Real phone-style dispatch through Input.parse_input_event.

var _failures: Array[String] = []
var _main: Node = null
var _placement: BuildingPlacement = null
var _hud: CanvasLayer = null
var _index: int = 10


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	get_window().size = Vector2i(844, 390)
	get_window().content_scale_factor = 1.0
	Input.emulate_mouse_from_touch = true
	GameManager.guided_opening_enabled = false
	GameManager.selected_population_limit = 80
	GameManager.selected_map_seed = 101
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)
	for _frame: int in 900:
		if _main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	if GameManager.current_state == GameManager.GameState.PAUSED:
		GameManager.set_paused(false)
	_placement = _main.get("_building_placement") as BuildingPlacement
	_hud = _main.get_node("HUD") as CanvasLayer
	_main.get_node("AIController").process_mode = Node.PROCESS_MODE_DISABLED
	ResourceManager._player_resources[0] = {"food": 5000, "wood": 5000, "gold": 5000}
	for frames_between: int in [2, 6, 18]:
		await _attempt(frames_between)
	_finish()


func _attempt(frames_between: int) -> void:
	var houses_before: int = _count_houses()
	var launcher: Control = _hud.get("build_menu_button") as Control
	if launcher != null and launcher.is_visible_in_tree():
		await _tap(launcher.get_global_rect().get_center(), 2)
	else:
		_hud.call("_on_build_menu_pressed")
	for _f: int in 6:
		await get_tree().process_frame
	var menu: Node = _main.get("_build_menu") as Node
	var card: Button = menu.get("_button_map").get(BuildingData.BuildingType.HOUSE) as Button if menu != null else null
	if card == null or not card.is_visible_in_tree():
		_failures.append("House card not visible (frames %d)" % frames_between)
		return
	var card_center: Vector2 = card.get_global_rect().get_center()
	await _tap(card_center, 2)
	if not _placement.active:
		_failures.append("card tap did not start placement (frames %d)" % frames_between)
		return
	for _f: int in frames_between:
		await get_tree().process_frame
	# L2: the first world tap after the card is never swallowed. Off the ghost
	# it moves the ghost there; on the ghost (or its Build button) it builds.
	var placed: bool = false
	var ghost_center: Vector2 = _placement.get_ghost_footprint_screen_rect().get_center()
	for spot: Vector2 in [Vector2(200, 120), Vector2(620, 140), Vector2(160, 200), Vector2(650, 220)]:
		if _placement.is_screen_point_on_ghost(spot) or (_hud.call("get_placement_ghost_card") as PlacementGhostCard).get_build_button_rect().grow(8.0).has_point(spot):
			continue
		await _tap(spot, 2)
		for _f: int in 3:
			await get_tree().process_frame
		_expect_no_build(houses_before, "an off-ghost tap %d frames after the card" % frames_between)
		var moved_center: Vector2 = _placement.get_ghost_footprint_screen_rect().get_center()
		if moved_center.distance_to(spot) > 40.0:
			_failures.append("a world tap %d frames after the card did not move the ghost (ghost %s, tap %s, was %s)" % [frames_between, moved_center, spot, ghost_center])
		break
	# Back to a valid spot, then one tap on the ghost builds it.
	_main.call("_snap_placement_to_best_spot", BuildingData.BuildingType.HOUSE)
	for _f: int in 3:
		await get_tree().process_frame
	await _real_wait(400)
	await _tap(_placement.get_ghost_footprint_screen_rect().get_center(), 2)
	for _f: int in 3:
		await get_tree().process_frame
	placed = _count_houses() == houses_before + 1
	if _placement.active:
		_main.call("_cancel_placement")
	if not placed:
		_failures.append("no House placed by tapping the ghost (frames %d)" % frames_between)
	for _f: int in 10:
		await get_tree().process_frame


func _expect_no_build(houses_before: int, label: String) -> void:
	if _count_houses() != houses_before:
		_failures.append("%s built a House" % label)


func _tap(position: Vector2, hold_frames: int) -> void:
	_index += 1
	var press := InputEventScreenTouch.new()
	press.index = _index
	press.position = position
	press.pressed = true
	Input.parse_input_event(press)
	for _f: int in hold_frames:
		await get_tree().process_frame
	var release := InputEventScreenTouch.new()
	release.index = _index
	release.position = position
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().process_frame
	await get_tree().process_frame


func _count_houses() -> int:
	var count: int = 0
	for building: Variant in _main.get("_player_buildings")[0]:
		if is_instance_valid(building) and (building as BuildingBase).building_type == BuildingData.BuildingType.HOUSE:
			count += 1
	return count


func _finish() -> void:
	if is_instance_valid(_main):
		_main.free()
	if _failures.is_empty():
		print("[PASS] touch_build_card_first_tap: first world tap after a Build card moves/builds at 2/6/18 frames")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] touch_build_card_first_tap: " + failure)
		get_tree().quit(1)


## Real (wall-clock) time: the 0.35 s double-confirm guard is measured in it.
func _real_wait(msec: int) -> void:
	var until: int = Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
