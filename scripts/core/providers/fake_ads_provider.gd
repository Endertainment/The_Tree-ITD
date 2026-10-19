class_name FakeAdsProvider
extends AdsProvider
## MVP ad provider: succeeds after a configurable delay, never shows UI.

const DEFAULT_DELAY := 2.0

## Simulated load/watch time in seconds. Tests set this to 0.
var delay := DEFAULT_DELAY


func is_ready() -> bool:
	return true


func show_rewarded(placement: String, callback: Callable) -> void:
	Analytics.log_event("fake_ad_show", {"placement": placement, "format": "rewarded"})
	await _wait(delay)
	if callback.is_valid():
		callback.call(true)


func show_interstitial(callback: Callable = Callable()) -> void:
	Analytics.log_event("fake_ad_show", {"format": "interstitial"})
	await _wait(delay)
	if callback.is_valid():
		callback.call()


func _wait(seconds: float) -> void:
	if seconds <= 0.0:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	# Never let Engine.time_scale shorten a simulated ad.
	await tree.create_timer(seconds, true, false, true).timeout
