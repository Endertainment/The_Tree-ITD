extends MenuScreen
## Cards tab: unlock with Gems, equip at most two, inspect modifiers.

const CARD_SCENE := preload("res://scenes/menu/CardWidget.tscn")
const GREEN := Color(0.494118, 0.784314, 0.313726, 1)
const RED := Color(0.898039, 0.423529, 0.360784, 1)

@onready var _header: Label = %Header
@onready var _hint: Label = %Hint
@onready var _grid: GridContainer = %Grid

var _widgets: Array[CardWidget] = []


func _ready() -> void:
	var cards := ConfigDB.all_cards()
	cards.sort_custom(func(a: CardData, b: CardData) -> bool: return a.unlock_cost < b.unlock_cost)
	for card: CardData in cards:
		var widget := CARD_SCENE.instantiate() as CardWidget
		_grid.add_child(widget)
		widget.setup(card)
		widget.action_pressed.connect(_on_card_action)
		widget.details_requested.connect(_on_card_details)
		_widgets.append(widget)


func refresh() -> void:
	_header.text = Loc.t_key("CARDS_HEADER")
	_hint.text = Loc.t_key("CARDS_HINT")
	for widget: CardWidget in _widgets:
		widget.refresh()


func _on_card_action(card: CardData) -> void:
	AudioManager.play_ui("ui_click")
	if not GameState.is_card_owned(card.id):
		_confirm_unlock(card)
		return
	if GameState.get_equipped_ids().has(card.id):
		GameState.unequip_card(card.id)
		main_menu.show_toast(Loc.t_key("CARDS_UNEQUIPPED_TOAST", {
			"name": Loc.t_key(card.name_key),
		}))
		refresh()
		return
	if GameState.get_equipped_ids().size() >= GameState.EQUIPPED_LIMIT:
		_open_replace(card)
		return
	GameState.equip_card(card.id)
	SaveManager.save_now(GameState.to_dict())
	main_menu.show_toast(Loc.t_key("CARDS_EQUIPPED_TOAST", {
		"name": Loc.t_key(card.name_key),
	}))
	refresh()


func _confirm_unlock(card: CardData) -> void:
	var cost := card.unlock_cost
	main_menu.open_modal(
		Loc.t_key("CARDS_UNLOCK_TITLE"),
		Loc.t_key("CARDS_UNLOCK_BODY", {
			"name": Loc.t_key(card.name_key),
			"cost": Loc.format_number(cost),
		}),
		Loc.t_key("CARDS_UNLOCK", {"cost": Loc.format_number(cost)}),
		"COMMON_CANCEL",
		func() -> void:
			if not GameState.spend_gems(cost):
				main_menu.show_toast(Loc.t_key("CARDS_NEED_GEMS", {
					"cost": Loc.format_number(cost - GameState.get_gems()),
				}))
				return
			GameState.own_card(card.id)
			SaveManager.save_now(GameState.to_dict())
			Analytics.log_event("card_unlocked", {"card": card.id, "cost": cost})
			main_menu.show_toast(Loc.t_key("CARDS_UNLOCKED", {
				"name": Loc.t_key(card.name_key),
			}))
			refresh()
	)


func _open_replace(card: CardData) -> void:
	var modal: ModalSheet = main_menu.open_modal(
		Loc.t_key("CARDS_REPLACE_TITLE"),
		Loc.t_key("CARDS_REPLACE_BODY", {"name": Loc.t_key(card.name_key)}),
		"",
		"COMMON_CANCEL"
	)
	for equipped_id: String in GameState.get_equipped_ids():
		var equipped_card := ConfigDB.get_card(equipped_id)
		if equipped_card == null:
			continue
		var button := Button.new()
		button.text = Loc.t_key(equipped_card.name_key)
		button.theme_type_variation = &"RowButton"
		button.custom_minimum_size = Vector2(0, 88)
		button.pressed.connect(_replace_with.bind(equipped_id, card.id, modal))
		modal.add_content(button)


func _replace_with(old_id: String, new_id: String, modal: ModalSheet) -> void:
	modal.close()
	GameState.replace_equipped_card(old_id, new_id)
	SaveManager.save_now(GameState.to_dict())
	main_menu.show_toast(Loc.t_key("CARDS_EQUIPPED_TOAST", {
		"name": Loc.t_key(ConfigDB.get_card(new_id).name_key),
	}))
	refresh()


func _on_card_details(card: CardData) -> void:
	AudioManager.play_ui("ui_click")
	var modal: ModalSheet = main_menu.open_modal(
		Loc.t_key(card.name_key),
		Loc.t_key(card.lore_key),
		"",
		"COMMON_CLOSE"
	)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var description := Label.new()
	description.text = Loc.t_key(card.description_key)
	description.theme_type_variation = &"HudSmall"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(description)
	for line: String in card.modifier_lines():
		var label := Label.new()
		label.text = line
		label.theme_type_variation = &"HudLabel"
		label.add_theme_color_override("font_color", RED if line.begins_with("-") else GREEN)
		box.add_child(label)
	modal.add_content(box)
