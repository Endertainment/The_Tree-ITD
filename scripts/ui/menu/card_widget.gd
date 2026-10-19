class_name CardWidget
extends PanelContainer
## One collectible card tile. Emits intents; the Cards screen owns the rules.

signal action_pressed(card: CardData)
signal details_requested(card: CardData)

@onready var _tint: ColorRect = %Tint
@onready var _name: Label = %Name
@onready var _state: Label = %State
@onready var _modifiers: Label = %Modifiers
@onready var _action: Button = %ActionButton

var _card: CardData


func setup(card: CardData) -> void:
	_card = card
	_action.pressed.connect(_on_action_pressed)
	gui_input.connect(_on_gui_input)
	refresh()


func refresh() -> void:
	if _card == null:
		return
	var owned := GameState.is_card_owned(_card.id)
	var equipped := GameState.get_equipped_ids().has(_card.id)
	var slots_full := GameState.get_equipped_ids().size() >= GameState.EQUIPPED_LIMIT
	_tint.color = _card.tint
	_name.text = Loc.t_key(_card.name_key)
	_modifiers.text = "\n".join(_card.modifier_lines())
	if equipped:
		_state.text = Loc.t_key("CARDS_EQUIPPED")
		_state.add_theme_color_override("font_color", Color(0.94902, 0.756863, 0.305882, 1))
	elif owned:
		_state.text = Loc.t_key("CARDS_OWNED")
		_state.add_theme_color_override("font_color", Color(0.494118, 0.784314, 0.313726, 1))
	else:
		_state.text = Loc.t_key("CARDS_LOCKED")
		_state.add_theme_color_override("font_color", Color(0.647059, 0.686275, 0.596078, 1))
	_refresh_action(owned, equipped, slots_full)


func _refresh_action(owned: bool, equipped: bool, slots_full: bool) -> void:
	if not owned:
		var missing := _card.unlock_cost - GameState.get_gems()
		if missing > 0:
			_action.text = Loc.t_key("CARDS_NEED_GEMS", {"cost": Loc.format_number(missing)})
			_action.disabled = true
		else:
			_action.text = Loc.t_key("CARDS_UNLOCK", {"cost": Loc.format_number(_card.unlock_cost)})
			_action.disabled = false
		return
	_action.disabled = false
	if equipped:
		_action.text = Loc.t_key("CARDS_UNEQUIP")
	elif slots_full:
		_action.text = Loc.t_key("CARDS_REPLACE")
	else:
		_action.text = Loc.t_key("CARDS_EQUIP")


func _on_action_pressed() -> void:
	if _card != null:
		action_pressed.emit(_card)


func _on_gui_input(event: InputEvent) -> void:
	if _card == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		details_requested.emit(_card)
