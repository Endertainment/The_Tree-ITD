extends Control
## Main menu shell: top currency bar, lazily instanced tab screens, bottom tabs.
##
## Screens are cached after their first visit, so switching tabs never reloads a
## scene or restarts music. The shell owns the single `ModalSheet` and toast so
## every tab confirms destructive actions the same way.

const MENU_SCREENS := {
	"home": "res://scenes/menu/HomeScreen.tscn",
	"upgrades": "res://scenes/menu/UpgradesScreen.tscn",
	"cards": "res://scenes/menu/CardsScreen.tscn",
	"missions": "res://scenes/menu/MissionsScreen.tscn",
	"shop": "res://scenes/menu/ShopScreen.tscn",
	"settings": "res://scenes/menu/SettingsScreen.tscn",
}
const TAB_ORDER: Array[String] = ["home", "upgrades", "cards", "missions", "shop", "settings"]
const BATTLE_SCENE := "res://scenes/battle/Battle.tscn"
const BOOT_SCENE := "res://scenes/boot/Boot.tscn"
const DEBUG_PANEL_SCENE := "res://ui/debug/MonetizationDebug.tscn"
const VERSION_SETTING := "application/config/version"
const SIDE_MARGIN := 24
const TOP_MARGIN := 16
const BOTTOM_MARGIN := 12
const FADE_SECONDS := 0.15
const TAB_ACCENT := Color(0.94902, 0.756863, 0.305882, 1)
const TAB_MUTED := Color(0.72549, 0.768627, 0.658824, 1)

@onready var _safe_area: MarginContainer = %SafeArea
@onready var _gold_label: Label = %GoldLabel
@onready var _gems_label: Label = %GemsLabel
@onready var _elf_label: Label = %ElfLabel
@onready var _best_label: Label = %BestLabel
@onready var _battle_shortcut: Button = %BattleShortcut
@onready var _screen_host: Control = %ScreenHost
@onready var _tab_bar: HBoxContainer = %TabBar
@onready var _modal: ModalSheet = %Modal
@onready var _toast: Toast = %Toast

var _screens: Dictionary = {}
var _tab_buttons: Dictionary = {}
var _active_id := ""
var _active_screen: MenuScreen
var _debug_panel


func _ready() -> void:
	_battle_shortcut.pressed.connect(_on_battle_pressed)
	for child in _tab_bar.get_children():
		if child is Button:
			var tab_id := _tab_id_for(child.name)
			_tab_buttons[tab_id] = child
			child.pressed.connect(_on_tab_pressed.bind(tab_id))
	EventBus.gold_changed.connect(_on_currency_changed)
	EventBus.gems_changed.connect(_on_currency_changed)
	EventBus.cards_changed.connect(_on_meta_changed)
	EventBus.products_changed.connect(_on_meta_changed)
	EventBus.missions_changed.connect(_on_meta_changed)
	EventBus.language_changed.connect(_on_language_changed)
	get_viewport().size_changed.connect(_apply_safe_area)
	GameState.missions.refresh_daily()
	GameState.missions.refresh_achievements()
	_apply_safe_area()
	_refresh_chrome()
	select_tab("home")
	Analytics.set_screen("main_menu")


## Switches to `tab_id`, instancing the screen scene on first visit.
func select_tab(tab_id: String) -> void:
	if not MENU_SCREENS.has(tab_id):
		return
	var screen := _ensure_screen(tab_id)
	if screen == null:
		return
	if _active_screen != null and _active_screen != screen:
		_active_screen.visible = false
	_active_id = tab_id
	_active_screen = screen
	screen.visible = true
	_battle_shortcut.visible = tab_id != "home"
	for id: String in _tab_buttons:
		var button := _tab_buttons[id] as Button
		button.button_pressed = id == tab_id
		_tint_tab(button, id == tab_id)
	screen.modulate.a = 0.0
	create_tween().tween_property(screen, "modulate:a", 1.0, FADE_SECONDS)
	screen.refresh()


## Shows a non-blocking toast above the tab bar.
func show_toast(text: String, seconds := 2.0) -> void:
	_toast.show_message(text, seconds)


## Opens the shared confirmation/detail sheet. `on_confirm` may be empty.
func open_modal(
	title: String,
	body: String,
	confirm_key := "",
	cancel_key := "COMMON_CLOSE",
	on_confirm := Callable()
) -> ModalSheet:
	_modal.open(title, body, confirm_key, cancel_key, on_confirm)
	return _modal


## Screen-space centre of the Gold counter, used by the claim fly animation.
func get_currency_anchor() -> Vector2:
	return _gold_label.get_global_rect().get_center()


