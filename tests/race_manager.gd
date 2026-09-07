extends SceneTree
## Gate/timer/persistence probes plus physical checkpoint reset through real R input.

class RaceProbe extends TorusBody:
	var placement: Dictionary = {}

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		if not placement.is_empty():
			# Fixture-only approach placement; motion is supplied by a linear impulse.
			state.apply_central_impulse(-state.linear_velocity / state.inverse_mass)
			state.transform.origin = placement.position
			state.apply_central_impulse(placement.velocity / state.inverse_mass)
			placement.clear()
		super._integrate_forces(state)

var _body: TorusBody
var _checks: int = 0
var _failures: int = 0
var _completed: int = 0
var _passed: Array[int] = []
var _laps: Array[Dictionary] = []
var _save_path: String
var _started_at: int


func _initialize() -> void:
	_started_at = Time.get_ticks_msec()
	_run.call_deferred()


func _physics_process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _started_at > 30000:
		push_error("Race manager test exceeded its bounded 30 second timeout")
		quit(1)
	return false


func _run() -> void:
	# Use the platform temp directory; a literal /tmp does not exist on Windows.
	_save_path = OS.get_temp_dir().path_join(
		"torus-race-test-%d-%d.cfg" % [OS.get_process_id(), Time.get_ticks_msec()])
	_body = TorusBody.new()
	_body.freeze = true
	root.add_child(_body)
	_test_order_and_clock()
	_test_geometry()
	_test_high_speed_and_order()
	_test_reset()
	await _test_persistence()
	await _test_physical_reset()
	_body.queue_free()
	if FileAccess.file_exists(_save_path):
		_check(DirAccess.remove_absolute(_save_path) == OK, "Remove only this test's isolated save file")
	_check(_completed == 6, "All race test stages completed without script errors")
	print("RACE MANAGER %s checks=%d failures=%d" % [
		"PASS" if _failures == 0 else "FAIL", _checks, _failures])
	quit(0 if _failures == 0 else 1)


func _race(persist: bool = false) -> RaceManager:
	var race := RaceManager.new()
	race.target = _body
	race.persistence_enabled = persist
	race.best_lap_path = _save_path
	_passed.clear()
	_laps.clear()
	race.checkpoint_passed.connect(func(index: int) -> void: _passed.append(index))
	race.lap_completed.connect(func(seconds: float, eligible: bool) -> void:
		_laps.append({"seconds": seconds, "eligible": eligible}))
	root.add_child(race)
	return race


func _point(race: RaceManager, gate: int, ahead: float,
		lateral: float = 0.0, height: float = 1.28) -> Vector3:
	var frame: Dictionary = race.gates[gate]
	return frame.position + frame.tangent * ahead + frame.right * lateral + frame.up * height


func _feed(race: RaceManager, point: Vector3, delta: float = 0.1, water: bool = false) -> void:
	race._on_physics_sampled({"origin": point, "delta": delta, "water_pending": water})


func _cross(race: RaceManager, gate: int, delta: float = 0.1) -> void:
	_feed(race, _point(race, gate, -1.0), delta)
	_feed(race, _point(race, gate, 1.0), delta)


func _finish_lap(race: RaceManager, delta: float = 0.1, first_gate: int = 1) -> void:
	for gate in range(first_gate, race.gates.size()):
		_cross(race, gate, delta)
	_cross(race, 0, delta)


