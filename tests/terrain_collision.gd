extends SceneTree
## Validate rendered terrain against real rays, rolling contacts and the sea hazard.

const SCENERY := preload("res://track_scenery.gd")
const ROAD := preload("res://track_builder.gd")
var _checks: int = 0
var _failures: int = 0
var _completed: int = 0
var _started: int = 0
var _splashes: int = 0
var _resets: int = 0
var _scene: Node3D
var _scenery: TrackScenery
var _road: StaticBody3D
var _hazard: WaterHazard
var _body: TorusBody


func _initialize() -> void:
	_started = Time.get_ticks_msec()
	_run.call_deferred()


func _physics_process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _started > 45000:
		push_error("Terrain test exceeded its bounded 45 second timeout")
		quit(1)
	return false


func _run() -> void:
	_scene = Node3D.new()
	root.add_child(_scene)
	_scenery = SCENERY.new()
	_scenery.name = "Scenery"
	_scene.add_child(_scenery)
	_road = ROAD.new()
	_scene.add_child(_road)
	_hazard = WaterHazard.new()
	_hazard.position.y = -4.0
	_hazard.surface_path = NodePath("../Scenery/Ocean")
	_hazard.water_entered.connect(func(_point: Vector3, _speed: float) -> void: _splashes += 1)
	_scene.add_child(_hazard)
	_body = TorusBody.new()
	_body.position = Vector3(80.0, 9.28, -65.0)
	_body.initial_spin = 24.0
	_body.automatic_nudge = false
	_body.tuning.rumble_enabled = false
	_body.water_hazard = _hazard
	_body.reset_completed.connect(func() -> void: _resets += 1)
	_scene.add_child(_body)
	await _body.physics_sampled
	await _body.physics_sampled
	_validate_meshes()
	_validate_rays()
	_validate_road_clearance()
	await _roll_on_grass()
	await _fall_into_sea()
	_check(_completed == 5, "All terrain test stages completed without script errors")
	_scene.queue_free()
	await process_frame
	print("TERRAIN COLLISION %s checks=%d failures=%d" % [
		"PASS" if _failures == 0 else "FAIL", _checks, _failures])
	quit(0 if _failures == 0 else 1)


func _validate_meshes() -> void:
	for name in ["IslandCliffs", "Beach"]:
		var visual := _scenery.get_node(name) as MeshInstance3D
		var terrain := visual.get_node("TerrainBody") as StaticBody3D
		var collider := terrain.get_node("TerrainCollision") as CollisionShape3D
		var shape := collider.shape as ConcavePolygonShape3D
		_check(shape != null and not shape.backface_collision \
			and shape.get_faces() == visual.mesh.get_faces(),
			name + " uses exactly its visible top and side triangles for static collision")
		_check(terrain.global_transform == visual.global_transform,
			name + " collision and rendering share the same transform")
		var expected := 0.85 if name == "IslandCliffs" else 0.9
		_check(is_equal_approx(terrain.physics_material_override.friction, expected) \
			and terrain.physics_material_override.rough \
			and is_zero_approx(terrain.physics_material_override.bounce),
			name + " has nonbouncy terrain-specific grip")
	_check(_scenery.find_children("*", "CollisionObject3D", true, false).size() == 2,
		"Only island and beach are solid; ocean, palms, rocks and harbor remain cosmetic")
	_completed += 1


func _validate_rays() -> void:
	var island := _scenery.get_node("IslandCliffs/TerrainBody")
	for point in [Vector3(80, 5, -65), Vector3(120, 5, -65), Vector3(0, 5, 0)]:
		var hit := _ray(point)
		_check(not hit.is_empty() and hit.collider == island \
			and absf(hit.position.y - 5.0) < 0.002 and hit.normal.y > 0.999,
			"Visible grass at %s has an upward-facing physical surface at y=5" % point)
	var beach := _scenery.get_node("Beach/TerrainBody")
	for point in [Vector3(146, -1, 0), Vector3(0, -1, 252)]:
		var hit := _ray(point)
		_check(not hit.is_empty() and hit.collider == beach \
			and absf(hit.position.y + 1.0) < 0.002 and hit.normal.y > 0.999,
			"Exposed beach outside the cliff has physical sand at y=-1")
	var sea := _ray(Vector3(170, -4, -65))
	_check(sea.is_empty(), "The off-island water-fall fixture at x=170 remains outside all terrain")
	_completed += 1


