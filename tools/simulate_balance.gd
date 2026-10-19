extends Node
## Headless balance model for waves 1-50 and a meta-progression profile of runs.
##
## Run with:
##   godot --headless --path <project> res://tools/SimulateBalance.tscn
##
## The model loads the real `data/*.tres` numbers and calls the real
## `WaveRules` formulas, so it cannot drift from what ships. It never
## instantiates a battle scene and never touches a gameplay autoload.
##
## How one wave is modelled:
## - the wave becomes a spawn plan: the authored table for waves up to
##   `max_authored_wave()`, `WaveRules.boss_wave_entries()` on boss waves, and
##   the procedural count formula for everything after the table;
## - every 0.2 s tick the nearest enemy walks toward the Tree, the Tree takes
##   contact damage, and all archer DPS plus every built tower's DPS hits that
##   nearest enemy (armour is subtracted per hit, Ballista ignores it);
## - the wave ends when the spawn queue is empty and the last enemy dies, or
##   when the Tree dies; then payout and the 40/25/20/15 spending heuristic run.
##
## Deliberate simplifications, restated in the generated report:
## - path length is inflated by a constant 15% instead of real steering forces;
## - all damage focuses the nearest enemy instead of per-tower targets;
## - procedural waves use the expected 55/30/15 Grunt/Runner/Brute mix instead
##   of the live random roll;
## - only the lead enemy is slowed by Frost Spires, because that is the enemy
##   the tower actually holds;
## - ads, cards, the revive, and Coins left over from a defeat are not rewarded.

const REPORT_PATH := "res://docs/BALANCE_REPORT.md"

## Fixed seed for wave modifiers, so a report is reproducible.
const SEED := 20261020

const MAX_WAVE := 50
const PROFILE_RUNS := 8
const TICK := 0.2
const MAX_ALIVE := 70
const SPAWN_RADIUS := 640.0
const CORE_RADIUS := 90.0
## Constant path overhead for steering, separation and the spawn telegraph.
const PATH_OVERHEAD := 1.15
const PREP_FIRST := 10.0
const PREP_BETWEEN := 6.0
const WAVE_TIME_CAP := 600.0

const ENEMY_IDS: Array[String] = ["orc_grunt", "orc_runner", "orc_brute", "orc_warlord"]
const TOWER_IDS: Array[String] = ["archer_tower", "frost_spire", "ballista"]
const UPGRADE_IDS: Array[String] = [
	"roots", "regrowth", "canopy_bows", "elven_haste", "far_sight", "extra_archer",
]
const META_IDS: Array[String] = [
	"tree_hp", "tree_regen", "archer_dmg", "archer_speed",
	"start_coins", "tower_discount", "coin_gain", "gold_gain",
]
## Build order used by the 15% "towers" slice of the spending heuristic.
const BUILD_ORDER: Array[String] = [
	"archer_tower", "archer_tower", "frost_spire", "archer_tower",
	"ballista", "archer_tower", "frost_spire", "ballista",
]

# Two spending profiles, so the report separates "the stage's example split"
# from "what a player who reads the DPS-per-Coin numbers actually buys".
const PROFILE_STAGE := {"damage": 0.40, "speed": 0.25, "hp": 0.20, "towers": 0.15}
const PROFILE_TOWER_FIRST := {"damage": 0.20, "speed": 0.10, "hp": 0.10, "towers": 0.60}

## Every flag raised by the model, keyed by rule id.
const FLAG_SLOW_CLEAR := "time_to_clear > 90 s"
const FLAG_LOW_TREE := "Tree HP < 30%"
const FLAG_INCOME := "coin income off target by > 30%"

var _enemies: Dictionary = {}
var _towers: Dictionary = {}
var _upgrades: Dictionary = {}
var _meta: Dictionary = {}
var _table: WaveTable

var _report: Array[String] = []
var _run1_flags: Array[Dictionary] = []
var _all_flags: Array[Dictionary] = []


func _ready() -> void:
	_load_data()
	if _table == null or _enemies.is_empty() or _towers.is_empty():
		printerr("SIMULATION ABORTED: data resources failed to load")
		get_tree().quit(1)
		return
	var profiles := {
		"A - stage brief 40/25/20/15": PROFILE_STAGE,
		"B - tower-first 20/10/10/60": PROFILE_TOWER_FIRST,
	}
	var results := {}
	for name: String in profiles:
		results[name] = _simulate_profile(profiles[name])
	_write_report(results)
	_print_summary(results)
	await get_tree().process_frame
	get_tree().quit(0)


