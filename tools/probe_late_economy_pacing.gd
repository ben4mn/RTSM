extends "res://tools/probe_ai_compact_paid_match.gd"
## Read-only economy observations on the existing paid two-AI match harness.
## Natural victories remain enabled. No extra resources, forced orders or units.
var _late_last_sample: float = -60.0
var _late_seen: Dictionary = {}
var _late_trade_delivered: Dictionary = {}
var _late_events: Array[Dictionary] = []
var _late_samples: Array[Dictionary] = []
var _late_totals: Array[Dictionary] = [
	{"farm_foundations": 0, "farms_completed": 0, "post_foundations": 0, "posts_completed": 0, "traders_queued": 0, "traders_cancelled": 0, "traders_born": 0, "trade_deliveries": 0, "trade_gold": 0, "food_deposited_with_farm_job": 0},
	{"farm_foundations": 0, "farms_completed": 0, "post_foundations": 0, "posts_completed": 0, "traders_queued": 0, "traders_cancelled": 0, "traders_born": 0, "trade_deliveries": 0, "trade_gold": 0, "food_deposited_with_farm_job": 0},
]
var _late_wall_start: int = 0
var _late_last_measure: float = -1.0
var _late_observer_usec: int = 0
var _late_measure_calls: int = 0
var _late_frames: int = 0
var _late_sacred: Array[Dictionary] = []
var _late_sacred_connected: bool = false
var _late_sacred_key: String = ""
var _late_performance: Dictionary = {}
var _sacred_continuation: bool = false
var _continuation_adapter: RefCounted

func _run() -> void:
	_late_wall_start = Time.get_ticks_msec()
	_sacred_continuation = "--sacred-continuation" in OS.get_cmdline_user_args()
	Engine.set_meta("balance_starting_villagers", 3)
	stats["late_economy"] = {
		"scope": ("Counterfactual Sacred-only continuation of normal paid AI policies; Town Center defeat retained. " if _sacred_continuation else "Read-only observations of normal paid AI policies on both sides. Natural victories are unchanged. ") + "Game time is simulated, not human/browser duration. Whole-map stock is audit-only and never supplied to either policy.",
		"food_attribution": "Food delivery while the worker's active gather target is an owned Farm. Reorders can change the target of previously carried food; this is job-at-delivery evidence, not an exact harvest-origin ledger.",
		"payment_scope": "Foundations originate from existing paid Main construction handlers. Trader queue signals observe accepted normal-price purchases; cancellations are separate. No resources, actors or outcomes are injected.",
		"events": _late_events, "samples": _late_samples, "totals": _late_totals,
		"starting_workers": UnitData.get_starting_villager_count(),
		"sacred_transitions": _late_sacred,
		"performance": _late_performance,
		"measurement_cadence": "Expensive labor/near-enemy summaries sampled at5Hz game time; birth/delivery observations remain every frame and Sacred phase/ticking transitions use the real status signal. Event-driven damage/deposit accounting remains active every frame.",
		"autosave_disabled_for_pacing": SoloSave.get_script().resource_path == "res://tools/fixtures/pacing_solo_save.gd",
		"sacred_continuation": {"enabled": _sacred_continuation, "attached": false, "scope": "Counterfactual: only Sacred conclusion suppressed; natural Town Center defeat remains. No resource, unit, AI policy or timer changes. This is not a natural match-duration sample." if _sacred_continuation else "Natural victory rules unchanged."},
	}
	await super._run()

func _measure() -> void:
	var started: int = Time.get_ticks_usec()
	_late_frames += 1
	if not _late_sacred_connected:
		if _sacred_continuation:
			_continuation_adapter = preload("res://tools/fixtures/pacing_sacred_continuation.gd").new()
			var attached: bool = _continuation_adapter.attach(match_scene)
			stats.late_economy.sacred_continuation.attached = attached
			assert(attached, "Continuation must intercept only the ordinary Sacred callback")
			stats.late_economy.sacred_continuation.blocked_sacred_windows = _continuation_adapter.windows
		match_scene.game_map.sacred_site.status_changed.connect(_observe_sacred_transition)
		_late_sacred_connected = true
		_observe_sacred_transition()
	_observe_late_actors()
	if GameManager.game_time - _late_last_measure >= 0.2:
		_late_last_measure = GameManager.game_time
		_late_measure_calls += 1
		super._measure()
		_sample_late(false)
	_late_observer_usec += Time.get_ticks_usec() - started

