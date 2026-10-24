extends Node
## Development-only actual texture/geometry gallery, not a gameplay test.

var destination: String = "res://output/kingdom-art-gallery.png"
var gallery: SubViewport


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		destination = args[0]
	call_deferred("_run")


func _run() -> void:
	var root: Window = get_tree().root
	# Isolate the gallery from the game's responsive window/content scaling.
	gallery = SubViewport.new()
	gallery.size = Vector2i(1800, 1500)
	gallery.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(gallery)
	var manager: Node = root.get_node("GameManager")
	manager.players.clear()
	manager.current_state = 0
	root.get_node("AudioManager").set_all_enabled(false)
	var background := ColorRect.new()
	background.color = Color("183332")
	background.size = Vector2(1800, 1500)
	gallery.add_child(background)
	for civilization: int in 3:
		manager.selected_civilization = civilization
		manager.selected_opponent_civilization = civilization
		var left: float = 30.0 + civilization * 600.0
		_label(CivilizationData.get_civilization_name(civilization), Vector2(left, 18), 28)
		_label("Actual world scale × 1.25 · teal ally / clay rival", Vector2(left, 56), 16)
		for kind: int in 6:
			var unit: UnitBase = load("res://scenes/units/unit_base.tscn").instantiate()
			unit.unit_type = kind
			unit.player_owner = kind % 2
			unit.position = Vector2(left + 80 + (kind % 3) * 180, 150 + floori(kind / 3.0) * 110)
			unit.scale = Vector2.ONE * 1.25
			gallery.add_child(unit)
			unit.set_process(false)
			_label(UnitData.get_unit_name(kind, kind % 2), unit.position + Vector2(-55, 18), 16)
		var index: int = 0
		for kind: int in KingdomArt.BUILDING_NAMES:
			var building := BuildingBase.new()
			building.building_type = kind
			building.player_owner = index % 2
			building.state = BuildingBase.State.ACTIVE
			gallery.add_child(building)
			building.set_process(false)
			building.scale = Vector2.ONE * 1.25
			var center := Vector2(left + 120 + (index % 2) * 280, 490 + floori(index / 2.0) * 225)
			building.position = center - building._footprint_center * building.scale
			_label(building.building_name, center + Vector2(-100, 60), 16)
			index += 1
	for frame: int in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var screenshot: Image = gallery.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(destination)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var status: Error = screenshot.save_png(path)
	print("Kingdom art gallery: " + path + " status=" + str(status))
	get_tree().quit(0 if status == OK else 1)


func _label(text: String, at: Vector2, point_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_override("font", load("res://assets/fonts/Barlow-Medium.ttf"))
	label.add_theme_font_size_override("font_size", point_size)
	label.add_theme_color_override("font_color", Color("f4eddd"))
	gallery.add_child(label)
