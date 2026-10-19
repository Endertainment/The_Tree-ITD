class_name FloatingTextLayer
extends Node2D
## Pool of 40 combat popups. When every label is busy the oldest is reused, so
## a big wave can never allocate a new node mid-frame.

const MAX_POPUPS := 40
const FLOATING_TEXT_SCENE := preload("res://scenes/battle/FloatingText.tscn")
const POPUP_MARGIN_X := 90.0
const POPUP_MARGIN_TOP := 150.0
const POPUP_MARGIN_BOTTOM := 280.0

var _free: Array[FloatingText] = []
var _active: Array[FloatingText] = []


func _ready() -> void:
	for _index in MAX_POPUPS:
		var item: FloatingText = FLOATING_TEXT_SCENE.instantiate()
		add_child(item)
		item.visible = false
		item.finished.connect(_on_popup_finished)
		_free.append(item)


## Shows `text` at `world_position`, clamped so edge spawns stay readable.
func add_popup(text: String, world_position: Vector2) -> void:
	var item := _acquire()
	if item == null:
		return
	var view_size := get_viewport_rect().size
	var clamped := Vector2(
		clampf(world_position.x, POPUP_MARGIN_X, view_size.x - POPUP_MARGIN_X),
		clampf(world_position.y, POPUP_MARGIN_TOP, view_size.y - POPUP_MARGIN_BOTTOM)
	)
	item.play(text, clamped)


## Number of visible popups, for the debug overlay.
func count_active() -> int:
	return _active.size()


## Cancels every popup, used when a run ends.
func clear_all() -> void:
	for item: FloatingText in _active:
		item.stop_now()
	_free.append_array(_active)
	_active.clear()


func _acquire() -> FloatingText:
	if not _free.is_empty():
		var item: FloatingText = _free.pop_back()
		_active.append(item)
		return item
	if _active.is_empty():
		return null
	return _active[0]


func _on_popup_finished(item: FloatingText) -> void:
	var index := _active.find(item)
	if index >= 0:
		_active.remove_at(index)
	if not _free.has(item):
		_free.append(item)
