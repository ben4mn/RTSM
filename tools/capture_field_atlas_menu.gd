extends Node
## Native captures of the actual menu, plus typography and motion-contract checks.

var _failures: Array[String] = []
const OUTPUT := "res://output/visual-redesign-2026-10-22/menu"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var had_preferences: bool = FileAccess.file_exists(GameManager.PREFERENCES_PATH)
	var previous_preferences: PackedByteArray = FileAccess.get_file_as_bytes(GameManager.PREFERENCES_PATH) if had_preferences else PackedByteArray()
	var original: Dictionary = {}
	for key: String in ["selected_map_archetype", "selected_map_seed", "ui_scale", "reduced_motion", "audio_enabled"]:
		original[key] = GameManager.get(key)
	AudioManager.set_all_enabled(false)
	GameManager.audio_enabled = false
	GameManager.selected_map_seed = 101
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var icon_image := Image.new()
	icon_image.load_svg_from_string(FileAccess.get_file_as_string("res://icon.svg"), 4.0)
	icon_image.save_png(OUTPUT.path_join("app-mark.png"))
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for scale: float in [1.0, 1.15]:
			get_window().size = phone
			get_window().content_scale_size = Vector2i(844, 390)
			get_window().content_scale_factor = scale
			GameManager.ui_scale = scale
			for archetype: int in MapData.MAP_ARCHETYPES:
				GameManager.selected_map_archetype = archetype
				GameManager.reduced_motion = true
				var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
				add_child(menu)
				await _frames(8)
				var suffix: String = "%dx%d-scale%s-map%d" % [phone.x, phone.y, scale, archetype]
				var title: Label = menu.get("title_label")
				var hero: Control = menu.get("_hero")
				_expect(hero.get_global_rect().encloses(title.get_global_rect()), "wordmark stays within visual column " + suffix)
				for control: Control in [menu.get("start_button"), menu.get("_online_button"), menu.get("settings_button"), menu.get("guided_opening_toggle")]:
					_expect(control.size.y >= 48.0, "touch action reaches 48px " + suffix)
				var art: Control = menu.get("_hero_art")
				var phase: float = art.get("_elapsed")
				await _frames(3)
				_expect(is_equal_approx(phase, float(art.get("_elapsed"))), "Reduced Motion freezes decorative formations " + suffix)
				if DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png(OUTPUT.path_join(suffix + ".png"))
				if phone.x == 844 and scale == 1.0 and archetype == 1:
					var file := FileAccess.open("res://web/field_atlas.svg", FileAccess.WRITE)
					file.store_string(str(art.call("get_web_svg_source")))
				menu.free()
	for key: String in original:
		GameManager.set(key, original[key])
	if had_preferences:
		var preferences := FileAccess.open(GameManager.PREFERENCES_PATH, FileAccess.WRITE)
		preferences.store_buffer(previous_preferences)
	elif FileAccess.file_exists(GameManager.PREFERENCES_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameManager.PREFERENCES_PATH))
	for failure: String in _failures:
		push_error("[FAIL] field_atlas_menu: " + failure)
	if _failures.is_empty():
		print("[PASS] field_atlas_menu: 12 native menu profiles, wordmark bounds, 48px actions and Reduced Motion; web atlas exported from actual River Crossings seed101")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
