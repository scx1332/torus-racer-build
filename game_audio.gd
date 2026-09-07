class_name GameAudio
extends Node
## Removable sound observer. It only reads body snapshots and hazard signals.

signal cue_played(kind: StringName)

@export var target: TorusBody
@export var water_hazard: Node3D
@export var sfx_enabled: bool = true:
	set(value):
		sfx_enabled = value
		if not value:
			_stop_effects()
@export_range(-40.0, 0.0, 1.0) var sfx_volume_db: float = -10.0

var _rolling: AudioStreamPlayer
var _effects: Dictionary = {}
var _sample: Dictionary = {}
var _seen_ground: bool = false
var _was_grounded: bool = false
var _air_time: float = 0.0
var _fall_speed: float = 0.0
var _last_velocity := Vector3.ZERO
var _impact_cooldown: float = 0.0
var _submerged: bool = false
var _water_reset_pending: bool = false


func _ready() -> void:
	_rolling = _player("Rolling", AudioSynth.rolling())
	_rolling.volume_db = -60.0
	for kind: StringName in [&"hop", &"landing", &"impact", &"splash"]:
		_effects[kind] = _player(String(kind).capitalize(), AudioSynth.cue(kind))
	if is_instance_valid(target):
		target.physics_sampled.connect(_on_physics_sampled)
		target.reset_completed.connect(_on_reset)
	if is_instance_valid(water_hazard) and water_hazard.has_signal(&"water_entered"):
		water_hazard.connect(&"water_entered", _on_water_entered)


func _process(delta: float) -> void:
	if not sfx_enabled or _submerged or _sample.is_empty() or _sample.get("water_pending", false):
		return
	var speed: float = _sample.get("speed", 0.0)
	if not _sample.get("grounded", false) or speed < 0.25:
		_rolling.stop()
		return
	var slip := clampf(float(_sample.get("slip_ratio", 0.0)), 0.0, 1.0)
	var strength := clampf(speed / 18.0, 0.04, 1.0)
	var volume := sfx_volume_db - 5.0 + linear_to_db(strength) + slip * 3.0
	var blend := 1.0 - exp(-10.0 * delta)
	_rolling.volume_db = lerpf(_rolling.volume_db, volume, blend)
	_rolling.pitch_scale = lerpf(_rolling.pitch_scale, clampf(0.72 + speed * 0.035 + slip * 0.25, 0.72, 2.3), blend)
	if not _rolling.playing:
		_rolling.play()


func _on_physics_sampled(sample: Dictionary) -> void:
	# Disabling a hazard can cancel rescue without a reset signal; trust explicit state.
	if _submerged and sample.has("water_pending") and not sample["water_pending"]:
		_on_reset()
	_sample = sample
	if _submerged or sample.get("water_pending", false):
		_rolling.stop()
		return
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)
	var grounded: bool = sample.get("grounded", false)
	var velocity: Vector3 = sample.get("linear_velocity", Vector3.ZERO)
	var landed := grounded and not _was_grounded and _seen_ground \
		and _air_time >= 0.06 and _fall_speed > 1.2
	if landed:
		_play_cue(&"landing", clampf(_fall_speed / 7.0, 0.3, 1.0))
	elif not grounded and _was_grounded and velocity.y > 1.0:
		_play_cue(&"hop", 0.55)
	elif _seen_ground and _impact_cooldown <= 0.0:
		var speed_change := (velocity - _last_velocity).slide(Vector3.UP).length()
		if speed_change > 2.5:
			_play_cue(&"impact", clampf(speed_change / 10.0, 0.25, 1.0))
	if grounded:
		_seen_ground = true
		_air_time = 0.0
		_fall_speed = 0.0
	else:
		_air_time += delta
		_fall_speed = maxf(_fall_speed, -velocity.y)
	_was_grounded = grounded
	_last_velocity = velocity


func _on_water_entered(_position: Vector3, impact_speed: float) -> void:
	if _water_reset_pending:
		return
	_stop_effects()
	_submerged = true
	_water_reset_pending = true
	_play_cue(&"splash", clampf(impact_speed / 10.0, 0.5, 1.0))


func _on_reset() -> void:
	# Splash has its own player so the water reset does not cut off its short tail.
	_stop_effects(_water_reset_pending)
	_sample = {}
	_seen_ground = false
	_was_grounded = false
	_air_time = 0.0
	_fall_speed = 0.0
	_last_velocity = Vector3.ZERO
	_impact_cooldown = 0.25
	_submerged = false
	_water_reset_pending = false


func _play_cue(kind: StringName, strength: float) -> void:
	if not sfx_enabled:
		return
	var player: AudioStreamPlayer = _effects[kind]
	player.volume_db = sfx_volume_db + linear_to_db(maxf(strength, 0.01))
	player.play()
	_impact_cooldown = 0.18
	cue_played.emit(kind)


func _stop_effects(preserve_splash: bool = false) -> void:
	if is_instance_valid(_rolling):
		_rolling.stop()
		_rolling.volume_db = -60.0
	for kind: StringName in _effects:
		if not (preserve_splash and kind == &"splash"):
			(_effects[kind] as AudioStreamPlayer).stop()


func _player(player_name: String, stream: AudioStreamWAV) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	add_child(player)
	return player
