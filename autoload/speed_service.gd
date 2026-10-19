extends Node
## Engine.time_scale control with the stage-4 unlock matrix.
##
## 1x is always available. 1.5x unlocks through `unlocks.speed_15`, Elf Level 3
## or a per-run trial; 2x through `unlocks.speed_2`, `best_wave >= 25` or a
## per-run trial that also has 1.5x. Trials are cleared when a run ends.

const BASE_SPEED := 1.0
const SPEEDS: Array[float] = [1.0, 1.5, 2.0]
const UNLOCK_FLAGS := {
	1.5: "speed_15",
	2.0: "speed_2",
}
const ELF_LEVEL_FOR_15 := 3
const BEST_WAVE_FOR_2 := 25

var _speed := BASE_SPEED
var _trial_15 := false
var _trial_2 := false


func _ready() -> void:
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_ended.connect(_on_run_ended)


## Applies a speed if unlocked and not paused. Returns false when refused.
func set_speed(multiplier: float) -> bool:
	if not is_speed_unlocked(multiplier):
		return false
	if get_tree().paused:
		return false
	_speed = multiplier
	Engine.time_scale = multiplier
	EventBus.speed_changed.emit(multiplier)
	return true


## Returns the current multiplier.
func get_speed() -> float:
	return _speed


## Re-applies the selected speed after a temporary slow-mo changed time scale.
func reapply() -> void:
	Engine.time_scale = _speed


## Grants (or clears) the per-run speed trials. Does not change the current speed.
func set_run_trials(trial_15: bool, trial_2: bool) -> void:
	_trial_15 = trial_15
	_trial_2 = trial_2


## True while any per-run speed trial is active.
func is_run_trial_active() -> bool:
	return _trial_15 or _trial_2


## True for 1x, or for a faster speed when one of its unlock paths is met.
func is_speed_unlocked(multiplier: float) -> bool:
	if is_equal_approx(multiplier, BASE_SPEED):
		return true
	if is_equal_approx(multiplier, 1.5):
		return (
			GameState.is_unlocked(UNLOCK_FLAGS[1.5])
			or GameState.get_elf_level() >= ELF_LEVEL_FOR_15
			or _trial_15
		)
	if is_equal_approx(multiplier, 2.0):
		return (
			GameState.is_unlocked(UNLOCK_FLAGS[2.0])
			or GameState.get_best_wave() >= BEST_WAVE_FOR_2
			or (_trial_2 and is_speed_unlocked(1.5))
		)
	return false


## Every speed the player can currently select, in cycle order.
func get_available_speeds() -> Array[float]:
	var result: Array[float] = []
	for speed: float in SPEEDS:
		if is_speed_unlocked(speed):
			result.append(speed)
	return result


## Advances to the next unlocked speed and applies it. Returns the new speed.
func cycle_speed() -> float:
	var available := get_available_speeds()
	if available.is_empty():
		return BASE_SPEED
	var index := available.find(_speed)
	var next := available[0]
	if index >= 0:
		next = available[(index + 1) % available.size()]
	set_speed(next)
	return _speed


## Localization key explaining how to unlock `multiplier`.
func get_locked_reason_key(multiplier: float) -> String:
	if is_equal_approx(multiplier, 1.5):
		return "SPEED_LOCK_15"
	if is_equal_approx(multiplier, 2.0):
		return "SPEED_LOCK_2"
	return ""


## "1x", "1.5x" or "2x" for the HUD button.
func get_speed_label(multiplier: float = -1.0) -> String:
	var value := _speed if multiplier < 0.0 else multiplier
	if is_equal_approx(value, roundf(value)):
		return "%dx" % int(roundf(value))
	return "%.1fx" % value


## Returns to 1x and clears any paused time scale.
func reset() -> void:
	var changed := not is_equal_approx(_speed, BASE_SPEED)
	_speed = BASE_SPEED
	Engine.time_scale = BASE_SPEED
	if changed:
		EventBus.speed_changed.emit(BASE_SPEED)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		reset()


func _on_run_started() -> void:
	reset()


func _on_run_ended(_summary: Variant) -> void:
	_trial_15 = false
	_trial_2 = false
	reset()
