class_name FakeIapProvider
extends IapProvider
## Default billing backend: nothing is charged and every outcome is simulated.
##
## Non-consumables are "owned" through the save, so restore is simply the saved
## `shop.owned_products` list and never re-grants currency.

const DEFAULT_DELAY := 0.8

enum Outcome { NONE, SUCCESS, CANCEL, FAIL }

var delay_seconds := DEFAULT_DELAY
var forced_outcome := Outcome.NONE


func initialize() -> bool:
	return true


func is_ready() -> bool:
	return true


func purchase(product_id: String) -> void:
	Analytics.log_event("fake_purchase_started", {"product_id": product_id})
	var outcome := _pick_outcome()
	if outcome == Outcome.CANCEL:
		purchase_cancelled.emit(product_id)
		return
	if outcome == Outcome.FAIL:
		purchase_failed.emit(product_id, "forced_fail")
		return
	await _wait(delay_seconds)
	match outcome:
		Outcome.CANCEL:
			purchase_cancelled.emit(product_id)
		Outcome.FAIL:
			purchase_failed.emit(product_id, "forced_fail")
		_:
			purchase_succeeded.emit(product_id)


func restore() -> void:
	await _wait(delay_seconds * 0.25)
	var owned: Array = []
	if GameState != null:
		owned.assign(GameState.get_owned_products())
	restore_completed.emit(owned)


func get_owned_product_ids() -> Array:
	var owned: Array = []
	if GameState != null:
		owned.assign(GameState.get_owned_products())
	return owned


## Sets the next outcome from a debug-panel id.
func set_forced_outcome(outcome_name: String) -> void:
	match outcome_name:
		"success":
			forced_outcome = Outcome.SUCCESS
		"cancel":
			forced_outcome = Outcome.CANCEL
		"fail":
			forced_outcome = Outcome.FAIL
		_:
			forced_outcome = Outcome.NONE


func _pick_outcome() -> int:
	return forced_outcome if forced_outcome != Outcome.NONE else Outcome.SUCCESS


func _wait(seconds: float) -> void:
	if seconds <= 0.0:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	await tree.create_timer(seconds, true, false, true).timeout
