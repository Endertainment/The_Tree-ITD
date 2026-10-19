class_name BattleHUD
extends CanvasLayer
## Battle HUD, pause sheet, boss bar, wave banner and the bottom action bar.
##
## Runs with `PROCESS_MODE_ALWAYS` so it keeps working while the gameplay tree is
## paused. Results are a separate scene now; this HUD never shows them.

signal pause_requested
signal resume_requested
signal quit_requested
signal call_wave_requested
signal upgrades_requested
signal settings_requested
signal revive_requested
signal revive_give_up_requested
signal speed_info_requested

## Android back / Escape. `Battle` decides whether to close a sheet or pause.
signal back_requested

const BASE_MARGIN_TOP := 18
const BASE_MARGIN_BOTTOM := 18
const SIDE_MARGIN := 32
const DEBUG_REFRESH_SECONDS := 0.25

@onready var _top_safe: MarginContainer = %TopSafe
@onready var _bottom_safe: MarginContainer = %BottomSafe
@onready var _hp_label: Label = %HpLabel
@onready var _hp_bar: ProgressBar = %HpBar
@onready var _wave_label: Label = %WaveLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _coins_caption: Label = %CoinsCaption
@onready var _coins_label: Label = %CoinsLabel
@onready var _speed_button: SpeedButton = %SpeedButton
@onready var _pause_button: Button = %PauseButton
@onready var _call_button: Button = %CallButton
@onready var _upgrades_button: Button = %UpgradesButton
@onready var _revive_prompt: RevivePrompt = %RevivePrompt
@onready var _banner: VBoxContainer = %Banner
@onready var _banner_title: Label = %BannerTitle
@onready var _banner_bonus: Label = %BannerBonus
@onready var _wave_banner: WaveBanner = %WaveBanner
@onready var _boss_bar: BossBar = %BossBar
@onready var _debug_label: Label = %DebugLabel
@onready var _pause_menu: Control = %PauseMenu
@onready var _pause_title: Label = %PauseTitle
@onready var _resume_button: Button = %ResumeButton
@onready var _quit_button: Button = %QuitButton
@onready var _settings_button: Button = %SettingsButton
@onready var _pause_version: Label = %PauseVersion
@onready var _quit_confirm: Control = %QuitConfirm
@onready var _quit_title: Label = %QuitTitle
@onready var _quit_body: Label = %QuitBody
@onready var _quit_cancel: Button = %QuitCancel
@onready var _quit_confirm_button: Button = %QuitConfirmButton
@onready var _tower_count: Label = %TowerCount
@onready var _pad_hint: Label = %PadHint
@onready var _sheet_host: Control = %SheetHost
@onready var _vignette: ColorRect = %DamageVignette

