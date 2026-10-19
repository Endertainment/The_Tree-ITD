class_name ConsentManager
extends RefCounted
## Consent gate for ads and purchases.
##
## MVP stub: consent is granted by default, so the game is playable offline and
## nothing is collected. The real build must replace `has_consent()` with a
## Google UMP flow before the first ad request in the EEA.
##
## TODO(UMP): request consent info with `ConsentInformation.requestConsentInfoUpdate()`
## and show the form when `isConsentFormAvailable()` is true. Until then every
## ad/purchase call goes through this gate, and the debug panel can force either
## answer so the blocked path stays testable.
##
## TODO(families): the MVP is not child-directed and does not behaviourally
## target users; revisit before a Families-policy release.

## -1 = default (granted), 0 = forced deny, 1 = forced grant.
static var _override := -1


## Forces the gate for tests and the debug panel.
static func set_override(granted: bool) -> void:
	_override = 1 if granted else 0


## Returns to the default (granted) stub behaviour.
static func clear_override() -> void:
	_override = -1


## Current consent answer.
static func has_consent() -> bool:
	if _override == 0:
		return false
	if _override == 1:
		return true
	return true


## Gate for every ad request.
static func can_request_ads() -> bool:
	return has_consent()


## Gate for every purchase. Billing consent is separate in a real store build,
## but the acceptance rule is that no monetization surface works without it.
static func can_purchase() -> bool:
	return has_consent()


## Localization key describing the current state, for the debug panel.
static func get_status_key() -> String:
	return "DEBUG_CONSENT_GRANTED" if has_consent() else "DEBUG_CONSENT_DENIED"
