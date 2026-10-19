extends Node
## Headless scene-flow test: MainMenu.BATTLE unlocks Battle, the quit
## confirmation opens the Results screen, and MAIN MENU returns to the menu.
##
## Run with:
##   godot --headless --path <project> res://tests/TestFlow.tscn
##
## A monitor node is parented to the tree root so it survives every scene swap.

const MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"
const BATTLE_SCENE := "res://scenes/battle/Battle.tscn"
const RESULTS_SCENE := "res://scenes/battle/Results.tscn"
const TIMEOUT_SECONDS := 24.0
const QUIT_DELAY_SECONDS := 0.6

var _monitor: FlowMonitor


class FlowMonitor extends Node:
	var elapsed := 0.0
	var phase := 0
	var phase_time := 0.0
	var prep_checked := false
	var battle: Battle

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		elapsed += delta
		phase_time += delta
		var current := get_tree().current_scene
		var path := current.scene_file_path if current != null else "<none>"

		if phase == 0:
			if path == BATTLE_SCENE:
				phase = 1
				phase_time = 0.0
				battle = current as Battle
		elif phase == 1:
			if battle != null:
				if not prep_checked and phase_time >= QUIT_DELAY_SECONDS:
					prep_checked = true
					if battle.wave_manager.get_prep_remaining() < 7.0:
						printerr("FLOW TEST FAILED: first prep is not ~10 s")
						get_tree().quit(1)
						return
				if battle.wave_manager.get_wave() >= 1:
					# The 10 s prep ran out and wave 1 started automatically.
					battle.pause_run()
					var quit_button := battle.hud.find_child("QuitButton", true, false) as Button
					var confirm_button := battle.hud.find_child("QuitConfirmButton", true, false) as Button
					if quit_button == null or confirm_button == null:
						printerr("FLOW TEST FAILED: quit confirmation buttons missing")
						get_tree().quit(1)
						return
					quit_button.pressed.emit()
					confirm_button.pressed.emit()
					battle = null
					phase = 2
					phase_time = 0.0
				elif prep_checked and phase_time > 12.0:
					printerr("FLOW TEST FAILED: wave 1 did not start after prep")
					get_tree().quit(1)
					return
		elif phase == 2:
			if path == RESULTS_SCENE and phase_time >= 0.5:
				var menu_button := current.find_child("MenuButton", true, false) as Button
				if menu_button == null:
					printerr("FLOW TEST FAILED: results screen has no MenuButton")
					get_tree().quit(1)
					return
				phase = 3
				phase_time = 0.0
				menu_button.pressed.emit()
			elif path == MAIN_MENU_SCENE:
				printerr("FLOW TEST FAILED: quit skipped the results screen")
				get_tree().quit(1)
		elif phase == 3:
			if path == MAIN_MENU_SCENE:
				print("FLOW TEST PASSED: menu -> battle -> 10 s prep -> wave 1 -> quit -> results -> menu")
				get_tree().quit(0)
				return

		if elapsed > TIMEOUT_SECONDS:
			printerr("FLOW TEST FAILED: phase %d, current scene is %s" % [phase, path])
			get_tree().quit(1)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_monitor = FlowMonitor.new()
	_monitor.name = "FlowMonitor"
	get_tree().root.add_child.call_deferred(_monitor)

	var menu: Control = load(MAIN_MENU_SCENE).instantiate()
	add_child(menu)
	await get_tree().process_frame

	var battle_button := menu.find_child("BattleButton", true, false) as Button
	if battle_button == null:
		printerr("FLOW TEST FAILED: BattleButton not found")
		get_tree().quit(1)
		return
	battle_button.pressed.emit()
