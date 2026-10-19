class_name SpatialHash
extends RefCounted
## Uniform-grid broad phase for enemy separation queries.
##
## `rebuild()` clears every bucket in place (the arrays keep their capacity) and
## re-inserts the active enemies. Query callers pass a reusable output array, so
## a steady-state frame allocates nothing here.

const CELL_SIZE := 64.0

var _cells: Dictionary = {}


## Empties every bucket without discarding the bucket arrays.
func clear() -> void:
	for key in _cells:
		var bucket: Array = _cells[key]
		bucket.clear()


## Inserts `object` at `pos`.
func insert(object: Object, pos: Vector2) -> void:
	var key := _cell_of(pos)
	var bucket: Array = _cells.get(key, [])
	if not _cells.has(key):
		_cells[key] = bucket
	bucket.append(object)


## Fills `out` with every object in the cells overlapping the query circle.
## The caller still filters by exact distance; the grid is only a broad phase.
func query(pos: Vector2, radius: float, out: Array) -> void:
	out.clear()
	var min_cell := _cell_of(pos - Vector2(radius, radius))
	var max_cell := _cell_of(pos + Vector2(radius, radius))
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			var bucket: Variant = _cells.get(Vector2i(x, y), null)
			if bucket is Array:
				out.append_array(bucket)


## Number of occupied cells, for the debug overlay.
func cell_count() -> int:
	return _cells.size()


func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL_SIZE), floori(pos.y / CELL_SIZE))
