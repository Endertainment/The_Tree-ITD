extends Node
## Headless stage-6 test: ads, free Gems, interstitial cadence, revive, IAP,
## consent, provider fallback and the debug panel.
##
## Run with:
##   godot --headless --path <project> res://tests/TestMonetization.tscn

const BATTLE_SCENE := preload("res://scenes/battle/Battle.tscn")
const DEBUG_PANEL_SCENE := preload("res://ui/debug/MonetizationDebug.tscn")
const PRE_BATTLE_SCENE := preload("res://scenes/menu/PreBattle.tscn")

var _checks := 0
var _failures: Array[String] = []
var _battles: Array[Battle] = []
var _debug_panel: MonetizationDebug


## Billing backend that fails restore, to exercise the error path.
class FailingIapProvider extends IapProvider:
	func initialize() -> bool:
		return true

	func is_ready() -> bool:
		return true

	func purchase(product_id: String) -> void:
		purchase_failed.emit(product_id, "forced_fail")

	func restore() -> void:
		restore_failed.emit("forced_fail")


## Billing backend that reports a receipt the fresh profile does not own yet.
class ServerRestoreIapProvider extends IapProvider:
	func initialize() -> bool:
		return true

	func is_ready() -> bool:
		return true

	func purchase(product_id: String) -> void:
		purchase_failed.emit(product_id, "not_used")

	func restore() -> void:
		restore_completed.emit(["remove_ads"])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await _run()
	_finish()


