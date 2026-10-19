extends Node
## Headless scene-flow test: MainMenu.BATTLE unlocks Battle, and the quit
## confirmation returns to MainMenu.
##
## Run with:
##   godot --headless --path <project> res://tests/TestFlow.tscn
##
## A monitor node is parented to the tree root so it survives the scene swap.

const MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"
const BATTLE_SCENE := "res://scenes/battle/Battle.tscn"
const TIMEOUT_SECONDS := 8.0
const QUIT_DELAY_SECONDS := 0.6

var _monitor: FlowMonitor


class FlowMonitor extends Node:
	var elapsed := 0.0
	var phase := 0
	var phase_time := 0.0
	var battle: Battle

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		elapsed += delta
		phase_time += delta
		var current := get_tree().current_scene

		if phase == 0:
			if current != null and current.scene_file_path == BATTLE_SCENE:
				phase = 1
				phase_time = 0.0
				battle = current as Battle
		elif phase == 1:
			# Wait for SceneRouter's fade-in to finish before leaving.
			if battle != null and phase_time >= QUIT_DELAY_SECONDS:
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
			elif current != null and current.scene_file_path == MAIN_MENU_SCENE:
				print("FLOW TEST PASSED: MainMenu -> Battle -> quit confirmation -> MainMenu")
				get_tree().quit(0)
				return

		if elapsed > TIMEOUT_SECONDS:
			var path := current.scene_file_path if current != null else "<none>"
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
