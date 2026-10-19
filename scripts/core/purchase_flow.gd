class_name PurchaseFlow
extends Node
## Purchase/restore state machine for one billing backend.
##
## Owned by `Monetization`; not an autoload. Grants through `MetaShop` after the
## provider reports an acknowledged purchase, so a provider can never pay twice
## and a cancelled/failed transaction never grants.

enum Status { IDLE, PENDING, SUCCESS, CANCELLED, FAILED }

const TIMEOUT_SECONDS := 10.0
const RESTORE_TIMEOUT_SECONDS := 10.0

var _provider: IapProvider
var _status := Status.IDLE
var _pending := false
var _product_id := ""
var _callback := Callable()
var _timer: Timer

var _restore_pending := false
var _restore_callback := Callable()
var _restore_timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_timer = _make_timer("PurchaseTimeout", _on_timeout)
	_restore_timer = _make_timer("RestoreTimeout", _on_restore_timeout)


## Installs the backend and reconnects its signals.
func set_provider(provider: IapProvider) -> void:
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
func get_provider() -> IapProvider:
	return _provider


## Human-readable backend name for the debug panel.
func get_provider_name() -> String:
	if _provider is FakeIapProvider:
		return "Fake"
	if _provider is PlayBillingProvider:
		return "Play Billing"
	return "None"


## Last completed state.
func get_status() -> int:
	return _status


## True while a purchase or restore is in flight.
func is_busy() -> bool:
	return _pending or _restore_pending


## Starts a purchase. Callback receives `&"success"`, `&"cancelled"`,
## `&"failed"`, `&"owned"`, `&"busy"`, `&"no_consent"` or `&"unavailable"`.
func purchase(product_id: String, callback: Callable) -> void:
	var product := ConfigDB.get_product(product_id)
	if product == null:
		_status = Status.FAILED
		_call(callback, &"failed")
		return
	if not ConsentManager.can_purchase():
		_status = Status.FAILED
		_call(callback, &"no_consent")
		return
	if product.is_one_time() and GameState.is_product_owned(product_id):
		_status = Status.IDLE
		_call(callback, &"owned")
		return
	if _pending:
		_call(callback, &"busy")
		return
	if _provider == null:
		_status = Status.FAILED
		_call(callback, &"unavailable")
		return
	_pending = true
	_product_id = product_id
	_callback = callback
	_status = Status.PENDING
	_timer.start(TIMEOUT_SECONDS)
	Analytics.log_event("purchase_started", {"product_id": product_id})
	_provider.purchase(product_id)


## Restores owned non-consumables. Callback receives `(ids: Array, ok: bool)`.
func restore(callback: Callable = Callable()) -> void:
	if _restore_pending:
		_call_restore(callback, [], false)
		return
	if _provider == null:
		_call_restore(callback, [], false)
		return
	_restore_pending = true
	_restore_callback = callback
	_restore_timer.start(RESTORE_TIMEOUT_SECONDS)
	Analytics.log_event("purchase_restore_started", {})
	_provider.restore()


func _make_timer(timer_name: String, callback: Callable) -> Timer:
	var timer := Timer.new()
	timer.name = timer_name
	timer.one_shot = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	timer.timeout.connect(callback)
	add_child(timer)
	return timer


func _on_purchase_succeeded(product_id: String) -> void:
	if not _pending or product_id != _product_id:
		return
	var product := ConfigDB.get_product(product_id)
	var granted := MetaShop.grant(product_id)
	if granted:
		_finish(&"success")
	elif product != null and product.is_one_time():
		_finish(&"owned")
	else:
		_finish(&"failed")


func _on_purchase_cancelled(product_id: String) -> void:
	if not _pending or product_id != _product_id:
		return
	_finish(&"cancelled")


func _on_purchase_failed(product_id: String, reason: String) -> void:
	if not _pending or product_id != _product_id:
		return
	Analytics.log_event("purchase_failed_reason", {"product_id": product_id, "reason": reason})
	_finish(&"failed")


func _finish(outcome: StringName) -> void:
	if not _pending:
		return
	var product_id := _product_id
	var callback := _callback
	_pending = false
	_product_id = ""
	_callback = Callable()
	_timer.stop()
	var success := outcome == &"success"
	match outcome:
		&"success":
			_status = Status.SUCCESS
		&"cancelled":
			_status = Status.CANCELLED
		&"failed", &"no_consent", &"unavailable":
			_status = Status.FAILED
		_:
			_status = Status.IDLE
	EventBus.purchase_completed.emit(product_id, success)
	if success:
		Analytics.log_event("purchase_success", {"product_id": product_id})
	else:
		Analytics.log_event("purchase_failed", {"product_id": product_id, "outcome": str(outcome)})
	if callback.is_valid():
		callback.call(outcome)


func _on_timeout() -> void:
	if _pending:
		_finish(&"failed")


func _on_restore_completed(product_ids: Array) -> void:
	if not _restore_pending:
		return
	# A reinstall has no local ownership rows; the store receipt is the source of
	# truth. Mark one-time products owned before re-applying their unlock flags.
	for value: Variant in product_ids:
		var product := ConfigDB.get_product(str(value))
		if product != null and product.is_one_time() and not GameState.is_product_owned(product.id):
			GameState.own_product(product.id)
	MetaShop.restore_owned()
	_finish_restore(product_ids, true)


func _on_restore_failed(reason: String) -> void:
	if not _restore_pending:
		return
	Analytics.log_event("purchase_restore_failed", {"reason": reason})
	_finish_restore([], false)


func _finish_restore(product_ids: Array, ok: bool) -> void:
	if not _restore_pending:
		return
	var callback := _restore_callback
	_restore_pending = false
	_restore_callback = Callable()
	_restore_timer.stop()
	if ok:
		Analytics.log_event("purchase_restore_success", {"count": product_ids.size()})
	_call_restore(callback, product_ids, ok)


func _on_restore_timeout() -> void:
	if _restore_pending:
		_finish_restore([], false)


func _call(callback: Callable, value: Variant) -> void:
	if callback.is_valid():
		callback.call(value)


func _call_restore(callback: Callable, product_ids: Array, ok: bool) -> void:
	if callback.is_valid():
		callback.call(product_ids, ok)


func _signal_table() -> Array:
	return [
		["purchase_succeeded", Callable(self, "_on_purchase_succeeded")],
		["purchase_failed", Callable(self, "_on_purchase_failed")],
		["purchase_cancelled", Callable(self, "_on_purchase_cancelled")],
		["restore_completed", Callable(self, "_on_restore_completed")],
		["restore_failed", Callable(self, "_on_restore_failed")],
	]
