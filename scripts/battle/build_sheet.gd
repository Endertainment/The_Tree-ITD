class_name BuildSheet
extends Control
## Bottom sheet that offers the three tower types for one empty pad.
##
## The sheet is created once per battle and only shown/hidden, so opening it
## fifty times neither leaks nodes nor re-instantiates cards forever: the card
## row is rebuilt from `ConfigDB` and removed on close.

signal build_requested(tower_id: String)
signal close_requested

const CARD_SCENE := preload("res://ui/TowerCard.tscn")
const BASE_BOTTOM_MARGIN := 16

var _battle: Battle
var _pad: BuildPad
var _cards: Array[TowerCard] = []

@onready var _panel: PanelContainer = %Panel
@onready var _title: Label = %SheetTitle
@onready var _coins: Label = %SheetCoins
@onready var _cards_box: HBoxContainer = %Cards
@onready var _hint: Label = %SheetHint
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UISkin.apply_panel(_panel, "sheet")
	UISkin.apply_icon(_close_button, "close")
	_close_button.flat = true
	UISkin.limit_widths(_panel)
	visible = false
	_close_button.pressed.connect(_on_close_pressed)


## Shows the sheet for `pad`, with prices from the current run's modifiers.
func open(pad: BuildPad, battle: Battle) -> void:
	_pad = pad
	_battle = battle
	_rebuild_cards()
	refresh()
	visible = true


## Hides the sheet and drops the card row.
func close() -> void:
	visible = false
	_pad = null
	_clear_cards()


## Repaints prices and affordability. Closes itself if the pad got occupied.
func refresh() -> void:
	if _battle == null or _pad == null:
		return
	if _pad.has_tower():
		close_requested.emit()
		return
	_title.text = Loc.t_key("SHEET_BUILD_TITLE")
	_coins.text = Loc.format_number(_battle.coins)
	_hint.text = Loc.t_key("SHEET_BUILD_HINT")
	for card: TowerCard in _cards:
		_refresh_card(card)


## Lifts the panel above the device's bottom safe-area inset.
func set_bottom_inset(inset: int) -> void:
	_panel.offset_bottom = -float(BASE_BOTTOM_MARGIN + maxi(0, inset))


func _rebuild_cards() -> void:
	_clear_cards()
	var datas: Array = ConfigDB.all_towers()
	datas.sort_custom(_sort_by_cost)
	for entry: Variant in datas:
		var data := entry as TowerData
		if data == null:
			continue
		var card: TowerCard = CARD_SCENE.instantiate()
		card.tower_id = data.id
		_cards_box.add_child(card)
		card.pressed.connect(_on_card_pressed.bind(data.id))
		_cards.append(card)


func _clear_cards() -> void:
	for card: TowerCard in _cards:
		if is_instance_valid(card):
			_cards_box.remove_child(card)
			card.queue_free()
	_cards.clear()


func _refresh_card(card: TowerCard) -> void:
	var data := ConfigDB.get_tower(card.tower_id) as TowerData
	if data == null:
		return
	var price := _battle.get_tower_cost(card.tower_id)
	var affordable := _battle.coins >= price
	var reason := ""
	if not affordable:
		reason = Loc.t_key("SHEET_NEED_COINS", {"cost": price - _battle.coins})
	card.setup(data, price, affordable, reason)


func _sort_by_cost(a: Variant, b: Variant) -> bool:
	var left := a as TowerData
	var right := b as TowerData
	if left == null or right == null:
		return false
	return left.cost < right.cost


func _on_card_pressed(tower_id: String) -> void:
	AudioManager.play_ui("ui_click")
	build_requested.emit(tower_id)


func _on_close_pressed() -> void:
	AudioManager.play_ui("ui_click")
	close_requested.emit()
