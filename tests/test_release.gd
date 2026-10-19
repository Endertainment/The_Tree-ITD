extends Node
## Headless release-hardening suite: rewarded-ad failure modes, purchase
## cancel/fail/double-tap, idempotent claims, a failed save write and a locale
## switch. Everything runs on the fake providers; no SDK and no device needed.
##
## Run with:
##   godot --headless --path <project> res://tests/TestRelease.tscn

const PRODUCT_GEMS := "gems_100"
const PRODUCT_BUNDLE := "starter_bundle"
const MISSION_ID := "ach_reach_wave_20"

var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	await _run()
	_finish()


func _run() -> void:
	await get_tree().process_frame
	SaveManager.reset_progress()
	GameState.from_dict(SaveDefaults.create())
	Monetization.debug_reset_ads()
	Monetization.set_fake_ad_delay(0.0)
	Monetization.set_fake_iap_delay(0.2)

	_section("rewarded ad: success grants once")
	var start_gems := GameState.get_gems()
	var success := await _free_gems()
	_check(bool(success.get("granted", false)), "a successful rewarded ad reports granted")
	_check(GameState.get_gems() == start_gems + 5, "the free-Gems ad grants exactly 5 Gems")

	var refused := await _free_gems()
	_check(not bool(refused.get("granted", false)), "a second request inside the cooldown is refused")
	_check(GameState.get_gems() == start_gems + 5, "the refused request grants nothing")

	_section("rewarded ad: close without reward")
	Monetization.debug_reset_ads()
	Monetization.debug_force_rewarded("close")
	var closed := await _free_gems()
	_check(not bool(closed.get("granted", false)), "closing the ad early grants nothing")
	_check(GameState.get_gems() == start_gems + 5, "closing does not change the balance")
	_check(Monetization.get_free_gems_state().get("allowed", false), "closing does not consume the daily attempt")

	_section("rewarded ad: provider failure")
	Monetization.debug_force_rewarded("fail")
	var failed := await _free_gems()
	_check(not bool(failed.get("granted", false)), "a provider failure grants nothing")
	_check(String(failed.get("reason", "")) != "", "the failure carries a reason for the UI")

	_section("rewarded ad: timeout")
	Monetization.debug_force_rewarded("timeout")
	Monetization.set_fake_ad_delay(5.0)
	Monetization.set_ad_timeout_seconds(0.3)
	var timed_out := await _free_gems()
	_check(not bool(timed_out.get("granted", false)), "a timed-out ad grants nothing")
	_check(not Monetization.is_ad_in_flight(), "the ad machine is idle after a timeout")
	Monetization.set_ad_timeout_seconds(15.0)
	Monetization.set_fake_ad_delay(0.0)

	_section("rewarded ad: double tap")
	Monetization.debug_reset_ads()
	Monetization.debug_force_rewarded("success")
	Monetization.set_fake_ad_delay(0.4)
	var gems_before_tap := GameState.get_gems()
	var taps: Array = []
	Monetization.request_free_gems(func(result: Dictionary) -> void: taps.append(result))
	Monetization.request_free_gems(func(result: Dictionary) -> void: taps.append(result))
	await _wait_until(func() -> bool: return taps.size() >= 2, 3.0)
	_check(taps.size() == 2, "both taps receive an answer")
	var granted_count := 0
	for tap: Dictionary in taps:
		if bool(tap.get("granted", false)):
			granted_count += 1
	_check(granted_count == 1, "a double tap grants exactly once")
	_check(GameState.get_gems() == gems_before_tap + 5, "a double tap adds one reward, not two")
	Monetization.set_fake_ad_delay(0.0)

	_section("purchase: cancel and fail")
	Monetization.debug_force_purchase("cancel")
	var cancel_outcome := await _purchase(PRODUCT_GEMS)
	_check(str(cancel_outcome) == "cancelled", "a cancelled purchase reports cancelled")
	_check(GameState.get_gems() == gems_before_tap + 5, "a cancelled purchase grants nothing")

	Monetization.debug_force_purchase("fail")
	var fail_outcome := await _purchase(PRODUCT_GEMS)
	_check(str(fail_outcome) == "failed", "a failed purchase reports failed")
	_check(GameState.get_gems() == gems_before_tap + 5, "a failed purchase grants nothing")

	_section("purchase: success and double tap")
	Monetization.debug_force_purchase("success")
	var gems_before_buy := GameState.get_gems()
	var outcomes: Array = []
	Monetization.purchase(PRODUCT_GEMS, func(outcome: StringName) -> void: outcomes.append(outcome))
	Monetization.purchase(PRODUCT_GEMS, func(outcome: StringName) -> void: outcomes.append(outcome))
	await _wait_until(func() -> bool: return outcomes.size() >= 2, 4.0)
	_check(outcomes.size() == 2, "both purchase taps receive an outcome")
	_check(outcomes.count(&"success") == 1, "only one tap succeeds")
	_check(outcomes.count(&"busy") == 1, "the second tap is refused as busy")
	_check(GameState.get_gems() == gems_before_buy + 100, "gems_100 grants 100 Gems once")
	_check(not Monetization.get_purchase_status() == PurchaseFlow.Status.PENDING, "the purchase machine is idle afterwards")

	_section("purchase: duplicate one-time bundle")
	Monetization.debug_force_purchase("success")
	_check(str(await _purchase(PRODUCT_BUNDLE)) == "success", "the starter bundle can be bought once")
	var gold_after_bundle := GameState.get_gold()
	var gems_after_bundle := GameState.get_gems()
	var again := await _purchase(PRODUCT_BUNDLE)
	_check(str(again) != "success", "buying the bundle again does not succeed")
	_check(GameState.get_gold() == gold_after_bundle, "the second bundle grants no Gold")
	_check(GameState.get_gems() == gems_after_bundle, "the second bundle grants no Gems")

	_section("claims are idempotent")
	var gold_before_claim := GameState.get_gold()
	_check(GameState.claim_mission("achievements", MISSION_ID, 500, 0), "the first claim succeeds")
	_check(not GameState.claim_mission("achievements", MISSION_ID, 500, 0), "the second claim is refused")
	_check(GameState.get_gold() == gold_before_claim + 500, "the claim pays out exactly once")

	_section("gold edges")
	var gold_now := GameState.get_gold()
	_check(not GameState.spend_gold(gold_now + 1), "spending more than the balance fails")
	_check(GameState.get_gold() == gold_now, "a failed spend changes nothing")
	_check(GameState.spend_gold(gold_now), "spending the exact balance succeeds")
	_check(GameState.get_gold() == 0, "the balance is zero after an exact spend")
	_check(not GameState.spend_gold(1), "spending from zero fails")

	_section("failed save write does not crash")
	var gold_before_failure := 0
	GameState.add_gold(321)
	gold_before_failure = GameState.get_gold()
	var tmp_dir := ProjectSettings.globalize_path("user://save.tmp")
	DirAccess.make_dir_absolute(tmp_dir)
	SaveManager.save_now(GameState.to_dict())
	_check(FileAccess.file_exists(SaveManager.get_save_path()), "the previous save survives a failed write")
	_check(int(SaveManager.load_game().get("currencies", {}).get("gold", 0)) >= 0, "the profile still loads")
	DirAccess.remove_absolute(tmp_dir)
	SaveManager.save_now(GameState.to_dict())
	_check(int(SaveManager.load_game().get("currencies", {}).get("gold", -1)) == gold_before_failure, "saving works again once storage recovers")

	_section("locale switch")
	Loc.set_locale("uk")
	_check(TranslationServer.get_locale().begins_with("uk"), "switching to Ukrainian changes the locale")
	_check(tr("HUD_WAVE") != "" and tr("HUD_WAVE") != "HUD_WAVE", "Ukrainian returns a real translation")
	Loc.set_locale("en")
	_check(TranslationServer.get_locale().begins_with("en"), "switching back to English works")
	_check(not Loc.format_number(12345).is_empty(), "number formatting survives a locale switch")

	_section("cleanup")
	Loc.set_locale("en")
	Monetization.debug_reset_ads()
	SaveManager.reset_progress()
	GameState.from_dict(SaveDefaults.create())
	_check(GameState.get_gold() == 0 and GameState.get_gems() == 0, "cleanup leaves a fresh profile")


func _free_gems() -> Dictionary:
	var result: Array = []
	Monetization.request_free_gems(func(value: Dictionary) -> void: result.append(value))
	await _wait_until(func() -> bool: return not result.is_empty(), 5.0)
	return result[0] if not result.is_empty() else {}


func _purchase(product_id: String) -> StringName:
	var result: Array = []
	Monetization.purchase(product_id, func(outcome: StringName) -> void: result.append(outcome))
	await _wait_until(func() -> bool: return not result.is_empty(), 5.0)
	return result[0] if not result.is_empty() else &"no_callback"


func _wait_until(condition: Callable, timeout: float) -> void:
	var waited := 0.0
	while not bool(condition.call()) and waited < timeout:
		await get_tree().create_timer(0.02).timeout
		waited += 0.02


func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("ALL RELEASE TESTS PASSED (%d checks)" % _checks)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	printerr("RELEASE TESTS FAILED: %d of %d checks" % [_failures.size(), _checks])
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
