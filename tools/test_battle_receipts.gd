extends Node
## Synthetic, visible/hidden combat fixtures exercise actual lethal hit signals.
## These are causal-attribution and serialization checks, not a played match.

const RECEIPTS := preload("res://scripts/main/battle_receipts.gd")
const DEBRIEF := preload("res://scripts/main/match_debrief.gd")
const ADAPTER := preload("res://scripts/network/network_match.gd")
var failures: Array[String] = []
var checks: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_bounded_receipts()
	await _test_actual_combat_and_private_snapshots()
	if failures.is_empty():
		print("[PASS] battle_receipts: %d checks; real lethal-hit signals, conservative fog, private summaries and exact civilization names" % checks)
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_bounded_receipts() -> void:
	var receipts: RefCounted = RECEIPTS.new()
	for _i in 3:
		receipts.record_loss(0, UnitData.UnitType.ARCHER, UnitData.UnitType.CAVALRY, true)
	receipts.record_loss(0, UnitData.UnitType.ARCHER, UnitData.UnitType.CAVALRY, false)
	receipts.record_loss(2, UnitData.UnitType.ARCHER, UnitData.UnitType.CAVALRY, true)
	receipts.record_loss(0, UnitData.UnitType.VILLAGER, UnitData.UnitType.CAVALRY, true)
	receipts.record_loss(0, UnitData.UnitType.ARCHER, UnitData.UnitType.SIEGE, true)
	receipts.record_loss(1, UnitData.UnitType.CAVALRY, UnitData.UnitType.INFANTRY, true)
	_expect(receipts.get_summary(0).losses_by_matchup == [[2, 3, 3]], "Only known core matchups enter local counters")
	_expect(receipts.get_summary(1).losses_by_matchup == [[3, 1, 1]], "Opposing receipts remain separately owned")
	var copy: Dictionary = receipts.get_summary(0)
	copy.losses_by_matchup[0][2] = 99
	_expect(receipts.get_summary(0).losses_by_matchup[0][2] == 3, "Published summary cannot mutate recorder")
	var lesson: Dictionary = RECEIPTS.get_counter_lesson(receipts.get_summary(0), 1, 2)
	_expect(lesson.count == 3 and lesson.unit_type == UnitData.UnitType.INFANTRY, "Three observed counter kills recommend a matching counter")
	_expect("Outriders landed final blows on 3 of your Longbows" in lesson.text and "Add Warriors" in lesson.text, "Public civilizations name victim, attacker and recommendation accurately")
	_expect(lesson.field_text == "Enemy Outriders finished 3 Longbows. Add Warriors.", "Field note summarizes the same observed final blows without claiming current enemy composition")
	_expect(RECEIPTS.get_counter_lesson(receipts.get_summary(1), 2, 1).is_empty(), "A single observed kill does not imply a repeated tactical pattern")
	var incoming: String = JSON.stringify(receipts.get_summary(0))
	var client: RefCounted = RECEIPTS.new()
	client.apply_local_summary(JSON.parse_string(incoming))
	_expect(client.get_summary(0) == receipts.get_summary(0) and client.get_summary(1).losses_by_matchup.is_empty(), "JSON roundtrip maps only own server receipt into local zero")
	client.apply_local_summary({"losses_by_matchup": [[2, 3, 999999], [2, 3, 100], [2, 3, 1.5], [0, 3, 8], [2, true, 4]]})
	_expect(client.get_summary(0).losses_by_matchup == [[2, 3, RECEIPTS.MAX_COUNT]], "Untrusted summaries clamp counts and reject duplicates, fractional numbers and non-core types")
	client.apply_local_summary({"losses_by_matchup": [[2, 3, 3], [2, 3, 3], [2, 3, 3], [2, 3, 3], [2, 3, 3], [2, 3, 3], [2, 3, 3], [2, 3, 3], [2, 3, 3], [2, 3, 3]]})
	_expect(client.get_summary(0).losses_by_matchup.is_empty(), "Oversized summary cannot grow memory or fabricate a lesson")
	for malformed: Variant in [null, "counter losses", [], {"losses_by_matchup": "invalid"}, {"losses_by_matchup": [[2, 3, -4], [2, 3, 0], [2, 3, INF], [2, 3, NAN], [2, 3], ["2", 3, 4]]}]:
		client.apply_local_summary(receipts.get_summary(0))
		client.apply_local_summary(malformed)
		_expect(client.get_summary(0).losses_by_matchup.is_empty(), "Malformed replacement receipt is rejected without retaining a stale lesson")
	_expect(RECEIPTS.get_counter_lesson({"losses_by_matchup": [[2, 1, 30]]}, 1, 0).is_empty(), "Repeated non-counter last hits do not invent a counter disadvantage")
	var strong: Dictionary = RECEIPTS.get_counter_lesson({"losses_by_matchup": [[2, 3, 4], [3, 1, 7]]}, 2, 1)
	_expect(strong.count == 7 and strong.unit_type == 2 and "Outriders" in strong.text, "One priority lesson uses the largest recorded counter matchup")
	_expect(DEBRIEF.describe({"battle": receipts.get_summary(0), "player_civilization": 1, "opponent_civilization": 2, "victory_reason": "Sacred Site held for 6:00"}) == lesson.text, "Measured battle receipt works without incomplete online learning telemetry")
	_expect(DEBRIEF.describe({"learning": {"paid_army": 3, "army_losses": 9, "army_replacements": 0}, "battle": {"losses_by_matchup": [[2, 3, 2]]}}).begins_with("Fighting troops lost 9"), "Below-threshold facts preserve existing debrief fallback")


