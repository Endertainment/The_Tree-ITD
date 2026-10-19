class_name UpgradeTrack
extends Resource
## One in-run upgrade track, e.g. Roots or Canopy Bows.
##
## Costs and per-level values live here, never in gameplay code. `RunStats`
## reads `effect` and `value_per_level` when it recomputes the run's live stats.

## Stable id used by the panel, analytics and the save file.
@export var id: String = ""

## Panel tab: `tree` or `archers`.
@export_enum("tree", "archers") var tab: String = "tree"

## Which live stat the track feeds.
@export_enum("max_hp", "regen", "archer_damage", "archer_speed", "archer_range", "archer_count")
var effect: String = "max_hp"

## Amount added (or percentage, for mult effects) per level.
@export var value_per_level: float = 0.0

@export var name_key: String = ""
@export var description_key: String = ""
@export var max_level: int = 5
@export var base_cost: int = 70

## Cost growth per level: `base_cost * cost_growth^level`, rounded to 5.
@export var cost_growth: float = 1.45


## Coins required to buy `level` (0-based level already owned).
func cost_for_level(level: int) -> int:
	return round_to_step(float(base_cost) * pow(cost_growth, maxi(0, level)), 5)


## Total contribution of this track at `level`.
func value_at(level: int) -> float:
	return value_per_level * float(clampi(level, 0, max_level))


## Rounds a price to the nearest multiple of `step` (5 by default).
static func round_to_step(value: float, step: int = 5) -> int:
	if step <= 1:
		return roundi(value)
	return roundi(value / float(step)) * step
