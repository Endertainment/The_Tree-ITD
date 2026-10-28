class_name UISkin
extends RefCounted
## Optional skin for the UI theme.
##
## Every file is optional: a missing texture leaves the themed `StyleBoxFlat`
## in place, so the UI keeps working while art arrives one piece at a time.
##
## Files live in `res://assets/art/ui/`:
##   button_<state>.png          all buttons (normal/hover/pressed/disabled)
##   button_primary_<state>.png  PrimaryButton override (the yellow CTA)
##   button_danger_<state>.png   DangerButton override
##   tab_<state>.png             bottom tab buttons
##   panel.png                   default 9-patch panel
##   panel_<slot>.png            per-context panel: card, sheet, pause, results,
##                               modal, toast, tower_card (fallback: panel.png)
##   icon_pause.png, icon_speed.png, icon_close.png
##   check_on.png, check_off.png (CheckButton/CheckBox)
##   slider_bg.png, slider_fill.png, slider_grabber.png
##   bar_<slot>_bg.png, bar_<slot>_fill.png (hp, profile, boss, mission, wave)
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
	_apply_panel_slots(theme)
	_apply_toggles(theme)
	_apply_slider(theme)


## Applies a per-context panel texture to one node. Falls back to
## `panel_<slot>.png`, then `panel.png`, then the themed flat style.
static func apply_panel(panel: Control, slot: String) -> void:
	if panel == null:
		return
	var texture := ArtLibrary.file("ui", "panel_%s" % slot)
	if texture == null:
		texture = ArtLibrary.file("ui", "panel")
	if texture == null:
		return
	panel.add_theme_stylebox_override("panel", _nine_patch(texture))


## Puts an optional texture icon on a button (keeps its text).
static func apply_icon(button: Button, slot: String) -> void:
	if button == null:
		return
	var texture := ArtLibrary.file("ui", "icon_%s" % slot)
	if texture == null:
		return
	button.icon = texture
	button.add_theme_constant_override("icon_max_width", int(texture.get_width()))


static func _apply_panel_slots(theme: Theme) -> void:
	# `PanelCard` is the base variation used by menu cards; other slots are
	# applied per node through `apply_panel()`.
	var texture := ArtLibrary.file("ui", "panel_card")
	if texture == null:
		texture = ArtLibrary.file("ui", "panel")
	if texture != null:
		theme.set_stylebox("panel", "PanelCard", _nine_patch(texture))
		theme.set_stylebox("panel", "Panel", _nine_patch(texture))
		theme.set_stylebox("panel", "PanelContainer", _nine_patch(texture))


static func _apply_toggles(theme: Theme) -> void:
	var on := ArtLibrary.file("ui", "check_on")
	var off := ArtLibrary.file("ui", "check_off")
	if on == null and off == null:
		return
	for type: String in ["CheckBox", "CheckButton"]:
		if on != null:
			theme.set_icon("checked", type, on)
			theme.set_icon("checked_disabled", type, on)
		if off != null:
			theme.set_icon("unchecked", type, off)
			theme.set_icon("unchecked_disabled", type, off)
		# The check textures are the whole control, so no extra label icon.
		theme.set_constant("h_separation", type, 12)


static func _apply_slider(theme: Theme) -> void:
	var background := ArtLibrary.file("ui", "slider_bg")
	var fill := ArtLibrary.file("ui", "slider_fill")
	var grabber := ArtLibrary.file("ui", "slider_grabber")
	if background != null:
		var style := StyleBoxTexture.new()
		style.texture = background
		style.content_margin_top = 10.0
		style.content_margin_bottom = 10.0
		theme.set_stylebox("slider", "HSlider", style)
	if fill != null:
		var style := StyleBoxTexture.new()
		style.texture = fill
		theme.set_stylebox("grabber_area", "HSlider", style)
		theme.set_stylebox("grabber_area_highlight", "HSlider", style)
	if grabber != null:
		theme.set_icon("grabber", "HSlider", grabber)
		theme.set_icon("grabber_highlight", "HSlider", grabber)


static func _apply_button(theme: Theme, type: String) -> void:
	var prefix := _button_prefix(type)
	for state: String in STATES:
		var texture := ArtLibrary.file("ui", "%s_%s" % [prefix, state])
		if texture == null and prefix != "button":
			texture = ArtLibrary.file("ui", "button_%s" % state)
		if texture == null:
			continue
		var style := _nine_patch(texture)
		# The artwork itself stays put; the label moves up on hover and down
		# when the button is held, which is what reads as "pressed".
		match state:
			"hover":
				style.content_margin_top = 6.0
			"pressed":
				style.content_margin_bottom = 6.0
		theme.set_stylebox(state, type, style)


## Content-sized buttons instead of full-panel width. Only buttons stacked in a
## VBox are affected; rows and dialogs keep their layout.
static func limit_widths(root: Node) -> void:
	if root == null:
		return
	for node: Node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null:
			continue
		var parent := button.get_parent()
		if parent is VBoxContainer and not button.flat:
			button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


## Per-card background: `ui/tower_card_<id>.png`, falling back to
## `ui/panel_tower_card.png`, then leaving the themed button as-is.
static func apply_card_background(button: Button, slot: String) -> void:
	if button == null:
		return
	var texture := ArtLibrary.file("ui", "tower_card_%s" % slot)
	if texture == null:
		texture = ArtLibrary.file("ui", "panel_tower_card")
	if texture == null:
		return
	var style := _nine_patch(texture)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("disabled", style)


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
