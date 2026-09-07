class_name RaceManager
extends Node
## Ordered, swept race gates. The physics observer only changes checkpoint metadata.

signal race_updated(snapshot: Dictionary)
signal checkpoint_passed(index: int)
signal lap_completed(seconds: float, eligible: bool)

@export var target: TorusBody
@export var persistence_enabled: bool = true
@export var best_lap_path: String = "user://coastline_best.cfg"

const GATE_DISTANCES := [55.0, 190.0, 330.0, 490.0, 620.0, 780.0, 940.0]
const CHECKPOINT_COUNT := 6
var gates: Array[Dictionary] = []
var started: bool = false
var lap_number: int = 0
var best_lap: float = 0.0
var last_lap: float = 0.0
var next_gate: int = 0
var lap_valid: bool = true
var _clock: float = 0.0
var _lap_started_at: float = 0.0
var _previous := Vector3.ZERO
var _has_previous: bool = false
var _save_queued: bool = false


func _ready() -> void:
	for distance: float in GATE_DISTANCES:
		var gate := TrackLayout.sample_at(distance)
		gate.distance = distance
		gates.append(gate)
	if persistence_enabled:
		_load_best()
	if is_instance_valid(target):
		target.physics_sampled.connect(_on_physics_sampled)
		target.reset_completed.connect(_on_reset)
	else:
		push_warning("RaceManager needs a target TorusBody.")
	race_updated.emit(get_snapshot())


func get_snapshot() -> Dictionary:
	return {"started": started, "lap_number": lap_number,
		"lap_time": maxf(0.0, _clock - _lap_started_at) if started else 0.0,
		"best_lap": best_lap, "last_lap": last_lap, "next_gate": next_gate,
		"checkpoint_count": CHECKPOINT_COUNT, "lap_valid": lap_valid}


func _on_physics_sampled(sample: Dictionary) -> void:
	var delta := float(sample.get("delta", 1.0 / float(Engine.physics_ticks_per_second)))
	if not is_finite(delta) or delta <= 0.0:
		return
	var segment_started_at := _clock
	_clock += delta
	var point: Vector3 = sample.get("origin", Vector3(INF, INF, INF))
	if not point.is_finite():
		_has_previous = false
	elif _has_previous and not sample.get("water_pending", false):
		var last_fraction := -1.0
		# A fast step may cross several gates, but only in geometric/time order.
		for crossing in range(gates.size()):
			var fraction := _crossing_fraction(gates[next_gate], _previous, point)
			if fraction < 0.0 or fraction <= last_fraction:
				break
			_pass_gate(segment_started_at + delta * fraction)
			last_fraction = fraction
	if point.is_finite():
		_previous = point
		_has_previous = true
	race_updated.emit(get_snapshot())


func _crossing_fraction(gate: Dictionary, from: Vector3, to: Vector3) -> float:
	var before := (from - Vector3(gate.position)).dot(gate.tangent)
	var after := (to - Vector3(gate.position)).dot(gate.tangent)
	if before >= 0.0 or after < 0.0:
		return -1.0
	var fraction := before / (before - after)
	var offset := from.lerp(to, fraction) - Vector3(gate.position)
	var lateral := absf(offset.dot(gate.right))
	var height := offset.dot(gate.up)
	if lateral > TrackLayout.WIDTH * 0.5 + TrackLayout.SHOULDER \
			or height < -0.3 or height > 8.0:
		return -1.0
	return fraction


func _pass_gate(crossed_at: float) -> void:
	var index := next_gate
	if index == 0:
		if started:
			last_lap = crossed_at - _lap_started_at
			if lap_valid and last_lap > 0.0 and (best_lap <= 0.0 or last_lap < best_lap):
				best_lap = last_lap
				_queue_best_save()
			lap_completed.emit(last_lap, lap_valid)
		started = true
		lap_number += 1
		_lap_started_at = crossed_at
		lap_valid = true
	next_gate = (index + 1) % gates.size()
	_store_checkpoint(index)
	checkpoint_passed.emit(index)


func _store_checkpoint(index: int) -> void:
	if not is_instance_valid(target):
		return
	# Place the reset just behind this gate on the actual banked centerline.
	# Local +X is the axle; positive spin follows the checkpoint's tangent.
	var frame := TrackLayout.sample_at(float(gates[index].distance) - 2.0)
	var clearance := target.major_radius + target.minor_radius + 0.03
	var orientation := Basis(-frame.right, frame.up, frame.tangent)
	target.set_checkpoint(Transform3D(orientation, frame.position + frame.up * clearance))


func _on_reset() -> void:
	# Never connect a pre-reset sample to its teleported checkpoint position.
	_has_previous = false
	if started:
		lap_valid = false
	race_updated.emit(get_snapshot())


func _load_best() -> void:
	var file := ConfigFile.new()
	var error := file.load(best_lap_path)
	if error == ERR_FILE_NOT_FOUND:
		return
	if error != OK:
		push_warning("Could not load coastline best lap: %s" % error_string(error))
		return
	var value: Variant = file.get_value("coastline_run", "best_lap", null)
	if not (value is float or value is int) or not is_finite(float(value)) or float(value) <= 0.0:
		push_warning("Ignoring invalid coastline best lap; a positive finite time is required.")
		return
	best_lap = float(value)


func _queue_best_save() -> void:
	if persistence_enabled and not _save_queued:
		_save_queued = true
		_save_best.call_deferred()


func _save_best() -> void:
	# File I/O is deferred outside the body's force-integration signal callback.
	_save_queued = false
	if not persistence_enabled or best_lap <= 0.0:
		return
	var file := ConfigFile.new()
	file.set_value("coastline_run", "best_lap", best_lap)
	var error := file.save(best_lap_path)
	if error != OK:
		push_warning("Could not save coastline best lap: %s" % error_string(error))
