extends Node
## Synthetic HUD fixture: real paid research/age transactions must match the
## recruitment figures and inspect-only controls. No combat/performance claim.

const PHONE_SIZE := Vector2i(844, 390)
const OUTPUT := "res://output/polish-2026-10-22/technology-info"

var _viewport: SubViewport
var _hud: CanvasLayer
var _failures: Array[String] = []
var _captures: Array[String] = []
var _age_requests: int = 0
var _had_preferences: bool = false
var _preferences_before: PackedByteArray


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_had_preferences = FileAccess.file_exists(GameManager.PREFERENCES_PATH)
	if _had_preferences:
		_preferences_before = FileAccess.get_file_as_bytes(GameManager.PREFERENCES_PATH)
	GameManager.ui_scale = 1.0
	GameManager.audio_enabled = false
	GameManager.guided_opening_enabled = false
	GameManager.hold_shortcuts_enabled = true
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	ResourceManager.reset()
	ResourceManager.initialize_player(0, {"food": 2000, "wood": 2000, "gold": 2000})
	_viewport = SubViewport.new()
	_viewport.size = PHONE_SIZE
	_viewport.handle_input_locally = true
	if DisplayServer.get_name() != "headless":
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_hud = load("res://scenes/ui/hud.tscn").instantiate()
	_viewport.add_child(_hud)
	_hud.age_up_requested.connect(func() -> void:
		_age_requests += 1
		GameManager.try_advance_age(0))
	_hud.research_requested.connect(func(building: Node2D, research_id: String) -> void:
		GameManager.try_research(0, building, research_id))
	var tc: BuildingBase = _building(BuildingData.BuildingType.TOWN_CENTER)
	var barracks: BuildingBase = _building(BuildingData.BuildingType.BARRACKS)
	var blacksmith: BuildingBase = _building(BuildingData.BuildingType.BLACKSMITH)
	await _select(tc)
	_expect(_training(UnitData.UnitType.VILLAGER).contains("HP 25 · Attack 3 · Armor 0"), "unresearched Villager information shows baseline combat stats")
	var feudal: String = _hud.call("_get_age_up_preview", 2)
	var castle: String = _hud.call("_get_age_up_preview", 3)
	_expect(feudal.contains("Advances immediately") and feudal.contains("unit HP, Attack and Armor stay the same"), "age preview explains actual timing and unlock-only effect")
	_expect(feudal.contains("Archer") and feudal.contains("Horseman"), "Feudal preview includes its new recruits")
	_expect(castle.contains("Town Center") and castle.contains("Siege Engine") and not castle.contains("+ Villager") and not castle.contains("+ Scout"), "Castle preview distinguishes extra Town Centers from already-available opening recruits")
	await _open_info("town-center-age-info.png")
	_expect((_hud.get("_info_body") as Label).text.contains(feudal), "tap-only Town Center Info contains the complete age preview")
	await _close_info()
	var age_button := _hud.get("age_up_button") as Button
	_expect(age_button.has_meta("hud_hold_control"), "Age Up supports the existing hold inspection control")
	var before: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	await _mouse(age_button.get_global_rect().get_center(), true)
	await get_tree().create_timer(0.60, true, false, true).timeout
	_expect(_hud.call("get_secondary_surface_name") == "info", "real Age Up hold opens inspection")
	_expect(_age_requests == 0 and GameManager.get_player_age(0) == 1 and ResourceManager.get_all_resources(0) == before, "holding Age Up neither pays nor advances")
	await _capture("age-hold.png")
	await _mouse(age_button.get_global_rect().get_center(), false)
	await _settle()
	_expect(_age_requests == 0, "release after an Age Up hold cannot purchase")
	var age_cost: Dictionary = GameManager.get_age_up_cost(0, 2)
	await _tap(age_button.get_global_rect().get_center())
	_expect(_age_requests == 1 and GameManager.get_player_age(0) == 2, "short Age Up tap still advances once through the paid transaction")
	for resource: String in ResourceManager.RESOURCE_NAMES:
		_expect(ResourceManager.get_resource(0, resource) == int(before.get(resource, 0)) - int(age_cost.get(resource, 0)), "age tap charges the displayed " + resource + " cost")
	await _select(blacksmith)
	for research_id: String in ["forging", "scale_mail", "wheelbarrow", "loom"]:
		var information: Dictionary = _hud.call("_research_information", research_id)
		var button := (_hud.get("_research_container") as Control).get_node("ResearchButton_" + research_id) as Button
		_expect(str(information.body).contains("Ready to research"), research_id + " Info reflects affordable readiness")
		_expect(button.tooltip_text.contains(str(information.body)) and button.accessibility_name.contains("Ready to research"), research_id + " hover/accessibility reuse the inspected details")
		_expect(not str(TechData.get_research_definition(research_id).get("details", "")).is_empty(), research_id + " has data-defined scope and timing details")
	await _capture("blacksmith-ready.png")
	await _open_info("blacksmith-details.png")
	_expect((_hud.get("_info_body") as Label).text.contains("Forge Weapons") and (_hud.get("_info_body") as Label).text.contains("Wheelbarrow"), "Blacksmith tap Info includes army and worker upgrades")
	await _close_info()
	for research_id: String in ["forging", "scale_mail", "loom"]:
		var button := (_hud.get("_research_container") as Control).get_node("ResearchButton_" + research_id) as Button
		# Paid transaction is the canonical action; late shelf cards may be
		# outside the current scroll page and are not clicked through clipping.
		_expect(GameManager.try_research(0, blacksmith, research_id), research_id + " purchases through the ordinary transaction")
		await _select(blacksmith)
		_expect(button.disabled and str(_hud.call("_research_information", research_id)).contains("Researched."), research_id + " card and Info agree after the purchase")
	await _select(barracks)
	_expect(_training(UnitData.UnitType.INFANTRY).contains("HP 60 · Attack 10 · Armor 3"), "Warrior recruitment includes Forge and Mail exactly once")
	await _capture_recruit_hold(UnitData.UnitType.INFANTRY, "warrior-upgraded.png")
	await _select(tc)
	_expect(_training(UnitData.UnitType.VILLAGER).contains("HP 40 · Attack 5 · Armor 1"), "Villager recruitment includes Loom, Forge and Mail")
	_expect(_training(UnitData.UnitType.SCOUT).contains("HP 45 · Attack 0 · Armor 1"), "Scout recruitment remains unarmed after Forge and includes Mail")
	await _capture_recruit_hold(UnitData.UnitType.VILLAGER, "villager-upgraded.png")
	await _capture_recruit_hold(UnitData.UnitType.SCOUT, "scout-upgraded.png")
	await _select(blacksmith)
	ResourceManager.try_spend(0, ResourceManager.get_all_resources(0))
	await _select(blacksmith)
	_expect(str(_hud.call("_research_information", "wheelbarrow")).contains("Need 175 food · 50 wood more"), "unaffordable research lists the complete live deficit")
	await _open_info("blacksmith-shortage.png")
	await _close_info()
	var farm: BuildingBase = _building(BuildingData.BuildingType.FARM)
	await _select(farm)
	var farm_info: String = str(_hud.call("_selection_information"))
	_expect(farm_info.contains("1 worker") and farm_info.contains("Available: assign one Villager") and not farm_info.contains("Clear production"), "Farm Info explains capacity and local availability without nonexistent production actions")
	await _open_info("farm-available.png")
	await _close_info()
	var worker: UnitBase = load("res://scenes/units/villager.tscn").instantiate()
	worker.player_owner = 0
	_viewport.add_child(worker)
	worker.set_process(false)
	_expect(farm.try_assign_worker(worker), "Farm UI fixture assigns the one worker through its capacity API")
	await _select(farm)
	_expect(str(_hud.call("_selection_information")).contains("Worker assigned"), "Farm Info reports a local reservation")
	await _open_info("farm-assigned.png")
	await _close_info()
	var was_online: bool = NetworkSession.online
	NetworkSession.online = true
	var replica_info: String = str(_hud.call("_farm_information", farm))
	NetworkSession.online = was_online
	_expect(replica_info.contains("1 worker") and not replica_info.contains("Worker assigned") and not replica_info.contains("Available:"), "online Farm Info does not invent reservation status from replica-local state")
	var palette: Node = load("res://scripts/ui/build_menu.gd").new()
	_expect(str(palette.call("_build_info", BuildingData.BuildingType.FARM)).contains("One worker per Farm"), "build Info discloses Farm capacity before purchase")
	palette.free()
	_finish()


