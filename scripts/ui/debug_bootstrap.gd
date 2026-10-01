extends Node
## Debug-only integration for the optional F1 developer panel.
##
## This autoload is feature-qualified in project.godot and removed from the
## staged production project. Keeping all panel ownership here prevents debug
## UI paths and cheat wiring from becoming dependencies of gameplay scripts.

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const DEBUG_PANEL_SCRIPT: Script = preload("res://scripts/ui/debug_panel.gd")

var _main_ref: WeakRef = null
var _panel_ref: WeakRef = null
var _attached_scene_id: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null or scene.scene_file_path != MAIN_SCENE_PATH:
		_attached_scene_id = 0
		_main_ref = null
		_panel_ref = null
		return
	if _attached_scene_id == scene.get_instance_id() and _get_panel() != null:
		return
	_attach_to_match(scene)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode not in [KEY_F1, KEY_QUOTELEFT]:
		return
	var panel: Node = _get_panel()
	if panel != null and panel.has_method("toggle"):
		panel.call("toggle")
		get_viewport().set_input_as_handled()


func _attach_to_match(main: Node) -> void:
	var hud_root: Node = main.get_node_or_null("HUD/Root")
	var game_map: Node = main.get_node_or_null("GameMap")
	var ai_controller: Node = main.get_node_or_null("AIController")
	if hud_root == null or game_map == null or ai_controller == null:
		return
	var decision_timer: Timer = ai_controller.get("_decision_timer") as Timer
	if decision_timer == null:
		return

	var panel: Node = DEBUG_PANEL_SCRIPT.new()
	panel.name = "DebugPanel"
	panel.call(
		"initialize",
		decision_timer,
		game_map.get("fog_of_war"),
		game_map.get_node_or_null("FogLayer")
	)
	panel.connect("spawn_units_requested", _on_spawn_units_requested)
	hud_root.add_child(panel)
	_main_ref = weakref(main)
	_panel_ref = weakref(panel)
	_attached_scene_id = main.get_instance_id()


func _on_spawn_units_requested(unit_type: int, count: int) -> void:
	var main: Node = _main_ref.get_ref() if _main_ref != null else null
	if main == null:
		return
	var game_map: Node = main.get_node_or_null("GameMap")
	if game_map == null:
		return
	var camera: Camera2D = game_map.get("camera") as Camera2D
	if camera == null:
		return
	for _index in count:
		var offset := Vector2(randf_range(-50.0, 50.0), randf_range(-50.0, 50.0))
		main.call("_spawn_unit", unit_type, 0, camera.position + offset)
	main.call("_update_population_display")


func _get_panel() -> Node:
	if _panel_ref == null:
		return null
	return _panel_ref.get_ref() as Node
