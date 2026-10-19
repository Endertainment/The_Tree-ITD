class_name CardData
extends Resource
## One collectible run modifier card.
##
## Stage 4 only needs the modifier payload so `RunModifiers` can consume equipped
## cards; the collection UI and the six `.tres` instances arrive in stage 5.
## Every entry in `modifiers` is `{stat: String, op: String, value: float}` where
## `op` is `"mult"` (additive percentage, applied as `1 + sum`) or `"add"`.

@export var id: String = ""
@export var name_key: String = ""
@export var description_key: String = ""

## Gems required to unlock the card. Zero for mission rewards.
@export var unlock_cost: int = 0

## `{stat, op, value}` entries consumed by `RunModifiers`.
@export var modifiers: Array[Dictionary] = []
