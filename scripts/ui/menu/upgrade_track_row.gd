class_name UpgradeTrackRow
extends PanelContainer
## One permanent upgrade row: level, current -> next effect, buy button.

@onready var _name: Label = %Name
@onready var _description: Label = %Description
@onready var _level: Label = %Level
@onready var _now: Label = %Now
@onready var _next: Label = %Next
@onready var _buy: Button = %BuyButton

var _track: MetaUpgradeData
var _on_buy: Callable


## Binds the row to `track`; `on_buy(track_id)` runs when the button is pressed.
func setup(track: MetaUpgradeData, on_buy: Callable) -> void:
	_track = track
	_on_buy = on_buy
	_buy.pressed.connect(_on_buy_pressed)
	refresh()


func refresh() -> void:
	if _track == null:
		return
	_name.text = Loc.t_key(_track.name_key)
	_description.text = Loc.t_key(_track.description_key)
	var level := GameState.get_upgrade_level(_track.id)
	_level.text = Loc.t_key("META_LEVEL", {"level": level, "max": _track.max_level})
	_now.text = Loc.t_key("META_NOW", {
		"value": StatText.format_value(_track.stat, _track.value_at(level)),
	})
	if level >= _track.max_level:
		_next.text = Loc.t_key("META_MAX")
		_buy.text = Loc.t_key("META_MAX")
		_buy.disabled = true
		return
	_next.text = Loc.t_key("META_NEXT", {
		"value": StatText.format_value(_track.stat, _track.value_at(level + 1)),
	})
	var cost := _track.cost_for_level(level)
	var missing := cost - GameState.get_gold()
	if missing > 0:
		_buy.text = Loc.t_key("META_NEED", {"cost": Loc.format_number(missing)})
		_buy.disabled = true
	else:
		_buy.text = Loc.t_key("META_BUY", {"cost": Loc.format_number(cost)})
		_buy.disabled = false


## Briefly highlights the row after a successful purchase.
func flash() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1.35, 1.25, 0.75, 1.0), 0.1)
	tween.tween_property(self, "modulate", Color.WHITE, 0.25)


func _on_buy_pressed() -> void:
	if _track != null and _on_buy.is_valid():
		_on_buy.call(_track.id)
