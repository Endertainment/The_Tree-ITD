class_name HealthComponent
extends Node
## Hit points and armor for one enemy.
##
## Damage is only applied here; the owner listens to `died` and runs its own
## death flow so pooled nodes never rely on `queue_free()`.

signal damaged(dealt: float, remaining: float)
signal died()

var max_hp := 1.0
var hp := 1.0
var armor := 0.0
var is_dead := false


## Resets the pool to `new_max_hp` and applies `new_armor`.
func setup(new_max_hp: float, new_armor: float = 0.0) -> void:
	max_hp = maxf(1.0, new_max_hp)
	hp = max_hp
	armor = maxf(0.0, new_armor)
	is_dead = false


## Applies `amount` after armor and returns the damage actually dealt.
func apply_damage(amount: float, ignore_armor := false) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var effective_armor := 0.0 if ignore_armor else armor
	var dealt := maxf(1.0, amount - effective_armor)
	hp = maxf(0.0, hp - dealt)
	damaged.emit(dealt, hp)
	if hp <= 0.0:
		is_dead = true
		died.emit()
	return dealt


## Restores HP without exceeding the maximum.
func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	hp = minf(max_hp, hp + amount)


## Current HP as a 0..1 ratio.
func ratio() -> float:
	if max_hp <= 0.0:
		return 0.0
	return hp / max_hp
