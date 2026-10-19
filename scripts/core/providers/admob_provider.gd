class_name AdMobProvider
extends AdsProvider
## DISABLED AdMob adapter.
##
## Intended plugin: Poing Studios `godot-admob-android`, Godot 4 build, Android
## only. Add it as an Android plugin and enable `USE_REAL_ADS` in
## `autoload/monetization.gd` only after a human supplies real app/unit ids.
##
## Initialization order (when the plugin is installed):
##   1. the plugin autoload registers the `AdMob` singleton at engine start;
##   2. `initialize()` configures it with `StoreConfig.admob_app_id`;
##   3. `ConsentManager.can_request_ads()` must be true before any load;
##   4. `load_rewarded()` loads the unit, `show_rewarded()` presents it.
##
## The exact plugin method and signal names below are the Poing 4.x surface and
## are guarded with `has_method` / `has_signal`. They are not executed in this
## project because the plugin is absent.
##
## TODO(verify): confirm the 4.x method names (`initialize`, `load_rewarded_ad`,
## `show_rewarded_ad`, `load_interstitial_ad`, `show_interstitial_ad`) and the
## signal arities against the plugin version pinned for release.
##
## TODO(families): the MVP is not child-directed; do not enable behavioural
## targeting or add this app to a Families programme without a policy review.

const PLUGIN_SINGLETON := "AdMob"
const PLUGIN_CLASS := "AdMob"

var _plugin: Object
var _available := false
var _pending_placement := ""
var _last_earned := false
var _loaded_rewarded := false
var _loaded_interstitial := false


func initialize() -> bool:
	if Engine.has_singleton(PLUGIN_SINGLETON):
		_plugin = Engine.get_singleton(PLUGIN_SINGLETON)
	elif ClassDB.class_exists(PLUGIN_CLASS):
		# The class exists but no autoload singleton was registered.
		return false
	else:
		return false
	if _plugin == null or not _plugin.has_method("initialize"):
		return false
	var config := ConfigDB.get_store_config()
	_plugin.call("initialize")
	_connect_plugin_signals()
	Analytics.log_event("admob_initialized", {"test_ids": config.use_test_ids})
	_available = true
	return true


func is_ready(placement: String) -> bool:
	return _available and _loaded_rewarded and not placement.is_empty()


func is_interstitial_ready() -> bool:
	return _available and _loaded_interstitial


func load_rewarded(placement: String) -> void:
	if not _can_request(placement, "rewarded"):
		return
	_pending_placement = placement
	_loaded_rewarded = false
	var unit := ConfigDB.get_store_config().rewarded_unit_id
	if _plugin.has_method("load_rewarded_ad"):
		_plugin.call("load_rewarded_ad", unit)
	else:
		rewarded_failed.emit(placement, "plugin_api_missing")


func show_rewarded(placement: String) -> void:
	if not _available or not _loaded_rewarded:
		rewarded_failed.emit(placement, "not_loaded")
		return
	_last_earned = false
	if _plugin.has_method("show_rewarded_ad"):
		_plugin.call("show_rewarded_ad")
	elif _plugin.has_method("show_rewarded"):
		_plugin.call("show_rewarded")
	else:
		rewarded_failed.emit(placement, "plugin_api_missing")


func load_interstitial(placement: String) -> void:
	if not _can_request(placement, "interstitial"):
		return
	_pending_placement = placement
	_loaded_interstitial = false
	var unit := ConfigDB.get_store_config().interstitial_unit_id
	if _plugin.has_method("load_interstitial_ad"):
		_plugin.call("load_interstitial_ad", unit)
	else:
		interstitial_failed.emit(placement, "plugin_api_missing")


func show_interstitial(placement: String) -> void:
	if not _available or not _loaded_interstitial:
		interstitial_failed.emit(placement, "not_loaded")
		return
	if _plugin.has_method("show_interstitial_ad"):
		_plugin.call("show_interstitial_ad")
	elif _plugin.has_method("show_interstitial"):
		_plugin.call("show_interstitial")
	else:
		interstitial_failed.emit(placement, "plugin_api_missing")


func reset_state() -> void:
	_loaded_rewarded = false
	_loaded_interstitial = false


## Applies the EEA consent gate before every request. The MVP stub returns true.
func _can_request(placement: String, format: String) -> bool:
	if not ConsentManager.can_request_ads():
		_emit_failure(placement, format, "no_consent")
		return false
	if not _available or _plugin == null:
		_emit_failure(placement, format, "unavailable")
		return false
	return true


func _emit_failure(placement: String, format: String, reason: String) -> void:
	if format == "interstitial":
		interstitial_failed.emit(placement, reason)
	else:
		rewarded_failed.emit(placement, reason)


func _connect_plugin_signals() -> void:
	_bind_signal("rewarded_ad_loaded", _on_rewarded_loaded)
	_bind_signal("rewarded_ad_failed_to_load", _on_rewarded_failed)
	_bind_signal("rewarded_ad_shown", _on_rewarded_shown)
	_bind_signal("user_earned_rewarded", _on_rewarded_earned)
	_bind_signal("rewarded_ad_dismissed", _on_rewarded_dismissed)
	_bind_signal("interstitial_ad_loaded", _on_interstitial_loaded)
	_bind_signal("interstitial_ad_failed_to_load", _on_interstitial_failed)
	_bind_signal("interstitial_ad_shown", _on_interstitial_shown)
	_bind_signal("interstitial_ad_dismissed", _on_interstitial_dismissed)


func _bind_signal(signal_name: String, handler: Callable) -> void:
	if not _plugin.has_signal(signal_name) or _plugin.is_connected(signal_name, handler):
		return
	_plugin.connect(signal_name, handler)


func _on_rewarded_loaded(_a = null) -> void:
	_loaded_rewarded = true
	rewarded_loaded.emit(_pending_placement)


func _on_rewarded_failed(_a = null, _b = null) -> void:
	_loaded_rewarded = false
	rewarded_failed.emit(_pending_placement, "load_failed")


func _on_rewarded_shown(_a = null) -> void:
	rewarded_shown.emit(_pending_placement)


func _on_rewarded_earned(_a = null, _b = null) -> void:
	_last_earned = true


func _on_rewarded_dismissed(_a = null) -> void:
	_loaded_rewarded = false
	rewarded_closed.emit(_pending_placement, _last_earned)
	_last_earned = false


func _on_interstitial_loaded(_a = null) -> void:
	_loaded_interstitial = true
	interstitial_loaded.emit(_pending_placement)


func _on_interstitial_failed(_a = null, _b = null) -> void:
	_loaded_interstitial = false
	interstitial_failed.emit(_pending_placement, "load_failed")


func _on_interstitial_shown(_a = null) -> void:
	interstitial_shown.emit(_pending_placement)


func _on_interstitial_dismissed(_a = null) -> void:
	_loaded_interstitial = false
	interstitial_closed.emit(_pending_placement)
