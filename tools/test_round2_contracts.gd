extends Node
## Round 2 Phase 0 contracts on the real Main scene: modifier registry and its
## save round trip, extension save sections, extension network commands with
## rejection of unknown/malformed orders, snapshot sections, and Blacksmith
## research through building context actions (solo HUD path and authority).
const STATE = preload("res://scripts/main/solo_match_state.gd")
const NETWORK = preload("res://scripts/network/network_match.gd")
const EXTENSIONS = preload("res://scripts/main/match_extensions.gd")
const CONTRACT_SIGNALS: Array[String] = ["research_started", "research_cancelled", "research_completed", "age_advance_started", "age_advance_cancelled", "age_advanced", "town_bell_changed", "wildlife_claimed", "boar_felled", "unit_tier_changed"]
const ACTION_KEYS: Array[String] = ["id", "label", "icon", "cost", "time", "progress", "disabled_reason"]

static var probe_block: String = ""
static var probe_performed: int = 0

var checks: int = 0
var failures: Array[String] = []
var main: Node
var _events: Array[String] = []
var _marker: Node2D
var _probe_counter: int = 0
var _restored: Dictionary = {}
var _finalized: Dictionary = {}
var _phases: Array[String] = []
var _commands: Array[Dictionary] = []
var _consumed: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)


func _wait_main() -> bool:
	main = null
	for frame: int in 900:
		await get_tree().process_frame
		var scene: Node = get_tree().current_scene
		if scene != null and scene.get("_building_placement") != null:
			main = scene
			main.process_mode = Node.PROCESS_MODE_DISABLED
			return true
	check(false, "Main initialized within bounded frames")
	return false


func _smith() -> BuildingBase:
	for building: BuildingBase in main._player_buildings[0]:
		if building.building_type == BuildingData.BuildingType.BLACKSMITH: return building
	return null


# --- Probe extension: what a later gameplay stream would register -----------

func _install_probe(main_node: Node) -> void:
	_marker = Node2D.new()
	_marker.name = "Round2ProbeMarker"
	main_node.add_child(_marker)
	main_node.ext.register_save("probe", _capture_probe.bind(main_node), _restore_probe.bind(main_node), _finalize_probe)


func _capture_probe(codec: RefCounted, main_node: Node) -> Dictionary:
	return {"counter": _probe_counter, "tc": codec.encode(main_node._player_town_center), "marker": codec.track(_marker)}


func _restore_probe(saved: Dictionary, codec: RefCounted, main_node: Node) -> void:
	_phases.append("restore")
	codec.bind(int(saved.marker), _marker)
	_restored = {"counter": saved.counter, "tc": codec.decode(saved.tc), "units": main_node._player_units[0].size(), "smith_hp": _smith_hp(main_node)}


func _finalize_probe(saved: Dictionary, codec: RefCounted) -> void:
	_phases.append("finalize")
	_finalized = {"marker": codec.decode({"$ref": int(saved.marker)})}


func _smith_hp(main_node: Node) -> int:
	for building: BuildingBase in main_node._player_buildings[0]:
		if building.building_type == BuildingData.BuildingType.BLACKSMITH: return building.hp
	return -1


static func probe_actions(building: BuildingBase, _player_id: int) -> Array:
	if building.building_type != BuildingData.BuildingType.BLACKSMITH: return []
	return [{"id": "probe:ping", "label": "Ping", "icon": "", "cost": {"wood": 5}, "time": 0.0, "progress": -1.0, "disabled_reason": probe_block, "desc": "Test action"}]


static func probe_perform(_building: BuildingBase, _player_id: int, _action_id: String) -> String:
	probe_performed += 1
	return ""


func _probe_command(owner: int, packet: Dictionary, units: Array, target: Node2D, position: Vector2) -> String:
	_commands.append({"owner": owner, "units": units.duplicate(), "target": target, "position": position})
	return "Probe refused" if packet.mode == "refuse" else ""


