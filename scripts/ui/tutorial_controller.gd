class_name TutorialController
extends CanvasLayer
## Three-step, non-blocking first-run tutorial.
##
## Each step highlights one target with a ring and a small card; gameplay keeps
## running underneath. A step completes when its action happens or after
## `STEP_TIMEOUT` seconds. Steps whose target does not exist are skipped, boss
## waves hide the tutorial, and the flag is persisted in `flags.tutorial_done`.

const STEP_TIMEOUT := 20.0
const CARD_WIDTH := 680.0
const CARD_HEIGHT := 280.0
const CARD_GAP := 48.0
const SCREEN_MARGIN := 24.0
const PAD_HIGHLIGHT := Vector2(150.0, 150.0)

const STEPS: Array[Dictionary] = [
	{"key": "TUTORIAL_BUILD", "target": "pad"},
	{"key": "TUTORIAL_UPGRADE", "target": "upgrade"},
	{"key": "TUTORIAL_CALL", "target": "call"},
]

@onready var _root: Control = %Root
@onready var _card: PanelContainer = %Card
@onready var _text: Label = %TutorialText
@onready var _skip: Button = %SkipButton
@onready var _highlight: Panel = %Highlight

var _battle: Battle
var _hud: BattleHUD
var _towers: TowerManager
var _step := -1
var _timer := 0.0
var _running := false


## Wires the tutorial to a live battle. Safe to call once per run.
func setup(battle: Battle, hud: BattleHUD, towers: TowerManager) -> void:
	_battle = battle
	_hud = hud
	_towers = towers
	_hide()
	_skip.text = Loc.t_key("TUTORIAL_SKIP")
	if not _skip.pressed.is_connected(skip):
		_skip.pressed.connect(skip)
	if not EventBus.tower_built.is_connected(_on_tower_built):
		EventBus.tower_built.connect(_on_tower_built)
	if not EventBus.upgrade_purchased.is_connected(_on_upgrade_purchased):
		EventBus.upgrade_purchased.connect(_on_upgrade_purchased)
	if not EventBus.boss_spawned.is_connected(_on_boss_spawned):
		EventBus.boss_spawned.connect(_on_boss_spawned)
	if not EventBus.language_changed.is_connected(_on_language_changed):
		EventBus.language_changed.connect(_on_language_changed)
	if _battle.has_signal("wave_called") and not _battle.wave_called.is_connected(_on_wave_called):
		_battle.wave_called.connect(_on_wave_called)


## Starts the tutorial when the profile has not completed it yet.
func start_if_needed() -> void:
	if _battle == null or GameState.has_flag("tutorial_done"):
		return
	_running = true
	_begin_step(0)


## Hides the tutorial and marks it done. Bound to the SKIP button.
func skip() -> void:
	if _battle == null:
		return
	_mark_done()
	_stop()


## True while a step is on screen.
func is_active() -> bool:
	return _running and _step >= 0


## Hides the tutorial without marking it complete (the run ended first).
func dismiss() -> void:
	_stop()


## Index of the step currently shown (-1 when idle).
func get_step() -> int:
	return _step


## Seconds left on the current step.
func get_time_left() -> float:
	return _timer


func _process(delta: float) -> void:
	if not _running or _step < 0 or get_tree().paused:
		return
	_timer -= delta
	if _timer <= 0.0:
		_advance()


func _begin_step(index: int) -> void:
	if not _running:
		return
	if index >= STEPS.size():
		_finish()
		return
	if _is_boss_fight():
		_finish()
		return
	var rect := _target_rect(str(STEPS[index]["target"]))
	if rect.size == Vector2.ZERO:
		_begin_step(index + 1)
		return
	_step = index
	_timer = STEP_TIMEOUT
	_text.text = Loc.t_key(str(STEPS[index]["key"]))
	_present(rect)


func _target_rect(kind: String) -> Rect2:
	match kind:
		"pad":
			return _first_empty_pad_rect()
		"upgrade":
			return _hud.get_upgrades_button_rect() if _hud != null else Rect2()
		"call":
			return _hud.get_call_button_rect() if _hud != null else Rect2()
		_:
			return Rect2()


func _first_empty_pad_rect() -> Rect2:
	if _towers == null:
		return Rect2()
	for pad: BuildPad in _towers.get_pads():
		if not pad.has_tower():
			return Rect2(pad.global_position - PAD_HIGHLIGHT * 0.5, PAD_HIGHLIGHT)
	return Rect2()


func _is_boss_fight() -> bool:
	if _battle == null or _battle.wave_manager == null:
		return false
	return _battle.wave_manager.get_boss() != null


func _present(target: Rect2) -> void:
	_highlight.position = target.position
	_highlight.size = target.size
	_highlight.visible = true
	# A fixed card height avoids measuring an autowrapped label before it has a
	# width, which otherwise reports a full-column height.
	_card.size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	var card_size := _card.size
	var view := _root.size
	var card_x := clampf(
		target.get_center().x - card_size.x * 0.5,
		SCREEN_MARGIN,
		maxf(SCREEN_MARGIN, view.x - card_size.x - SCREEN_MARGIN)
	)
	var card_y := target.position.y - card_size.y - CARD_GAP
	if card_y < SCREEN_MARGIN:
		card_y = target.end.y + CARD_GAP
	card_y = clampf(card_y, SCREEN_MARGIN, maxf(SCREEN_MARGIN, view.y - card_size.y - SCREEN_MARGIN))
	_card.position = Vector2(card_x, card_y)
	_card.visible = true


func _hide() -> void:
	if _highlight != null:
		_highlight.visible = false
	if _card != null:
		_card.visible = false


func _advance() -> void:
	if _step < 0:
		return
	var next := _step + 1
	_hide()
	_begin_step(next)


func _finish() -> void:
	_mark_done()
	_stop()


func _stop() -> void:
	_running = false
	_step = -1
	_timer = 0.0
	_hide()


func _mark_done() -> void:
	GameState.set_flag("tutorial_done", true)


func _on_tower_built(_tower_id: String) -> void:
	if _step == 0:
		_advance()


func _on_upgrade_purchased(_track_id: String, _level: int) -> void:
	if _step == 1:
		_advance()


func _on_wave_called() -> void:
	if _step == 2:
		_advance()


func _on_boss_spawned(_boss_index: int) -> void:
	_finish()


func _on_language_changed(_locale: String) -> void:
	_skip.text = Loc.t_key("TUTORIAL_SKIP")
	if _step >= 0 and _step < STEPS.size():
		_text.text = Loc.t_key(str(STEPS[_step]["key"]))
		if _highlight.visible:
			_present(Rect2(_highlight.position, _highlight.size))
