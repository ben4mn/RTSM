extends Node
## Sound identity hub. Edited CC0 recordings only (Kenney + the sources listed in
## docs/licensed_audio_2026-11.md). World cues require visible, on-screen sources;
## owned alerts and interface responses use a separate, reserved voice pool.
## Music and ambience live in child directors on their own buses.
##
## Class-aware cues are resolved HERE from existing signals and the legacy cue
## names other scripts already call, so gameplay code needs no audio knowledge.

const SAMPLE_RATE: int = 22050
const WORLD_VOICES: int = 14
const UI_VOICES: int = 6
const RESERVED_ALERT_VOICES: int = 2
const ALERT_SOUNDS: Array[String] = ["under_attack", "unit_trained", "building_complete", "age_up", "victory", "defeat", "research_complete", "town_bell", "sacred_captured", "sacred_lost"]
const COOLDOWNS := {"button_click": 0.08, "select_unit": 0.18, "command_move": 0.20, "command_attack": 0.24, "attack_hit": 0.20, "unit_death": 0.50, "gather_food": 1.3, "gather_wood": 1.0, "gather_gold": 1.2, "construction_work": 1.1, "under_attack": 6.0, "unit_trained": 0.65, "building_complete": 0.8, "age_up": 2.0, "victory": 3.0, "defeat": 3.0, "research_complete": 1.0, "town_bell": 2.5, "sacred_captured": 3.0, "sacred_lost": 3.0}
const GAINS := {"button_click": -13.0, "select_unit": -11.0, "command_move": -10.0, "command_attack": -10.0, "attack_hit": -15.0, "unit_death": -18.0, "gather_food": -23.0, "gather_wood": -22.0, "gather_gold": -23.0, "construction_work": -21.0, "building_place": -10.0, "building_invalid": -13.0, "unit_trained": -9.0, "building_complete": -8.0, "under_attack": -6.0, "age_up": -7.0, "victory": -5.0, "defeat": -7.0}
const GROUPS := {"gather_food": "work", "gather_wood": "work", "gather_gold": "work", "construction_work": "work", "attack_hit": "combat", "unit_death": "combat", "command_move": "orders", "command_attack": "orders"}
const GROUP_COOLDOWNS := {"work": 1.50, "combat": 0.24, "orders": 0.18, "clash": 0.10, "volley": 0.11, "arrows": 0.11, "heavy": 0.16, "masonry": 0.13, "death": 0.18, "ack": 0.16}
const PRIORITIES := {"attack_hit": 1, "unit_death": 1, "button_click": 0, "select_unit": 1, "command_move": 2, "command_attack": 2, "building_place": 2, "building_invalid": 2, "unit_trained": 3, "building_complete": 3, "under_attack": 4, "age_up": 4, "victory": 5, "defeat": 5, "research_complete": 3, "town_bell": 4, "sacred_captured": 4, "sacred_lost": 4}

