extends Node
## Dev-only screenshot helper (excluded from export).
##
## Renders the MainMenu in EN, in UK, and with a live HUD update plus toast:
##   godot --path <project> res://tools/CaptureTool.tscn
## It exists so layout, Cyrillic rendering and the currency signal wiring can be
## checked without a device.

const MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"
const SETTLE_SECONDS := 0.8
const LOCALE_SETTLE_SECONDS := 0.3
const TOAST_SETTLE_SECONDS := 0.3
const DEMO_GOLD := 1250


func _ready() -> void:
	var data := SaveManager.load_game()
	GameState.from_dict(data)
	Loc.set_locale("en")
	AudioManager.apply_settings()

	var menu: Node = load(MAIN_MENU_SCENE).instantiate()
	add_child(menu)
	await get_tree().create_timer(SETTLE_SECONDS, true, false, true).timeout
	await _capture("en")

	Loc.set_locale("uk")
	await get_tree().create_timer(LOCALE_SETTLE_SECONDS, true, false, true).timeout
	await _capture("uk")

	Loc.set_locale("en")
	await get_tree().create_timer(LOCALE_SETTLE_SECONDS, true, false, true).timeout
	GameState.add_gold(DEMO_GOLD)
	var battle_button := menu.find_child("BattleButton", true, false) as Button
	if battle_button != null:
		battle_button.pressed.emit()
	await get_tree().create_timer(TOAST_SETTLE_SECONDS, true, false, true).timeout
	await _capture("en_hud")

	get_tree().quit(0)


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "user://screenshot_menu_%s.png" % label
	var err := image.save_png(path)
	print("[capture] %s -> %s (error %d)" % [path, ProjectSettings.globalize_path(path), err])
