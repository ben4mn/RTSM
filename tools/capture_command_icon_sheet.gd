extends Node
## Actual Godot SVG imports at32px and in48px controls with24px glyphs.

const OUTPUT := "res://output/visual-redesign-2026-10-22/icon-sheet.png"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	get_window().size = Vector2i(1280, 780)
	get_window().content_scale_size = Vector2i(1280, 780)
	get_window().content_scale_factor = 1.0
	var background := ColorRect.new()
	background.color = KingdomTheme.INK
	background.size = Vector2(1280, 780)
	add_child(background)
	var title := Label.new()
	title.text = "FIELD COMPANY / COMMAND EQUIPMENT"
	title.position = Vector2(18, 12)
	title.theme = KingdomTheme.create_theme()
	title.add_theme_font_override("font", KingdomTheme.FONT_HEADING)
	title.add_theme_font_size_override("font_size", 24)
	add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Native SVG imports:32px master ·24px normal and pressed controls"
	subtitle.position = Vector2(18, 42)
	subtitle.theme = KingdomTheme.create_theme()
	subtitle.add_theme_color_override("font_color", KingdomTheme.MUTED)
	add_child(subtitle)
	var keys: Array[String] = []
	for file: String in DirAccess.get_files_at("res://assets/ui/icons"):
		if file.ends_with(".svg"):
			keys.append(file.get_basename())
	keys.sort()
	for index: int in keys.size():
		var key: String = keys[index]
		var origin := Vector2(16 + (index % 8) * 156, 84 + (index / 8) * 112)
		var label := Label.new()
		label.text = key
		label.position = origin
		label.theme = KingdomTheme.create_theme()
		label.add_theme_font_size_override("font_size", 14)
		add_child(label)
		var texture: Texture2D = load("res://assets/ui/icons/%s.svg" % key)
		var preview := TextureRect.new()
		preview.texture = texture
		preview.position = origin + Vector2(2, 34)
		preview.size = Vector2(32, 32)
		if key == "play_dark":
			var plate := ColorRect.new()
			plate.color = KingdomTheme.PARCHMENT
			plate.position = origin + Vector2(0, 32)
			plate.size = Vector2(36, 36)
			add_child(plate)
		add_child(preview)
		for pressed: bool in [false, true]:
			var button := Button.new()
			button.position = origin + Vector2(98 if pressed else 44, 27)
			button.size = Vector2(48, 48)
			button.theme = KingdomTheme.create_theme()
			button.icon = texture
			button.toggle_mode = true
			button.button_pressed = pressed
			button.add_theme_constant_override("icon_max_width", 24)
			button.add_theme_color_override("icon_normal_color", KingdomTheme.PARCHMENT)
			button.add_theme_color_override("icon_pressed_color", KingdomTheme.INK)
			if key == "play_dark":
				KingdomTheme.apply_primary(button)
				button.add_theme_color_override("icon_normal_color", Color.WHITE)
				button.add_theme_color_override("icon_pressed_color", Color.WHITE)
			add_child(button)
	for frame: int in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUTPUT)
	print("[PASS] command_icon_sheet: ", keys.size(), " SVGs imported and rendered at32/24px with normal and pressed theme contrast")
	get_tree().quit()
