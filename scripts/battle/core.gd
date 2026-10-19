class_name Core
extends Area2D
## The Life Tree. Owns its HP, damage flash, shake, HP bar and archer anchors.
##
## The Tree draws itself in `_draw()`; there is no sprite, so placeholder art
## needs no import step. The HP bar lerps toward the real value; the numeric
## readout lives in the HUD.

signal died

const BODY_RADIUS := 90.0
const HP_BAR_WIDTH := 240.0
const HP_BAR_HEIGHT := 20.0
const HP_BAR_TOP := Vector2(-120.0, -232.0)
const SHAKE_SECONDS := 0.12
const SHAKE_DISTANCE := 4.0
const REGEN_TICK := 0.25

var max_hp := 1000.0
var hp := 1000.0
var regen := 0.0

@onready var _archers: Node2D = %Archers
@onready var _leaf_puff: CPUParticles2D = %LeafPuff

var _display_hp := 1000.0
var _flash := 0.0
var _shake_time := 0.0
var _shake_offset := Vector2.ZERO
var _base_position := Vector2.ZERO
var _dead := false
var _regen_tick := 0.0
var _invuln := 0.0
var _pulse := 0.0


func _ready() -> void:
	_base_position = position
	_display_hp = hp
	queue_redraw()


## Resets HP for a new run. `new_max_hp` already includes meta modifiers.
func setup(new_max_hp: float) -> void:
	max_hp = maxf(1.0, new_max_hp)
	hp = max_hp
	_display_hp = hp
	regen = 0.0
	_flash = 0.0
	_shake_time = 0.0
	_regen_tick = 0.0
	position = _base_position
	_dead = false
	_invuln = 0.0
	_pulse = 0.0
	queue_redraw()


## Applies the run's live max HP and regeneration without resetting current HP.
func apply_stats(stats: RunStats) -> void:
	max_hp = maxf(1.0, stats.max_hp)
	hp = minf(hp, max_hp)
	_display_hp = minf(_display_hp, max_hp)
	regen = maxf(0.0, stats.regen)
	EventBus.core_damaged.emit(hp, max_hp)
	queue_redraw()


## Adds max HP and heals by `heal_amount` (Roots heals exactly what it adds).
func add_max_hp(amount: float, heal_amount: float) -> void:
	max_hp = maxf(1.0, max_hp + amount)
	hp = minf(max_hp, hp + maxf(0.0, heal_amount))
	EventBus.core_damaged.emit(hp, max_hp)
	queue_redraw()


## Applies contact damage. Ignore-armor does not apply to the Tree.
func take_damage(amount: float) -> void:
	if _dead or amount <= 0.0 or _invuln > 0.0:
		return
	hp = maxf(0.0, hp - amount)
	_flash = 1.0
	_regen_tick = 0.0
	if not GameState.is_low_quality():
		_shake_time = SHAKE_SECONDS
		var angle := randf_range(0.0, TAU)
		_shake_offset = Vector2(cos(angle), sin(angle)) * SHAKE_DISTANCE
		_leaf_puff.restart()
		_leaf_puff.emitting = true
	EventBus.core_damaged.emit(hp, max_hp)
	queue_redraw()
	if hp <= 0.0:
		_dead = true
		died.emit()
		EventBus.core_died.emit()


## Restores HP. Used by the revive flow.
func heal(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	hp = minf(max_hp, hp + amount)
	EventBus.core_damaged.emit(hp, max_hp)
	queue_redraw()


## Brings the Tree back after a defeat with `ratio` of its max HP.
func revive(ratio: float = 0.5) -> void:
	_dead = false
	hp = clampf(max_hp * clampf(ratio, 0.01, 1.0), 1.0, max_hp)
	_display_hp = hp
	_flash = 0.0
	_regen_tick = 0.0
	EventBus.core_damaged.emit(hp, max_hp)
	queue_redraw()


## Ignores all contact damage for `seconds`. Refreshed, never stacked.
func grant_invulnerability(seconds: float) -> void:
	_invuln = maxf(_invuln, maxf(0.0, seconds))
	_pulse = 0.0
	queue_redraw()


## True while the revive shield is active.
func is_invulnerable() -> bool:
	return _invuln > 0.0


## Drops the shield immediately. Used by tests and by a future debug command.
func clear_invulnerability() -> void:
	_invuln = 0.0
	queue_redraw()


## Small camera shake, used by the Ballista impact. `strength` scales duration.
func shake(strength: float = 1.0) -> void:
	if GameState.is_low_quality():
		return
	_shake_time = SHAKE_SECONDS * clampf(strength, 0.1, 3.0)
	var angle := randf_range(0.0, TAU)
	_shake_offset = Vector2(cos(angle), sin(angle)) * SHAKE_DISTANCE


## Current HP.
func get_hp() -> float:
	return hp


## Current regeneration in HP/s.
func get_regen() -> float:
	return regen


## Maximum HP for this run.
func get_max_hp() -> float:
	return max_hp


## True once HP reached 0.
func is_dead() -> bool:
	return _dead


## Global position of archer anchor `index` (0-based, up to 5).
func get_archer_anchor(index: int) -> Vector2:
	var marker := _archers.get_node_or_null("Anchor%d" % (index + 1)) as Node2D
	if marker == null:
		return global_position
	return marker.global_position


func _process(delta: float) -> void:
	var needs_redraw := false

	if _invuln > 0.0:
		_invuln = maxf(0.0, _invuln - delta)
		_pulse += delta
		needs_redraw = true

	if regen > 0.0 and not _dead and hp > 0.0 and hp < max_hp:
		_regen_tick += delta
		if _regen_tick >= REGEN_TICK:
			hp = minf(max_hp, hp + regen * _regen_tick)
			_regen_tick = 0.0
			EventBus.core_damaged.emit(hp, max_hp)
			needs_redraw = true

	if not is_equal_approx(_display_hp, hp):
		var speed := maxf(1.0, max_hp * 0.9)
		_display_hp = move_toward(_display_hp, hp, speed * delta)
		needs_redraw = true

	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 7.0)
		needs_redraw = true

	if _shake_time > 0.0:
		_shake_time = maxf(0.0, _shake_time - delta)
		position = _base_position + _shake_offset * (_shake_time / SHAKE_SECONDS)
		if _shake_time <= 0.0:
			position = _base_position

	if needs_redraw:
		queue_redraw()


