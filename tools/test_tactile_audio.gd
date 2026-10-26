extends Node
## Real scheduler/PCM regression. This does not claim subjective listening.

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var bank: Dictionary = preload("res://scripts/audio/sample_palette.gd").build()
	_expect(bank.size() == 18, "complete action palette")
	for cue: String in bank:
		var hashes: Array[int] = []
		for stream: AudioStreamWAV in bank[cue]:
			_expect(stream.get_length() > 0.05 and stream.get_length() < 1.21, "bounded duration: " + cue)
			_expect(stream.data.decode_s16(0) == 0 and absi(stream.data.decode_s16(stream.data.size() - 2)) < 3, "click-free ends: " + cue)
			var peak: int = 0
			for index: int in range(0, stream.data.size(), 2):
				peak = maxi(peak, absi(stream.data.decode_s16(index)))
			_expect(peak > 100 and peak < 22000, "audible unclipped PCM: " + cue)
			_expect(not hashes.has(hash(stream.data)), "distinct variations: " + cue)
			hashes.append(hash(stream.data))
	var previous_state: int = GameManager.current_state
	var previous_enabled: bool = GameManager.audio_enabled
	GameManager.audio_enabled = true
	AudioManager.set_all_enabled(true)
	AudioManager.call("_set_backgrounded", false)
	GameManager.set_state(GameManager.GameState.PLAYING)
	AudioManager.stop_all()
	var before: Dictionary = AudioManager.get_audio_diagnostics().played
	for index: int in 500:
		for cue: String in ["attack_hit", "unit_death", "gather_food", "gather_wood", "gather_gold", "construction_work"]:
			AudioManager.play_sfx(cue)
	var after: Dictionary = AudioManager.get_audio_diagnostics().played
	var total: int = 0
	for cue: String in after: total += int(after[cue]) - int(before.get(cue, 0))
	_expect(total == 2, "3000 simultaneous world events become one work and one combat cue")
	_expect(AudioManager.get_audio_diagnostics().active_voices <= AudioManager.WORLD_VOICES + AudioManager.UI_VOICES, "voice cap")
	await get_tree().create_timer(0.2).timeout
	var prior_variant: int = -1
	for index: int in 12:
		AudioManager.stop_all()
		AudioManager.play_ui("select_unit")
		var variant: int = AudioManager.get_audio_diagnostics().variants.select_unit
		_expect(variant != prior_variant, "no immediately repeated selection take")
		prior_variant = variant
		await get_tree().create_timer(0.14).timeout
	# Fill the real reserved pool with important, playing voices. A low-priority
	# recruitment must not cut an outcome; victory must displace a generic click.
	AudioManager.stop_all()
	var players: Array = AudioManager.get("_ui_players")
	for voice: AudioStreamPlayer in players:
		voice.stream = bank.victory[0]
		voice.set_meta("priority", 5)
		voice.set_meta("cue", "victory")
		voice.play()
	await get_tree().create_timer(0.05).timeout
	before = AudioManager.get_audio_diagnostics().played
	AudioManager.play_ui("unit_trained")
	_expect(AudioManager.get_audio_diagnostics().played == before, "recruitment cannot steal an outcome")
	players[0].set_meta("priority", 0)
	players[0].set_meta("cue", "button_click")
	AudioManager.play_ui("victory")
	_expect(players[0].get_meta("cue") == "victory", "outcome preempts lower priority")
	await get_tree().create_timer(0.05).timeout
	AudioManager.call("_set_backgrounded", true)
	AudioManager.play_ui("under_attack")
	_expect(AudioManager.get_audio_diagnostics().active_voices == 0, "background drops and stops all cues")
	AudioManager.call("_set_backgrounded", false)
	_expect(AudioManager.get_audio_diagnostics().active_voices == 0, "resume never replays a backlog")
	AudioManager.set("_web_activated", false)
	before = AudioManager.get_audio_diagnostics().played
	AudioManager.play_ui("select_unit")
	_expect(AudioManager.get_audio_diagnostics().played == before, "pre-gesture cue is discarded")
	var gesture := InputEventScreenTouch.new()
	gesture.pressed = true
	AudioManager.call("_input", gesture)
	AudioManager.play_ui("select_unit")
	_expect(AudioManager.get_audio_diagnostics().played != before, "real input gesture enables subsequent cues")
	await get_tree().create_timer(0.14).timeout
	GameManager.audio_enabled = previous_enabled
	GameManager.set_state(previous_state)
	AudioManager.apply_preferences()
	AudioManager.stop_all()
	await get_tree().create_timer(0.2).timeout
	if _failures.is_empty():
		print("[PASS] tactile_audio: 18 PCM banks, bounded tails/headroom, nonrepeating variants, 3000-event work/combat burst, real priority preemption, gesture/background lifecycle")
		get_tree().quit(0)
	else:
		for failure: String in _failures: push_error("[FAIL] tactile_audio: " + failure)
		get_tree().quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition: _failures.append(message)

