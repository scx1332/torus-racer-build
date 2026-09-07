extends SceneTree
## Follow real horizontal velocity through degenerate and wraparound headings.

const CAMERA := preload("res://chase_camera.gd")
const PLAYABLE := preload("res://controls_lab.tscn")
const PHYSICS_LAB := preload("res://physics_validation.tscn")
var _target: RigidBody3D
var _camera: Camera3D
var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_target = RigidBody3D.new()
	_target.freeze = true
	root.add_child(_target)
	_camera = CAMERA.new()
	_camera.target = _target
	root.add_child(_camera)
	_camera.set_process(false)
	# One update halves the remaining yaw with the configured exponential response.
	var half_time: float = log(2.0) / _camera.follow_response
	_follow(35.0, 35.0, half_time)
	_near(_heading(), 35.0, "identical heading stays unchanged")
	for angle in [-179.999, -90.0, -0.001, 0.0, 0.001, 90.0, 179.999]:
		for offset in [-0.001, -0.00001, 0.00001, 0.001]:
			_follow(angle, angle + offset, half_time)
			_near(_heading(), angle + offset * 0.5, "near-parallel heading takes a small step")
	_follow(0.0, 90.0, half_time)
	_near(_heading(), 45.0, "response keeps half of a quarter turn")
	_follow(179.0, -179.0, half_time)
	_near(absf(_heading()), 180.0, "positive wrap crosses the nearby boundary")
	_follow(-179.0, 179.0, half_time)
	_near(absf(_heading()), 180.0, "negative wrap crosses the nearby boundary")
	_follow(0.0, 180.0, half_time)
	_near(absf(_heading()), 90.0, "opposite direction remains a horizontal quarter turn")
	_target.linear_velocity = Vector3.UP * 20.0
	var before: Vector3 = _camera.get("_travel_direction")
	_camera._process(half_time)
	_check(before.is_equal_approx(_camera.get("_travel_direction")),
		"vertical-only velocity preserves the last heading")
	# Repeated tiny changes previously exercised the unstable slerp rotation axis.
	for step in range(1000):
		var angle := 0.7 + sin(float(step) * 0.013) * 0.00001
		_target.linear_velocity = Vector3(sin(angle), 0.0, cos(angle)) * 15.0
		_camera._process(1.0 / 60.0)
		_check_valid("smooth trajectory tick %d" % step)
	_test_playable_projection()
	for failure in _failures:
		push_error("FAIL: " + failure)
	print("CHASE CAMERA %s checks=%d failures=%d" % [
		"PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _test_playable_projection() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.world_3d = World3D.new()
	root.add_child(viewport)
	var scene := PLAYABLE.instantiate()
	var body := scene.get_node("Torus") as TorusBody
	body.freeze = true # Projection fixture: no simulation or input changes its pose.
	viewport.add_child(scene)
	var camera := scene.get_node("ChaseCamera") as Camera3D
	camera.set_process(false)
	_check(is_zero_approx(camera.side_offset), "playable camera starts centered")
	camera._process(1.0 / 60.0)
	var stationary_transform := camera.global_transform
	var banks: Array[float] = []
	for bank in [-20.0, 0.0, 20.0]:
		body.basis = Basis(Vector3.BACK, deg_to_rad(bank))
		var center := body.global_position
		# Project a ring diameter chosen from world up, independent of wheel spin.
		var top := Vector3.UP.slide(body.basis.x).normalized() * body.major_radius
		var diameter := camera.unproject_position(center + top) \
			- camera.unproject_position(center - top)
		_check(diameter.is_finite() and diameter.length() > 1.0, "bank diameter projects visibly")
		banks.append(rad_to_deg(atan2(diameter.x, -diameter.y)))
	_check(banks[0] < 0.0 and banks[2] > 0.0, "opposite banks project to opposite screen sides")
	_near(banks[0], -banks[2], "equal physical banks have mirrored apparent lean")
	_near(banks[1], 0.0, "upright ring diameter projects vertically")
	_check(camera.global_transform.is_equal_approx(stationary_transform),
		"bank projection comparison uses one stationary camera")
	# Frozen presentation fixture: no force integration or simulated pose is changed.
	body.water_pending = true
	body.water_position = Vector3(220.0, -3.96, -65.0)
	body.position = Vector3(225.0, -12.0, -60.0)
	body.linear_velocity = Vector3(20.0, -30.0, 0.0)
	var water_heading: Vector3 = camera.get("_travel_direction")
	camera._process(10.0)
	var focus := body.water_position + Vector3.UP * 0.8
	var expected_position: Vector3 = focus - water_heading * camera.follow_distance \
		+ Vector3.UP * camera.follow_height
	_check(camera.global_position.is_equal_approx(expected_position),
		"Rescue camera frames the surface splash rather than the submerged torus")
	_check(camera.get("_travel_direction").is_equal_approx(water_heading),
		"Underwater motion cannot rotate the rescue camera heading")
	_check((-camera.global_basis.z).dot((focus - camera.global_position).normalized()) > 0.99999,
		"Rescue camera looks at the splash")
	body.water_pending = false
	body.transform = body.checkpoint_transform
	body.linear_velocity = Vector3.ZERO
	body.reset_completed.emit()
	camera._process(1.0 / 60.0)
	expected_position = body.global_position + Vector3.UP * (0.4 + camera.follow_height) \
		- Vector3.BACK * camera.follow_distance
	_check(camera.global_position.is_equal_approx(expected_position),
		"Reset snaps the camera back to the checkpoint without a long return pan")
	viewport.free()
	var lab := PHYSICS_LAB.instantiate()
	_check(lab.get_node("ChaseCamera").side_offset > 0.0, "Phase 1 retains its optional shoulder view")
	lab.free()


func _follow(start_degrees: float, target_degrees: float, delta: float) -> void:
	var start := deg_to_rad(start_degrees)
	var destination := deg_to_rad(target_degrees)
	_camera.set("_travel_direction", Vector3(sin(start), 0.0, cos(start)))
	_target.linear_velocity = Vector3(sin(destination), 0.0, cos(destination)) * 15.0
	_camera._process(delta)
	_check_valid("heading %.5f to %.5f" % [start_degrees, target_degrees])


func _heading() -> float:
	var direction: Vector3 = _camera.get("_travel_direction")
	return rad_to_deg(atan2(direction.x, direction.z))


func _check_valid(context: String) -> void:
	var direction: Vector3 = _camera.get("_travel_direction")
	_check(direction.is_finite() and absf(direction.length_squared() - 1.0) < 0.000001
		and direction.y == 0.0 and _camera.global_transform.is_finite(),
		context + ": heading is horizontal, unit length and camera transform is finite")


func _near(actual: float, expected: float, context: String) -> void:
	var error := wrapf(actual - expected, -180.0, 180.0)
	_check(absf(error) < 0.00005, "%s: expected %.5f, got %.5f" % [context, expected, actual])


func _check(passed: bool, context: String) -> void:
	_checks += 1
	if not passed:
		_failures.append(context)
