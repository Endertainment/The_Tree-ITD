class_name AdsFlow
extends Node
## Rewarded/interstitial state machine for one ad backend.
##
## Owned by `Monetization`; not an autoload. One request at a time, one
## resolution per request, a 15 s timeout, and a background guard. Placement
## eligibility (cooldowns, caps) lives in `Monetization`/`AdPolicy`; this class
## only enforces consent, pause safety and the provider protocol.

enum Phase { IDLE, LOADING, SHOWING }
enum Kind { REWARDED, INTERSTITIAL }

const DEFAULT_TIMEOUT_SECONDS := 15.0

var _provider: AdsProvider
var _phase := Phase.IDLE
var _kind := Kind.REWARDED
var _placement := ""
var _callback := Callable()
var _timer: Timer
var _timeout_seconds := DEFAULT_TIMEOUT_SECONDS
var _backgrounded := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_timer = Timer.new()
	_timer.name = "AdTimeout"
	_timer.one_shot = true
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_timer.timeout.connect(_on_timeout)
	add_child(_timer)


## Installs the backend and reconnects its signals.
func set_provider(provider: AdsProvider) -> void:
	if _provider != null:
		for entry: Array in _signal_table():
			if _provider.is_connected(entry[0], entry[1]):
				_provider.disconnect(entry[0], entry[1])
	_provider = provider
	if provider == null:
		return
	for entry: Array in _signal_table():
		if not provider.is_connected(entry[0], entry[1]):
			provider.connect(entry[0], entry[1])


## Current backend, or null.
func get_provider() -> AdsProvider:
	return _provider


## Human-readable backend name for the debug panel.
func get_provider_name() -> String:
	if _provider is FakeAdsProvider:
		return "Fake"
	if _provider is AdMobProvider:
		return "AdMob"
	return "None"


## True while a request has not resolved.
func is_in_flight() -> bool:
	return _phase != Phase.IDLE


## Current phase enum value.
func get_phase() -> int:
	return _phase


## Placement of the request in flight, or "".
func get_placement() -> String:
	return _placement


## True when a rewarded placement is ready.
func is_ready(placement: String) -> bool:
	return _provider != null and _provider.is_ready(placement)


## True when an interstitial is ready.
func is_interstitial_ready() -> bool:
	return _provider != null and _provider.is_interstitial_ready()


## Shortens the safety timeout (tests).
func set_timeout_seconds(seconds: float) -> void:
	_timeout_seconds = maxf(0.05, seconds)


## Shows a rewarded ad. `callback(success)` is called exactly once.
func show_rewarded(placement: String, callback: Callable) -> void:
	if _phase != Phase.IDLE:
		_refuse(placement, Kind.REWARDED, "busy", callback)
		return
	var refusal := _refusal_reason(placement)
	if not refusal.is_empty():
		_refuse(placement, Kind.REWARDED, refusal, callback)
		return
	_kind = Kind.REWARDED
	_placement = placement
	_callback = callback
	_phase = Phase.LOADING
	_backgrounded = false
	Analytics.log_event("ad_requested", {"placement": placement, "format": "rewarded"})
	_provider.load_rewarded(placement)


## Shows an interstitial. `callback(success)` is called exactly once.
func show_interstitial(placement: String, callback: Callable = Callable()) -> void:
	if _phase != Phase.IDLE:
		_refuse(placement, Kind.INTERSTITIAL, "busy", callback)
		return
	var refusal := _refusal_reason(placement)
	if not refusal.is_empty():
		_refuse(placement, Kind.INTERSTITIAL, refusal, callback)
		return
	_kind = Kind.INTERSTITIAL
	_placement = placement
	_callback = callback
	_phase = Phase.LOADING
	_backgrounded = false
	Analytics.log_event("ad_requested", {"placement": placement, "format": "interstitial"})
	_provider.load_interstitial(placement)


func _refusal_reason(placement: String) -> String:
	if _provider == null:
		return "unavailable"
	if not ConsentManager.can_request_ads():
		return "no_consent"
	if get_tree() != null and get_tree().paused and not AdPolicy.is_paused_allowed(placement):
		return "paused"
	return ""


