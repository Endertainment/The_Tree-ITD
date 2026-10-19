extends Node
## Global signal hub. Signals only: no state, no logic, no methods.


## An enemy died and awarded coins. Position is the death point for popups.
signal enemy_died(enemy_id: String, coin_value: int, position: Vector2)

## An enemy entered the arena.
signal enemy_spawned(enemy_id: String)

## A wave began. Wave numbers start at 1.
signal wave_started(wave: int)

## All enemies of a wave are dead.
signal wave_cleared(wave: int, time_taken: float)

## A boss entered the arena. Boss indices start at 1.
signal boss_spawned(boss_index: int)

## A boss was killed.
signal boss_died(boss_index: int)

## The Tree lost HP.
signal core_damaged(current_hp: float, max_hp: float)

## The Tree reached 0 HP.
signal core_died()

## In-run Coins changed.
signal coins_changed(amount: int)

## Meta Gold changed.
signal gold_changed(amount: int)

## Premium Gems changed.
signal gems_changed(amount: int)

## A battle run started.
signal run_started()

## A battle run ended. The payload is a RunSummary from stage 4 onward.
signal run_ended(summary)

## An in-run upgrade track was purchased or changed.
signal upgrade_purchased(track_id: String, level: int)

## A tower was built on a pad.
signal tower_built(tower_id: String)

## The game speed multiplier changed.
signal speed_changed(multiplier: float)

## An ad finished. `success` is false for every failure path.
signal ad_watched(placement: String, success: bool)

## An IAP transaction finished.
signal purchase_completed(product_id: String, success: bool)

## Mission or achievement progress changed.
signal mission_progress(mission_id: String, current: int, target: int)

## The active locale changed.
signal language_changed(locale: String)