## Identity cue families: gain dB, per-cue cooldown s, group, priority, max simultaneous
## voices of this cue, random pitch spread (+/- fraction), random level spread (dB down).
## Files are loudness-matched per class by tools/audio/build_sound_identity.py.
const IDENTITY := {
	"melee_hit": [-10.0, 0.07, "clash", 1, 4, 0.07, 3.0],
	"villager_hit": [-12.0, 0.09, "clash", 1, 2, 0.07, 3.0],
	"cavalry_hit": [-9.0, 0.12, "clash", 1, 3, 0.05, 2.5],
	"bow_release": [-13.0, 0.06, "volley", 1, 3, 0.08, 3.0],
	"arrow_impact": [-12.0, 0.06, "arrows", 1, 3, 0.08, 3.0],
	"siege_launch": [-8.0, 0.25, "heavy", 2, 2, 0.05, 1.5],
	"siege_impact": [-6.0, 0.25, "heavy", 2, 2, 0.06, 1.5],
	"building_hit": [-12.0, 0.10, "masonry", 1, 3, 0.07, 3.0],
	"building_collapse": [-4.0, 0.6, "", 3, 2, 0.05, 1.0],
	"death_infantry": [-11.0, 0.14, "death", 2, 2, 0.06, 2.0],
	"death_soft": [-12.0, 0.14, "death", 2, 2, 0.06, 2.0],
	"death_cavalry": [-10.0, 0.5, "death", 2, 2, 0.05, 1.5],
	"death_siege": [-8.0, 0.3, "death", 2, 2, 0.05, 1.5],
	"select_villager": [-10.0, 0.22, "ack", 1, 1, 0.05, 1.5],
	"select_infantry": [-10.0, 0.22, "ack", 1, 1, 0.05, 1.5],
	"select_archer": [-10.0, 0.22, "ack", 1, 1, 0.05, 1.5],
	"select_cavalry": [-10.0, 0.45, "ack", 1, 1, 0.04, 1.5],
	"select_siege": [-10.0, 0.45, "ack", 1, 1, 0.04, 1.5],
	"order_villager": [-9.0, 0.22, "orders", 2, 1, 0.05, 1.5],
	"order_infantry": [-9.0, 0.22, "orders", 2, 1, 0.05, 1.5],
	"order_archer": [-9.0, 0.22, "orders", 2, 1, 0.05, 1.5],
	"order_cavalry": [-9.0, 0.30, "orders", 2, 1, 0.04, 1.5],
	"order_siege": [-9.0, 0.45, "orders", 2, 1, 0.04, 1.5],
	"order_attack_melee": [-9.0, 0.26, "orders", 2, 1, 0.05, 1.5],
	"order_attack_villager": [-9.0, 0.26, "orders", 2, 1, 0.05, 1.5],
	"order_attack_archer": [-9.0, 0.30, "orders", 2, 1, 0.05, 1.5],
	"order_attack_cavalry": [-9.0, 0.6, "orders", 2, 1, 0.04, 1.5],
	"order_attack_siege": [-9.0, 0.6, "orders", 2, 1, 0.04, 1.5],
	"select_town_center": [-12.0, 0.5, "ack", 1, 1, 0.0, 0.0],
	"select_house": [-10.0, 0.3, "ack", 1, 1, 0.05, 1.0],
	"select_barracks": [-11.0, 0.3, "ack", 1, 1, 0.05, 1.0],
	"select_archery_range": [-10.0, 0.3, "ack", 1, 1, 0.05, 1.0],
	"select_stable": [-10.0, 0.6, "ack", 1, 1, 0.04, 1.0],
	"select_farm": [-10.0, 0.3, "ack", 1, 1, 0.05, 1.0],
	"select_resource_camp": [-10.0, 0.3, "ack", 1, 1, 0.05, 1.0],
	"select_siege_workshop": [-10.0, 0.5, "ack", 1, 1, 0.04, 1.0],
	"select_blacksmith": [-11.0, 0.5, "ack", 1, 1, 0.03, 1.0],
	"select_watch_tower": [-10.0, 0.3, "ack", 1, 1, 0.05, 1.0],
	"age_up_fanfare": [-3.0, 2.0, "", 4, 1, 0.0, 0.0],
	"alert_town": [-4.0, 1.0, "", 4, 1, 0.0, 0.0],
	"alert_army": [-4.0, 1.0, "", 4, 1, 0.0, 0.0],
	"trained_villager": [-9.0, 0.5, "", 3, 1, 0.03, 0.0],
	"trained_military": [-8.0, 0.5, "", 3, 1, 0.03, 0.0],
	"building_complete_chime": [-7.0, 0.8, "", 3, 1, 0.02, 0.0],
	"research_complete": [-7.0, 1.0, "", 3, 1, 0.0, 0.0],
	"sacred_captured": [-4.0, 3.0, "", 4, 1, 0.0, 0.0],
	"sacred_lost": [-4.0, 3.0, "", 4, 1, 0.0, 0.0],
	"town_bell": [-4.0, 2.5, "", 4, 1, 0.0, 0.0],
}
## Mirrors UnitData.UnitType / BuildingData.BuildingType by value so this autoload does
## not compile the unit scripts that themselves depend on it (test_sound_identity checks).
const UNIT_CLASS := {0: "villager", 1: "infantry", 2: "archer", 3: "cavalry", 4: "cavalry", 5: "siege", 6: "villager"}
const IMPACT_BY_CLASS := {"villager": "villager_hit", "infantry": "melee_hit", "archer": "arrow_impact", "cavalry": "cavalry_hit", "siege": "siege_impact"}
const DEATH_BY_CLASS := {"villager": "death_soft", "infantry": "death_infantry", "archer": "death_soft", "cavalry": "death_cavalry", "siege": "death_siege"}
const ATTACK_ORDER_BY_CLASS := {"villager": "order_attack_villager", "infantry": "order_attack_melee", "archer": "order_attack_archer", "cavalry": "order_attack_cavalry", "siege": "order_attack_siege"}
const BUILDING_SELECT := {0: "select_town_center", 1: "select_house", 2: "select_barracks", 3: "select_archery_range", 4: "select_stable", 5: "select_farm", 6: "select_resource_camp", 8: "select_siege_workshop", 9: "select_blacksmith", 10: "select_watch_tower", 11: "select_resource_camp"}
const SIEGE_BUILDING_HIT_HP: int = 45

## Battle music hysteresis. Heat rises with combat that involves the player and
## decays continuously; the thresholds and holds stop the score from flapping.
const BATTLE_HEAT_ENTER: float = 9.0
const BATTLE_HEAT_EXIT: float = 1.5
const BATTLE_HEAT_MAX: float = 14.0
const BATTLE_HEAT_DECAY: float = 1.1
const BATTLE_MIN_SECONDS: float = 14.0
const BATTLE_CALM_SECONDS: float = 8.0