func _run() -> void:
	await get_tree().process_frame
	_reset_profile()

	_section("providers and defaults")
	_check(Monetization.ads_provider is FakeAdsProvider, "fake ads is the default backend")
	_check(Monetization.iap_provider is FakeIapProvider, "fake IAP is the default backend")
	_check(Monetization.get_ads_provider_name() == "Fake", "ads provider reports Fake")
	_check(Monetization.get_iap_provider_name() == "Fake", "IAP provider reports Fake")
	_check(ConsentManager.has_consent(), "consent defaults to granted")
	var store := ConfigDB.get_store_config()
	_check(store != null and store.use_test_ids, "store config loads with test ids")
	_check(ConfigDB.get_product("remove_ads").get_store_id() == "thetree.remove_ads", "products expose a store id")
	_check(not Monetization.is_ad_in_flight(), "no ad is in flight at boot")

	Monetization.initialize_providers(true, true)
	_check(Monetization.ads_provider is FakeAdsProvider, "missing AdMob falls back to fake ads")
	_check(Monetization.iap_provider is FakeIapProvider, "missing Billing falls back to fake IAP")
	_reset_profile()

	_section("rewarded outcomes")
	Monetization.debug_force_rewarded("success")
	var ads_before := GameState.get_stat("ads_watched")
	var success_result := await _rewarded()
	_check(bool(success_result.get("success", false)), "forced success resolves true")
	_check(int(success_result.get("calls", 0)) == 1, "success callback fires once")
	_check(GameState.get_stat("ads_watched") == ads_before + 1, "a rewarded success counts for missions")
	await _wait_ms(40)
	_check(int(success_result.get("calls", 0)) == 1, "a late duplicate callback is impossible")

	Monetization.debug_force_rewarded("fail")
	var fail_result := await _rewarded()
	_check(not bool(fail_result.get("success", true)), "forced fail resolves false")

	Monetization.debug_force_rewarded("close")
	var close_result := await _rewarded()
	_check(not bool(close_result.get("success", true)), "forced close resolves false without a reward")

	Monetization.set_ad_timeout_seconds(0.1)
	Monetization.debug_force_rewarded("timeout")
	var timeout_result := await _rewarded()
	_check(not bool(timeout_result.get("success", true)), "timeout resolves false")
	_check(not Monetization.is_ad_in_flight(), "timeout releases the ad slot")
	_check(int(timeout_result.get("calls", 0)) == 1, "timeout callback fires once")
	Monetization.set_ad_timeout_seconds(1.0)

	Monetization.debug_force_rewarded("success")
	Monetization.set_fake_ad_delay(0.15)
	var first := {"done": false, "calls": 0, "success": false}
	var second := {"done": false, "calls": 0, "success": true}
	Monetization.show_rewarded("first", func(value: bool) -> void:
		first["calls"] = int(first["calls"]) + 1
		first["success"] = value
		first["done"] = true
	)
	Monetization.show_rewarded("second", func(value: bool) -> void:
		second["calls"] = int(second["calls"]) + 1
		second["success"] = value
		second["done"] = true
	)
	await _wait_until(func() -> bool: return bool(second["done"]), 1.0)
	_check(not bool(second["success"]), "a second request while busy is refused")
	await _wait_until(func() -> bool: return bool(first["done"]), 2.0)
	_check(bool(first["success"]), "the first request still completes")
	_check(int(first["calls"]) == 1 and int(second["calls"]) == 1, "busy handoff resolves both requests once")
	Monetization.set_fake_ad_delay(0.002)

	_section("backgrounding")
	Monetization.debug_force_rewarded("success")
	Monetization.set_fake_ad_delay(0.3)
	var backgrounded := {"done": false, "success": true}
	Monetization.show_rewarded("backgrounded", func(value: bool) -> void:
		backgrounded["success"] = value
		backgrounded["done"] = true
	)
	await _wait_until(func() -> bool: return Monetization.is_ad_in_flight(), 1.0)
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_PAUSED)
	get_tree().root.propagate_notification(NOTIFICATION_APPLICATION_RESUMED)
	await _wait_until(func() -> bool: return bool(backgrounded["done"]), 2.0)
	_check(not bool(backgrounded["success"]), "backgrounding an ad resolves without a reward")
	_check(not Monetization.is_ad_in_flight(), "backgrounding releases the ad slot")
	Monetization.set_fake_ad_delay(0.002)

	_section("speed trial")
	_reset_profile()
	Monetization.debug_force_rewarded("success")
	_check(await _trial_once() == &"success", "watching the trial ad succeeds")
	_check(SpeedService.has_pending_trial_15(), "the trial is pending for the next run")
	_check(await _trial_once() == &"active", "a pending trial cannot be bought twice")
	var trial_modifiers := RunModifiers.build(GameState.to_dict(), [], SpeedService.consume_pending_trial_15())
	_check(trial_modifiers.speed_trial_15, "the consumed trial reaches RunModifiers")
	SpeedService.set_run_trials(true, false)
	EventBus.run_ended.emit(null)
	_check(not SpeedService.is_run_trial_active(), "the trial clears when the run ends")
	_check(not SpeedService.has_pending_trial_15(), "run end also clears a pending trial")
	GameState.unlock("speed_15", true)
	_check(await _trial_once() == &"owned", "a permanent unlock hides the ad path")
	GameState.unlock("speed_15", false)
	Monetization.debug_force_rewarded("fail")
	_check(await _trial_once() == &"failed", "a failed trial ad reports failure")
	_check(not SpeedService.has_pending_trial_15(), "a failed ad grants no trial")

	var prebattle := PRE_BATTLE_SCENE.instantiate() as PreBattle
	add_child(prebattle)
	await get_tree().process_frame
	var trial_button := prebattle.find_child("SpeedTrialButton", true, false) as Button
	var unlocked_label := prebattle.find_child("SpeedUnlockedLabel", true, false) as Label
	_check(trial_button != null and trial_button.visible, "a locked profile shows the trial chip")
	GameState.unlock("speed_15", true)
	prebattle.refresh()
	_check(not trial_button.visible, "a permanent 1.5x unlock hides the trial chip")
	_check(unlocked_label.visible, "a permanent 1.5x unlock shows the static label")
	GameState.unlock("speed_15", false)
	SpeedService.grant_pending_trial_15()
	prebattle.refresh()
	_check(trial_button.disabled, "an active pending trial disables the chip")
	_check(trial_button.text == Loc.t_key("PREPARE_TRIAL_ACTIVE"), "the active trial chip says ACTIVE")
	SpeedService.clear_pending_trial_15()
	prebattle.queue_free()
	await get_tree().process_frame

	_section("free gems")
	_reset_profile()
	var initial_state := Monetization.get_free_gems_state()
	_check(bool(initial_state.get("allowed", false)), "free Gems start available")
	Monetization.debug_force_rewarded("success")
	var free_result := await _free_gems_once()
	_check(bool(free_result.get("granted", false)), "the free-Gems ad grants")
	_check(GameState.get_gems() == AdPolicy.FREE_GEMS_AMOUNT, "free Gems adds five Gems")
	var cooldown_state := Monetization.get_free_gems_state()
	_check(not bool(cooldown_state.get("allowed", true)), "the 4h cooldown starts immediately")
	_check(str(cooldown_state.get("reason", "")) == "ADS_FREE_GEMS_COOLDOWN", "the cooldown reason is reported")
	var blocked_result := await _free_gems_once()
	_check(not bool(blocked_result.get("granted", true)), "a second claim is refused")
	_check(GameState.get_gems() == AdPolicy.FREE_GEMS_AMOUNT, "the refused claim grants nothing")

	var now_ts := int(Time.get_unix_time_from_system())
	var today := Time.get_date_string_from_system()
	GameState.update_ads({
		"free_gems_last_ts": now_ts - AdPolicy.FREE_GEMS_COOLDOWN_SECONDS - 1,
	})
	_check(bool(Monetization.get_free_gems_state().get("allowed", false)), "an elapsed cooldown reopens the button")
	_check(bool((await _free_gems_once()).get("granted", false)), "second claim grants after the cooldown")
	GameState.update_ads({
		"free_gems_last_ts": int(Time.get_unix_time_from_system()) - AdPolicy.FREE_GEMS_COOLDOWN_SECONDS - 1,
	})
	_check(bool((await _free_gems_once()).get("granted", false)), "third claim grants after the cooldown")
	_check(GameState.get_gems() == AdPolicy.FREE_GEMS_AMOUNT * 3, "three claims pay fifteen Gems")
	var cap_state := Monetization.get_free_gems_state()
	_check(not bool(cap_state.get("allowed", true)), "the third claim hits the daily cap")
	_check(str(cap_state.get("reason", "")) == "ADS_FREE_GEMS_CAP", "the cap reason is reported")

	GameState.update_ads({
		"free_gems_last_ts": now_ts - AdPolicy.FREE_GEMS_COOLDOWN_SECONDS - 1,
		"free_gems_day": "2000-01-01",
		"free_gems_today": 3,
	})
	var rollover_state := Monetization.get_free_gems_state()
	_check(bool(rollover_state.get("allowed", false)), "a new local date resets the daily cap")
	_check(int(rollover_state.get("today", 3)) == 0, "the new day starts at zero claims")
	SaveManager.save_now(GameState.to_dict())
	var reloaded := SaveManager.load_game()
	GameState.from_dict(reloaded)
	_check(
		int(Monetization.get_free_gems_state().get("today", 3)) == 0,
		"the date rollover persists"
	)

	GameState.from_dict(SaveDefaults.create())
	GameState.update_ads({"free_gems_day": today, "free_gems_today": 0, "free_gems_last_ts": 0})
	Monetization.debug_force_rewarded("fail")
	var failed_free := await _free_gems_once()
	_check(not bool(failed_free.get("granted", true)), "a failed free-Gems ad grants nothing")
	_check(GameState.get_gems() == 0, "a failed free-Gems ad leaves the balance alone")
	_check(int(GameState.get_ads().get("free_gems_today", -1)) == 0, "a failed ad does not consume a daily claim")

	_section("interstitial policy")
	_check(not AdPolicy.should_show_interstitial(1, 3, false), "run 1 never shows an interstitial")
	_check(not AdPolicy.should_show_interstitial(3, 3, false), "run 3 never shows an interstitial")
	_check(not AdPolicy.should_show_interstitial(4, 1, false), "the first eligible run needs three counted runs")
	_check(AdPolicy.should_show_interstitial(4, 3, false), "a full counter shows on an eligible run")
	_check(not AdPolicy.should_show_interstitial(6, 3, true), "remove_ads blocks interstitials")
	var counter_after := AdPolicy.on_run_completed({"runs_since_interstitial": 2}, 6)
	_check(int(counter_after.get("runs_since_interstitial", 0)) == 3, "a completed run advances the counter")
	var counter_early := AdPolicy.on_run_completed({"runs_since_interstitial": 2}, 2)
	_check(int(counter_early.get("runs_since_interstitial", -1)) == 0, "the first three runs hold the counter at zero")

	_reset_profile()
	GameState.add_stat("runs", 6)
	GameState.update_ads({"runs_since_interstitial": 2})
	Monetization.note_completed_run(6)
	_check(Monetization.is_interstitial_due(), "run 6 with a full counter is due")
	Monetization.debug_force_rewarded("success")
	var interstitial_result := await _interstitial_once()
	_check(bool(interstitial_result.get("success", false)), "the interstitial completes")
	_check(int(GameState.get_ads().get("runs_since_interstitial", -1)) == 0, "showing resets the counter")
	Monetization.note_completed_run(7)
	_check(not Monetization.is_interstitial_due(), "the next run is not due yet")
	GameState.update_ads({"runs_since_interstitial": 3})
	GameState.unlock("remove_ads", true)
	_check(not Monetization.is_interstitial_due(), "remove_ads wins over a full counter")
	GameState.unlock("remove_ads", false)

	get_tree().paused = true
	var paused_reward := await _rewarded("results_double_gold")
	_check(not bool(paused_reward.get("success", true)), "no non-revive ad starts while paused")
	Monetization.debug_force_rewarded("success")
	var paused_revive := await _rewarded(AdPolicy.P_REVIVE)
	_check(bool(paused_revive.get("success", false)), "the revive placement may run while paused")
	get_tree().paused = false

	_section("revive")
	_reset_profile()
	Monetization.debug_force_rewarded("success")
	var battle := await _make_battle()
	var near: Enemy = battle.enemy_pool.spawn(
		ConfigDB.get_enemy("orc_grunt"),
		Battle.CENTER + Vector2(100.0, 0.0),
		{"spawn_delay": 0.0}
	)
	await get_tree().physics_frame
	_check(near != null and near.is_targetable(), "a test enemy stands near the Tree")
	var coins_before := battle.coins
	battle.core.take_damage(999999.0)
	var prompt_shown := await _wait_until(func() -> bool: return battle.hud.is_revive_visible(), 2.0)
	_check(prompt_shown, "defeat opens the revive prompt")
	_check(get_tree().paused, "the battle is paused while the prompt is open")
	var revive_button := battle.hud.find_child("ReviveButton", true, false) as Button
	_check(revive_button != null, "the revive button exists")
	if revive_button != null:
		revive_button.pressed.emit()
		await _wait_until(func() -> bool: return not get_tree().paused and not battle.hud.is_revive_visible(), 2.0)
	_check(is_equal_approx(battle.core.get_hp(), battle.core.get_max_hp() * 0.5), "revive restores 50% HP")
	_check(battle.core.is_invulnerable(), "revive grants the shield")
	_check(near == null or not near.is_targetable(), "revive clears enemies within 250 px")
	_check(battle.coins > coins_before, "cleared enemies award Coins")
	_check(not battle.is_over(), "the run continues after a revive")
	_check(not get_tree().paused, "the battle resumes unpaused")

	battle.core.clear_invulnerability()
	battle.core.take_damage(999999.0)
	await _wait_until(func() -> bool: return battle.is_over(), 2.0)
	_check(battle.is_over(), "a second death ends the run")
	_check(battle.summary.reason == &"defeat", "the second death keeps the defeat reason")
	_check(not battle.hud.is_revive_visible(), "revive is not offered twice")
	_check(not get_tree().paused, "the final defeat leaves the tree unpaused")
	_free_battle(battle)

	Monetization.debug_force_rewarded("fail")
	var fail_battle := await _make_battle()
	fail_battle.core.take_damage(999999.0)
	await _wait_until(func() -> bool: return fail_battle.hud.is_revive_visible(), 2.0)
	var fail_revive := fail_battle.hud.find_child("ReviveButton", true, false) as Button
	if fail_revive != null:
		fail_revive.pressed.emit()
		await _wait_until(func() -> bool: return fail_battle.is_over(), 2.0)
	_check(fail_battle.is_over(), "a failed revive ad ends the run")
	_check(not get_tree().paused, "a failed revive releases the pause")
	_free_battle(fail_battle)

	_section("IAP")
	_reset_profile()
	Monetization.debug_force_purchase("success")
	_check(await _purchase_once("gems_100") == &"success", "a gem pack purchases")
	_check(Monetization.get_purchase_status() == PurchaseFlow.Status.SUCCESS, "the purchase state is success")
	_check(GameState.get_gems() == 100, "the gem pack grants once")
	_check(await _purchase_once("gems_100") == &"success", "a consumable can be bought again")
	_check(GameState.get_gems() == 200, "the second gem pack grants again")

	_check(await _purchase_once("remove_ads") == &"success", "remove_ads purchases")
	_check(GameState.is_unlocked("remove_ads"), "remove_ads sets its unlock")
	_check(GameState.is_product_owned("remove_ads"), "remove_ads is owned")
	_check(await _purchase_once("remove_ads") == &"owned", "remove_ads cannot be bought twice")

	_check(await _purchase_once("starter_bundle") == &"success", "the starter bundle purchases")
	_check(GameState.get_gems() == 500, "the bundle adds Gems")
	_check(GameState.get_gold() == 3000, "the bundle adds Gold")
	_check(await _purchase_once("starter_bundle") == &"owned", "the bundle is one-time")

	Monetization.debug_force_purchase("cancel")
	_check(await _purchase_once("gems_550") == &"cancelled", "a cancelled purchase reports cancellation")
	_check(Monetization.get_purchase_status() == PurchaseFlow.Status.CANCELLED, "the purchase state is cancelled")
	_check(GameState.get_gems() == 500, "a cancelled purchase grants nothing")
	Monetization.debug_force_purchase("fail")
	_check(await _purchase_once("gems_550") == &"failed", "a failed purchase reports failure")
	_check(Monetization.get_purchase_status() == PurchaseFlow.Status.FAILED, "the purchase state is failed")
	_check(GameState.get_gems() == 500, "a failed purchase grants nothing")

	Monetization.debug_force_purchase("success")
	Monetization.set_fake_iap_delay(0.1)
	var busy_state := {"done": false, "outcome": &""}
	Monetization.purchase("gems_1200", func(outcome: StringName) -> void:
		busy_state["outcome"] = outcome
		busy_state["done"] = true
	)
	var busy_second := await _purchase_once("gems_1200")
	_check(busy_second == &"busy", "a double tap is refused while pending")
	await _wait_until(func() -> bool: return bool(busy_state["done"]), 2.0)
	_check(StringName(busy_state["outcome"]) == &"success", "the first double-tapped purchase completes")
	_check(GameState.get_gems() == 1700, "the double tap grants only once")
	Monetization.set_fake_iap_delay(0.002)

	ConsentManager.set_override(false)
	_check(await _purchase_once("gems_100") == &"no_consent", "no purchase is possible without consent")
	ConsentManager.clear_override()

	_reset_profile()
	GameState.own_product("remove_ads")
	GameState.unlock("remove_ads", false)
	var restore_state := await _restore_once()
	_check(bool(restore_state.get("ok", false)), "restore reports success")
	_check((restore_state.get("ids", []) as Array).has("remove_ads"), "restore returns owned products")
	_check(GameState.is_unlocked("remove_ads"), "restore re-applies the permanent unlock")
	var restore_again := await _restore_once()
	_check(bool(restore_again.get("ok", false)), "restore is repeatable")
	_check(GameState.get_gems() == 0 and GameState.get_gold() == 0, "restore never re-grants currency")

	var old_iap := Monetization.iap_provider
	Monetization.set_iap_provider(FailingIapProvider.new())
	var failed_restore := await _restore_once()
	_check(not bool(failed_restore.get("ok", true)), "a failed backend reports restore failure")
	Monetization.set_iap_provider(old_iap)

	_reset_profile()
	Monetization.set_iap_provider(ServerRestoreIapProvider.new())
	var server_restore := await _restore_once()
	_check(bool(server_restore.get("ok", false)), "a store receipt restores on a fresh profile")
	_check(GameState.is_product_owned("remove_ads"), "a restored receipt marks the product owned")
	_check(GameState.is_unlocked("remove_ads"), "a restored receipt re-applies its unlock")
	_check(GameState.get_gems() == 0 and GameState.get_gold() == 0, "a restored receipt pays no currency")
	Monetization.set_iap_provider(FakeIapProvider.new())

	_section("consent gate")
	ConsentManager.set_override(false)
	var denied := await _rewarded()
	_check(not bool(denied.get("success", true)), "no ad is possible without consent")
	ConsentManager.clear_override()

	_section("debug panel")
	_reset_profile()
	_debug_panel = DEBUG_PANEL_SCENE.instantiate() as MonetizationDebug
	add_child(_debug_panel)
	await get_tree().process_frame
	_debug_panel.open()
	_check(_debug_panel.visible, "the debug panel opens")
	_check(not (_debug_panel.find_child("Status", true, false) as Label).text.is_empty(), "the panel shows a status snapshot")
	var success_button := _debug_panel.find_child("SuccessButton", true, false) as Button
	var reset_button := _debug_panel.find_child("ResetButton", true, false) as Button
	var consent_button := _debug_panel.find_child("ConsentButton", true, false) as Button
	_check(success_button != null and reset_button != null and consent_button != null, "the panel exposes its controls")
	if success_button != null:
		success_button.pressed.emit()
		var forced := await _rewarded()
		_check(bool(forced.get("success", false)), "the panel forces the next rewarded outcome")
	var fail_button := _debug_panel.find_child("FailButton", true, false) as Button
	var close_button := _debug_panel.find_child("CloseAdButton", true, false) as Button
	var timeout_button := _debug_panel.find_child("TimeoutButton", true, false) as Button
	if fail_button != null:
		fail_button.pressed.emit()
		_check(not bool((await _rewarded()).get("success", true)), "the panel forces a rewarded failure")
	if close_button != null:
		close_button.pressed.emit()
		_check(not bool((await _rewarded()).get("success", true)), "the panel forces a no-reward close")
	if timeout_button != null:
		Monetization.set_ad_timeout_seconds(0.1)
		timeout_button.pressed.emit()
		_check(not bool((await _rewarded()).get("success", true)), "the panel forces a timeout")
		Monetization.set_ad_timeout_seconds(1.0)
	var buy_cancel_button := _debug_panel.find_child("BuyCancelButton", true, false) as Button
	if buy_cancel_button != null:
		buy_cancel_button.pressed.emit()
		_check(await _purchase_once("gems_100") == &"cancelled", "the panel forces a cancelled purchase")
		_check(GameState.get_gems() == 0, "the forced cancelled purchase grants nothing")
	if reset_button != null:
		GameState.update_ads({"runs_since_interstitial": 5, "free_gems_today": 2})
		reset_button.pressed.emit()
		_check(int(GameState.get_ads().get("runs_since_interstitial", -1)) == 0, "the panel resets cooldowns and counters")
	if consent_button != null:
		var before_consent := ConsentManager.has_consent()
		consent_button.pressed.emit()
		_check(ConsentManager.has_consent() != before_consent, "the panel toggles consent")
		ConsentManager.clear_override()
	_debug_panel.close()
	_check(not _debug_panel.visible, "the debug panel closes")

	var snapshot := Monetization.get_status_snapshot()
	_check(snapshot.has("ads_provider") and snapshot.has("free_gems"), "the status snapshot has provider and cooldown data")
	_check(int(snapshot.get("runs", -1)) == 0, "the snapshot reports the run count")

	_section("cleanup")
	_debug_panel.queue_free()
	_debug_panel = null
	for battle_ref: Battle in _battles:
		if is_instance_valid(battle_ref):
			battle_ref.queue_free()
	_battles.clear()
	get_tree().paused = false
	Engine.time_scale = 1.0
	Monetization.initialize_providers(false, false)
	Monetization.set_fake_ad_delay(0.002)
	Monetization.set_fake_iap_delay(0.002)
	ConsentManager.clear_override()
	SpeedService.clear_pending_trial_15()
	SpeedService.reset()
	GameState.from_dict(SaveDefaults.create())
	SaveManager.reset_progress()
	await get_tree().process_frame
	await get_tree().process_frame
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(orphans < 24, "no orphan node growth (%d orphans)" % orphans)


