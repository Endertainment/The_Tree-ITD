class_name Battle
extends Node2D
## Owns one run: Coins, archers, waves, towers, pause/defeat and the RunSummary.
##
## Gameplay nodes are pausable; the HUD is `PROCESS_MODE_ALWAYS` so pause,
## sheets and the defeat panel keep working while `get_tree().paused` is true.
## Tower world state lives in `TowerManager`; this script owns the run economy
## and the sheet/pause ownership rules.

const CENTER := Vector2(540.0, 900.0)
const ARENA_RADIUS := 500.0
const SPAWN_RADIUS := 640.0
const CORE_RADIUS := 90.0

# TODO(stage-4): move these run constants into RunModifiers once it exists.
const START_COINS := 120
const BASE_TREE_HP := 1000.0
const BASE_ARCHERS := 2
const ARCHER_DAMAGE := 12.0
const ARCHER_INTERVAL := 0.8
const ARCHER_RANGE := 520.0
const ARCHER_PROJECTILE_SPEED := 900.0
const DEFEAT_SLOW_MO := 0.35
const DEFEAT_SLOW_MO_SECONDS := 0.4

const MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"
## `Archer.tscn` is deliberately loaded in `_ready()` instead of `preload`:
## preloading it here closes a Battle -> Archer -> Enemy -> Battle script cycle,
## and a cyclic preload yields an empty PackedScene in some load orders.
const ARCHER_SCENE_PATH := "res://scenes/battle/Archer.tscn"
const TOAST_SCENE := preload("res://ui/Toast.tscn")
const BUILD_SHEET_SCENE := preload("res://scenes/battle/BuildSheet.tscn")
const TOWER_SHEET_SCENE := preload("res://scenes/battle/TowerSheet.tscn")

var coins := 0
var coins_earned := 0
var kills := 0
var run_time := 0.0
var summary: RunSummary
var rng := RandomNumberGenerator.new()

## Same Array instance as `TowerManager.obstacles`; enemies read it directly.
var obstacles: Array[Dictionary] = []

@onready var core: Core = $Core
@onready var enemy_pool: EnemyPool = $EnemyPool
@onready var projectile_pool: ProjectilePool = $ProjectilePool
@onready var tower_projectile_pool: TowerProjectilePool = %TowerProjectilePool
@onready var tower_manager: TowerManager = %TowerManager
@onready var wave_manager: WaveManager = $WaveManager
@onready var floating_layer: FloatingTextLayer = $FloatingTextLayer
@onready var hud: BattleHUD = $HUD
@onready var archers_root: Node2D = $Core/Archers

var _ended := false
var _ending := false
var _toast: Toast
var _build_sheet: BuildSheet
var _tower_sheet: TowerSheet
var _sheet_open := false
var _active_pad: BuildPad
var _tower_cost_mult := 1.0
var _archer_scene: PackedScene


func _ready() -> void:
	rng.randomize()
	_archer_scene = load(ARCHER_SCENE_PATH) as PackedScene
	enemy_pool.setup(self)
	tower_projectile_pool.setup(enemy_pool, self)
	tower_manager.setup(self, enemy_pool, tower_projectile_pool)
	obstacles = tower_manager.obstacles
	enemy_pool.set_obstacles(obstacles)
	wave_manager.setup(enemy_pool, self)
	core.setup(BASE_TREE_HP)

	_toast = TOAST_SCENE.instantiate()
	_toast.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_toast)

	_create_sheets()

	hud.bind(self, wave_manager)
	hud.pause_requested.connect(pause_run)
	hud.resume_requested.connect(resume_run)
	hud.quit_requested.connect(_on_quit_confirmed)
	hud.back_to_menu_requested.connect(_on_back_to_menu)
	hud.call_wave_requested.connect(_on_call_wave)
	hud.upgrades_requested.connect(_on_upgrades)
	hud.settings_requested.connect(_on_settings)
	hud.back_requested.connect(_handle_back)

	core.died.connect(_on_core_died)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.coins_changed.connect(_on_coins_changed)
	EventBus.language_changed.connect(_on_language_changed)
	EventBus.tower_built.connect(_on_tower_built)

	Analytics.set_screen("battle")
	start_run()


