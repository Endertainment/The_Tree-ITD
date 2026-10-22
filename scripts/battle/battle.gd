class_name Battle
extends Node2D
## Owns one run: Coins, stats, archers, waves, towers, pause/defeat and the
## RunSummary.
##
## Gameplay nodes are pausable; the HUD is `PROCESS_MODE_ALWAYS` so pause,
## sheets and the results hand-off keep working while `get_tree().paused` is
## true. Tower world state lives in `TowerManager`, sheet ownership in
## `BattleSheets`, and every live combat value in `RunStats`.

const CENTER := Vector2(540.0, 900.0)
const ARENA_RADIUS := 500.0
const SPAWN_RADIUS := 640.0
const CORE_RADIUS := 90.0

const DEFEAT_SLOW_MO := 0.35
const DEFEAT_SLOW_MO_SECONDS := 0.4
const BOSS_SLOW_MO := 0.25
const BOSS_SLOW_MO_SECONDS := 0.3
const RESULTS_SCENE := "res://scenes/battle/Results.tscn"

const BENCHMARK_SECONDS := 10.0
const BENCHMARK_ENEMIES := 70
const BENCHMARK_TOWERS := 8
const HIT_SHAKE_PIXELS := 6.0
## One Back press can arrive twice (OS notification plus ui_cancel).
const BACK_DEBOUNCE_MS := 250

var _last_back_msec := 0
const CORE_SHAKE_PIXELS := 4.0

## Emitted when the player calls the next wave early.
signal wave_called

## `Archer.tscn` is deliberately loaded in `_ready()` instead of `preload`:
## preloading it here closes a Battle -> Archer -> Enemy -> Battle script cycle,
## and a cyclic preload yields an empty PackedScene in some load orders.
const ARCHER_SCENE_PATH := "res://scenes/battle/Archer.tscn"
const TOAST_SCENE := preload("res://ui/Toast.tscn")

var coins := 0
var coins_earned := 0
var kills := 0
var run_time := 0.0
var summary: RunSummary
var rng := RandomNumberGenerator.new()
var run_modifiers: RunModifiers
var run_stats: RunStats

## Tests switch this off to exercise the old immediate-defeat path.
var offer_revive := true

## Tests switch this off to keep the battle scene alive after a defeat.
var auto_route_results := true

## Same Array instance as `TowerManager.obstacles`; enemies read it directly.
var obstacles: Array[Dictionary] = []

## Enemy shots (spears, curse orbs, stones) aimed at the Tree.
var _enemy_shots: EnemyProjectilePool

@onready var core: Core = $Core
@onready var enemy_pool: EnemyPool = $EnemyPool
@onready var projectile_pool: ProjectilePool = $ProjectilePool
@onready var tower_projectile_pool: TowerProjectilePool = %TowerProjectilePool
@onready var tower_manager: TowerManager = %TowerManager
@onready var wave_manager: WaveManager = $WaveManager
@onready var floating_layer: FloatingTextLayer = $FloatingTextLayer
@onready var hud: BattleHUD = $HUD
@onready var archers_root: Node2D = $Core/Archers
@onready var vfx: VfxLayer = %VfxLayer
@onready var shake: ScreenShake = %ScreenShake
@onready var tutorial: TutorialController = %TutorialOverlay

var _bench_active := false
var _bench_time := 0.0
var _bench_frames := 0
var _bench_duration := BENCHMARK_SECONDS

var _ended := false
var _ending := false
var _toast: Toast
var _sheets: BattleSheets
var _archer_scene: PackedScene
var _boss_slow_mo := false
var _starting_run := false
var _revive_used := false
var _revive_offered := false
var _reviving := false
var _speed_before_defeat := 1.0


