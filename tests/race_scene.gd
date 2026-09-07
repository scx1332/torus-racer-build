extends SceneTree
## Exercise the loaded circuit, race HUD, physical driving and the real reset key.

var _checks: int = 0
var _failures: int = 0
var _race: Dictionary = {}
var _resets: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Input.use_accumulated_input = false
	var scene := load("res://track.tscn").instantiate() as Node3D
	var manager := scene.get_node("RaceManager")
	manager.persistence_enabled = false
	manager.race_updated.connect(func(snapshot: Dictionary) -> void: _race = snapshot)
	root.add_child(scene)
	var body := scene.get_node("Torus") as TorusBody
	var hud := scene.get_node("HUD")
	var markers := scene.get_node("CheckpointMarkers") as CheckpointMarkers
	body.tuning.rumble_enabled = false
	_check(body.tuning.direct_lean and body.capsule_count == 64 \
		and is_zero_approx(body.linear_damping),
		"Race inherits direct lean and the low-loss rim from the playable lab")
	body.reset_completed.connect(func() -> void: _resets += 1)
	await body.physics_sampled
	_check(manager.target == body and hud.race_manager == manager \
		and markers.race_manager == manager, "Scene connects race observers to the player and manager")
	_check(not _race.get("started", true) and is_zero_approx(_race.get("lap_time", -1.0)),
		"Spawn approaches the start without starting the clock early")
	_check(markers.get_child_count() == 7 and _collision_count(markers) == 0,
		"Seven gate markers have no collision or physical influence")
	var gates: Array = manager.gates
	for index in range(gates.size()):
		var marker := markers.get_child(index) as Node3D
		_check(marker.global_position.is_equal_approx(gates[index].position) \
			and marker.global_basis.y.dot(gates[index].up) > 0.9999,
			"Gate %d visual and crossing plane share the banked layout frame" % index)
	_key(KEY_UP, true)
	for tick in range(240 * 15):
		await body.physics_sampled
		if _race.get("next_gate", 0) == 2:
			break
	_key(KEY_UP, false)
	_check(_race.get("started", false) and _race.get("next_gate", 0) == 2 \
		and _race.get("lap_time", 0.0) > 1.0 and _race.get("lap_valid", false),
		"Real torus crosses start, clears jump and reaches checkpoint 1 in order")
	_check(markers._next_gate == 2 and markers._labels[2].text == "NEXT / CP 02",
		"The next checkpoint becomes the highlighted navigation marker")
	var checkpoint := body.checkpoint_transform
	var first_gate: Dictionary = gates[1]
	var expected: Vector3 = first_gate.position - first_gate.tangent * 2.0 \
		+ first_gate.up * (body.major_radius + body.minor_radius + 0.03)
	_check(checkpoint.origin.distance_to(expected) < 0.01 \
		and checkpoint.basis.z.dot(first_gate.tangent) > 0.999,
		"Passed checkpoint records a safe spawn just behind its forward-facing gate")
	var before: float = _race.get("lap_time", 0.0)
	_key(KEY_R, true)
	for tick in range(8):
		await body.physics_sampled
		if _resets > 0:
			break
	_key(KEY_R, false)
	_check(_resets == 1 and (body.last_sample.origin as Vector3).distance_to(checkpoint.origin) < 0.0001,
		"Real R input restores the last passed checkpoint, not the original start")
	_check(_race.get("next_gate", 0) == 2 and _race.get("lap_time", 0.0) >= before \
		and not _race.get("lap_valid", true),
		"Reset retains progress and running time, invalidates the lap and counts no teleported gate")
	await body.physics_sampled
	_check(absf(body.spin_rate - body.initial_spin) < 0.001,
		"Checkpoint reset relaunches spin through the normal physics path")
	for tick in range(240):
		await body.physics_sampled
	var initial_lean := body.lean_degrees
	_key(KEY_RIGHT, true)
	for tick in range(72):
		await body.physics_sampled
		_check(body.bank_pivot_impulse.is_zero_approx(),
			"Direct lean on the circuit uses native contact without the old pivot assist")
	_key(KEY_RIGHT, false)
	_check(body.lean_degrees > initial_lean + 2.0,
		"A short right input visibly leans the race body after checkpoint reset")
	await body.physics_sampled
	_check(body.input_torque.is_zero_approx(), "Releasing the race lean key removes player torque")
	print("RACE SCENE lap_time=%.3f checkpoint=%s next=%d" % [
		_race.get("lap_time", 0.0), checkpoint.origin, _race.get("next_gate", -1)])
	scene.queue_free()
	var deadline := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < deadline:
		await process_frame
	print("RACE SCENE %s checks=%d failures=%d" % [
		"PASS" if _failures == 0 else "FAIL", _checks, _failures])
	quit(0 if _failures == 0 else 1)


func _collision_count(node: Node) -> int:
	var count := int(node is CollisionObject3D or node is CollisionShape3D)
	for child in node.get_children():
		count += _collision_count(child)
	return count


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
