# Decisions

Append-only log. Newest decisions at the bottom. To change a decision, add a new
row that supersedes the old one — never rewrite or delete history.

## Locked product decisions (master context §4)

| Date | Decision | Why |
|---|---|---|
| 2026-10-19 | Coins are run-only; Gold and Gems are persisted meta currencies. | Keeps the in-run economy and the long-term economy separately meaningful. |
| 2026-10-19 | Towers are built on eight fixed circular pads around the Tree; no free placement. | Removes path-blocking exploits and keeps touch input simple. |
| 2026-10-19 | Enemies target only the Tree; towers are indestructible obstacles. | Preserves the "no lanes" pillar and avoids tower HP bookkeeping. |
| 2026-10-19 | Endless mode: no victory screen, run ends at Tree death or quit, `best_wave` persisted. | Matches the session length target of 8–15 minutes. |
| 2026-10-19 | The Tree auto-attacks with 2 base archers, up to 5 through in-run upgrades. | Gives the player a baseline defense before the first tower. |
| 2026-10-19 | Speed 1x always available; 1.5x and 2x are unlocks driven by `Engine.time_scale`. | Single implementation point, resets cleanly on pause and scene change. |
| 2026-10-19 | Portrait-only, 1080x1920 reference, `canvas_items` / `expand`. | One-thumb play on phones; `expand` avoids letterboxing on tall screens. |
| 2026-10-19 | All strings go through the translation system; EN and UK ship in the MVP. | The architecture must accept more locales without code changes. |
| 2026-10-19 | Save format is versioned JSON at `user://save.json` with atomic write and backup. | Human-readable, migratable, and crash-safe without a database addon. |
| 2026-10-19 | No network calls except ad/IAP adapters; the game is fully playable offline. | MVP scope; monetization stays behind a facade. |

## Stage 1 decisions

| Date | Decision | Why |
|---|---|---|
| 2026-10-19 | `strings.csv` is parsed at runtime into `Translation` objects instead of relying on Godot's CSV import pipeline. | A fresh clone must run `--headless` without an editor import pass; the import step would otherwise be a hidden prerequisite. The BOM is still required for editors and for a future switch to the importer, and the parser strips it from the header cell. |
| 2026-10-19 | `ConfigDB` returns plain `Resource` values for now. | The seven typed data classes (`EnemyData`, `TowerData`, ...) arrive in stage 2; defining them half-used in stage 1 would be dead code. |
| 2026-10-19 | `ui/theme.tres` and `ui/Toast.tscn` live in `res://ui/`, while `scenes/ui/` keeps a `.gitkeep`. | Stage 1 file list prescribes `ui/`; master §7.1 lists `scenes/ui/` for screens. The theme is a project-level resource, not a screen. |
| 2026-10-19 | Default `settings.locale` is `en`; Boot applies the stored locale. | Deterministic default for tests and a sane fallback when the CSV lacks the OS locale. |
| 2026-10-19 | Atomic save: write `save.tmp`, verify JSON, refresh `save.bak`, rename onto `save.json`; if the rename fails, remove the target and retry, then fall back to a copy. | Windows can refuse a rename over an existing file. `save.bak` always holds the previous good profile, so a crash between remove and rename still recovers. |
| 2026-10-19 | Verified with the non-mono Godot 4.7.2 build extracted to `C:\Tools\godot-4.7.2`. | The only installed build is the .NET/mono editor, which reintroduces a `[dotnet]` section and `.csproj` scaffolding that this project must not contain. |
| 2026-10-19 | Removed the tracked `addons/godot-git-plugin/windows/~libgit_plugin.windows.editor.x86_64.dll`. | 6.1 MB temporary copy left behind by an editor/antivirus cycle; it is not referenced by `git_plugin.gdextension` and exceeds the 5 MB blob limit. |
| 2026-10-19 | Speed resets on `NOTIFICATION_APPLICATION_PAUSED` and on run start/end, not on focus loss. | Losing window focus on desktop must not silently drop the player's chosen speed; backgrounding the app on Android does pause it. |
| 2026-10-19 | `docs/` and `tests/` are part of the shipped repository; `tools/` is dev-only and must be excluded from export filters. | Matches master §7.1 and keeps the screenshot helper out of the APK. |

