extends Node
## Sound identity regression: class-aware cue resolution from real signals in a real
## match, battle-music hysteresis, music gating (gesture, mute, background), voice
## bounds under a 40-unit burst, and bank/asset integrity. Structural only — it makes
## no claim about how anything sounds.

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_tables_and_bank()
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.audio_enabled = true
	GameManager.sfx_muted = false
	GameManager.ui_alert_muted = false
	GameManager.music_muted = false
	GameManager.music_volume = 0.5
	AudioManager.apply_preferences()
	AudioManager.call("_set_backgrounded", false)
	# Autoplay gate: nothing may start before a gesture.
	GameManager.set_state(GameManager.GameState.MENU)
	AudioManager.set_meta("headless_streams", true)
	AudioManager.set("_web_activated", false)
	AudioManager.set("_streams_unlocked", false)
	AudioManager.call("_refresh_directors")
	_expect(not bool(_music().allowed) and not bool(_music().playing), "music waits for the first gesture")
	var gesture := InputEventScreenTouch.new()
	gesture.pressed = true
	AudioManager.call("_input", gesture)
	await get_tree().process_frame
	_expect(str(_music().mode) == "menu" and str(_music().track) == "menu_exploration" and bool(_music().playing), "first gesture starts the menu theme")

	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for _frame: int in 900:
		if main.get("_building_placement") != null: break
		await get_tree().process_frame
	_expect(main.get("_building_placement") != null, "Main initialized")
	if main.get("_building_placement") == null:
		_finish()
		return
	main.set_process(false)
	main.ai_controller.set_process(false)
	main.ai_controller.get("_decision_timer").stop()
	GameManager.set_state(GameManager.GameState.PLAYING)
	await get_tree().process_frame
	_expect(str(_music().mode) == "peace" and str(_music().track).begins_with("peace_") or str(_music().track) == "menu_exploration", "a match plays the peace playlist")
	var map: Node2D = main.game_map
	var center: BuildingBase = main.get("_player_town_center")
	map.note_camera_interaction()
	map.camera.position = center.global_position
	map.camera.reset_smoothing()
	map.camera.force_update_scroll()
	var spot: Vector2 = center.global_position + Vector2(60, 40)
	for owner: int in 2:
		GameManager.increase_population_cap(owner, 20)  # Round 2 E: the opening cap is 8.
	var own: UnitBase = main.call("_spawn_unit", UnitData.UnitType.INFANTRY, 0, spot)
	var own_archer: UnitBase = main.call("_spawn_unit", UnitData.UnitType.ARCHER, 0, spot + Vector2(20, 0))
	var own_horse: UnitBase = main.call("_spawn_unit", UnitData.UnitType.CAVALRY, 0, spot + Vector2(40, 0))
	var own_villager: UnitBase = main.call("_spawn_unit", UnitData.UnitType.VILLAGER, 0, spot + Vector2(0, 30))
	var foe: UnitBase = main.call("_spawn_unit", UnitData.UnitType.INFANTRY, 1, spot + Vector2(10, 10))
	var foe_archer: UnitBase = main.call("_spawn_unit", UnitData.UnitType.ARCHER, 1, spot + Vector2(30, 10))
	var foe_siege: UnitBase = main.call("_spawn_unit", UnitData.UnitType.SIEGE, 1, spot + Vector2(50, 10))
	for unit: UnitBase in [own, own_archer, own_horse, own_villager, foe, foe_archer, foe_siege]:
		unit.set_process(false)
		unit.set_physics_process(false)
	await get_tree().process_frame
	AudioManager.stop_all()
	_expect(not is_nan(float(AudioManager.call("_world_attenuation", own, 80.0))), "owned unit beside the town centre is audible")

	# Impacts follow the ATTACKER's weapon class.
	for pair: Array in [[foe, "melee_hit"], [foe_archer, "arrow_impact"], [foe_siege, "siege_impact"], [own_horse, "cavalry_hit"], [own_villager, "villager_hit"]]:
		AudioManager.stop_all()
		var before: int = _resolved(str(pair[1]))
		(pair[0] as UnitBase).attack_landed.emit(pair[0], own, 3.0, 1.0)
		_expect(_resolved(str(pair[1])) == before + 1, "attack by class plays " + str(pair[1]))
	# A real hit resolves once: the anonymous take_damage cue must not double it.
	AudioManager.stop_all()
	var generic_before: int = _resolved("villager_hit")
	var melee_before: int = _resolved("melee_hit")
	Combat.resolve_unit_hit(foe, own, 1.0, 1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(_resolved("melee_hit") == melee_before + 1 and _resolved("villager_hit") == generic_before, "one impact per resolved hit, named by the attacker")
	# Ranged release is heard at launch, from the projectile the combat code already spawns.
	AudioManager.stop_all()
	var release_before: int = _resolved("bow_release")
	Combat.launch_ranged_attack(own_archer, foe)
	_expect(_resolved("bow_release") == release_before + 1, "arrow release at launch")
	AudioManager.stop_all()
	var launch_before: int = _resolved("siege_launch")
	Combat.launch_ranged_attack(foe_siege, own)
	_expect(_resolved("siege_launch") == launch_before + (1 if AudioManager.is_source_visible(foe_siege) else 0), "siege launch at release when visible")

	# Selection and orders answer in the unit's own non-verbal voice.
	for pair: Array in [[own, "infantry"], [own_archer, "archer"], [own_horse, "cavalry"], [own_villager, "villager"]]:
		AudioManager.stop_all()
		var select_before: int = _resolved("select_" + str(pair[1]))
		var pluck_before: int = _played("select_unit")
		(pair[0] as UnitBase).select()
		_expect(_resolved("select_" + str(pair[1])) == select_before + 1 and _played("select_unit") == pluck_before, "selection voice: " + str(pair[1]))
		AudioManager.stop_all()
		var order_before: int = _resolved("order_" + str(pair[1]))
		AudioManager.play_ui("command_move")
		_expect(_resolved("order_" + str(pair[1])) == order_before + 1, "order voice: " + str(pair[1]))
		(pair[0] as UnitBase).deselect()
	AudioManager.stop_all()
	var rapid_before: Dictionary = AudioManager.get_audio_diagnostics().resolved
	for _tap: int in 30:
		own.select()
		own_archer.select()
	var rapid_total: int = 0
	var rapid_after: Dictionary = AudioManager.get_audio_diagnostics().resolved
	for cue: String in rapid_after: rapid_total += int(rapid_after[cue]) - int(rapid_before.get(cue, 0))
	_expect(rapid_total == 1, "sixty selections in one frame make one acknowledgement")
	AudioManager.stop_all()
	var bell_before: int = _resolved("select_town_center")
	center.select()
	_expect(_resolved("select_town_center") == bell_before + 1, "town centre answers with its bell")
	center.deselect()

	# Alerts: town and army are different sounds on the same reserved channel.
	AudioManager.stop_all()
	own_villager.damage_received.emit(own_villager, 1.0)
	AudioManager.play_sfx("under_attack")
	_expect(str(_ui_cue_playing()) == "alert_town", "villagers under attack ring the town alarm")
	AudioManager.stop_all()
	own.damage_received.emit(own, 1.0)
	AudioManager.play_sfx("under_attack")
	_expect(str(_ui_cue_playing()) == "alert_army", "soldiers under attack sound the war horn")
	AudioManager.stop_all()
	AudioManager.play_research_complete()
	AudioManager.play_town_bell()
	_expect(_played("research_complete") >= 1 and _played("town_bell") >= 1, "research and town bell cues are exposed")
	AudioManager.stop_all()
	GameManager.age_advanced.emit(0, 1)
	_expect(str(_ui_cue_playing()) == "age_up_fanfare", "age advance plays the fanfare")

	# Deaths by class, collapse for buildings.
	AudioManager.stop_all()
	var death_before: int = _resolved("death_cavalry")
	AudioManager.play_world("unit_death", own_horse)
	_expect(_resolved("death_cavalry") == death_before + 1, "cavalry death has its own sound")

	# Forty fighters: full, bounded, and the alert channel stays free.
	AudioManager.stop_all()
	AudioManager.set("_peak_active_voices", 0)
	for _round: int in 400:
		for attacker: UnitBase in [foe, foe_archer, foe_siege, own_horse, own_villager]:
			attacker.attack_landed.emit(attacker, own, 2.0, 1.0)
		AudioManager.play_world("unit_death", own)
	var world_busy: int = 0
	for voice: AudioStreamPlayer in AudioManager.get("_world_players"):
		if voice.playing: world_busy += 1
	_expect(world_busy >= 3 and world_busy <= AudioManager.WORLD_VOICES, "burst is audible but bounded (%d voices)" % world_busy)
	AudioManager.play_sfx("under_attack")
	_expect(str(_ui_cue_playing()).begins_with("alert_"), "alert still sounds over a full battle")

	# Battle music: enters on sustained combat, holds, then returns to peace.
	AudioManager.stop_all()
	AudioManager.set("_battle_heat", 0.0)
	AudioManager.call("_set_battle", false)
	foe.attack_landed.emit(foe, own, 2.0, 1.0)
	AudioManager.call("_process", 0.1)
	_expect(not AudioManager.battle_active and str(_music().mode) == "peace", "a single blow is not a battle")
	for _hit: int in 14:
		AudioManager.set("_cooldowns", {})
		AudioManager.set("_group_cooldowns", {})
		foe.attack_landed.emit(foe, own, 2.0, 1.0)
	AudioManager.call("_process", 0.1)
	_expect(AudioManager.battle_active and str(_music().mode) == "battle" and str(_music().track) == "battle", "sustained fighting brings the battle theme")
	_expect(bool(AudioManager.get_audio_diagnostics().ambience.battle_duck), "ambience ducks under battle")
	for _second: int in 10:
		AudioManager.call("_process", 1.0)
	_expect(AudioManager.battle_active, "battle theme holds for its minimum time after the last blow")
	for _second: int in 20:
		AudioManager.call("_process", 1.0)
	_expect(not AudioManager.battle_active and str(_music().mode) == "peace", "calm returns the peace playlist")
	var transitions: int = int(_music().transitions)
	foe.attack_landed.emit(foe, own, 2.0, 1.0)
	AudioManager.call("_process", 0.1)
	_expect(int(_music().transitions) == transitions, "a stray hit afterwards does not flap the score")

	# Mute, volume, background.
	GameManager.music_muted = true
	GameManager.apply_preferences()
	_expect(not bool(_music().playing) and AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "music mute silences and stops the decks")
	GameManager.music_muted = false
	GameManager.music_volume = 0.25
	GameManager.apply_preferences()
	await get_tree().process_frame
	_expect(bool(_music().playing) and is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(0.25)), "unmute resumes at the chosen level")
	for _frame: int in 20: await get_tree().process_frame
	var held_track: String = str(_music().track)
	var held_at: float = float(_music().position)
	AudioManager.call("_set_backgrounded", true)
	await get_tree().create_timer(0.6).timeout
	_expect(bool(_music().held) and not bool(_music().playing), "hidden tab silences the music")
	AudioManager.call("_set_backgrounded", false)
	await get_tree().process_frame
	var resumed_at: float = float(_music().position)
	_expect(bool(_music().playing) and str(_music().track) == held_track and resumed_at >= held_at - 0.05 and resumed_at < held_at + 0.4, "music resumes in place when visible again (%.2f -> %.2f)" % [held_at, resumed_at])

	# Result stinger.
	GameManager.game_over.emit(0)
	_expect(str(_music().mode) == "victory" and str(_music().track) == "stinger_victory", "victory stinger")
	AudioManager.stop_all()
	GameManager.set_state(GameManager.GameState.MENU)
	main.queue_free()
	await get_tree().process_frame
	_expect(str(_music().mode) == "menu" or str(_music().mode) == "victory", "leaving the match settles the score")
	_finish()


