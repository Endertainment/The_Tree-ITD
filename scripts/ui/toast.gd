class_name Toast
extends CanvasLayer
## Non-blocking message strip anchored above the bottom edge.

const FADE_IN := 0.15
const FADE_OUT := 0.3
const DEFAULT_SECONDS := 2.0

@onready var _panel: PanelContainer = %Panel
@onready var _label: Label = %Message

var _tween: Tween


func _ready() -> void:
	layer = 64
	_panel.modulate.a = 0.0


## Shows `text`, then fades it out. Re-calling restarts the timer.
func show_message(text: String, duration := DEFAULT_SECONDS) -> void:
	if not is_node_ready():
		await ready
	_label.text = text
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_panel.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 1.0, FADE_IN)
	_tween.tween_interval(duration)
	_tween.tween_property(_panel, "modulate:a", 0.0, FADE_OUT)