func _observe_sacred_transition() -> void:
	var site: Node = match_scene.game_map.sacred_site
	var status: Dictionary = site.get_status()
	var key: String = "%s:%d:%s:%s" % [status.phase, status.owner, status.clock_ticking, status.garrison_paused]
	if key == _late_sacred_key: return
	_late_sacred_key = key
	var event: Dictionary = {"time": GameManager.game_time, "hold_elapsed": site.victory_timer}
	event.merge(status)
	_late_sacred.append(event)
	print("[SACRED_TRANSITION] ", JSON.stringify(event))

func _event(owner: int, kind: String, actor: Node, extra: Dictionary = {}) -> void:
	var entry: Dictionary = {"time": GameManager.game_time, "owner": owner, "kind": kind, "id": actor.get_instance_id()}
	entry.merge(extra)
	_late_events.append(entry)
	print("[LATE_EVENT] ", JSON.stringify(entry))

func _observe_late_actors() -> void:
	for owner: int in [0, 1]:
		for building: BuildingBase in match_scene._player_buildings[owner]:
			if not is_instance_valid(building) or building.building_type not in [BuildingData.BuildingType.FARM, BuildingData.BuildingType.TRADE_POST] or _late_seen.has(building.get_instance_id()): continue
			_late_seen[building.get_instance_id()] = true
			var kind: String = "farm" if building.building_type == BuildingData.BuildingType.FARM else "post"
			_late_totals[owner][kind + "_foundations"] += 1
			_event(owner, kind + "_foundation", building, {"normal_cost": BuildingData.get_building_cost(building.building_type), "position": [building.position.x, building.position.y]})
			building.construction_complete.connect(_late_completed)
			building.building_destroyed.connect(_late_destroyed)
			if building.state == BuildingBase.State.ACTIVE: _late_completed(building)
			var queue: ProductionQueue = building.get_production_queue() as ProductionQueue
			if queue != null:
				queue.unit_queued.connect(_late_queued.bind(building))
				queue.unit_cancelled.connect(_late_cancelled.bind(building))
		for unit: UnitBase in match_scene._player_units[owner]:
			if not is_instance_valid(unit): continue
			if not _late_seen.has(unit.get_instance_id()):
				_late_seen[unit.get_instance_id()] = true
				if unit is Villager: (unit as Villager).resource_deposited.connect(_late_food_deposit.bind(unit))
				if unit is Trader:
					_late_totals[owner].traders_born += 1
					_event(owner, "trader_born", unit)
					unit.unit_died.connect(_late_trader_died)
			if unit is Trader: _observe_trade_delivery(unit)

func _late_completed(building: BuildingBase) -> void:
	var key: String = "farms" if building.building_type == BuildingData.BuildingType.FARM else "posts"
	_late_totals[building.player_owner][key + "_completed"] += 1
	_event(building.player_owner, key + "_completed", building)

func _late_destroyed(building: BuildingBase) -> void:
	_event(building.player_owner, "farm_destroyed" if building.building_type == BuildingData.BuildingType.FARM else "post_destroyed", building)

func _late_queued(type: int, building: BuildingBase) -> void:
	if type != UnitData.UnitType.TRADER: return
	_late_totals[building.player_owner].traders_queued += 1
	_event(building.player_owner, "trader_paid_queue", building, {"normal_cost": UnitData.get_unit_cost(type)})

func _late_cancelled(type: int, building: BuildingBase) -> void:
	if type != UnitData.UnitType.TRADER: return
	_late_totals[building.player_owner].traders_cancelled += 1
	_event(building.player_owner, "trader_cancelled_refunded", building)

func _late_food_deposit(resource: String, amount: int, worker: Villager) -> void:
	if resource == "food" and is_instance_valid(worker.gather_target) and worker.gather_target is BuildingBase and worker.gather_target.building_type == BuildingData.BuildingType.FARM:
		_late_totals[worker.player_owner].food_deposited_with_farm_job += amount

func _observe_trade_delivery(trader: Trader) -> void:
	var prior: int = int(_late_trade_delivered.get(trader.get_instance_id(), 0))
	if trader.delivered_gold > prior:
		var amount: int = trader.delivered_gold - prior
		_late_totals[trader.player_owner].trade_gold += amount
		_late_totals[trader.player_owner].trade_deliveries += 1
		_event(trader.player_owner, "trade_delivery", trader, {"gold": amount, "lifetime_gold": trader.delivered_gold})
	_late_trade_delivered[trader.get_instance_id()] = trader.delivered_gold

