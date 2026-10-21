class_name Airship
extends Boss
## Oroch airship: the even-numbered boss (waves 20, 40, ...).
##
## Flies over the Tree, ignores towers on the way, bombs the Tree from above and
## keeps releasing wyvern riders. It never walks, so it overrides the whole
## movement/attack loop through `_custom_behaviour()`.

const HOVER_OFFSET := Vector2(0.0, -260.0)
const HOVER_DEADZONE := 6.0
const RIDER_ID := "wyvern_rider"
const RIDER_COUNT := 4
const RIDER_INTERVAL := 8.0
const RIDER_TELEGRAPH := 0.6

var _hover := Vector2.ZERO
var _bomb_timer := 0.0
var _rider_timer := 0.0


## Applies airship stats on top of the normal boss setup.
func setup(enemy_data: EnemyData, modifiers: Dictionary) -> void:
	super(enemy_data, modifiers)
	radius = enemy_data.radius
	var circle := _shape.shape as CircleShape2D
	if circle != null:
		circle.radius = radius
	_health.setup(
		WaveRules.airship_hp(boss_index),
		enemy_data.armor * float(modifiers.get("armor_mult", 1.0))
	)
	_status.set_slow_immune(0.0)
	z_index = 9
	_hover = Battle.CENTER + HOVER_OFFSET
	_bomb_timer = 1.2
	_rider_timer = RIDER_INTERVAL
	for _index in RIDER_COUNT:
		_spawn_rider()
	queue_redraw()


## The airship has no enrage and no threshold summons; riders are its pressure.
func _on_damaged(_dealt: float, _remaining: float) -> void:
	pass


## Own movement: drift to the hover point, bomb the Tree, release riders.
func _custom_behaviour(delta: float) -> bool:
	if global_position.distance_to(_hover) <= HOVER_DEADZONE:
		global_position = _hover
	else:
		global_position = global_position.move_toward(_hover, speed * delta)

	_bomb_timer -= delta
	if _bomb_timer <= 0.0:
		_bomb_timer = data.attack_cooldown
		if _battle != null and _battle.core != null and not _battle.core.is_dead():
			_battle.core.take_damage(data.damage)
		queue_redraw()

	_rider_timer -= delta
	if _rider_timer <= 0.0:
		_rider_timer = RIDER_INTERVAL
		_spawn_rider()
	return true


func _spawn_rider() -> void:
	if _pool == null:
		return
	var rider := ConfigDB.get_enemy(RIDER_ID)
	if rider == null:
		return
	var angle := randf_range(0.0, TAU)
	var at := global_position + Vector2(cos(angle), sin(angle)) * (radius + 26.0)
	_pool.spawn(rider, at, {
		"hp_mult": 1.0,
		"speed_mult": 1.0,
		"coin_mult": 1.0,
		"spawn_delay": RIDER_TELEGRAPH,
	})


func _draw() -> void:
	var body := data.color if data != null else Color("#4a3b2a")
	var accent := data.accent_color if data != null else Color("#8a2f22")
	# Balloon.
	draw_circle(Vector2(0.0, -radius * 0.55), radius * 0.95, body)
	draw_circle(Vector2(-radius * 0.3, -radius * 0.8), radius * 0.35, Color(1.0, 1.0, 1.0, 0.08))
	# Ropes and gondola.
	draw_line(Vector2(-radius * 0.5, -radius * 0.15), Vector2(-radius * 0.35, radius * 0.35), Color("#6b5a45"), 3.0)
	draw_line(Vector2(radius * 0.5, -radius * 0.15), Vector2(radius * 0.35, radius * 0.35), Color("#6b5a45"), 3.0)
	draw_rect(Rect2(-radius * 0.42, radius * 0.25, radius * 0.84, radius * 0.42), accent)
	draw_rect(Rect2(-radius * 0.28, radius * 0.34, radius * 0.56, radius * 0.16), Color("#2a1c12"))
	# Tail fins.
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-radius * 0.95, -radius * 0.5),
			Vector2(-radius * 1.3, -radius * 0.35),
			Vector2(-radius * 0.95, -radius * 0.2),
		]),
		accent
	)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(radius * 0.95, -radius * 0.5),
			Vector2(radius * 1.3, -radius * 0.35),
			Vector2(radius * 0.95, -radius * 0.2),
		]),
		accent
	)
