extends SceneTree
## Real HUD controls must expose authoritative age costs and affordability.

const HUD_SCENE := "res://scenes/ui/hud.tscn"
const VIEWPORT_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(844, 390)]
const BUILDING_STATE_ACTIVE := 2

var _failures: Array[String] = []
var _game_manager: Node
var _resource_manager: Node
var _profiles_checked: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_game_manager = root.get_node("GameManager")
	_resource_manager = root.get_node("ResourceManager")
	for viewport_size: Vector2i in VIEWPORT_SIZES:
		for population_limit: int in SkirmishData.POPULATION_OPTIONS:
			await _exercise_profile(viewport_size, population_limit)
	_expect(_profiles_checked == VIEWPORT_SIZES.size() * SkirmishData.POPULATION_OPTIONS.size(), "every requested profile completed")
	# Drain finished UI alert playback before immediate SceneTree shutdown.
	root.get_node("AudioManager").call("stop_all")
	await create_timer(0.15, true).timeout
	if _failures.is_empty():
		print("[PASS] age_up_affordability: six desktop/phone population profiles expose live Dark/Feudal costs, deposit/spend availability, pause/resume guards, supported-age boundary, and fitted button text")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("[FAIL] age_up_affordability: %s" % failure)
		quit(1)


func _exercise_profile(viewport_size: Vector2i, population_limit: int) -> void:
	_game_manager.set("selected_population_limit", population_limit)
	_game_manager.call("initialize_game", 1)
	_resource_manager.call("reset")
	_resource_manager.call("initialize_player", 0, {"food": 0, "wood": 0, "gold": 0})
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	root.add_child(viewport)
	var hud: CanvasLayer = (load(HUD_SCENE) as PackedScene).instantiate() as CanvasLayer
	viewport.add_child(hud)
	var town_center: Node2D = (load("res://scripts/buildings/building_base.gd") as GDScript).new() as Node2D
	town_center.set("building_type", BuildingData.BuildingType.TOWN_CENTER)
	town_center.set("player_owner", 0)
	town_center.set("state", BUILDING_STATE_ACTIVE)
	viewport.add_child(town_center)
	hud.call("show_building_selection", "Town Center", 5000, 5000, [], [], town_center)
	hud.call("set_early_game_ui_state", false)
	hud.call("apply_mobile_layout", Vector2(viewport_size), Rect2(Vector2.ZERO, Vector2(viewport_size)))
	await process_frame
	await process_frame
	var button: Button = hud.get("age_up_button") as Button
	var prefix := "%dx%d %d population" % [viewport_size.x, viewport_size.y, population_limit]
	var ages_tested: int = 0
	# The progression contract comes from costs, including its supported boundary.
	# GameManager's legacy MAX_AGE includes an age with no skirmish purchase.
	while not (_game_manager.call("get_age_up_cost", 0, int(_game_manager.call("get_player_age", 0)) + 1) as Dictionary).is_empty():
		var age: int = int(_game_manager.call("get_player_age", 0))
		var cost: Dictionary = _game_manager.call("get_age_up_cost", 0, age + 1)
		var context := "%s %s" % [prefix, _game_manager.call("get_age_name", age)]
		_expect(cost.has("food") and cost.has("gold"), context + " fixture requires food and gold costs")
		_resource_manager.call("reset")
		_resource_manager.call("initialize_player", 0, {"food": int(cost["food"]) - 1, "wood": 0, "gold": int(cost["gold"]) - 1})
		hud.call("refresh_match_state")
		_expect(button.is_visible_in_tree(), context + " Town Center exposes age action")
		_assert_authoritative_text(hud, button, cost, age, context)
		_expect(button.disabled, context + " action is disabled below both costs")
		_expect(button.tooltip_text.contains("Need +1 food · +1 gold"), context + " preview explains both missing resources")
		_resource_manager.call("add_resource", 0, "food", 1)
		_expect(button.disabled, context + " food-only deposit cannot enable while gold is missing")
		_resource_manager.call("add_resource", 0, "gold", 1)
		_expect(not button.disabled and button.tooltip_text.contains("Ready to advance"), context + " exact-cost deposit immediately enables and updates preview")
		_expect(bool(_resource_manager.call("try_spend", 0, {"food": 1})), context + " fixture can spend one food")
		_expect(button.disabled and button.tooltip_text.contains("Need +1 food · +0 gold"), context + " spending immediately disables and updates missing cost")
		_game_manager.call("set_state", 3)
		_resource_manager.call("add_resource", 0, "food", 1)
		_expect(button.disabled, context + " affordable resource changes cannot enable a paused action")
		_expect(bool(_resource_manager.call("try_spend", 0, {"gold": 1})), context + " fixture can spend while paused")
		_game_manager.call("set_state", 2)
		_expect(button.disabled and button.tooltip_text.contains("Need +0 food · +1 gold"), context + " resume reflects current cost shortage")
		_resource_manager.call("add_resource", 0, "gold", 1)
		_expect(not button.disabled, context + " post-resume deposit enables the action")
		await process_frame
		await process_frame
		_assert_button_layout(button, viewport_size, context)
		_expect(bool(_resource_manager.call("try_spend", 0, cost)), context + " advancement fixture pays authoritative costs")
		_expect(bool(_game_manager.call("advance_age", 0)), context + " advancement emits authoritative age refresh")
		ages_tested += 1
		await process_frame
	_expect(ages_tested > 0, prefix + " tests at least one supported advancement")
	_expect(button.disabled and button.text == "Max Age", prefix + " empty next-age costs produce disabled Max Age")
	_resource_manager.call("add_resource", 0, "food", 100000)
	_resource_manager.call("add_resource", 0, "gold", 100000)
	_expect(button.disabled and button.text == "Max Age", prefix + " ample resources cannot enable unsupported advancement")
	hud.call("apply_mobile_layout", Vector2(viewport_size), Rect2(Vector2.ZERO, Vector2(viewport_size)))
	await process_frame
	_expect(not button.visible, prefix + " context layout hides an unsupported next-age action")
	viewport.free()
	await process_frame
	_profiles_checked += 1


