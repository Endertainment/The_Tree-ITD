extends MenuScreen
## Settings tab: audio, haptics, language, quality, reset and legal links.

const PRIVACY_URL := "https://example.com/the-tree/privacy"
const BOOT_SCENE := "res://scenes/boot/Boot.tscn"
const VERSION_SETTING := "application/config/version"

@onready var _header: Label = %Header
@onready var _music_label: Label = %MusicLabel
@onready var _music_slider: HSlider = %MusicSlider
@onready var _music_value: Label = %MusicValue
@onready var _sfx_label: Label = %SfxLabel
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _sfx_value: Label = %SfxValue
@onready var _haptics_label: Label = %HapticsLabel
@onready var _haptics_toggle: CheckButton = %HapticsToggle
@onready var _damage_label: Label = %DamageNumbersLabel
@onready var _damage_toggle: CheckButton = %DamageNumbersToggle
@onready var _focus_label: Label = %FocusLabel
@onready var _focus_toggle: CheckButton = %FocusToggle
@onready var _replay_button: Button = %ReplayButton
@onready var _language_label: Label = %LanguageLabel
@onready var _language_option: OptionButton = %LanguageOption
@onready var _quality_label: Label = %QualityLabel
@onready var _quality_option: OptionButton = %QualityOption
@onready var _quality_hint: Label = %QualityHint
@onready var _reset_button: Button = %ResetButton
@onready var _privacy_button: Button = %PrivacyButton
@onready var _version: Label = %Version
@onready var _credits: Label = %Credits

var _updating := false


func _ready() -> void:
	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_haptics_toggle.toggled.connect(_on_haptics_toggled)
	_damage_toggle.toggled.connect(_on_damage_numbers_toggled)
	_focus_toggle.toggled.connect(_on_focus_mute_toggled)
	_replay_button.pressed.connect(_on_replay_tutorial)
	_language_option.item_selected.connect(_on_language_selected)
	_quality_option.item_selected.connect(_on_quality_selected)
	_reset_button.pressed.connect(_on_reset_pressed)
	_privacy_button.pressed.connect(_on_privacy_pressed)


func refresh() -> void:
	_updating = true
	_header.text = Loc.t_key("SETTINGS_HEADER")
	_music_label.text = Loc.t_key("SET_MUSIC")
	_sfx_label.text = Loc.t_key("SET_SFX")
	_haptics_label.text = Loc.t_key("SET_HAPTICS")
	_damage_label.text = Loc.t_key("SET_DAMAGE_NUMBERS")
	_focus_label.text = Loc.t_key("SET_MUTE_FOCUS")
	_replay_button.text = Loc.t_key("SET_REPLAY_TUTORIAL")
	_language_label.text = Loc.t_key("SET_LANGUAGE")
	_quality_label.text = Loc.t_key("SET_QUALITY")
	_quality_hint.text = Loc.t_key("SET_QUALITY_HINT")
	_reset_button.text = Loc.t_key("SET_RESET")
	_privacy_button.text = Loc.t_key("SET_PRIVACY")
	_credits.text = Loc.t_key("SET_CREDITS")
	_version.text = Loc.t_key("SET_VERSION", {
		"version": str(ProjectSettings.get_setting(VERSION_SETTING, "0.1.0")),
	})
	var music := float(GameState.get_setting("music", 0.8))
	var sfx := float(GameState.get_setting("sfx", 1.0))
	_music_slider.set_value_no_signal(music * 100.0)
	_sfx_slider.set_value_no_signal(sfx * 100.0)
	_music_value.text = Loc.format_percent(music * 100.0)
	_sfx_value.text = Loc.format_percent(sfx * 100.0)
	_haptics_toggle.set_pressed_no_signal(bool(GameState.get_setting("haptics", true)))
	_damage_toggle.set_pressed_no_signal(bool(GameState.get_setting("show_damage_numbers", true)))
	_focus_toggle.set_pressed_no_signal(bool(GameState.get_setting("mute_on_focus_loss", true)))
	_populate_languages()
	_populate_quality()
	_updating = false


func _populate_languages() -> void:
	_language_option.clear()
	_language_option.add_item(Loc.t_key("SET_LANGUAGE_SYSTEM"))
	_language_option.add_item(Loc.t_key("SET_LANGUAGE_EN"))
	_language_option.add_item(Loc.t_key("SET_LANGUAGE_UK"))
	var current := Loc.get_locale()
	if current == OS.get_locale_language():
		_language_option.select(0)
	elif current == "uk":
		_language_option.select(2)
	else:
		_language_option.select(1)


func _populate_quality() -> void:
	_quality_option.clear()
	_quality_option.add_item(Loc.t_key("SET_QUALITY_HIGH"))
	_quality_option.add_item(Loc.t_key("SET_QUALITY_LOW"))
	_quality_option.select(1 if GameState.is_low_quality() else 0)


func _on_music_changed(value: float) -> void:
	if _updating:
		return
	AudioManager.set_bus_volume(AudioManager.MUSIC_BUS, value / 100.0)
	_music_value.text = Loc.format_percent(value)


func _on_sfx_changed(value: float) -> void:
	if _updating:
		return
	AudioManager.set_bus_volume(AudioManager.SFX_BUS, value / 100.0)
	AudioManager.set_bus_volume(AudioManager.UI_BUS, value / 100.0)
	_sfx_value.text = Loc.format_percent(value)


func _on_haptics_toggled(pressed: bool) -> void:
	if _updating:
		return
	GameState.set_setting("haptics", pressed)


func _on_damage_numbers_toggled(pressed: bool) -> void:
	if _updating:
		return
	GameState.set_setting("show_damage_numbers", pressed)


func _on_focus_mute_toggled(pressed: bool) -> void:
	if _updating:
		return
	GameState.set_setting("mute_on_focus_loss", pressed)
	AudioManager.apply_settings()


## Clears the tutorial flag; the hints return on the next battle.
func _on_replay_tutorial() -> void:
	AudioManager.play_ui("ui_tap")
	GameState.set_flag("tutorial_done", false)
	main_menu.show_toast(Loc.t_key("SET_REPLAY_TOAST"))


func _on_language_selected(index: int) -> void:
	if _updating:
		return
	var target := "en"
	match index:
		0:
			target = OS.get_locale_language()
		1:
			target = "en"
		2:
			target = "uk"
	Loc.set_locale(target)
	refresh()


func _on_quality_selected(index: int) -> void:
	if _updating:
		return
	GameState.set_setting("quality", "low" if index == 1 else "high")
	refresh()


func _on_reset_pressed() -> void:
	AudioManager.play_ui("ui_click")
	main_menu.open_modal(
		Loc.t_key("SET_RESET_TITLE"),
		Loc.t_key("SET_RESET_BODY"),
		"SET_RESET_CONFIRM",
		"COMMON_CANCEL",
		_confirm_reset
	)


func _confirm_reset() -> void:
	main_menu.open_modal(
		Loc.t_key("SET_RESET_FINAL_TITLE"),
		Loc.t_key("SET_RESET_FINAL_BODY"),
		"SET_RESET_FINAL_CONFIRM",
		"COMMON_CANCEL",
		_do_reset
	)


func _do_reset() -> void:
	SpeedService.reset()
	get_tree().paused = false
	GameState.reset_progress()
	Loc.set_locale("en")
	SceneRouter.goto(BOOT_SCENE, true)


func _on_privacy_pressed() -> void:
	AudioManager.play_ui("ui_click")
	var error := OS.shell_open(PRIVACY_URL)
	if error != OK:
		main_menu.show_toast(Loc.t_key("SET_PRIVACY_FAILED"))
