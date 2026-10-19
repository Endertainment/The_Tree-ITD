class_name Arena
extends Node2D
## Static battle backdrop. Everything is drawn in one `_draw()` call at load:
## grass field, darker outer ring, golden boundary, roots and stones.

const BACKGROUND := Color("#101a12")
const PLAYFIELD := Color("#26381f")
const PLAYFIELD_INNER := Color("#2d4124")
const BOUNDARY := Color("#f2c14e")
const ROOT := Color("#4a2f1b")
const STONE := Color("#55604c")

const VIGNETTE_STEPS := 16
const STONE_COUNT := 42
const GRASS_COUNT := 90
const SCENE_SEED := 20261019


func _draw() -> void:
	var view_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view_size), BACKGROUND)

	draw_circle(Battle.CENTER, Battle.ARENA_RADIUS, PLAYFIELD)
	draw_circle(Battle.CENTER, Battle.ARENA_RADIUS - 58.0, PLAYFIELD_INNER)

	_draw_vignette()
	_draw_roots()
	_draw_grass_and_stones()

	draw_arc(Battle.CENTER, Battle.ARENA_RADIUS, 0.0, TAU, 96, BOUNDARY, 6.0, true)
	draw_arc(Battle.CENTER, Battle.ARENA_RADIUS - 10.0, 0.0, TAU, 96, Color(0.95, 0.76, 0.31, 0.22), 2.0, true)


func _draw_vignette() -> void:
	for index in VIGNETTE_STEPS:
		var t := float(index) / float(VIGNETTE_STEPS - 1)
		var radius := Battle.ARENA_RADIUS + 18.0 + t * 430.0
		var alpha := 0.04 + t * 0.24
		draw_arc(Battle.CENTER, radius, 0.0, TAU, 96, Color(0.02, 0.03, 0.02, alpha), 32.0)


func _draw_roots() -> void:
	var roots := [
		PackedVector2Array([
			Vector2(120.0, 1320.0), Vector2(250.0, 1220.0),
			Vector2(320.0, 1080.0), Vector2(430.0, 1010.0),
		]),
		PackedVector2Array([
			Vector2(960.0, 520.0), Vector2(860.0, 610.0),
			Vector2(810.0, 730.0), Vector2(700.0, 790.0),
		]),
		PackedVector2Array([
			Vector2(170.0, 540.0), Vector2(280.0, 640.0),
			Vector2(330.0, 760.0), Vector2(430.0, 820.0),
		]),
		PackedVector2Array([
			Vector2(900.0, 1290.0), Vector2(800.0, 1200.0),
			Vector2(760.0, 1090.0), Vector2(650.0, 1030.0),
		]),
	]
	for points: PackedVector2Array in roots:
		draw_polyline(points, ROOT, 15.0, true)
		draw_polyline(points, ROOT.lightened(0.08), 6.0, true)


func _draw_grass_and_stones() -> void:
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = SCENE_SEED

	for _index in GRASS_COUNT:
		var angle := local_rng.randf_range(0.0, TAU)
		var distance := local_rng.randf_range(95.0, Battle.ARENA_RADIUS - 24.0)
		var position := Battle.CENTER + Vector2(cos(angle), sin(angle)) * distance
		var length := local_rng.randf_range(6.0, 13.0)
		draw_line(
			position,
			position + Vector2(0.0, -length),
			Color(0.28, 0.42, 0.2, 0.55),
			2.0
		)

	for _index in STONE_COUNT:
		var angle := local_rng.randf_range(0.0, TAU)
		var distance := local_rng.randf_range(105.0, Battle.ARENA_RADIUS - 20.0)
		var position := Battle.CENTER + Vector2(cos(angle), sin(angle)) * distance
		var radius := local_rng.randf_range(3.0, 8.0)
		draw_circle(position, radius, STONE)
