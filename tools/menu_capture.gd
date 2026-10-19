extends Node
## Dev-only screenshot helper for the six menu tabs (excluded from export).
##
## Seeds a demo profile in memory, captures every tab in EN and UK, then restores
## the developer's real save files. Run with:
##   godot --path <project> res://tools/MenuCapture.tscn

const MENU_SCENE := preload("res://scenes/menu/MainMenu.tscn")
const TABS: Array[String] = ["home", "upgrades", "cards", "missions", "shop", "settings"]
const SAVE_FILES := ["save.json", "save.tmp", "save.bak", "save.corrupt"]
const BACKUP_DIR := "user://capture_backup"
const SETTLE := 0.45

var _menu: Control


func _ready() -> void:
	_backup_saves()
	GameState.from_dict(_demo_profile())
	Loc.set_locale("en")
	AudioManager.apply_settings()
	GameState.missions.refresh_achievements()
	_menu = MENU_SCENE.instantiate()
	add_child(_menu)
	await get_tree().create_timer(0.6, true, false, true).timeout
	for tab: String in TABS:
		_menu.select_tab(tab)
		await get_tree().create_timer(SETTLE, true, false, true).timeout
		await _capture("menu_%s_en" % tab)
	Loc.set_locale("uk")
	await get_tree().create_timer(SETTLE, true, false, true).timeout
	for tab: String in TABS:
		_menu.select_tab(tab)
		await get_tree().create_timer(SETTLE, true, false, true).timeout
		await _capture("menu_%s_uk" % tab)
	Loc.set_locale("en")
	await get_tree().create_timer(SETTLE, true, false, true).timeout
	_menu.select_tab("home")
	await get_tree().create_timer(2.0, true, false, true).timeout
	print("[capture] menu fps=%.1f" % Engine.get_frames_per_second())
	_restore_saves()
	get_tree().quit(0)


func _demo_profile() -> Dictionary:
	var data := SaveDefaults.create()
	data["currencies"] = {"gold": 2450, "gems": 680}
	data["upgrades"]["tree_hp"] = 3
	data["upgrades"]["archer_dmg"] = 2
	data["upgrades"]["start_coins"] = 1
	data["cards"]["owned"] = ["heartwood", "swift_leaves", "midas_bark", "frost_roots"]
	data["cards"]["equipped"] = ["heartwood", "swift_leaves"]
	data["stats"] = {
		"runs": 12,
		"best_wave": 23,
		"total_kills": 640,
		"bosses_killed": 4,
		"total_gold_earned": 4820,
		"total_waves_cleared": 72,
		"towers_built": 38,
		"ads_watched": 3,
	}
	data["missions"]["achievements"]["claimed"] = ["ach_reach_wave_20"]
	data["unlocks"]["speed_15"] = true
	return data


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "user://screenshot_%s.png" % label
	var err := image.save_png(path)
	print("[capture] %s -> %s (error %d)" % [path, ProjectSettings.globalize_path(path), err])


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