func _ready() -> void:
	_apply_battle_background()
	# A run has its own track; without `battle_theme` the menu music stops and
	# the run stays SFX-only.

	AudioManager.play_battle_music(0.8)
	rng.randomize()
	_archer_scene = load(ARCHER_SCENE_PATH) as PackedScene
	enemy_pool.setup(self)
	_enemy_shots = EnemyProjectilePool.new()
	_enemy_shots.name = "EnemyShots"
	add_child(_enemy_shots)
	_enemy_shots.setup(self)
	tower_projectile_pool.setup(enemy_pool, self)
	tower_manager.setup(self, enemy_pool, tower_projectile_pool)
	obstacles = tower_manager.obstacles
	enemy_pool.set_obstacles(obstacles)
	wave_manager.setup(enemy_pool, self)
	core.setup(RunStats.BASE_TREE_HP)

	_toast = TOAST_SCENE.instantiate()
	_toast.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_toast)

	_create_sheets()

	hud.bind(self, wave_manager)
	hud.pause_requested.connect(pause_run)
	hud.resume_requested.connect(resume_run)
	hud.quit_requested.connect(_on_quit_confirmed)
	hud.call_wave_requested.connect(_on_call_wave)
	hud.upgrades_requested.connect(_on_upgrades)
	hud.settings_requested.connect(_on_settings)
	hud.back_requested.connect(_handle_back)
	hud.revive_requested.connect(_on_revive_requested)
	hud.revive_give_up_requested.connect(_on_revive_give_up)
	hud.speed_info_requested.connect(_on_speed_info_requested)

	core.died.connect(_on_core_died)
	core.damage_taken.connect(_on_core_hit)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.coins_changed.connect(_on_coins_changed)
	EventBus.language_changed.connect(_on_language_changed)
	EventBus.tower_built.connect(_on_tower_built)
	EventBus.boss_died.connect(_on_boss_died)
	wave_manager.wave_announced.connect(_on_wave_announced)

	Analytics.set_screen("battle")
	tutorial.setup(self, hud, tower_manager)
	start_run()
	tutorial.start_if_needed()


## Resets Coins, stats, archers, towers, waves and the summary, then emits
## `run_started`. Passing null builds the modifiers from the save file.
func start_run(modifiers: RunModifiers = null) -> void:
	_ended = false
	_ending = false
	_boss_slow_mo = false
	_revive_used = false
	_revive_offered = false
	_reviving = false
	_speed_before_defeat = 1.0
	close_sheet()
	hud.hide_revive_prompt()
	# A run always starts from a clean pause state, even when the previous run
	# ended on the results panel or with a sheet open.
	get_tree().paused = false
	hud.show_pause(false)
	enemy_pool.despawn_all()
	projectile_pool.clear_all()
	tower_projectile_pool.clear_all()
	if _enemy_shots != null:
		_enemy_shots.clear_all()
	tower_manager.reset()
	floating_layer.clear_all()
	coins = 0
	coins_earned = 0
	kills = 0
	run_time = 0.0

	# A trial bought on the pre-battle panel is consumed by the run it starts.
	var trial := SpeedService.consume_pending_trial_15()
	if modifiers != null:
		run_modifiers = modifiers
		if trial:
			run_modifiers.speed_trial_15 = true
	else:
		run_modifiers = RunModifiers.build(
			GameState.to_dict(),
			GameState.get_equipped_cards(),
			trial
		)
	SpeedService.set_run_trials(run_modifiers.speed_trial_15, run_modifiers.speed_trial_2)
	_ensure_run_stats()
	_starting_run = true
	run_stats.setup(run_modifiers)
	_starting_run = false

	summary = RunSummary.new()
	summary.reason = &"in_progress"
	summary.best_wave_before = GameState.get_best_wave()
	summary.gold_mult = run_modifiers.gold_mult

	core.setup(run_stats.max_hp)
	core.apply_stats(run_stats)
	_spawn_archers(run_stats.start_archers)

	coins = run_stats.start_coins
	hud.set_pause_enabled(true)
	hud.set_stats(run_stats)
	hud.refresh_speed()
	wave_manager.start(rng.randi())
	_refresh_tower_hud()
	tower_manager.on_coins_changed()

	EventBus.run_started.emit()
	EventBus.coins_changed.emit(coins)


## Adds run Coins and updates the earned total. Wave rewards and kills call this.
func add_coins(amount: int) -> void:
	if amount <= 0:
		return
	coins += amount
	coins_earned += amount
	EventBus.coins_changed.emit(coins)


