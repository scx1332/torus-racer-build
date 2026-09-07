class_name TorusSteering
extends RefCounted
## Motorcycle-like bank input plus an explicit grounded pivot correction.


static func bank_torque(state: PhysicsDirectBodyState3D, axle: Vector3,
		steering: float, tuning: TorusTuning) -> Vector3:
	if is_zero_approx(steering):
		return Vector3.ZERO # Releasing input does not automatically stand us up.
	var forward := axle.cross(Vector3.UP).normalized()
	var bank_axis := Vector3.UP.slide(axle).normalized()
	if forward.is_zero_approx() or bank_axis.is_zero_approx():
		return Vector3.ZERO
	var bank := asin(clampf(axle.y, -1.0, 1.0))
	var target := deg_to_rad(tuning.lean_angle_limit) * steering
	var rate_limit := deg_to_rad(tuning.lean_rate_limit)
	var bank_rate := clampf((target - bank) * tuning.lean_response, -rate_limit, rate_limit)
	var momentum := state.inverse_inertia_tensor.inverse() * state.angular_velocity
	var spin := state.angular_velocity.dot(axle)
	# Gyroscopic bank actuator: tau = Omega_bank x L_spin. This rotates the
	# old forward torque axis by 90 degrees, changing bank instead of commanding yaw.
	var torque := bank_axis * momentum.dot(axle) * bank_rate
	# Dampen bank-rate nutation while the player controls bank, without damping
	# axle spin. A bank-angle controller without this transverse damping excites
	# the gyro's oscillatory mode even when its final yaw points the correct way.
	torque += forward * (bank_rate - state.angular_velocity.dot(forward)) * tuning.lean_damping
	# Near rest the gyroscope has little authority; ordinary roll torque lets
	# the player tip the body. This fades out completely above 2 rad/s spin.
	var low_spin := 1.0 - smoothstep(0.0, 2.0, absf(spin))
	torque += forward * bank_rate / maxf(rate_limit, 0.001) \
		* tuning.lean_low_spin_torque * low_spin
	return torque.limit_length(tuning.lean_torque)


static func pivot_impulse(state: PhysicsDirectBodyState3D, axle: Vector3,
		contacts: Array, tuning: TorusTuning) -> Vector3:
	if contacts.is_empty() or tuning.lean_pivot_strength <= 0.0:
		return Vector3.ZERO
	var forward := axle.cross(Vector3.UP).normalized()
	if forward.is_zero_approx():
		return Vector3.ZERO
	var pivot := pivot_point(contacts, tuning.lean_pivot_height)
	var center := state.transform.origin + state.center_of_mass
	var arm := pivot - center
	var side := forward.cross(Vector3.UP).normalized()
	var contact_velocity := state.linear_velocity + state.angular_velocity.cross(arm)
	# Effective mass includes the angular reaction r x J at the support point.
	# A COM-only correction suppresses the contact torque needed to turn into bank.
	var side_response := side * state.inverse_mass \
		+ (state.inverse_inertia_tensor * arm.cross(side)).cross(arm)
	var up_response := Vector3.UP * state.inverse_mass \
		+ (state.inverse_inertia_tensor * arm.cross(Vector3.UP)).cross(arm)
	var a := side.dot(side_response)
	var b := side.dot(up_response)
	var c := Vector3.UP.dot(side_response)
	var d := Vector3.UP.dot(up_response)
	var determinant := a * d - b * c
	if determinant <= 0.0:
		return Vector3.ZERO
	var blend := 1.0 - exp(-tuning.lean_pivot_response * state.step)
	var change_side := -contact_velocity.dot(side) * blend
	var change_up := -contact_velocity.y * blend
	# Solve K J = -v_contact in the banking plane, without a forward impulse.
	# Scaling this dissipative impulse by 0..1 preserves its passive energy bound.
	var impulse := side * ((d * change_side - b * change_up) / determinant) \
		+ Vector3.UP * ((a * change_up - c * change_side) / determinant)
	return impulse.limit_length(tuning.lean_pivot_max_acceleration * state.step \
		/ state.inverse_mass) * tuning.lean_pivot_strength


static func pivot_point(contacts: Array, height: float) -> Vector3:
	if contacts.is_empty():
		return Vector3.ZERO
	var position := Vector3.ZERO
	var normal := Vector3.ZERO
	for contact: Dictionary in contacts:
		position += Vector3(contact.position)
		normal += Vector3(contact.normal)
	return position / float(contacts.size()) + normal.normalized() * height
