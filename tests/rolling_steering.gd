extends SceneTree
## Regression for steering that was weak and reversed with real rolling contact.
## Use the playable scene, its default tuning, mapped input events and native
## collision response. Do not disable gravity, friction or gyroscopic torque.
## Steering leans the ring about its travel axis; the turn follows from gravity
## acting on the leaned rolling ring, so it is slower than the lean itself and
## weakens as spin rises. Minimum turns are set per scenario accordingly.

const LAB := preload("res://controls_lab.tscn")
const PRELUDE_TICKS := 480
const STEERING_TICKS := 480
## Lean input is a short tap; a held key at the default lean rate would tip the
## ring far past its balance point, exactly as a real rider would not do.
const HOLD_TICKS := 72

var _failures: int = 0
var _full_right_turn: float = 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Input.use_accumulated_input = false
	for scenario: Dictionary in [
		{"name": "right key coasting", "right": true, "drive": false, "stick": 0.0, "min_turn": 8.0},
		{"name": "left key coasting", "right": false, "drive": false, "stick": 0.0, "min_turn": 8.0},
		{"name": "right key accelerating", "right": true, "drive": true, "stick": 0.0, "min_turn": 3.0},
		{"name": "left key accelerating", "right": false, "drive": true, "stick": 0.0, "min_turn": 3.0},
		{"name": "partial right stick", "right": true, "drive": false, "stick": 0.575, "min_turn": 3.0},
		{"name": "partial left stick accelerating", "right": false, "drive": true, "stick": -0.575, "min_turn": 1.0},
	]:
		await _scenario(scenario)
	print("ROLLING STEERING %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _scenario(settings: Dictionary) -> void:
	var scene := LAB.instantiate()
	var body := scene.get_node("Torus") as TorusBody
	# The scene may carry a slow hand-testing tune; pin the reference tune here.
	body.tuning = TorusTuning.new()
	body.tuning.rumble_enabled = false
	body.initial_spin = 24.0
	root.add_child(scene)
	_clear_inputs()
	if settings.drive:
		_key(KEY_UP, true)
	await _ticks(body, PRELUDE_TICKS)
	var start_position: Vector3 = body.last_sample.origin
	var forward: Vector3 = body.last_sample.linear_velocity
	forward.y = 0.0
	forward = forward.normalized()
	# Camera-relative right is travel cross world up, NOT body-local +X.
	var right := forward.cross(Vector3.UP).normalized()
	_check(body.last_sample.speed > 5.0 and absf(body.spin_rate) > 5.0,
		settings.name + ": fixture is genuinely rolling and spinning")
	var direction := 1.0 if settings.right else -1.0
	if settings.stick != 0.0:
		_stick(settings.stick)
	else:
		_key(KEY_RIGHT if settings.right else KEY_LEFT, true)
	var ground_ticks := 0
	var peak_lean := 0.0
	var correct_lean := 0.0
	var finite := true
	var air_ticks := 0
	var longest_airborne := 0
	var peak_clearance := 0.0
	var peak_vertical_speed := 0.0
	var minimum_height := INF
	var maximum_height := -INF
	var chord_inset := body.major_radius * (1.0 - cos(PI / body.capsule_count))
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity")) * body.gravity_scale
	# A skip rising one tube radius under gravity takes this long to land.
	# Permit two contact-sampling ticks at takeoff/landing. This is a geometry-
	# and gravity-based bound, independent of the solver's contact duty cycle.
	var maximum_skip_duration := 2.0 * sqrt(2.0 * body.minor_radius / gravity) \
		+ 2.0 / Engine.physics_ticks_per_second
	for tick in range(STEERING_TICKS):
		await body.physics_sampled
		if tick == HOLD_TICKS:
			_clear_inputs()
			if settings.drive:
				_key(KEY_UP, true)
		var sample := body.last_sample
		ground_ticks += int(sample.grounded)
		air_ticks = 0 if sample.grounded else air_ticks + 1
		longest_airborne = maxi(longest_airborne, air_ticks)
		peak_lean = maxf(peak_lean, absf(sample.lean_degrees))
		# Geometry-independent top of the ring: project world up into its plane.
		var axle: Vector3 = sample.spin_axis
		# Ideal torus support height above the flat lab floor. Add the maximum
		# chord inset to conservatively bound clearance of the compound rim.
		var support_height := body.major_radius * sqrt(maxf(0.0, 1.0 - axle.y * axle.y)) \
			+ body.minor_radius
		var height: float = sample.origin.y
		peak_clearance = maxf(peak_clearance, height - support_height + chord_inset)
		peak_vertical_speed = maxf(peak_vertical_speed, absf(sample.linear_velocity.y))
		minimum_height = minf(minimum_height, height)
		maximum_height = maxf(maximum_height, height)
		var top := Vector3.UP.slide(axle).normalized()
		correct_lean = maxf(correct_lean, rad_to_deg(asin(clampf(
			top.dot(right) * direction, -1.0, 1.0))))
		finite = finite and (sample.origin as Vector3).is_finite() \
			and (sample.linear_velocity as Vector3).is_finite() \
			and (sample.angular_velocity as Vector3).is_finite()
	var velocity: Vector3 = body.last_sample.linear_velocity
	velocity.y = 0.0
	var turn := rad_to_deg(atan2(velocity.dot(right), velocity.dot(forward))) * direction
	var displacement: Vector3 = body.last_sample.origin - start_position
	var lateral := displacement.dot(right) * direction
	var minimum_turn: float = settings.min_turn
	_check(turn > minimum_turn, "%s: turn %.2f must exceed %.1f degrees in requested direction" % [
		settings.name, turn, minimum_turn])
	_check(lateral > 0.3, "%s: moves toward requested side (%.2f m)" % [settings.name, lateral])
	_check(finite and peak_lean < 45.0, settings.name + ": stays finite and upright")
	# The 20-capsule rim skips at speed. Contacts must recur within the flight
	# time of a tube-radius bounce, and the rim must stay within that distance
	# of the floor. This rejects loss of support without requiring uninterrupted
	# solver contacts or choosing an arbitrary fraction of grounded ticks.
	_check(ground_ticks > 0 and peak_clearance < body.minor_radius \
		and float(longest_airborne) / Engine.physics_ticks_per_second < maximum_skip_duration,
		settings.name + ": maintains recurring ground support with only shallow rim skips")
	if settings.stick == 0.0:
		_check(correct_lean > 2.0, settings.name + ": ring visibly leans toward requested side")
	if settings.name == "right key coasting":
		_full_right_turn = turn
	elif settings.name == "partial right stick":
		_check(turn < _full_right_turn * 0.65, "partial stick produces gentler turning than keyboard")
	print("STEERING %s: turn=%+.2f lateral=%+.2f lean_peak=%.2f contacts=%d/%d air_max=%.3fs clearance_max=%.3fm height=%.3f..%.3fm vertical_speed_max=%.3fm/s" % [
		settings.name, turn, lateral, peak_lean, ground_ticks, STEERING_TICKS,
		float(longest_airborne) / Engine.physics_ticks_per_second, peak_clearance,
		minimum_height, maximum_height, peak_vertical_speed])
	_clear_inputs()
	scene.queue_free()
	await process_frame


func _ticks(body: TorusBody, count: int) -> void:
	for tick in range(count):
		await body.physics_sampled


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
