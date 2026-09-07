class_name AudioSynth
extends RefCounted
## Original, cached mono PCM: no downloaded samples and no realtime synthesis.

const SAMPLE_RATE := 22050
static var _cache: Dictionary = {}


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


static func _pcm(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for index in range(samples.size()):
		# Short boundary fades prevent clicks, including at the rolling loop seam.
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
