extends SceneTree
## Headless controls regressions using real Jolt bodies and additive inputs.

class Probe extends TorusBody:
	var seed_impulse := Vector3.ZERO
	var seeded: bool = false
	var inverse_tensor := Basis.IDENTITY
	var tick_step: float = 0.0
	var press_hop: bool = false
	var _release_hop: bool = false

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		if _release_hop:
			Input.action_release("hop")
		_release_hop = press_hop
		if press_hop:
			# action_press schedules just_pressed for the following physics tick;
			# tests await both injection and consumption, independent of rendering.
			Input.action_press("hop")
			press_hop = false
		if not seeded:
			# Test launch supplies momentum through the same impulse API as hop.
			state.apply_central_impulse(seed_impulse)
			seeded = true
		inverse_tensor = state.inverse_inertia_tensor
		tick_step = state.step
		super._integrate_forces(state)

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TorusInput.install_actions()
	var version := Engine.get_version_info()
	_check(version.major == 4 and version.minor == 7, "Godot 4.7.x")
	_check(ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics", "Jolt backend")
	await _test_acceleration()
	await _test_brakes()
	await _test_lean()
	await _test_direct_lean()
	await _test_hop()
	await _test_wall_contact()
	await _test_reset()
	_release_inputs()
	print("CONTROLS PHYSICS %s checks=%d failures=%d" % [
		"PASS" if _failures == 0 else "FAIL", _checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)


func _release_inputs() -> void:
	for action in TorusInput.ACTIONS:
		Input.action_release(action)


func _body(spin: float = 0.0, orientation: Basis = Basis.IDENTITY) -> Probe:
	_release_inputs()
	var body := Probe.new()
	body.controls_enabled = true
	body.automatic_nudge = false
	body.manual_gyroscope = false
	body.initial_spin = spin
	body.gravity_scale = 0.0
	body.linear_damping = 0.0
	body.angular_damping = 0.0
	body.surface_friction = 0.0
	body.tuning.rumble_enabled = false
	body.tuning.direct_lean = false
	body.tuning.lean_torque = 30.0
	body.position = Vector3(0, 10, 0)
	body.basis = orientation
	root.add_child(body)
	await body.physics_sampled
	return body


func _ticks(body: Probe, count: int) -> Dictionary:
	for tick in range(count):
		await body.physics_sampled
	return body.last_sample


func _dispose(body: Probe) -> void:
	_release_inputs()
	body.queue_free()
	await process_frame


func _drive_delta(strength: float, brake: float = 0.0) -> float:
	var body := await _body(6.0)
	Input.action_press("accelerate", strength)
	if brake > 0.0:
		Input.action_press("brake", brake)
	var start := await _ticks(body, 1)
	var finish := await _ticks(body, 60)
	var torque := body.tuning.acceleration_torque * strength - body.tuning.braking_torque * brake
	_check((finish.input_torque as Vector3).is_equal_approx(Vector3.RIGHT * torque),
		"axle torque follows independent accel %.2f / brake %.2f strengths" % [strength, brake])
	var delta: float = finish.spin_rate - start.spin_rate
	var expected := torque * body.inverse_tensor.x.x * body.tick_step * 60.0
	_check(absf(delta - expected) < 0.002, "actual spin change matches torque / inertia integration")
	_check((finish.angular_velocity as Vector3).is_finite(), "accelerating state stays finite")
	await _dispose(body)
	return delta


func _test_acceleration() -> void:
	var full := await _drive_delta(1.0)
	var quarter := await _drive_delta(0.25)
	_check(absf(full - quarter * 4.0) < 0.002, "quarter trigger produces quarter spin acceleration")
	await _drive_delta(0.7, 0.2)


func _test_brakes() -> void:
	for spin in [2.0, -2.0, 0.0001, -0.0001, 0.0]:
		var body := await _body(spin)
		Input.action_press("brake", 1.0)
		var minimum := INF
		var maximum := -INF
		for tick in range(150):
			var sample := await _ticks(body, 1)
			minimum = minf(minimum, sample.spin_rate)
			maximum = maxf(maximum, sample.spin_rate)
		var kept_sign: bool = minimum >= -0.00001 if spin >= 0.0 else maximum <= 0.00001
		_check(kept_sign, "brake never reverses initial spin %.5f" % spin)
		_check(absf(body.spin_rate) < 0.0001, "brake reaches rest from spin %.5f" % spin)
		await _dispose(body)
	var together := await _body(0.0001)
	Input.action_press("accelerate", 0.2)
	Input.action_press("brake", 1.0)
	var result := await _ticks(together, 1)
	_check((result.input_torque as Vector3).x < 0.0,
		"brake cap accounts for simultaneous acceleration near zero")
	await _dispose(together)
	var stopped := await _body()
	Input.action_press("accelerate", 0.5)
	Input.action_press("brake", 1.0)
	var held := await _ticks(stopped, 60)
	_check(absf(held.spin_rate) < 0.00001 and (held.input_torque as Vector3).is_zero_approx(),
		"simultaneous triggers keep a stopped ring still when brake exceeds drive")
	await _dispose(stopped)


func _test_lean() -> void:
	for yaw in [0.0, PI * 0.5]:
		for direction: float in [-1.0, 1.0]:
			var action := "lean_right" if direction > 0.0 else "lean_left"
			var description := "%s at yaw %.0f" % [action, rad_to_deg(yaw)]
			var stopped := await _body(0.0, Basis(Vector3.UP, yaw))
			stopped.tuning.lean_damping = 0.0 # Isolate the low-spin actuator.
			Input.action_press(action, 1.0)
			var low_spin := await _ticks(stopped, 1)
			var axle: Vector3 = low_spin.spin_axis
			var fallback := axle.cross(Vector3.UP).normalized() \
				* direction * stopped.tuning.lean_low_spin_torque
			_check((low_spin.input_torque as Vector3).is_equal_approx(fallback),
				"low-spin roll torque follows the ring: " + description)
			var tipped := await _ticks(stopped, 20)
			_check(tipped.lean_degrees * direction > 0.1,
				"low-spin input physically tips toward the requested side: " + description)
			await _dispose(stopped)

			# Start slightly banked so world UP is distinguishable from its
			# projection into the ring plane; preserve real high-spin gyroscopy.
			var orientation := Basis(Vector3.UP, yaw) \
				* Basis(Vector3.BACK, deg_to_rad(5.0 * direction))
			var spinning := await _body(24.0, orientation)
			spinning.manual_gyroscope = true
			spinning.tuning.lean_damping = 0.0 # Isolate the gyroscopic bank axis.
			Input.action_press(action, 1.0)
			var high_spin := await _ticks(spinning, 1)
			axle = high_spin.spin_axis
			var bank_axis := Vector3.UP.slide(axle).normalized()
			var torque: Vector3 = high_spin.input_torque
			_check(torque.normalized().is_equal_approx(bank_axis * direction) \
				and absf(torque.length() - spinning.tuning.lean_torque) < 0.001,
				"high-spin bank torque uses the ring's projected-up axis and torque cap: " + description)
			_check(absf(torque.dot(axle.cross(Vector3.UP).normalized())) < 0.0001,
				"high-spin input does not apply the former forward-axis yaw torque: " + description)
			var banked := await _ticks(spinning, 60)
			_check(banked.lean_degrees * direction > 7.0,
				"high-spin gyro input increases the requested bank: " + description)
			_check((banked.linear_velocity as Vector3).is_zero_approx() \
				and spinning.bank_pivot_impulse.is_zero_approx(),
				"airborne banking adds no pivot or linear impulse: " + description)
			_release_inputs()
			var released := await _ticks(spinning, 1)
			_check((released.input_torque as Vector3).is_zero_approx(),
				"releasing bank input adds no automatic righting torque: " + description)
			await _dispose(spinning)

	# At 6 rad/s, a 6 N m/(rad/s) feedback gain leaves headroom below the
	# torque cap, so the rate-feedback law can be checked independently.
	var damped := await _body(6.0)
	damped.manual_gyroscope = true
	damped.tuning.lean_damping = 6.0
	Input.action_press("lean_right", 1.0)
	var starting := await _ticks(damped, 1)
	var forward := (starting.spin_axis as Vector3).cross(Vector3.UP).normalized()
	var requested_rate := deg_to_rad(damped.tuning.lean_rate_limit)
	_check(absf((starting.input_torque as Vector3).dot(forward) \
		- requested_rate * damped.tuning.lean_damping) < 0.0001,
		"bank-rate feedback starts rolling toward the requested rate")
	var moving := await _ticks(damped, 30)
	forward = (moving.spin_axis as Vector3).cross(Vector3.UP).normalized()
	_check((moving.angular_velocity as Vector3).dot(forward) > 0.05,
		"rate-feedback fixture develops actual rightward bank motion")
	Input.action_release("lean_right")
	Input.action_press("lean_left", 1.0)
	var reversing := await _ticks(damped, 1)
	forward = (reversing.spin_axis as Vector3).cross(Vector3.UP).normalized()
	var actual_rate := (reversing.angular_velocity as Vector3).dot(forward)
	var expected_feedback := (-requested_rate - actual_rate) * damped.tuning.lean_damping
	_check((reversing.input_torque as Vector3).length() < damped.tuning.lean_torque - 0.1 \
		and absf((reversing.input_torque as Vector3).dot(forward) - expected_feedback) < 0.0001,
		"reversing bank input counters the measured bank rate without torque clipping")
	_release_inputs()
	var released := await _ticks(damped, 1)
	_check((released.input_torque as Vector3).is_zero_approx(),
		"releasing input disables bank-rate feedback as well as bank actuation")
	await _dispose(damped)


func _test_hop() -> void:
	var floor := StaticBody3D.new()
	floor.position.y = -0.5
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, 1, 100)
	collider.shape = shape
	floor.add_child(collider)
	root.add_child(floor)
	var body := await _body()
	body.gravity_scale = 1.0
	body.manual_gyroscope = true
	# The free-flight helper disables friction; ground-contact checks need the
	# playable surface friction to dissipate tangential motion from landing.
	body.surface_friction = 0.8
	body.set_checkpoint(Transform3D(Basis.IDENTITY, Vector3(0, 1.28, 0)))
	body.request_reset()
	await _ticks(body, 2)
	for tick in range(240):
		if body.grounded:
			break
		await _ticks(body, 1)
	await _ticks(body, 24)
	_check(body.grounded, "real floor contact permits hop")
	var world_contacts: bool = not body.last_sample.contacts.is_empty()
	var tangent_traction: bool = world_contacts
	for contact: Dictionary in body.last_sample.contacts:
		world_contacts = world_contacts and (contact.normal as Vector3).dot(Vector3.UP) > 0.99 \
			and absf((contact.position as Vector3).y) < 0.03
		tangent_traction = tangent_traction and absf((contact.traction as Vector3).dot(contact.normal)) < 0.0001
	_check(world_contacts, "floor contact points and normals use world coordinates")
	_check(tangent_traction, "support traction excludes the normal contact impulse")
	_check(body.last_sample.slip_ratio < 0.001, "resting ring has negligible contact slip")
	body.press_hop = true
	var hop := await _ticks(body, 2)
	_check((hop.linear_velocity as Vector3).y > 2.5, "ground hop adds upward momentum")
	body.press_hop = true
	var immediately := await _ticks(body, 2)
	_check((immediately.linear_velocity as Vector3).y <= (hop.linear_velocity as Vector3).y + 0.01,
		"immediate hop repress cannot reuse a stale ground contact")
	await _ticks(body, 6)
	_check(not body.grounded, "hop leaves the real floor")
	var previous_y: float = body.last_sample.linear_velocity.y
	for attempt in range(4):
		body.press_hop = true
		var airborne := await _ticks(body, 2)
		_check((airborne.linear_velocity as Vector3).y <= previous_y + 0.01,
			"airborne hop repress %d adds no impulse" % attempt)
		previous_y = airborne.linear_velocity.y
		await _ticks(body, 1)
	for tick in range(300):
		if body.grounded:
			break
		await _ticks(body, 1)
	_check(body.grounded, "hop returns to ground")
	_check((body.last_sample.linear_velocity as Vector3).y < 1.0,
		"airborne requests do not queue another hop on landing")
	body.press_hop = true
	var second := await _ticks(body, 2)
	_check((second.linear_velocity as Vector3).y > 2.5, "landing rearms hop")
	await _dispose(body)
	floor.queue_free()
	await process_frame


func _test_wall_contact() -> void:
	var wall := StaticBody3D.new()
	wall.position = Vector3(0.75, 10, 0)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 100, 100)
	collider.shape = shape
	wall.add_child(collider)
	root.add_child(wall)
	var body := await _body()
	body.seeded = false
	body.seed_impulse = Vector3(3, 0, 0)
	for tick in range(120):
		await _ticks(body, 1)
		if body.contact_count > 0:
			break
	_check(body.contact_count > 0, "real wall produces rigid-body contacts")
	_check(not body.grounded and body.last_sample.contacts.is_empty(),
		"wall-only contacts do not count as ground support")
	var before_y: float = body.last_sample.linear_velocity.y
	body.press_hop = true
	var sample := await _ticks(body, 2)
	_check(body.contact_count > 0 and not sample.grounded, "hop is evaluated while touching only wall")
	_check(absf((sample.linear_velocity as Vector3).y - before_y) < 0.0001,
		"wall-only hop request adds no upward momentum")
	await _dispose(body)
	wall.queue_free()
	await process_frame


