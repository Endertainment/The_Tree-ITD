class_name FakeAdsProvider
extends AdsProvider
## Default ad backend: simulates load, watch and close without any SDK.
##
## `delay_seconds` covers the whole watch. `forced_outcome` lets the debug panel
## drive every failure path; otherwise `success_rate` decides the reward.

const DEFAULT_DELAY := 2.0

enum Outcome { NONE, SUCCESS, FAIL, CLOSE, TIMEOUT }

var delay_seconds := DEFAULT_DELAY
var success_rate := 1.0
var auto_close := true
var forced_outcome := Outcome.NONE

var _showing := false
var _interstitial_showing := false
var _active_placement := ""


func initialize() -> bool:
	return true


func is_ready(_placement: String) -> bool:
	return true


func is_interstitial_ready() -> bool:
	return true


func load_rewarded(placement: String) -> void:
	Analytics.log_event("fake_ad_load", {"placement": placement, "format": "rewarded"})
	# Deferred so the facade finishes wiring its state before the callback.
	call_deferred("_emit_loaded", placement)


func show_rewarded(placement: String) -> void:
	if _showing:
		rewarded_failed.emit(placement, "busy")
		return
	_showing = true
	_active_placement = placement
	rewarded_shown.emit(placement)
	Analytics.log_event("fake_ad_shown", {"placement": placement, "format": "rewarded"})

	var outcome := _pick_outcome()
	if outcome == Outcome.TIMEOUT:
		# Deliberately never resolves; the facade timeout must recover the UI.
		_showing = false
		return

	await _wait(delay_seconds)
	if not _showing:
		return
	if not auto_close and outcome == Outcome.SUCCESS:
		# Stay open until `dismiss_rewarded` is called (debug/manual path).
		return
	if not auto_close and outcome == Outcome.CLOSE:
		return
	_resolve_rewarded(placement, outcome)


## Closes an ad that was left open by `auto_close = false`.
func dismiss_rewarded(earned: bool) -> void:
	if not _showing:
		return
	_showing = false
	rewarded_closed.emit(_active_placement, earned)


func load_interstitial(placement: String) -> void:
	Analytics.log_event("fake_ad_load", {"placement": placement, "format": "interstitial"})
	call_deferred("_emit_interstitial_loaded", placement)


func show_interstitial(placement: String) -> void:
	if _interstitial_showing:
		interstitial_failed.emit(placement, "busy")
		return
	_interstitial_showing = true
	_active_placement = placement
	interstitial_shown.emit(placement)
	Analytics.log_event("fake_ad_shown", {"placement": placement, "format": "interstitial"})

	var outcome := _pick_outcome()
	if outcome == Outcome.TIMEOUT:
		_interstitial_showing = false
		return

	await _wait(delay_seconds)
	if not _interstitial_showing:
		return
	_interstitial_showing = false
	if outcome == Outcome.FAIL:
		interstitial_failed.emit(placement, "forced_fail")
	else:
		interstitial_closed.emit(placement)


func reset_state() -> void:
	_showing = false
	_interstitial_showing = false


## Sets the next outcome from a debug-panel id.
func set_forced_outcome(outcome_name: String) -> void:
	match outcome_name:
		"success":
			forced_outcome = Outcome.SUCCESS
		"fail":
			forced_outcome = Outcome.FAIL
		"close":
			forced_outcome = Outcome.CLOSE
		"timeout":
			forced_outcome = Outcome.TIMEOUT
		_:
			forced_outcome = Outcome.NONE


func _resolve_rewarded(placement: String, outcome: int) -> void:
	_showing = false
	match outcome:
		Outcome.FAIL:
			rewarded_failed.emit(placement, "forced_fail")
		Outcome.CLOSE:
			rewarded_closed.emit(placement, false)
		_:
			rewarded_closed.emit(placement, true)


func _pick_outcome() -> int:
	if forced_outcome != Outcome.NONE:
		return forced_outcome
	return Outcome.SUCCESS if randf() <= clampf(success_rate, 0.0, 1.0) else Outcome.FAIL


func _emit_loaded(placement: String) -> void:
	rewarded_loaded.emit(placement)


func _emit_interstitial_loaded(placement: String) -> void:
	interstitial_loaded.emit(placement)


func _wait(seconds: float) -> void:
	if seconds <= 0.0:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	# Never let Engine.time_scale shorten a simulated ad.
	await tree.create_timer(seconds, true, false, true).timeout
