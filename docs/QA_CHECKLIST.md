# QA Checklist

Legend: `[x]` verified in this environment · `[ ]` not verified yet (manual or
later stage). Never tick a box that was not actually observed.

Verified with Godot `4.7.2.stable.official` (standard build, not .NET), Windows 11.

## Boot

- [x] Main scene starts and routes to the menu with no errors.
      `godot --headless --path . --quit-after 100000` → stdout contains
      `[analytics] screen_view {"screen":"main_menu"}`, stderr empty.
- [x] Windowed launch reaches `MainMenu` on the first try: D3D12 / Forward
      Mobile, no errors or warnings.
- [x] Boot splash holds ~0.8 s via a real-time timer (`ignore_time_scale`), then
      fades over 0.2 s.
- [x] `Boot` is safe to re-enter (guarded by `_starting`; a fresh instance runs
      the full sequence).
- [ ] Cold-start timing on a mid-range Android device. Deferred to stage 7.

## Save

- [x] Fresh profile: no files → defaults, Gold = Gems = 0.
- [x] Round trip: `add_gold(123)`, `add_gems(45)`, `save_now`, wipe memory, load
      → 123 / 45 restored, `settings.music` restored.
- [x] Locale setting survives a reload.
- [x] `save.bak` is created on the second write and always holds the previous
      good profile.
- [x] Corrupt `save.json` (`{bad json`): load recovers the value from `save.bak`
      and writes `save.corrupt`.
- [x] Deleted `save.json` with a valid `save.bak` recovers the profile (explicit
      test, not just the corrupt-file path).
- [x] Unknown keys are preserved; a save without `version` becomes a fresh
      current-version profile; a v1 save stays v1.
- [x] Headless test: `godot --headless --path . res://tests/TestSave.tscn` →
      `ALL SAVE TESTS PASSED (36 checks)`, exit code 0.
- [ ] Killing the app mid-write on a real device. The design is crash-safe
      (`save.tmp` + `save.bak`), but no forced-kill test was run.

## Localization

- [x] CSV loads from `res://localization/strings.csv` (UTF-8 with BOM); the BOM is
      stripped from the header cell.
- [x] UK renders Cyrillic correctly: `Дерево`, `Монети`, `БІЙ`, `Захист Дерева`
      verified in a rendered 540x960 screenshot.
- [x] EN ↔ UK toggle retranslates the visible screen immediately (title,
      subtitle, button, currency labels, language button) and persists across
      reload.
- [x] `format_number(12500)` → `12 500` (thin space), `0` → `0`.
- [x] Version placeholder `v{version}` substitutes to `v0.1.0`.
- [x] Unknown/missing keys fall back to the key text rather than crashing.
- [ ] Export packaging: a packaged build has no raw CSV, so `Loc` falls back to
      the compiled `*.translation` resources. The fallback is implemented but not
      yet exercised by an export (stage 7).

## UI

- [x] Desktop window is portrait 540x960 with a 1080x1920 reference; layout was
      captured and inspected: no stretching artifacts, 16:9 canvas maps 1:1.
- [x] Safe-area padding applied on ready and on viewport resize.
- [x] Currency HUD updates live through `EventBus` (`add_gold(1250)` →
      `Gold 1 250`) with no manual refresh call.
- [x] `BATTLE` shows the "Coming in stage 2" toast; the toast is opaque, sits
      below the HUD and does not cover the primary button.
- [x] Touch targets: BATTLE is 160 px tall, the language button 140x88 logical px
      (both above the 88 px minimum).
- [x] No per-node font sizes in scenes; text styles come from `ui/theme.tres`
      type variations (`Title`, `Subtitle`, `PrimaryButton`).
- [ ] Real-device touch feel, thumb reach and safe area on a notched phone.
      Deferred to device testing.

## Project hygiene

- [x] `project.godot` has no `[dotnet]` section; no `.cs` / `.csproj` anywhere.
- [x] No new addons; the bundled git plugin is left as-is (still not enabled).
- [x] `.godot/`, `*.translation`, keystores and store files are git-ignored.
- [x] `docs/DECISIONS.md`, `docs/QA_CHECKLIST.md`, `docs/ARCHITECTURE.md` filled.
- [ ] Android export, AAB signing, ETC2/ASTC validation. Deferred to stage 7.

## Reproduce everything

```powershell
$godot = "C:\Tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe"
$proj  = "C:\Users\VOVA\Documents\the-tree---idle-tower-defense"

& $godot --headless --path $proj --import                # one-time import pass
& $godot --headless --path $proj res://tests/TestSave.tscn
& $godot --path $proj res://tools/CaptureTool.tscn        # EN / UK / HUD screenshots
```

## Known environment quirks

- **Cold headless import exit code.** After deleting `.godot/`, the first
  `--headless --editor --quit` / `--import` run on this machine finishes the
  import and then dies with an access violation (`0xC0000005`) during editor
  teardown. The import does complete (the save test passes on the next command)
  and every warm run exits 0. It reproduces with the git plugin folder removed
  and with the D3D12 driver override removed, so it is not caused by project
  code. Ignore the exit code of a cold run, or open the project in the editor
  once instead.