## Animates a reward label from `from_global` into the Gold counter.
func fly_reward(from_global: Vector2, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"HudValue"
	label.z_index = 100
	label.position = from_global - Vector2(40.0, 24.0)
	add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", get_currency_anchor(), 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(label, "modulate:a", 0.0, 0.55)
	tween.chain().tween_callback(label.queue_free)


## Id of the visible tab ("home" before the first selection).
func get_active_tab() -> String:
	return _active_id


## Opens the debug-only monetization panel. Called from the Home 5-tap.
func open_monetization_debug() -> void:
	if not OS.is_debug_build():
		return
	if _debug_panel == null:
		var packed := load(DEBUG_PANEL_SCENE) as PackedScene
		if packed == null:
			push_warning("[MainMenu] missing debug panel: %s" % DEBUG_PANEL_SCENE)
			return
		_debug_panel = packed.instantiate()
		if _debug_panel == null:
			return
		add_child(_debug_panel)
		_debug_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_debug_panel.open()


## True while the monetization debug panel is on screen.
func is_debug_panel_open() -> bool:
	return _debug_panel != null and _debug_panel.visible


## Closes the debug panel if it is open.
func close_monetization_debug() -> void:
	if _debug_panel != null:
		_debug_panel.close()


## Android back behaviour, also used by the desktop Esc key and the tests.
func go_back() -> void:
	if not is_node_ready():
		return
	_handle_back()


func _ensure_screen(tab_id: String) -> MenuScreen:
	var cached: Variant = _screens.get(tab_id, null)
	if cached != null:
		return cached as MenuScreen
	var packed := load(MENU_SCREENS[tab_id]) as PackedScene
	if packed == null:
		push_error("[MainMenu] missing screen scene: %s" % MENU_SCREENS[tab_id])
		return null
	var instance := packed.instantiate()
	if not instance is MenuScreen:
		push_error("[MainMenu] %s is not a MenuScreen" % MENU_SCREENS[tab_id])
		instance.queue_free()
		return null
	var screen := instance as MenuScreen
	screen.main_menu = self
	_screen_host.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screens[tab_id] = screen
	return screen


func _refresh_chrome() -> void:
	_gold_label.text = "%s  %s" % [
		Loc.t_key("CURRENCY_GOLD"), Loc.format_number(GameState.get_gold())
	]
	_gems_label.text = "%s  %s" % [
		Loc.t_key("CURRENCY_GEMS"), Loc.format_number(GameState.get_gems())
	]
	_elf_label.text = Loc.t_key("TOP_ELF", {"level": GameState.get_elf_level()})
	_best_label.text = Loc.t_key("TOP_BEST", {
		"wave": Loc.format_number(GameState.get_best_wave()),
	})
	_battle_shortcut.text = Loc.t_key("MENU_BATTLE")
	for id: String in _tab_buttons:
		var button := _tab_buttons[id] as Button
		var label := button.get_node_or_null("Stack/Label") as Label
		if label != null:
			label.text = Loc.t_key("TAB_%s" % id.to_upper())
		button.tooltip_text = Loc.t_key("TAB_%s" % id.to_upper())


func _apply_safe_area() -> void:
	if _safe_area == null:
		return
	var viewport_size := get_viewport_rect().size
	var window_size := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	var scale_y := 1.0
	if window_size.y > 0:
		scale_y = viewport_size.y / float(window_size.y)
	var top_inset := int(maxf(0.0, float(safe.position.y) * scale_y))
	var bottom_inset := int(maxf(0.0, float(window_size.y - safe.end.y) * scale_y))
	_safe_area.add_theme_constant_override("margin_top", TOP_MARGIN + top_inset)
	_safe_area.add_theme_constant_override("margin_bottom", BOTTOM_MARGIN + bottom_inset)
	_safe_area.add_theme_constant_override("margin_left", SIDE_MARGIN)
	_safe_area.add_theme_constant_override("margin_right", SIDE_MARGIN)


func _tab_id_for(node_name: StringName) -> String:
	return String(node_name).trim_prefix("Tab").to_lower()


## Colours the stacked icon and label of one tab.
func _tint_tab(button: Button, active: bool) -> void:
	var color := TAB_ACCENT if active else TAB_MUTED
	var icon := button.get_node_or_null("Stack/Icon") as TextureRect
	if icon != null:
		icon.self_modulate = color
	var label := button.get_node_or_null("Stack/Label") as Label
	if label != null:
		label.add_theme_color_override("font_color", color)


func _on_tab_pressed(tab_id: String) -> void:
	AudioManager.play_ui("ui_click")
	select_tab(tab_id)


func _on_battle_pressed() -> void:
	AudioManager.play_ui("ui_click")
	SceneRouter.goto(BATTLE_SCENE)


func _on_currency_changed(_amount: int) -> void:
	_refresh_chrome()
	_refresh_active_screen()


func _on_meta_changed() -> void:
	_refresh_active_screen()


func _on_language_changed(_locale: String) -> void:
	_refresh_chrome()
	_refresh_active_screen()


func _refresh_active_screen() -> void:
	if _active_screen != null:
		_active_screen.refresh()


func _on_modal_closed() -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		go_back()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()


## Android back: close the debug panel, then the sheet, then return to Home,
## then confirm exit.
func _handle_back() -> void:
	if is_debug_panel_open():
		close_monetization_debug()
		return
	if _modal.visible:
		_modal.close()
		return
	if _active_id != "home":
		select_tab("home")
		return
	_show_exit_confirm()


func _show_exit_confirm() -> void:
	open_modal(
		Loc.t_key("MENU_EXIT_TITLE"),
		Loc.t_key("MENU_EXIT_BODY"),
		"MENU_EXIT_CONFIRM",
		"COMMON_CANCEL",
		func() -> void:
			get_tree().quit()
	)
