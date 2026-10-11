extends Node2D
## Controlled visual fixture: stable role/team sprites after resolved hit bursts.

var _folder: String = "res://output/evolution/damage-team-feedback-20261010/rendered-after"


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
	var records: Array[Dictionary] = []
	for pixels: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for zoom_value: float in [0.65, 1.6]:
			get_window().size = pixels
			get_window().content_scale_size = pixels
			var backdrop := ColorRect.new()
			backdrop.color = Color("15282c")
			backdrop.size = Vector2(pixels)
			add_child(backdrop)
			var title := Label.new()
			title.text = "Team color after damage  |  %dx%d  |  zoom %.2f" % [pixels.x, pixels.y, zoom_value]
			title.position = Vector2(24, 24)
			title.add_theme_font_size_override("font_size", 20)
			add_child(title)
			var units: Array[UnitBase] = []
			var labels: Array[Label] = []
			for index: int in range(4):
				var defender: UnitBase = load("res://scenes/units/infantry.tscn").instantiate() as UnitBase
				defender.player_owner = 0 if index == 0 else 1
				add_child(defender)
				defender.set_process(false)
				defender.position = Vector2(float(pixels.x) * (0.16 + index * 0.225), float(pixels.y) * 0.57)
				defender.scale = Vector2.ONE * zoom_value
				units.append(defender)
				var label := Label.new()
				label.text = ["Friendly control", "Enemy control", "Enemy: one hit", "Enemy: two hits"][index]
				label.position = defender.position + Vector2(-70, 50)
				label.add_theme_font_size_override("font_size", 16)
				add_child(label)
				labels.append(label)
			var attacker: UnitBase = load("res://scenes/units/infantry.tscn").instantiate() as UnitBase
			add_child(attacker)
			attacker.set_process(false)
			attacker.visible = false
			Combat.deal_damage(attacker, units[2])
			Combat.deal_damage(attacker, units[3])
			Combat.deal_damage(attacker, units[3])
			await get_tree().create_timer(0.35).timeout
			await RenderingServer.frame_post_draw
			var path: String = "%s/%dx%d-zoom-%d.png" % [_folder, pixels.x, pixels.y, roundi(zoom_value * 100)]
			var result: int = get_viewport().get_texture().get_image().save_png(path)
			assert(result == OK)
			records.append({"pixels": str(pixels), "zoom": zoom_value, "path": path, "enemy_control": str((units[1].get("_sprite") as Sprite2D).modulate), "enemy_single_hit": str((units[2].get("_sprite") as Sprite2D).modulate), "enemy_burst": str((units[3].get("_sprite") as Sprite2D).modulate)})
			attacker.free()
			for unit: UnitBase in units:
				unit.free()
			for label: Label in labels:
				label.free()
			title.free()
			backdrop.free()
	var receipt: Dictionary = {"scope": "Controlled native visual fixture; stable sprites 0.35s after canonical Combat hits, both phone pixel sizes and overview/detail sprite scales. No paid match, gameplay/input, physical phone or accessibility user study.", "unit_base_sha256": (load("res://scripts/units/unit_base.gd") as Script).get_source_code().sha256_text(), "captures": records}
	var file: FileAccess = FileAccess.open(_folder + "/manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(receipt, "\t"))
	get_tree().quit()
