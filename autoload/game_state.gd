extends Node
## Canonical save data plus typed accessors for the meta layer.
##
## Owns currencies, permanent upgrades, cards, unlocks, stats, missions, shop
## ownership, settings and flags. Never holds run state (Coins, waves, enemies) -
## that belongs to the battle scene.
##
## Data is validated every time it enters the process (`from_dict`): unknown card
## and product ids are dropped, the equipped pair is capped at two, and upgrade
## levels are clamped to their data-defined maximum.

const EQUIPPED_LIMIT := 2

var _data: Dictionary = {}
var missions: MissionTracker


func _ready() -> void:
	_data = SaveDefaults.create()
	missions = MissionTracker.new()
	missions.name = "MissionTracker"
	add_child(missions)


## Replaces all data at once, e.g. after Boot loads the save file.
func from_dict(data: Dictionary) -> void:
	_data = data.duplicate(true)
	if _data.is_empty():
		_data = SaveDefaults.create()
	_sanitize()
	_emit_currency_signals()
	if missions != null:
		missions.reload()


## Returns a deep copy safe to hand to SaveManager.
func to_dict() -> Dictionary:
	return _data.duplicate(true)


## Wipes the profile on disk and in memory.
func reset_progress() -> void:
	_data = SaveDefaults.create()
	SaveManager.reset_progress()
	_sanitize()
	_emit_currency_signals()
	if missions != null:
		missions.reload()


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
	var track := ConfigDB.get_meta_upgrade(id) if ConfigDB != null else null
	if track != null:
		clamped = mini(clamped, track.max_level)
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


## Waves still needed for the next Elf Level, or 0 at the cap.
func get_elf_level_progress() -> Dictionary:
	var cleared := get_stat("total_waves_cleared")
	var level := get_elf_level()
	if level >= 40:
		return {"current": 0, "needed": 0, "percent": 1.0}
	var into_level := cleared % 15
	return {
		"current": into_level,
		"needed": 15,
		"percent": float(into_level) / 15.0,
	}


## Equipped cards as resources. Unknown ids are skipped.
func get_equipped_cards() -> Array[CardData]:
	var result: Array[CardData] = []
	for id: String in get_equipped_ids():
		var card := ConfigDB.get_card(id)
		if card != null:
			result.append(card)
	return result


func is_card_owned(id: String) -> bool:
	return _card_list("owned").has(id)


## Adds `id` to the collection. False when unknown or already owned.
func own_card(id: String) -> bool:
	if ConfigDB.get_card(id) == null or is_card_owned(id):
		return false
	var owned := _card_list("owned")
	owned.append(id)
	_section("cards")["owned"] = owned
	EventBus.cards_changed.emit()
	_persist()
	return true


## Equipped card ids, in equip order.
func get_equipped_ids() -> Array[String]:
	var result: Array[String] = []
	for value: Variant in _card_list("equipped"):
		result.append(str(value))
	return result


## Equips `id` when owned, not already equipped, and a slot is free.
func equip_card(id: String) -> bool:
	if not is_card_owned(id):
		return false
	var equipped := get_equipped_ids()
	if equipped.has(id) or equipped.size() >= EQUIPPED_LIMIT:
		return false
	equipped.append(id)
	_store_equipped(equipped)
	return true


## Removes `id` from the equipped pair.
func unequip_card(id: String) -> bool:
	var equipped := get_equipped_ids()
	if not equipped.has(id):
		return false
	equipped.erase(id)
	_store_equipped(equipped)
	return true


## Swaps `old_id` for `new_id`, preserving slot order.
func replace_equipped_card(old_id: String, new_id: String) -> bool:
	if not is_card_owned(new_id) or old_id == new_id:
		return false
	var equipped := get_equipped_ids()
	var index := equipped.find(old_id)
	if index < 0 or equipped.has(new_id):
		return false
	equipped[index] = new_id
	_store_equipped(equipped)
	return true


## --- Missions -------------------------------------------------------------

## Local date the stored daily set belongs to (`YYYY-MM-DD`).
func get_daily_date() -> String:
	return str(_mission_section("daily").get("date", ""))


## Starts a new daily cycle: clears progress and claims, stores `date`.
func reset_daily(date: String) -> void:
	var daily := _mission_section("daily")
	daily["date"] = date
	daily["progress"] = {}
	daily["claimed"] = []
	_persist()
	EventBus.missions_changed.emit()


## Daily progress dictionary (mission id -> int), copied.
func get_daily_progress() -> Dictionary:
	return (_mission_section("daily").get("progress", {}) as Dictionary).duplicate(true)


## Replaces the daily progress dictionary.
func set_daily_progress(progress: Dictionary) -> void:
	_mission_section("daily")["progress"] = progress.duplicate(true)
	_persist()


func get_mission_progress(scope: String, id: String) -> int:
	var progress: Dictionary = _mission_section(scope).get("progress", {})
	return int(progress.get(id, 0))


## Stores one mission's progress and announces it.
func set_mission_progress(scope: String, id: String, value: int, target := 0) -> void:
	var section := _mission_section(scope)
	var progress: Dictionary = section.get("progress", {})
	var clamped := maxi(0, value)
	if int(progress.get(id, 0)) == clamped:
		return
	progress[id] = clamped
	section["progress"] = progress
	EventBus.mission_progress.emit(id, clamped, target)
	_persist()


func is_mission_claimed(scope: String, id: String) -> bool:
	return _claimed_list(scope).has(id)


