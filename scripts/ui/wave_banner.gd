class_name WaveBanner
extends Control
## Centred announcement banner used for wave modifiers. Fades in, holds for
## 1.5 s and fades out; never takes input.

const DEFAULT_SECONDS := 1.5
const FADE_IN := 0.12
const FADE_OUT := 0.35

var _tween: Tween

@onready var _label: Label = %Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	_label.text = ""


## Shows `text` for `seconds`, then fades it out. Re-calling restarts the hold.
func show_banner(text: String, seconds := DEFAULT_SECONDS) -> void:
	_label.text = text
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_IN)
	_tween.tween_interval(seconds)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT)


## Hides the banner immediately.
func hide_banner() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 0.0
