extends Node2D
## Presentation fixture, not gameplay or device performance. Never saves preferences.
var _failures: Array[String] = []
var _checks: int = 0
var _output: String = "res://output/iteration-2026-10-23/cargo"
var _baseline: bool = false
var _harvest_redraw: Dictionary = {}

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		elif argument == "--baseline":
			_baseline = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	GameManager.set_process(false)
	GameManager.guided_opening_enabled = false
	GameManager.reduced_motion = true
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(844, 475)
	get_window().content_scale_factor = 1.0
	var background := ColorRect.new()
	background.color = Color("9ba58a")
	background.size = Vector2(1600, 1000)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_label("WORKERS / WHAT IS IN THE BAG", Vector2(26, 20), 24)
	_label("Food", Vector2(148, 65), 18)
	_label("Timber", Vector2(318, 65), 18)
	_label("Ore", Vector2(488, 65), 18)
	_label("Mixed load", Vector2(658, 65), 18)
	for row: int in 3:
		_label(["Working", "Selected", "Online"][row], Vector2(26, 135 + row * 105), 16)
		for column: int in 4:
			var kind: String = ["food", "wood", "gold", "mixed"][column]
			var unit := _worker(Vector2(180 + column * 170, 156 + row * 105))
			unit.scale = Vector2.ONE * 1.6
			unit.carried_resource_type = "food" if column == 3 else kind
			unit.carried_amount = 7 if row != 1 else unit.carry_capacity
			unit.current_state = UnitBase.State.GATHERING if row == 0 else UnitBase.State.MOVING
			unit.is_selected = row == 1
			var cargo: Dictionary = {"food": 3, "wood": unit.carried_amount - 3} if column == 3 else {kind: unit.carried_amount}
			unit.set("_cargo", cargo.duplicate())
			if row == 2:
				unit.set_meta("network_cargo", cargo.duplicate())
				unit.carried_resource_type = "gold" # The next job must not relabel the current bag.
				unit.set("_cargo", {})
			if not _baseline:
				_expect(unit.call("_resource_marker_type") == kind, "typed cargo marker row%d col%d" % [row, column])
				var bounds: Rect2 = unit.get_visual_bounds()
				var size: float = UnitBase.UNIT_SIZES.get(unit.unit_type, 8.0)
				_expect(bounds.encloses(unit.global_transform * Rect2(size - 3, -8, 14, 17)), "framing includes glyph and selected capacity")
			unit.queue_redraw()
	if not _baseline:
		_contracts()
		if DisplayServer.get_name() != "headless":
			await _unselected_harvest_redraw()
	for _frame: int in 6:
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_output.path_join("cargo-gallery.png"))
		get_window().size = Vector2i(844, 475)
		for _frame: int in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_output.path_join("cargo-gallery-small.png"))
	var file := FileAccess.open(_output.path_join("receipt.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope": "Synthetic native gallery, read-only cargo marker contracts and detached real-resource harvest/redraw regression; no paid gameplay, network connection or physical device claim.", "baseline": _baseline, "checks": _checks, "failures": _failures, "harvest_redraw": _harvest_redraw, "renderer": DisplayServer.get_name(), "source": FileAccess.get_sha256("res://scripts/units/villager.gd")}, "  "))
	for failure: String in _failures:
		push_error("[FAIL] worker_cargo_presentation: " + failure)
	print("[PASS] worker_cargo_presentation: ", _checks, " checks; baseline=", _baseline, " failures=", _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)