func _refuse(placement: String, kind: int, reason: String, callback: Callable) -> void:
	Analytics.log_event("ad_failed", {"placement": placement, "reason": reason})
	if kind == Kind.REWARDED:
		EventBus.ad_watched.emit(placement, false)
	if callback.is_valid():
		callback.call(false)


func _is_current(placement: String, kind: int) -> bool:
	return _phase != Phase.IDLE and _kind == kind and _placement == placement


func _on_rewarded_loaded(placement: String) -> void:
	if not _is_current(placement, Kind.REWARDED):
		return
	_phase = Phase.SHOWING
	_timer.start(_timeout_seconds)
	Analytics.log_event("ad_shown", {"placement": placement, "format": "rewarded"})
	_provider.show_rewarded(placement)


func _on_rewarded_shown(_placement: String) -> void:
	pass


func _on_rewarded_failed(placement: String, reason: String) -> void:
	if not _is_current(placement, Kind.REWARDED):
		return
	_finish_rewarded(false, reason)


func _on_rewarded_closed(placement: String, earned: bool) -> void:
	if not _is_current(placement, Kind.REWARDED):
		return
	_finish_rewarded(earned, "earned" if earned else "closed")


func _finish_rewarded(success: bool, reason: String) -> void:
	if _phase == Phase.IDLE or _kind != Kind.REWARDED:
		return
	var placement := _placement
	var callback := _callback
	_timer.stop()
	_phase = Phase.IDLE
	_placement = ""
	_callback = Callable()
	if success:
		Analytics.log_event("ad_rewarded", {"placement": placement})
	else:
		Analytics.log_event("ad_failed", {"placement": placement, "reason": reason})
	EventBus.ad_watched.emit(placement, success)
	if callback.is_valid():
		callback.call(success)


func _on_interstitial_loaded(placement: String) -> void:
	if not _is_current(placement, Kind.INTERSTITIAL):
		return
	_phase = Phase.SHOWING
	_timer.start(_timeout_seconds)
	Analytics.log_event("ad_shown", {"placement": placement, "format": "interstitial"})
	_provider.show_interstitial(placement)


func _on_interstitial_shown(_placement: String) -> void:
	pass


func _on_interstitial_failed(placement: String, reason: String) -> void:
	if not _is_current(placement, Kind.INTERSTITIAL):
		return
	_finish_interstitial(false, reason)


func _on_interstitial_closed(placement: String) -> void:
	if not _is_current(placement, Kind.INTERSTITIAL):
		return
	_finish_interstitial(true, "closed")


func _finish_interstitial(success: bool, reason: String) -> void:
	if _phase == Phase.IDLE or _kind != Kind.INTERSTITIAL:
		return
	var placement := _placement
	var callback := _callback
	_timer.stop()
	_phase = Phase.IDLE
	_placement = ""
	_callback = Callable()
	if success:
		Analytics.log_event("interstitial_shown", {"placement": placement})
	else:
		Analytics.log_event("ad_failed", {"placement": placement, "reason": reason})
	if callback.is_valid():
		callback.call(success)


func _on_timeout() -> void:
	if _phase == Phase.IDLE:
		return
	if _provider != null:
		_provider.reset_state()
	if _kind == Kind.REWARDED:
		_finish_rewarded(false, "timeout")
	else:
		_finish_interstitial(false, "timeout")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		if _phase != Phase.IDLE:
			_backgrounded = true
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		if not _backgrounded:
			return
		_backgrounded = false
		if _phase == Phase.IDLE:
			return
		if _provider != null:
			_provider.reset_state()
		if _kind == Kind.REWARDED:
			_finish_rewarded(false, "backgrounded")
		else:
			_finish_interstitial(false, "backgrounded")


func _signal_table() -> Array:
	return [
		["rewarded_loaded", Callable(self, "_on_rewarded_loaded")],
		["rewarded_shown", Callable(self, "_on_rewarded_shown")],
		["rewarded_failed", Callable(self, "_on_rewarded_failed")],
		["rewarded_closed", Callable(self, "_on_rewarded_closed")],
		["interstitial_loaded", Callable(self, "_on_interstitial_loaded")],
		["interstitial_shown", Callable(self, "_on_interstitial_shown")],
		["interstitial_failed", Callable(self, "_on_interstitial_failed")],
		["interstitial_closed", Callable(self, "_on_interstitial_closed")],
	]
