extends Node
## Native phone settings review: real touch navigation plus synthetic safe areas.

const OUTPUT := "res://output/visual-redesign-2026-10-22/settings-review"
const SECTIONS: Array[String] = ["Audio", "Controls", "Display", "Match", "Map"]
var _failures: Array[String] = []
var _records: Array[Dictionary] = []
var _contact_id: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var previous_scale: float = GameManager.ui_scale
	AudioManager.set_all_enabled(false)
	Input.emulate_mouse_from_touch = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for phone: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for notched: bool in [false, true]:
			await _profile(phone, notched)
	GameManager.ui_scale = previous_scale
	GameManager.save_preferences()
	var receipt := FileAccess.open(OUTPUT.path_join("receipt.json"), FileAccess.WRITE)
	receipt.store_string(JSON.stringify({"scope": "Native root-window renders at actual phone pixel sizes and1.15 UI scale. Settings and each tab opened using ScreenTouch. Safe areas are synthetic44px sides/18px bottom on notched profiles.", "profiles": _records, "failures": _failures}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] settings_review: " + failure)
	if _failures.is_empty():
		print("[PASS] settings_review: 20 actual native settings screens, real touch tab navigation, both phone sizes at maximum scale, ordinary and notched safe areas")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _profile(phone: Vector2i, notched: bool) -> void:
	get_window().size = phone
	get_window().content_scale_size = Vector2i(844, 390)
	get_window().content_scale_factor = 1.15
	GameManager.ui_scale = 1.15
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await _frames(8)
	await _tap(menu.get("settings_button"))
	var settings: Control = menu.get("_shared_settings")
	if settings == null:
		_failures.append("Settings touch failed at " + str(phone))
		menu.free()
		return
	var viewport: Viewport = get_viewport()
	var logical: Vector2 = viewport.get_visible_rect().size
	var transform: Transform2D = viewport.get_final_transform()
	var pixel_scale := Vector2(transform.x.length(), transform.y.length())
	var safe := Rect2(Vector2.ZERO, logical)
	if notched:
		safe = Rect2(Vector2(44.0 / pixel_scale.x, 0.0), logical - Vector2(88.0 / pixel_scale.x, 18.0 / pixel_scale.y))
	for index: int in SECTIONS.size():
		await _tap(settings.find_child(SECTIONS[index] + "Tab", true, false))
		menu.call("apply_mobile_layout", logical, safe)
		await _frames(4)
		var name: String = "%dx%d-max-%s-%s" % [phone.x, phone.y, "notched" if notched else "ordinary", SECTIONS[index].to_lower()]
		_expect(int(settings.get("_section")) == index, "touch selected " + name)
		var card: Control = settings.get("_panel")
		var scroll: Control = settings.get("_scroll")
		var body: Control = settings.get("_body")
		_expect(safe.grow(0.5).encloses(card.get_global_rect()), "card within safe area " + name)
		_expect(scroll.get_global_rect().grow(1.0).encloses(body.get_global_rect()), "all settings fit without hidden scrolling " + name)
		var controls: Array[Dictionary] = []
		for child: Node in settings.find_children("*", "Control", true, false):
			var control := child as Control
			if not control.is_visible_in_tree() or not (control is BaseButton or control is Label or control is Range or control is LineEdit):
				continue
			var rect: Rect2 = control.get_global_rect()
			_expect(safe.grow(0.5).encloses(rect), "visible control inside safe area: " + name + " " + control.name)
			controls.append({"name": str(control.name), "rect": str(rect), "text": str(control.get("text")) if control is Label or control is Button or control is LineEdit else ""})
			if control is BaseButton:
				_expect(control.size.y * pixel_scale.y >= 47.5, "48px physical touch height " + name + " " + control.name)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var bitmap: Image = viewport.get_texture().get_image()
			_expect(bitmap.get_size() == phone, "actual phone-sized capture " + name)
			bitmap.save_png(OUTPUT.path_join(name + ".png"))
		_records.append({"name": name, "phone": str(phone), "safe_logical": str(safe), "logical_size": str(logical), "pixel_scale": str(pixel_scale), "controls": controls})
	await _tap(settings.find_child("SettingsDoneButton", true, false))
	_expect(not is_instance_valid(menu.get("_shared_settings")), "Done closes settings at " + str(phone))
	menu.free()
	await _frames(3)


func _tap(control: Control) -> void:
	if not is_instance_valid(control):
		_failures.append("Missing touch target")
		return
	_contact_id += 1
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = _contact_id
		event.position = get_viewport().get_final_transform() * control.get_global_rect().get_center()
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)
	await _frames(3)


func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
