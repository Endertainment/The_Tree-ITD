class_name Boss
extends Enemy
## Orc Warlord: a one-off, non-pooled enemy with an HP bar, two summon
## thresholds, a 3 s opening slow immunity and an enrage phase below 30% HP.
##
## The scene inherits `Enemy.tscn`, so Health/Steering/Status/Shape/Puff are the
## same components; only stats, behaviour and art differ.

signal enraged

const SLOW_IMMUNITY := 3.0
const SUMMON_THRESHOLDS: Array[float] = [0.7, 0.4]
const SUMMON_COUNT := 4
const SUMMON_TELEGRAPH := 0.6
const ENRAGE_RATIO := 0.3
const ENRAGE_MULT := 1.3
const BOSS_RADIUS := 70.0

var boss_index := 1

var _thresholds_fired: Array[float] = []
var _enraged := false
var _death_announced := false
var _summon_hp_mult := 1.0
var _aura := 0.0


func _ready() -> void:
	super()
	_health.damaged.connect(_on_damaged)


## Applies boss stats on top of the normal enemy setup.
func setup(enemy_data: EnemyData, modifiers: Dictionary) -> void:
	boss_index = maxi(1, int(modifiers.get("boss_index", 1)))
	_summon_hp_mult = float(modifiers.get("hp_mult", 1.0))
	super(enemy_data, modifiers)

	radius = BOSS_RADIUS
	var circle := _shape.shape as CircleShape2D
	if circle != null:
		circle.radius = radius
	_health.setup(
		WaveRules.boss_hp(boss_index),
		enemy_data.armor * float(modifiers.get("armor_mult", 1.0))
	)
	_status.set_slow_immune(SLOW_IMMUNITY)
	_thresholds_fired.clear()
	_enraged = false
	_death_announced = false
	_aura = 0.0
	queue_redraw()


## True once the enrage phase started.
func is_enraged() -> bool:
	return _enraged


## Current HP ratio for the boss bar.
func get_hp_ratio() -> float:
	return _health.ratio()


## Emits `boss_died` after the normal coin award and death flow.
func die() -> void:
	if is_dying or not is_alive:
		return
	super()
	if not _death_announced:
		_death_announced = true
		EventBus.boss_died.emit(boss_index)


func _on_damaged(_dealt: float, _remaining: float) -> void:
	var ratio := _health.ratio()
	for threshold: float in SUMMON_THRESHOLDS:
		if ratio <= threshold and not _thresholds_fired.has(threshold):
			_thresholds_fired.append(threshold)
			_summon_runners()
	if ratio < ENRAGE_RATIO and not _enraged:
		_enraged = true
		apply_enrage(ENRAGE_MULT)
		_aura = 0.0
		enraged.emit()
		AudioManager.play_sfx("boss_roar")
		queue_redraw()


func _summon_runners() -> void:
	var runner := ConfigDB.get_enemy("orc_runner")
	if _pool == null or runner == null:
		return
	for index in SUMMON_COUNT:
		var angle := TAU * float(index) / float(SUMMON_COUNT) + randf_range(-0.2, 0.2)
		var spawn_position := global_position + Vector2(cos(angle), sin(angle)) * (radius + 30.0)
		_pool.spawn(runner, spawn_position, {
			"spawn_delay": SUMMON_TELEGRAPH,
			"hp_mult": _summon_hp_mult,
			"speed_mult": 1.0,
			"coin_mult": 1.0,
		})
	AudioManager.play_sfx("boss_summon")


func _process(delta: float) -> void:
	super(delta)
	if _enraged:
		_aura += delta
		queue_redraw()


func _draw() -> void:
	if data == null:
		return
	if is_alive and _spawn_timer > 0.0:
		_draw_telegraph()
		return
	if not is_alive:
		return

	var body := data.color.lerp(Color.WHITE, _flash * 0.5)
	var accent := data.accent_color
	if _enraged:
		var pulse := 0.5 + 0.5 * sin(_aura * 7.0)
		draw_circle(Vector2.ZERO, radius + 16.0 + pulse * 6.0, Color(0.85, 0.2, 0.15, 0.14 + pulse * 0.1))

	draw_circle(Vector2(0.0, 12.0), radius + 2.0, Color(0.02, 0.03, 0.02, 0.45))
	draw_circle(Vector2.ZERO, radius, body)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, accent, 6.0, true)

	# Horns.
	var horn := accent.darkened(0.1)
	draw_line(Vector2(-radius * 0.55, -radius * 0.66), Vector2(-radius * 1.02, -radius * 1.32), horn, 11.0)
	draw_line(Vector2(radius * 0.55, -radius * 0.66), Vector2(radius * 1.02, -radius * 1.32), horn, 11.0)
	draw_line(Vector2(-radius * 0.2, -radius * 0.9), Vector2(-radius * 0.34, -radius * 1.3), horn, 7.0)
	draw_line(Vector2(radius * 0.2, -radius * 0.9), Vector2(radius * 0.34, -radius * 1.3), horn, 7.0)

	# Eyes and tusks.
	var eye := Color(0.98, 0.86, 0.62) if not _enraged else Color(1.0, 0.4, 0.25)
	draw_circle(Vector2(radius * 0.34, -radius * 0.18), radius * 0.1, eye)
	draw_circle(Vector2(radius * 0.62, -radius * 0.12), radius * 0.1, eye)
	draw_line(
		Vector2(radius * 0.2, radius * 0.42),
		Vector2(radius * 0.52, radius * 0.66),
		Color("#e8d9a8"),
		5.0
	)
	draw_line(
		Vector2(radius * 0.52, radius * 0.42),
		Vector2(radius * 0.78, radius * 0.6),
		Color("#e8d9a8"),
		5.0
	)

	if _status.slow_multiplier < 0.999:
		draw_arc(Vector2.ZERO, radius + 6.0, 0.0, TAU, 40, Color(0.72, 0.92, 1.0, 0.6), 4.0, true)
