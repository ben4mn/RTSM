extends RefCounted
## Counterfactual experiment adapter. Only Sacred conclusion is suppressed;
## Main's real Town Center destruction and defeat paths remain connected.
var windows: Array[Dictionary] = []
var blocked_tick_count: int = 0
var _main: WeakRef
var _site: WeakRef
var _original: Callable
var _window_open: bool = false

func attach(main: Node) -> bool:
	if NetworkSession.is_network_match() or not is_instance_valid(main): return false
	var site: Node = main.game_map.sacred_site
	_original = Callable(main, "_on_sacred_site_timer_tick")
	if not site.victory_timer_tick.is_connected(_original): return false
	_main = weakref(main)
	_site = weakref(site)
	site.victory_timer_tick.disconnect(_original)
	site.victory_timer_tick.connect(_on_tick)
	site.status_changed.connect(_on_status)
	return true

func _on_status() -> void:
	var site: Node = _site.get_ref()
	if is_instance_valid(site) and not bool(site.clock_ticking): _window_open = false

func _on_tick(owner: int, remaining: float, total: float) -> void:
	if remaining > 0.0:
		_window_open = false
		_original.call(owner, remaining, total)
		return
	var main: Node = _main.get_ref()
	if not is_instance_valid(main): return
	# Preserve the ordinary telemetry preceding Main's conclusion branch.
	if owner == main._sacred_control_owner and main._sacred_last_remaining >= remaining:
		main._sacred_control_seconds[owner] += main._sacred_last_remaining - remaining
	main._sacred_control_owner = owner
	main._sacred_last_remaining = remaining
	blocked_tick_count += 1
	if not _window_open or int(windows[-1].owner) != owner:
		windows.append({"owner": owner, "first_time": GameManager.game_time, "last_time": GameManager.game_time, "ticks": 0, "required_hold": total})
		_window_open = true
		print("[SUPPRESSED_SACRED_WIN] ", JSON.stringify(windows[-1]))
	windows[-1].last_time = GameManager.game_time
	windows[-1].ticks += 1
