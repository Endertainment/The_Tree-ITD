extends Node
## Headless stage-3 tower test.
##
## Run with:
##   godot --headless --path <project> --fixed-fps 60 res://tests/TestTowers.tscn
##
## Exits 0 when every check passes. It covers pad layout, building, upgrade and
## sell maths, targeting modes, spirit root, ballista armor piercing, steering
## obstacles, sheet pause handling and node leaks.

const BATTLE_SCENE := preload("res://scenes/battle/Battle.tscn")

var _checks := 0
var _failures: Array[String] = []
var _battle: Battle
var _manager: TowerManager
var _tower_built_signals := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.tower_built.connect(_on_tower_built)
	await _run()
	_finish()


func _run() -> void:
	await get_tree().process_frame
	_battle = BATTLE_SCENE.instantiate()
	_battle.auto_route_results = false
	add_child(_battle)
	_battle.process_mode = Node.PROCESS_MODE_PAUSABLE
	await get_tree().physics_frame
	await get_tree().physics_frame
	_manager = _battle.tower_manager
	# Freeze the wave manager so spawns never interfere with the measurements.
	_battle.wave_manager.stop()
	_battle.enemy_pool.despawn_all()

	_section("pads")
	_check(_manager.get_pads().size() == 8, "eight pads exist")
	_check_pad_ring()
	_check(_manager.find_pad_at(Battle.CENTER) == null, "the Tree centre is not a pad")
	var pad0 := _manager.get_pads()[0]
	_check(
		_manager.find_pad_at(pad0.global_position) == pad0,
		"a tap on a pad resolves to that pad"
	)
	_check(pad0.get_tap_radius() * 2.0 >= 88.0, "tap target is at least 88 px wide")

	_section("build")
	_check(_battle.coins == RunStats.BASE_COINS, "run starts with 120 Coins")
	_check(_battle.get_tower_cost("archer_tower") == 60, "archer tower costs 60")
	_check(_battle.get_tower_cost("spirit_tower") == 90, "spirit tower costs 90")
	_check(_battle.get_tower_cost("ballista") == 140, "ballista costs 140")

	var pad_a := _manager.get_pads()[0]
	var pad_b := _manager.get_pads()[1]
	var pad_c := _manager.get_pads()[2]
	_check(_manager.build(pad_a, "archer_tower"), "archer tower builds on a free pad")
	_check(_battle.coins == 60, "building deducts exactly 60 Coins")
	_check(pad_a.has_tower(), "the pad now reports a tower")
	_check(_manager.get_towers().size() == 1, "one tower is registered")
	_check(_battle.obstacles.size() == 1, "the tower is a steering obstacle")
	_check(_tower_built_signals == 1, "EventBus.tower_built fires once")
	_check(
		not _manager.build(pad_a, "ballista"),
		"a pad that already has a tower cannot be built on"
	)
	_check(not _manager.build(pad_b, "spirit_tower"), "a tower costs more than the Coins left")
	_check(_battle.coins == 60 and _manager.get_towers().size() == 1, "a failed build changes nothing")

	_battle.add_coins(260)
	_check(_manager.build(pad_b, "spirit_tower"), "spirit tower builds after earning Coins")
	_check(_manager.build(pad_c, "ballista"), "ballista builds after earning Coins")
	_check(_manager.get_towers().size() == 3, "three towers stand")
	_check(_battle.obstacles.size() == 3, "three obstacles are published")
	_check(not _battle.spend_coins(100000), "spending more than the balance fails")
	_check(_battle.coins >= 0, "Coins never go negative")

	_section("upgrade and sell")
	_battle.add_coins(1000)
	var archer: Tower = pad_a.tower
	_check(archer.get_upgrade_cost() == 95, "L1 -> L2 costs 60 * 1.6 rounded to 5")
	_check(_manager.upgrade(archer), "the upgrade is paid")
	_check(archer.level == 2, "the tower is level 2")
	_check(archer.get_invested() == 155, "invested total tracks build plus upgrade")
	_check(archer.get_stats().damage == 22.0, "level 2 uses the level 2 damage")
	_check(archer.get_upgrade_cost() == 155, "L2 -> L3 costs 60 * 2.56 rounded to 5")
	_check(_manager.upgrade(archer), "the second upgrade is paid")
	_check(archer.level == 3 and archer.is_max_level(), "the tower reaches max level")
	_check(archer.get_next_stats() == null, "max level has no next stats")
	_check(archer.get_upgrade_cost() == 0, "max level has no upgrade price")
	_check(not _manager.upgrade(archer), "upgrading past max level is refused")
	_check(archer.get_stats().range == 500.0, "level 3 uses the level 3 range")

	var refund_expected := int(floor(310.0 * 0.6))
	var coins_before_sell := _battle.coins
	_check(archer.get_sell_refund() == refund_expected, "sell refund is 60% of everything invested")
	var refund := _manager.sell(archer)
	_check(refund == refund_expected, "selling returns the refund")
	_check(_battle.coins == coins_before_sell + refund_expected, "the refund reaches the Coins balance")
	_check(not pad_a.has_tower(), "selling frees the pad")
	_check(_battle.obstacles.size() == 2, "selling removes the steering obstacle")
	_check(_manager.get_towers().size() == 2, "two towers remain")

	_section("targeting")
	await _reset_run()
	_clear_archers()
	_battle.add_coins(2000)
	var centre_pad := _manager.get_pads()[0]
	_manager.build(centre_pad, "archer_tower")
	var tower: Tower = centre_pad.tower
	tower.set_target_mode(Tower.TargetMode.STRONGEST)
	_check(tower.target_mode == Tower.TargetMode.STRONGEST, "target mode changes")
	_check(tower.get_target_mode_key() == "TOWER_TARGET_STRONGEST", "target mode has a label key")
	tower.set_target_mode(Tower.TargetMode.FIRST)
	_check(tower.target_mode == Tower.TargetMode.FIRST, "target mode changes again")

	_section("archer tower damage")
	var grunt := ConfigDB.get_enemy("orc_grunt")
	var near := centre_pad.global_position + Vector2(120.0, 0.0)
	var target: Enemy = _battle.enemy_pool.spawn(grunt, near, {"spawn_delay": 0.0})
	_check(target != null, "an enemy can be spawned for the tower")
	if target != null:
		var hp_before := target.get_health().hp
		await _simulate(1.4)
		_check(target.get_health().hp < hp_before, "the archer tower damages an enemy in range")

	_section("spirit root")
	await _reset_run()
	_clear_archers()
	_battle.add_coins(2000)
	var spirit_pad := _manager.get_pads()[0]
	_manager.build(spirit_pad, "spirit_tower")
	var runner := ConfigDB.get_enemy("orc_runner")
	var runner_enemy: Enemy = _battle.enemy_pool.spawn(
		runner, spirit_pad.global_position + Vector2(0.0, 140.0), {"spawn_delay": 0.0}
	)
	var rooted := false
	for _step in 300:
		await get_tree().physics_frame
		if runner_enemy != null and runner_enemy.is_stunned():
			rooted = true
			break
	_check(rooted, "the spirit tower roots its target")
	if runner_enemy != null:
		_check(runner_enemy.get_stun_time() > 0.9, "level 1 root lasts about 1.2 s")
		_check(runner_enemy.is_targetable(), "the root does not kill the target")

	_section("ballista armor")
	await _reset_run()
	_clear_archers()
	_battle.add_coins(2000)
	var ballista_pad := _manager.get_pads()[0]
	_manager.build(ballista_pad, "ballista")
	var brute := ConfigDB.get_enemy("orc_brute")
	var brute_enemy: Enemy = _battle.enemy_pool.spawn(
		brute, ballista_pad.global_position + Vector2(0.0, 170.0), {"spawn_delay": 0.0, "hp_mult": 10.0}
	)
	_check(brute_enemy != null and brute_enemy.get_health().armor > 0.0, "the brute has armor")
	if brute_enemy != null:
		var started := brute_enemy.get_health().hp
		var fired := false
		for _step in 300:
			await get_tree().physics_frame
			if brute_enemy.get_health().hp < started - 0.5:
				fired = true
				break
		_check(fired, "the ballista hits the armored brute")
		if fired:
			var dealt := started - brute_enemy.get_health().hp
			_check(
				is_equal_approx(dealt, 55.0),
				"ballista damage ignores armor (dealt %.1f, expected 55)" % dealt
			)

	_section("obstacles and steering")
	await _reset_run()
	_clear_archers()
	_battle.core.setup(100000.0)
	_battle.add_coins(5000)
	var pad_list := _manager.get_pads()
	for index in pad_list.size():
		var tower_id: String = ["archer_tower", "spirit_tower", "ballista"][index % 3]
		_manager.build(pad_list[index], tower_id)
	_check(_manager.get_towers().size() == 8, "all eight pads can be built")
	_check(_battle.obstacles.size() == 8, "eight obstacles are published")
	var radius_ok := true
	for obstacle: Dictionary in _battle.obstacles:
		if float(obstacle["radius"]) < 48.0:
			radius_ok = false
	_check(radius_ok, "obstacle radius includes the 18 px margin")

	var crowd: Array[Enemy] = []
	var crowd_data := ConfigDB.get_enemy("orc_grunt")
	for index in 24:
		var angle := TAU * float(index) / 24.0
		var position := Battle.CENTER + Vector2(cos(angle), sin(angle)) * 520.0
		var spawned: Enemy = _battle.enemy_pool.spawn(
			crowd_data, position, {"spawn_delay": 0.0, "hp_mult": 60.0, "speed_mult": 1.2}
		)
		if spawned != null:
			crowd.append(spawned)
	_check(crowd.size() == 24, "24 enemies spawn around the ring")

	await _simulate(6.0)
	var start_distances: Array[float] = []
	for enemy: Enemy in crowd:
		start_distances.append(enemy.global_position.distance_to(Battle.CENTER))

	await _simulate(5.0)
	var progressed := 0
	var clipped := 0
	var stuck := 0
	for enemy: Enemy in crowd:
		if not enemy.is_alive:
			continue
		var distance := enemy.global_position.distance_to(Battle.CENTER)
		var contact := Battle.CORE_RADIUS + enemy.radius
		if distance < contact + 4.0:
			progressed += 1
			continue
		if _inside_any_tower(enemy.global_position, enemy.radius):
			clipped += 1
		var before := start_distances[crowd.find(enemy)]
		if distance < before - 20.0:
			progressed += 1
		else:
			stuck += 1
	_check(clipped == 0, "no living enemy overlaps a tower body")
	_check(stuck == 0, "no living enemy is wedged between towers (%d stuck)" % stuck)
	_check(progressed > 0, "enemies keep flowing toward the Tree through the ring")

	_section("sheets and pause")
	await _reset_run()
	_battle.add_coins(500)
	_check(not _battle.is_sheet_open(), "no sheet is open at run start")
	var empty_pad := _manager.get_pads()[3]
	var tap_event := InputEventScreenTouch.new()
	tap_event.index = 0
	tap_event.pressed = true
	tap_event.position = _battle.get_global_transform_with_canvas() * empty_pad.global_position
	get_viewport().push_input(tap_event, true)
	await get_tree().process_frame
	_check(_battle.is_sheet_open(), "tapping an empty pad opens the build sheet")
	_check(get_tree().paused, "an open sheet pauses the game")
	_check(not _battle.hud.is_pause_visible(), "the pause sheet is not shown")

	_battle.pause_run()
	_check(_battle.hud.is_pause_visible(), "pause still opens on top of an open sheet")
	_battle.resume_run()
	_check(get_tree().paused, "resuming keeps the game paused while a sheet is open")
	_battle.close_sheet()
	_check(not _battle.is_sheet_open(), "closing the sheet releases the pause")
	_check(not get_tree().paused, "the game resumes after the sheet closes")
	_check(not _battle.hud.is_pause_visible(), "the pause sheet closed first")

	# Sell confirmation state must not leak between sheet openings.
	var sheet_pad := _manager.get_pads()[4]
	_manager.build(sheet_pad, "archer_tower")
	_battle.open_pad(sheet_pad)
	_check(_battle.is_sheet_open(), "tapping a built pad opens the tower sheet")
	_battle.close_sheet()
	_check(not get_tree().paused, "the tower sheet releases the pause too")

	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for _cycle in 50:
		_battle.open_pad(empty_pad)
		_battle.close_sheet()
	await get_tree().process_frame
	var nodes_after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_check(
		nodes_after - nodes_before < 8,
		"50 sheet cycles do not leak nodes (%d -> %d)" % [nodes_before, nodes_after]
	)

	_section("cleanup")
	get_tree().paused = false
	Engine.time_scale = 1.0
	_battle.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(orphans < 20, "no orphan node growth (%d orphans)" % orphans)


