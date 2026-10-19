class_name Tower
extends Area2D
## One built tower: level, targeting, cooldown and placeholder art.
##
## Towers are indestructible and never block projectiles; enemies only see them
## through `Battle.obstacles` (steering), never through physics.

enum TargetMode { NEAREST, STRONGEST, FIRST }

const RETARGET_SECONDS := 0.15
const UPGRADE_GROWTH := 1.6
const SELL_REFUND_RATIO := 0.6
const PRICE_STEP := 5

var data: TowerData
var level := 1
var invested := 0
var target_mode := TargetMode.NEAREST
var pad: BuildPad

var _battle: Battle
var _enemy_pool: EnemyPool
var _projectiles: TowerProjectilePool
var _target: Enemy
var _retarget_timer := 0.0
var _cooldown := 0.0
var _recoil := 0.0
var _pop := 1.0
var _aim := 0.0
var _selected := false

@onready var _shape: CollisionShape2D = $Shape
@onready var _snow: CPUParticles2D = $Snow


func _ready() -> void:
	monitoring = false
	monitorable = false
	if _shape != null and _shape.shape != null:
		_shape.shape = _shape.shape.duplicate()


## Injects the data and the run services. `price` is the Coins actually paid.
func setup(
	tower_data: TowerData,
	battle: Battle,
	enemy_pool: EnemyPool,
	projectiles: TowerProjectilePool,
	price: int
) -> void:
	data = tower_data
	_battle = battle
	_enemy_pool = enemy_pool
	_projectiles = projectiles
	invested = maxi(0, price)
	level = 1
	_target = null
	_retarget_timer = 0.0
	_recoil = 0.0
	_aim = 0.0
	_selected = false

	var stats := get_stats()
	# A fresh tower still has to wait out one interval before its first shot.
	_cooldown = stats.interval if stats != null else 0.0

	var circle := _shape.shape as CircleShape2D
	if circle != null:
		circle.radius = data.body_radius
	if _snow != null:
		_snow.emitting = false
	queue_redraw()


## Plays the scale pop used after building or upgrading.
func play_pop() -> void:
	_pop = 1.2
	scale = Vector2(_pop, _pop)


## Current level stats.
func get_stats() -> TowerLevel:
	return data.get_level_stats(level) if data != null else null


## Next level stats, or null at max level.
func get_next_stats() -> TowerLevel:
	if data == null or is_max_level():
		return null
	return data.get_level_stats(level + 1)


## Coins required for the next level, 0 at max level.
func get_upgrade_cost() -> int:
	if data == null or is_max_level():
		return 0
	return round_to_step(float(data.cost) * pow(UPGRADE_GROWTH, level), PRICE_STEP)


## Coins refunded on sell: 60% of build plus upgrades, rounded down.
func get_sell_refund() -> int:
	return int(floor(float(invested) * SELL_REFUND_RATIO))


## Build cost plus every upgrade paid so far.
func get_invested() -> int:
	return invested


## True at the highest authored level.
func is_max_level() -> bool:
	return data == null or level >= data.max_level()


## Body radius used for steering obstacles.
func get_body_radius() -> float:
	return data.body_radius if data != null else 32.0


## Raises the level once and adds the paid cost to the invested total.
func upgrade(paid_cost: int) -> void:
	if is_max_level():
		return
	level += 1
	invested += maxi(0, paid_cost)
	if _snow != null:
		_snow.emitting = level >= 3 and data.silhouette == "frost" and not GameState.is_low_quality()
	queue_redraw()
	play_pop()


## Toggles the golden selection outline.
func set_selected(selected_now: bool) -> void:
	if _selected == selected_now:
		return
	_selected = selected_now
	queue_redraw()


## Switches the targeting mode and re-acquires immediately.
func set_target_mode(mode: int) -> void:
	target_mode = clampi(mode, TargetMode.NEAREST, TargetMode.FIRST)
	_retarget_timer = 0.0


## Localization key of the current targeting mode.
func get_target_mode_key() -> String:
	match target_mode:
		TargetMode.STRONGEST:
			return "TOWER_TARGET_STRONGEST"
		TargetMode.FIRST:
			return "TOWER_TARGET_FIRST"
		_:
			return "TOWER_TARGET_NEAREST"


## Rounds a price to the nearest multiple of `step`.
static func round_to_step(value: float, step: int) -> int:
	if step <= 1:
		return roundi(value)
	return roundi(value / float(step)) * step


func _physics_process(delta: float) -> void:
	if data == null:
		return
	var stats := get_stats()
	if stats == null:
		return

	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = RETARGET_SECONDS
		_target = _acquire_target(stats.range)
	elif not _is_target_valid(stats.range):
		_target = null

	if _target != null:
		var wanted := (_target.global_position - global_position).angle()
		_aim = lerp_angle(_aim, wanted, clampf(delta * 10.0, 0.0, 1.0))
		if _cooldown <= 0.0:
			_fire(stats)

	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)


func _process(delta: float) -> void:
	if _recoil > 0.0:
		_recoil = maxf(0.0, _recoil - delta * 5.0)
		queue_redraw()
	if _pop > 1.0:
		_pop = maxf(1.0, _pop - delta * 1.2)
		scale = Vector2(_pop, _pop)
		if _pop <= 1.0:
			scale = Vector2.ONE


func _is_target_valid(attack_range: float) -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	if not _target.is_targetable():
		return false
	return global_position.distance_squared_to(_target.global_position) <= attack_range * attack_range


