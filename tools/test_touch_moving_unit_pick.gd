extends Node
## G1: a tap lands where the eye last saw a walking unit. Picking accepts the
## unit's recent drawn path (TAP_TRAIL_SECONDS of real time, capped on screen),
## scaled by game speed, and never extends it ahead of the unit or onto a
## standing unit.

var _failures: Array[String] = []


class FakeGameMap extends Node2D:
	func world_to_tile(_world_pos: Vector2) -> Vector2i:
		return Vector2i(7, 9)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	var previous_time_scale: float = Engine.time_scale
	var game_map := FakeGameMap.new()
	game_map.name = "FakeGameMap"
	add_child(game_map)
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	game_map.add_child(camera)
	var selection_manager := SelectionManager.new()
	selection_manager.touch_context_enabled = false
	selection_manager.game_map = game_map
	game_map.add_child(selection_manager)

	var villager_scene: PackedScene = load("res://scenes/units/villager.tscn")
	var walker: Villager = villager_scene.instantiate() as Villager
	walker.global_position = Vector2(200.0, 0.0)
	game_map.add_child(walker)
	walker.set_process(false)
	var stander: Villager = villager_scene.instantiate() as Villager
	stander.global_position = Vector2(-300.0, 0.0)
	game_map.add_child(stander)
	stander.set_process(false)
	await get_tree().process_frame

	# 60 world px per game second to the right.
	_set_motion(walker, Vector2(60.0, 0.0))
	_expect(walker.get_drawn_velocity().is_equal_approx(Vector2(60.0, 0.0)), "drawn velocity comes from the newest simulated step")
	_expect(stander.get_drawn_velocity() == Vector2.ZERO, "a standing unit has no drawn velocity")

	var radius: float = float(selection_manager.call("_screen_px_to_world_radius", selection_manager.touch_unit_hit_radius_px))
	Engine.time_scale = 1.0
	var trail_1x: float = 60.0 * SelectionManager.TAP_TRAIL_SECONDS
	# Feet just outside the plain radius behind the walker, inside it with the trail.
	var behind: Vector2 = walker.get_visual_position() - Vector2(radius + trail_1x * 0.8, 0.0)
	_expect(selection_manager.call("_get_node_at", behind, true) == walker, "1x: a tap a reaction-time behind a walker picks it")
	SelectionManager.legacy_picking = true
	_expect(selection_manager.call("_get_node_at", behind, true) != walker, "legacy picking misses the same tap (fixture sanity)")
	SelectionManager.legacy_picking = false
	var ahead: Vector2 = walker.get_visual_position() + Vector2(radius + trail_1x * 0.8, 0.0)
	_expect(selection_manager.call("_get_node_at", ahead, true) != walker, "the trail never extends ahead of a walker")

	# 3x speed: the trail triples but stays within the on-screen cap.
	Engine.time_scale = 3.0
	var cap_world: float = SelectionManager.TAP_TRAIL_MAX_PX / maxf(0.25, camera.zoom.x)
	var trail_3x: float = minf(60.0 * 3.0 * SelectionManager.TAP_TRAIL_SECONDS, cap_world)
	var behind_3x: Vector2 = walker.get_visual_position() - Vector2(radius + trail_3x * 0.9, 0.0)
	_expect(selection_manager.call("_get_node_at", behind_3x, true) == walker, "3x: the longer recent path still picks the walker")
	var beyond_cap: Vector2 = walker.get_visual_position() - Vector2(radius + cap_world + 6.0, 0.0)
	_expect(selection_manager.call("_get_node_at", beyond_cap, true) != walker, "3x: the trail is capped on screen")

	# Body hits follow the same path: a tap on where the torso was drawn.
	var sprite: Sprite2D = walker.get_node("UnitSprite") as Sprite2D
	var body_rect: Rect2 = selection_manager.call("_unit_touch_body_rect", sprite)
	var torso: Vector2 = sprite.to_global(body_rect.get_center()) + walker.get_visual_position() - walker.global_position
	var old_torso: Vector2 = torso - Vector2(trail_3x * 0.9, 0.0)
	_expect(bool(selection_manager.call("_is_touch_on_unit_body", walker, old_torso)), "body hit test accepts the torso's recent position")

	# Tap routing end to end: nothing selected, tap behind the walker selects it.
	selection_manager.call("_handle_tap", selection_manager.call("_world_to_screen", behind_3x), true)
	_expect(selection_manager.selected == [walker], "tap behind a walking villager selects it")
	# A standing unit's feet ring is unchanged...
	var beside: Vector2 = stander.get_visual_position() - Vector2(radius + 4.0, 0.0)
	_expect(selection_manager.call("_get_node_at", beside, true) != stander, "standing unit keeps the plain radius at its feet")
	# ...but a thumb beside its torso (outside the narrow body box and beyond
	# the feet radius) now counts: the figure is a capsule from feet to body.
	var stander_sprite: Sprite2D = stander.get_node("UnitSprite") as Sprite2D
	var stander_rect: Rect2 = selection_manager.call("_unit_touch_body_rect", stander_sprite)
	var stander_torso: Vector2 = stander_sprite.to_global(stander_rect.get_center())
	var beside_torso: Vector2 = stander_torso - Vector2(radius * 0.85, 0.0)
	_expect(stander.get_visual_position().distance_to(beside_torso) > radius, "fixture: beside-torso tap is outside the feet radius (%.1f vs %.1f)" % [stander.get_visual_position().distance_to(beside_torso), radius])
	_expect(not bool(selection_manager.call("_is_touch_on_unit_body", stander, beside_torso)), "fixture: beside-torso tap is outside the body box")
	_expect(selection_manager.call("_get_node_at", beside_torso, true) == stander, "a tap beside the torso picks the standing unit")
	SelectionManager.legacy_picking = true
	var legacy_pick: Variant = selection_manager.call("_get_node_at", beside_torso, true)
	SelectionManager.legacy_picking = false
	_expect(legacy_pick != stander or stander.get_visual_position().distance_to(beside_torso) <= radius, "legacy picking missed the beside-torso tap (fixture sanity)")

	Engine.time_scale = previous_time_scale
	game_map.free()
	if _failures.is_empty():
		print("[PASS] touch_moving_unit_pick: taps on a walker's recent drawn path pick it at 1x/3x; capped, never ahead, standing unchanged")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] touch_moving_unit_pick: %s" % failure)
	get_tree().quit(1)


func _set_motion(unit: UnitBase, velocity: Vector2) -> void:
	var step: float = 0.05
	unit.set("_trail_p1", unit.global_position - velocity * step)
	unit.set("_trail_p2", unit.global_position)
	unit.set("_trail_t1", 1.0)
	unit.set("_trail_t2", 1.0 + step)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
