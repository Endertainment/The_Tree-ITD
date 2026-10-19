extends Node
## Headless polish tests for the stage-7 presentation layer.
##
## Covers safe-area maths, camera shake, particle capping, the sound library,
## plural rules, localized formatting and the tutorial state machine.
##
## Run with:
##   godot --headless --path <project> res://tests/TestPolish.tscn

const BATTLE_SCENE := preload("res://scenes/battle/Battle.tscn")

var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	await _run()
	_finish()


func _run() -> void:
	await get_tree().process_frame

	_test_safe_area()
	_test_plural()
	await _test_formatting()
	await _test_audio()
	await _test_shake()
	await _test_vfx()
	await _test_haptics()
	await _test_tutorial()


func _test_safe_area() -> void:
	_section("safe area")
	# A 1080x1920 phone with a 100 px notch and a 60 px gesture bar.
	var notched := SafeArea.insets_for(
		Vector2i(1080, 1920),
		Rect2i(0, 100, 1080, 1760),
		Vector2(1080, 1920),
		true
	)
	_check(is_equal_approx(notched.x, 100.0), "notch inset becomes top padding")
	_check(is_equal_approx(notched.z, 60.0), "gesture bar becomes bottom padding")
	_check(is_equal_approx(notched.y, 0.0) and is_equal_approx(notched.w, 0.0), "no side padding without side cutouts")

	# Same phone at a 720x1280 render size: insets scale with the viewport.
	var scaled := SafeArea.insets_for(
		Vector2i(1080, 1920),
		Rect2i(0, 100, 1080, 1760),
		Vector2(720, 1280),
		true
	)
	_check(is_equal_approx(scaled.x, 100.0 * 720.0 / 1080.0), "insets scale to 720x1280")

	var desktop := SafeArea.insets_for(
		Vector2i(1280, 720),
		Rect2i(0, 0, 1280, 720),
		Vector2(1080, 1920),
		false
	)
	_check(desktop == Vector4.ZERO, "desktop windows get no insets")

	var fullscreen := SafeArea.insets_for(
		Vector2i(1080, 1920),
		Rect2i(0, 0, 1080, 1920),
		Vector2(1080, 1920),
		true
	)
	_check(fullscreen == Vector4.ZERO, "a device without a cutout gets no insets")


func _test_plural() -> void:
	_section("plural rules")
	var cases := {
		1: "one",
		2: "few",
		5: "many",
		11: "many",
		21: "one",
		22: "few",
		25: "many",
		0: "many",
	}
	for count: int in cases:
		var expected := str(cases[count])
		var actual := Loc.plural_key(count, "one", "few", "many", "uk")
		_check(actual == expected, "uk plural for %d is %s" % [count, expected])
	_check(Loc.plural_key(1, "one", "few", "many", "en") == "one", "en plural for 1 is one")
	_check(Loc.plural_key(2, "one", "few", "many", "en") == "many", "en plural for 2 is many")


func _test_formatting() -> void:
	_section("localized formatting")
	var previous := Loc.get_locale()
	Loc.set_locale("en")
	_check(Loc.format_percent(80.0) == "80%", "en percent has no space")
	_check(Loc.format_time(43200) == "12h 00m", "en duration reads 12h 00m")
	_check(Loc.format_number(12500) == "12\u2009500", "numbers use thin-space grouping")
	Loc.set_locale("uk")
	_check(Loc.format_percent(80.0) == "80 %", "uk percent uses a spaced sign")
	_check(Loc.format_time(43200).contains("год"), "uk duration uses год/хв")
	_check(Loc.format_time(300).contains("хв"), "uk minutes use хв")
	Loc.set_locale(previous)
	await get_tree().process_frame


func _test_audio() -> void:
	_section("audio library")
	var ids := AudioManager.get_sfx_ids()
	_check(ids.size() >= 12, "at least 12 sound effects are registered")
	_check(AudioManager.has_sound("hit"), "hit sound resolves by id")
	_check(AudioManager.has_sound("ui_click"), "ui_click alias resolves to ui_tap")
	_check(AudioManager.has_sound("tower_fire"), "tower_fire alias resolves to arrow")
	_check(not AudioManager.has_sound("definitely_missing"), "unknown ids do not resolve")

	_section("pause ducking")
	var music_bus := AudioServer.get_bus_index(AudioManager.MUSIC_BUS)
	_check(music_bus >= 0, "Music bus exists")
	_check(AudioServer.get_bus_index(AudioManager.SFX_BUS) >= 0, "SFX bus exists")
	_check(AudioServer.get_bus_index(AudioManager.UI_BUS) >= 0, "UI bus exists")
	AudioManager.refresh_pause_duck()
	var running_db := AudioServer.get_bus_volume_db(music_bus)
	get_tree().paused = true
	AudioManager.refresh_pause_duck()
	var paused_db := AudioServer.get_bus_volume_db(music_bus)
	get_tree().paused = false
	AudioManager.refresh_pause_duck()
	_check(is_equal_approx(paused_db, running_db + AudioManager.DUCK_DB), "paused music ducks by 6 dB")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(music_bus), running_db), "resuming restores the music level")
	_check(not AudioManager.is_ducked(), "duck flag clears on resume")
	await get_tree().process_frame


