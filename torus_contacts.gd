class_name TorusContacts
extends RefCounted
## Read only, called from the body's integration callback. Jolt returns WORLD
## coordinates even for getters named get_contact_local_*.

static func sample(state: PhysicsDirectBodyState3D, axle: Vector3,
		outer_radius: float, min_up_dot: float) -> Dictionary:
	var ground_contacts: Array[Dictionary] = []
	var slip_speed := 0.0
	var impact_impulse := 0.0
	for index in range(state.get_contact_count()):
		var normal := state.get_contact_local_normal(index).normalized()
		var impulse := state.get_contact_impulse(index)
		impact_impulse = maxf(impact_impulse, impulse.length())
		if normal.dot(Vector3.UP) < min_up_dot:
			continue
		var relative_velocity := state.get_contact_local_velocity_at_position(index) \
			- state.get_contact_collider_velocity_at_position(index)
		slip_speed = maxf(slip_speed, relative_velocity.slide(normal).length())
		# Estimated tangential contact impulse / dt is the traction force ON us.
		ground_contacts.append({
			"position": state.get_contact_local_position(index),
			"normal": normal,
			"traction": impulse.slide(normal) / state.step,
		})
	var rim_speed := absf(state.angular_velocity.dot(axle)) * outer_radius
	return {
		"contacts": ground_contacts,
		"grounded": not ground_contacts.is_empty(),
		# Regularize near rest; zero contact slip remains zero at zero spin.
		"slip_ratio": slip_speed / maxf(rim_speed, 0.1),
		"impact_impulse": impact_impulse,
	}
