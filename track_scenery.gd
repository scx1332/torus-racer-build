class_name TrackScenery
extends Node3D
## Deterministic coast: terrain is solid; water, vegetation and props are cosmetic.

@export var scenery_seed: int = 43119
@export_range(0, 160, 1) var palm_count: int = 72

const CLIFF := preload("res://materials/cliff.gdshader")
const OCEAN := preload("res://materials/ocean.gdshader")
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = scenery_seed
	_build_island()
	_build_palms()
	_build_rocks()
	_build_harbor()


func _build_island() -> void:
	var sea := PlaneMesh.new()
	sea.size = Vector2(3000.0, 3000.0)
	sea.subdivide_width = 96
	sea.subdivide_depth = 96
	var water := ShaderMaterial.new()
	water.shader = OCEAN
	var ocean := _mesh("Ocean", sea, water, Vector3(0.0, -4.0, 0.0))
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rock := ShaderMaterial.new()
	rock.shader = CLIFF
	_terrain("IslandCliffs", _island_mesh([
		Vector3(137.0, 5.0, 242.0), Vector3(141.0, 0.0, 247.0),
		Vector3(131.0, -8.0, 239.0), Vector3(122.0, -20.0, 227.0),
	]), rock, 0.85)
	var sand := ShaderMaterial.new()
	sand.shader = CLIFF
	sand.set_shader_parameter("top_color", Color("b09a66"))
	sand.set_shader_parameter("rock_color", Color("c49961"))
	sand.set_shader_parameter("layer_color", Color("e6cf97"))
	_terrain("Beach", _island_mesh([
		Vector3(147.0, -1.0, 255.0), Vector3(162.0, -6.0, 280.0),
		Vector3(155.0, -15.0, 272.0),
	]), sand, 0.9)


func _terrain(node_name: String, mesh: ArrayMesh, material: Material, friction: float) -> void:
	var visual := _mesh(node_name, mesh, material)
	var terrain := StaticBody3D.new()
	terrain.name = "TerrainBody"
	terrain.physics_material_override = PhysicsMaterial.new()
	terrain.physics_material_override.friction = friction
	terrain.physics_material_override.bounce = 0.0
	# Rough terrain uses its grip instead of the ring's smoother material.
	terrain.physics_material_override.rough = true
	var collider := CollisionShape3D.new()
	collider.name = "TerrainCollision"
	# Static concave terrain reuses every visible triangle, including cliff sides.
	# Keeping it under the visual also keeps both transforms exactly aligned.
	collider.shape = mesh.create_trimesh_shape()
	terrain.add_child(collider)
	visual.add_child(terrain)


func _island_mesh(rings: Array) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 96
	for index in range(count):
		var a := TAU * index / count
		var b := TAU * (index + 1) / count
		_triangle(surface, Vector3(0.0, rings[0].y, 0.0), _shore(rings[0], b), _shore(rings[0], a))
		for layer in range(rings.size() - 1):
			var top_a := _shore(rings[layer], a)
			var top_b := _shore(rings[layer], b)
			var bottom_a := _shore(rings[layer + 1], a)
			var bottom_b := _shore(rings[layer + 1], b)
			_triangle(surface, top_a, top_b, bottom_a)
			_triangle(surface, top_b, bottom_b, bottom_a)
	return surface.commit()


func _shore(ring: Vector3, angle: float) -> Vector3:
	var edge := 1.0 + 0.018 * sin(angle * 7.0 + 0.8) + 0.012 * sin(angle * 13.0)
	return Vector3(cos(angle) * ring.x * edge, ring.y, sin(angle) * ring.z * edge)


func _build_palms() -> void:
	var trunks: Array[Transform3D] = []
	var leaves: Array[Transform3D] = []
	var trunk_colors: Array[Color] = []
	var leaf_colors: Array[Color] = []
	var placed := 0
	for attempt in range(palm_count * 12):
		if placed >= palm_count:
			break
		var point := Vector3(_rng.randf_range(-66.0, 66.0), 5.0, _rng.randf_range(-172.0, 172.0))
		# Retry mode follows attempts, so rejected coastal points cannot stall the grove.
		if attempt % 3 == 0:
			var angle := _rng.randf_range(0.0, TAU)
			point = Vector3(cos(angle) * 130.0, 5.0, sin(angle) * 233.0)
		# A 25m centreline clearance includes the 12m half-road and the whole canopy.
		if _road_distance(point) < 25.0:
			continue
		var height := _rng.randf_range(5.8, 10.5)
		var bend := Vector3(_rng.randf_range(-0.8, 0.8), 0.0, _rng.randf_range(-0.8, 0.8))
		for segment in range(3):
			var from := point + Vector3.UP * height * segment / 3.0 + bend * pow(float(segment) / 3.0, 2.0)
			var to := point + Vector3.UP * height * (segment + 1) / 3.0 + bend * pow(float(segment + 1) / 3.0, 2.0)
			var delta := to - from
			var basis := Basis(Quaternion(Vector3.UP, delta.normalized()))
			trunks.append(Transform3D(basis * Basis.from_scale(Vector3(1.2, delta.length(), 1.2)), (from + to) * 0.5))
			trunk_colors.append(Color("a17a4d").lightened(_rng.randf_range(0.0, 0.16)))
		var crown := point + Vector3.UP * height + bend
		var phase := _rng.randf_range(0.0, TAU)
		for leaf in range(7):
			var size := _rng.randf_range(0.8, 1.2)
			var basis := Basis(Vector3.UP, phase + TAU * leaf / 7.0)
			leaves.append(Transform3D(basis.scaled(Vector3.ONE * size), crown))
			leaf_colors.append(Color("205e36").lerp(Color("668c3d"), _rng.randf()))
		placed += 1
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.15
	trunk.bottom_radius = 0.23
	trunk.height = 1.0
	trunk.radial_segments = 8
	_batch("PalmTrunks", trunk, _material(Color.WHITE), trunks, trunk_colors)
	var foliage := _material(Color.WHITE)
	foliage.cull_mode = BaseMaterial3D.CULL_DISABLED
	_batch("PalmFronds", _frond_mesh(), foliage, leaves, leaf_colors)


