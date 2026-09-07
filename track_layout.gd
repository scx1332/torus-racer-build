class_name TrackLayout
extends RefCounted
## Shared, deterministic centerline for road geometry, scenery and validation.

const RADIUS := 100.0
const STRAIGHT := 200.0
const WIDTH := 24.0
const HEIGHT := 8.0
const SHOULDER := 1.5
const BANK_DEGREES := 12.0
const SPAWN_DISTANCE := 35.0
const JUMP_START := 110.0
const JUMP_LIP := 136.0
const JUMP_END := 164.0
const JUMP_HEIGHT := 3.0


static func length() -> float:
	return 2.0 * STRAIGHT + TAU * RADIUS


static func sample_at(distance: float) -> Dictionary:
	var s := fposmod(distance, length())
	var position := Vector3.ZERO
	var tangent := Vector3.BACK
	var corner := -1.0
	if s < STRAIGHT:
		position = Vector3(RADIUS, HEIGHT, s - STRAIGHT * 0.5)
	elif s < STRAIGHT + PI * RADIUS:
		corner = (s - STRAIGHT) / (PI * RADIUS)
		var angle := corner * PI
		position = Vector3(cos(angle) * RADIUS, HEIGHT, STRAIGHT * 0.5 + sin(angle) * RADIUS)
		tangent = Vector3(-sin(angle), 0.0, cos(angle))
	elif s < 2.0 * STRAIGHT + PI * RADIUS:
		position = Vector3(-RADIUS, HEIGHT, STRAIGHT * 0.5 - (s - STRAIGHT - PI * RADIUS))
		tangent = Vector3.FORWARD
	else:
		corner = (s - 2.0 * STRAIGHT - PI * RADIUS) / (PI * RADIUS)
		var angle := PI + corner * PI
		position = Vector3(cos(angle) * RADIUS, HEIGHT, -STRAIGHT * 0.5 + sin(angle) * RADIUS)
		tangent = Vector3(-sin(angle), 0.0, cos(angle))
	var jump := _jump_profile(s)
	position.y += jump.x
	tangent = Vector3(tangent.x, jump.y, tangent.z).normalized()
	var bank := 0.0
	if corner >= 0.0:
		# Ease into the cross-slope, keeping road height/frame continuous at the straights.
		bank = deg_to_rad(BANK_DEGREES) * smoothstep(0.0, 0.2, corner) \
			* (1.0 - smoothstep(0.8, 1.0, corner))
	var right := tangent.cross(Vector3.UP).normalized().rotated(tangent, bank)
	return {"position": position, "tangent": tangent, "right": right,
		"up": right.cross(tangent).normalized(), "bank": bank, "width": WIDTH}


static func spawn_transform() -> Transform3D:
	var frame := sample_at(SPAWN_DISTANCE)
	# Local +X is the torus axle; positive spin rolls along the centerline tangent.
	return Transform3D(Basis(-frame.right, frame.up, frame.tangent),
		frame.position + frame.up * 1.28)


static func _jump_profile(distance: float) -> Vector2:
	if distance < JUMP_START or distance >= JUMP_END:
		return Vector2.ZERO
	if distance < JUMP_LIP:
		var run := JUMP_LIP - JUMP_START
		var t := (distance - JUMP_START) / run
		return Vector2(JUMP_HEIGHT * t * t, 2.0 * JUMP_HEIGHT * t / run)
	var run := JUMP_END - JUMP_LIP
	var t := (distance - JUMP_LIP) / run
	# A convex launch lip with a continuous downhill landing: no mandatory chasm.
	return Vector2(JUMP_HEIGHT * (1.0 - t) * (1.0 - t),
		-2.0 * JUMP_HEIGHT * (1.0 - t) / run)
