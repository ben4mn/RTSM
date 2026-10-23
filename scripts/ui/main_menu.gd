extends Control
## One game-creation journey: battlefield, opponent, shared room, then battle.

const THEME := preload("res://scripts/ui/kingdom_theme.gd")
const DIORAMA := preload("res://scripts/ui/menu_diorama.gd")
const MAP_PREVIEW := preload("res://scripts/ui/map_preview.gd")
const WEB_SHELL_BRIDGE := preload("res://scripts/ui/web_shell_bridge.gd")
const DIFFICULTY_NAMES: Array[String] = ["Easy", "Medium", "Hard"]
const DIFFICULTY_DESCRIPTIONS: Array[String] = ["Time to build. Light pressure.", "Regular raids. Balanced pressure.", "Early raids. Relentless pressure."]
const MAP_TRAITS: Array[String] = ["Room to manoeuvre", "Control the crossings", "Find the side routes"]
# Expanded cards, tabs, header and footer need 545px with the current fonts.
# Leave a little rounding headroom inside the frame, after safe areas and chrome.
const EXPANDED_LAYOUT_MIN_HEIGHT: float = 560.0

@export var main_menu_diagnostics: Dictionary = {}
var _shared_settings: Control
var _active_safe_area := Rect2()
var _compact_layout: bool = false
var _screen: String = "home"
var _mode: String = "solo"
var _selected_difficulty: int = 0
var _selected_population_limit: int = 30
var _network_search_active: bool = false
var _room_waiting: bool = false
var _web_update_safe: bool = false
var _session: Node
var _transition: Tween
var _root_margin: MarginContainer
var _frame_rect := Rect2()
var _frame_reflow_queued: bool = false
var _shell: VBoxContainer
var _header: HBoxContainer
var _page_title: Label
var _back_button: Button
var settings_button: Button
var _home: BoxContainer
var _hero: VBoxContainer
var title_label: Label
var promise_label: Label
var _hero_art: Control
var _home_actions: VBoxContainer
var _home_intro: Label
var _home_note: Label
var _new_game_button: Button
var _online_button: Button
var _setup: VBoxContainer
var _tabs: HBoxContainer
var _solo_tab: Button
var _online_tab: Button
var _columns: BoxContainer
var _map_scroll: ScrollContainer
var _map_panel: VBoxContainer
var _map_cards: HBoxContainer
var _map_buttons: Array[Button] = []
var _map_previews: Array[Control] = []
var _map_names: Array[Label] = []
var _map_badges: Array[Label] = []
var map_summary_label: Label
var _map_note: Label
var _map_heading: Label
var _options_panel: PanelContainer
var _options_scroll: ScrollContainer
var _options_body: VBoxContainer
var _solo_options: VBoxContainer
var _multiplayer_options: VBoxContainer
var _difficulty_row: HBoxContainer
var _difficulty_buttons: Array[Button] = []
var difficulty_option: OptionButton
var difficulty_description: Label
var guided_opening_toggle: CheckButton
var _population_buttons: Array[Button] = []
var _rules_option: OptionButton
var seed_input: LineEdit
var random_seed_button: Button
var _host_button: Button
var _join_input: LineEdit
var _join_button: Button
var _quick_match_button: Button
var _room_details: VBoxContainer
var _room_code: Label
var _room_players: Label
var _room_map: Label
var _network_status: Label
var _footer: HBoxContainer
var _selection_summary: Label
var start_button: Button
var _leave_button: Button


func _ready() -> void:
	GameManager.set_state(GameManager.GameState.MENU)
	theme = THEME.create_theme()
	_selected_difficulty = clampi(GameManager.selected_difficulty, 0, 2)
	_selected_population_limit = GameManager.selected_population_limit
	_session = get_node_or_null("/root/NetworkSession")
	_build_interface()
	if _session != null:
		_session.connect("status_changed", _on_network_status_changed)
		if _session.has_signal("room_changed"):
			_session.connect("room_changed", _on_room_changed)
		_on_network_status_changed(str(_session.get("state")), str(_session.get("status_text")))
	_refresh_selection()
	_show_screen("home")
	if GameManager.has_meta("open_new_game"):
		var requested_mode: String = str(GameManager.get_meta("open_new_game"))
		GameManager.remove_meta("open_new_game")
		_open_new_game("multiplayer" if requested_mode == "multiplayer" else "solo")
	get_viewport().size_changed.connect(_refresh_responsive_layout)
	WEB_SHELL_BRIDGE.watch_safe_area(self, _refresh_responsive_layout)
	WEB_SHELL_BRIDGE.set_controls_visible(true)
	_refresh_web_update_safety()
	call_deferred("_refresh_responsive_layout")