func _acquire_target(attack_range: float) -> Enemy:
	if _enemy_pool == null:
		return null
	var radius_sq := attack_range * attack_range
	var best: Enemy = null
	var best_score := INF
	for enemy: Enemy in _enemy_pool.get_active():
		if not enemy.is_targetable():
			continue
		var distance_sq := global_position.distance_squared_to(enemy.global_position)
		if distance_sq > radius_sq:
			continue
		var score: float = distance_sq
		match target_mode:
			TargetMode.STRONGEST:
				score = -enemy.get_health().max_hp
			TargetMode.FIRST:
				score = enemy.global_position.distance_squared_to(Battle.CENTER)
		if score < best_score:
			best_score = score
			best = enemy
	return best


func _fire(stats: TowerLevel) -> void:
	if _target == null or _projectiles == null:
		return
	if not _is_target_valid(stats.range):
		return
	var kind := _projectile_kind()
	_projectiles.spawn(global_position, _target, kind, stats, data.accent_color)
	_cooldown = maxf(0.1, stats.interval)
	_recoil = 1.0
	AudioManager.play_sfx("tower_fire")
	queue_redraw()


func _projectile_kind() -> int:
	match data.projectile:
		"frost_bolt":
			return TowerProjectile.Kind.FROST_BOLT
		"ballista_bolt":
			return TowerProjectile.Kind.BALLISTA_BOLT
		_:
			return TowerProjectile.Kind.ARROW


func _draw() -> void:
	if data == null:
		return
	var radius := data.body_radius
	var base := data.base_color
	var accent := data.accent_color

	draw_circle(Vector2(0.0, 10.0), radius + 3.0, Color(0.02, 0.03, 0.02, 0.4))
	draw_circle(Vector2.ZERO, radius, base.darkened(0.25))
	draw_arc(Vector2.ZERO, radius - 2.0, 0.0, TAU, 32, base.lightened(0.18), 3.0, true)

	match data.silhouette:
		"frost":
			_draw_frost(radius, base, accent)
		"ballista":
			_draw_ballista(radius, base, accent)
		_:
			_draw_archer(radius, base, accent)

	if level >= 2:
		draw_arc(Vector2.ZERO, radius * 0.74, 0.0, TAU, 28, Color(accent.r, accent.g, accent.b, 0.55), 2.0, true)
	if level >= 3:
		draw_arc(Vector2.ZERO, radius * 0.56, 0.0, TAU, 24, Color(accent.r, accent.g, accent.b, 0.75), 2.0, true)

	if _selected:
		draw_arc(Vector2.ZERO, radius + 10.0, 0.0, TAU, 40, Color("#f2c14e"), 3.0, true)


func _draw_archer(radius: float, base: Color, accent: Color) -> void:
	var height := 30.0 + float(level) * 10.0
	var width := radius * 0.7
	draw_rect(Rect2(-width * 0.5, -height, width, height), base.lightened(0.05))
	draw_rect(Rect2(-width * 0.5, -height, width, 4.0), base.darkened(0.35))
	draw_line(Vector2(0.0, -height), Vector2(0.0, -height - 16.0), Color("#5a3a22"), 3.0)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(1.0, -height - 14.0),
			Vector2(1.0, -height - 32.0),
			Vector2(20.0, -height - 23.0),
		]),
		Color("#7ec850")
	)
	if level >= 3:
		draw_rect(Rect2(-width * 0.5, -height - 6.0, width, 6.0), accent.darkened(0.2))
	draw_circle(Vector2(0.0, -radius * 0.15), radius * 0.32, base.darkened(0.15))


func _draw_frost(radius: float, base: Color, accent: Color) -> void:
	var height := 34.0 + float(level) * 14.0
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-radius * 0.62, 6.0),
			Vector2(radius * 0.62, 6.0),
			Vector2(0.0, -height),
		]),
		base.lightened(0.08)
	)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-radius * 0.62, 6.0),
			Vector2(0.0, 6.0),
			Vector2(0.0, -height),
		]),
		base.darkened(0.12)
	)
	var crystal := radius * 0.34
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(0.0, -height - crystal),
			Vector2(crystal * 0.7, -height - crystal * 0.2),
			Vector2(0.0, -height + crystal * 0.8),
			Vector2(-crystal * 0.7, -height - crystal * 0.2),
		]),
		accent
	)


func _draw_ballista(radius: float, base: Color, accent: Color) -> void:
	draw_rect(Rect2(-radius * 0.8, -6.0, radius * 1.6, 12.0), base.lightened(0.12))
	draw_rect(Rect2(-6.0, -10.0, 12.0, 26.0), base.darkened(0.2))
	var limb := radius * 1.05
	draw_line(Vector2(-limb, -limb * 0.72), Vector2(limb, -limb * 0.72), Color("#5a3a22"), 7.0)
	draw_line(Vector2(-limb, -limb * 0.72), Vector2(-limb * 0.35, -limb * 0.2), accent.darkened(0.3), 3.0)
	draw_line(Vector2(limb, -limb * 0.72), Vector2(limb * 0.35, -limb * 0.2), accent.darkened(0.3), 3.0)

	draw_set_transform(Vector2.ZERO, _aim, Vector2.ONE)
	var draw_back := radius * 0.2 * _recoil
	draw_line(Vector2(-14.0 - draw_back, -radius * 0.9), Vector2(30.0 - draw_back, -radius * 0.9), Color("#2a1d12"), 7.0)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(30.0 - draw_back, -radius * 0.9),
			Vector2(16.0 - draw_back, -radius * 0.9 - 8.0),
			Vector2(16.0 - draw_back, -radius * 0.9 + 8.0),
		]),
		accent
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