var sfx_enabled: bool = true
var ui_enabled: bool = true
var music_enabled: bool = true
var battle_active: bool = false
var _sounds: Dictionary = {}
var _cooldowns: Dictionary = {}
var _group_cooldowns: Dictionary = {}
var _last_variants: Dictionary = {}
var _last_intent_time: float = -100.0
var _web_activated: bool = false
var _streams_unlocked: bool = false
var _world_players: Array[AudioStreamPlayer] = []
var _ui_players: Array[AudioStreamPlayer] = []
var _rng := RandomNumberGenerator.new()
var _backgrounded: bool = false
var _preview_serial: int = 0
var _web_visibility_callback: JavaScriptObject
var _web_dump_callback: JavaScriptObject
var _peak_active_voices: int = 0
var _played: Dictionary = {}
var _resolved: Dictionary = {}
var _suppressed: Dictionary = {}
var _music: Node
var _ambience: Node
var _battle_heat: float = 0.0
var _battle_seconds: float = 0.0
var _battle_calm: float = 0.0
var _specific_hits: Dictionary = {}
var _pending_generic_hits: Array[int] = []
var _swallow_select_frame: int = -1
var _selected_class: String = ""
var _last_spawned: WeakRef
var _last_spawn_msec: int = -100000
var _last_own_damage_kind: String = "town"
var _last_own_damage_msec: int = -100000
var _last_tower_fire_msec: int = -100000
var _sacred_owner: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 73109 # Sound construction must never perturb gameplay random state.
	_web_activated = not OS.has_feature("web")
	_ensure_bus("World", "Master")
	_ensure_bus("UIAlerts", "Master")
	_ensure_bus("Music", "Master")
	_ensure_bus("Ambience", "Master")
	_ensure_mix_effects()
	_create_players(_world_players, WORLD_VOICES, "World")
	_create_players(_ui_players, UI_VOICES, "UIAlerts")
	_generate_all_sounds()
	_music = preload("res://scripts/audio/music_director.gd").new()
	_music.name = "MusicDirector"
	add_child(_music)
	_ambience = preload("res://scripts/audio/ambience_director.gd").new()
	_ambience.name = "AmbienceDirector"
	add_child(_ambience)
	apply_preferences()
	GameManager.game_state_changed.connect(_on_game_state_changed)
	GameManager.age_advanced.connect(func(owner: int, _age: int) -> void:
		if owner == 0: play_ui("age_up")
	)
	GameManager.research_completed.connect(func(owner: int, _research: String) -> void:
		if owner == 0: play_ui("research_complete")
	)
	GameManager.game_over.connect(_on_game_over)
	get_tree().node_added.connect(_on_node_added)
	_install_web_lifecycle()
	_streams_unlocked = _web_activated and _stream_runtime()
	_refresh_directors()


func _input(event: InputEvent) -> void:
	# Discard pre-gesture cues rather than accumulating a burst behind autoplay.
	# The browser/Godot driver remains responsible for unlocking its AudioContext.
	if (event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey) and event.is_pressed():
		_web_activated = true
		if not _streams_unlocked and _stream_runtime():
			_streams_unlocked = true
			_refresh_directors() # Music may begin only now, inside the first gesture.


## Headless runs have no listener and exit abruptly, so the streaming decks stay
## cold there unless a regression opts in through this metadata.
func _stream_runtime() -> bool:
	return DisplayServer.get_name() != "headless" or bool(get_meta("headless_streams", false))


func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING or get_tree().paused:
		return
	_battle_heat = maxf(0.0, _battle_heat - BATTLE_HEAT_DECAY * delta)
	if battle_active:
		_battle_seconds += delta
		_battle_calm = _battle_calm + delta if _battle_heat <= BATTLE_HEAT_EXIT else 0.0
		if _battle_seconds >= BATTLE_MIN_SECONDS and _battle_calm >= BATTLE_CALM_SECONDS:
			_set_battle(false)
	elif _battle_heat >= BATTLE_HEAT_ENTER:
		_set_battle(true)


func _set_battle(active: bool) -> void:
	if battle_active == active:
		return
	battle_active = active
	_battle_seconds = 0.0
	_battle_calm = 0.0
	_refresh_directors()


func _add_battle_heat(amount: float) -> void:
	_battle_heat = minf(BATTLE_HEAT_MAX, _battle_heat + amount)


func _ensure_bus(bus_name: String, parent_bus: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, parent_bus)


