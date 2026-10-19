# Architecture (one page)

## Scene flow

```
Boot.tscn ──0.8 s──▶ MainMenu.tscn ──BATTLE──▶ Battle.tscn
                                                  │
                                   defeat / quit  │
                                                  ▼
                        MainMenu.tscn ◀── Results.tscn
```

`SceneRouter.goto(path)` fades out (0.2 s), calls `change_scene_to_file`, fades
in. The fade overlay lives on a `CanvasLayer` owned by the autoload, so it
survives the swap. Navigation is ignored while a transition is running and when
the requested path is already the current scene. `goto_with_payload(path, data)`
stores a one-shot payload which the next scene takes with `consume_payload()`;
the battle uses it to hand its `RunSummary` to Results without a global.

Boot is the only place that reads the save: load → `GameState.from_dict` →
`Loc.set_locale` → `AudioManager.apply_settings` → wait → route. A debug build
with `--debug-battle` routes straight to `Battle.tscn`.

## Autoloads (order matters)

| # | Name | Responsibility | Never does |
|---|---|---|---|
| 1 | `EventBus` | Signals only | Hold state or logic |
| 2 | `SaveManager` | JSON I/O, migration call, atomic write, backup, corruption recovery | Touch `GameState` |
| 3 | `GameState` | Canonical save dict + typed accessors, cards/missions/shop APIs, owns `MissionTracker` | Hold run state (Coins, waves) |
| 4 | `ConfigDB` | `id -> Resource` maps for all data folders | Own balance numbers |
| 5 | `AudioManager` | Music/SFX/UI buses, pooling, volume persistence | Know about gameplay |
| 6 | `Loc` | Runtime `Translation` objects, locale switch, number formatting | Format currency rules |
| 7 | `SceneRouter` | Fade transitions, double-navigation guard | Own screen logic |
| 8 | `SpeedService` | `Engine.time_scale` with unlock checks | Change time scale while paused |
| 9 | `Monetization` | Ads/IAP facade over provider interfaces | Import SDKs into gameplay |
| 10 | `Analytics` | Debug-only event logging | Ship an SDK |

Autoloads never `get_node()` each other's children. They talk through
`EventBus` signals or direct singleton calls.

## Battle scene

```
Battle (battle.gd: coins, kills, pause, RunStats, RunSummary, results hand-off)
├── Arena            static _draw() backdrop, boundary, roots, stones
├── TowerManager     pads, towers, obstacles, selection, range ring
│   ├── Pads         8 x BuildPad (Area2D, layer pads)
│   ├── Towers       built Tower nodes
│   └── RangeIndicator  one shared dashed range ring
├── Core             Tree HP/regen, flash, shake, HP bar, 5 archer anchors
├── EnemyPool        70 preallocated Enemy nodes + one-off boss + SpatialHash
├── ProjectilePool   48 preallocated Arrow nodes + shared hit spark
├── TowerProjectilePool  72 pooled tower shots + 3 impact rings
├── WaveManager      PREPARE -> SPAWNING -> CLEARING -> PREPARE + boss waves
├── FloatingTextLayer 40 pooled "+N" labels
├── Sheets (BattleSheets: build/tower/upgrade sheet ownership + pause claim)
└── HUD (CanvasLayer, PROCESS_MODE_ALWAYS)
    ├── TopSafe / BottomSafe (safe-area padded, speed button, trial chip)
    ├── BossBar (name, HP %, enrage pulse)
    ├── WaveBanner (1.5 s modifier announcement)
    ├── SheetHost (BuildSheet + TowerSheet + UpgradePanel)
    ├── PauseMenu + QuitConfirm
    └── DebugLabel (F3)
```

- `Battle.CENTER = (540, 900)`, `ARENA_RADIUS = 500`, `SPAWN_RADIUS = 640`,
  `CORE_RADIUS = 90`; everything uses the 1080x1920 design space.