func _reset_run() -> void:
	get_tree().paused = false
	_battle.start_run()
	_battle.wave_manager.stop()
	_battle.enemy_pool.despawn_all()
	await get_tree().physics_frame


## Removes the Tree's archers so a combat check can only be satisfied by a
## tower's own projectile.
func _clear_archers() -> void:
	for child in _battle.archers_root.get_children():
		if child is Archer:
			_battle.archers_root.remove_child(child)
			child.queue_free()


func _check_pad_ring() -> void:
	var ok_radius := true
	var ok_angles := true
	for index in _manager.get_pads().size():
		var pad: BuildPad = _manager.get_pads()[index]
		var offset := pad.global_position - Battle.CENTER
		if absf(offset.length() - TowerManager.RING_RADIUS) > 0.5:
			ok_radius = false
		var expected := deg_to_rad(22.5 + float(index) * 45.0)
		if absf(wrapf(offset.angle() - expected, -PI, PI)) > 0.01:
			ok_angles = false
		if absf(offset.x) < 40.0:
			ok_angles = false
	_check(ok_radius, "pads sit on a 300 px ring")
	_check(ok_angles, "pads use 22.5 deg + i * 45 deg and avoid the vertical axis")


func _inside_any_tower(world_position: Vector2, enemy_radius: float) -> bool:
	for obstacle: Dictionary in _battle.obstacles:
		var center: Vector2 = obstacle["position"]
		var radius := float(obstacle["radius"]) - 18.0 + enemy_radius * 0.2
		if world_position.distance_to(center) < radius:
			return true
	return false


func _simulate(seconds: float) -> void:
	var frames := maxi(1, int(round(seconds * 60.0)))
	for _index in frames:
		await get_tree().physics_frame


func _on_tower_built(_tower_id: String) -> void:
	_tower_built_signals += 1


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("ALL TOWER TESTS PASSED (%d checks)" % _checks)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	printerr("TOWER TESTS FAILED: %d of %d checks" % [_failures.size(), _checks])
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
