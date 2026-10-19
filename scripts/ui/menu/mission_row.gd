class_name MissionRow
extends PanelContainer
## One daily mission or achievement row.

@onready var _title: Label = %Title
@onready var _description: Label = %Description
@onready var _bar: ProgressBar = %Bar
@onready var _progress: Label = %Progress
@onready var _reward: Label = %Reward
@onready var _claim: Button = %ClaimButton

var _mission: MissionData
var _on_claim: Callable


func setup(mission: MissionData, on_claim: Callable) -> void:
	_mission = mission
	_on_claim = on_claim
	_claim.pressed.connect(_on_claim_pressed)
	refresh()


func refresh() -> void:
	if _mission == null:
		return
	var current := mini(GameState.missions.get_progress(_mission.id), _mission.target)
	var claimed := GameState.missions.is_claimed(_mission.id)
	var complete := _mission.is_complete(current)
	_title.text = Loc.t_key(_mission.title_key)
	_description.text = Loc.t_key(_mission.description_key)
	_bar.max_value = float(_mission.target)
	_bar.value = float(current)
	_progress.text = Loc.t_key("MISSIONS_PROGRESS", {
		"current": Loc.format_number(current),
		"target": Loc.format_number(_mission.target),
	})
	_reward.text = Loc.t_key("MISSIONS_REWARD", {
		"gold": Loc.format_number(_mission.reward_gold),
		"gems": Loc.format_number(_mission.reward_gems),
	})
	_claim.text = Loc.t_key("MISSIONS_CLAIMED" if claimed else "MISSIONS_CLAIM")
	_claim.disabled = claimed or not complete
	modulate = Color(1, 1, 1, 0.65) if claimed else Color.WHITE


func _on_claim_pressed() -> void:
	if _mission != null and _on_claim.is_valid():
		_on_claim.call(_mission)
