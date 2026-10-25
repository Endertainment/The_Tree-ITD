class_name WaveRules
extends RefCounted
## Pure wave rules: boss cadence, boss HP, wave modifiers and wave scaling.
##
## Kept free of scene state so the headless tests can verify every formula
## without spawning a single enemy. `WaveManager` calls these functions.

enum Modifier { NONE, ARMORED, SWIFT, SWARM }

const BOSS_WAVE_INTERVAL := 10
const BOSS_BASE_HP := 1500.0
const AIRSHIP_BASE_HP := 2200.0
const BOSS_HP_GROWTH := 1.35
const BOSS_ESCORT_GRUNTS := 6
const BOSS_ESCORT_BRUTES := 2
const MODIFIER_START_WAVE := 8
const WARLORD_ID := "orc_warlord"
const AIRSHIP_ID := "orc_airship"

## Presentation keys for the 1.5 s wave banner.
const BANNER_KEYS := {
	Modifier.ARMORED: "BANNER_MOD_ARMORED",
	Modifier.SWIFT: "BANNER_MOD_SWIFT",
	Modifier.SWARM: "BANNER_MOD_SWARM",
}

const MODIFIER_NAMES := {
	Modifier.NONE: "none",
	Modifier.ARMORED: "armored",
	Modifier.SWIFT: "swift",
	Modifier.SWARM: "swarm",
}


## True for waves 10, 20, 30, ...
static func is_boss_wave(wave: int) -> bool:
	return wave > 0 and wave % BOSS_WAVE_INTERVAL == 0


## 1-based boss index for a boss wave.
static func boss_index_for_wave(wave: int) -> int:
	return maxi(1, wave / BOSS_WAVE_INTERVAL)


## Boss HP before wave scaling: `1500 * 1.35^(index - 1)`.
static func boss_hp(boss_index: int) -> float:
	return BOSS_BASE_HP * pow(BOSS_HP_GROWTH, float(maxi(1, boss_index) - 1))


## Airship HP: the second boss starts higher than the Warlord.
static func airship_hp(boss_index: int) -> float:
	return AIRSHIP_BASE_HP * pow(BOSS_HP_GROWTH, float(maxi(1, boss_index) - 1))


## Odd bosses are the Warlord, even bosses are the airship.
static func uses_airship(boss_index: int) -> bool:
	return boss_index % 2 == 0


## Enemy id for a boss index.
static func boss_id_for(boss_index: int) -> String:
	return AIRSHIP_ID if uses_airship(boss_index) else WARLORD_ID


## Deterministic modifier for one wave of one run. Boss waves and waves before
## 8 never get a modifier.
static func modifier_for(wave: int, run_seed: int) -> Modifier:
	if wave < MODIFIER_START_WAVE or is_boss_wave(wave):
		return Modifier.NONE
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%d" % [run_seed, wave])
	var options: Array[Modifier] = [Modifier.ARMORED, Modifier.SWIFT, Modifier.SWARM]
	return options[rng.randi_range(0, options.size() - 1)]


## Localization key of the banner text for `modifier`, or "" for none.
static func banner_key(modifier: Modifier) -> String:
	return str(BANNER_KEYS.get(modifier, ""))


## Lower-case id used by data, Analytics and tests.
static func modifier_name(modifier: Modifier) -> String:
	return str(MODIFIER_NAMES.get(modifier, "none"))


## Spawn-modifier keys for one wave modifier, merged over the wave multipliers.
## Boss waves and waves before 8 return an empty dictionary.
static func spawn_modifiers(modifier: Modifier) -> Dictionary:
	match modifier:
		Modifier.ARMORED:
			return {"armor_mult": 1.5, "modifier": "armored"}
		Modifier.SWIFT:
			return {"speed_mult": 1.25, "modifier": "swift"}
		Modifier.SWARM:
			return {"hp_mult": 0.8, "scale": 0.85, "modifier": "swarm"}
		_:
			return {}


## Extra count multiplier for the wave (Swarm adds 25%).
static func count_multiplier(modifier: Modifier) -> float:
	return 1.25 if modifier == Modifier.SWARM else 1.0


## Boss-wave spawn groups. The boss spawns first; escorts follow over ~2 s.
## `boss_id` comes from `boss_id_for()` so later waves can host the airship.
static func boss_wave_entries(boss_id := WARLORD_ID) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	entries.append({"time": 0.0, "enemy_id": boss_id, "is_boss": true})
	for index in BOSS_ESCORT_GRUNTS:
		entries.append({
			"time": 1.0 + float(index) * 0.35,
			"enemy_id": "orc_grunt",
			"is_escort": true,
		})
	for index in BOSS_ESCORT_BRUTES:
		entries.append({
			"time": 1.4 + float(index) * 0.9,
			"enemy_id": "orc_brute",
			"is_escort": true,
		})
	return entries


## Master scaling for a wave, applied on top of authored/procedural stats.
##
## Waves 1-`authored_max` are authored and already carry their difficulty, so
## they get no multiplier. The `1.12`/`1.02`/`1.08` curves then start from the
## authored strength at wave `authored_max + 1` instead of from wave 1. The HP
## slope was 1.16 until the 2026-10-25 autoplay pass: 20 real runs peaked at
## wave 19 and 15 of them died on 17-18, so the curve outran every tower and
## meta upgrade the player could buy.
static func scaling_for_wave(wave: int, authored_max: int = 10) -> Dictionary:
	var step := maxi(0, wave - authored_max - 1)
	return {
		"hp_mult": pow(1.12, float(step)),
		"speed_mult": minf(1.4, pow(1.02, float(step))),
		"coin_mult": pow(1.08, float(step)),
	}
