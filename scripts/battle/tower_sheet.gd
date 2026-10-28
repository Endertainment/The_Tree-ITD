class_name TowerSheet
extends Control
## Bottom sheet for a built tower: level, stats, deltas, upgrade, sell and the
## targeting mode. Selling always asks for confirmation.

signal close_requested
signal upgrade_requested(tower: Tower)
signal sell_requested(tower: Tower)
signal target_mode_changed(tower: Tower, mode: int)

const BASE_BOTTOM_MARGIN := 16
const MODE_KEYS := ["TOWER_TARGET_NEAREST", "TOWER_TARGET_STRONGEST", "TOWER_TARGET_FIRST"]

var _battle: Battle
var _tower: Tower
var _target_buttons: Array[Button] = []

@onready var _panel: PanelContainer = %Panel
@onready var _icon: TowerIcon = %TowerIcon
@onready var _title: Label = %SheetTitle
@onready var _level_label: Label = %SheetLevel
@onready var _stats_now: Label = %StatsNow
@onready var _stats_next: Label = %StatsNext
@onready var _upgrade_button: Button = %UpgradeButton
@onready var _upgrade_reason: Label = %UpgradeReason
@onready var _target_label: Label = %TargetLabel
@onready var _sell_button: Button = %SellButton
@onready var _sell_confirm: Control = %SellConfirm
@onready var _sell_title: Label = %SellTitle
@onready var _sell_body: Label = %SellBody
@onready var _sell_cancel: Button = %SellCancel
@onready var _sell_ok: Button = %SellConfirmButton
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UISkin.apply_panel(_panel, "sheet")
	UISkin.apply_icon(_close_button, "close")
	_close_button.flat = true
	UISkin.limit_widths(_panel)
	visible = false
	_target_buttons = [%TargetNearest, %TargetStrongest, %TargetFirst]
	_close_button.pressed.connect(_on_close_pressed)
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	_sell_button.pressed.connect(_on_sell_pressed)
	_sell_cancel.pressed.connect(_on_sell_cancelled)
	_sell_ok.pressed.connect(_on_sell_confirmed)
	for index in _target_buttons.size():
		_target_buttons[index].pressed.connect(_on_target_pressed.bind(index))


## Shows the sheet for one tower.
func open(tower: Tower, battle: Battle) -> void:
	_tower = tower
	_battle = battle
	visible = true
	refresh()


## Hides the sheet and forgets the tower.
func close() -> void:
	visible = false
	_tower = null
	_sell_confirm.visible = false


## Repaints every label from the tower's current level and the run's Coins.
func refresh() -> void:
	if _tower == null or not is_instance_valid(_tower) or _tower.data == null:
		close_requested.emit()
		return

	var data := _tower.data
	var stats := _tower.get_stats()
	_title.text = Loc.t_key(data.display_name_key)
	_level_label.text = Loc.t_key("TOWER_LEVEL_LABEL", {
		"level": _tower.level,
		"max": data.max_level(),
	})
	_icon.setup(data.silhouette, _tower.level, data.base_color, data.accent_color)
	_sell_confirm.visible = false

	if stats != null:
		_stats_now.text = Loc.t_key("TOWER_STATS_NOW", {
			"damage": int(round(stats.damage)),
			"rate": _format_rate(stats.interval),
			"range": int(round(stats.range)),
		})
	_refresh_next_line()
	_refresh_upgrade_button()
	_refresh_target_row()

	_sell_button.text = Loc.t_key("SHEET_SELL", {
		"refund": Loc.format_number(_tower.get_sell_refund()),
	})
	_sell_title.text = Loc.t_key("SHEET_SELL_TITLE")
	_sell_body.text = Loc.t_key("SHEET_SELL_BODY", {
		"name": Loc.t_key(data.display_name_key),
		"level": _tower.level,
		"refund": _tower.get_sell_refund(),
	})
	_sell_cancel.text = Loc.t_key("SHEET_CANCEL")
	_sell_ok.text = Loc.t_key("SHEET_SELL_CONFIRM")
	_target_label.text = Loc.t_key("TOWER_TARGET")


## Lifts the panel above the device's bottom safe-area inset.
func set_bottom_inset(inset: int) -> void:
	_panel.offset_bottom = -float(BASE_BOTTOM_MARGIN + maxi(0, inset))


func _refresh_next_line() -> void:
	var next := _tower.get_next_stats()
	if next == null:
		_stats_next.text = ""
		_stats_next.visible = false
		return
	var now := _tower.get_stats()
	_stats_next.visible = true
	_stats_next.modulate = Color(0.6, 0.88, 0.55)
	if now == null:
		return
	_stats_next.text = Loc.t_key("TOWER_STATS_NEXT", {
		"damage": int(round(next.damage)),
		"damage_delta": _format_signed(next.damage - now.damage, 0),
		"rate": _format_rate(next.interval),
		"rate_delta": _format_signed(next.interval - now.interval, 1),
		"range": int(round(next.range)),
		"range_delta": _format_signed(next.range - now.range, 0),
	})


func _refresh_upgrade_button() -> void:
	if _tower.is_max_level():
		_upgrade_button.text = Loc.t_key("SHEET_UPGRADE_MAX")
		_upgrade_button.disabled = true
		_upgrade_reason.text = ""
		return

	var cost := _tower.get_upgrade_cost()
	var affordable := _battle != null and _battle.coins >= cost
	_upgrade_button.text = Loc.t_key("SHEET_UPGRADE", {"cost": Loc.format_number(cost)})
	_upgrade_button.disabled = not affordable
	_upgrade_reason.text = "" if affordable else Loc.t_key("SHEET_NEED_COINS", {"cost": cost - _battle.coins})


func _refresh_target_row() -> void:
	for index in _target_buttons.size():
		var button := _target_buttons[index]
		button.text = Loc.t_key(MODE_KEYS[index])
		button.button_pressed = _tower.target_mode == index


func _format_rate(interval: float) -> String:
	return "%.1f" % interval


func _format_signed(value: float, decimals: int) -> String:
	var text: String = ("%." + str(decimals) + "f") % value
	if value > 0.0:
		return "+" + text
	return text


func _on_upgrade_pressed() -> void:
	AudioManager.play_ui("ui_click")
	upgrade_requested.emit(_tower)


func _on_sell_pressed() -> void:
	AudioManager.play_ui("ui_click")
	_sell_confirm.visible = true


func _on_sell_cancelled() -> void:
	_sell_confirm.visible = false


func _on_sell_confirmed() -> void:
	AudioManager.play_ui("ui_click")
	sell_requested.emit(_tower)


func _on_target_pressed(mode: int) -> void:
	AudioManager.play_ui("ui_click")
	target_mode_changed.emit(_tower, mode)


func _on_close_pressed() -> void:
	AudioManager.play_ui("ui_click")
	close_requested.emit()
