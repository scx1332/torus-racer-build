extends SceneTree
## Validate the real drivable mesh, then roll the default torus through its crest.

const TRACK := preload("res://track.tscn")

class FallProbe extends TorusBody:
	var fall_requested: bool = false

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		if fall_requested:
			# Fixture-only relocation starts a free fall beside the actual road;
			# cancel translation additively and preserve the player's real spin.
			state.apply_central_impulse(-state.linear_velocity / state.inverse_mass)
			state.transform.origin = Vector3(170.0, 9.28, -65.0)
			fall_requested = false
		super._integrate_forces(state)

var _checks: int = 0
var _failures: int = 0
var _ray_count: int = 0
var _completed: Array[String] = []
var _water_entries: Array[Dictionary] = []
var _reset_count: int = 0
var _splash_sounds: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Input.use_accumulated_input = false
	_validate_layout()
	var scene := TRACK.instantiate()
	var original := scene.get_node("Torus") as TorusBody
	# Preserve every serialized scene export when adding the test-only callback.
	# The original node remains, so all scene references still target the player.
	var exports := {}
	for property in original.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE:
			exports[property.name] = original.get(property.name)
	original.set_script(FallProbe)
	for key in exports:
		original.set(key, exports[key])
	root.add_child(scene)
	var road := scene.get_node("Road") as StaticBody3D
	var body := scene.get_node("Torus") as FallProbe
	var hazard := scene.get_node("WaterHazard") as WaterHazard
	hazard.water_entered.connect(func(point: Vector3, speed: float) -> void:
		_water_entries.append({"position": point, "speed": speed}))
	body.reset_completed.connect(func() -> void: _reset_count += 1)
	(scene.get_node("GameAudio") as GameAudio).cue_played.connect(func(kind: StringName) -> void:
		if kind == &"splash":
			_splash_sounds += 1)
	# The scene may carry a slow hand-testing tune; pin the reference tune here.
	body.tuning = TorusTuning.new()
	body.tuning.rumble_enabled = false
	body.initial_spin = 24.0
	await body.physics_sampled
	await body.physics_sampled
	_validate_mesh(road, body)
	_validate_rays(road, body)
	_validate_water_wiring(scene, body)
	var scenery := scene.get_node("Scenery")
	_check(scenery.get_node("PalmTrunks").multimesh.instance_count == scenery.palm_count * 3 \
		and scenery.get_node("PalmFronds").multimesh.instance_count == scenery.palm_count * 7,
		"Coastal placement fills the requested palm count")
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://track.tscn",
		"The coastline track is the default scene")
	_check(load("res://controls_lab.tscn") is PackedScene \
		and load("res://physics_validation.tscn") is PackedScene,
		"Both earlier physics labs remain loadable")
	await _drive_crest(body, true)
	_key(KEY_UP, false)
	body.request_reset()
	await body.physics_sampled
	await _drive_crest(body, false)
	_check(_water_entries.is_empty() and _splash_sounds == 0 and _reset_count == 1,
		"Both safe crest runs stay dry with no splash, splash sound or automatic rescue")
	await _offroad_fall(scene, body)
	_check(_completed.size() == 7, "All geometry, wiring, driving and water-fall checks completed")
	scene.queue_free()
	# Scene removal stops audio, whose mixer releases playbacks asynchronously.
	# Use wall time: --fixed-fps advances simulation timers faster than the mixer.
	var audio_deadline := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < audio_deadline:
		await process_frame
	print("TRACK VALIDATION %s checks=%d failures=%d rays=%d" % [
		"PASS" if _failures == 0 else "FAIL", _checks, _failures, _ray_count])
	quit(0 if _failures == 0 else 1)


