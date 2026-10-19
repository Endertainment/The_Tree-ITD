class_name EnemyData
extends Resource
## Tunable stats for one enemy archetype.
##
## Balance numbers live in `data/enemies/*.tres`, never in gameplay code. The
## wave manager passes per-wave multipliers through `Enemy.setup()`; this
## resource always holds the base values.

## Stable id used by waves, saves and analytics.
@export var id: String = ""

## Localization key for the display name (not shown in stage 2).
@export var display_name_key: String = ""

@export var max_hp: float = 60.0
@export var speed: float = 55.0

## Damage per contact hit against the Tree.
@export var damage: float = 15.0
@export var armor: float = 0.0
@export var coin_value: int = 6

## Collision and visual radius in design pixels.
@export var radius: float = 22.0
@export var color: Color = Color("#6b8f3a")
@export var accent_color: Color = Color("#7a4a2b")

## 0.6 is the default crowd weight; the Brute uses 0.25 to push through.
@export_range(0.0, 1.5, 0.05) var separation_weight: float = 0.6

## Runner weave: lateral velocity offset in px/s and frequency in Hz.
@export var weave_amplitude: float = 0.0
@export var weave_frequency: float = 2.2

## Seconds between contact hits once the enemy reaches the Tree.
@export var attack_cooldown: float = 0.8

## Placeholder body silhouette: grunt, runner or brute.
@export_enum("grunt", "runner", "brute") var shape: String = "grunt"