func _assert_authoritative_text(hud: CanvasLayer, button: Button, cost: Dictionary, age: int, context: String) -> void:
	var expected_cost := "%dF · %dG" % [int(cost["food"]), int(cost["gold"])]
	_expect(button.text.contains("\n" + expected_cost), context + " actual action label renders authoritative costs")
	_expect(button.icon == null, context + " costs have the whole button width")
	_expect((hud.get("age_label") as Label).text == String(_game_manager.call("get_age_name", age)), context + " age label matches current state")
	_expect(button.tooltip_text.begins_with("Advance to " + String(_game_manager.call("get_age_name", age + 1))), context + " preview names the authoritative next age")
	_expect(button.tooltip_text.contains("%d food · %d gold" % [int(cost["food"]), int(cost["gold"])]), context + " preview includes current population-scaled costs")


func _assert_button_layout(button: Button, viewport_size: Vector2i, context: String) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(viewport_size))
	_expect(bounds.encloses(button.get_global_rect()), context + " button stays within the viewport")
	_expect(button.size.x >= 48.0 and button.size.y >= 48.0, context + " action keeps a full touch target")
	var font: Font = button.get_theme_font("font")
	var font_size: int = button.get_theme_font_size("font_size")
	var lines: PackedStringArray = button.text.split("\n")
	for style_name: String in ["normal", "hover", "pressed", "disabled"]:
		var style: StyleBox = button.get_theme_stylebox(style_name)
		var content: Vector2 = button.size - style.get_minimum_size()
		for line: String in lines:
			var width: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			_expect(width <= content.x + 0.5, "%s %s cost text fits width (%.1f <= %.1f)" % [context, style_name, width, content.x])
		var text_height: float = font.get_height(font_size) * float(lines.size())
		_expect(text_height <= content.y + 0.5, "%s %s two-line text fits height (%.1f <= %.1f)" % [context, style_name, text_height, content.y])
	print("Age cost fit: %s label=%s size=%s font=%d" % [context, button.text.replace("\n", " / "), button.size, font_size])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
