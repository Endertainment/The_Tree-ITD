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
| 2026-10-19 | Verification added: `TestFlow` (menu → battle → quit confirmation → menu), `TestBattle` (42 checks), `TestSoak` (10 simulated minutes, 0 orphans, 701 nodes stable), and battle screenshots through `CaptureTool`. | Headless plus a desktop window only; no Android device is available. |
