class_name BuildPad
extends Area2D
## One of the eight fixed build pads around the Tree.
##
## The pad owns its tower reference; taps are resolved by `Battle` against
## `get_tap_radius()` so touch input works identically on desktop, Android and
## in headless tests.

const BODY_RADIUS := 40.0
const TAP_RADIUS := 56.0
const REDRAW_SECONDS := 0.12

var index := 0
var tower: Tower

var _selected := false
var _affordable := true
var _pulse := 0.0
var _clock := 0.0


func _ready() -> void:
	_pulse = float(index) * 0.7
	queue_redraw()


## Stores the ring index so the pulse phase differs per pad.
func setup(pad_index: int) -> void:
	index = pad_index
	_pulse = float(index) * 0.7
	queue_redraw()


## Attaches a freshly built tower to this pad.
func set_tower(new_tower: Tower) -> void:
	tower = new_tower
	if tower != null:
		tower.pad = self
	queue_redraw()


## Detaches the tower so the pad becomes buildable again.
func clear_tower() -> void:
	if tower != null and is_instance_valid(tower):
		tower.pad = null
	tower = null
	queue_redraw()


## True while a tower stands on this pad.
func has_tower() -> bool:
	return tower != null and is_instance_valid(tower)


## Radius used by `Battle` for touch hit-testing.
func get_tap_radius() -> float:
	return TAP_RADIUS


## Toggles the golden selection ring.
func set_selected(selected_now: bool) -> void:
	if _selected == selected_now:
		return
	_selected = selected_now
	queue_redraw()


## Drives the "you can afford something" glow.
func set_affordable(affordable: bool) -> void:
	if _affordable == affordable:
		return
	_affordable = affordable
	queue_redraw()


func _process(delta: float) -> void:
	if not _affordable and not _selected:
		return
	_clock += delta
	if _clock < REDRAW_SECONDS:
		return
	_clock = 0.0
	_pulse += delta * 2.0
	queue_redraw()


func _draw() -> void:
	var stone := Color("#55604c")
	var glow := Color(0.949, 0.757, 0.306, 0.28 + 0.18 * sin(_pulse))

	draw_circle(Vector2(0.0, 6.0), BODY_RADIUS + 4.0, Color(0.02, 0.03, 0.02, 0.35))
	draw_circle(Vector2.ZERO, BODY_RADIUS, stone.darkened(0.35))
	draw_circle(Vector2.ZERO, BODY_RADIUS - 6.0, stone)

	if _affordable and not has_tower():
		draw_arc(Vector2.ZERO, BODY_RADIUS + 5.0, 0.0, TAU, 36, glow, 4.0, true)
	if not has_tower():
		draw_line(Vector2(-18.0, 0.0), Vector2(18.0, 0.0), Color("#e8d9a8"), 5.0)
		draw_line(Vector2(0.0, -18.0), Vector2(0.0, 18.0), Color("#e8d9a8"), 5.0)

	if _selected:
		draw_arc(Vector2.ZERO, BODY_RADIUS + 10.0, 0.0, TAU, 40, Color("#f2c14e"), 3.0, true)
