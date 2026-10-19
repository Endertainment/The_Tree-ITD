class_name RunModifiers
extends RefCounted
## Resolves every run-wide multiplier once, at run start.
##
## Sources, in order: base values, permanent meta upgrades, equipped cards and
## run-only effects. Multipliers are additive within a category and applied as
## `value * (1 + sum)`, per master context section 7.7. Nodes never read the
## save file themselves; they read `RunStats`, which owns one instance of this.

## Permanent upgrade id -> stat key and value per level.
const META_UPGRADES := {
	"tree_hp": {"stat": "tree_hp_mult", "per_level": 0.05},
	"tree_regen": {"stat": "tree_regen_add", "per_level": 0.5},
	"archer_dmg": {"stat": "archer_dmg_mult", "per_level": 0.04},
	"archer_speed": {"stat": "archer_speed_mult", "per_level": 0.03},
	"start_coins": {"stat": "start_coins_add", "per_level": 20.0},
	"tower_discount": {"stat": "tower_cost_mult", "per_level": -0.02},
	"coin_gain": {"stat": "coin_mult", "per_level": 0.03},
	"gold_gain": {"stat": "gold_mult", "per_level": 0.04},
}

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

var _sums: Dictionary = {}


## Builds the run modifiers from `meta` (a save dictionary), equipped cards and
## the per-run speed trial flag.
static func build(meta: Dictionary, cards: Array[CardData] = [], trial_speed := false) -> RunModifiers:
	var result := RunModifiers.new()
	var upgrades: Dictionary = meta.get("upgrades", {})
	for id: String in META_UPGRADES:
		var level := int(upgrades.get(id, 0))
		if level <= 0:
			continue
		var entry: Dictionary = META_UPGRADES[id]
		result._add(str(entry["stat"]), float(level) * float(entry["per_level"]))
	for card: CardData in cards:
		if card == null:
			continue
		for modifier: Dictionary in card.modifiers:
			var stat := str(modifier.get("stat", ""))
			if stat.is_empty():
				continue
			# Both ops accumulate: multipliers add into `1 + sum`, flat effects
			# add to their own total, per master 7.7.
			result._add(stat, float(modifier.get("value", 0.0)))
	result._finalize()
	result.speed_trial_15 = trial_speed
	return result


func _add(stat: String, value: float) -> void:
	_sums[stat] = float(_sums.get(stat, 0.0)) + value


func _finalize() -> void:
	tree_hp_mult = _mult("tree_hp_mult")
	tree_regen_add = _additive("tree_regen_add")
	archer_dmg_mult = _mult("archer_dmg_mult")
	archer_speed_mult = _mult("archer_speed_mult")
	archer_range_mult = _mult("archer_range_mult")
	projectile_speed_mult = _mult("projectile_speed_mult")
	coin_mult = _mult("coin_mult")
	gold_mult = _mult("gold_mult")
	tower_cost_mult = _mult("tower_cost_mult")
	slow_strength = _additive("slow_strength")
	start_coins_add = roundi(_additive("start_coins_add"))
	start_archers_add = roundi(_additive("start_archers_add"))


func _mult(stat: String) -> float:
	return maxf(MIN_MULT, 1.0 + float(_sums.get(stat, 0.0)))


func _additive(stat: String) -> float:
	return float(_sums.get(stat, 0.0))
