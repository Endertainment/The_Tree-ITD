class_name TowerData
extends Resource
## Tunable definition of one buildable tower.
##
## Balance lives in `data/towers/*.tres`; `ConfigDB` loads them into an
## `id -> TowerData` map at startup. `levels[0]` is the level-1 tower.

## Stable id used by pads, saves and analytics.
@export var id: String = ""

## Localization keys for the build card and the tower sheet.
@export var display_name_key: String = ""
@export var role_key: String = ""

## Build price in run Coins, before `tower_cost_mult`.
@export var cost: int = 60

## Body radius in design pixels. Enemy steering keeps this radius plus a margin.
@export var body_radius: float = 32.0

## Placeholder silhouette drawn by `Tower._draw()`.
@export_enum("archer", "frost", "ballista") var silhouette: String = "archer"

## Projectile flavour fired by this tower.
@export_enum("arrow", "frost_bolt", "ballista_bolt") var projectile: String = "arrow"

@export var base_color: Color = Color("#7a4a2b")
@export var accent_color: Color = Color("#f2c14e")

## Level 1 up to the maximum level, in order.
@export var levels: Array[TowerLevel] = []


## Highest level this tower can reach; 1 when the data is empty.
func max_level() -> int:
	return maxi(1, levels.size())


## Level stats for a 1-based `level`, clamped into the authored range.
func get_level_stats(level: int) -> TowerLevel:
	if levels.is_empty():
		return null
	var index := clampi(level - 1, 0, levels.size() - 1)
	return levels[index]


## Damage-per-second estimate of level `level`, for the build card.
func dps_at(level: int) -> float:
	var stats := get_level_stats(level)
	return stats.dps() if stats != null else 0.0
