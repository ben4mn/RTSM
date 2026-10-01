extends Node
## Real-main-scene wiring regression for the touch unit command rail.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const READY_FRAME_LIMIT := 900

var _failures: Array[String] = []
var _match_scene: Node = null


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_manager: Node = get_node("/root/GameManager")
	var audio_manager: Node = get_node("/root/AudioManager")
	audio_manager.call("set_all_enabled", false)
	game_manager.set("guided_opening_enabled", false)
	var match_scene: Node = load(MAIN_SCENE).instantiate()
	_match_scene = match_scene
	add_child(match_scene)
	if not await _wait_for(func() -> bool:
		return int(game_manager.get("current_state")) == 2 and not ((match_scene.get("_player_units") as Array)[0] as Array).is_empty()
	):
		_fail("match did not reach a playable state")
		_finish()
		return

	var game_map: Node = match_scene.get_node("GameMap")
	var selection_manager: SelectionManager = game_map.get("selection_mgr") as SelectionManager
	var hud: CanvasLayer = match_scene.get_node("HUD") as CanvasLayer
	var villager: UnitBase = ((match_scene.get("_player_units") as Array)[0] as Array)[0] as UnitBase
	selection_manager.select_single(villager)
	await get_tree().process_frame
	var command_container: HBoxContainer = hud.get("_unit_command_container") as HBoxContainer
	var advanced_container: HBoxContainer = hud.get("_advanced_command_container") as HBoxContainer
	_expect(command_container.visible, "owned unit selection does not expose the touch command rail")
	_expect((advanced_container.get_node("UnitPatrolButton") as Button).disabled, "villager-only Patrol should be disabled")

	var resources: Array[Node] = get_tree().get_nodes_in_group("resources")
	_expect(not resources.is_empty(), "live match did not expose a resource target fixture")
	(command_container.get_node("UnitMoveButton") as Button).pressed.emit()
	_expect(bool(match_scene.get("_move_command_armed")), "Move button does not arm forced movement")
	_expect(not bool(match_scene.get("_attack_move_command_armed")), "Move button leaves A-Move armed")
	if not resources.is_empty():
		match_scene.call("_on_gather_command", resources[0] as Node2D)
	_expect(not bool(match_scene.get("_move_command_armed")), "Move mode is not one-shot")
	_expect(not selection_manager.unit_command_armed, "SelectionManager retains Move interception after the one-shot command")
	_expect_eq(villager.current_state, UnitBase.State.MOVING, "Move-on-resource was reinterpreted as gathering")
	_expect(bool(villager.get("_force_move_active")), "Move-on-resource does not preserve the no-engagement override")
	villager.command_stop()

	(command_container.get_node("UnitMoreButton") as Button).pressed.emit()
	_expect((hud.get("_advanced_command_panel") as PanelContainer).visible, "More does not reveal advanced orders")
	(advanced_container.get_node("UnitAttackMoveButton") as Button).pressed.emit()
	_expect(bool(match_scene.get("_attack_move_command_armed")), "A-Move button does not arm attack-move")
	match_scene.call("_on_move_command", game_map.call("world_to_tile", villager.global_position) + Vector2i(0, 2))
	_expect(not bool(match_scene.get("_attack_move_command_armed")), "A-Move mode is not one-shot")

	var initial_stance: int = villager.stance
	(advanced_container.get_node("UnitStanceButton") as Button).pressed.emit()
	_expect(villager.stance != initial_stance, "Stance button does not toggle selected unit stance")
	(command_container.get_node("UnitStopButton") as Button).pressed.emit()
	_expect_eq(villager.current_state, UnitBase.State.IDLE, "Stop button does not stop the selected unit")

	var scout: UnitBase = match_scene.call("_spawn_unit", UnitData.UnitType.SCOUT, 0, villager.global_position + Vector2(24.0, 0.0)) as UnitBase
	_expect(scout != null, "could not spawn a military fixture within the live population cap")
	if scout != null:
		var house_scene: PackedScene = load("res://scenes/buildings/house.tscn")
		var foundation: BuildingBase = house_scene.instantiate() as BuildingBase
		foundation.player_owner = 0
		foundation.global_position = villager.global_position + Vector2(160.0, 0.0)
		game_map.get_node("BuildingsContainer").add_child(foundation)
		foundation.start_construction()
		var mixed_selection: Array[Node2D] = [villager, scout]
		selection_manager.select_many(mixed_selection)
		await get_tree().process_frame
		(advanced_container.get_node("UnitAttackMoveButton") as Button).pressed.emit()
		_expect(bool(match_scene.get("_attack_move_command_armed")), "mixed selection did not arm A-Move")
		match_scene.call("_on_build_command", foundation)
		_expect(not bool(match_scene.get("_attack_move_command_armed")), "A-Move-on-foundation is not one-shot")
		_expect_eq(villager.current_state, UnitBase.State.MOVING, "A-Move-on-foundation was reinterpreted as construction")
		_expect(villager.get("build_target") != foundation, "A-Move-on-foundation assigned a build target")
		_expect(bool(villager.get("attack_move")), "A-Move-on-foundation did not arm the Villager's attack-move")
		_expect(bool(scout.get("attack_move")), "A-Move-on-foundation did not arm the Scout's attack-move")
		villager.command_stop()
		scout.command_stop()

		selection_manager.select_single(scout)
		await get_tree().process_frame
		_expect(not (advanced_container.get_node("UnitPatrolButton") as Button).disabled, "military selection does not enable Patrol")
		(advanced_container.get_node("UnitPatrolButton") as Button).pressed.emit()
		_expect(bool(match_scene.get("_patrol_command_armed")), "Patrol button does not arm a destination")

	(command_container.get_node("UnitClearButton") as Button).pressed.emit()
	await get_tree().process_frame
	_expect(selection_manager.selected.is_empty(), "Clear button does not clear selection")
	_expect(not (hud.get("selection_panel") as PanelContainer).visible, "selection shelf remains visible after Clear")
	_expect(not bool(match_scene.get("_patrol_command_armed")), "Clear leaves Patrol armed")
	_finish()


func _wait_for(predicate: Callable) -> bool:
	for _frame in READY_FRAME_LIMIT:
		if predicate.call():
			return true
		await get_tree().process_frame
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, expected, actual])


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("[FAIL] mobile_unit_commands: %s" % message)


func _finish() -> void:
	if is_instance_valid(_match_scene):
		_match_scene.free()
		_match_scene = null
	if _failures.is_empty():
		print("[PASS] mobile_unit_commands: live Move/A-Move/Patrol/Stop/Stance/Clear wiring")
		get_tree().quit(0)
	else:
		get_tree().quit(1)
