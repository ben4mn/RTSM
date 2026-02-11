extends CanvasLayer
## Game over screen. Shows victory/defeat, stats, and replay options.

signal restart_requested()
signal main_menu_requested()

@onready var panel: PanelContainer = %GameOverPanel
@onready var result_label: Label = %ResultLabel
@onready var stats_label: Label = %StatsLabel
@onready var play_again_button: Button = %PlayAgainButton
@onready var main_menu_button: Button = %MainMenuButton


func _ready() -> void:
	layer = 20
	visible = false
	play_again_button.pressed.connect(_on_play_again)
	main_menu_button.pressed.connect(_on_main_menu)


func show_victory(stats: Dictionary) -> void:
	_show_result("VICTORY", Color(1.0, 0.85, 0.2), stats)


func show_defeat(stats: Dictionary) -> void:
	_show_result("DEFEAT", Color(0.9, 0.25, 0.2), stats)


func _show_result(text: String, color: Color, stats: Dictionary) -> void:
	result_label.text = text
	result_label.add_theme_color_override("font_color", color)

	var lines: PackedStringArray = PackedStringArray()
	if stats.has("score") and stats["score"] > 0:
		lines.append("Score: %d" % stats["score"])
		lines.append("")
	lines.append("Game Time: %s" % stats.get("game_time", "00:00"))
	lines.append("Units Trained: %d" % stats.get("units_trained", 0))
	lines.append("Units Killed: %d" % stats.get("units_killed", 0))
	lines.append("Units Lost: %d" % stats.get("units_lost", 0))
	lines.append("Resources Gathered: %d" % stats.get("resources_gathered", 0))
	lines.append("Buildings Built: %d" % stats.get("buildings_built", 0))
	stats_label.text = "\n".join(lines)

	visible = true
	# Pause game tree so gameplay stops behind the overlay
	get_tree().paused = true


func _on_play_again() -> void:
	get_tree().paused = false
	visible = false
	restart_requested.emit()


func _on_main_menu() -> void:
	get_tree().paused = false
	visible = false
	main_menu_requested.emit()
