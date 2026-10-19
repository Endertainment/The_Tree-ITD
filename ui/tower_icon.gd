class_name TowerIcon
extends Control
## Miniature code-drawn tower silhouette for build cards and the tower sheet.
##
## Placeholder art only: it reuses the same colour language as `Tower._draw()`
## so a card and the thing it builds read as the same object.

var _silhouette := "archer"
var _level := 1
var _base := Color("#7a4a2b")
var _accent := Color("#f2c14e")


## Paints a silhouette at `level` with the tower's colours.
func setup(silhouette: String, level: int, base: Color, accent: Color) -> void:
	_silhouette = silhouette
	_level = maxi(1, level)
	_base = base
	_accent = accent
	queue_redraw()


func _draw() -> void:
	var scale_factor := minf(size.x, size.y) / 120.0
	if scale_factor <= 0.0:
		return
	var center := size * 0.5
	draw_set_transform(center, 0.0, Vector2(scale_factor, scale_factor))

	draw_circle(Vector2(0.0, 22.0), 42.0, Color(0.02, 0.03, 0.02, 0.35))
	draw_circle(Vector2.ZERO, 34.0, _base.darkened(0.2))

	match _silhouette:
		"frost":
			draw_colored_polygon(
				PackedVector2Array([
					Vector2(-22.0, 8.0), Vector2(22.0, 8.0), Vector2(0.0, -46.0),
				]),
				_base.lightened(0.1)
			)
			draw_colored_polygon(
				PackedVector2Array([
					Vector2(0.0, -54.0), Vector2(10.0, -34.0), Vector2(0.0, -18.0), Vector2(-10.0, -34.0),
				]),
				_accent
			)
		"ballista":
			draw_line(Vector2(-30.0, -16.0), Vector2(30.0, -16.0), Color("#5a3a22"), 7.0)
			draw_line(Vector2(-30.0, -16.0), Vector2(-12.0, 0.0), _accent.darkened(0.3), 3.0)
			draw_line(Vector2(30.0, -16.0), Vector2(12.0, 0.0), _accent.darkened(0.3), 3.0)
			draw_line(Vector2(-18.0, -22.0), Vector2(26.0, -22.0), Color("#2a1d12"), 6.0)
			draw_colored_polygon(
				PackedVector2Array([
					Vector2(34.0, -22.0), Vector2(22.0, -30.0), Vector2(22.0, -14.0),
				]),
				_accent
			)
		_:
			draw_rect(Rect2(-12.0, -18.0, 24.0, 40.0), _base.lightened(0.05))
			draw_line(Vector2(0.0, -18.0), Vector2(0.0, -34.0), Color("#5a3a22"), 3.0)
			draw_colored_polygon(
				PackedVector2Array([
					Vector2(1.0, -32.0), Vector2(1.0, -50.0), Vector2(20.0, -41.0),
				]),
				Color("#7ec850")
			)

	if _level >= 2:
		draw_arc(Vector2.ZERO, 25.0, 0.0, TAU, 28, Color(_accent.r, _accent.g, _accent.b, 0.6), 2.0, true)
	if _level >= 3:
		draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 24, Color(_accent.r, _accent.g, _accent.b, 0.8), 2.0, true)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
