class_name AdSpinner
extends Control
## Small rotating busy indicator shown while an ad or purchase is in flight.
##
## A code-drawn arc keeps the widget asset-free and cheap; it only processes
## while visible.

const RADIUS_MARGIN := 4.0
const COLOR := Color("#f2c14e")
const THICKNESS := 6.0
const ARC := PI * 1.35
const SPEED := 2.4

var _angle := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(48.0, 48.0)
	visible = false
	set_process(false)
	queue_redraw()


## Shows and animates the spinner.
func start() -> void:
	visible = true
	set_process(true)
	queue_redraw()


## Hides and stops the spinner.
func stop() -> void:
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	_angle = wrapf(_angle + delta * SPEED, 0.0, TAU)
	queue_redraw()


func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5 - RADIUS_MARGIN
	if radius <= 0.0:
		return
	draw_arc(size * 0.5, radius, _angle, _angle + ARC, 24, COLOR, THICKNESS, true)
