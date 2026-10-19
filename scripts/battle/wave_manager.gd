class_name WaveManager
extends Node
## Wave state machine: PREPARE -> SPAWNING -> CLEARING -> PREPARE.
##
## Authored waves 1-9 come from `data/waves/waves_01_10.tres`; wave 10 and every
## tenth wave after it is a boss wave; everything else is generated from the
## master scaling formulas. Wave modifiers start at wave 8 and are deterministic
## per run seed. Every timer is a delta accumulator, never a SceneTreeTimer, so
## pause and time scale are safe.

signal state_changed(state: int)

## Emitted when a wave starts. `modifier` is a `WaveRules.Modifier` value and is
## always NONE on boss waves. The HUD turns it into a 1.5 s banner.
signal wave_announced(wave: int, modifier: int)

enum State { IDLE, PREPARE, SPAWNING, CLEARING }

const FIRST_PREP_SECONDS := 10.0
const BETWEEN_PREP_SECONDS := 6.0
const MAX_ALIVE := 70
const MAX_CALL_BONUS := 10
const BOSS_ID := "orc_warlord"
## Loaded in `setup()` instead of `preload`: WaveManager -> Boss -> Enemy ->
## Battle -> WaveManager is a script cycle, and a cyclic preload can yield an
## empty script when the battle scene is loaded outside the editor.
const BOSS_SCENE_PATH := "res://scenes/battle/Boss.tscn"

var _boss_scene: PackedScene

var _state := State.IDLE
var _wave := 0
var _cleared := 0
var _prep_remaining := 0.0
var _wave_time := 0.0
var _spawn_queue: Array[Dictionary] = []
var _spawn_cursor := 0
var _table: WaveTable
var _authored_max := 0
var _rng := RandomNumberGenerator.new()
var _last_angle := 0.0
var _pool: EnemyPool
var _battle: Battle
var _spawn_modifiers: Dictionary = {}
var _wave_modifier := WaveRules.Modifier.NONE
var _run_seed := 0
var _boss: Boss
var _boss_index := 0


## Injects the pool and Battle, loads the authored table once.
func setup(pool: EnemyPool, battle: Battle) -> void:
	_pool = pool
	_battle = battle
	_boss_scene = load(BOSS_SCENE_PATH) as PackedScene
	_table = ConfigDB.get_wave_table("main")
	if _table == null:
		push_warning("[WaveManager] no authored wave table, using procedural waves")
	else:
		_authored_max = _table.max_authored_wave()
	_rng.randomize()


## Begins a fresh run at wave 0 with the first preparation countdown.
## `run_seed` makes wave modifiers deterministic; 0 means "random seed".
func start(run_seed := 0) -> void:
	_run_seed = run_seed if run_seed != 0 else _rng.randi()
	_wave = 0
	_cleared = 0
	_prep_remaining = FIRST_PREP_SECONDS
	_wave_time = 0.0
	_spawn_queue.clear()
	_spawn_cursor = 0
	_last_angle = 0.0
	_boss = null
	_boss_index = 0
	_wave_modifier = WaveRules.Modifier.NONE
	_set_state(State.PREPARE)


## Stops all spawning for the rest of the run.
func stop() -> void:
	_spawn_queue.clear()
	_spawn_cursor = 0
	_prep_remaining = 0.0
	_boss = null
	_set_state(State.IDLE)


## Skips the remaining prep and grants floor(remaining / 2) Coins, capped at 10.
func call_wave_early() -> bool:
	if _state != State.PREPARE:
		return false
	var bonus := get_call_bonus()
	if bonus > 0 and _battle != null:
		_battle.add_coins(bonus)
	_begin_wave()
	return true


## Coins the player would gain by calling the wave right now.
func get_call_bonus() -> int:
	if _state != State.PREPARE:
		return 0
	return mini(MAX_CALL_BONUS, int(floor(_prep_remaining / 2.0)))


## Current state enum value.
func get_state() -> int:
	return _state


## True while the preparation countdown is running.
func is_preparing() -> bool:
	return _state == State.PREPARE


## Seconds left before the next wave, or 0 outside PREPARE.
func get_prep_remaining() -> float:
	return _prep_remaining if _state == State.PREPARE else 0.0


## Current wave number; 0 before wave 1.
func get_wave() -> int:
	return _wave


## Number of fully cleared waves.
func get_cleared_waves() -> int:
	return _cleared


