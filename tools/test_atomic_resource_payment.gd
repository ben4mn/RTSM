extends SceneTree
## Nested production/research purchases triggered by synchronous bank signals.
var failures: Array[String] = []
var manager: Node
var nested_accepted: bool = false
var nested_attempted: bool = false
var pending_nested: Dictionary = {}
var first_bank: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	manager = root.get_node("ResourceManager")
	for costs: Array in [
		[{"food": 100, "gold": 50}, {"gold": 50}],
		[UnitData.get_unit_cost(UnitData.UnitType.INFANTRY), {"wood": 20}],
		[UnitData.get_unit_cost(UnitData.UnitType.SIEGE), {"gold": 100}],
	]:
		var outer: Dictionary = costs[0]
		pending_nested = costs[1]
		for funded: bool in [false, true]:
			var bank: Dictionary = {"food": 0, "wood": 0, "gold": 0}
			for resource: String in outer:
				bank[resource] = outer[resource]
			if funded:
				for resource: String in pending_nested:
					bank[resource] += pending_nested[resource]
			manager.initialize_player(0, bank)
			manager.initialize_player(1, {"food": 31, "wood": 42, "gold": 53})
			nested_attempted = false
			nested_accepted = false
			first_bank = {}
			manager.resources_changed.connect(_on_change)
			_expect(manager.try_spend(0, outer), "funded outer transaction succeeds")
			manager.resources_changed.disconnect(_on_change)
			_expect(nested_attempted and nested_accepted == funded, "nested purchase uses only the complete remaining bank")
			_expect(manager.get_all_resources(0) == {"food": 0, "wood": 0, "gold": 0}, "shared payments never leave negative resources")
			_expect(manager.get_all_resources(1) == {"food": 31, "wood": 42, "gold": 53}, "payments preserve the other player's bank")
			for resource: String in outer:
				_expect(int(first_bank[resource]) == int(pending_nested.get(resource, 0)) if funded else int(first_bank[resource]) == 0, "first observer sees all cost components committed")
	for failure: String in failures:
		push_error(failure)
	print("[PASS] atomic_resource_payment" if failures.is_empty() else "[FAIL] atomic_resource_payment")
	quit(0 if failures.is_empty() else 1)

func _on_change(player_id: int, _resource: String, _amount: int) -> void:
	if player_id != 0 or nested_attempted:
		return
	first_bank = manager.get_all_resources(0)
	nested_attempted = true
	nested_accepted = manager.try_spend(player_id, pending_nested)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
