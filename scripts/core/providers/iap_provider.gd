class_name IapProvider
extends RefCounted
## Interface for an in-app purchase backend.
##
## Every request resolves exactly once: `purchase_succeeded`, `purchase_failed`
## or `purchase_cancelled`; restore answers with `restore_completed` or
## `restore_failed`. Providers must acknowledge/consume a purchase before they
## report success.

signal purchase_succeeded(product_id: String)
signal purchase_failed(product_id: String, reason: String)
signal purchase_cancelled(product_id: String)

signal restore_completed(product_ids: Array)
signal restore_failed(reason: String)


## Prepares the billing client. False means the plugin is absent.
func initialize() -> bool:
	return false


## True when the store connection is ready.
func is_ready() -> bool:
	return false


## Starts a purchase for the logical product id.
func purchase(product_id: String) -> void:
	purchase_failed.emit(product_id, "not_implemented")


## Queries previously owned non-consumables.
func restore() -> void:
	restore_failed.emit("not_implemented")


## Product ids the backend already owns, for diagnostics.
func get_owned_product_ids() -> Array:
	return []
