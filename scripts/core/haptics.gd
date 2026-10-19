class_name Haptics
extends RefCounted
## Device haptics, gated by the `haptics` setting and by platform.
##
## `Input.vibrate_handheld()` is a no-op (and logs) off mobile, so every call
## funnels through `enabled()` first. Durations follow master §9: a light tick on
## UI confirmation, a medium one when the Tree is hit, a long one for a boss.

const UI_CONFIRM_MS := 15
const CORE_DAMAGE_MS := 30
const BOSS_SPAWN_MS := 60


## True when haptics are available and switched on.
static func enabled() -> bool:
	if not OS.has_feature("mobile"):
		return false
	if GameState == null:
		return false
	return bool(GameState.get_setting("haptics", true))


## Light tick for a confirmed UI action.
static func tap() -> void:
	vibrate(UI_CONFIRM_MS)


## Medium pulse when the Tree takes contact damage.
static func core_damage() -> void:
	vibrate(CORE_DAMAGE_MS)


## Long pulse when a boss enters the arena.
static func boss_spawn() -> void:
	vibrate(BOSS_SPAWN_MS)


## Fires a `milliseconds` vibration if haptics are enabled.
static func vibrate(milliseconds: int) -> void:
	if milliseconds <= 0 or not enabled():
		return
	Input.vibrate_handheld(milliseconds)
