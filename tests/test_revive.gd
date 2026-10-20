extends Node
## Headless revive-flow suite: the defeat prompt must either revive the tree or
## end the run, never leave the battle paused with no UI.
##
## This pins the stage-8 "give up freezes the game" bug: the prompt used to hide
## itself before emitting `give_up_requested`, so `Battle` saw a hidden prompt,
## returned early, and left `get_tree().paused` true forever.
##
## Run with:
##   godot --headless --path <project> res://tests/TestRevive.tscn

const BATTLE_SCENE := preload("res://scenes/battle/Battle.tscn")

var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	_finish()


func _run() -> void:
	await get_tree().process_frame
	SaveManager.reset_progress()
	GameState.from_dict(SaveDefaults.create())

	_section("give up ends the paused run")
	var battle := await _start_battle()
	_check(battle != null, "battle scene starts")
	if battle == null:
		return
	battle.auto_route_results = false
	battle.offer_revive = true
	battle.core.take_damage(99999.0)
	await _wait_seconds(0.8)
	_check(battle.hud.is_revive_visible(), "the defeat prompt is shown")
	_check(get_tree().paused, "the run is paused while the prompt is open")
	_check(not battle.is_over(), "the run is not over while the prompt is open")

	var prompt := battle.find_child("RevivePrompt", true, false)
	_check(prompt != null, "the prompt node exists")
	if prompt != null:
		prompt.call("_on_give_up_pressed")
	await _wait_seconds(0.3)
	_check(battle.is_over(), "giving up marks the run as over")
	_check(not get_tree().paused, "giving up releases the pause")
	_check(not battle.hud.is_revive_visible(), "giving up closes the prompt")
	_check(battle.wave_manager.get_state() != WaveManager.State.SPAWNING, "the wave loop is stopped")
	_cleanup(battle)

	_section("revive restores the run")
	battle = await _start_battle()
	_check(battle != null, "battle scene restarts")
	if battle == null:
		return
	battle.auto_route_results = false
	battle.offer_revive = true
	Monetization.debug_force_rewarded("success")
	Monetization.set_fake_ad_delay(0.0)
	battle.core.take_damage(99999.0)
	await _wait_seconds(0.8)
	_check(battle.hud.is_revive_visible(), "the prompt appears for the revive path")
	var prompt2 := battle.find_child("RevivePrompt", true, false)
	if prompt2 != null:
		prompt2.call("_on_revive_pressed")
	await _wait_seconds(0.6)
	_check(not battle.is_over(), "a successful revive does not end the run")
	_check(not get_tree().paused, "a successful revive releases the pause")
	_check(not battle.hud.is_revive_visible(), "a successful revive closes the prompt")
	_check(battle.core.get_hp() > 0.0, "a successful revive restores Tree HP")
	_cleanup(battle)

	_section("cleanup")
	Monetization.debug_reset_ads()
	SaveManager.reset_progress()
	GameState.from_dict(SaveDefaults.create())
	_check(not get_tree().paused, "the tree is unpaused at the end")


func _start_battle() -> Battle:
	var battle := BATTLE_SCENE.instantiate() as Battle
	if battle == null:
		return null
	add_child(battle)
	await get_tree().process_frame
	await get_tree().physics_frame
	return battle


func _wait_seconds(seconds: float) -> void:
	var waited := 0.0
	while waited < seconds:
		await get_tree().create_timer(0.02, true, false, true).timeout
		waited += 0.02


func _cleanup(battle: Battle) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	battle.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("ALL REVIVE TESTS PASSED (%d checks)" % _checks)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	printerr("REVIVE TESTS FAILED: %d of %d checks" % [_failures.size(), _checks])
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