## --- Helpers --------------------------------------------------------------

func _reset_profile() -> void:
	if get_tree().paused:
		get_tree().paused = false
	Engine.time_scale = 1.0
	Monetization.initialize_providers(false, false)
	Monetization.set_fake_ad_delay(0.002)
	Monetization.set_fake_iap_delay(0.002)
	Monetization.set_ad_timeout_seconds(1.0)
	Monetization.debug_force_rewarded("none")
	Monetization.debug_force_purchase("none")
	ConsentManager.clear_override()
	SpeedService.clear_pending_trial_15()
	SpeedService.reset()
	GameState.from_dict(SaveDefaults.create())
	SaveManager.save_now(GameState.to_dict())


func _rewarded(placement := "test_placement") -> Dictionary:
	var state := {"done": false, "success": false, "calls": 0}
	Monetization.show_rewarded(placement, func(value: bool) -> void:
		state["calls"] = int(state["calls"]) + 1
		state["success"] = value
		state["done"] = true
	)
	await _wait_until(func() -> bool: return bool(state["done"]), 3.0)
	return state


func _free_gems_once() -> Dictionary:
	var state := {"done": false, "result": {}}
	Monetization.request_free_gems(func(result: Dictionary) -> void:
		state["result"] = result
		state["done"] = true
	)
	await _wait_until(func() -> bool: return bool(state["done"]), 3.0)
	return state["result"]


