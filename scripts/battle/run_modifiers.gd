class_name RunModifiers
extends RefCounted
## Resolves every run-wide modifier once, at run start.
##
## Sources, in order: base values, permanent meta upgrades, equipped cards and
## run-only effects. Multipliers are additive within a category and applied as
## `value * (1 + sum)`, per master context section 7.7. Nodes never read the
## save file themselves; they read `RunStats`, which owns one instance of this.
##
## Every number comes from data: `data/meta_upgrades/*.tres` and
## `data/cards/*.tres`. This class only decides how entries accumulate.

## Multiplier stats clamp their final value to this floor.
const MIN_MULT := 0.2

var tree_hp_mult := 1.0
var tree_regen_add := 0.0
var archer_dmg_mult := 1.0
var archer_speed_mult := 1.0
var archer_range_mult := 1.0
var projectile_speed_mult := 1.0
var coin_mult := 1.0
var gold_mult := 1.0
var tower_cost_mult := 1.0
var slow_strength := 0.0
var start_coins_add := 0
var start_archers_add := 0

## Speed trials granted for this run only (the ad chip).
var speed_trial_15 := false
var speed_trial_2 := false

var _mult_sums: Dictionary = {}
var _flat_sums: Dictionary = {}


## Builds the run modifiers from `meta` (a save dictionary), equipped cards and
## the per-run speed trial flag.
static func build(meta: Dictionary, cards: Array[CardData] = [], trial_speed := false) -> RunModifiers:
	var result := RunModifiers.new()
	var upgrades: Dictionary = meta.get("upgrades", {})
	if ConfigDB != null:
		for track: MetaUpgradeData in ConfigDB.all_meta_upgrades():
			var level := int(upgrades.get(track.id, 0))
			if level <= 0:
				continue
			result._add(track.stat, track.op, float(level) * track.value_per_level)
	for card: CardData in cards:
		if card == null:
			continue
		for modifier: StatModifier in card.modifiers:
			if modifier == null or modifier.stat.is_empty():
				continue
			result._add(modifier.stat, modifier.op, modifier.value)
	result._finalize()
	result.speed_trial_15 = trial_speed
	return result


## Accumulates one entry. `mult` feeds `1 + sum`, `add` feeds a flat total.
func _add(stat: String, op: String, value: float) -> void:
	if op == "add":
		_flat_sums[stat] = float(_flat_sums.get(stat, 0.0)) + value
		return
	_mult_sums[stat] = float(_mult_sums.get(stat, 0.0)) + value


func _finalize() -> void:
	tree_hp_mult = _mult("tree_hp_mult")
	tree_regen_add = _flat("tree_regen_add")
	archer_dmg_mult = _mult("archer_dmg_mult")
	archer_speed_mult = _mult("archer_speed_mult")
	archer_range_mult = _mult("archer_range_mult")
	projectile_speed_mult = _mult("projectile_speed_mult")
	coin_mult = _mult("coin_mult")
	gold_mult = _mult("gold_mult")
	tower_cost_mult = _mult("tower_cost_mult")
	slow_strength = _flat("slow_strength")
	start_coins_add = roundi(_flat("start_coins_add"))
	start_archers_add = roundi(_flat("start_archers_add"))


func _mult(stat: String) -> float:
	return maxf(MIN_MULT, 1.0 + float(_mult_sums.get(stat, 0.0)))


func _flat(stat: String) -> float:
	return float(_flat_sums.get(stat, 0.0))