func _test_shake() -> void:
	_section("screen shake")
	var shake := ScreenShake.new()
	add_child(shake)
	await get_tree().process_frame
	GameState.set_setting("quality", "high")
	shake.shake_pixels(6.0)
	_check(shake.is_shaking(), "shake starts")
	var first := shake.get_trauma()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(shake.get_trauma() < first, "trauma decays over time")
	shake.reset_shake()
	_check(not shake.is_shaking() and shake.offset == Vector2.ZERO, "reset clears the camera offset")

	GameState.set_setting("quality", "low")
	shake.reset_shake()
	shake.shake_pixels(6.0)
	_check(not shake.is_shaking(), "low quality disables shake")
	GameState.set_setting("quality", "high")
	shake.queue_free()
	await get_tree().process_frame


func _test_vfx() -> void:
	_section("particle budget")
	var layer := VfxLayer.new()
	add_child(layer)
	await get_tree().process_frame
	GameState.set_setting("quality", "high")
	for index in 40:
		layer.hit_spark(Vector2(100.0 + index, 200.0))
		layer.death_puff(Vector2(300.0, 300.0), Color.GREEN)
	_check(layer.get_alive_particles() <= layer.get_particle_cap(), "particle count stays under the cap")
	_check(layer.get_particle_cap() == 120, "cap is 120 particles")
	layer.queue_free()
	await get_tree().process_frame


func _test_haptics() -> void:
	_section("haptics")
	GameState.set_setting("haptics", true)
	_check(not Haptics.enabled(), "desktop builds never vibrate")
	Haptics.tap()
	Haptics.core_damage()
	Haptics.boss_spawn()
	_check(true, "haptic calls are safe without a device")
	GameState.set_setting("haptics", false)
	_check(not Haptics.enabled(), "the setting can switch haptics off")
	GameState.set_setting("haptics", true)
	await get_tree().process_frame


func _test_tutorial() -> void:
	_section("tutorial")
	GameState.from_dict(SaveDefaults.create())
	SaveManager.save_now(GameState.to_dict())
	var battle: Battle = BATTLE_SCENE.instantiate()
	battle.auto_route_results = false
	battle.offer_revive = false
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(GameState.has_flag("tutorial_done") == false, "fresh profile starts with the tutorial pending")
	_check(battle.tutorial.is_active(), "tutorial starts on the first battle")
	_check(battle.tutorial.get_step() == 0, "first step is the build hint")
	_check(battle.tutorial.get_time_left() > 0.0, "step has a timeout")

	battle.tutorial.skip()
	_check(not battle.tutorial.is_active(), "SKIP hides the tutorial")
	_check(GameState.has_flag("tutorial_done"), "SKIP persists the flag")

	battle.tutorial.start_if_needed()
	_check(not battle.tutorial.is_active(), "a completed tutorial does not restart")

	GameState.set_flag("tutorial_done", false)
	battle.tutorial.start_if_needed()
	_check(battle.tutorial.is_active(), "replay flag shows it again")
	battle.tutorial.dismiss()
	_check(not battle.tutorial.is_active(), "dismiss hides without marking done")

	# Damage numbers follow the setting, and low quality forces them off.
	GameState.set_flag("tutorial_done", true)
	GameState.set_setting("quality", "high")
	GameState.set_setting("show_damage_numbers", true)
	_check(battle.shows_damage_numbers(), "damage numbers follow the setting")
	GameState.set_setting("show_damage_numbers", false)
	_check(not battle.shows_damage_numbers(), "damage numbers can be switched off")
	GameState.set_setting("show_damage_numbers", true)
	GameState.set_setting("quality", "low")
	_check(not battle.shows_damage_numbers(), "low quality hides damage numbers")
	GameState.set_setting("quality", "high")

	battle.queue_free()
	GameState.from_dict(SaveDefaults.create())
	await get_tree().process_frame


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("ALL POLISH TESTS PASSED (%d checks)" % _checks)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	printerr("POLISH TESTS FAILED: %d of %d checks" % [_failures.size(), _checks])
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
