class_name UISkin
extends RefCounted
## Optional 9-patch skin for the UI theme.
##
## Every file is optional: a missing texture leaves the themed `StyleBoxFlat`
## in place, so the UI keeps working while art arrives one piece at a time.
##
## Files live in `res://assets/art/ui/`:
##   button_<state>.png          all buttons          (normal/hover/pressed/disabled)
##   button_primary_<state>.png  PrimaryButton override (the yellow CTA)
##   button_danger_<state>.png   DangerButton override
##   tab_<state>.png             bottom tab buttons
##   panel.png                   9-patch for PanelCard
##   hp_bar_bg.png, hp_bar_fill.png
##   menu_background.png         handled by `main_menu.gd`
##
## A 9-patch texture needs a corner margin; `MARGIN` is expressed in texture
## pixels and is clamped to half the texture.

const ROOT := "res://assets/art/ui"
const MARGIN := 36
const BUTTON_TYPES: Array[String] = [
	"Button", "PrimaryButton", "SecondaryButton", "DangerButton",
	"RowButton", "SegmentButton", "TabButton",
]
const STATES: Array[String] = ["normal", "hover", "pressed", "disabled"]

static var _applied := false


## Applies the skin once per process. Safe to call from every screen.
static func ensure_applied() -> void:
	if _applied:
		return
	_applied = true
	var theme: Theme = ThemeDB.get_project_theme()
	if theme == null:
		return
	for type: String in BUTTON_TYPES:
		_apply_button(theme, type)
	_apply_panel(theme, "PanelCard")
	_apply_panel(theme, "Panel")
	_apply_bar(theme)


static func _apply_button(theme: Theme, type: String) -> void:
	var prefix := _button_prefix(type)
	for state: String in STATES:
		var texture := ArtLibrary.file("ui", "%s_%s" % [prefix, state])
		if texture == null and prefix != "button":
			texture = ArtLibrary.file("ui", "button_%s" % state)
		if texture == null:
			continue
		theme.set_stylebox(state, type, _nine_patch(texture))


static func _apply_panel(theme: Theme, type: String) -> void:
	var texture := ArtLibrary.file("ui", "panel")
	if texture == null:
		return
	theme.set_stylebox("panel", type, _nine_patch(texture))


static func _apply_bar(theme: Theme) -> void:
	var background := ArtLibrary.file("ui", "hp_bar_bg")
	var fill := ArtLibrary.file("ui", "hp_bar_fill")
	if background != null:
		var style := StyleBoxTexture.new()
		style.texture = background
		theme.set_stylebox("background", "HpBar", style)
	if fill != null:
		var style := StyleBoxTexture.new()
		style.texture = fill
		theme.set_stylebox("fill", "HpBar", style)


static func _button_prefix(type: String) -> String:
	match type:
		"PrimaryButton":
			return "button_primary"
		"DangerButton":
			return "button_danger"
		"TabButton":
			return "tab"
		_:
			return "button"


static func _nine_patch(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	var size := texture.get_size()
	var margin := mini(MARGIN, int(minf(size.x, size.y) * 0.5) - 1)
	style.texture_margin_left = float(margin)
	style.texture_margin_top = float(margin)
	style.texture_margin_right = float(margin)
	style.texture_margin_bottom = float(margin)
	return style
