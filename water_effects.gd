class_name WaterEffects
extends Node3D
## Cosmetic water-entry observer: no body reference or physics writes.

@export var hazard: Node3D
@export var debug_view: TorusDebug
@export var enabled: bool = true
@export_range(0.0, 1.0, 0.05) var intensity: float = 0.85

const POOL_SIZE := 4
const LIFETIME := 1.2
var _bursts: Array[Dictionary] = []
var _pending: Array[Dictionary] = []
var _next_burst: int = 0


func _ready() -> void:
	# Splashes outlive the reset and remain where the torus entered the sea.
	top_level = true
	global_transform = Transform3D.IDENTITY
	if not is_instance_valid(hazard) or not hazard.has_signal(&"water_entered"):
		push_warning("WaterEffects needs a hazard with a water_entered signal.")
		set_process(false)
		return
	var texture := _splash_texture()
	for index in range(POOL_SIZE):
		var rings: Array[MeshInstance3D] = []
		for ring_index in range(2):
			rings.append(_make_ring())
		_bursts.append({"droplets": _make_emitter(texture, false, index),
			"mist": _make_emitter(texture, true, index), "rings": rings,
			"age": LIFETIME, "strength": 0.0})
	hazard.connect(&"water_entered", _on_water_entered)


func _on_water_entered(point: Vector3, impact_speed: float) -> void:
	# Called from the physics event: only copy data, never mutate rendering or
	# physics state here. Disabled/debug events are discarded, not replayed later.
	if not _should_show() or not point.is_finite() or not is_finite(impact_speed):
		return
	if _pending.size() >= POOL_SIZE:
		_pending.pop_front()
	_pending.append({"position": point, "speed": absf(impact_speed)})


func _process(delta: float) -> void:
	if not _should_show():
		if visible or not _pending.is_empty():
			_clear_effects()
		visible = false
		return
	visible = true
	for burst: Dictionary in _bursts:
		burst.age = minf(float(burst.age) + delta, LIFETIME)
		_update_rings(burst)
	for event: Dictionary in _pending:
		_emit_splash(event)
	_pending.clear()


func _should_show() -> bool:
	return enabled and intensity > 0.0 \
		and not (is_instance_valid(debug_view) and debug_view.enabled)


func _emit_splash(event: Dictionary) -> void:
	var burst := _bursts[_next_burst]
	_next_burst = (_next_burst + 1) % POOL_SIZE
	burst.age = 0.0
	burst.strength = clampf(float(event.speed) / 16.0, 0.15, 1.0)
	var strength: float = burst.strength
	var droplets: CPUParticles3D = burst.droplets
	droplets.global_position = event.position + Vector3.UP * 0.08
	droplets.initial_velocity_min = lerpf(1.4, 2.6, strength)
	droplets.initial_velocity_max = lerpf(3.0, 6.8, strength)
	droplets.color = Color(0.7, 0.95, 1.0, 0.9 * intensity)
	var mist: CPUParticles3D = burst.mist
	mist.global_position = event.position + Vector3.UP * 0.25
	mist.initial_velocity_max = lerpf(0.6, 1.8, strength)
	mist.color = Color(0.85, 0.98, 1.0, 0.35 * intensity)
	for emitter: CPUParticles3D in [droplets, mist]:
		emitter.restart()
		emitter.emitting = true
	for ring: MeshInstance3D in burst.rings:
		# Ocean vertices undulate by at most 0.26 m; keep the thin foam readable.
		ring.global_position = event.position + Vector3.UP * 0.30
	_update_rings(burst)


func _update_rings(burst: Dictionary) -> void:
	for index in range(burst.rings.size()):
		var ring: MeshInstance3D = burst.rings[index]
		var age := float(burst.age) - float(index) * 0.12
		ring.visible = age >= 0.0 and float(burst.age) < LIFETIME
		if not ring.visible:
			continue
		var progress := clampf(age / (LIFETIME - float(index) * 0.12), 0.0, 1.0)
		var radius := lerpf(0.45, 2.8 + float(burst.strength) * 1.8, progress)
		ring.scale = Vector3(radius, 0.35, radius)
		var material := ring.material_override as StandardMaterial3D
		material.albedo_color.a = pow(1.0 - progress, 1.4) * intensity * 0.7


func _make_ring() -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.92
	mesh.outer_radius = 1.0
	mesh.rings = 48
	mesh.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.86, 1.0, 0.97, 0.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ring := MeshInstance3D.new()
	ring.name = "FoamRing"
	ring.mesh = mesh
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	add_child(ring)
	return ring


func _make_emitter(texture: Texture2D, mist: bool, seed_index: int) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = "WaterMist" if mist else "WaterDroplets"
	particles.emitting = false
	particles.amount = 18 if mist else 36
	particles.lifetime = LIFETIME if mist else 1.05
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.local_coords = false
	particles.use_fixed_seed = true
	particles.seed = 401 + seed_index
	particles.direction = Vector3.UP
	particles.spread = 85.0 if mist else 65.0
	particles.gravity = Vector3(0.0, 0.18, 0.0) if mist else Vector3.DOWN * 9.8
	particles.initial_velocity_min = 0.3
	particles.scale_amount_min = 0.45 if mist else 0.08
	particles.scale_amount_max = 1.2 if mist else 0.22
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.08, 0.6, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE,
		Color(1, 1, 1, 0.75), Color(1, 1, 1, 0)])
	particles.color_ramp = fade
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE if mist else Vector2(0.65, 1.0)
	quad.material = material
	particles.mesh = quad
	add_child(particles)
	return particles


func _splash_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.width = 32
	texture.height = 32
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	return texture


func _clear_effects() -> void:
	_pending.clear()
	for burst: Dictionary in _bursts:
		burst.age = LIFETIME
		for emitter: CPUParticles3D in [burst.droplets, burst.mist]:
			emitter.restart()
			emitter.emitting = false
		for ring: MeshInstance3D in burst.rings:
			ring.visible = false