var _battle: Battle
var _waves: WaveManager
var _stats: RunStats
var _vignette_tween: Tween
var _last_state := -1
var _last_prep_second := -1
var _last_bonus := -1
var _debug_accum := 0.0
var _banner_tween: Tween
var _coin_tween: Tween
var _bottom_inset := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_menu.visible = false
	_quit_confirm.visible = false
	_sheet_host.visible = false
	_revive_prompt.close()
	_banner.modulate.a = 0.0
	_debug_label.visible = false

	_pause_button.pressed.connect(_on_pause_pressed)
	_resume_button.pressed.connect(_on_resume_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_cancel.pressed.connect(_on_quit_cancel)
	_quit_confirm_button.pressed.connect(_on_quit_confirmed)
	_call_button.pressed.connect(_on_call_pressed)
	_upgrades_button.pressed.connect(_on_upgrades_pressed)
	_speed_button.info_requested.connect(_on_speed_info_pressed)
	_revive_prompt.revive_requested.connect(func() -> void: revive_requested.emit())
	_revive_prompt.give_up_requested.connect(func() -> void: revive_give_up_requested.emit())

	EventBus.coins_changed.connect(_on_coins_changed)
	EventBus.core_damaged.connect(_on_core_damaged)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.language_changed.connect(_on_language_changed)
	get_viewport().size_changed.connect(_apply_safe_area)

	_refresh_texts()
	_apply_safe_area()
	_hp_bar.max_value = 1000.0
	_hp_bar.value = 1000.0
	_coins_label.text = "0"


## Wires the HUD to the run that owns it and paints the initial state.
func bind(battle: Battle, waves: WaveManager) -> void:
	_battle = battle
	_waves = waves
	_hp_bar.max_value = battle.core.get_max_hp()
	_refresh_texts()
	set_coins(battle.coins)
	set_hp(battle.core.get_hp(), battle.core.get_max_hp())
	_hide_announcements()
	_last_state = -1
	_refresh_wave_state()


## Keeps a reference to the live stats for the debug overlay.
func set_stats(stats: RunStats) -> void:
	_stats = stats


## Shows the boss bar for a freshly spawned boss.
func show_boss(boss: Boss) -> void:
	_boss_bar.show_boss(boss)


## Hides the boss bar.
func hide_boss() -> void:
	_boss_bar.hide_boss()


## Shows the 1.5 s modifier banner for a wave, if the wave has one.
func show_wave_modifier(wave: int, modifier: int) -> void:
	if modifier == WaveRules.Modifier.NONE:
		return
	var key := WaveRules.banner_key(modifier)
	if key.is_empty():
		return
	_wave_banner.show_banner(Loc.t_key(key))
	Analytics.log_event("wave_modifier", {"wave": wave, "modifier": WaveRules.modifier_name(modifier)})


## Updates the Coins readout with thousands separators and pulses on change.
func set_coins(amount: int) -> void:
	var text := Loc.format_number(amount)
	if _coins_label.text == text:
		return
	_coins_label.text = text
	if _coin_tween != null and _coin_tween.is_valid():
		_coin_tween.kill()
	_coins_label.pivot_offset = _coins_label.size * 0.5
	_coins_label.scale = Vector2(1.12, 1.12)
	_coin_tween = create_tween()
	_coin_tween.tween_property(_coins_label, "scale", Vector2.ONE, 0.22)


## Updates the built-tower counter and shows the first-run pad hint.
func set_tower_count(built: int, total: int) -> void:
	_tower_count.text = Loc.t_key("HUD_TOWERS", {"built": built, "total": total})
	_pad_hint.text = Loc.t_key("HUD_TAP_PAD")
	_pad_hint.visible = built == 0


## Hides the bottom action bar while a sheet is open.
func set_sheet_mode(active: bool) -> void:
	_bottom_safe.visible = not active
	_sheet_host.visible = active


## Container that hosts the build, tower and upgrade sheets.
func get_sheet_host() -> Control:
	return _sheet_host


## Safe-area inset at the bottom of the screen, in design pixels.
func get_bottom_inset() -> int:
	return _bottom_inset


## Updates the HP label and bar from the current Tree values.
func set_hp(current: float, maximum: float) -> void:
	_hp_bar.max_value = maxf(1.0, maximum)
	_hp_bar.value = clampf(current, 0.0, maximum)
	_hp_label.text = Loc.t_key("HUD_HP", {
		"current": int(ceil(maxf(0.0, current))),
		"max": int(maximum),
	})


## Enables or disables the pause button (disabled during the defeat slow-mo).
func set_pause_enabled(enabled: bool) -> void:
	_pause_button.disabled = not enabled


## Shows or hides the pause sheet and closes the quit confirmation with it.
func show_pause(visible_now: bool) -> void:
	_pause_menu.visible = visible_now
	if visible_now:
		_quit_confirm.visible = false


## True while the pause sheet is visible.
func is_pause_visible() -> bool:
	return _pause_menu.visible


## True while the quit confirmation is on top of the pause sheet.
func is_quit_confirm_visible() -> bool:
	return _quit_confirm.visible


## Shows the wave-cleared banner under the top bar.
func show_wave_cleared(wave: int, bonus: int) -> void:
	_banner_title.text = Loc.t_key("HUD_WAVE_CLEARED", {"wave": wave})
	_banner_bonus.text = Loc.t_key("HUD_WAVE_BONUS", {"coins": bonus})
	_banner.modulate.a = 1.0
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(1.2)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.45)


## Shows the defeat revive prompt and pauses input on the HUD behind it.
func show_revive_prompt() -> void:
	_pause_menu.visible = false
	_quit_confirm.visible = false
	_revive_prompt.open()


