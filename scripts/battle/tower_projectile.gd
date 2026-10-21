class_name TowerProjectile
extends Area2D
## Pooled tower shot. Uses a swept raycast between frames, so a slow Ballista
## bolt and a fast frost bolt both hit exactly once even at 2x speed.
##
## Kind decides the visuals, the turn rate and the on-hit effect:
## arrow (homing, single target), frost bolt (small homing, splash slow),
## ballista bolt (barely homing, ignores armor, camera shake).

enum Kind { ARROW, FROST_BOLT, BALLISTA_BOLT, SPIRIT_BOLT }

const ENEMY_LAYER := 1
const MAX_LIFETIME := 4.0

var kind := Kind.ARROW

var _pool: TowerProjectilePool
var _enemy_pool: EnemyPool
var _target: Enemy
var _target_serial := 0
var _damage := 0.0
var _speed := 700.0
var _splash_radius := 0.0
var _slow_strength := 0.0
var _slow_duration := 0.0
var _stun_duration := 0.0
var _ignore_armor := false
var _tint := Color.WHITE
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


## Injects the owning pool and the enemy pool used for splash. Called once.
func configure(pool: TowerProjectilePool, enemies: EnemyPool) -> void:
	_pool = pool
	_enemy_pool = enemies


## Starts a flight using the stats of the firing tower level.
func begin(
	from: Vector2, target: Enemy, new_kind: int, stats: TowerLevel, tint: Color,
	stun_bonus := 0.0
) -> void:
	kind = new_kind
	_damage = stats.damage
	_speed = maxf(120.0, stats.projectile_speed)
	_splash_radius = stats.splash_radius
	_slow_strength = stats.slow_strength
	_slow_duration = stats.slow_duration
	_stun_duration = stats.stun_duration + maxf(0.0, stun_bonus)
	_ignore_armor = stats.ignores_armor
	_tint = tint
	_target = target
	_target_serial = target.get_spawn_serial() if target != null else 0
	_life = 0.0
	_active = true
	visible = true

	global_position = from
	var direction := Vector2.RIGHT
	if target != null:
		var to_target := target.global_position - from
		if to_target.length_squared() > 0.0001:
			direction = to_target.normalized()
	rotation = direction.angle()
	set_physics_process(true)
	queue_redraw()


## Stops the projectile and hides it. Called by the pool.
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
			var max_turn := _turn_rate() * delta
			var wanted := to_target.angle()
			rotation += clampf(wrapf(wanted - rotation, -PI, PI), -max_turn, max_turn)
			direction = Vector2.RIGHT.rotated(rotation)

	var next_position := global_position + direction * _speed * delta
	_query.from = global_position
	_query.to = next_position
	var hit := get_world_2d().direct_space_state.intersect_ray(_query)
	if not hit.is_empty():
		_impact(hit.get("collider") as Enemy, hit.get("position", next_position))
		return

	global_position = next_position


func _turn_rate() -> float:
	match kind:
		Kind.BALLISTA_BOLT:
			return 1.0
		Kind.FROST_BOLT:
			return 3.0
		Kind.SPIRIT_BOLT:
			return 6.0
		_:
			return 9.0


func _impact(enemy: Enemy, impact_position: Vector2) -> void:
	if kind == Kind.FROST_BOLT:
		AudioManager.play_sfx_throttled("frost_burst", 0.05)
	else:
		AudioManager.play_sfx_throttled("hit", 0.04)

	if enemy != null:
		enemy.take_damage(_damage, _ignore_armor)
		if _stun_duration > 0.0:
			enemy.apply_stun(_stun_duration)

	if _splash_radius > 0.0 and _slow_strength > 0.0:
		_apply_splash_slow(impact_position)

	if _pool != null:
		_pool.on_impact(impact_position, kind, _splash_radius)
	_finish()


func _apply_splash_slow(impact_position: Vector2) -> void:
	if _enemy_pool == null:
		return
	var radius_sq := _splash_radius * _splash_radius
	for other: Enemy in _enemy_pool.get_active():
		if not other.is_targetable():
			continue
		if impact_position.distance_squared_to(other.global_position) > radius_sq:
			continue
		other.apply_slow(_slow_strength, _slow_duration)


func _finish() -> void:
	if not _active:
		return
	_active = false
	visible = false
	set_physics_process(false)
	if _pool != null:
		_pool.release(self)


## File-name form of the current kind, used for the optional projectile art.
func _kind_name() -> String:
	match kind:
		Kind.FROST_BOLT:
			return "frost_bolt"
		Kind.BALLISTA_BOLT:
			return "ballista_bolt"
		Kind.SPIRIT_BOLT:
			return "spirit_bolt"
		_:
			return "arrow"


func _draw() -> void:
	var texture := ArtLibrary.projectile(_kind_name())
	if texture != null:
		ArtLibrary.draw_centered(self, texture, Vector2.ZERO, Vector2(48.0, 48.0), _tint)
		return

	match kind:
		Kind.FROST_BOLT:
			draw_line(Vector2(-26.0, 0.0), Vector2(-6.0, 0.0), Color(_tint.r, _tint.g, _tint.b, 0.45), 6.0)
			draw_circle(Vector2.ZERO, 9.0, _tint)
			draw_circle(Vector2.ZERO, 4.0, Color(1.0, 1.0, 1.0, 0.92))
		Kind.SPIRIT_BOLT:
			draw_circle(Vector2.ZERO, 10.0, Color(_tint.r, _tint.g, _tint.b, 0.35))
			draw_circle(Vector2.ZERO, 6.0, _tint)
			draw_circle(Vector2.ZERO, 2.5, Color(1.0, 1.0, 1.0, 0.9))
		Kind.BALLISTA_BOLT:
			draw_line(Vector2(-30.0, 0.0), Vector2(10.0, 0.0), Color("#3a2a1c"), 9.0)
			draw_line(Vector2(-30.0, 0.0), Vector2(-18.0, 0.0), Color("#7a4a2b"), 9.0)
			draw_colored_polygon(
				PackedVector2Array([
					Vector2(22.0, 0.0), Vector2(8.0, -8.0), Vector2(8.0, 8.0),
				]),
				Color("#b8c0c8")
			)
		_:
			draw_line(Vector2(-16.0, 0.0), Vector2(8.0, 0.0), Color("#e8d9a8"), 3.0)
			draw_colored_polygon(
				PackedVector2Array([
					Vector2(12.0, 0.0), Vector2(2.0, -6.0), Vector2(2.0, 6.0),
				]),
				_tint
			)
			draw_line(Vector2(-16.0, 0.0), Vector2(-22.0, -6.0), Color("#d8e6b0"), 2.0)
			draw_line(Vector2(-16.0, 0.0), Vector2(-22.0, 6.0), Color("#d8e6b0"), 2.0)
