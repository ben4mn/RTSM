extends Node
## Read-only integration observation: actual worker clock and exclusion methods,
## controlled current-visible reachable resource, then production AI lookup.

const SEARCH_FIXTURE: Script = preload("res://tools/test_ai_resource_deficit_search.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	GameManager.initialize_game(2)
	var map := SEARCH_FIXTURE.SearchMap.new()
	add_child(map)
	var resource := preload("res://scenes/map/resource_node.tscn").instantiate() as ResourceNode
	resource.tile_position = Vector2i(25, 10)
	resource.position = map.tile_to_world(resource.tile_position)
	map.add_child(resource)
	map.resources.append(resource)
	var worker := preload("res://scenes/units/villager.tscn").instantiate() as Villager
	worker.player_owner = 1
	worker.position = map.tile_to_world(Vector2i(33, 6))
	map.add_child(worker)
	worker.set_process(false)
	var ai := AIController.new()
	ai.player_id = 1
	ai.game_map = map
	add_child(ai)
	ai.start_ai(Vector2i(33, 6), worker.position)
	(ai.get("_decision_timer") as Timer).stop()
	ai.set_process(false)
	var cache: Dictionary = worker.get("_unreachable_resource_ids_until") as Dictionary
	worker.call("_remember_unreachable_target", resource, cache)
	var initial_excluded: bool = ai.call("_find_resource_for_villager", "wood", worker) == null
	for _frame: int in range(301):
		worker.call("_process", 1.0 / 60.0)
	var excluded_after_expiry: bool = ai.call("_find_resource_for_villager", "wood", worker) == null
	var clock: float = float(worker.get("_simulation_elapsed_seconds"))
	var recorded_deadline: float = float(cache.get(resource.get_instance_id(), -1.0))
	worker.call("_prune_expired_unreachable_targets", cache)
	var target_after_explicit_prune: bool = ai.call("_find_resource_for_villager", "wood", worker) == resource
	var report: Dictionary = {"scope": "controlled currently visible/reachable resource, actual idle worker simulation clock and production AI lookup; no paid match or cargo claims", "initial_excluded": initial_excluded, "worker_simulation_seconds": clock, "cached_deadline_seconds": recorded_deadline, "ai_excludes_after_expiry_without_prune": excluded_after_expiry, "ai_resolves_after_explicit_worker_prune": target_after_explicit_prune, "source_sha256": {"ai": (load("res://scripts/ai/ai_controller.gd") as Script).source_code.sha256_text(), "unit_base": (load("res://scripts/units/unit_base.gd") as Script).source_code.sha256_text(), "villager": (load("res://scripts/units/villager.gd") as Script).source_code.sha256_text(), "probe": get_script().source_code.sha256_text()}}
	var path: String = "res://output/evolution/simulation-cooldowns-20261010/independent-ai-cache-expiry.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("[OBSERVED] ai_unreachable_cache_expiry ", JSON.stringify(report))
	get_tree().quit(0)