# --- Scenario ----------------------------------------------------------------

func _run() -> void:
	# Keep the fixture alive while the real scene lifecycle replaces Main.
	get_tree().current_scene = null
	AudioManager.set_all_enabled(false)
	SoloSave.set_process(false)
	SoloSave.discard_save("round2_contracts_fixture")
	GameManager.selected_map_seed = 424242
	GameManager.selected_map_archetype = 0
	GameManager.guided_opening_enabled = false
	EXTENSIONS.installers.append(_install_probe)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	if not await _wait_main():
		await _finish()
		return
	check(main.ext != null and main.ext.has_command("building_action"), "Main owns an extension registry with the built-in building_action command")
	_check_registry()
	_check_context_actions()
	if not await _check_save_round_trip():
		await _finish()
		return
	_check_network()
	await _finish()


func _check_registry() -> void:
	for signal_name: String in CONTRACT_SIGNALS:
		check(GameManager.has_signal(signal_name), "GameManager declares " + signal_name)
	check(GameManager.get_modifier(0, "attack") == 0.0 and GameManager.get_modifier(0, "missing", 7.5) == 7.5, "unset keys read as the default")
	check(GameManager.add_modifier(0, "attack", 2.0) == 2.0 and GameManager.add_modifier(0, "attack", 2.0) == 4.0, "add_modifier is additive and returns the total")
	check(GameManager.get_attack_bonus(0) == 4 and GameManager.get_attack_bonus(1) == 0, "legacy attack getter wraps the registry per player")
	GameManager.apply_armor_upgrade(1, 1)
	GameManager.apply_gather_upgrade(1, 0.25)
	GameManager.apply_villager_hp_upgrade(1, 15)
	check(GameManager.get_modifier(1, "armor") == 1.0 and GameManager.get_modifier(1, "gather_all") == 0.25 and GameManager.get_modifier(1, "villager_hp") == 15.0, "legacy appliers write registry keys")
	check(GameManager.player_upgrades[1] == {"attack_bonus": 0, "armor_bonus": 1, "gather_bonus": 0.25, "villager_hp_bonus": 15}, "player_upgrades alias keeps the old shape and types")
	GameManager.add_modifier(0, "gather_wood", 0.2)
	GameManager.add_modifier(0, "gather_wood", 0.15)
	check(is_equal_approx(GameManager.get_modifier_multiplier(0, "gather_wood"), 1.35) and GameManager.get_modifier_multiplier(0, "gather_gold") == 1.0, "percentage keys combine into one multiplier")
	GameManager.set_modifier(0, "tier_1", 2.0)
	GameManager.set_modifier(0, "tier_1", 3.0)
	check(GameManager.get_modifier(0, "tier_1") == 3.0, "set_modifier overwrites level-like keys")
	GameManager.add_modifier(7, "attack", 9.0)
	check(not GameManager.player_modifiers.has(7) and GameManager.get_modifier(7, "attack") == 0.0, "players outside the match are ignored")
	GameManager.import_legacy_upgrades(1, {"attack_bonus": 2, "armor_bonus": 0})
	check(GameManager.get_modifier(1, "attack") == 2.0 and GameManager.get_modifier(1, "armor") == 0.0 and GameManager.get_modifier(1, "villager_hp") == 15.0, "legacy dictionaries import only the fields they carry")
	GameManager.player_modifiers = {0: {}, 1: {}}


