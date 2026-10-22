extends Node
## Native phone-scale visual receipt of the six real unit scenes and owner variants.

const OUTPUT: String = "res://output/battle-art-2026-10-22"
const ROLES: Array[String] = ["Builder", "Warrior", "Archer", "Horseman", "Scout", "Siege"]
const SCENES: Array[String] = ["villager", "infantry", "archer", "cavalry", "scout", "siege"]
var _units: Array[UnitBase] = []
var _role_labels: Array[Label] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	GameManager.set_process(false)
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = 0
	GameManager.current_state = GameManager.GameState.PLAYING
	GameManager.ui_scale = 1.0
	get_window().size = Vector2i(844, 390)
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = 1.0
	var game_map: Node2D = load("res://scenes/map/game_map.tscn").instantiate()
	add_child(game_map)
	await get_tree().process_frame
	_disable_processes(game_map)
	game_map.get_node("FogLayer").hide()
	(game_map.get_node("FogOfWar") as FogManager).owning_player = -1
	for resource: Node in get_tree().get_nodes_in_group("resources"):
		(resource as CanvasItem).hide()
	for site: Node in get_tree().get_nodes_in_group("sacred_sites"):
		(site as CanvasItem).hide()
	var center: Vector2 = game_map.tile_to_world(Vector2i(36, 36))
	var camera: Camera2D = game_map.get_node("Camera2D")
	camera.position = center
	camera.zoom = Vector2(1.1, 1.1)
	for owner: int in 2:
		for role: int in SCENES.size():
			var unit: UnitBase = load("res://scenes/units/" + SCENES[role] + ".tscn").instantiate()
			unit.player_owner = owner
			unit.position = center + Vector2(-280.0 + role * 112.0, -60.0 + owner * 130.0)
			game_map.get_node("UnitsContainer").add_child(unit)
			unit.set_process(false)
			_units.append(unit)
	var overlay := CanvasLayer.new()
	add_child(overlay)
	_label(overlay, "THE COMPANY  /  SIX BATTLEFIELD SILHOUETTES", Vector2(24, 18), 15)
	_label(overlay, "YOUR COMPANY", Vector2(24, 50), 12)
	_label(overlay, "OPPOSING COMPANY", Vector2(24, 205), 12)
	for role: int in ROLES.size():
		var x: float = 422.0 + (-280.0 + role * 112.0) * 1.1 - 38.0
		_role_labels.append(_label(overlay, ROLES[role], Vector2(x, 154), 13, 76))
		_role_labels.append(_label(overlay, ROLES[role], Vector2(x, 297), 13, 76))
	GameManager.clearer_player_markers = false
	await _capture("roles-phone.png")
	GameManager.clearer_player_markers = true
	_units[1].is_selected = true
	_units[8].hp = _units[8].max_hp * 0.25
	_units[4].stance = UnitBase.Stance.STAND_GROUND
	for unit: UnitBase in _units:
		unit.queue_redraw()
	await _capture("roles-phone-accessible.png")
	camera.zoom = Vector2(0.75, 0.75)
	for role: int in ROLES.size():
		_role_labels[role * 2].position.x = 422.0 + (-280.0 + role * 112.0) * 0.75 - 38.0
		_role_labels[role * 2 + 1].position.x = _role_labels[role * 2].position.x
	await _capture("roles-phone-zoomed-out.png")
	print("[PASS] capture_battle_art: six actual roles, both owners, selected/critical/Stand Ground and clearer-player-marker variants")
	get_tree().quit()


func _label(parent: Node, text: String, at: Vector2, font_size: int, width: float = 0.0) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_color_override("font_color", Color("293235"))
	label.add_theme_font_override("font", load("res://assets/fonts/Barlow-Medium.ttf"))
	label.add_theme_font_size_override("font_size", font_size)
	if width > 0.0:
		label.size.x = width
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


func _capture(filename: String) -> void:
	for frame: int in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(filename))


func _disable_processes(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children():
		_disable_processes(child)