## Resets Coins, archers, towers, waves and the summary, then emits `run_started`.
func start_run(modifiers: Dictionary = {}) -> void:
	_ended = false
	_ending = false
	close_sheet()
	# A run always starts from a clean pause state, even when the previous run
	# ended on the defeat panel or with a sheet open.
	get_tree().paused = false
	hud.show_pause(false)
	enemy_pool.despawn_all()
	projectile_pool.clear_all()
	tower_projectile_pool.clear_all()
	tower_manager.reset()
	floating_layer.clear_all()
	coins = 0
	coins_earned = 0
	kills = 0
	run_time = 0.0
	_tower_cost_mult = float(modifiers.get("tower_cost_mult", 1.0))

	summary = RunSummary.new()
	summary.reason = &"in_progress"

	var tree_hp := BASE_TREE_HP * float(modifiers.get("tree_hp_mult", 1.0))
	core.setup(tree_hp)
	_spawn_archers(BASE_ARCHERS + int(modifiers.get("start_archers_add", 0)))

	coins = maxi(0, START_COINS + int(modifiers.get("start_coins_add", 0)))
	hud.set_pause_enabled(true)
	hud.hide_defeat()
	wave_manager.start()
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


## Current price of a tower, including the run's `tower_cost_mult`.
func get_tower_cost(tower_id: String) -> int:
	var data := ConfigDB.get_tower(tower_id) as TowerData
	if data == null:
		return 0
	return Tower.round_to_step(float(data.cost) * _tower_cost_mult, Tower.PRICE_STEP)


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


## Called by WaveManager when a wave is cleared. The reward is already added.
func on_wave_cleared(wave: int, reward: int, time_taken: float) -> void:
	add_coins(reward)
	EventBus.wave_cleared.emit(wave, time_taken)
	hud.show_wave_cleared(wave, reward)


## Freezes gameplay and opens the pause sheet. Safe to call twice.
func pause_run() -> void:
	if _ended or _ending or hud.is_pause_visible():
		return
	SpeedService.reset()
	get_tree().paused = true
	hud.show_pause(true)


## Closes the pause sheet and resumes, unless a build/tower sheet is still open.
func resume_run() -> void:
	if not hud.is_pause_visible():
		return
	hud.show_pause(false)
	if not _sheet_open and not _ended and not _ending:
		get_tree().paused = false


## Ends the run once, builds the summary and routes or shows the defeat panel.
func end_run(reason: StringName) -> void:
	if _ended:
		return
	_ended = true
	close_sheet()
	wave_manager.stop()
	hud.set_pause_enabled(false)

	if summary == null:
		summary = RunSummary.new()
	summary.waves_cleared = wave_manager.get_cleared_waves()
	summary.kills = kills
	summary.coins_earned = coins_earned
	summary.time_seconds = run_time
	summary.reason = reason

	EventBus.run_ended.emit(summary)
	Analytics.log_event("run_ended", summary.to_dict())

	if reason == &"quit":
		get_tree().paused = false
		SpeedService.reset()
		SceneRouter.goto(MAIN_MENU_SCENE)
	elif reason == &"defeat":
		get_tree().paused = true
		hud.show_defeat(summary)


## True once `end_run` has built the summary.
func is_over() -> bool:
	return _ended


## True while a build or tower sheet owns the pause.
func is_sheet_open() -> bool:
	return _sheet_open


## Opens the build sheet for an empty pad, or the tower sheet for a built one.
## Pauses the tree and keeps exactly one sheet on screen.
func open_pad(pad: BuildPad) -> void:
	if pad == null or _sheet_open or _ended or _ending:
		return
	_sheet_open = true
	_active_pad = pad
	tower_manager.select(pad)
	get_tree().paused = true
	hud.set_sheet_mode(true)

	var inset := hud.get_bottom_inset()
	if pad.has_tower():
		_tower_sheet.set_bottom_inset(inset)
		_tower_sheet.open(pad.tower, self)
	else:
		_build_sheet.set_bottom_inset(inset)
		_build_sheet.open(pad, self)


## Closes whichever sheet is open and releases the pause it held.
func close_sheet() -> void:
	if not _sheet_open:
		return
	_sheet_open = false
	_build_sheet.close()
	_tower_sheet.close()
	hud.set_sheet_mode(false)
	tower_manager.select(null)
	_active_pad = null
	if not _ended and not _ending and not hud.is_pause_visible():
		get_tree().paused = false


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