## Enemies still waiting to spawn in the queue.
func get_queued_count() -> int:
	return maxi(0, _spawn_queue.size() - _spawn_cursor)


## Modifier of the current wave (`WaveRules.Modifier`).
func get_wave_modifier() -> int:
	return _wave_modifier


## Boss currently alive, or null.
func get_boss() -> Boss:
	return _boss


## Debug label for the current state.
func get_state_name() -> String:
	match _state:
		State.PREPARE:
			return "PREPARE"
		State.SPAWNING:
			return "SPAWNING"
		State.CLEARING:
			return "CLEARING"
		_:
			return "IDLE"


## Debug/test helper: jumps straight into `wave`. Debug builds only.
func debug_begin_wave(wave: int) -> void:
	if not OS.is_debug_build():
		return
	_wave = maxi(0, wave - 1)
	_cleared = _wave
	_prep_remaining = 0.0
	_wave_time = 0.0
	_begin_wave()


func _physics_process(delta: float) -> void:
	match _state:
		State.PREPARE:
			_prep_remaining -= delta
			if _prep_remaining <= 0.0:
				_begin_wave()
		State.SPAWNING:
			_wave_time += delta
			_spawn_due()
			if _spawn_cursor >= _spawn_queue.size() and _pool != null and _pool.count_present() == 0:
				_finish_wave()


func _begin_wave() -> void:
	_wave += 1
	_wave_time = 0.0
	_spawn_cursor = 0
	_wave_modifier = WaveRules.modifier_for(_wave, _run_seed)
	if WaveRules.is_boss_wave(_wave):
		_build_boss_wave(_wave)
	else:
		_build_queue(_wave)
	_set_state(State.SPAWNING)
	EventBus.wave_started.emit(_wave)
	wave_announced.emit(_wave, _wave_modifier)


func _finish_wave() -> void:
	_cleared = _wave
	_set_state(State.CLEARING)
	var reward := 10 + 2 * _wave
	if _battle != null:
		_battle.on_wave_cleared(_wave, reward, _wave_time)
	_prep_remaining = BETWEEN_PREP_SECONDS
	_set_state(State.PREPARE)


func _build_queue(wave: int) -> void:
	_spawn_queue.clear()
	_spawn_cursor = 0
	_wave_time = 0.0
	if _table != null and wave <= _authored_max:
		_build_authored(wave)
	if _spawn_queue.is_empty():
		_build_procedural(wave)
	_spawn_queue.sort_custom(_sort_by_time)


func _build_authored(wave: int) -> void:
	var count_mult := _count_multiplier()
	for entry: WaveEntry in _table.entries_for(wave):
		if entry == null or entry.count <= 0:
			continue
		var interval := maxf(0.15, entry.interval)
		var total := maxi(1, roundi(float(entry.count) * count_mult))
		for index in total:
			_spawn_queue.append({
				"time": entry.start_delay + float(index) * interval,
				"enemy_id": entry.enemy_id,
				"hp_mult": entry.hp_mult,
				"speed_mult": entry.speed_mult,
				"coin_mult": entry.coin_mult,
			})


func _build_procedural(wave: int) -> void:
	var scaling := WaveRules.scaling_for_wave(wave, _authored_max)
	var count := maxi(1, roundi((6.0 + float(wave) * 1.4) * _count_multiplier()))
	var interval := maxf(0.25, 1.1 - 0.02 * float(wave))
	for index in count:
		_spawn_queue.append({
			"time": float(index) * interval,
			"enemy_id": _pick_enemy_id(),
			"hp_mult": scaling["hp_mult"],
			"speed_mult": scaling["speed_mult"],
			"coin_mult": scaling["coin_mult"],
		})


func _build_boss_wave(wave: int) -> void:
	_spawn_queue.clear()
	_spawn_cursor = 0
	_boss_index = WaveRules.boss_index_for_wave(wave)
	var scaling := WaveRules.scaling_for_wave(wave, _authored_max)
	for entry: Dictionary in WaveRules.boss_wave_entries():
		var is_boss := bool(entry.get("is_boss", false))
		_spawn_queue.append({
			"time": float(entry.get("time", 0.0)),
			"enemy_id": str(entry.get("enemy_id", BOSS_ID)),
			"hp_mult": 1.0 if is_boss else scaling["hp_mult"],
			"speed_mult": scaling["speed_mult"],
			"coin_mult": scaling["coin_mult"],
			"is_boss": is_boss,
			"is_escort": bool(entry.get("is_escort", false)),
			"boss_index": _boss_index,
		})
	_spawn_queue.sort_custom(_sort_by_time)


