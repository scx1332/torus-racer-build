extends SceneTree
## Run: godot --headless --path . --script res://tests/gyro_conservation.gd -- --manual
## Omitting --manual is the negative control: stock Jolt omits gyroscopic dynamics.

const DURATION := 6.0
# Permit finite-step error at 240 Hz, but reject visible momentum drift or
# artificial spin-up: a torque-free body conserves world L and kinetic energy.
const MAX_DIRECTION_ERROR_DEGREES := 3.0
const MAX_MOMENTUM_ERROR := 0.02
const MAX_ENERGY_ERROR := 0.02

class ConservationBody extends TorusBody:

	var baseline_momentum := Vector3.ZERO
	var baseline_energy: float = 0.0
	var max_direction_error: float = 0.0
	var max_momentum_error: float = 0.0
	var max_energy_error: float = 0.0
	var finite_state: bool = true
	var seeded: bool = false
	var launch_valid: bool = false
	var launch_spin: float = 0.0
	var launch_transverse: float = 0.0
	var sampled_contacts: int = 0


	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		if not seeded:
			# This sole transverse impulse excites torque-free precession. The
			# parent adds its own axial launch impulse in this same callback.
			var inertia_world := state.inverse_inertia_tensor.inverse()
			state.apply_torque_impulse(inertia_world * Vector3(0.0, 3.0, 0.0))
		super._integrate_forces(state)
		var inertia_world := state.inverse_inertia_tensor.inverse()
		var omega := state.angular_velocity
		var momentum := inertia_world * omega
		var energy := 0.5 * omega.dot(momentum)
		finite_state = finite_state and momentum.is_finite() and is_finite(energy)
		sampled_contacts += state.get_contact_count()
		if not seeded:
			baseline_momentum = momentum
			baseline_energy = energy
			var axle := state.transform.basis.x.normalized()
			launch_spin = omega.dot(axle)
			launch_transverse = (omega - axle * launch_spin).length()
			# Without both components, principal-axis rotation can falsely pass
			# conservation even when the gyroscopic term is entirely missing.
			# Allow 0.01 rad/s for numerical error in the launch impulses.
			launch_valid = absf(launch_spin - 24.0) < 0.01 \
				and absf(launch_transverse - 3.0) < 0.01
			seeded = true
		elif finite_state:
			max_direction_error = maxf(max_direction_error,
				rad_to_deg(momentum.angle_to(baseline_momentum)))
			max_momentum_error = maxf(max_momentum_error,
				absf(momentum.length() / baseline_momentum.length() - 1.0))
			max_energy_error = maxf(max_energy_error,
				absf(energy / baseline_energy - 1.0))


var _body: ConservationBody
var _next_sample: float = 1.0


func _initialize() -> void:
	var version := Engine.get_version_info()
	if version.major != 4 or version.minor != 7:
		push_error("Conservation validation requires Godot 4.7.x.")
		quit(2)
		return
	if ProjectSettings.get_setting("physics/3d/physics_engine") != "Jolt Physics":
		push_error("Conservation validation requires built-in Jolt Physics.")
		quit(2)
		return
	_start.call_deferred()


func _start() -> void:
	_body = ConservationBody.new()
	_body.name = "FreeFlightTorus"
	_body.gravity_scale = 0.0
	_body.collision_layer = 0
	_body.collision_mask = 0
	_body.linear_damping = 0.0
	_body.angular_damping = 0.0
	_body.initial_spin = 24.0
	_body.automatic_nudge = false
	_body.manual_gyroscope = "--manual" in OS.get_cmdline_user_args()
	root.add_child(_body)
	print("CONSERVATION gyro=%s duration=%.1f hz=%d" % [
		"manual" if _body.manual_gyroscope else "native", DURATION,
		Engine.physics_ticks_per_second])


func _physics_process(_delta: float) -> bool:
	if not is_instance_valid(_body) or not _body.seeded:
		return false
	if _body.elapsed >= _next_sample:
		print("t=%.1f L_direction_error=%.3fdeg L_magnitude_error=%.3f%% energy_error=%.3f%%" % [
			_body.elapsed, _body.max_direction_error,
			100.0 * _body.max_momentum_error, 100.0 * _body.max_energy_error])
		_next_sample += 1.0
	if _body.elapsed >= DURATION or not _body.finite_state or not _body.launch_valid:
		var passed := _body.finite_state and _body.launch_valid and _body.sampled_contacts == 0 \
			and _body.max_direction_error < MAX_DIRECTION_ERROR_DEGREES \
			and _body.max_momentum_error < MAX_MOMENTUM_ERROR \
			and _body.max_energy_error < MAX_ENERGY_ERROR
		print("LAUNCH %s axial=%.4f rad/s transverse=%.4f rad/s" % [
			"PASS" if _body.launch_valid else "FAIL", _body.launch_spin, _body.launch_transverse])
		print("CONSERVATION %s L_direction_error=%.3fdeg L_magnitude_error=%.3f%% energy_error=%.3f%% finite=%s contacts=%d" % [
			"PASS" if passed else "FAIL", _body.max_direction_error,
			100.0 * _body.max_momentum_error, 100.0 * _body.max_energy_error,
			_body.finite_state, _body.sampled_contacts])
		quit(0 if passed else 1)
	return false