## Marks `id` claimed, grants its rewards and writes the save atomically.
## Returns false when it was already claimed (double-tap safe).
func claim_mission(scope: String, id: String, gold: int, gems: int) -> bool:
	if is_mission_claimed(scope, id):
		return false
	var claimed := _claimed_list(scope)
	claimed.append(id)
	_mission_section(scope)["claimed"] = claimed
	var currencies := _section("currencies")
	if gold > 0:
		currencies["gold"] = maxi(0, int(currencies.get("gold", 0)) + gold)
	if gems > 0:
		currencies["gems"] = maxi(0, int(currencies.get("gems", 0)) + gems)
	SaveManager.save_now(to_dict())
	EventBus.gold_changed.emit(get_gold())
	EventBus.gems_changed.emit(get_gems())
	EventBus.missions_changed.emit()
	return true


## --- Shop -----------------------------------------------------------------

func get_owned_products() -> Array[String]:
	var result: Array[String] = []
	for value: Variant in _section("shop").get("owned_products", []):
		result.append(str(value))
	return result


func is_product_owned(id: String) -> bool:
	return get_owned_products().has(id)


## Marks a non-consumable product as owned. False when already owned.
func own_product(id: String) -> bool:
	if is_product_owned(id):
		return false
	var owned := get_owned_products()
	owned.append(id)
	_section("shop")["owned_products"] = owned
	EventBus.products_changed.emit()
	_persist()
	return true


## --- Settings -------------------------------------------------------------

## Low quality disables decorative particles and camera shake.
func is_low_quality() -> bool:
	return str(get_setting("quality", "high")) == "low"


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
	SaveManager.save_now(to_dict())
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


## --- Internals ------------------------------------------------------------

func _section(section_name: String) -> Dictionary:
	var value: Variant = _data.get(section_name, null)
	if value is Dictionary:
		return value
	var created: Dictionary = {}
	_data[section_name] = created
	return created


func _mission_section(scope: String) -> Dictionary:
	var missions_data := _section("missions")
	var value: Variant = missions_data.get(scope, null)
	if value is Dictionary:
		return value
	var created: Dictionary = {"progress": {}, "claimed": []}
	missions_data[scope] = created
	return created


func _card_list(key: String) -> Array:
	var value: Variant = _section("cards").get(key, [])
	if value is Array:
		return value
	return []


func _claimed_list(scope: String) -> Array:
	var value: Variant = _mission_section(scope).get("claimed", [])
	if value is Array:
		return value
	return []


func _store_equipped(ids: Array[String]) -> void:
	_section("cards")["equipped"] = ids
	EventBus.cards_changed.emit()
	_persist()


func _persist() -> void:
	if SaveManager != null:
		SaveManager.save_game(to_dict())


func _emit_currency_signals() -> void:
	EventBus.gold_changed.emit(get_gold())
	EventBus.gems_changed.emit(get_gems())


## Drops ids that no longer exist in data and repairs the shape of every
## stage-5 section. Unknown top-level save keys are preserved.
func _sanitize() -> void:
	if ConfigDB == null:
		return
	_sanitize_cards()
	_sanitize_upgrades()
	_sanitize_missions()
	_sanitize_shop()
	_sanitize_settings()


func _sanitize_cards() -> void:
	var cards := _section("cards")
	var owned: Array = []
	for value: Variant in cards.get("owned", []):
		var id := str(value)
		if ConfigDB.get_card(id) != null and not owned.has(id):
			owned.append(id)
	cards["owned"] = owned
	var equipped: Array = []
	for value: Variant in cards.get("equipped", []):
		var id := str(value)
		if owned.has(id) and not equipped.has(id) and equipped.size() < EQUIPPED_LIMIT:
			equipped.append(id)
	cards["equipped"] = equipped


func _sanitize_upgrades() -> void:
	var upgrades := _section("upgrades")
	for track: MetaUpgradeData in ConfigDB.all_meta_upgrades():
		upgrades[track.id] = clampi(int(upgrades.get(track.id, 0)), 0, track.max_level)


func _sanitize_missions() -> void:
	for scope: String in ["daily", "achievements"]:
		var section := _mission_section(scope)
		var raw_progress: Variant = section.get("progress", {})
		var progress: Dictionary = raw_progress if raw_progress is Dictionary else {}
		var clean_progress: Dictionary = {}
		for key: Variant in progress:
			var mission := ConfigDB.get_mission(str(key))
			if mission != null and (mission.daily == (scope == "daily")):
				clean_progress[str(key)] = maxi(0, int(progress[key]))
		section["progress"] = clean_progress
		var claimed: Array = []
		for value: Variant in section.get("claimed", []):
			var mission := ConfigDB.get_mission(str(value))
			if mission != null and (mission.daily == (scope == "daily")) and not claimed.has(str(value)):
				claimed.append(str(value))
		section["claimed"] = claimed


func _sanitize_shop() -> void:
	var owned: Array = []
	for value: Variant in _section("shop").get("owned_products", []):
		var id := str(value)
		if ConfigDB.get_product(id) != null and not owned.has(id):
			owned.append(id)
	_section("shop")["owned_products"] = owned


func _sanitize_settings() -> void:
	var settings := _section("settings")
	settings["music"] = clampf(float(settings.get("music", 0.8)), 0.0, 1.0)
	settings["sfx"] = clampf(float(settings.get("sfx", 1.0)), 0.0, 1.0)
	settings["haptics"] = bool(settings.get("haptics", true))
	settings["show_damage_numbers"] = bool(settings.get("show_damage_numbers", true))
	var quality := str(settings.get("quality", "high"))
	settings["quality"] = quality if quality in ["high", "low"] else "high"
