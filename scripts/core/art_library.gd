class_name ArtLibrary
extends RefCounted
## Optional painted art, addressed by file path and cached.
##
## Every game object draws itself procedurally and asks this class for a texture
## first. A missing file returns `null`, so the procedural drawing stays as the
## working fallback and art can be added one file at a time.
##
## Naming conventions (all paths relative to `res://assets/art/`):
##   enemies/<id>.png            orc_grunt, orc_runner, orc_brute, orc_warlord
##   towers/<id>_l<level>.png    archer_tower_l2, frost_spire_l3, ...
##   towers/<id>.png             fallback for every level
##   projectiles/<kind>.png      arrow, frost_bolt, ballista_bolt
##   archers/archer.png
##   battle/build_pad.png
##   battle/arena_ground.png     handled by `arena.gd`
##   tree/tree_body.png          handled by `core.gd`

const ROOT := "res://assets/art"

static var _cache: Dictionary = {}


## Returns the texture at `path`, or null when the file does not exist.
static func texture(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var result: Texture2D = null
	if ResourceLoader.exists(path):
		result = load(path) as Texture2D
	_cache[path] = result
	return result


## `res://assets/art/<folder>/<file>.png`.
static func file(folder: String, file_name: String) -> Texture2D:
	return texture("%s/%s/%s.png" % [ROOT, folder, file_name])


## Enemy art by enemy id (`orc_grunt` -> `enemies/orc_grunt.png`).
static func unit(enemy_id: String) -> Texture2D:
	return file("enemies", enemy_id)


## Tower art for one level, falling back to the level-less file.
static func tower(tower_id: String, level: int) -> Texture2D:
	var per_level := file("towers", "%s_l%d" % [tower_id, level])
	return per_level if per_level != null else file("towers", tower_id)


## Projectile art by kind name.
static func projectile(kind_name: String) -> Texture2D:
	return file("projectiles", kind_name)


## Draws `texture` centred on `center` at exactly `target_size`.
static func draw_centered(
	canvas: CanvasItem,
	texture: Texture2D,
	center: Vector2,
	target_size: Vector2,
	modulate: Color = Color.WHITE
) -> void:
	canvas.draw_texture_rect(texture, Rect2(center - target_size * 0.5, target_size), false, modulate)


## Draws `texture` at `center` with `height`, preserving the art's aspect ratio.
static func draw_fitted_height(
	canvas: CanvasItem,
	texture: Texture2D,
	center: Vector2,
	height: float,
	modulate: Color = Color.WHITE
) -> void:
	var texture_size := texture.get_size()
	var aspect := texture_size.x / maxf(1.0, texture_size.y)
	draw_centered(canvas, texture, center, Vector2(height * aspect, height), modulate)
