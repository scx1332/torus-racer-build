extends SceneTree
## Long holds, reversal and release with the optional previous bank controller.
## Keep the 100-capsule rim, ground contact, gyro and bank pivot enabled.

const LAB := preload("res://controls_lab.tscn")
const SETTLING_SECONDS := 3
const BANK_TOLERANCE := 3.0

var _body: TorusBody
var _name := ""
var _start_forward := Vector3.ZERO
var _start_right := Vector3.ZERO
var _last_heading := 0.0
var _total_heading := 0.0
var _air_ticks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Input.use_accumulated_input = false
	for drive in [false, true]:
		_clear_inputs()
		_name = "accelerating" if drive else "coasting"
		var world := SubViewport.new()
		world.world_3d = World3D.new()
		root.add_child(world)
		var scene := LAB.instantiate()
		_body = scene.get_node("Torus") as TorusBody
		# The scene may carry a slow hand-testing tune; pin the reference tune here.
		_body.tuning = TorusTuning.new()
		_body.tuning.rumble_enabled = false
		_body.tuning.direct_lean = false
		_body.tuning.lean_torque = 30.0
		_body.initial_spin = 24.0
		_body.capsule_count = 100
		_body.linear_damping = 0.01
		world.add_child(scene)
		_check(_body.capsule_count == 100 and _body.manual_gyroscope \
			and _body.tuning.lean_pivot_strength > 0.0 \
			and is_equal_approx(_body.tuning.lean_angle_limit, 25.0),
			_name + ": default 100-capsule bank fixture includes gyro and pivot")
		_key(KEY_UP, drive)
		for tick in range(2 * Engine.physics_ticks_per_second):
			await _body.physics_sampled
		_start_forward = Vector3(_body.last_sample.linear_velocity).slide(Vector3.UP).normalized()
		_start_right = _start_forward.cross(Vector3.UP)
		_last_heading = 0.0
		_total_heading = 0.0
		_air_ticks = 0
		_check(_body.last_sample.speed > 5.0 and absf(_body.spin_rate) > 5.0,
			_name + ": lifecycle starts with real rolling speed and spin")
		await _phase("hold right", 1.0, 6)
		await _phase("reverse left", -1.0, 4)
		await _phase("release", 0.0, 3)
		_clear_inputs()
		world.queue_free()
		await process_frame
	print("STEERING LIFECYCLE %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _phase(phase: String, direction: float, seconds: int) -> void:
	_key(KEY_RIGHT, direction > 0.0)
	_key(KEY_LEFT, direction < 0.0)
	var label := _name + " " + phase
	var hz := Engine.physics_ticks_per_second
	var target := _body.tuning.lean_angle_limit * direction
	var initial_heading := _total_heading
	var previous_second_heading := _total_heading
	var minimum_settled_turn := INF
	var settled_turn_windows := 0
	var settled_bank_error := 0.0
	var peak_bank := 0.0
	var grounded_ticks := 0
	var longest_airborne := 0
	var peak_clearance := 0.0
	var max_bank_torque := 0.0
	var max_pivot_impulse := 0.0
	var finite := true
	var chord_inset := _body.major_radius * (1.0 - cos(PI / _body.capsule_count))
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity")) * _body.gravity_scale
	# A tube-radius bounce sets both the clearance and ballistic flight bound.
	var maximum_skip := 2.0 * sqrt(2.0 * _body.minor_radius / gravity) + 2.0 / hz
	for tick in range(seconds * hz):
		await _body.physics_sampled
		var sample := _body.last_sample
		var axle: Vector3 = sample.spin_axis
		var velocity: Vector3 = sample.linear_velocity
		var heading := atan2(velocity.dot(_start_right), velocity.dot(_start_forward))
		# Unwrap travel heading so long turns and reversals can cross +/-180 degrees.
		_total_heading += wrapf(heading - _last_heading, -PI, PI)
		_last_heading = heading
		peak_bank = maxf(peak_bank, absf(sample.lean_degrees))
		grounded_ticks += int(sample.grounded)
		_air_ticks = 0 if sample.grounded else _air_ticks + 1
		longest_airborne = maxi(longest_airborne, _air_ticks)
		var support := _body.major_radius * sqrt(maxf(0.0, 1.0 - axle.y * axle.y)) \
			+ _body.minor_radius
		peak_clearance = maxf(peak_clearance, float(sample.origin.y) - support + chord_inset)
		max_bank_torque = maxf(max_bank_torque, Vector3(sample.input_torque).slide(axle).length())
		max_pivot_impulse = maxf(max_pivot_impulse, _body.bank_pivot_impulse.length())
		finite = finite and Vector3(sample.origin).is_finite() \
			and velocity.is_finite() and Vector3(sample.angular_velocity).is_finite()
		if direction != 0.0 and tick >= SETTLING_SECONDS * hz:
			settled_bank_error = maxf(settled_bank_error, absf(sample.lean_degrees - target))
		if (tick + 1) % hz == 0:
			if direction != 0.0 and tick + 1 > SETTLING_SECONDS * hz:
				var turn := rad_to_deg(_total_heading - previous_second_heading) * direction
				minimum_settled_turn = minf(minimum_settled_turn, turn)
				settled_turn_windows += 1
			previous_second_heading = _total_heading
	_check(finite and peak_bank < 45.0, label + ": remains finite and upright")
	_check(grounded_ticks > 0 and peak_clearance < _body.minor_radius \
		and float(longest_airborne) / hz < maximum_skip,
		label + ": recurring support with only shallow rim skips")
	if direction != 0.0:
		_check(settled_turn_windows > 0 and settled_bank_error <= BANK_TOLERANCE,
			"%s: settles to %+.0f degrees within 3 seconds (worst settled error %.3f)" % [
				label, target, settled_bank_error])
		_check(settled_turn_windows > 0 and minimum_settled_turn > 0.0,
			"%s: travel turns toward the settled bank in every one-second window (min %.3f deg)" % [
				label, minimum_settled_turn])
	else:
		_check(max_bank_torque < 0.0001 and max_pivot_impulse < 0.000001,
			label + ": release disables bank torque and pivot throughout all 3 seconds")
	var settled_turn_text := "%.3f" % minimum_settled_turn if settled_turn_windows > 0 else "n/a"
	print("LIFECYCLE %s: bank=%+.3f peak=%.3f settled_error=%.3f min_settled_turn=%s phase_turn=%+.3f speed=%.3f ground=%d/%d air_max=%.3fs clearance=%.4fm bank_torque_max=%.6f pivot_max=%.6f" % [
		label, _body.lean_degrees, peak_bank, settled_bank_error, settled_turn_text,
		rad_to_deg(_total_heading - initial_heading), _body.last_sample.speed,
		grounded_ticks, seconds * hz, float(longest_airborne) / hz, peak_clearance,
		max_bank_torque, max_pivot_impulse])


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _clear_inputs() -> void:
	for code in [KEY_UP, KEY_LEFT, KEY_RIGHT]:
		_key(code, false)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
