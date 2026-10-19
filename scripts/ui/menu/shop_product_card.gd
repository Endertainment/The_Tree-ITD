class_name ShopProductCard
extends PanelContainer
## One fake-IAP product tile.

signal buy_requested(product: ShopProduct)

@onready var _badge: Label = %Badge
@onready var _title: Label = %Title
@onready var _contents: Label = %Contents
@onready var _price: Label = %Price
@onready var _buy: Button = %BuyButton

var _product: ShopProduct
var _busy := false


func setup(product: ShopProduct) -> void:
	_product = product
	_buy.pressed.connect(_on_buy_pressed)
	refresh()


func refresh() -> void:
	if _product == null:
		return
	var owned := _product.is_one_time() and GameState.is_product_owned(_product.id)
	_title.text = Loc.t_key(_product.title_key)
	_contents.text = _product.contents_text()
	_price.text = _product.price_text
	_badge.visible = not _product.badge_key.is_empty() and not owned
	if _badge.visible:
		_badge.text = Loc.t_key(_product.badge_key)
	_buy.text = Loc.t_key("SHOP_OWNED" if owned else "SHOP_BUY")
	_buy.disabled = owned or _busy
	modulate = Color(1, 1, 1, 0.7) if owned else Color.WHITE


## Locks the button while the provider call is in flight.
func set_busy(busy: bool) -> void:
	_busy = busy
	refresh()


func _on_buy_pressed() -> void:
	if _product != null and not _busy:
		buy_requested.emit(_product)
