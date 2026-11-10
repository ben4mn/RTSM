extends Node
## Every Blacksmith upgrade must fit the fixed shelf and accept paid pointer input.
## Round 2 B: four cards at a time; a second tier takes its predecessor's card.

const FIRST_TIER: Array[String] = ["forging", "scale_mail", "fletching", "stone_keep"]
const PURCHASE_ORDER: Array[String] = ["forging", "iron_casting", "scale_mail", "chain_mail", "fletching", "stone_keep"]

const HUD := preload("res://scenes/ui/hud.tscn")
var failures: Array[String] = []
var checks: int = 0
var requests: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	for profile: Dictionary in [
		{"size": Vector2(1280, 720), "scale": 1.0, "notch": false},
		{"size": Vector2(844, 390), "scale": 1.0, "notch": false},
		{"size": Vector2(844, 390), "scale": 1.15, "notch": true},
		{"size": Vector2(932, 430), "scale": 1.15, "notch": true},
		{"size": Vector2(632, 356), "scale": 1.0, "notch": false},
	]:
		await _profile(profile)
	for failure: String in failures:
		push_error("[FAIL] research_shelf: " + failure)
	if failures.is_empty():
		print("[PASS] research_shelf: %d checks across five desktop/phone/safe-area profiles; four cards fit at every step of the six-tech Blacksmith tree, readable three-line copy, stable identities, follow-up cards, live shortage/completion details and actual paid pointer purchases" % checks)
	get_tree().quit(0 if failures.is_empty() else 1)


func _profile(profile: Dictionary) -> void:
	GameManager.initialize_game(1)
	GameManager.set_state(GameManager.GameState.PLAYING)
	GameManager.players[0]["age"] = 3
	ResourceManager.reset()
	ResourceManager.initialize_player(0, {"food": 0, "wood": 0, "gold": 0})
	var logical: Vector2 = (profile.size / profile.scale).floor()
	var safe := Rect2(Vector2.ZERO, logical)
	if profile.notch:
		safe = Rect2(Vector2(44.0 / profile.scale, 0), logical - Vector2(88.0 / profile.scale, 18.0 / profile.scale))
	var context: String = "%s scale%s notch%s" % [profile.size, profile.scale, profile.notch]
	var viewport := SubViewport.new()
	viewport.size = Vector2i(logical)
	viewport.handle_input_locally = true
	add_child(viewport)
	var hud: CanvasLayer = HUD.instantiate()
	viewport.add_child(hud)
	var smith := BuildingBase.new()
	smith.building_type = BuildingData.BuildingType.BLACKSMITH
	smith.player_owner = 0
	viewport.add_child(smith)
	smith.state = BuildingBase.State.ACTIVE
	smith.hp = 1200
	hud.call("set_early_game_ui_state", false)
	requests.clear()
	hud.research_requested.connect(func(building: Node2D, research_id: String) -> void:
		requests.append(research_id)
		GameManager.try_research(0, building, research_id)
	)
	await _refresh(hud, smith, logical, safe)
	var row: HBoxContainer = hud.get("_research_container")
	var shelf: ScrollContainer = hud.get("command_scroll")
	var ids: Dictionary = {}
	_expect(row.get_child_count() == 4, context + " exactly four upgrade cards")
	for id: String in FIRST_TIER:
		var definition: Dictionary = TechData.get_research_definition(id)
		var button: Button = row.get_node("ResearchButton_" + id)
		ids[id] = button.get_instance_id()
		_expect(button.disabled, context + " unaffordable upgrade is disabled")
		_expect(button.text.contains("Need "), context + " blocked card says why: " + button.text)
		_expect(button.tooltip_text.contains("Need ") and button.tooltip_text.contains(str(definition.name)), context + " shortage and full name in details")
		_check_card(button, shelf, safe, context)
	var information: Dictionary = hud.call("_selection_information")
	for id: String in FIRST_TIER:
		_expect(str(information.body).contains(str(TechData.get_research_definition(id).name)), context + " tap-only Info contains " + id)
	for resource: String in ["food", "wood", "gold"]:
		ResourceManager.add_resource(0, resource, 1000)
	await _refresh(hud, smith, logical, safe)
	for id: String in PURCHASE_ORDER:
		var definition: Dictionary = TechData.get_research_definition(id)
		var button: Button = row.get_node("ResearchButton_" + id)
		_expect(not button.disabled, context + " funded upgrade is available: " + id)
		if ids.has(id):
			_expect(button.get_instance_id() == int(ids[id]), context + " update preserves button identity")
		var before: Dictionary = ResourceManager.get_all_resources(0).duplicate()
		await _click(viewport, button.get_global_rect().get_center())
		_expect(GameManager.has_research(0, id), context + " pointer buys " + id)
		for resource: String in ["food", "wood", "gold"]:
			_expect(ResourceManager.get_resource(0, resource) == int(before.get(resource, 0)) - int(definition.cost.get(resource, 0)), context + " exact cost for " + id)
		await _refresh(hud, smith, logical, safe)
		var successor: String = TechData.get_successor_id(id)
		if successor.is_empty():
			button = row.get_node("ResearchButton_" + id)
			_expect(button.disabled and button.text.contains("Complete"), context + " completed upgrade is clear and cannot repeat")
		else:
			_expect(row.get_node_or_null("ResearchButton_" + id) == null, context + " finished first tier leaves the shelf: " + id)
			button = row.get_node_or_null("ResearchButton_" + successor)
			_expect(button != null and not button.disabled, context + " follow-up takes its card: " + successor)
		_expect(row.get_child_count() == 4, context + " still four cards after " + id)
		if button != null:
			_check_card(button, shelf, safe, context)
	_expect(requests.size() == PURCHASE_ORDER.size(), context + " all six paid actions reached via fixed shelf")
	smith.free()
	viewport.free()
	await get_tree().process_frame


func _refresh(hud: CanvasLayer, smith: BuildingBase, logical: Vector2, safe: Rect2) -> void:
	hud.call("show_building_selection", "Blacksmith", 1200, 1200, [], [], smith)
	await get_tree().process_frame
	await get_tree().process_frame
	hud.call("apply_mobile_layout", logical, safe)
	await get_tree().process_frame
	await get_tree().process_frame


func _check_card(button: Button, shelf: Control, safe: Rect2, context: String) -> void:
	_expect(button.size.x >= 48 and button.size.y >= 48, context + " target at least 48px")
	_expect(shelf.get_global_rect().grow(0.5).encloses(button.get_global_rect()), context + " shelf fully exposes " + button.name + " " + str(button.get_global_rect()))
	_expect(safe.grow(0.5).encloses(button.get_global_rect()), context + " safe bounds contain " + button.name)
	var available: float = button.size.x - button.get_theme_stylebox("normal").get_minimum_size().x
	for line: String in button.text.split("\n"):
		var width: float = button.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
		_expect(width <= available + 0.5, context + " readable line: " + line)
	_expect(button.get_minimum_size().y <= button.size.y + 0.5, context + " full text height")


func _click(viewport: SubViewport, point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	viewport.push_input(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		viewport.push_input(event)
		await get_tree().process_frame


func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
