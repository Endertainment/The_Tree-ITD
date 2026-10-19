class_name Enemy
extends Area2D
## Pooled orc. Moves with custom steering, damages the Tree on contact and
## returns itself to `EnemyPool` after a short death effect.
##
## Node order matters: `_physics_process` moves first, then checks arrival. All
## timers are delta accumulators so pause and time scale behave correctly.

const SPAWN_TELEGRAPH := 0.6
const DEATH_EFFECT := 0.25
const ARRIVAL_HIT_DELAY := 0.15
const STUCK_SECONDS := 2.0
const STUCK_PROGRESS_PX := 6.0
const NUDGE_SECONDS := 0.45
const NUDGE_WEIGHT := 0.9
const SLOW_FLASH_SECONDS := 0.3
const HIT_FLASH_SECONDS := 0.06

var data: EnemyData
var speed := 0.0
var radius := 22.0
var coin_mult := 1.0
var is_alive := false
var is_dying := false

## False for non-pooled nodes such as the boss; `EnemyPool` frees those instead
## of returning them to the free list.
var pooled := true

## Incremented on every reuse. Arrows store it so a homing arrow cannot follow a
## recycled node that now represents a different orc.
var spawn_serial := 0

var _pool: EnemyPool
var _battle: Battle
var _base_speed := 0.0
var _enrage_mult := 1.0
var _modifier := ""
var _velocity := Vector2.ZERO
var _attacking := false
var _spawn_timer := 0.0
var _death_timer := 0.0
var _attack_timer := 0.0
var _time := 0.0
var _phase := 0.0
var _flash := 0.0
var _lunge := 0.0
var _neighbors: Array = []
var _obstacles: Array = []
var _best_distance := INF
var _no_progress := 0.0
var _nudge_time := 0.0
var _nudge_sign := 1.0
var _slow_flash := 0.0

@onready var _health: HealthComponent = %Health
@onready var _steering: SteeringComponent = %Steering
@onready var _status: StatusComponent = %Status
@onready var _shape: CollisionShape2D = %Shape
@onready var _puff: CPUParticles2D = %Puff


func _ready() -> void:
	_health.died.connect(_on_health_died)
	if _shape != null and _shape.shape != null:
		# The scene's sub-resource is shared by every pooled instance; give each
		# enemy its own CircleShape2D once, not once per spawn.
		_shape.shape = _shape.shape.duplicate()


## Injects the owning pool and scene. Called once when the pool is built.
func configure(pool: EnemyPool, battle: Battle) -> void:
	_pool = pool
	_battle = battle


## Applies data plus per-wave multipliers. The pool positions the node first.
## Recognised keys: `hp_mult`, `speed_mult`, `coin_mult`, `armor_mult`, `scale`,
## `spawn_delay`, `modifier` ("armored" / "swift" / "swarm") and `boss_index`.
func setup(enemy_data: EnemyData, modifiers: Dictionary) -> void:
	data = enemy_data
	var scale_mult := maxf(0.2, float(modifiers.get("scale", 1.0)))
	radius = data.radius * scale_mult
	_base_speed = maxf(1.0, data.speed * float(modifiers.get("speed_mult", 1.0)))
	_enrage_mult = 1.0
	speed = _base_speed
	coin_mult = float(modifiers.get("coin_mult", 1.0))
	_modifier = str(modifiers.get("modifier", ""))
	_health.setup(
		data.max_hp * float(modifiers.get("hp_mult", 1.0)),
		data.armor * float(modifiers.get("armor_mult", 1.0))
	)

	_steering.target_position = Battle.CENTER
	_steering.max_speed = speed
	_steering.separation_weight = data.separation_weight
	_status.clear()

	_velocity = Vector2.ZERO
	_attacking = false
	_spawn_timer = float(modifiers.get("spawn_delay", SPAWN_TELEGRAPH))
	_death_timer = 0.0
	_attack_timer = 0.0
	_time = 0.0
	_phase = randf() * TAU
	_flash = 0.0
	_lunge = 0.0
	_best_distance = INF
	_no_progress = 0.0
	_nudge_time = 0.0
	_nudge_sign = 1.0 if randf() < 0.5 else -1.0
	_slow_flash = 0.0
	is_alive = true
	is_dying = false
	spawn_serial += 1

	var circle := _shape.shape as CircleShape2D
	if circle != null:
		circle.radius = radius
	_shape.set_deferred("disabled", _spawn_timer > 0.0)
	_puff.color = data.color
	_puff.emitting = false
	queue_redraw()

