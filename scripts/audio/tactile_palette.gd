extends RefCounted
## Original Pocket Kingdoms sound recipes, authored for the illustrated beta7.
## No recordings, sample packs, voices or third-party compositions are used.
## Every stream is deterministic; this local RNG never changes gameplay RNG.

const RATE: int = 22050


static func build() -> Dictionary:
	var bank: Dictionary = {}
	# Frequency, seconds, cloth/rustle amount, secondary wood resonance.
	var taps := {
		"button_click": [390.0, 0.065, 0.05, 0.22],
		"select_unit": [285.0, 0.105, 0.20, 0.12],
		"attack_hit": [155.0, 0.14, 0.26, 0.23],
		"unit_death": [105.0, 0.20, 0.48, 0.03],
		"gather_food": [240.0, 0.11, 0.55, 0.03],
		"gather_wood": [190.0, 0.10, 0.12, 0.30],
		"gather_gold": [610.0, 0.14, 0.04, 0.18],
		"construction_work": [225.0, 0.13, 0.12, 0.26],
		"building_place": [145.0, 0.20, 0.28, 0.14],
	}
	for cue: String in taps:
		var params: Array = taps[cue]
		var variants: Array[AudioStreamWAV] = []
		for variation: int in 3:
			var tune: float = [0.973, 1.0, 1.028][variation]
			variants.append(_tap(float(params[0]) * tune, float(params[1]) * (0.96 + variation * 0.04), float(params[2]), float(params[3]), 73109 + variation * 101 + cue.hash()))
		bank[cue] = variants
	# The same soft felt-plucked instrument marks increasing importance with
	# phrase length, not an abrupt horn or a louder, sharper attack.
	var phrases := {
		"command_move": [[293.66, 440.0], 0.070, 0.18],
		"command_attack": [[220.0, 293.66], 0.075, 0.19],
		"building_invalid": [[246.94, 220.0], 0.09, 0.19],
		"unit_trained": [[392.0, 523.25], 0.10, 0.23],
		"building_complete": [[261.63, 392.0, 523.25], 0.11, 0.29],
		"under_attack": [[293.66, 293.66], 0.18, 0.25],
		"age_up": [[261.63, 329.63, 392.0, 523.25], 0.13, 0.36],
		"victory": [[261.63, 329.63, 392.0, 523.25, 659.25], 0.14, 0.48],
		"defeat": [[329.63, 293.66, 220.0], 0.22, 0.50],
	}
	for cue: String in phrases:
		var params: Array = phrases[cue]
		var variants: Array[AudioStreamWAV] = []
		# Important cadences retain a stable pitch. Small timbral variations in
		# orders prevent repeated navigation from becoming a notification jingle.
		for variation: int in (3 if cue.begins_with("command_") else 1):
			variants.append(_felt_phrase(params[0], float(params[1]), float(params[2]), 0.12 + variation * 0.025))
		bank[cue] = variants
	return bank


static func _tap(frequency: float, duration: float, cloth: float, resonance: float, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var samples := PackedFloat32Array()
	samples.resize(int(duration * RATE))
	var noise: float = 0.0
	var slow_noise: float = 0.0
	for i: int in samples.size():
		var t: float = float(i) / RATE
		noise = lerpf(noise, rng.randf_range(-1.0, 1.0), 0.15)
		slow_noise = lerpf(slow_noise, noise, 0.09)
		var onset: float = smoothstep(0.0, 0.004, t)
		var ending: float = smoothstep(0.0, 0.018, duration - t)
		var body: float = sin(TAU * frequency * t) * exp(-t * 36.0)
		var wood: float = sin(TAU * frequency * 1.53 * t) * exp(-t * 47.0)
		var rustle: float = (noise - slow_noise * 0.6) * exp(-t * 18.0)
		samples[i] = (body * 0.40 + wood * resonance + rustle * cloth) * onset * ending * 0.75
	return _stream(samples)


static func _felt_phrase(notes: Array, spacing: float, tail: float, color: float) -> AudioStreamWAV:
	var duration: float = spacing * (notes.size() - 1) + tail
	var samples := PackedFloat32Array()
	samples.resize(int(duration * RATE))
	for i: int in samples.size():
		var t: float = float(i) / RATE
		var value: float = 0.0
		for n: int in notes.size():
			var local_t: float = t - n * spacing
			if local_t < 0.0 or local_t >= tail: continue
			var phase: float = TAU * float(notes[n]) * local_t
			var envelope: float = smoothstep(0.0, 0.008, local_t) * exp(-local_t * 10.0) * smoothstep(0.0, 0.055, tail - local_t)
			value += (sin(phase) + sin(phase * 2.0) * color * exp(-local_t * 22.0)) * envelope * 0.24
		samples[i] = value
	return _stream(samples)


static func _stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i: int in samples.size():
		var value: int = int(clampf(samples[i], -0.95, 0.95) * 32767.0)
		bytes.encode_s16(i * 2, value)
	wav.data = bytes
	return wav
