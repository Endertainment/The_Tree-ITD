extends SceneTree
## Generates the Android launcher icons and the boot splash from `icon.svg`.
##
## Run:
##   godot --headless --path . --script res://tools/gen_android_icons.gd
##
## Output:
##   assets/art/android/icon_main_192.png              (legacy launcher icon)
##   assets/art/android/icon_adaptive_foreground_432.png
##   assets/art/android/icon_adaptive_background_432.png
##   assets/art/splash.png                              (1080x1920)
##
## The adaptive foreground keeps the mark inside Android's 66% safe zone so the
## launcher mask never clips the canopy.

const ICON_SVG := "res://icon.svg"
const OUT_DIR := "res://assets/art/android"
const SPLASH_PATH := "res://assets/art/splash.png"
const BACKGROUND := Color("#1d2a1f")
const GLOW := Color("#2f4a30")
const SPLASH_SIZE := Vector2i(1080, 1920)
const ADAPTIVE_SIZE := 432
const ADAPTIVE_SAFE_RATIO := 0.66
const MAIN_SIZE := 192

var _wrote := 0


func _initialize() -> void:
	var svg := _read_svg()
	if svg.is_empty():
		push_error("[gen_icons] cannot read %s" % ICON_SVG)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# Legacy launcher icon: the mark on the brand background at 192 px.
	var mark := _render(svg, MAIN_SIZE)
	_save(_compose(mark, BACKGROUND, MAIN_SIZE), OUT_DIR + "/icon_main_192.png")

	# Adaptive background: a flat brand-colour plate.
	var plate := Image.create(ADAPTIVE_SIZE, ADAPTIVE_SIZE, false, Image.FORMAT_RGBA8)
	plate.fill(BACKGROUND)
	_save(plate, OUT_DIR + "/icon_adaptive_background_432.png")

	# Adaptive foreground: transparent, mark inside the safe zone.
	var safe := int(round(float(ADAPTIVE_SIZE) * ADAPTIVE_SAFE_RATIO))
	var foreground := Image.create(ADAPTIVE_SIZE, ADAPTIVE_SIZE, false, Image.FORMAT_RGBA8)
	foreground.fill(Color(0.0, 0.0, 0.0, 0.0))
	var inset := (ADAPTIVE_SIZE - safe) / 2
	foreground.blend_rect(
		_render(svg, safe),
		Rect2i(0, 0, safe, safe),
		Vector2i(inset, inset)
	)
	_save(foreground, OUT_DIR + "/icon_adaptive_foreground_432.png")

	_save(_make_splash(svg), SPLASH_PATH)

	print("[gen_icons] wrote %d files" % _wrote)
	quit(0)


func _read_svg() -> String:
	var file := FileAccess.open(ICON_SVG, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


## Rasterizes the SVG to an exact `size` square.
func _render(svg: String, size: int) -> Image:
	var image := Image.new()
	var scale := float(size) / 512.0
	var err := image.load_svg_from_string(svg, scale)
	if err != OK:
		push_error("[gen_icons] SVG rasterize failed (%d)" % err)
		return Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.convert(Image.FORMAT_RGBA8)
	if image.get_width() != size or image.get_height() != size:
		image.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return image


func _compose(foreground: Image, background: Color, size: int) -> Image:
	var canvas := Image.create(size, size, false, Image.FORMAT_RGBA8)
	canvas.fill(background)
	canvas.blend_rect(foreground, Rect2i(0, 0, size, size), Vector2i.ZERO)
	return canvas


## 1080x1920 boot splash: vignetted brand background with the mark centred.
func _make_splash(svg: String) -> Image:
	var image := Image.create(SPLASH_SIZE.x, SPLASH_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(BACKGROUND)
	var center := Vector2(SPLASH_SIZE) * 0.5
	var max_radius := center.y
	var half_width := float(SPLASH_SIZE.x) * 0.5
	for y in SPLASH_SIZE.y:
		for x in SPLASH_SIZE.x:
			var distance := Vector2(x, y).distance_to(center) / max_radius
			var glow := clampf(1.0 - distance, 0.0, 1.0)
			var edge := clampf(absf(float(x) - half_width) / half_width, 0.0, 1.0)
			var tint := BACKGROUND.lerp(GLOW, glow * 0.35 * (1.0 - edge * 0.4))
			image.set_pixel(x, y, tint)
	var mark_size := 620
	var mark := _render(svg, mark_size)
	var origin := Vector2i(
		(SPLASH_SIZE.x - mark_size) / 2,
		int(center.y - float(mark_size) * 0.62)
	)
	image.blend_rect(mark, Rect2i(0, 0, mark_size, mark_size), origin)
	return image


func _save(image: Image, path: String) -> void:
	var err := image.save_png(path)
	if err != OK:
		push_error("[gen_icons] save failed (%d): %s" % [err, path])
		return
	_wrote += 1
	print("[gen_icons] %-46s %dx%d" % [path, image.get_width(), image.get_height()])
