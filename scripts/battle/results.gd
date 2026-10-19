class_name Results
extends Control
## Results screen for both defeat and quit.
##
## The `RunSummary` arrives through a one-shot `SceneRouter` payload. Rewards are
## granted exactly once on entry; the double-Gold ad can only add its bonus once.

const MENU_SCENE := "res://scenes/menu/MainMenu.tscn"
const BATTLE_SCENE := "res://scenes/battle/Battle.tscn"
const MILESTONE_WAVE := 30
const MILESTONE_GEMS := 10

var summary: RunSummary
var _gold := 0
var _gems := 0
var _base_gold := 0
var _milestone := false
var _doubled := false
var _rewards_applied := false

@onready var _header: Label = %Header
@onready var _best_label: Label = %BestLabel
@onready var _new_best: Label = %NewBest
@onready var _waves: Label = %StatWaves
@onready var _kills: Label = %StatKills
@onready var _bosses: Label = %StatBosses
@onready var _time: Label = %StatTime
@onready var _coins: Label = %StatCoins
@onready var _gold_counter: RewardCounter = %GoldCounter
@onready var _gems_counter: RewardCounter = %GemsCounter
@onready var _double_button: Button = %DoubleGoldButton
@onready var _milestone_label: Label = %MilestoneLabel
@onready var _play_button: Button = %PlayAgainButton
@onready var _menu_button: Button = %MenuButton
@onready var _toast: Toast = %Toast


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	SpeedService.reset()
	summary = SceneRouter.consume_payload() as RunSummary
	if summary == null:
		SceneRouter.goto(MENU_SCENE)
		return

	_milestone = summary.waves_cleared >= MILESTONE_WAVE and not GameState.has_flag("milestone_30")
	_base_gold = compute_gold(summary)
	_gold = _base_gold
	_gems = compute_gems(summary, _milestone)
	var applied := GameState.apply_run_result(summary, _gold, _gems)
	_rewards_applied = true
	MissionHooks.report_run(summary, _gold)

	_double_button.pressed.connect(_on_double_gold_pressed)
	_play_button.pressed.connect(_on_play_again_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)
	EventBus.language_changed.connect(_on_language_changed)

	_refresh_texts()
	_refresh_best(applied)
	_gold_counter.set_value_now(0)
	_gems_counter.set_value_now(0)
	_gold_counter.count_to(_gold)
	_gems_counter.count_to(_gems)
	_maybe_toast_elf_level(applied)
	Analytics.set_screen("results")


## Gold payout: `sum(8 + 2*w)` for cleared waves, times the run's gold multiplier.
static func compute_gold(run: RunSummary) -> int:
	if run == null or run.waves_cleared <= 0:
		return 0
	var base := 0
	for wave in range(1, run.waves_cleared + 1):
		base += 8 + 2 * wave
	return maxi(0, int(floor(float(base) * maxf(0.0, run.gold_mult))))


## Gem payout: 2 per five cleared waves, 5 per boss, plus the one-time milestone.
static func compute_gems(run: RunSummary, milestone: bool) -> int:
	if run == null:
		return 0
	var gems := 2 * int(run.waves_cleared / 5) + 5 * run.bosses_killed
	if milestone and run.waves_cleared >= MILESTONE_WAVE:
		gems += MILESTONE_GEMS
	return maxi(0, gems)


func _refresh_texts() -> void:
	_header.text = Loc.t_key(
		"RESULTS_DEFEAT_TITLE" if summary.reason == &"defeat" else "RESULTS_QUIT_TITLE"
	)
	_waves.text = Loc.t_key("RESULTS_WAVES", {"count": summary.waves_cleared})
	_kills.text = Loc.t_key("RESULTS_KILLS", {"count": summary.kills})
	_bosses.text = Loc.t_key("RESULTS_BOSSES", {"count": summary.bosses_killed})
	_time.text = Loc.t_key("RESULTS_TIME", {"time": summary.get_time_string()})
	_coins.text = Loc.t_key("RESULTS_COINS", {"count": Loc.format_number(summary.coins_earned)})
	_double_button.text = Loc.t_key("RESULTS_DOUBLE_GOLD")
	_play_button.text = Loc.t_key("RESULTS_PLAY_AGAIN")
	_menu_button.text = Loc.t_key("RESULTS_MENU")
	_new_best.text = Loc.t_key("RESULTS_NEW_BEST")
	_gold_counter.setup("CURRENCY_GOLD")
	_gems_counter.setup("CURRENCY_GEMS")
	_milestone_label.text = Loc.t_key("RESULTS_MILESTONE", {"gems": MILESTONE_GEMS})
	_milestone_label.visible = _milestone


func _refresh_best(applied: Dictionary) -> void:
	_new_best.visible = bool(applied.get("new_best", false))
	_best_label.text = Loc.t_key("RESULTS_BEST", {"wave": int(applied.get("best_wave", 0))})


func _maybe_toast_elf_level(applied: Dictionary) -> void:
	var elf_before := int(applied.get("elf_before", 1))
	var elf_after := int(applied.get("elf_after", 1))
	if elf_before < SpeedService.ELF_LEVEL_FOR_15 and elf_after >= SpeedService.ELF_LEVEL_FOR_15:
		_toast.show_message(Loc.t_key("SPEED_UNLOCKED_TOAST"), 2.5)


func _on_double_gold_pressed() -> void:
	if _doubled or not _rewards_applied:
		return
	_double_button.disabled = true
	Monetization.show_rewarded("results_double_gold", _on_double_gold_result)


func _on_double_gold_result(success: bool) -> void:
	if success and _rewards_applied and not _doubled:
		_doubled = true
		GameState.add_gold(_base_gold)
		_gold += _base_gold
		_gold_counter.count_to(_gold)
		_double_button.visible = false
		_toast.show_message(Loc.t_key("RESULTS_DOUBLE_DONE"))
		return
	_double_button.disabled = false
	_toast.show_message(Loc.t_key("RESULTS_AD_FAILED"))


func _on_language_changed(_locale: String) -> void:
	_refresh_texts()
	_best_label.text = Loc.t_key("RESULTS_BEST", {"wave": GameState.get_best_wave()})


func _on_play_again_pressed() -> void:
	AudioManager.play_ui("ui_click")
	SceneRouter.goto(BATTLE_SCENE)


func _on_menu_pressed() -> void:
	AudioManager.play_ui("ui_click")
	SceneRouter.goto(MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneRouter.goto(MENU_SCENE)
		get_viewport().set_input_as_handled()
