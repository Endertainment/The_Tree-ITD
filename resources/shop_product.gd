class_name ShopProduct
extends Resource
## One fake-IAP product (master context section 6.5).
##
## A product grants Gold, Gems, both (the starter bundle) or a permanent unlock.
## The price is a display string in the MVP; stage 6 replaces it with the store's
## localized price.

@export var id: String = ""

@export var title_key: String = ""
@export var description_key: String = ""

## Placeholder price, e.g. `$1.99`.
@export var price_text: String = "$0.99"

@export var gold_amount: int = 0
@export var gems_amount: int = 0

## False for one-time products that stay owned forever.
@export var consumable: bool = true

## Badge key (`SHOP_BADGE_BEST`, `SHOP_BADGE_ONE_TIME`) or empty.
@export var badge_key: String = ""

## Save unlock flag set on purchase (`remove_ads`), or empty.
@export var unlock_flag: String = ""

## Display order in the shop grid.
@export var order: int = 0


## True when this product can only ever be bought once.
func is_one_time() -> bool:
	return not consumable


## Human-readable contents for the card, using `Loc`.
func contents_text() -> String:
	if not unlock_flag.is_empty():
		return Loc.t_key(description_key)
	if gold_amount > 0 and gems_amount > 0:
		return Loc.t_key("SHOP_BUNDLE_CONTENTS", {
			"gems": Loc.format_number(gems_amount),
			"gold": Loc.format_number(gold_amount),
		})
	if gems_amount > 0:
		return Loc.t_key("SHOP_GEMS_CONTENTS", {"amount": Loc.format_number(gems_amount)})
	return Loc.t_key("SHOP_GOLD_CONTENTS", {"amount": Loc.format_number(gold_amount)})
