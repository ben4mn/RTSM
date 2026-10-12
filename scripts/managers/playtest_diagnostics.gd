extends Node
## Small, anonymous input history. Diagnostic data never drives gameplay.

const SCHEMA_VERSION: int = 1
const MAX_EVENTS: int = 600
const MAX_EVENT_KINDS: int = 64
const PROBLEM_PRECEDING_EVENTS: int = 120
const PROBLEM_FOLLOWING_EVENTS: int = 80
const MAX_FIELDS: int = 24
const MAX_ARRAY_ITEMS: int = 24
const MAX_STRING_LENGTH: int = 192
const MAX_VALUES_PER_RECORD: int = 128
const SAVE_INTERVAL_MSEC: int = 5000
const SNAPSHOT_PATH: String = "user://playtest-diagnostics.json"
const PRIVATE_KEYS: Array[String] = [
	"username", "player_name", "real_name", "email", "address", "phone",
	"cookie", "cookies", "token", "authorization", "password", "ip", "ip_address",
	"latitude", "longitude", "location", "device_id", "user_id",
]

var _session_id: String = ""
var _started_utc: String = ""
var _started_msec: int = 0
var _next_sequence: int = 1
var _events: Array[Dictionary] = []
var _counters: Dictionary = {}
var _context: Dictionary = {}
var _build: Dictionary = {}
var _dropped_count: int = 0
var _problem: Dictionary = {}
var _problem_following_count: int = 0
var _dirty: bool = false
var _last_save_msec: int = 0
var _persistence_enabled: bool = true
var _web_bridge: JavaScriptObject = null
var _sanitize_values_left: int = MAX_VALUES_PER_RECORD


func _init() -> void:
	_new_session()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Headless checks should neither read nor replace a player's diagnostic file.
	_persistence_enabled = DisplayServer.get_name() != "headless"
	if OS.has_feature("web"):
		var has_bridge: Variant = JavaScriptBridge.eval(
			"typeof window.PocketPlaytestDiagnostics === 'object' && typeof window.PocketPlaytestDiagnostics.record === 'function'", true
		)
		if has_bridge == true:
			_web_bridge = JavaScriptBridge.get_interface("PocketPlaytestDiagnostics")
	record_event("session_start", {"platform": OS.get_name()})


func _process(_delta: float) -> void:
	if _dirty and Time.get_ticks_msec() - _last_save_msec >= SAVE_INTERVAL_MSEC:
		_save_snapshot()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST, NOTIFICATION_PREDELETE]:
		if _dirty:
			_save_snapshot()


func record_event(kind: String, fields: Dictionary = {}) -> void:
	var safe_kind: String = _safe_kind(kind)
	if safe_kind.is_empty():
		return
	if not _counters.has(safe_kind) and _counters.size() >= MAX_EVENT_KINDS - 1:
		safe_kind = "other"
	_counters[safe_kind] = int(_counters.get(safe_kind, 0)) + 1
	var now_msec: int = Time.get_ticks_msec()
	var event: Dictionary = {
		"sequence": _next_sequence,
		"elapsed_ms": maxi(0, now_msec - _started_msec),
		"utc_ms": int(Time.get_unix_time_from_system() * 1000.0),
		"kind": safe_kind,
		"fields": _sanitize_dictionary(fields, 0),
	}
	_next_sequence += 1
	if _events.size() >= MAX_EVENTS:
		_events.pop_front()
		_dropped_count += 1
	_events.append(event)
	if not _problem.is_empty() and _problem_following_count < PROBLEM_FOLLOWING_EVENTS:
		var following: Array = _problem["following_events"]
		following.append(event.duplicate(true))
		_problem_following_count += 1
	_dirty = true
	_send_web_packet({"type": "event", "event": event})


func start_match(metadata: Dictionary = {}) -> void:
	_context = _sanitize_dictionary(metadata, 0)
	if metadata.get("build") is Dictionary:
		# The loaded PCK's identity remains authoritative if shell metadata differs.
		_build.merge(_sanitize_dictionary(metadata["build"], 0), false)
	_context.erase("build")
	record_event("match_start", _context)


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"session_id": _session_id,
		"started_utc": _started_utc,
		"build": _build.duplicate(true),
		"context": _context.duplicate(true),
		"counters": _counters.duplicate(true),
		"events": _events.duplicate(true),
		"dropped_count": _dropped_count,
		"next_sequence": _next_sequence,
		"problem": _problem.duplicate(true),
	}


