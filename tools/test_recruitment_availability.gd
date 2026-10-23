extends Node
## Recruitment must explain live purchase blockers without losing touch input.

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const PHONE_SIZE := Vector2i(844, 390)
const VILLAGER := UnitData.UnitType.VILLAGER
const SCOUT := UnitData.UnitType.SCOUT

var _failures: Array[String] = []
var _viewport: SubViewport
var _hud: CanvasLayer
var _building: BuildingBase
var _queue: ProductionQueue
var _requests: int = 0
var _captures: Array[String] = []
const CAPTURE_OUTPUT := "res://output/polish-2026-10-22/recruitment"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(1)
	ResourceManager.reset()
	ResourceManager.initialize_player(0, {"food": 20, "wood": 0, "gold": 0})
	_viewport = SubViewport.new()
	_viewport.size = PHONE_SIZE
	_viewport.handle_input_locally = true
	if DisplayServer.get_name() != "headless":
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_hud = HUD_SCENE.instantiate() as CanvasLayer
	_viewport.add_child(_hud)
	_building = _producer()
	_queue = _building.get_production_queue() as ProductionQueue
	_hud.train_unit_requested.connect(func(_producer_ref: Node2D, _unit_type: int) -> void: _requests += 1)
	await _refresh()
	var scout: Button = _button(SCOUT)
	var stable_id: int = scout.get_instance_id()
	_expect(not scout.disabled and scout.text.contains("Need 20F +"), "resource-blocked Scout remains tappable with a compact shortage")
	_expect(scout.get_global_rect().size.x >= 48 and scout.get_global_rect().size.y >= 48, "blocked card keeps a comfortable touch target")
	_expect(scout.get_global_rect().size.x <= 90, "multi-resource blocker does not widen the phone card")
	var info: String = _information(SCOUT)
	_expect(info.contains("Need 20 food · 10 gold more"), "Info spells out all current resource deficits")
	_expect(info.contains("Cost: 40 food · 10 gold") and info.contains("Training: 8s"), "Info retains total cost and training time while blocked")
	_expect(scout.tooltip_text.contains(info), "hover and touch Info share the same description")
	_expect(_information(VILLAGER).contains("Shortcut: Q") and not info.contains("Shortcut: Q"), "Q is advertised only on the producer's first unit")
	var summary: Dictionary = _hud.call("_selection_information")
	_expect(str(summary.get("body", "")).contains("Need 20 food · 10 gold more"), "tap-only summary Info includes live recruitment blockers")
	await _capture_state("resources")
	await _tap(scout.get_global_rect().get_center())
	_expect(_requests == 1, "an unavailable card still emits its normal request for failure feedback")
	_expect(ResourceManager.get_resource(0, "food") == 20 and GameManager.get_committed_population(0) == 0, "inspection and request-only UI do not spend or reserve")

	ResourceManager.add_resource(0, "food", 1000)
	ResourceManager.add_resource(0, "gold", 100)
	await _refresh()
	_expect(_button(SCOUT).get_instance_id() == stable_id, "resource refresh keeps the same button instance")
	_expect(_button(SCOUT).text.contains("40F") and not _button(SCOUT).text.contains("Need"), "recovered card restores its cost")
	_expect(_information(SCOUT).contains("Ready to train"), "Info clears a recovered deficit")
	_expect(_button(SCOUT).get_theme_color("font_color") == KingdomTheme.PARCHMENT, "ready card restores the normal text color")
	await _capture_state("ready")

	_set_cap(1)
	var other: BuildingBase = _producer()
	var other_queue: ProductionQueue = other.get_production_queue() as ProductionQueue
	_expect(other_queue.enqueue_unit(VILLAGER), "other producer reserves the only population slot")
	await _refresh()
	_expect(_button(SCOUT).text.contains("Pop 1/1"), "card includes paid slots reserved by another producer")
	_expect(_information(SCOUT).contains("Including 1 paid slots") and _information(SCOUT).contains("cancel paid units"), "paid-population blocker explains refundable reservations")
	await _capture_state("population")
	other_queue.cancel_all()
	_expect(GameManager.add_population(0, 1), "housing fixture fills the only slot with a living unit")
	await _refresh()
	_expect(_information(SCOUT).contains("Build a House") and _information(SCOUT).contains("alone cannot open a slot"), "living-population blocker does not promise a refund can open housing")
	GameManager.remove_population(0, 1)
	var limit: int = GameManager.get_player_population_limit(0)
	_set_cap(limit)
	_expect(GameManager.add_population(0, limit), "match-limit fixture fills allowed population")
	await _refresh()
	_expect(_information(SCOUT).contains("Match population limit reached") and not _information(SCOUT).contains("Build a House"), "match-cap Info does not recommend ineffective housing")
	GameManager.remove_population(0, limit)

	for index in ProductionQueue.MAX_QUEUE_SIZE:
		_expect(_queue.enqueue_unit(VILLAGER), "queue fixture pays for slot %d" % index)
	await _refresh()
	_expect(_button(SCOUT).text.contains("Queue full"), "full producer queue has a compact visible reason")
	_expect(_information(SCOUT).contains("Queue full (5/5)") and _information(SCOUT).contains("use Queue to cancel"), "full queue Info offers a concrete recovery")
	await _capture_state("queue-full")
	_queue.cancel_unit(4)
	await _refresh()
	_expect(_information(SCOUT).contains("Ready to train. Queue 4/5"), "canceling a queue item immediately clears the queue blocker")
	_building.state = BuildingBase.State.CONSTRUCTING
	await _refresh()
	_expect(_information(SCOUT).contains("Finish construction"), "inactive producer Info explains construction")
	_building.state = BuildingBase.State.ACTIVE
	_queue.cancel_all()
	other.free()
	_viewport.free()
	if not _captures.is_empty():
		FileAccess.open(CAPTURE_OUTPUT.path_join("captures.json"), FileAccess.WRITE).store_string(JSON.stringify({"captures": _captures, "failures": _failures, "scope": "Native isolated HUD fixture at 844x390 and 1280x720; no battlefield/performance/device claim."}, "\t") + "\n")
	if _failures.is_empty():
		print("[PASS] recruitment_availability: shared live cost/time/status; touch targets and input preserved; resource, paid-population, housing, match-limit and queue recovery")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] recruitment_availability: %s" % failure)
		get_tree().quit(1)


