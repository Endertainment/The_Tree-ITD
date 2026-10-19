class_name StatusComponent
extends Node
## Timer-based status effects. Stage 2 only declares the slow hooks that the
## Frost Spire fills in stage 3; nothing applies a slow yet.

var slow_multiplier := 1.0

var _slow_time := 0.0


## Applies a slow. Repeated hits refresh the timer but do not stack strength.
func apply_slow(strength: float, duration: float) -> void:
	var candidate := clampf(1.0 - strength, 0.1, 1.0)
	slow_multiplier = minf(slow_multiplier, candidate)
	_slow_time = maxf(_slow_time, duration)


## Advances timers. Call once per physics frame while the enemy is active.
func tick(delta: float) -> void:
	if _slow_time <= 0.0:
		return
	_slow_time -= delta
	if _slow_time <= 0.0:
		_slow_time = 0.0
		slow_multiplier = 1.0


## Removes every status, used when a pooled enemy is reused.
func clear() -> void:
	slow_multiplier = 1.0
	_slow_time = 0.0
