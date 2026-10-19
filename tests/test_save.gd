extends Node
## Headless save-system smoke test.
##
## Run with:
##   godot --headless --path <project> res://tests/TestSave.tscn
##
## Prints "ALL SAVE TESTS PASSED" and exits 0 on success, exits 1 otherwise.
## Never depends on the editor: it only uses autoloads and user:// files.

const SAVE_JSON := "user://save.json"
const SAVE_BAK := "user://save.bak"
const SAVE_CORRUPT := "user://save.corrupt"

var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	await _run()
	_finish()


func _run() -> void:
	await get_tree().process_frame

	_section("reset")
	SaveManager.reset_progress()
	GameState.from_dict(SaveDefaults.create())
	_check(SaveManager.get_save_path().ends_with("save.json"), "save path points at save.json")
	_check(GameState.get_gold() == 0, "fresh profile starts with 0 Gold")
	_check(GameState.get_gems() == 0, "fresh profile starts with 0 Gems")

	_section("round trip")
	GameState.add_gold(123)
	GameState.add_gems(45)
	GameState.set_setting("music", 0.35)
	SaveManager.save_now(GameState.to_dict())
	_check(FileAccess.file_exists(SAVE_JSON), "save.json written")
	_check(GameState.get_gold() == 123, "memory holds 123 Gold")

	GameState.from_dict(SaveDefaults.create())
	_check(GameState.get_gold() == 0, "in-memory state wiped")
	var loaded := SaveManager.load_game()
	GameState.from_dict(loaded)
	_check(GameState.get_gold() == 123, "Gold survives a reload")
	_check(GameState.get_gems() == 45, "Gems survive a reload")
	_check(is_equal_approx(float(GameState.get_setting("music")), 0.35), "settings survive a reload")

	_section("settings persistence")
	GameState.set_setting("locale", "uk")
	SaveManager.save_now(GameState.to_dict())
	var reloaded := SaveManager.load_game()
	var reloaded_settings: Dictionary = reloaded.get("settings", {})
	_check(str(reloaded_settings.get("locale", "")) == "uk", "locale survives a reload")
	GameState.set_setting("locale", "en")
	SaveManager.save_now(GameState.to_dict())

	_section("repeated writes and backup")
	GameState.add_gold(1)
	SaveManager.save_now(GameState.to_dict())
	_check(FileAccess.file_exists(SAVE_BAK), "save.bak created on the second write")
	GameState.add_gold(1)
	SaveManager.save_now(GameState.to_dict())
	var newest := SaveManager.load_game()
	var newest_currencies: Dictionary = newest.get("currencies", {})
	_check(int(newest_currencies.get("gold", 0)) == 125, "third save keeps the newest value")

	_section("corruption recovery")
	var corrupt := FileAccess.open(SAVE_JSON, FileAccess.WRITE)
	_check(corrupt != null, "can write a corrupt save.json")
	if corrupt != null:
		corrupt.store_string("{bad json")
		corrupt.flush()
		corrupt.close()
	var recovered := SaveManager.load_game()
	GameState.from_dict(recovered)
	_check(GameState.get_gold() == 124, "recovered the previous good value from save.bak")
	_check(FileAccess.file_exists(SAVE_CORRUPT), "corrupt file kept as save.corrupt")

	_section("deleted primary file")
	DirAccess.remove_absolute(SAVE_JSON)
	_check(not FileAccess.file_exists(SAVE_JSON), "save.json deleted")
	var from_backup := SaveManager.load_game()
	var backup_currencies: Dictionary = from_backup.get("currencies", {})
	_check(int(backup_currencies.get("gold", 0)) == 124, "deleted save.json recovers from save.bak")

	_section("migrations")
	var migrated := SaveMigrations.migrate({"version": 1, "currencies": {"gold": 7}})
	_check(int(migrated.get("version", 0)) == 1, "v1 stays v1")
	_check(migrated.has("currencies"), "migration preserves the payload")
	var unknown := SaveMigrations.migrate({"version": 1, "unknown_key": "keep me"})
	_check(unknown.get("unknown_key", "") == "keep me", "unknown keys are preserved")
	var unversioned := SaveMigrations.migrate({"currencies": {"gold": 99}})
	_check(int(unversioned.get("version", 0)) == SaveDefaults.CURRENT_VERSION, "unversioned save becomes current")

	_section("localization")
	Loc.set_locale("uk")
	_check(Loc.get_locale() == "uk", "locale switches to uk")
	_check(Loc.t_key("MENU_TITLE") == "Дерево", "uk MENU_TITLE is Дерево")
	_check(Loc.t_key("CURRENCY_GEMS") == "Монети", "uk CURRENCY_GEMS is Монети")
	Loc.set_locale("en")
	_check(Loc.get_locale() == "en", "locale switches back to en")
	_check(Loc.t_key("MENU_TITLE") == "The Tree", "en MENU_TITLE is The Tree")
	_check(Loc.t_key("VERSION_LABEL", {"version": "0.1.0"}) == "v0.1.0", "version placeholder substitutes")
	_check(Loc.format_number(12500) == "12\u2009500", "numbers use thin spaces")
	_check(Loc.format_number(0) == "0", "zero formats as 0")

	_section("config db")
	_check(ConfigDB.get_enemy("orc_grunt") == null, "unknown enemy returns null")
	_check(ConfigDB.all_enemies().is_empty(), "empty data folder loads cleanly")

	_section("speed service")
	_check(SpeedService.set_speed(1.5) == false, "1.5x is locked without the unlock")
	_check(SpeedService.set_speed(1.0) == true, "1x is always allowed")
	_check(is_equal_approx(Engine.time_scale, 1.0), "time scale is reset")

	_section("cleanup")
	Loc.set_locale("en")
	SaveManager.reset_progress()
	GameState.from_dict(SaveDefaults.create())
	_check(not FileAccess.file_exists(SAVE_CORRUPT), "cleanup removes save.corrupt")
	_check(GameState.get_gold() == 0, "cleanup leaves a fresh profile")


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("ALL SAVE TESTS PASSED (%d checks)" % _checks)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	printerr("SAVE TESTS FAILED: %d of %d checks" % [_failures.size(), _checks])
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
