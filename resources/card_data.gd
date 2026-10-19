class_name CardData
extends Resource
## One collectible run-modifier card (master context section 6.3).
##
## The modifiers are plain `StatModifier` resources consumed by `RunModifiers`;
## battle code never branches on a card id. Card names, lore and prices live in
## `data/cards/*.tres`.

@export var id: String = ""

@export var name_key: String = ""
@export var description_key: String = ""

## Flavour line shown in the card detail popup.
@export var lore_key: String = ""

## Gems required to unlock the card. Zero for mission rewards.
@export var unlock_cost: int = 0

## Placeholder card tint while there is no final art.
@export var tint: Color = Color(0.494118, 0.784314, 0.313726, 1)

## Stat changes applied at run start.
@export var modifiers: Array[StatModifier] = []


## Human-readable modifier lines, e.g. "+20% Tree HP".
func modifier_lines() -> Array[String]:
	var lines: Array[String] = []
	for modifier: StatModifier in modifiers:
		if modifier == null:
			continue
		lines.append(StatText.describe(modifier.stat, modifier.op, modifier.value))
	return lines