func _contracts() -> void:
	var unit := _worker(Vector2(-1000, -1000))
	unit.carried_resource_type = "gold"
	unit.carried_amount = 5
	unit.set("_cargo", {"wood": 5})
	var before: Dictionary = unit.get("_cargo").duplicate()
	_expect(unit.call("_resource_marker_type") == "wood", "retasked worker keeps old load identity")
	_expect(unit.get("_cargo") == before and unit.carried_amount == 5, "drawing does not alter cargo")
	unit.set("_cargo", {"food": 2, "wood": 3, "gold": 0})
	_expect(unit.call("_resource_marker_type") == "mixed", "two nonzero types show mixed satchel")
	unit.set("_cargo", {})
	_expect(unit.call("_resource_marker_type") == "gold", "legacy single-stack fallback")
	unit.carried_amount = 0
	unit.current_state = UnitBase.State.GATHERING
	_expect(unit.call("_resource_marker_type") == "gold", "empty gathering worker shows current work")
	unit.current_state = UnitBase.State.IDLE
	_expect(unit.call("_resource_marker_type") == "", "empty idle worker has no cargo marker")
	unit.carried_amount = 5
	unit.current_state = UnitBase.State.DEAD
	_expect(unit.call("_resource_marker_type") == "", "dead worker has no floating bag")
	unit.free()

func _unselected_harvest_redraw() -> void:
	# Keep the real unit/resource implementations, manually stepping gathering
	# without selection animation or a state change causing a coincidental draw.
	var unit := _worker(Vector2(790, 440))
	var wood := ResourceNode.new()
	wood.resource_type = "wood"
	wood.position = unit.position + Vector2(10, 0)
	add_child(wood)
	var food := ResourceNode.new()
	food.resource_type = "food"
	food.position = unit.position + Vector2(-10, 0)
	add_child(food)
	var drawn_kinds: Array[String] = []
	unit.draw.connect(func() -> void: drawn_kinds.append(str(unit.call("_resource_marker_type"))))
	_expect(unit.command_gather(wood), "redraw: real wood job accepted")
	unit.call("_process_gathering", unit.gather_tick_time / float(UnitData.RESOURCE_GATHER_SPEEDS["wood"]))
	_expect(unit.carried_amount == 1 and wood.remaining == wood.total_amount - 1, "redraw: real initial wood harvest")
	_expect(unit.command_gather(food), "redraw: partially loaded worker accepts real food job")
	unit.deselect()
	await _settle_draws()
	_expect(not drawn_kinds.is_empty() and drawn_kinds.back() == "wood", "redraw: unselected retasked worker first renders its old wood load")
	var draws_before: int = drawn_kinds.size()
	unit.call("_process_gathering", 0.0)
	await _settle_draws()
	_expect(drawn_kinds.size() == draws_before, "redraw: no successful harvest causes no extra draw")
	unit.call("_process_gathering", unit.gather_tick_time / float(UnitData.RESOURCE_GATHER_SPEEDS["food"]))
	var cargo: Dictionary = unit.get("_cargo")
	_expect(unit.carried_amount == 2 and cargo.get("wood", 0) == 1 and cargo.get("food", 0) == 1 and food.remaining == food.total_amount - 1, "redraw: real second resource harvest creates exact mixed cargo")
	_expect(not unit.is_selected and unit.current_state == UnitBase.State.GATHERING, "redraw: mixed harvest does not select worker or change its state")
	await _settle_draws()
	_expect(drawn_kinds.size() > draws_before and drawn_kinds.back() == "mixed", "redraw: successful unselected harvest emits a native draw with the mixed marker")
	_harvest_redraw = {"drawn_kinds": drawn_kinds.duplicate(), "draws_before_mixed_harvest": draws_before, "cargo": cargo.duplicate(), "unselected": not unit.is_selected, "state": unit.current_state}
	unit.free()
	wood.free()
	food.free()

func _settle_draws() -> void:
	for _frame: int in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

func _worker(at: Vector2) -> Villager:
	var unit: Villager = load("res://scenes/units/villager.tscn").instantiate()
	unit.position = at
	unit.player_owner = 0
	add_child(unit)
	unit.set_process(false)
	return unit

func _label(value: String, at: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_color_override("font_color", Color("253a3c"))
	label.add_theme_font_size_override("font_size", size)
	add_child(label)

func _expect(ok: bool, detail: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(detail)
