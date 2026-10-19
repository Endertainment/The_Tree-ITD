class_name SteeringComponent
extends Node
## Allocation-free seek + separation + obstacle avoidance.
##
## The owner sets `max_speed`, `separation_weight` and `target_position` before
## each call. Neighbours come from `EnemyPool`'s spatial hash; obstacles are the
## `{position, radius}` dictionaries owned by `TowerManager`.
##
## Avoidance has two parts: a tangential probe that steers an enemy around a
## tower before it arrives, and a hard push-out that keeps the body from ever
## overlapping the tower circle. Without the second part an enemy that spawns
## inside the circle (or is pushed in by the crowd) would visibly clip.

const SEPARATION_RADIUS := 44.0

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
		direction = Vector2.UP

	var probe := pos + direction * lookahead
	var force := Vector2.ZERO
	for item in obstacles:
		if not (item is Dictionary):
			continue
		var obstacle: Dictionary = item
		var center: Vector2 = obstacle.get("position", Vector2.ZERO)
		var radius := float(obstacle.get("radius", 0.0))
		if radius <= 0.0:
			continue

		# Hard clearance: never let the body sit inside the tower radius.
		var offset := pos - center
		var distance_sq := offset.length_squared()
		if distance_sq < radius * radius:
			if distance_sq <= 0.0001:
				offset = Vector2.LEFT
			force += offset.normalized() * max_speed

		# Lookahead steering: turn onto the tangent before touching the tower.
		var probe_offset := probe - center
		if probe_offset.length_squared() >= radius * radius:
			continue
		if probe_offset.length_squared() <= 0.0001:
			probe_offset = Vector2.LEFT
		var tangent := Vector2(-probe_offset.y, probe_offset.x).normalized()
		if tangent.dot(velocity) < 0.0:
			tangent = -tangent
		force += tangent * max_speed
	return force