## Hides the revive prompt.
func hide_revive_prompt() -> void:
	_revive_prompt.close()


## True while the revive prompt is visible.
func is_revive_visible() -> bool:
	return _revive_prompt.is_open()


## Disables the revive actions while the ad is pending.
func set_revive_busy(busy: bool) -> void:
	_revive_prompt.set_busy(busy)


## Repaints the speed button after the trial or an unlock changed.
func refresh_speed() -> void:
	_speed_button.refresh()


## Toggles the F3 diagnostics overlay.
func toggle_debug() -> void:
	_debug_label.visible = not _debug_label.visible
	if _debug_label.visible:
		_update_debug()


## True while the F3 overlay is visible.
func is_debug_visible() -> bool:
	return _debug_label.visible


## Android back / Escape: the revive prompt requires a choice, then close the
## top panel, else open pause.
func handle_back() -> void:
	if _revive_prompt.is_open():
		return
	if _quit_confirm.visible:
		_quit_confirm.visible = false
		return
	if _pause_menu.visible:
		resume_requested.emit()
		return
	pause_requested.emit()


func _process(delta: float) -> void:
	if _waves == null:
		return

	if _debug_label.visible:
		_debug_accum += delta
		if _debug_accum >= DEBUG_REFRESH_SECONDS:
			_debug_accum = 0.0
			_update_debug()

	var state := _waves.get_state()
	if state != _last_state:
		_refresh_wave_state()

	if _waves.is_preparing():
		var seconds := int(ceil(_waves.get_prep_remaining()))
		if seconds != _last_prep_second:
			_last_prep_second = seconds
			_timer_label.text = Loc.t_key("HUD_NEXT_IN", {"seconds": seconds})
		var bonus := _waves.get_call_bonus()
		if bonus != _last_bonus:
			_last_bonus = bonus
			_call_button.text = Loc.t_key("HUD_CALL_WAVE_BONUS", {"bonus": bonus})


func _refresh_wave_state() -> void:
	if _waves == null:
		return
	_last_state = _waves.get_state()
	var wave := _waves.get_wave()

	match _last_state:
		WaveManager.State.PREPARE:
			_wave_label.text = Loc.t_key("HUD_PREPARE") if wave == 0 else Loc.t_key("HUD_WAVE", {"wave": wave})
			_timer_label.visible = true
			_call_button.disabled = false
			_last_prep_second = -1
			_last_bonus = -1
		WaveManager.State.SPAWNING, WaveManager.State.CLEARING:
			_wave_label.text = Loc.t_key("HUD_WAVE", {"wave": wave})
			_timer_label.visible = true
			_timer_label.text = Loc.t_key("HUD_IN_PROGRESS")
			_call_button.disabled = true
			_call_button.text = Loc.t_key("HUD_CALL_DISABLED")
		_:
			_timer_label.visible = false
			_call_button.disabled = true
			_call_button.text = Loc.t_key("HUD_CALL_WAVE")


func _refresh_texts() -> void:
	_coins_caption.text = Loc.t_key("HUD_COINS")
	_upgrades_button.text = Loc.t_key("HUD_UPGRADES")
	_pause_title.text = Loc.t_key("PAUSE_TITLE")
	_resume_button.text = Loc.t_key("PAUSE_RESUME")
	_quit_button.text = Loc.t_key("PAUSE_QUIT")
	_settings_button.text = Loc.t_key("PAUSE_SETTINGS")
	_quit_title.text = Loc.t_key("QUIT_TITLE")
	_quit_body.text = Loc.t_key("QUIT_BODY")
	_quit_cancel.text = Loc.t_key("QUIT_CANCEL")
	_quit_confirm_button.text = Loc.t_key("QUIT_CONFIRM")
	_pad_hint.text = Loc.t_key("HUD_TAP_PAD")
	_speed_button.refresh()
	_revive_prompt.refresh_texts()

	var version := str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	_pause_version.text = Loc.t_key("VERSION_LABEL", {"version": version})