func _test_reset() -> void:
	var body := await _body(12.0)
	body.seeded = false
	body.seed_impulse = Vector3(21, 9, -15)
	Input.action_press("lean_right")
	await _ticks(body, 30)
	_check(body.last_sample.speed > 1.0, "reset test starts with linear momentum")
	var checkpoint := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(20, 8, -12))
	body.set_checkpoint(checkpoint)
	_release_inputs()
	body.request_reset()
	var reset := await _ticks(body, 1)
	_check((reset.origin as Vector3).is_equal_approx(checkpoint.origin), "reset relocates to checkpoint")
	_check((reset.spin_axis as Vector3).is_equal_approx(checkpoint.basis.x), "reset restores checkpoint heading")
	_check((reset.linear_velocity as Vector3).length() < 0.0001, "reset impulses cancel linear momentum")
	_check((reset.angular_velocity as Vector3).length() < 0.0001, "reset impulses cancel angular momentum")
	_check((reset.input_torque as Vector3).is_zero_approx(), "reset clears player torque")
	_check(not reset.grounded and reset.contacts.is_empty(), "reset clears stale contacts")
	var launched := await _ticks(body, 1)
	_check(absf(launched.spin_rate - 12.0) < 0.001, "next tick launches along checkpoint axle")
	_check((launched.linear_velocity as Vector3).length() < 0.0001, "reset launch preserves cancelled linear momentum")
	await _dispose(body)


