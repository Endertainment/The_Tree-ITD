extends Node
## Headless save-corruption suite: truncated JSON, wrong types, missing keys,
## unknown keys, nulls, a future schema version and 100 torn-write cycles.
##
## Run with:
##   godot --headless --path <project> res://tests/TestCorruption.tscn
##
## Every case must leave a loadable profile: the game may fall back to `save.bak`
## or to defaults, but it must never return a broken dictionary, crash, or lose
## data that a newer build owns.

const SAVE_PATH := "user://save.json"
const BAK_PATH := "user://save.bak"
const TMP_PATH := "user://save.tmp"
const CORRUPT_PATH := "user://save.corrupt"
const WRITE_CYCLES := 100

var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	await _run()
	_finish()


func _run() -> void:
	await get_tree().process_frame
	SaveManager.reset_progress()
	GameState.from_dict(SaveDefaults.create())

	_section("defaults")
	var fresh := SaveManager.load_game()
	_check(int(fresh.get("version", 0)) == 2, "fresh profile is v2")
	_check(_gold(fresh) == 0, "fresh profile has 0 Gold")
	_check(fresh.has("ads"), "fresh profile has the ads block")

	_section("truncated JSON recovers from the backup")
	await _write_profile(100, 0)
	await _write_profile(123, 45)
	await _write_profile(999, 9)
	var before := _read_file(SAVE_PATH)
	_write_text(SAVE_PATH, before.substr(0, before.length() / 2))
	var recovered := SaveManager.load_game()
	_check(_gold(recovered) == 123, "truncated save.json recovers the Gold from save.bak")
	_check(_gems(recovered) == 45, "truncated save.json recovers the Gems from save.bak")
	_check(FileAccess.file_exists(CORRUPT_PATH), "the unreadable file is kept as save.corrupt")

	_section("wrong types do not break the boot")
	await _write_profile(10, 10)
	_write_text(SAVE_PATH, JSON.stringify({
		"version": 2,
		"currencies": "not a dictionary",
		"stats": null,
		"settings": 42,
		"upgrades": [],
		"missions": "nope",
	}))
	var typed := SaveManager.load_game()
	_check(int(typed.get("version", 0)) == 2, "wrong-typed profile still loads as v2")
	GameState.from_dict(typed)
	_check(GameState.get_gold() == 0, "a string currency sanitises to 0 Gold")
	_check(GameState.get_gems() == 0, "a string currency sanitises to 0 Gems")
	_check(is_equal_approx(float(GameState.get_setting("music", -1.0)), 0.8), "wrong-typed settings fall back to defaults")
	_check(GameState.get_upgrade_level("tree_hp") == 0, "a list where upgrades belong sanitises to level 0")

	_section("missing keys are filled")
	_write_text(SAVE_PATH, JSON.stringify({"version": 2}))
	var bare := SaveManager.load_game()
	_check(bare.has("currencies"), "missing currencies block is filled")
	_check(bare.has("settings"), "missing settings block is filled")
	_check(bare.has("ads"), "missing ads block is filled")
	_check(int(bare.get("stats", {}).get("best_wave", -1)) == 0, "missing stats default to 0")
	GameState.from_dict(bare)
	_check(GameState.get_gold() == 0, "bare profile boots into GameState")

	_section("unknown keys are preserved")
	_write_text(SAVE_PATH, JSON.stringify({
		"version": 2,
		"future_feature": {"nested": [1, 2, 3]},
		"currencies": {"gold": 77, "gems": 3},
	}))
	var future := SaveManager.load_game()
	_check((future.get("future_feature", {}) as Dictionary).has("nested"), "unknown top-level keys survive a load")
	_check(_gold(future) == 77, "known keys survive next to unknown ones")

	_section("null values sanitise")
	_write_text(SAVE_PATH, JSON.stringify({
		"version": 2,
		"currencies": {"gold": null, "gems": null},
		"stats": {"best_wave": null, "runs": null},
	}))
	var nulled := SaveManager.load_game()
	GameState.from_dict(nulled)
	_check(GameState.get_gold() == 0, "null Gold becomes 0")
	_check(GameState.get_gems() == 0, "null Gems becomes 0")
	_check(GameState.get_best_wave() == 0, "null best_wave becomes 0")

	_section("a newer schema is loaded, not destroyed")
	_write_text(SAVE_PATH, JSON.stringify({
		"version": 99,
		"currencies": {"gold": 4242, "gems": 99},
		"save_v99_only": {"keep": true},
	}))
	var newer := SaveManager.load_game()
	_check(int(newer.get("version", 0)) == 99, "a future version stays at 99")
	_check(_gold(newer) == 4242, "a future version keeps its Gold")
	_check((newer.get("save_v99_only", {}) as Dictionary).get("keep", false), "a future version keeps its unknown block")
	SaveManager.save_now(newer)
	var rewritten := _read_file(SAVE_PATH)
	_check(rewritten.contains("save_v99_only"), "rewriting the profile still contains the unknown block")

	_section("100 commits with torn temp writes")
	SaveManager.reset_progress()
	var base := SaveDefaults.create()
	base["currencies"]["gold"] = 0
	var survived := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261020
	for cycle in WRITE_CYCLES:
		base["currencies"]["gold"] = cycle + 1
		if rng.randf() < 0.25:
			# A killed process leaves a half-written temp file behind.
			_write_text(TMP_PATH, "{\"version\": 2, \"currenc")
		SaveManager.save_now(base)
		var parsed := _read_file(SAVE_PATH)
		var data: Variant = JSON.parse_string(parsed)
		if data is Dictionary and int((data as Dictionary).get("version", 0)) == 2 \
				and int(((data as Dictionary).get("currencies", {}) as Dictionary).get("gold", -1)) == cycle + 1:
			survived += 1
	_check(survived == WRITE_CYCLES, "all %d commits survived a torn temp file (%d parsed)" % [WRITE_CYCLES, survived])
	_check(not FileAccess.file_exists(TMP_PATH), "no save.tmp is left behind after a successful commit")

	_section("cleanup")
	SaveManager.reset_progress()
	GameState.from_dict(SaveDefaults.create())
	_check(_gold(SaveManager.load_game()) == 0, "cleanup leaves a fresh profile")


## Writes one complete profile; the next write moves it into `save.bak`.
func _write_profile(gold: int, gems: int) -> void:
	var data := SaveDefaults.create()
	data["currencies"]["gold"] = gold
	data["currencies"]["gems"] = gems
	SaveManager.save_now(data)


func _gold(data: Dictionary) -> int:
	return int((data.get("currencies", {}) as Dictionary).get("gold", 0))


func _gems(data: Dictionary) -> int:
	return int((data.get("currencies", {}) as Dictionary).get("gems", 0))


func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.flush()
	file.close()


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("ALL CORRUPTION TESTS PASSED (%d checks)" % _checks)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	printerr("CORRUPTION TESTS FAILED: %d of %d checks" % [_failures.size(), _checks])
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
