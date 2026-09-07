class_name TorusBody
extends RigidBody3D
## All simulation changes happen in _integrate_forces or helpers called by it.
## Local +X is the axle; the ring lies in the local YZ plane.

signal physics_sampled(sample: Dictionary)
signal reset_completed

@export var controls_enabled: bool = false
@export var tuning: TorusTuning = TorusTuning.new()
@export var water_hazard: WaterHazard

@export_group("Geometry (restart after editing)")
@export_range(0.1, 5.0, 0.01) var major_radius: float = 1.0
@export_range(0.02, 1.0, 0.01) var minor_radius: float = 0.25
@export_range(12, 128, 1) var capsule_count: int = 100

@export_group("Physics")
@export var manual_gyroscope: bool = true
@export_range(0.0, 1.0, 0.001) var angular_damping: float = 0.0
@export_range(0.0, 1.0, 0.001) var linear_damping: float = 0.01
@export_range(0.0, 1.0, 0.01) var surface_friction: float = 0.8

@export_group("Repeatable experiment (restart after editing)")
@export_range(0.0, 40.0, 0.1) var initial_spin: float = 24.0
@export var automatic_nudge: bool = true
@export_range(0.1, 10.0, 0.1) var nudge_after_seconds: float = 2.0
@export_range(-10.0, 10.0, 0.05) var nudge_impulse: float = 8.0

var elapsed: float = 0.0
var lean_degrees: float = 0.0
var heading_radians: float = 0.0
var spin_rate: float = 0.0
var contact_count: int = 0
var gyroscopic_torque := Vector3.ZERO
var has_nudged: bool = false
var grounded: bool = false
var input_torque := Vector3.ZERO
var assist_torque := Vector3.ZERO
var bank_pivot_impulse := Vector3.ZERO
var bank_pivot_position := Vector3.ZERO
var bank_pivot_torque_impulse := Vector3.ZERO
var _support_contacts: Array = []
var last_sample: Dictionary = {}
var input_reader: TorusInput
var checkpoint_transform := Transform3D.IDENTITY
var _initialized: bool = false
var _reset_requested: bool = false
var _hop_locked: bool = false
var _air_time: float = 0.0
var _rumble_timer: float = 0.0
var _previous_velocity := Vector3.ZERO
var water_pending: bool = false
var water_remaining: float = 0.0
var water_position := Vector3.ZERO


func _ready() -> void:
	mass = 3.0
	can_sleep = false
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 16
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.0
	TorusGeometry.build(self, major_radius, minor_radius, capsule_count)
	checkpoint_transform = global_transform
	input_reader = TorusInput.new()
	input_reader.name = "PlayerInput"
	input_reader.tuning = tuning
	add_child(input_reader)


func set_checkpoint(checkpoint: Transform3D) -> void:
	checkpoint_transform = checkpoint.orthonormalized()


func request_reset() -> void:
	_reset_requested = true


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	linear_damp = linear_damping
	angular_damp = angular_damping
	physics_material_override.friction = surface_friction
	input_torque = Vector3.ZERO
	assist_torque = Vector3.ZERO  # Phase 3 will supply this separate torque layer.
	bank_pivot_impulse = Vector3.ZERO
	bank_pivot_position = Vector3.ZERO
	bank_pivot_torque_impulse = Vector3.ZERO
	if _reset_requested or (controls_enabled and Input.is_action_just_pressed("reset")):
		_reset_to_checkpoint(state)
		_publish_sample(state, {"contacts": [], "slip_ratio": 0.0})
		return
	if _update_water_hazard(state):
		_publish_sample(state, {"contacts": [], "slip_ratio": 0.0})
		return
	var orientation := state.transform.basis.orthonormalized()
	var axle := orientation.x
	if not _initialized:
		# One launch impulse supplies angular momentum Iω about the ring axle.
		# No velocity assignment: ground friction subsequently produces rolling.
		var world_inertia := state.inverse_inertia_tensor.inverse()
		state.apply_torque_impulse(world_inertia * (axle * initial_spin))
		_initialized = true
	var contact_data := TorusContacts.sample(state, axle,
		major_radius + minor_radius, tuning.ground_normal_min_dot)
	grounded = contact_data.grounded
	_support_contacts = contact_data.contacts
	if not water_pending:
		_update_landing(state, contact_data.impact_impulse)
	if controls_enabled and not water_pending:
		input_reader.tuning = tuning
		_apply_player_input(state, axle)

	elapsed += state.step
	if automatic_nudge and not has_nudged and elapsed >= nudge_after_seconds:
		# One angular impulse about the forward axis tips the axle out of level.
		# There is no continuing steering or righting force after this nudge.
		var lean_axis := axle.cross(Vector3.UP).normalized()
		state.apply_torque_impulse(lean_axis * nudge_impulse)
		has_nudged = true

	gyroscopic_torque = Vector3.ZERO
	if manual_gyroscope:
		_apply_gyroscopic_torque(state, orientation)

	contact_count = state.get_contact_count()
	_publish_sample(state, contact_data)
	_previous_velocity = state.linear_velocity


