class_name UpgradePanel
extends Control
## Pausing bottom sheet with the TREE / ARCHERS / TOWERS tabs.
##
## Rows are built once from `ConfigDB` and re-painted on open and on every stat
## or Coins change. The TOWERS tab is a shortcut list; tower upgrades still
## happen in the tower sheet.

signal close_requested
signal upgrade_requested(track_id: String)
signal tower_selected(tower: Tower)

const ROW_SCENE := preload("res://scenes/battle/UpgradeRow.tscn")
const TAB_TREE := "tree"
const TAB_ARCHERS := "archers"
const TAB_TOWERS := "towers"
const BASE_BOTTOM_MARGIN := 16

## Panel order, so the six tracks never shuffle with dictionary order.
const TRACK_ORDER: Array[String] = [
	"roots",
	"regrowth",
	"canopy_bows",
	"elven_haste",
	"far_sight",
	"extra_archer",
]

var _rows: Array[UpgradeRow] = []
var _tower_buttons: Array[Button] = []
var _tab := TAB_TREE
var _stats: RunStats
var _coins := 0
var _towers: Array[Tower] = []
var _bottom_inset := 0

@onready var _panel: PanelContainer = %Panel
@onready var _title: Label = %PanelTitle
@onready var _close_button: Button = %CloseButton
@onready var _summary: Label = %Summary
@onready var _rows_box: VBoxContainer = %Rows
@onready var _towers_box: VBoxContainer = %Towers
@onready var _towers_empty: Label = %TowersEmpty
@onready var _scroll: ScrollContainer = %Scroll
@onready var _tab_buttons: Array[Button] = [
	%TreeTab as Button,
	%ArchersTab as Button,
	%TowersTab as Button,
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_close_button.pressed.connect(_on_close_pressed)
	_tab_buttons[0].pressed.connect(_on_tab_pressed.bind(TAB_TREE))
	_tab_buttons[1].pressed.connect(_on_tab_pressed.bind(TAB_ARCHERS))
	_tab_buttons[2].pressed.connect(_on_tab_pressed.bind(TAB_TOWERS))
	_build_rows()


## Shows the sheet for the current run.
func open(stats: RunStats, coins: int, towers: Array[Tower]) -> void:
	_tab = TAB_TREE
	visible = true
	refresh(stats, coins, towers)


## Hides the sheet.
func close() -> void:
	visible = false


## Repaints the header, the active tab and the tower shortcut list.
func refresh(stats: RunStats, coins: int, towers: Array[Tower]) -> void:
	_stats = stats
	_coins = coins
	if stats == null:
		return
	_towers = towers
	_title.text = Loc.t_key("UPG_TITLE")
	_close_button.text = Loc.t_key("SHEET_CANCEL")
	_tab_buttons[0].text = Loc.t_key("UPG_TAB_TREE")
	_tab_buttons[1].text = Loc.t_key("UPG_TAB_ARCHERS")
	_tab_buttons[2].text = Loc.t_key("UPG_TAB_TOWERS")
	_result_tab_state()
	_summary.text = Loc.t_key("UPG_SUMMARY", {
		"hp": int(round(stats.max_hp)),
		"regen": "%.1f" % stats.regen,
		"dps": int(round(stats.get_archer_dps())),
		"archers": stats.start_archers,
	})
	for row: UpgradeRow in _rows:
		row.refresh(stats, coins)
	_rebuild_towers()


## Lifts the panel above the device's bottom safe-area inset.
func set_bottom_inset(inset: int) -> void:
	_bottom_inset = maxi(0, inset)
	_panel.offset_bottom = -float(BASE_BOTTOM_MARGIN + _bottom_inset)
	_fit_panel_height()


func _build_rows() -> void:
	for track_id: String in TRACK_ORDER:
		var track := ConfigDB.get_upgrade(track_id)
		if track == null:
			push_warning("[UpgradePanel] missing track '%s'" % track_id)
			continue
		var row := ROW_SCENE.instantiate() as UpgradeRow
		_rows_box.add_child(row)
		row.setup(track)
		row.purchase_requested.connect(_on_purchase_requested)
		_rows.append(row)


func _result_tab_state() -> void:
	for index in _tab_buttons.size():
		_tab_buttons[index].button_pressed = _tab == _tab_id(index)
	for row: UpgradeRow in _rows:
		row.visible = row.tab == _tab
	_towers_box.visible = _tab == TAB_TOWERS
	_towers_empty.visible = _tab == TAB_TOWERS and _towers.is_empty()
	_scroll.scroll_vertical = 0
	_fit_panel_height()


## Sizes the sheet to its content: two rows for TREE, four for ARCHERS, the
## scroll cap for TOWERS. Keeps the sheet from floating with a large empty area.
func _fit_panel_height() -> void:
	if not is_node_ready():
		return
	var visible_rows := 0
	for row: UpgradeRow in _rows:
		if row.visible:
			visible_rows += 1
	var rows_height := 320.0
	if _tab == TAB_TOWERS:
		rows_height = 620.0
	elif visible_rows > 0:
		rows_height = clampf(float(visible_rows) * 158.0 + 16.0, 320.0, 620.0)
	_scroll.custom_minimum_size.y = rows_height
	_panel.offset_top = -(rows_height + 400.0)


func _tab_id(index: int) -> String:
	match index:
		1:
			return TAB_ARCHERS
		2:
			return TAB_TOWERS
		_:
			return TAB_TREE


func _rebuild_towers() -> void:
	for button: Button in _tower_buttons:
		if is_instance_valid(button):
			_towers_box.remove_child(button)
			button.queue_free()
	_tower_buttons.clear()
	if _tab != TAB_TOWERS:
		return
	_towers_empty.text = Loc.t_key("UPG_TOWERS_EMPTY")
	for tower: Tower in _towers:
		if tower == null or not is_instance_valid(tower) or tower.data == null:
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 92.0)
		button.theme_type_variation = &"SecondaryButton"
		button.text = "%s  L%d" % [Loc.t_key(tower.data.display_name_key), tower.level]
		button.pressed.connect(_on_tower_button_pressed.bind(tower))
		_towers_box.add_child(button)
		_tower_buttons.append(button)


func _on_purchase_requested(track_id: String) -> void:
	AudioManager.play_ui("ui_click")
	upgrade_requested.emit(track_id)


func _on_tower_button_pressed(tower: Tower) -> void:
	AudioManager.play_ui("ui_click")
	tower_selected.emit(tower)


func _on_tab_pressed(tab: String) -> void:
	if _tab == tab:
		_result_tab_state()
		return
	AudioManager.play_ui("ui_click")
	_tab = tab
	if _stats != null:
		refresh(_stats, _coins, _towers)


func _on_close_pressed() -> void:
	AudioManager.play_ui("ui_click")
	close_requested.emit()
