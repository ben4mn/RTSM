extends Node
## Tracks actual app/tab backgrounding. Losing focus to another Web control is
## deliberately not a lifecycle event; foregrounding never resumes a match.

signal background_changed(backgrounded: bool)

const WEB_LIFECYCLE_SOURCE: String = """
window.PocketMatchLifecycle = {
  create(callback) {
    const reportVisibility = () => callback(document.visibilityState === 'hidden');
    const reportPageHide = () => callback(true);
    document.addEventListener('visibilitychange', reportVisibility);
    window.addEventListener('pagehide', reportPageHide);
    window.addEventListener('pageshow', reportVisibility);
    reportVisibility();
    return { detach() {
      document.removeEventListener('visibilitychange', reportVisibility);
      window.removeEventListener('pagehide', reportPageHide);
      window.removeEventListener('pageshow', reportVisibility);
    }};
  }
};
"""

var backgrounded: bool = false
var _web_environment: bool = OS.has_feature("web")
var _native_suspended: bool = false
var _native_unfocused: bool = false
var _web_callback: JavaScriptObject
var _web_binding: JavaScriptObject


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _web_environment:
		JavaScriptBridge.eval(WEB_LIFECYCLE_SOURCE, true)
		_web_callback = JavaScriptBridge.create_callback(_on_web_visibility)
		var factory: JavaScriptObject = JavaScriptBridge.get_interface("PocketMatchLifecycle")
		_web_binding = factory.create(_web_callback)
	elif DisplayServer.get_name() != "headless":
		_native_unfocused = not DisplayServer.window_is_focused()
		_set_backgrounded(_native_unfocused)


func _notification(what: int) -> void:
	# On Web these notifications also include canvas/DOM focus changes. Only
	# document visibility and page lifecycle are authoritative there.
	if _web_environment:
		return
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_native_suspended = true
		NOTIFICATION_APPLICATION_RESUMED:
			_native_suspended = false
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_native_unfocused = true
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_native_unfocused = false
		_:
			return
	_set_backgrounded(_native_suspended or _native_unfocused)


func _on_web_visibility(arguments: Array) -> void:
	if not arguments.is_empty():
		_set_backgrounded(bool(arguments[0]))


func _set_backgrounded(value: bool) -> void:
	if backgrounded == value:
		return
	backgrounded = value
	background_changed.emit(value)


func _exit_tree() -> void:
	# Each scene owns its binding: an old scene cannot detach a new scene's
	# listeners when a restart overlaps their lifetimes.
	if _web_binding != null:
		_web_binding.detach()
		_web_binding = null
	_web_callback = null
