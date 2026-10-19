extends Node
## Dev-only benchmark runner (excluded from export).
##
## Instantiates the battle twice - once on high quality, once on low - runs
## `Battle.run_benchmark()` and prints both reports. Use it as a perf regression
## check on a desktop GPU; the real device numbers come from the in-game
## `F2 -> BENCHMARK` command.
##
## Run with:
##   godot --path <project> res://tools/BenchmarkRun.tscn

const BATTLE_SCENE := preload("res://scenes/battle/Battle.tscn")
const DURATION := 10.0
const SETTLE := 2.0

var _battle: Battle


func _ready() -> void:
	GameState.from_dict(SaveDefaults.create())
	GameState.set_flag("tutorial_done", true)
	Loc.set_locale("en")
	AudioManager.apply_settings()

	await _run_case("high")
	await _run_case("low")
	get_tree().quit(0)


func _run_case(quality: String) -> void:
	GameState.set_setting("quality", quality)
	_battle = BATTLE_SCENE.instantiate()
	_battle.auto_route_results = false
	_battle.offer_revive = false
	add_child(_battle)
	await _wait(SETTLE)
	_battle.run_benchmark(DURATION)
	await _wait(DURATION + 1.0)
	_battle.queue_free()
	_battle = null
	await _wait(0.5)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
