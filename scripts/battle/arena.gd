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

## Optional painted ground. Drop a PNG at this path (1024x1024 is the expected
## canvas) and it replaces the painted grass, roots and stones; delete the file
## and the procedural arena comes back. It is mapped into the 500 px playfield
## circle, so the artwork should be authored as a full top-down arena.
const GROUND_TEXTURE_PATH := "res://assets/art/battle/arena_ground.png"
const GROUND_TEXTURE_SEGMENTS := 96

## Optional full-screen battle backdrop drawn behind the arena (sky, distant
## forest, ...). Any aspect ratio works: it is scaled to cover the viewport and
## the overflow is cropped. Delete the file to get the flat dark background.
const BACKGROUND_TEXTURE_PATH := "res://assets/art/battle/battle_background.png"

## Assigned automatically from `GROUND_TEXTURE_PATH` when the file exists; the
## export lets a different texture be set per instance in the inspector.
@export var ground_texture: Texture2D
## Assigned automatically from `BACKGROUND_TEXTURE_PATH` when it exists.
@export var background_texture: Texture2D


func _ready() -> void:
	if ground_texture == null and ResourceLoader.exists(GROUND_TEXTURE_PATH):
		ground_texture = load(GROUND_TEXTURE_PATH) as Texture2D
	if background_texture == null and ResourceLoader.exists(BACKGROUND_TEXTURE_PATH):
		background_texture = load(BACKGROUND_TEXTURE_PATH) as Texture2D
	queue_redraw()


func _draw() -> void:
	var view_size := get_viewport_rect().size
	if background_texture != null:
		_draw_background_texture(view_size)
	else:
		draw_rect(Rect2(Vector2.ZERO, view_size), BACKGROUND)

	if ground_texture != null:
		_draw_ground_texture()
	else:
		draw_circle(Battle.CENTER, Battle.ARENA_RADIUS, PLAYFIELD)
		draw_circle(Battle.CENTER, Battle.ARENA_RADIUS - 58.0, PLAYFIELD_INNER)
		_draw_roots()
		_draw_grass_and_stones()

	_draw_vignette()

	draw_arc(Battle.CENTER, Battle.ARENA_RADIUS, 0.0, TAU, 96, BOUNDARY, 6.0, true)
	draw_arc(Battle.CENTER, Battle.ARENA_RADIUS - 10.0, 0.0, TAU, 96, Color(0.95, 0.76, 0.31, 0.22), 2.0, true)


## Scales the backdrop to cover the viewport, centred, cropping the overflow.
func _draw_background_texture(view_size: Vector2) -> void:
	var texture_size := background_texture.get_size()
	var scale := maxf(view_size.x / texture_size.x, view_size.y / texture_size.y)
	var draw_size := texture_size * scale
	var top_left := (view_size - draw_size) * 0.5
	draw_texture_rect(background_texture, Rect2(top_left, draw_size), false)


## Maps the texture onto the playfield circle with a triangle fan, so square
## artwork never shows its corners outside the arena.
func _draw_ground_texture() -> void:
	var texture_size := ground_texture.get_size()
	var side := minf(texture_size.x, texture_size.y)
	# `draw_polygon` UVs are normalised (0..1), not texture pixels. The centre
	# square of a non-square image is mapped to the circle.
	var uv_scale := Vector2(side, side) / texture_size
	var uv_origin := (texture_size - Vector2(side, side)) * 0.5 / texture_size

	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	points.resize(GROUND_TEXTURE_SEGMENTS)
	uvs.resize(GROUND_TEXTURE_SEGMENTS)
	for index in GROUND_TEXTURE_SEGMENTS:
		var angle := TAU * float(index) / float(GROUND_TEXTURE_SEGMENTS)
		var direction := Vector2(cos(angle), sin(angle))
		points[index] = Battle.CENTER + direction * Battle.ARENA_RADIUS
		uvs[index] = uv_origin + (direction * 0.5 + Vector2(0.5, 0.5)) * uv_scale

	var colors := PackedColorArray()
	colors.resize(GROUND_TEXTURE_SEGMENTS)
	colors.fill(Color.WHITE)
	draw_polygon(points, colors, uvs, ground_texture)


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
