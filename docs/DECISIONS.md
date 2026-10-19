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
