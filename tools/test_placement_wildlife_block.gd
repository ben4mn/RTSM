extends Node
## G1: a building cannot be placed on top of an animal or a carcass with food
## left; clear ground right beside it stays valid.

var _failures: Array[String] = []


class FakeGameMap extends Node2D:
	var animals: Array[Node2D] = []

	func world_to_tile(world_pos: Vector2) -> Vector2i:
		return Vector2i(floori(world_pos.x / 10.0), floori(world_pos.y / 10.0))

	func is_tile_visible_to_player(_tile: Vector2i, _player_id: int) -> bool:
		return true

	func is_tile_buildable(_tile: Vector2i) -> bool:
		return true

	func get_wildlife_nodes(_kind: String = "") -> Array[Node2D]:
		return animals


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioManager.set_all_enabled(false)
	var game_map := FakeGameMap.new()
	add_child(game_map)
	var placement := BuildingPlacement.new()
	game_map.add_child(placement)
	var sheep := Node2D.new()
	sheep.global_position = Vector2(55.0, 55.0)  # tile (5, 5)
	game_map.add_child(sheep)
	game_map.animals.append(sheep)
	await get_tree().process_frame

	var house_world := Vector2(45.0, 45.0)  # tile (4, 4): a 2x2 footprint covers (5, 5)
	_expect(not placement.revalidate_confirmation(BuildingData.BuildingType.HOUSE, house_world, 0), "a House cannot be placed over a sheep")
	_expect(placement.get_invalid_reason() == "Animal in the way", "the reason names the animal (got %s)" % placement.get_invalid_reason())
	var beside := Vector2(75.0, 75.0)  # tile (7, 7): clear of the sheep
	_expect(placement.revalidate_confirmation(BuildingData.BuildingType.HOUSE, beside, 0), "clear ground beside the animal stays valid (%s)" % placement.get_invalid_reason())
	game_map.animals.clear()
	_expect(placement.revalidate_confirmation(BuildingData.BuildingType.HOUSE, house_world, 0), "once the animal is gone the spot is valid again")

	game_map.free()
	if _failures.is_empty():
		print("[PASS] placement_wildlife_block: footprints over animals are refused with a named reason; clear ground stays valid")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[FAIL] placement_wildlife_block: %s" % failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
