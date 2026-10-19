class_name SaveDefaults
extends RefCounted
## Canonical v1 save dictionary.
##
## Every consumer (SaveManager, GameState, the tests) starts from this one
## definition so there is a single source of truth for the schema in
## master context section 7.6.

const CURRENT_VERSION := 1


## Returns a fresh, fully populated save dictionary.
static func create() -> Dictionary:
	return {
		"version": CURRENT_VERSION,
		"created_at": int(Time.get_unix_time_from_system()),
		"last_seen": 0,
		"currencies": {
			"gold": 0,
			"gems": 0,
		},
		"upgrades": {
			"tree_hp": 0,
			"tree_regen": 0,
			"archer_dmg": 0,
			"archer_speed": 0,
			"start_coins": 0,
			"tower_discount": 0,
			"coin_gain": 0,
			"gold_gain": 0,
		},
		"cards": {
			"owned": [],
			"equipped": [],
		},
		"unlocks": {
			"speed_15": false,
			"speed_2": false,
			"remove_ads": false,
		},
		"stats": {
			"runs": 0,
			"best_wave": 0,
			"total_kills": 0,
			"bosses_killed": 0,
			"total_gold_earned": 0,
			"total_waves_cleared": 0,
			"towers_built": 0,
			"ads_watched": 0,
		},
		"missions": {
			"daily": {
				"date": "",
				"progress": {},
				"claimed": [],
			},
			"achievements": {
				"progress": {},
				"claimed": [],
			},
		},
		"settings": {
			"music": 0.8,
			"sfx": 1.0,
			"haptics": true,
			"locale": "en",
			"quality": "high",
			"show_damage_numbers": true,
		},
		"shop": {
			"owned_products": [],
		},
		"flags": {
			"tutorial_done": false,
			"milestone_30": false,
		},
	}
