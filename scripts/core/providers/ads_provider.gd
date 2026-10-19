class_name AdsProvider
extends RefCounted
## Interface for an ad backend.
##
## Implementations must resolve their callback exactly once, on success and on
## every failure path, so callers can never soft-lock.


## True when an ad is loaded and can be shown right now.
func is_ready() -> bool:
	return false


## Shows a rewarded ad. `callback(success: bool)` must always fire.
func show_rewarded(_placement: String, callback: Callable) -> void:
	if callback.is_valid():
		callback.call(false)


## Shows an interstitial. `callback()` runs when it is dismissed.
func show_interstitial(callback: Callable = Callable()) -> void:
	if callback.is_valid():
		callback.call()
