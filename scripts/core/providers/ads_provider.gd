class_name AdsProvider
extends RefCounted
## Interface for an ad backend.
##
## One request is resolved exactly once through `rewarded_closed` (a watched ad,
## with or without a reward) or `rewarded_failed` (load/show failure). The
## facade owns the 15 s timeout, so a provider that never answers is safe too.
##
## Interstitials use their own small signal pair. A provider must never show two
## ads at once.

signal rewarded_loaded(placement: String)
signal rewarded_shown(placement: String)
signal rewarded_failed(placement: String, reason: String)
signal rewarded_closed(placement: String, earned: bool)

signal interstitial_loaded(placement: String)
signal interstitial_shown(placement: String)
signal interstitial_failed(placement: String, reason: String)
signal interstitial_closed(placement: String)


## Prepares the SDK. Returns false when the plugin or singleton is absent, so
## `Monetization` can fall back to the fake provider.
func initialize() -> bool:
	return false


## True when a rewarded ad for `placement` is loaded and can be shown.
func is_ready(_placement: String) -> bool:
	return false


## True when an interstitial is loaded.
func is_interstitial_ready() -> bool:
	return false


## Starts loading a rewarded ad. Resolves with `rewarded_loaded` or
## `rewarded_failed`.
func load_rewarded(placement: String) -> void:
	rewarded_failed.emit(placement, "not_implemented")


## Shows the loaded rewarded ad for `placement`.
func show_rewarded(placement: String) -> void:
	rewarded_failed.emit(placement, "not_implemented")


## Starts loading an interstitial.
func load_interstitial(placement: String) -> void:
	interstitial_failed.emit(placement, "not_implemented")


## Shows the loaded interstitial.
func show_interstitial(placement: String) -> void:
	interstitial_failed.emit(placement, "not_implemented")


## Drops any half-open ad after a timeout so the backend is usable again.
func reset_state() -> void:
	pass
