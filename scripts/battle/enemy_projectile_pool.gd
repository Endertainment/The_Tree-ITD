class_name EnemyProjectilePool
extends Node2D
## Fixed pool of enemy shots. Built once per battle scene, no allocations
## during a wave.

const MAX_SHOTS := 48

var _free: Array[EnemyProjectile] = []
var _active: Array[EnemyProjectile] = []
var _battle: Battle


## Builds the pool and hands the battle reference to every shot.
func setup(battle: Battle) -> void:
	_battle = battle
	for _index in MAX_SHOTS:
		var shot := EnemyProjectile.new()
		add_child(shot)
		shot.configure(self, battle)
		shot.sleep()
		_free.append(shot)


## Fires one projectile from `from`. Returns null when the pool is exhausted.
func spawn(from: Vector2, kind: String, damage: float) -> EnemyProjectile:
	if _free.is_empty():
		return null
	var shot: EnemyProjectile = _free.pop_back()
	shot.configure(self, _battle)
	shot.launch(from, kind, damage)
	_active.append(shot)
	return shot


## Returns a spent projectile to the free list.
func release(shot: EnemyProjectile) -> void:
	var index := _active.find(shot)
	if index >= 0:
		_active.remove_at(index)
	shot.sleep()
	if not _free.has(shot):
		_free.append(shot)


## Returns every shot to the pool at the end of a run.
func clear_all() -> void:
	for shot: EnemyProjectile in _active.duplicate():
		release(shot)


## Shots currently in flight.
func count_active() -> int:
	return _active.size()
