class_name CheckpointMarkers
extends Node3D
## Removable gate furniture. Highlights race state without participating in physics.

@export var race_manager: Node

const WAITING := Color("658f94")
const NEXT := Color("65f2c3")
const FINISH := Color("ffd378")
var _paints: Array[StandardMaterial3D] = []
var _labels: Array[Label3D] = []
var _next_gate: int = -1
var _started: bool = false


func _ready() -> void:
	if not is_instance_valid(race_manager):
		return
	var gates: Array = race_manager.get("gates")
	for index in range(gates.size()):
		_build_marker(gates[index], index)
	race_manager.connect(&"race_updated", _on_race_updated)
	_on_race_updated({"next_gate": 0, "started": false})


func _build_marker(frame: Dictionary, index: int) -> void:
	var marker := Node3D.new()
	marker.name = "StartFinish" if index == 0 else "Checkpoint%02d" % index
	marker.transform = Transform3D(Basis(frame.right, frame.up, -frame.tangent), frame.position)
	add_child(marker)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = WAITING
	paint.roughness = 0.8
	_paints.append(paint)
	if index > 0:
		# All posts stand outside the road shoulders; the crossbar clears the ring.
		var half_span := TrackLayout.WIDTH * 0.5 + TrackLayout.SHOULDER + 1.7
		for side: float in [-1.0, 1.0]:
			_box(marker, Vector3(side * half_span, 4.15, 0.0), Vector3(0.3, 8.3, 0.3), paint)
		_box(marker, Vector3(0.0, 8.3, 0.0), Vector3(half_span * 2.0, 0.18, 0.3), paint)
		_box(marker, Vector3(0.0, 0.04, 0.0), Vector3(TrackLayout.WIDTH, 0.025, 0.32), paint)
	var label := Label3D.new()
	label.name = "GateLabel"
	label.text = "START" if index == 0 else "CHECKPOINT %02d" % index
	label.position = Vector3(0.0, 10.0 if index == 0 else 9.15, 0.0)
	label.font_size = 64
	label.pixel_size = 0.018
	label.outline_size = 8
	label.modulate = WAITING
	marker.add_child(label)
	_labels.append(label)


func _on_race_updated(snapshot: Dictionary) -> void:
	var next: int = snapshot.get("next_gate", 0)
	var started: bool = snapshot.get("started", false)
	if next == _next_gate and started == _started:
		return
	_next_gate = next
	_started = started
	for index in range(_paints.size()):
		var color := (FINISH if index == 0 else NEXT) if index == next else WAITING
		_paints[index].albedo_color = color
		_paints[index].emission_enabled = index == next
		_paints[index].emission = color * 0.25
		_labels[index].modulate = color
		_labels[index].text = ("FINISH" if started else "START") if index == 0 \
			else ("NEXT / CP %02d" if index == next else "CHECKPOINT %02d") % index


func _box(parent: Node3D, position: Vector3, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	parent.add_child(instance)