func _frond_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var left := Vector3(-0.95, 0.12, 2.0)
	var right := Vector3(0.95, 0.12, 2.0)
	var ridge := Vector3(0.0, 0.48, 2.0)
	var tip := Vector3(0.0, -1.15, 4.8)
	_triangle(surface, Vector3.ZERO, left, ridge)
	_triangle(surface, Vector3.ZERO, ridge, right)
	_triangle(surface, left, tip, ridge)
	_triangle(surface, ridge, tip, right)
	return surface.commit()


func _build_rocks() -> void:
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for index in range(110):
		var point := Vector3(_rng.randf_range(-70.0, 70.0), 5.0, _rng.randf_range(-176.0, 176.0))
		if _road_distance(point) < 27.0:
			continue
		var scale := Vector3(_rng.randf_range(1.2, 4.0), _rng.randf_range(0.8, 3.2), _rng.randf_range(1.2, 4.0))
		transforms.append(Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(scale), point))
		colors.append(Color("bd805d").lerp(Color("e0b986"), _rng.randf()))
	for point in [Vector3(-22.0, 5.0, 30.0), Vector3(16.0, 5.0, 49.0), Vector3(7.0, 5.0, -30.0)]:
		transforms.append(Transform3D(Basis.from_scale(Vector3(20.0, 10.0, 24.0)), point))
		colors.append(Color("c18c67"))
	var rock := SphereMesh.new()
	rock.radius = 1.0
	rock.height = 2.0
	rock.radial_segments = 7
	rock.rings = 3
	_batch("SandstoneBoulders", rock, _material(Color.WHITE), transforms, colors)


func _build_harbor() -> void:
	var timber := _material(Color("7b654e"))
	var deck := BoxMesh.new()
	deck.size = Vector3(62.0, 0.7, 6.0)
	_mesh("HarborPier", deck, timber, Vector3(180.0, -1.7, -55.0))
	var piles: Array[Transform3D] = []
	for index in range(9):
		for side in [-2.3, 2.3]:
			piles.append(Transform3D(Basis.from_scale(Vector3(0.7, 7.0, 0.7)), Vector3(150.0 + index * 7.5, -4.5, -55.0 + side)))
	var cylinder := CylinderMesh.new()
	cylinder.height = 1.0
	cylinder.radial_segments = 10
	_batch("PierPiles", cylinder, timber, piles)
	var white := _material(Color("f3e7c5"))
	var coral := _material(Color("cf5c42"))
	var navy := _material(Color("254c5b"))
	# A lighthouse inside the north bend provides a distant, recognizable landmark.
	for tier in range(5):
		var tower := CylinderMesh.new()
		tower.height = 2.8
		tower.top_radius = 3.3 - tier * 0.32
		tower.bottom_radius = 3.65 - tier * 0.32
		tower.radial_segments = 12
		_mesh("LighthouseTier%d" % tier, tower, white if tier % 2 == 0 else coral, Vector3(-34.0, 6.4 + tier * 2.8, 150.0))
	var lantern := CylinderMesh.new()
	lantern.height = 2.3
	lantern.top_radius = 2.0
	lantern.bottom_radius = 2.0
	lantern.radial_segments = 12
	_mesh("LighthouseLantern", lantern, _material(Color("ffd27d")), Vector3(-34.0, 20.0, 150.0))
	var roof := CylinderMesh.new()
	roof.height = 1.8
	roof.top_radius = 0.0
	roof.bottom_radius = 3.0
	roof.radial_segments = 12
	_mesh("LighthouseRoof", roof, navy, Vector3(-34.0, 22.0, 150.0))
	for index in range(12):
		var buoy := CylinderMesh.new()
		buoy.height = 2.2
		buoy.top_radius = 0.45
		buoy.bottom_radius = 0.9
		buoy.radial_segments = 8
		_mesh("HarborBuoy%02d" % index, buoy, coral if index % 2 == 0 else white,
			Vector3(184.0 + sin(index * 0.8) * 14.0, -3.0, -135.0 + index * 15.0))


static func _road_distance(point: Vector3) -> float:
	return absf(Vector2(point.x, maxf(absf(point.z) - 100.0, 0.0)).length() - 100.0)


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	material.metallic_specular = 0.2
	return material


func _mesh(node_name: String, mesh: Mesh, material: Material, position: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	add_child(instance)
	return instance


func _batch(node_name: String, mesh: Mesh, material: Material,
		transforms: Array[Transform3D], colors: Array[Color] = []) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = not colors.is_empty()
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
		if not colors.is_empty():
			multimesh.set_instance_color(index, colors[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	add_child(instance)


static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	# Godot uses clockwise front faces; retain the outward geometric normal.
	for vertex in [a, c, b]:
		surface.set_normal(normal)
		surface.add_vertex(vertex)