func _producer() -> BuildingBase:
	var building := BuildingBase.new()
	building.building_type = BuildingData.BuildingType.TOWN_CENTER
	building.player_owner = 0
	building.state = BuildingBase.State.ACTIVE
	_viewport.add_child(building)
	building.add_child(ProductionQueue.new())
	return building


func _refresh() -> void:
	_hud.call("show_building_selection", "Town Center", 5000, 5000, _queue.get_queue_info(), [VILLAGER, SCOUT], _building)
	var size := Vector2(_viewport.size)
	_hud.call("apply_mobile_layout", size, Rect2(Vector2.ZERO, size))
	await get_tree().process_frame
	await get_tree().process_frame


func _capture_state(state_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_OUTPUT))
	for size: Vector2i in [PHONE_SIZE, Vector2i(1280, 720)]:
		_viewport.size = size
		await _refresh()
		await _capture("%s-%dx%d.png" % [state_name, size.x, size.y])
		# This is the same tap-only Info path, not a synthetic text rendering.
		_hud.call("_show_selection_information")
		await _capture("%s-info-%dx%d.png" % [state_name, size.x, size.y])
		_hud.call("close_secondary_surface")
	_viewport.size = PHONE_SIZE
	await _refresh()


func _capture(filename: String) -> void:
	for frame: int in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error: Error = _viewport.get_texture().get_image().save_png(CAPTURE_OUTPUT.path_join(filename))
	_expect(error == OK, "native recruitment capture saves " + filename)
	_captures.append(filename)


func _button(unit_type: int) -> Button:
	return (_hud.get("_train_buttons_container") as Control).get_node("TrainButton_%d" % unit_type) as Button


func _information(unit_type: int) -> String:
	return str((_hud.call("_train_information", unit_type) as Dictionary).get("body", ""))


func _set_cap(target: int) -> void:
	var cap: int = int(GameManager.players[0].get("population_cap", 0))
	if target > cap:
		GameManager.increase_population_cap(0, target - cap)
	elif target < cap:
		GameManager.decrease_population_cap(0, cap - target)
	_expect(int(GameManager.players[0].get("population_cap", 0)) == target, "fixture sets population cap %d" % target)


func _tap(position: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = position
		event.global_position = position
		event.pressed = pressed
		_viewport.push_input(event, true)
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
