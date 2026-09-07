class_name TorusEffects
extends Node3D
## Removable presentation observer: snapshots never write back to the rigid body.

@export var target: TorusBody
@export var debug_view: TorusDebug
@export var enabled: bool = true
@export_range(0.0, 1.0, 0.05) var intensity: float = 0.8
@export_range(0.0, 1.0, 0.01) var slip_threshold: float = 0.12
@export_range(1.0, 12.0, 0.5) var skid_lifetime: float = 6.0

const MAX_SKIDS := 160
var _dust: CPUParticles3D
var _puffs: Array[CPUParticles3D] = []
var _puff_index: int = 0
var _skid_mesh := ImmediateMesh.new()
var _skid_material := StandardMaterial3D.new()
var _marks: Array[Dictionary] = []
var _sample: Dictionary = {}
var _pending_landing: Dictionary = {}
var _fall_speed: float = 0.0
var _air_samples: int = 0
var _last_contact := Vector3.ZERO
var _has_last_contact: bool = false


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	if not is_instance_valid(target):
		push_warning("TorusEffects needs a target TorusBody.")
		set_process(false)
		return
	var texture := _dust_texture()
	_dust = _make_emitter(texture, 48, false)
	_dust.name = "SlipDust"
	for index in range(3):
		var puff := _make_emitter(texture, 18, true)
		puff.name = "LandingPuff%d" % index
		_puffs.append(puff)
	_skid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_skid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_skid_material.vertex_color_use_as_albedo = true
	_skid_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var skid_visual := MeshInstance3D.new()
	skid_visual.name = "SkidMarks"
	skid_visual.mesh = _skid_mesh
	skid_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(skid_visual)
	target.physics_sampled.connect(_on_physics_sampled)
	target.reset_completed.connect(_clear_effects)


func _on_physics_sampled(sample: Dictionary) -> void:
	_sample = sample
	if not sample.get("grounded", false):
		var velocity: Vector3 = sample.get("linear_velocity", Vector3.ZERO)
		_fall_speed = maxf(_fall_speed, -velocity.y)
		_air_samples += 1
		_has_last_contact = false
		return
	if _air_samples > 8 and _fall_speed > 1.5:
		_pending_landing = {"contact": _ground_contact(sample), "speed": _fall_speed}
	_air_samples = 0
	_fall_speed = 0.0


func _process(delta: float) -> void:
	var show_effects := enabled and intensity > 0.0 \
		and not (is_instance_valid(debug_view) and debug_view.enabled)
	if not show_effects:
		if visible:
			_clear_effects()
		visible = false
		_pending_landing.clear()
		return
	visible = true
	if not _pending_landing.is_empty():
		_emit_landing(_pending_landing)
		_pending_landing.clear()
	if not _sample.is_empty():
		_update_slip()
	_update_skids(delta)


func _update_slip() -> void:
	var contact := _ground_contact(_sample)
	var radius := target.major_radius + target.minor_radius
	var rim_speed := absf(float(_sample.spin_rate)) * radius
	var slip: float = _sample.slip_ratio
	# A parked body and pure rolling emit nothing; contact slip releases dust.
	var strength := clampf((slip - slip_threshold) * 1.5, 0.0, 1.0) \
		* clampf(maxf(float(_sample.speed), rim_speed) / 7.0, 0.0, 1.0) * intensity
	_dust.emitting = not contact.is_empty() and strength > 0.025
	if not _dust.emitting:
		_has_last_contact = false
		return
	var point: Vector3 = contact.position
	var normal: Vector3 = contact.normal
	var velocity: Vector3 = _sample.linear_velocity
	_dust.global_position = point + normal * 0.07
	_dust.direction = (normal * 0.8 - velocity.slide(normal).normalized() * 0.5).normalized()
	_dust.initial_velocity_max = lerpf(0.45, 2.2, strength)
	_dust.color = Color(0.63, 0.57, 0.46, strength * 0.55)
	var distance := point.distance_to(_last_contact)
	if _has_last_contact and distance >= 0.06 and distance < 2.5:
		var side := (point - _last_contact).cross(normal).normalized() * 0.16
		_marks.append({"start": _last_contact + normal * 0.012,
			"end": point + normal * 0.012, "side": side, "age": 0.0,
			"strength": strength})
		if _marks.size() > MAX_SKIDS:
			_marks.pop_front()
	if not _has_last_contact or distance >= 0.06:
		_last_contact = point
	_has_last_contact = true


