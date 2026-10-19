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
Battle (battle.gd: coins, kills, pause, RunSummary)
├── Arena            static _draw() backdrop, boundary, roots, stones
├── Core             Tree HP, flash, shake, HP bar, 5 archer anchors
├── EnemyPool        70 preallocated Enemy nodes + SpatialHash + neighbour query
├── ProjectilePool   48 preallocated Arrow nodes + shared hit spark
├── WaveManager      PREPARE -> SPAWNING -> CLEARING -> PREPARE
├── FloatingTextLayer 40 pooled "+N" labels
└── HUD (CanvasLayer, PROCESS_MODE_ALWAYS)
    ├── TopSafe / BottomSafe (safe-area padded)
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

`Battle.start_run()` resets Coins/kills/time, builds an empty `RunSummary`, sets
Tree HP, spawns archers and starts `WaveManager`. `EventBus.run_started` fires
after the state is ready.

`Battle.end_run(reason)` is idempotent: it stops the wave manager, fills the
summary (`waves_cleared`, `kills`, `coins_earned`, `time_seconds`, `reason`),
emits `EventBus.run_ended(summary)`, then either routes to the menu (`quit`) or
pauses and opens the defeat panel (`defeat`).

Pause and defeat use `get_tree().paused`; the HUD is `PROCESS_MODE_ALWAYS`.
Defeat plays a 0.4 s real-time 0.35x slow-mo, restores time scale through
`SpeedService`, then pauses. Arrows, enemies, waves and Coins are all reset per
run and never persisted.

## Data flow

```
data/enemies/*.tres ──┐
data/waves/*.tres ────┤──▶ ConfigDB ──▶ EnemyData / WaveTable
                      │                     │
                      │                     ▼
                      │              WaveManager builds spawn queue
                      │                     │
                      ▼                     ▼
                  Enemy.setup(data, per-wave multipliers)
                      │
                      ▼
          kill → Battle.add_coins → EventBus.coins_changed / enemy_died
                      │
                      ▼
          Battle fills RunSummary → EventBus.run_ended → Results (stage 4)
```

`GameState` still owns the canonical save dict; stage 2 never saves mid-run.

## Where to add content

| Content | Steps |
|---|---|
| **Enemy** | Create `data/enemies/<id>.tres` with `EnemyData`; add it to a wave or the procedural weights. `ConfigDB` picks it up at startup. |
| **Authored wave** | Add `WaveEntry` groups to `data/waves/waves_01_10.tres` tagged with `wave`. Waves beyond the authored max are procedural. |
| **String** | Add a row to `localization/strings.csv` (UTF-8 with BOM), then use `Loc.t_key("KEY")`. |
| **Screen** | Scene in `scenes/<area>/`, controller in `scripts/ui/` or `scripts/battle/`, navigate with `SceneRouter.goto`. |

## Stage 2 non-goals

No towers, build pads, bosses, wave modifiers, meta rewards, revive or ads.
The UPGRADES button and SETTINGS button only show a placeholder toast; stage 3
adds towers and stage 4 adds the real upgrade/results flow.
