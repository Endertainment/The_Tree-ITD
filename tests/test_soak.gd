extends Node
## Headless battle soak test: ten simulated minutes of waves, deaths and popups.
##
## Run with:
##   godot --headless --path <project> --fixed-fps 60 res://tests/TestSoak.tscn
##
## The Tree HP is raised so the run cannot end, and every active enemy is killed
## every 20 simulated seconds to force pool churn. It checks for orphan nodes and
## node-count growth at the end.

const BATTLE_SCENE := preload("res://scenes/battle/Battle.tscn")
const SIM_SECONDS := 600.0
const KILL_INTERVAL_SECONDS := 20.0
const WAVE_INTERVAL_SECONDS := 6.0
const PHYSICS_FPS := 60.0

var _battle: Battle
var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	_finish()


func _run() -> void:
	await get_tree().process_frame
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.process_mode = Node.PROCESS_MODE_PAUSABLE
	await get_tree().physics_frame
	_battle.core.setup(1000000.0)

	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var total_frames := int(SIM_SECONDS * PHYSICS_FPS)
	var kill_every := int(KILL_INTERVAL_SECONDS * PHYSICS_FPS)
	var wave_every := int(WAVE_INTERVAL_SECONDS * PHYSICS_FPS)

	for frame in total_frames:
		if frame % wave_every == 0:
			_battle.wave_manager.call_wave_early()
		if frame > 0 and frame % kill_every == 0:
			_kill_all_active()
		await get_tree().physics_frame

	var nodes_after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	print("")
	print("== soak summary ==")
	print("  simulated seconds: %.0f" % SIM_SECONDS)
	print("  wave: %d  cleared: %d  kills: %d" % [
		_battle.wave_manager.get_wave(),
		_battle.wave_manager.get_cleared_waves(),
		_battle.kills,
	])
	print("  nodes: %d -> %d  orphans: %d" % [nodes_before, nodes_after, orphans])

	_check(int(_battle.wave_manager.get_wave()) >= 20, "at least 20 waves started")
	_check(_battle.kills >= 300, "pool churn produced 300+ kills")
	_check(_battle.core.get_hp() > 0.0, "Tree survives the raised-HP soak")
	_check(orphans < 20, "orphan node count stays low (%d)" % orphans)
	_check(nodes_after < nodes_before + 120, "node count does not grow with pools")

	get_tree().paused = false
	Engine.time_scale = 1.0
	_battle.queue_free()
	await get_tree().process_frame


func _kill_all_active() -> void:
	for enemy: Enemy in _battle.enemy_pool.get_active():
		if enemy.is_targetable():
			enemy.take_damage(99999.0)


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("ALL SOAK TESTS PASSED (%d checks)" % _checks)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	printerr("SOAK TESTS FAILED: %d of %d checks" % [_failures.size(), _checks])
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures.append(message)
		print("  FAIL ", message)
