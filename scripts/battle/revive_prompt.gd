class_name RevivePrompt
extends Control
## Defeat prompt: one rewarded revive or give up.
##
## Runs with `PROCESS_MODE_ALWAYS` because the battle tree is paused while it is
## open. It owns no reward logic; `Battle` decides what a successful revive does.

signal revive_requested
signal give_up_requested

@onready var _title: Label = %Title
@onready var _body: Label = %Body
@onready var _reward: Label = %RewardLabel
@onready var _revive_button: Button = %ReviveButton
@onready var _give_up_button: Button = %GiveUpButton
@onready var _spinner: AdSpinner = %Spinner


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_revive_button.pressed.connect(_on_revive_pressed)
	_give_up_button.pressed.connect(_on_give_up_pressed)
	refresh_texts()


## Shows the prompt in its idle state.
func open() -> void:
	visible = true
	set_busy(false)
	refresh_texts()


## Hides the prompt and stops the spinner.
func close() -> void:
	visible = false
	_spinner.stop()


## True while the prompt is on screen.
func is_open() -> bool:
	return visible


## Disables both actions and shows the spinner while the ad is pending.
func set_busy(busy: bool) -> void:
	_revive_button.disabled = busy
	_give_up_button.disabled = busy
	if busy:
		_spinner.start()
	else:
		_spinner.stop()


## Reapplies every localized string.
func refresh_texts() -> void:
	_title.text = Loc.t_key("REVIVE_TITLE")
	_body.text = Loc.t_key("REVIVE_BODY")
	_reward.text = Loc.t_key("REVIVE_REWARD")
	_revive_button.text = Loc.t_key("REVIVE_BUTTON")
	_give_up_button.text = Loc.t_key("REVIVE_GIVE_UP")


func _on_revive_pressed() -> void:
	AudioManager.play_ui("ui_click")
	set_busy(true)
	revive_requested.emit()


func _on_give_up_pressed() -> void:
	AudioManager.play_ui("ui_click")
	# Battle owns the prompt lifetime: it closes the prompt and releases the pause
	# in one step. Closing here first made Battle see a hidden prompt and bail,
	# leaving the run paused with no UI.
	give_up_requested.emit()
