extends "res://tools/wildlife_test_world.gd"
## G1: animals are simulated by their own _process. ResourceNode only processes
## while selected (static deposits), which once left every animal frozen in
## live play: an enraged boar never chased its lurer (the fixture-stepped
## regressions call _process by hand and could not see it). Here the engine
## drives the frames.


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	build_world()
	var den := Vector2i(30, 60)
	var boar: WildlifeNode = director.spawn(900, WildlifeData.BOAR, world.tile_to_world(den))
	var sheep: WildlifeNode = director.spawn(901, WildlifeData.SHEEP, world.tile_to_world(den + Vector2i(0, 6)), 0)
	await get_tree().process_frame
	expect(boar.is_processing() and sheep.is_processing(), "a spawned animal processes every frame")
	sheep.select()
	sheep.deselect()
	expect(sheep.is_processing(), "deselecting an animal keeps it processing")

	# A lurer three tiles away; the engine (not the test) steps the boar.
	var lurer: Villager = worker(den + Vector2i(-3, 0))
	boar.enrage(lurer)
	expect(boar.mood == WildlifeNode.Mood.ENRAGED, "the boar is enraged at the lurer")
	var start_gap: float = boar.global_position.distance_to(lurer.global_position)
	var frames: int = 0
	while frames < 240 and boar.global_position.distance_to(lurer.global_position) > WildlifeData.BOAR_BITE_RANGE:
		await get_tree().process_frame
		frames += 1
	var end_gap: float = boar.global_position.distance_to(lurer.global_position)
	expect(end_gap < start_gap - 20.0, "the engine-driven boar closes on its lurer (%.0f -> %.0f px in %d frames)" % [start_gap, end_gap, frames])

	# A sheep told to walk walks on its own.
	var sheep_start: Vector2 = sheep.global_position
	expect(sheep.walk_to(world.tile_to_world(den + Vector2i(4, 6))), "the sheep accepts a walk")
	for i: int in 60:
		await get_tree().process_frame
	expect(sheep.global_position.distance_to(sheep_start) > 10.0, "the engine-driven sheep walks")
	finish("wildlife_processing")