func mark_report(note: String = "") -> Dictionary:
	# Retain a bounded neighborhood even if play continues until the ring wraps.
	_problem.clear()
	_problem_following_count = 0
	record_event("problem_marked", {"note": _safe_string(note)})
	var marker: Dictionary = _events.back()
	var preceding: Array[Dictionary] = []
	var first: int = maxi(0, _events.size() - PROBLEM_PRECEDING_EVENTS - 1)
	for index: int in range(first, _events.size() - 1):
		preceding.append(_events[index].duplicate(true))
	_problem = {
		"id": "%s-%d" % [_session_id, int(marker["sequence"])],
		"marker": marker.duplicate(true),
		"context": _context.duplicate(true),
		"preceding_events": preceding,
		"following_events": [],
	}
	var report: Dictionary = get_report()
	_send_web_packet({"type": "report", "report": report})
	_save_snapshot()
	return report


func reset_for_test() -> void:
	# Focused checks create their own instance and never modify player storage.
	_persistence_enabled = false
	_web_bridge = null
	_new_session()


func _new_session() -> void:
	_session_id = Crypto.new().generate_random_bytes(16).hex_encode()
	_started_utc = Time.get_datetime_string_from_system(true) + "Z"
	_started_msec = Time.get_ticks_msec()
	_next_sequence = 1
	_events.clear()
	_counters.clear()
	_context.clear()
	_build = {
		"game_version": str(ProjectSettings.get_setting("application/config/version", "unknown")),
		"runtime_revision": str(ProjectSettings.get_setting("application/config/playtest_revision", "development")),
	}
	_dropped_count = 0
	_problem.clear()
	_problem_following_count = 0
	_dirty = false
	_last_save_msec = _started_msec


func _send_web_packet(payload: Dictionary) -> void:
	if _web_bridge == null:
		return
	var packet: Dictionary = {
		"schema": SCHEMA_VERSION,
		"session_id": _session_id,
		"started_utc": _started_utc,
		"build": _build,
		"context": _context,
	}
	packet.merge(payload)
	_web_bridge.record(JSON.stringify(packet))


func _save_snapshot() -> void:
	_last_save_msec = Time.get_ticks_msec()
	_dirty = false
	if not _persistence_enabled:
		return
	var file: FileAccess = FileAccess.open(SNAPSHOT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(get_report()))


func _safe_kind(kind: String) -> String:
	var result: String = ""
	for character: String in kind.to_lower().left(48):
		if character in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			result += character
	return result


func _safe_string(value: String) -> String:
	# Labels/reasons are short game data. Strip credential-like or contact text.
	var result: String = value.left(MAX_STRING_LENGTH).replace("\n", " ").replace("\r", " ")
	if "@" in result or "bearer " in result.to_lower() or "cookie=" in result.to_lower():
		return "[redacted]"
	return result


func _sanitize_dictionary(fields: Dictionary, depth: int) -> Dictionary:
	var result: Dictionary = {}
	if depth == 0:
		_sanitize_values_left = MAX_VALUES_PER_RECORD
	if depth > 3:
		return result
	for raw_key: Variant in fields:
		if result.size() >= MAX_FIELDS or _sanitize_values_left <= 0:
			break
		if not raw_key is String and not raw_key is StringName:
			continue
		var key: String = str(raw_key).left(48)
		if key.to_lower() in PRIVATE_KEYS:
			continue
		var sanitized: Variant = _sanitize_value(fields[raw_key], depth + 1)
		if sanitized != null:
			result[key] = sanitized
	return result


func _sanitize_value(value: Variant, depth: int) -> Variant:
	if depth > 4 or _sanitize_values_left <= 0:
		return null
	_sanitize_values_left -= 1
	match typeof(value):
		TYPE_BOOL, TYPE_INT:
			return value
		TYPE_FLOAT:
			return value if is_finite(float(value)) else null
		TYPE_STRING, TYPE_STRING_NAME:
			return _safe_string(str(value))
		TYPE_DICTIONARY:
			return _sanitize_dictionary(value, depth)
		TYPE_ARRAY:
			var result: Array = []
			for item: Variant in value:
				if result.size() >= MAX_ARRAY_ITEMS or _sanitize_values_left <= 0:
					break
				var sanitized: Variant = _sanitize_value(item, depth + 1)
				if sanitized != null:
					result.append(sanitized)
			return result
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [snappedf(float(value.x), 1.0), snappedf(float(value.y), 1.0)]
		TYPE_RECT2, TYPE_RECT2I:
			return {"position": _sanitize_value(value.position, depth + 1), "size": _sanitize_value(value.size, depth + 1)}
	return null