- `EnemyPool` rebuilds the spatial hash in its own `_physics_process`, which runs
  before the pooled enemies (its children) move. Each enemy owns a reusable
  neighbour array.
- Arrows fly with a swept raycast against the `enemies` layer, so 900 px/s
  projectiles cannot tunnel.
- `Core` draws everything in `_draw()`: no sprite assets, no camera.

## Run lifecycle

`Battle.start_run(modifiers)` resets Coins/kills/time, clears towers, sheets and
pools, builds `RunModifiers` (save meta + equipped cards + trial), resets
`RunStats` from it, sets Tree HP and regen, spawns the archer count, then starts
`WaveManager` with a run seed. `EventBus.run_started` fires after the state is
ready; `SpeedService` resets to 1x on that signal.

Stat changes flow one way:

```
RunModifiers (meta + cards) ──▶ RunStats ──stats_changed──▶ Core / Archers / HUD
                                   ▲
                     upgrade panel ┘ (RunStats.apply_upgrade)
```

`Battle.end_run(reason)` is idempotent: it closes an open sheet, stops the wave
manager, fills the summary (`waves_cleared`, `kills`, `bosses_killed`,
`coins_earned`, `time_seconds`, `reason`, `best_wave_before`, `mode`,
`gold_mult`), emits `EventBus.run_ended(summary)`, then routes to
`Results.tscn` with the summary as a one-shot payload.

Pause and sheets use `get_tree().paused`; the HUD is `PROCESS_MODE_ALWAYS`.
Defeat plays a 0.4 s real-time 0.35x slow-mo, restores time scale through
`SpeedService`, then routes to Results. Arrows, tower shots, enemies, towers,
waves and Coins are all reset per run and never persisted.

## Stage 4 progression

- **In-run upgrades.** Six `UpgradeTrack` resources in `data/upgrades/` feed the
  TREE and ARCHERS tabs. `RunStats.apply_upgrade()` owns the level counter and
  recomputation; costs are `round_to_5(base * growth^level)`. Roots grows max HP
  and heals the same amount through `Core.add_max_hp()`.
- **Bosses.** `WaveRules` marks every tenth wave and computes boss HP
  (`1500 * 1.35^(index-1)`). `Boss.tscn` inherits `Enemy.tscn`; it is spawned
  through `EnemyPool.spawn_custom()`, counts toward the 70-alive cap and is
  freed instead of pooled. It summons four runners at 70% and 40%, ignores slow
  for 3 s and enrages below 30%. `Battle` plays the 0.3 s slow-mo on
  `EventBus.boss_died` and restores the selected speed with `SpeedService.reapply()`.
- **Wave modifiers.** From wave 8, `WaveRules.modifier_for(wave, run_seed)` picks
  `Armored` / `Swift` / `Swarm` deterministically; `WaveManager` merges
  `WaveRules.spawn_modifiers()` into each spawn. Boss waves never get one.
- **Results.** `Results.tscn` computes Gold/Gems, calls
  `GameState.apply_run_result()` once, animates the counters and offers the
  single-use double-Gold rewarded ad. Rewards are never granted twice.
- **Speed.** `SpeedService` resolves 1.5x (flag / Elf Level 3 / trial) and 2x
  (flag / best wave 25 / trial with 1.5x). `SpeedButton` cycles only unlocked
  speeds and shows the lock reason on a long press.

## Stage 5 meta layer

```
MainMenu (shell: top bar, ScreenHost, TabBar, Modal, Toast)
├── TopBar        Gold / Gems / Elf Level / best wave + BATTLE shortcut
├── ScreenHost    cached screen instances, one visible at a time
│   ├── HomeScreen        BATTLE, daily summary, equipped cards, music, version
│   ├── UpgradesScreen    8 x UpgradeTrackRow (data/meta_upgrades)
│   ├── CardsScreen       6 x CardWidget (data/cards) + detail/replace modal
│   ├── MissionsScreen    3 daily or 8 achievements, MissionRow list
│   ├── ShopScreen        8 x ShopProductCard (data/shop) + restore
│   └── SettingsScreen    audio, haptics, language, quality, reset, credits
├── TabBar        six stacked icon+label buttons, 112 px tall
├── ModalSheet    one shared bottom sheet for confirmations and card details
└── Toast         non-blocking messages
```

