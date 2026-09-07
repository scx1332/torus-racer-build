extends SceneTree
## Real Jolt falls and resets; fixture impulses never bypass force integration.

class Probe extends TorusBody:
	var placement: Dictionary = {}

	func place(origin: Vector3, impulse := Vector3.ZERO) -> void:
		placement = {"origin": origin, "impulse": impulse}

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		if not placement.is_empty():
			# The fixture starts a new fall using the same additive momentum API.
			state.apply_central_impulse(-state.linear_velocity / state.inverse_mass)
			state.apply_torque_impulse(-(state.inverse_inertia_tensor.inverse() * state.angular_velocity))
			state.transform.origin = placement.origin
			state.apply_central_impulse(placement.impulse)
			placement.clear()
		super._integrate_forces(state)

class Fixture extends RefCounted:
	var world: SubViewport
	var hazard: WaterHazard
	var body: Probe
	var splashes: Array[Dictionary] = []
	var resets: int = 0

var _checks: int = 0
var _failures: int = 0
var _completed: int = 0
var _started: int = 0


func _initialize() -> void:
	_started = Time.get_ticks_msec()
	_run.call_deferred()


func _physics_process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _started > 45000:
		push_error("Water hazard test exceeded its bounded 45 second timeout")
		quit(1)
	return false


func _run() -> void:
	TorusInput.install_actions()
	Input.use_accumulated_input = false
	await _geometry()
	for angle in [0.0, 45.0, 90.0, -90.0]:
		await _fall(angle)
	await _fast_crossing_and_manual_reset()
	await _ballistic_jump()
	await _effects_invariance()
	_check(_completed == 8, "All water test stages completed without script errors")
	print("WATER HAZARD %s checks=%d failures=%d" % [
		"PASS" if _failures == 0 else "FAIL", _checks, _failures])
	quit(0 if _failures == 0 else 1)


func _fixture(height: float, angle: float = 0.0, gravity: float = 0.0, spin: float = 0.0) -> Fixture:
	var result := Fixture.new()
	result.world = SubViewport.new()
	result.world.world_3d = World3D.new()
	root.add_child(result.world)
	result.hazard = WaterHazard.new()
	result.hazard.position.y = -4.0
	result.world.add_child(result.hazard)
	result.hazard.water_entered.connect(func(point: Vector3, speed: float) -> void:
		result.splashes.append({"position": point, "speed": speed}))
	result.body = Probe.new()
	result.body.position = Vector3(0.0, height, 0.0)
	result.body.basis = Basis(Vector3.BACK, deg_to_rad(angle))
	result.body.gravity_scale = gravity
	result.body.initial_spin = spin
	result.body.automatic_nudge = false
	result.body.linear_damping = 0.0
	result.body.controls_enabled = true
	result.body.tuning.rumble_enabled = false
	result.body.water_hazard = result.hazard
	result.world.add_child(result.body)
	result.body.reset_completed.connect(func() -> void: result.resets += 1)
	return result


func _ticks(body: TorusBody, count: int) -> void:
	for tick in range(count):
		await body.physics_sampled


func _dispose(fixture: Fixture) -> void:
	fixture.world.queue_free()
	await process_frame


func _geometry() -> void:
	var fixture := _fixture(9.28)
	await _ticks(fixture.body, 2)
	var hazard := fixture.hazard
	for angle in [0.0, 45.0, 90.0, -90.0]:
		var axle := Basis(Vector3.BACK, deg_to_rad(angle)).x
		for radii: Vector2 in [Vector2(1.0, 0.25), Vector2(1.6, 0.35)]:
			var extent := radii.x * cos(deg_to_rad(angle)) + radii.y
			var threshold := hazard.surface_level() - hazard.immersion_depth + extent
			var above := hazard.sample(Vector3(0, threshold + 0.01, 0), axle, radii.x, radii.y)
			var below := hazard.sample(Vector3(0, threshold - 0.01, 0), axle, radii.x, radii.y)
			_check(not above.submerged and below.submerged,
				"Immersion uses the actual torus vertical extent at %.0f degrees, radii %s" % [angle, radii])
	_check(not hazard.sample(Vector3(0, -3.0, 0), Vector3.UP, 1.0, 0.25).submerged,
		"A flat ring above the sea is not tested as an upright bounding sphere")
	_check(not hazard.sample(Vector3(1501, -20, 0), Vector3.RIGHT, 1.0, 0.25).submerged,
		"Water query respects its horizontal bounds")
	hazard.enabled = false
	_check(not hazard.sample(Vector3(0, -20, 0), Vector3.RIGHT, 1.0, 0.25).submerged,
		"Disabled water cannot trigger a fall")
	hazard.enabled = true
	await _ticks(fixture.body, 240)
	_check(fixture.splashes.is_empty() and fixture.resets == 0 and not fixture.body.water_pending,
		"Racing height above the water produces no false splash or reset")
	_completed += 1
	await _dispose(fixture)


