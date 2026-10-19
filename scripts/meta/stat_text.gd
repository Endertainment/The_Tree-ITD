class_name StatText
extends RefCounted
## Presentation helper for `StatModifier` entries and meta-upgrade tracks.
##
## The stat-key -> label mapping is UI text, not balance, so it lives in code
## next to the screens that render it. Magnitudes always come from data.

## Stat key -> localization key of its short label.
const STAT_LABELS := {
	"tree_hp_mult": "STAT_TREE_HP",
	"tree_regen_add": "STAT_TREE_REGEN",
	"archer_dmg_mult": "STAT_ARCHER_DMG",
	"archer_speed_mult": "STAT_ARCHER_SPEED",
	"archer_range_mult": "STAT_ARCHER_RANGE",
	"projectile_speed_mult": "STAT_PROJECTILE_SPEED",
	"coin_mult": "STAT_COIN_GAIN",
	"gold_mult": "STAT_GOLD_GAIN",
	"tower_cost_mult": "STAT_TOWER_COST",
	"slow_strength": "STAT_SLOW",
	"start_coins_add": "STAT_START_COINS",
	"start_archers_add": "STAT_START_ARCHERS",
}

## Stats whose value is a percentage of something rather than a flat number.
const PERCENT_STATS := [
	"tree_hp_mult",
	"archer_dmg_mult",
	"archer_speed_mult",
	"archer_range_mult",
	"projectile_speed_mult",
	"coin_mult",
	"gold_mult",
	"tower_cost_mult",
	"slow_strength",
]


## Localized label for `stat`, or the raw key when unknown.
static func label(stat: String) -> String:
	return Loc.t_key(str(STAT_LABELS.get(stat, stat)))


## True when `stat` is displayed as a percentage.
static func is_percent(stat: String) -> bool:
	return PERCENT_STATS.has(stat)


## Formats one value in the stat's own unit: `+20%`, `-2%`, `+20`, `+0.5/s`.
static func format_value(stat: String, value: float) -> String:
	var sign_text := "+" if value >= 0.0 else ""
	if is_percent(stat):
		return "%s%d%%" % [sign_text, roundi(value * 100.0)]
	if absf(value) < 0.05:
		return "0"
	var flat := ("%.1f" % value).trim_suffix(".0")
	if stat.ends_with("_add") and stat != "start_coins_add" and stat != "start_archers_add":
		return "%s%s/s" % [sign_text, flat]
	return "%s%s" % [sign_text, flat]


## One full line: `+20% Tree HP`.
static func describe(stat: String, _op: String, value: float) -> String:
	return "%s %s" % [format_value(stat, value), label(stat)]