func _ground_contact(sample: Dictionary) -> Dictionary:
	var contacts: Array = sample.get("contacts", [])
	if contacts.is_empty():
		return {}
	var point := Vector3.ZERO
	var normal := Vector3.ZERO
	for contact: Dictionary in contacts:
		point += Vector3(contact.position)
		normal += Vector3(contact.normal)
	return {"position": point / float(contacts.size()), "normal": normal.normalized()}


func _emit_landing(event: Dictionary) -> void:
	if event.contact.is_empty():
		return
	var puff := _puffs[_puff_index]
	_puff_index = (_puff_index + 1) % _puffs.size()
	puff.global_position = event.contact.position + event.contact.normal * 0.09
	puff.direction = event.contact.normal
	puff.initial_velocity_max = clampf(float(event.speed) * 0.4, 0.7, 3.0)
	puff.color = Color(0.7, 0.62, 0.49, minf(float(event.speed) / 6.0, 1.0) * intensity * 0.5)
	puff.restart()
	puff.emitting = true


func _update_skids(delta: float) -> void:
	_skid_mesh.clear_surfaces()
	for index in range(_marks.size() - 1, -1, -1):
		_marks[index].age += delta
		if _marks[index].age >= skid_lifetime:
			_marks.remove_at(index)
	if _marks.is_empty():
		return
	_skid_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _skid_material)
	for mark: Dictionary in _marks:
		var color := Color(0.035, 0.028, 0.025,
			float(mark.strength) * 0.5 * (1.0 - float(mark.age) / skid_lifetime))
		# Two strips soften the outer edges with vertex alpha, without decals.
		for sign_value in [-1.0, 1.0]:
			var offset: Vector3 = mark.side * sign_value
			for vertex in [mark.start, mark.end, mark.start + offset,
					mark.start + offset, mark.end, mark.end + offset]:
				var edge: bool = vertex == mark.start + offset or vertex == mark.end + offset
				_skid_mesh.surface_set_color(Color(color, 0.0) if edge else color)
				_skid_mesh.surface_add_vertex(vertex)
	_skid_mesh.surface_end()


func _make_emitter(texture: Texture2D, count: int, burst: bool) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.amount = count
	particles.lifetime = 0.65 if burst else 0.55
	particles.one_shot = burst
	particles.explosiveness = 1.0 if burst else 0.0
	particles.local_coords = false
	particles.use_fixed_seed = true
	particles.seed = 73
	particles.spread = 85.0 if burst else 35.0
	particles.gravity = Vector3(0.0, 0.22, 0.0)
	particles.initial_velocity_min = 0.25
	particles.scale_amount_min = 0.15
	particles.scale_amount_max = 0.4
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color(1, 1, 1, 0)])
	particles.color_ramp = fade
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var quad := QuadMesh.new()
	quad.material = material
	particles.mesh = quad
	add_child(particles)
	return particles


func _dust_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.65), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.width = 32
	texture.height = 32
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	return texture


func _clear_effects() -> void:
	_has_last_contact = false
	_fall_speed = 0.0
	_air_samples = 0
	_pending_landing.clear()
	_sample = {}
	_marks.clear()
	_skid_mesh.clear_surfaces()
	for emitter: CPUParticles3D in [_dust] + _puffs:
		emitter.restart()
		emitter.emitting = false
