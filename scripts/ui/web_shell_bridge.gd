extends RefCounted
## Keep browser screen controls outside active gameplay input.


static func set_controls_visible(visible: bool) -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(
		"window.PocketWebShell && window.PocketWebShell.setControlsVisible(%s);" % ("true" if visible else "false"),
		true
	)