func _validate_water_wiring(scene: Node, body: TorusBody) -> void:
	var hazard := scene.get_node("WaterHazard") as WaterHazard
	var effects := scene.get_node("WaterEffects") as WaterEffects
	var audio := scene.get_node("GameAudio") as GameAudio
	var ocean := scene.get_node("Scenery/Ocean") as MeshInstance3D
	_check(body.water_hazard == hazard and effects.hazard == hazard \
		and effects.debug_view == scene.get_node("TorusDebug") \
		and audio.water_hazard == hazard and audio.target == body,
		"Loaded scene connects player, splash visuals, debug and audio to the same water hazard")
	_check(hazard._surface == ocean and is_equal_approx(hazard.surface_level(), ocean.global_position.y) \
		and is_equal_approx(hazard.surface_level(), -4.0),
		"Analytic water height is linked to the generated ocean mesh")
	_check(hazard.water_entered.is_connected(effects._on_water_entered) \
		and hazard.water_entered.is_connected(audio._on_water_entered) \
		and body.physics_sampled.is_connected(audio._on_physics_sampled) \
		and body.reset_completed.is_connected(audio._on_reset),
		"Live splash and audio observers are connected after scene startup")
	_completed.append("water wiring")


func _offroad_fall(scene: Node, body: FallProbe) -> void:
	var checkpoint := body.checkpoint_transform
	var resets_before := _reset_count
	var peak_fall_speed := 0.0
	var fell_beside_track := false
	body.fall_requested = true
	for tick in range(720):
		await body.physics_sampled
		var sample := body.last_sample
		peak_fall_speed = maxf(peak_fall_speed, -sample.linear_velocity.y)
		fell_beside_track = fell_beside_track or (sample.origin.x > 160.0 \
			and sample.origin.y < TrackLayout.HEIGHT - 1.0 and not sample.grounded)
		if _reset_count > resets_before:
			break
	_check(fell_beside_track and peak_fall_speed > 10.0,
		"The actual scene player falls freely off-road toward the ocean")
	_check(_water_entries.size() == 1 and _splash_sounds == 1 \
		and scene.get_node("WaterEffects")._next_burst == 1,
		"A real off-road fall emits exactly one splash event, visible burst and sound cue")
	_check(_reset_count == resets_before + 1 and not body.water_pending \
		and (body.last_sample.origin as Vector3).distance_to(checkpoint.origin) < 0.0001 \
		and (body.last_sample.linear_velocity as Vector3).length() < 0.0001 \
		and (body.last_sample.angular_velocity as Vector3).length() < 0.0001,
		"Scene hazard automatically restores the last checkpoint with cancelled momentum")
	await body.physics_sampled
	_check(absf(body.spin_rate - body.initial_spin) < 0.001,
		"The rescued scene player relaunches its spin on the following physics tick")
	print("TRACK WATER FALL splash=%d audio=%d resets=%d peak_fall_speed=%.3fm/s" % [
		_water_entries.size(), _splash_sounds, _reset_count - resets_before, peak_fall_speed])
	_completed.append("off-road fall")


