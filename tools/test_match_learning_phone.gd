extends Node
## Label shaping, touch target and safe-bounds coverage for optional lessons.

var failures: Array[String] = []
var profiles: Array[Dictionary] = []
var inputs: Array[Dictionary] = []
const LESSON_TEXTS: Array[String] = [
	"Army · Gather Food + Wood. Build a Barracks, then recruit a Warrior.",
	"Army · Select Barracks → Warrior. Queued troops must finish training.",
	"Counters · Add Archers at an Archery Range. Archers beat Warriors; Warriors beat Horsemen.",
	"Counters · Enemy Horseman: recruit Warrior at Barracks.",
	"Retreat · Select hurt troops → Move → safe ground. Attack fights on the way.",
	"Recover · Home → Villager. Food restores your gathering economy.",
	"Recover · Recruit replacement troops. Keep Food + Wood workers gathering.",
	"Sacred · Tap the Site locator; send your army into its ring to capture or contest.",
	"Sacred · Both sides are in the ring. The victory clock is paused; reinforce.",
	"Sacred · Hold for 10:00. Rally replacements nearby and protect your workers.",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_tree().root.get_node("GameManager").initialize_game(2)
	get_tree().root.get_node("ResourceManager").initialize_player(0)
	for physical: Vector2 in [Vector2(844, 390), Vector2(932, 430)]:
		for scale_value: float in [1.0, 1.075, 1.15]:
			for notched: bool in [false, true]:
				await _check_profile(physical, scale_value, notched)
	await _check_root_input(Vector2i(844, 390))
	await _check_root_input(Vector2i(932, 430))
	DirAccess.make_dir_recursive_absolute("res://output/evolution/learning-20261010-battle-lessons")
	var output := FileAccess.open("res://output/evolution/learning-20261010-battle-lessons/phone-lessons.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"scope": "Headless SubViewport Control/font shaping and synthetic screen-touch dispatch; no device rendering or performance claim", "profiles": profiles, "inputs": inputs, "failures": failures}, "\t"))
	if failures.is_empty():
		print("[PASS] match_learning_phone: ten instructions, Skip, Pause lessons action, 12 phone/scale/safe-area profiles")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("[FAIL] match_learning_phone: " + failure)
		get_tree().quit(1)


func _check_profile(physical: Vector2, scale_value: float, notched: bool) -> void:
	var logical := Vector2(floorf(physical.x / scale_value), floorf(physical.y / scale_value))
	var inset: float = 44.0 / scale_value if notched else 0.0
	var safe := Rect2(Vector2(inset, 0.0), logical - Vector2(inset * 2.0, 18.0 / scale_value if notched else 0.0))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(logical)
	viewport.gui_disable_input = false
	add_child(viewport)
	var hud: CanvasLayer = load("res://scenes/ui/hud.tscn").instantiate()
	viewport.add_child(hud)
	await get_tree().process_frame
	hud.set_early_game_ui_state(false)
	hud.set_match_learning_active(true)
	var panel: Control = hud.get("_progression_hint_panel")
	var label: Label = hud.get("_progression_hint_label")
	var skip: Button = hud.get("_guidance_dismiss_button")
	var worst_lines: int = 0
	var label_sizes: Array[String] = []
	for text: String in LESSON_TEXTS:
		hud.set_primary_action(text, "", -1, -1, false)
		hud.apply_mobile_layout(logical, safe)
		await get_tree().process_frame
		await get_tree().process_frame
		worst_lines = maxi(worst_lines, label.get_line_count())
		if label.get_line_count() > 2:
			failures.append("%s scale %.3f notch %s clips %d-line lesson: %s" % [physical, scale_value, notched, label.get_line_count(), text])
		label_sizes.append(str(label.size))
	if not safe.encloses(panel.get_global_rect()):
		failures.append("Lesson banner escapes safe bounds")
	if skip.size.y * scale_value < 48.0:
		failures.append("Skip under 48 physical px")
	hud.set_ui_modal_state(hud.UIModalState.PAUSE_MENU)
	hud.apply_mobile_layout(logical, safe)
	await get_tree().process_frame
	await get_tree().process_frame
	var pause_menu: Control = hud.get("_pause_overlay").get_node("PauseMenu")
	var learn: Button = hud.get("_match_learning_button")
	if not safe.encloses(pause_menu.get_global_rect()):
		failures.append("Pause menu escapes safe bounds: %s vs %s" % [pause_menu.get_global_rect(), safe])
	profiles.append({"physical": str(physical), "scale": scale_value, "notched": notched, "worst_lines": worst_lines, "label_size": str(label.size), "banner": str(panel.get_global_rect()), "pause": str(pause_menu.get_global_rect())})
	viewport.free()
	await get_tree().process_frame


func _check_root_input(dimensions: Vector2i) -> void:
	var window: Window = get_tree().root
	window.size = dimensions
	window.content_scale_size = dimensions
	Input.set_emulate_mouse_from_touch(true)
	var hud: CanvasLayer = load("res://scenes/ui/hud.tscn").instantiate()
	window.add_child(hud)
	await get_tree().process_frame
	hud.set_early_game_ui_state(false)
	hud.set_match_learning_active(true)
	hud.set_primary_action(LESSON_TEXTS[0], "", -1, -1, false)
	await get_tree().process_frame
	await get_tree().process_frame
	var dismissed: Array[bool] = [false]
	hud.guidance_dismissed.connect(func() -> void: dismissed[0] = true)
	await _tap(hud.get("_guidance_dismiss_button").get_global_rect().get_center())
	if not dismissed[0]:
		failures.append("%s root screen-touch Skip failed" % dimensions)
	hud.set_ui_modal_state(hud.UIModalState.PAUSE_MENU)
	await get_tree().process_frame
	await get_tree().process_frame
	var requested: Array[bool] = [false]
	hud.match_learning_requested.connect(func() -> void: requested[0] = true)
	await _tap(hud.get("_match_learning_button").get_global_rect().get_center())
	if not requested[0]:
		failures.append("%s root screen-touch Learn failed" % dimensions)
	inputs.append({"dimensions": str(dimensions), "scope": "Actual Input.parse_input_event screen touch with engine mouse emulation", "skip": dismissed[0], "learn": requested[0]})
	hud.free()
	await get_tree().process_frame


func _tap(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = get_viewport().get_final_transform() * position
		event.pressed = pressed
		event.index = 0
		Input.parse_input_event(event)
		await get_tree().process_frame
		await get_tree().process_frame
