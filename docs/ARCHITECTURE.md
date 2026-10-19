# Architecture (one page)

## Scene flow

```
Boot.tscn ──0.8 s──▶ MainMenu.tscn ──BATTLE──▶ Battle.tscn
                                                  │
                        quit / BACK TO MENU ◀─────┤
                                                  │
                          defeat panel (stage 2 stub)
                                                  │
                          Results.tscn (stage 4) ─┘
```

`SceneRouter.goto(path)` fades out (0.2 s), calls `change_scene_to_file`, fades
in. The fade overlay lives on a `CanvasLayer` owned by the autoload, so it
survives the swap. Navigation is ignored while a transition is running and when
the requested path is already the current scene.

Boot is the only place that reads the save: load → `GameState.from_dict` →
`Loc.set_locale` → `AudioManager.apply_settings` → wait → route. A debug build
with `--debug-battle` routes straight to `Battle.tscn`.

## Autoloads (order matters)

| # | Name | Responsibility | Never does |
|---|---|---|---|
| 1 | `EventBus` | Signals only | Hold state or logic |
| 2 | `SaveManager` | JSON I/O, migration call, atomic write, backup, corruption recovery | Touch `GameState` |
| 3 | `GameState` | Canonical save dict + typed accessors, emits change signals | Hold run state (Coins, waves) |
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
Battle (battle.gd: coins, kills, pause, RunSummary, sheet ownership)
├── Arena            static _draw() backdrop, boundary, roots, stones
├── TowerManager     pads, towers, obstacles, selection, range ring
│   ├── Pads         8 x BuildPad (Area2D, layer pads)
│   ├── Towers       built Tower nodes
│   └── RangeIndicator  one shared dashed range ring
├── Core             Tree HP, flash, shake, HP bar, 5 archer anchors
├── EnemyPool        70 preallocated Enemy nodes + SpatialHash + neighbour query
├── ProjectilePool   48 preallocated Arrow nodes + shared hit spark
├── TowerProjectilePool  72 pooled tower shots + 3 impact rings
├── WaveManager      PREPARE -> SPAWNING -> CLEARING -> PREPARE
├── FloatingTextLayer 40 pooled "+N" labels
└── HUD (CanvasLayer, PROCESS_MODE_ALWAYS)
    ├── TopSafe / BottomSafe (safe-area padded, tower counter + hint)
    ├── SheetHost (BuildSheet + TowerSheet, below the pause sheet)
    ├── PauseMenu + QuitConfirm
    ├── DefeatPanel
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

`Battle.start_run()` resets Coins/kills/time, clears towers and sheets, builds an
empty `RunSummary`, sets Tree HP, spawns archers and starts `WaveManager`.
`EventBus.run_started` fires after the state is ready.

`Battle.end_run(reason)` is idempotent: it closes an open sheet, stops the wave
manager, fills the summary (`waves_cleared`, `kills`, `coins_earned`,
`time_seconds`, `reason`), emits `EventBus.run_ended(summary)`, then either routes
to the menu (`quit`) or pauses and opens the defeat panel (`defeat`).

Pause and defeat use `get_tree().paused`; the HUD is `PROCESS_MODE_ALWAYS`.
Defeat plays a 0.4 s real-time 0.35x slow-mo, restores time scale through
`SpeedService`, then pauses. Arrows, tower shots, enemies, towers, waves and
Coins are all reset per run and never persisted.

## Data flow

```
data/enemies/*.tres ──┐
data/waves/*.tres ────┤──▶ ConfigDB ──▶ EnemyData / WaveTable / TowerData
data/towers/*.tres ───┘                     │
                                            ▼
                              WaveManager builds spawn queue
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
              Battle fills RunSummary → EventBus.run_ended → Results (stage 4)
```

`GameState` still owns the canonical save dict; nothing in stage 3 is persisted.

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

Sheets are created once by `Battle._create_sheets()` and parented under
`BattleHUD %SheetHost`, which sits *before* the pause menu so pause still draws
on top. `Battle._sheet_open` is the single source of truth: opening pauses the
tree, closing resumes unless the pause sheet is visible, and `start_run()` always
clears the flag.

## Where to add content

| Content | Steps |
|---|---|
| **Enemy** | Create `data/enemies/<id>.tres` with `EnemyData`; add it to a wave or the procedural weights. `ConfigDB` picks it up at startup. |
| **Tower** | Create `data/towers/<id>.tres` with `TowerData` + `TowerLevel` entries (cost, silhouette, projectile, 3 levels). Add its strings to `strings.csv`. The build sheet builds its cards from `ConfigDB.all_towers()` sorted by cost, so no UI change is needed. |
| **Authored wave** | Add `WaveEntry` groups to `data/waves/waves_01_10.tres` tagged with `wave`. Waves beyond the authored max are procedural. |
| **String** | Add a row to `localization/strings.csv` (UTF-8 with BOM), then use `Loc.t_key("KEY")`. |
| **Screen** | Scene in `scenes/<area>/`, controller in `scripts/ui/` or `scripts/battle/`, navigate with `SceneRouter.goto`. |

## Stage 3 non-goals

No global tower upgrades, synergies, auras or set bonuses. No towers that take
damage, no free placement, no boss waves or meta cards affecting towers — those
arrive in stages 4–5.

