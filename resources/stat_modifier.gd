class_name StatModifier
extends Resource
## One data-driven stat change shipped by a card.
##
## `op` decides how the value accumulates in `RunModifiers`: `mult` adds into
## `value * (1 + sum_of_mults)`, `add` adds to a flat total. Balance values live
## in `data/cards/*.tres`, never in code.

## Stat key understood by `RunModifiers`, e.g. `tree_hp_mult` or `start_coins_add`.
@export var stat: String = ""

## `mult` for percentages, `add` for flat values.
@export_enum("mult", "add") var op: String = "mult"

## Magnitude. `0.2` means +20% for a `mult` entry, or +0.2 for an `add` entry.
@export var value: float = 0.0