func _exit_tree() -> void:
	WEB_SHELL_BRIDGE.set_update_safe(false)
	WEB_SHELL_BRIDGE.set_controls_visible(false)


func _input(event: InputEvent) -> void:
	if is_instance_valid(_shared_settings):
		return
	if event.is_action_pressed("cancel") and _screen != "home":
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _build_interface() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.color = THEME.INK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_root_margin = MarginContainer.new()
	_root_margin.name = "MenuFrame"
	add_child(_root_margin)
	_root_margin.minimum_size_changed.connect(_queue_frame_reflow)
	_shell = VBoxContainer.new()
	_shell.add_theme_constant_override("separation", 14)
	_root_margin.add_child(_shell)
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 16)
	_shell.add_child(_header)
	_back_button = _button("Back", "BackButton", _on_back_pressed)
	_header.add_child(_back_button)
	_page_title = _label("POCKET KINGDOMS", 22)
	THEME.apply_heading(_page_title, 22)
	_page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(_page_title)
	settings_button = _button("Settings", "SettingsButton", _on_settings_pressed)
	settings_button.icon = load("res://assets/ui/icons/settings.svg")
	settings_button.add_theme_constant_override("icon_max_width", 20)
	_header.add_child(settings_button)
	var rule := HSeparator.new()
	var rule_style := StyleBoxLine.new()
	rule_style.color = THEME.BORDER
	rule_style.thickness = 1
	rule.add_theme_stylebox_override("separator", rule_style)
	_shell.add_child(rule)
	_build_home()
	_build_setup()
	_footer = HBoxContainer.new()
	_footer.name = "GameFooter"
	_footer.add_theme_constant_override("separation", 12)
	_shell.add_child(_footer)
	_selection_summary = _label("", 15, true)
	_selection_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.add_child(_selection_summary)
	_leave_button = _button("Leave room", "LeaveRoomButton", _leave_room)
	_footer.add_child(_leave_button)
	start_button = _button("Start game", "StartButton", _on_start_pressed)
	start_button.custom_minimum_size.x = 184
	THEME.apply_primary(start_button)
	_footer.add_child(start_button)


func _build_home() -> void:
	_home = BoxContainer.new()
	_home.name = "Home"
	_home.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_home.add_theme_constant_override("separation", 48)
	_shell.add_child(_home)
	_hero = VBoxContainer.new()
	_hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero.add_theme_constant_override("separation", 6)
	_home.add_child(_hero)
	var eyebrow := _label("BUILD A KINGDOM. COMMAND THE FIELD.", 12)
	THEME.apply_eyebrow(eyebrow)
	_hero.add_child(eyebrow)
	title_label = _label("Pocket\nKingdoms", 52)
	THEME.apply_heading(title_label, 52)
	_hero.add_child(title_label)
	_hero_art = Control.new()
	_hero_art.set_script(DIORAMA)
	_hero_art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero_art.clip_contents = true
	_hero.add_child(_hero_art)
	_home_actions = VBoxContainer.new()
	_home_actions.name = "HomeActions"
	_home_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_home_actions.custom_minimum_size.x = 290
	_home_actions.add_theme_constant_override("separation", 12)
	_home.add_child(_home_actions)
	promise_label = _label("A kingdom begins\nwith a choice.", 28)
	THEME.apply_heading(promise_label, 28)
	_home_actions.add_child(promise_label)
	_home_intro = _label("Gather, build and command your army.\nClaim the Sacred Site or break the enemy town.", 16, true)
	_home_intro.add_theme_color_override("font_color", THEME.MUTED)
	_home_actions.add_child(_home_intro)
	_new_game_button = _button("New Game", "NewGameButton", _open_new_game.bind("solo"))
	_new_game_button.custom_minimum_size.y = 58
	THEME.apply_primary(_new_game_button)
	_home_actions.add_child(_new_game_button)
	_online_button = _button("Join a friend", "JoinFriendButton", _open_new_game.bind("multiplayer"))
	_home_actions.add_child(_online_button)
	_home_note = _label("Solo skirmish  ·  Private 1v1 rooms", 13)
	_home_note.add_theme_color_override("font_color", THEME.MUTED)
	_home_actions.add_child(_home_note)


