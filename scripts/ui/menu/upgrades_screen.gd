extends MenuScreen
## Upgrades tab: the eight permanent Gold tracks from master context 6.2.

const ROW_SCENE := preload("res://scenes/menu/UpgradeTrackRow.tscn")

@onready var _header: Label = %Header
@onready var _hint: Label = %Hint
@onready var _list: VBoxContainer = %List

var _rows: Dictionary = {}


func _ready() -> void:
	for track: MetaUpgradeData in ConfigDB.all_meta_upgrades():
		var row := ROW_SCENE.instantiate() as UpgradeTrackRow
		_list.add_child(row)
		row.setup(track, _on_purchase_requested)
		_rows[track.id] = row


func refresh() -> void:
	_header.text = Loc.t_key("META_HEADER")
	_hint.text = Loc.t_key("META_HINT")
	for id: String in _rows:
		(_rows[id] as UpgradeTrackRow).refresh()


func _on_purchase_requested(track_id: String) -> void:
	var track := ConfigDB.get_meta_upgrade(track_id)
	if track == null:
		return
	var level := GameState.get_upgrade_level(track_id)
	if level >= track.max_level:
		return
	var cost := track.cost_for_level(level)
	if not GameState.spend_gold(cost):
		main_menu.show_toast(Loc.t_key("META_NOT_ENOUGH", {
			"cost": Loc.format_number(cost - GameState.get_gold()),
		}))
		return
	GameState.set_upgrade_level(track_id, level + 1)
	SaveManager.save_now(GameState.to_dict())
	Analytics.log_event("meta_upgrade", {"track": track_id, "level": level + 1, "cost": cost})
	main_menu.show_toast(Loc.t_key("META_PURCHASED", {
		"name": Loc.t_key(track.name_key),
		"level": level + 1,
	}))
	refresh()
	(_rows[track_id] as UpgradeTrackRow).flash()
