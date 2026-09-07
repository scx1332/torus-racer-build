extends Camera3D
## Visual follow only. Ring rotation never becomes camera rotation.

@export var target: RigidBody3D
@export var follow_distance: float = 6.0
@export var follow_height: float = 3.0
@export var side_offset: float = 4.5
@export var follow_response: float = 5.0

var _travel_direction := Vector3.FORWARD
var _placed: bool = false


func _ready() -> void:
	if target is TorusBody:
		(target as TorusBody).reset_completed.connect(_on_target_reset)
		_on_target_reset()


func _on_target_reset() -> void:
	_placed = false
	var body := target as TorusBody
	# Positive axle spin rolls toward axle × UP; start behind that direction.
	_travel_direction = body.checkpoint_transform.basis.x.cross(Vector3.UP).normalized()
	if body.initial_spin < 0.0:
		_travel_direction = -_travel_direction
	if _travel_direction.is_zero_approx():
		_travel_direction = Vector3.FORWARD


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var velocity := target.linear_velocity
	velocity.y = 0.0
	var body := target as TorusBody
	var in_water := body != null and body.water_pending
	var blend := 1.0 - exp(-follow_response * delta)
	if not in_water and velocity.length_squared() > 1.0:
		# Follow horizontal yaw without normalizing a near-zero 3D rotation axis.
		var heading := atan2(_travel_direction.x, _travel_direction.z)
		var desired_heading := atan2(velocity.x, velocity.z)
		heading = lerp_angle(heading, desired_heading, blend)
		_travel_direction = Vector3(sin(heading), 0.0, cos(heading))
	var focus := target.global_position + Vector3.UP * 0.4
	if in_water:
		# Watch the splash above the surface, not the falling body's underwater path.
		focus = body.water_position + Vector3.UP * 0.8
	# Optional shoulder view exposes the hole; centered play view keeps banks symmetric.
	var side := _travel_direction.cross(Vector3.UP) * side_offset
	var desired := focus - _travel_direction * follow_distance + Vector3.UP * follow_height + side
	global_position = global_position.lerp(desired, blend) if _placed else desired
	_placed = true
	look_at(focus, Vector3.UP)
