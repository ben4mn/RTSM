extends RefCounted
## Instrumented frozen-copy probes only. Nested buckets are inclusive.
static var enabled: bool = false
static var frame: Dictionary = {}

static func record(label: String, elapsed_usec: int) -> void:
	if not enabled: return
	if not frame.has(label): frame[label] = {"us": 0, "calls": 0, "max_us": 0}
	frame[label].us += elapsed_usec
	frame[label].calls += 1
	frame[label].max_us = maxi(frame[label].max_us, elapsed_usec)

static func take_frame() -> Dictionary:
	var result: Dictionary = frame
	frame = {}
	return result