func _test_order_and_clock() -> void:
	var race := _race()
	_check(not race.started and race.get_snapshot().lap_time == 0.0,
		"Timer waits for the initial forward start crossing")
	_cross(race, 0)
	_check(race.started and race.lap_number == 1 and race.next_gate == 1,
		"Forward start crossing begins lap one and targets checkpoint one")
	_check(is_equal_approx(race.get_snapshot().lap_time, 0.05),
		"Start crossing uses the half-step timestamp, not the sample boundary")
	_finish_lap(race, 0.2)
	_check(_passed == [0, 1, 2, 3, 4, 5, 6, 0], "Every gate is reported once in required order")
	_check(_laps.size() == 1 and _laps[0].eligible and is_equal_approx(_laps[0].seconds, 2.75),
		"Six checkpoints and finish complete an exactly timed eligible lap")
	_check(race.lap_number == 2 and race.next_gate == 1 and race.lap_valid \
		and is_equal_approx(race.best_lap, 2.75) and is_equal_approx(race.get_snapshot().lap_time, 0.1),
		"Finish starts the next lap with fractional remainder and records the best")
	var frame := TrackLayout.sample_at(328.0)
	race._store_checkpoint(2)
	_check(_body.checkpoint_transform.origin.distance_to(frame.position + frame.up * 1.28) < 0.0001 \
		and _body.checkpoint_transform.basis.x.distance_to(-frame.right) < 0.0001 \
		and _body.checkpoint_transform.basis.z.distance_to(frame.tangent) < 0.0001,
		"Banked reset metadata uses the gate's approach and correct positive-spin orientation")
	_check(not FileAccess.file_exists(_save_path), "Disabled persistence writes no save file")
	race.free()
	_completed += 1


func _test_geometry() -> void:
	var race := _race()
	_feed(race, _point(race, 0, 1.0))
	_feed(race, _point(race, 0, -1.0))
	_check(not race.started, "Reverse start crossing is ignored")
	for offset: Vector2 in [Vector2(13.51, 1.28), Vector2(-13.51, 1.28),
			Vector2(0, -0.31), Vector2(0, 8.01)]:
		_feed(race, _point(race, 0, -1.0, offset.x, offset.y))
		_feed(race, _point(race, 0, 1.0, offset.x, offset.y))
	_check(not race.started, "Side bypass, below-road and above-gate crossings are ignored")
	for gate in range(race.gates.size()):
		var fraction := race._crossing_fraction(race.gates[gate],
			_point(race, gate, -3.0, 13.49, 7.99), _point(race, gate, 3.0, 13.49, 7.99))
		_check(absf(fraction - 0.5) < 0.00001, "Banked gate %d accepts road edge and airborne height" % gate)
	_feed(race, _point(race, 0, -1.0, 13.5, 8.0))
	_feed(race, _point(race, 0, 1.0, 13.5, 8.0))
	_check(race.started, "Exact outer shoulder and maximum height are inclusive")
	_feed(race, _point(race, 1, -1.0))
	_feed(race, _point(race, 1, 1.0), 0.1, true)
	_check(race.next_gate == 1, "Pending water rescue cannot award checkpoints")
	race.free()
	_completed += 1


func _test_high_speed_and_order() -> void:
	var race := _race()
	_feed(race, TrackLayout.sample_at(30.0).position + Vector3.UP * 1.28, 0.01)
	_feed(race, TrackLayout.sample_at(200.0).position + Vector3.UP * 1.28, 0.01)
	_check(_passed == [0, 1] and race.next_gate == 2,
		"One long swept step detects multiple ordered gates without tunneling")
	_check(absf(race.get_snapshot().lap_time - 0.01 * 145.0 / 170.0) < 0.000001,
		"High-speed sweep retains its exact start-crossing fraction")
	race.free()
	race = _race()
	_cross(race, 0)
	_cross(race, 2)
	_cross(race, 0)
	_check(race.next_gate == 1 and race.lap_number == 1 and _laps.is_empty(),
		"Skipping a checkpoint and recrossing finish cannot complete a lap")
	race.free()
	_completed += 1


