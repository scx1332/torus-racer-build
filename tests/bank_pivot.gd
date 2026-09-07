extends SceneTree
## Exercise the explicit banking pivot with actual Jolt support and hop input.

class Probe extends TorusBody:
	var tick_step: float = 0.0
	var before_velocity := Vector3.ZERO
	var before_angular := Vector3.ZERO
	var inverse_tensor := Basis.IDENTITY
	var press_hop: bool = false
	var inspect_helper: bool = false
	var helper_results: Dictionary = {}
	var _release_hop: bool = false

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		if _release_hop:
			Input.action_release("hop")
		_release_hop = press_hop
		if press_hop:
			# Schedule the mapped hop edge for the following physics tick.
			Input.action_press("hop")
			press_hop = false
		tick_step = state.step
		before_velocity = state.linear_velocity
		before_angular = state.angular_velocity
		inverse_tensor = state.inverse_inertia_tensor
		if inspect_helper:
			_probe_helper(state)
			inspect_helper = false
		super._integrate_forces(state)

	func _probe_helper(state: PhysicsDirectBodyState3D) -> void:
		var axle := state.transform.basis.x.normalized()
		var contacts: Array = TorusContacts.sample(state, axle,
			major_radius + minor_radius, tuning.ground_normal_min_dot).contacts
		var settings := tuning.duplicate() as TorusTuning
		var velocity := state.linear_velocity
		var angular := state.angular_velocity
		settings.lean_pivot_strength = 0.0
		helper_results["zero_strength"] = TorusSteering.pivot_impulse(state, axle, contacts, settings)
		settings.lean_pivot_strength = 1.0
		helper_results["no_support"] = TorusSteering.pivot_impulse(state, axle, [], settings)
		# A gentle response avoids saturation when comparing two pivot heights.
		settings.lean_pivot_response = 1.0
		settings.lean_pivot_max_acceleration = 50.0
		settings.lean_pivot_height = 0.0
		helper_results["low"] = TorusSteering.pivot_impulse(state, axle, contacts, settings)
		settings.lean_pivot_height = 0.25
		helper_results["raised"] = TorusSteering.pivot_impulse(state, axle, contacts, settings)
		var point := TorusSteering.pivot_point(contacts, settings.lean_pivot_height)
		var arm := point - (state.transform.origin + state.center_of_mass)
		var impulse: Vector3 = helper_results.raised
		var next_velocity := velocity + impulse * state.inverse_mass
		var next_angular := angular + state.inverse_inertia_tensor * arm.cross(impulse)
		helper_results["energy_before"] = kinetic_energy(velocity, angular)
		helper_results["energy_after"] = kinetic_energy(next_velocity, next_angular)
		settings.lean_pivot_strength = 0.4
		settings.lean_pivot_max_acceleration = 0.05
		helper_results["limited"] = TorusSteering.pivot_impulse(state, axle, contacts, settings)
		helper_results["bound"] = 0.4 * 0.05 * state.step / state.inverse_mass
		helper_results["forward"] = axle.cross(Vector3.UP).normalized()
		helper_results["bank_rate"] = angular.dot(helper_results.forward)
		helper_results["grounded"] = not contacts.is_empty()
		helper_results["unchanged"] = state.linear_velocity == velocity and state.angular_velocity == angular

	func kinetic_energy(velocity: Vector3, angular: Vector3) -> float:
		return 0.5 * (mass * velocity.length_squared() + angular.dot(inverse_tensor.inverse() * angular))

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TorusInput.install_actions()
	var world := SubViewport.new()
	world.world_3d = World3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.position.y = -0.5
	ground.physics_material_override = PhysicsMaterial.new()
	ground.physics_material_override.friction = 0.8
	var shape := BoxShape3D.new()
	shape.size = Vector3(1000.0, 1.0, 1000.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	ground.add_child(collider)
	world.add_child(ground)
	var body := Probe.new()
	body.position.y = 1.28
	body.controls_enabled = true
	body.automatic_nudge = false
	body.tuning.rumble_enabled = false
	body.tuning.direct_lean = false
	body.tuning.lean_torque = 30.0
	body.tuning.lean_pivot_strength = 1.0
	world.add_child(body)
	await _ticks(body, 480)
	_check(body.grounded and body.last_sample.speed > 5.0, "Fixture rolls on real support")
	_check(body.bank_pivot_impulse.is_zero_approx(), "No bank input leaves pivot off")
	Input.action_press("lean_right", 1.0)
	var active_ticks := 0
	var bounded := true
	var preserves_forward := true
	var angular_reaction := true
	var linear_reaction := true
	var passive := true
	for tick in range(120):
		await _ticks(body, 1)
		var impulse: Vector3 = body.last_sample.bank_pivot_impulse
		var forward: Vector3 = body.last_sample.spin_axis.cross(Vector3.UP).normalized()
		active_ticks += int(not impulse.is_zero_approx())
		bounded = bounded and impulse.is_finite() and impulse.length() \
			<= body.mass * body.tuning.lean_pivot_max_acceleration * body.tick_step + 0.000001
		preserves_forward = preserves_forward and absf(impulse.dot(forward)) < 0.000001
		var angular_change: Vector3 = body.last_sample.angular_velocity - body.before_angular
		var expected_angular: Vector3 = body.inverse_tensor * body.last_sample.bank_pivot_torque_impulse
		angular_reaction = angular_reaction and angular_change.distance_to(expected_angular) < 0.00001
		var linear_change: Vector3 = body.last_sample.linear_velocity - body.before_velocity
		linear_reaction = linear_reaction and linear_change.distance_to(impulse / body.mass) < 0.00001
		var before_energy := body.kinetic_energy(body.before_velocity, body.before_angular)
		var after_energy := body.kinetic_energy(body.last_sample.linear_velocity, body.last_sample.angular_velocity)
		passive = passive and after_energy <= before_energy + 0.0001
		if tick == 30:
			body.inspect_helper = true
	_check(active_ticks > 10, "Held bank input activates the supported pivot")
	_check(bounded, "Pivot impulse stays within mass times acceleration times delta")
	_check(preserves_forward, "Pivot never supplies a forward impulse")
	_check(angular_reaction, "Actual angular change matches inverse inertia times r cross J")
	_check(linear_reaction, "Actual linear change matches the support impulse divided by mass")
	_check(passive, "Every support impulse preserves or dissipates total kinetic energy")
	_test_helper_results(body.helper_results)
	body.tuning.lean_pivot_strength = 0.0
	await _ticks(body, 8)
	_check(body.bank_pivot_impulse.is_zero_approx(), "Zero strength disables the live body correction")
	body.tuning.lean_pivot_strength = 1.0
	Input.action_release("lean_right")
	await _ticks(body, 4)
	_check(body.bank_pivot_impulse.is_zero_approx(), "Releasing bank input disables the correction")
	Input.action_press("lean_right", 1.0)
	for tick in range(120):
		await _ticks(body, 1)
		if body.grounded and not body.bank_pivot_impulse.is_zero_approx():
			break
	_check(body.grounded and not body.bank_pivot_impulse.is_zero_approx(),
		"Hop starts with lean held and pivot active on support")
	body.press_hop = true
	await _ticks(body, 2)
	var hop_change: float = body.last_sample.linear_velocity.y - body.before_velocity.y
	_check(absf(hop_change - body.tuning.hop_impulse / body.mass) < 0.0001,
		"Leaning hop retains its full upward impulse")
	_check(body.bank_pivot_impulse.is_zero_approx(), "Pivot is off on the hop impulse tick")
	var airborne_ticks := 0
	var pivot_off := true
	for tick in range(36):
		await _ticks(body, 1)
		airborne_ticks += int(not body.grounded)
		pivot_off = pivot_off and body.bank_pivot_impulse.is_zero_approx()
	_check(airborne_ticks > 20, "Held-lean hop leaves the floor")
	_check(pivot_off, "Hop lock and airborne guard keep pivot off after takeoff")
	body.queue_free()
	await process_frame
	var airborne := Probe.new()
	airborne.position.y = 10.0
	airborne.gravity_scale = 0.0
	airborne.controls_enabled = true
	airborne.automatic_nudge = false
	# Direct lean is kinematic and grounded-only; this probe checks the bank
	# controller's free-flight torque, so select that mode explicitly.
	airborne.tuning.direct_lean = false
	world.add_child(airborne)
	await _ticks(airborne, 24)
	_check(not airborne.grounded and not airborne._hop_locked and airborne.input_torque.length() > 0.1,
		"Free-flight probe banks without a hop lock or support")
	_check(airborne.bank_pivot_impulse.is_zero_approx(), "Unsupported banking never applies pivot impulse")
	for action in TorusInput.ACTIONS:
		Input.action_release(action)
	world.queue_free()
	await process_frame
	print("BANK PIVOT %s checks=%d failures=%d active_ticks=%d airborne_ticks=%d" % [
		"PASS" if _failures == 0 else "FAIL", _checks, _failures, active_ticks, airborne_ticks])
	quit(0 if _failures == 0 else 1)


func _test_helper_results(results: Dictionary) -> void:
	_check(not results.is_empty(), "Helper probe runs inside force integration")
	if results.is_empty():
		return
	_check(results.grounded and absf(results.bank_rate) > 0.001,
		"Helper probe has actual contacts and a nonzero bank rate")
	_check(results.zero_strength.is_zero_approx(), "Helper returns zero at zero strength")
	_check(results.no_support.is_zero_approx(), "Helper returns zero without support")
	_check(results.low.distance_to(results.raised) > 0.000001,
		"Raising the pivot changes the banking lever response")
	_check(absf(results.limited.length() - results.bound) < 0.0000001,
		"A capped helper impulse respects fractional strength and acceleration budget")
	_check(absf(results.raised.dot(results.forward)) < 0.000001,
		"Changing pivot height still preserves forward travel")
	_check(results.unchanged, "Helper calculation itself does not mutate velocities")
	_check(results.energy_after <= results.energy_before + 0.0001,
		"Raised-pivot helper impulse satisfies the kinetic energy bound")


func _ticks(body: Probe, count: int) -> void:
	for tick in range(count):
		await body.physics_sampled


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
