class_name BundleFeed
extends RefCounted
## Bundle offer list, optionally replaced by the server without an app update.
##
## Order of preference:
##   1. `user://bundles_cache.json` — the last successful server response
##   2. `res://data/bundles.json`   — the bundled default (offline / first run)
##
## A server can add, reorder or disable offers by changing the same JSON, and
## the app picks it up on the next launch (see `MainMenu._refresh_bundles_remote`).
## Disabled bundles (`"enabled": false`) are dropped here, so the UI needs no
## knowledge of them.

const DEFAULT_PATH := "res://data/bundles.json"
const CACHE_PATH := "user://bundles_cache.json"


## Enabled bundles, sorted by `order`.
static func load_bundles() -> Array:
	var data := _read_json(CACHE_PATH)
	if data.is_empty():
		data = _read_json(DEFAULT_PATH)
	var bundles: Array = []
	for entry: Variant in data.get("bundles", []):
		var bundle := entry as Dictionary
		if bundle == null or not bool(bundle.get("enabled", true)):
			continue
		if str(bundle.get("product_id", "")).is_empty():
			continue
		bundles.append(bundle)
	bundles.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("order", 0)) < int(b.get("order", 0))
	)
	return bundles


## Stores a server response so the next launch shows it.
static func save_cache(json_text: String) -> bool:
	if json_text.strip_edges().is_empty():
		return false
	var file := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(json_text)
	file.close()
	return true


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
