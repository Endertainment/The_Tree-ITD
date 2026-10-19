class_name ScreenShake
extends Camera2D
## Trauma-decay screen shake for the battle view.
##
## The camera is centred on `Battle.CENTER`, so it renders the same 1080x1920
## slice the project used before; only `offset` moves. Shake decays with
## squared trauma and is disabled entirely on low quality.

signal shook(strength: float)

const MAX_OFFSET_PX := 18.0
const DECAY_PER_SECOND := 1.6
const MAX_TRAUMA := 1.0
const FREQUENCY_A := 47.0
const FREQUENCY_B := 61.0

var _trauma := 0.0
var _time := 0.0


func _process(delta: float) -> void:
	if _trauma <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return
	_time += delta
	_trauma = maxf(0.0, _trauma - DECAY_PER_SECOND * delta)
	if _trauma <= 0.0:
		offset = Vector2.ZERO
		return
	var strength := _trauma * _trauma
	offset = Vector2(
		sin(_time * FREQUENCY_A) + sin(_time * FREQUENCY_B * 0.5) * 0.4,
		cos(_time * FREQUENCY_B) + cos(_time * FREQUENCY_A * 0.5) * 0.4
	) / 1.4 * MAX_OFFSET_PX * strength


## Adds `amount` (0..1) of trauma, saturating at full.
func add_trauma(amount: float) -> void:
	if GameState.is_low_quality() or amount <= 0.0:
		return
	_trauma = clampf(_trauma + amount, 0.0, MAX_TRAUMA)
	shook.emit(amount)


## Requests an initial on-screen displacement of `pixels` (squared decay makes
## the offset non-linear, so this solves for the matching trauma).
func shake_pixels(pixels: float) -> void:
	if pixels <= 0.0:
		return
	add_trauma(sqrt(clampf(pixels / MAX_OFFSET_PX, 0.0, 1.0)))


## Current trauma level (0 when idle).
func get_trauma() -> float:
	return _trauma


## True while the camera is displaced.
func is_shaking() -> bool:
	return _trauma > 0.0


## Clears any in-flight shake, used on pause/defeat/results.
func reset_shake() -> void:
	_trauma = 0.0
	offset = Vector2.ZERO
