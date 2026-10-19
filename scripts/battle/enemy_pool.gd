class_name EnemyPool
extends Node2D
## Fixed-size enemy pool with a per-frame spatial hash.
##
## All 70 nodes are instantiated at scene load, so spawning during a wave never
## allocates. The hash is rebuilt in this node's `_physics_process`, which runs
## before the pooled enemies (children) move.

const MAX_ALIVE := 70
const NEIGHBOR_RADIUS := 44.0
const ENEMY_SCENE := preload("res://scenes/battle/Enemy.tscn")

var battle: Battle

var _free: Array[Enemy] = []
var _active: Array[Enemy] = []
var _hash := SpatialHash.new()


func _ready() -> void:
	for _index in MAX_ALIVE:
		var enemy: Enemy = ENEMY_SCENE.instantiate()
		add_child(enemy)
		enemy.configure(self, battle)
		enemy.despawn()
		_free.append(enemy)


## Injects the Battle reference into the pool and every pooled enemy.
func setup(battle_ref: Battle) -> void:
	battle = battle_ref
	for enemy: Enemy in _free:
		enemy.configure(self, battle)


## Activates a pooled enemy at `position`. Returns null when the pool is full.
func spawn(enemy_data: EnemyData, position: Vector2, modifiers: Dictionary) -> Enemy:
	if enemy_data == null or _free.is_empty() or _active.size() >= MAX_ALIVE:
		return null
	var enemy: Enemy = _free.pop_back()
	enemy.configure(self, battle)
	enemy.global_position = position
	enemy.rotation = 0.0
	enemy.setup(enemy_data, modifiers)
	enemy.activate()
	_active.append(enemy)
	return enemy


## Returns an enemy to the free list. Called by the enemy after its death effect.
func release(enemy: Enemy) -> void:
	var index := _active.find(enemy)
	if index >= 0:
		_active.remove_at(index)
	enemy.despawn()
	if not _free.has(enemy):
		_free.append(enemy)


## Fills `out` with broad-phase neighbours around `position`.
func query_neighbors(position: Vector2, out: Array) -> void:
	_hash.query(position, NEIGHBOR_RADIUS, out)


## Returns the closest targetable enemy within `max_distance`, or null.
func find_nearest(position: Vector2, max_distance: float) -> Enemy:
	var best: Enemy = null
	var best_distance_sq := max_distance * max_distance
	for enemy: Enemy in _active:
		if not enemy.is_targetable():
			continue
		var distance_sq := position.distance_squared_to(enemy.global_position)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best = enemy
	return best


## Active nodes, including enemies still playing their death effect.
func count_present() -> int:
	return _active.size()


## Enemies that can currently be targeted or damage the Tree.
func count_alive() -> int:
	var alive := 0
	for enemy: Enemy in _active:
		if enemy.is_targetable():
			alive += 1
	return alive


## The live array, for targeting and tests. Do not mutate it.
func get_active() -> Array[Enemy]:
	return _active


## Number of enemies available for reuse.
func get_free_count() -> int:
	return _free.size()


## Occupied spatial-hash cells, for the debug overlay.
func get_spatial_cell_count() -> int:
	return _hash.cell_count()


## Returns every active enemy to the pool. Used when a run ends.
func despawn_all() -> void:
	var snapshot := _active.duplicate()
	for enemy: Enemy in snapshot:
		release(enemy)


func _physics_process(_delta: float) -> void:
	_hash.clear()
	for enemy: Enemy in _active:
		if enemy.is_targetable():
			_hash.insert(enemy, enemy.global_position)
