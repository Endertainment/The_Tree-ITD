class_name Archer
extends Node2D
## Elf archer anchored in the Tree canopy. Acquires the nearest target in range
## at 10 Hz, plays a 0.15 s bow draw, then asks the projectile pool for an arrow.

const DRAW_SECONDS := 0.15
const TARGET_CACHE_SECONDS := 0.15
const IDLE_SWAY_SPEED := 1.4

var damage := 12.0
var attack_interval := 0.8
var attack_range := 520.0
var projectile_speed := 900.0

var _enemy_pool: EnemyPool
var _projectiles: ProjectilePool
var _target: Enemy
var _retarget_timer := 0.0
var _cooldown := 0.0
var _draw_timer := 0.0
var _sway := 0.0


## Injects the pools and the archer's stats for this run.
func setup(
	enemy_pool: EnemyPool,
	projectiles: ProjectilePool,
	archer_damage: float,
	interval: float,
	range_px: float,
	speed: float
) -> void:
	_enemy_pool = enemy_pool
	_projectiles = projectiles
	damage = archer_damage
	attack_interval = interval
	attack_range = range_px
	projectile_speed = speed
	_cooldown = 0.0
	_draw_timer = 0.0
	_retarget_timer = 0.0
	_target = null
	queue_redraw()


## Refreshes damage, rate, range and projectile speed from the run's live stats.
func apply_stats(stats: RunStats) -> void:
	damage = stats.archer_damage
	attack_interval = stats.archer_interval
	attack_range = stats.archer_range
	projectile_speed = stats.projectile_speed
	_cooldown = minf(_cooldown, attack_interval)


func _physics_process(delta: float) -> void:
	_sway += delta

	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = TARGET_CACHE_SECONDS
		_target = _find_target()

	if _target != null and (not is_instance_valid(_target) or not _target.is_targetable()):
		_target = null
	if _target != null:
		var to_target := _target.global_position - global_position
		if to_target.length_squared() > attack_range * attack_range:
			_target = null

	_aim(delta)

	if _draw_timer > 0.0:
		_draw_timer -= delta
		queue_redraw()
		if _draw_timer <= 0.0:
			_fire()
			_cooldown = attack_interval

	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)

	if _target != null and _cooldown <= 0.0 and _draw_timer <= 0.0:
		_draw_timer = DRAW_SECONDS
		queue_redraw()


func _aim(delta: float) -> void:
	if _target != null:
		var to_target := _target.global_position - global_position
		if to_target.length_squared() > 0.0001:
			rotation = lerp_angle(rotation, to_target.angle(), clampf(delta * 14.0, 0.0, 1.0))
		return
	rotation = sin(_sway * IDLE_SWAY_SPEED) * 0.06


func _find_target() -> Enemy:
	if _enemy_pool == null:
		return null
	return _enemy_pool.find_nearest(global_position, attack_range)


func _fire() -> void:
	if _target == null or _projectiles == null:
		return
	if not is_instance_valid(_target) or not _target.is_targetable():
		return
	var muzzle := global_position + Vector2(20.0, 0.0).rotated(rotation)
	_projectiles.spawn(muzzle, _target, damage, projectile_speed, false)


func _draw() -> void:
	var skin := Color("#d8e6b0")
	var leather := Color("#7a4a2b")
	var gold := Color("#f2c14e")

	# Torso and head, facing +x.
	draw_circle(Vector2(-2.0, 0.0), 10.0, leather)
	draw_circle(Vector2(4.0, -2.0), 8.0, skin)
	draw_circle(Vector2(11.0, -2.0), 6.0, skin)
	draw_line(Vector2(-2.0, 7.0), Vector2(-7.0, 15.0), leather, 4.0)
	draw_line(Vector2(-2.0, 7.0), Vector2(2.0, 15.0), leather, 4.0)

	# Bow.
	draw_arc(Vector2(16.0, 0.0), 16.0, -PI * 0.5, PI * 0.5, 14, gold, 3.0, true)
	var pull := clampf(_draw_timer / DRAW_SECONDS, 0.0, 1.0)
	var nock := Vector2(16.0 - 10.0 * pull, 0.0)
	draw_line(Vector2(16.0, -16.0), nock, Color("#e8d9a8"), 1.5)
	draw_line(Vector2(16.0, 16.0), nock, Color("#e8d9a8"), 1.5)
	if pull > 0.0:
		draw_line(nock, Vector2(28.0, 0.0), Color("#e8d9a8"), 2.0)
		draw_colored_polygon(
			PackedVector2Array([Vector2(28.0, 0.0), Vector2(21.0, -4.0), Vector2(21.0, 4.0)]),
			gold
		)
