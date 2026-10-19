class_name ProjectilePool
extends Node2D
## Fixed-size arrow pool plus one shared hit spark.

const POOL_SIZE := 48
const ARROW_SCENE := preload("res://scenes/battle/Arrow.tscn")

var _free: Array[Arrow] = []
var _active: Array[Arrow] = []

@onready var _spark: CPUParticles2D = %HitSpark


func _ready() -> void:
	for _index in POOL_SIZE:
		var arrow: Arrow = ARROW_SCENE.instantiate()
		add_child(arrow)
		arrow._pool = self
		arrow.sleep()
		_free.append(arrow)


## Fires one arrow. Returns null when every pooled arrow is in flight.
func spawn(from: Vector2, target: Enemy, damage: float, speed: float, ignore_armor := false) -> Arrow:
	if _free.is_empty():
		return null
	var arrow: Arrow = _free.pop_back()
	arrow.begin(from, target, damage, speed, ignore_armor)
	_active.append(arrow)
	return arrow


## Returns an arrow to the free list.
func release(arrow: Arrow) -> void:
	var index := _active.find(arrow)
	if index >= 0:
		_active.remove_at(index)
	arrow.sleep()
	if not _free.has(arrow):
		_free.append(arrow)


## Plays the shared hit spark at a world position.
func on_hit(position: Vector2) -> void:
	_spark.global_position = position
	_spark.restart()
	_spark.emitting = true


## Arrows currently in flight.
func count_active() -> int:
	return _active.size()


## Returns every arrow to the free list, used when a run ends.
func clear_all() -> void:
	var snapshot := _active.duplicate()
	for arrow: Arrow in snapshot:
		release(arrow)