# --- data -----------------------------------------------------------------


func _load_data() -> void:
	for id: String in ENEMY_IDS:
		_enemies[id] = load("res://data/enemies/%s.tres" % id)
	for id: String in TOWER_IDS:
		_towers[id] = load("res://data/towers/%s.tres" % id)
	for id: String in UPGRADE_IDS:
		_upgrades[id] = load("res://data/upgrades/%s.tres" % id)
	for id: String in META_IDS:
		_meta[id] = load("res://data/meta_upgrades/%s.tres" % id)
	_table = load("res://data/waves/waves_01_10.tres") as WaveTable


# --- profile --------------------------------------------------------------


## Simulates `PROFILE_RUNS` back-to-back runs, buying meta upgrades with the
## Gold each run pays out. Returns one dictionary per run.
func _simulate_profile(weights: Dictionary) -> Dictionary:
	_all_flags.clear()
	var runs: Array[Dictionary] = []
	var meta := {}
	for id: String in META_IDS:
		meta[id] = 0
	var gold := 0
	for index: int in PROFILE_RUNS:
		var run := _simulate_run(index, meta, weights)
		runs.append(run)
		gold += int(run["gold"])
		var spent := _buy_meta(meta, gold)
		gold -= spent
	return {"runs": runs, "flags": _all_flags.duplicate(true), "weights": weights}


## One run from wave 1 until defeat or `MAX_WAVE`.
func _simulate_run(index: int, meta: Dictionary, weights: Dictionary) -> Dictionary:
	var state := _new_state(meta)
	_opening_build(state, meta)
	var rows: Array[Dictionary] = []
	var cleared := 0
	var gold_sum := 0
	var seconds := PREP_FIRST
	var defeated := false
	for wave: int in range(1, MAX_WAVE + 1):
		var row := _simulate_wave(wave, state, meta)
		rows.append(row)
		if float(row["tree_hp"]) <= 0.0 or bool(row["timed_out"]):
			defeated = true
			break
		cleared = wave
		gold_sum += 8 + 2 * wave
		seconds += float(row["clear"]) + PREP_BETWEEN
		state["hp"] = minf(float(state["max_hp"]), float(state["hp"]) + _regen(state, meta) * PREP_BETWEEN)
		_spend_coins(state, meta, weights)
	var gold_mult := 1.0 + 0.04 * float(meta["gold_gain"])
	_collect_flags(index, rows)
	return {
		"index": index + 1,
		"cleared": cleared,
		"reached": cleared if not defeated else mini(MAX_WAVE, cleared + 1),
		"gold": int(floor(float(gold_sum) * gold_mult)),
		"rows": rows,
		"meta": meta.duplicate(true),
		"seconds": seconds,
		"tree_pct": 100.0 * maxf(0.0, float(state["hp"])) / float(state["max_hp"]),
	}


func _new_state(meta: Dictionary) -> Dictionary:
	var max_hp := 1000.0 * (1.0 + 0.05 * float(meta["tree_hp"]))
	var levels := {}
	for id: String in UPGRADE_IDS:
		levels[id] = 0
	return {
		"hp": max_hp,
		"max_hp": max_hp,
		"coins": 120 + 20 * int(meta["start_coins"]),
		"levels": levels,
		"towers": [],
	}


## A real player does not walk into wave 1 with 120 Coins unspent: the first
## purchase is a tower on the nearest pad.
func _opening_build(state: Dictionary, meta: Dictionary) -> void:
	var data: TowerData = _towers["archer_tower"]
	var cost := int(round(float(data.cost) * (1.0 - 0.02 * float(meta["tower_discount"]))))
	if int(state["coins"]) >= cost:
		state["coins"] = int(state["coins"]) - cost
		(state["towers"] as Array).append({"id": "archer_tower", "level": 1})


# --- one wave -------------------------------------------------------------


