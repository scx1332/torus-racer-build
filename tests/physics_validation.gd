extends SceneTree
## Run with --headless --path . --script res://tests/physics_validation.gd.
## Optional user arguments: -- --manual, --no-nudge, --no-spin.

const SCENE := preload("res://physics_validation.tscn")
const DURATION := 12.0

var _body: TorusBody
var _next_sample: float = 1.0
var _max_lean: float = 0.0
var _pre_nudge_lean: float = 0.0
var _heading_at_nudge: float = 0.0
var _max_turn: float = 0.0
var _travel_at_nudge := Vector3.FORWARD
var _max_travel_turn: float = 0.0
var _contact_ticks: int = 0
var _ticks: int = 0


func _initialize() -> void:
	var version := Engine.get_version_info()
	if version.major != 4 or version.minor != 7:
		push_error("This validation requires Godot 4.7.x; found %s" % version.string)
		quit(2)
		return
	if ProjectSettings.get_setting("physics/3d/physics_engine") != "Jolt Physics":
		push_error("This validation requires built-in Jolt Physics.")
		quit(2)
		return
	var scene := SCENE.instantiate()
	_body = scene.get_node("Torus") as TorusBody
	var arguments := OS.get_cmdline_user_args()
	_body.manual_gyroscope = "--manual" in arguments
	_body.automatic_nudge = "--no-nudge" not in arguments
	if "--no-spin" in arguments:
		_body.initial_spin = 0.0
	for argument in arguments:
		if argument.begins_with("--nudge="):
			_body.nudge_impulse = argument.trim_prefix("--nudge=").to_float()
	root.add_child.call_deferred(scene)
	print("EXPERIMENT Godot=%s backend=Jolt gyro=%s spin=%.1f nudge=%s" % [
		version.string, "manual" if _body.manual_gyroscope else "native",
		_body.initial_spin, _body.automatic_nudge])


func _physics_process(_delta: float) -> bool:
	if not is_instance_valid(_body) or _body.elapsed <= 0.0:
		return false
	_ticks += 1
	if _body.contact_count > 0:
		_contact_ticks += 1
	_max_lean = maxf(_max_lean, absf(_body.lean_degrees))
	var travel := _body.linear_velocity
	travel.y = 0.0
	if not _body.has_nudged:
		_pre_nudge_lean = _max_lean
		_heading_at_nudge = _body.heading_radians
		if travel.length_squared() > 1.0:
			_travel_at_nudge = travel.normalized()
	else:
		var turn := absf(rad_to_deg(angle_difference(_heading_at_nudge, _body.heading_radians)))
		_max_turn = maxf(_max_turn, turn)
		if travel.length_squared() > 1.0:
			_max_travel_turn = maxf(_max_travel_turn, rad_to_deg(travel.angle_to(_travel_at_nudge)))
	if not _body.global_position.is_finite() or not _body.angular_velocity.is_finite():
		push_error("FAIL: physics produced a non-finite state")
		quit(1)
		return false
	if _body.elapsed >= _next_sample:
		print("t=%4.1f lean=%7.2f heading=%7.2f spin=%6.2f speed=%6.2f height=%.3f contacts=%d" % [
			_body.elapsed, _body.lean_degrees, rad_to_deg(_body.heading_radians),
			_body.spin_rate, _body.linear_velocity.length(), _body.position.y, _body.contact_count])
		_next_sample += 1.0
	if _body.elapsed >= DURATION:
		var grounded_fraction := float(_contact_ticks) / maxi(_ticks, 1)
		var passed := _pre_nudge_lean < 5.0 and _max_lean < 45.0 and grounded_fraction > 0.5
		if _body.automatic_nudge:
			passed = passed and _max_turn > 3.0 and _max_travel_turn > 3.0
		print("RESULT %s pre_nudge_lean=%.2f max_lean=%.2f axle_turn=%.2f travel_turn=%.2f grounded=%.3f" % [
			"PASS" if passed else "FAIL", _pre_nudge_lean, _max_lean,
			_max_turn, _max_travel_turn, grounded_fraction])
		quit(0 if passed else 1)
	return false
