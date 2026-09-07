class_name TorusDebug
extends Node3D
## Optional, read-only physics visualization. Remove this node for release builds.

signal toggled(enabled: bool)

@export var target: TorusBody
@export_range(0.001, 1.0, 0.001) var debug_vector_scale: float = 0.08

const CONTACT_COLOR := Color("ffffff")
const NORMAL_COLOR := Color("65e572")
const TRACTION_COLOR := Color("ffad42")
const VELOCITY_COLOR := Color("48cfff")
const ANGULAR_COLOR := Color("cb86ff")
const INPUT_COLOR := Color("fff06a")
const ASSIST_COLOR := Color("ff73b4")
const GYRO_COLOR := Color("ff5f65")
const PIVOT_COLOR := Color("64e4c6")

var enabled: bool = false
var _mesh := ImmediateMesh.new()
var _lines_material := StandardMaterial3D.new()
var _transparent_material := StandardMaterial3D.new()
var _original_material: Material
var _visual: MeshInstance3D
var _edge := MeshInstance3D.new()
var _labels: Array[Label3D] = []
var _label_index: int = 0


func _ready() -> void:
	# Vector vertices are snapshots in world space, independent of ring rotation.
	top_level = true
	global_transform = Transform3D.IDENTITY
	visible = false
	if not is_instance_valid(target):
		push_warning("TorusDebug needs a target TorusBody.")
		set_process_unhandled_input(false)
		return
	_visual = target.get_node_or_null("TorusMesh") as MeshInstance3D
	_lines_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lines_material.vertex_color_use_as_albedo = true
	_lines_material.no_depth_test = true
	var lines := MeshInstance3D.new()
	lines.name = "Vectors"
	lines.mesh = _mesh
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lines)
	_transparent_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_transparent_material.albedo_color = Color(0.65, 0.8, 1.0, 0.25)
	_transparent_material.roughness = 0.65
	_build_ring_edge()
	target.connect(&"physics_sampled", _on_physics_sampled)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_toggle") and not event.is_echo():
		set_enabled(not enabled)
		get_viewport().set_input_as_handled()


func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	visible = value
	if is_instance_valid(_visual):
		if enabled:
			_original_material = _visual.material_override
			_visual.material_override = _transparent_material
		else:
			_visual.material_override = _original_material
	if not enabled:
		_mesh.clear_surfaces()
		for label in _labels:
			label.visible = false
	toggled.emit(enabled)


func _exit_tree() -> void:
	if enabled and is_instance_valid(_visual):
		_visual.material_override = _original_material


func _build_ring_edge() -> void:
	# Thin inner and outer rims retain the ring silhouette through transparency.
	var edge_mesh := ImmediateMesh.new()
	edge_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _lines_material)
	for radius in [target.major_radius - target.minor_radius,
			target.major_radius + target.minor_radius]:
		for index in range(96):
			var angle_a := TAU * float(index) / 96.0
			var angle_b := TAU * float(index + 1) / 96.0
			_add_line(edge_mesh, Vector3(0.0, cos(angle_a), sin(angle_a)) * radius,
				Vector3(0.0, cos(angle_b), sin(angle_b)) * radius,
				Color(0.62, 0.77, 0.91))
	edge_mesh.surface_end()
	_edge.name = "RingOutline"
	_edge.mesh = edge_mesh
	_edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_edge)