func _pick_enemy_id() -> String:
	var roll := _rng.randf()
	if roll < 0.15:
		return "orc_brute"
	if roll < 0.45:
		return "orc_runner"
	return "orc_grunt"


func _spawn_due() -> void:
	while _spawn_cursor < _spawn_queue.size():
		var entry: Dictionary = _spawn_queue[_spawn_cursor]
		if float(entry.get("time", 0.0)) > _wave_time:
			break
		if not bool(entry.get("is_boss", false)) and _pool != null and _pool.count_present() >= MAX_ALIVE:
			break
		_spawn_cursor += 1
		_spawn_entry(entry)


func _spawn_entry(entry: Dictionary) -> void:
	var enemy_id := str(entry.get("enemy_id", ""))
	var enemy_data := ConfigDB.get_enemy(enemy_id)
	if enemy_data == null:
		push_warning("[WaveManager] unknown enemy id '%s'" % enemy_id)
		return
	if _pool == null:
		return

	var angle := _pick_angle()
	var spawn_position := Battle.CENTER + Vector2(cos(angle), sin(angle)) * Battle.SPAWN_RADIUS
	_fill_spawn_modifiers(entry)
	if bool(entry.get("is_boss", false)):
		_spawn_boss(enemy_data, spawn_position, entry)
		return
	if not bool(entry.get("is_escort", false)):
		_apply_wave_modifier()
	_pool.spawn(enemy_data, spawn_position, _spawn_modifiers)


func _spawn_boss(enemy_data: EnemyData, spawn_position: Vector2, entry: Dictionary) -> void:
	if _pool == null:
		return
	_spawn_modifiers["boss_index"] = int(entry.get("boss_index", 1))
	var boss := _pool.spawn_custom(_boss_scene, enemy_data, spawn_position, _spawn_modifiers) as Boss
	if boss == null:
		push_warning("[WaveManager] boss spawn failed")
		return
	_boss = boss
	EventBus.boss_spawned.emit(boss.boss_index)
	if _battle != null:
		_battle.on_boss_spawned(boss)


## Fills `_spawn_modifiers` from scratch for one spawn, so no key leaks between
## waves (for example the previous wave's armor multiplier).
func _fill_spawn_modifiers(entry: Dictionary) -> void:
	_spawn_modifiers["hp_mult"] = float(entry.get("hp_mult", 1.0))
	_spawn_modifiers["speed_mult"] = float(entry.get("speed_mult", 1.0))
	_spawn_modifiers["coin_mult"] = float(entry.get("coin_mult", 1.0))
	_spawn_modifiers["armor_mult"] = 1.0
	_spawn_modifiers["scale"] = 1.0
	_spawn_modifiers["modifier"] = ""
	_spawn_modifiers["spawn_delay"] = Enemy.SPAWN_TELEGRAPH


func _apply_wave_modifier() -> void:
	var extra := WaveRules.spawn_modifiers(_wave_modifier)
	if extra.is_empty():
		return
	if extra.has("hp_mult"):
		_spawn_modifiers["hp_mult"] = float(_spawn_modifiers["hp_mult"]) * float(extra["hp_mult"])
	if extra.has("speed_mult"):
		_spawn_modifiers["speed_mult"] = float(_spawn_modifiers["speed_mult"]) * float(extra["speed_mult"])
	if extra.has("armor_mult"):
		_spawn_modifiers["armor_mult"] = extra["armor_mult"]
	if extra.has("scale"):
		_spawn_modifiers["scale"] = extra["scale"]
	_spawn_modifiers["modifier"] = extra.get("modifier", "")


func _count_multiplier() -> float:
	return WaveRules.count_multiplier(_wave_modifier)


func _pick_angle() -> float:
	var angle := _rng.randf_range(0.0, TAU)
	var min_separation := deg_to_rad(8.0)
	var difference := wrapf(angle - _last_angle, -PI, PI)
	if absf(difference) < min_separation:
		var direction := 1.0 if difference >= 0.0 else -1.0
		angle = _last_angle + direction * min_separation
	angle = wrapf(angle, 0.0, TAU)
	_last_angle = angle
	return angle


func _set_state(new_state: int) -> void:
	_state = new_state
	state_changed.emit(_state)


func _sort_by_time(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("time", 0.0)) < float(b.get("time", 0.0))
