class_name MissionTracker
extends Node
## Feeds daily missions and achievements from `EventBus`.
##
## Lives under `GameState` (no new autoload is allowed), so battle events are
## counted even while the menu scene is unloaded. Daily progress is accumulated
## in memory and written to the save at checkpoints only - never on every kill -
## which keeps the "no mid-run saves" rule from master section 7.6.
##
## Daily selection is deterministic: `seed = hash("YYYY-MM-DD")`, a Fisher-Yates
## shuffle of the eight-mission pool, first three. The same date always picks the
## same set, so progress survives a restart without storing the selection.

const DAILY_COUNT := 3
const DAILY_SCOPE := "daily"
const ACHIEVEMENT_SCOPE := "achievements"

var _daily_ids: Array[String] = []
var _daily_runtime: Dictionary = {}
var _daily_date := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_cleared.connect(_on_wave_cleared)
	EventBus.boss_died.connect(_on_boss_died)
	EventBus.tower_built.connect(_on_tower_built)
	EventBus.ad_watched.connect(_on_ad_watched)
	EventBus.run_ended.connect(_on_run_ended)


## Re-reads the profile after a load or reset. Safe to call at any time.
func reload() -> void:
	_daily_ids.clear()
	_daily_runtime.clear()
	_daily_date = ""
	refresh_daily(true)
	refresh_achievements()


## Rolls the daily set over when the local date changed, then reloads progress.
## Returns true when a new day started.
func refresh_daily(force := false) -> bool:
	var today := Time.get_date_string_from_system()
	if not force and today == _daily_date and not _daily_ids.is_empty():
		return false
	var rolled := today != GameState.get_daily_date()
	if rolled:
		GameState.reset_daily(today)
	_daily_date = today
	_daily_ids = select_daily(today)
	_daily_runtime.clear()
	var saved := GameState.get_daily_progress()
	for id: String in _daily_ids:
		_daily_runtime[id] = int(saved.get(id, 0))
	sync_daily_progress()
	if rolled:
		EventBus.missions_changed.emit()
	return rolled


## The three mission ids active today, in pool order.
func get_daily_ids() -> Array[String]:
	return _daily_ids.duplicate()


## Achievement ids ordered by ascending target, for the achievements tab.
func get_achievement_ids() -> Array[String]:
	var missions := ConfigDB.all_achievements()
	missions.sort_custom(func(a: MissionData, b: MissionData) -> bool: return a.target < b.target)
	var result: Array[String] = []
	for mission: MissionData in missions:
		result.append(mission.id)
	return result


## Current progress of `mission_id`, daily or achievement.
func get_progress(mission_id: String) -> int:
	if _daily_runtime.has(mission_id):
		return int(_daily_runtime[mission_id])
	var mission := ConfigDB.get_mission(mission_id)
	if mission == null:
		return 0
	return GameState.get_mission_progress(_scope_for(mission), mission_id)


## True when `mission_id` has been claimed for its current scope and date.
func is_claimed(mission_id: String) -> bool:
	var mission := ConfigDB.get_mission(mission_id)
	if mission == null:
		return false
	return GameState.is_mission_claimed(_scope_for(mission), mission_id)


## Claims `mission_id` when complete. Returns false when incomplete, unknown or
## already claimed.
func claim(mission_id: String) -> bool:
	var mission := ConfigDB.get_mission(mission_id)
	if mission == null or is_claimed(mission_id):
		return false
	if get_progress(mission_id) < mission.target:
		return false
	# Include the in-memory daily counters in the same atomic save as the claim.
	sync_daily_progress()
	return GameState.claim_mission(
		_scope_for(mission), mission_id, mission.reward_gold, mission.reward_gems
	)


## Recomputes every achievement from persistent stats and stores the result.
## Idempotent: unchanged values do not emit or write.
func refresh_achievements() -> void:
	for mission: MissionData in ConfigDB.all_achievements():
		var current := mini(mission.target, _achievement_value(mission.metric))
		GameState.set_mission_progress(
			ACHIEVEMENT_SCOPE, mission.id, current, mission.target
		)


## Three deterministic missions for `date`, drawn from the daily pool.
static func select_daily(date: String, count := DAILY_COUNT) -> Array[String]:
	var pool: Array[String] = []
	for mission: MissionData in ConfigDB.all_daily_missions():
		pool.append(mission.id)
	pool.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(date)
	for index in range(pool.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var swap := pool[index]
		pool[index] = pool[other]
		pool[other] = swap
	var result: Array[String] = []
	for index in mini(count, pool.size()):
		result.append(pool[index])
	return result


## Seconds until local midnight, for the "Resets in 7h 12m" label.
static func seconds_until_reset() -> int:
	var now := Time.get_datetime_dict_from_system()
	var elapsed := int(now["hour"]) * 3600 + int(now["minute"]) * 60 + int(now["second"])
	return maxi(0, 86400 - elapsed)


## Writes the in-memory daily counters to the save. Called at run end, on ad
## completion and when the menu shows, not per kill.
func sync_daily_progress() -> void:
	var progress: Dictionary = {}
	for id: String in _daily_ids:
		progress[id] = int(_daily_runtime.get(id, 0))
	GameState.set_daily_progress(progress)


func _scope_for(mission: MissionData) -> String:
	return DAILY_SCOPE if mission.daily else ACHIEVEMENT_SCOPE


func _bump(metric: String, amount: int, mode: String) -> void:
	for id: String in _daily_ids:
		var mission := ConfigDB.get_mission(id)
		if mission == null or mission.metric != metric:
			continue
		var current := int(_daily_runtime.get(id, 0))
		var next := current + amount if mode == "sum" else maxi(current, amount)
		if next == current:
			continue
		_daily_runtime[id] = next
		EventBus.mission_progress.emit(id, next, mission.target)


func _achievement_value(metric: String) -> int:
	match metric:
		"reach_wave":
			return GameState.get_stat("best_wave")
		"kill_orcs":
			return GameState.get_stat("total_kills")
		"kill_bosses":
			return GameState.get_stat("bosses_killed")
		"build_towers":
			return GameState.get_stat("towers_built")
		"earn_gold":
			return GameState.get_stat("total_gold_earned")
		"complete_runs":
			return GameState.get_stat("runs")
		"watch_ads":
			return GameState.get_stat("ads_watched")
		"clear_waves":
			return GameState.get_stat("total_waves_cleared")
		_:
			return 0


func _on_enemy_died(_enemy_id: String, _coin_value: int, _position: Vector2) -> void:
	_bump("kill_orcs", 1, "sum")


func _on_wave_started(wave: int) -> void:
	_bump("reach_wave", wave, "max")


func _on_wave_cleared(wave: int, _time_taken: float) -> void:
	_bump("clear_waves", 1, "sum")
	_bump("reach_wave", wave, "max")


func _on_boss_died(_boss_index: int) -> void:
	_bump("kill_bosses", 1, "sum")


func _on_tower_built(_tower_id: String) -> void:
	_bump("build_towers", 1, "sum")


func _on_ad_watched(_placement: String, success: bool) -> void:
	if not success:
		return
	GameState.add_stat("ads_watched", 1)
	_bump("watch_ads", 1, "sum")
	sync_daily_progress()
	SaveManager.save_now(GameState.to_dict())


func _on_run_ended(summary: Variant) -> void:
	var run := summary as RunSummary
	if run == null:
		return
	_bump("complete_runs", 1, "sum")
	_bump("earn_coins", run.coins_earned, "max")
	sync_daily_progress()
	SaveManager.save_now(GameState.to_dict())
	refresh_achievements()
