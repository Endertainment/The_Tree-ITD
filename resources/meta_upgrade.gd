class_name MetaUpgradeData
extends Resource
## One permanent Gold upgrade track (master context section 6.2).
##
## The same resource feeds the Upgrades screen and `RunModifiers`, so a displayed
## price and the effect it buys can never drift apart.

## Stable id, also the key in the save file's `upgrades` dictionary.
@export var id: String = ""

@export var name_key: String = ""
@export var description_key: String = ""

## Stat key understood by `RunModifiers`.
@export var stat: String = ""

## `mult` for percentages, `add` for flat values.
@export_enum("mult", "add") var op: String = "mult"

## Effect added per level, in the stat's own unit (0.05 = +5%, 0.5 = +0.5 HP/s).
@export var value_per_level: float = 0.0

## How the effect is rendered: `percent` or `flat`.
@export_enum("percent", "flat") var unit: String = "percent"

@export var max_level: int = 10
@export var base_cost: int = 150

## Cost growth per level: `base_cost * cost_growth^level`, rounded to 5 Gold.
@export var cost_growth: float = 1.55

## Display order on the Upgrades screen.
@export var order: int = 0


## Gold required to buy `level` (0-based level already owned).
func cost_for_level(level: int) -> int:
	return UpgradeTrack.round_to_step(float(base_cost) * pow(cost_growth, maxi(0, level)), 5)


## Total contribution of this track at `level`.
func value_at(level: int) -> float:
	return value_per_level * float(clampi(level, 0, max_level))