func _build_setup() -> void:
	_setup = VBoxContainer.new()
	_setup.name = "NewGame"
	_setup.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_setup.add_theme_constant_override("separation", 12)
	_shell.add_child(_setup)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	_setup.add_child(_tabs)
	_solo_tab = _button("Solo skirmish", "SoloTab", _set_mode.bind("solo"))
	_online_tab = _button("Multiplayer", "MultiplayerTab", _set_mode.bind("multiplayer"))
	for button: Button in [_solo_tab, _online_tab]:
		button.toggle_mode = true
		button.custom_minimum_size.x = 160
		_tabs.add_child(button)
	_columns = BoxContainer.new()
	_columns.name = "SetupColumns"
	_columns.add_theme_constant_override("separation", 20)
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_setup.add_child(_columns)
	_map_scroll = ScrollContainer.new()
	_map_scroll.name = "BattlefieldScroll"
	_map_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_scroll.size_flags_stretch_ratio = 1.6
	_map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_map_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_columns.add_child(_map_scroll)
	_map_panel = VBoxContainer.new()
	_map_panel.name = "BattlefieldSelection"
	_map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_panel.add_theme_constant_override("separation", 8)
	_map_scroll.add_child(_map_panel)
	_map_heading = _label("CHOOSE YOUR BATTLEFIELD", 12)
	THEME.apply_eyebrow(_map_heading)
	_map_panel.add_child(_map_heading)
	_map_cards = HBoxContainer.new()
	_map_cards.name = "MapChoices"
	_map_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_cards.add_theme_constant_override("separation", 10)
	_map_panel.add_child(_map_cards)
	var group := ButtonGroup.new()
	for archetype: int in MapData.MAP_ARCHETYPES:
		var button := _button("", "Map%dButton" % archetype, _select_map.bind(archetype))
		button.tooltip_text = MapData.get_archetype_description(archetype)
		button.accessibility_name = MapData.get_archetype_name(archetype) + ". " + button.tooltip_text
		button.toggle_mode = true
		button.button_group = group
		var selected_style: StyleBoxFlat = THEME.panel_style(THEME.INK_LIGHT, THEME.GOLD)
		selected_style.set_border_width_all(2)
		button.add_theme_stylebox_override("pressed", selected_style)
		button.add_theme_stylebox_override("hover_pressed", selected_style)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_map_cards.add_child(button)
		_map_buttons.append(button)
		var stack := VBoxContainer.new()
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.offset_left = 8
		stack.offset_top = 8
		stack.offset_right = -8
		stack.offset_bottom = -8
		stack.add_theme_constant_override("separation", 5)
		button.add_child(stack)
		var preview: Control = MAP_PREVIEW.new()
		preview.set("archetype", archetype)
		preview.custom_minimum_size.y = 82
		preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		stack.add_child(preview)
		_map_previews.append(preview)
		var name_label := _label(MapData.get_archetype_name(archetype).replace(" ", "\n"), 17)
		name_label.add_theme_font_override("font", THEME.FONT_MEDIUM)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(name_label)
		_map_names.append(name_label)
		var badge := _label("SELECT", 11)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_color_override("font_color", THEME.MUTED)
		stack.add_child(badge)
		_map_badges.append(badge)
	map_summary_label = _label("", 15, true)
	map_summary_label.custom_minimum_size.y = 36
	_map_panel.add_child(map_summary_label)
	_map_note = _label("Terrain previews · blue / red starts · diamond objective", 12)
	_map_note.add_theme_color_override("font_color", THEME.MUTED)
	_map_panel.add_child(_map_note)
	_build_options()


