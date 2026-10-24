extends Node
## Real Main in phone SubViewports; resize signals run while the match is paused.

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_map_archetype = MapData.MapArchetype.OPEN_PLAINS
	for size: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		await _profile(size)
	if _failures.is_empty():
		print("[PASS] camera_resize_zoom: fitted and manual zoom survive repeated paused phone rotations, logical UI resizing, profile limit clamps and explicit default changes")
	else:
		for failure: String in _failures:
			push_error("[FAIL] camera_resize_zoom: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _profile(size: Vector2i) -> void:
	GameManager.set_state(GameManager.GameState.MENU)
	var phone := SubViewport.new()
	phone.size = size
	add_child(phone)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	phone.add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	_expect(main.get("_player_town_center") != null, str(size) + " real match booted")
	if main.get("_player_town_center") == null:
		phone.free()
		return
	await _frames(4)
	var map: Node2D = main.get("game_map")
	var camera: Camera2D = map.get("camera")
	GameManager.set_paused(true)
	_expect(get_tree().paused, str(size) + " rotation fixture is paused")
	_expect(not bool(map.get("_user_zoom_override")), str(size) + " real opening has no deliberate zoom")
	# Use the normal opening-fit API to guarantee a wider-than-default view,
	# independent of seed-dependent food/worker placement and HUD occlusion.
	map.call("fit_opening_zoom", float(map.call("_get_default_zoom")) * 0.7)
	var fitted_zoom: float = camera.zoom.x
	_expect(fitted_zoom < float(map.call("_get_default_zoom")) - 0.01, "opening fixture must actually fit below the configured default")
	var initial_revision: int = map.call("get_camera_interaction_revision")
	for cycle: int in 2:
		await _round_trip(phone, map, camera, size, fitted_zoom, false, "opening rotation %d" % cycle)
	# Interface preferences change logical viewport size too. The camera should
	# retain its view rather than treating that layout change as a Reset action.
	phone.size = Vector2i(Vector2(size) / 1.15)
	await _frames(4)
	_expect(is_equal_approx(camera.zoom.x, fitted_zoom), "logical UI resize preserves fitted zoom")
	phone.size = size
	await _frames(4)
	_expect(is_equal_approx(camera.zoom.x, fitted_zoom), "logical UI resize round trip has no zoom accumulation")
	_expect(int(map.call("get_camera_interaction_revision")) == initial_revision, "automatic resize never impersonates user camera input")
	map.call("zoom_in")
	map.call("_update_camera_zoom", 0.03)
	var manual_zoom: float = camera.zoom.x
	_expect(manual_zoom > fitted_zoom and bool(map.get("_user_zoom_override")), "normal plus control creates deliberate zoom")
	_expect(bool(map.get("_zoom_transition_active")), "resize fixture must interrupt a genuinely pending zoom step")
	for cycle: int in 2:
		await _round_trip(phone, map, camera, size, manual_zoom, true, "manual rotation %d" % cycle)
	# A true profile/default-setting application remains intentional: false
	# selects the new configured value even after the player has chosen a zoom.
	map.set("mobile_default_zoom", 1.05)
	var revised_default: float = map.call("_get_default_zoom")
	map.call("_apply_camera_profile", Vector2(size), false)
	_expect(is_equal_approx(camera.zoom.x, revised_default), "explicit profile application honors the changed default")
	_expect(bool(map.get("_user_zoom_override")), "explicit profile application preserves the existing user-intent flag")
	# Retaining a view still obeys newly selected profile limits. Repeated
	# resizes cannot multiply the zoom or escape the narrower allowed range.
	map.set("mobile_zoom_max", revised_default * 0.9)
	await _round_trip(phone, map, camera, size, revised_default * 0.9, true, "reduced maximum")
	var limited_zoom: float = camera.zoom.x
	map.set("mobile_zoom_min", limited_zoom + 0.05)
	map.set("mobile_zoom_max", 2.2)
	await _round_trip(phone, map, camera, size, limited_zoom + 0.05, true, "increased minimum")
	# Non-touch desktop windows use a different profile. A real touch device
	# intentionally remains mobile even at these dimensions.
	if not DisplayServer.is_touchscreen_available() and not OS.has_feature("mobile"):
		map.set("mobile_zoom_min", 0.42)
		var before_desktop: float = camera.zoom.x
		phone.size = Vector2i(1280, 800)
		await _frames(4)
		_expect(not bool(map.get("_mobile_profile_active")), "large non-touch viewport selects the desktop profile")
		_expect(is_equal_approx(camera.zoom.x, before_desktop), "desktop profile switch preserves legal fitted/manual scale")
		map.call("_set_zoom_anchored", 2.4, Vector2(-1, -1), Vector2(-1, -1), true)
		_expect(is_equal_approx(camera.zoom.x, 2.4), "desktop profile permits its larger detail range")
		phone.size = size
		await _frames(4)
		_expect(bool(map.get("_mobile_profile_active")) and is_equal_approx(camera.zoom.x, 2.2), "return to phone clamps desktop detail to the mobile maximum")
		phone.size = Vector2i(1280, 800)
		await _frames(4)
		_expect(is_equal_approx(camera.zoom.x, 2.2), "repeated profile switch does not restore an out-of-range prior zoom")
		map.call("_set_zoom_anchored", 0.41, Vector2(-1, -1), Vector2(-1, -1), true)
		_expect(is_equal_approx(camera.zoom.x, 0.41), "desktop profile permits its wider overview range")
		phone.size = size
		await _frames(4)
		_expect(is_equal_approx(camera.zoom.x, 0.42), "return to phone clamps desktop overview to the mobile minimum")
	else:
		print("[NOT RUN] camera_resize_zoom desktop-profile branch: touchscreen/mobile runtime intentionally stays mobile")
	print("[CAMERA_RESIZE] " + JSON.stringify({"phone": str(size), "fitted_zoom": fitted_zoom, "manual_zoom": manual_zoom, "explicit_default": revised_default, "final_zoom": camera.zoom.x, "source_sha256": FileAccess.get_sha256("res://scripts/map/game_map.gd")}))
	phone.free()
	GameManager.set_state(GameManager.GameState.MENU)
	await _frames(2)


func _round_trip(phone: SubViewport, map: Node2D, camera: Camera2D, size: Vector2i, expected_zoom: float, user_override: bool, label: String) -> void:
	var focus: Vector2 = camera.position
	var revision: int = map.call("get_camera_interaction_revision")
	for next_size: Vector2i in [Vector2i(size.y, size.x), size]:
		phone.size = next_size
		await _frames(4)
		var prefix: String = "%s %s -> %s" % [size, label, next_size]
		_expect(is_equal_approx(camera.zoom.x, expected_zoom), "%s zoom %f differs from retained/clamped %f" % [prefix, camera.zoom.x, expected_zoom])
		_expect(bool(map.get("_user_zoom_override")) == user_override, prefix + " changed the user-intent flag")
		_expect(int(map.call("get_camera_interaction_revision")) == revision, prefix + " changed the interaction revision")
		_expect(camera.position.distance_to(focus) < 0.01, prefix + " changed the world focus")
		var half_view: Vector2 = map.call("_get_camera_half_view_world")
		var bounds: Rect2 = map.get("_camera_world_bounds")
		_expect(camera.limit_left == floori(bounds.position.x - half_view.x) and camera.limit_right == ceili(bounds.end.x + half_view.x), prefix + " did not refresh horizontal limits")
		_expect(camera.limit_top == floori(bounds.position.y - half_view.y) and camera.limit_bottom == ceili(bounds.end.y + half_view.y), prefix + " did not refresh vertical limits")
		_expect(not bool(map.get("_zoom_transition_active")), prefix + " retained an old zoom transition")
		_expect(get_tree().paused, prefix + " resumed the paused match")


func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