## Called by the pool after all state is set, immediately before use.
func activate() -> void:
	visible = true
	set_physics_process(true)
	set_process(true)


## A spawn-telegraphing or dying enemy cannot be targeted.
func is_targetable() -> bool:
	return is_alive and not is_dying and _spawn_timer <= 0.0


## Identifies this incarnation of the pooled node.
func get_spawn_serial() -> int:
	return spawn_serial


## Shares the live obstacle list maintained by `TowerManager`. The array is
## rebuilt in place, so the reference stays valid for the whole run.
func set_obstacles(list: Array) -> void:
	_obstacles = list


## Applies a slow from a Frost Spire and flashes the snowflake marker.
## The strongest slow wins and reapplication only refreshes the duration.
func apply_slow(strength: float, duration: float) -> void:
	if not is_targetable() or strength <= 0.0 or duration <= 0.0:
		return
	_status.apply_slow(strength, duration)
	_slow_flash = SLOW_FLASH_SECONDS
	queue_redraw()


## Current slow multiplier, used by tests and the frost visual.
func get_slow_multiplier() -> float:
	return _status.slow_multiplier


## Current wave-modifier id ("armored", "swift", "swarm" or "").
func get_modifier_name() -> String:
	return _modifier


## Multiplies base speed for the boss enrage phase.
func apply_enrage(multiplier: float) -> void:
	_enrage_mult = maxf(1.0, multiplier)
	speed = _base_speed * _enrage_mult
	_steering.max_speed = speed


## Applies damage after armor. Ignore-armor is used by the Ballista later.
func take_damage(amount: float, ignore_armor := false) -> void:
	if not is_targetable():
		return
	var dealt := _health.apply_damage(amount, ignore_armor)
	if dealt <= 0.0:
		return
	_flash = 1.0
	if _battle != null:
		_battle.show_damage(self, dealt)
	queue_redraw()


## Runs the death flow, awards Coins and emits `enemy_died`.
func die() -> void:
	if is_dying or not is_alive:
		return
	is_alive = false
	is_dying = true
	_death_timer = DEATH_EFFECT
	_velocity = Vector2.ZERO
	_shape.set_deferred("disabled", true)

	var reward := maxi(1, roundi(float(data.coin_value) * coin_mult))
	if _battle != null:
		_battle.add_coins(reward)
	EventBus.enemy_died.emit(data.id, reward, global_position)

	if not GameState.is_low_quality():
		_puff.restart()
		_puff.emitting = true
	queue_redraw()


## Resets the node for the free list. Called by the pool, never by gameplay.
func despawn() -> void:
	is_alive = false
	is_dying = false
	_attacking = false
	_spawn_timer = 0.0
	_death_timer = 0.0
	_velocity = Vector2.ZERO
	_status.clear()
	_puff.emitting = false
	_shape.set_deferred("disabled", true)
	visible = false
	_enrage_mult = 1.0
	set_physics_process(false)
	set_process(false)


func get_health() -> HealthComponent:
	return _health


func _physics_process(delta: float) -> void:
	if is_dying:
		_death_timer -= delta
		if _death_timer <= 0.0 and _pool != null:
			_pool.release(self)
		return

	if not is_alive:
		return

	if _spawn_timer > 0.0:
		_spawn_timer -= delta
		queue_redraw()
		if _spawn_timer > 0.0:
			return
		_shape.set_deferred("disabled", false)
		EventBus.enemy_spawned.emit(data.id)
		queue_redraw()

	_status.tick(delta)

	if _attacking:
		_tick_attack(delta)
		return

	_time += delta
	_steering.max_speed = speed * _status.slow_multiplier
	if _pool != null:
		_pool.query_neighbors(global_position, _neighbors)

	_update_stuck(delta)
	var next_velocity := _steering.compute_velocity(
		global_position, _velocity, _neighbors, _obstacles, delta
	)
	next_velocity = _apply_weave(next_velocity)
	next_velocity = _apply_nudge(next_velocity)

	_velocity = next_velocity
	global_position += _velocity * delta
	if _velocity.length_squared() > 1.0:
		rotation = _velocity.angle()

	_check_arrival()