func _building(building_type: int) -> BuildingBase:
	var building := BuildingBase.new()
	building.building_type = building_type
	building.player_owner = 0
	building.state = BuildingBase.State.ACTIVE
	_viewport.add_child(building)
	if not building.trainable_units.is_empty():
		building.add_child(ProductionQueue.new())
	return building


func _select(building: BuildingBase) -> void:
	var queue: ProductionQueue = building.get_production_queue() as ProductionQueue
	_hud.call("show_building_selection", BuildingData.get_building_name(building.building_type), building.hp, building.max_hp, queue.get_queue_info() if queue != null else [], building.trainable_units, building)
	_hud.call("_update_age_display")
	await _settle()


func _training(unit_type: int) -> String:
	return str((_hud.call("_train_information", unit_type) as Dictionary).get("body", ""))


func _capture_recruit_hold(unit_type: int, filename: String) -> void:
	var button := (_hud.get("_train_buttons_container") as Control).get_node("TrainButton_%d" % unit_type) as Button
	var before: Dictionary = ResourceManager.get_all_resources(0).duplicate()
	await _mouse(button.get_global_rect().get_center(), true)
	await get_tree().create_timer(0.60, true, false, true).timeout
	_expect(_hud.call("get_secondary_surface_name") == "info", "recruit hold opens live-stat inspection: " + filename)
	await _capture(filename)
	await _mouse(button.get_global_rect().get_center(), false)
	await _settle()
	_expect(ResourceManager.get_all_resources(0) == before, "recruit inspection does not spend: " + filename)


