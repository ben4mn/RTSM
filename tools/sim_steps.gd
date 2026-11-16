extends RefCounted
## Fixture helper for the fixed unit simulation step (UnitBase.sim_step).
## Units think once per step on a per-unit phase, not on every rendered frame,
## so a fixture that runs the engine frame by frame and asserts after "one
## frame" should instead advance whole steps:
##   const SIM_STEPS := preload("res://tools/sim_steps.gd")
##   await SIM_STEPS.advance(get_tree(), 2)   # every unit has thought twice
## Direct `unit._process(delta)` calls are still one immediate think each.


## Run engine frames until every unit has thought `steps` more times.
static func advance(tree: SceneTree, steps: int = 1) -> void:
	var remaining: float = UnitBase.sim_step * float(maxi(1, steps))
	var guard: int = 0
	while remaining > 0.000001 and guard < 100000:
		await tree.process_frame
		remaining -= tree.root.get_process_delta_time()
		guard += 1
	# Phases are spread over a step; one more frame lets the last one land.
	await tree.process_frame


## Frames per unit think at the current frame time (1 at the match server).
static func frames_per_step(tree: SceneTree) -> int:
	var frame: float = maxf(0.000001, tree.root.get_process_delta_time())
	return maxi(1, ceili(UnitBase.sim_step / frame - 0.0001))