func _ensure_mix_effects() -> void:
	# default_bus_layout.tres normally supplies these; this is the fallback for
	# contexts that boot without the project layout.
	var master: int = AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -1.0
		limiter.release = 0.12
		AudioServer.add_bus_effect(master, limiter)
	var world: int = AudioServer.get_bus_index("World")
	if world >= 0 and AudioServer.get_bus_effect_count(world) == 0:
		var compressor := AudioEffectCompressor.new()
		compressor.threshold = -16.0
		compressor.ratio = 3.0
		compressor.attack_us = 4000.0
		compressor.release_ms = 160.0
		AudioServer.add_bus_effect(world, compressor)


func _create_players(pool: Array[AudioStreamPlayer], count: int, bus_name: String) -> void:
	for i: int in count:
		var player := AudioStreamPlayer.new()
		player.name = "%sVoice%d" % [bus_name, i]
		player.bus = bus_name
		# Use Godot's bounded stream mixer. The Web sample backend can retain
		# stale bus indices after runtime bus changes, silently creating a cycle.
		player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		add_child(player)
		pool.append(player)


# --- Scene hooks: everything class-aware is learned from existing signals ---

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_connect_button.call_deferred(node.get_instance_id())
	elif node is Node2D:
		if node.has_signal("attack_landed"):
			_hook_unit(node)
		elif node.has_signal("building_destroyed"):
			_hook_building(node)
		elif node.has_signal("victory_timer_tick"):
			_hook_sacred_site(node)
		elif node.get("flight_seconds") != null and node.get("attacker_ref") != null:
			_on_projectile_launched(node)


func _connect_button(instance_id: int) -> void:
	var node: Node = instance_from_id(instance_id) as Node
	if is_instance_valid(node) and node is BaseButton:
		(node as BaseButton).pressed.connect(func() -> void: play_ui("button_click"))


func _hook_unit(unit: Node) -> void:
	if unit.is_connected("attack_landed", _on_attack_landed):
		return
	unit.connect("attack_landed", _on_attack_landed)
	unit.connect("unit_selected", _on_unit_selected)
	unit.connect("damage_received", _on_unit_damaged)
	_last_spawned = weakref(unit)
	_last_spawn_msec = Time.get_ticks_msec()


func _hook_building(building: Node) -> void:
	if building.is_connected("building_destroyed", _on_building_destroyed):
		return
	building.connect("building_destroyed", _on_building_destroyed)
	building.connect("building_selected", _on_building_selected)
	building.connect("damage_received", _on_building_damaged)
	if building.has_signal("defensive_attack_fired"):
		building.connect("defensive_attack_fired", _on_defensive_fire.bind(building))
	_ambience.call("track_building", building)


func _hook_sacred_site(site: Node) -> void:
	_sacred_owner = -1
	if not site.is_connected("captured", _on_sacred_captured):
		site.connect("captured", _on_sacred_captured)
		if site.has_signal("neutralized"):
			site.connect("neutralized", _on_sacred_neutralized)


func _unit_class(unit: Object) -> String:
	return str(UNIT_CLASS.get(int(unit.get("unit_type")), "infantry"))


func _involves_player(first: Object, second: Object = null) -> bool:
	return (first != null and int(first.get("player_owner")) == 0) or (second != null and int(second.get("player_owner")) == 0)


func _on_attack_landed(attacker: Node2D, defender: Node2D, _hp_loss: float, _counter_bonus: float) -> void:
	if not is_instance_valid(defender) or not is_instance_valid(attacker):
		return
	_specific_hits[defender.get_instance_id()] = Engine.get_process_frames()
	var cue: String = str(IMPACT_BY_CLASS[_unit_class(attacker)])
	if bool(attacker.get("is_ranged")) and cue != "siege_impact":
		cue = "arrow_impact"
	var audible: bool = _play_world_cue(cue, defender)
	if _involves_player(attacker, defender):
		_add_battle_heat(1.0 if audible else 0.2)


func _on_projectile_launched(projectile: Node) -> void:
	var reference: WeakRef = projectile.get("attacker_ref") as WeakRef
	var attacker: Node2D = reference.get_ref() as Node2D if reference != null else null
	if attacker != null and is_instance_valid(attacker):
		_play_world_cue("siege_launch" if _unit_class(attacker) == "siege" else "bow_release", attacker)


func _on_defensive_fire(_target: Node2D, building: Node2D) -> void:
	_last_tower_fire_msec = Time.get_ticks_msec()
	if is_instance_valid(building):
		_play_world_cue("bow_release", building)


func _on_unit_damaged(unit: Node2D, _hp_loss: float) -> void:
	if is_instance_valid(unit) and int(unit.get("player_owner")) == 0:
		_last_own_damage_kind = "town" if _unit_class(unit) == "villager" else "army"
		_last_own_damage_msec = Time.get_ticks_msec()