func _validate_road_clearance() -> void:
	var clear := true
	var minimum_clearance := INF
	var mismatches := 0
	for index in range(160):
		var frame := TrackLayout.sample_at((float(index) + 0.31) * TrackLayout.length() / 160.0)
		for lane in [-13.4, -6.0, 0.0, 6.0, 13.4]:
			var point: Vector3 = frame.position + frame.right * lane
			var road_hit := _ray(point)
			# Banked rails can overhang the outer shoulder vertically. They belong
			# to the road and sit above its surface; neither is terrain penetration.
			var matches: bool = not road_hit.is_empty() and road_hit.collider == _road \
				and road_hit.position.y >= point.y - 0.025
			clear = clear and matches
			if not matches and mismatches < 6:
				print("TERRAIN ROAD RAY expected=%s lane=%.1f hit=%s" % [point, lane, road_hit])
				mismatches += 1
			var terrain_hit := _ray(point, [_road.get_rid()])
			if not terrain_hit.is_empty():
				minimum_clearance = minf(minimum_clearance, point.y - terrain_hit.position.y)
	_check(clear and minimum_clearance > 0.15,
		"Terrain stays below the full asphalt and shoulder width, including banked corners")
	print("TERRAIN ROAD CLEARANCE minimum=%.4fm" % minimum_clearance)
	_completed += 1


func _roll_on_grass() -> void:
	var contacts := 0
	var minimum_height := INF
	var maximum_speed := 0.0
	var start: Vector3 = _body.last_sample.origin
	for tick in range(960):
		await _body.physics_sampled
		var sample := _body.last_sample
		if sample.grounded:
			contacts += 1
		if contacts > 0:
			minimum_height = minf(minimum_height, sample.origin.y)
		maximum_speed = maxf(maximum_speed, sample.speed)
	_check(contacts > 600 and minimum_height > 6.15,
		"The real torus lands on grass and remains supported instead of falling through it")
	_check(maximum_speed > 5.0 and _body.last_sample.origin.distance_to(start) > 20.0,
		"Grass supports real friction-driven rolling, not only a resting raycast fixture")
	_check(_splashes == 0 and _resets == 0 and not _body.water_pending,
		"Off-road grass travel never triggers the hidden water hazard")
	print("TERRAIN GRASS ROLL grounded=%d min_height=%.4fm speed=%.3fm/s finish=%s" % [
		contacts, minimum_height, maximum_speed, _body.last_sample.origin])
	_completed += 1


func _fall_into_sea() -> void:
	var checkpoint := _body.checkpoint_transform
	# Only the normal reset callback relocates the fixture, inside force integration.
	_body.set_checkpoint(Transform3D(Basis.IDENTITY, Vector3(170.0, 9.28, -65.0)))
	_body.request_reset()
	await _body.physics_sampled
	_body.set_checkpoint(checkpoint)
	var resets_before := _resets
	var fell := false
	for tick in range(720):
		await _body.physics_sampled
		fell = fell or (_body.last_sample.origin.y < -3.0 and _body.water_pending)
		if _resets > resets_before:
			break
	_check(fell and _splashes == 1 and _resets == resets_before + 1,
		"The actual ocean outside the new terrain still produces one splash and automatic rescue")
	_check(not _body.water_pending \
		and (_body.last_sample.origin as Vector3).distance_to(checkpoint.origin) < 0.0001,
		"Off-island rescue returns to the dry checkpoint")
	_completed += 1


func _ray(point: Vector3, additional_exclusions: Array[RID] = []) -> Dictionary:
	var excluded: Array[RID] = [_body.get_rid()]
	excluded.append_array(additional_exclusions)
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 25.0,
		point + Vector3.DOWN * 35.0, 0xffffffff, excluded)
	query.hit_back_faces = false
	return _scene.get_world_3d().direct_space_state.intersect_ray(query)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
