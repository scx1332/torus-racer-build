extends SceneTree
## Same colliding, rolling rigid body with/without the optional debug observer.

const TICKS := 720
const TOLERANCE := 0.00001
const SNAPSHOT_VECTORS := ["origin", "linear_velocity", "angular_velocity",
	"spin_axis", "input_torque", "assist_torque", "gyroscopic_torque",
	"bank_pivot_impulse", "bank_pivot_force", "bank_pivot_torque"]

var _observed_world: SubViewport
var _plain: TorusBody
var _observed: TorusBody
var _debug: TorusDebug
var _original_material: Material
var _ticks: int = 0
var _contact_ticks: int = 0
var _max_error: float = 0.0
var _max_speed: float = 0.0
var _max_spin: float = 0.0
var _max_gyro: float = 0.0
var _max_pivot: float = 0.0
var _started_at: int = 0
var _failed: bool = false


func _initialize() -> void:
	_started_at = Time.get_ticks_msec()
	call_deferred("_setup")


func _setup() -> void:
	_plain = _create_body("Plain", _create_world())
	_observed_world = _create_world()
	_observed = _create_body("Observed", _observed_world)
	_debug = TorusDebug.new()
	_debug.target = _observed
	_observed_world.add_child(_debug)
	_original_material = _observed.get_node("TorusMesh").material_override
	_probe_draw_paths()
	_debug.set_enabled(true)


func _create_world() -> SubViewport:
	# Identical independent solvers avoid constraint-order differences between
	# two bodies in one world while advancing under the same physics clock.
	var world := SubViewport.new()
	world.world_3d = World3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.position.y = -0.5
	ground.physics_material_override = PhysicsMaterial.new()
	ground.physics_material_override.friction = 0.8
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1000.0, 1.0, 1000.0)
	collider.shape = shape
	ground.add_child(collider)
	world.add_child(ground)
	return world


func _create_body(body_name: String, world: SubViewport) -> TorusBody:
	var body := TorusBody.new()
	body.name = body_name
	body.position = Vector3(0.0, 1.28, 0.0)
	body.controls_enabled = true
	body.tuning.rumble_enabled = false
	if "--bank-controller" in OS.get_cmdline_user_args():
		body.tuning.direct_lean = false
		body.tuning.lean_torque = 30.0
	else:
		body.capsule_count = 64
		body.linear_damping = 0.0
	body.initial_spin = 24.0
	body.automatic_nudge = true
	body.manual_gyroscope = true
	world.add_child(body)
	return body


func _probe_draw_paths() -> void:
	var visual := _observed.get_node("TorusMesh") as MeshInstance3D
	_check(not _debug.enabled and not _debug.visible, "Debug must start off")
	_debug.set_enabled(true)
	var material := visual.material_override as StandardMaterial3D
	_check(material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,
		"Enabled debug must use alpha transparency")
	_check(material != null and is_equal_approx(material.albedo_color.a, 0.25),
		"Debug opacity must be 25 percent")
	var sample := {"origin": Vector3.ZERO, "linear_velocity": Vector3.ZERO,
		"angular_velocity": Vector3.ZERO, "spin_axis": Vector3.RIGHT,
		"input_torque": Vector3.ZERO, "assist_torque": Vector3.ZERO,
		"gyroscopic_torque": Vector3.ZERO, "contacts": []}
	_observed.physics_sampled.emit(sample)
	_check(_debug.get_node("Vectors").mesh.get_surface_count() > 0,
		"Zero vectors must still render the center marker")
	sample.contacts = [{"position": Vector3.DOWN, "normal": Vector3.UP,
		"traction": Vector3.BACK * 3.0}]
	_observed.physics_sampled.emit(sample)
	_check(_debug.get_node("Vectors").mesh.get_surface_count() > 0,
		"Contact snapshot must render")
	sample.bank_pivot_position = Vector3.DOWN
	sample.bank_pivot_force = Vector3.RIGHT * 2.0
	sample.bank_pivot_torque = Vector3.BACK * 2.0
	_observed.physics_sampled.emit(sample)
	var pivot_label := false
	var reaction_label := false
	for label: Label3D in _debug._labels:
		pivot_label = pivot_label or (label.visible and label.text == "Bank pivot force 2.00")
		reaction_label = reaction_label or (label.visible and label.text == "Assist torque 2.00")
	_check(pivot_label and reaction_label, "Debug must show pivot force and its angular reaction")
	_debug.set_enabled(false)
	_check(visual.material_override == _original_material, "Toggle must restore original material")
	_check(_observed.linear_velocity == Vector3.ZERO and _observed.angular_velocity == Vector3.ZERO,
		"Synthetic debug snapshots must not change body velocities")