## Stage 2 decisions

| Date | Decision | Why |
|---|---|---|
| 2026-10-19 | Scene files use `PascalCase.tscn` per master §8.2; the stage-2 list's lowercase names would contradict the master. Scripts stay `snake_case.gd`. | One naming rule across the project. |
| 2026-10-19 | Typed data classes live in `resources/`; their `.tres` instances stay under `data/`. | The stage-2 file list names `resources/...`; the stage-1 architecture note suggested `scripts/core/data/`, which would separate definitions from instances. |
| 2026-10-19 | `WaveTable` is one authored file with flat `WaveEntry` groups tagged `wave` and ordered by `start_delay`; waves 11+ are generated in `WaveManager`. | Keeps the promised `waves_01_10.tres` + two classes while staying data-driven for waves 1-10. |
| 2026-10-19 | Placeholder art is code-drawn in `_draw()` (`Arena`, `Core`, `Enemy`, `Archer`) and tinted from `EnemyData`; no sprites or binary art are added and no `AnimatedSprite2D` is needed. | Stage 2 forbids final art and this needs no import pipeline or external assets. |
| 2026-10-19 | The arena vignette is composed of concentric arcs in `Arena._draw()` instead of a shader or gradient `ColorRect`. | One less asset and draw item; the effect is purely decorative. |
| 2026-10-19 | The HUD is `BattleHUD.tscn`, instanced as `Battle/HUD` rather than inlined into `Battle.tscn`. | Keeps `Battle.tscn` readable and follows the master's component rule; the logical scene shape is unchanged. |
| 2026-10-19 | Arrows use a swept raycast against the enemies layer; the arrow's own collision shape is disabled and enemy `monitoring` is off. | Prevents tunneling at 900 px/s and at 2x speed without paying for area overlap checks. |
| 2026-10-19 | The 0.6 s spawn telegraph is drawn by `Enemy`; the death puff is a per-instance `CPUParticles2D`. | No per-spawn nodes: both effects are preallocated with the pool. |
| 2026-10-19 | Defeat slow-mo sets `Engine.time_scale = 0.35` for 0.4 s of real time, then calls `SpeedService.reset()` and only then pauses. | Gives the death beat without leaving time scale outside `SpeedService`'s control. |
| 2026-10-19 | Pause and defeat use `get_tree().paused`; HUD, pause sheet and defeat panel run with `PROCESS_MODE_ALWAYS`. | Gameplay freezes while the UI keeps accepting input. |
| 2026-10-19 | Run constants (120 Coins, 1000 Tree HP, 2 archers, archer stats) live in `battle.gd` until `RunModifiers` arrives in stage 4. | Stage 2 has no modifier pipeline yet; enemy and wave balance already lives in `.tres`. Marked temporary with a stage-4 TODO. |
| 2026-10-19 | The speed button shows a disabled `1x` with a tooltip; no unlock UI is built. | Speed unlocks are stage 4/6 scope. |
| 2026-10-19 | The spatial hash clears buckets in place and each enemy owns a reusable neighbour array; `EnemyPool` rebuilds the hash before pooled enemies move. | Steady-state frames avoid allocating arrays or dictionaries. |
| 2026-10-19 | `project.godot` names the three 2D physics layers and restores the explicit 60 Hz physics tick the editor had dropped. | Scene files reference the layer names; the explicit tick documents the target. |
| 2026-10-19 | UK `CURRENCY_GEMS` changed from `Монети` to `Самоцвіти`. | `Монети` means coins; stage 2 now shows Coins and Gems as separate concepts. |
| 2026-10-19 | Verification added: `TestFlow` (menu → battle → 10 s prep → wave 1 → quit confirmation → menu), `TestBattle` (42 checks), `TestSoak` (10 simulated minutes, 0 orphans, 701 nodes stable), and battle screenshots through `CaptureTool`. | Headless plus a desktop window only; no Android device is available. |