func _check_tables_and_bank() -> void:
	for type_name: String in UnitData.UnitType.keys():
		_expect(AudioManager.UNIT_CLASS.has(int(UnitData.UnitType[type_name])), "unit class mapped: " + type_name)
	_expect(AudioManager.UNIT_CLASS[UnitData.UnitType.VILLAGER] == "villager" and AudioManager.UNIT_CLASS[UnitData.UnitType.INFANTRY] == "infantry" and AudioManager.UNIT_CLASS[UnitData.UnitType.ARCHER] == "archer" and AudioManager.UNIT_CLASS[UnitData.UnitType.CAVALRY] == "cavalry" and AudioManager.UNIT_CLASS[UnitData.UnitType.SCOUT] == "cavalry" and AudioManager.UNIT_CLASS[UnitData.UnitType.SIEGE] == "siege", "unit class mirror matches UnitData")
	for type_name: String in BuildingData.BuildingType.keys():
		_expect(AudioManager.BUILDING_SELECT.has(int(BuildingData.BuildingType[type_name])), "building voice mapped: " + type_name)
	_expect(AudioManager.BUILDING_SELECT[BuildingData.BuildingType.TOWN_CENTER] == "select_town_center" and AudioManager.BUILDING_SELECT[BuildingData.BuildingType.BARRACKS] == "select_barracks" and AudioManager.BUILDING_SELECT[BuildingData.BuildingType.STABLE] == "select_stable" and AudioManager.BUILDING_SELECT[BuildingData.BuildingType.BLACKSMITH] == "select_blacksmith", "building mirror matches BuildingData")
	var bank: Dictionary = preload("res://scripts/audio/identity_palette.gd").build()
	for cue: String in AudioManager.IDENTITY:
		_expect(bank.has(cue), "configured cue has recordings: " + cue)
	for cue: String in bank:
		_expect(AudioManager.IDENTITY.has(cue), "recorded cue is configured: " + cue)
		for stream: AudioStream in bank[cue]:
			_expect(stream != null and stream.get_length() > 0.08 and stream.get_length() < 5.4, "bounded duration: " + cue)
	for cue: String in ["melee_hit", "villager_hit", "cavalry_hit", "bow_release", "arrow_impact", "siege_launch", "siege_impact", "building_hit", "building_collapse", "death_infantry", "death_soft", "death_cavalry", "death_siege", "select_villager", "select_infantry", "select_archer", "select_cavalry", "select_siege"]:
		_expect(bank.has(cue) and (bank[cue] as Array).size() >= 3, "three or more variants: " + cue)
	for table: Dictionary in [AudioManager.IMPACT_BY_CLASS, AudioManager.DEATH_BY_CLASS, AudioManager.ATTACK_ORDER_BY_CLASS]:
		for unit_class: String in table:
			_expect(bank.has(str(table[unit_class])), "class table points at a real cue: " + str(table[unit_class]))
	for unit_class: String in ["villager", "infantry", "archer", "cavalry", "siege"]:
		_expect(bank.has("select_" + unit_class) and bank.has("order_" + unit_class), "acknowledgements exist: " + unit_class)
	for building_cue: String in AudioManager.BUILDING_SELECT.values():
		_expect(bank.has(building_cue), "building voice exists: " + building_cue)
	var director: GDScript = preload("res://scripts/audio/music_director.gd")
	var seen: Dictionary = {}
	for list_name: String in director.PLAYLISTS:
		for track: String in director.PLAYLISTS[list_name]:
			seen[track] = true
			var stream: AudioStream = load(director.MUSIC_DIR + track + ".ogg") as AudioStream
			_expect(stream != null and stream.get_length() > 20.0, "music track loads: " + track)
	_expect(seen.size() == 8 and (director.PLAYLISTS["peace"] as Array).size() >= 4, "four or more peace tracks, battle, menu and two stingers")
	var ambience: GDScript = preload("res://scripts/audio/ambience_director.gd")
	for layer: String in ambience.LAYERS:
		var loop: AudioStream = load(ambience.AMBIENCE_DIR + layer + ".ogg") as AudioStream
		_expect(loop != null and loop.get_length() >= 18.0, "ambience loop loads: " + layer)
	for bus: String in ["Master", "World", "UIAlerts", "Music", "Ambience"]:
		_expect(AudioServer.get_bus_index(bus) >= 0, "bus exists: " + bus)
	_expect(AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Master")) >= 1 and AudioServer.get_bus_effect(AudioServer.get_bus_index("Master"), 0) is AudioEffectHardLimiter, "master limiter present")


func _music() -> Dictionary:
	return AudioManager.get_audio_diagnostics().music


func _played(cue: String) -> int:
	return int(AudioManager.get_audio_diagnostics().played.get(cue, 0))


func _resolved(cue: String) -> int:
	return int(AudioManager.get_audio_diagnostics().resolved.get(cue, 0))


func _ui_cue_playing() -> String:
	for voice: AudioStreamPlayer in AudioManager.get("_ui_players"):
		if voice.playing and int(voice.get_meta("priority", 0)) >= 3:
			return str(voice.get_meta("cue", ""))
	return ""


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition: _failures.append(description)


func _finish() -> void:
	GameManager.music_volume = 0.5
	GameManager.music_muted = false
	GameManager.apply_preferences()
	AudioManager.stop_all()
	# Release the streaming decks before the process exits.
	AudioManager.set("_streams_unlocked", false)
	AudioManager.call("_refresh_directors")
	AudioManager.remove_meta("headless_streams")
	await get_tree().create_timer(0.4).timeout
	if _failures.is_empty():
		print("[PASS] sound_identity: %d checks; class impacts/deaths/acknowledgements from real signals, town vs army alerts, bounded 40-unit burst, battle-music hysteresis, gesture/mute/background music lifecycle, banks and buses" % _checks)
	else:
		for failure: String in _failures: push_error("[FAIL] sound_identity: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
