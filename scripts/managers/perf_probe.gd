class_name PerfProbe
extends RefCounted
## Opt-in scoped timers for tools/bench_scale and `PocketDev.cmd('perf', ...)`.
## `on` stays false in every shipped path, so an instrumented site costs one
## static bool read.
##   var _pp: int = Time.get_ticks_usec() if PerfProbe.on else 0
##   ...
##   if PerfProbe.on: PerfProbe.add(&"unit.think", _pp)
## Times are inclusive: a dotted child ("unit.path") is also inside its parent.
##
## Frame phases (browser profiling): `frame_begin` / `frame_process_end` are
## called by marker nodes that process first and last in the frame, and the
## RenderingServer pre/post draw signals bracket the render submission. Each
## frame then splits into process (every _process / internal process), late
## (deferred calls after process: queued `_draw`s, signals), render (canvas
## culling, batching and GL submission) and rest (physics, input, browser idle).

static var on: bool = false
static var usec: Dictionary = {}
static var calls: Dictionary = {}
static var counts: Dictionary = {}

static var _begin_usec: int = 0
static var _process_end_usec: int = 0
static var _pre_draw_usec: int = 0
static var _post_draw_usec: int = 0
static var frame_wall := PackedFloat32Array()
static var frame_process := PackedFloat32Array()
static var frame_late := PackedFloat32Array()
static var frame_render := PackedFloat32Array()
static var frame_draw_calls := PackedInt32Array()
static var frame_objects := PackedInt32Array()
static var frame_primitives := PackedInt32Array()
const SPIKE_MS: float = 12.0
static var spike_frames: int = 0
static var spike_usec: Dictionary = {}
static var _frame_snapshot: Dictionary = {}


## Returns the current tick so consecutive scopes can chain.
static func add(key: StringName, started_usec: int) -> int:
	var now: int = Time.get_ticks_usec()
	usec[key] = int(usec.get(key, 0)) + now - started_usec
	calls[key] = int(calls.get(key, 0)) + 1
	return now


## Counts an event without timing it (e.g. redraws per frame).
static func count(key: StringName, amount: int = 1) -> void:
	counts[key] = int(counts.get(key, 0)) + amount


static func reset() -> void:
	usec.clear()
	calls.clear()
	counts.clear()
	_begin_usec = 0
	_process_end_usec = 0
	_pre_draw_usec = 0
	_post_draw_usec = 0
	frame_wall.clear()
	frame_process.clear()
	frame_late.clear()
	frame_render.clear()
	frame_draw_calls.clear()
	frame_objects.clear()
	frame_primitives.clear()
	spike_frames = 0
	spike_usec.clear()
	_frame_snapshot.clear()


static func frame_begin() -> void:
	var now: int = Time.get_ticks_usec()
	if _begin_usec > 0 and _process_end_usec > _begin_usec:
		frame_wall.append(float(now - _begin_usec) / 1000.0)
		frame_process.append(float(_process_end_usec - _begin_usec) / 1000.0)
		var drew: bool = _pre_draw_usec >= _process_end_usec and _post_draw_usec >= _pre_draw_usec
		frame_late.append(float((_pre_draw_usec if drew else now) - _process_end_usec) / 1000.0)
		frame_render.append(float(_post_draw_usec - _pre_draw_usec) / 1000.0 if drew else 0.0)
		frame_draw_calls.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		frame_objects.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
		frame_primitives.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		# Spike attribution: which probes grew during frames whose process
		# phase exceeded SPIKE_MS.
		if frame_process[frame_process.size() - 1] > SPIKE_MS:
			spike_frames += 1
			for key: StringName in usec:
				spike_usec[key] = int(spike_usec.get(key, 0)) + int(usec[key]) - int(_frame_snapshot.get(key, 0))
		_frame_snapshot = usec.duplicate()
	_begin_usec = now


static func frame_process_end() -> void:
	_process_end_usec = Time.get_ticks_usec()


static func frame_pre_draw() -> void:
	_pre_draw_usec = Time.get_ticks_usec()


static func frame_post_draw() -> void:
	_post_draw_usec = Time.get_ticks_usec()


static func percentiles(values: Variant) -> Dictionary:
	var sorted: Array = Array(values)
	if sorted.is_empty():
		return {}
	sorted.sort()
	var total: float = 0.0
	for value: Variant in sorted:
		total += float(value)
	var n: int = sorted.size()
	return {
		"mean": snappedf(total / float(n), 0.01),
		"p50": snappedf(float(sorted[n / 2]), 0.01),
		"p95": snappedf(float(sorted[mini(n - 1, int(n * 0.95))]), 0.01),
		"max": snappedf(float(sorted[n - 1]), 0.01),
	}
