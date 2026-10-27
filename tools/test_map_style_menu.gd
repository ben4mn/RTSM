extends Node
## Native viewport evidence for representative style art and the saved-solo menu.
## Saved-match availability is a UI fixture; backend persistence has separate tests.
const MENU := preload("res://scripts/ui/main_menu.gd")
var failures: Array[String] = []
var output: String = "res://build/map-style-menu-evidence"
var captures: Array[String] = []

class SaveFixture extends Node:
	signal save_changed
	var available: bool = true
	var resumed: bool = false
	var discarded: bool = false
	func has_save() -> bool: return available
	func get_summary() -> Dictionary: return {"available": available, "game_time": 754, "map_name": "Twin Lakes"}
	func resume_match() -> bool:
		resumed = true
		return true
	func discard_save(_reason: String) -> bool:
		discarded = true
		available = false
		save_changed.emit()
		return true

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	AudioManager.set_all_enabled(false)
	GameManager.reduced_motion = true
	for dimensions: Vector2i in [Vector2i(844, 390), Vector2i(1280, 720)]:
		get_window().size = dimensions
		get_window().content_scale_size = dimensions
		get_window().content_scale_factor = 1.0
		GameManager.ui_scale = 1.0
		var menu: Control = MENU.new()
		add_child(menu)
		var save := SaveFixture.new()
		add_child(save)
		menu._save_service = save
		menu._refresh_resume()
		menu._refresh_responsive_layout()
		await _frames()
		var prefix := "%dx%d" % [dimensions.x, dimensions.y]
		for button: Button in [menu._resume_button, menu._new_game_button, menu._online_button]:
			_expect(button.is_visible_in_tree() and Rect2(Vector2.ZERO, dimensions).encloses(button.get_global_rect()), prefix + " home button fits: " + button.name)
			_expect(button.size.y >= 48, prefix + " touch target: " + button.name)
		await _capture(prefix + "-resume")
		menu._resume_button.pressed.emit()
		_expect(save.resumed and not save.discarded, "Resume invokes backend without discarding")
		menu._resume_button.disabled = false
		menu._new_game_button.pressed.emit()
		await _frames()
		_expect(not save.discarded and menu.start_button.text == "Start new solo" and menu._selection_summary.text.contains("Replaces your saved solo"), "setup preserves save and clearly labels replacement")
		var art_hashes: Array[int] = []
		for style: int in MapData.MAP_ARCHETYPES:
			menu._select_map(style)
			await _frames()
			await _capture(prefix + "-style-%d" % style)
			var image_a: Image = await _art_image(menu._selected_map_preview)
			menu._selected_map_preview.refresh(style, 987654)
			await _frames()
			var image_b: Image = await _art_image(menu._selected_map_preview)
			_expect(image_a.get_data() == image_b.get_data(), "style illustration does not vary with seed")
			art_hashes.append(hash(image_a.get_data()))
		for style: int in 5:
			_expect(art_hashes.count(art_hashes[style]) == 1, "each map style has distinct rendered art")
		menu._set_map_picker_expanded(true)
		await _frames()
		await _capture(prefix + "-picker")
		for button: Button in menu._map_buttons:
			menu._map_scroll.ensure_control_visible(button)
			await _frames()
			_expect(menu._map_scroll.get_global_rect().grow(1).encloses(button.get_global_rect()), "every style card scrolls into view")
		menu._open_new_game("multiplayer")
		_expect(not save.discarded, "Online browsing preserves solo save")
		menu._show_screen("home")
		save.available = false
		menu._refresh_resume()
		menu._refresh_responsive_layout()
		await _frames()
		_expect(not menu._resume_button.visible and menu._new_game_button.text == "Play solo", "no save restores simple Play solo hierarchy")
		await _capture(prefix + "-new-player")
		menu.free()
		save.free()
		await _frames()
	var receipt := {"scope": "Native Godot rendered UI at 844x390 and 1280x720; five representative map styles, seed-independent artwork, scrollable picker, synthetic valid-save menu. No physical-device or persistence-backend claim.", "captures": captures, "failures": failures}
	FileAccess.open(output.path_join("receipt.json"), FileAccess.WRITE).store_string(JSON.stringify(receipt, "  "))
	for failure: String in failures: push_error("[FAIL] map_style_menu: " + failure)
	if failures.is_empty(): print("[PASS] map_style_menu: five distinct seed-independent dioramas; resume/new/online hierarchy; 844x390 and 1280x720")
	get_tree().quit(0 if failures.is_empty() else 1)

func _frames() -> void:
	for index: int in 8: await get_tree().process_frame

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png"))
	captures.append(label)

func _art_image(control: Control) -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image().get_region(Rect2i(control.get_global_rect()))

func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
