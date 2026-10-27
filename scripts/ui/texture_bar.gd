class_name TextureBar
extends ProgressBar
## Progress bar that paints optional art and *cuts* the fill instead of
## stretching it. Attach to an existing `ProgressBar`; `slot` picks the files:
##
##   assets/art/ui/bar_<slot>_bg.png
##   assets/art/ui/bar_<slot>_fill.png
##
## Slots: hp, profile, boss, mission, wave. Missing files fall back to
## `hp_bar_bg.png` / `hp_bar_fill.png`, and if neither exists the normal themed
## ProgressBar is left untouched.

@export var slot := "hp"
## Draw a flat fallback bar when no art exists (used by the wave bar).
@export var draw_fallback := false

var _background: Texture2D
var _fill: Texture2D


func _ready() -> void:
	_background = ArtLibrary.file("ui", "bar_%s_bg" % slot)
	_fill = ArtLibrary.file("ui", "bar_%s_fill" % slot)
	if _background == null:
		_background = ArtLibrary.file("ui", "hp_bar_bg")
	if _fill == null:
		_fill = ArtLibrary.file("ui", "hp_bar_fill")
	if _background == null and _fill == null and not draw_fallback:
		return
	show_percentage = false
	add_theme_stylebox_override("background", StyleBoxEmpty.new())
	add_theme_stylebox_override("fill", StyleBoxEmpty.new())
	value_changed.connect(func(_value: float) -> void: queue_redraw())
	resized.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if _background != null:
		draw_texture_rect(_background, rect, false)
	elif draw_fallback:
		draw_rect(rect, Color(0.04, 0.06, 0.04, 0.85))
		draw_rect(rect, Color(0.91, 0.85, 0.66, 0.5), false, 2.0)
	if _fill == null and not draw_fallback:
		return
	var ratio := 0.0
	if max_value > 0.0:
		ratio = clampf(value / max_value, 0.0, 1.0)
	if ratio <= 0.0:
		return
	if _fill == null:
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * ratio, size.y)), Color(0.49, 0.78, 0.31))
		return
	var texture_size := _fill.get_size()
	var source := Rect2(Vector2.ZERO, Vector2(texture_size.x * ratio, texture_size.y))
	var target := Rect2(Vector2.ZERO, Vector2(size.x * ratio, size.y))
	draw_texture_rect_region(_fill, target, source)
