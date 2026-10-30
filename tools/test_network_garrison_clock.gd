extends Node
## Private rule experiment: actual Site processing and authority snapshots,
## then real recipient application with all actors omitted. No sockets/paid game.

const NETWORK := preload("res://scripts/network/network_match.gd")
const SITE := preload("res://scripts/map/sacred_site.gd")
var failures: Array[String] = []
var checks: int = 0
var main: Node
var map: Node2D
var site: Node2D
var server: Node
var cases: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	NetworkSession.online = false
	NetworkSession.player_slot = 0
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_match_mode = SkirmishData.MatchMode.STANDARD
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	main.set_process(false)
	main.get_node("AIController").process_mode = Node.PROCESS_MODE_DISABLED
	main.get_node("StrategyController").set_process(false)
	GameManager.set_process(false)
	map = main.get("game_map")
	map.set_process(false)
	site = map.sacred_site
	site.set_process(false)
	for unit: Node in get_tree().get_nodes_in_group("units"):
		unit.set_process(false)
	get_tree().paused = true
	server = NETWORK.new()
	main.add_child(server)
	server.main = main
	server.game_map = map
	server.set_process(false)
	var scout: UnitBase = main.call("_spawn_unit", UnitData.UnitType.SCOUT, 0, site.global_position)
	var fighter: UnitBase = main.call("_spawn_unit", UnitData.UnitType.INFANTRY, 0, site.global_position + Vector2(1000, 0))
	var enemy: UnitBase = main.call("_spawn_unit", UnitData.UnitType.SCOUT, 1, site.global_position + Vector2(-1000, 0))
	for unit: UnitBase in [scout, fighter, enemy]:
		unit.set_process(false)
	server.call("_register_server_entities")
	site.configure_match_mode(SkirmishData.MatchMode.STANDARD)
	site.victory_wake_time = 0.0  # The 8:00 opening has its own test (test_sacred_wake).
	site.state = SITE.SiteState.CAPTURED
	site.owning_player = 0
	site.capture_progress = 1.0
	site.victory_timer = 30.0
	var gold: int = ResourceManager.get_resource(0, "gold")
	site.call("_process", 1.0)
	_expect(site.garrison_paused and not site.clock_ticking and site.victory_timer == 30.0, "actual Scout-only Standard site preserves accumulated timer")
	_expect(ResourceManager.get_resource(0, "gold") == gold + 2, "actual paused site retains ordinary captured income")
	_capture_case("unguarded", SkirmishData.MatchMode.STANDARD, false, true, false)
	fighter.global_position = site.global_position + Vector2(20, 0)
	site.call("_process", 1.0)
	_expect(site.clock_ticking and not site.garrison_paused and site.victory_timer == 31.0, "real armed occupant advances actual authority clock")
	_capture_case("holding", SkirmishData.MatchMode.STANDARD, true, false, false)
	scout.global_position += Vector2(1000, 0)
	fighter.global_position += Vector2(1000, 0)
	enemy.global_position = site.global_position
	site.call("_process", 1.0)
	_expect(site.get_status().phase == "neutralizing" and not site.clock_ticking, "actual hostile neutralization precedes garrison state")
	_capture_case("neutralizing", SkirmishData.MatchMode.STANDARD, false, false, true)
	enemy.global_position += Vector2(-1000, 0)
	scout.global_position = site.global_position
	site.configure_match_mode(SkirmishData.MatchMode.QUICK_CONTROL)
	site.victory_wake_time = 0.0  # The 8:00 opening has its own test (test_sacred_wake).
	site.state = SITE.SiteState.CAPTURED
	site.owning_player = 0
	site.capture_progress = 1.0
	site.call("_process", 1.0)
	_expect(site.clock_ticking and not site.garrison_paused and site.victory_timer == 1.0, "Control race remains Scout-eligible and advances normally")
	_capture_case("holding", SkirmishData.MatchMode.QUICK_CONTROL, true, false, false)
	NetworkSession.online = true
	for slot: int in 2:
		NetworkSession.player_slot = slot
		var client: Node = NETWORK.new()
		main.add_child(client)
		client.main = main
		client.game_map = map
		client.set_process(false)
		for example: Dictionary in cases:
			site.configure_match_mode(example.mode)
			site.victory_wake_time = 0.0  # The 8:00 opening has its own test (test_sacred_wake).
			var packet: Dictionary = example.packets[slot].duplicate(true)
			# Deliberately remove all visible actors. Public authority alone must
			# convey clock eligibility, including an unseen opponent garrison.
			packet.actors = []
			client.apply_snapshot(packet)
			_expect(site.owning_player == (0 if slot == 0 else 1), "actual recipient owner remapping for slot%d" % slot)
			_expect(site.clock_ticking == example.ticking and site.garrison_paused == example.paused and site.get_status().phase == example.phase, "slot%d reads authority phase without any actor replicas: %s" % [slot, example.phase])
			_expect(is_equal_approx(site.victory_timer, float(packet.site.timer)) and client.entities.is_empty(), "snapshot timer stays exact with zero local actors")
		_test_adversarial(client, slot)
		client.free()
	NetworkSession.online = false
	NetworkSession.player_slot = 0
	get_tree().paused = false
	main.free()
	await get_tree().process_frame
	for failure: String in failures:
		push_error("[FAIL] network_garrison_clock: " + failure)
	print("NETWORK_GARRISON_CLOCK checks=%d failures=%s scope=private-actual-authority-replica-no-sockets" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _capture_case(phase: String, mode: int, ticking: bool, paused: bool, neutralizing: bool) -> void:
	var packets: Array[Dictionary] = []
	for slot: int in 2:
		var packet: Dictionary = server.call("_snapshot_for", slot)
		for field: String in ["clock_ticking", "garrison_paused", "neutralizing"]:
			_expect(typeof(packet.site.get(field)) == TYPE_BOOL, "actual authority serializes strictbool " + field)
		_expect(packet.site.clock_ticking == ticking and packet.site.garrison_paused == paused and packet.site.neutralizing == neutralizing, "authority public flags match actual processed Site")
		packets.append(packet)
	cases.append({"phase": phase, "mode": mode, "ticking": ticking, "paused": paused, "packets": packets})


func _test_adversarial(client: Node, slot: int) -> void:
	site.configure_match_mode(SkirmishData.MatchMode.STANDARD)
	site.victory_wake_time = 0.0  # The 8:00 opening has its own test (test_sacred_wake).
	var original: Dictionary = cases[1].packets[slot].duplicate(true)
	original.actors = []
	for field: String in ["clock_ticking", "garrison_paused", "neutralizing"]:
		for invalid: Variant in [1, 0, "true", [], {}, null]:
			var packet: Dictionary = original.duplicate(true)
			packet.site.clock_ticking = false
			packet.site.garrison_paused = false
			packet.site.neutralizing = false
			packet.site[field] = true
			client.apply_snapshot(packet)
			packet.site[field] = invalid
			client.apply_snapshot(packet)
			_expect(not site.clock_ticking and not site.garrison_paused and not site.get("_being_neutralized"), "slot%d malformed%s clears all previously true flags" % [slot, field])
		var missing: Dictionary = original.duplicate(true)
		missing.site.clock_ticking = false
		missing.site.garrison_paused = false
		missing.site.neutralizing = false
		missing.site[field] = true
		client.apply_snapshot(missing)
		missing.site.erase(field)
		client.apply_snapshot(missing)
		_expect(not site.clock_ticking and not site.garrison_paused and not site.get("_being_neutralized"), "slot%d absent%s clears earlier authority state" % [slot, field])
	var contradictory: Dictionary = original.duplicate(true)
	contradictory.site.clock_ticking = true
	contradictory.site.garrison_paused = true
	client.apply_snapshot(contradictory)
	_expect(site.garrison_paused and not site.clock_ticking and site.get_status().phase == "unguarded", "explicit Standard pause wins contradictory clock flag")
	contradictory.site.neutralizing = true
	client.apply_snapshot(contradictory)
	_expect(site.get_status().phase == "neutralizing" and not site.garrison_paused and not site.clock_ticking, "neutralizing takes priority over both other flags")
	for invalid_state: int in [SITE.SiteState.NEUTRAL, SITE.SiteState.CAPTURING, SITE.SiteState.CONTESTED]:
		contradictory.site.state = invalid_state
		client.apply_snapshot(contradictory)
		_expect(not site.clock_ticking and not site.garrison_paused and not site.get("_being_neutralized"), "noncaptured state cannot display captured clock flags")
	contradictory.site.state = SITE.SiteState.CAPTURED
	for invalid_owner: int in [-1, 2]:
		contradictory.site.owner = invalid_owner
		client.apply_snapshot(contradictory)
		_expect(not site.clock_ticking and not site.garrison_paused and not site.get("_being_neutralized"), "invalid authority owner cannot retain clock flags")
	client.apply_snapshot(original)
	client.apply_snapshot({"actors": []})
	_expect(not site.clock_ticking and not site.garrison_paused and not site.get("_being_neutralized"), "entire missing site clears previous public flags")
	site.configure_match_mode(SkirmishData.MatchMode.QUICK_CONTROL)
	site.victory_wake_time = 0.0  # The 8:00 opening has its own test (test_sacred_wake).
	contradictory = original.duplicate(true)
	contradictory.site.clock_ticking = true
	contradictory.site.garrison_paused = true
	contradictory.site.neutralizing = false
	client.apply_snapshot(contradictory)
	_expect(site.clock_ticking and not site.garrison_paused and site.get_status().phase == "holding", "Control ignores invalid Standard-only pause without stopping its authority clock")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
