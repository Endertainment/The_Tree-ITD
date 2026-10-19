class_name PreBattle
extends PanelContainer
## Run briefing embedded on Home: best wave, difficulty, equipped cards and the
## rewarded 1.5x speed trial, with the one-tap BATTLE button.
##
## This is a panel, not a scene between `MainMenu` and `Battle`: master section
## 7.4 locks that flow, and the stage-6 panel option keeps BATTLE one tap away.

signal battle_requested

const DIFFICULTY_FAIR := 3
const DIFFICULTY_HARD := 10
const DIFFICULTY_DEADLY := 20

@onready var _title: Label = %Title
@onready var _best: Label = %BestLabel
@onready var _difficulty: Label = %DifficultyLabel
@onready var _cards_title: Label = %CardsTitle
@onready var _cards_row: HBoxContainer = %CardsRow
@onready var _cards_empty: Label = %CardsEmpty
@onready var _trial_button: Button = %SpeedTrialButton
@onready var _unlocked_label: Label = %SpeedUnlockedLabel
@onready var _status: Label = %StatusLabel
@onready var _spinner: AdSpinner = %Spinner
@onready var _battle_button: Button = %BattleButton

var _busy := false
var _status_key := ""


func _ready() -> void:
	_trial_button.pressed.connect(_on_trial_pressed)
	_battle_button.pressed.connect(_on_battle_pressed)
	refresh()


## Repaints every label and the trial chip. Safe to call on language change.
func refresh() -> void:
	_title.text = Loc.t_key("PREPARE_TITLE")
	_best.text = Loc.t_key("PREPARE_BEST", {
		"wave": Loc.format_number(GameState.get_best_wave()),
	})
	_difficulty.text = Loc.t_key("PREPARE_DIFFICULTY", {
		"level": Loc.t_key(_difficulty_key(GameState.get_best_wave())),
	})
	_cards_title.text = Loc.t_key("PREPARE_CARDS")
	_cards_empty.text = Loc.t_key("PREPARE_NO_CARDS")
	_battle_button.text = Loc.t_key("MENU_BATTLE")
	_status.visible = not _status_key.is_empty()
	_status.text = Loc.t_key(_status_key) if not _status_key.is_empty() else ""
	_refresh_cards()
	_refresh_trial()


func _refresh_cards() -> void:
	for child in _cards_row.get_children():
		_cards_row.remove_child(child)
		child.queue_free()
	var cards := GameState.get_equipped_cards()
	_cards_row.visible = not cards.is_empty()
	_cards_empty.visible = cards.is_empty()
	for card: CardData in cards:
		var pill := Label.new()
		pill.theme_type_variation = &"HudLabel"
		pill.text = Loc.t_key(card.name_key)
		pill.custom_minimum_size = Vector2(0, 68)
		pill.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pill.clip_text = true
		pill.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_cards_row.add_child(pill)


func _refresh_trial() -> void:
	var owned := SpeedService.is_speed_15_permanently_unlocked()
	_trial_button.visible = not owned
	_unlocked_label.visible = owned
	_unlocked_label.text = Loc.t_key("PREPARE_SPEED_UNLOCKED")
	var pending := SpeedService.has_pending_trial_15()
	_trial_button.disabled = _busy or pending
	if pending:
		_trial_button.text = Loc.t_key("PREPARE_TRIAL_ACTIVE")
	else:
		_trial_button.text = Loc.t_key("SPEED_TRIAL_CHIP")


func _on_trial_pressed() -> void:
	if _busy:
		return
	AudioManager.play_ui("ui_click")
	_busy = true
	_status_key = ""
	_status.visible = false
	_spinner.start()
	_refresh_trial()
	Monetization.request_speed_trial(_on_trial_result)


func _on_trial_result(result: StringName) -> void:
	_busy = false
	_spinner.stop()
	match result:
		&"success":
			_status_key = "SPEED_TRIAL_GRANTED"
		&"failed":
			_status_key = "SPEED_TRIAL_FAILED"
		&"owned":
			_status_key = "PREPARE_SPEED_UNLOCKED"
		_:
			_status_key = ""
	refresh()


func _on_battle_pressed() -> void:
	if _busy:
		return
	AudioManager.play_ui("ui_click")
	battle_requested.emit()


func _difficulty_key(best_wave: int) -> String:
	if best_wave >= DIFFICULTY_DEADLY:
		return "PREPARE_DIFFICULTY_DEADLY"
	if best_wave >= DIFFICULTY_HARD:
		return "PREPARE_DIFFICULTY_HARD"
	if best_wave >= DIFFICULTY_FAIR:
		return "PREPARE_DIFFICULTY_FAIR"
	return "PREPARE_DIFFICULTY_EASY"