func _check_context_actions() -> void:
	var center: Vector2i = main.game_map.map_generator.get_expansion_pocket_centers()[0]
	var smith: BuildingBase = main._spawn_building(BuildingData.BuildingType.BLACKSMITH, 0, center)
	smith.start_construction()
	check(smith.get_context_actions(0).is_empty(), "a foundation offers no research")
	smith.complete_instantly()
	# Round 2 B: Blacksmith research is timed and starts in the Feudal Age.
	GameManager.players[0]["age"] = 2
	ResourceManager.initialize_player(0, {"food": 0, "wood": 0, "gold": 0})
	var actions: Array[Dictionary] = smith.get_context_actions(0)
	var ids: Array = actions.map(func(action: Dictionary) -> String: return action.id)
	check(ids == ["research:forging", "research:scale_mail", "research:fletching", "research:stone_keep"], "Blacksmith exposes its first-tier techs in shelf order: " + str(ids))
	for action: Dictionary in actions:
		for key: String in ACTION_KEYS:
			check(action.has(key), "%s carries %s" % [action.id, key])
		var definition: Dictionary = TechData.get_research_definition(str(action.id).trim_prefix("research:"))
		check(action.label == definition.name and action.cost == definition.cost and action.time == definition.time and action.time > 0.0 and action.progress == -1.0, action.id + " mirrors its tech definition")
		check(action.reason == ("age_required" if action.id == "research:stone_keep" else "unaffordable") and action.disabled_reason.begins_with("Need ") and action.done == false, action.id + " reports why it is blocked: " + action.disabled_reason)
	check(smith.get_context_actions(1).is_empty(), "the opponent is offered nothing on this building")
	check(main._player_buildings[0].filter(func(building: BuildingBase) -> bool: return building.building_type == BuildingData.BuildingType.HOUSE).all(func(house: BuildingBase) -> bool: return house.get_context_actions(0).is_empty()) and main._player_town_center.get_context_actions(0).any(func(action: Dictionary) -> bool: return action.id == "research:loom"), "only buildings with techs or providers have actions")
	ResourceManager.initialize_player(0, {"food": 2000, "wood": 2000, "gold": 2000})
	check(smith.get_context_actions(0).slice(0, 3).all(func(action: Dictionary) -> bool: return action.disabled_reason == ""), "funded techs of the current age are enabled")
	GameManager.research_started.connect(func(player_id: int, building: Node2D, research_id: String, duration: float) -> void: _events.append("started:%d:%s:%s:%s" % [player_id, research_id, building == _smith(), duration]))
	GameManager.research_completed.connect(func(player_id: int, research_id: String) -> void: _events.append("completed:%d:%s" % [player_id, research_id]))
	check(smith.perform_context_action(1, "research:forging") == "Select your building" and not GameManager.has_research(1, "forging") and not GameManager.has_research(0, "forging"), "another player cannot use the building")
	check(ResourceManager.get_all_resources(0) == {"food": 2000, "wood": 2000, "gold": 2000}, "a rejected action spends nothing")
	# Solo path: exactly what the HUD row emits.
	main._on_building_action_requested(smith, "research:forging")
	check(smith.research_id == "forging" and not GameManager.has_research(0, "forging") and smith.get_context_actions(0)[0].progress == 0.0, "the context action starts the timed research")
	main._advance_production_queues(30.5)
	check(GameManager.has_research(0, "forging") and GameManager.get_modifier(0, "attack") == 2.0 and GameManager.get_attack_bonus(0) == 2, "context action researches Forging into the registry")
	check(ResourceManager.get_all_resources(0) == {"food": 1900, "wood": 2000, "gold": 1950}, "research charges its exact cost once")
	check(_events == ["started:0:forging:true:30.0", "completed:0:forging"], "research_started (with its duration) precedes research_completed: " + str(_events))
	check(smith.perform_context_action(0, "research:forging") == "Research unavailable" and ResourceManager.get_resource(0, "food") == 1900, "a completed tech cannot be bought twice")
	var forging: Dictionary = smith.get_context_actions(0)[0]
	check(forging.id == "research:iron_casting" and forging.reason == "age_required" and forging.done == false, "a finished tech hands its card to its follow-up")
	GameManager.complete_research(0, "fletching")
	forging = smith.get_context_actions(0)[2]
	check(forging.id == "research:fletching" and forging.done == true and forging.reason == "already_researched", "completed tech is reported done")
	GameManager.researched_upgrades[0].erase("fletching")
	check(smith.perform_context_action(0, "bogus:thing") == "Action unavailable" and smith.perform_context_action(0, "research:nope") == "Research unavailable", "unknown actions are rejected")
	# The real HUD row, on the real Main.
	var hud: CanvasLayer = main.hud
	hud.show_building_selection("Blacksmith", smith.hp, smith.max_hp, [], [], smith)
	var row: HBoxContainer = hud.get("_research_container")
	check(row != null and row.visible and row.get_child_count() == 4, "HUD renders four action cards for the Blacksmith")
	var forge_card: Button = row.get_node_or_null("ResearchButton_iron_casting") as Button
	var mail_card: Button = row.get_node_or_null("ResearchButton_scale_mail") as Button
	check(forge_card != null and forge_card.disabled and forge_card.text == "Iron Cast\n+2 Attack\nNeed Castle", "a blocked card says why where its cost was: " + (forge_card.text if forge_card != null else "missing"))
	check(mail_card != null and not mail_card.disabled and mail_card.text == "Mail\n+1 Armor\n100F · 50G", "available card keeps name, effect and cost: " + (mail_card.text if mail_card != null else "missing"))
	if mail_card != null: mail_card.pressed.emit()
	hud.show_building_selection("Blacksmith", smith.hp, smith.max_hp, [], [], smith)
	mail_card = row.get_node_or_null("ResearchButton_scale_mail") as Button
	check(smith.research_id == "scale_mail" and mail_card != null and not mail_card.disabled and mail_card.text == "Mail\n+1 Armor\nCancel", "a running card is the cancel meter: " + (mail_card.text if mail_card != null else "missing"))
	main._advance_production_queues(30.5)
	check(GameManager.has_research(0, "scale_mail") and GameManager.get_armor_bonus(0) == 1 and ResourceManager.get_all_resources(0) == {"food": 1800, "wood": 2000, "gold": 1900}, "pressing a card buys through building_action_requested exactly once")
	# A later stream's provider needs no HUD or BuildingBase edit.
	BuildingBase.register_context_provider("probe", probe_actions, probe_perform)
	check(smith.get_context_actions(0).size() == 5 and smith.get_context_actions(0)[4].id == "probe:ping" and not main._player_town_center.get_context_actions(0).any(func(action: Dictionary) -> bool: return action.id == "probe:ping"), "registered provider appends its action to matching buildings only")
	hud.show_building_selection("Blacksmith", smith.hp, smith.max_hp, [], [], smith)
	var ping: Button = row.get_node_or_null("ActionButton_probe_ping") as Button
	check(ping != null and not ping.disabled and ping.text == "Ping\nTest action\n5W", "HUD renders a provider action generically: " + (ping.text if ping != null else "missing"))
	if ping != null: ping.pressed.emit()
	check(probe_performed == 1, "provider action executes through the same HUD signal")
	probe_block = "Bell is cooling down"
	check(smith.perform_context_action(0, "probe:ping") == "Bell is cooling down" and probe_performed == 1, "a disabled provider action returns its reason and does not run")
	hud.show_building_selection("Blacksmith", smith.hp, smith.max_hp, [], [], smith)
	ping = row.get_node_or_null("ActionButton_probe_ping") as Button
	check(ping != null and ping.disabled, "HUD disables a blocked provider action")
	BuildingBase.unregister_context_provider("probe")
	check(smith.get_context_actions(0).size() == 4, "unregistering removes the provider")