func _on_building_damaged(building: Node2D, hp_loss: int) -> void:
	if not is_instance_valid(building):
		return
	_specific_hits[building.get_instance_id()] = Engine.get_process_frames()
	var audible: bool = _play_world_cue("siege_impact" if hp_loss >= SIEGE_BUILDING_HIT_HP else "building_hit", building)
	if int(building.get("player_owner")) == 0:
		_last_own_damage_kind = "town"
		_last_own_damage_msec = Time.get_ticks_msec()
		_add_battle_heat(1.5) # The player's town burning matters wherever the camera is.
	elif audible:
		_add_battle_heat(1.0)


func _on_building_destroyed(building: Node2D) -> void:
	if is_instance_valid(building):
		_play_world_cue("building_collapse", building, 260.0)


func _on_unit_selected(unit: Node2D) -> void:
	if not is_instance_valid(unit) or int(unit.get("player_owner")) != 0:
		return
	_selected_class = _unit_class(unit)
	_swallow_select_frame = Engine.get_process_frames()
	_play_identity_ui("select_" + _selected_class)


func _on_building_selected(building: Node2D) -> void:
	if not is_instance_valid(building) or int(building.get("player_owner")) != 0:
		return
	var cue: String = str(BUILDING_SELECT.get(int(building.get("building_type")), ""))
	if cue.is_empty():
		return
	_swallow_select_frame = Engine.get_process_frames()
	_play_identity_ui(cue)


func _on_sacred_captured(player_id: int) -> void:
	if player_id == _sacred_owner:
		return
	_sacred_owner = player_id
	play_ui("sacred_captured" if player_id == 0 else "sacred_lost")


func _on_sacred_neutralized() -> void:
	if _sacred_owner == 0:
		play_ui("sacred_lost")
	_sacred_owner = -1


func _on_game_over(winner: int) -> void:
	play_ui("victory" if winner == 0 else "defeat")
	_set_battle(false)
	_music.call("set_mode", "victory" if winner == 0 else "defeat")


# --- Public cue API (unchanged names; richer resolution) ---

func play_sfx(sound_name: String) -> void:
	# Global positive feedback belongs to the player's alert channel. Repeated
	# world sounds use play_world with a source, never this notification API.
	if sound_name in ALERT_SOUNDS or sound_name in ["select_unit", "command_move", "command_attack", "building_invalid", "building_place"]:
		play_ui(sound_name)
		return
	if sfx_enabled and not _backgrounded and GameManager.current_state == GameManager.GameState.PLAYING:
		_play(sound_name, _world_players)


func play_world(sound_name: String, source: Node2D) -> void:
	if not sfx_enabled or _backgrounded or GameManager.current_state != GameManager.GameState.PLAYING:
		return
	if not is_instance_valid(source) or not source.is_inside_tree():
		return
	if sound_name == "attack_hit" and (source.has_signal("attack_landed") or source.has_signal("building_destroyed")):
		# The attacker's weapon decides the impact; a signal later this frame
		# normally names it. Only an anonymous hit falls back to a neutral thud.
		_pending_generic_hits.append(source.get_instance_id())
		if _pending_generic_hits.size() == 1:
			_flush_generic_hits.call_deferred()
		return
	if sound_name == "unit_death" and source.has_signal("attack_landed"):
		_play_world_cue(str(DEATH_BY_CLASS[_unit_class(source)]), source)
		return
	var attenuation: float = _world_attenuation(source, 80.0)
	if not is_nan(attenuation):
		_play(sound_name, _world_players, attenuation)


func _flush_generic_hits() -> void:
	var frame: int = Engine.get_process_frames()
	for instance_id: int in _pending_generic_hits:
		if int(_specific_hits.get(instance_id, -9)) >= frame - 1:
			continue
		var victim: Node2D = instance_from_id(instance_id) as Node2D
		if victim == null or not is_instance_valid(victim):
			continue
		if victim.has_signal("building_destroyed"):
			_play_world_cue("building_hit", victim)
		else:
			var tower: bool = Time.get_ticks_msec() - _last_tower_fire_msec < 700
			_play_world_cue("arrow_impact" if tower else "villager_hit", victim)
	_pending_generic_hits.clear()
	if _specific_hits.size() > 256:
		_specific_hits.clear()


## Plays an identity cue at a visible, on-screen source. Returns whether it was audible.
func _play_world_cue(cue: String, source: Node2D, margin: float = 80.0) -> bool:
	if not sfx_enabled or _backgrounded or GameManager.current_state != GameManager.GameState.PLAYING:
		return false
	if not is_instance_valid(source) or not source.is_inside_tree():
		return false
	var attenuation: float = _world_attenuation(source, margin)
	if is_nan(attenuation):
		return false
	_play(cue, _world_players, attenuation, cue)
	return true