func _validate_layout() -> void:
	var length := TrackLayout.length()
	_check(absf(length - (2.0 * TrackLayout.STRAIGHT + TAU * TrackLayout.RADIUS)) < 0.001,
		"Closed stadium has the declared straights and curve radius")
	var start := TrackLayout.sample_at(0.0)
	var finish := TrackLayout.sample_at(length)
	_check(start.position.is_equal_approx(finish.position) \
		and start.tangent.is_equal_approx(finish.tangent) \
		and start.right.is_equal_approx(finish.right), "Loop seam closes its position and frame")
	var frames_valid := true
	for index in range(257):
		var frame := TrackLayout.sample_at(float(index) * length / 256.0)
		var tangent: Vector3 = frame.tangent
		var right: Vector3 = frame.right
		var up: Vector3 = frame.up
		frames_valid = frames_valid and frame.position.is_finite() \
			and tangent.is_normalized() and right.is_normalized() and up.is_normalized() \
			and absf(tangent.dot(right)) < 0.0001 and absf(tangent.dot(up)) < 0.0001 \
			and absf(right.dot(up)) < 0.0001 and up.y > 0.8
	_check(frames_valid, "Sampled road frames are finite, orthonormal and upward")
	for join in [0.0, TrackLayout.STRAIGHT, TrackLayout.STRAIGHT + PI * TrackLayout.RADIUS,
			2.0 * TrackLayout.STRAIGHT + PI * TrackLayout.RADIUS]:
		var before := TrackLayout.sample_at(join - 0.01)
		var after := TrackLayout.sample_at(join + 0.01)
		_check(before.position.distance_to(after.position) < 0.021 \
			and before.right.distance_to(after.right) < 0.001,
			"Centerline and bank join smoothly at distance %.2f" % join)
	for join in [TrackLayout.JUMP_START, TrackLayout.JUMP_LIP, TrackLayout.JUMP_END]:
		var before := TrackLayout.sample_at(join - 0.01)
		var after := TrackLayout.sample_at(join + 0.01)
		_check(before.position.distance_to(after.position) < 0.025,
			"The jump has a continuous road surface at distance %.2f" % join)
	_check(absf(TrackLayout.sample_at(TrackLayout.JUMP_LIP).position.y \
		- TrackLayout.HEIGHT - TrackLayout.JUMP_HEIGHT) < 0.001, "Launch crest has the declared rise")
	_check(TrackLayout.spawn_transform().origin.is_equal_approx(Vector3(100.0, 9.28, -65.0)),
		"Spawn sits above the approach straight")
	_completed.append("layout")


func _validate_mesh(road: StaticBody3D, body: TorusBody) -> void:
	var visual := road.get_node("RoadSurface") as MeshInstance3D
	var collision := road.get_node("RoadCollision") as CollisionShape3D
	_check(visual.mesh is ArrayMesh and visual.mesh.get_surface_count() > 0,
		"Road uses a generated render mesh")
	_check(collision.shape is ConcavePolygonShape3D \
		and not collision.shape.backface_collision,
		"Concave collision belongs to the static road and uses front faces")
	var faces: PackedVector3Array = collision.shape.get_faces()
	_check(faces.size() > 1000 and faces.size() == visual.mesh.get_faces().size(),
		"Road collision covers the complete render surface")
	var upward := true
	for index in range(0, faces.size(), 3):
		# Godot front faces are clockwise: reverse the mathematical cross product.
		var normal := (faces[index + 2] - faces[index]).cross(faces[index + 1] - faces[index])
		upward = upward and normal.length_squared() > 0.000001 and normal.normalized().y > 0.8
	_check(upward, "Every road triangle is nondegenerate and faces upward")
	var bounds := visual.mesh.get_aabb()
	_check(bounds.size.x > 200.0 and bounds.size.x < 240.0 \
		and bounds.size.z > 400.0 and bounds.size.z < 440.0 \
		and bounds.position.y > 4.0 and bounds.end.y <= 11.01,
		"Mesh bounds cover the elevated stadium, banking and crest")
	var capsules := 0
	var dynamic_concave := false
	for child in body.get_children():
		if child is CollisionShape3D:
			capsules += int(child.shape is CapsuleShape3D)
			dynamic_concave = dynamic_concave or child.shape is ConcavePolygonShape3D
	_check(capsules == body.capsule_count and capsules == 64 and not dynamic_concave,
		"The moving torus uses the 64-capsule low-loss rim")
	_completed.append("mesh")