func _settle() -> void:
	_hud.call("apply_mobile_layout", Vector2(PHONE_SIZE), Rect2(Vector2.ZERO, Vector2(PHONE_SIZE)))
	for frame: int in 4:
		await get_tree().process_frame


func _open_info(filename: String) -> void:
	var button := _hud.get("_selection_info_button") as Button
	await _tap(button.get_global_rect().get_center())
	await _settle()
	var panel := _hud.get("_info_panel") as Control
	_expect(panel.is_visible_in_tree() and (_hud.call("get_hold_safe_rect") as Rect2).encloses(panel.get_global_rect()), "technology Info opens safely at 844x390: " + filename)
	await _capture(filename)


func _close_info() -> void:
	var button := (_hud.get("_info_panel") as Control).find_child("InfoCloseButton", true, false) as Button
	await _tap(button.get_global_rect().get_center())
	await _settle()
	_expect(_hud.call("get_secondary_surface_name") == "none", "technology Info closes through its button")


func _tap(position: Vector2) -> void:
	await _mouse(position, true)
	await _mouse(position, false)


func _mouse(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = position
	event.global_position = position
	event.pressed = pressed
	_viewport.push_input(event, true)
	await get_tree().process_frame


func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	await RenderingServer.frame_post_draw
	var error: Error = _viewport.get_texture().get_image().save_png(OUTPUT.path_join(filename))
	_expect(error == OK, "technology image saves: " + filename)
	if error == OK:
		_captures.append(filename)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var report := FileAccess.open(OUTPUT.path_join("evidence.json"), FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"captures": _captures, "failures": _failures, "scope": "Synthetic HUD fixture with funded ordinary paid age/research transactions, native 844x390 captures when rendered. No ordinary-match, performance or device claim."}, "\t") + "\n")
	if _had_preferences:
		FileAccess.open(GameManager.PREFERENCES_PATH, FileAccess.WRITE).store_buffer(_preferences_before)
	else:
		DirAccess.remove_absolute(GameManager.PREFERENCES_PATH)
	_viewport.free()
	for failure: String in _failures:
		push_error("[FAIL] technology_information: " + failure)
	if _failures.is_empty():
		print("[PASS] technology_information: paid upgrade stats, Scout zero attack, research scope/status, correct age unlocks, Age Up hold versus tap, safe tap Info; %d native captures" % _captures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
