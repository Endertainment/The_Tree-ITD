extends Node
## Engine.time_scale control with unlock checks.
##
## 1x is always available. 1.5x and 2x require the matching unlock flag until
## the stage 6 ad trial grants them for a single run.

const BASE_SPEED := 1.0
const SPEEDS: Array[float] = [1.0, 1.5, 2.0]
const UNLOCK_FLAGS := {
	1.5: "speed_15",
	2.0: "speed_2",
}

var _speed := BASE_SPEED


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


## True for 1x, or for 1.5x / 2x when the matching unlock is owned.
func is_speed_unlocked(multiplier: float) -> bool:
	if is_equal_approx(multiplier, BASE_SPEED):
		return true
	var flag := _unlock_flag(multiplier)
	if flag.is_empty():
		return false
	return GameState.is_unlocked(flag)


## Returns to 1x and clears any paused time scale.
func reset() -> void:
	var changed := not is_equal_approx(_speed, BASE_SPEED)
	_speed = BASE_SPEED
	Engine.time_scale = BASE_SPEED
	if changed:
		EventBus.speed_changed.emit(BASE_SPEED)


func _unlock_flag(multiplier: float) -> String:
	for speed: float in UNLOCK_FLAGS:
		if is_equal_approx(speed, multiplier):
			return UNLOCK_FLAGS[speed]
	return ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		reset()


func _on_run_started() -> void:
	reset()


func _on_run_ended(_summary: Variant) -> void:
	reset()
