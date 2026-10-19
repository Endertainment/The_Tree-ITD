class_name SafeArea
extends MarginContainer
## Pads a container by the device safe-area insets so nothing lands under a
## notch, punch-hole or rounded corner.
##
## On desktop the computed insets are zero, so this is a no-op there. The
## inset maths is a pure static function so it can be unit-tested without a
## notched device.

@export var pad_top := true
@export var pad_bottom := true
@export var pad_sides := true

const _INSET_KEYS := ["margin_top", "margin_right", "margin_bottom", "margin_left"]

## Scene-authored margins, captured once so insets are added to them rather
## than replacing the layout's own padding.
var _base_margins := {}


func _ready() -> void:
	set_process(false)
	for key: String in _INSET_KEYS:
		_base_margins[key] = get_theme_constant(key)
	if not get_viewport().size_changed.is_connected(apply_insets):
		get_viewport().size_changed.connect(apply_insets)
	apply_insets()


## Recomputes and applies the four margin overrides.
func apply_insets() -> void:
	var insets := get_safe_insets()
	var offsets := [
		int(round(insets.x)) if pad_top else 0,
		int(round(insets.y)) if pad_sides else 0,
		int(round(insets.z)) if pad_bottom else 0,
		int(round(insets.w)) if pad_sides else 0,
	]
	for index in _INSET_KEYS.size():
		var key: String = _INSET_KEYS[index]
		add_theme_constant_override(key, int(_base_margins.get(key, 0)) + offsets[index])


## Current safe-area insets in viewport pixels as (top, right, bottom, left).
func get_safe_insets() -> Vector4:
	if not is_inside_tree():
		return Vector4.ZERO
	return insets_for(
		DisplayServer.window_get_size(),
		DisplayServer.get_display_safe_area(),
		get_viewport_rect().size,
		OS.has_feature("mobile")
	)


## Pure inset maths, split out so tests can drive it with fabricated devices.
##
## `mobile` gates the whole computation: desktop windows report the monitor as
## the safe area, which would otherwise produce large bogus insets.
static func insets_for(
	window_size: Vector2i,
	safe_rect: Rect2i,
	view_size: Vector2,
	mobile: bool
) -> Vector4:
	if not mobile:
		return Vector4.ZERO
	if window_size.x <= 0 or window_size.y <= 0:
		return Vector4.ZERO
	if safe_rect.size.x <= 0 or safe_rect.size.y <= 0:
		return Vector4.ZERO
	if safe_rect.size.x >= window_size.x and safe_rect.size.y >= window_size.y:
		return Vector4.ZERO
	var scale_x := view_size.x / float(window_size.x)
	var scale_y := view_size.y / float(window_size.y)
	var top := maxf(0.0, float(safe_rect.position.y) * scale_y)
	var left := maxf(0.0, float(safe_rect.position.x) * scale_x)
	var right := maxf(0.0, float(window_size.x - safe_rect.end.x) * scale_x)
	var bottom := maxf(0.0, float(window_size.y - safe_rect.end.y) * scale_y)
	return Vector4(top, right, bottom, left)