func _late_trader_died(unit: UnitBase) -> void:
	_observe_trade_delivery(unit as Trader)
	_event(unit.player_owner, "trader_died", unit)

func _sample_late(force: bool) -> void:
	if not force and GameManager.game_time - _late_last_sample < 60.0: return
	_late_last_sample = GameManager.game_time
	var stock: Dictionary = {"food": 0, "wood": 0, "gold": 0}
	for node: Node in match_scene.game_map.resource_nodes.values():
		if is_instance_valid(node): stock[node.resource_type] += node.remaining
	var sample: Dictionary = {"time": GameManager.game_time, "whole_map_remaining_audit_only": stock, "players": []}
	for owner: int in [0, 1]:
		var farms: int = 0
		var staffed: int = 0
		var posts: int = 0
		var towns: int = 0
		var traders: Array[Dictionary] = []
		for building: BuildingBase in match_scene._player_buildings[owner]:
			if not is_instance_valid(building) or building.state != BuildingBase.State.ACTIVE: continue
			if building.building_type == BuildingData.BuildingType.FARM:
				farms += 1
				staffed += int(is_instance_valid(building.get_assigned_worker()))
			if building.building_type == BuildingData.BuildingType.TRADE_POST: posts += 1
			if building.building_type == BuildingData.BuildingType.TOWN_CENTER: towns += 1
		for unit: UnitBase in match_scene._player_units[owner]:
			if not is_instance_valid(unit) or not unit is Trader or unit.current_state == UnitBase.State.DEAD: continue
			traders.append({"status": unit.get_trade_status(), "cargo": unit.carried_gold, "delivered": unit.delivered_gold, "route_active": unit.trade_route_active})
		var brain: AIController = human_bot if owner == 0 else match_scene.ai_controller
		sample.players.append({"age": GameManager.get_player_age(owner), "bank": ResourceManager.get_all_resources(owner), "active_farms": farms, "staffed_farms": staffed, "active_posts": posts, "traders": traders, "lifetime": _late_totals[owner].duplicate(), "trade_policy": {"clock": brain._game_time, "next_check": brain._next_trade_decision, "under_pressure": brain._is_under_pressure, "worker_recovery": brain._needs_compact_worker_recovery(), "cursor": brain._trade_site_cursor}})
		if brain.has_method("_get_gold_bank_target"):
			sample.players[-1].trade_policy.merge({"gold_bank_target": brain._get_gold_bank_target(), "capital": brain._trade_capital.duplicate(), "capital_until": brain._trade_capital_until})
		sample.players[-1]["active_towns"] = towns
		if brain.has_method("get_opening_strategy"):
			sample.players[-1]["opening_strategy"] = brain.get_opening_strategy()
	_late_samples.append(sample)
	print("[LATE_SAMPLE] ", JSON.stringify(sample))
	_late_performance.merge({"wall_seconds": float(Time.get_ticks_msec() - _late_wall_start) / 1000.0, "game_seconds": GameManager.game_time, "observer_usec": _late_observer_usec, "measure_calls": _late_measure_calls, "frames": _late_frames, "time_scale": Engine.time_scale, "physics_ticks_per_second": Engine.physics_ticks_per_second}, true)
	if _sacred_continuation: stats.late_economy.sacred_continuation.blocked_tick_count = _continuation_adapter.blocked_tick_count
	# Keep useful data even if a host timeout interrupts a genuinely long match.
	# This is a compact observer receipt, not a restorable gameplay checkpoint.
	var partial: Dictionary = stats.duplicate()
	partial.merge({"phase": "terminal" if force else "running", "time": GameManager.game_time, "seed": match_scene.game_map.map_seed, "map_archetype": map_archetype, "age_times": match_scene._age_reached_at.duplicate(true)}, true)
	var file := FileAccess.open(result_path + ".partial.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(partial))
		file.close()

func _finalize_cadence() -> void:
	_observe_late_actors()
	_sample_late(true)
	stats.late_economy.wall_seconds = float(Time.get_ticks_msec() - _late_wall_start) / 1000.0
	stats.late_economy.actual_map_seed = match_scene.game_map.map_seed
	super._finalize_cadence()

func _get_runtime_source_hashes() -> Dictionary:
	var hashes: Dictionary = super._get_runtime_source_hashes()
	hashes["tools/probe_late_economy_pacing.gd"] = get_script().get_source_code().sha256_text()
	hashes["scenes/buildings/trade_post.tscn"] = FileAccess.get_file_as_string("res://scenes/buildings/trade_post.tscn").sha256_text()
	return hashes
