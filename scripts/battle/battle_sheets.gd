class_name BattleSheets
extends Node
## Owns the build, tower and upgrade sheets and the single pause they hold.
##
## `Battle` keeps the gameplay rules (economy, purchases, tower manager) and this
## node keeps the sheet lifecycle, so exactly one sheet is open and exactly one
## pause owner exists at a time.

signal build_requested(tower_id: String)
signal tower_upgrade_requested(tower: Tower)
signal tower_sell_requested(tower: Tower)
signal target_mode_changed(tower: Tower, mode: int)
signal upgrade_requested(track_id: String)
signal tower_focus_requested(tower: Tower)

const BUILD_SHEET_SCENE := preload("res://scenes/battle/BuildSheet.tscn")
const TOWER_SHEET_SCENE := preload("res://scenes/battle/TowerSheet.tscn")
const UPGRADE_PANEL_SCENE := preload("res://scenes/battle/UpgradePanel.tscn")

var _battle: Battle
var _hud: BattleHUD
var _tower_manager: TowerManager
var _build_sheet: BuildSheet
var _tower_sheet: TowerSheet
var _upgrade_panel: UpgradePanel
var _open := false
var _active_pad: BuildPad


## Builds every sheet once under the HUD sheet host and wires their signals.
func setup(battle: Battle, hud: BattleHUD, tower_manager: TowerManager) -> void:
	_battle = battle
	_hud = hud
	_tower_manager = tower_manager
	var host := hud.get_sheet_host()

	_build_sheet = BUILD_SHEET_SCENE.instantiate() as BuildSheet
	_build_sheet.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_build_sheet)
	_build_sheet.build_requested.connect(_on_build_requested)
	_build_sheet.close_requested.connect(close)

	_tower_sheet = TOWER_SHEET_SCENE.instantiate() as TowerSheet
	_tower_sheet.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_tower_sheet)
	_tower_sheet.close_requested.connect(close)
	_tower_sheet.upgrade_requested.connect(_on_tower_upgrade_requested)
	_tower_sheet.sell_requested.connect(_on_tower_sell_requested)
	_tower_sheet.target_mode_changed.connect(_on_target_mode_changed)

	_upgrade_panel = UPGRADE_PANEL_SCENE.instantiate() as UpgradePanel
	_upgrade_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_upgrade_panel)
	_upgrade_panel.close_requested.connect(close)
	_upgrade_panel.upgrade_requested.connect(_on_upgrade_requested)
	_upgrade_panel.tower_selected.connect(_on_tower_selected)


## True while one of the sheets owns the pause.
func is_open() -> bool:
	return _open


## Pad that opened the current build/tower sheet, or null.
func active_pad() -> BuildPad:
	return _active_pad


## Opens the build sheet for `pad`, or the tower sheet when it is occupied.
func open_pad(pad: BuildPad) -> void:
	if pad == null or _open or _battle == null or _battle.is_over():
		return
	_open = true
	_active_pad = pad
	_tower_manager.select(pad)
	get_tree().paused = true
	_hud.set_sheet_mode(true)

	var inset := _hud.get_bottom_inset()
	if pad.has_tower():
		_tower_sheet.set_bottom_inset(inset)
		_tower_sheet.open(pad.tower, _battle)
	else:
		_build_sheet.set_bottom_inset(inset)
		_build_sheet.open(pad, _battle)


## Opens the in-run upgrade panel and pauses the battle.
func open_upgrades() -> void:
	if _open or _battle == null or _battle.is_over() or _battle.run_stats == null:
		return
	_open = true
	get_tree().paused = true
	_hud.set_sheet_mode(true)
	_upgrade_panel.set_bottom_inset(_hud.get_bottom_inset())
	_upgrade_panel.open(_battle.run_stats, _battle.coins, _tower_manager.get_towers())


## Switches from the upgrade panel to the tower sheet of `tower`.
func focus_tower(tower: Tower) -> void:
	if tower == null or tower.pad == null:
		return
	close()
	open_pad(tower.pad)


## Closes whichever sheet is open and releases the pause it held.
func close() -> void:
	if not _open:
		return
	_open = false
	_build_sheet.close()
	_tower_sheet.close()
	_upgrade_panel.close()
	_hud.set_sheet_mode(false)
	_tower_manager.select(null)
	_active_pad = null
	if _battle != null and not _battle.is_over() and not _hud.is_pause_visible():
		get_tree().paused = false


## Repaints the open sheet after Coins, stats or the locale changed.
func refresh() -> void:
	if not _open or _battle == null:
		return
	if _upgrade_panel.visible:
		_upgrade_panel.refresh(_battle.run_stats, _battle.coins, _tower_manager.get_towers())
	elif _active_pad != null:
		if _tower_sheet.visible:
			_tower_sheet.refresh()
		elif _build_sheet.visible:
			_build_sheet.refresh()


func _on_build_requested(tower_id: String) -> void:
	build_requested.emit(tower_id)


func _on_tower_upgrade_requested(tower: Tower) -> void:
	tower_upgrade_requested.emit(tower)


func _on_tower_sell_requested(tower: Tower) -> void:
	tower_sell_requested.emit(tower)


func _on_target_mode_changed(tower: Tower, mode: int) -> void:
	target_mode_changed.emit(tower, mode)


func _on_upgrade_requested(track_id: String) -> void:
	upgrade_requested.emit(track_id)


func _on_tower_selected(tower: Tower) -> void:
	tower_focus_requested.emit(tower)
