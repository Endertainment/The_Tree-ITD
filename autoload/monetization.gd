extends Node
## Ads and IAP facade.
##
## Fake providers are the default and the whole game works offline. Real AdMob
## and Play Billing adapters are shipped disabled behind `USE_REAL_ADS` /
## `USE_REAL_IAP`; if a plugin is missing the facade logs one warning and falls
## back to the fake provider instead of crashing.
##
## The state machines live in `AdsFlow` and `PurchaseFlow` (child nodes). This
## autoload owns provider selection, placement rules and the save-visible
## rewards, so callers never talk to a provider directly.

const USE_REAL_ADS := false
const USE_REAL_IAP := false

var _ads: AdsFlow
var _purchases: PurchaseFlow


## Installed ad backend (read-only from the outside).
var ads_provider: AdsProvider:
	get:
		return _ads.get_provider() if _ads != null else null

## Installed billing backend (read-only from the outside).
var iap_provider: IapProvider:
	get:
		return _purchases.get_provider() if _purchases != null else null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_flows()
	initialize_providers(USE_REAL_ADS, USE_REAL_IAP)


## Selects providers. Public so tests can exercise the real-target fallback.
func initialize_providers(use_real_ads: bool, use_real_iap: bool) -> void:
	_ensure_flows()
	var chosen_ads: AdsProvider
	if use_real_ads:
		var real_ads := AdMobProvider.new()
		if real_ads.initialize():
			chosen_ads = real_ads
		else:
			push_warning("[Monetization] real ads unavailable; using the fake provider")
	if chosen_ads == null:
		chosen_ads = FakeAdsProvider.new()
	set_ads_provider(chosen_ads)

	var chosen_iap: IapProvider
	if use_real_iap:
		var real_iap := PlayBillingProvider.new()
		if real_iap.initialize():
			chosen_iap = real_iap
		else:
			push_warning("[Monetization] real billing unavailable; using the fake provider")
	if chosen_iap == null:
		chosen_iap = FakeIapProvider.new()
	set_iap_provider(chosen_iap)


## Replaces the ad backend.
func set_ads_provider(provider: AdsProvider) -> void:
	_ensure_flows()
	_ads.set_provider(provider)


## Replaces the billing backend.
func set_iap_provider(provider: IapProvider) -> void:
	_ensure_flows()
	_purchases.set_provider(provider)


## True while a rewarded or interstitial request has not resolved.
func is_ad_in_flight() -> bool:
	return _ads != null and _ads.is_in_flight()


## True when the current backend reports a rewarded placement as ready.
func is_placement_ready(placement: String) -> bool:
	return _ads != null and _ads.is_ready(placement)


## True while an interstitial could be loaded.
func is_interstitial_ready() -> bool:
	return _ads != null and _ads.is_interstitial_ready()


## Shows a rewarded ad. `callback(success)` is called exactly once.
func show_rewarded(placement: String, callback: Callable) -> void:
	_ensure_flows()
	_ads.show_rewarded(placement, callback)


## Shows an interstitial. `callback(success)` is called exactly once.
func show_interstitial(placement: String, callback: Callable = Callable()) -> void:
	_ensure_flows()
	_ads.show_interstitial(placement, callback)


## --- Placements -----------------------------------------------------------

## Grants the 1.5x trial for the next run. Callback receives
## `&"success"`, `&"failed"`, `&"owned"` or `&"active"`.
func request_speed_trial(callback: Callable) -> void:
	if SpeedService.is_speed_15_permanently_unlocked():
		_call(callback, &"owned")
		return
	if SpeedService.has_pending_trial_15():
		_call(callback, &"active")
		return
	show_rewarded(AdPolicy.P_RUN_SPEED_TRIAL, func(success: bool) -> void:
		if not success:
			_call(callback, &"failed")
			return
		SpeedService.grant_pending_trial_15()
		Analytics.log_event("speed_trial_used", {})
		_call(callback, &"success")
	)


## Current free-Gems availability. See `AdPolicy.free_gems_state`.
func get_free_gems_state() -> Dictionary:
	if GameState == null:
		return {"allowed": false, "reason": "ADS_FAILED", "remaining": 0, "today": 0}
	return AdPolicy.free_gems_state(
		GameState.get_ads(),
		int(Time.get_unix_time_from_system()),
		Time.get_date_string_from_system()
	)


## Shows the free-Gems ad and grants exactly once. Callback receives a
## dictionary with `granted`, `reason`, `remaining` and `amount`.
func request_free_gems(callback: Callable) -> void:
	var state := get_free_gems_state()
	if not bool(state.get("allowed", false)):
		_call(callback, {
			"granted": false,
			"reason": str(state.get("reason", "")),
			"remaining": int(state.get("remaining", 0)),
			"amount": 0,
		})
		return
	show_rewarded(AdPolicy.P_FREE_GEMS, func(success: bool) -> void:
		if not success:
			_call(callback, {"granted": false, "reason": "ADS_FAILED", "remaining": 0, "amount": 0})
			return
		var now_ts := int(Time.get_unix_time_from_system())
		var today := Time.get_date_string_from_system()
		GameState.update_ads(AdPolicy.record_free_gems(GameState.get_ads(), now_ts, today))
		GameState.add_gems(AdPolicy.FREE_GEMS_AMOUNT)
		SaveManager.save_now(GameState.to_dict())
		Analytics.log_event("free_gems_granted", {"amount": AdPolicy.FREE_GEMS_AMOUNT})
		_call(callback, {
			"granted": true,
			"reason": "",
			"remaining": 0,
			"amount": AdPolicy.FREE_GEMS_AMOUNT,
		})
	)


