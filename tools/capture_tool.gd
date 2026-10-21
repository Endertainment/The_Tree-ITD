extends Node
## Dev-only screenshot helper (excluded from export).
##
## Renders the menu, the battle HUD, both bottom sheets, the upgrade panel, a
## wave-modifier banner, the boss bar and the results screen:
##   godot --path <project> res://tools/CaptureTool.tscn
## It exists so layout, Cyrillic rendering and the battle HUD can be checked
## without a device.

const MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"
const BATTLE_SCENE := "res://scenes/battle/Battle.tscn"
const RESULTS_SCENE := "res://scenes/battle/Results.tscn"
const SETTLE_SECONDS := 0.8
const LOCALE_SETTLE_SECONDS := 0.3
const BATTLE_SETTLE_SECONDS := 1.0
const WAVE_SETTLE_SECONDS := 3.0
const PAUSE_SETTLE_SECONDS := 0.3
const RESULTS_SETTLE_SECONDS := 1.4

var _menu: Node
var _battle: Battle


class ResultsCapture extends Node:
	## Survives the battle -> results scene swap and captures the results screen.
	const RESULTS_PATH := "res://scenes/battle/Results.tscn"
	const SETTLE := 1.4
	const LOCALE_SETTLE := 0.3

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_capture_results()

	func _capture_results() -> void:
		var waited := 0.0
		while true:
			await get_tree().process_frame
			waited += get_process_delta_time()
			var current := get_tree().current_scene
			if current != null and current.scene_file_path == RESULTS_PATH:
				break
			if waited > 10.0:
				printerr("[capture] results screen never appeared")
				get_tree().quit(1)
				return
		await get_tree().create_timer(SETTLE, true, false, true).timeout
		await _capture("results_defeat")
		Loc.set_locale("uk")
		await get_tree().create_timer(LOCALE_SETTLE, true, false, true).timeout
		await _capture("results_defeat_uk")
		get_tree().quit(0)

	func _capture(label: String) -> void:
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := "user://screenshot_%s.png" % label
		var err := image.save_png(path)
		print("[capture] %s -> %s (error %d)" % [path, ProjectSettings.globalize_path(path), err])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var data := SaveManager.load_game()
	GameState.from_dict(data)
	Loc.set_locale("en")
	AudioManager.apply_settings()

	_menu = load(MAIN_MENU_SCENE).instantiate()
	add_child(_menu)
	await get_tree().create_timer(SETTLE_SECONDS, true, false, true).timeout
	await _capture("menu_en")

	Loc.set_locale("uk")
	await get_tree().create_timer(LOCALE_SETTLE_SECONDS, true, false, true).timeout
	await _capture("menu_uk")

	Loc.set_locale("en")
	await get_tree().create_timer(LOCALE_SETTLE_SECONDS, true, false, true).timeout
	_menu.queue_free()
	await get_tree().process_frame

	_battle = load(BATTLE_SCENE).instantiate() as Battle
	add_child(_battle)
	_battle.process_mode = Node.PROCESS_MODE_PAUSABLE
	await get_tree().create_timer(BATTLE_SETTLE_SECONDS, true, false, true).timeout
	await _capture("battle_prep")

	Loc.set_locale("uk")
	await get_tree().create_timer(LOCALE_SETTLE_SECONDS, true, false, true).timeout
	await _capture("battle_prep_uk")

	Loc.set_locale("en")
	_battle.wave_manager.call_wave_early()
	await get_tree().create_timer(WAVE_SETTLE_SECONDS, true, false, true).timeout
	await _capture("battle_wave")

	# Show the pooled "+N" popups by killing a few enemies.
	var killed := 0
	for enemy: Enemy in _battle.enemy_pool.get_active():
		if killed >= 3:
			break
		if enemy.is_targetable():
			enemy.take_damage(99999.0)
			killed += 1
	await get_tree().create_timer(0.2, true, false, true).timeout
	await _capture("battle_popup")

	# Fill the three upgrade slots so the stress shot matches the acceptance
	# budget (70 enemies + 5 archers).
	var archer_scene := preload("res://scenes/battle/Archer.tscn")
	for index in range(_count_archers(), RunStats.MAX_ARCHERS):
		var archer: Archer = archer_scene.instantiate()
		_battle.archers_root.add_child(archer)
		archer.global_position = _battle.core.get_archer_anchor(index)
		archer.setup(
			_battle.enemy_pool,
			_battle.projectile_pool,
			_battle.run_stats.archer_damage,
			_battle.run_stats.archer_interval,
			_battle.run_stats.archer_range,
			_battle.run_stats.projectile_speed
		)

	# Stress the pool and show the F3 overlay for a readable performance shot.
	var grunt := ConfigDB.get_enemy("orc_grunt")
	for index in EnemyPool.MAX_ALIVE:
		var angle := TAU * float(index) / float(EnemyPool.MAX_ALIVE)
		var position := Battle.CENTER + Vector2(cos(angle), sin(angle)) * Battle.SPAWN_RADIUS
		_battle.enemy_pool.spawn(grunt, position, {"spawn_delay": 0.0, "hp_mult": 20.0})
	_battle.hud.toggle_debug()
	await get_tree().create_timer(2.5, true, false, true).timeout
	await _capture("battle_stress")
	_battle.hud.toggle_debug()

	# Build every pad, then capture the ring and both bottom sheets.
	_battle.add_coins(10000)
	var pad_list := _battle.tower_manager.get_pads()
	var tower_ids: Array[String] = ["archer_tower", "spirit_tower", "ballista"]
	for index in pad_list.size():
		_battle.tower_manager.build(pad_list[index], tower_ids[index % 3])
	_battle.tower_manager.upgrade(pad_list[0].tower)
	_battle.tower_manager.upgrade(pad_list[0].tower)
	await get_tree().create_timer(0.8, true, false, true).timeout
	await _capture("battle_towers")

	_battle.hud.toggle_debug()
	await get_tree().create_timer(2.0, true, false, true).timeout
	await _capture("battle_towers_stress")
	_battle.hud.toggle_debug()

	_battle.open_pad(pad_list[0])
	await get_tree().create_timer(PAUSE_SETTLE_SECONDS, true, false, true).timeout
	await _capture("battle_tower_sheet")
	Loc.set_locale("uk")
	await get_tree().create_timer(LOCALE_SETTLE_SECONDS, true, false, true).timeout
	await _capture("battle_tower_sheet_uk")
	Loc.set_locale("en")
	await get_tree().create_timer(LOCALE_SETTLE_SECONDS, true, false, true).timeout
	_battle.close_sheet()

	_battle.open_pad(pad_list[1])
	await get_tree().create_timer(PAUSE_SETTLE_SECONDS, true, false, true).timeout
	await _capture("battle_tower_sheet_l1")
	_battle.close_sheet()

	_battle.tower_manager.sell(pad_list[7].tower)
	_battle.open_pad(pad_list[7])
	await get_tree().create_timer(PAUSE_SETTLE_SECONDS, true, false, true).timeout
	await _capture("battle_build_sheet")
	_battle.close_sheet()

	# Disabled cards: leave just 10 Coins and reopen the empty pad.
	_battle.spend_coins(_battle.coins - 10)
	_battle.open_pad(pad_list[7])
	await get_tree().create_timer(PAUSE_SETTLE_SECONDS, true, false, true).timeout
	await _capture("battle_build_sheet_locked")
	_battle.close_sheet()

	# Pause drawn on top of an open tower sheet (pause ownership check).
	_battle.open_pad(pad_list[6])
	await get_tree().create_timer(PAUSE_SETTLE_SECONDS, true, false, true).timeout
	_battle.pause_run()
	await get_tree().create_timer(PAUSE_SETTLE_SECONDS, true, false, true).timeout
	await _capture("battle_sheet_pause")
	_battle.resume_run()
	_battle.close_sheet()

	_battle.pause_run()
	await get_tree().create_timer(PAUSE_SETTLE_SECONDS, true, false, true).timeout
	await _capture("battle_pause")
	_battle.resume_run()

	# Stage 4: upgrade panel, in both locales.
	_battle.add_coins(2000)
	_battle.open_upgrades()
	await get_tree().create_timer(PAUSE_SETTLE_SECONDS, true, false, true).timeout
	await _capture("battle_upgrades")
	var archers_tab := _battle.hud.find_child("ArchersTab", true, false) as Button
	if archers_tab != null:
		archers_tab.pressed.emit()
		await get_tree().create_timer(PAUSE_SETTLE_SECONDS, true, false, true).timeout
		await _capture("battle_upgrades_archers")
		var tree_tab := _battle.hud.find_child("TreeTab", true, false) as Button
		if tree_tab != null:
			tree_tab.pressed.emit()
			await get_tree().create_timer(PAUSE_SETTLE_SECONDS, true, false, true).timeout
	Loc.set_locale("uk")
	await get_tree().create_timer(LOCALE_SETTLE_SECONDS, true, false, true).timeout
	await _capture("battle_upgrades_uk")
	Loc.set_locale("en")
	await get_tree().create_timer(LOCALE_SETTLE_SECONDS, true, false, true).timeout
	_battle.close_sheet()

	# Wave-modifier banner and a boss wave for the bar / silhouette. Clear the
	# stress crowd first so the boss and its escorts read clearly.
	_battle.enemy_pool.despawn_all()
	_battle.wave_manager.start(4242)
	_battle.wave_manager.debug_begin_wave(8)
	await get_tree().create_timer(0.4, true, false, true).timeout
	await _capture("battle_modifier")
	_battle.enemy_pool.despawn_all()
	_battle.wave_manager.debug_begin_wave(10)
	await get_tree().create_timer(2.5, true, false, true).timeout
	await _capture("battle_boss")

	# Real defeat flow: the helper survives the scene swap and captures Results.
	var helper := ResultsCapture.new()
	helper.name = "ResultsCapture"
	get_tree().root.add_child(helper)
	await get_tree().process_frame
	_battle.core.take_damage(999999.0)


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "user://screenshot_%s.png" % label
	var err := image.save_png(path)
	print("[capture] %s -> %s (error %d)" % [path, ProjectSettings.globalize_path(path), err])


func _count_archers() -> int:
	var count := 0
	for child in _battle.archers_root.get_children():
		if child is Archer:
			count += 1
	return count