func _validate_rays(road: StaticBody3D, body: TorusBody) -> void:
	var distances: Array[float] = [-0.02, 0.02, TrackLayout.JUMP_START + 0.25,
		TrackLayout.JUMP_LIP - 0.25, TrackLayout.JUMP_LIP + 0.25, TrackLayout.JUMP_END - 0.25]
	for index in range(64):
		distances.append((float(index) + 0.37) * TrackLayout.length() / 64.0)
	var hits_match := true
	var mismatches := PackedStringArray()
	for distance in distances:
		var frame := TrackLayout.sample_at(distance)
		for lane in [-0.4, 0.0, 0.4]:
			var point: Vector3 = frame.position + frame.right * TrackLayout.WIDTH * lane
			var hit := _road_ray(road, body, point)
			var matches: bool = not hit.is_empty() and hit.collider == road \
				and absf(hit.position.y - point.y) < 0.02 and hit.normal.dot(frame.up) > 0.85
			hits_match = hits_match and matches
			if not matches and mismatches.size() < 8:
				mismatches.append("s=%.3f lane=%.1f expected=%s hit=%s" % [distance, lane, point, hit])
	for mismatch in mismatches:
		print("ROAD RAY MISMATCH " + mismatch)
	_check(hits_match, "Front-face rays find matching road height and normal around all lanes and the seam")
	for distance in [TrackLayout.STRAIGHT + PI * TrackLayout.RADIUS * 0.5,
			2.0 * TrackLayout.STRAIGHT + PI * TrackLayout.RADIUS * 1.5]:
		var frame := TrackLayout.sample_at(distance)
		var inside := _road_ray(road, body, frame.position + frame.right * 9.0)
		var outside := _road_ray(road, body, frame.position - frame.right * 9.0)
		_check(not inside.is_empty() and not outside.is_empty() \
			and outside.position.y - inside.position.y > 3.0,
			"Banked corner collision slopes down toward the circuit interior")
	_completed.append("rays")


func _road_ray(road: StaticBody3D, body: TorusBody, point: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 20.0,
		point - Vector3.UP * 20.0, 0xffffffff, [body.get_rid()])
	query.hit_back_faces = false
	_ray_count += 1
	return road.get_world_3d().direct_space_state.intersect_ray(query)


func _drive_crest(body: TorusBody, accelerate: bool) -> void:
	_key(KEY_UP, accelerate)
	var mode := "accelerating" if accelerate else "coasting"
	var reached := false
	var on_approach := false
	var air_ticks := 0
	var longest_air := 0
	var peak_height := 0.0
	var peak_speed := 0.0
	var finite := true
	for tick in range(240 * 20):
		await body.physics_sampled
		var sample := body.last_sample
		var position: Vector3 = sample.origin
		var progress := position.z + TrackLayout.STRAIGHT * 0.5
		finite = finite and position.is_finite() and sample.linear_velocity.is_finite() \
			and sample.angular_velocity.is_finite()
		if progress < TrackLayout.JUMP_START and sample.grounded:
			on_approach = true
		if progress >= TrackLayout.JUMP_LIP - 2.0:
			air_ticks = 0 if sample.grounded else air_ticks + 1
			longest_air = maxi(longest_air, air_ticks)
		peak_height = maxf(peak_height, position.y)
		peak_speed = maxf(peak_speed, sample.speed)
		if progress > TrackLayout.JUMP_END + 8.0 and sample.grounded:
			reached = true
			break
		if not finite or position.y < TrackLayout.HEIGHT - 3.0:
			break
	_check(on_approach and peak_speed > 10.0, "Default torus rolls along the real approach while " + mode)
	_check(finite and reached, "Default torus clears the ramp and lands beyond it while " + mode)
	_check(peak_height > TrackLayout.HEIGHT + TrackLayout.JUMP_HEIGHT + 1.0 \
		and (not accelerate or longest_air >= 12),
		"The crest is reachable and acceleration produces a jump without hop input")
	_check(absf(body.last_sample.origin.x - TrackLayout.RADIUS) < TrackLayout.WIDTH * 0.5,
		"Straight driving remains within road width through landing")
	print("TRACK DRIVE mode=%s reached=%s airborne=%.3fs peak_height=%.3fm peak_speed=%.3fm/s finish=%s" % [
		mode, reached, float(longest_air) / Engine.physics_ticks_per_second, peak_height,
		peak_speed, body.last_sample.origin])
	_completed.append(mode)


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