func _update_water_hazard(state: PhysicsDirectBodyState3D) -> bool:
	if not is_instance_valid(water_hazard) or not water_hazard.enabled:
		water_pending = false
		water_remaining = 0.0
		water_position = Vector3.ZERO
		return false
	if water_pending:
		water_remaining = maxf(0.0, water_remaining - state.step)
	else:
		var center := state.transform.origin + state.center_of_mass
		var axle := state.transform.basis.x.normalized()
		var water := water_hazard.sample(center, axle, major_radius, minor_radius)
		if not water.submerged:
			return false
		water_pending = true
		water_remaining = water_hazard.respawn_delay
		water_position = water.position
		# One event per fall. Presentation can be removed without affecting rescue.
		water_hazard.water_entered.emit(water_position, maxf(0.0, -state.linear_velocity.y))
	if water_remaining <= 0.0:
		# Reuse the impulse-based reset; the following physics tick relaunches spin.
		_reset_to_checkpoint(state)
		return true
	return false


func _apply_player_input(state: PhysicsDirectBodyState3D, axle: Vector3) -> void:
	var actions := input_reader.sample()
	var drive := actions.x * tuning.acceleration_torque
	var spin := state.angular_velocity.dot(axle)
	var inverse_axle_inertia := axle.dot(state.inverse_inertia_tensor * axle)
	var brake_direction := signf(spin) if not is_zero_approx(spin) else signf(drive)
	# Brake opposes current spin. Cap its one-step effect at zero, accounting
	# for simultaneous acceleration; LT alone never becomes a reverse motor.
	var brake_limit := maxf(0.0, absf(spin) / (state.step * inverse_axle_inertia)
		+ brake_direction * drive)
	var brake := minf(actions.y * tuning.braking_torque, brake_limit) * brake_direction
	# Axial drive accelerates rolling through ground friction. Banking controls
	# the axle tilt; no player torque directly commands a yaw rate or heading.
	input_torque = axle * (drive - brake)
	if not tuning.direct_lean:
		input_torque += TorusSteering.bank_torque(state, axle, actions.z, tuning)
	state.apply_torque(input_torque)
	if tuning.direct_lean:
		if grounded and not is_zero_approx(actions.z):
			_lean_about_support(state, actions.z)
	elif grounded and not _hop_locked and not is_zero_approx(actions.z) \
			and not Input.is_action_just_pressed("hop"):
		# The lower-pivot reaction supplies both linear impulse J and angular
		# impulse r x J. Keep this support constraint off during hops and flight.
		bank_pivot_impulse = TorusSteering.pivot_impulse(state, axle, _support_contacts, tuning)
		bank_pivot_position = TorusSteering.pivot_point(_support_contacts, tuning.lean_pivot_height)
		var arm := bank_pivot_position - (state.transform.origin + state.center_of_mass)
		bank_pivot_torque_impulse = arm.cross(bank_pivot_impulse)
		state.apply_impulse(bank_pivot_impulse, bank_pivot_position - state.transform.origin)
	if Input.is_action_just_pressed("hop") and grounded and not _hop_locked:
		# One upward impulse, allowed once until a genuine airborne/landing cycle.
		state.apply_central_impulse(Vector3.UP * tuning.hop_impulse)
		_hop_locked = true


func _lean_about_support(state: PhysicsDirectBodyState3D, steering: float) -> void:
	# Back-to-basics steering: rotate the whole body kinematically about its
	# ground support point, tipping sideways around the travel axis so the
	# bottom stays planted while the top swings over (up to lying flat).
	# This bypasses forces entirely; lean_rate_limit sets the tipping speed
	# and releasing the input keeps the current lean.
	if _support_contacts.is_empty():
		return
	var travel := state.linear_velocity.slide(Vector3.UP)
	var axis := travel.normalized() if travel.length() > 0.5 \
		else state.transform.basis.x.cross(Vector3.UP).normalized()
	if axis.is_zero_approx():
		return
	var pivot := TorusSteering.pivot_point(_support_contacts, 0.0)
	var rotation := Basis(axis, deg_to_rad(tuning.lean_rate_limit) * steering * state.step)
	var transform := state.transform
	transform.basis = (rotation * transform.basis).orthonormalized()
	transform.origin = pivot + rotation * (transform.origin - pivot)
	state.transform = transform
	# Carry the spin along so the gyroscope does not fight the imposed lean.
	state.angular_velocity = rotation * state.angular_velocity