func _draw() -> void:
	var leaf := Color("#3f7d3a").lerp(Color("#c0503a"), _flash * 0.6)
	var leaf_light := leaf.lightened(0.12)
	var leaf_dark := leaf.darkened(0.22)

	draw_circle(Vector2(0.0, 72.0), 108.0, Color(0.03, 0.05, 0.03, 0.4))

	# Trunk and roots.
	draw_rect(Rect2(-26.0, -16.0, 52.0, 148.0), Color("#5a3a22"))
	draw_line(Vector2(-18.0, 118.0), Vector2(-74.0, 150.0), Color("#4a2f1b"), 10.0)
	draw_line(Vector2(18.0, 118.0), Vector2(74.0, 150.0), Color("#4a2f1b"), 10.0)
	draw_line(Vector2(-20.0, 96.0), Vector2(-58.0, 126.0), Color("#4a2f1b"), 7.0)
	draw_line(Vector2(20.0, 96.0), Vector2(58.0, 126.0), Color("#4a2f1b"), 7.0)

	# Canopy.
	draw_circle(Vector2(0.0, -46.0), 96.0, leaf_dark)
	draw_circle(Vector2(-58.0, -92.0), 62.0, leaf)
	draw_circle(Vector2(58.0, -96.0), 64.0, leaf)
	draw_circle(Vector2(0.0, -132.0), 58.0, leaf_light)
	draw_circle(Vector2(-30.0, -60.0), 54.0, leaf_light)
	draw_circle(Vector2(34.0, -58.0), 52.0, leaf)

	# Light dapples.
	draw_circle(Vector2(-38.0, -112.0), 16.0, leaf_light.lightened(0.18))
	draw_circle(Vector2(44.0, -128.0), 13.0, leaf_light.lightened(0.14))
	draw_circle(Vector2(6.0, -78.0), 11.0, leaf_light.lightened(0.2))

	_draw_health_bar()
	if _invuln > 0.0:
		_draw_shield()


func _draw_shield() -> void:
	var alpha := 0.35 + 0.18 * sin(_pulse * 6.0)
	draw_circle(Vector2.ZERO, 176.0, Color(0.42, 0.78, 1.0, alpha * 0.18))
	draw_arc(
		Vector2.ZERO,
		190.0,
		0.0,
		TAU,
		64,
		Color(0.55, 0.86, 1.0, alpha),
		6.0,
		true
	)


func _draw_health_bar() -> void:
	var ratio := 0.0
	if max_hp > 0.0:
		ratio = clampf(_display_hp / max_hp, 0.0, 1.0)

	draw_rect(Rect2(HP_BAR_TOP, Vector2(HP_BAR_WIDTH, HP_BAR_HEIGHT)), Color(0.04, 0.06, 0.04, 0.85))
	if ratio > 0.0:
		var fill_color := Color("#7ec850").lerp(Color("#d95c4a"), 1.0 - ratio)
		draw_rect(
			Rect2(HP_BAR_TOP + Vector2(3.0, 3.0), Vector2((HP_BAR_WIDTH - 6.0) * ratio, HP_BAR_HEIGHT - 6.0)),
			fill_color
		)
	draw_rect(
		Rect2(HP_BAR_TOP, Vector2(HP_BAR_WIDTH, HP_BAR_HEIGHT)),
		Color("#e8d9a8"),
		false,
		2.0
	)
