extends MenuScreen
## Shop tab: eight fake-IAP products with exactly-once grants and restore.

const CARD_SCENE := preload("res://scenes/menu/ShopProductCard.tscn")

@onready var _header: Label = %Header
@onready var _banner: Label = %Banner
@onready var _list: VBoxContainer = %List
@onready var _restore: Button = %RestoreButton

var _cards: Dictionary = {}
var _busy := ""


func _ready() -> void:
	_restore.pressed.connect(_on_restore_pressed)
	for product: ShopProduct in ConfigDB.all_products():
		var card := CARD_SCENE.instantiate() as ShopProductCard
		_list.add_child(card)
		card.setup(product)
		card.buy_requested.connect(_on_buy_requested)
		_cards[product.id] = card


func refresh() -> void:
	_header.text = Loc.t_key("SHOP_HEADER")
	_banner.text = Loc.t_key("SHOP_BANNER")
	_banner.visible = Monetization.iap_provider is FakeIapProvider
	_restore.text = Loc.t_key("SHOP_RESTORE")
	_restore.disabled = not _busy.is_empty()
	for id: String in _cards:
		var card := _cards[id] as ShopProductCard
		var product := ConfigDB.get_product(id)
		card.refresh()
		var owned := product.is_one_time() and GameState.is_product_owned(id)
		card.visible = not (owned and product.unlock_flag.is_empty())


func _on_buy_requested(product: ShopProduct) -> void:
	AudioManager.play_ui("ui_click")
	main_menu.open_modal(
		Loc.t_key("SHOP_CONFIRM_TITLE"),
		Loc.t_key("SHOP_CONFIRM_BODY", {
			"product": Loc.t_key(product.title_key),
			"price": product.price_text,
		}),
		"SHOP_BUY",
		"COMMON_CANCEL",
		func() -> void:
			_start_purchase(product)
	)


func _start_purchase(product: ShopProduct) -> void:
	if not _busy.is_empty():
		return
	_busy = product.id
	(_cards[product.id] as ShopProductCard).set_busy(true)
	_restore.disabled = true
	Monetization.purchase(product.id, func(success: bool) -> void:
		_on_purchase_finished(product, success)
	)


func _on_purchase_finished(product: ShopProduct, success: bool) -> void:
	_busy = ""
	(_cards[product.id] as ShopProductCard).set_busy(false)
	if success:
		if MetaShop.grant(product.id):
			main_menu.show_toast(Loc.t_key("SHOP_SUCCESS"))
		else:
			main_menu.show_toast(Loc.t_key("SHOP_ALREADY"))
	else:
		main_menu.show_toast(Loc.t_key("SHOP_FAILED"))
	refresh()


func _on_restore_pressed() -> void:
	AudioManager.play_ui("ui_click")
	Monetization.restore_purchases(func(ids: Array) -> void:
		_on_restore_finished(ids)
	)


## The fake provider has no server state, so the save is the source of truth for
## what this profile already owns. Restore only re-applies permanent unlocks and
## never re-grants currency.
func _on_restore_finished(restored_ids: Array) -> void:
	var owned := GameState.get_owned_products()
	for value: Variant in restored_ids:
		var id := str(value)
		if not owned.has(id):
			owned.append(id)
	MetaShop.restore_owned()
	if owned.is_empty():
		main_menu.show_toast(Loc.t_key("SHOP_NOTHING"))
	else:
		main_menu.show_toast(Loc.t_key("SHOP_RESTORED"))
	refresh()
