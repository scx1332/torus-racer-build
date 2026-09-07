class_name TrackProps
extends Node3D
## Deterministic coastal race furniture. Every child is visual; no collisions.

var _navy: StandardMaterial3D
var _teal: StandardMaterial3D
var _coral: StandardMaterial3D
var _cream: StandardMaterial3D
var _gold: StandardMaterial3D
var _steel: StandardMaterial3D


func _ready() -> void:
	_navy = _paint(Color("123d4d"))
	_teal = _paint(Color("31cfbb"))
	_coral = _paint(Color("ef795c"))
	_cream = _paint(Color("fff1d5"))
	_gold = _paint(Color("ffca60"))
	_steel = _paint(Color("8caaad"), 0.45, 0.5)
	_gantry(55.0)
	_canopy(82.0, -1.0, _teal, "COAST CREW / 01")
	_canopy(TrackLayout.length() * 0.5 + 78.0, 1.0, _coral, "COAST CREW / 02")
	for distance: float in [24.0, 43.0, 72.0, 95.0]:
		_banner(distance, -1.0, _coral)
		_banner(distance + 5.0, 1.0, _teal)
	for entry: float in [200.0, TrackLayout.length() * 0.5 + 200.0]:
		_section_sign(entry - 34.0, -1.0, "BANK RIGHT", "FOLLOW THE COAST", _gold)
		for offset: float in [-18.0, 2.0, 22.0, 42.0]:
			_chevron(entry + offset)
	_section_sign(91.0, -1.0, "JUMP", "CREST AHEAD", _coral)
	_section_sign(TrackLayout.length() * 0.5 + 18.0, 1.0,
		"SEA BRIDGE", "OPEN WATER / SECTOR 02", _teal)


func _gantry(distance: float) -> void:
	var width := float(TrackLayout.sample_at(distance).width)
	var frame := _mount("StartFinish", distance, 0.0)
	var pillar_x := width * 0.5 + 3.0
	var span := pillar_x * 2.0 + 1.0
	for side: float in [-1.0, 1.0]:
		var x := pillar_x * side
		_box(frame, Vector3(x, -6.0, 0), Vector3(1.1, 12.0, 1.1), _steel)
		_box(frame, Vector3(x, 0.15, 0), Vector3(1.5, 0.3, 1.5), _steel)
		_box(frame, Vector3(x, 3.85, 0), Vector3(0.85, 7.7, 0.8), _navy)
		_box(frame, Vector3(x, 3.9, 0.43), Vector3(0.2, 6.9, 0.08), _teal)
		_box(frame, Vector3(x, 6.75, 0.48), Vector3(0.6, 0.13, 0.1), _gold)
	# The lowest overhead geometry is 7.35 m above the road: clear of the
	# rolling body and its chase camera. Pillars stand beyond the road edges.
	_box(frame, Vector3(0, 8.1, 0), Vector3(span, 1.5, 0.9), _navy)
	_box(frame, Vector3(0, 8.9, 0), Vector3(span + 0.4, 0.14, 1.02), _teal)
	_box(frame, Vector3(0, 7.39, 0.5), Vector3(span - 0.6, 0.09, 0.08), _coral)
	_label(frame, "TORUS / COASTLINE RUN", Vector3(0.8, 8.28, 0.48), 0.0105, _cream.albedo_color)
	_label(frame, "START / FINISH", Vector3(0.8, 7.67, 0.49), 0.003, _teal.albedo_color)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.24
	ring.outer_radius = 0.55
	ring.rings = 32
	ring.ring_segments = 12
	var emblem := MeshInstance3D.new()
	emblem.name = "DonutEmblem"
	emblem.mesh = ring
	emblem.material_override = _gold
	emblem.position = Vector3(-width * 0.45, 8.1, 0.58)
	emblem.rotation.x = PI * 0.5
	frame.add_child(emblem)


