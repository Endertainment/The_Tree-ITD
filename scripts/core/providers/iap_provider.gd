class_name IapProvider
extends RefCounted
## Interface for an in-app purchase backend.
##
## Implementations must resolve their callback exactly once, on success and on
## every failure path.


## Starts a purchase. `callback(success: bool)` must always fire.
func purchase(_product_id: String, callback: Callable) -> void:
	if callback.is_valid():
		callback.call(false)


## Restores previous purchases. `callback(product_ids: Array)` must always fire.
func restore(callback: Callable = Callable()) -> void:
	if callback.is_valid():
		callback.call([])