func _physics_process(_delta: float) -> bool:
	if _failed:
		return false
	if Time.get_ticks_msec() - _started_at > 30000:
		_check(false, "Physics comparison exceeded its 30 second timeout")
		return false
	if not is_instance_valid(_plain) or _plain.last_sample.is_empty() \
			or _observed.last_sample.is_empty():
		return false
	_ticks += 1
	if _ticks == 240:
		Input.action_press("lean_right")
	elif _ticks == 480:
		Input.action_release("lean_right")
	_check(is_equal_approx(_plain.elapsed, _observed.elapsed), "Bodies must advance together")
	for key in SNAPSHOT_VECTORS:
		_compare_vector(_plain.last_sample[key], _observed.last_sample[key], key)
	for axis in range(3):
		_compare_vector(_plain.global_basis[axis], _observed.global_basis[axis], "orientation")
	_compare_vector(_plain.global_position, _observed.global_position, "position")
	_check(_plain.grounded == _observed.grounded, "Debug must preserve grounded detection")
	_check(absf(_plain.last_sample.slip_ratio - _observed.last_sample.slip_ratio) < TOLERANCE,
		"Debug must preserve slip ratio")
	var plain_contacts: Array = _plain.last_sample.contacts
	var observed_contacts: Array = _observed.last_sample.contacts
	_check(plain_contacts.size() == observed_contacts.size(), "Debug must preserve contact count")
	for index in range(mini(plain_contacts.size(), observed_contacts.size())):
		for key in ["position", "normal", "traction"]:
			_compare_vector(plain_contacts[index][key], observed_contacts[index][key], "contact " + key)
	if _plain.grounded:
		_contact_ticks += 1
	_max_speed = maxf(_max_speed, _plain.last_sample.speed)
	_max_spin = maxf(_max_spin, absf(_plain.last_sample.spin_rate))
	_max_gyro = maxf(_max_gyro, _plain.last_sample.gyroscopic_torque.length())
	_max_pivot = maxf(_max_pivot, _plain.last_sample.bank_pivot_force.length())
	if _ticks >= TICKS and not _failed:
		_finish()
	return false


func _compare_vector(a: Vector3, b: Vector3, description: String) -> void:
	var error := a.distance_to(b)
	_max_error = maxf(_max_error, error)
	_check(a.is_finite() and b.is_finite() and error < TOLERANCE,
		"Debug altered %s at tick %d (difference %.8f)" % [description, _ticks, error])


func _finish() -> void:
	_check(_contact_ticks > TICKS / 2, "Fixture needs sustained real ground contacts")
	_check(_max_speed > 1.0 and _max_spin > 10.0, "Fixture needs real translation and spin")
	_check(_plain.global_position.distance_to(Vector3(0.0, 1.28, 0.0)) > 2.0,
		"Fixture must have travelled")
	_check(_plain.has_nudged and _observed.has_nudged and _max_gyro > 1.0,
		"Fixture must exercise the lean nudge and gyroscopic torque")
	if _plain.tuning.direct_lean:
		_check(is_zero_approx(_max_pivot), "Direct lean must leave the bank correction disabled")
	else:
		_check(_max_pivot > 0.01, "Fixture must exercise the actual supported bank correction")
	# Removing an enabled debug observer must also restore the original material.
	_observed_world.remove_child(_debug)
	_debug.free()
	_check(_observed.get_node("TorusMesh").material_override == _original_material,
		"Removing enabled debug must restore original material")
	if not _failed:
		print("PASS debug invariance: %d ticks, %d grounded, max difference %.8f, speed %.2f, gyro %.2f" % [
			_ticks, _contact_ticks, _max_error, _max_speed, _max_gyro])
		quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition and not _failed:
		_failed = true
		push_error("FAIL: " + message)
		quit(1)