func _canopy(distance: float, side: float, color: StandardMaterial3D, title: String) -> void:
	var width := float(TrackLayout.sample_at(distance).width)
	var tent := _mount("CoastCrew", distance, side * (width * 0.5 + 10.0))
	# The crew canopy sits on its own pier, outside the driveable bridge deck.
	_box(tent, Vector3(0, -0.18, 0), Vector3(11.0, 0.36, 7.0), _cream)
	for x: float in [-4.8, 4.8]:
		for z: float in [-2.8, 2.8]:
			_box(tent, Vector3(x, -6.0, z), Vector3(0.4, 12.0, 0.4), _steel)
			_box(tent, Vector3(x, 1.65, z), Vector3(0.15, 3.3, 0.15), _steel)
	var pitch := atan2(0.9, 3.0)
	var roof_length := Vector2(3.0, 0.9).length()
	for stripe in range(8):
		var stripe_color := color if stripe % 2 == 0 else _cream
		for end: float in [-1.0, 1.0]:
			var roof := _box(tent, Vector3(-4.375 + stripe * 1.25, 3.75, end * 1.5),
				Vector3(1.25, 0.08, roof_length), stripe_color)
			roof.rotation.x = pitch * end
	_box(tent, Vector3(0, 3.13, 3.02), Vector3(10.0, 0.4, 0.09), color)
	_label(tent, title, Vector3(0, 3.13, 3.09), 0.003, _navy.albedo_color)
	_box(tent, Vector3(0, 0.6, -0.4), Vector3(6.0, 1.2, 0.8), _navy)
	_box(tent, Vector3(0, 1.23, -0.4), Vector3(6.3, 0.12, 1.0), _cream)


func _banner(distance: float, side: float, color: StandardMaterial3D) -> void:
	var width := float(TrackLayout.sample_at(distance).width)
	var flag := _mount("CoastBanner", distance, side * (width * 0.5 + 3.5))
	_box(flag, Vector3(0, 2.8, 0), Vector3(0.1, 5.6, 0.1), _steel)
	_box(flag, Vector3(0.75, 3.45, 0), Vector3(1.35, 3.8, 0.07), color)
	_box(flag, Vector3(0.75, 5.15, 0.05), Vector3(1.35, 0.18, 0.05), _cream)
	_box(flag, Vector3(0.75, 1.85, 0.05), Vector3(1.35, 0.18, 0.05), _navy)
	var lettering := _label(flag, "COAST", Vector3(0.75, 3.45, 0.055), 0.0055, _navy.albedo_color)
	lettering.rotation.z = PI * 0.5


func _section_sign(distance: float, side: float, title: String,
		subtitle: String, color: StandardMaterial3D) -> void:
	var width := float(TrackLayout.sample_at(distance).width)
	var sign := _mount("SectionSign", distance, side * (width * 0.5 + 5.0))
	_box(sign, Vector3(0, 1.35, 0), Vector3(0.15, 2.7, 0.15), _steel)
	_box(sign, Vector3(0, 2.75, 0), Vector3(5.2, 1.5, 0.16), _navy)
	_box(sign, Vector3(-2.5, 2.75, 0.11), Vector3(0.19, 1.5, 0.08), color)
	_label(sign, title, Vector3(0.12, 2.98, 0.1), 0.0048, _cream.albedo_color)
	_label(sign, subtitle, Vector3(0.12, 2.46, 0.1), 0.0018, color.albedo_color)


func _chevron(distance: float) -> void:
	var width := float(TrackLayout.sample_at(distance).width)
	var sign := _mount("RightTurnChevron", distance, -(width * 0.5 + 4.0))
	_box(sign, Vector3(0, 0.85, 0), Vector3(0.12, 1.7, 0.12), _steel)
	_box(sign, Vector3(0, 1.9, 0), Vector3(3.0, 1.5, 0.15), _navy)
	for x: float in [-0.75, 0.65]:
		_bar(sign, Vector3(x - 0.35, 2.45, 0.11), Vector3(x + 0.3, 1.9, 0.11), _gold)
		_bar(sign, Vector3(x + 0.3, 1.9, 0.11), Vector3(x - 0.35, 1.35, 0.11), _gold)


func _mount(node_name: String, distance: float, lateral: float) -> Node3D:
	var sample: Dictionary = TrackLayout.sample_at(distance)
	var forward := Vector3(sample.tangent).slide(Vector3.UP).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var node := Node3D.new()
	node.name = node_name
	# Local +Z faces approaching racers; posts remain vertical on banked road.
	node.transform = Transform3D(Basis(right, Vector3.UP, -forward),
		Vector3(sample.position) + Vector3(sample.right) * lateral)
	add_child(node)
	return node


func _box(parent: Node3D, position: Vector3, size: Vector3,
		material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.position = position
	parent.add_child(visual)
	return visual


func _bar(parent: Node3D, from: Vector3, to: Vector3, material: StandardMaterial3D) -> void:
	var direction := to - from
	var bar := _box(parent, (from + to) * 0.5, Vector3(0.21, direction.length(), 0.06), material)
	bar.basis = Basis(Quaternion(Vector3.UP, direction.normalized()))


func _label(parent: Node3D, text: String, position: Vector3,
		pixel_size: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = pixel_size
	label.outline_size = 0
	label.modulate = color
	label.position = position
	parent.add_child(label)
	return label


func _paint(color: Color, roughness: float = 0.72, metal: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metal
	return material
