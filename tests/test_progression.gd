extends Node
## Headless stage-4 test: run modifiers, upgrade tracks, bosses, wave modifiers,
## results maths, persistence and the speed unlock matrix.
##
## Run with:
##   godot --headless --path <project> --fixed-fps 60 res://tests/TestProgression.tscn

const BATTLE_SCENE := preload("res://scenes/battle/Battle.tscn")
const RESULTS_SCENE := preload("res://scenes/battle/Results.tscn")

var _checks := 0
var _failures: Array[String] = []
var _battle: Battle
var _boss_deaths := 0


## Ad provider that always fails, to exercise the no-reward path.
class FailingAdsProvider extends AdsProvider:
	func is_ready() -> bool:
		return true

	func show_rewarded(_placement: String, callback: Callable) -> void:
		if callback.is_valid():
			callback.call(false)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.boss_died.connect(_on_boss_died)
	await _run()
	_finish()


func _run() -> void:
	await get_tree().process_frame
	GameState.from_dict(SaveDefaults.create())

	_section("upgrade tracks")
	var roots := ConfigDB.get_upgrade("roots")
	_check(roots != null, "roots track loads")
	_check(ConfigDB.all_upgrades().size() == 6, "six in-run tracks load")
	if roots != null:
		_check(roots.cost_for_level(0) == 70, "roots level 1 costs 70")
		_check(roots.cost_for_level(1) == 100, "roots level 2 costs 100 after rounding")
		_check(roots.cost_for_level(2) == 145, "roots level 3 costs 145 after rounding")
		_check(roots.max_level == 5, "roots caps at level 5")
	var archer_track := ConfigDB.get_upgrade("extra_archer")
	if archer_track != null:
		_check(archer_track.cost_for_level(1) == 900, "extra archer level 2 costs 900")

	_section("run stats")
	var stats := RunStats.new()
	stats.setup(RunModifiers.build({}))
	_check(is_equal_approx(stats.max_hp, 1000.0), "base Tree HP is 1000")
	_check(is_equal_approx(stats.archer_damage, 12.0), "base archer damage is 12")
	_check(is_equal_approx(stats.archer_interval, 0.8), "base archer interval is 0.8")
	_check(is_equal_approx(stats.archer_range, 520.0), "base archer range is 520")
	_check(stats.start_archers == 2, "base archers are 2")
	_check(stats.start_coins == 120, "base start Coins are 120")

	_check(stats.apply_upgrade("roots"), "roots can be bought")
	_check(is_equal_approx(stats.max_hp, 1150.0), "roots adds exactly 150 max HP")
	_check(stats.get_next_cost("roots") == 100, "the next roots level costs 100")
	var display := stats.get_display("roots")
	_check(int(display.get("now", 0)) == 1150 and int(display.get("next", 0)) == 1300, "row previews 1150 -> 1300")
	_check(stats.apply_upgrade("canopy_bows"), "canopy bows can be bought")
	_check(is_equal_approx(stats.archer_damage, 13.8), "canopy bows adds +15% damage")
	_check(stats.apply_upgrade("elven_haste"), "elven haste can be bought")
	_check(is_equal_approx(stats.archer_interval, 0.741), "haste lowers the interval to 0.741")
	_check(stats.apply_upgrade("far_sight"), "far sight can be bought")
	_check(is_equal_approx(stats.archer_range, 560.0), "far sight adds 40 range")
	_check(stats.apply_upgrade("extra_archer"), "extra archer can be bought")
	_check(stats.start_archers == 3, "extra archer raises the archer count to 3")
	_check(stats.apply_upgrade("regrowth"), "regrowth can be bought")
	_check(is_equal_approx(stats.regen, 2.0), "regrowth adds 2 HP/s")

	_section("meta and card modifiers")
	var meta := SaveDefaults.create()
	var upgrades: Dictionary = meta["upgrades"]
	upgrades["tree_hp"] = 2
	upgrades["start_coins"] = 1
	upgrades["archer_dmg"] = 5
	upgrades["tower_discount"] = 5
	upgrades["gold_gain"] = 2
	upgrades["coin_gain"] = 1
	var meta_mods := RunModifiers.build(meta)
	_check(is_equal_approx(meta_mods.tree_hp_mult, 1.1), "tree_hp level 2 is +10%")
	_check(meta_mods.start_coins_add == 20, "start_coins level 1 adds 20 Coins")
	_check(is_equal_approx(meta_mods.archer_dmg_mult, 1.2), "archer_dmg level 5 is +20%")
	_check(is_equal_approx(meta_mods.tower_cost_mult, 0.9), "tower_discount level 5 is -10%")
	_check(is_equal_approx(meta_mods.gold_mult, 1.08), "gold_gain level 2 is +8%")
	_check(is_equal_approx(meta_mods.coin_mult, 1.03), "coin_gain level 1 is +3%")

	var meta_stats := RunStats.new()
	meta_stats.setup(meta_mods)
	_check(is_equal_approx(meta_stats.max_hp, 1100.0), "meta HP applies before in-run upgrades")
	_check(meta_stats.start_coins == 140, "meta start Coins apply")
	_check(is_equal_approx(meta_stats.archer_damage, 14.4), "meta damage applies")

	var card := CardData.new()
	var hp_modifier := StatModifier.new()
	hp_modifier.stat = "tree_hp_mult"
	hp_modifier.op = "mult"
	hp_modifier.value = 0.2
	var damage_modifier := StatModifier.new()
	damage_modifier.stat = "archer_dmg_mult"
	damage_modifier.op = "mult"
	damage_modifier.value = -0.1
	card.modifiers = [hp_modifier, damage_modifier]
	var cards: Array[CardData] = [card]
	var card_mods := RunModifiers.build({}, cards)
	_check(is_equal_approx(card_mods.tree_hp_mult, 1.2), "a card adds its multiplier")
	_check(is_equal_approx(card_mods.archer_dmg_mult, 0.9), "a card can reduce a multiplier")

	_section("battle integration")
	_battle = BATTLE_SCENE.instantiate()
	_battle.auto_route_results = false
	add_child(_battle)
	_battle.process_mode = Node.PROCESS_MODE_PAUSABLE
	await get_tree().physics_frame
	await get_tree().physics_frame
	_battle.wave_manager.stop()
	_battle.enemy_pool.despawn_all()

	_check(_battle.run_stats != null, "the battle owns a RunStats")
	_check(_battle.run_stats.start_archers == 2, "the battle spawns the base archers")
	_check(_battle.coins == 120, "the battle starts with 120 Coins")
	_battle.core.take_damage(200.0)
	var hp_after_hit := _battle.core.get_hp()
	_check(_battle.purchase_run_upgrade("roots"), "roots can be bought in battle")
	_check(_battle.coins == 50, "roots deducts 70 Coins")
	_check(is_equal_approx(_battle.core.get_max_hp(), 1150.0), "the Tree max HP grows by 150")
	_check(is_equal_approx(_battle.core.get_hp(), hp_after_hit + 150.0), "roots heals by the same 150")
	_check(not _battle.purchase_run_upgrade("roots"), "an unaffordable track is refused")
	_check(_battle.coins == 50, "a refused purchase changes nothing")

	_battle.add_coins(1000)
	_check(_battle.purchase_run_upgrade("extra_archer"), "extra archer can be bought in battle")
	await get_tree().process_frame
	_check(_count_archers() == 3, "the third archer spawns immediately")
	_check(_battle.purchase_run_upgrade("canopy_bows"), "canopy bows can be bought in battle")
	await get_tree().process_frame
	var archer := _first_archer()
	_check(archer != null and is_equal_approx(archer.damage, 13.8), "archers refresh their damage")

	_section("wave rules")
	_check(WaveRules.is_boss_wave(10), "wave 10 is a boss wave")
	_check(WaveRules.is_boss_wave(20), "wave 20 is a boss wave")
	_check(not WaveRules.is_boss_wave(11), "wave 11 is not a boss wave")
	_check(WaveRules.modifier_for(7, 99) == WaveRules.Modifier.NONE, "no modifier before wave 8")
	_check(
		WaveRules.modifier_for(8, 99) == WaveRules.modifier_for(8, 99),
		"the wave 8 modifier is deterministic"
	)
	_check(
		WaveRules.modifier_for(10, 99) == WaveRules.Modifier.NONE,
		"boss waves have no modifier"
	)
	_check(is_equal_approx(WaveRules.boss_hp(1), 1500.0), "boss 1 has 1500 HP")
	_check(is_equal_approx(WaveRules.boss_hp(2), 2025.0), "boss 2 has 2025 HP")
	var armored := WaveRules.spawn_modifiers(WaveRules.Modifier.ARMORED)
	_check(is_equal_approx(float(armored.get("armor_mult", 0.0)), 1.5), "armored adds 50% armor")
	var swift := WaveRules.spawn_modifiers(WaveRules.Modifier.SWIFT)
	_check(is_equal_approx(float(swift.get("speed_mult", 0.0)), 1.25), "swift adds 25% speed")
	var swarm := WaveRules.spawn_modifiers(WaveRules.Modifier.SWARM)
	_check(is_equal_approx(float(swarm.get("hp_mult", 0.0)), 0.8), "swarm removes 20% HP")
	_check(is_equal_approx(WaveRules.count_multiplier(WaveRules.Modifier.SWARM), 1.4), "swarm adds 40% count")

	var armored_enemy := _battle.enemy_pool.spawn(
		ConfigDB.get_enemy("orc_brute"),
		Battle.CENTER + Vector2(0.0, 200.0),
		{"spawn_delay": 0.0, "armor_mult": 1.5, "modifier": "armored"}
	)
	_check(
		armored_enemy != null and armored_enemy.get_modifier_name() == "armored",
		"the modifier reaches the spawned enemy"
	)
	_check(
		armored_enemy != null and is_equal_approx(armored_enemy.get_health().armor, 4.5),
		"an armored brute has 1.5x armor (3 -> 4.5)"
	)
	if armored_enemy != null:
		_battle.enemy_pool.release(armored_enemy)

	_section("boss")
	_battle.enemy_pool.despawn_all()
	_battle.wave_manager.start(1234)
	_battle.wave_manager.debug_begin_wave(10)
	await _simulate(0.8)
	var boss := _battle.get_boss()
	_check(boss != null, "wave 10 spawns the boss")
	if boss != null:
		_check(boss.boss_index == 1, "the first boss is Warlord I")
		_check(is_equal_approx(boss.get_health().max_hp, 1500.0), "the boss starts at 1500 HP")
		boss.apply_slow(0.35, 2.0)
		_check(is_equal_approx(boss.get_slow_multiplier(), 1.0), "the boss ignores slow for 3 s")

		var present_before := _battle.enemy_pool.count_present()
		boss.take_damage(boss.get_health().max_hp * 0.31, true)
		_check(
			_battle.enemy_pool.count_present() >= present_before + 4,
			"70% HP summons four runners"
		)
		boss.take_damage(boss.get_health().max_hp * 0.30, true)
		_check(
			_battle.enemy_pool.count_present() >= present_before + 8,
			"40% HP summons four more runners"
		)
		var speed_before := boss.speed
		boss.take_damage(boss.get_health().max_hp * 0.11, true)
		_check(boss.is_enraged(), "below 30% the boss enrages")
		_check(boss.speed > speed_before, "enrage raises the boss speed")

		await _simulate(3.2)
		boss.apply_slow(0.35, 2.0)
		_check(boss.get_slow_multiplier() < 1.0, "slow applies after the immunity expires")

		_boss_deaths = 0
		var kills_before := int(_battle.summary.bosses_killed)
		boss.take_damage(999999.0, true)
		_check(_boss_deaths == 1, "boss death emits boss_died once")
		_check(int(_battle.summary.bosses_killed) == kills_before + 1, "the summary counts the boss")
		await get_tree().create_timer(0.5, true, false, true).timeout
		_check(is_equal_approx(Engine.time_scale, 1.0), "boss slow-mo restores the chosen speed")

	_section("quit rewards")
	_battle.summary = RunSummary.new()
	_battle.summary.reason = &"in_progress"
	_battle.wave_manager.debug_begin_wave(5)
	_battle.end_run(&"quit")
	_check(_battle.summary.reason == &"quit", "a quit builds a quit summary")
	_check(_battle.summary.waves_cleared == 4, "a quit at wave 5 counts 4 cleared waves")
	_check(Results.compute_gold(_battle.summary) == 52, "4 cleared waves pay 52 Gold")
	_check(Results.compute_gems(_battle.summary, false) == 0, "no boss means no boss Gems")

	_section("results maths")
	var run := RunSummary.new()
	run.waves_cleared = 7
	run.gold_mult = 1.0
	_check(Results.compute_gold(run) == 112, "7 cleared waves pay 112 Gold")
	run.gold_mult = 1.5
	_check(Results.compute_gold(run) == 168, "the gold multiplier applies to the payout")
	run.bosses_killed = 2
	_check(Results.compute_gems(run, false) == 12, "7 waves + 2 bosses pay 12 Gems")
	run.waves_cleared = 30
	_check(Results.compute_gems(run, true) == 32, "wave 30 adds the 10 Gem milestone")
	run.waves_cleared = 0
	run.gold_mult = 1.0
	_check(Results.compute_gold(run) == 0, "a quit before wave 1 pays no Gold")

	_section("persistence")
	GameState.from_dict(SaveDefaults.create())
	var summary := RunSummary.new()
	summary.waves_cleared = 7
	summary.kills = 33
	summary.bosses_killed = 1
	var applied := GameState.apply_run_result(summary, 112, 12)
	_check(GameState.get_stat("runs") == 1, "runs counter increments once")
	_check(GameState.get_stat("best_wave") == 7, "best wave becomes 7")
	_check(GameState.get_stat("total_kills") == 33, "kills are persisted")
	_check(GameState.get_stat("bosses_killed") == 1, "bosses are persisted")
	_check(GameState.get_stat("total_gold_earned") == 112, "Gold earned is persisted")
	_check(GameState.get_stat("total_waves_cleared") == 7, "cleared waves are persisted")
	_check(GameState.get_gold() == 112 and GameState.get_gems() == 12, "currencies are granted")
	_check(bool(applied.get("new_best", false)), "the first result is a new best")
	var disk := SaveManager.load_game()
	var disk_currencies: Dictionary = disk.get("currencies", {})
	_check(int(disk_currencies.get("gold", 0)) == 112, "Gold persists to disk immediately")

	GameState.from_dict(SaveDefaults.create())
	GameState.add_stat("total_waves_cleared", 29)
	var elf_run := RunSummary.new()
	elf_run.waves_cleared = 1
	var elf_applied := GameState.apply_run_result(elf_run, 0, 0)
	_check(int(elf_applied.get("elf_before", 0)) == 2, "Elf Level 2 before the run")
	_check(int(elf_applied.get("elf_after", 0)) == 3, "clearing wave 30 reaches Elf Level 3")
	_check(GameState.get_elf_level() == 3, "Elf Level is persisted")

	GameState.from_dict(SaveDefaults.create())
	var milestone_run := RunSummary.new()
	milestone_run.waves_cleared = 30
	GameState.apply_run_result(milestone_run, 0, 0)
	_check(GameState.has_flag("milestone_30"), "wave 30 sets the milestone flag")

	_section("results screen payout")
	GameState.from_dict(SaveDefaults.create())
	var screen_run := RunSummary.new()
	screen_run.waves_cleared = 7
	screen_run.gold_mult = 1.0
	screen_run.reason = &"quit"
	SceneRouter.set("_payload", screen_run)
	var screen := RESULTS_SCENE.instantiate() as Results
	add_child(screen)
	await get_tree().process_frame
	_check(GameState.get_gold() == 112, "the results screen grants Gold on entry")
	_check(GameState.get_gems() == 2, "the results screen grants Gems on entry")
	var double_button := screen.find_child("DoubleGoldButton", true, false) as Button
	_check(double_button != null, "the double-Gold button exists")
	Monetization.set_fake_ad_delay(0.01)
	if double_button != null:
		double_button.pressed.emit()
		await get_tree().create_timer(0.12, true, false, true).timeout
		await get_tree().process_frame
		_check(GameState.get_gold() == 224, "double Gold adds exactly the base reward")
		_check(not double_button.visible, "the double-Gold button hides after use")
		double_button.pressed.emit()
		await get_tree().process_frame
		_check(GameState.get_gold() == 224, "Gold cannot be doubled twice")
	screen.queue_free()
	await get_tree().process_frame

	GameState.from_dict(SaveDefaults.create())
	var fail_run := RunSummary.new()
	fail_run.waves_cleared = 7
	fail_run.gold_mult = 1.0
	fail_run.reason = &"quit"
	SceneRouter.set("_payload", fail_run)
	var fail_screen := RESULTS_SCENE.instantiate() as Results
	add_child(fail_screen)
	await get_tree().process_frame
	var fail_button := fail_screen.find_child("DoubleGoldButton", true, false) as Button
	var old_provider := Monetization.ads_provider
	Monetization.ads_provider = FailingAdsProvider.new()
	if fail_button != null:
		fail_button.pressed.emit()
		await get_tree().create_timer(0.05, true, false, true).timeout
		await get_tree().process_frame
		_check(GameState.get_gold() == 112, "a failed ad keeps the base Gold")
		_check(
			fail_button.visible and not fail_button.disabled,
			"the button can be retried after a failed ad"
		)
	Monetization.ads_provider = old_provider
	Monetization.set_fake_ad_delay(0.0)
	fail_screen.queue_free()
	await get_tree().process_frame

	_section("speed unlocks")
	GameState.from_dict(SaveDefaults.create())
	_check(SpeedService.is_speed_unlocked(1.0), "1x is always unlocked")
	_check(not SpeedService.is_speed_unlocked(1.5), "1.5x is locked on a fresh profile")
	_check(not SpeedService.is_speed_unlocked(2.0), "2x is locked on a fresh profile")
	GameState.add_stat("total_waves_cleared", 30)
	_check(SpeedService.is_speed_unlocked(1.5), "Elf Level 3 unlocks 1.5x")
	_check(not SpeedService.is_speed_unlocked(2.0), "2x still needs wave 25 or a trial")
	GameState.add_stat("best_wave", 25)
	_check(SpeedService.is_speed_unlocked(2.0), "best wave 25 unlocks 2x")
	_check(SpeedService.set_speed(2.0), "2x can be selected")
	_check(is_equal_approx(Engine.time_scale, 2.0), "2x sets the engine time scale")
	SpeedService.reset()

	GameState.from_dict(SaveDefaults.create())
	SpeedService.set_run_trials(true, false)
	_check(SpeedService.is_speed_unlocked(1.5), "the run trial unlocks 1.5x")
	_check(is_equal_approx(SpeedService.cycle_speed(), 1.5), "the speed button cycles to 1.5x")
	SpeedService.set_run_trials(true, true)
	_check(SpeedService.is_speed_unlocked(2.0), "the 2x trial needs 1.5x available")
	EventBus.run_ended.emit(null)
	_check(not SpeedService.is_run_trial_active(), "trials clear when the run ends")

	_section("cleanup")
	get_tree().paused = false
	Engine.time_scale = 1.0
	_battle.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(orphans < 20, "no orphan node growth (%d orphans)" % orphans)
	SaveManager.reset_progress()
	GameState.from_dict(SaveDefaults.create())


func _count_archers() -> int:
	var count := 0
	for child in _battle.archers_root.get_children():
		if child is Archer:
			count += 1
	return count


func _first_archer() -> Archer:
	for child in _battle.archers_root.get_children():
		if child is Archer:
			return child as Archer
	return null


func _on_boss_died(_boss_index: int) -> void:
	_boss_deaths += 1


func _simulate(seconds: float) -> void:
	var frames := maxi(1, int(round(seconds * 60.0)))
	for _index in frames:
		await get_tree().physics_frame


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("ALL PROGRESSION TESTS PASSED (%d checks)" % _checks)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	printerr("PROGRESSION TESTS FAILED: %d of %d checks" % [_failures.size(), _checks])
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
