extends RefCounted
## Keep browser screen controls outside active gameplay input.


static func get_safe_area_rect(viewport_size: Vector2) -> Rect2:
	if not OS.has_feature("web"):
		return Rect2(Vector2.ZERO, viewport_size)
	var encoded: Variant = JavaScriptBridge.eval(
		"JSON.stringify(window.PocketWebShell && window.PocketWebShell.getSafeArea ? window.PocketWebShell.getSafeArea() : []);", true
	)
	var insets: Variant = JSON.parse_string(encoded) if encoded is String else null
	return map_safe_area_insets(viewport_size, insets if insets is Array else [])


static func get_menu_top_clearance(viewport_size: Vector2) -> float:
	if not OS.has_feature("web"):
		return 0.0
	var normalized: Variant = JavaScriptBridge.eval(
		"window.PocketWebShell && window.PocketWebShell.getMenuTopClearance ? window.PocketWebShell.getMenuTopClearance() : 0;", true
	)
	if not (normalized is float or normalized is int) or not is_finite(float(normalized)):
		return 0.0
	return clampf(float(normalized), 0.0, 1.0) * viewport_size.y


static func map_safe_area_insets(viewport_size: Vector2, insets: Array) -> Rect2:
	var full := Rect2(Vector2.ZERO, viewport_size)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0 or insets.size() != 4:
		return full
	for value: Variant in insets:
		if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0.0:
			return full
	var top_left := Vector2(float(insets[0]), float(insets[1]))
	var bottom_right := Vector2(float(insets[2]), float(insets[3]))
	var available := Vector2.ONE - top_left - bottom_right
	if available.x <= 0.0 or available.y <= 0.0:
		return full
	return Rect2(top_left * viewport_size, available * viewport_size)


static func watch_safe_area(owner: Node, refresh: Callable) -> void:
	if not OS.has_feature("web"):
		return
	var bridge: JavaScriptObject = JavaScriptBridge.get_interface("PocketWebShell")
	if bridge == null:
		return
	var callback: JavaScriptObject = JavaScriptBridge.create_callback(func(_arguments: Array) -> void:
		if owner.is_inside_tree():
			refresh.call_deferred()
	)
	# JavaScript callbacks must stay referenced for the lifetime of their owner.
	owner.set_meta("web_safe_area_callback", callback)
	bridge.addSafeAreaListener(callback)
	owner.tree_exiting.connect(func() -> void:
		bridge.removeSafeAreaListener(callback)
		owner.remove_meta("web_safe_area_callback")
	, CONNECT_ONE_SHOT)


static func set_controls_visible(visible: bool) -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(
		"window.PocketWebShell && window.PocketWebShell.setControlsVisible(%s);" % ("true" if visible else "false"),
		true
	)


static func set_update_safe(safe: bool) -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(
		"window.PocketWebShell && window.PocketWebShell.setUpdateSafe(%s);" % ("true" if safe else "false"),
		true
	)


static func begin_match() -> bool:
	if not OS.has_feature("web"):
		return true
	# A worker activation briefly locks all safe menus. A Button event already
	# queued by Godot must not start a match in that same activation window.
	var held: bool = bool(JavaScriptBridge.eval(
		"!!(window.PocketUpdates && window.PocketUpdates.isHeld());", true
	))
	if held:
		return false
	set_update_safe(false)
	return true
