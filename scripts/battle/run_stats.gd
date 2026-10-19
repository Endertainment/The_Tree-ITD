class_name RunStats
extends RefCounted
## The single source of truth for one run's live combat values.
##
## Built from base values plus `RunModifiers` (meta + cards) plus the in-run
## upgrade tracks. `Core`, archers, wave spawning and towers read these fields;
## only `apply_upgrade()` writes them, and every write emits `stats_changed`.

signal stats_changed

const BASE_TREE_HP := 1000.0
const BASE_COINS := 120
const BASE_ARCHERS := 2
const MAX_ARCHERS := 5
const BASE_ARCHER_DAMAGE := 12.0
const BASE_ARCHER_INTERVAL := 0.8
const BASE_ARCHER_RANGE := 520.0
const BASE_PROJECTILE_SPEED := 900.0

var max_hp := BASE_TREE_HP
var regen := 0.0
var archer_damage := BASE_ARCHER_DAMAGE
var archer_interval := BASE_ARCHER_INTERVAL
var archer_range := BASE_ARCHER_RANGE
var projectile_speed := BASE_PROJECTILE_SPEED
var coin_mult := 1.0
var start_coins := BASE_COINS
var start_archers := BASE_ARCHERS
var tower_cost_mult := 1.0
var slow_strength := 0.0

var _modifiers: RunModifiers
var _levels: Dictionary = {}
var _tracks: Dictionary = {}


## Resets every level and recomputes from `modifiers` (or neutral modifiers).
func setup(modifiers: RunModifiers = null) -> void:
	_modifiers = modifiers if modifiers != null else RunModifiers.build({})
	_levels.clear()
	_tracks.clear()
	for entry: Variant in ConfigDB.all_upgrades():
		var track := entry as UpgradeTrack
		if track == null:
			continue
		_tracks[track.id] = track
		_levels[track.id] = 0
	recompute()


## Buys one level of `track_id`. Returns false when unknown or maxed.
func apply_upgrade(track_id: String) -> bool:
	var track := get_track(track_id)
	if track == null:
		return false
	var level := get_level(track_id)
	if level >= track.max_level:
		return false
	_levels[track_id] = level + 1
	recompute()
	EventBus.upgrade_purchased.emit("run:%s" % track_id, level + 1)
	return true


## Recomputes every field. Called after each purchase and once per run.
func recompute() -> void:
	var multipliers := _modifiers if _modifiers != null else RunModifiers.new()

	max_hp = BASE_TREE_HP * multipliers.tree_hp_mult + _sum_effect("max_hp")
	regen = multipliers.tree_regen_add + _sum_effect("regen")
	archer_damage = snappedf(
		BASE_ARCHER_DAMAGE * multipliers.archer_dmg_mult * (1.0 + _sum_effect("archer_damage")),
		0.1
	)
	archer_interval = snappedf(
		BASE_ARCHER_INTERVAL / maxf(
			0.1,
			multipliers.archer_speed_mult * (1.0 + _sum_effect("archer_speed"))
		),
		0.001
	)
	archer_range = BASE_ARCHER_RANGE * multipliers.archer_range_mult + _sum_effect("archer_range")
	projectile_speed = BASE_PROJECTILE_SPEED * multipliers.projectile_speed_mult
	coin_mult = multipliers.coin_mult
	start_coins = maxi(0, BASE_COINS + multipliers.start_coins_add)
	start_archers = clampi(
		BASE_ARCHERS + multipliers.start_archers_add + int(_sum_effect("archer_count")),
		1,
		MAX_ARCHERS
	)
	tower_cost_mult = multipliers.tower_cost_mult
	slow_strength = multipliers.slow_strength
	stats_changed.emit()


## The track resource for `track_id`, or null.
func get_track(track_id: String) -> UpgradeTrack:
	return _tracks.get(track_id, null) as UpgradeTrack


## Levels currently owned in `track_id`.
func get_level(track_id: String) -> int:
	return int(_levels.get(track_id, 0))


## Coins for the next level, or 0 at max level.
func get_next_cost(track_id: String) -> int:
	var track := get_track(track_id)
	if track == null:
		return 0
	var level := get_level(track_id)
	if level >= track.max_level:
		return 0
	return track.cost_for_level(level)


## True when the track cannot be bought again.
func is_maxed(track_id: String) -> bool:
	var track := get_track(track_id)
	return track == null or get_level(track_id) >= track.max_level


## Archer damage per second with the current stats.
func get_archer_dps() -> float:
	if archer_interval <= 0.0:
		return 0.0
	return archer_damage / archer_interval * float(start_archers)


## Current and next display value of one track, for the panel row.
## `now`/`next` are in the effect's own unit (HP, HP/s, px, seconds, count).
func get_display(track_id: String) -> Dictionary:
	var track := get_track(track_id)
	if track == null:
		return {}
	var level := get_level(track_id)
	var next_level := mini(level + 1, track.max_level)
	return {
		"effect": track.effect,
		"now": _effect_value(track.effect),
		"next": _effect_value_preview(track.id, track.effect, next_level),
		"maxed": level >= track.max_level,
	}


## Effect value at `level` for one track, independent of the others.
func _effect_value(effect: String) -> float:
	match effect:
		"max_hp":
			return max_hp
		"regen":
			return regen
		"archer_damage":
			return archer_damage
		"archer_speed":
			return archer_interval
		"archer_range":
			return archer_range
		"archer_count":
			return float(start_archers)
		_:
			return 0.0


## Same as `_effect_value`, but with `track_id` evaluated at `override_level`.
func _effect_value_preview(track_id: String, effect: String, override_level: int) -> float:
	var multipliers := _modifiers if _modifiers != null else RunModifiers.new()
	match effect:
		"max_hp":
			return BASE_TREE_HP * multipliers.tree_hp_mult + _sum_effect("max_hp", track_id, override_level)
		"regen":
			return multipliers.tree_regen_add + _sum_effect("regen", track_id, override_level)
		"archer_damage":
			return snappedf(
				BASE_ARCHER_DAMAGE * multipliers.archer_dmg_mult
					* (1.0 + _sum_effect("archer_damage", track_id, override_level)),
				0.1
			)
		"archer_speed":
			return snappedf(
				BASE_ARCHER_INTERVAL / maxf(
					0.1,
					multipliers.archer_speed_mult
						* (1.0 + _sum_effect("archer_speed", track_id, override_level))
				),
				0.001
			)
		"archer_range":
			return BASE_ARCHER_RANGE * multipliers.archer_range_mult + _sum_effect(
				"archer_range", track_id, override_level
			)
		"archer_count":
			return float(clampi(
				BASE_ARCHERS + multipliers.start_archers_add
					+ int(_sum_effect("archer_count", track_id, override_level)),
				1,
				MAX_ARCHERS
			))
		_:
			return 0.0


## Sums the contribution of every track with `effect`.
## `override_id`/`override_level` let a preview evaluate one track at another
## level.
func _sum_effect(effect: String, override_id := "", override_level := -1) -> float:
	var total := 0.0
	for track_id: String in _tracks:
		var track: UpgradeTrack = _tracks[track_id]
		if track.effect != effect:
			continue
		var level := override_level if track_id == override_id and override_level >= 0 else get_level(track_id)
		var value := track.value_at(level)
		total += value
	return total
