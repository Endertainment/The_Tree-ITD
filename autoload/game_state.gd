extends Node
## Canonical save data plus typed accessors for the meta layer.
##
## Owns currencies, permanent upgrades, cards, unlocks, stats, missions,
## settings and flags. Never holds run state (Coins, waves, enemies) - that
## belongs to the battle scene.

var _data: Dictionary = {}


func _ready() -> void:
	_data = SaveDefaults.create()


## Replaces all data at once, e.g. after Boot loads the save file.
func from_dict(data: Dictionary) -> void:
	_data = data.duplicate(true)
	if _data.is_empty():
		_data = SaveDefaults.create()
	_emit_currency_signals()


## Returns a deep copy safe to hand to SaveManager.
func to_dict() -> Dictionary:
	return _data.duplicate(true)


## Wipes the profile on disk and in memory.
func reset_progress() -> void:
	_data = SaveDefaults.create()
	SaveManager.reset_progress()
	_emit_currency_signals()


func get_gold() -> int:
	return int(_section("currencies").get("gold", 0))


func add_gold(amount: int) -> void:
	var currencies := _section("currencies")
	currencies["gold"] = maxi(0, int(currencies.get("gold", 0)) + amount)
	EventBus.gold_changed.emit(get_gold())
	_persist()


func spend_gold(amount: int) -> bool:
	if amount <= 0 or get_gold() < amount:
		return false
	add_gold(-amount)
	return true


func get_gems() -> int:
	return int(_section("currencies").get("gems", 0))


func add_gems(amount: int) -> void:
	var currencies := _section("currencies")
	currencies["gems"] = maxi(0, int(currencies.get("gems", 0)) + amount)
	EventBus.gems_changed.emit(get_gems())
	_persist()


func spend_gems(amount: int) -> bool:
	if amount <= 0 or get_gems() < amount:
		return false
	add_gems(-amount)
	return true


func get_upgrade_level(id: String) -> int:
	return int(_section("upgrades").get(id, 0))


func set_upgrade_level(id: String, level: int) -> void:
	var upgrades := _section("upgrades")
	var clamped := maxi(0, level)
	upgrades[id] = clamped
	EventBus.upgrade_purchased.emit(id, clamped)
	_persist()


func is_unlocked(id: String) -> bool:
	return bool(_section("unlocks").get(id, false))


func unlock(id: String, value := true) -> void:
	_section("unlocks")[id] = value
	_persist()


func get_stat(id: String) -> int:
	return int(_section("stats").get(id, 0))


func add_stat(id: String, amount: int) -> void:
	var stats := _section("stats")
	stats[id] = maxi(0, int(stats.get(id, 0)) + amount)
	_persist()


func get_setting(key: String, default_value: Variant = null) -> Variant:
	return _section("settings").get(key, default_value)


func set_setting(key: String, value: Variant) -> void:
	var settings := _section("settings")
	var previous: Variant = settings.get(key, null)
	settings[key] = value
	if key == "locale" and previous != value:
		EventBus.language_changed.emit(str(value))
	_persist()


func has_flag(id: String) -> bool:
	return bool(_section("flags").get(id, false))


func set_flag(id: String, value := true) -> void:
	_section("flags")[id] = value
	_persist()


func get_best_wave() -> int:
	return get_stat("best_wave")


## Elf Level = 1 + floor(total_waves_cleared / 15), capped at 40.
func get_elf_level() -> int:
	return clampi(1 + int(get_stat("total_waves_cleared") / 15), 1, 40)


func get_card_state() -> Dictionary:
	return _section("cards").duplicate(true)


## Equipped cards as resources. Unknown ids are skipped; the collection UI is
## stage 5, so the list is normally empty in stage 4.
func get_equipped_cards() -> Array[CardData]:
	var result: Array[CardData] = []
	var equipped: Array = _section("cards").get("equipped", [])
	for id: Variant in equipped:
		var card := ConfigDB.get_card(str(id))
		if card != null:
			result.append(card)
	return result


## Adds run-domain counters used by the stage-5 mission system.
func record_mission_metrics(metrics: Dictionary) -> void:
	var missions := _section("missions")
	var achievements: Dictionary = missions.get("achievements", {})
	var progress: Dictionary = achievements.get("progress", {})
	for key: String in metrics:
		progress[key] = maxi(0, int(progress.get(key, 0)) + int(metrics[key]))
	achievements["progress"] = progress
	missions["achievements"] = achievements
	_persist()


## Current value of one mission/achievement metric.
func get_mission_metric(id: String) -> int:
	var achievements: Dictionary = _section("missions").get("achievements", {})
	var progress: Dictionary = achievements.get("progress", {})
	return int(progress.get(id, 0))


## Applies one finished run exactly once: stats, best wave, milestone flag,
## Gold/Gems and the Elf Level transition. Returns a summary dictionary for the
## results screen. The caller computes the reward amounts.
func apply_run_result(summary: RunSummary, gold: int, gems: int) -> Dictionary:
	var stats := _section("stats")
	var currencies := _section("currencies")
	var flags := _section("flags")
	var best_before := int(stats.get("best_wave", 0))
	var elf_before := get_elf_level()

	stats["runs"] = int(stats.get("runs", 0)) + 1
	stats["best_wave"] = maxi(best_before, summary.waves_cleared)
	stats["total_kills"] = int(stats.get("total_kills", 0)) + summary.kills
	stats["bosses_killed"] = int(stats.get("bosses_killed", 0)) + summary.bosses_killed
	stats["total_gold_earned"] = int(stats.get("total_gold_earned", 0)) + gold
	stats["total_waves_cleared"] = int(stats.get("total_waves_cleared", 0)) + summary.waves_cleared
	if summary.waves_cleared >= 30:
		flags["milestone_30"] = true

	currencies["gold"] = maxi(0, int(currencies.get("gold", 0)) + gold)
	currencies["gems"] = maxi(0, int(currencies.get("gems", 0)) + gems)

	var elf_after := get_elf_level()
	_persist()
	EventBus.gold_changed.emit(get_gold())
	EventBus.gems_changed.emit(get_gems())

	return {
		"gold": gold,
		"gems": gems,
		"best_before": best_before,
		"best_wave": int(stats["best_wave"]),
		"new_best": summary.waves_cleared > best_before,
		"elf_before": elf_before,
		"elf_after": elf_after,
	}


func _section(section_name: String) -> Dictionary:
	var value: Variant = _data.get(section_name, null)
	if value is Dictionary:
		return value
	var created: Dictionary = {}
	_data[section_name] = created
	return created


func _persist() -> void:
	if SaveManager != null:
		SaveManager.save_game(to_dict())


func _emit_currency_signals() -> void:
	EventBus.gold_changed.emit(get_gold())
	EventBus.gems_changed.emit(get_gems())
