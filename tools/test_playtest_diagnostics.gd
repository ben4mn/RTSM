extends Node
## Bounds and report continuity using a separate storage-free instance.

const DiagnosticsScript = preload("res://scripts/managers/playtest_diagnostics.gd")
var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_state: int = GameManager.current_state
	var paused_before: bool = get_tree().paused
	var resource_bank: Dictionary = ResourceManager.get_all_resources(0)
	var diagnostics: Node = DiagnosticsScript.new()
	add_child(diagnostics)
	diagnostics.reset_for_test()
	var session_id: String = diagnostics.get_report()["session_id"]
	_expect(session_id.length() == 32, "session identifier must be random and anonymous")
	var loaded_revision: String = str(ProjectSettings.get_setting("application/config/playtest_revision", "development"))
	diagnostics.start_match({"seed": 101, "viewport": Vector2i(844, 390), "ui_scale": 1.15, "build": {"revision": "fixture", "runtime_revision": "incorrect-shell-revision"}})
	for index: int in range(700):
		diagnostics.record_event("touch_release", {"contact": index % 3, "hit": "worker", "position": Vector2(140.2, 160.8)})
	var report: Dictionary = diagnostics.get_report()
	_expect(report["events"].size() == 600, "ring must stop at 600 events")
	_expect(int(report["dropped_count"]) == 101, "discarded event count must include match start")
	_expect(int(report["counters"]["touch_release"]) == 700, "counters must survive ring wrap")
	_expect(int(report["events"][0]["sequence"]) == 102 and int(report["events"][-1]["sequence"]) == 701, "retained sequences must remain monotonic")
	_expect(report["context"]["viewport"] == [844.0, 390.0] and report["build"]["revision"] == "fixture", "match/build context must serialize without engine values")
	_expect(not report["context"].has("build"), "build belongs in the report build field")
	_expect(report["build"]["runtime_revision"] == loaded_revision and report["build"]["game_version"] == str(ProjectSettings.get_setting("application/config/version")), "loaded runtime revision/version must remain authoritative")
	var previous_elapsed: int = -1
	for event: Dictionary in report["events"]:
		_expect(int(event["elapsed_ms"]) >= previous_elapsed and int(event["utc_ms"]) > 0, "events require a monotonic real-time clock and wall-clock timestamp")
		previous_elapsed = int(event["elapsed_ms"])
	var marker_report: Dictionary = diagnostics.mark_report("missed worker tap")
	var marker_sequence: int = int(marker_report["problem"]["marker"]["sequence"])
	_expect(marker_report["problem"]["preceding_events"].size() == 120, "problem window must retain 120 prior events")
	for index: int in range(900):
		diagnostics.record_event("scroll", {"phase": "pan", "distance": index})
	# Scene/match context changes must not discard the session or report evidence.
	diagnostics.start_match({"seed": 202, "state": "new_match"})
	report = diagnostics.get_report()
	_expect(report["session_id"] == session_id, "scene/match transition replaced session identity")
	_expect(report["context"]["seed"] == 202 and report["problem"]["context"]["seed"] == 101, "marker must preserve its original match context")
	_expect(int(report["problem"]["marker"]["sequence"]) == marker_sequence, "ring wrap lost problem marker")
	_expect(report["problem"]["following_events"].size() == 80, "problem follow-up must have a fixed bound")
	_expect(int(report["problem"]["following_events"][0]["sequence"]) == marker_sequence + 1, "problem must retain the first subsequent input")
	_expect(int(report["problem"]["following_events"][-1]["sequence"]) == marker_sequence + 80, "problem follow-up must stop after eighty events")
	_expect(int(report["events"][0]["sequence"]) > marker_sequence, "fixture must actually wrap past the marker")
	# Getter must return a copy; UI inspection cannot mutate stored history.
	report["events"].clear()
	report["context"]["seed"] = -1
	_expect(diagnostics.get_report()["events"].size() == 600 and diagnostics.get_report()["context"]["seed"] == 202, "report getter exposed mutable storage")
	var fields: Dictionary = {"name": "Villager", "player_name": "private", "email": "person@example.test", "cookie": "private", "ip_address": "private", "position": Vector2(20.2, 41.9), "target": "worker", "note": "person@example.test", "object": self, "nonfinite": NAN, "nested": {"token": "private", "okay": true}}
	var huge: Array = []
	for index: int in range(100):
		huge.append(index)
	fields["array"] = huge
	fields["label"] = "a".repeat(500)
	diagnostics.record_event("tap_result", fields)
	var sanitized: Dictionary = diagnostics.get_report()["events"][-1]["fields"]
	_expect(not sanitized.has("player_name") and not sanitized.has("email") and not sanitized.has("cookie") and not sanitized.has("ip_address"), "private fields were retained")
	_expect(sanitized["name"] == "Villager", "game-role candidate name should remain available for debugging")
	_expect(not sanitized.has("object") and not sanitized.has("nonfinite"), "engine objects/nonfinite values were retained")
	_expect(sanitized["note"] == "[redacted]" and sanitized["position"] == [20.0, 42.0], "strings and positions need bounded safe conversion")
	_expect(sanitized["array"].size() == 24 and sanitized["label"].length() == 192 and not sanitized["nested"].has("token"), "nested values must remain bounded and sanitized")
	var many_fields: Dictionary = {}
	for index: int in range(100):
		many_fields["field_%d" % index] = index
	diagnostics.record_event("wide_fields", many_fields)
	_expect(diagnostics.get_report()["events"][-1]["fields"].size() == 24, "top-level fields must have a fixed bound")
	for index: int in range(100):
		diagnostics.record_event("custom_%d" % index)
	_expect(diagnostics.get_report()["counters"].size() <= 64, "event-kind counters must have a fixed bound")
	var serialized: String = JSON.stringify(diagnostics.get_report())
	var decoded: Variant = JSON.parse_string(serialized)
	_expect(decoded is Dictionary and decoded["events"].size() == 600, "diagnostic report must round-trip as JSON")
	var previous_session: String = diagnostics.get_report()["session_id"]
	diagnostics.reset_for_test()
	_expect(diagnostics.get_report()["session_id"] != previous_session, "anonymous identifier must change for a fresh session")
	diagnostics.record_event("offline_input", {"active": true})
	_expect(diagnostics.get_report()["events"].size() == 1, "absent Web bridge prevented local logging")
	_expect(GameManager.current_state == game_state and get_tree().paused == paused_before and ResourceManager.get_all_resources(0) == resource_bank, "diagnostics changed gameplay state, pause, or resources")
	diagnostics.free()
	for failure: String in _failures:
		push_error("[FAIL] playtest_diagnostics: " + failure)
	if _failures.is_empty():
		print("[PASS] playtest_diagnostics: bounded history/counters, anonymous session, match context, retained before/after marker, safe JSON, offline bridge")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
