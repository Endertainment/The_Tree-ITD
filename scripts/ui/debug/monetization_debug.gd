class_name MonetizationDebug
extends Control
## Debug-only monetization panel, opened by five taps on the Home version label.
##
## It never grants rewards itself: it only drives the fake providers and the
## facade's counters, so every forced outcome exercises the real flow.

const REFRESH_SECONDS := 0.5

@onready var _title: Label = %Title
@onready var _status: Label = %Status
@onready var _rewarded_title: Label = %RewardedTitle
@onready var _purchase_title: Label = %PurchaseTitle
@onready var _success: Button = %SuccessButton
@onready var _fail: Button = %FailButton
@onready var _close: Button = %CloseAdButton
@onready var _timeout: Button = %TimeoutButton
@onready var _buy_success: Button = %BuySuccessButton
@onready var _buy_cancel: Button = %BuyCancelButton
@onready var _buy_fail: Button = %BuyFailButton
@onready var _reset: Button = %ResetButton
@onready var _consent: Button = %ConsentButton
@onready var _close_panel: Button = %ClosePanelButton

var _accum := 0.0
var _forced_note := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_success.pressed.connect(_force_rewarded.bind("success"))
	_fail.pressed.connect(_force_rewarded.bind("fail"))
	_close.pressed.connect(_force_rewarded.bind("close"))
	_timeout.pressed.connect(_force_rewarded.bind("timeout"))
	_buy_success.pressed.connect(_force_purchase.bind("success"))
	_buy_cancel.pressed.connect(_force_purchase.bind("cancel"))
	_buy_fail.pressed.connect(_force_purchase.bind("fail"))
	_reset.pressed.connect(_on_reset)
	_consent.pressed.connect(_on_consent)
	_close_panel.pressed.connect(close)
	refresh()


## Shows the panel.
func open() -> void:
	visible = true
	_accum = 0.0
	refresh()


## Hides the panel.
func close() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum >= REFRESH_SECONDS:
		_accum = 0.0
		refresh()


## Repaints every label and reflects provider readiness.
func refresh() -> void:
	_title.text = Loc.t_key("DEBUG_TITLE")
	_rewarded_title.text = Loc.t_key("DEBUG_FORCE_REWARDED")
	_purchase_title.text = Loc.t_key("DEBUG_FORCE_PURCHASE")
	_success.text = Loc.t_key("DEBUG_SUCCESS")
	_fail.text = Loc.t_key("DEBUG_FAIL")
	_close.text = Loc.t_key("DEBUG_CLOSE_AD")
	_timeout.text = Loc.t_key("DEBUG_TIMEOUT")
	_buy_success.text = Loc.t_key("DEBUG_PURCHASE_SUCCESS")
	_buy_cancel.text = Loc.t_key("DEBUG_PURCHASE_CANCEL")
	_buy_fail.text = Loc.t_key("DEBUG_PURCHASE_FAIL")
	_reset.text = Loc.t_key("DEBUG_RESET")
	_consent.text = Loc.t_key("DEBUG_TOGGLE_CONSENT")
	_close_panel.text = Loc.t_key("DEBUG_CLOSE")

	var fake_ads := Monetization.ads_provider is FakeAdsProvider
	var fake_iap := Monetization.iap_provider is FakeIapProvider
	for button: Button in [_success, _fail, _close, _timeout]:
		button.disabled = not fake_ads
	for button: Button in [_buy_success, _buy_cancel, _buy_fail]:
		button.disabled = not fake_iap

	var snapshot := Monetization.get_status_snapshot()
	var free_gems: Dictionary = snapshot.get("free_gems", {})
	var placements: Dictionary = snapshot.get("placements", {})
	var cooldown := int(free_gems.get("remaining", 0))
	var lines := [
		Loc.t_key("DEBUG_ADS_LINE", {
			"ads": snapshot.get("ads_provider", "None"),
			"iap": snapshot.get("iap_provider", "None"),
		}),
		Loc.t_key("DEBUG_CONSENT_LINE", {
			"state": Loc.t_key(ConsentManager.get_status_key()),
		}),
		Loc.t_key("DEBUG_PHASE_LINE", {
			"phase": Loc.t_key(_phase_key(int(snapshot.get("ad_phase", 0)))),
			"placement": str(snapshot.get("ad_placement", "")),
		}),
		Loc.t_key("DEBUG_INTERSTITIAL_LINE", {
			"count": int(snapshot.get("interstitial_counter", 0)),
			"due": Loc.t_key("DEBUG_YES" if bool(snapshot.get("interstitial_due", false)) else "DEBUG_NO"),
		}),
		Loc.t_key("DEBUG_FREE_GEMS_LINE", {
			"today": int(free_gems.get("today", 0)),
			"next": _cooldown_text(cooldown),
		}),
		Loc.t_key("DEBUG_RUNS_LINE", {"runs": int(snapshot.get("runs", 0))}),
		Loc.t_key("DEBUG_PLACEMENTS_LINE", {
			"speed": Loc.t_key("DEBUG_YES" if bool(placements.get("speed_trial", false)) else "DEBUG_NO"),
			"free": Loc.t_key("DEBUG_YES" if bool(placements.get("free_gems", false)) else "DEBUG_NO"),
			"interstitial": Loc.t_key("DEBUG_YES" if bool(placements.get("interstitial", false)) else "DEBUG_NO"),
		}),
	]
	if not _forced_note.is_empty():
		lines.append(_forced_note)
	_status.text = "\n".join(lines)


func _force_rewarded(outcome: String) -> void:
	Monetization.debug_force_rewarded(outcome)
	_forced_note = Loc.t_key("DEBUG_NEXT_REWARDED", {"outcome": outcome.to_upper()})
	refresh()


func _force_purchase(outcome: String) -> void:
	Monetization.debug_force_purchase(outcome)
	_forced_note = Loc.t_key("DEBUG_NEXT_PURCHASE", {"outcome": outcome.to_upper()})
	refresh()


func _on_reset() -> void:
	Monetization.debug_reset_ads()
	_forced_note = Loc.t_key("DEBUG_COUNTERS_RESET")
	refresh()


func _on_consent() -> void:
	ConsentManager.set_override(not ConsentManager.has_consent())
	refresh()


func _phase_key(phase: int) -> String:
	match phase:
		1:
			return "DEBUG_PHASE_LOADING"
		2:
			return "DEBUG_PHASE_SHOWING"
		_:
			return "DEBUG_PHASE_IDLE"


func _cooldown_text(seconds: int) -> String:
	if seconds <= 0:
		return Loc.t_key("DEBUG_READY")
	var minutes := int(ceil(float(seconds) / 60.0))
	if minutes >= 60:
		return Loc.t_key("TIME_HOURS_MINUTES", {
			"hours": minutes / 60,
			"minutes": minutes % 60,
		})
	return Loc.t_key("TIME_MINUTES", {"minutes": minutes})
