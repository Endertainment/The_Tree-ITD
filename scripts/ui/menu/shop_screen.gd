extends MenuScreen
## Shop tab: eight fake-IAP products with exactly-once grants and restore.

const CARD_SCENE := preload("res://scenes/menu/ShopProductCard.tscn")

@onready var _header: Label = %Header
@onready var _banner: Label = %Banner
@onready var _free_title: Label = %FreeTitle
@onready var _free_status: Label = %FreeStatus
@onready var _free_button: Button = %FreeButton
@onready var _free_spinner: AdSpinner = %FreeSpinner
@onready var _list: VBoxContainer = %List
@onready var _restore: Button = %RestoreButton

var _cards: Dictionary = {}
var _busy := ""
var _free_busy := false


func _ready() -> void:
	_restore.pressed.connect(_on_restore_pressed)
	_free_button.pressed.connect(_on_free_gems_pressed)
	for product: ShopProduct in ConfigDB.all_products():
		var card := CARD_SCENE.instantiate() as ShopProductCard
		_list.add_child(card)
		card.setup(product)
		card.buy_requested.connect(_on_buy_requested)
		_cards[product.id] = card


func refresh() -> void:
	_header.text = Loc.t_key("SHOP_HEADER")
	_banner.text = Loc.t_key("SHOP_TEST_MODE")
	_banner.visible = Monetization.iap_provider is FakeIapProvider
	_free_title.text = Loc.t_key("FREE_GEMS_TITLE")
	_restore.text = Loc.t_key("SHOP_RESTORE")
	_restore.disabled = not _busy.is_empty()
	_refresh_free_gems()
	for id: String in _cards:
		var card := _cards[id] as ShopProductCard
		var product := ConfigDB.get_product(id)
		card.refresh()
		var owned := product.is_one_time() and GameState.is_product_owned(id)
		card.visible = not (owned and product.unlock_flag.is_empty())


func _refresh_free_gems() -> void:
	var state := Monetization.get_free_gems_state()
	var today := int(state.get("today", 0))
	var remaining := int(state.get("remaining", 0))
	_free_button.disabled = _free_busy or not bool(state.get("allowed", false))
	if _free_busy:
		_free_button.text = Loc.t_key("FREE_GEMS_LOADING")
	elif bool(state.get("allowed", false)):
		_free_button.text = Loc.t_key("FREE_GEMS_READY", {
			"amount": AdPolicy.FREE_GEMS_AMOUNT,
		})
	elif str(state.get("reason", "")) == "ADS_FREE_GEMS_CAP":
		_free_button.text = Loc.t_key("FREE_GEMS_CAP")
	else:
		_free_button.text = Loc.t_key("FREE_GEMS_COOLDOWN", {
			"time": _format_cooldown(remaining),
		})
	_free_status.text = Loc.t_key("FREE_GEMS_STATUS", {
		"today": today,
		"cap": AdPolicy.FREE_GEMS_DAILY_CAP,
	})
	if _free_busy:
		_free_spinner.start()
	else:
		_free_spinner.stop()


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
	Monetization.purchase(product.id, func(outcome: StringName) -> void:
		_on_purchase_finished(product, outcome)
	)


func _on_purchase_finished(product: ShopProduct, outcome: StringName) -> void:
	_busy = ""
	(_cards[product.id] as ShopProductCard).set_busy(false)
	match outcome:
		&"success":
			main_menu.show_toast(Loc.t_key("SHOP_SUCCESS"))
		&"owned":
			main_menu.show_toast(Loc.t_key("SHOP_ALREADY"))
		&"cancelled":
			main_menu.show_toast(Loc.t_key("SHOP_CANCELLED"))
		&"no_consent":
			main_menu.show_toast(Loc.t_key("SHOP_NO_CONSENT"))
		&"busy":
			pass
		_:
			main_menu.show_toast(Loc.t_key("SHOP_FAILED"))
	refresh()


func _on_free_gems_pressed() -> void:
	if _free_busy:
		return
	AudioManager.play_ui("ui_click")
	_free_busy = true
	_refresh_free_gems()
	Monetization.request_free_gems(_on_free_gems_result)


func _on_free_gems_result(result: Dictionary) -> void:
	_free_busy = false
	if bool(result.get("granted", false)):
		main_menu.show_toast(Loc.t_key("FREE_GEMS_SUCCESS", {
			"amount": int(result.get("amount", AdPolicy.FREE_GEMS_AMOUNT)),
		}))
	else:
		var reason := str(result.get("reason", ""))
		if reason.is_empty() or reason == "ADS_FAILED":
			main_menu.show_toast(Loc.t_key("FREE_GEMS_FAILED"))
		else:
			main_menu.show_toast(Loc.t_key(reason))
	refresh()


func _on_restore_pressed() -> void:
	AudioManager.play_ui("ui_click")
	_restore.disabled = true
	Monetization.restore_purchases(func(ids: Array, ok: bool) -> void:
		_on_restore_finished(ids, ok)
	)


## Restore only re-applies permanent unlocks; the backend owns the receipt, so
## currency is never re-granted here.
func _on_restore_finished(_restored_ids: Array, ok: bool) -> void:
	if not ok:
		main_menu.show_toast(Loc.t_key("SHOP_RESTORE_FAILED"))
	elif GameState.get_owned_products().is_empty():
		main_menu.show_toast(Loc.t_key("SHOP_NOTHING"))
	else:
		main_menu.show_toast(Loc.t_key("SHOP_RESTORED"))
	refresh()


## "3h 12m" / "12m" for the free-Gems cooldown label.
func _format_cooldown(seconds: int) -> String:
	if seconds <= 0:
		return Loc.t_key("DEBUG_READY")
	var minutes := int(ceil(float(seconds) / 60.0))
	if minutes >= 60:
		return Loc.t_key("TIME_HOURS_MINUTES", {
			"hours": minutes / 60,
			"minutes": minutes % 60,
		})
	return Loc.t_key("TIME_MINUTES", {"minutes": minutes})