## dB offset for a world source, or NAN when it is fogged or off screen.
func _world_attenuation(source: Node2D, margin: float) -> float:
	if not is_source_visible(source):
		_suppress("fog")
		return NAN
	var viewport: Viewport = source.get_viewport()
	var canvas: Transform2D = viewport.get_canvas_transform()
	var screen: Vector2 = canvas * source.global_position
	var view_rect: Rect2 = viewport.get_visible_rect()
	if not view_rect.grow(margin).has_point(screen):
		_suppress("distance")
		return NAN
	var distance: float = screen.distance_to(view_rect.get_center()) / maxf(1.0, view_rect.size.length() * 0.5)
	# Zoomed out, the battlefield is further from the listener: about 4 dB per halving.
	var zoom: float = maxf(0.05, canvas.get_scale().x)
	var zoom_loss: float = clampf(-log(zoom) / log(2.0) * 4.0, -1.5, 8.0)
	return -clampf(distance, 0.0, 1.6) * 7.0 - zoom_loss


func is_source_visible(source: Node2D) -> bool:
	if not is_instance_valid(source) or not source.is_inside_tree(): return false
	var map: Node = source.get_parent()
	while map != null and not map.has_method("is_entity_visible_to_player"):
		map = map.get_parent()
	return map != null and bool(map.call("is_entity_visible_to_player", source, 0))


func play_ui(sound_name: String) -> void:
	if not ui_enabled or _backgrounded:
		return
	var resolved: String = ""
	match sound_name:
		"select_unit":
			if _swallow_select_frame == Engine.get_process_frames():
				return # The unit or building already answered in its own voice.
		"command_move":
			if not _selected_class.is_empty(): resolved = "order_" + _selected_class
		"command_attack":
			if not _selected_class.is_empty(): resolved = str(ATTACK_ORDER_BY_CLASS[_selected_class])
		"unit_trained":
			resolved = _trained_cue()
		"under_attack":
			var recent: bool = Time.get_ticks_msec() - _last_own_damage_msec < 1500
			resolved = "alert_army" if recent and _last_own_damage_kind == "army" else "alert_town"
			_add_battle_heat(4.0)
		"building_complete":
			resolved = "building_complete_chime"
		"age_up":
			resolved = "age_up_fanfare"
		"research_complete", "town_bell", "sacred_captured", "sacred_lost":
			resolved = sound_name
	_play(sound_name, _ui_players, 0.0, resolved)


## Cues owned by features that land later (timed research, garrison bell).
func play_research_complete() -> void:
	play_ui("research_complete")


func play_town_bell() -> void:
	play_ui("town_bell")


func _play_identity_ui(cue: String) -> void:
	if ui_enabled and not _backgrounded:
		_play(cue, _ui_players, 0.0, cue)


func _trained_cue() -> String:
	var unit: Object = _last_spawned.get_ref() if _last_spawned != null else null
	if unit != null and is_instance_valid(unit) and Time.get_ticks_msec() - _last_spawn_msec < 400:
		return "trained_villager" if _unit_class(unit) == "villager" else "trained_military"
	return "trained_villager"


func set_sfx_enabled(enabled: bool) -> void:
	sfx_enabled = enabled
	if not enabled: _stop_pool(_world_players)


func set_ui_enabled(enabled: bool) -> void:
	ui_enabled = enabled
	if not enabled: _stop_pool(_ui_players)


func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	_refresh_directors()


func set_all_enabled(enabled: bool) -> void:
	sfx_enabled = enabled
	ui_enabled = enabled
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), not enabled)
	if not enabled: stop_all()


func apply_preferences() -> void:
	set_all_enabled(GameManager.audio_enabled)
	set_sfx_enabled(GameManager.audio_enabled and not GameManager.sfx_muted)
	set_ui_enabled(GameManager.audio_enabled and not GameManager.ui_alert_muted)
	music_enabled = GameManager.audio_enabled and not GameManager.music_muted and GameManager.music_volume > 0.0
	_set_volume("Master", GameManager.master_volume)
	_set_volume("World", GameManager.sfx_volume)
	_set_volume("UIAlerts", GameManager.ui_alert_volume)
	_set_volume("Music", GameManager.music_volume)
	_set_volume("Ambience", GameManager.sfx_volume)
	if _music != null:
		_refresh_directors()


func _set_volume(bus_name: String, volume: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index >= 0:
		AudioServer.set_bus_mute(index, volume <= 0.0 or (bus_name == "Master" and not GameManager.audio_enabled) or (bus_name == "Music" and GameManager.music_muted))
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.00001, clampf(volume, 0.0, 1.0))))


