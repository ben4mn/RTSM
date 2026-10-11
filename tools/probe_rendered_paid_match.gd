extends "res://tools/probe_ai_compact_paid_match.gd"
## Native desktop frame timing of ordinary paid policies. No fixed FPS, resource
## grants or injected population. This does not measure a phone or Web renderer.

var _profiles: Array[Dictionary] = []
var _started_us: int = 0
var _previous_us: int = 0
var _profile_index: int = -1
var _last_profile_us: int = 0
var _hooked: bool = false
var _perf_output: String = "res://output/evolution/rendered-paid-performance.json"
var _perf_start_game_seconds: float = 0.0
var _profile_wall_seconds: float = 10.0
var _sampling_started_us: int = 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Native rendered probe requires omitting --headless and --fixed-fps")
		get_tree().quit(1)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--perf-output="):
			_perf_output = argument.trim_prefix("--perf-output=")
		elif argument.begins_with("--perf-start="):
			_perf_start_game_seconds = maxf(0.0, float(argument.trim_prefix("--perf-start=")))
		elif argument.begins_with("--profile-wall-seconds="):
			_profile_wall_seconds = maxf(5.0, float(argument.trim_prefix("--profile-wall-seconds=")))
	OS.set_environment("AOEM_SIM_TIME_SCALE", "3")
	super._ready()


func _process(_delta: float) -> void:
	if not is_instance_valid(match_scene) or not is_instance_valid(human_bot):
		return
	var now_us: int = Time.get_ticks_usec()
	if not _hooked:
		_hooked = true
		_started_us = now_us
		match_scene.tree_exiting.connect(_write_performance)
	if GameManager.game_time < _perf_start_game_seconds:
		return
	if _sampling_started_us == 0:
		_sampling_started_us = now_us
	var elapsed: float = float(now_us - _sampling_started_us) / 1000000.0
	var desired_profile: int = mini(int(elapsed / _profile_wall_seconds), 3)
	if desired_profile != _profile_index:
		_profile_index = desired_profile
		_last_profile_us = now_us
		var phone: Vector2i = Vector2i(844, 390) if desired_profile < 2 else Vector2i(932, 430)
		var zoom_value: float = 0.65 if desired_profile % 2 == 0 else 1.6
		get_window().size = phone
		get_window().content_scale_size = Vector2i(844, 390)
		match_scene.game_map.camera.zoom = Vector2.ONE * zoom_value
		_profiles.append({"pixels": str(phone), "zoom": zoom_value, "frame_ms": [], "process_ms": [], "draw_calls": [], "peak_units": 0, "peak_buildings": 0})
	# Ignore first two wall seconds after resizing; include no startup/loading
	# frames in steady-state timing. Intervals are monotonic wall time, unscaled.
	if now_us - _last_profile_us >= 2000000 and _previous_us > 0:
		var profile: Dictionary = _profiles[_profile_index]
		profile["frame_ms"].append(float(now_us - _previous_us) / 1000.0)
		profile["process_ms"].append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		profile["draw_calls"].append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		profile["peak_units"] = maxi(int(profile["peak_units"]), get_tree().get_nodes_in_group("units").size())
		profile["peak_buildings"] = maxi(int(profile["peak_buildings"]), get_tree().get_nodes_in_group("buildings").size())
		profile["contact_seen"] = float(stats.get("first_contact", -1.0)) >= 0.0
	_previous_us = now_us


func _write_performance() -> void:
	var summaries: Array[Dictionary] = []
	for profile: Dictionary in _profiles:
		var intervals: Array = profile["frame_ms"]
		intervals.sort()
		var process_times: Array = profile["process_ms"]
		process_times.sort()
		var draw_calls: Array = profile["draw_calls"]
		draw_calls.sort()
		summaries.append({"pixels": profile["pixels"], "zoom": profile["zoom"], "sample_frames": intervals.size(), "frame_ms_p50": _percentile(intervals, 0.5), "frame_ms_p95": _percentile(intervals, 0.95), "frame_ms_p99": _percentile(intervals, 0.99), "process_ms_p95": _percentile(process_times, 0.95), "draw_calls_p95": _percentile(draw_calls, 0.95), "peak_units": profile["peak_units"], "peak_buildings": profile["peak_buildings"], "contact_seen": profile.get("contact_seen", false)})
	var result: Dictionary = {"scope": "Native desktop rendered paid policies, no fixed FPS; 3x gameplay speed; four phone pixel/zoom profiles; first two resize seconds excluded. Not Web/physical-phone/GPU timing or human play. Background workloads can affect intervals.", "sampling_start_game_seconds": _perf_start_game_seconds, "profile_wall_seconds": _profile_wall_seconds, "first_contact_game_seconds": stats.get("first_contact", -1.0), "engine": Engine.get_version_info(), "display": DisplayServer.get_name(), "renderer": RenderingServer.get_rendering_device().get_device_name() if RenderingServer.get_rendering_device() != null else "Compatibility", "wall_seconds": float(Time.get_ticks_usec() - _started_us) / 1000000.0, "game_seconds": GameManager.game_time, "source_hashes": stats.get("runtime_source_hashes", {}), "probe_sha256": FileAccess.get_file_as_string("res://tools/probe_rendered_paid_match.gd").sha256_text(), "profiles": summaries}
	var file: FileAccess = FileAccess.open(_perf_output, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("[RENDERED_PAID_PERFORMANCE] ", JSON.stringify(result))


func _percentile(values: Array, fraction: float) -> float:
	if values.is_empty():
		return -1.0
	return float(values[mini(values.size() - 1, int(ceil(values.size() * fraction)) - 1)])
