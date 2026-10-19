class_name Battle
extends Node2D
## Owns one run: Coins, archers, waves, pause/defeat and the RunSummary.
##
## Gameplay nodes are pausable; the HUD is `PROCESS_MODE_ALWAYS` so pause and
## defeat panels keep working while `get_tree().paused` is true.

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
const ARCHER_SCENE := preload("res://scenes/battle/Archer.tscn")
const TOAST_SCENE := preload("res://ui/Toast.tscn")

var coins := 0
var coins_earned := 0
var kills := 0
var run_time := 0.0
var summary: RunSummary
var rng := RandomNumberGenerator.new()

@onready var core: Core = $Core
@onready var enemy_pool: EnemyPool = $EnemyPool
@onready var projectile_pool: ProjectilePool = $ProjectilePool
@onready var wave_manager: WaveManager = $WaveManager
@onready var floating_layer: FloatingTextLayer = $FloatingTextLayer
@onready var hud: BattleHUD = $HUD
@onready var archers_root: Node2D = $Core/Archers

var _ended := false
var _ending := false
var _toast: Toast


func _ready() -> void:
	rng.randomize()
	enemy_pool.setup(self)
	wave_manager.setup(enemy_pool, self)
	core.setup(BASE_TREE_HP)

	_toast = TOAST_SCENE.instantiate()
	_toast.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_toast)

	hud.bind(self, wave_manager)
	hud.pause_requested.connect(pause_run)
	hud.resume_requested.connect(resume_run)
	hud.quit_requested.connect(_on_quit_confirmed)
	hud.back_to_menu_requested.connect(_on_back_to_menu)
	hud.call_wave_requested.connect(_on_call_wave)
	hud.upgrades_requested.connect(_on_upgrades)
	hud.settings_requested.connect(_on_settings)

	core.died.connect(_on_core_died)
	EventBus.enemy_died.connect(_on_enemy_died)

	Analytics.set_screen("battle")
	start_run()


## Resets Coins, archers, waves and the summary, then emits `run_started`.
func start_run(modifiers: Dictionary = {}) -> void:
	_ended = false
	_ending = false
	enemy_pool.despawn_all()
	projectile_pool.clear_all()
	floating_layer.clear_all()
	coins = 0
	coins_earned = 0
	kills = 0
	run_time = 0.0

	summary = RunSummary.new()
	summary.reason = &"in_progress"

	var tree_hp := BASE_TREE_HP * float(modifiers.get("tree_hp_mult", 1.0))
	core.setup(tree_hp)
	_spawn_archers(BASE_ARCHERS + int(modifiers.get("start_archers_add", 0)))

	coins = maxi(0, START_COINS + int(modifiers.get("start_coins_add", 0)))
	hud.set_pause_enabled(true)
	hud.hide_defeat()
	wave_manager.start()

	EventBus.run_started.emit()
	EventBus.coins_changed.emit(coins)


## Adds run Coins and updates the earned total. Wave rewards and kills call this.
func add_coins(amount: int) -> void:
	if amount <= 0:
		return
	coins += amount
	coins_earned += amount
	EventBus.coins_changed.emit(coins)


## Called by WaveManager when a wave is cleared. The reward is already added.
func on_wave_cleared(wave: int, reward: int, time_taken: float) -> void:
	add_coins(reward)
	EventBus.wave_cleared.emit(wave, time_taken)
	hud.show_wave_cleared(wave, reward)


## Freezes gameplay and opens the pause sheet. Safe to call twice.
func pause_run() -> void:
	if _ended or _ending or get_tree().paused:
		return
	SpeedService.reset()
	get_tree().paused = true
	hud.show_pause(true)


## Closes the pause sheet and resumes the simulation.
func resume_run() -> void:
	if not get_tree().paused:
		return
	get_tree().paused = false
	hud.show_pause(false)


## Ends the run once, builds the summary and routes or shows the defeat panel.
func end_run(reason: StringName) -> void:
	if _ended:
		return
	_ended = true
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


## Active enemy nodes, including enemies still playing their death effect.
func get_active_enemy_count() -> int:
	return enemy_pool.count_present()


## Enemies that can be targeted or damage the Tree right now.
func get_alive_enemy_count() -> int:
	return enemy_pool.count_alive()


## Arrows currently in flight.
func get_active_arrow_count() -> int:
	return projectile_pool.count_active()


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


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if hud != null:
			hud.handle_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if not _ended and not _ending:
			pause_run()


func _exit_tree() -> void:
	if get_tree() != null:
		get_tree().paused = false
	if SpeedService != null:
		SpeedService.reset()


func _spawn_archers(count: int) -> void:
	for child in archers_root.get_children():
		if child is Archer:
			archers_root.remove_child(child)
			child.queue_free()

	var archer_count := clampi(count, 0, 5)
	for index in archer_count:
		var archer: Archer = ARCHER_SCENE.instantiate()
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
	wave_manager.stop()
	hud.set_pause_enabled(false)
	Engine.time_scale = DEFEAT_SLOW_MO
	await get_tree().create_timer(DEFEAT_SLOW_MO_SECONDS, true, false, true).timeout
	Engine.time_scale = 1.0
	SpeedService.reset()
	_ending = false
	end_run(&"defeat")