## Spends Coins if the player has them. Returns false and changes nothing
## otherwise, so every build/upgrade path can share one guard.
func spend_coins(cost: int) -> bool:
	if cost <= 0:
		return true
	if coins < cost:
		return false
	coins -= cost
	EventBus.coins_changed.emit(coins)
	return true


## Multiplier applied to kill rewards by the `coin_gain` meta upgrade.
func get_kill_coin_multiplier() -> float:
	return run_stats.coin_mult if run_stats != null else 1.0


## Spawns an enemy projectile aimed at the Tree. Called by ranged enemies.
func spawn_enemy_shot(from: Vector2, kind: String, damage: float) -> void:
	if _enemy_shots != null:
		_enemy_shots.spawn(from, kind, damage)


## Enemy projectiles currently in flight, for tests and the debug overlay.
func get_active_enemy_shot_count() -> int:
	return _enemy_shots.count_active() if _enemy_shots != null else 0


## Spawns the hit spark and, when enabled, a floating damage number.
## Called by `Enemy.take_damage` so every damage source shares one path.
func show_damage(enemy: Enemy, amount: float) -> void:
	if enemy == null or not is_instance_valid(enemy) or amount <= 0.0:
		return
	var at := enemy.global_position
	vfx.hit_spark(at)
	if amount >= HIT_SHAKE_PIXELS * 8.0:
		request_shake(HIT_SHAKE_PIXELS)
	if not shows_damage_numbers():
		return
	floating_layer.add_popup(Loc.format_number(roundi(amount)), at)


## True when damage numbers are both enabled in settings and cheap enough to draw.
func shows_damage_numbers() -> bool:
	if GameState.is_low_quality():
		return false
	return bool(GameState.get_setting("show_damage_numbers", true))


## Asks the camera for a `pixels`-sized shake; low quality ignores it.
func request_shake(pixels: float) -> void:
	if shake != null:
		shake.shake_pixels(pixels)


## Runs the 70-enemy / 8-tower benchmark and reports the average FPS.
func run_benchmark(duration := BENCHMARK_SECONDS) -> void:
	if _bench_active or _ended or _ending:
		return
	_bench_active = true
	_bench_time = 0.0
	_bench_frames = 0
	_bench_duration = maxf(1.0, duration)
	var pads := tower_manager.get_pads()
	for index in mini(BENCHMARK_TOWERS, pads.size()):
		var pad: BuildPad = pads[index]
		if not pad.has_tower():
			tower_manager.build(pad, "archer_tower")
	var grunt := ConfigDB.get_enemy("orc_grunt")
	if grunt != null:
		for index in BENCHMARK_ENEMIES:
			var angle := TAU * float(index) / float(BENCHMARK_ENEMIES)
			enemy_pool.spawn(
				grunt,
				CENTER + Vector2(cos(angle), sin(angle)) * SPAWN_RADIUS * 0.9,
				{"hp_mult": 40.0, "speed_mult": 0.6, "coin_mult": 0.0, "spawn_delay": 0.0}
			)
	_toast.show_message(Loc.t_key("DEV_BENCH_RUNNING"), 3.0)


## Current price of a tower, including the run's `tower_cost_mult`.
func get_tower_cost(tower_id: String) -> int:
	var data := ConfigDB.get_tower(tower_id) as TowerData
	if data == null:
		return 0
	var cost_mult := run_stats.tower_cost_mult if run_stats != null else 1.0
	return Tower.round_to_step(float(data.cost) * cost_mult, Tower.PRICE_STEP)


## Lowest tower price this run; drives the pad affordability glow.
func get_cheapest_tower_cost() -> int:
	var cheapest := 0
	for entry: Variant in ConfigDB.all_towers():
		var data := entry as TowerData
		if data == null:
			continue
		var price := get_tower_cost(data.id)
		if cheapest == 0 or price < cheapest:
			cheapest = price
	return cheapest