## Stage 3 decisions

| Date | Decision | Why |
|---|---|---|
| 2026-10-19 | Scene files are `Tower.tscn`, `BuildPad.tscn`, `BuildSheet.tscn`, `TowerSheet.tscn`, `TowerProjectile.tscn`, `ui/TowerCard.tscn`, while the stage file list used lowercase names. | Follows the stage-2 naming decision and master §8.2; one naming rule across the project. |
| 2026-10-19 | `TowerManager` (a `Node2D` child of `Battle`) owns the eight pads, the built towers and the obstacle list. `Battle.obstacles` is the *same* `Array` instance and is rebuilt in place on build/sell. | Keeps `battle.gd` within the size guideline and lets every pooled enemy hold one stable array reference for the whole run. |
| 2026-10-19 | `TowerLevel` / `TowerData` live in `resources/`, their instances in `data/towers/*.tres` as `Array[ExtResource("tower_level.gd")]`. | Matches the stage-2 rule that typed data classes live in `resources/`; typed arrays keep the editor honest. |
| 2026-10-19 | Pad taps are resolved by a hit-test in `Battle._unhandled_input` against `BuildPad.get_tap_radius()` (56 px), not by `Area2D.input_event`. The pad is still an `Area2D` on the `pads` layer with a radius-56 collider. | Physics picking for touch is fragile and untestable headless; the explicit hit-test behaves the same for `InputEventScreenTouch`, mouse clicks and injected test events. |
| 2026-10-19 | Upgrade costs are rounded to the nearest 5, so the Archer Tower goes 60 → 95 → 155. The stage table's `UPGRADE — 96` is treated as illustrative. | Requirement 3 says "rounded to nearest 5"; that rule is stated twice, the 96 appears once as a mock value. |
| 2026-10-19 | The Frost Spire keeps its 70 px splash at levels 2 and 3. | The stage table lists the splash only in the L1 column; removing it on upgrade would be a balance trap, so it is a per-level data field that stays 70. |
| 2026-10-19 | Build/tower sheets live under `BattleHUD %SheetHost`, which sits before `PauseMenu` in the HUD scene. They pause the tree themselves and `Battle` owns a single `_sheet_open` flag. | The pause sheet and quit confirm must still draw above an open sheet; `start_run` forces `paused = false` so a rerun never starts frozen. |
| 2026-10-19 | Backgrounding the app while a sheet is open does not stack the pause sheet: the run is already paused and the sheet stays intact. | Matches the stage manual test; opening pause over a bottom sheet is still possible from the pause button. |
| 2026-10-19 | Tower shots get their own 72-node pool next to the 48 arrows (120 total). | Master §8.5 caps projectiles at 120; one shared pool would starve either archers or towers. |
| 2026-10-19 | Obstacle radius is `body_radius + 18` and `SteeringComponent` no longer adds its own margin; avoidance now also has a hard push-out plus a 2 s no-progress nudge. | The stage specifies the margin once; the push-out is what stops an enemy from clipping through a tower when the crowd pushes it inside the circle. |
| 2026-10-19 | `Enemy.apply_slow()` wraps the existing `StatusComponent`: strongest slow wins, reapplication refreshes duration, plus a blue tint and a 0.3 s snowflake marker. | The component already had the right semantics; only the feedback was missing. |
| 2026-10-19 | `Archer.tscn` is `load()`ed in `Battle._ready()` instead of `preload`ed. | A cyclic preload (Battle → Archer → Enemy → Battle) produced an empty `PackedScene` in one windowed load order (`CaptureTool`), which left the battle without archers. Loading after the script compiles removes the race; `_spawn_archers` also guards null. |
| 2026-10-19 | `tower_cost_mult` is read from the `start_run(modifiers)` dictionary (default 1.0). | `RunModifiers` is stage-4 scope; the cost pipeline already accepts the multiplier without inventing a stage-4 class. |
| 2026-10-19 | `Battle.start_run()` clears the pause flag and hides the pause sheet. | Needed by `TestTowers`, which reruns `start_run` after a defeat; a real "play again" flow needs the same. |
| 2026-10-19 | Verification: `TestTowers` (74 checks), plus `TestBattle` 42, `TestSave` 42, `TestFlow`, `TestSoak`, and new `CaptureTool` screenshots for the ring, both sheets, the locked cards and the 8-tower stress frame. | Desktop window only; no Android device, no 720x1280 device pass. |
| 2026-10-19 | Known deviation: `battle.gd` grew to ~520 lines (master §8.1 suggests ~300). Tower world state already moved into `TowerManager`; the remaining run lifecycle, economy, pause ownership and sheet plumbing stay in the scene controller until stage 4 adds `RunModifiers`/`RunState`. | Splitting the economy now would duplicate stage 4's work; the behaviour is covered by 74 tower checks plus the stage-2 suites. Recorded so stage 4 pays this debt instead of forgetting it. |


