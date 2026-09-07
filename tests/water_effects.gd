extends "res://tests/debug_invariance.gd"
## Synthetic entry events plus 720 real physics ticks in identical worlds.

class FakeHazard extends Node3D:
	signal water_entered(position: Vector3, impact_speed: float)

var _hazard: FakeHazard
var _effects: WaterEffects
var _anchor: Node3D
var _probes_complete: bool = false


func _setup() -> void:
	super._setup()
	_debug.set_enabled(false)
	_hazard = FakeHazard.new()
	_observed_world.add_child(_hazard)
	_anchor = Node3D.new()
	_observed_world.add_child(_anchor)
	_effects = WaterEffects.new()
	_effects.hazard = _hazard
	_effects.debug_view = _debug
	_anchor.add_child(_effects)
	_probe_splashes()


func _probe_splashes() -> void:
	var point := Vector3(12.0, -4.0, 8.0)
	_check(_effects._bursts.size() == WaterEffects.POOL_SIZE, "Splash pool must be fixed")
	var node_count := _effects.get_child_count()
	_hazard.water_entered.emit(point, 14.0)
	_check(_effects._pending.size() == 1, "Physics event must queue one splash")
	_check(not _effects._bursts[0].droplets.emitting,
		"Physics callback must not change particles before the render tick")
	_effects._process(0.016)
	var burst: Dictionary = _effects._bursts[0]
	_check(_effects._pending.is_empty() and _effects._next_burst == 1,
		"A queued entry must emit exactly once")
	_check(burst.droplets.emitting and burst.mist.emitting and burst.rings[0].visible,
		"Water entry must emit droplets, mist and visible foam")
	_check(burst.droplets.one_shot and burst.mist.one_shot,
		"Splash particles must be finite one-shot bursts")
	_check(not burst.droplets.local_coords and not burst.mist.local_coords,
		"Particles must remain in world coordinates")
	_check(burst.droplets.amount == 36 and burst.mist.amount == 18,
		"Particle counts must be bounded per burst")
	_check(burst.droplets.global_position.is_equal_approx(point + Vector3.UP * 0.08),
		"Splash must originate at the water hit, not the torus or scene origin")
	var start_radius: float = burst.rings[0].scale.x
	_effects._process(0.2)
	_check(_effects._next_burst == 1 and burst.rings[0].scale.x > start_radius,
		"Next frame must expand foam without emitting a second splash")
	_check(burst.rings[1].visible, "The trailing foam ring must appear after its delay")
	var splash_position: Vector3 = burst.droplets.global_position
	_anchor.position = Vector3(50.0, 20.0, -30.0)
	_observed.reset_completed.emit()
	_check(burst.droplets.global_position == splash_position and burst.rings[0].visible,
		"Parent motion and body reset must preserve the old world-space splash")
	_effects._process(WaterEffects.LIFETIME)
	_check(not burst.rings[0].visible and not burst.rings[1].visible,
		"Both foam rings must expire")
	for index in range(40):
		_hazard.water_entered.emit(point + Vector3.RIGHT * index, 8.0)
	_check(_effects._pending.size() == WaterEffects.POOL_SIZE,
		"Even several physics events before rendering must use a bounded queue")
	_effects._process(0.016)
	_check(_effects.get_child_count() == node_count
		and _effects._bursts.size() == WaterEffects.POOL_SIZE,
		"Repeated splashes must reuse nodes, meshes and emitters")
	_effects._clear_effects()
	for pooled: Dictionary in _effects._bursts:
		_check(not pooled.droplets.emitting and not pooled.mist.emitting
			and not pooled.rings[0].visible and not pooled.rings[1].visible,
			"Explicit clear must stop every pooled visual")
	_effects.enabled = false
	_hazard.water_entered.emit(point, 8.0)
	_effects._process(0.016)
	_check(not _effects.visible and _effects._pending.is_empty(),
		"Disabled effects must ignore events, not replay them on re-enable")
	_effects.enabled = true
	_effects.intensity = 0.0
	_hazard.water_entered.emit(point, 8.0)
	_effects._process(0.016)
	_check(not _effects.visible and _effects._pending.is_empty(),
		"Zero intensity must suppress all splashes")
	_effects.intensity = 0.85
	_hazard.water_entered.emit(point, 8.0)
	_effects._process(0.016)
	_debug.set_enabled(true)
	_effects._process(0.016)
	_hazard.water_entered.emit(point, 8.0)
	_check(not _effects.visible and _effects._pending.is_empty(),
		"Physics debug must hide existing splashes and discard new events")
	_debug.set_enabled(false)
	_effects._process(0.016)
	_check(_effects.visible and _effects._pending.is_empty(),
		"Leaving debug must resume without replaying suppressed splashes")
	_check(_observed.linear_velocity == Vector3.ZERO and _observed.angular_velocity == Vector3.ZERO,
		"Synthetic water effects must not change either body velocity")
	_probes_complete = true


func _physics_process(delta: float) -> bool:
	if is_instance_valid(_hazard) and _ticks % 120 == 0:
		_hazard.water_entered.emit(Vector3(float(_ticks) * 0.01, -4.0, 0.0), 12.0)
	return super._physics_process(delta)


func _finish() -> void:
	_check(_probes_complete, "Every splash probe must complete")
	if not _failed:
		print("PASS water effects: event queue, bounded pool, world-space reset persistence, "
			+ "foam expiry, toggles/debug suppression; 720 ticks max difference %.8f" % _max_error)
	super._finish()