## Buys one level of an in-run upgrade. Returns false when maxed or unaffordable.
func purchase_run_upgrade(track_id: String) -> bool:
	if _ended or _ending or run_stats == null:
		return false
	var track := run_stats.get_track(track_id)
	if track == null or run_stats.is_maxed(track_id):
		return false
	var cost := run_stats.get_next_cost(track_id)
	if not spend_coins(cost):
		_sheets.refresh()
		return false
	if track.effect == "max_hp":
		# Grow the Tree before the stats signal so `apply_stats` sees no delta.
		core.add_max_hp(track.value_per_level, track.value_per_level)
	if not run_stats.apply_upgrade(track_id):
		return false
	_sheets.refresh()
	return true


## Called by WaveManager when a wave is cleared. The reward is already added.
func on_wave_cleared(wave: int, reward: int, time_taken: float) -> void:
	add_coins(reward)
	AudioManager.play_sfx("victory")
	EventBus.wave_cleared.emit(wave, time_taken)
	hud.show_wave_cleared(wave, reward)


## Called by WaveManager when a boss finishes spawning.
func on_boss_spawned(boss: Boss) -> void:
	if boss == null:
		return
	Haptics.boss_spawn()
	AudioManager.play_sfx("boss_roar")
	hud.show_boss(boss)


## Freezes gameplay and opens the pause sheet. Safe to call twice.
func pause_run() -> void:
	if _ended or _ending or hud.is_pause_visible():
		return
	SpeedService.reset()
	get_tree().paused = true
	shake.reset_shake()
	hud.show_pause(true)


## Closes the pause sheet and resumes, unless a sheet is still open.
func resume_run() -> void:
	if not hud.is_pause_visible():
		return
	hud.show_pause(false)
	if not _sheets.is_open() and not _ended and not _ending:
		get_tree().paused = false


## Ends the run once, builds the summary and routes to the results screen.
func end_run(reason: StringName) -> void:
	if _ended:
		return
	_ended = true
	_revive_offered = false
	close_sheet()
	hud.hide_revive_prompt()
	tutorial.dismiss()
	shake.reset_shake()
	wave_manager.stop()
	hud.set_pause_enabled(false)
	hud.hide_boss()

	if summary == null:
		summary = RunSummary.new()
	summary.waves_cleared = wave_manager.get_cleared_waves()
	summary.kills = kills
	summary.coins_earned = coins_earned
	summary.time_seconds = run_time
	summary.reason = reason
	if run_modifiers != null:
		summary.gold_mult = run_modifiers.gold_mult

	EventBus.run_ended.emit(summary)
	Analytics.log_event("run_ended", summary.to_dict())

	get_tree().paused = false
	SpeedService.reset()
	# Fade the battle track out under the results transition.
	AudioManager.stop_music(1.2)
	if auto_route_results:
		SceneRouter.goto_with_payload(RESULTS_SCENE, summary)


## True once `end_run` has built the summary.
func is_over() -> bool:
	return _ended


## True while a build, tower or upgrade sheet owns the pause.
func is_sheet_open() -> bool:
	return _sheets != null and _sheets.is_open()


## Opens the build sheet for an empty pad, or the tower sheet for a built one.
func open_pad(pad: BuildPad) -> void:
	if _ended or _ending:
		return
	_sheets.open_pad(pad)


## Opens the in-run upgrade panel.
func open_upgrades() -> void:
	if _ended or _ending:
		return
	_sheets.open_upgrades()


## Closes whichever sheet is open and releases the pause it held.
func close_sheet() -> void:
	if _sheets != null:
		_sheets.close()


## Active enemy nodes, including enemies still playing their death effect.
func get_active_enemy_count() -> int:
	return enemy_pool.count_present()


## Enemies that can be targeted or damage the Tree right now.
func get_alive_enemy_count() -> int:
	return enemy_pool.count_alive()


## Arrows currently in flight.
func get_active_arrow_count() -> int:
	return projectile_pool.count_active()


## Tower projectiles currently in flight.
func get_active_tower_shot_count() -> int:
	return tower_projectile_pool.count_active()


## Enemies still waiting in the spawn queue.
func get_queued_enemy_count() -> int:
	return wave_manager.get_queued_count()


## Boss currently alive, or null.
func get_boss() -> Boss:
	return wave_manager.get_boss()