func _on_physics_sampled(sample: Dictionary) -> void:
	if not enabled:
		return
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _lines_material)
	_label_index = 0
	_edge.global_transform = target.global_transform
	var origin: Vector3 = sample["origin"]
	var camera := get_viewport().get_camera_3d()
	var right := camera.global_basis.x if camera != null else Vector3.RIGHT
	var up := camera.global_basis.y if camera != null else Vector3.UP
	var column_offset := target.major_radius + target.minor_radius + 0.45
	var body_column := origin + right * column_offset + up * 0.9
	var contact_column := origin - right * column_offset + up * 0.9
	_draw_marker(origin, VELOCITY_COLOR, 0.025)
	_draw_arrow(origin, sample["linear_velocity"], VELOCITY_COLOR, "Velocity", body_column)
	_draw_arrow(origin, sample["angular_velocity"], ANGULAR_COLOR, "Angular velocity",
		body_column - up * 0.42)
	_draw_arrow(origin, sample["input_torque"], INPUT_COLOR, "Player torque",
		body_column - up * 0.84)
	# Include the lower-pivot impulse's average torque for display only. The
	# physics integrator must not apply that instantaneous angular impulse twice.
	var assist: Vector3 = sample["assist_torque"] \
		+ sample.get("bank_pivot_torque", Vector3.ZERO)
	_draw_arrow(origin, assist, ASSIST_COLOR, "Assist torque",
		body_column - up * 1.26)
	_draw_arrow(origin, sample["gyroscopic_torque"], GYRO_COLOR, "Gyro torque",
		body_column - up * 1.68)
	var pivot_force: Vector3 = sample.get("bank_pivot_force", Vector3.ZERO)
	var pivot: Vector3 = sample.get("bank_pivot_position", origin)
	if not pivot_force.is_zero_approx():
		_draw_marker(pivot, PIVOT_COLOR, 0.055)
	_draw_arrow(pivot if not pivot_force.is_zero_approx() else origin, pivot_force,
		PIVOT_COLOR, "Bank pivot force", body_column - up * 2.1)
	var contact_index := 0
	for contact: Dictionary in sample["contacts"]:
		var point: Vector3 = contact["position"]
		var row := contact_column - up * float(contact_index) * 1.4
		_draw_marker(point, CONTACT_COLOR, 0.055)
		_add_line(_mesh, point, row, CONTACT_COLOR.darkened(0.7))
		_draw_label(row, "C%d contact" % contact_index, CONTACT_COLOR,
			HORIZONTAL_ALIGNMENT_RIGHT)
		_draw_arrow(point, contact["normal"], NORMAL_COLOR,
			"C%d normal" % contact_index, row - up * 0.42, HORIZONTAL_ALIGNMENT_RIGHT)
		_draw_arrow(point, contact["traction"], TRACTION_COLOR,
			"C%d traction (est.)" % contact_index, row - up * 0.84, HORIZONTAL_ALIGNMENT_RIGHT)
		contact_index += 1
	_mesh.surface_end()
	for index in range(_label_index, _labels.size()):
		_labels[index].visible = false


func _draw_arrow(origin: Vector3, vector: Vector3, color: Color,
		caption: String, label_position: Vector3, alignment: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	# A common scale preserves magnitudes. Zero vectors still have a named label.
	var arrow := vector * debug_vector_scale
	var end := origin + arrow
	var length := arrow.length()
	if length > 0.00001:
		_add_line(_mesh, origin, end, color)
		var direction := arrow / length
		var reference := Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT
		var side := direction.cross(reference).normalized()
		var head_size := minf(length * 0.25, 0.16)
		_add_line(_mesh, end, end - direction * head_size + side * head_size * 0.5, color)
		_add_line(_mesh, end, end - direction * head_size - side * head_size * 0.5, color)
	# Labels occupy camera-facing columns; faint leaders identify exact endpoints.
	_add_line(_mesh, end, label_position, color.darkened(0.7))
	_draw_label(label_position, "%s %.2f" % [caption, vector.length()], color, alignment)


func _draw_marker(point: Vector3, color: Color, radius: float) -> void:
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_add_line(_mesh, point - axis * radius, point + axis * radius, color)


func _draw_label(position_world: Vector3, caption: String, color: Color,
		alignment: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	if _label_index == _labels.size():
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 28
		label.pixel_size = 0.012
		label.outline_size = 6
		label.no_depth_test = true
		add_child(label)
		_labels.append(label)
	var label := _labels[_label_index]
	label.position = position_world
	label.text = caption
	label.modulate = color
	label.horizontal_alignment = alignment
	label.visible = true
	_label_index += 1


func _add_line(mesh: ImmediateMesh, start: Vector3, end: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(start)
	mesh.surface_add_vertex(end)
