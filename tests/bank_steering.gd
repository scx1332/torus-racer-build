extends SceneTree
## Matched motorcycle-bank inputs in independent worlds, using the playable scene.
## Preserve the previous controller's 100-capsule fixture with native gravity and gyro.

const LAB := preload("res://controls_lab.tscn")
const PRELUDE_TICKS := 480
const STEERING_TICKS := 480
const BANK_TOLERANCE := 3.0

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Input.use_accumulated_input = false
	for analog in [false, true]:
		for drive in [false, true]:
			var right := await _scenario(analog, drive, 1.0)
			var left := await _scenario(analog, drive, -1.0)
			_compare_pair(right, left)
	print("ROLLING STEERING %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _scenario(analog: bool, drive: bool, direction: float) -> Dictionary:
	_clear_inputs()
	# Reusing the root physics world lets earlier solver/contact state contaminate comparisons.
	var world := SubViewport.new()
	world.world_3d = World3D.new()
	root.add_child(world)
	var scene := LAB.instantiate()
	var body := scene.get_node("Torus") as TorusBody
	# The scene may carry a slow hand-testing tune; pin the reference tune here.
	body.tuning = TorusTuning.new()
	body.tuning.rumble_enabled = false
	body.tuning.direct_lean = false
	body.tuning.lean_torque = 30.0
	body.initial_spin = 24.0
	body.capsule_count = 100
	body.linear_damping = 0.01
	world.add_child(scene)
	var name := "%s %s %s" % ["analog" if analog else "keyboard",
		"drive" if drive else "coast", "right" if direction > 0.0 else "left"]
	var capsules := 0
	for child in body.get_children():
		if child is CollisionShape3D and child.shape is CapsuleShape3D:
			capsules += 1
	_check(body.capsule_count == 100 and capsules == 100, name + ": default 100-capsule rim")
	_check(is_equal_approx(body.tuning.lean_angle_limit, 25.0), name + ": default target is 25 degrees")
	_key(KEY_UP, drive)
	for tick in range(PRELUDE_TICKS):
		await body.physics_sampled
	var start := body.last_sample.duplicate(true)
	var forward: Vector3 = start.linear_velocity
	forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	_check(start.speed > 5.0 and absf(start.spin_rate) > 5.0 and start.grounded,
		name + ": starts rolling, spinning and grounded")
	# Raw stick 0.575 maps to halfway past the 0.15 deadzone, then exponent 1.5.
	var target_bank := 25.0 * (pow(0.5, 1.5) if analog else 1.0)
	if analog:
		_stick(0.575 * direction)
	else:
		_key(KEY_RIGHT if direction > 0.0 else KEY_LEFT, true)
	var banks := PackedFloat64Array()
	var grounded := 0
	var air_ticks := 0
	var longest_airborne := 0
	var peak_bank := 0.0
	var final_half_min := INF
	var final_half_sum := 0.0
	var final_half_turn := 0.0
	var turn := 0.0
	var peak_clearance := 0.0
	var finite := true
	var chord_inset := body.major_radius * (1.0 - cos(PI / body.capsule_count))
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity")) * body.gravity_scale
	# Maximum ballistic duration of a skip rising one tube radius; include two sample ticks.
	var maximum_skip := 2.0 * sqrt(2.0 * body.minor_radius / gravity) \
		+ 2.0 / Engine.physics_ticks_per_second
	for tick in range(STEERING_TICKS):
		await body.physics_sampled
		var sample := body.last_sample
		var signed_bank: float = sample.lean_degrees * direction
		banks.append(sample.lean_degrees)
		peak_bank = maxf(peak_bank, absf(sample.lean_degrees))
		grounded += int(sample.grounded)
		air_ticks = 0 if sample.grounded else air_ticks + 1
		longest_airborne = maxi(longest_airborne, air_ticks)
		var axle: Vector3 = sample.spin_axis
		var support_height := body.major_radius * sqrt(maxf(0.0, 1.0 - axle.y * axle.y)) \
			+ body.minor_radius
		peak_clearance = maxf(peak_clearance, float(sample.origin.y) - support_height + chord_inset)
		var velocity: Vector3 = sample.linear_velocity
		velocity.y = 0.0
		turn = rad_to_deg(atan2(velocity.dot(right), velocity.dot(forward))) * direction
		if tick >= STEERING_TICKS / 2:
			final_half_min = minf(final_half_min, signed_bank)
			final_half_sum += signed_bank
			final_half_turn += turn
		finite = finite and (sample.origin as Vector3).is_finite() \
			and (sample.linear_velocity as Vector3).is_finite() \
			and (sample.angular_velocity as Vector3).is_finite()
	var final_bank := banks[-1] * direction
	var mean_bank := final_half_sum / (STEERING_TICKS / 2)
	var mean_turn := final_half_turn / (STEERING_TICKS / 2)
	_check(finite and peak_bank <= target_bank + 5.0,
		"%s: finite motion and bounded bank overshoot (peak %.2f target %.2f)" % [name, peak_bank, target_bank])
	_check(absf(final_bank - target_bank) <= BANK_TOLERANCE,
		"%s: reaches target bank (final %.2f target %.2f)" % [name, final_bank, target_bank])
	_check(final_half_min > 0.0 and absf(mean_bank - target_bank) <= BANK_TOLERANCE,
		"%s: sustains requested bank during final second (min %.2f mean %.2f)" % [name, final_half_min, mean_bank])
	# A short countersteer while banking is allowed. Afterwards actual travel must turn
	# toward the requested bank; this deliberately imposes no arcade yaw-angle target.
	_check(turn > 0.0 and mean_turn > 0.0,
		"%s: physical travel turns toward the bank (final %.2f mean %.2f)" % [name, turn, mean_turn])
	_check(grounded > 0 and peak_clearance < body.minor_radius \
		and float(longest_airborne) / Engine.physics_ticks_per_second < maximum_skip,
		name + ": recurring ground support with skips smaller than one tube radius")
	print("BANK %s: target=%.3f final=%.3f mean_last=%.3f min_last=%.3f peak=%.3f turn=%.3f turn_mean=%.3f ground=%d/%d air_max=%.4fs clearance=%.4fm" % [
		name, target_bank, final_bank, mean_bank, final_half_min, peak_bank, turn, mean_turn,
		grounded, STEERING_TICKS, float(longest_airborne) / Engine.physics_ticks_per_second, peak_clearance])
	_clear_inputs()
	world.queue_free()
	await process_frame
	return {"name": name, "start": start, "banks": banks, "grounded": grounded}


func _compare_pair(right: Dictionary, left: Dictionary) -> void:
	var a: Dictionary = right.start
	var b: Dictionary = left.start
	var same_start := true
	for field in ["origin", "linear_velocity", "angular_velocity", "spin_axis"]:
		same_start = same_start and Vector3(a[field]).distance_to(Vector3(b[field])) < 0.0001
	_check(same_start and a.grounded == b.grounded, right.name + ": mirrored run starts from matching physical state")
	var mirror_error := 0.0
	for tick in range(STEERING_TICKS):
		mirror_error += absf(right.banks[tick] + left.banks[tick]) / STEERING_TICKS
	_check(mirror_error < 1.0, "%s: mirrored bank mean error %.4f stays below 1 degree" % [right.name, mirror_error])
	print("BANK MIRROR %s: same_start=%s mean_error=%.5fdeg ground_right=%d ground_left=%d start_position=%s start_velocity=%s" % [
		right.name, same_start, mirror_error, right.grounded, left.grounded, a.origin, a.linear_velocity])


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _stick(value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _clear_inputs() -> void:
	for code in [KEY_UP, KEY_LEFT, KEY_RIGHT]:
		_key(code, false)
	_stick(0.0)


func _check(passed: bool, message: String) -> void:
	if not passed:
		_failures += 1
		push_error("FAIL: " + message)
