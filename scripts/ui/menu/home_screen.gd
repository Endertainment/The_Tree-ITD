extends MenuScreen
## Home tab: identity, run briefing, daily summary and the BATTLE entry point.
##
## The run briefing is `PreBattle`, embedded here so `Home -> BATTLE` stays one
## tap. The version label also carries the debug-only 5-tap monetization panel.

const BATTLE_SCENE := "res://scenes/battle/Battle.tscn"
const VERSION_SETTING := "application/config/version"
const DEBUG_TAP_COUNT := 5
const DEBUG_TAP_WINDOW_MS := 2000

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _best_wave: Label = %BestWaveLabel
@onready var _elf_label: Label = %ElfLabel
@onready var _elf_progress: Label = %ElfProgress
@onready var _elf_bar: ProgressBar = %ElfBar
@onready var _pre_battle: PreBattle = %PreBattle
@onready var _daily_title: Label = %DailyTitle
@onready var _daily_progress: Label = %DailyProgress
@onready var _daily_view: Button = %DailyView
@onready var _music_button: Button = %MusicButton
@onready var _version: Label = %VersionLabel

var _version_taps: Array[int] = []


func _ready() -> void:
	_pre_battle.battle_requested.connect(_on_battle_pressed)
	_daily_view.pressed.connect(_on_daily_view_pressed)
	_music_button.pressed.connect(_on_music_pressed)
	_version.gui_input.connect(_on_version_gui_input)


func refresh() -> void:
	_title.text = Loc.t_key("MENU_TITLE")
	_subtitle.text = Loc.t_key("MENU_SUBTITLE")
	_best_wave.text = Loc.t_key("HOME_BEST", {
		"wave": Loc.format_number(GameState.get_best_wave()),
	})
	var elf_level := GameState.get_elf_level()
	_elf_label.text = Loc.t_key("HOME_ELF", {"level": elf_level})
	var progress := GameState.get_elf_level_progress()
	_elf_bar.value = float(progress["percent"]) * 100.0
	if int(progress["needed"]) <= 0:
		_elf_progress.text = Loc.t_key("HOME_ELF_MAX")
	else:
		_elf_progress.text = Loc.t_key("HOME_ELF_PROGRESS", {
			"current": int(progress["current"]),
			"needed": int(progress["needed"]),
		})
	_refresh_daily()
	_daily_title.text = Loc.t_key("HOME_DAILY")
	_daily_view.text = Loc.t_key("HOME_DAILY_VIEW")
	_version.text = Loc.t_key("VERSION_LABEL", {
		"version": str(ProjectSettings.get_setting(VERSION_SETTING, "0.1.0")),
	})
	_music_button.text = Loc.t_key(
		"HOME_MUSIC_ON" if AudioManager.get_bus_volume(AudioManager.MUSIC_BUS) > 0.01 else "HOME_MUSIC_OFF"
	)
	_pre_battle.refresh()


func _refresh_daily() -> void:
	var ids := GameState.missions.get_daily_ids()
	var done := 0
	for id: String in ids:
		if GameState.missions.is_claimed(id):
			done += 1
	_daily_progress.text = Loc.t_key("HOME_DAILY_PROGRESS", {
		"done": done,
		"total": ids.size(),
	})


func _on_battle_pressed() -> void:
	SceneRouter.goto(BATTLE_SCENE)


func _on_daily_view_pressed() -> void:
	main_menu.select_tab("missions")


func _on_music_pressed() -> void:
	AudioManager.play_ui("ui_click")
	var muted := AudioManager.get_bus_volume(AudioManager.MUSIC_BUS) <= 0.01
	AudioManager.set_bus_volume(AudioManager.MUSIC_BUS, 0.8 if muted else 0.0)
	refresh()


## Records one tap on the version label. Five taps inside two seconds open the
## monetization debug panel, in debug builds only.
func register_version_tap() -> void:
	if not OS.is_debug_build():
		return
	var now := Time.get_ticks_msec()
	var recent: Array[int] = []
	for stamp: int in _version_taps:
		if now - stamp <= DEBUG_TAP_WINDOW_MS:
			recent.append(stamp)
	_version_taps = recent
	_version_taps.append(now)
	if _version_taps.size() < DEBUG_TAP_COUNT:
		return
	_version_taps.clear()
	if main_menu != null:
		main_menu.open_monetization_debug()


func _on_version_gui_input(event: InputEvent) -> void:
	var tapped := false
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		tapped = click.pressed and click.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		tapped = (event as InputEventScreenTouch).pressed
	if tapped:
		register_version_tap()
