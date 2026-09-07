extends SceneTree
## A horizontal external torque must not create vertical angular momentum.
## Optional --uncoupled-gyro restores the old integrator as a failing control.

const DURATION := 6.0
const APPLIED_TORQUE := 30.0
const MAX_MOMENTUM_ERROR := 0.2
const MAX_VERTICAL_MOMENTUM := 0.1
const MAX_WORK_ERROR := 0.02

class ForcedBody extends TorusBody:
	var uncoupled_gyro := false
	var seeded := false
	var initial_energy := 0.0
	var initial_spin_measured := 0.0
	var external_work := 0.0
	var expected_momentum := Vector3.ZERO
	var previous_omega := Vector3.ZERO
	var previous_torque := Vector3.ZERO
	var previous_step := 0.0
	var max_momentum_error := 0.0
	var max_vertical_momentum := 0.0
	var max_work_error := 0.0
	var max_transverse_speed := 0.0
	var max_gyro_torque := 0.0
	var max_vertical_input := 0.0
	var minimum_input_torque := INF
	var sampled_contacts := 0
	var finite_state := true

	func _apply_player_input(state: PhysicsDirectBodyState3D, axle: Vector3) -> void:
		# Controlled external torque rotates angular momentum in the horizontal
		# plane. Keep this independent of the game's current banking controls.
		input_torque = axle.cross(Vector3.UP).normalized() * APPLIED_TORQUE
		state.apply_torque(input_torque)

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		super._integrate_forces(state)
		var omega := state.angular_velocity
		var momentum := state.inverse_inertia_tensor.inverse() * omega
		var energy := 0.5 * omega.dot(momentum)
		var axle := state.transform.basis.x.normalized()
		if not seeded:
			initial_energy = energy
			initial_spin_measured = omega.dot(axle)
			expected_momentum = momentum
			seeded = true
		else:
			# The previous callback supplied the torque for the completed step.
			expected_momentum += previous_torque * previous_step
			# Integrate external work P = torque dot omega with midpoint velocity.
			external_work += previous_torque.dot((previous_omega + omega) * 0.5) * previous_step
			max_momentum_error = maxf(max_momentum_error, momentum.distance_to(expected_momentum))
			max_vertical_momentum = maxf(max_vertical_momentum, absf(momentum.y))
			max_work_error = maxf(max_work_error, absf(energy - initial_energy - external_work))
		previous_omega = omega
		previous_torque = input_torque
		previous_step = state.step
		max_transverse_speed = maxf(max_transverse_speed, omega.slide(axle).length())
		max_gyro_torque = maxf(max_gyro_torque, gyroscopic_torque.length())
		max_vertical_input = maxf(max_vertical_input, absf(input_torque.y))
		minimum_input_torque = minf(minimum_input_torque, input_torque.length())
		sampled_contacts += state.get_contact_count()
		finite_state = finite_state and momentum.is_finite() and expected_momentum.is_finite() \
			and is_finite(energy) and is_finite(external_work)

	func _apply_gyroscopic_torque(state: PhysicsDirectBodyState3D, orientation: Basis) -> void:
		if not uncoupled_gyro:
			super._apply_gyroscopic_torque(state, orientation)
			return
		# Negative control: omitting the external torque from the midpoint was
		# the production bug. It manufactures vertical momentum under steering.
		var inertia := state.inverse_inertia_tensor.inverse()
		var omega := state.angular_velocity
		var midpoint := omega
		for iteration in range(6):
			var torque := -midpoint.cross(inertia * midpoint)
			midpoint = omega + state.inverse_inertia_tensor * torque * (state.step * 0.5)
		gyroscopic_torque = -midpoint.cross(inertia * midpoint)
		state.apply_torque(gyroscopic_torque)

var _body: ForcedBody
var _failures := 0


func _initialize() -> void:
	var version := Engine.get_version_info()
	if version.major != 4 or version.minor != 7 \
		or ProjectSettings.get_setting("physics/3d/physics_engine") != "Jolt Physics":
		push_error("Forced gyro validation requires Godot 4.7.x with built-in Jolt.")
		quit(2)
		return
	_start.call_deferred()


func _start() -> void:
	_body = ForcedBody.new()
	_body.controls_enabled = true
	_body.automatic_nudge = false
	_body.manual_gyroscope = true
	_body.initial_spin = 24.0
	_body.gravity_scale = 0.0
	_body.collision_layer = 0
	_body.collision_mask = 0
	_body.linear_damping = 0.0
	_body.angular_damping = 0.0
	_body.tuning.rumble_enabled = false
	_body.uncoupled_gyro = "--uncoupled-gyro" in OS.get_cmdline_user_args()
	root.add_child(_body)


func _physics_process(_delta: float) -> bool:
	if not is_instance_valid(_body) or not _body.seeded or _body.elapsed < DURATION:
		return false
	_check(_body.finite_state and _body.sampled_contacts == 0, "finite state without contact impulses")
	_check(absf(_body.initial_spin_measured - 24.0) < 0.01, "fixture starts with real axial spin")
	_check(_body.minimum_input_torque > 29.99 and _body.max_vertical_input < 0.00001,
		"full horizontal steering torque acts throughout the test")
	_check(_body.max_transverse_speed > 0.1 and _body.max_gyro_torque > 5.0,
		"steering excites transverse rotation and gyroscopic coupling")
	_check(_body.max_vertical_momentum < MAX_VERTICAL_MOMENTUM,
		"horizontal torque preserves vertical angular momentum")
	_check(_body.max_momentum_error < MAX_MOMENTUM_ERROR,
		"world angular momentum follows the integrated external torque")
	_check(_body.max_work_error < MAX_WORK_ERROR, "rotational energy follows external torque work")
	print("FORCED GYRO %s mode=%s duration=%.1fs hz=%d L_error=%.6f Ly_error=%.6f work_error=%.6f failures=%d" % [
		"PASS" if _failures == 0 else "FAIL", "uncoupled" if _body.uncoupled_gyro else "production",
		DURATION, Engine.physics_ticks_per_second, _body.max_momentum_error,
		_body.max_vertical_momentum, _body.max_work_error, _failures])
	quit(0 if _failures == 0 else 1)
	return false


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
