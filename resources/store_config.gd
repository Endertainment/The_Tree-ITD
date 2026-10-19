class_name StoreConfig
extends Resource
## Real ad/store identifiers, kept in `data/monetization/store_config.tres`.
##
## The disabled adapters read this resource, so switching a live build on means
## replacing IDs in data, not editing GDScript. Product ids live next to their
## balance entry in `data/shop/*.tres` (`ShopProduct.store_id`).

@export var id: String = "main"

## AdMob app id and unit ids. The shipped `.tres` contains Google's public test
## ids; a live build replaces them there.
@export var admob_app_id: String = ""
@export var rewarded_unit_id: String = ""
@export var interstitial_unit_id: String = ""

## Play Billing public key; empty means the provider refuses to initialize.
@export var billing_public_key: String = ""

## Documented switch: keep true until a human supplies real accounts and IDs.
@export var use_test_ids: bool = true

## Real builds must gate ads behind a UMP consent flow; the MVP stub returns
## true, so this flag is documentation for the SDK adapter.
@export var consent_required: bool = true
