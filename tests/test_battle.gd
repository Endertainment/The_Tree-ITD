extends Node
## Headless stage-2 battle smoke test.
##
## Run with:
##   godot --headless --path <project> res://tests/TestBattle.tscn
##
## Exits 0 when every check passes. It exercises spawning, steering, archer
## kills, Coins, wave clear, contact damage, pause and defeat without a window.

const BATTLE_SCENE := preload("res://scenes/battle/Battle.tscn")

var _checks := 0
var _failures: Array[String] = []
var _battle: Battle
var _wave_clears := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.wave_cleared.connect(_on_wave_cleared)
	await _run()
	_finish()


func _run() -> void:
	await get_tree().process_frame

	_section("start")
	_battle = BATTLE_SCENE.instantiate()
	# Keep the battle alive after a defeat; the real game routes to Results.
	_battle.auto_route_results = false
	add_child(_battle)
	# The test root runs ALWAYS so it survives pause; the battle itself must be
	# pausable, exactly like the real scene root.
	_battle.process_mode = Node.PROCESS_MODE_PAUSABLE
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check(_battle.coins == RunStats.BASE_COINS, "run starts with 120 Coins")
	_check(is_equal_approx(_battle.core.get_hp(), RunStats.BASE_TREE_HP), "Tree starts at 1000 HP")
	_check(_count_archers() == RunStats.BASE_ARCHERS, "two archers spawn")
	_check(
		_battle.wave_manager.get_state() == WaveManager.State.PREPARE,
		"run starts in PREPARE"
	)
	_check(_battle.wave_manager.get_prep_remaining() > 8.0, "first prep is ~10 s")

	_section("armor")
	var health := HealthComponent.new()
	health.setup(100.0, 3.0)
	_check(is_equal_approx(health.apply_damage(10.0), 7.0), "armor subtracts from damage")
	health.setup(100.0, 30.0)
	_check(is_equal_approx(health.apply_damage(10.0), 1.0), "damage floors at 1")
	health.setup(100.0, 30.0)
	_check(is_equal_approx(health.apply_damage(10.0, true), 10.0), "ignore-armor skips armor")
	health.free()

	_section("debug overlay")
	var key := InputEventKey.new()
	key.keycode = KEY_F3
	key.pressed = true
	get_viewport().push_input(key)
	await get_tree().process_frame
	_check(_battle.hud.is_debug_visible(), "F3 opens the debug overlay")
	key = InputEventKey.new()
	key.keycode = KEY_F3
	key.pressed = true
	get_viewport().push_input(key)
	await get_tree().process_frame
	_check(not _battle.hud.is_debug_visible(), "F3 closes the debug overlay")

	_section("call wave")
	var bonus := _battle.wave_manager.get_call_bonus()
	_check(bonus >= 4 and bonus <= 5, "calling immediately grants 4-5 Coins")
	_check(_battle.wave_manager.call_wave_early(), "call wave is accepted during prep")
	_check(_battle.coins == RunStats.BASE_COINS + bonus, "call bonus is added to Coins")
	_check(_battle.wave_manager.get_wave() == 1, "wave counter advances to 1")

	_section("steering")
	await _simulate(2.0)
	_check(_battle.get_active_enemy_count() > 0, "wave 1 spawns enemies")
	_check(_battle.get_active_enemy_count() <= EnemyPool.MAX_ALIVE, "alive cap is respected")

	var first: Enemy = _first_targetable_enemy()
	_check(first != null, "at least one enemy is active")
	if first != null:
		var distance_before := first.global_position.distance_to(Battle.CENTER)
		await _simulate(1.0)
		var distance_after := first.global_position.distance_to(Battle.CENTER)
		_check(distance_after < distance_before, "enemies converge on the Tree")
		_check(
			distance_before > Battle.ARENA_RADIUS - 200.0,
			"enemies spawn outside the playfield"
		)

	_section("separation")
	var grunt := ConfigDB.get_enemy("orc_grunt")
	var separation_origin := Battle.CENTER + Vector2(0.0, 420.0)
	var a := _battle.enemy_pool.spawn(grunt, separation_origin, {"spawn_delay": 0.0})
	var b := _battle.enemy_pool.spawn(grunt, separation_origin, {"spawn_delay": 0.0})
	_check(a != null and b != null, "two enemies can share a spawn point")
	if a != null and b != null:
		await _simulate(1.0)
		_check(
			a.global_position.distance_to(b.global_position) > 8.0,
			"separation pushes overlapping enemies apart"
		)
		a.take_damage(9999.0)
		b.take_damage(9999.0)

	_section("wave clear and rewards")
	var coins_before_clear := _battle.coins
	await _simulate(24.0)
	var cleared := _battle.wave_manager.get_cleared_waves()
	_check(cleared >= 1, "wave 1 clears with archers only")
	_check(_wave_clears >= 1, "wave_cleared signal fires")
	if cleared >= 1:
		_check(_battle.kills >= 5, "archer arrows killed wave 1")
		_check(_battle.coins >= coins_before_clear, "Coins never decrease during the run")
		_check(_battle.coins > coins_before_clear, "kills and clear reward add Coins")
		_check(
			_battle.wave_manager.get_wave() >= 2,
			"wave 2 starts automatically after the 6 s prep"
		)

	_section("contact damage")
	var hp_before := _battle.core.get_hp()
	var brute := ConfigDB.get_enemy("orc_brute")
	_battle.enemy_pool.spawn(brute, Battle.CENTER + Vector2(150.0, 0.0), {"spawn_delay": 0.0})
	await _simulate(1.5)
	_check(_battle.core.get_hp() < hp_before, "an enemy at the Tree damages it")

	_section("pause")
	var sample: Enemy = _first_targetable_enemy()
	_battle.pause_run()
	_check(get_tree().paused, "pause sets the scene tree paused")
	_check(_battle.hud.is_pause_visible(), "pause sheet is visible")
	# Let the in-flight physics frame finish before sampling the position.
	await _real_wait(0.1)
	var sample_position := sample.global_position if sample != null else Vector2.ZERO
	await _real_wait(0.3)
	if sample != null:
		_check(
			sample.global_position.distance_to(sample_position) < 0.01,
			"enemies freeze while paused"
		)
	_battle.resume_run()
	_check(not get_tree().paused, "resume clears the paused flag")

	_section("quit confirmation")
	_battle.pause_run()
	var quit_button := _battle.hud.find_child("QuitButton", true, false) as Button
	var cancel_button := _battle.hud.find_child("QuitCancel", true, false) as Button
	_check(quit_button != null and cancel_button != null, "quit controls exist")
	if quit_button != null and cancel_button != null:
		quit_button.pressed.emit()
		_check(_battle.hud.is_quit_confirm_visible(), "quit asks for confirmation")
		cancel_button.pressed.emit()
		_check(not _battle.hud.is_quit_confirm_visible(), "cancel keeps the run")
	_battle.resume_run()

	_section("defeat")
	_battle.core.take_damage(999999.0)
	await _real_wait(1.0)
	_check(_battle.is_over(), "Tree death ends the run")
	_check(_battle.summary.reason == &"defeat", "summary reason is defeat")
	_check(_battle.summary.waves_cleared >= 1, "summary keeps cleared waves")
	_check(_battle.summary.kills >= 5, "summary keeps kill count")
	_check(_battle.summary.bosses_killed == 0, "no boss was killed before wave 10")
	_check(not get_tree().paused, "the battle releases the pause on the way out")

	_section("cleanup")
	get_tree().paused = false
	Engine.time_scale = 1.0
	_battle.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(orphans < 20, "no orphan node growth (%d orphans)" % orphans)


func _count_archers() -> int:
	var count := 0
	for child in _battle.archers_root.get_children():
		if child is Archer:
			count += 1
	return count


func _first_targetable_enemy() -> Enemy:
	for enemy: Enemy in _battle.enemy_pool.get_active():
		if enemy.is_targetable():
			return enemy
	return null


func _simulate(seconds: float) -> void:
	var frames := maxi(1, int(round(seconds * 60.0)))
	for _index in frames:
		await get_tree().physics_frame


func _real_wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _on_wave_cleared(_wave: int, _time_taken: float) -> void:
	_wave_clears += 1


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("ALL BATTLE TESTS PASSED (%d checks)" % _checks)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	printerr("BATTLE TESTS FAILED: %d of %d checks" % [_failures.size(), _checks])
	get_tree().quit(1)


func _section(title: String) -> void:
	print("")
	print("== %s ==" % title)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures.append(message)
		print("  FAIL ", message)