func _update_debug() -> void:
	if _battle == null:
		return
	var run_total := maxi(0, int(_battle.run_time))
	var dps := 0.0
	if _stats != null:
		dps = _stats.get_archer_dps()
	_debug_label.text = "FPS %d\nWAVE %d  %s  MOD %s\nALIVE %d  QUEUED %d\nARROWS %d  SHOTS %d  POPUPS %d  CELLS %d\nHP %d/%d  REGEN %.1f  DPS %d\nTIME x%.2f  RUN %d:%02d" % [
		Engine.get_frames_per_second(),
		_battle.wave_manager.get_wave(),
		_battle.wave_manager.get_state_name(),
		WaveRules.modifier_name(_battle.wave_manager.get_wave_modifier()),
		_battle.get_alive_enemy_count(),
		_battle.get_queued_enemy_count(),
		_battle.get_active_arrow_count(),
		_battle.get_active_tower_shot_count(),
		_battle.floating_layer.count_active(),
		_battle.enemy_pool.get_spatial_cell_count(),
		int(_battle.core.get_hp()),
		int(_battle.core.get_max_hp()),
		_battle.core.get_regen(),
		int(round(dps)),
		Engine.time_scale,
		run_total / 60,
		run_total % 60,
	]


func _apply_safe_area() -> void:
	var insets := SafeArea.insets_for(
		DisplayServer.window_get_size(),
		DisplayServer.get_display_safe_area(),
		get_viewport().get_visible_rect().size,
		OS.has_feature("mobile")
	)
	_top_safe.add_theme_constant_override("margin_top", BASE_MARGIN_TOP + int(insets.x))
	_top_safe.add_theme_constant_override("margin_left", SIDE_MARGIN + int(insets.w))
	_top_safe.add_theme_constant_override("margin_right", SIDE_MARGIN + int(insets.y))
	_bottom_safe.add_theme_constant_override("margin_bottom", BASE_MARGIN_BOTTOM + int(insets.z))
	_bottom_safe.add_theme_constant_override("margin_left", SIDE_MARGIN + int(insets.w))
	_bottom_safe.add_theme_constant_override("margin_right", SIDE_MARGIN + int(insets.y))
	_bottom_inset = int(insets.z)


func _hide_announcements() -> void:
	_banner.modulate.a = 0.0
	_wave_banner.hide_banner()
	_boss_bar.hide_boss()


func _on_coins_changed(amount: int) -> void:
	set_coins(amount)


func _on_core_damaged(current: float, maximum: float) -> void:
	set_hp(current, maximum)


func _on_wave_started(wave: int) -> void:
	_wave_label.text = Loc.t_key("HUD_WAVE", {"wave": wave})


func _on_language_changed(_locale: String) -> void:
	_refresh_texts()
	_refresh_wave_state()
	_wave_banner.hide_banner()
	if _battle != null:
		_coins_label.text = Loc.format_number(_battle.coins)
		set_hp(_battle.core.get_hp(), _battle.core.get_max_hp())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()


func _on_pause_pressed() -> void:
	pause_requested.emit()


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_quit_pressed() -> void:
	_quit_confirm.visible = true


func _on_quit_cancel() -> void:
	_quit_confirm.visible = false


func _on_quit_confirmed() -> void:
	quit_requested.emit()


func _on_call_pressed() -> void:
	call_wave_requested.emit()


func _on_upgrades_pressed() -> void:
	upgrades_requested.emit()


func _on_settings_pressed() -> void:
	settings_requested.emit()


func _on_speed_info_pressed() -> void:
	speed_info_requested.emit()


## Global rect of the UPGRADES button, used by the tutorial highlight.
func get_upgrades_button_rect() -> Rect2:
	return Rect2(_upgrades_button.global_position, _upgrades_button.size)


## Global rect of the CALL WAVE button, used by the tutorial highlight.
func get_call_button_rect() -> Rect2:
	return Rect2(_call_button.global_position, _call_button.size)


## Pulses the red damage vignette. Skipped on low quality.
func pulse_damage() -> void:
	if _vignette == null or GameState.is_low_quality():
		return
	if _vignette_tween != null and _vignette_tween.is_valid():
		_vignette_tween.kill()
	_vignette.color.a = 0.0
	_vignette_tween = create_tween()
	_vignette_tween.tween_property(_vignette, "color:a", 0.34, 0.08)
	_vignette_tween.tween_property(_vignette, "color:a", 0.0, 0.36)