func _process(delta: float) -> void:
	if not _ended and not _ending:
		run_time += delta
	_tick_benchmark(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_F3:
			hud.toggle_debug()
			get_viewport().set_input_as_handled()
			return

	if is_sheet_open() or _ended or _ending:
		return

	var tap_position := Vector2.INF
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			tap_position = touch.position
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			tap_position = click.position
	if tap_position == Vector2.INF:
		return
	if _handle_tap(tap_position):
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if hud != null:
			_handle_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if not _ended and not _ending and not is_sheet_open() and not get_tree().paused:
			pause_run()


func _exit_tree() -> void:
	if get_tree() != null:
		get_tree().paused = false
	if SpeedService != null:
		SpeedService.reset()


func _ensure_run_stats() -> void:
	if run_stats == null:
		run_stats = RunStats.new()
		run_stats.stats_changed.connect(_on_stats_changed)


func _create_sheets() -> void:
	_sheets = BattleSheets.new()
	_sheets.name = "Sheets"
	add_child(_sheets)
	_sheets.setup(self, hud, tower_manager)
	_sheets.build_requested.connect(_on_build_requested)
	_sheets.tower_upgrade_requested.connect(_on_tower_upgrade_requested)
	_sheets.tower_sell_requested.connect(_on_tower_sell_requested)
	_sheets.target_mode_changed.connect(_on_target_mode_changed)
	_sheets.upgrade_requested.connect(purchase_run_upgrade)
	_sheets.tower_focus_requested.connect(_on_tower_focus_requested)


func _handle_tap(screen_position: Vector2) -> bool:
	var world := get_global_transform_with_canvas().affine_inverse() * screen_position
	var pad := tower_manager.find_pad_at(world)
	if pad == null:
		return false
	open_pad(pad)
	return true


func _handle_back() -> void:
	# Android delivers one Back press as both NOTIFICATION_WM_GO_BACK_REQUEST and
	# a ui_cancel action, so without this guard the pause toggles open and shut in
	# the same frame and Back appears to do nothing.
	var now := Time.get_ticks_msec()
	if now - _last_back_msec < BACK_DEBOUNCE_MS:
		return
	_last_back_msec = now
	if hud.is_quit_confirm_visible() or hud.is_pause_visible():
		hud.handle_back()
		return
	if is_sheet_open():
		close_sheet()
		return
	hud.handle_back()


func _refresh_tower_hud() -> void:
	hud.set_tower_count(tower_manager.count_built(), TowerManager.PAD_COUNT)


func _spawn_archers(count: int) -> void:
	if _archer_scene == null:
		push_error("[Battle] archer scene failed to load: %s" % ARCHER_SCENE_PATH)
		return
	for child in archers_root.get_children():
		if child is Archer:
			archers_root.remove_child(child)
			child.queue_free()

	var archer_count := clampi(count, 0, RunStats.MAX_ARCHERS)
	for index in archer_count:
		_spawn_archer(index)


func _spawn_archer(index: int) -> void:
	if _archer_scene == null:
		return
	var archer: Archer = _archer_scene.instantiate() as Archer
	if archer == null:
		push_error("[Battle] could not instantiate the archer scene")
		return
	archers_root.add_child(archer)
	archer.global_position = core.get_archer_anchor(index)
	archer.setup(
		enemy_pool,
		projectile_pool,
		run_stats.archer_damage,
		run_stats.archer_interval,
		run_stats.archer_range,
		run_stats.projectile_speed
	)


func _count_archers() -> int:
	var count := 0
	for child in archers_root.get_children():
		if child is Archer:
			count += 1
	return count


## Adds or removes archers so the canopy matches `RunStats.start_archers`.
func _sync_archer_count() -> void:
	if run_stats == null:
		return
	var target := run_stats.start_archers
	var current := _count_archers()
	while current < target:
		_spawn_archer(current)
		current += 1
	while current > target:
		var last := archers_root.get_child(archers_root.get_child_count() - 1)
		if last is Archer:
			archers_root.remove_child(last)
			last.queue_free()
			current -= 1
		else:
			break


func _on_stats_changed() -> void:
	if run_stats == null or _starting_run:
		return
	core.apply_stats(run_stats)
	for child in archers_root.get_children():
		if child is Archer:
			(child as Archer).apply_stats(run_stats)
	_sync_archer_count()
	hud.set_stats(run_stats)
	_refresh_tower_hud()
	if _sheets != null:
		_sheets.refresh()


func _on_enemy_died(_enemy_id: String, coin_value: int, position: Vector2) -> void:
	kills += 1
	floating_layer.add_popup("+%d" % coin_value, position)
	vfx.coin_sparkle(position)
	AudioManager.play_sfx_throttled("coin", 0.08)


func _on_call_wave() -> void:
	if _ended or _ending:
		return
	if wave_manager.call_wave_early():
		wave_called.emit()


func _on_core_hit(amount: float) -> void:
	if amount <= 0.0 or _ended or _ending:
		return
	Haptics.core_damage()
	AudioManager.play_sfx_throttled("tree_hit", 0.12)
	request_shake(CORE_SHAKE_PIXELS)
	vfx.leaf_burst(core.global_position)
	hud.pulse_damage()


func _tick_benchmark(delta: float) -> void:
	if not _bench_active:
		return
	_bench_time += delta
	_bench_frames += 1
	if _bench_time >= _bench_duration:
		_finish_benchmark()


func _finish_benchmark() -> void:
	_bench_active = false
	var fps := float(_bench_frames) / maxf(0.001, _bench_time)
	var report := Loc.t_key("DEV_BENCH_RESULT", {
		"fps": roundi(fps),
		"seconds": roundi(_bench_time),
	})
	print("[BENCHMARK] quality=%s fps=%d frames=%d seconds=%.1f draws=%d objects=%d nodes=%d orphans=%d" % [
		"low" if GameState.is_low_quality() else "high",
		roundi(fps),
		_bench_frames,
		_bench_time,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
	])
	_toast.show_message(report, 6.0)


func _on_quit_confirmed() -> void:
	hud.show_pause(false)
	get_tree().paused = false
	end_run(&"quit")


func _on_upgrades() -> void:
	open_upgrades()


func _on_settings() -> void:
	_toast.show_message(Loc.t_key("PAUSE_SETTINGS_SOON"))


func _on_core_died() -> void:
	if _ending or _ended:
		return
	if offer_revive and not _revive_used:
		_offer_revive()
		return
	_finish_defeat()


## Slow-mo into the revive prompt. The tree stays paused until the player
## chooses, and the wave state is left untouched so a revive resumes it.
func _offer_revive() -> void:
	_ending = true
	_revive_offered = true
	close_sheet()
	hud.set_pause_enabled(false)
	hud.hide_boss()
	_speed_before_defeat = SpeedService.get_speed()
	Engine.time_scale = DEFEAT_SLOW_MO
	await get_tree().create_timer(DEFEAT_SLOW_MO_SECONDS, true, false, true).timeout
	SpeedService.reset()
	get_tree().paused = true
	hud.show_revive_prompt()


## Final defeat: slow-mo, then results. Used by quit/give-up and by a second
## death after a revive.
func _finish_defeat() -> void:
	if _ended:
		return
	_ending = true
	AudioManager.play_sfx("defeat")
	close_sheet()
	hud.hide_revive_prompt()
	wave_manager.stop()
	hud.set_pause_enabled(false)
	hud.hide_boss()
	Engine.time_scale = DEFEAT_SLOW_MO
	await get_tree().create_timer(DEFEAT_SLOW_MO_SECONDS, true, false, true).timeout
	SpeedService.reset()
	_ending = false
	end_run(&"defeat")


func _on_revive_requested() -> void:
	if not _revive_offered or _revive_used:
		return
	Monetization.show_rewarded(AdPolicy.P_REVIVE, _on_revive_ad_result)


func _on_revive_ad_result(success: bool) -> void:
	if not _revive_offered:
		return
	if not success:
		_toast.show_message(Loc.t_key("REVIVE_FAILED"))
		_close_revive_prompt_and_end()
		return
	hud.hide_revive_prompt()
	get_tree().paused = false
	_revive_offered = false
	_revive_used = true
	_reviving = true
	Analytics.log_event("revive_used", {})
	AudioManager.play_sfx("revive")
	core.revive(0.5)
	_clear_enemies_near_core(250.0)
	core.grant_invulnerability(3.0)
	hud.set_pause_enabled(true)
	_ending = false
	if not SpeedService.set_speed(_speed_before_defeat):
		SpeedService.reset()
	_reviving = false
	_toast.show_message(Loc.t_key("REVIVE_SUCCESS"))


func _on_revive_give_up() -> void:
	if not _revive_offered or _revive_used:
		return
	_close_revive_prompt_and_end()


func _close_revive_prompt_and_end() -> void:
	_revive_offered = false
	hud.hide_revive_prompt()
	get_tree().paused = false
	_ending = false
	end_run(&"defeat")


## Kills every targetable enemy within `radius` of the Tree, awarding their
## Coins through the normal death flow. Returns how many were cleared.
func _clear_enemies_near_core(radius: float) -> int:
	var cleared := 0
	var snapshot := enemy_pool.get_active().duplicate()
	for enemy: Enemy in snapshot:
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_targetable():
			continue
		if enemy.global_position.distance_to(core.global_position) <= radius:
			enemy.die()
			cleared += 1
	return cleared


func _on_boss_died(_boss_index: int) -> void:
	if summary != null:
		summary.bosses_killed += 1
	AudioManager.play_sfx("boss_die")
	hud.hide_boss()
	if _reviving or _ended or _ending or _boss_slow_mo:
		return
	_boss_slow_mo = true
	Engine.time_scale = BOSS_SLOW_MO
	await get_tree().create_timer(BOSS_SLOW_MO_SECONDS, true, false, true).timeout
	_boss_slow_mo = false
	if not _ending and not _ended:
		SpeedService.reapply()


func _on_wave_announced(wave: int, modifier: int) -> void:
	AudioManager.play_sfx("wave_start")
	hud.show_wave_modifier(wave, modifier)


func _on_speed_info_requested() -> void:
	var available := SpeedService.get_available_speeds()
	if available.size() >= SpeedService.SPEEDS.size():
		_toast.show_message(Loc.t_key("SPEED_ALL_UNLOCKED"))
		return
	var next_locked := 1.5 if available.size() < 2 else 2.0
	_toast.show_message(Loc.t_key(SpeedService.get_locked_reason_key(next_locked)))


func _on_coins_changed(_amount: int) -> void:
	tower_manager.on_coins_changed()
	if _sheets != null:
		_sheets.refresh()


func _on_language_changed(_locale: String) -> void:
	_refresh_tower_hud()
	if _sheets != null:
		_sheets.refresh()


func _on_build_requested(tower_id: String) -> void:
	if _sheets.active_pad() == null:
		return
	if tower_manager.build(_sheets.active_pad(), tower_id):
		_refresh_tower_hud()
		close_sheet()
		return
	_sheets.refresh()


func _on_tower_upgrade_requested(tower: Tower) -> void:
	if tower_manager.upgrade(tower):
		_refresh_tower_hud()
	_sheets.refresh()


func _on_tower_sell_requested(tower: Tower) -> void:
	if tower == null or not is_instance_valid(tower):
		return
	var refund_position := tower.global_position
	var refund := tower_manager.sell(tower)
	if refund > 0:
		floating_layer.add_popup("+%d" % refund, refund_position)
	_refresh_tower_hud()
	close_sheet()


func _on_target_mode_changed(tower: Tower, mode: int) -> void:
	if tower == null or not is_instance_valid(tower):
		return
	tower.set_target_mode(mode)
	_sheets.refresh()


func _on_tower_focus_requested(tower: Tower) -> void:
	if tower == null or not is_instance_valid(tower) or tower.pad == null:
		return
	_sheets.focus_tower(tower)


func _on_tower_built(_tower_id: String) -> void:
	_refresh_tower_hud()

const BATTLE_BACKGROUND_PATH := "res://assets/art/battle/battle_background.png"

func _apply_battle_background() -> void:	
	var texture := ArtLibrary.texture(BATTLE_BACKGROUND_PATH)
	if texture == null:
		return
	var background := TextureRect.new()
	background.name = "ArtBackground"
	background.texture = texture
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	move_child(background, 0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var flat := get_node_or_null("Background") as ColorRect
	
	if flat != null:
		flat.visible = false
	
