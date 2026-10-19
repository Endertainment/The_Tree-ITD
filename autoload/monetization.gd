extends Node
## Ads and IAP facade. Fake providers by default; real SDK adapters plug in
## behind the same interface in stage 6.

var ads_provider: AdsProvider
var iap_provider: IapProvider


func _ready() -> void:
	if ads_provider == null:
		ads_provider = FakeAdsProvider.new()
	if iap_provider == null:
		iap_provider = FakeIapProvider.new()


func is_ads_ready() -> bool:
	return ads_provider != null and ads_provider.is_ready()


## Shows a rewarded ad. `callback(success)` is always called exactly once.
func show_rewarded(placement: String, callback: Callable) -> void:
	if not is_ads_ready():
		push_warning("[Monetization] no ad available for '%s'" % placement)
		_finish_rewarded(placement, false, callback)
		return
	ads_provider.show_rewarded(
		placement,
		func(success: bool) -> void:
			_finish_rewarded(placement, success, callback)
	)


## Shows an interstitial. `callback()` runs when the ad is dismissed.
func show_interstitial(callback: Callable = Callable()) -> void:
	if ads_provider == null:
		if callback.is_valid():
			callback.call()
		return
	ads_provider.show_interstitial(callback)


## Starts an IAP. `callback(success)` is always called exactly once.
func purchase(product_id: String, callback: Callable) -> void:
	if iap_provider == null:
		EventBus.purchase_completed.emit(product_id, false)
		if callback.is_valid():
			callback.call(false)
		return
	iap_provider.purchase(
		product_id,
		func(success: bool) -> void:
			EventBus.purchase_completed.emit(product_id, success)
			if callback.is_valid():
				callback.call(success)
	)


## Restores previous purchases. `callback(product_ids)` receives an array.
func restore_purchases(callback: Callable = Callable()) -> void:
	if iap_provider == null:
		if callback.is_valid():
			callback.call([])
		return
	iap_provider.restore(callback)


## Overrides the fake rewarded-ad delay, in seconds.
func set_fake_ad_delay(seconds: float) -> void:
	if ads_provider is FakeAdsProvider:
		(ads_provider as FakeAdsProvider).delay = maxf(0.0, seconds)


## Returns the fake rewarded-ad delay, in seconds.
func get_fake_ad_delay() -> float:
	if ads_provider is FakeAdsProvider:
		return (ads_provider as FakeAdsProvider).delay
	return 0.0


func _finish_rewarded(placement: String, success: bool, callback: Callable) -> void:
	EventBus.ad_watched.emit(placement, success)
	Analytics.log_event("ad_watched", {"placement": placement, "success": success})
	if callback.is_valid():
		callback.call(success)
