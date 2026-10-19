class_name TowerManager
extends Node2D
## Owns the eight pads, the built towers and the steering obstacle list.
##
## Everything that lives in the world about towers is here: layout, build,
## upgrade, sell, selection and the `obstacles` array that `EnemyPool` hands to
## every enemy. Coins stay on `Battle`, so every purchase goes through
## `Battle.spend_coins()` and can never go negative.

const PAD_COUNT := 8
const RING_RADIUS := 300.0
const START_ANGLE_DEG := 22.5
const ANGLE_STEP_DEG := 45.0

## Enemy steering keeps this much space around a tower body.
const OBSTACLE_MARGIN := 18.0

const PAD_SCENE := preload("res://scenes/battle/BuildPad.tscn")
const TOWER_SCENE := preload("res://scenes/battle/Tower.tscn")

## `{position: Vector2, radius: float}` per built tower. Rebuilt only on change.
var obstacles: Array[Dictionary] = []

var _battle: Battle
var _enemy_pool: EnemyPool
var _projectiles: TowerProjectilePool
var _pads: Array[BuildPad] = []
var _towers: Array[Tower] = []

@onready var _pads_root: Node2D = $Pads
@onready var _towers_root: Node2D = $Towers
@onready var _range: RangeIndicator = $RangeIndicator


## Builds the eight pads once, when the battle scene is ready.
func setup(battle_ref: Battle, enemies: EnemyPool, projectiles: TowerProjectilePool) -> void:
	_battle = battle_ref
	_enemy_pool = enemies
	_projectiles = projectiles
	_create_pads()


## Removes every tower and frees the pads for a new run.
func reset() -> void:
	for tower: Tower in _towers.duplicate():
		if is_instance_valid(tower):
			_towers_root.remove_child(tower)
			tower.queue_free()
	_towers.clear()
	for pad: BuildPad in _pads:
		pad.clear_tower()
		pad.set_selected(false)
	obstacles.clear()
	hide_range()
	_update_affordability()


## Every pad, in ring order.
func get_pads() -> Array[BuildPad]:
	return _pads


## Every built tower.
func get_towers() -> Array[Tower]:
	return _towers


## Number of built towers, for the HUD counter.
func count_built() -> int:
	return _towers.size()


## Pad under a world-space tap, or null when the tap missed every pad.
func find_pad_at(world_position: Vector2) -> BuildPad:
	var best: BuildPad = null
	var best_distance := INF
	for pad: BuildPad in _pads:
		var distance := world_position.distance_to(pad.global_position)
		if distance <= pad.get_tap_radius() and distance < best_distance:
			best_distance = distance
			best = pad
	return best


## Builds `tower_id` on `pad` if the pad is free and the Coins are available.
func build(pad: BuildPad, tower_id: String) -> bool:
	if pad == null or pad.has_tower() or _battle == null:
		return false
	var data := ConfigDB.get_tower(tower_id) as TowerData
	if data == null:
		push_warning("[TowerManager] unknown tower id '%s'" % tower_id)
		return false
	var price := _battle.get_tower_cost(tower_id)
	if not _battle.spend_coins(price):
		return false

	var tower: Tower = TOWER_SCENE.instantiate()
	_towers_root.add_child(tower)
	tower.global_position = pad.global_position
	tower.setup(data, _battle, _enemy_pool, _projectiles, price)
	tower.play_pop()
	pad.set_tower(tower)
	_towers.append(tower)

	_rebuild_obstacles()
	_update_affordability()
	EventBus.tower_built.emit(tower_id)
	Analytics.log_event("tower_built", {"tower": tower_id, "price": price})
	return true


## Pays for and applies the next level. Returns false at max level or when the
## player cannot afford it.
func upgrade(tower: Tower) -> bool:
	if tower == null or not is_instance_valid(tower) or tower.is_max_level():
		return false
	if _battle == null:
		return false
	var cost := tower.get_upgrade_cost()
	if not _battle.spend_coins(cost):
		return false
	tower.upgrade(cost)
	EventBus.upgrade_purchased.emit("tower:%s" % tower.data.id, tower.level)
	Analytics.log_event("tower_upgraded", {"tower": tower.data.id, "level": tower.level})
	return true


## Sells a tower, refunds 60% of everything invested and frees the pad.
func sell(tower: Tower) -> int:
	if tower == null or not is_instance_valid(tower):
		return 0
	var refund := tower.get_sell_refund()
	if tower.pad != null and is_instance_valid(tower.pad):
		tower.pad.clear_tower()
	_towers.erase(tower)
	_towers_root.remove_child(tower)
	tower.queue_free()
	if _battle != null:
		_battle.add_coins(refund)
	_rebuild_obstacles()
	_update_affordability()
	hide_range()
	return refund


## Highlights one pad (or none) and shows the range of its tower.
func select(pad: BuildPad) -> void:
	for other: BuildPad in _pads:
		if other != pad:
			other.set_selected(false)
	if pad == null:
		hide_range()
		return
	pad.set_selected(true)
	if pad.has_tower():
		show_range(pad.tower)
	else:
		hide_range()


## Draws the dashed range ring for `tower`.
func show_range(tower: Tower) -> void:
	_range.show_for(tower)


## Hides the range ring.
func hide_range() -> void:
	_range.hide_ring()


## Cheap price of the current run, used for the pad affordability glow.
func get_cheapest_cost() -> int:
	if _battle == null:
		return 0
	return _battle.get_cheapest_tower_cost()


## Re-evaluates every pad glow after Coins changed.
func on_coins_changed() -> void:
	_update_affordability()


func _create_pads() -> void:
	for index in PAD_COUNT:
		var pad: BuildPad = PAD_SCENE.instantiate()
		_pads_root.add_child(pad)
		var degrees := START_ANGLE_DEG + float(index) * ANGLE_STEP_DEG
		var angle := deg_to_rad(degrees)
		pad.global_position = Battle.CENTER + Vector2(cos(angle), sin(angle)) * RING_RADIUS
		pad.setup(index)
		_pads.append(pad)


func _rebuild_obstacles() -> void:
	obstacles.clear()
	for tower: Tower in _towers:
		if not is_instance_valid(tower):
			continue
		obstacles.append({
			"position": tower.global_position,
			"radius": tower.get_body_radius() + OBSTACLE_MARGIN,
		})


func _update_affordability() -> void:
	if _battle == null:
		return
	var cheapest := get_cheapest_cost()
	for pad: BuildPad in _pads:
		pad.set_affordable(not pad.has_tower() and _battle.coins >= cheapest)
