# Architecture (one page)

## Scene flow

```
Boot.tscn ──0.8 s──▶ MainMenu.tscn ──▶ (stage 2) Battle.tscn ──▶ Results.tscn ──▶ MainMenu.tscn
```

`SceneRouter.goto(path)` fades out (0.2 s), calls `change_scene_to_file`, fades
in. The fade overlay lives on a `CanvasLayer` owned by the autoload, so it
survives the swap. Navigation is ignored while a transition is running and when
the requested path is already the current scene.

Boot is the only place that reads the save: load → `GameState.from_dict` →
`Loc.set_locale` → `AudioManager.apply_settings` → wait → route.

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

## Data flow

```
user://save.json ──load_game()──▶ SaveManager ──▶ SaveMigrations ──▶ GameState._data
                                                                          │
                                       accessors (add_gold, unlock, ...) ◀─┘
                                                                          │
                                                    EventBus signal ──▶ UI
                                                                          │
                                              SaveManager.save_game(to_dict())  (debounced 0.5 s)
```

- `GameState` holds the single canonical `Dictionary`; `SaveManager` only stores
  and returns dictionaries, so autoload order cannot deadlock.
- Every mutation emits its `EventBus` signal and queues a debounced write.
  `save_now()` flushes immediately (pause, quit, purchases, tests).
- Missing keys are merged from `SaveDefaults`; unknown keys are preserved.
- On a parse error the corrupt file is copied to `save.corrupt`, then `save.bak`
  is tried, then a fresh profile is created.

## Where to add content

| Content | Steps |
|---|---|
| **Enemy** | Add `scripts/core/data/enemy_data.gd` (stage 2), create `data/enemies/<id>.tres`, set `id`, `ConfigDB.get_enemy(id)` picks it up on start. |
| **Tower** | Same pattern with `TowerData` + `data/towers/<id>.tres` (stage 3). |
| **Wave** | A `WaveTable` `.tres` in `data/waves/`, referenced through `ConfigDB.get_wave_table()`. |
| **Upgrade** | `UpgradeTrack` `.tres` in `data/upgrades/`; meta ids live in `GameState`'s `upgrades` dict, run upgrades stay in the battle scene. |
| **String** | Add a row to `localization/strings.csv` (UTF-8 with BOM), then use `Loc.t_key("KEY")`. |
| **Screen** | Scene in `scenes/<area>/`, controller in `scripts/ui/`, navigate with `SceneRouter.goto`. |

## Stage 1 non-goals

No enemies, towers, waves, battle scene, cards, missions, shop screens, real ads
or billing. Those arrive stage 2–6 and must not be pre-implemented here.