func _interstitial_once() -> Dictionary:
	var state := {"done": false, "success": false}
	Monetization.show_results_interstitial(func(success: bool) -> void:
		state["success"] = success
		state["done"] = true
	)
	await _wait_until(func() -> bool: return bool(state["done"]), 3.0)
	return state


func _trial_once() -> StringName:
	var state := {"done": false, "result": &""}
	Monetization.request_speed_trial(func(result: StringName) -> void:
		state["result"] = result
		state["done"] = true
	)
	await _wait_until(func() -> bool: return bool(state["done"]), 3.0)
	return StringName(state["result"])


func _purchase_once(product_id: String) -> StringName:
	var state := {"done": false, "outcome": &""}
	Monetization.purchase(product_id, func(outcome: StringName) -> void:
		state["outcome"] = outcome
		state["done"] = true
	)
	await _wait_until(func() -> bool: return bool(state["done"]), 3.0)
	return StringName(state["outcome"])


func _restore_once() -> Dictionary:
	var state := {"done": false, "ok": false, "ids": []}
	Monetization.restore_purchases(func(ids: Array, ok: bool) -> void:
		state["ids"] = ids
		state["ok"] = ok
		state["done"] = true
	)
	await _wait_until(func() -> bool: return bool(state["done"]), 3.0)
	return state


func _make_battle() -> Battle:
	var battle := BATTLE_SCENE.instantiate() as Battle
	battle.auto_route_results = false
	battle.offer_revive = true
	add_child(battle)
	battle.process_mode = Node.PROCESS_MODE_PAUSABLE
	await get_tree().physics_frame
	await get_tree().physics_frame
	_battles.append(battle)
	return battle


func _free_battle(battle: Battle) -> void:
	if battle == null or not is_instance_valid(battle):
		return
	_battles.erase(battle)
	battle.queue_free()
	await get_tree().process_frame
	get_tree().paused = false


func _wait_until(predicate: Callable, timeout_seconds := 2.0) -> bool:
	var start := Time.get_ticks_msec()
	var limit := int(timeout_seconds * 1000.0)
	while not bool(predicate.call()):
		if Time.get_ticks_msec() - start > limit:
			return false
		await get_tree().process_frame
	return true


func _wait_ms(milliseconds: int) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < milliseconds:
		await get_tree().process_frame


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("ALL MONETIZATION TESTS PASSED (%d checks)" % _checks)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	printerr("MONETIZATION TESTS FAILED: %d of %d checks" % [_failures.size(), _checks])
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
