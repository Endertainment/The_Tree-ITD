class_name WaveEntry
extends Resource
## One spawn group inside a wave: `count` enemies of `enemy_id`, `interval`
## seconds apart, starting `start_delay` seconds after the wave begins.
##
## The authored file stores groups for waves 1-10 flat, each tagged with `wave`.

@export var wave: int = 1
@export var enemy_id: String = "orc_grunt"
@export var count: int = 5
@export var interval: float = 1.0
@export var start_delay: float = 0.0

## Per-group stat multipliers, applied on top of `EnemyData`.
@export var hp_mult: float = 1.0
@export var speed_mult: float = 1.0
@export var coin_mult: float = 1.0
