extends SceneTree
## Validate cached PCM, audio event transitions, controls, and observer independence.

class TestWater extends Node3D:
	signal water_entered(position: Vector3, impact_speed: float)

var _failures: int = 0
var _checks: int = 0
var _cues: Array[StringName] = []
var _body: TorusBody
var _audio: GameAudio
var _water: TestWater


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_streams()
	_body = TorusBody.new()
	_body.freeze = true
	_body.automatic_nudge = false
	root.add_child(_body)
	_water = TestWater.new()
	root.add_child(_water)
	_audio = GameAudio.new()
	_audio.target = _body
	_audio.water_hazard = _water
	_audio.cue_played.connect(func(kind: StringName) -> void: _cues.append(kind))
	root.add_child(_audio)
	_audio.set_process(false)
	var initial_transform := _body.transform
	var initial_linear := _body.linear_velocity
	var initial_angular := _body.angular_velocity
	await create_timer(0.05).timeout
	await _test_events()
	_test_music_toggle()
	_check(_body.transform == initial_transform and _body.linear_velocity == initial_linear
		and _body.angular_velocity == initial_angular, "Audio events never alter rigid-body state")
	_audio.queue_free()
	_body.queue_free()
	_water.queue_free()
	# Give the audio mixer time to release stopped playbacks before shutting it down.
	await create_timer(0.1).timeout
	print("AUDIO FEEDBACK %s checks=%d failures=%d" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_streams() -> void:
	var started := Time.get_ticks_msec()
	var streams := [AudioSynth.music(), AudioSynth.rolling(), AudioSynth.cue(&"hop"),
		AudioSynth.cue(&"landing"), AudioSynth.cue(&"impact"), AudioSynth.cue(&"splash")]
	var total_bytes := 0
	for stream: AudioStreamWAV in streams:
		var pcm := stream.data
		var peak := 0
		var energy := 0.0
		for offset in range(0, pcm.size(), 2):
			var sample := pcm.decode_s16(offset)
			peak = maxi(peak, absi(sample))
			energy += float(sample * sample)
		_check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 22050
			and not stream.stereo and pcm.size() > 1000, "Generated stream has valid mono PCM")
		_check(peak > 500 and peak < 29000 and energy > 1000000.0, "Generated stream is audible with headroom")
		_check(pcm.decode_s16(0) == 0 and pcm.decode_s16(pcm.size() - 2) == 0, "Stream boundaries fade without clicks")
		total_bytes += pcm.size()
	_check(total_bytes < 1000000, "Cached audio occupies less than 1MB of PCM")
	_check(streams[0] == AudioSynth.music() and streams[1] == AudioSynth.rolling()
		and streams[2] == AudioSynth.cue(&"hop"), "Repeated requests reuse synthesized resources")
	_check(streams[0].loop_mode == AudioStreamWAV.LOOP_FORWARD and streams[1].loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"Music and rolling streams loop")
	print("AUDIO SYNTH bytes=%d generation_and_scan_ms=%d" % [total_bytes, Time.get_ticks_msec() - started])


func _test_events() -> void:
	_sample(false, Vector3(0, -5, 0))
	for tick in range(20):
		_sample(false, Vector3(0, -5, 0))
	_sample(true, Vector3.ZERO)
	_check(_cues.is_empty(), "Initial spawn does not produce landing or impact cues")
	_sample(true, Vector3.BACK * 8.0)
	_audio._process(0.2)
	_check(_audio._rolling.playing, "Grounded motion starts rolling audio")
	var quiet := _audio._rolling.volume_db
	var slow := _audio._rolling.pitch_scale
	_sample(true, Vector3.BACK * 20.0, 0.8)
	_audio._process(0.2)
	_check(_audio._rolling.volume_db > quiet and _audio._rolling.pitch_scale > slow,
		"Speed and slip increase rolling sound")
	await create_timer(0.04).timeout
	_cues.clear()
	_sample(false, Vector3(0, 3, 20))
	_audio._process(0.1)
	_check(_cues == [&"hop"] and not _audio._rolling.playing, "Takeoff plays hop and stops ground rolling")
	await create_timer(0.04).timeout
	for tick in range(24):
		_sample(false, Vector3(0, -4, 20))
	_sample(true, Vector3.BACK * 20.0)
	_check(_cues.count(&"landing") == 1, "Airborne descent produces one landing cue")
	await create_timer(0.04).timeout
	for tick in range(50):
		_sample(true, Vector3.BACK * 20.0)
	_sample(true, Vector3.BACK * 10.0)
	_check(_cues.count(&"impact") == 1, "Hard horizontal speed change produces impact cue")
	await create_timer(0.04).timeout
	_body.reset_completed.emit()
	_check(not _audio._rolling.playing and not _audio._effects[&"impact"].playing,
		"Reset stops rolling and transient collision sounds")
	_cues.clear()
	_sample(true, Vector3.ZERO)
	_check(_cues.is_empty(), "First sample after reset is quiet")
	_water.water_entered.emit(Vector3.ZERO, 8.0)
	_water.water_entered.emit(Vector3.ZERO, 8.0)
	_check(_cues == [&"splash"], "Water entry plays exactly one splash")
	await create_timer(0.04).timeout
	var pending := {"grounded": true, "speed": 20.0, "linear_velocity": Vector3.BACK * 20.0, "water_pending": true}
	_body.physics_sampled.emit(pending)
	_audio._process(0.1)
	_check(not _audio._rolling.playing and _cues == [&"splash"], "Pending rescue suppresses rolling and collision cues")
	_body.physics_sampled.emit({"grounded": true, "speed": 8.0,
		"linear_velocity": Vector3.BACK * 8.0, "water_pending": false})
	_audio._process(0.1)
	_check(not _audio._submerged and _audio._rolling.playing and _cues == [&"splash"],
		"Canceling rescue through a snapshot resumes rolling without false collisions")
	await create_timer(0.04).timeout
	_water.water_entered.emit(Vector3.ZERO, 8.0)
	_check(_cues.count(&"splash") == 2, "A canceled rescue does not suppress the next water entry")
	await create_timer(0.04).timeout
	_body.reset_completed.emit()
	_check(_audio._effects[&"splash"].playing, "Water splash tail survives the reset")
	_audio.sfx_enabled = false
	_check(not _audio._effects[&"splash"].playing, "SFX setting silences even an active splash")
	_cues.clear()
	_water.water_entered.emit(Vector3.ZERO, 8.0)
	_check(_cues.is_empty(), "Muted SFX produce no playback events")
	_audio.sfx_enabled = true
	_body.reset_completed.emit()


func _test_music_toggle() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_M
	key.pressed = true
	_check(InputMap.action_has_event(&"music_toggle", key), "M is mapped to music toggle")
	_check(_audio._music.playing and _audio.music_enabled, "Music starts enabled")
	_audio._unhandled_input(key)
	_check(not _audio.music_enabled and _audio._music.stream_paused and _audio.sfx_enabled,
		"M pauses music while leaving SFX enabled")
	_audio._unhandled_input(key)
	_check(_audio.music_enabled and not _audio._music.stream_paused, "Second M resumes music")
	_audio.music_volume_db = -28.0
	_audio._process(0.1)
	_check(is_equal_approx(_audio._music.volume_db, -28.0), "Music volume can be tuned live")


func _sample(grounded: bool, velocity: Vector3, slip: float = 0.0) -> void:
	_body.physics_sampled.emit({"grounded": grounded, "linear_velocity": velocity,
		"speed": velocity.length(), "slip_ratio": slip})


func _check(passed: bool, message: String) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		push_error("FAIL: " + message)
