class_name EnemyProjectile
extends Node2D
## One enemy shot flying at the Life Tree.
##
## Ranged orcs (spear thrower, mage, wyvern rider, trebuchet) stop at their
## attack range and fire these; the projectile travels to the Tree surface and
## applies its damage there. Pooled by `EnemyProjectilePool`, never freed.

const HIT_PADDING := 6.0

var _pool: EnemyProjectilePool
var _battle: Battle
var _kind := "spear"
var _damage := 10.0
var _speed := 520.0
var _active := false


## Injects the owning pool and the battle that owns the Tree.
func configure(pool: EnemyProjectilePool, battle: Battle) -> void:
	_pool = pool
	_battle = battle


## Starts a flight from `from` toward the Tree centre.
func launch(from: Vector2, kind: String, damage: float) -> void:
	global_position = from
	_kind = kind
	_damage = damage
	_speed = speed_for(kind)
	_active = true
	visible = true
	var to_center := Battle.CENTER - from
	if to_center.length_squared() > 0.0001:
		rotation = to_center.angle()
	set_physics_process(true)
	queue_redraw()


## Stops and hides the projectile. Called by the pool.
func sleep() -> void:
	_active = false
	visible = false
	set_physics_process(false)


## Travel speed for each projectile id.
static func speed_for(kind: String) -> float:
	match kind:
		"curse_orb":
			return 380.0
		"stone":
			return 420.0
		_:
			return 520.0


## Damage this projectile carries, for tests.
func get_damage() -> float:
	return _damage


func _physics_process(delta: float) -> void:
	if not _active:
		return
	var to_center := Battle.CENTER - global_position
	var distance := to_center.length()
	var step := _speed * delta
	if distance <= step + Battle.CORE_RADIUS + HIT_PADDING:
		_impact()
		return
	global_position += to_center.normalized() * step
	rotation = to_center.angle()


func _impact() -> void:
	if _battle != null and _battle.core != null and not _battle.core.is_dead():
		_battle.core.take_damage(_damage)
	if _pool != null:
		_pool.release(self)


func _draw() -> void:
	match _kind:
		"curse_orb":
			draw_circle(Vector2.ZERO, 9.0, Color(0.42, 0.18, 0.55, 0.55))
			draw_circle(Vector2.ZERO, 6.0, Color("#8a4de0"))
			draw_circle(Vector2(-1.0, -1.0), 2.5, Color("#e0c8ff"))
		"stone":
			draw_circle(Vector2.ZERO, 11.0, Color("#5d4c38"))
			draw_circle(Vector2(-3.0, -3.0), 3.5, Color("#8a7660"))
		_:
			draw_line(Vector2(-16.0, 0.0), Vector2(8.0, 0.0), Color("#d8c9a0"), 3.0)
			draw_colored_polygon(
				PackedVector2Array([Vector2(16.0, 0.0), Vector2(6.0, -5.0), Vector2(6.0, 5.0)]),
				Color("#cfd6dd")
			)