func _fall(angle: float) -> void:
	var fixture := _fixture(8.0, angle, 1.0, 12.0)
	var body := fixture.body
	var checkpoint := Transform3D(Basis(Vector3.UP, 0.4), Vector3(20, 8, 10))
	body.set_checkpoint(checkpoint)
	var hit := false
	for tick in range(480):
		await body.physics_sampled
		if body.water_pending:
			hit = true
			break
	_check(hit and fixture.splashes.size() == 1, "A real %.0f degree fall emits one water entry" % angle)
	if hit:
		var sample := body.last_sample
		var axle: Vector3 = sample.spin_axis
		var extent := body.major_radius * sqrt(maxf(0.0, 1.0 - axle.y * axle.y)) + body.minor_radius
		var depth: float = fixture.hazard.surface_level() - (sample.origin.y - extent)
		_check(depth >= fixture.hazard.immersion_depth - 0.0001 \
			and depth <= fixture.hazard.immersion_depth + sample.speed / 240.0 + 0.002,
			"Real entry occurs at the leaned lower rim, within one integration step")
		_check(fixture.splashes[0].speed > 10.0 \
			and is_equal_approx(fixture.splashes[0].position.y, -3.96),
			"Splash reports actual falling speed and the water-surface position")
		Input.action_press("accelerate")
		await _ticks(body, 12)
		Input.action_release("accelerate")
		_check(body.input_torque.is_zero_approx() and fixture.resets == 0 \
			and fixture.splashes.size() == 1 and body.water_remaining > 0.6,
			"Continued immersion blocks controls without repeating splash or resetting early")
		var countdown_ticks := 12
		while fixture.resets == 0 and countdown_ticks < 190:
			await body.physics_sampled
			countdown_ticks += 1
		_check(fixture.resets == 1 and fixture.splashes.size() == 1 \
			and absf(float(countdown_ticks) / 240.0 - fixture.hazard.respawn_delay) <= 1.0 / 240.0,
			"Each fall resets once after the configured physics-time delay")
		var reset := body.last_sample
		_check((reset.origin as Vector3).distance_to(checkpoint.origin) < 0.0001 \
			and (reset.spin_axis as Vector3).distance_to(checkpoint.basis.x) < 0.0001 \
			and (reset.linear_velocity as Vector3).length() < 0.0001 \
			and (reset.angular_velocity as Vector3).length() < 0.0001,
			"Automatic rescue restores checkpoint heading and cancels both momenta")
		_check(not reset.water_pending and is_zero_approx(reset.water_remaining) \
			and reset.contacts.is_empty(), "Rescue clears the water episode and stale contacts")
		await _ticks(body, 1)
		_check(absf(body.spin_rate - body.initial_spin) < 0.001,
			"Only the following physics tick relaunches the initial spin")
	print("WATER FALL angle=%.0f splash_count=%d reset_count=%d" % [
		angle, fixture.splashes.size(), fixture.resets])
	_completed += 1
	await _dispose(fixture)


func _fast_crossing_and_manual_reset() -> void:
	var fixture := _fixture(8.0)
	var body := fixture.body
	await _ticks(body, 2)
	body.place(Vector3(0, -2.8, 0), Vector3.DOWN * body.mass * 400.0)
	await _ticks(body, 2)
	_check(body.water_pending and fixture.splashes.size() == 1 and body.last_sample.origin.y < -4.0,
		"A fast body crossing the whole surface in one tick cannot skip water detection")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_R
	event.keycode = KEY_R
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _ticks(body, 2)
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	_check(fixture.resets == 1 and not body.water_pending and is_zero_approx(body.water_remaining),
		"Physical R cancels the pending rescue and immediately resets")
	await _ticks(body, 210)
	_check(fixture.resets == 1 and fixture.splashes.size() == 1,
		"Cancelled delayed rescue never fires again after manual reset")
	body.place(Vector3(0, -8, 0))
	await _ticks(body, 1)
	_check(body.water_pending and fixture.splashes.size() == 2,
		"The next fall rearms after manual reset")
	await _ticks(body, 190)
	_check(fixture.resets == 2 and fixture.splashes.size() == 2 and not body.water_pending,
		"The rearmed fall also produces exactly one automatic rescue")
	_completed += 1
	await _dispose(fixture)


func _ballistic_jump() -> void:
	var fixture := _fixture(9.28, 0.0, 1.0, 24.0)
	var body := fixture.body
	await _ticks(body, 1)
	body.place(Vector3(0, 9.28, 0), Vector3(0, 7, 20) * body.mass)
	var peak := 0.0
	for tick in range(336):
		await body.physics_sampled
		peak = maxf(peak, body.last_sample.origin.y)
	_check(peak > 11.5 and body.last_sample.origin.z > 25.0 and not body.grounded,
		"Fixture exercises a real ballistic airborne jump above the sea")
	_check(fixture.splashes.is_empty() and fixture.resets == 0 and not body.water_pending,
		"Normal airborne travel does not cause a water rescue")
	_completed += 1
	await _dispose(fixture)


func _effects_invariance() -> void:
	var plain := _fixture(8.0, 23.0, 1.0, 24.0)
	var observed := _fixture(8.0, 23.0, 1.0, 24.0)
	var effects := WaterEffects.new()
	effects.hazard = observed.hazard
	observed.world.add_child(effects)
	var max_error := 0.0
	for tick in range(720):
		await physics_frame
		if plain.body.last_sample.is_empty() or observed.body.last_sample.is_empty():
			continue
		for key in ["origin", "linear_velocity", "angular_velocity", "spin_axis"]:
			var left: Vector3 = plain.body.last_sample[key]
			var right: Vector3 = observed.body.last_sample[key]
			max_error = maxf(max_error, left.distance_to(right))
		if tick == 480:
			effects.queue_free()
	_check(max_error < 0.00001 and plain.splashes.size() == 1 and observed.splashes.size() == 1 \
		and plain.resets == 1 and observed.resets == 1,
		"Adding then removing splash effects preserves all 720 real fall/reset physics samples")
	print("WATER EFFECT INVARIANCE max_difference=%.8f" % max_error)
	_completed += 1
	await _dispose(plain)
	await _dispose(observed)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