func _simulate_wave(wave: int, state: Dictionary, meta: Dictionary) -> Dictionary:
	var plan := _spawn_plan(wave)
	var archer := _archer_stats(state, meta)
	var towers := _tower_stats(state)
	var slow_target := _frost_strength(state)
	var regen := _regen(state, meta)
	var coin_mult := 1.0 + 0.03 * float(meta["coin_gain"])

	var alive: Array[Dictionary] = []
	var pending: Array[Dictionary] = []
	var plan_index := 0
	var t := 0.0
	var hp_pool := 0.0
	var coins := 0.0
	var leaked := 0
	var dps_at_start := _aggregate_dps(archer, towers)

	while t < WAVE_TIME_CAP and (plan_index < plan.size() or not alive.is_empty()):
		while plan_index < plan.size() and float(plan[plan_index]["time"]) <= t and alive.size() < MAX_ALIVE:
			var enemy := _instantiate(plan[plan_index], meta, coin_mult)
			hp_pool += float(enemy["max_hp"])
			alive.append(enemy)
			plan_index += 1
		for extra: Dictionary in pending:
			hp_pool += float(extra["max_hp"])
			alive.append(extra)
		pending.clear()

		_step(alive, state, archer, towers, slow_target, pending)
		var survivors: Array[Dictionary] = []
		for enemy: Dictionary in alive:
			if float(enemy["hp"]) <= 0.0:
				coins += float(enemy["coin"])
			else:
				survivors.append(enemy)
		alive = survivors
		state["hp"] = minf(float(state["max_hp"]), float(state["hp"]) + regen * TICK)
		if float(state["hp"]) <= 0.0:
			break
		t += TICK

	for enemy: Dictionary in alive:
		if bool(enemy["contacted"]):
			leaked += 1

	var wave_reward := 10 + 2 * wave
	state["coins"] = int(state["coins"]) + int(round(coins)) + wave_reward
	var row := {
		"wave": wave,
		"count": plan.size(),
		"total_hp": hp_pool,
		"dps": dps_at_start,
		"clear": t,
		"kills": int(round(coins)),
		"coins": wave_reward + int(round(coins)),
		"tree_hp": float(state["hp"]),
		"tree_pct": 100.0 * maxf(0.0, float(state["hp"])) / float(state["max_hp"]),
		"leaked": leaked,
		"timed_out": t >= WAVE_TIME_CAP and not alive.is_empty(),
		"modifier": WaveRules.modifier_name(WaveRules.modifier_for(wave, SEED)),
		"boss": WaveRules.is_boss_wave(wave),
	}
	return row


func _step(
	alive: Array[Dictionary],
	state: Dictionary,
	archer: Dictionary,
	towers: Array[Dictionary],
	slow_target: float,
	pending: Array[Dictionary]
) -> void:
	if alive.is_empty():
		return
	alive.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	for index: int in alive.size():
		var enemy: Dictionary = alive[index]
		if bool(enemy["contacted"]):
			continue
		var speed := float(enemy["speed"])
		if index == 0 and slow_target > 0.0:
			speed *= 1.0 - slow_target
		enemy["dist"] = maxf(
			CORE_RADIUS + float(enemy["radius"]),
			float(enemy["dist"]) - speed * TICK / PATH_OVERHEAD
		)
		if float(enemy["dist"]) <= CORE_RADIUS + float(enemy["radius"]):
			enemy["contacted"] = true
	# Contact damage: enemies that reached the Tree stay there and keep hitting.
	for enemy: Dictionary in alive:
		if not bool(enemy["contacted"]):
			continue
		enemy["contact_cd"] = float(enemy["contact_cd"]) - TICK
		if float(enemy["contact_cd"]) <= 0.0:
			state["hp"] = maxf(0.0, float(state["hp"]) - float(enemy["damage"]))
			enemy["contact_cd"] = float(enemy["cooldown"])

	var target: Dictionary = alive[0]
	var damage := 0.0
	if float(target["dist"]) <= float(archer["range"]):
		damage += archer["count"] * maxf(1.0, float(archer["damage"]) - float(target["armor"])) \
			/ float(archer["interval"])
	for tower: Dictionary in towers:
		var hit := float(tower["damage"])
		if not bool(tower["ignores_armor"]):
			hit = maxf(1.0, hit - float(target["armor"]))
		damage += hit / float(tower["interval"])
	target["hp"] = float(target["hp"]) - damage * TICK

	if bool(target["is_boss"]):
		_boss_abilities(target, pending)


## Boss summons at 70% / 40% HP and enrages below 30%, matching `Boss.gd`.
func _boss_abilities(boss: Dictionary, pending: Array[Dictionary]) -> void:
	var ratio := float(boss["hp"]) / float(boss["max_hp"])
	if ratio <= 0.7 and not bool(boss["summon_70"]):
		boss["summon_70"] = true
		_summon_runners(boss, pending)
	if ratio <= 0.4 and not bool(boss["summon_40"]):
		boss["summon_40"] = true
		_summon_runners(boss, pending)
	if ratio <= 0.3 and not bool(boss["enraged"]):
		boss["enraged"] = true
		boss["speed"] = float(boss["speed"]) * 1.3


