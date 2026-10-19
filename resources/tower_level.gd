class_name TowerLevel
extends Resource
## One upgrade level of a tower.
##
## Every number a tower needs for combat lives here, so balance can be tuned in
## `data/towers/*.tres` without touching code. Level 1 of a `TowerData` is the
## freshly built tower; each further entry is one upgrade.

## Damage per shot before the target's armor.
@export var damage: float = 10.0

## Seconds between shots.
@export var interval: float = 1.0

## Acquisition range in design pixels.
@export var range: float = 400.0

## Projectile travel speed in px/s.
@export var projectile_speed: float = 800.0

## Frost only: slow applied in this radius around the impact, 0 = single target.
@export var splash_radius: float = 0.0

## Frost only: slow strength as a fraction (0.35 = 35% slower).
@export_range(0.0, 0.9, 0.01) var slow_strength: float = 0.0
@export var slow_duration: float = 0.0

## Ballista only: bypass the target's armor.
@export var ignores_armor: bool = false


## Damage per second, used by the build card estimate.
func dps() -> float:
	if interval <= 0.0:
		return damage
	return damage / interval
