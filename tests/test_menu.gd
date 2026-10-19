extends Node
## Headless stage-5 test: data wiring, permanent upgrades, cards, missions,
## shop grants, settings persistence and the menu shell itself.
##
## Run with:
##   godot --headless --path <project> res://tests/TestMenu.tscn

const MENU_SCENE := preload("res://scenes/menu/MainMenu.tscn")
const TAB_ORDER: Array[String] = ["home", "upgrades", "cards", "missions", "shop", "settings"]

var _checks := 0
var _failures: Array[String] = []
var _menu: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	_finish()


func _run() -> void:
	await get_tree().process_frame
	SaveManager.reset_progress()
	GameState.from_dict(SaveDefaults.create())

	_section("data")
	_check(ConfigDB.all_cards().size() == 6, "six cards load")
	_check(ConfigDB.all_daily_missions().size() == 8, "eight daily missions load")
	_check(ConfigDB.all_achievements().size() == 8, "eight achievements load")
	_check(ConfigDB.all_products().size() == 8, "eight shop products load")
	_check(ConfigDB.all_meta_upgrades().size() == 8, "eight permanent upgrades load")
	var tree_hp := ConfigDB.get_meta_upgrade("tree_hp")
	_check(tree_hp != null, "tree_hp track loads")
	if tree_hp != null:
		_check(tree_hp.cost_for_level(0) == 150, "tree_hp level 1 costs 150")
		_check(tree_hp.cost_for_level(1) == 235, "tree_hp level 2 costs 235 after rounding")
		_check(tree_hp.max_level == 10, "tree_hp caps at 10")
	_check(ConfigDB.get_card("heartwood") != null, "heartwood card loads")
	_check(ConfigDB.get_mission("daily_kill_orcs") != null, "daily mission loads")
	_check(ConfigDB.get_product("gems_1200") != null, "shop product loads")

	_section("permanent upgrades feed the run")
	GameState.add_gold(5000)
	for _level in 3:
		var level := GameState.get_upgrade_level("tree_hp")
		var cost := tree_hp.cost_for_level(level)
		_check(GameState.spend_gold(cost), "tree_hp level %d is affordable" % (level + 1))
		GameState.set_upgrade_level("tree_hp", level + 1)
	_check(GameState.get_upgrade_level("tree_hp") == 3, "tree_hp reaches level 3")
	var meta_modifiers := RunModifiers.build(GameState.to_dict())
	_check(is_equal_approx(meta_modifiers.tree_hp_mult, 1.15), "tree_hp level 3 is +15% HP")
	var meta_stats := RunStats.new()
	meta_stats.setup(meta_modifiers)
	_check(is_equal_approx(meta_stats.max_hp, 1150.0), "the next run starts at 1150 Tree HP")

	_section("cards")
	GameState.from_dict(SaveDefaults.create())
	GameState.add_gems(1000)
	_check(GameState.own_card("heartwood"), "heartwood unlocks")
	_check(not GameState.own_card("heartwood"), "a card cannot be unlocked twice")
	_check(GameState.equip_card("heartwood"), "heartwood equips")
	var card_modifiers := RunModifiers.build(
		GameState.to_dict(), GameState.get_equipped_cards()
	)
	_check(is_equal_approx(card_modifiers.tree_hp_mult, 1.2), "heartwood adds +20% Tree HP")
	_check(is_equal_approx(card_modifiers.archer_dmg_mult, 0.9), "heartwood removes 10% archer damage")
	GameState.own_card("swift_leaves")
	GameState.own_card("ancient_memory")
	_check(GameState.equip_card("swift_leaves"), "a second card equips")
	_check(not GameState.equip_card("ancient_memory"), "a third card is refused")
	_check(GameState.replace_equipped_card("swift_leaves", "ancient_memory"), "a third card can replace one")
	var equipped := GameState.get_equipped_ids()
	_check(equipped.size() == 2, "two cards stay equipped")
	_check(equipped.has("ancient_memory"), "the replacement is equipped")
	var memory_modifiers := RunModifiers.build({}, GameState.get_equipped_cards())
	_check(memory_modifiers.start_archers_add == 1, "Ancient Memory adds an archer")
	_check(memory_modifiers.start_coins_add == -20, "Ancient Memory removes 20 starting Coins")
	SaveManager.save_now(GameState.to_dict())
	GameState.from_dict(SaveManager.load_game())
	_check(GameState.get_equipped_ids().has("ancient_memory"), "equipped cards persist")

	var dirty := GameState.to_dict()
	dirty["cards"] = {
		"owned": ["nope", "heartwood", "swift_leaves"],
		"equipped": ["nope", "heartwood", "swift_leaves", "ancient_memory"],
	}
	GameState.from_dict(dirty)
	_check(not GameState.is_card_owned("nope"), "unknown card ids are dropped on load")
	_check(GameState.get_equipped_ids().size() == 2, "equipped cards are capped at two on load")

	_section("daily missions")
	GameState.from_dict(SaveDefaults.create())
	var today := Time.get_date_string_from_system()
	var daily_ids := GameState.missions.get_daily_ids()
	_check(daily_ids.size() == 3, "three daily missions are active")
	_check(daily_ids == MissionTracker.select_daily(today), "selection is deterministic for the date")
	_check(daily_ids[0] != daily_ids[1] and daily_ids[1] != daily_ids[2], "daily missions are unique")
	for id: String in daily_ids:
		_satisfy_mission(id)
	for id: String in daily_ids:
		var mission := ConfigDB.get_mission(id)
		_check(GameState.missions.get_progress(id) >= mission.target, "%s reaches its target" % id)
		var gold_before := GameState.get_gold()
		_check(GameState.missions.claim(id), "%s can be claimed" % id)
		_check(GameState.get_gold() >= gold_before + mission.reward_gold, "%s pays Gold" % id)
		_check(not GameState.missions.claim(id), "%s cannot be claimed twice" % id)
	SaveManager.save_now(GameState.to_dict())
	GameState.from_dict(SaveManager.load_game())
	_check(GameState.missions.is_claimed(daily_ids[0]), "a daily claim survives a reload")
	_check(
		GameState.missions.get_progress(daily_ids[0]) >= ConfigDB.get_mission(daily_ids[0]).target,
		"daily progress survives a reload"
	)

	var stale := GameState.to_dict()
	stale["missions"]["daily"] = {
		"date": "2020-01-01",
		"progress": {"daily_kill_orcs": 99},
		"claimed": ["daily_kill_orcs"],
	}
	GameState.from_dict(stale)
	_check(GameState.get_daily_date() == today, "a stale daily date rolls over on load")
	var fresh_progress := GameState.get_daily_progress()
	var all_zero := true
	for value: Variant in fresh_progress.values():
		if int(value) != 0:
			all_zero = false
	_check(all_zero, "daily progress resets with the date")
	_check(not GameState.missions.is_claimed("daily_kill_orcs"), "daily claims reset with the date")

	_section("achievements")
	GameState.from_dict(SaveDefaults.create())
	GameState.add_stat("total_kills", 1000)
	GameState.add_stat("best_wave", 20)
	GameState.add_stat("total_gold_earned", 10000)
	GameState.missions.refresh_achievements()
	_check(GameState.missions.get_progress("ach_slay_1000") == 1000, "kill achievement derives from stats")
	_check(GameState.missions.get_progress("ach_reach_wave_20") == 20, "wave achievement derives from best wave")
	_check(GameState.missions.get_progress("ach_earn_10000_gold") == 10000, "gold achievement derives from stats")
	_check(GameState.missions.claim("ach_slay_1000"), "an achievement can be claimed")
	_check(not GameState.missions.claim("ach_slay_1000"), "an achievement cannot be claimed twice")
	SaveManager.save_now(GameState.to_dict())
	GameState.from_dict(SaveManager.load_game())
	_check(GameState.missions.is_claimed("ach_slay_1000"), "claimed achievements survive a reload")
	_check(GameState.missions.get_progress("ach_slay_1000") == 1000, "achievement progress survives a reload")

	_section("shop")
	GameState.from_dict(SaveDefaults.create())
	for product: ShopProduct in ConfigDB.all_products():
		_check(MetaShop.grant(product.id), "%s grants" % product.id)
		if product.is_one_time():
			_check(not MetaShop.grant(product.id), "%s cannot be granted twice" % product.id)
	_check(GameState.get_gems() == 4650, "every gem product and the bundle paid out")
	_check(GameState.get_gold() == 33000, "every gold product and the bundle paid out")
	_check(GameState.is_product_owned("starter_bundle"), "the starter bundle is marked owned")
	_check(MetaShop.grant("gems_100"), "a consumable can be granted again")
	_check(GameState.get_gems() == 4750, "the consumable paid out again")
	_check(MetaShop.grant("remove_ads") == false, "remove-ads cannot be granted twice")
	_check(GameState.is_unlocked("remove_ads"), "remove-ads sets its unlock flag")
	SaveManager.save_now(GameState.to_dict())
	GameState.from_dict(SaveManager.load_game())
	_check(GameState.is_product_owned("starter_bundle"), "owned products persist")
	_check(GameState.is_unlocked("remove_ads"), "the remove-ads flag persists")

	_section("restore purchases")
	GameState.from_dict(SaveDefaults.create())
	GameState.own_product("remove_ads")
	_check(not GameState.is_unlocked("remove_ads"), "a restored product can miss its flag")
	_check(MetaShop.restore_owned() == 1, "restore re-applies the remove-ads unlock")
	_check(GameState.is_unlocked("remove_ads"), "restore sets the unlock flag")
	_check(MetaShop.restore_owned() == 0, "restore is idempotent")

	_section("settings")
	GameState.set_setting("quality", "low")
	_check(GameState.is_low_quality(), "quality low is stored")
	SaveManager.save_now(GameState.to_dict())
	GameState.from_dict(SaveManager.load_game())
	_check(GameState.is_low_quality(), "quality low survives a reload")
	GameState.set_setting("quality", "high")
	Loc.set_locale("uk")
	_check(Loc.get_locale() == "uk", "the locale switches to Ukrainian")
	_check(str(GameState.get_setting("locale", "")) == "uk", "the locale is persisted")
	AudioManager.set_bus_volume(AudioManager.MUSIC_BUS, 0.25)
	_check(
		absf(AudioManager.get_bus_volume(AudioManager.MUSIC_BUS) - 0.25) < 0.02,
		"music volume applies to the bus immediately"
	)
	AudioManager.set_bus_volume(AudioManager.MUSIC_BUS, 0.8)
	Loc.set_locale("en")
	_check(Loc.t_key("TAB_MISSIONS") == "MISSIONS", "EN strings resolve")
	Loc.set_locale("uk")
	_check(Loc.t_key("TAB_MISSIONS") == "МІСІЇ", "UK strings resolve")
	Loc.set_locale("en")

	_section("menu shell")
	GameState.from_dict(SaveDefaults.create())
	_menu = MENU_SCENE.instantiate()
	add_child(_menu)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_menu.get_active_tab() == "home", "the menu opens on Home")
	var host := _menu.get_node("%ScreenHost") as Control
	for tab: String in TAB_ORDER:
		_menu.select_tab(tab)
		await get_tree().process_frame
		_check(_menu.get_active_tab() == tab, "the %s tab opens" % tab)
	_check(host.get_child_count() == 6, "six screens are cached after a full tour")
	var all_screens := true
	for child in host.get_children():
		if not child is MenuScreen:
			all_screens = false
	_check(all_screens, "every cached screen is a MenuScreen")
	_check(_menu.get_node("SafeArea/Column/TabBar/TabMissions").button_pressed == false, "the active tab is the only pressed one")
	_menu.select_tab("missions")
	await get_tree().process_frame
	_check(_menu.get_node("SafeArea/Column/TabBar/TabMissions").button_pressed, "the missions tab is highlighted")
	_menu.select_tab("cards")
	await get_tree().process_frame
	_check(_menu.get_node("SafeArea/Column/TabBar/TabMissions").button_pressed == false, "leaving a tab clears its highlight")
	var cards_tab := _menu.get_node("SafeArea/Column/TabBar/TabCards/Stack/Label") as Label
	Loc.set_locale("uk")
	await get_tree().process_frame
	_check(cards_tab.text == "КАРТИ", "tab labels retranslate live")
	Loc.set_locale("en")
	await get_tree().process_frame
	_check(cards_tab.text == "CARDS", "tab labels return to English")

	var home_screen := host.get_child(0)
	for _tap in 5:
		home_screen.call("register_version_tap")
	await get_tree().process_frame
	_check(_menu.is_debug_panel_open(), "five version taps open the debug panel")
	_menu.close_monetization_debug()
	_check(not _menu.is_debug_panel_open(), "the debug panel closes")

	var modal := _menu.get_node("%Modal") as ModalSheet
	_check(not modal.visible, "the modal starts hidden")
	_menu.open_modal("Test", "Body", "COMMON_CLOSE", "COMMON_CLOSE", Callable())
	_check(modal.visible, "the modal opens")
	modal.close()
	_check(not modal.visible, "the modal closes")

	_menu.select_tab("settings")
	await get_tree().process_frame
	_menu.go_back()
	_check(_menu.get_active_tab() == "home", "back returns to Home from another tab")
	_menu.open_modal("Test", "Body", "COMMON_CLOSE", "COMMON_CLOSE", Callable())
	_menu.go_back()
	_check(_menu.get_active_tab() == "home" and not modal.visible, "back closes a modal before leaving Home")
	_menu.fly_reward(Vector2(200, 200), "+5")
	await get_tree().process_frame

	_menu.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(orphans < 30, "no orphan node growth (%d orphans)" % orphans)

	_section("cleanup")
	SaveManager.reset_progress()
	GameState.from_dict(SaveDefaults.create())
	Loc.set_locale("en")