func _build_options() -> void:
	_options_panel = PanelContainer.new()
	_options_panel.name = "MatchOptions"
	_options_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options_panel.add_theme_stylebox_override("panel", THEME.inset_panel())
	_columns.add_child(_options_panel)
	_options_scroll = ScrollContainer.new()
	_options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_options_panel.add_child(_options_scroll)
	_options_body = VBoxContainer.new()
	_options_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options_body.add_theme_constant_override("separation", 12)
	_options_scroll.add_child(_options_body)
	_solo_options = VBoxContainer.new()
	_solo_options.add_theme_constant_override("separation", 8)
	_options_body.add_child(_solo_options)
	var label := _label("YOUR OPPONENT", 12)
	THEME.apply_eyebrow(label)
	_solo_options.add_child(label)
	_difficulty_row = HBoxContainer.new()
	_difficulty_row.add_theme_constant_override("separation", 4)
	_solo_options.add_child(_difficulty_row)
	difficulty_option = OptionButton.new()
	for difficulty: String in DIFFICULTY_NAMES:
		difficulty_option.add_item(difficulty)
	difficulty_option.hide()
	_solo_options.add_child(difficulty_option)
	for i: int in DIFFICULTY_NAMES.size():
		var button := _button(DIFFICULTY_NAMES[i], DIFFICULTY_NAMES[i] + "Difficulty", _on_difficulty_changed.bind(i))
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 14)
		button.add_theme_stylebox_override("normal", _small_button_style("normal"))
		button.add_theme_stylebox_override("pressed", _small_button_style("pressed"))
		_difficulty_row.add_child(button)
		_difficulty_buttons.append(button)
	difficulty_description = _label("", 13, true)
	difficulty_description.add_theme_color_override("font_color", THEME.MUTED)
	_solo_options.add_child(difficulty_description)
	guided_opening_toggle = CheckButton.new()
	guided_opening_toggle.name = "GuidedOpeningToggle"
	guided_opening_toggle.text = "Guide my opening"
	guided_opening_toggle.custom_minimum_size.y = 48
	guided_opening_toggle.add_theme_font_size_override("font_size", 14)
	guided_opening_toggle.set_pressed_no_signal(GameManager.guided_opening_enabled)
	guided_opening_toggle.toggled.connect(_on_guided_opening_toggled)
	_solo_options.add_child(guided_opening_toggle)
	var rules_label := _label("MATCH RULES", 12)
	THEME.apply_eyebrow(rules_label)
	_solo_options.add_child(rules_label)
	_rules_option = OptionButton.new()
	_rules_option.name = "MatchRulesOption"
	_rules_option.custom_minimum_size.y = 48
	_rules_option.add_item("Standard skirmish")
	_rules_option.add_item("Control race")
	_rules_option.select(GameManager.selected_match_mode)
	_rules_option.item_selected.connect(func(index: int) -> void:
		GameManager.selected_match_mode = index
		_refresh_selection()
	)
	_solo_options.add_child(_rules_option)
	_solo_options.add_child(_label("Population per player", 14))
	var population := HBoxContainer.new()
	population.add_theme_constant_override("separation", 6)
	_solo_options.add_child(population)
	for limit: int in SkirmishData.POPULATION_OPTIONS:
		var button := _button(str(limit), "Population%dButton" % limit, _on_population_selected.bind(limit))
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		population.add_child(button)
		_population_buttons.append(button)
	_solo_options.add_child(_label("Map seed (optional)", 14))
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 6)
	_solo_options.add_child(seed_row)
	seed_input = LineEdit.new()
	seed_input.name = "MapSeedInput"
	seed_input.placeholder_text = "Random"
	seed_input.text = str(GameManager.selected_map_seed) if GameManager.selected_map_seed >= 0 else ""
	seed_input.custom_minimum_size = Vector2(90, 48)
	seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_input.text_changed.connect(_on_seed_text_changed)
	seed_row.add_child(seed_input)
	random_seed_button = _button("Random", "RandomSeedButton", _on_random_seed_pressed)
	seed_row.add_child(random_seed_button)
	_build_multiplayer_options()


func _build_multiplayer_options() -> void:
	_multiplayer_options = VBoxContainer.new()
	_multiplayer_options.name = "MultiplayerSetup"
	_multiplayer_options.add_theme_constant_override("separation", 10)
	_options_body.add_child(_multiplayer_options)
	var heading := _label("PLAY WITH A FRIEND", 12)
	THEME.apply_eyebrow(heading)
	_multiplayer_options.add_child(heading)
	_multiplayer_options.add_child(_label("Choose a battlefield, then share your room code.", 15, true))
	_host_button = _button("Create room", "HostGameButton", _host_game)
	THEME.apply_primary(_host_button)
	_multiplayer_options.add_child(_host_button)
	_multiplayer_options.add_child(_label("Already have a code?", 14))
	_join_input = LineEdit.new()
	_join_input.name = "RoomCodeInput"
	_join_input.placeholder_text = "Enter room code"
	_join_input.max_length = 6
	_join_input.custom_minimum_size.y = 48
	_join_input.text_changed.connect(func(_text: String) -> void: _join_button.disabled = _join_input.text.strip_edges().length() != 6)
	_join_input.text_submitted.connect(func(_text: String) -> void: _join_game())
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 6)
	_multiplayer_options.add_child(join_row)
	_join_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_input.custom_minimum_size.x = 90
	join_row.add_child(_join_input)
	_join_button = _button("Join", "JoinGameButton", _join_game)
	_join_button.disabled = true
	join_row.add_child(_join_button)
	_multiplayer_options.add_child(_label("Standard rules · 30 population\nBoth players see the host’s battlefield.", 13, true))
	_quick_match_button = _button("Quick match", "QuickMatchButton", func() -> void:
		if _session != null:
			_session.call("find_match")
	)
	_multiplayer_options.add_child(_quick_match_button)
	_multiplayer_options.add_child(_label("Find any opponent. The server chooses the battlefield.", 13, true))
	_room_details = VBoxContainer.new()
	_room_details.name = "RoomDetails"
	_room_details.add_theme_constant_override("separation", 12)
	_options_body.add_child(_room_details)
	var room_heading := _label("YOUR ROOM", 12)
	THEME.apply_eyebrow(room_heading)
	_room_details.add_child(room_heading)
	_room_code = _label("", 30)
	THEME.apply_heading(_room_code, 30)
	_room_details.add_child(_room_code)
	_room_players = _label("", 16, true)
	_room_details.add_child(_room_players)
	_room_map = _label("", 15, true)
	_room_details.add_child(_room_map)
	_room_details.add_child(_label("Standard rules · 30 population", 13, true))
	_network_status = _label("", 14, true)
	_network_status.name = "NetworkStatus"
	_network_status.add_theme_color_override("font_color", THEME.MUTED)
	_options_body.add_child(_network_status)
	_options_body.move_child(_network_status, 0)