## Tracks progress toward the Tree and arms a short tangential nudge when an
## enemy is wedged between towers for too long.
func _update_stuck(delta: float) -> void:
	var distance := global_position.distance_to(Battle.CENTER)
	if distance < _best_distance - STUCK_PROGRESS_PX:
		_best_distance = distance
		_no_progress = 0.0
	else:
		_no_progress += delta

	if _no_progress >= STUCK_SECONDS and _nudge_time <= 0.0:
		_no_progress = 0.0
		_nudge_time = NUDGE_SECONDS
		_nudge_sign = -_nudge_sign
		_best_distance = distance
		if OS.is_debug_build() and data != null:
			push_warning("[Enemy] %s stalled at %s, nudging" % [data.id, global_position])

	if _nudge_time > 0.0:
		_nudge_time = maxf(0.0, _nudge_time - delta)


func _apply_nudge(next_velocity: Vector2) -> Vector2:
	if _nudge_time <= 0.0:
		return next_velocity
	var to_center := Battle.CENTER - global_position
	if to_center.length_squared() <= 0.0001:
		return next_velocity
	var tangent := Vector2(-to_center.y, to_center.x).normalized() * _nudge_sign
	var limit := speed * _status.slow_multiplier
	var nudged := next_velocity + tangent * limit * NUDGE_WEIGHT
	if nudged.length_squared() > limit * limit:
		nudged = nudged.normalized() * limit
	return nudged


func _apply_weave(next_velocity: Vector2) -> Vector2:
	if data == null or data.weave_amplitude <= 0.0:
		return next_velocity
	if next_velocity.length_squared() <= 1.0:
		return next_velocity
	var perpendicular := Vector2(-next_velocity.y, next_velocity.x).normalized()
	var weave := sin(_time * TAU * data.weave_frequency + _phase) * data.weave_amplitude
	var woven := next_velocity + perpendicular * weave
	var limit := speed * _status.slow_multiplier
	if woven.length_squared() > limit * limit:
		woven = woven.normalized() * limit
	return woven


func _check_arrival() -> void:
	var offset := global_position - Battle.CENTER
	var distance := offset.length()
	var contact := Battle.CORE_RADIUS + radius
	if distance > contact:
		return
	if distance <= 0.0001:
		offset = Vector2.RIGHT
	_attacking = true
	_velocity = Vector2.ZERO
	global_position = Battle.CENTER + offset.normalized() * contact
	_attack_timer = ARRIVAL_HIT_DELAY
	queue_redraw()


func _tick_attack(delta: float) -> void:
	_velocity = Vector2.ZERO
	_attack_timer -= delta
	if _attack_timer > 0.0:
		return
	_attack_timer = data.attack_cooldown
	_lunge = 1.0
	queue_redraw()
	if _battle != null and _battle.core != null and not _battle.core.is_dead():
		_battle.core.take_damage(data.damage)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta / HIT_FLASH_SECONDS)
		queue_redraw()
	if _lunge > 0.0:
		_lunge = maxf(0.0, _lunge - delta * 4.0)
		queue_redraw()
	if _slow_flash > 0.0:
		_slow_flash = maxf(0.0, _slow_flash - delta)
		queue_redraw()


func _on_health_died() -> void:
	die()