func _test_reset() -> void:
	var race := _race()
	_cross(race, 0)
	_cross(race, 1)
	_feed(race, _point(race, 2, -1.0))
	var time_before: float = race.get_snapshot().lap_time
	_body.reset_completed.emit()
	_feed(race, _point(race, 2, 1.0))
	_check(race.next_gate == 2 and not race.lap_valid \
		and is_equal_approx(race.get_snapshot().lap_time, time_before + 0.1),
		"Reset retains progress/time, invalidates best eligibility and rejects teleport crossing")
	_cross(race, 2)
	_finish_lap(race, 0.1, 3)
	_check(_laps.size() == 1 and not _laps[0].eligible and race.best_lap == 0.0,
		"A reset-assisted lap completes but cannot become the best lap")
	_check(race.lap_valid and race.lap_number == 2, "Next full lap restores best eligibility")
	_finish_lap(race)
	_check(_laps.size() == 2 and _laps[1].eligible and race.best_lap > 0.0,
		"An uninterrupted subsequent lap can establish a best time")
	race.free()
	_completed += 1


func _test_persistence() -> void:
	var race := _race(true)
	_cross(race, 0)
	_finish_lap(race)
	_check(race._save_queued and not FileAccess.file_exists(_save_path),
		"Best-lap file writes are deferred outside the physics callback")
	var best := race.best_lap
	await process_frame
	var saved := ConfigFile.new()
	_check(saved.load(_save_path) == OK \
		and is_equal_approx(float(saved.get_value("coastline_run", "best_lap", 0.0)), best),
		"Deferred best time is stored in the isolated ConfigFile")
	race.free()
	race = _race(true)
	_check(is_equal_approx(race.best_lap, best), "A new manager loads the previous positive best time")
	_cross(race, 0, 0.2)
	_finish_lap(race, 0.2)
	_check(is_equal_approx(race.best_lap, best) and not race._save_queued,
		"A slower lap never overwrites the best")
	race.free()
	print("RACE PERSISTENCE: the following invalid-value warnings are expected")
	for invalid: Variant in [-1.0, 0.0, INF, NAN, "12.0", true]:
		saved.set_value("coastline_run", "best_lap", invalid)
		_check(saved.save(_save_path) == OK, "Write isolated invalid-value fixture")
		race = _race(true)
		_check(race.best_lap == 0.0, "Malformed/nonpositive/nonfinite saved time is ignored")
		race.free()
	_completed += 1


func _test_physical_reset() -> void:
	var world := SubViewport.new()
	world.world_3d = World3D.new()
	root.add_child(world)
	var body := RaceProbe.new()
	body.gravity_scale = 0.0
	body.initial_spin = 0.0
	body.automatic_nudge = false
	body.controls_enabled = true
	body.tuning.rumble_enabled = false
	body.position = TrackLayout.sample_at(53.0).position + Vector3.UP * 1.28
	world.add_child(body)
	var race := RaceManager.new()
	race.target = body
	race.persistence_enabled = false
	world.add_child(race)
	await body.physics_sampled
	for distance: float in [53.0, 188.0]:
		body.placement = {"position": TrackLayout.sample_at(distance).position + Vector3.UP * 1.28,
			"velocity": Vector3.BACK * 120.0}
		for tick in range(8):
			await body.physics_sampled
	_check(race.started and race.next_gate == 2, "Real integrated motion passes start and first checkpoint")
	var checkpoint := body.checkpoint_transform
	var event := InputEventKey.new()
	event.physical_keycode = KEY_R
	event.keycode = KEY_R
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await body.physics_sampled
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	_check(body.last_sample.origin.distance_to(checkpoint.origin) < 0.0001 \
		and body.last_sample.linear_velocity.length() < 0.0001 \
		and body.last_sample.angular_velocity.length() < 0.0001,
		"Physical R uses the race checkpoint and cancels momentum through the existing body reset")
	_check(race.next_gate == 2 and not race.lap_valid,
		"The real reset signal preserves ordered progress without awarding a teleport gate")
	world.queue_free()
	await process_frame
	_completed += 1


func _check(passed: bool, message: String) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		push_error("FAIL: " + message)