func _process(delta: float) -> void:
	if not _ended and not _ending:
		run_time += delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_F3:
			hud.toggle_debug()
			get_viewport().set_input_as_handled()
			return

	if _sheet_open or _ended or _ending:
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
		if not _ended and not _ending and not _sheet_open and not get_tree().paused:
			pause_run()


func _exit_tree() -> void:
	if get_tree() != null:
		get_tree().paused = false
	if SpeedService != null:
		SpeedService.reset()


func _create_sheets() -> void:
	var host := hud.get_sheet_host()
	_build_sheet = BUILD_SHEET_SCENE.instantiate()
	_build_sheet.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_build_sheet)
	_build_sheet.build_requested.connect(_on_build_requested)
	_build_sheet.close_requested.connect(_on_sheet_close_requested)

	_tower_sheet = TOWER_SHEET_SCENE.instantiate()
	_tower_sheet.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_tower_sheet)
	_tower_sheet.close_requested.connect(_on_sheet_close_requested)
	_tower_sheet.upgrade_requested.connect(_on_tower_upgrade_requested)
	_tower_sheet.sell_requested.connect(_on_tower_sell_requested)
	_tower_sheet.target_mode_changed.connect(_on_target_mode_changed)


func _handle_tap(screen_position: Vector2) -> bool:
	var world := get_global_transform_with_canvas().affine_inverse() * screen_position
	var pad := tower_manager.find_pad_at(world)
	if pad == null:
		return false
	open_pad(pad)
	return true


func _handle_back() -> void:
	if hud.is_quit_confirm_visible() or hud.is_pause_visible():
		hud.handle_back()
		return
	if _sheet_open:
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

	var archer_count := clampi(count, 0, 5)
	for index in archer_count:
		var archer: Archer = _archer_scene.instantiate() as Archer
		if archer == null:
			push_error("[Battle] could not instantiate the archer scene")
			return
		archers_root.add_child(archer)
		archer.global_position = core.get_archer_anchor(index)
		archer.setup(
			enemy_pool,
			projectile_pool,
			ARCHER_DAMAGE,
			ARCHER_INTERVAL,
			ARCHER_RANGE,
			ARCHER_PROJECTILE_SPEED
		)


func _on_enemy_died(_enemy_id: String, coin_value: int, position: Vector2) -> void:
	kills += 1
	floating_layer.add_popup("+%d" % coin_value, position)


func _on_call_wave() -> void:
	if _ended or _ending:
		return
	wave_manager.call_wave_early()


func _on_quit_confirmed() -> void:
	hud.show_pause(false)
	get_tree().paused = false
	end_run(&"quit")


func _on_back_to_menu() -> void:
	close_sheet()
	get_tree().paused = false
	SpeedService.reset()
	SceneRouter.goto(MAIN_MENU_SCENE)


func _on_upgrades() -> void:
	_toast.show_message(Loc.t_key("HUD_UPGRADES_SOON"))


func _on_settings() -> void:
	_toast.show_message(Loc.t_key("PAUSE_SETTINGS_SOON"))


func _on_core_died() -> void:
	if _ending or _ended:
		return
	_ending = true
	close_sheet()
	wave_manager.stop()
	hud.set_pause_enabled(false)
	Engine.time_scale = DEFEAT_SLOW_MO
	await get_tree().create_timer(DEFEAT_SLOW_MO_SECONDS, true, false, true).timeout
	Engine.time_scale = 1.0
	SpeedService.reset()
	_ending = false
	end_run(&"defeat")


func _on_coins_changed(_amount: int) -> void:
	tower_manager.on_coins_changed()


func _on_language_changed(_locale: String) -> void:
	_refresh_tower_hud()
	if not _sheet_open:
		return
	if _active_pad != null and _active_pad.has_tower():
		_tower_sheet.refresh()
	else:
		_build_sheet.refresh()


func _on_build_requested(tower_id: String) -> void:
	if _active_pad == null:
		return
	if tower_manager.build(_active_pad, tower_id):
		_refresh_tower_hud()
		close_sheet()
		return
	_build_sheet.refresh()


func _on_tower_upgrade_requested(tower: Tower) -> void:
	if tower_manager.upgrade(tower):
		_refresh_tower_hud()
	_tower_sheet.refresh()


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
	_tower_sheet.refresh()


func _on_sheet_close_requested() -> void:
	close_sheet()


func _on_tower_built(_tower_id: String) -> void:
	_refresh_tower_hud()
