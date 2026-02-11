extends Node
## Global resource manager. Autoloaded as ResourceManager.
##
## Tracks food, wood, and gold for each player. Emits signals on changes.

signal resources_changed(player_id: int, resource_type: String, new_amount: int)
signal resources_insufficient(player_id: int, missing: Dictionary)

enum ResourceType {
	FOOD,
	WOOD,
	GOLD
}

const RESOURCE_NAMES: Array[String] = ["food", "wood", "gold"]

const STARTING_RESOURCES: Dictionary = {
	"food": 200,
	"wood": 200,
	"gold": 100,
}

# player_id -> { "food": int, "wood": int, "gold": int }
var _player_resources: Dictionary = {}


func _ready() -> void:
	pass


func initialize_player(player_id: int, starting: Dictionary = {}) -> void:
	var resources: Dictionary = STARTING_RESOURCES.duplicate()
	if not starting.is_empty():
		for key in starting:
			if resources.has(key):
				resources[key] = starting[key]
	_player_resources[player_id] = resources


func get_resource(player_id: int, resource_type: String) -> int:
	if _player_resources.has(player_id) and _player_resources[player_id].has(resource_type):
		return _player_resources[player_id][resource_type]
	return 0


func get_all_resources(player_id: int) -> Dictionary:
	if _player_resources.has(player_id):
		return _player_resources[player_id].duplicate()
	return { "food": 0, "wood": 0, "gold": 0 }


func add_resource(player_id: int, resource_type: String, amount: int) -> void:
	if not _player_resources.has(player_id):
		return
	if not _player_resources[player_id].has(resource_type):
		return

	_player_resources[player_id][resource_type] += amount
	resources_changed.emit(player_id, resource_type, _player_resources[player_id][resource_type])


func can_afford(player_id: int, cost: Dictionary) -> bool:
	if not _player_resources.has(player_id):
		return false

	for resource_type in cost:
		if cost[resource_type] <= 0:
			continue
		if get_resource(player_id, resource_type) < cost[resource_type]:
			return false
	return true


func try_spend(player_id: int, cost: Dictionary) -> bool:
	## Attempts to spend resources. Returns true if successful, false if insufficient.
	if not can_afford(player_id, cost):
		var missing: Dictionary = get_missing_resources(player_id, cost)
		resources_insufficient.emit(player_id, missing)
		return false

	for resource_type in cost:
		if cost[resource_type] <= 0:
			continue
		_player_resources[player_id][resource_type] -= cost[resource_type]
		resources_changed.emit(player_id, resource_type, _player_resources[player_id][resource_type])

	return true


func refund(player_id: int, cost: Dictionary) -> void:
	## Refunds resources (e.g., when cancelling a building or unit).
	for resource_type in cost:
		if cost[resource_type] > 0:
			add_resource(player_id, resource_type, cost[resource_type])


func get_missing_resources(player_id: int, cost: Dictionary) -> Dictionary:
	var missing: Dictionary = {}
	for resource_type in cost:
		if cost[resource_type] <= 0:
			continue
		var current: int = get_resource(player_id, resource_type)
		if current < cost[resource_type]:
			missing[resource_type] = cost[resource_type] - current
	return missing


func reset() -> void:
	_player_resources.clear()