- Screens are loaded on first visit and cached in `MainMenu._screens`; switching
  tabs toggles visibility, fades alpha over 0.15 s and calls `refresh()`. Every
  screen re-reads `GameState` in `refresh()` and writes every localized label
  there, so `Loc.set_locale()` retranslates the visible tab live.
- The shell owns the single `ModalSheet` and `Toast`; screens ask the shell to
  show them. `go_back()` implements the Android contract: close the sheet, else
  go Home, else confirm exit.
- The tab buttons keep their icon and label in a child VBox (not `Button.text`),
  which lets both locales fit six tabs at 1080 px without clipping.

Meta state flow:

```
EventBus (enemy_died, wave_started/cleared, boss_died, tower_built,
          ad_watched, run_ended)
        │
        ▼
MissionTracker (child of GameState)
  daily counters in memory ──flush──▶ GameState.missions.daily.progress
  achievements derived from stats ──▶ GameState.missions.achievements.progress
        │
        ▼
MissionsScreen.refresh() / claim() ──▶ GameState.claim_mission()
                                         (mark + grant + save_now)
```

Cards and permanent upgrades are resolved once per run:

```
data/meta_upgrades/*.tres ─┐
data/cards/*.tres ──────────┤──▶ ConfigDB ──▶ RunModifiers.build(save, equipped)
                            │                        │
save.upgrades / save.cards ─┘                        ▼
                                                   RunStats ──▶ battle
```

- `GameState.from_dict()` validates the incoming profile: unknown card/product
  ids are dropped, equipped cards are capped at two, upgrade levels are clamped
  to their data maximum, and mission claimed/progress maps are pruned.
- Daily missions are `hash(local date)` + Fisher-Yates over the eight-mission
  pool, three per day. `MissionTracker.refresh_daily()` rolls over on boot, menu
  show, run end and ad completion; progress is never written mid-run.
- Claims and purchases are one atomic operation: append to `claimed`/owned, grant
  currency or the unlock flag, then `SaveManager.save_now()`. The shop sets its
  busy flag before calling `Monetization`, because the fake provider resolves
  synchronously.
- Restore reports the save's owned products (the fake provider has no server
  state) and only re-applies permanent unlock flags; it never pays currency.
- Settings are persisted through `GameState.set_setting()` (debounced save).
  Quality is read live by the VFX guards; the locale switch is immediate and the
  audio sliders write straight to the buses.

## Data flow

```
data/enemies/*.tres ──┐
data/waves/*.tres ────┤──▶ ConfigDB ──▶ EnemyData / WaveTable / TowerData
data/towers/*.tres ───┘                     │       UpgradeTrack / CardData
data/upgrades/*.tres ───────────────────────┘
                                            ▼
                              WaveManager builds spawn queue (+ boss/modifier)
                                            │
                                            ▼
                              Enemy.setup(data, per-wave multipliers)
                                            │
              Battle.obstacles ──▶ EnemyPool ──▶ SteeringComponent
                                            │
                                            ▼
                        kill → Battle.add_coins → EventBus.coins_changed
                                            │
                                            ▼
              Battle fills RunSummary → payload → Results → GameState
```

`GameState` owns the canonical save dict. Stage 4 persists run results, best
wave, stats, milestone flags and mission metrics through `Results`; the battle
itself never writes the save mid-run.

## Towers (stage 3)

`TowerManager` is the single owner of tower world state:

- `get_pads()` → the eight `BuildPad`s, placed once at `CENTER + 300 px` on
  `22.5° + i·45°`.
