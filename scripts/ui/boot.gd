extends Control
## Boot splash: loads the save, applies locale and audio, then routes to the menu.
##
## Idempotent if the scene is re-entered (reset-progress path): `_starting`
## guards the sequence so it cannot run twice on the same instance.

const MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"
const BATTLE_SCENE := "res://scenes/battle/Battle.tscn"
const DEBUG_BATTLE_FLAG := "--debug-battle"
const BOOT_SECONDS := 0.8
const VERSION_SETTING := "application/config/version"

@onready var _title: Label = %Title
@onready var _version: Label = %Version

var _starting := false


func _ready() -> void:
	UISkin.ensure_applied()
	if _starting:
		return
	_starting = true
	_refresh_texts()
	await _start()


func _start() -> void:
	var data := SaveManager.load_game()
	GameState.from_dict(data)
	Loc.set_locale(str(GameState.get_setting("locale", Loc.FALLBACK_LOCALE)))
	AudioManager.apply_settings()
	_refresh_texts()
	await get_tree().create_timer(BOOT_SECONDS, true, false, true).timeout
	var next_scene := MAIN_MENU_SCENE
	if _starts_in_battle():
		next_scene = BATTLE_SCENE
	SceneRouter.goto(next_scene)


## True when the dev-only `--debug-battle` flag was passed to a debug build.
func _starts_in_battle() -> bool:
	if not OS.is_debug_build():
		return false
	return (
		OS.get_cmdline_args().has(DEBUG_BATTLE_FLAG)
		or OS.get_cmdline_user_args().has(DEBUG_BATTLE_FLAG)
	)


func _refresh_texts() -> void:
	_title.text = Loc.t_key("BOOT_TITLE")
	_version.text = Loc.t_key("VERSION_LABEL", {
		"version": str(ProjectSettings.get_setting(VERSION_SETTING, "0.1.0")),
	})
