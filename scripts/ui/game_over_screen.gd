extends CanvasLayer
## Game over screen. Shows victory/defeat with player vs AI comparison.

signal restart_requested()
signal main_menu_requested()

@onready var panel: PanelContainer = %GameOverPanel
@onready var result_label: Label = %ResultLabel
@onready var time_label: Label = %TimeLabel
@onready var score_bar: HBoxContainer = %ScoreBar
@onready var player_score_label: Label = %PlayerScoreLabel
@onready var ai_score_label: Label = %AIScoreLabel
@onready var stats_container: VBoxContainer = %StatsContainer
@onready var play_again_button: Button = %PlayAgainButton
@onready var main_menu_button: Button = %MainMenuButton

@export var summary_diagnostics: Dictionary = {}

const COLOR_WIN := Color(0.3, 0.85, 0.3)
const COLOR_LOSE := Color(1.0, 0.35, 0.35)
const COLOR_TIE := Color(0.7, 0.7, 0.7)
const HUD_LAYOUT_SCRIPT := preload("res://scripts/ui/hud.gd")


func _ready() -> void:
	layer = 20
	visible = false
	panel.theme = KingdomTheme.create_theme()
	KingdomTheme.apply_primary(play_again_button)
	play_again_button.pressed.connect(_on_play_again)
	main_menu_button.pressed.connect(_on_main_menu)
	get_viewport().size_changed.connect(_fit_panel_to_viewport)
	_fit_panel_to_viewport()


func _fit_panel_to_viewport() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_fit_panel_to_size(viewport_size, _get_safe_area_rect(viewport_size))


func _fit_panel_to_size(viewport_size: Vector2, safe_area: Rect2 = Rect2()) -> void:
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
	var safe_bounds: Rect2 = safe_area.intersection(viewport_rect) if safe_area.has_area() else viewport_rect
	if not safe_bounds.has_area():
		safe_bounds = viewport_rect
	var compact: bool = viewport_size.y <= 500.0
	var target_size := Vector2(
		minf(480.0, safe_bounds.size.x - 16.0),
		minf(440.0, safe_bounds.size.y - 16.0)
	)
	var panel_center: Vector2 = safe_bounds.position + safe_bounds.size * 0.5
	var center_offset: Vector2 = panel_center - viewport_size * 0.5
	panel.custom_minimum_size = target_size
	panel.offset_left = center_offset.x - target_size.x * 0.5
	panel.offset_right = center_offset.x + target_size.x * 0.5
	panel.offset_top = center_offset.y - target_size.y * 0.5
	panel.offset_bottom = center_offset.y + target_size.y * 0.5
	var margin: MarginContainer = panel.get_node("Margin")
	var vbox: VBoxContainer = margin.get_node("VBox")
	var button_row: BoxContainer = vbox.get_node("ButtonRow")
	margin.add_theme_constant_override("margin_left", 14 if compact else 24)
	margin.add_theme_constant_override("margin_right", 14 if compact else 24)
	margin.add_theme_constant_override("margin_top", 5 if compact else 20)
	margin.add_theme_constant_override("margin_bottom", 5 if compact else 20)
	vbox.add_theme_constant_override("separation", 2 if compact else 12)
	button_row.add_theme_constant_override("separation", 4 if compact else 10)
	result_label.add_theme_font_size_override("font_size", 24 if compact else 36)
	time_label.add_theme_font_size_override("font_size", 12 if compact else 14)
	player_score_label.add_theme_font_size_override("font_size", 16 if compact else 20)
	ai_score_label.add_theme_font_size_override("font_size", 16 if compact else 20)
	play_again_button.add_theme_font_size_override("font_size", 16 if compact else 18)
	main_menu_button.add_theme_font_size_override("font_size", 16 if compact else 18)


func _get_safe_area_rect(viewport_size: Vector2) -> Rect2:
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
	if OS.has_feature("web"):
		return viewport_rect
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		return viewport_rect
	var safe_rect_i: Rect2i = DisplayServer.get_display_safe_area()
	if safe_rect_i.size.x <= 0 or safe_rect_i.size.y <= 0:
		return viewport_rect
	var screen_id: int = DisplayServer.SCREEN_OF_MAIN_WINDOW
	var display_rect := Rect2(
		Vector2(DisplayServer.screen_get_position(screen_id)),
		Vector2(DisplayServer.screen_get_size(screen_id))
	)
	return HUD_LAYOUT_SCRIPT.map_display_safe_area_to_viewport(
		Rect2(Vector2(safe_rect_i.position), Vector2(safe_rect_i.size)),
		display_rect,
		viewport_size
	)


func show_victory(stats: Dictionary) -> void:
	_show_result("VICTORY", Color(1.0, 0.85, 0.2), stats)


func show_defeat(stats: Dictionary) -> void:
	_show_result("DEFEAT", Color(0.9, 0.25, 0.2), stats)