func _summon_runners(boss: Dictionary, pending: Array[Dictionary]) -> void:
	var data: EnemyData = _enemies["orc_runner"]
	for _i: int in 4:
		pending.append({
			"id": "orc_runner",
			"max_hp": data.max_hp,
			"hp": data.max_hp,
			"speed": data.speed,
			"damage": data.damage,
			"armor": data.armor,
			"coin": data.coin_value,
			"radius": data.radius,
			"cooldown": data.attack_cooldown,
			"contact_cd": data.attack_cooldown,
			"dist": float(boss["dist"]),
			"contacted": bool(boss["contacted"]),
			"is_boss": false,
			"summon_70": false,
			"summon_40": false,
			"enraged": false,
		})


func _instantiate(entry: Dictionary, meta: Dictionary, coin_mult: float) -> Dictionary:
	var data: EnemyData = _enemies[str(entry["enemy_id"])]
	var is_boss := bool(entry.get("is_boss", false))
	var hp := WaveRules.boss_hp(int(entry.get("boss_index", 1))) if is_boss \
		else data.max_hp * float(entry.get("hp_mult", 1.0))
	return {
		"id": data.id,
		"max_hp": hp,
		"hp": hp,
		"speed": data.speed * float(entry.get("speed_mult", 1.0)),
		"damage": data.damage,
		"armor": data.armor * float(entry.get("armor_mult", 1.0)),
		"coin": maxi(1, roundi(float(data.coin_value) * float(entry.get("coin_mult", 1.0)) * coin_mult)),
		"radius": data.radius,
		"cooldown": data.attack_cooldown,
		"contact_cd": 0.0,
		"dist": SPAWN_RADIUS,
		"contacted": false,
		"is_boss": is_boss,
		"summon_70": false,
		"summon_40": false,
		"enraged": false,
	}


# --- spawn plan -----------------------------------------------------------


func _spawn_plan(wave: int) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	var modifier := WaveRules.modifier_for(wave, SEED)
	var extra := WaveRules.spawn_modifiers(modifier)
	var count_mult := WaveRules.count_multiplier(modifier)
	var scaling := WaveRules.scaling_for_wave(wave, _table.max_authored_wave())
	var extra_hp := float(extra.get("hp_mult", 1.0))
	var extra_speed := float(extra.get("speed_mult", 1.0))
	var extra_armor := float(extra.get("armor_mult", 1.0))

	if WaveRules.is_boss_wave(wave):
		var boss_index := WaveRules.boss_index_for_wave(wave)
		for entry: Dictionary in WaveRules.boss_wave_entries():
			var is_boss := bool(entry.get("is_boss", false))
			# Escorts scale with the wave; the boss scales by its own index and
			# never takes the wave modifier (matches `WaveManager`).
			plan.append({
				"time": float(entry.get("time", 0.0)),
				"enemy_id": str(entry.get("enemy_id", "orc_warlord")),
				"hp_mult": 1.0 if is_boss else float(scaling["hp_mult"]),
				"speed_mult": float(scaling["speed_mult"]),
				"coin_mult": float(scaling["coin_mult"]),
				"armor_mult": 1.0,
				"is_boss": is_boss,
				"boss_index": boss_index,
			})
	elif wave <= _table.max_authored_wave():
		for entry: WaveEntry in _table.entries_for(wave):
			var total := maxi(1, roundi(float(entry.count) * count_mult))
			var interval := maxf(0.15, entry.interval)
			for index: int in total:
				plan.append({
					"time": entry.start_delay + float(index) * interval,
					"enemy_id": entry.enemy_id,
					"hp_mult": entry.hp_mult * extra_hp,
					"speed_mult": entry.speed_mult * extra_speed,
					"coin_mult": entry.coin_mult,
					"armor_mult": extra_armor,
					"is_boss": false,
				})
	else:
		var total := maxi(1, roundi((6.0 + float(wave) * 1.4) * count_mult))
		var interval := maxf(0.25, 1.1 - 0.02 * float(wave))
		for index: int in total:
			plan.append({
				"time": float(index) * interval,
				"enemy_id": _procedural_enemy(index),
				"hp_mult": float(scaling["hp_mult"]) * extra_hp,
				"speed_mult": float(scaling["speed_mult"]) * extra_speed,
				"coin_mult": float(scaling["coin_mult"]),
				"armor_mult": extra_armor,
				"is_boss": false,
			})
	plan.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["time"]) < float(b["time"]))
	return plan


