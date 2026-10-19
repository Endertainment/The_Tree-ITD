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
- [x] UK renders Cyrillic correctly: `Дерево`, `Самоцвіти`, `БІЙ`, `Захист Дерева`
      verified in a rendered 540x960 screenshot. `CURRENCY_GEMS` was corrected
      from `Монети` (coins) to `Самоцвіти` in stage 2.
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

## Battle (stage 2)

Verified with Godot `4.7.2.stable.official` (standard build), Windows 11,
NVIDIA RTX 3050 Laptop, 540x960 window (1080x1920 reference).

- [x] `MainMenu` → `Battle` (10 s prep → automatic wave 1) → quit
      confirmation → `MainMenu` flow: `TestFlow` prints
      `FLOW TEST PASSED: menu -> battle -> 10 s prep -> wave 1 -> quit -> menu`.
- [x] Fresh run starts with 120 Coins, 1000 Tree HP, 2 archers and a ~10 s
      `PREPARE` (`TestBattle`, 42 checks).
- [x] `CALL WAVE` during prep grants 4-5 Coins at ~10 s left and starts wave 1.
- [x] Enemies spawn outside the arena boundary, converge on the Tree, and
      separation pushes two enemies sharing a spawn point apart (`TestBattle`).
- [x] Archers acquire targets and fire; arrows kill wave 1 with archers only.
- [x] Armor: 10 damage vs 3 armor → 7; vs 30 armor → 1; ignore-armor → 10
      (`TestBattle`).
- [x] Kills add Coins and `+N` popups; wave clear adds `10 + 2*wave`
      (`TestBattle`, `screenshot_battle_popup.png`).
- [x] An enemy at the Tree damages it; defeat panel shows waves/kills/Coins/time
      and `TestBattle` matches them against `RunSummary`.
- [x] Pause freezes enemies and timers; resume continues (`TestBattle`); pause
      sheet rendered in `screenshot_battle_pause.png`.
- [x] F3 toggles the debug overlay; it reports FPS, wave/state, alive, queued,
      arrows, spatial cells, time scale and run time (`TestBattle` +
      `screenshot_battle_stress.png`).
- [x] 70 alive enemies + 5 archers held 60 FPS in the 540x960 window during the
      stress screenshot; this is the desktop GPU, not a mid-range phone.
- [x] 10 simulated minutes at fixed 60 FPS: wave 21, 418 kills, 701 nodes
      before and after, **0 orphan nodes** (`TestSoak`).
- [x] Headless runs report no project errors or warnings. `TestSave` still
      prints the expected warnings from its deliberate corrupt-save cases.
- [ ] 720x1280 low-end layout and frame time. Not run.
- [ ] Android device: touch targets, back button, app-background auto-pause,
      notched safe area. Code paths exist; not exercised on hardware.
- [ ] Profiler / per-frame allocation proof. No allocation profiler run; the
      pools and reusable query buffers are designed for it, but this is not
      measured.
- [ ] Wall-clock 10 minute session. The soak is simulated at fixed 60 FPS.
- [x] Quit asks for confirmation; cancel keeps the run; confirm returns to the
      menu (`TestBattle` + `TestFlow`). The buttons were emitted
      programmatically, not tapped on a touchscreen.

## Towers (stage 3)

Verified with Godot `4.7.2.stable.official`, Windows 11, 540x960 window
(1080x1920 reference). Headless suites plus the `CaptureTool` screenshots.

- [x] Eight pads exist on a 300 px ring at `22.5° + i·45°`, none on the vertical
      axis, tap radius 56 px (≥88 px target) (`TestTowers`).
- [x] A tap on an empty pad opens the build sheet; a tap on a built pad opens the
      tower sheet; the sheet pauses the tree (`TestTowers`, injected touch).
- [x] Building deducts the exact cost (60 / 90 / 140), refuses when the Coins are
      short and leaves the balance unchanged on refusal (`TestTowers`).
- [x] Building registers a steering obstacle; selling removes it again
      (`TestTowers`, obstacle radius includes the 18 px margin).
