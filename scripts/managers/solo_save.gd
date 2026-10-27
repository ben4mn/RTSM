extends Node
## Solo-only device checkpoint. Browser writes are durable only after IndexedDB
## transaction completion; native slots retain the previous validated generation.
signal save_changed()
signal status_changed(status: Dictionary)
signal save_written(generation: int)
signal save_completed(generation: int, success: bool)
const STATE = preload("res://scripts/main/solo_match_state.gd")
const SLOTS: Array[String] = ["user://solo-a.save", "user://solo-b.save"]
const MAX_BYTES := 8 * 1024 * 1024
const AUTOSAVE_SECONDS := 15.0
const PREFERENCE_FIELDS: Array[String] = ["selected_map_seed", "selected_map_archetype", "selected_difficulty", "selected_population_limit", "selected_match_mode", "selected_civilization", "selected_opponent_civilization"]
var _summary: Dictionary = {"available": false}
var _status: Dictionary = {"state": "empty", "durable": false, "error": ""}
var _last_good_payload: String = ""
var _saved_data: Dictionary = {}
var _generation: int = 0
var _native_slot: int = -1
var _epoch: int = 0
var _pending: bool = false
var _pending_restore: Dictionary = {}
var _preferences: Dictionary = {}
var _main_ref: WeakRef
var _codec: RefCounted = STATE.new()
var _elapsed: float = 0.0
var _web_callbacks: Dictionary = {}
var _web_storage: JavaScriptObject

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"): _web_storage = JavaScriptBridge.get_interface("PocketSoloStorage")
	reload_save()

func _online() -> bool:
	return NetworkSession.is_network_match() or NetworkSession.server_mode or NetworkSession.online

func has_save() -> bool: return bool(_summary.get("available", false))
func get_summary() -> Dictionary: return _summary.duplicate(true)
func get_status() -> Dictionary:
	var result: Dictionary = _status.duplicate(true)
	var main: Node = _main_ref.get_ref() if _main_ref != null else null
	result.dirty = is_instance_valid(main) and (not has_save() or GameManager.game_time > float(_summary.get("game_time", -1.0)) + 0.001)
	return result
func is_restoring() -> bool: return not _pending_restore.is_empty() and not _online()

func _set_status(state: String, error: String = "") -> void:
	_status = {"state": state, "error": error, "durable": state == "saved", "local_written": state == "saved", "generation": _generation, "saved_at": _summary.get("saved_at", 0), "game_time": _summary.get("game_time", 0.0)}
	status_changed.emit(get_status())

func _summarize(data: Dictionary, saved_at: int, recovered: bool = false) -> Dictionary:
	return {"available": true, "saved_at": saved_at, "game_time": data.manager.game_time, "map_name": MapData.get_archetype_name(int(data.style)), "map_archetype": data.style, "civilization": data.manager.players[0].civilization, "difficulty": data.difficulty, "recovered_backup": recovered}

func _envelope(data: Dictionary, generation: int) -> String:
	var bytes: PackedByteArray = var_to_bytes(data)
	return JSON.stringify({"format": "PocketKingdomsSolo", "version": 1, "generation": generation, "saved_at": int(Time.get_unix_time_from_system()), "sha256": bytes.hex_encode().sha256_text(), "payload": Marshalls.raw_to_base64(bytes)})

func _unpack(payload: String) -> Dictionary:
	if payload.is_empty() or payload.to_utf8_buffer().size() > MAX_BYTES: return {}
	var parser := JSON.new()
	if parser.parse(payload) != OK: return {}
	var envelope: Variant = parser.data
	if not envelope is Dictionary or envelope.get("format") != "PocketKingdomsSolo" or envelope.get("version") != 1 or not envelope.get("payload") is String or not envelope.get("sha256") is String: return {}
	if not envelope.get("generation") is float or not is_finite(envelope.generation) or envelope.generation < 1 or envelope.generation != floor(envelope.generation): return {}
	var bytes: PackedByteArray = Marshalls.base64_to_raw(envelope.payload)
	if bytes.is_empty() or bytes.size() > MAX_BYTES or bytes.hex_encode().sha256_text() != envelope.sha256: return {}
	var data: Variant = bytes_to_var(bytes)
	if not data is Dictionary or not STATE.validate(data).is_empty(): return {}
	return {"data": data, "generation": int(envelope.generation), "saved_at": int(envelope.get("saved_at", 0))}

