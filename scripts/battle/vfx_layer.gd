class_name VfxLayer
extends Node2D
## Pooled one-shot particle bursts for combat feedback.
##
## Eight `CPUParticles2D` emitters are created once and reconfigured per burst,
## so no node is allocated during a wave. Emitters inherit the tree's pause
## state, and the layer refuses to exceed `MAX_ALIVE_PARTICLES` at any time.
## On low quality every burst is halved and the decorative ones are dropped.

const MAX_EMITTERS := 8
const MAX_ALIVE_PARTICLES := 120
const DOT_SIZE := 16

var _emitters: Array[CPUParticles2D] = []
var _remaining: Array[float] = []
var _cursor := 0
var _alive := 0
var _dot: GradientTexture2D
var _fade: Gradient


func _ready() -> void:
	_dot = _build_dot_texture()
	_fade = _build_fade_gradient()
	for index in MAX_EMITTERS:
		_emitters.append(_make_emitter("Burst%d" % index))
		_remaining.append(0.0)


func _process(delta: float) -> void:
	for index in _emitters.size():
		if _remaining[index] <= 0.0:
			continue
		_remaining[index] = maxf(0.0, _remaining[index] - delta)
	_alive = _count_alive()


## Particles currently alive, derived from burst lifetimes (pause-safe).
func _count_alive() -> int:
	var alive := 0
	for index in _emitters.size():
		if _remaining[index] > 0.0:
			alive += _emitters[index].amount
	return alive


## White flash spark on an enemy that just took damage.
func hit_spark(at: Vector2) -> void:
	_burst(at, Color("#ffe9b0"), 3, 0.18, 70.0, 150.0, 180.0, Vector2.ZERO, 0.8, 1.6)


## Green/brown puff when an orc dies, tinted by the enemy colour.
func death_puff(at: Vector2, tint: Color) -> void:
	_burst(at, tint.darkened(0.12), 6, 0.32, 30.0, 95.0, 180.0, Vector2(0.0, -40.0), 1.4, 2.6)


## Golden sparkle rising off a killed enemy.
func coin_sparkle(at: Vector2) -> void:
	if GameState.is_low_quality():
		return
	_burst(at + Vector2(0.0, -16.0), Color("#f2c14e"), 5, 0.42, 30.0, 80.0, 60.0, Vector2(0.0, -150.0), 1.0, 2.0, Vector2.UP)


## Tiny dust kick where a projectile landed.
func arrow_dust(at: Vector2) -> void:
	_burst(at, Color("#8a7d5a"), 3, 0.22, 20.0, 60.0, 180.0, Vector2(0.0, 50.0), 1.0, 2.0)


## Leaf burst above the Tree when it takes damage.
func leaf_burst(at: Vector2) -> void:
	if GameState.is_low_quality():
		return
	_burst(at + Vector2(0.0, -80.0), Color("#6b9a4a"), 8, 0.5, 40.0, 120.0, 140.0, Vector2(0.0, 140.0), 1.6, 3.0)


## Arena dust ring used for boss summons and spawn telegraphs.
func ground_ring(at: Vector2, tint: Color) -> void:
	_burst(at, tint, 10, 0.4, 60.0, 130.0, 180.0, Vector2.ZERO, 1.2, 2.2)


## Number of particles currently alive across the pool (capped).
func get_alive_particles() -> int:
	return _alive


## Highest simultaneous burst the pool can hold.
func get_particle_cap() -> int:
	return MAX_ALIVE_PARTICLES


func _burst(
	at: Vector2,
	color: Color,
	amount: int,
	lifetime: float,
	speed_min: float,
	speed_max: float,
	spread: float,
	gravity: Vector2,
	scale_min: float,
	scale_max: float,
	direction := Vector2.UP
) -> void:
	if amount <= 0 or _emitters.is_empty():
		return
	if GameState.is_low_quality():
		amount = maxi(1, amount / 2)
	var allowed := MAX_ALIVE_PARTICLES - _alive
	if allowed <= 0:
		return
	amount = mini(amount, allowed)

	var index := _cursor
	_cursor = (_cursor + 1) % _emitters.size()
	var emitter := _emitters[index]

	emitter.global_position = at
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.direction = direction
	emitter.spread = spread
	emitter.gravity = gravity
	emitter.initial_velocity_min = speed_min
	emitter.initial_velocity_max = speed_max
	emitter.scale_amount_min = scale_min
	emitter.scale_amount_max = scale_max
	emitter.color = color
	emitter.restart()
	emitter.emitting = true
	_remaining[index] = lifetime + 0.05
	_alive = _count_alive()


func _make_emitter(emitter_name: String) -> CPUParticles2D:
	var emitter := CPUParticles2D.new()
	emitter.name = emitter_name
	emitter.emitting = false
	emitter.one_shot = true
	emitter.explosiveness = 1.0
	emitter.local_coords = false
	emitter.texture = _dot
	emitter.color_ramp = _fade
	emitter.z_index = 3
	add_child(emitter)
	return emitter


func _build_dot_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = DOT_SIZE
	texture.height = DOT_SIZE
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	return texture


func _build_fade_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	return gradient
