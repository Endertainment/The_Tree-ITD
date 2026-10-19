# Economy

All numbers come from data resources (`data/*.tres`) and from the formulas in the
master context; this page only aggregates them. Estimates are arithmetic from
those formulas, **not** results of a balance simulation. Run time is the roughest
input: it assumes ~12 s of combat per wave plus the authored preparation timers
(10 s before wave 1, 6 s between waves).

## Currencies

| Currency | Scope | Earned from | Spent on | Persisted |
|---|---|---|---|---|
| **Coins** | one run | kills, wave clears, 120 starting Coins (+ meta) | towers, tower upgrades, in-run Tree/archer tracks | no |
| **Gold** | profile | run payout, daily missions, achievements, shop | eight permanent upgrade tracks | yes |
| **Gems** | profile | bosses, every 5 waves, wave-30 milestone, dailies, achievements, ads, shop | card unlocks, speed unlocks, shop | yes |

## Per-run sources

Formulas (all floored, never negative):

- **Gold** = `sum over cleared waves w of (8 + 2w)` × `gold_mult`, then the optional double-Gold ad.
- **Gems** = `2 * floor(waves / 5) + 5 * bosses` (+10 once at the wave-30 milestone).
- **Coins** = `120 + start_coins_add` + kills + `sum(10 + 2w)` wave clears.

Kill counts use the procedural spawn formula `6 + round(1.4 * wave)`; kill Coins
assume an average of 7 per orc (Grunt 6, Runner 7, Shaman 15, Brute 18, boss 150,
so this is conservative on brute-heavy waves).

| Cleared waves | Enemies | Kill Coins @7 | Wave-clear Coins | Run Coins | Gold | Gems | Est. run time | Gold/hour | Gems/hour |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 137 | 959 | 210 | ~1 290 | 190 | 9 | ~3 min | ~3 800 | ~180 |
| 20 | 414 | 2 898 | 620 | ~3 640 | 580 | 18 | ~6 min | ~5 800 | ~180 |
| 30 | 831 | 5 817 | 1 230 | ~7 170 | 1 170 | 37 | ~14 min | ~5 000 | ~159 |

With `gold_gain` maxed (+40%) the Gold/hour column becomes ~5 300 / ~8 100 /
~7 000. `coin_gain` (+3%/level) and `start_coins` (+20/level) raise the Coins
column by up to 30% and +200 respectively.

## In-run sinks (Coins)

Tower build costs: Archer 60, Frost 90, Ballista 140 (total 290 for one of each,
8 pads available). Tower upgrades cost `base * 1.6^level` (rounded to 5), e.g.
Archer 95 then 155. Selling refunds 60% of everything invested.

In-run upgrade tracks, total Coins to max:

| Track | Max level | Level 1 | Level max | Total to max |
|---|---:|---:|---:|---:|
| Roots | 5 | 70 | 310 | 840 |
| Regrowth | 5 | 90 | 455 | 1 190 |
| Canopy Bows | 8 | 80 | 845 | 2 745 |
| Elven Haste | 8 | 85 | 990 | 3 140 |
| Far Sight | 5 | 75 | 290 | 820 |
| Extra Archer | 3 | 400 | 2 025 | 3 325 |
| **All tracks** | | | | **12 060** |

A 20-wave run (~3 640 Coins) can max one or two tracks **or** build and upgrade
several towers — the intended either/or.

## Permanent Gold sinks

| Track | Effect per level | Max | Level 1 | Level max | Total |
|---|---|---:|---:|---:|---:|
| Tree Vitality (`tree_hp`) | +5% Tree HP | 10 | 150 | 7 745 | 21 555 |
| Tree Regeneration (`tree_regen`) | +0.5 HP/s | 10 | 180 | 9 295 | 25 865 |
| Archer Training (`archer_dmg`) | +4% archer damage | 10 | 200 | 10 330 | 28 750 |
| Elven Discipline (`archer_speed`) | +3% attack speed | 10 | 200 | 10 330 | 28 750 |
| Grove Treasury (`start_coins`) | +20 starting Coins | 10 | 120 | 4 615 | 13 600 |
| Tower Masonry (`tower_discount`) | −2% tower cost | 8 | 220 | 4 730 | 12 930 |
| Scavenger's Blessing (`coin_gain`) | +3% kill Coins | 10 | 240 | 12 395 | 34 490 |
| Golden Roots (`gold_gain`) | +4% run Gold | 10 | 260 | 13 425 | 37 365 |
| **All tracks** | | | | | **203 305** |

At ~5 800 Gold/hour, maxing every permanent track is roughly **35 hours** of
play; a single maxed track costs 12–37k, i.e. 2–6 hours. This is the long-term
sink that keeps Gold meaningful after cards are unlocked.

## Gem sinks

| Sink | Cost |
|---|---|
| Six card unlocks (150 / 150 / 200 / 250 / 300 / 400) | 1 450 total |
| 1.5x speed | 250 |
| 2x speed | 600 |
| Shop packs (consumables) | priced in cash below |
| **Non-shop total** | **2 300** |

At ~160–180 Gems/hour a dedicated player unlocks all cards in ~8–9 hours; with
dailies (15–45/day) and achievements (225 one-time) it is faster.

## Recurring and one-time bonuses

| Source | Reward | Cadence / cap |
|---|---|---|
| Daily missions | 3 × (80–250 Gold, 5–15 Gems) = 240–750 Gold, 15–45 Gems | per local day |
| Eight achievements | 5 000 Gold, 225 Gems total | one-time |
| Wave-30 milestone | +10 Gems | once per profile |
| Rewarded `free_gems` | +5 Gems | 4 h cooldown, max 3/day (stage 6) |
| Rewarded double Gold | +100% of the run's Gold | once per run (stage 6) |

## Shop value (fake prices)

| Product | Contents | Price | Value |
|---|---|---|---|
| `gems_100` | 100 Gems | $1.99 | ~50 Gems/$ |
| `gems_550` | 550 Gems | $4.99 | ~110 Gems/$ |
| `gems_1200` | 1 200 Gems | $9.99 | ~120 Gems/$ (best value badge) |
| `gems_2500` | 2 500 Gems | $19.99 | ~125 Gems/$ |
| `gold_5000` | 5 000 Gold | $1.99 | ~2 500 Gold/$ |
| `gold_25000` | 25 000 Gold | $7.99 | ~3 100 Gold/$ |
| `starter_bundle` | 300 Gems + 3 000 Gold | $2.99 | one-time |
| `remove_ads` | no interstitials | $3.99 | one-time |

A $9.99 gem pack buys about 2/3 of all card unlocks (1 200 of 1 450), which is
the intended "one purchase finishes the collection" feel. All products are fake
in this build; no money is charged.

## Time-to-goal summary

| Goal | Cost | Rough time (no purchases) |
|---|---|---|
| All six cards | 1 450 Gems | ~8–9 h of runs, less with dailies |
| Both speed unlocks | 850 Gems | ~5 h |
| One maxed permanent track | 12 000–37 000 Gold | 2–6 h |
| All permanent tracks | 203 305 Gold | ~35 h |
| Wave-30 milestone | 1 run | one strong run |

## Caveats

- The kill-Coin average of 7 ignores boss-heavy waves; a boss wave alone adds
  ~150 Coins plus its escort.
- Ad income is stage 6; no ad values are included in the per-hour table.
- Run-time estimates assume the player calls early waves promptly; idling in
  preparation lowers Gold/hour.
- Changing any number in `data/` invalidates these tables — regenerate them from
  the same formulas rather than editing this page by hand.
