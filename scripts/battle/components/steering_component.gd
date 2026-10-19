class_name SteeringComponent
extends Node
## Allocation-free seek + separation + tangential obstacle avoidance.
##
## The owner sets `max_speed`, `separation_weight` and `target_position` before
## each call. Neighbours come from `EnemyPool`'s spatial hash; obstacles stay
## empty until towers arrive in stage 3.

const SEPARATION_RADIUS := 44.0
const AVOIDANCE_MARGIN := 18.0

var target_position := Vector2.ZERO
var max_speed := 55.0
var separation_weight := 0.6

## How far ahead the avoidance probe looks, in design pixels.
var lookahead := 70.0


## Returns the next velocity for one physics frame.
func compute_velocity(
	pos: Vector2,
	velocity: Vector2,
	neighbors: Array,
	obstacles: Array,
	delta: float
) -> Vector2:
	var desired := Vector2.ZERO
	var to_target := target_position - pos
	if to_target.length_squared() > 0.0001:
		desired = to_target.normalized() * max_speed
	desired += _separation_force(pos, neighbors)
	desired += _avoidance_force(pos, velocity, obstacles)

	var desired_length_sq := desired.length_squared()
	if desired_length_sq > max_speed * max_speed:
		desired = desired * (max_speed / sqrt(desired_length_sq))

	var blended := velocity.lerp(desired, clampf(delta * 6.0, 0.0, 1.0))
	var blended_length_sq := blended.length_squared()
	if blended_length_sq > max_speed * max_speed:
		blended = blended * (max_speed / sqrt(blended_length_sq))
	return blended


func _separation_force(pos: Vector2, neighbors: Array) -> Vector2:
	var push := Vector2.ZERO
	for neighbor in neighbors:
		var other := neighbor as Node2D
		if other == null:
			continue
		var offset := pos - other.global_position
		var distance_sq := offset.length_squared()
		if distance_sq <= 0.0001 or distance_sq >= SEPARATION_RADIUS * SEPARATION_RADIUS:
			continue
		var distance := sqrt(distance_sq)
		push += offset * ((1.0 - distance / SEPARATION_RADIUS) / distance)
	if push.length_squared() <= 0.0001:
		return Vector2.ZERO
	return push.normalized() * (max_speed * separation_weight)


func _avoidance_force(pos: Vector2, velocity: Vector2, obstacles: Array) -> Vector2:
	if obstacles.is_empty():
		return Vector2.ZERO
	var direction := velocity.normalized()
	if direction.length_squared() <= 0.0001:
		direction = (target_position - pos).normalized()
	if direction.length_squared() <= 0.0001:
		return Vector2.ZERO

	var probe := pos + direction * lookahead
	var force := Vector2.ZERO
	for item in obstacles:
		if not (item is Dictionary):
			continue
		var obstacle: Dictionary = item
		var center: Vector2 = obstacle.get("position", Vector2.ZERO)
		var radius := float(obstacle.get("radius", 0.0)) + AVOIDANCE_MARGIN
		if probe.distance_squared_to(center) >= radius * radius:
			continue

		var away := probe - center
		if away.length_squared() <= 0.0001:
			away = Vector2.LEFT
		# Tangential steering: pick the tangent that stays closest to the
		# current heading, which prevents left/right oscillation in a crowd.
		var tangent := Vector2(-away.y, away.x).normalized()
		if tangent.dot(velocity) < 0.0:
			tangent = -tangent
		force += tangent * max_speed
	return force
