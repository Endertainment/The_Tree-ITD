extends MenuScreen
## Home tab: identity, BATTLE entry point, daily summary and equipped cards.

const BATTLE_SCENE := "res://scenes/battle/Battle.tscn"
const VERSION_SETTING := "application/config/version"

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _best_wave: Label = %BestWaveLabel
@onready var _elf_label: Label = %ElfLabel
@onready var _elf_progress: Label = %ElfProgress
@onready var _elf_bar: ProgressBar = %ElfBar
@onready var _battle_button: Button = %BattleButton
@onready var _daily_title: Label = %DailyTitle
@onready var _daily_progress: Label = %DailyProgress
@onready var _daily_view: Button = %DailyView
@onready var _equipped_row: HBoxContainer = %EquippedRow
@onready var _equipped_title: Label = %EquippedTitle
@onready var _equipped_empty: Label = %EquippedEmpty
@onready var _speed_chip: Button = %SpeedChip
@onready var _music_button: Button = %MusicButton
@onready var _version: Label = %VersionLabel


func _ready() -> void:
	_battle_button.pressed.connect(_on_battle_pressed)
	_daily_view.pressed.connect(_on_daily_view_pressed)
	_music_button.pressed.connect(_on_music_pressed)
	_speed_chip.disabled = true


func refresh() -> void:
	_title.text = Loc.t_key("MENU_TITLE")
	_subtitle.text = Loc.t_key("MENU_SUBTITLE")
	_battle_button.text = Loc.t_key("MENU_BATTLE")
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
	_refresh_equipped()
	_daily_title.text = Loc.t_key("HOME_DAILY")
	_equipped_title.text = Loc.t_key("HOME_EQUIPPED")
	_equipped_empty.text = Loc.t_key("HOME_NO_CARDS")
	_daily_view.text = Loc.t_key("HOME_DAILY_VIEW")
	_speed_chip.text = Loc.t_key("HOME_SPEED_TRIAL")
	_version.text = Loc.t_key("VERSION_LABEL", {
		"version": str(ProjectSettings.get_setting(VERSION_SETTING, "0.1.0")),
	})
	_music_button.text = Loc.t_key(
		"HOME_MUSIC_ON" if AudioManager.get_bus_volume(AudioManager.MUSIC_BUS) > 0.01 else "HOME_MUSIC_OFF"
	)


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


func _refresh_equipped() -> void:
	for child in _equipped_row.get_children():
		_equipped_row.remove_child(child)
		child.queue_free()
	var cards := GameState.get_equipped_cards()
	_equipped_empty.visible = cards.is_empty()
	_equipped_row.visible = not cards.is_empty()
	for card: CardData in cards:
		var pill := Label.new()
		pill.theme_type_variation = &"HudLabel"
		pill.text = Loc.t_key(card.name_key)
		pill.custom_minimum_size = Vector2(0, 72)
		pill.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_equipped_row.add_child(pill)


func _on_battle_pressed() -> void:
	AudioManager.play_ui("ui_click")
	SceneRouter.goto(BATTLE_SCENE)


func _on_daily_view_pressed() -> void:
	main_menu.select_tab("missions")


func _on_music_pressed() -> void:
	AudioManager.play_ui("ui_click")
	var muted := AudioManager.get_bus_volume(AudioManager.MUSIC_BUS) <= 0.01
	AudioManager.set_bus_volume(AudioManager.MUSIC_BUS, 0.8 if muted else 0.0)
	refresh()