func _update_landing(state: PhysicsDirectBodyState3D, impact: float) -> void:
	_rumble_timer = maxf(0.0, _rumble_timer - state.step)
	var landed := grounded and _air_time >= tuning.hop_rearm_airtime
	if landed:
		_hop_locked = false
	_air_time = 0.0 if grounded else _air_time + state.step
	var hard_landing := landed and -_previous_velocity.y >= tuning.landing_rumble_speed
	if not controls_enabled or not tuning.rumble_enabled or _rumble_timer > 0.0:
		return
	if (hard_landing or impact >= tuning.collision_rumble_impulse) \
			and input_reader.active_joypad in Input.get_connected_joypads():
		Input.start_joy_vibration(input_reader.active_joypad, 0.25, 0.5, 0.12)
		_rumble_timer = tuning.rumble_cooldown


func _reset_to_checkpoint(state: PhysicsDirectBodyState3D) -> void:
	# Reset alone relocates the body. Cancel momentum with additive impulses;
	# neither driving nor resetting assigns linear/angular velocity directly.
	state.apply_central_impulse(-state.linear_velocity / state.inverse_mass)
	state.apply_torque_impulse(-(state.inverse_inertia_tensor.inverse() * state.angular_velocity))
	state.transform = checkpoint_transform
	state.sleeping = false
	_reset_requested = false
	_initialized = false
	_hop_locked = false
	_air_time = 0.0
	_previous_velocity = Vector3.ZERO
	water_pending = false
	water_remaining = 0.0
	water_position = Vector3.ZERO
	grounded = false
	contact_count = 0
	_support_contacts = []
	bank_pivot_impulse = Vector3.ZERO
	bank_pivot_position = Vector3.ZERO
	bank_pivot_torque_impulse = Vector3.ZERO
	gyroscopic_torque = Vector3.ZERO
	elapsed = 0.0
	has_nudged = false
	reset_completed.emit()


func _publish_sample(state: PhysicsDirectBodyState3D, contacts: Dictionary) -> void:
	var axle := state.transform.basis.x.normalized()
	lean_degrees = rad_to_deg(asin(clampf(axle.y, -1.0, 1.0)))
	heading_radians = atan2(-axle.z, axle.x)
	spin_rate = state.angular_velocity.dot(axle)
	# Read-only snapshots let HUD/debug nodes be removed without changing forces.
	last_sample = {
		"delta": state.step,
		"origin": state.transform.origin + state.center_of_mass,
		"linear_velocity": state.linear_velocity, "angular_velocity": state.angular_velocity,
		"spin_axis": axle, "input_torque": input_torque, "assist_torque": assist_torque,
		"gyroscopic_torque": -state.angular_velocity.cross(
			state.inverse_inertia_tensor.inverse() * state.angular_velocity),
		"gyro_applied_torque": gyroscopic_torque, "contacts": contacts.contacts,
		"bank_pivot_impulse": bank_pivot_impulse,
		"bank_pivot_position": bank_pivot_position,
		"bank_pivot_torque_impulse": bank_pivot_torque_impulse,
		"bank_pivot_force": bank_pivot_impulse / state.step,
		"bank_pivot_torque": bank_pivot_torque_impulse / state.step,
		"speed": state.linear_velocity.length(), "spin_rate": spin_rate,
		"lean_degrees": lean_degrees, "grounded": grounded, "slip_ratio": contacts.slip_ratio,
		"water_pending": water_pending, "water_remaining": water_remaining,
		"water_position": water_position,
	}
	physics_sampled.emit(last_sample)


func _apply_gyroscopic_torque(state: PhysicsDirectBodyState3D, orientation: Basis) -> void:
	# Recover the full local tensor from Jolt's world inverse tensor, including
	# any principal-axis rotation, then I_world = B * I_local * Bᵀ.
	var local_inverse := orientation.transposed() * state.inverse_inertia_tensor * orientation
	var local_inertia := local_inverse.inverse()
	var world_inertia := orientation * local_inertia * orientation.transposed()
	var omega := state.angular_velocity
	# Euler gyroscopic term: τ_gyro = -ω × (I_world ω).
	# Evaluate it at the implicit midpoint: raw forward Euler artificially adds
	# rotational energy. Six fixed-point iterations converge at this scene's
	# 240 Hz and spin range. This changes only the torque's numerical integration.
	var midpoint_omega := omega
	# Player/assist torques act during the same step. Including them in the
	# midpoint prevents artificial angular-momentum drift while steering.
	var external_torque := input_torque + assist_torque
	for iteration in range(6):
		var midpoint_torque := -midpoint_omega.cross(world_inertia * midpoint_omega)
		midpoint_omega = omega + state.inverse_inertia_tensor \
			* (external_torque + midpoint_torque) * (state.step * 0.5)
	gyroscopic_torque = -midpoint_omega.cross(world_inertia * midpoint_omega)
	state.apply_torque(gyroscopic_torque)
