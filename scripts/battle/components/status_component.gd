class_name StatusComponent
extends Node
## Timer-based status effects: slow, stun and the boss's opening slow immunity.

var slow_multiplier := 1.0
var stun_time := 0.0

var _slow_time := 0.0
var _slow_immune := 0.0


## Applies a slow. Repeated hits refresh the timer but do not stack strength.
## Refused while the immunity timer is running.
func apply_slow(strength: float, duration: float) -> void:
	if _slow_immune > 0.0:
		return
	var candidate := clampf(1.0 - strength, 0.1, 1.0)
	slow_multiplier = minf(slow_multiplier, candidate)
	_slow_time = maxf(_slow_time, duration)


## Freezes the owner for `duration` seconds. Repeated hits refresh the timer.
## Refused while the immunity timer is running, like `apply_slow`.
func apply_stun(duration: float) -> void:
	if duration <= 0.0 or _slow_immune > 0.0:
		return
	stun_time = maxf(stun_time, duration)


## True while the owner cannot move or attack.
func is_stunned() -> bool:
	return stun_time > 0.0


## Makes the owner immune to slow for `seconds` (boss opening window).
func set_slow_immune(seconds: float) -> void:
	_slow_immune = maxf(_slow_immune, seconds)


## True while slow applications are being refused.
func is_slow_immune() -> bool:
	return _slow_immune > 0.0


## Advances timers. Call once per physics frame while the enemy is active.
func tick(delta: float) -> void:
	if _slow_immune > 0.0:
		_slow_immune = maxf(0.0, _slow_immune - delta)
	if stun_time > 0.0:
		stun_time = maxf(0.0, stun_time - delta)
	if _slow_time <= 0.0:
		return
	_slow_time -= delta
	if _slow_time <= 0.0:
		_slow_time = 0.0
		slow_multiplier = 1.0


## Removes every status, used when a pooled enemy is reused.
func clear() -> void:
	slow_multiplier = 1.0
	stun_time = 0.0
	_slow_time = 0.0
	_slow_immune = 0.0
