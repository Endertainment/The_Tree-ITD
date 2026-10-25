# Autoplay balance report — 21.10.2026

20 real runs of `Battle.tscn` in headless Godot 4.7.2, driven by a scripted
player (not the analytical model in `simulate_balance.gd`). The run is
time-scaled ×12 to keep the pass short; physics stays at 60 Hz.

## Method

- The autoplayer builds eight towers in a fixed order
  (`archer, archer, spirit, archer, ballista, spirit, ballista, archer`),
  upgrades the cheapest tower when it has 120 Coins spare, buys in-run tracks
  once all pads are full (keeping a 260-Coin reserve), and always calls the next
  wave early.
- Between runs it grants the real `Results.compute_gold()` payout through
  `GameState.apply_run_result()` and spends all Gold cheapest-first on the eight
  meta tracks, so run 20 has real meta progression behind it.
- No cards are equipped (they cost Gems), no targeting micro, no pause.
- A run is capped at 15 game minutes; no run reached the cap.

## Results

| Run | Wave | Kills | Coins left | Gold | Seconds |
|---:|---:|---:|---:|---:|---:|
| 1 | 16 | 316 | 369 | 400 | 376 |
| 2 | 18 | 440 | 407 | 486 | 500 |
| 3 | 17 | 388 | 385 | 442 | 434 |
| 4 | 18 | 404 | 328 | 486 | 461 |
| 5 | 17 | 342 | 350 | 442 | 395 |
| 6 | 16 | 357 | 383 | 416 | 406 |
| 7 | 9 | 132 | 174 | 168 | 172 |
| 8 | 17 | 344 | 377 | 459 | 385 |
| 9 | 18 | 377 | 471 | 505 | 433 |
| 10 | 17 | 365 | 411 | 459 | 415 |
| 11 | 18 | 408 | 407 | 505 | 448 |
| 12 | 16 | 321 | 464 | 416 | 358 |
| 13 | 18 | 431 | 429 | 524 | 466 |
| 14 | 17 | 372 | 398 | 477 | 422 |
| 15 | 18 | 389 | 399 | 524 | 437 |
| 16 | 19 | 421 | 384 | 574 | 467 |
| 17 | 17 | 355 | 459 | 477 | 400 |
| 18 | 17 | 373 | 341 | 477 | 414 |
| 19 | 18 | 394 | 386 | 524 | 437 |
| 20 | 18 | 402 | 204 | 524 | 460 |

- **Max wave 19, median 17, mean 16.9.**
- **15 of 20 runs died on waves 17–18.** Only run 16 reached wave 20 and died
  there, after killing five airship riders.
- Deaths by wave: `9: 1, 16: 3, 17: 7, 18: 8, 19: 1`.
- Total Gold earned: **9 285** (~464 per run).

## Progression after 20 runs

| Track | Level |
|---|---:|
| `tree_hp` | 4 |
| `start_coins` | 5 |
| `tree_regen` | 3 |
| `archer_dmg` | 3 |
| `archer_speed` | 3 |
| `coin_gain` | 3 |
| `tower_discount` | 3 |
| `gold_gain` | 2 |

That is roughly **+12 % archer damage, +9 % attack speed, +20 % Tree HP** over
20 full runs — while procedural waves scale `1.16^step` HP, about ×3.3 by wave 18.
The meta layer cannot keep up with the wave curve.

## Where the run breaks

Wave clear time (median, seconds) rises steadily and then saturates the arena:

| Wave | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Seconds | 23.7 | 26.0 | 28.4 | 28.4 | 31.2 | 32.2 | 35.6 | 39.2 |

By wave 17–18 a wave takes 35–39 s against a 70-alive cap, so the arena is
effectively full and the Tree takes continuous contact damage.

Other observations:

- **Coins are idle at death**: median **386** unspent Coins. All eight pads are
  full and the towers are at max level, so there is nothing left to buy — the
  build has a hard power ceiling.
- **New units carry the wall**: from wave 11 the procedural pool mixes
  `orc_thrower` (541 kills), `orc_raider` (406), `orc_mage` (361) and
  `orc_shaman` (242). Their combined pressure is what the 17–18 wall is made of.
