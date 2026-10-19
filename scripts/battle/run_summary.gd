class_name RunSummary
extends RefCounted
## Result of one battle. Passed to the results screen through a one-shot
## `SceneRouter` payload and to Analytics; never read from a global.

var waves_cleared := 0
var kills := 0
var bosses_killed := 0
var coins_earned := 0
var time_seconds := 0.0
var reason: StringName = &"defeat"

## Best wave the profile had *before* this run, for the NEW BEST badge.
var best_wave_before := 0

## Run mode; endless is the only MVP mode.
var mode: StringName = &"endless"

## Gold multiplier resolved by this run's modifiers, so the payout does not
## depend on meta state that could change before the results screen opens.
var gold_mult := 1.0


## Plain dictionary for analytics and stage-4 persistence.
func to_dict() -> Dictionary:
	return {
		"waves_cleared": waves_cleared,
		"kills": kills,
		"bosses_killed": bosses_killed,
		"coins_earned": coins_earned,
		"time_seconds": snappedf(time_seconds, 0.1),
		"reason": str(reason),
		"best_wave_before": best_wave_before,
		"mode": str(mode),
		"gold_mult": snappedf(gold_mult, 0.001),
	}


## "m:ss" for the results screen.
func get_time_string() -> String:
	var total := maxi(0, int(time_seconds))
	return "%d:%02d" % [total / 60, total % 60]