## Single place that tells the directors what the session currently allows and wants.
func _refresh_directors() -> void:
	if _music == null or _ambience == null:
		return
	var state: int = GameManager.current_state
	_music.call("set_allowed", _streams_unlocked and music_enabled)
	_music.call("set_held", _backgrounded)
	_ambience.call("set_allowed", _streams_unlocked and sfx_enabled)
	_ambience.call("set_held", _backgrounded)
	_ambience.call("set_in_match", state == GameManager.GameState.PLAYING or state == GameManager.GameState.PAUSED)
	_ambience.call("set_battle", battle_active)
	match state:
		GameManager.GameState.MENU, GameManager.GameState.LOADING:
			_music.call("set_mode", "menu")
		GameManager.GameState.PLAYING:
			_music.call("set_mode", "battle" if battle_active else "peace")
		_:
			pass # Paused keeps its score; game over is driven by the result stinger.


func _play(sound_name: String, pool: Array[AudioStreamPlayer], attenuation: float = 0.0, resolved: String = "") -> void:
	var key: String = resolved if _sounds.has(resolved) else sound_name
	if not _sounds.has(key): return
	if not _web_activated:
		_suppress("activation")
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var config: Array = IDENTITY.get(key, [])
	# A successful order/selection already supplies tactile feedback. The button
	# hookup must not layer a second click over that same gesture.
	if sound_name == "button_click" and now - _last_intent_time < 0.07:
		_suppress("gesture")
		return
	var cooldown: float = float(COOLDOWNS.get(sound_name, config[1] if not config.is_empty() else 0.15))
	if now - float(_cooldowns.get(sound_name, -100.0)) < cooldown:
		_suppress("cooldown")
		return
	var group: String = str(GROUPS.get(sound_name, config[2] if not config.is_empty() else ""))
	if not group.is_empty() and now - float(_group_cooldowns.get(group, -100.0)) < float(GROUP_COOLDOWNS[group]):
		_suppress("group_cooldown")
		return
	var priority: int = int(PRIORITIES.get(sound_name, config[3] if not config.is_empty() else 0))
	# The last interface voices are reserved for alerts. Click storms cannot
	# steal an attack horn, an age confirmation or the result of the match.
	var alert: bool = sound_name in ALERT_SOUNDS or priority >= 3
	var first_reserved: int = UI_VOICES - RESERVED_ALERT_VOICES
	var voice: AudioStreamPlayer
	var same_cue: int = 0
	var busy: int = 0
	for i: int in pool.size():
		if pool[i].playing:
			busy += 1
			if str(pool[i].get_meta("cue", "")) == key: same_cue += 1
		elif voice == null and not (pool == _ui_players and not alert and i >= first_reserved):
			voice = pool[i]
	if not config.is_empty() and same_cue >= int(config[4]):
		_suppress("family_limit")
		return
	if voice == null:
		# Only a more important cue may displace another. Recruitment cannot cut
		# off an attack warning, and nothing may cut off a victory/defeat cadence.
		var lowest: int = priority
		for i: int in pool.size():
			if pool == _ui_players and not alert and i >= first_reserved: continue
			var candidate: int = int(pool[i].get_meta("priority", 0))
			if candidate < lowest:
				voice = pool[i]
				lowest = candidate
		if voice == null:
			_suppress("voice_limit")
			return
	_cooldowns[sound_name] = now
	if not group.is_empty(): _group_cooldowns[group] = now
	if pool == _ui_players and sound_name != "button_click": _last_intent_time = now
	voice.stop()
	var bank: Array = _sounds[key]
	var variant: int = _rng.randi_range(0, bank.size() - 1)
	if bank.size() > 1 and variant == int(_last_variants.get(key, -1)):
		variant = (variant + 1) % bank.size()
	_last_variants[key] = variant
	if key != sound_name: _last_variants[sound_name] = variant
	voice.stream = bank[variant]
	voice.set_meta("priority", priority)
	voice.set_meta("cue", key)
	if config.is_empty():
		voice.volume_db = float(GAINS.get(sound_name, -8.0)) + attenuation
		voice.pitch_scale = 1.0
	else:
		# A crowded field turns each new voice down a little so forty fighters
		# read as one dense battle rather than a wall of equal-loud hits.
		var crowd: float = minf(5.0, busy * 0.45) if pool == _world_players else 0.0
		voice.volume_db = float(config[0]) + attenuation - crowd - _rng.randf() * float(config[6])
		voice.pitch_scale = 1.0 + _rng.randf_range(-float(config[5]), float(config[5]))
	voice.play()
	_played[sound_name] = int(_played.get(sound_name, 0)) + 1
	if not config.is_empty(): _resolved[key] = int(_resolved.get(key, 0)) + 1
	_peak_active_voices = maxi(_peak_active_voices, _active_voices())


func _active_voices() -> int:
	var count: int = 0
	for player: AudioStreamPlayer in _world_players + _ui_players:
		if player.playing: count += 1
	return count


func _suppress(reason: String) -> void:
	_suppressed[reason] = int(_suppressed.get(reason, 0)) + 1


