class_name TowerProjectilePool
extends Node2D
## Fixed pool for tower shots plus three reusable impact rings.
##
## Arrows keep their own 48-node pool; this one adds 72 tower shots, so the
## combined projectile budget stays at the master's 120.

const POOL_SIZE := 72
const RING_COUNT := 3
const PROJECTILE_SCENE := preload("res://scenes/battle/TowerProjectile.tscn")

## Set by `Battle.setup()`; the Ballista impact asks the Tree for a small shake.
var battle: Battle

var _enemy_pool: EnemyPool
var _free: Array[TowerProjectile] = []
var _active: Array[TowerProjectile] = []
var _rings: Array[ImpactRing] = []


## Expanding ring used for every impact; no per-hit allocation.
class ImpactRing extends Node2D:
	const DURATION := 0.3

	var _time := 0.0
	var _radius := 30.0
	var _width := 4.0
	var _color := Color.WHITE
	var _active := false

	func play(at: Vector2, color: Color, radius: float, width: float) -> void:
		global_position = at
		_color = color
		_radius = maxf(12.0, radius)
		_width = width
		_time = DURATION
		_active = true
		visible = true
		queue_redraw()

	func _process(delta: float) -> void:
		if not _active:
			return
		_time -= delta
		if _time <= 0.0:
			_time = 0.0
			_active = false
			visible = false
			return
		queue_redraw()

	func _draw() -> void:
		var progress := 1.0 - _time / DURATION
		var radius := lerpf(_radius * 0.35, _radius, progress)
		var alpha := (1.0 - progress) * 0.85
		draw_arc(
			Vector2.ZERO, radius, 0.0, TAU, 30,
			Color(_color.r, _color.g, _color.b, alpha), _width, true
		)


func _ready() -> void:
	for _index in POOL_SIZE:
		var projectile: TowerProjectile = PROJECTILE_SCENE.instantiate()
		add_child(projectile)
		projectile.sleep()
		_free.append(projectile)
	for _index in RING_COUNT:
		var ring := ImpactRing.new()
		ring.visible = false
		add_child(ring)
		_rings.append(ring)


## Injects the enemy pool and the owning Battle. Called once from `Battle`.
func setup(enemies: EnemyPool, battle_ref: Battle) -> void:
	_enemy_pool = enemies
	battle = battle_ref
	for projectile: TowerProjectile in _free:
		projectile.configure(self, enemies)
	for projectile: TowerProjectile in _active:
		projectile.configure(self, enemies)


## Fires one pooled projectile. Returns null when every slot is in flight.
func spawn(
	from: Vector2, target: Enemy, kind: int, stats: TowerLevel, tint: Color
) -> TowerProjectile:
	if _free.is_empty() or stats == null:
		return null
	var projectile: TowerProjectile = _free.pop_back()
	projectile.configure(self, _enemy_pool)
	projectile.begin(from, target, kind, stats, tint)
	_active.append(projectile)
	return projectile


## Returns a projectile to the free list.
func release(projectile: TowerProjectile) -> void:
	var index := _active.find(projectile)
	if index >= 0:
		_active.remove_at(index)
	projectile.sleep()
	if not _free.has(projectile):
		_free.append(projectile)


## Plays the impact ring and shakes the camera for heavy bolts.
func on_impact(position: Vector2, kind: int, splash_radius: float) -> void:
	var ring := _next_ring()
	match kind:
		TowerProjectile.Kind.BALLISTA_BOLT:
			ring.play(position, Color(0.95, 0.85, 0.5), 30.0, 5.0)
			if battle != null:
				battle.request_shake(6.0)
		TowerProjectile.Kind.FROST_BOLT:
			ring.play(position, Color(0.44, 0.85, 0.91), splash_radius, 4.0)
		_:
			ring.play(position, Color(0.91, 0.85, 0.66), 18.0, 3.0)


## Projectiles currently in flight.
func count_active() -> int:
	return _active.size()


## Returns every projectile to the free list, used when a run ends.
func clear_all() -> void:
	var snapshot := _active.duplicate()
	for projectile: TowerProjectile in snapshot:
		release(projectile)


func _next_ring() -> ImpactRing:
	for ring: ImpactRing in _rings:
		if not ring.visible:
			return ring
	return _rings[0]
