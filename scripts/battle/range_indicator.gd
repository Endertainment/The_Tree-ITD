class_name RangeIndicator
extends Node2D
## Single shared ring that shows the selected tower's range.
##
## One node draws for every tower, so selecting does not add nodes or draw
## items. The ring is dashed: the gaps keep the playfield readable.

const SEGMENTS := 72
const COLOR := Color(0.949, 0.757, 0.306, 0.55)

var _radius := 0.0
var _active := false


## Positions the ring on `tower` and shows its current range.
func show_for(tower: Tower) -> void:
	var stats: TowerLevel = tower.get_stats() if tower != null else null
	if stats == null:
		return
	global_position = tower.global_position
	_radius = stats.range
	_active = true
	visible = true
	queue_redraw()


## Hides the ring when nothing is selected.
func hide_ring() -> void:
	_active = false
	visible = false


func _draw() -> void:
	if not _active:
		return
	for index in SEGMENTS:
		if index % 2 == 0:
			continue
		var start := TAU * float(index) / float(SEGMENTS)
		var end := TAU * float(index + 1) / float(SEGMENTS)
		draw_arc(Vector2.ZERO, _radius, start, end, 3, COLOR, 2.0, true)
