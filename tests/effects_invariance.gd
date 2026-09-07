extends "res://tests/debug_invariance.gd"
## Reuse the paired independent worlds and all 720-tick trajectory assertions.

var _effects: TorusEffects
var _probes_complete: bool = false


func _setup() -> void:
	super._setup()
	_debug.set_enabled(false)
	_effects = TorusEffects.new()
	_effects.target = _observed
	_effects.debug_view = _debug
	_observed_world.add_child(_effects)
	_probe_effects()


func _effect_sample(point: Vector3, grounded: bool = true) -> Dictionary:
	return {"origin": point + Vector3.UP, "linear_velocity": Vector3.BACK * 8.0,
		"angular_velocity": Vector3.RIGHT * 12.0, "spin_axis": Vector3.RIGHT,
		"input_torque": Vector3.ZERO, "assist_torque": Vector3.ZERO,
		"gyroscopic_torque": Vector3.ZERO, "grounded": grounded, "speed": 8.0,
		"spin_rate": 12.0, "slip_ratio": 0.8,
		"contacts": [{"position": point, "normal": Vector3.UP,
			"traction": Vector3.BACK}] if grounded else []}


func _probe_effects() -> void:
	var idle := _effect_sample(Vector3.ZERO)
	idle.speed = 0.0
	idle.spin_rate = 0.0
	idle.slip_ratio = 0.0
	_observed.physics_sampled.emit(idle)
	_effects._process(0.016)
	_check(not _effects._dust.emitting, "Rest must not emit dust")
	var rolling := _effect_sample(Vector3.ZERO)
	rolling.slip_ratio = 0.0
	_observed.physics_sampled.emit(rolling)
	_effects._process(0.016)
	_check(not _effects._dust.emitting, "Pure rolling must not emit dust")
	var slipping := _effect_sample(Vector3.ZERO)
	var original_sample := slipping.duplicate(true)
	_observed.physics_sampled.emit(slipping)
	_effects._process(0.016)
	_check(_effects._dust.emitting, "Moving contact slip must emit dust")
	_check(not _effects._dust.local_coords, "Dust must remain in world coordinates")
	_check(_effects._dust.amount == 48, "Continuous particles must be bounded")
	_observed.physics_sampled.emit(_effect_sample(Vector3.BACK * 0.3))
	_effects._process(0.016)
	_check(_effects._marks.size() == 1, "Slip travel must create a contact skid")
	_check(_effects._skid_mesh.get_surface_count() == 1, "Skid must build a visible mesh")
	_effects._process(_effects.skid_lifetime + 0.1)
	_check(_effects._marks.is_empty(), "Skids must expire")
	for index in range(180):
		_observed.physics_sampled.emit(_effect_sample(Vector3.BACK * (0.6 + index * 0.3)))
		_effects._process(0.001)
	_check(_effects._marks.size() == TorusEffects.MAX_SKIDS, "Skid pool must be bounded")
	var airborne := _effect_sample(Vector3.ZERO, false)
	airborne.linear_velocity = Vector3.DOWN * 4.0
	for index in range(12):
		_observed.physics_sampled.emit(airborne)
	_effects._process(0.016)
	_check(not _effects._dust.emitting, "Airborne spin must not emit contact dust")
	_observed.physics_sampled.emit(_effect_sample(Vector3.ZERO))
	_effects._process(0.016)
	_check(_effects._puffs[0].emitting, "A descending landing must emit a one-shot puff")
	_check(_effects._puffs[0].one_shot, "Landing must use a bounded burst")
	_debug.set_enabled(true)
	_effects._process(0.016)
	_check(not _effects.visible and not _effects._dust.emitting,
		"Physics debug must suppress effects")
	_check(_effects._marks.is_empty(), "Debug must clear distracting marks")
	_debug.set_enabled(false)
	_observed.physics_sampled.emit(slipping)
	_effects._process(0.016)
	_check(_effects.visible and _effects._dust.emitting, "Effects must resume after debug")
	_observed.reset_completed.emit()
	_check(_effects._marks.is_empty() and not _effects._has_last_contact,
		"Reset must break skid continuity")
	_check(not _effects._dust.emitting and not _effects._puffs[0].emitting,
		"Reset must stop both particle sources")
	_check(slipping == original_sample, "Effects must not mutate their source snapshot")
	_observed.physics_sampled.emit(_effect_sample(Vector3(500, 0, 500)))
	_effects._process(0.016)
	_check(_effects._marks.is_empty(), "Reset must never draw a line across checkpoints")
	_effects.enabled = false
	_effects._process(0.016)
	_check(not _effects.visible and not _effects._dust.emitting,
		"The inspector toggle must disable effects")
	_effects.enabled = true
	_effects._clear_effects()
	_check(_observed.linear_velocity == Vector3.ZERO and _observed.angular_velocity == Vector3.ZERO,
		"Synthetic effects samples must not alter body velocities")
	_probes_complete = true


func _finish() -> void:
	_check(_probes_complete, "All presentation probes must complete before passing")
	if not _failed:
		print("PASS effects: slip dust, landing, fading/skid bounds, reset, debug suppression; "
			+ "720 physics ticks with max trajectory difference %.8f" % _max_error)
	super._finish()
