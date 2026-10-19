extends Node
## Stage-7 screenshot helper (dev-only, excluded from export).
##
## Captures the battle HUD with and without the tutorial in both locales, plus
## the Settings screen with the new toggles. Restores the developer's real save.
##
## Run with:
##   godot --path <project> res://tools/PolishCapture.tscn

const BATTLE_SCENE := preload("res://scenes/battle/Battle.tscn")
const MENU_SCENE := preload("res://scenes/menu/MainMenu.tscn")
const SAVE_FILES := ["save.json", "save.tmp", "save.bak", "save.corrupt"]
const BACKUP_DIR := "user://capture_backup"

var _battle: Battle
var _menu: Control


func _ready() -> void:
	_backup_saves()
	GameState.from_dict(SaveDefaults.create())
	GameState.set_setting("quality", "high")
	GameState.set_setting("show_damage_numbers", true)
	GameState.set_flag("tutorial_done", false)
	Loc.set_locale("en")
	AudioManager.apply_settings()

	await _capture_battle()
	await _capture_settings()

	_restore_saves()
	get_tree().quit(0)


func _capture_battle() -> void:
	_battle = BATTLE_SCENE.instantiate()
	_battle.auto_route_results = false
	_battle.offer_revive = false
	add_child(_battle)
	await _wait(2.0)
	await _capture("battle_tutorial_en")

	Loc.set_locale("uk")
	await _wait(0.8)
	await _capture("battle_tutorial_uk")

	_battle.tutorial.skip()
	await _wait(0.8)
	await _capture("battle_hud_uk")

	Loc.set_locale("en")
	await _wait(0.8)
	await _capture("battle_hud_en")

	# Wider low-end profile.
	DisplayServer.window_set_size(Vector2i(720, 1280))
	await _wait(1.0)
	Loc.set_locale("uk")
	await _wait(0.6)
	await _capture("battle_hud_uk_720")
	DisplayServer.window_set_size(Vector2i(540, 960))
	await _wait(0.8)

	_battle.queue_free()
	await _wait(0.4)


func _capture_settings() -> void:
	_menu = MENU_SCENE.instantiate()
	add_child(_menu)
	await _wait(1.0)
	_menu.select_tab("settings")
	await _wait(0.8)
	await _capture("settings_en")
	Loc.set_locale("uk")
	await _wait(0.8)
	await _capture("settings_uk")
	_menu.queue_free()
	await _wait(0.4)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "user://screenshot_%s.png" % label
	var err := image.save_png(path)
	print("[capture] %s -> %s (%dx%d, error %d)" % [
		label,
		ProjectSettings.globalize_path(path),
		image.get_width(),
		image.get_height(),
		err,
	])


func _backup_saves() -> void:
	DirAccess.make_dir_recursive_absolute(BACKUP_DIR)
	for file_name: String in SAVE_FILES:
		_copy("user://" + file_name, BACKUP_DIR + "/" + file_name)


func _restore_saves() -> void:
	for file_name: String in SAVE_FILES:
		_copy(BACKUP_DIR + "/" + file_name, "user://" + file_name)


func _copy(from_path: String, to_path: String) -> void:
	if not FileAccess.file_exists(from_path):
		return
	var source := FileAccess.open(from_path, FileAccess.READ)
	if source == null:
		return
	var target := FileAccess.open(to_path, FileAccess.WRITE)
	if target == null:
		source.close()
		return
	target.store_buffer(source.get_buffer(source.get_length()))
	target.flush()
	target.close()
	source.close()