## Stage 4 decisions

| Date | Decision | Why |
|---|---|---|
| 2026-10-19 | `CardData` is defined in stage 4 even though cards are stage-5 content. | `RunModifiers.build(meta, cards, trial)` is a stage-4 signature; the class has no `.tres` instances and the collection UI stays out of scope. |
| 2026-10-19 | `RunStats` is a `RefCounted` with `stats_changed`; `Battle` owns the only instance. | Typed signal, no node overhead, and one writer for every live combat value. |
| 2026-10-19 | Modifier order is base -> meta/cards -> in-run upgrades; multipliers are additive per category, attack speed divides the interval. | Matches master 7.7 and keeps stacking predictable; the arithmetic is pinned by `TestProgression`. |
| 2026-10-19 | Upgrade effects and values live in `data/upgrades/*.tres`; `RunStats` only switches on the `effect` id. | Balance stays out of code and the six tracks stay data-driven. |
| 2026-10-19 | Scene names are PascalCase (`UpgradePanel.tscn`, `SpeedButton.tscn`, ...), not the lowercase names in the stage file list. | Follows the stage-2 naming decision and master 8.2. |
| 2026-10-19 | `WaveRules` is a pure static class for boss cadence/HP, modifier choice and spawn modifiers. | Every formula is testable headlessly and `WaveManager` stays a state machine. |
| 2026-10-19 | The authored wave 10 is replaced by a pure boss wave (boss + 6 Grunts + 2 Brutes). | The stage asks for a boss on every tenth wave; authored grunt groups would dilute the escort. |
| 2026-10-19 | The boss is a non-pooled `Enemy` (`Boss.tscn` inherits `Enemy.tscn`) tracked by `EnemyPool.spawn_custom()`. | One spawn per ten waves does not need a second pool; it still counts toward the alive cap and targeting. |
| 2026-10-19 | `Boss.tscn` is `load()`ed in `WaveManager.setup()`, never preloaded. | WaveManager -> Boss -> Enemy -> Battle -> WaveManager is the same cyclic-preload class that broke archers in stage 3; a windowed `CaptureTool` run reproduced it (WaveManager lost its script). |
| 2026-10-19 | A boss may enter at the 70-alive cap. | The wave's centrepiece must never be skipped; regular spawns keep respecting the cap. |
| 2026-10-19 | Results replaces the HUD defeat panel for both defeat and quit; the summary travels as a one-shot `SceneRouter` payload. | One payout path, no global run state, and quit now pays for cleared waves as master 5.10 requires. |
| 2026-10-19 | `Results` grants rewards once on entry; the double-Gold ad adds the base Gold exactly once. | Prevents double payouts on replay, language change or a repeated ad callback. |
| 2026-10-19 | `RunSummary.gold_mult` snapshots the run's multiplier instead of re-reading meta on the results screen. | The payout must not change if the profile changes between battle and results. |
| 2026-10-19 | `MissionHooks` stores metric counters (`run_completed`, `wave_reached`, `bosses_killed`, `gold_earned`) and emits `mission_progress` with target 0. | Stage 5 owns MissionData; target 0 means "metric updated, no specific mission yet" and is documented in the class. |
| 2026-10-19 | The speed-trial chip lives in the first battle preparation; stage 6 moves it to the pre-battle card row. | Stage 4 has no menu surface for it and the acceptance requires a working one-run trial now. |
| 2026-10-19 | Boss slow-mo (0.3 s at 0.25x) restores `SpeedService.get_speed()` via `reapply()`, not 1x. | The player's chosen 1.5x/2x must survive the boss death beat; defeat still resets to 1x. |
| 2026-10-19 | `BattleSheets` owns the build/tower/upgrade sheet lifecycle and the single pause claim. | Pays part of the stage-3 `battle.gd` size debt; the controller still exceeds the 300-line guideline. |
| 2026-10-19 | `Battle.auto_route_results` lets headless suites inspect a defeated battle. | `SceneRouter` replaces the current scene, which would otherwise kill the test runner mid-suite. Test-only switch, documented here. |
| 2026-10-19 | `GameState.apply_run_result()` writes the save synchronously (`save_now`), and the double-Gold grant flushes too. | Run rewards must survive an app kill inside the 0.5 s debounce window; the results screen is not a hot path. |
| 2026-10-19 | Verification: `TestProgression` (120 checks), `TestBattle` 42, `TestTowers` 74, `TestSave` 42, `TestFlow` (quit -> results -> menu), `TestSoak` 5, plus CaptureTool shots (upgrade panel EN/UK, modifier banner, boss bar, results EN/UK). | Desktop window and headless only; no Android device, no 720x1280 pass, no real ad SDK. |
| 2026-10-19 | Known deviation: battle node count is ~922 (master 8.5 suggests <400); `battle.gd` is ~644, `battle_hud.gd` ~452 and `wave_manager.gd` ~374 lines (master 8.1 suggests ~300). | Pools, sheets and HUD widgets dominate the node count; recorded rather than hidden. Stage 7 perf work should profile the HUD and the pool split, and the controllers can be split further. |

