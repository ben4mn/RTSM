class_name PerfProbe
extends RefCounted
## Opt-in scoped timers for tools/bench_scale. `on` stays false in every shipped
## path, so an instrumented site costs one static bool read.
##   var _pp: int = Time.get_ticks_usec() if PerfProbe.on else 0
##   ...
##   if PerfProbe.on: PerfProbe.add(&"unit.think", _pp)
## Times are inclusive: a dotted child ("unit.path") is also inside its parent.

static var on: bool = false
static var usec: Dictionary = {}
static var calls: Dictionary = {}


## Returns the current tick so consecutive scopes can chain.
static func add(key: StringName, started_usec: int) -> int:
	var now: int = Time.get_ticks_usec()
	usec[key] = int(usec.get(key, 0)) + now - started_usec
	calls[key] = int(calls.get(key, 0)) + 1
	return now


static func reset() -> void:
	usec.clear()
	calls.clear()
