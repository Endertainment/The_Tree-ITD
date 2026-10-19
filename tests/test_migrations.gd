extends Node
## Headless save-migration test: a real v1 profile must survive v1 -> v2.
##
## Run with:
##   godot --headless --path <project> res://tests/TestMigrations.tscn

const FIXTURE_PATH := "res://tests/fixtures/save_v1.json"
const SAVE_PATH := "user://save.json"

var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	await _run()
	_finish()


func _run() -> void:
	await get_tree().process_frame
	SaveManager.reset_progress()
	GameState.from_dict(SaveDefaults.create())

	var fixture := _read_fixture()
	_check(not fixture.is_empty(), "v1 fixture parses")
	if fixture.is_empty():
		return

	_section("pure migration")
	var migrated := SaveMigrations.migrate(fixture)
	_check(int(migrated.get("version", 0)) == 2, "fixture migrates to version 2")
	var currencies: Dictionary = migrated.get("currencies", {})
	_check(int(currencies.get("gold", 0)) == 321, "migration keeps Gold")
	_check(int(currencies.get("gems", 0)) == 77, "migration keeps Gems")
	var upgrades: Dictionary = migrated.get("upgrades", {})
	_check(int(upgrades.get("tree_hp", 0)) == 3, "migration keeps upgrade levels")
	var shop: Dictionary = migrated.get("shop", {})
	_check((shop.get("owned_products", []) as Array).has("starter_bundle"), "migration keeps owned products")
	_check(migrated.get("unknown_key", "") == "keep me", "migration preserves unknown keys")
	var ads: Dictionary = migrated.get("ads", {})
	_check(int(ads.get("runs_since_interstitial", -1)) == 0, "migration inserts the interstitial counter")
	_check(int(ads.get("free_gems_today", -1)) == 0, "migration inserts the daily free-Gems count")
	_check(int(ads.get("free_gems_last_ts", -1)) == 0, "migration inserts the free-Gems timestamp")
	_check(str(ads.get("free_gems_day", "x")) == "", "migration leaves the free-Gems day empty")

	_section("idempotency")
	var twice := SaveMigrations.migrate(migrated)
	_check(int(twice.get("version", 0)) == 2, "migrating a v2 save stays at v2")
	_check(int((twice.get("currencies", {}) as Dictionary).get("gold", 0)) == 321, "second migration keeps Gold")
	_check(int((twice.get("ads", {}) as Dictionary).get("runs_since_interstitial", -1)) == 0, "second migration keeps ads")

	_section("load through SaveManager")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	_check(file != null, "fixture can be written to user://save.json")
	if file != null:
		file.store_string(JSON.stringify(fixture, "\t"))
		file.flush()
		file.close()
	var loaded := SaveManager.load_game()
	_check(int(loaded.get("version", 0)) == 2, "SaveManager returns a v2 profile")
	var loaded_ads: Dictionary = loaded.get("ads", {})
	_check(int(loaded_ads.get("runs_since_interstitial", -1)) == 0, "loaded profile has ads defaults")
	GameState.from_dict(loaded)
	_check(GameState.get_gold() == 321, "loaded Gold survives into GameState")
	_check(GameState.get_gems() == 77, "loaded Gems survive into GameState")
	_check(GameState.get_upgrade_level("tree_hp") == 3, "loaded upgrade survives validation")
	_check(GameState.is_product_owned("starter_bundle"), "loaded product survives validation")
	_check(GameState.is_unlocked("speed_15"), "loaded unlock survives validation")
	_check(GameState.is_card_owned("heartwood"), "loaded card survives validation")
	_check(not GameState.is_card_owned("not_a_card"), "unknown cards are dropped")

	_section("cleanup")
	SaveManager.reset_progress()
	GameState.from_dict(SaveDefaults.create())
	_check(int(GameState.get_ads().get("runs_since_interstitial", -1)) == 0, "cleanup leaves a fresh ads block")


func _read_fixture() -> Dictionary:
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("ALL MIGRATION TESTS PASSED (%d checks)" % _checks)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	printerr("MIGRATION TESTS FAILED: %d of %d checks" % [_failures.size(), _checks])
	get_tree().quit(1)


func _section(title: String) -> void:
	print("")
	print("== %s ==" % title)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures.append(message)
		print("  FAIL ", message)