## Stage 5 decisions

| Date | Decision | Why |
|---|---|---|
| 2026-10-19 | Menu screen controllers live in `scripts/ui/menu/` and meta logic in `scripts/meta/`; the stage list's `scripts/menu/` was not used. | Master 7.1 puts screen controllers under `scripts/ui/` and meta systems under `scripts/meta/`; a stage prompt may not contradict the master. |
| 2026-10-19 | Cards now carry `Array[StatModifier]` (typed Resource with `stat`, `op`, `value`); `RunModifiers` dispatches on `op`, and `TestProgression` builds modifiers as resources. | Typed data is editor-safe and keeps the "no card-id branches" rule; `op` is now authoritative instead of being inferred from the stat key. The stage-4 test was updated, not duplicated. |
| 2026-10-19 | Permanent upgrade balance moved from the `META_UPGRADES` const into `data/meta_upgrades/*.tres` (`MetaUpgradeData`); `RunModifiers` reads `ConfigDB.all_meta_upgrades()`. | Master 7.5/8.1 puts balance in data, and the Upgrades screen and the run pipeline must read the same numbers so a displayed price can never drift from its effect. |
| 2026-10-19 | `MissionTracker` is a child node created by `GameState`, not an eleventh autoload. | Master 7.2 fixes the autoload list; parenting the tracker to `GameState` keeps it alive during battle so kills, waves, towers and ads are counted while the menu scene is unloaded. |
| 2026-10-19 | Daily counters live in memory and are written to the save only at run end, after a rewarded ad, on menu show and on claim. | Master 7.6 forbids mid-run saves; a killed app loses the current run's daily progress along with the run itself, but never the profile. |
| 2026-10-19 | `MissionHooks` was deleted. `EventBus.run_ended` feeds run metrics, and achievements are derived from persistent `stats` on refresh instead of being counted a second time. | One writer for mission progress; deriving achievements from stats is idempotent and migration-safe for stage-4 profiles. |
| 2026-10-19 | Daily selection is `seed = hash("YYYY-MM-DD")` plus a Fisher-Yates shuffle of the sorted 8-mission pool; the three ids are re-derived rather than stored. Rollover is checked on boot, menu show, run end and ad completion. | Deterministic per date, so a restart mid-day picks the same missions without an extra save key, and the stored date alone decides when to reset. |
| 2026-10-19 | Claims and purchases mark state, grant rewards and call `SaveManager.save_now()` in one call; the shop sets its busy flag before calling the provider. | The fake IAP resolves synchronously, so a flag set after the call would allow a second grant; the save must include the claim before the button re-enables. |
| 2026-10-19 | `FakeIapProvider.restore` returns the owned product ids from the save, and restore only re-applies `unlocks` flags - never currency. | The fake provider has no server state; re-granting on restore would duplicate a starter bundle after a reinstall. |
| 2026-10-19 | `ShopProduct` models contents as `gold_amount` + `gems_amount` + `unlock_flag`, not the master's single `currency`/`amount` pair. The starter bundle is one-time and is hidden once owned; remove-ads shows `OWNED`. | The master table already contains a two-currency bundle and a non-currency unlock, so one pair of fields cannot describe every product. |
| 2026-10-19 | There is no pre-battle screen: master 7.4 is `MainMenu -> Battle`. Equipped cards are shown on Home and the speed-trial chip there is a disabled stage-6 placeholder. | Adding a screen between menu and battle would change the locked scene flow; the acceptance criteria only require Home visibility. |
| 2026-10-19 | `MenuScreen.main_menu` is untyped and the shell has no `class_name`. | Typing the screen base as `MainMenu` and the shell as `MenuScreen` creates a cyclic script dependency; untyped access keeps the one-way dependency. |
| 2026-10-19 | Low quality is read live with `GameState.is_low_quality()` at the four decorative effect sites (Tree shake/leaf puff, death puff, arrow spark, Frost Lv3 snow). | No Boot pass is needed, and changing the setting applies on the next battle without touching gameplay values. |
| 2026-10-19 | The tab bar is a Button with a stacked icon and label in a child VBox, not a Button icon plus text. | Six single-line tabs with 28 px icons overflowed 1080 px in Ukrainian; stacking gives the label the full tab width and every locale fits without clipping. |
| 2026-10-19 | Placeholder English text remains in the `.tscn` files as editor preview only. Every screen overwrites its labels in `refresh()` before the first rendered frame. | Follows the existing stage 1-4 scene convention while keeping runtime strings localized; the QA pass checks EN and UK screenshots for leftovers. |
| 2026-10-19 | `stats.ads_watched` was added to the v1 save defaults. | Achievements need a lifetime ad counter; `SaveManager._merge_missing` adds it to older profiles, so the schema version does not change. |
| 2026-10-19 | Verification: `TestMenu` (110 checks) plus `TestSave` 42, `TestFlow`, `TestBattle` 42, `TestTowers` 74, `TestProgression` 120 and `TestSoak` 5 all pass; 12 menu screenshots (six tabs, EN + UK) at 540x960 and 60 FPS in a windowed run. | Desktop/headless only: no Android device, no 720x1280 pass, no real IAP/ads. The reset flow and the reward-fly animation were code-reviewed, not executed end to end. |
| 2026-10-19 | Known deviation: `GameState` is ~495 lines (master 8.1 suggests ~300). | Stage 5 added the card/mission/shop accessors and load-time validation to the canonical store. Splitting the dictionary behind another indirection would not remove the logic; the single-writer property is worth more than the line count. Recorded for a future refactor alongside `battle.gd` (~644). |