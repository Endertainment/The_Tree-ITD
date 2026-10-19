class_name PlayBillingProvider
extends IapProvider
## DISABLED Google Play Billing adapter.
##
## Intended plugin: the official Godot 4 Android Billing plugin (singleton
## `GodotGooglePlayBilling`). Enable `USE_REAL_IAP` only after a human supplies
## real product ids and a Play Console build.
##
## Flow:
##   1. `initialize()` connects to the billing service;
##   2. `purchase()` queries the store id from `ShopProduct.store_id` and launches
##      the purchase;
##   3. on `purchase` the adapter acknowledges a one-time product or consumes a
##      consumable **before** emitting `purchase_succeeded`;
##   4. `restore()` queries owned purchases and maps store ids back to logical
##      product ids.
##
## All calls are guarded with `has_method` / `has_signal`; without the plugin the
## adapter never initializes and `Monetization` falls back to the fake provider.
##
## TODO(verify): confirm the singleton name, method names
## (`startConnection`, `querySkuDetails`, `purchase`, `acknowledgePurchase`,
## `consumePurchase`, `queryPurchases`) and signal payload shapes for the pinned
## plugin version.

const PLUGIN_SINGLETON := "GodotGooglePlayBilling"

var _plugin: Object
var _available := false
var _pending_product := ""
var _pending_store_id := ""


func initialize() -> bool:
	if not Engine.has_singleton(PLUGIN_SINGLETON):
		return false
	_plugin = Engine.get_singleton(PLUGIN_SINGLETON)
	if _plugin == null or not _plugin.has_method("startConnection"):
		return false
	_connect_plugin_signals()
	_plugin.call("startConnection")
	_available = true
	Analytics.log_event("play_billing_initialized", {})
	return true


func is_ready() -> bool:
	return _available


func purchase(product_id: String) -> void:
	if not _available or _plugin == null:
		purchase_failed.emit(product_id, "unavailable")
		return
	var product := ConfigDB.get_product(product_id)
	if product == null:
		purchase_failed.emit(product_id, "unknown_product")
		return
	_pending_product = product_id
	_pending_store_id = product.get_store_id()
	# TODO(verify): the official plugin expects a prior `querySkuDetails` pass and
	# a `purchase(store_id)` call; wire the details cache here before enabling.
	if not _plugin.has_method("purchase"):
		purchase_failed.emit(product_id, "plugin_api_missing")
		return
	_plugin.call("purchase", _pending_store_id)


func restore() -> void:
	if not _available or _plugin == null or not _plugin.has_method("queryPurchases"):
		restore_failed.emit("unavailable")
		return
	_plugin.call("queryPurchases", "inapp")


func get_owned_product_ids() -> Array:
	return []


func _connect_plugin_signals() -> void:
	_bind_signal("purchase", _on_purchase)
	_bind_signal("purchases_updated", _on_purchases_updated)
	_bind_signal("purchase_error", _on_purchase_error)
	_bind_signal("purchases_query_completed", _on_purchases_query_completed)
	_bind_signal("purchases_query_error", _on_purchases_query_error)


func _bind_signal(signal_name: String, handler: Callable) -> void:
	if not _plugin.has_signal(signal_name) or _plugin.is_connected(signal_name, handler):
		return
	_plugin.connect(signal_name, handler)


## A finished purchase. Acknowledges/consumes before reporting success.
func _on_purchase(response: Dictionary = {}) -> void:
	var store_id := _store_id_from_response(response)
	var logical := _logical_from_store(store_id)
	if logical.is_empty() or not _available:
		purchase_failed.emit(_pending_product, "unknown_response")
		return
	var product := ConfigDB.get_product(logical)
	if product == null:
		purchase_failed.emit(_pending_product, "unknown_product")
		return
	var token := _token_from_response(response)
	var acknowledged := _acknowledge(product, token)
	if not acknowledged:
		purchase_failed.emit(logical, "ack_failed")
		return
	purchase_succeeded.emit(logical)


func _on_purchase_error(_response = null) -> void:
	purchase_failed.emit(_pending_product, "store_error")


func _on_purchases_updated(_response = null) -> void:
	# The plugin also reports finished purchases here; the facade only needs the
	# explicit purchase signal for grants, so this is a no-op placeholder.
	pass


func _on_purchases_query_completed(response: Dictionary = {}) -> void:
	var owned: Array = []
	for entry: Variant in response.get("purchases", []):
		if entry is Dictionary:
			var logical := _logical_from_store(_store_id_from_response(entry))
			if not logical.is_empty():
				owned.append(logical)
	restore_completed.emit(owned)


func _on_purchases_query_error(_response = null) -> void:
	restore_failed.emit("query_failed")


## True when the purchase was acknowledged (one-time) or consumed (repeatable).
func _acknowledge(product: ShopProduct, token: String) -> bool:
	if token.is_empty():
		return false
	var result: Variant
	if product.consumable and _plugin.has_method("consumePurchase"):
		result = _plugin.call("consumePurchase", token)
	elif not product.consumable and _plugin.has_method("acknowledgePurchase"):
		result = _plugin.call("acknowledgePurchase", token)
	else:
		return false
	# TODO(verify): the plugin may answer asynchronously instead of returning an
	# Error; never report success on a value this build does not understand.
	return typeof(result) == TYPE_INT and int(result) == OK


func _store_id_from_response(response: Dictionary) -> String:
	var products: Variant = response.get("products", [])
	if products is Array and not (products as Array).is_empty():
		return str((products as Array)[0])
	return str(response.get("product_id", ""))


func _token_from_response(response: Dictionary) -> String:
	return str(response.get("purchase_token", response.get("token", "")))


func _logical_from_store(store_id: String) -> String:
	if store_id.is_empty():
		return ""
	for product: ShopProduct in ConfigDB.all_products():
		if product.get_store_id() == store_id:
			return product.id
	return ""
