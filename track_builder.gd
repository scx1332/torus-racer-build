extends StaticBody3D
## A single static path-extruded road. The moving torus keeps its capsule compound.

const STEP := 2.0
const THICKNESS := 0.65
const RAIL_HEIGHT := 0.9
var sections: Array[Dictionary] = []


func _ready() -> void:
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.8
	var distances: Array[float] = []
	for index in range(int(ceil(TrackLayout.length() / STEP))):
		distances.append(minf(float(index) * STEP, TrackLayout.length()))
	# Include the lip exactly so collision geometry matches the analytic ramp.
	for distance in [TrackLayout.JUMP_START, TrackLayout.JUMP_LIP, TrackLayout.JUMP_END,
			TrackLayout.STRAIGHT, TrackLayout.STRAIGHT + PI * TrackLayout.RADIUS,
			2.0 * TrackLayout.STRAIGHT + PI * TrackLayout.RADIUS, TrackLayout.length()]:
		if not distances.has(distance):
			distances.append(distance)
	distances.sort()
	for distance in distances:
		var section := TrackLayout.sample_at(distance)
		section["distance"] = distance
		sections.append(section)
	_build_surface()
	_build_rails()
	_build_supports()


func _build_surface() -> void:
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material := ShaderMaterial.new()
	material.shader = preload("res://materials/road.gdshader")
	top.set_material(material)
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	sides.set_material(_material(Color("b7a589")))
	var half := TrackLayout.WIDTH * 0.5 + TrackLayout.SHOULDER
	for index in range(sections.size() - 1):
		var a := sections[index]
		var b := sections[index + 1]
		var points: Array[Vector3] = [a.position - a.right * half, a.position + a.right * half,
			b.position + b.right * half, b.position - b.right * half]
		var uv_left := 0.5 - half / TrackLayout.WIDTH
		var uv_right := 0.5 + half / TrackLayout.WIDTH
		var uvs: Array[Vector2] = [Vector2(uv_left, a.distance), Vector2(uv_right, a.distance),
			Vector2(uv_right, b.distance), Vector2(uv_left, b.distance)]
		# Changing bank twists a wide quad: subdivide across the deck as well as
		# along it, keeping the centerline supported without diagonal height dips.
		for lane in range(8):
			var left := float(lane) / 8.0
			var right := float(lane + 1) / 8.0
			_quad(top, [points[0].lerp(points[1], left), points[0].lerp(points[1], right),
				points[3].lerp(points[2], right), points[3].lerp(points[2], left)],
				[uvs[0].lerp(uvs[1], left), uvs[0].lerp(uvs[1], right),
				uvs[3].lerp(uvs[2], right), uvs[3].lerp(uvs[2], left)],
				(a.up + b.up).normalized())
		for edge in [[0, 3], [2, 1]]:
			var p: Vector3 = points[edge[0]]
			var q: Vector3 = points[edge[1]]
			_quad(sides, [p, q, q + Vector3.DOWN * THICKNESS, p + Vector3.DOWN * THICKNESS],
				[Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN],
				(q - p).cross(Vector3.UP).normalized())
	var mesh := top.commit()
	var visual := MeshInstance3D.new()
	visual.name = "RoadSurface"
	visual.mesh = mesh
	add_child(visual)
	var collider := CollisionShape3D.new()
	collider.name = "RoadCollision"
	# Concave mesh is valid here: only this unmoving road is a StaticBody3D.
	collider.shape = mesh.create_trimesh_shape()
	add_child(collider)
	var edge_visual := MeshInstance3D.new()
	edge_visual.name = "DeckEdges"
	edge_visual.mesh = sides.commit()
	add_child(edge_visual)


func _build_rails() -> void:
	var count := int(ceil(TrackLayout.length() / 5.0))
	var segment_length := TrackLayout.length() / count
	var pale := _material(Color("eadbc1"))
	var coral := _material(Color("cf5039"))
	for side in [-1.0, 1.0]:
		for index in range(count):
			var frame := TrackLayout.sample_at((index + 0.5) * segment_length)
			var position: Vector3 = frame.position + frame.right * side \
				* (TrackLayout.WIDTH * 0.5 + TrackLayout.SHOULDER + 0.35)
			position += frame.up * RAIL_HEIGHT * 0.5
			var basis := Basis(-frame.right, frame.up, frame.tangent)
			var size := Vector3(0.65, RAIL_HEIGHT, segment_length + 0.12)
			var rail := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = size
			rail.mesh = mesh
			rail.material_override = coral if index % 4 == 0 else pale
			rail.transform = Transform3D(basis, position)
			add_child(rail)
			var collider := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = size
			collider.shape = shape
			collider.transform = rail.transform
			add_child(collider)


func _build_supports() -> void:
	var concrete := _material(Color("b6a285"))
	for index in range(int(TrackLayout.length() / 22.0)):
		var frame := TrackLayout.sample_at(float(index) * 22.0)
		for side in [-1.0, 1.0]:
			var top: Vector3 = frame.position + frame.right * side * 8.0
			var mesh := CylinderMesh.new()
			mesh.top_radius = 1.0
			mesh.bottom_radius = 1.5
			mesh.height = top.y + 6.0
			mesh.radial_segments = 8
			var column := MeshInstance3D.new()
			column.mesh = mesh
			column.material_override = concrete
			column.position = Vector3(top.x, top.y - mesh.height * 0.5 - 0.1, top.z)
			add_child(column)


func _quad(surface: SurfaceTool, points: Array, uvs: Array, normal: Vector3) -> void:
	# Clockwise front faces, as required by Godot's renderer and one-sided collider.
	for index in [0, 2, 1, 0, 3, 2]:
		surface.set_normal(normal)
		surface.set_uv(uvs[index])
		surface.add_vertex(points[index])


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	return material
