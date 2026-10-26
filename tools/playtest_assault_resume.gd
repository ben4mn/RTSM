extends Node
## Manual, staged combat witness; never exported with the production game.
## Select the blue Warrior and tap the red House. R resets the staged encounter.
var main: Node
var map: Node2D
var fighter: UnitBase
var threat: UnitBase
var house: BuildingBase
var center: Vector2
var launched: bool = false
var reported_retaliation: bool = false
var reported_resume: bool = false

func _ready() -> void:
	call_deferred("_setup")

func _setup() -> void:
	get_window().size = Vector2i(667, 375)
	get_window().title = "Pocket Kingdoms - staged assault playtest"
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_civilization = CivilizationData.Civilization.CROWNLANDS
	GameManager.selected_opponent_civilization = CivilizationData.Civilization.CROWNLANDS
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	while main.get("_building_placement") == null:
		await get_tree().process_frame
	main.ai_controller.set_process(false)
	main.set_process(false)
	main.ai_controller.get("_decision_timer").stop()
	map = main.game_map
	map.fog_of_war.set_process(false)
	map.fog_of_war.reveal_all()
	map.fog_of_war.fog_layer.clear()
	for unit: UnitBase in get_tree().get_nodes_in_group("units"):
		unit.command_stop()
		unit.set_process(false)
	# Find an ordinary unobstructed region; all movement still uses real navigation.
	var tile := Vector2i(20, 20)
	for x: int in range(15, 60):
		var clear: bool = true
		for dx: int in range(-4, 5):
			for dy: int in range(-4, 5):
				if not map.is_tile_walkable(Vector2i(x + dx, 20 + dy)):
					clear = false
		if clear:
			tile = Vector2i(x, 20)
			break
	center = map.tile_to_world(tile)
	house = main._spawn_building(BuildingData.BuildingType.HOUSE, 1, tile)
	house.complete_instantly()
	fighter = main._spawn_unit(UnitData.UnitType.INFANTRY, 0, center + Vector2(-160, 50))
	fighter.stance = UnitBase.Stance.STAND_GROUND
	fighter.visible = true
	house.visible = true
	map.note_camera_interaction()
	map.camera.position = center + Vector2(-30, 20)
	map.camera.zoom = Vector2.ONE
	map.camera.reset_smoothing()
	map.camera.force_update_scroll()
	_reset()

func _reset() -> void:
	if is_instance_valid(threat): threat.queue_free()
	fighter.command_stop()
	fighter.global_position = center + Vector2(-160, 50)
	fighter.hp = fighter.max_hp
	house.hp = house.max_hp
	launched = false
	reported_retaliation = false
	reported_resume = false
	main.hud.show_notification("Staged test: select Warrior, tap enemy House. R resets.", Color.WHITE)
	print("[MANUAL] ready for player building-attack input")

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R and is_instance_valid(fighter):
		_reset()

func _process(_delta: float) -> void:
	if not is_instance_valid(fighter) or not is_instance_valid(house): return
	if not launched and fighter.attack_building_target == house and house.hp < house.max_hp:
		launched = true
		threat = main._spawn_unit(UnitData.UnitType.INFANTRY, 1, fighter.global_position + Vector2(-30, 20))
		threat.hp = 24
		threat.command_attack(fighter)
		print("[MANUAL] actual building hit; staged attacker released")
	if launched and not reported_retaliation and is_instance_valid(threat) and fighter.attack_target == threat:
		reported_retaliation = true
		print("[MANUAL] fighter retaliating against actual attacker")
	if reported_retaliation and not reported_resume and fighter.attack_building_target == house:
		reported_resume = true
		main.hud.show_notification("Threat defeated; original House attack resumed.", Color.WHITE)
		print("[MANUAL] resumed original House attack")
