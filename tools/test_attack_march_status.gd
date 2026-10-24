extends Node
## Synthetic actors in real Main, actual authority snapshots/remapped replicas,
## and native HUD layout. No socket, paid-gameplay, pacing or phone claim.

const NETWORK := preload("res://scripts/network/network_match.gd")
var checks: int = 0
var failures: Array[String] = []
var records: Array[Dictionary] = []
var output: String = ""
var main: Node
var map: Node2D
var hud: CanvasLayer
var safe: Rect2
var own: Array[UnitBase] = []
var opposing: Array[UnitBase] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	AudioManager.set_all_enabled(false)
	NetworkSession.online = false
	GameManager.guided_opening_enabled = false
	GameManager.selected_map_seed = 101
	GameManager.selected_civilization = CivilizationData.Civilization.SUNSTRIDE_CLANS
	GameManager.selected_opponent_civilization = CivilizationData.Civilization.CROWNLANDS
	main = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	for frame: int in 900:
		if main.get("_building_placement") != null and GameManager.current_state == GameManager.GameState.PLAYING:
			break
		await get_tree().process_frame
	_expect(main.get("_building_placement") != null, "real Main initialized")
	get_tree().paused = true
	main.set_process(false)
	main.get_node("AIController").process_mode = Node.PROCESS_MODE_DISABLED
	main.get_node("StrategyController").set_process(false)
	map = main.get("game_map")
	hud = main.get_node("HUD")
	map.set_process(false)
	var generator := MapGenerator.new(101)
	generator.call("_init_grid")
	map.set("pathfinding", Pathfinding.new(generator))
	var server: Node = NETWORK.new()
	main.add_child(server)
	server.main = main
	server.game_map = map
	server.set_process(false)
	for owner: int in [0, 1]:
		var group: Array[UnitBase] = []
		for index: int in 2:
			var unit: UnitBase = main.call("_spawn_unit", UnitData.UnitType.INFANTRY if index == 0 else UnitData.UnitType.CAVALRY, owner, map.tile_to_world(Vector2i(20 + index, 20 + owner * 2)))
			unit.set_process(false)
			group.append(unit)
		if owner == 0:
			own = group
		else:
			opposing = group
	server.call("_register_server_entities")
	for group: Array[UnitBase] in [own, opposing]:
		var goal: Vector2 = map.tile_to_world(Vector2i(30, 20 + group[0].player_owner * 2))
		var result: String = server.execute_command(group[0].player_owner, {"command": "attack_move", "ids": [NetworkSession.entity_id(group[0]), NetworkSession.entity_id(group[1])], "position": [goal.x, goal.y]})
		_expect(result.is_empty() and group[0].is_attack_marching() and group[1].is_attack_marching(), "accepted authority attack move sets active status for owner%d" % group[0].player_owner)
	main.call("_update_fog_of_war")
	var token: RefCounted = own[0].get_attack_march()
	var before_scans: int = int(token.get("member_scans"))
	for iteration: int in 20:
		own[0].is_attack_marching()
		own[1].is_attack_marching()
		server.call("_snapshot_for", 0)
	_expect(int(token.get("member_scans")) == before_scans, "status and snapshot reads never scan or mutate the token")
	var active_packets: Array[Dictionary] = []
	for slot: int in 2:
		var packet: Dictionary = server.call("_snapshot_for", slot)
		packet.actors = _only_fixture_actors(packet.actors)
		var own_seen: int = 0
		var enemies_seen: int = 0
		for actor: Dictionary in packet.actors:
			if int(actor.owner) == slot:
				own_seen += 1
				_expect(typeof(actor.get("marching")) == TYPE_BOOL and actor.marching == true, "own authority actor explicitly reports true")
			else:
				enemies_seen += 1
				_expect(not actor.has("marching"), "visible enemy actor contains no march status")
		_expect(own_seen == 2 and enemies_seen == 2, "actual fog admits both visible opposing actors without private status")
		active_packets.append(packet)
	_check_direct_free_status()
	await _check_layouts()
	own[0].take_damage(1.0)
	_expect(own[1].get_attack_march() != null and not own[1].is_attack_marching(), "retained released token cannot leave visible status true")
	var released: Dictionary = server.call("_snapshot_for", 0)
	for actor: Dictionary in _only_fixture_actors(released.actors):
		if int(actor.owner) == 0:
			_expect(actor.get("marching") == false, "actual damage clears the next own authority snapshot")
	main.call("_on_selection_changed", [own[1]] as Array[Node2D])
	_expect(not str(hud.get("selection_details").text).contains("together"), "contact clears actual Main HUD even before movement consumes token")
	_expect(own[1].speed == 110.0 and opposing[1].speed == 95.0, "base civilization speeds remain unchanged")
	await _check_replicas(active_packets)
	NetworkSession.online = false
	NetworkSession.player_slot = 0
	get_tree().paused = false
	main.free()
	if not output.is_empty():
		var file := FileAccess.open(output + "/receipt.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"scope": "Synthetic actors, actual offline authority serialization and local remapped replica application, native HUD font/rectangle checks. No sockets, paid match, physical phone or performance claim.", "checks": checks, "failures": failures, "states": records}, "  "))
	for failure: String in failures:
		push_error("[FAIL] attack_march_status: " + failure)
	print("ATTACK_MARCH_STATUS checks=%d failures=%s" % [checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)


func _only_fixture_actors(actors: Array) -> Array:
	var ids: Array[int] = []
	for unit: UnitBase in own + opposing:
		ids.append(NetworkSession.entity_id(unit))
	return actors.filter(func(actor: Dictionary) -> bool: return int(actor.id) in ids)


func _check_direct_free_status() -> void:
	# This deliberately bypasses normal death. Keep its synthetic actors out of
	# Main/server registries, whose normal death callbacks would remove them.
	var first: UnitBase = load("res://scenes/units/infantry.tscn").instantiate()
	var second: UnitBase = load("res://scenes/units/cavalry.tscn").instantiate()
	first.position = Vector2.ZERO
	second.position = Vector2(0, 48)
	add_child(first)
	add_child(second)
	first.set_process(false)
	second.set_process(false)
	var orders: Array[Dictionary] = []
	for unit: UnitBase in [first, second]:
		var route := PackedVector2Array([unit.position, unit.position + Vector2(600, 0)])
		unit.command_attack_move_path(route)
		orders.append({"unit": unit, "path": route, "destination": route[1]})
	var token: RefCounted = load("res://scripts/main/attack_march_cohesion.gd").attach_orders(orders)
	_expect(token != null and second.is_attack_marching(), "direct-free pair begins active while simulation is paused")
	var scans: int = int(token.get("member_scans")) if token != null else -1
	first.free()
	_expect(not second.is_attack_marching(), "tree exit immediately clears the surviving member without a movement frame")
	_expect(token != null and int(token.get("member_scans")) == scans, "tree-exit clearing keeps status observation scan-free")
	second.free()


func _check_layouts() -> void:
	hud.call("set_early_game_ui_state", false)
	hud.call("set_progression_hint", "")
	hud.set("_movement_controls_hint_shown", true)
	var extra: UnitBase = main.call("_spawn_unit", UnitData.UnitType.CAVALRY, 0, own[1].position + Vector2(40, 0))
	extra.set_process(false)
	for size: Vector2i in [Vector2i(844, 390), Vector2i(932, 430)]:
		for scale: float in [0.85, 1.0, 1.15]:
			get_window().size = size
			get_window().content_scale_size = Vector2i(844, 390)
			get_window().content_scale_factor = scale
			await get_tree().process_frame
			var logical: Vector2 = get_viewport().get_visible_rect().size
			safe = Rect2(Vector2.ZERO, logical)
			if scale > 1.0:
				safe = Rect2(Vector2(44.0 / scale, 0), logical - Vector2(88.0 / scale, 18.0 / scale + 60.0))
			var profile: String = "%dx%d-%d" % [size.x, size.y, roundi(scale * 100.0)]
			map.selection_mgr.select_single(own[1])
			await _layout_state(profile, "single", "Marching\ntogether")
			map.selection_mgr.select_many([own[0], own[1], extra] as Array[Node2D])
			await _layout_state(profile, "partial", "Group march\n2/3 fighters")
			var info: Dictionary = hud.call("_selection_information")
			_expect(str(info.body).contains("Group march · 2/3 fighters") and str(info.body).contains("Move travels at normal speed."), "Info explains original group pace without replacing base stats")
			map.selection_mgr.select_single(opposing[1])
			await _layout_state(profile, "enemy", "")
			_expect(not str(hud.call("_selection_information").body).contains("Group march"), "enemy inspection never exposes group state")
			map.selection_mgr.select_single(own[1])
			hud.call("configure_unit_commands", true, true, "Aggressive", "move")
			await _layout_state(profile, "armed-move", "Tap to move")
			hud.call("configure_unit_commands", true, true, "Aggressive", "smart")
			# Worst supported count must fit the same minimum text column.
			hud.call("show_unit_selection", "Army", 100, 100, "Moving", 64, {"player_owner": 0, "selected_fighters": 64, "marching_fighters": 64, "role_counts": {UnitData.UnitType.CAVALRY: 32, UnitData.UnitType.INFANTRY: 32}})
			await _layout_state(profile, "max-count", "Group march\n64/64 fighters")


func _layout_state(profile: String, state: String, expected: String) -> void:
	for frame: int in 4:
		await get_tree().process_frame
		hud.call("apply_mobile_layout", get_viewport().get_visible_rect().size, safe)
	var label: Label = hud.get("selection_details")
	if state == "enemy":
		_expect(not label.text.contains("march") and not label.text.contains("together"), profile + " enemy dock hides march")
	elif state == "armed-move":
		_expect(label.text.begins_with(expected), profile + " new order prompt has priority")
	else:
		_expect(label.text == expected, profile + " " + state + " actual Main payload reaches dock")
	var widths: Array[float] = []
	if state != "enemy" and state != "armed-move":
		for line: String in label.text.split("\n"):
			var width: float = label.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
			widths.append(width)
			_expect(width <= minf(96.0, label.size.x) + 0.5, profile + " complete march line fits96px: " + line)
	var panel: Control = hud.get("selection_panel")
	_expect(panel.size.y <= 80.5 and safe.grow(1.0).encloses(panel.get_global_rect()), profile + " compact dock fits safe bounds")
	records.append({"profile": profile, "state": state, "details": label.text, "widths": widths, "available": label.size.x, "dock": str(panel.get_global_rect()), "safe": str(safe)})
	if not output.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output + "/" + profile + "-" + state + ".png")


func _check_replicas(packets: Array[Dictionary]) -> void:
	NetworkSession.online = true
	for slot: int in 2:
		NetworkSession.player_slot = slot
		var client: Node = NETWORK.new()
		main.add_child(client)
		client.main = main
		client.game_map = map
		client.set_process(false)
		var packet: Dictionary = packets[slot].duplicate(true)
		client.apply_snapshot(packet)
		var own_actor: Dictionary = {}
		var enemy_actor: Dictionary = {}
		for actor: Dictionary in packet.actors:
			if int(actor.owner) == slot:
				own_actor = actor
			else:
				enemy_actor = actor
		var replica: UnitBase = client.entities[int(own_actor.id)]
		var enemy: UnitBase = client.entities[int(enemy_actor.id)]
		_expect(replica.player_owner == 0 and enemy.player_owner == 1, "actual replica remapping for slot%d" % slot)
		_expect(replica.process_mode == Node.PROCESS_MODE_DISABLED and replica.get_attack_march() == null and replica.is_attack_marching(), "own inert replica displays authority boolean without a local token")
		_expect(not enemy.is_attack_marching(), "opponent replica never infers march")
		map.selection_mgr.select_single(replica)
		_expect(str(hud.get("selection_details").text) == "Marching\ntogether", "actual remapped own replica reaches Main HUD")
		enemy_actor["marching"] = true
		enemy_actor["attack_move"] = true
		client.apply_snapshot(packet)
		_expect(not enemy.is_attack_marching() and enemy.get_meta("network_attack_march", false) == false, "injected enemy flag ignored by recipient adapter")
		for invalid: Variant in [1, "true", {}, null]:
			own_actor["marching"] = invalid
			client.apply_snapshot(packet)
			_expect(not replica.is_attack_marching(), "non-boolean flag clears earlier own status")
		own_actor["marching"] = true
		client.apply_snapshot(packet)
		_expect(replica.is_attack_marching(), "later explicit own true can restore status")
		own_actor.erase("marching")
		client.apply_snapshot(packet)
		_expect(not replica.is_attack_marching(), "missing field clears stale status")
		own_actor["marching"] = false
		client.apply_snapshot(packet)
		_expect(not replica.is_attack_marching(), "explicit authority false clears status")
		own_actor["marching"] = true
		own_actor["state"] = UnitBase.State.IDLE
		client.apply_snapshot(packet)
		_expect(not replica.is_attack_marching(), "idle state cannot display active march even with contradictory flag")
		own_actor["state"] = UnitBase.State.MOVING
		own_actor["owner"] = 1 - slot
		client.apply_snapshot(packet)
		_expect(not replica.is_attack_marching(), "changed actor ownership cannot retain previous own flag")
		own_actor["owner"] = slot
		client.apply_snapshot(packet)
		client.apply_snapshot({"actors": []})
		_expect(not replica.is_attack_marching() and replica.get_meta("network_attack_march", false) == false, "removed actor clears status before queued deletion")
		await get_tree().process_frame
		client.free()


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