## Advances the interstitial counter after a completed run. Does not save on
## its own: the results screen's `apply_run_result` flushes the same snapshot.
func note_completed_run(runs_completed: int) -> void:
	if GameState == null:
		return
	GameState.update_ads(AdPolicy.on_run_completed(GameState.get_ads(), runs_completed))


## True when the results -> menu transition should show an interstitial now.
func is_interstitial_due() -> bool:
	if GameState == null:
		return false
	var removed := GameState.is_unlocked("remove_ads") or GameState.is_product_owned("remove_ads")
	return AdPolicy.should_show_interstitial(
		GameState.get_stat("runs"),
		int(GameState.get_ads().get("runs_since_interstitial", 0)),
		removed
	)


## Shows the results interstitial when due, then calls `callback(shown)`.
func show_results_interstitial(callback: Callable = Callable()) -> void:
	if not is_interstitial_due():
		_call(callback, false)
		return
	show_interstitial(AdPolicy.P_INTERSTITIAL_RESULTS, func(success: bool) -> void:
		if success:
			GameState.update_ads(AdPolicy.reset_interstitial_counter(GameState.get_ads()))
			SaveManager.save_now(GameState.to_dict())
		_call(callback, success)
	)


## --- IAP ------------------------------------------------------------------

## Starts a purchase. Callback receives `&"success"`, `&"cancelled"`,
## `&"failed"`, `&"owned"`, `&"busy"`, `&"no_consent"` or `&"unavailable"`.
func purchase(product_id: String, callback: Callable) -> void:
	_ensure_flows()
	_purchases.purchase(product_id, callback)


## Restores previously owned non-consumables. Callback receives
## `(product_ids: Array, ok: bool)`.
func restore_purchases(callback: Callable = Callable()) -> void:
	_ensure_flows()
	_purchases.restore(callback)


## Last purchase state for the debug panel.
func get_purchase_status() -> int:
	return _purchases.get_status() if _purchases != null else PurchaseFlow.Status.IDLE


## --- Debug/test hooks -----------------------------------------------------

## Fake rewarded delay in seconds.
func set_fake_ad_delay(seconds: float) -> void:
	if ads_provider is FakeAdsProvider:
		(ads_provider as FakeAdsProvider).delay_seconds = maxf(0.0, seconds)


## Returns the fake rewarded delay.
func get_fake_ad_delay() -> float:
	if ads_provider is FakeAdsProvider:
		return (ads_provider as FakeAdsProvider).delay_seconds
	return 0.0


## Fake purchase delay in seconds.
func set_fake_iap_delay(seconds: float) -> void:
	if iap_provider is FakeIapProvider:
		(iap_provider as FakeIapProvider).delay_seconds = maxf(0.0, seconds)


## Shortens the ad timeout for tests.
func set_ad_timeout_seconds(seconds: float) -> void:
	if _ads != null:
		_ads.set_timeout_seconds(seconds)


## Forces the next fake rewarded/interstitial outcome.
func debug_force_rewarded(outcome: String) -> void:
	if ads_provider is FakeAdsProvider:
		(ads_provider as FakeAdsProvider).set_forced_outcome(outcome)


## Forces the next fake purchase outcome.
func debug_force_purchase(outcome: String) -> void:
	if iap_provider is FakeIapProvider:
		(iap_provider as FakeIapProvider).set_forced_outcome(outcome)


## Clears ad cooldowns and counters.
func debug_reset_ads() -> void:
	if GameState == null:
		return
	GameState.reset_ads()
	SaveManager.save_now(GameState.to_dict())


## Snapshot for the debug panel.
func get_status_snapshot() -> Dictionary:
	var ads := GameState.get_ads() if GameState != null else {}
	return {
		"ads_provider": get_ads_provider_name(),
		"iap_provider": get_iap_provider_name(),
		"consent": ConsentManager.has_consent(),
		"ad_phase": _ads.get_phase() if _ads != null else 0,
		"ad_placement": _ads.get_placement() if _ads != null else "",
		"purchase_pending": _purchases.is_busy() if _purchases != null else false,
		"purchase_status": get_purchase_status(),
		"interstitial_counter": int(ads.get("runs_since_interstitial", 0)),
		"interstitial_due": is_interstitial_due(),
		"free_gems": get_free_gems_state(),
		"placements": {
			"speed_trial": not SpeedService.is_speed_15_permanently_unlocked()
				and not SpeedService.has_pending_trial_15(),
			"free_gems": bool(get_free_gems_state().get("allowed", false)),
			"interstitial": is_interstitial_due(),
		},
		"runs": GameState.get_stat("runs") if GameState != null else 0,
	}


## Human-readable provider name for the debug panel.
func get_ads_provider_name() -> String:
	return _ads.get_provider_name() if _ads != null else "None"


## Human-readable billing provider name.
func get_iap_provider_name() -> String:
	return _purchases.get_provider_name() if _purchases != null else "None"


## --- Internals ------------------------------------------------------------

func _ensure_flows() -> void:
	if _ads == null:
		_ads = AdsFlow.new()
		_ads.name = "AdsFlow"
		add_child(_ads)
	if _purchases == null:
		_purchases = PurchaseFlow.new()
		_purchases.name = "PurchaseFlow"
		add_child(_purchases)


func _call(callback: Callable, value: Variant) -> void:
	if callback.is_valid():
		callback.call(value)
