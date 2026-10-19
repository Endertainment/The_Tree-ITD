class_name WaveRules
extends RefCounted
## Pure wave rules: boss cadence, boss HP, wave modifiers and wave scaling.
##
## Kept free of scene state so the headless tests can verify every formula
## without spawning a single enemy. `WaveManager` calls these functions.

enum Modifier { NONE, ARMORED, SWIFT, SWARM }

const BOSS_WAVE_INTERVAL := 10
const BOSS_BASE_HP := 1500.0
const BOSS_HP_GROWTH := 1.35
const BOSS_ESCORT_GRUNTS := 6
const BOSS_ESCORT_BRUTES := 2
const MODIFIER_START_WAVE := 8

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


## Extra count multiplier for the wave (Swarm adds 40%).
static func count_multiplier(modifier: Modifier) -> float:
	return 1.4 if modifier == Modifier.SWARM else 1.0


## Boss-wave spawn groups. The boss spawns first; escorts follow over ~2 s.
static func boss_wave_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	entries.append({"time": 0.0, "enemy_id": "orc_warlord", "is_boss": true})
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
static func scaling_for_wave(wave: int) -> Dictionary:
	return {
		"hp_mult": pow(1.16, float(wave - 1)),
		"speed_mult": minf(1.4, pow(1.02, float(wave - 1))),
		"coin_mult": pow(1.06, float(wave - 1)),
	}
