extends "res://tools/probe_ai_compact_paid_match.gd"
## Simulation comparison only: ordinary paid AI transactions for both sides.
func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--workers="):
			Engine.set_meta("balance_starting_villagers", int(argument.trim_prefix("--workers=")))
	super._ready()

var _last_stock_sample: float = -120.0
func _measure() -> void:
	super._measure()
	if GameManager.game_time - _last_stock_sample < 120.0: return
	_last_stock_sample = GameManager.game_time
	if not stats.has("natural_stock_samples"):
		stats["natural_stock_samples"] = []
		stats["starting_workers"] = UnitData.get_starting_villager_count()
	var stock: Dictionary = {"food": 0, "wood": 0, "gold": 0}
	for node: Node in match_scene.game_map.resource_nodes.values():
		if is_instance_valid(node): stock[node.resource_type] += node.remaining
	stats["natural_stock_samples"].append({"time": GameManager.game_time, "whole_map_remaining_audit_only": stock})