func _test_actual_combat_and_private_snapshots() -> void:
	var manager: Node = get_node("/root/GameManager")
	get_node("/root/AudioManager").set_all_enabled(false)
	manager.guided_opening_enabled = false
	manager.selected_civilization = 1
	manager.selected_opponent_civilization = 2
	manager.selected_map_seed = 42
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	for _i in 900:
		if main.get("_building_placement") != null:
			break
		await get_tree().process_frame
	main.set_process(false)
	main.get_node("AIController").set_process(false)
	var map: Node = main.get_node("GameMap")
	var fog: Node = map.fog_of_war
	fog.set_process(false)
	var visible_position: Vector2 = main.get("_player_town_center").global_position + Vector2(20, 0)
	var hidden_position: Vector2 = map.tile_to_world(Vector2i(55, 55))
	var receipts: RefCounted = main.get("_battle_receipts")
	var attacker: UnitBase = main.call("_spawn_unit", UnitData.UnitType.CAVALRY, 1, visible_position)
	attacker.set_process(false)
	var victims: Array[UnitBase] = []
	for _i in 3:
		var defender: UnitBase = main.call("_spawn_unit", UnitData.UnitType.ARCHER, 0, visible_position)
		defender.set_process(false)
		victims.append(defender)
		Combat.deal_damage(attacker, defender)
		var before_records: Array = receipts.get_summary(0).losses_by_matchup
		_expect((0 if before_records.is_empty() else int(before_records[0][2])) == _i, "Nonlethal damage produces no death attribution")
		Combat.deal_damage(attacker, defender)
		Combat.deal_damage(attacker, defender)
		_expect(receipts.get_summary(0).losses_by_matchup[0][2] == _i + 1, "Actual lethal counter hit counted once; repeat hit on dead target ignored")
	var hidden_attacker: UnitBase = main.call("_spawn_unit", UnitData.UnitType.CAVALRY, 1, hidden_position)
	hidden_attacker.set_process(false)
	var hidden_victim: UnitBase = main.call("_spawn_unit", UnitData.UnitType.ARCHER, 0, hidden_position)
	hidden_victim.set_process(false)
	_expect(not map.is_entity_visible_to_player(hidden_attacker, 0), "Hidden fixture attacker is outside observed fog")
	Combat.resolve_unit_hit(hidden_attacker, hidden_victim, 1000.0, 1.5)
	_expect(receipts.get_summary(0).losses_by_matchup == [[2, 3, 3]], "Lethal hidden attacker never gains a classified receipt")
	var unclassified: UnitBase = main.call("_spawn_unit", UnitData.UnitType.ARCHER, 0, visible_position)
	unclassified.take_damage(1000)
	_expect(receipts.get_summary(0).losses_by_matchup == [[2, 3, 3]], "Unattributed damage never infers the most recently seen attacker")
	var guest_home: Vector2 = main.get("_player_buildings")[1][0].global_position
	var warrior: UnitBase = main.call("_spawn_unit", UnitData.UnitType.INFANTRY, 0, guest_home)
	warrior.set_process(false)
	_expect(map.is_entity_visible_to_player(warrior, 1), "Guest sees attacker through its live Town Center vision")
	for _i in 3:
		var cavalry: UnitBase = main.call("_spawn_unit", UnitData.UnitType.CAVALRY, 1, guest_home)
		cavalry.set_process(false)
		for _hit in 5:
			Combat.deal_damage(warrior, cavalry)
	var adapter: Node = ADAPTER.new()
	main.add_child(adapter)
	adapter.main = main
	adapter.game_map = map
	adapter.call("_register_server_entities")
	var first: Dictionary = adapter.call("_snapshot_for", 0)
	var second: Dictionary = adapter.call("_snapshot_for", 1)
	_expect(first.battle.losses_by_matchup == [[2, 3, 3]], "Server slot zero snapshot carries its observed losses")
	_expect(second.battle.losses_by_matchup == [[3, 1, 3]], "Server slot one cannot read slot zero battle history")
	main.get_node("StrategyController").call("_refresh")
	var field: StrategyOverview = main.get_node("HUD").get("_strategy_overview")
	_expect(field.get("_first_army_note_body").text == "Enemy Outriders finished 3 Longbows. Add Warriors.", "Actual lethal-hit history reaches the live local Army note")
	_expect(not field.panel.visible, "A live lesson does not open an unsolicited management sheet")
	main.call("_conclude_match", 1, "Sacred Site held for 6:00")
	var summary: Dictionary = main.get("match_summary_diagnostics")
	_expect(summary.battle == first.battle and summary.player_civilization == 1 and summary.opponent_civilization == 2, "Result retains observed receipts and latched public kingdom names")
	_expect("Outriders landed final blows on 3 of your Longbows" in DEBRIEF.describe(summary), "Real main combat produces precise tactical debrief")
	get_tree().paused = false
	main.free()
	get_tree().current_scene = null
	await get_tree().process_frame
	await _test_guest_terminal_snapshot(second)


