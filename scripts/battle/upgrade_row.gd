class_name UpgradeRow
extends PanelContainer
## One row of the in-run upgrade panel: name, level pips, current -> next value
## and the cost button.

signal purchase_requested(track_id: String)

var track: UpgradeTrack
var tab := "tree"

@onready var _name: Label = %NameLabel
@onready var _level: Label = %LevelLabel
@onready var _value: Label = %ValueLabel
@onready var _description: Label = %DescriptionLabel
@onready var _cost_button: Button = %CostButton
@onready var _reason: Label = %ReasonLabel


func _ready() -> void:
	_cost_button.pressed.connect(_on_cost_pressed)


## Binds the row to one track. Call before refreshing.
func setup(upgrade_track: UpgradeTrack) -> void:
	track = upgrade_track
	tab = track.tab
	_name.text = Loc.t_key(track.name_key)
	_description.text = Loc.t_key(track.description_key)


## Repaints level, value preview and affordability.
func refresh(stats: RunStats, coins: int) -> void:
	if track == null or stats == null:
		return
	var level := stats.get_level(track.id)
	_level.text = Loc.t_key("UPG_LEVEL", {"level": level, "max": track.max_level})
	var display := stats.get_display(track.id)
	_value.text = _format_value(str(display.get("effect", track.effect)), display)

	if stats.is_maxed(track.id):
		_cost_button.text = Loc.t_key("UPG_MAX")
		_cost_button.disabled = true
		_reason.text = ""
		return

	var cost := stats.get_next_cost(track.id)
	_cost_button.text = Loc.t_key("UPG_BUY", {"cost": Loc.format_number(cost)})
	var affordable := coins >= cost
	_cost_button.disabled = not affordable
	_reason.text = "" if affordable else Loc.t_key("SHEET_NEED_COINS", {"cost": cost - coins})


func _format_value(effect: String, display: Dictionary) -> String:
	var now: float = float(display.get("now", 0.0))
	var next: float = float(display.get("next", now))
	var maxed := bool(display.get("maxed", false))
	match effect:
		"max_hp":
			return Loc.t_key("UPG_VALUE_HP", {"now": int(round(now)), "next": int(round(next))})
		"regen":
			return Loc.t_key("UPG_VALUE_REGEN", {"now": "%.1f" % now, "next": "%.1f" % next})
		"archer_damage":
			return Loc.t_key("UPG_VALUE_DMG", {"now": "%.1f" % now, "next": "%.1f" % next})
		"archer_speed":
			return Loc.t_key("UPG_VALUE_RATE", {"now": "%.2f" % now, "next": "%.2f" % next})
		"archer_range":
			return Loc.t_key("UPG_VALUE_RANGE", {"now": int(round(now)), "next": int(round(next))})
		"archer_count":
			return Loc.t_key("UPG_VALUE_ARCHERS", {"now": int(now), "next": int(next)})
		_:
			return Loc.t_key("UPG_MAX") if maxed else ""


func _on_cost_pressed() -> void:
	AudioManager.play_ui("ui_click")
	purchase_requested.emit(track.id)
