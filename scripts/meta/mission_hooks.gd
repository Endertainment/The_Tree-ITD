class_name MissionHooks
extends RefCounted
## Stage-4 bridge from a finished run to the stage-5 mission system.
##
## Stores open-ended metric counters in the save (runs, waves, bosses, gold) and
## emits `mission_progress` with `target = 0`, meaning "metric updated, no
## specific mission target yet". Stage 5 maps MissionData to these metrics and
## replaces the zero targets.


## Records the run's contribution and emits one progress signal per metric.
static func report_run(summary: RunSummary, gold: int) -> void:
	var metrics := {
		"run_completed": 1,
		"wave_reached": summary.waves_cleared,
		"bosses_killed": summary.bosses_killed,
		"gold_earned": gold,
	}
	GameState.record_mission_metrics(metrics)
	for key: String in metrics:
		EventBus.mission_progress.emit(key, GameState.get_mission_metric(key), 0)