func _draw() -> void:
	if data == null:
		return
	if is_alive and _spawn_timer > 0.0:
		_draw_telegraph()
		return
	if not is_alive:
		return

	var body := data.color.lerp(Color.WHITE, _flash * 0.65)
	if _status.slow_multiplier < 0.999:
		body = body.lerp(Color("#7fc8e8"), 0.45)
	match _modifier:
		"armored":
			body = body.lerp(Color("#9aa0a6"), 0.5)
		"swift":
			body = body.lerp(Color("#e0c34a"), 0.3)
	var accent := data.accent_color.darkened(0.35)
	var offset := Vector2(radius * 0.3 * _lunge, 0.0)
	var low := GameState.is_low_quality()

	# Low quality keeps only the silhouette and its outline: one enemy drops
	# from ~12 immediate-mode primitives to 3, which is what makes the quality
	# toggle measurable in the BENCHMARK draw-call count.
	if low:
		draw_circle(offset, radius, body)
		draw_arc(offset, radius, 0.0, TAU, 16, accent, 3.0, true)
		return

	if _modifier == "swift":
		for index in 3:
			var trail_alpha := 0.2 * (1.0 - float(index) / 3.0)
			var trail_distance := radius * (1.25 + float(index) * 0.6)
			draw_circle(
				Vector2(-trail_distance, 0.0),
				radius * (0.62 - float(index) * 0.12),
				Color(0.88, 0.76, 0.29, trail_alpha)
			)

	if data.shape == "brute":
		draw_circle(offset + Vector2(-radius * 0.55, -radius * 0.35), radius * 0.45, body.darkened(0.12))
		draw_circle(offset + Vector2(radius * 0.55, -radius * 0.35), radius * 0.45, body.darkened(0.12))
	elif data.shape == "runner":
		draw_line(offset + Vector2(-radius * 0.9, 0.0), offset + Vector2(-radius * 1.8, 0.0), accent, 4.0)
		draw_line(offset + Vector2(-radius * 0.9, radius * 0.4), offset + Vector2(-radius * 1.5, radius * 0.8), accent, 3.0)

	draw_circle(offset + Vector2(0.0, 4.0), radius + 2.0, Color(0.02, 0.03, 0.02, 0.38))
	draw_circle(offset, radius, body)
	draw_arc(offset, radius, 0.0, TAU, 28, accent, 4.0, true)
	draw_arc(offset, radius - 4.0, PI * 1.05, PI * 1.55, 10, body.lightened(0.22), 3.0, true)

	var eye := Color(0.95, 0.9, 0.72)
	draw_circle(offset + Vector2(radius * 0.45, -radius * 0.3), radius * 0.14, eye)
	draw_circle(offset + Vector2(radius * 0.45, radius * 0.3), radius * 0.14, eye)

	if data.shape == "grunt" or data.shape == "brute":
		draw_line(
			offset + Vector2(radius * 0.35, radius * 0.55),
			offset + Vector2(radius * 0.75, radius * 0.82),
			eye.darkened(0.25), 4.0
		)
	if data.shape == "brute":
		draw_line(
			offset + Vector2(radius * 0.2, -radius * 0.75),
			offset + Vector2(radius * 0.55, -radius * 1.15),
			eye.darkened(0.3), 5.0
		)

	if _slow_flash > 0.0:
		_draw_snowflake(Vector2(0.0, -radius - 18.0))


## Small frost marker shown for a moment whenever a slow is applied.
func _draw_snowflake(at: Vector2) -> void:
	var alpha := clampf(_slow_flash / SLOW_FLASH_SECONDS, 0.0, 1.0)
	var color := Color(0.72, 0.92, 1.0, alpha)
	for arm in 3:
		var direction := Vector2.RIGHT.rotated(TAU * float(arm) / 3.0)
		draw_line(at - direction * 8.0, at + direction * 8.0, color, 2.0)


func _draw_telegraph() -> void:
	var progress := 1.0 - clampf(_spawn_timer / SPAWN_TELEGRAPH, 0.0, 1.0)
	var ring := radius * (0.6 + 0.8 * progress)
	draw_arc(Vector2.ZERO, ring, 0.0, TAU, 24, Color(0.949, 0.757, 0.306, 0.8), 3.0, true)
	draw_circle(Vector2.ZERO, radius * 0.3, Color(0.2, 0.3, 0.16, 0.35))
	# A few dust/leaf motes so the 0.6 s warning reads as a puff, not a UI ring.
	for index in 4:
		var angle := TAU * float(index) / 4.0 + progress * 0.8
		var distance := ring * (1.05 + 0.25 * progress)
		var mote := Vector2(cos(angle), sin(angle)) * distance
		draw_circle(mote, 3.0, Color(0.6, 0.62, 0.35, 0.7 * (1.0 - progress * 0.5)))
