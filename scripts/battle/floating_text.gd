class_name FloatingText
extends Node2D
## One rising, fading combat popup. Pooled by `FloatingTextLayer`.

signal finished(item: FloatingText)

const RISE_DISTANCE := 44.0
const DURATION := 0.7
const FADE_DELAY := 0.25

@onready var _value: Label = %Value

var _tween: Tween


func _ready() -> void:
	visible = false


## Starts the popup at a world position. Reuse restarts it cleanly.
func play(text: String, world_position: Vector2) -> void:
	global_position = world_position
	_value.text = text
	visible = true
	modulate.a = 1.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "global_position:y", world_position.y - RISE_DISTANCE, DURATION)
	_tween.parallel().tween_property(self, "modulate:a", 0.0, DURATION - FADE_DELAY).set_delay(FADE_DELAY)
	_tween.finished.connect(_on_tween_finished, CONNECT_ONE_SHOT)


## Cancels the animation and hides the label immediately.
func stop_now() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = false


func _on_tween_finished() -> void:
	visible = false
	finished.emit(self)