func _button(text: String, node_name: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(48, 48)
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(callback)
	return button


func _label(text: String, font_size: int, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _small_button_style(state: String) -> StyleBoxFlat:
	var style: StyleBoxFlat = THEME.button_style("secondary", state)
	style.content_margin_left = 7
	style.content_margin_right = 7
	return style


func _open_new_game(mode: String = "solo") -> void:
	_set_mode(mode)
	_show_screen("setup")


func _show_screen(screen: String) -> void:
	var changed: bool = _screen != screen
	_screen = screen
	_home.visible = screen == "home"
	_setup.visible = screen != "home"
	_footer.visible = screen != "home"
	_tabs.visible = screen != "home"
	_back_button.visible = screen != "home"
	_page_title.text = "THE COMMAND TABLE" if screen == "home" else "New Game"
	_refresh_selection()
	if changed and not GameManager.reduced_motion:
		if _transition != null:
			_transition.kill()
		var surface: Control = _home if screen == "home" else _setup
		surface.modulate.a = 0.0
		_transition = create_tween()
		_transition.tween_property(surface, "modulate:a", 1.0, 0.16)
	call_deferred("_refresh_responsive_layout")


func _set_mode(mode: String) -> void:
	if _is_room_open() or _network_search_active:
		return
	_mode = mode
	_options_scroll.scroll_vertical = 0
	_refresh_selection()


func _select_map(archetype: int) -> void:
	if _is_room_open():
		if not bool(_session.get("room_host")):
			return
		_session.call("set_hosted_map", archetype)
		return
	GameManager.selected_map_archetype = MapData.normalize_archetype(archetype)
	_refresh_selection()


func _refresh_selection() -> void:
	if not is_instance_valid(start_button):
		return
	var room: bool = _is_room_open()
	var online: bool = _mode == "multiplayer" or room
	var archetype: int = int(_session.get("match_map_archetype")) if room else GameManager.selected_map_archetype
	var guest: bool = room and not bool(_session.get("room_host"))
	for i: int in _map_buttons.size():
		_map_buttons[i].set_pressed_no_signal(i == archetype)
		_map_buttons[i].disabled = guest or _network_search_active or _room_waiting
		_map_names[i].add_theme_color_override("font_color", THEME.PARCHMENT)
		_map_buttons[i].add_theme_stylebox_override("disabled", _map_buttons[i].get_theme_stylebox("pressed") if i == archetype else THEME.button_style())
		_map_badges[i].text = "SELECTED" if i == archetype else "SELECT"
		_map_badges[i].add_theme_color_override("font_color", THEME.GOLD if i == archetype else THEME.MUTED)
	_map_heading.text = "HOST’S BATTLEFIELD" if guest else "CHOOSE YOUR BATTLEFIELD"
	map_summary_label.text = MapData.get_archetype_description(archetype)
	_selection_summary.text = "%s\n%s" % [MapData.get_archetype_name(archetype), "Shared battlefield · Standard rules" if online else "%s opponent · %d population" % [DIFFICULTY_NAMES[_selected_difficulty], _selected_population_limit]]
	_solo_tab.set_pressed_no_signal(not online)
	_online_tab.set_pressed_no_signal(online)
	_solo_tab.disabled = room or _network_search_active
	_online_tab.disabled = room or _network_search_active
	_solo_options.visible = not online
	_multiplayer_options.visible = online and not room
	_room_details.visible = room
	_network_status.visible = online and not _network_status.text.is_empty()
	_leave_button.visible = room or _network_search_active
	start_button.visible = not online or room
	start_button.text = "Start game" if not room else ("Start match" if not guest else "Waiting for host")
	start_button.disabled = _network_search_active or _room_waiting or (room and (guest or int(_session.get("room_players")) < 2))
	_host_button.disabled = _network_search_active
	_quick_match_button.disabled = _network_search_active
	_leave_button.text = "Cancel search" if _network_search_active and not room else "Leave room"
	_join_button.disabled = _network_search_active or _join_input.text.strip_edges().length() != 6
	_join_input.editable = not _network_search_active
	for i: int in _difficulty_buttons.size():
		_difficulty_buttons[i].set_pressed_no_signal(i == _selected_difficulty)
	difficulty_option.select(_selected_difficulty)
	difficulty_description.text = DIFFICULTY_DESCRIPTIONS[_selected_difficulty]
	for button: Button in _population_buttons:
		button.set_pressed_no_signal(int(button.text) == _selected_population_limit)
	_refresh_main_menu_diagnostics()


func _is_room_open() -> bool:
	return _session != null and str(_session.get("room_code")) != "" and str(_session.get("state")) in ["lobby", "loading", "playing"]


func _host_game() -> void:
	if _session != null and not _network_search_active:
		_session.call("host_game", GameManager.selected_map_archetype)


func _join_game() -> void:
	if _session != null and not _join_button.disabled:
		_session.call("join_game", _join_input.text.strip_edges().to_upper())


func _on_room_changed() -> void:
	if _is_room_open():
		_mode = "multiplayer"
		_show_screen("setup")
		_room_code.text = str(_session.get("room_code"))
		_room_players.text = "You are the host\n%d / 2 players joined" % int(_session.get("room_players")) if bool(_session.get("room_host")) else "You joined the room\n2 / 2 players joined"
		_room_map.text = "Battlefield\n" + MapData.get_archetype_name(int(_session.get("match_map_archetype")))
	_refresh_selection()


func _on_network_status_changed(state: String, message: String) -> void:
	_network_search_active = state in ["connecting", "searching", "hosting", "joining", "loading"]
	_room_waiting = state == "lobby" and message == "Waiting for an arena…"
	_network_status.text = message
	_network_status.add_theme_color_override("font_color", THEME.RUST if state == "error" else THEME.MUTED)
	_refresh_web_update_safety()
	_on_room_changed()
	_refresh_selection()


func _leave_room() -> void:
	if _session != null:
		_session.call("leave_match")
	_refresh_selection()


func _on_back_pressed() -> void:
	if _is_room_open() or _network_search_active:
		_leave_room()
	else:
		_show_screen("home")


func _on_difficulty_changed(index: int) -> void:
	_selected_difficulty = clampi(index, 0, 2)
	GameManager.selected_difficulty = _selected_difficulty
	_refresh_selection()


func _on_population_selected(limit: int) -> void:
	_selected_population_limit = SkirmishData.normalize_population_limit(limit)
	GameManager.selected_population_limit = _selected_population_limit
	_refresh_selection()


func _on_guided_opening_toggled(enabled: bool) -> void:
	GameManager.guided_opening_enabled = enabled
	_refresh_main_menu_diagnostics()


func _on_seed_text_changed(_text: String) -> void:
	_refresh_main_menu_diagnostics()


func _on_random_seed_pressed() -> void:
	seed_input.text = ""
	GameManager.selected_map_seed = -1
	seed_input.release_focus()
	_refresh_main_menu_diagnostics()


func _on_settings_pressed() -> void:
	_shared_settings = preload("res://scripts/ui/settings_panel.gd").open(self)
	_shared_settings.closed.connect(_on_settings_closed)
	_refresh_web_update_safety()
	call_deferred("_refresh_responsive_layout")


func _on_settings_closed() -> void:
	_shared_settings = null
	_refresh_web_update_safety()
	call_deferred("_refresh_responsive_layout")


func _refresh_web_update_safety() -> void:
	# A waiting room is a live connection too. Status changes and closing Settings
	# must not let a pending service-worker update reload a room or loading match.
	var session_state: String = str(_session.get("state")) if _session != null else "idle"
	_web_update_safe = not is_instance_valid(_shared_settings) and session_state in ["idle", "error"]
	WEB_SHELL_BRIDGE.set_update_safe(_web_update_safe)


func _on_start_pressed() -> void:
	if start_button.disabled:
		return
	if _is_room_open():
		_session.call("start_hosted_match")
		return
	if _mode != "solo" or not WEB_SHELL_BRIDGE.begin_match():
		return
	GameManager.selected_difficulty = _selected_difficulty
	GameManager.selected_population_limit = _selected_population_limit
	GameManager.guided_opening_enabled = guided_opening_toggle.button_pressed
	var seed_text: String = seed_input.text.strip_edges()
	GameManager.selected_map_seed = maxi(-1, int(seed_text)) if seed_text.is_valid_int() else -1
	GameManager.save_preferences()
	start_button.disabled = true
	# Preserve input dispatch lifetime on touch/Web, including repeat presses.
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main/main.tscn")


func _refresh_responsive_layout() -> void:
	if not is_node_ready():
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	apply_mobile_layout(viewport_size, _get_safe_area_rect(viewport_size))
	call_deferred("_refresh_main_menu_diagnostics")


func apply_mobile_layout(viewport_size: Vector2, safe_area: Rect2, shell_top_clearance: float = -1.0) -> void:
	_active_safe_area = safe_area.intersection(Rect2(Vector2.ZERO, viewport_size))
	if not _active_safe_area.has_area():
		_active_safe_area = Rect2(Vector2.ZERO, viewport_size)
	if is_instance_valid(_shared_settings):
		_shared_settings.apply_mobile_layout(viewport_size, _active_safe_area)
	var web_clearance: float = shell_top_clearance if shell_top_clearance >= 0.0 else WEB_SHELL_BRIDGE.get_menu_top_clearance(viewport_size)
	var expanded_frame: Rect2 = _menu_frame_rect(_active_safe_area, 32.0, web_clearance)
	_compact_layout = expanded_frame.size.y < EXPANDED_LAYOUT_MIN_HEIGHT
	var compact: bool = _compact_layout
	var desired_tab_parent: Node = _header if compact else _setup
	if _tabs.get_parent() != desired_tab_parent:
		_tabs.reparent(desired_tab_parent)
		desired_tab_parent.move_child(_tabs, 1 if compact else 0)
	_page_title.visible = not compact or _screen == "home"
	_home_intro.visible = not compact
	_home_note.visible = not compact
	var margin: float = 12.0 if compact else 32.0
	var available: Rect2 = _menu_frame_rect(_active_safe_area, margin, web_clearance)
	# On the shortest UI-scaled phones the browser toolbar leaves less than the
	# compact body's minimum. Keep actions fixed and scroll battlefield details.
	var short_body: bool = compact and available.size.y < 302.0
	_map_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if short_body else ScrollContainer.SCROLL_MODE_DISABLED
	_map_heading.visible = not short_body
	var max_width: float = 1280.0
	if available.size.x > max_width:
		available.position.x += (available.size.x - max_width) * 0.5
		available.size.x = max_width
	_frame_rect = available
	_root_margin.position = available.position
	_root_margin.size = available.size
	_shell.add_theme_constant_override("separation", 6 if compact else 14)
	_setup.add_theme_constant_override("separation", 6 if compact else 14)
	_columns.add_theme_constant_override("separation", 12 if compact else 24)
	_map_cards.add_theme_constant_override("separation", 6 if compact else 12)
	_map_panel.add_theme_constant_override("separation", 4 if compact else 8)
	_options_panel.custom_minimum_size.x = 236 if compact else 310
	_columns.vertical = available.size.x < 560
	_page_title.add_theme_font_size_override("font_size", 18 if compact else 22)
	_header.add_theme_constant_override("separation", 8 if compact else 16)
	for button: Button in [_solo_tab, _online_tab]:
		button.custom_minimum_size.x = 140 if compact else 180
	_map_note.visible = not compact
	map_summary_label.add_theme_font_size_override("font_size", 13 if compact else 15)
	map_summary_label.custom_minimum_size.y = 30 if compact else 38
	for i: int in _map_buttons.size():
		_map_buttons[i].custom_minimum_size.y = 126 if compact else 240
		_map_previews[i].custom_minimum_size.y = 54 if compact else 144
		_map_names[i].add_theme_font_size_override("font_size", 14 if compact else 18)
		_map_badges[i].add_theme_font_size_override("font_size", 10 if compact else 12)
	_home.add_theme_constant_override("separation", 24 if compact else 64)
	_home_actions.custom_minimum_size.x = minf(310, available.size.x * 0.43)
	title_label.add_theme_font_size_override("font_size", 34 if compact else 60)
	promise_label.add_theme_font_size_override("font_size", 22 if compact else 30)
	_selection_summary.add_theme_font_size_override("font_size", 13 if compact else 16)
	start_button.custom_minimum_size.x = 158 if compact else 200
	start_button.custom_minimum_size.y = 48 if compact else 56
	if available.size.x < 560:
		_home.vertical = true
		_home_actions.custom_minimum_size.x = 0
		_hero_art.custom_minimum_size.y = 90
	else:
		_home.vertical = false
		_hero_art.custom_minimum_size.y = 0


func _queue_frame_reflow() -> void:
	if _frame_reflow_queued:
		return
	_frame_reflow_queued = true
	call_deferred("_restore_frame_size")


func _restore_frame_size() -> void:
	_frame_reflow_queued = false
	if not is_inside_tree() or not _frame_rect.has_area():
		return
	# First-show autowrap can briefly inflate a manually sized Container. Once
	# its minimum settles, restore the viewport allocation instead of retaining
	# that transient height and stretching the map cards off screen.
	_root_margin.size = _frame_rect.size


static func _menu_frame_rect(safe_area: Rect2, margin: float, top_clearance: float) -> Rect2:
	var available: Rect2 = safe_area.grow(-margin)
	if top_clearance > available.position.y:
		available.size.y -= top_clearance - available.position.y
		available.position.y = top_clearance
	return available


func _get_safe_area_rect(viewport_size: Vector2) -> Rect2:
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
	if OS.has_feature("web"):
		return WEB_SHELL_BRIDGE.get_safe_area_rect(viewport_size)
	if not OS.has_feature("mobile"):
		return viewport_rect
	var safe_rect: Rect2i = DisplayServer.get_display_safe_area()
	var screen_id: int = DisplayServer.SCREEN_OF_MAIN_WINDOW
	return map_display_safe_area_to_viewport(Rect2(safe_rect), Rect2(Vector2(DisplayServer.screen_get_position(screen_id)), Vector2(DisplayServer.screen_get_size(screen_id))), viewport_size)


static func map_display_safe_area_to_viewport(raw_safe_area: Rect2, display_rect: Rect2, viewport_size: Vector2) -> Rect2:
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
	if not raw_safe_area.has_area() or not display_rect.has_area():
		return viewport_rect
	var clipped: Rect2 = raw_safe_area.intersection(display_rect)
	if not clipped.has_area():
		return viewport_rect
	var factor := viewport_size / display_rect.size
	return Rect2((clipped.position - display_rect.position) * factor, clipped.size * factor).intersection(viewport_rect)


func _refresh_main_menu_diagnostics() -> void:
	if not is_inside_tree() or not is_instance_valid(start_button) or OS.has_feature("production"):
		return
	main_menu_diagnostics = {
		"ready": is_node_ready(), "screen": _screen, "mode": _mode,
		"title": title_label.text, "map_summary": map_summary_label.text,
		"selected_map_archetype": int(_session.get("match_map_archetype")) if _is_room_open() else GameManager.selected_map_archetype,
		"selected_difficulty": _selected_difficulty, "selected_population_limit": _selected_population_limit,
		"compact_layout": _compact_layout,
		"viewport_width": get_viewport().get_visible_rect().size.x, "viewport_height": get_viewport().get_visible_rect().size.y,
		"safe_area": {"x": _active_safe_area.position.x, "y": _active_safe_area.position.y, "width": _active_safe_area.size.x, "height": _active_safe_area.size.y},
		"main_menu_bounds": _control_diag(_root_margin), "kingdom_preview": _control_diag(_hero),
		"start_button": _control_diag(start_button), "new_game_button": _control_diag(_new_game_button),
		"settings_button": _control_diag(settings_button), "guided_opening_toggle": _control_diag(guided_opening_toggle),
		"seed_input": _control_diag(seed_input), "random_seed_button": _control_diag(random_seed_button),
		"difficulty_option": _control_diag(difficulty_option), "difficulty_choices": _button_diagnostics(_difficulty_buttons),
		"map_choices": _button_diagnostics(_map_buttons), "population_choices": _button_diagnostics(_population_buttons),
		"settings_open": is_instance_valid(_shared_settings), "room_open": _is_room_open(),
		"web_update_safe": _web_update_safe,
	}


func _button_diagnostics(buttons: Array[Button]) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for button: Button in buttons:
		results.append(_control_diag(button))
	return results


func _control_diag(control: Control) -> Dictionary:
	var rect: Rect2 = control.get_global_rect()
	return {"name": control.name, "path": str(control.get_path()), "visible": control.is_visible_in_tree(), "disabled": control.disabled if control is BaseButton else false, "x": rect.position.x, "y": rect.position.y, "width": rect.size.x, "height": rect.size.y, "within_viewport": Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).grow(0.5).encloses(rect), "within_safe_area": _active_safe_area.grow(0.5).encloses(rect)}