- **Late units are almost invisible**: wyvern riders appeared only as airship
  summons (5 kills) and `orc_ram` / `orc_trebuchet` never spawned at all.
- **Boss 1 is a speed bump**: wave 10 clear time is 29 s, only ~9 s longer than
  wave 9, and the Warlord dies in essentially every run that reaches it.
- **Boss 2 is almost unseen**: only run 16 reached wave 20; the airship was not
  killed.
- **Variance**: run 7 died at wave 9 with normal clear times (18–20 s), so this
  is composition/modifier variance, not a slow wave. Wave 8–9 carries the first
  wave modifier and is the only sub-16 death.

## Recommendations (highest impact first)

1. **Flatten the procedural curve.**
   - `WaveRules.scaling_for_wave`: HP `1.16` → **`1.12`**, coin `1.06` → **`1.08`**.
   - `WaveManager._build_procedural`: count `6 + 1.4·wave` → **`5 + 1.0·wave`**;
     spawn interval floor `0.25` → **`0.55`**.
   - Target: median wave **25+** after 20 runs instead of 17.

2. **Make meta progression visible.** With 464 Gold per run and `1.55^level`
   costs, level 5 of one track already costs 800+ Gold.
   - Cost growth `1.55` → **`1.40`**.
   - Per level: `archer_dmg` 4 % → **7 %**, `archer_speed` 3 % → **5 %**,
     `tree_hp` 5 % → **8 %**, `start_coins` +20 → **+30**, `gold_gain` 4 % → **6 %**.
   - Target: a level-6–8 profile after 20 runs.

3. **Give Coins a late sink.** ~386 Coins are idle at death every run.
   - Add a fourth tower level, or a repeatable in-run "tower damage" track, so
     the ~400 Coins can still buy power.

4. **Tune the new units that form the wall.**
   - `orc_shaman`: heal 8 → **5** per pulse, interval 1.5 s → **2.0 s**.
   - `orc_thrower` / `orc_mage`: range 320/340 → **300/320**, so they sit deeper
     inside tower coverage.
   - Watch `swarm` at waves 8–10; consider `1.4` → **`1.25`** count multiplier.

5. **Bring the late content forward** once the curve is fixed:
   `wyvern_rider` 22 → **16**, `orc_ram` 22 → **18**, `orc_trebuchet` 22 → **20**,
   and trim the trebuchet (damage 45 → 35, range 560 → 540) because only the
   Ballista can answer it.

6. **Make boss 2 reachable.** With fixes 1–2 a median player should reach wave 20;
   if not, move the airship to wave 15 rather than leaving it unplayable.

## Caveats

- The autoplayer is competent but not optimal: fixed build order, no cards, no
  manual targeting, no pause, and it calls every wave immediately (it takes the
  +5 Coin bonus but gives up preparation time).
- Time scale ×12 slightly changes combat fidelity: projectiles and contact
  damage resolve in 0.2 s steps instead of 1/60 s.
- Absolute wave numbers may move by ±2 for a human player, but the shape of the
  curve — a hard 17–18 wall and a meta layer that cannot answer it — is solid.

## Applied in this pass (2026-10-25)

- `WaveRules.scaling_for_wave`: HP ×1.16 → ×1.12, coin ×1.06 → ×1.08.
- `WaveManager._build_procedural`: `5 + 1.0·wave` enemies, spawn interval floor 0.55 s.
- `WaveRules.count_multiplier`: Swarm +40 % → +25 % count.
- Meta tracks: cost growth 1.55 → 1.40; `archer_dmg` 4 % → 7 %, `archer_speed`
  3 % → 5 %, `tree_hp` 5 % → 8 %, `start_coins` +20 → +30, `gold_gain` 4 % → 6 %.
- Units: shaman heals 5 HP / 2.0 s, thrower range 300, mage range 320, trebuchet
  35 damage / 540 range.
- Late units join earlier: wyvern at 16, ram at 18, trebuchet at 20.
- Coin sink: archer / spirit / ballista get a level 4 (L3→L4 costs 245 / 370 / 575).
- Tests updated; all 14 scenes still green.