func _show_result(text: String, color: Color, stats: Dictionary) -> void:
	play_again_button.disabled = false
	main_menu_button.disabled = false
	summary_diagnostics = stats.duplicate(true)
	summary_diagnostics["result"] = text
	result_label.text = text
	result_label.add_theme_color_override("font_color", color)

	# Time and age
	var time_str: String = stats.get("game_time", "00:00")
	var player_age: int = stats.get("player_age", 1)
	var ai_age: int = stats.get("ai_age", 1)
	var age_names: Array = ["", "Dark Age", "Feudal Age", "Castle Age", "Imperial Age"]
	var p_age_name: String = age_names[clampi(player_age, 1, 4)]
	var a_age_name: String = age_names[clampi(ai_age, 1, 4)]
	var reason: String = str(stats.get("victory_reason", "Match concluded"))
	var player_feudal: String = _format_timing(float(stats.get("player_feudal_seconds", -1.0)))
	var ai_feudal: String = _format_timing(float(stats.get("ai_feudal_seconds", -1.0)))
	time_label.text = "%s  •  %s\nFeudal %s vs %s  •  End %s vs %s" % [time_str, reason, player_feudal, ai_feudal, p_age_name, a_age_name]

	# Scores
	var player_score: int = stats.get("score", 0)
	var ai_score: int = stats.get("ai_score", 0)
	player_score_label.text = "You: %d" % player_score
	ai_score_label.text = "AI: %d" % ai_score
	if player_score == ai_score:
		player_score_label.add_theme_color_override("font_color", COLOR_TIE)
		ai_score_label.add_theme_color_override("font_color", COLOR_TIE)
	else:
		player_score_label.add_theme_color_override("font_color",
			COLOR_WIN if player_score > ai_score else COLOR_LOSE)
		ai_score_label.add_theme_color_override("font_color",
			COLOR_WIN if ai_score > player_score else COLOR_LOSE)

	# Stat comparison rows
	for child in stats_container.get_children():
		child.queue_free()
	_add_stat_row("Army Produced", stats.get("army_trained", 0), stats.get("ai_army_trained", 0))
	_add_stat_row("Units Lost", stats.get("units_lost", 0), stats.get("ai_units_lost", 0), true)
	_add_stat_row("Buildings Lost", stats.get("buildings_lost", 0), stats.get("ai_buildings_lost", 0), true)
	_add_stat_row("Resources Gathered", stats.get("resources_gathered", 0), stats.get("ai_resources_gathered", 0))
	_add_stat_row("Sacred Control", stats.get("sacred_control_seconds", 0), stats.get("ai_sacred_control_seconds", 0))

	_fit_panel_to_viewport()
	visible = true
	get_tree().paused = true
	_animate_in()


func _format_timing(seconds_value: float) -> String:
	if seconds_value < 0.0:
		return "—"
	var total_seconds: int = int(round(seconds_value))
	@warning_ignore("integer_division")
	return "%d:%02d" % [total_seconds / 60, total_seconds % 60]


func _add_stat_row(label_text: String, player_val: int, ai_val: int, lower_is_better: bool = false) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var p_label := Label.new()
	p_label.text = str(player_val)
	p_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	p_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var compact: bool = get_viewport().get_visible_rect().size.y <= 500.0
	p_label.add_theme_font_size_override("font_size", 11 if compact else 15)

	var center := Label.new()
	center.text = label_text
	center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_font_size_override("font_size", 11 if compact else 14)
	center.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

	var a_label := Label.new()
	a_label.text = str(ai_val)
	a_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	a_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a_label.add_theme_font_size_override("font_size", 11 if compact else 15)

	# Color code: green for winner, red for loser
	if player_val != ai_val:
		var player_wins: bool
		if lower_is_better:
			player_wins = player_val < ai_val
		else:
			player_wins = player_val > ai_val
		p_label.add_theme_color_override("font_color", COLOR_WIN if player_wins else COLOR_LOSE)
		a_label.add_theme_color_override("font_color", COLOR_LOSE if player_wins else COLOR_WIN)
	else:
		p_label.add_theme_color_override("font_color", COLOR_TIE)
		a_label.add_theme_color_override("font_color", COLOR_TIE)

	row.add_child(p_label)
	row.add_child(center)
	row.add_child(a_label)
	stats_container.add_child(row)


func _animate_in() -> void:
	# Fade and scale within the safe bounds; a downward slide can put the panel
	# under a landscape home indicator during its first animation frames.
	panel.modulate = Color(1, 1, 1, 0)
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.96, 0.96)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Panel fades and settles without leaving its fitted rectangle.
	tween.tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.4)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.4)


func _on_play_again() -> void:
	if play_again_button.disabled:
		return
	play_again_button.disabled = true
	main_menu_button.disabled = true
	AudioManager.play_ui("button_click")
	get_tree().paused = false
	visible = false
	restart_requested.emit()


func _on_main_menu() -> void:
	if main_menu_button.disabled:
		return
	play_again_button.disabled = true
	main_menu_button.disabled = true
	AudioManager.play_ui("button_click")
	get_tree().paused = false
	visible = false
	main_menu_requested.emit()