## Emits the events that satisfy one daily mission's metric.
func _satisfy_mission(mission_id: String) -> void:
	var mission := ConfigDB.get_mission(mission_id)
	if mission == null:
		return
	match mission.metric:
		"kill_orcs":
			for _index in mission.target:
				EventBus.enemy_died.emit("orc_grunt", 6, Vector2.ZERO)
		"clear_waves":
			for index in mission.target:
				EventBus.wave_cleared.emit(index + 1, 1.0)
		"reach_wave":
			EventBus.wave_started.emit(mission.target)
		"build_towers":
			for _index in mission.target:
				EventBus.tower_built.emit("archer_tower")
		"earn_coins":
			var rich_run := RunSummary.new()
			rich_run.coins_earned = mission.target
			EventBus.run_ended.emit(rich_run)
		"kill_bosses":
			for index in mission.target:
				EventBus.boss_died.emit(index + 1)
		"complete_runs":
			for _index in mission.target:
				EventBus.run_ended.emit(RunSummary.new())
		"watch_ads":
			for _index in mission.target:
				EventBus.ad_watched.emit("test", true)
		_:
			pass


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("ALL MENU TESTS PASSED (%d checks)" % _checks)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	printerr("MENU TESTS FAILED: %d of %d checks" % [_failures.size(), _checks])
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