func _check_save_round_trip() -> bool:
	GameManager.set_modifier(0, "tier_1", 2.0)
	GameManager.add_modifier(1, "gather_wood", 0.2)
	_probe_counter = 41
	var smith: BuildingBase = _smith()
	smith.hp -= 37
	var data: Dictionary = STATE.new().capture(main)
	check(STATE.validate(data).is_empty(), "schema-2 capture validates: " + STATE.validate(data))
	check(data.schema == 2 and data.ext is Dictionary and data.ext.get("probe", {}).get("counter") == 41, "capture stores the registered extension section")
	check(data.manager.player_modifiers == {0: {"attack": 2.0, "armor": 1.0, "tier_1": 2.0}, 1: {"gather_wood": 0.2}} and not data.manager.has("player_upgrades"), "capture stores the modifier registry: " + str(data.manager.player_modifiers))
	var old: Dictionary = data.duplicate(true)
	old.schema = 1
	check(STATE.validate(old) == "This save belongs to a different game version.", "schema-1 checkpoints are rejected with the existing message")
	var broken: Dictionary = data.duplicate(true)
	broken.erase("ext")
	check(STATE.validate(broken) == "Incomplete solo save.", "a save without ext is incomplete")
	broken = data.duplicate(true)
	broken.ext["Bad Name"] = {}
	check(STATE.validate(broken) == "Invalid extension state.", "extension names are validated")
	broken = data.duplicate(true)
	broken.ext["probe"] = [1, 2]
	check(STATE.validate(broken) == "Invalid extension state.", "extension sections must be dictionaries")
	broken = data.duplicate(true)
	broken.manager.player_modifiers[0]["attack"] = "2"
	check(STATE.validate(broken) == "Invalid player state.", "modifier values must be finite numbers")
	check(SoloSave.save_current("round2_contracts"), "native checkpoint accepts the schema-2 match")
	# Diverge live state so only a real restore can bring it back.
	_probe_counter = 0
	GameManager.player_modifiers = {0: {}, 1: {}}
	check(SoloSave.resume_match(), "checkpoint resumes through the real Main lifecycle")
	if not await _wait_main(): return false
	check(_phases == ["restore", "finalize"], "extension restore runs before finalize, once each: " + str(_phases))
	check(_restored.get("counter") == 41 and _restored.get("tc") == main._player_town_center and main._player_town_center != null, "extension data and actor references round-trip")
	check(int(_restored.get("units", 0)) == main._player_units[0].size() and int(_restored.get("smith_hp", -1)) != -1, "restore phase already sees every spawned actor: " + str(_restored))
	check(_finalized.get("marker") == _marker and is_instance_valid(_marker) and _marker.get_parent() == main, "a node bound by the extension resolves by its saved identity")
	check(GameManager.player_modifiers == {0: {"attack": 2.0, "armor": 1.0, "tier_1": 2.0}, 1: {"gather_wood": 0.2}}, "modifier registry round-trips: " + str(GameManager.player_modifiers))
	check(GameManager.get_attack_bonus(0) == 2 and GameManager.get_armor_bonus(0) == 1 and GameManager.has_research(0, "forging") and GameManager.has_research(0, "scale_mail"), "restored research still applies through the legacy getters")
	check(_smith() != null and _smith().hp == smith_full_hp() - 37, "restored Blacksmith keeps its saved state")
	GameManager.set_paused(false)
	return true


