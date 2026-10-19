class_name MissionData
extends Resource
## One daily mission or one persistent achievement (master context section 6.4).
##
## `metric` is the counter the tracker feeds; `mode` decides whether repeated
## events add up (`sum`) or keep the best single value (`max`).

## Stable id and the key in `missions.*.progress`.
@export var id: String = ""

@export var title_key: String = ""
@export var description_key: String = ""

## Counter this mission listens to.
@export_enum(
	"kill_orcs",
	"clear_waves",
	"reach_wave",
	"build_towers",
	"earn_coins",
	"kill_bosses",
	"complete_runs",
	"watch_ads",
	"earn_gold"
)
var metric: String = "kill_orcs"

## `sum` accumulates events, `max` keeps the highest single value.
@export_enum("sum", "max") var mode: String = "sum"

## Amount of `metric` required to claim.
@export var target: int = 1

@export var reward_gold: int = 0
@export var reward_gems: int = 0

## True for the rotating daily pool, false for a permanent achievement.
@export var daily: bool = true


## True when `current` already satisfies this mission.
func is_complete(current: int) -> bool:
	return current >= target