func get_audio_diagnostics() -> Dictionary:
	return {"active_voices": _active_voices(), "voice_limit": WORLD_VOICES + UI_VOICES, "peak_active_voices": _peak_active_voices, "backgrounded": _backgrounded, "activated": _web_activated, "streams_unlocked": _streams_unlocked, "variants": _last_variants.duplicate(), "played": _played.duplicate(), "resolved": _resolved.duplicate(), "suppressed": _suppressed.duplicate(), "master_volume": GameManager.master_volume, "sfx_volume": GameManager.sfx_volume, "ui_alert_volume": GameManager.ui_alert_volume, "music_volume": GameManager.music_volume, "music_muted": GameManager.music_muted, "enabled": sfx_enabled, "battle": {"active": battle_active, "heat": snappedf(_battle_heat, 0.01), "seconds": snappedf(_battle_seconds, 0.1), "calm": snappedf(_battle_calm, 0.1)}, "music": _music.call("get_state") if _music != null else {}, "ambience": _ambience.call("get_state") if _ambience != null else {}}


func _stop_pool(pool: Array[AudioStreamPlayer]) -> void:
	for player: AudioStreamPlayer in pool:
		player.stop()


func stop_all() -> void:
	_preview_serial += 1
	_stop_pool(_world_players)
	_stop_pool(_ui_players)
	_cooldowns.clear()
	_group_cooldowns.clear()
	_last_intent_time = -100.0


func _on_game_state_changed(state: int) -> void:
	stop_all() # No battle tails, preview timers or loops survive scene/pause boundaries.
	if state == GameManager.GameState.MENU or state == GameManager.GameState.LOADING:
		_battle_heat = 0.0
		_selected_class = ""
		_set_battle(false)
	_refresh_directors()


func _notification(what: int) -> void:
	# Only the explicit native recording fixture sets this metadata. Release
	# builds cannot bypass lifecycle handling through this diagnostic hook.
	if OS.is_debug_build() and bool(get_meta("controlled_audio_capture", false)): return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_set_backgrounded(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_set_backgrounded(false)


func _set_backgrounded(value: bool) -> void:
	_backgrounded = value
	if value: stop_all()
	# Music and ambience hold their position while hidden and resume in place;
	# one-shot cues are discarded, never queued.
	_refresh_directors()


func _install_web_lifecycle() -> void:
	if not OS.has_feature("web"): return
	# Godot's Web Audio driver owns user-gesture unlocking. This only discards
	# obsolete sounds when the tab/PWA is hidden; nothing is queued for resume.
	# dump() is a read-only inspection hook: it publishes the diagnostics as JSON.
	JavaScriptBridge.eval("window.PocketAudioLifecycle = {last: null, attach(cb, dump) { this.cb = cb; this.dumpCb = dump; this.listener = () => cb(document.hidden); document.addEventListener('visibilitychange', this.listener); cb(document.hidden); }, dump() { if (this.dumpCb) this.dumpCb(); return this.last; }, detach() { document.removeEventListener('visibilitychange', this.listener); this.cb = null; this.dumpCb = null; }};", true)
	_web_visibility_callback = JavaScriptBridge.create_callback(_on_web_visibility)
	_web_dump_callback = JavaScriptBridge.create_callback(_on_web_dump)
	var bridge: JavaScriptObject = JavaScriptBridge.get_interface("PocketAudioLifecycle")
	bridge.attach(_web_visibility_callback, _web_dump_callback)


func _on_web_visibility(arguments: Array) -> void:
	if not arguments.is_empty(): _set_backgrounded(bool(arguments[0]))


func _on_web_dump(_arguments: Array) -> void:
	var bridge: JavaScriptObject = JavaScriptBridge.get_interface("PocketAudioLifecycle")
	if bridge != null:
		bridge.last = JSON.stringify(get_audio_diagnostics())


func _exit_tree() -> void:
	for player: AudioStreamPlayer in _world_players + _ui_players:
		player.stop()
		player.stream = null
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.PocketAudioLifecycle && window.PocketAudioLifecycle.detach();", true)


func preview() -> void:
	_preview_serial += 1
	var serial: int = _preview_serial
	play_ui("button_click")
	await get_tree().create_timer(0.25, true, false, true).timeout
	if serial != _preview_serial or _backgrounded: return
	if sfx_enabled: _play("melee_hit", _world_players, 0.0, "melee_hit")
	await get_tree().create_timer(0.4, true, false, true).timeout
	if serial != _preview_serial or _backgrounded: return
	_play("under_attack", _ui_players, 0.0, "alert_town")


func _generate_all_sounds() -> void:
	_sounds = preload("res://scripts/audio/sample_palette.gd").build()
	_sounds.merge(preload("res://scripts/audio/identity_palette.gd").build())