func smith_full_hp() -> int:
	return _smith().max_hp if _smith() != null else -2


func _check_network() -> void:
	# In-process authority regression (the adapter the match server runs), not a
	# socket-connected match; tools/run_online_tests.py covers the transport.
	NetworkSession.set_process(false)
	NetworkSession.set_physics_process(false)
	NetworkSession.online = true
	NetworkSession.server_mode = true
	var server: Node = NETWORK.new()
	main.add_child(server)
	server.main = main
	server.game_map = main.game_map
	server.set_process(false)
	server._register_server_entities()
	var smith: BuildingBase = _smith()
	var smith_id: int = NetworkSession.entity_id(smith)
	var own_ids: Array = main._player_units[0].map(func(unit: Node) -> int: return NetworkSession.entity_id(unit))
	var enemy_id: int = NetworkSession.entity_id(main._player_units[1][0])
	check(server.execute_command(0, {"command": "definitely_not_an_order"}) == "Unknown order" and server.execute_command(0, {"command": "probe_echo", "mode": "x"}) == "Unknown order", "unregistered operations are rejected exactly as before")
	check(not main.ext.register_command("Bad Name", _probe_command) and not main.ext.has_command("Bad Name"), "malformed operation names cannot be registered")
	check(main.ext.register_command("probe_echo", _probe_command, func(packet: Dictionary) -> bool: return packet.get("mode") is String), "a stream registers its command")
	check(server.execute_command(0, {"command": "probe_echo", "mode": "x", "ids": own_ids + [enemy_id], "target": smith_id, "position": [12.0, 34.0]}) == "" and _commands.size() == 1, "registered operation is dispatched")
	if _commands.size() == 1:
		var seen: Dictionary = _commands[0]
		check(seen.owner == 0 and seen.target == smith and seen.position == Vector2(12.0, 34.0), "handler receives owner, target and position")
		check(seen.units.size() == own_ids.size() and seen.units.all(func(unit: UnitBase) -> bool: return unit.player_owner == 0), "handler receives only the sender's own units")
	check(server.execute_command(1, {"command": "probe_echo", "mode": "refuse"}) == "Probe refused" and _commands.size() == 2, "handler rejection reason reaches the sender")
	check(server.execute_command(0, {"command": "probe_echo"}) == "Invalid order" and server.execute_command(0, {"command": "probe_echo", "mode": 5}) == "Invalid order", "the registered validator rejects malformed packets")
	check(server.execute_command(0, {"command": "probe_echo", "mode": "x", "blob": {"nested": 1}}) == "Invalid order" and server.execute_command(0, {"command": "probe_echo", "mode": "x".repeat(65)}) == "Invalid order" and server.execute_command(0, {"command": "probe_echo", "mode": "x", "list": ["text"]}) == "Invalid order", "nested, oversized and non-numeric-array values are rejected generically")
	check(server.execute_command(2, {"command": "probe_echo", "mode": "x"}) == "Invalid order" and _commands.size() == 2, "no rejected packet reaches the handler")
	# Generic building_action: the HUD row's online route, validated on the authority.
	ResourceManager.initialize_player(0, {"food": 1000, "wood": 1000, "gold": 1000})
	ResourceManager.initialize_player(1, {"food": 1000, "wood": 1000, "gold": 1000})
	var tc_id: int = NetworkSession.entity_id(main._player_town_center)
	var action: Dictionary = {"command": "building_action", "target": tc_id, "action": "research:wheelbarrow"}
	check(server.execute_command(1, action) == "Select your building" and not GameManager.has_research(0, "wheelbarrow") and not GameManager.has_research(1, "wheelbarrow"), "authority rejects another player's building")
	check(server.execute_command(0, {"command": "building_action", "target": smith_id, "action": 5}) == "Invalid order" and server.execute_command(0, {"command": "building_action", "target": smith_id}) == "Invalid order", "authority rejects a malformed action id")
	check(server.execute_command(0, {"command": "building_action", "target": smith_id, "action": "research:nope"}) == "Research unavailable" and server.execute_command(0, {"command": "building_action", "target": smith_id, "action": "bogus"}) == "Action unavailable" and server.execute_command(0, {"command": "building_action", "target": NetworkSession.entity_id(main._player_units[0][0]), "action": "research:wheelbarrow"}) == "Select your building", "authority rejects unknown actions and non-building targets")
	check(ResourceManager.get_all_resources(0) == {"food": 1000, "wood": 1000, "gold": 1000} and ResourceManager.get_all_resources(1) == {"food": 1000, "wood": 1000, "gold": 1000}, "rejected building actions spend nothing")
	check(server.execute_command(0, action) == "" and not GameManager.has_research(0, "wheelbarrow") and ResourceManager.get_all_resources(0) == {"food": 825, "wood": 950, "gold": 1000}, "authority starts Wheelbarrow through building_action at its exact cost")
	main._advance_production_queues(35.5)
	check(GameManager.has_research(0, "wheelbarrow"), "the timed research completes on the authority")
	check(is_equal_approx(GameManager.get_modifier(0, "carry"), 0.34) and is_equal_approx(GameManager.get_modifier(0, "villager_speed"), 0.1) and GameManager.get_modifier(0, "gather_all") == 0.0, "its effect lands in the registry")
	check(server.execute_command(0, action) == "Research unavailable" and ResourceManager.get_resource(0, "food") == 825, "authority refuses a repeat purchase")
	check(server.execute_command(0, {"command": "research", "target": tc_id, "research": "loom"}) == "" and GameManager.get_villager_hp_bonus(0) == 0, "the original research command starts a timed research")
	main._advance_production_queues(15.5)
	check(GameManager.get_villager_hp_bonus(0) == 15, "and it completes")
	# Snapshot sections.
	main.ext.register_snapshot("probe", func(slot: int) -> Dictionary: return {"slot": slot, "n": 3}, func(section: Variant) -> void: _consumed.append(section))
	main.ext.register_snapshot("probe_empty", func(_slot: int) -> Variant: return null)
	var snapshot: Dictionary = server._snapshot_for(0)
	check(snapshot.get("ext", {}).get("probe") == {"slot": 0, "n": 3} and not snapshot.ext.has("probe_empty") and snapshot.ext.has("research") and server._snapshot_for(1).ext.probe.slot == 1, "snapshot.ext carries each provider's per-recipient section and omits null")
	check(snapshot.get("modifiers") == GameManager.player_modifiers[0] and not snapshot.has("upgrades") and snapshot.modifiers.get("attack") == 2.0, "snapshot replicates the owner's modifier registry")
	var wire: Variant = JSON.parse_string(JSON.stringify({"ext": snapshot.ext, "modifiers": snapshot.modifiers}))
	check(wire is Dictionary and wire.ext.probe.n == 3.0, "extension sections survive the JSON wire format")
	# Client side: a fresh replica adapter applying what the wire delivered.
	var client: Node = NETWORK.new()
	main.add_child(client)
	client.main = main
	client.game_map = main.game_map
	client.set_process(false)
	client.apply_snapshot({"modifiers": {"attack": 3.0, "tier_1": 2.0}, "ext": wire.ext if wire is Dictionary else {}, "research": ["forging"]})
	check(_consumed.size() == 1 and _consumed[0].get("slot") == 0.0, "registered consumer receives its section on the client")
	check(GameManager.get_modifier(0, "attack") == 3.0 and GameManager.get_modifier(0, "tier_1") == 2.0 and GameManager.get_modifier(0, "armor") == 0.0 and GameManager.get_attack_bonus(0) == 3, "client adopts the authoritative modifiers")
	client.apply_snapshot({"upgrades": {"attack_bonus": 1, "armor_bonus": 1}})
	check(_consumed.size() == 1 and GameManager.get_attack_bonus(0) == 1 and GameManager.get_armor_bonus(0) == 1 and GameManager.get_modifier(0, "tier_1") == 0.0, "a snapshot without ext or modifiers is tolerated")
	NetworkSession.online = false
	NetworkSession.server_mode = false


func _finish() -> void:
	EXTENSIONS.installers.erase(_install_probe)
	BuildingBase.unregister_context_provider("probe")
	print(JSON.stringify({"test": "round2_contracts", "checks": checks, "failures": failures, "scope": "real Main scene; modifier registry, context actions via HUD and authority adapter, ext commands/snapshots, native schema-2 save/resume with an extension section"}))
	if failures.is_empty():
		print("[PASS] round2_contracts: %d checks" % checks)
	else:
		for failure: String in failures: push_error("[FAIL] round2_contracts: " + failure)
	if is_instance_valid(main): main.queue_free()
	get_tree().paused = false
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
