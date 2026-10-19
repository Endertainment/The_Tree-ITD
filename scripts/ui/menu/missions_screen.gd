extends MenuScreen
## Missions tab: deterministic daily set plus persistent achievements.

const ROW_SCENE := preload("res://scenes/menu/MissionRow.tscn")

@onready var _header: Label = %Header
@onready var _daily_button: Button = %DailyButton
@onready var _achievements_button: Button = %AchievementsButton
@onready var _reset_label: Label = %ResetLabel
@onready var _list: VBoxContainer = %List

var _scope := "daily"
var _rows: Array[MissionRow] = []
var _rows_by_id: Dictionary = {}
var _signature := ""
var _countdown := 0.0
var _rolling := false


func _ready() -> void:
	_daily_button.pressed.connect(_set_scope.bind("daily"))
	_achievements_button.pressed.connect(_set_scope.bind("achievements"))


func refresh() -> void:
	_header.text = Loc.t_key("MISSIONS_HEADER")
	_daily_button.text = Loc.t_key("MISSIONS_DAILY")
	_achievements_button.text = Loc.t_key("MISSIONS_ACHIEVEMENTS")
	_daily_button.button_pressed = _scope == "daily"
	_achievements_button.button_pressed = _scope == "achievements"
	_reset_label.visible = _scope == "daily"
	_update_countdown()
	var ids := _ids_for_scope()
	var signature := "%s:%s" % [_scope, ",".join(ids)]
	if signature != _signature:
		_signature = signature
		_rebuild(ids)
	for row: MissionRow in _rows:
		row.refresh()


func _ids_for_scope() -> Array[String]:
	if _scope == "daily":
		return GameState.missions.get_daily_ids()
	return GameState.missions.get_achievement_ids()


func _rebuild(ids: Array[String]) -> void:
	for row: MissionRow in _rows:
		_list.remove_child(row)
		row.queue_free()
	_rows.clear()
	_rows_by_id.clear()
	for id: String in ids:
		var mission := ConfigDB.get_mission(id)
		if mission == null:
			continue
		var row := ROW_SCENE.instantiate() as MissionRow
		_list.add_child(row)
		row.setup(mission, _on_claim_requested)
		_rows.append(row)
		_rows_by_id[id] = row


func _set_scope(scope: String) -> void:
	AudioManager.play_ui("ui_click")
	_scope = scope
	_signature = ""
	refresh()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _scope != "daily":
		return
	_countdown += delta
	if _countdown >= 1.0:
		_countdown = 0.0
		_update_countdown()


func _update_countdown() -> void:
	if _reset_label == null:
		return
	var remaining := MissionTracker.seconds_until_reset()
	_reset_label.text = Loc.t_key("MISSIONS_RESETS", {
		"time": Loc.format_time(remaining),
	})
	# A menu left open across local midnight rolls over in place.
	if remaining <= 1 and not _rolling and GameState.missions.refresh_daily():
		_rolling = true
		refresh()
		_rolling = false


func _on_claim_requested(mission: MissionData) -> void:
	if not GameState.missions.claim(mission.id):
		return
	AudioManager.play_ui("ui_click")
	main_menu.show_toast(Loc.t_key("MISSIONS_CLAIM_TOAST", {
		"gold": Loc.format_number(mission.reward_gold),
		"gems": Loc.format_number(mission.reward_gems),
	}))
	var row: MissionRow = _rows_by_id.get(mission.id, null)
	if row != null:
		main_menu.fly_reward(row.get_global_rect().get_center(), "+%d" % mission.reward_gold)
	refresh()