func _test_direct_lean() -> void:
	# Direct lean is kinematic: while grounded, steering rotates the whole body
	# about its ground support point around the travel axis at lean_rate_limit,
	# applying no steering torque or assist impulse. Releasing keeps the lean.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(400.0, 1.0, 400.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor_body)
	for yaw in [0.0, PI * 0.5]:
		var body := await _body(12.0, Basis(Vector3.UP, yaw))
		body.manual_gyroscope = true
		body.gravity_scale = 1.0
		body.surface_friction = 0.8
		body.tuning.direct_lean = true
		body.position = Vector3(0.0, body.major_radius + body.minor_radius + 0.02, 0.0)
		var settled := await _ticks(body, 240)
		_check(body.grounded and (settled.linear_velocity as Vector3).length() > 1.0,
			"direct-lean fixture rolls on support at yaw %.0f" % rad_to_deg(yaw))
		var start_lean := absf(body.lean_degrees)
		var start_heading: float = body.heading_radians
		var travel := (settled.linear_velocity as Vector3).slide(Vector3.UP).normalized()
		var camera_right := travel.cross(Vector3.UP).normalized()
		Input.action_press("lean_right", 1.0)
		var during := await _ticks(body, 60)
		_check((during.input_torque as Vector3).slide(during.spin_axis as Vector3).is_zero_approx(),
			"direct lean applies no steering torque at yaw %.0f" % rad_to_deg(yaw))
		_check((during.bank_pivot_impulse as Vector3).is_zero_approx(),
			"direct lean applies no pivot assist impulse at yaw %.0f" % rad_to_deg(yaw))
		var held_lean := absf(body.lean_degrees)
		var gained := held_lean - start_lean
		var commanded := body.tuning.lean_rate_limit * 60.0 / 240.0
		_check(gained > commanded * 0.5 and gained < commanded * 2.0,
			"held input tips near lean_rate_limit (%.2f of %.2f deg) at yaw %.0f"
				% [gained, commanded, rad_to_deg(yaw)])
		var top := Vector3.UP.slide(during.spin_axis as Vector3).normalized()
		_check(top.dot(camera_right) > 0.0,
			"right input tips the top toward camera-right at yaw %.0f" % rad_to_deg(yaw))
		var heading_change := absf(rad_to_deg(angle_difference(start_heading, body.heading_radians)))
		_check(heading_change < held_lean,
			"lean input tips rather than yaws (heading change %.2f deg) at yaw %.0f"
				% [heading_change, rad_to_deg(yaw)])
		Input.action_release("lean_right")
		await _ticks(body, 30)
		_check(absf(body.lean_degrees) > held_lean * 0.5,
			"releasing the input keeps the lean at yaw %.0f" % rad_to_deg(yaw))
		await _dispose(body)
	floor_body.queue_free()
	await process_frame