- `build(pad, tower_id)` → pays through `Battle.spend_coins()` (never negative),
  instantiates `Tower.tscn`, applies the level-1 stats and emits
  `EventBus.tower_built`.
- `upgrade(tower)` / `sell(tower)` → pay or refund, emit `upgrade_purchased`, free
  the pad and rebuild the obstacle array.
- `obstacles` → `[{position, radius}]`, rebuilt **in place** on build/sell only.
  `Battle.obstacles` is the same array and `EnemyPool` hands it to every enemy, so
  `SteeringComponent` always reads fresh data without re-querying the scene.

Tower combat:

```
Tower._physics_process (retarget 0.15 s) -> TowerProjectilePool.spawn()
  -> swept raycast on the enemies layer -> Enemy.take_damage()
  -> frost: splash slow in 70 px -> Enemy.apply_slow() -> StatusComponent
  -> impact ring (and Core.shake() for the Ballista)
```

Targeting modes live on the tower (`NEAREST`, `STRONGEST`, `FIRST`); the scan is
a plain loop over `EnemyPool.get_active()` with no allocations.

Sheets are created once by `BattleSheets.setup()` and parented under
`BattleHUD %SheetHost`, which sits *before* the pause menu so pause still draws
on top. `BattleSheets._open` is the single source of truth: opening pauses the
tree, closing resumes unless the pause sheet is visible, and `start_run()` always
closes any open sheet. `Battle` keeps the gameplay rules (economy, tower
purchases) and delegates only the sheet lifecycle.

## Where to add content

| Content | Steps |
|---|---|
| **Enemy** | Create `data/enemies/<id>.tres` with `EnemyData`; add it to a wave or the procedural weights. `ConfigDB` picks it up at startup. |
| **In-run upgrade** | Create `data/upgrades/<id>.tres` with `UpgradeTrack` (effect, per-level value, cost growth); add its id to `UpgradePanel.TRACK_ORDER` and its name/description keys to `strings.csv`. |
| **Permanent upgrade** | Create `data/meta_upgrades/<id>.tres` with `MetaUpgradeData` (`stat`, `op`, per-level value, `unit`, cost, growth, `order`); add name/description keys. Both the Upgrades screen and `RunModifiers` read it, so no code change is needed. |
| **Card** | Create `data/cards/<id>.tres` with `CardData` and `StatModifier` sub-resources; add name/description/lore keys. The grid sorts by unlock cost, so it appears automatically. |
| **Mission** | Create `data/missions/<id>.tres` with `MissionData` (`metric`, `mode`, target, rewards, `daily`). Daily missions join the 8-mission rotation; achievements appear in the achievements tab. |
| **Shop product** | Create `data/shop/<id>.tres` with `ShopProduct` (amounts, price text, badge, unlock flag, order); the shop grid and restore handle it. |
| **Tower** | Create `data/towers/<id>.tres` with `TowerData` + `TowerLevel` entries (cost, silhouette, projectile, 3 levels). Add its strings to `strings.csv`. The build sheet builds its cards from `ConfigDB.all_towers()` sorted by cost, so no UI change is needed. |
| **Authored wave** | Add `WaveEntry` groups to `data/waves/waves_01_10.tres` tagged with `wave` (wave 10 is replaced by the boss wave). Waves beyond the authored max are procedural. |
| **String** | Add a row to `localization/strings.csv` (UTF-8 with BOM), then use `Loc.t_key("KEY")`. |
| **Screen** | Scene in `scenes/menu/`, controller in `scripts/ui/menu/`, add it to `MainMenu.MENU_SCREENS` and the tab bar. |

## Stage 5 non-goals

No real billing, ad SDKs, consent flow, cloud saves, accounts or leaderboards (stages
6-7). Cards are unlocked directly with Gems; no card packs or duplicates. Scores are
not submitted anywhere; the shop prices are display strings.