func _read_native(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES: return ""
	return file.get_as_text()

func reload_save() -> void:
	if _pending: return
	var candidates: Array[String] = []
	if OS.has_feature("web"):
		if _web_storage != null and bool(_web_storage.available()):
			candidates.assign([str(_web_storage.read()), str(_web_storage.readBackup())])
	else:
		for path: String in SLOTS: candidates.append(_read_native(path))
	var best: Dictionary = {}
	var selected: String = ""
	var selected_index: int = -1
	for index: int in candidates.size():
		var parsed: Dictionary = _unpack(candidates[index])
		if not parsed.is_empty() and int(parsed.generation) > int(best.get("generation", 0)):
			best = parsed
			selected = candidates[index]
			selected_index = index
	_native_slot = selected_index
	_saved_data = best.get("data", {})
	_last_good_payload = selected
	_generation = int(best.get("generation", 0))
	var recovered: bool = OS.has_feature("web") and selected_index == 1
	for candidate: String in candidates:
		if not candidate.is_empty() and _unpack(candidate).is_empty(): recovered = not best.is_empty()
	_summary = _summarize(_saved_data, int(best.saved_at), recovered) if not best.is_empty() else {"available": false}
	_set_status("saved" if has_save() else "empty")
	save_changed.emit()

func attach_match(main: Node) -> void:
	if _online(): return
	_main_ref = weakref(main)
	_elapsed = 0.0
	if is_restoring():
		_codec.restore_context(main, _pending_restore)
		_pending_restore.clear()
		_restore_preferences()
		# Resume starts safely paused; the player chooses when play continues.
		GameManager.set_paused(true)
		main._sync_hud_modal_state()
		_set_status("saved")
	else:
		_set_status("unsaved")
		call_deferred("save_current", "match_start")

func restore_world(main: Node) -> bool:
	if not is_restoring(): return false
	return _codec.restore_world(main, _pending_restore)

func resume_match() -> bool:
	if _online() or _pending or not has_save(): return false
	var parsed: Dictionary = _unpack(_last_good_payload)
	if parsed.is_empty():
		_set_status("failed", "The saved match could not be read.")
		return false
	_pending_restore = parsed.data
	_preferences.clear()
	for field: String in PREFERENCE_FIELDS: _preferences[field] = GameManager.get(field)
	GameManager.selected_map_seed = int(_pending_restore.seed)
	GameManager.selected_map_archetype = int(_pending_restore.style)
	GameManager.selected_difficulty = int(_pending_restore.difficulty)
	GameManager.selected_population_limit = int(_pending_restore.manager._match_population_limit)
	GameManager.selected_match_mode = int(_pending_restore.manager._match_mode)
	GameManager.selected_civilization = int(_pending_restore.manager.players[0].civilization)
	GameManager.selected_opponent_civilization = int(_pending_restore.manager.players[1].civilization)
	GameManager.remove_meta("auto_solo_opponent")
	get_tree().paused = false
	var error: Error = get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	if error != OK:
		_pending_restore.clear()
		_restore_preferences()
		_set_status("failed", "Could not open the saved battlefield.")
		return false
	return true

func abort_restore(message: String) -> void:
	_pending_restore.clear()
	_restore_preferences()
	_main_ref = null
	_codec = STATE.new()
	_set_status("failed", message)
	get_tree().paused = false
	GameManager.set_state(GameManager.GameState.MENU)
	get_tree().call_deferred("change_scene_to_file", "res://scenes/ui/main_menu.tscn")

func _restore_preferences() -> void:
	for field: String in _preferences: GameManager.set(field, _preferences[field])
	_preferences.clear()

func save_current(reason: String = "manual") -> bool:
	if _online() or is_restoring() or _pending: return false
	var main: Node = _main_ref.get_ref() if _main_ref != null else null
	if not is_instance_valid(main) or main.is_queued_for_deletion() or GameManager.current_state not in [GameManager.GameState.PLAYING, GameManager.GameState.PAUSED]: return false
	if not GameManager._research_transactions.is_empty() or not GameManager._age_transactions.is_empty(): return false
	var data: Dictionary = _codec.capture(main)
	var validation: String = STATE.validate(data)
	if not validation.is_empty():
		_set_status("failed", validation)
		return false
	var generation: int = _generation + 1
	var payload: String = _envelope(data, generation)
	if payload.to_utf8_buffer().size() > MAX_BYTES:
		_set_status("failed", "This match is too large to save.")
		return false
	_pending = true
	_generation = generation
	_set_status("saving")
	_status.reason = reason
	save_written.emit(generation)
	if OS.has_feature("web"):
		if _web_storage == null or not bool(_web_storage.available()):
			_complete_write([], generation, _epoch, payload, false, "Browser storage is unavailable.")
			return false
		var callback: JavaScriptObject = JavaScriptBridge.create_callback(_complete_write.bind(generation, _epoch, payload))
		_web_callbacks[generation] = callback
		_web_storage.write(payload, _last_good_payload, callback)
		return true
	var success: bool = _write_native(payload, generation)
	_complete_write([], generation, _epoch, payload, success, "" if success else "Could not write the saved match.")
	return success

func _write_native(payload: String, generation: int) -> bool:
	var next_slot: int = 0 if _native_slot < 0 else 1 - _native_slot
	var target: String = SLOTS[next_slot]
	var temporary: String = target + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	file.store_string(payload)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK or _unpack(_read_native(temporary)).is_empty(): return false
	# Only replace the older slot after a complete validated temporary write.
	# An interruption leaves the most recent good slot untouched.
	if FileAccess.file_exists(target) and DirAccess.remove_absolute(target) != OK: return false
	if DirAccess.rename_absolute(temporary, target) != OK: return false
	_native_slot = next_slot
	return true

func _complete_write(arguments: Array, generation: int, epoch: int, payload: String, native_success: bool = false, native_error: String = "") -> void:
	_web_callbacks.erase(generation)
	if epoch != _epoch: return
	_pending = false
	var success: bool = bool(arguments[0]) if not arguments.is_empty() else native_success
	var error: String = str(arguments[1]) if arguments.size() > 1 else native_error
	if success:
		var parsed: Dictionary = _unpack(payload)
		_last_good_payload = payload
		_saved_data = parsed.data
		_summary = _summarize(parsed.data, int(parsed.saved_at))
		_set_status("saved")
		save_changed.emit()
	else:
		_set_status("failed", error if not error.is_empty() else "The match could not be saved.")
	save_completed.emit(generation, success)

func save_and_wait(reason: String = "manual") -> bool:
	var deadline: int = Time.get_ticks_msec() + 15000
	while _pending and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	if _pending: return false
	if not save_current(reason): return false
	while _pending and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	return not _pending and _status.state == "saved"

func discard_save(reason: String = "new_match") -> void:
	if _online(): return
	_epoch += 1
	_pending = false
	_pending_restore.clear()
	_saved_data.clear()
	_last_good_payload = ""
	_summary = {"available": false}
	_main_ref = null
	_native_slot = -1
	if OS.has_feature("web"):
		if _web_storage != null and bool(_web_storage.available()):
			var callback: JavaScriptObject = JavaScriptBridge.create_callback(_clear_finished.bind(_epoch))
			_web_callbacks[-_epoch] = callback
			_web_storage.clear(callback)
	else:
		for path: String in SLOTS:
			if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	_set_status("empty")
	_status.reason = reason
	save_changed.emit()

func _clear_finished(arguments: Array, epoch: int) -> void:
	_web_callbacks.erase(-epoch)
	if epoch != _epoch: return
	if arguments.is_empty() or not bool(arguments[0]): _set_status("failed", str(arguments[1]) if arguments.size() > 1 else "Could not remove the old save.")

func _process(delta: float) -> void:
	if _online() or is_restoring() or _pending or GameManager.current_state != GameManager.GameState.PLAYING: return
	_elapsed += delta / maxf(0.01, Engine.time_scale)
	if _elapsed >= AUTOSAVE_SECONDS:
		_elapsed = 0.0
		save_current("autosave")

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST]: save_current("background")
