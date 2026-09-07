class_name TorusGeometry
extends RefCounted
## Local +X is the axle; capsule centerlines form chords in the YZ plane.

static func build(body: RigidBody3D, major: float, minor: float, count: int) -> void:
	assert(minor < major, "The torus hole requires minor_radius < major_radius.")
	for index in range(count):
		var angle_a := TAU * float(index) / count
		var angle_b := TAU * float(index + 1) / count
		var point_a := Vector3(0.0, cos(angle_a), sin(angle_a)) * major
		var point_b := Vector3(0.0, cos(angle_b), sin(angle_b)) * major
		var chord := point_b - point_a
		var capsule := CapsuleShape3D.new()
		capsule.radius = minor
		# Capsule height includes both rounded ends, which overlap at ring vertices.
		capsule.height = chord.length() + 2.0 * minor
		var collision := CollisionShape3D.new()
		collision.name = "RingCapsule%02d" % index
		collision.shape = capsule
		collision.position = (point_a + point_b) * 0.5
		collision.basis = Basis(Quaternion(Vector3.UP, chord.normalized()))
		body.add_child(collision)
	var mesh := TorusMesh.new()
	mesh.inner_radius = major - minor
	mesh.outer_radius = major + minor
	mesh.rings = 96
	mesh.ring_segments = 24
	var visual := MeshInstance3D.new()
	visual.name = "TorusMesh"
	visual.mesh = mesh
	visual.rotation.z = PI * 0.5
	var material := ShaderMaterial.new()
	material.shader = preload("res://materials/torus.gdshader")
	visual.material_override = material
	body.add_child(visual)
