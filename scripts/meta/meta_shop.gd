class_name MetaShop
extends RefCounted
## Grants shop products exactly once.
##
## Kept out of `ShopScreen` so the "never grant twice" rule is testable headless:
## every call checks the owned list and the unlock flag before adding anything.

## Grants `product_id`. Returns false when the product is unknown, already
## owned (one-time only) or when the unlock flag is already set.
static func grant(product_id: String) -> bool:
	var product := ConfigDB.get_product(product_id)
	if product == null:
		return false
	if product.is_one_time() and GameState.is_product_owned(product_id):
		return false
	if not product.unlock_flag.is_empty() and GameState.is_unlocked(product.unlock_flag):
		return false

	if product.gold_amount > 0:
		GameState.add_gold(product.gold_amount)
	if product.gems_amount > 0:
		GameState.add_gems(product.gems_amount)
	if not product.unlock_flag.is_empty():
		GameState.unlock(product.unlock_flag, true)
	if product.is_one_time():
		GameState.own_product(product_id)
	SaveManager.save_now(GameState.to_dict())
	Analytics.log_event("product_granted", {
		"product_id": product_id,
		"gold": product.gold_amount,
		"gems": product.gems_amount,
	})
	return true


## Re-applies permanent unlocks for every owned product (store restore path).
## Returns how many unlocks were missing. Never re-grants currency.
static func restore_owned() -> int:
	var restored := 0
	for id: String in GameState.get_owned_products():
		var product := ConfigDB.get_product(id)
		if product == null or product.unlock_flag.is_empty():
			continue
		if GameState.is_unlocked(product.unlock_flag):
			continue
		GameState.unlock(product.unlock_flag, true)
		restored += 1
	SaveManager.save_now(GameState.to_dict())
	return restored
