extends Node2D
## Controlled Godot role-art fixture. This is not a paid match or an input test.

var _folder: String = "res://output/evolution/ux-redesign-20261011/character-after"
var _records: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	get_tree().current_scene = null
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--folder="):
			_folder = argument.trim_prefix("--folder=")
	DirAccess.make_dir_recursive_absolute(_folder)
	for pixels: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for zoom_value: float in [0.62, 1.25, 2.0]:
			await _capture_roles(pixels, zoom_value)
	var receipt: Dictionary = {
		"scope": "Controlled native Godot art fixture: five production unit scenes, both phone sizes, overview/default/detail sprite projection, selected human and enemy roles after two canonical Combat hits. Stroke frame manually advances visual pose only; no paid match, gameplay/input, hardware phone or human-enjoyment evidence.",
		"unit_base_sha256": (load("res://scripts/units/unit_base.gd") as Script).get_source_code().sha256_text(),
		"captures": _records,
	}
	var file: FileAccess = FileAccess.open(_folder + "/manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(receipt, "\t"))
	get_tree().quit()


func _capture_roles(pixels: Vector2i, zoom_value: float) -> void:
	get_window().size = pixels
	get_window().content_scale_size = pixels
	var backdrop := ColorRect.new()
	backdrop.color = Color("88956e")
	backdrop.size = Vector2(pixels)
	add_child(backdrop)
	var title := Label.new()
	title.text = "Pocket Kingdoms miniatures  |  %dx%d  |  %.2fx" % [pixels.x, pixels.y, zoom_value]
	title.position = Vector2(20, 14)
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color("f4edda"))
	add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Human roles above; enemy roles below, recovered after two combat hits"
	subtitle.position = Vector2(20, 39)
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color("243d39"))
	add_child(subtitle)
	var units: Array[UnitBase] = []
	var labels: Array[Label] = []
	var names: Array[String] = ["Worker", "Spear infantry", "Archer", "Scout", "Cavalry"]
	var scenes: Array[String] = ["villager", "infantry", "archer", "scout", "cavalry"]
	var attacker: UnitBase = load("res://scenes/units/infantry.tscn").instantiate() as UnitBase
	add_child(attacker)
	attacker.set_process(false)
	attacker.visible = false
	for row: int in range(2):
		for column: int in range(5):
			var unit: UnitBase = load("res://scenes/units/%s.tscn" % scenes[column]).instantiate() as UnitBase
			unit.player_owner = row
			add_child(unit)
			unit.set_process(false)
			unit.set_team_color(Color("7fc6d0") if row == 0 else Color("ef806d"))
			unit.select()
			unit.position = Vector2(float(pixels.x) * (0.12 + column * 0.19), float(pixels.y) * (0.435 if row == 0 else 0.85))
			unit.scale = Vector2.ONE * zoom_value
			units.append(unit)
			if row == 1:
				Combat.deal_damage(attacker, unit)
				Combat.deal_damage(attacker, unit)
			var label := Label.new()
			label.text = names[column]
			label.position = unit.position + Vector2(-70, 25)
			label.size = Vector2(140, 20)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 14)
			label.add_theme_color_override("font_color", Color("f4edda"))
			add_child(label)
			labels.append(label)
	await get_tree().create_timer(0.35).timeout
	await _save_frame(pixels, zoom_value, "standing", units)
	for index: int in range(units.size()):
		var unit: UnitBase = units[index]
		# Set a visual-only walking/work/attack sample on real scene instances.
		unit.set("_last_visual_position", unit.global_position - Vector2(1.0, 0.0))
		unit.call("_update_sprite_motion", 0.11)
		if index % 5 == 0:
			unit.current_state = UnitBase.State.BUILDING
			unit.set("_last_visual_position", unit.global_position)
			unit.call("_update_sprite_motion", 0.08)
		elif index % 5 in [1, 2, 4]:
			unit.set("_attack_animation_direction", Vector2.RIGHT)
			unit.set("_attack_animation_duration", 0.34)
			unit.set("_attack_animation_remaining", 0.21)
			unit.call("_update_sprite_motion", 0.04)
	await _save_frame(pixels, zoom_value, "stroke", units)
	attacker.free()
	for unit: UnitBase in units:
		unit.free()
	for label: Label in labels:
		label.free()
	title.free()
	subtitle.free()
	backdrop.free()


func _save_frame(pixels: Vector2i, zoom_value: float, pose: String, units: Array[UnitBase]) -> void:
	await RenderingServer.frame_post_draw
	var path: String = "%s/%dx%d-zoom-%d-%s.png" % [_folder, pixels.x, pixels.y, roundi(zoom_value * 100), pose]
	var result: int = get_viewport().get_texture().get_image().save_png(path)
	assert(result == OK)
	var rows: Array[Dictionary] = []
	for unit: UnitBase in units:
		var sprite: Sprite2D = unit.get("_sprite") as Sprite2D
		rows.append({"role": UnitData.get_unit_name(unit.unit_type), "player": unit.player_owner, "settled_tint": str(sprite.modulate), "stable_tint": str(unit.get("_sprite_team_modulate")), "world_bounds": str(unit.get_visual_bounds())})
	_records.append({"pixels": str(pixels), "zoom": zoom_value, "pose": pose, "path": path, "roles": rows})
