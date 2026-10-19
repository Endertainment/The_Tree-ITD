class_name RunSummary
extends RefCounted
## Immutable-ish result of one battle. Passed to results screens and analytics;
## never read from a global.

var waves_cleared := 0
var kills := 0
var coins_earned := 0
var time_seconds := 0.0
var reason: StringName = &"defeat"


## Plain dictionary for analytics and stage-4 persistence.
func to_dict() -> Dictionary:
	return {
		"waves_cleared": waves_cleared,
		"kills": kills,
		"coins_earned": coins_earned,
		"time_seconds": snappedf(time_seconds, 0.1),
		"reason": str(reason),
	}


## "m:ss" for the defeat panel.
func get_time_string() -> String:
	var total := maxi(0, int(time_seconds))
	return "%d:%02d" % [total / 60, total % 60]
