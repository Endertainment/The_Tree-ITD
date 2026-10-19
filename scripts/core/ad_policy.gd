class_name AdPolicy
extends RefCounted
## Pure rules for every monetization placement.
##
## Kept out of `Monetization` so cooldowns, daily caps and the interstitial
## cadence can be tested headlessly with an injected clock and without touching
## the scene tree. Nothing here reads or writes the save.

const FREE_GEMS_AMOUNT := 5
const FREE_GEMS_COOLDOWN_SECONDS := 4 * 60 * 60
const FREE_GEMS_DAILY_CAP := 3
const INTERSTITIAL_EVERY_RUNS := 3
## The profile's first three completed runs never show an interstitial.
const INTERSTITIAL_MIN_RUNS := 4

const P_RUN_SPEED_TRIAL := "run_speed_trial"
const P_RESULTS_DOUBLE_GOLD := "results_double_gold"
const P_REVIVE := "revive"
const P_FREE_GEMS := "free_gems"
const P_INTERSTITIAL_RESULTS := "interstitial_results"

## Placements that are allowed to start while the scene tree is paused. Revive
## pauses the battle on purpose before the ad opens.
const PAUSED_ALLOWED := ["revive"]


## True when `placement` may start with `get_tree().paused == true`.
static func is_paused_allowed(placement: String) -> bool:
	return PAUSED_ALLOWED.has(placement)


## Cooldown/cap snapshot for the free-Gems button. `today` must be the local
## date string (`YYYY-MM-DD`); `now_ts` is a unix timestamp.
static func free_gems_state(ads: Dictionary, now_ts: int, today: String) -> Dictionary:
	var count := int(ads.get("free_gems_today", 0))
	if str(ads.get("free_gems_day", "")) != today:
		count = 0
	var last_ts := int(ads.get("free_gems_last_ts", 0))
	var remaining := 0
	if last_ts > 0:
		remaining = last_ts + FREE_GEMS_COOLDOWN_SECONDS - now_ts
		if now_ts < last_ts:
			# The device clock moved backwards; never let that shorten the wait.
			remaining = FREE_GEMS_COOLDOWN_SECONDS
		remaining = maxi(0, remaining)
	if count >= FREE_GEMS_DAILY_CAP:
		return {
			"allowed": false,
			"reason": "ADS_FREE_GEMS_CAP",
			"remaining": 0,
			"today": count,
			"last_ts": last_ts,
		}
	if remaining > 0:
		return {
			"allowed": false,
			"reason": "ADS_FREE_GEMS_COOLDOWN",
			"remaining": remaining,
			"today": count,
			"last_ts": last_ts,
		}
	return {
		"allowed": true,
		"reason": "",
		"remaining": 0,
		"today": count,
		"last_ts": last_ts,
	}


## Returns the ads block with one free-Gems claim recorded.
static func record_free_gems(ads: Dictionary, now_ts: int, today: String) -> Dictionary:
	var out: Dictionary = ads.duplicate(true)
	var count := int(out.get("free_gems_today", 0))
	if str(out.get("free_gems_day", "")) != today:
		count = 0
	out["free_gems_day"] = today
	out["free_gems_last_ts"] = now_ts
	out["free_gems_today"] = mini(FREE_GEMS_DAILY_CAP, count + 1)
	return out


## Advances the interstitial counter after a completed run. The first three
## runs hold the counter at zero so the first ad can only appear on run 6.
static func on_run_completed(ads: Dictionary, runs_completed: int) -> Dictionary:
	var out: Dictionary = ads.duplicate(true)
	var counter := int(out.get("runs_since_interstitial", 0))
	out["runs_since_interstitial"] = 0 if runs_completed < INTERSTITIAL_MIN_RUNS else counter + 1
	return out


## True when the results -> menu transition should show an interstitial.
static func should_show_interstitial(runs_completed: int, counter: int, ads_removed: bool) -> bool:
	if ads_removed or runs_completed < INTERSTITIAL_MIN_RUNS:
		return false
	return counter >= INTERSTITIAL_EVERY_RUNS


## Returns the ads block with the interstitial counter reset.
static func reset_interstitial_counter(ads: Dictionary) -> Dictionary:
	var out: Dictionary = ads.duplicate(true)
	out["runs_since_interstitial"] = 0
	return out
