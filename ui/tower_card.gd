class_name TowerCard
extends Button
## Build-sheet card for one tower type: icon, name, cost, role and DPS estimate.
##
## A disabled card dims to 40%, shows a lock overlay and prints the reason, so
## the player never has to guess why a tower is unavailable.

var tower_id := ""

@onready var _icon: TowerIcon = %Icon
@onready var _name: Label = %CardName
@onready var _cost: Label = %CardCost
@onready var _role: Label = %CardRole
@onready var _dps: Label = %CardDps
@onready var _lock: ColorRect = %LockOverlay
@onready var _lock_label: Label = %LockLabel
@onready var _reason: Label = %Reason


## Fills the card from tower data and the discounted price for this run.
func setup(data: TowerData, price: int, affordable: bool, reason: String) -> void:
	if data == null:
		return
	tower_id = data.id
	UISkin.apply_card_background(self, data.id)
	_icon.setup(data.silhouette, 1, data.base_color, data.accent_color)
	_name.text = Loc.t_key(data.display_name_key)
	_cost.text = Loc.format_number(price)
	_role.text = Loc.t_key(data.role_key)
	_dps.text = Loc.t_key("SHEET_CARD_DPS", {"value": int(round(data.dps_at(1)))})

	disabled = not affordable
	modulate = Color(1.0, 1.0, 1.0, 0.4 if disabled else 1.0)
	_lock.visible = disabled
	_lock_label.visible = disabled
	_lock_label.text = Loc.t_key("SHEET_LOCKED")
	_reason.text = reason
	_reason.visible = not reason.is_empty()
	_reason.modulate = Color(1.0, 0.62, 0.5) if disabled else Color(0.6, 0.85, 0.55)
