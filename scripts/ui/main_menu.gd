extends Control
## Stage 2 menu: currency HUD, BATTLE entry point, language toggle.
##
## Signal connections live in code because the labels they refresh do not exist
## in the scene as signal sources.

const BATTLE_SCENE := "res://scenes/battle/Battle.tscn"
const VERSION_SETTING := "application/config/version"
const BASE_MARGIN := 32
const SIDE_MARGIN := 40

@onready var _safe_area: MarginContainer = %SafeArea
@onready var _gold_label: Label = %GoldLabel
@onready var _gems_label: Label = %GemsLabel
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _battle_button: Button = %BattleButton
@onready var _lang_button: Button = %LangButton
@onready var _version_label: Label = %VersionLabel


func _ready() -> void:
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.gems_changed.connect(_on_gems_changed)
	EventBus.language_changed.connect(_on_language_changed)
	_battle_button.pressed.connect(_on_battle_pressed)
	_lang_button.pressed.connect(_on_lang_pressed)
	get_viewport().size_changed.connect(_apply_safe_area)
	_refresh_texts()
	_refresh_currencies()
	_apply_safe_area()
	Analytics.set_screen("main_menu")


func _refresh_texts() -> void:
	_title.text = Loc.t_key("MENU_TITLE")
	_subtitle.text = Loc.t_key("MENU_SUBTITLE")
	_battle_button.text = Loc.t_key("MENU_BATTLE")
	_lang_button.text = Loc.get_locale().to_upper()
	_version_label.text = Loc.t_key("VERSION_LABEL", {
		"version": str(ProjectSettings.get_setting(VERSION_SETTING, "0.1.0")),
	})


func _refresh_currencies() -> void:
	_gold_label.text = "%s  %s" % [Loc.t_key("CURRENCY_GOLD"), Loc.format_number(GameState.get_gold())]
	_gems_label.text = "%s  %s" % [Loc.t_key("CURRENCY_GEMS"), Loc.format_number(GameState.get_gems())]


func _apply_safe_area() -> void:
	var viewport_size := get_viewport_rect().size
	var window_size := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	var scale_y := 1.0
	if window_size.y > 0:
		scale_y = viewport_size.y / float(window_size.y)
	var top_inset := int(maxf(0.0, float(safe.position.y) * scale_y))
	var bottom_inset := int(maxf(0.0, float(window_size.y - safe.end.y) * scale_y))
	_safe_area.add_theme_constant_override("margin_top", BASE_MARGIN + top_inset)
	_safe_area.add_theme_constant_override("margin_bottom", BASE_MARGIN + bottom_inset)
	_safe_area.add_theme_constant_override("margin_left", SIDE_MARGIN)
	_safe_area.add_theme_constant_override("margin_right", SIDE_MARGIN)


func _on_gold_changed(_amount: int) -> void:
	_refresh_currencies()


func _on_gems_changed(_amount: int) -> void:
	_refresh_currencies()


func _on_language_changed(_locale: String) -> void:
	_refresh_texts()
	_refresh_currencies()


func _on_battle_pressed() -> void:
	AudioManager.play_ui("ui_click")
	SceneRouter.goto(BATTLE_SCENE)


func _on_lang_pressed() -> void:
	AudioManager.play_ui("ui_click")
	var next_locale := "uk" if Loc.get_locale() == "en" else "en"
	Loc.set_locale(next_locale)
