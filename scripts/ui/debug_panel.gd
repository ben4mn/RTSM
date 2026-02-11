class_name DebugPanel
extends PanelContainer
## Developer cheat panel for testing. Toggled with F1 or backtick.
## Provides resource injection, instant age up, AI toggle, fog toggle, and unit spawning.

signal spawn_units_requested(unit_type: int, count: int)

var _ai_timer: Timer = null
var _fog_of_war: Node = null
var _fog_layer: Node = null
var _ai_enabled: bool = true
var _fog_visible: bool = true
var _ai_button: Button = null
var _fog_button: Button = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 8
	offset_top = 50
	_build_ui()


func initialize(ai_timer: Timer, fog_of_war: Node, fog_layer: Node) -> void:
	_ai_timer = ai_timer
	_fog_of_war = fog_of_war
	_fog_layer = fog_layer


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Debug (F1)"
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	_add_button(vbox, "+500 Resources", _on_add_resources)
	_add_button(vbox, "Instant Age Up", _on_instant_age_up)
	_ai_button = _add_button(vbox, "AI: ON", _on_toggle_ai)
	_fog_button = _add_button(vbox, "Fog: ON", _on_toggle_fog)
	_add_button(vbox, "+5 Villagers", _on_add_villagers)
	_add_button(vbox, "+5 Infantry", _on_add_infantry)

	add_child(vbox)


func _add_button(parent: Node, text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn


func toggle() -> void:
	visible = !visible


func _on_add_resources() -> void:
	var rm: Node = get_node_or_null("/root/ResourceManager")
	if rm:
		for res_type in ["food", "wood", "gold"]:
			rm.add_resource(0, res_type, 500)


func _on_instant_age_up() -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm:
		gm.advance_age(0)


func _on_toggle_ai() -> void:
	if _ai_timer == null:
		return
	_ai_enabled = !_ai_enabled
	if _ai_enabled:
		_ai_timer.start()
	else:
		_ai_timer.stop()
	_ai_button.text = "AI: ON" if _ai_enabled else "AI: OFF"


func _on_toggle_fog() -> void:
	_fog_visible = !_fog_visible
	if _fog_of_war:
		_fog_of_war.visible = _fog_visible
	if _fog_layer:
		_fog_layer.visible = _fog_visible
	_fog_button.text = "Fog: ON" if _fog_visible else "Fog: OFF"


func _on_add_villagers() -> void:
	spawn_units_requested.emit(UnitData.UnitType.VILLAGER, 5)


func _on_add_infantry() -> void:
	spawn_units_requested.emit(UnitData.UnitType.INFANTRY, 5)
