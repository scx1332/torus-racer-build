class_name AudioSynth
extends RefCounted
## Original, cached mono PCM: no downloaded samples and no realtime synthesis.

const SAMPLE_RATE := 22050
static var _cache: Dictionary = {}


static func music() -> AudioStreamWAV:
	if _cache.has(&"music"):
		return _cache[&"music"]
	var beat := 0.625 # 96 BPM, four original bars with a soft coastal feel.
	var samples := PackedFloat32Array()
	samples.resize(int(16.0 * beat * SAMPLE_RATE))
	var chords := [[60, 64, 67, 71], [57, 60, 64, 67], [53, 57, 60, 64], [55, 59, 62, 64]]
	var melody := [72, 76, 79, 76, -1, 81, 79, -1,
		76, 69, 72, 76, 79, 76, 74, -1,
		77, 76, 72, 69, 72, 77, 76, -1,
		74, 79, 83, 81, 79, 76, 74, -1]
	for bar in range(4):
		for note: int in chords[bar]:
			_tone(samples, bar * beat * 4.0, beat * 3.9, _frequency(note), 0.035, 1.0, 0.06)
		for pulse in [0.0, 1.5, 2.0, 3.5]:
			_tone(samples, (bar * 4.0 + pulse) * beat, beat * 0.45,
				_frequency(chords[bar][0] - 24), 0.16, 4.0, 0.18)
	for step in range(melody.size()):
		if melody[step] >= 0:
			_tone(samples, step * beat * 0.5, beat * 0.48,
				_frequency(melody[step]), 0.13, 7.0, 0.22)
	var rng := RandomNumberGenerator.new()
	rng.seed = 39027
	for pulse in range(16):
		_percussion(samples, pulse * beat, 0.15, pulse % 2 == 0, rng)
		_percussion(samples, (pulse + 0.5) * beat, 0.055, false, rng, 0.25)
	_cache[&"music"] = _pcm(samples, true)
	return _cache[&"music"]


static func rolling() -> AudioStreamWAV:
	if _cache.has(&"rolling"):
		return _cache[&"rolling"]
	var samples := PackedFloat32Array()
	samples.resize(SAMPLE_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 491
	var low := 0.0
	for index in range(samples.size()):
		var time := float(index) / SAMPLE_RATE
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.14)
		samples[index] = low * 0.23 + sin(TAU * 56.0 * time) * 0.045 \
			+ sin(TAU * 112.0 * time) * 0.018
	_cache[&"rolling"] = _pcm(samples, true)
	return _cache[&"rolling"]


static func cue(kind: StringName) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind]
	var duration: float = {&"hop": 0.20, &"landing": 0.25, &"impact": 0.18, &"splash": 0.85}.get(kind, 0.20)
	var samples := PackedFloat32Array()
	samples.resize(int(duration * SAMPLE_RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 762
	var low := 0.0
	for index in range(samples.size()):
		var time := float(index) / SAMPLE_RATE
		var progress := time / duration
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.22)
		var value := 0.0
		match kind:
			&"hop":
				value = sin(TAU * (180.0 * time + 780.0 * time * time)) * 0.42 * exp(-time * 9.0)
			&"landing":
				value = (sin(TAU * (100.0 * time - 100.0 * time * time)) * 0.55 + low * 0.25) * exp(-time * 17.0)
			&"impact":
				value = (sin(TAU * 230.0 * time) * 0.28 + sin(TAU * 371.0 * time) * 0.14 + low * 0.32) * exp(-time * 25.0)
			&"splash":
				var bubbles := sin(TAU * (420.0 * time - 140.0 * time * time)) * sin(TAU * 17.0 * time)
				value = (low * 0.75 + bubbles * 0.10) * (1.0 - progress) * exp(-time * 2.1)
		samples[index] = value
	_cache[kind] = _pcm(samples)
	return _cache[kind]


static func _tone(samples: PackedFloat32Array, start: float, duration: float,
		frequency: float, gain: float, decay: float, brightness: float) -> void:
	var begin := int(start * SAMPLE_RATE)
	var count := mini(int(duration * SAMPLE_RATE), samples.size() - begin)
	for index in range(count):
		var time := float(index) / SAMPLE_RATE
		var envelope := minf(time / 0.008, 1.0) * minf((duration - time) / 0.035, 1.0) * exp(-time * decay)
		var phase := TAU * frequency * time
		samples[begin + index] += gain * envelope * (sin(phase) + sin(phase * 2.0) * brightness)


static func _percussion(samples: PackedFloat32Array, start: float, duration: float,
		kick: bool, rng: RandomNumberGenerator, gain: float = 1.0) -> void:
	var begin := int(start * SAMPLE_RATE)
	for index in range(mini(int(duration * SAMPLE_RATE), samples.size() - begin)):
		var time := float(index) / SAMPLE_RATE
		var value := sin(TAU * (75.0 * time - 120.0 * time * time)) * 0.16 if kick \
			else rng.randf_range(-1.0, 1.0) * 0.055
		samples[begin + index] += value * exp(-time * 35.0) * minf(time / 0.002, 1.0) * gain


static func _frequency(note: int) -> float:
	return 440.0 * pow(2.0, float(note - 69) / 12.0)


static func _pcm(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for index in range(samples.size()):
		# Short boundary fades prevent clicks, including at the rolling/music loop seam.
		var fade := minf(1.0, minf(float(index), float(samples.size() - 1 - index)) / (SAMPLE_RATE * 0.006))
		var value := int(clampf(samples[index] * fade, -0.85, 0.85) * 32767.0)
		bytes.encode_s16(index * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = samples.size()
	return stream