func _test_guest_terminal_snapshot(server_snapshot: Dictionary) -> void:
	# Feed real server serializer output through the ordinary client packet path.
	# Transport is synthetic here; no socket/private-opponent-data claim is made.
	var session: Node = get_node("/root/NetworkSession")
	session.call("_client_packet", {"op": "matched", "slot": 1, "seed": 42, "match": 91, "civilizations": [1, 2]})
	for _i in 900:
		await get_tree().process_frame
		if is_instance_valid(session.adapter):
			break
	_expect(is_instance_valid(session.adapter), "Guest scene attaches for terminal receipt test")
	if not is_instance_valid(session.adapter):
		return
	var packet: Dictionary = JSON.parse_string(JSON.stringify(server_snapshot))
	packet["op"] = "snapshot"
	packet["match"] = 91
	session.call("_client_packet", packet)
	var client_main: Node = session.adapter.main
	client_main.get_node("StrategyController").call("_refresh")
	var field: StrategyOverview = client_main.get_node("HUD").get("_strategy_overview")
	_expect(field.get("_first_army_note_body").text == "Enemy Warriors finished 3 Outriders. Add Archers.", "Guest live note uses only the remapped recipient history and kingdom names")
	session.call("_client_packet", {"op": "ended", "winner": 0, "reason": "Surrender"})
	var result: Dictionary = client_main.match_summary_diagnostics
	_expect(result.battle.losses_by_matchup == [[3, 1, 3]], "Guest terminal result contains only its own authority battle receipt")
	_expect(result.player_civilization == 2 and result.opponent_civilization == 1, "Guest terminal names follow public slot remapping")
	_expect("Warriors landed final blows on 3 of your Outriders" in DEBRIEF.describe(result), "Guest result describes actual own cavalry losses with correct names")
	_expect("Add Archers" in DEBRIEF.describe(result), "Guest counter recommendation uses its own civilization")
	var screen: Node = client_main.get_node("GameOverScreen")
	var label: Label = screen.get("_debrief_label")
	_expect(label.visible and "Warriors landed final blows on 3 of your Outriders" in label.text, "Actual online result screen visibly presents its authority battle lesson")
	_expect(screen.summary_diagnostics.debrief == label.text and not screen.score_bar.visible, "Online diagnostic matches displayed text while opponent comparisons stay private")
	var without_receipt: Dictionary = result.duplicate(true)
	without_receipt["battle"] = {}
	without_receipt["learning"] = {"paid_army": 0, "worker_losses": 99, "worker_replacements": 0}
	screen.show_defeat(without_receipt)
	_expect(not label.visible and label.text.is_empty(), "Online screen never falls back to incomplete local learning telemetry")
	session.leave_match()
	get_tree().paused = false
	client_main.free()
	get_tree().current_scene = null
	await get_tree().process_frame
	await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("[FAIL] battle_receipts: " + message)
