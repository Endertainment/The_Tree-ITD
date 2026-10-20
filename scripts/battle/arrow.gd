class_name Arrow
extends Area2D
## Pooled homing arrow. Uses a swept raycast, not area overlap, so a 900 px/s
## projectile cannot tunnel through a 16 px hitbox at 2x speed.

const TURN_RATE := 8.0
const MAX_LIFETIME := 2.5
const ENEMY_LAYER := 1

var _pool: ProjectilePool
var _target: Enemy
var _target_serial := 0
var _damage := 0.0
var _speed := 900.0
var _ignore_armor := false
var _life := 0.0
var _active := false
var _query: PhysicsRayQueryParameters2D


func _ready() -> void:
	monitoring = false
	monitorable = false
	_query = PhysicsRayQueryParameters2D.create(Vector2.ZERO, Vector2.ZERO, ENEMY_LAYER)
	_query.collide_with_areas = true
	_query.collide_with_bodies = false
	sleep()


## Starts a flight. `target` may be null, in which case the arrow flies straight.
func begin(from: Vector2, target: Enemy, damage: float, speed: float, ignore_armor := false) -> void:
	global_position = from
	_target = target
	_target_serial = target.get_spawn_serial() if target != null else 0
	_damage = damage
	_speed = speed
	_ignore_armor = ignore_armor
	_life = 0.0
	_active = true
	visible = true
	var direction := Vector2.RIGHT
	if target != null:
		var to_target := target.global_position - from
		if to_target.length_squared() > 0.0001:
			direction = to_target.normalized()
	rotation = direction.angle()
	set_physics_process(true)


## Stops the arrow and hides it. Called by the pool.
func sleep() -> void:
	_active = false
	_target = null
	visible = false
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not _active:
		return

	_life += delta
	if _life >= MAX_LIFETIME:
		_finish()
		return

	if _target != null and (
		not is_instance_valid(_target)
		or not _target.is_targetable()
		or _target.get_spawn_serial() != _target_serial
	):
		_target = null

	var direction := Vector2.RIGHT.rotated(rotation)
	if _target != null:
		var to_target := _target.global_position - global_position
		if to_target.length_squared() > 0.0001:
			var wanted := to_target.angle()
			var max_turn := TURN_RATE * delta
			rotation += clampf(wrapf(wanted - rotation, -PI, PI), -max_turn, max_turn)
			direction = Vector2.RIGHT.rotated(rotation)

	var next_position := global_position + direction * _speed * delta
	_query.from = global_position
	_query.to = next_position
	var hit := get_world_2d().direct_space_state.intersect_ray(_query)
	if not hit.is_empty():
		var enemy := hit.get("collider") as Enemy
		if enemy != null:
			enemy.take_damage(_damage, _ignore_armor)
		AudioManager.play_sfx_throttled("hit", 0.04)
		if _pool != null:
			_pool.on_hit(hit.get("position", next_position))
		_finish()
		return

	global_position = next_position


func _finish() -> void:
	if not _active:
		return
	_active = false
	visible = false
	set_physics_process(false)
	if _pool != null:
		_pool.release(self)


func _draw() -> void:
	var texture := ArtLibrary.projectile("arrow")
	if texture != null:
		ArtLibrary.draw_centered(self, texture, Vector2.ZERO, Vector2(40.0, 40.0))
		return

	draw_line(Vector2(-12.0, 0.0), Vector2(10.0, 0.0), Color("#e8d9a8"), 2.0)
	draw_colored_polygon(
		PackedVector2Array([Vector2(10.0, 0.0), Vector2(2.0, -5.0), Vector2(2.0, 5.0)]),
		Color("#f2c14e")
	)
	draw_line(Vector2(-12.0, 0.0), Vector2(-17.0, -5.0), Color("#d8e6b0"), 2.0)
	draw_line(Vector2(-12.0, 0.0), Vector2(-17.0, 5.0), Color("#d8e6b0"), 2.0)
