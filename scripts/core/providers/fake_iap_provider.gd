class_name FakeIapProvider
extends IapProvider
## MVP billing provider: every purchase succeeds immediately, nothing is charged.


func purchase(product_id: String, callback: Callable) -> void:
	Analytics.log_event("fake_purchase", {"product_id": product_id})
	if callback.is_valid():
		callback.call(true)


func restore(callback: Callable = Callable()) -> void:
	var owned: Array = []
	if GameState != null:
		owned.assign(GameState.get_owned_products())
	if callback.is_valid():
		callback.call(owned)
