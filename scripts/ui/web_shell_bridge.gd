extends RefCounted
## Keep browser screen controls outside active gameplay input.


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