- [x] Upgrade curve: Archer 60 → 95 → 155 (rounded to 5), level 3 shows 34 dmg /
      0.8 s / 500 range, max level disables the button (`TestTowers`).
- [x] Sell refunds 60% of build + upgrades (310 invested → 186), frees the pad
      and removes the obstacle (`TestTowers`).
- [x] Archer tower damages a target in range; Frost Spire applies a 0.65 slow
      multiplier; Ballista deals its full 55 damage to a 3-armor Brute
      (`TestTowers`, archers removed so only the tower can score the hit).
- [x] Target modes NEAREST / STRONGEST / FIRST switch and expose label keys; the
      sheet highlights the active mode (screenshot `battle_tower_sheet.png`).
- [x] 8 towers + 24 enemies for 11 simulated seconds: no living enemy overlaps a
      tower body, none stays wedged between towers, all keep flowing inward
      (`TestTowers`, includes the 2 s stuck-nudge path).
- [x] Disabled build cards dim to 40%, show `LOCKED` and print the exact
      shortfall (`Need 50 more Coins`) — `screenshot_battle_build_sheet_locked.png`.
- [x] HUD counter shows `TOWERS 8 / 8`; the `Tap a pad to build` hint hides once
      a tower exists (`screenshot_battle_towers.png`).
- [x] Open sheet + pause: the pause sheet draws on top, resuming keeps the game
      paused while the sheet is open, closing the sheet resumes, and the back
      button closes the sheet first (`TestTowers`,
      `screenshot_battle_sheet_pause.png`).
- [x] 50 open/close cycles of both sheets: node count unchanged (845 → 845) and
      0 orphan nodes (`TestTowers`).
- [x] UK sheet renders Cyrillic (`Вежа лучників`, `МАКС. РІВЕНЬ`, `ПРОДАТИ`) in a
      540x960 screenshot; the EN/UK toggle retranslates an open sheet live.
- [x] 8 towers + 69 enemies on the desktop GPU: F3 overlay reads 60 FPS
      (`screenshot_battle_towers_stress.png`). Desktop only — not a phone.
- [x] `TestSoak` after the steering changes: wave 21, 418 kills, 842 nodes before
      and after, 0 orphans.
- [ ] Android device: real touch targets, back button, app-background while a
      sheet is open, notched safe area. Code paths exist; not exercised on hardware.
- [ ] 720x1280 low-end layout and frame time. Not run.
- [ ] Audio hooks (`AudioManager.play_ui` / `play_sfx`) are called but the project
      still ships no audio assets, so nothing is audible yet.
- [ ] Per-frame allocation proof for tower targeting. Each tower scans the active
      enemy array every 0.15 s (no allocations), but no profiler run was made.

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
& $godot --headless --path $proj res://tests/TestFlow.tscn
& $godot --headless --path $proj --fixed-fps 60 res://tests/TestBattle.tscn
& $godot --headless --path $proj --fixed-fps 60 res://tests/TestSoak.tscn
& $godot --headless --path $proj --fixed-fps 60 res://tests/TestTowers.tscn
& $godot --path $proj res://tools/CaptureTool.tscn        # menu + battle screenshots
```

`CaptureTool` writes `user://screenshot_menu_en.png`, `menu_uk`, `battle_prep`,
`battle_prep_uk`, `battle_wave`, `battle_stress`, `battle_towers`,
`battle_towers_stress`, `battle_tower_sheet`, `battle_tower_sheet_uk`,
`battle_tower_sheet_l1`, `battle_build_sheet`, `battle_build_sheet_locked`,
`battle_sheet_pause`, `battle_pause`, `battle_defeat` and `battle_defeat_uk`.

## Known environment quirks

- **Cold headless import exit code.** After deleting `.godot/`, the first
  `--headless --editor --quit` / `--import` run on this machine finishes the
  import and then dies with an access violation (`0xC0000005`) during editor
  teardown. The import does complete (the save test passes on the next command)
  and every warm run exits 0. It reproduces with the git plugin folder removed
  and with the D3D12 driver override removed, so it is not caused by project
  code. Ignore the exit code of a cold run, or open the project in the editor
  once instead.

