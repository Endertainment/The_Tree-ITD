class_name SpeedButton
extends Button
## HUD speed control: cycles through unlocked speeds, shows a lock badge when a
## faster speed is still locked, and reports a long press for the unlock info.

signal info_requested

const LONG_PRESS_SECONDS := 0.45

var _hold := 0.0
var _holding := false
var _long_fired := false

@onready var _lock_badge: Label = %LockBadge


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	pressed.connect(_on_pressed)
	EventBus.speed_changed.connect(_on_speed_changed)
	refresh()


## Repaints the label, lock badge and tooltip from `SpeedService`.
func refresh() -> void:
	text = SpeedService.get_speed_label()
	var locked := _next_locked_speed()
	_lock_badge.visible = locked > 0.0
	if locked > 0.0:
		tooltip_text = Loc.t_key(SpeedService.get_locked_reason_key(locked))
	else:
		tooltip_text = ""


func _process(delta: float) -> void:
	if not _holding or _long_fired:
		return
	_hold += delta
	if _hold >= LONG_PRESS_SECONDS:
		_long_fired = true
		info_requested.emit()


func _next_locked_speed() -> float:
	if not SpeedService.is_speed_unlocked(1.5):
		return 1.5
	if not SpeedService.is_speed_unlocked(2.0):
		return 2.0
	return 0.0


func _on_button_down() -> void:
	_holding = true
	_hold = 0.0
	_long_fired = false


func _on_button_up() -> void:
	_holding = false


func _on_pressed() -> void:
	if _long_fired:
		_long_fired = false
		return
	if SpeedService.get_available_speeds().size() <= 1:
		info_requested.emit()
		return
	SpeedService.cycle_speed()
	refresh()


func _on_speed_changed(_multiplier: float) -> void:
	refresh()