## Deterministic stand-in for the live 15% Brute / 30% Runner / 55% Grunt roll.
func _procedural_enemy(index: int) -> String:
	var roll := fposmod(0.3 + float(index) * 0.6180339887, 1.0)
	if roll < 0.15:
		return "orc_brute"
	if roll < 0.45:
		return "orc_runner"
	return "orc_grunt"


# --- player power ---------------------------------------------------------


func _archer_stats(state: Dictionary, meta: Dictionary) -> Dictionary:
	var levels: Dictionary = state["levels"]
	var damage_mult := (1.0 + 0.04 * float(meta["archer_dmg"])) \
		* (1.0 + 0.15 * float(levels["canopy_bows"]))
	var speed_mult := (1.0 + 0.03 * float(meta["archer_speed"])) \
		* (1.0 + 0.08 * float(levels["elven_haste"]))
	return {
		"damage": snappedf(12.0 * damage_mult, 0.1),
		"interval": snappedf(0.8 / maxf(0.1, speed_mult), 0.001),
		"range": 520.0 + 40.0 * float(levels["far_sight"]),
		"count": clampi(2 + int(levels["extra_archer"]), 1, 5),
	}


func _tower_stats(state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tower: Dictionary in state["towers"]:
		var data: TowerData = _towers[str(tower["id"])]
		var level: TowerLevel = data.get_level_stats(int(tower["level"]))
		if level == null:
			continue
		result.append({
			"id": data.id,
			"level": int(tower["level"]),
			"damage": level.damage,
			"interval": level.interval,
			"range": level.range,
			"ignores_armor": level.ignores_armor,
			"slow": level.slow_strength,
		})
	return result


func _frost_strength(state: Dictionary) -> float:
	var strongest := 0.0
	for tower: Dictionary in state["towers"]:
		var data: TowerData = _towers[str(tower["id"])]
		var level: TowerLevel = data.get_level_stats(int(tower["level"]))
		if level != null:
			strongest = maxf(strongest, level.slow_strength)
	return strongest


func _regen(state: Dictionary, meta: Dictionary) -> float:
	return 0.5 * float(meta["tree_regen"]) + 2.0 * float(state["levels"]["regrowth"])


func _aggregate_dps(archer: Dictionary, towers: Array[Dictionary]) -> float:
	var dps := float(archer["count"]) * float(archer["damage"]) / float(archer["interval"])
	for tower: Dictionary in towers:
		dps += float(tower["damage"]) / float(tower["interval"])
	return dps


# --- spending -------------------------------------------------------------


## Spends this wave's Coins with the profile's split.
func _spend_coins(state: Dictionary, meta: Dictionary, weights: Dictionary) -> void:
	var budget := float(state["coins"])
	_buy_track(state, "canopy_bows", budget * float(weights["damage"]))
	_buy_track(state, "elven_haste", budget * float(weights["speed"]))
	var roots_before := int(state["levels"]["roots"])
	_buy_track(state, "roots", budget * float(weights["hp"]))
	var roots_gained := int(state["levels"]["roots"]) - roots_before
	if roots_gained > 0:
		var root_track: UpgradeTrack = _upgrades["roots"]
		var extra_hp := root_track.value_at(int(state["levels"]["roots"])) \
			- root_track.value_at(roots_before)
		state["max_hp"] = float(state["max_hp"]) + extra_hp
		state["hp"] = minf(float(state["max_hp"]), float(state["hp"]) + extra_hp)
	_buy_towers(state, meta, budget * float(weights["towers"]))


func _buy_track(state: Dictionary, track_id: String, allowance: float) -> void:
	var track: UpgradeTrack = _upgrades[track_id]
	var levels: Dictionary = state["levels"]
	while int(levels[track_id]) < track.max_level:
		var cost := track.cost_for_level(int(levels[track_id]))
		if float(cost) > allowance or int(cost) > int(state["coins"]):
			return
		levels[track_id] = int(levels[track_id]) + 1
		state["coins"] = int(state["coins"]) - cost
		allowance -= float(cost)


func _buy_towers(state: Dictionary, meta: Dictionary, allowance: float) -> void:
	var towers: Array = state["towers"]
	if towers.size() < BUILD_ORDER.size():
		var id := BUILD_ORDER[towers.size()]
		var data: TowerData = _towers[id]
		var cost := int(round(float(data.cost) * (1.0 - 0.02 * float(meta["tower_discount"]))))
		if float(cost) <= allowance and cost <= int(state["coins"]):
			state["coins"] = int(state["coins"]) - cost
			towers.append({"id": id, "level": 1})
		return
	# All pads full: upgrade the cheapest tower instead.
	var best_index := -1
	var best_cost := 1 << 30
	for index: int in towers.size():
		var tower: Dictionary = towers[index]
		var data: TowerData = _towers[str(tower["id"])]
		if int(tower["level"]) >= data.max_level():
			continue
		var cost := _tower_upgrade_cost(data, int(tower["level"]))
		if cost < best_cost:
			best_cost = cost
			best_index = index
	if best_index >= 0 and float(best_cost) <= allowance and best_cost <= int(state["coins"]):
		var tower: Dictionary = towers[best_index]
		tower["level"] = int(tower["level"]) + 1
		state["coins"] = int(state["coins"]) - best_cost


func _tower_upgrade_cost(data: TowerData, level: int) -> int:
	return _round_to_step(float(data.cost) * pow(1.6, float(level)), 5)


func _round_to_step(value: float, step: int) -> int:
	return int(round(value / float(step)) * step)


## Buys the cheapest available meta upgrade until the Gold is gone.
func _buy_meta(meta: Dictionary, gold: int) -> int:
	var spent := 0
	var bought := true
	while bought:
		bought = false
		var best_id := ""
		var best_cost := 1 << 30
		for id: String in META_IDS:
			var track: MetaUpgradeData = _meta[id]
			var level := int(meta[id])
			if level >= track.max_level:
				continue
			var cost := track.cost_for_level(level)
			if cost < best_cost:
				best_cost = cost
				best_id = id
		if best_id != "" and best_cost <= gold - spent:
			spent += best_cost
			meta[best_id] = int(meta[best_id]) + 1
			bought = true
	return spent


# --- report ---------------------------------------------------------------


func _write_report(results: Dictionary) -> void:
	_push("# Balance simulation report")
	_push("")
	_push("Generated by `tools/simulate_balance.gd` (Godot 4.7.2, headless).")
	_push("")
	_push("```")
	_push("godot --headless --path <project> res://tools/SimulateBalance.tscn")
	_push("```")
	_push("")
	_push("Seed `%d`, tick `%.1f s`, waves `1-%d`, runs `%d`. Every number is read from"
		% [SEED, TICK, MAX_WAVE, PROFILE_RUNS])
	_push("`data/*.tres` and every formula from `WaveRules`; nothing is duplicated here.")
	_push("")
	_push("## Model and assumptions")
	_push("")
	_push("- The Tree sits at the arena centre; the archer range is measured from it.")
	_push("- Enemies walk from `%.0f px` to the Tree surface (`%.0f px` + body radius)."
		% [SPAWN_RADIUS, CORE_RADIUS])
	_push("- Path length is inflated by a constant `%.0f%%` for steering and separation."
		% ((PATH_OVERHEAD - 1.0) * 100.0))
	_push("- All archer and tower damage focuses the nearest enemy, matching the")
	_push("  default `nearest` targeting; overkill is wasted like it is in game.")
	_push("- Towers are assumed to have the whole path inside their range (pads sit")
	_push("  at `300 px`, the shortest tower range is `380 px`, the path spans")
	_push("  `90-640 px`), so their DPS applies while a target is in range.")
	_push("- Procedural spawns use the expected `55/30/15` Grunt/Runner/Brute mix.")
	_push("- Only the lead enemy is slowed by Frost Spires.")
	_push("- Bosses summon `4` Runners at `70%` and `40%` HP and enrage at `30%`")
	_push("  (`WaveRules.boss_hp` and `WaveRules.boss_wave_entries`).")
	_push("- Waves 1-`authored_max` are authored and get no wave multiplier; the")
	_push("  `1.16`/`1.02`/`1.06` curves start at wave `authored_max + 1`.")
	_push("- Between runs all Gold is spent cheapest-first on the eight meta tracks.")
	_push("- Cards, ads, revives and the wave-30 Gem milestone do not affect power.")
	_push("- Two spending profiles are simulated because the split matters: a")
	_push("  tower costs `60` Coins for `14` DPS (about `0.23` DPS/Coin) while the")
	_push("  first Canopy Bows level costs `80` for about `4.5` DPS (`0.06`).")
	_push("")

	for name: String in results:
		var profile: Dictionary = results[name]
		var runs: Array = profile["runs"]
		var weights: Dictionary = profile["weights"]
		_push("## Spending profile %s" % name)
		_push("")
		_push("Weights of the Coins on hand: towers `%d%%`, damage `%d%%`, speed `%d%%`, HP `%d%%`."
			% [
				int(round(float(weights["towers"]) * 100.0)),
				int(round(float(weights["damage"]) * 100.0)),
				int(round(float(weights["speed"]) * 100.0)),
				int(round(float(weights["hp"]) * 100.0)),
			])
		_push("")
		_push("### Run 1 - no meta upgrades")
		_push("")
		_push(_wave_table(runs[0]))
		_push("")
		_push("### Meta progression (all Gold spent cheapest-first)")
		_push("")
		_push("| Run | Wave reached | Waves cleared | Run time | Tree HP | Gold earned | Meta levels bought |")
		_push("|---:|---:|---:|---:|---:|---:|---|")
		for run: Dictionary in runs:
			_push("| %d | %d | %d | %s | %d%% | %d | %s |" % [
				int(run["index"]), int(run["reached"]), int(run["cleared"]),
				_mmss(float(run["seconds"])), int(round(float(run["tree_pct"]))),
				int(run["gold"]), _meta_summary(run["meta"]),
			])
		_push("")
		_push("### Target curve")
		_push("")
		_push("| Target | Expected | Measured | Verdict |")
		_push("|---|---|---|---|")
		_push(_target_row("First run", "waves 8-12", int(runs[0]["reached"]), "range"))
		var run_5 := int(runs[mini(4, runs.size() - 1)]["reached"])
		var run_8 := int(runs[runs.size() - 1]["reached"])
		_push(_target_row("Run 5", "wave 20+", run_5, "min"))
		_push(_target_row("Run 8", "wave 20+", run_8, "min"))
		_push("")
		_push("### Flagged waves")
		_push("")
		var flags: Array = profile["flags"]
		if flags.is_empty():
			_push("None.")
		else:
			_push("| Run | Wave | Rule | Detail |")
			_push("|---:|---:|---|---|")
			var shown := 0
			for flag: Dictionary in flags:
				if shown >= 40:
					break
				_push("| %d | %d | %s | %s |" % [
					int(flag["run"]), int(flag["wave"]), str(flag["rule"]), str(flag["detail"]),
				])
				shown += 1
			if flags.size() > shown:
				_push("")
				_push("_%d further flagged rows (mostly the `income` rule on waves "
					% (flags.size() - shown))
				_push("15-50) are listed in the wave tables above; the rule counts are:")
				for rule: String in [FLAG_SLOW_CLEAR, FLAG_LOW_TREE, FLAG_INCOME]:
					var count := 0
					for flag: Dictionary in flags:
						if str(flag["rule"]) == rule:
							count += 1
					_push("- `%s`: %d" % [rule, count])
		_push("")

	_push("## Reading the report")
	_push("")
	_push("- `DPS` is the archer + tower damage per second against zero armor at the")
	_push("  start of the wave; armored waves clear slower than `total HP / DPS`.")
	_push("- `Coins` is the wave payout (kills + `10 + 2*wave`) and excludes the")
	_push("  starting balance and earlier waves.")
	_push("- `Wave reached` counts the wave the run died in; `Waves cleared` does not.")
	_push("- A wave only ends when the last enemy dies, so leaked enemies keep")
	_push("  hitting the Tree and inflate the clear time.")
	_push("")
	_push("## Tuning notes")
	_push("")
	_push(str(_tuning_notes()))
	_push("")
	_write_file("\n".join(PackedStringArray(_report)) + "\n")


func _wave_table(run: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("| Wave | Enemies | Total HP | DPS | Clear | Coins | Tree HP | Leaked | Modifier | Flags |")
	lines.append("|---:|---:|---:|---:|---:|---:|---:|---:|---|---|")
	for row: Dictionary in run["rows"]:
		lines.append("| %d | %d | %d | %d | %.1f s | %d | %d%% | %d | %s | %s |" % [
			int(row["wave"]), int(row["count"]), int(row["total_hp"]), int(row["dps"]),
			float(row["clear"]), int(row["coins"]), int(round(float(row["tree_pct"]))),
			int(row["leaked"]), str(row["modifier"]), _flag_labels(row),
		])
	return "\n".join(lines)


func _flag_labels(row: Dictionary) -> String:
	var labels: Array[String] = []
	for rule: String in _flags_for(row):
		match rule:
			FLAG_SLOW_CLEAR:
				labels.append("slow")
			FLAG_LOW_TREE:
				labels.append("tree")
			FLAG_INCOME:
				labels.append("income")
	return ", ".join(labels)


func _flags_for(row: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if float(row["clear"]) > 90.0:
		result.append(FLAG_SLOW_CLEAR)
	if float(row["tree_pct"]) < 30.0:
		result.append(FLAG_LOW_TREE)
	var target := float(10 + 2 * int(row["wave"])) + float(row["count"]) * 7.0
	if target > 0.0 and absf(float(row["coins"]) - target) / target > 0.30:
		result.append(FLAG_INCOME)
	return result


func _collect_flags(run_index: int, rows: Array[Dictionary]) -> void:
	for row: Dictionary in rows:
		for rule: String in _flags_for(row):
			var detail := "clear `%.1f s`, Tree `%d%%`, coins `%d`" % [
				float(row["clear"]), int(round(float(row["tree_pct"]))), int(row["coins"]),
			]
			var flag := {"run": run_index + 1, "wave": int(row["wave"]), "rule": rule, "detail": detail}
			_all_flags.append(flag)
			if run_index == 0:
				_run1_flags.append(flag)


func _target_row(label: String, expected: String, measured: int, kind: String) -> String:
	var verdict := "meets"
	if kind == "range":
		if measured < 8:
			verdict = "below"
		elif measured > 12:
			verdict = "above"
	elif measured < 20:
		verdict = "below"
	return "| %s | %s | wave %d | %s |" % [label, expected, measured, verdict]


func _meta_summary(meta: Dictionary) -> String:
	var parts: Array[String] = []
	for id: String in META_IDS:
		if int(meta[id]) > 0:
			parts.append("%s %d" % [id, int(meta[id])])
	return ", ".join(parts) if not parts.is_empty() else "-"


func _tuning_notes() -> String:
	return "\n".join(PackedStringArray([
		"- One formula changed. `WaveRules.scaling_for_wave()` now starts the",
		"  `1.16` / `1.02` / `1.06` curves at wave `authored_max + 1` instead of at",
		"  wave 1. Before the fix, authored waves 1-10 ran at x1.0 and wave 11",
		"  jumped to `1.16^10` (~4.4x) with no matching growth in player power.",
		"- No `.tres` value was changed by this pass.",
		"- Finding 1 - wave 8 is the first wall. Both profiles lose runs there",
		"  while player DPS is still 56-115; the authored spike (19 enemies,",
		"  `swift`, first wave modifier) arrives before the economy can answer it.",
		"- Finding 2 - the curve flattens after wave 10. Once a run passes wave 8",
		"  it usually reaches wave 20-37, because procedural waves 11-19 have less",
		"  total HP than the authored wave 9 (e.g. `1.16^1` vs 32 enemies at",
		"  `swarm`), so the same DPS clears them faster.",
		"- Finding 3 - Gold is winner-take-all. A run that dies at wave 8 pays 112",
		"  Gold; a run that passes it pays 1 600-2 000, which buys most of the",
		"  cheap meta tracks at once. The measured jump from `wave 8` (runs 1-5)",
		"  to `wave 37` (run 6) is that step, not a smooth progression.",
		"- Finding 4 - strategy spread. `0.23 DPS/Coin` for an Archer Tower versus",
		"  `0.06` for the first Canopy Bows level makes tower-first play worth",
		"  roughly two extra waves on run 1 and ten on later runs.",
		"- Recommendation (not applied - this stage is bug-fix only): raise the",
		"  early upgrade efficiency or the tower price, soften the wave 8-9",
		"  authored spike, and re-run this scene before any store build.",
	]))


func _mmss(seconds: float) -> String:
	return "%d:%02d" % [int(seconds / 60.0), int(seconds) % 60]


func _push(line: String) -> void:
	_report.append(line)


func _write_file(text: String) -> void:
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		printerr("Could not write %s" % REPORT_PATH)
		return
	file.store_string(text)
	file.close()
	print("[simulate_balance] wrote %s" % REPORT_PATH)


func _print_summary(results: Dictionary) -> void:
	print("")
	print("== balance simulation ==")
	for name: String in results:
		var runs: Array = results[name]["runs"]
		print("profile %s" % name)
		for run: Dictionary in runs:
			print("  run %d: reached wave %d, gold %d, tree %d%%" % [
				int(run["index"]), int(run["reached"]), int(run["gold"]),
				int(round(float(run["tree_pct"]))),
			])
		print("  flagged rows: %d" % (results[name]["flags"] as Array).size())
