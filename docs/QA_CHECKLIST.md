# QA Checklist

Legend: `[x]` verified in this environment Â· `[ ]` not verified yet (manual or
later stage). Never tick a box that was not actually observed.

Verified with Godot `4.7.2.stable.official` (standard build, not .NET), Windows 11.

## Boot

- [x] Main scene starts and routes to the menu with no errors.
      `godot --headless --path . --quit-after 100000` â†’ stdout contains
      `[analytics] screen_view {"screen":"main_menu"}`, stderr empty.
- [x] Windowed launch reaches `MainMenu` on the first try: D3D12 / Forward
      Mobile, no errors or warnings.
- [x] Boot splash holds ~0.8 s via a real-time timer (`ignore_time_scale`), then
      fades over 0.2 s.
- [x] `Boot` is safe to re-enter (guarded by `_starting`; a fresh instance runs
      the full sequence).
- [ ] Cold-start timing on a mid-range Android device. Deferred to stage 7.

## Save

- [x] Fresh profile: no files â†’ defaults, Gold = Gems = 0.
- [x] Round trip: `add_gold(123)`, `add_gems(45)`, `save_now`, wipe memory, load
      â†’ 123 / 45 restored, `settings.music` restored.
- [x] Locale setting survives a reload.
- [x] `save.bak` is created on the second write and always holds the previous
      good profile.
- [x] Corrupt `save.json` (`{bad json`): load recovers the value from `save.bak`
      and writes `save.corrupt`.
- [x] Deleted `save.json` with a valid `save.bak` recovers the profile (explicit
      test, not just the corrupt-file path).
- [x] Unknown keys are preserved; a save without `version` becomes a fresh
      current-version profile; a v1 save stays v1.
- [x] Headless test: `godot --headless --path . res://tests/TestSave.tscn` â†’
      `ALL SAVE TESTS PASSED (36 checks)`, exit code 0.
- [ ] Killing the app mid-write on a real device. The design is crash-safe
      (`save.tmp` + `save.bak`), but no forced-kill test was run.

## Localization

- [x] CSV loads from `res://localization/strings.csv` (UTF-8 with BOM); the BOM is
      stripped from the header cell.
- [x] UK renders Cyrillic correctly: `Ð”ÐµÑ€ÐµÐ²Ð¾`, `Ð¡Ð°Ð¼Ð¾Ñ†Ð²Ñ–Ñ‚Ð¸`, `Ð‘Ð†Ð™`, `Ð—Ð°Ñ…Ð¸ÑÑ‚ Ð”ÐµÑ€ÐµÐ²Ð°`
      verified in a rendered 540x960 screenshot. `CURRENCY_GEMS` was corrected
      from `ÐœÐ¾Ð½ÐµÑ‚Ð¸` (coins) to `Ð¡Ð°Ð¼Ð¾Ñ†Ð²Ñ–Ñ‚Ð¸` in stage 2.
- [x] EN â†” UK toggle retranslates the visible screen immediately (title,
      subtitle, button, currency labels, language button) and persists across
      reload.
- [x] `format_number(12500)` â†’ `12 500` (thin space), `0` â†’ `0`.
- [x] Version placeholder `v{version}` substitutes to `v0.1.0`.
- [x] Unknown/missing keys fall back to the key text rather than crashing.
- [ ] Export packaging: a packaged build has no raw CSV, so `Loc` falls back to
      the compiled `*.translation` resources. The fallback is implemented but not
      yet exercised by an export (stage 7).

## UI

- [x] Desktop window is portrait 540x960 with a 1080x1920 reference; layout was
      captured and inspected: no stretching artifacts, 16:9 canvas maps 1:1.
- [x] Safe-area padding applied on ready and on viewport resize.
- [x] Currency HUD updates live through `EventBus` (`add_gold(1250)` â†’
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

- [x] `MainMenu` â†’ `Battle` (10 s prep â†’ automatic wave 1) â†’ quit
      confirmation â†’ `MainMenu` flow: `TestFlow` prints
      `FLOW TEST PASSED: menu -> battle -> 10 s prep -> wave 1 -> quit -> menu`.
- [x] Fresh run starts with 120 Coins, 1000 Tree HP, 2 archers and a ~10 s
      `PREPARE` (`TestBattle`, 42 checks).
- [x] `CALL WAVE` during prep grants 4-5 Coins at ~10 s left and starts wave 1.
- [x] Enemies spawn outside the arena boundary, converge on the Tree, and
      separation pushes two enemies sharing a spawn point apart (`TestBattle`).
- [x] Archers acquire targets and fire; arrows kill wave 1 with archers only.
- [x] Armor: 10 damage vs 3 armor â†’ 7; vs 30 armor â†’ 1; ignore-armor â†’ 10
      (`TestBattle`).
- [x] Kills add Coins and `+N` popups; wave clear adds `10 + 2*wave`
      (`TestBattle`, `screenshot_battle_popup.png`).
- [x] An enemy at the Tree damages it; the battle builds a `RunSummary` and
      `TestBattle` matches its waves/kills/Coins/time fields.
- [x] Defeat and quit both route to `Results.tscn`; the old in-HUD defeat panel
      was removed in stage 4.
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

- [x] Eight pads exist on a 300 px ring at `22.5Â° + iÂ·45Â°`, none on the vertical
      axis, tap radius 56 px (â‰¥88 px target) (`TestTowers`).
- [x] A tap on an empty pad opens the build sheet; a tap on a built pad opens the
      tower sheet; the sheet pauses the tree (`TestTowers`, injected touch).
- [x] Building deducts the exact cost (60 / 90 / 140), refuses when the Coins are
      short and leaves the balance unchanged on refusal (`TestTowers`).
- [x] Building registers a steering obstacle; selling removes it again
      (`TestTowers`, obstacle radius includes the 18 px margin).
- [x] Upgrade curve: Archer 60 â†’ 95 â†’ 155 (rounded to 5), level 3 shows 34 dmg /
      0.8 s / 500 range, max level disables the button (`TestTowers`).
- [x] Sell refunds 60% of build + upgrades (310 invested â†’ 186), frees the pad
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
      shortfall (`Need 50 more Coins`) â€” `screenshot_battle_build_sheet_locked.png`.
- [x] HUD counter shows `TOWERS 8 / 8`; the `Tap a pad to build` hint hides once
      a tower exists (`screenshot_battle_towers.png`).
- [x] Open sheet + pause: the pause sheet draws on top, resuming keeps the game
      paused while the sheet is open, closing the sheet resumes, and the back
      button closes the sheet first (`TestTowers`,
      `screenshot_battle_sheet_pause.png`).
- [x] 50 open/close cycles of both sheets: node count unchanged (845 â†’ 845) and
      0 orphan nodes (`TestTowers`).
- [x] UK sheet renders Cyrillic (`Ð’ÐµÐ¶Ð° Ð»ÑƒÑ‡Ð½Ð¸ÐºÑ–Ð²`, `ÐœÐÐšÐ¡. Ð Ð†Ð’Ð•ÐÐ¬`, `ÐŸÐ ÐžÐ”ÐÐ¢Ð˜`) in a
      540x960 screenshot; the EN/UK toggle retranslates an open sheet live.
- [x] 8 towers + 69 enemies on the desktop GPU: F3 overlay reads 60 FPS
      (`screenshot_battle_towers_stress.png`). Desktop only â€” not a phone.
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
& $godot --headless --path $proj res://tests/TestMenu.tscn
& $godot --headless --path $proj --fixed-fps 60 res://tests/TestBattle.tscn
& $godot --headless --path $proj --fixed-fps 60 res://tests/TestSoak.tscn
& $godot --headless --path $proj --fixed-fps 60 res://tests/TestTowers.tscn
& $godot --headless --path $proj --fixed-fps 60 res://tests/TestProgression.tscn
& $godot --path $proj res://tools/CaptureTool.tscn        # menu, battle, results shots
& $godot --path $proj res://tools/MenuCapture.tscn        # six menu tabs, EN + UK
```

`CaptureTool` writes `user://screenshot_menu_en.png`, `menu_uk`, `battle_prep`,
`battle_prep_uk`, `battle_wave`, `battle_popup`, `battle_stress`,
`battle_towers`, `battle_towers_stress`, `battle_tower_sheet`,
`battle_tower_sheet_uk`, `battle_tower_sheet_l1`, `battle_build_sheet`,
`battle_build_sheet_locked`, `battle_sheet_pause`, `battle_pause`,
`battle_upgrades`, `battle_upgrades_archers`, `battle_upgrades_uk`,
`battle_modifier`, `battle_boss`, `results_defeat` and `results_defeat_uk`.

## Stage 4 â€” progression, bosses, results, speed

- [x] Six in-run tracks load from `data/upgrades/` with the authored costs
      (`TestProgression`: roots 70 / 100 / 145, extra archer 900 at level 2).
- [x] Roots adds and heals exactly 150 HP; Regrowth adds 2 HP/s and the Tree
      regenerates during battle.
- [x] The upgrade panel opens from UPGRADES during prep and combat, pauses the
      game and switches TREE / ARCHERS / TOWERS.
- [x] Canopy Bows, Elven Haste, Far Sight and Extra Archer change archer values
      immediately (damage 12 -> 13.8, interval 0.8 -> 0.741, range 520 -> 560,
      archers 2 -> 3).
- [x] A boss spawns on wave 10 with the top bar, 1500 HP, 3 s slow immunity,
      summons four runners at 70% and 40%, and enrages below 30%.
- [x] Boss death emits `boss_died` once, counts in the summary and restores the
      selected speed after the 0.3 s slow-mo.
- [x] Wave modifiers begin at wave 8, are deterministic per run seed, are
      announced by a 1.5 s banner and tint/scale the enemies.
- [x] Speed cycles only through unlocked speeds; the lock badge and long-press
      reason work; the prep chip grants 1.5x for one run.
- [x] Results shows correct waves, kills, bosses, time and Coins for defeat and
      for a quit; `TestFlow` covers quit -> Results -> menu, and
      `TestProgression` covers a quit at wave 5 (4 cleared waves -> 52 Gold,
      0 boss Gems).
- [x] Gold = `sum(8 + 2w) * gold_mult`; Gems = `2*floor(N/5) + 5*bosses` plus the
      one-time wave-30 milestone, all floored.
- [x] Rewards are granted once, persist after restart and update best wave.
- [x] DOUBLE GOLD doubles only Gold, once, and an ad failure keeps the base
      reward (`TestProgression`: 112 -> 224, a second press changes nothing, a
      failing provider leaves 112 and re-enables the button).
- [x] Wave 30 sets `flags.milestone_30` and pays +10 Gems only once.
- [x] Elf Level 3 unlocks 1.5x and shows the toast on the results screen.
- [ ] Real Android device pass, 720x1280 layout, real rewarded-ad SDK. Deferred
      to stages 6-7.

## Stage 5 â€” meta menu, upgrades, cards, missions, shop, settings

- [x] Data loads: six cards, eight daily missions, eight achievements, eight shop
      products, eight permanent tracks (`TestMenu`, `ConfigDB` counts).
- [x] Permanent upgrades: `tree_hp` costs 150 then 235; buying three levels
      deducts 1 145 Gold, persists, and `RunStats` starts the next run at
      1 150 Tree HP (`TestMenu`).
- [x] Cards: unlock with Gems, equip, replace, persist across reload; Heartwood
      gives +20% Tree HP and âˆ’10% archer damage through `RunModifiers`; a third
      equip is refused; unknown ids are dropped and the pair is capped at two.
- [x] Daily missions: three deterministic ids for the current date
      (`select_daily(date)` is stable), all eight metric types advance through
      `EventBus`, a claim pays once and survives a reload, and a stale stored
      date resets progress and claims.
- [x] Achievements: derived from persistent stats (1 000 kills, best wave 20,
      10 000 Gold earned), claimed once, and stay claimed after a reload.
- [x] Shop: all eight products grant; the starter bundle and remove-ads cannot
      be granted twice; a gem pack can be bought again; remove-ads sets
      `unlocks.remove_ads`; `MetaShop.restore_owned()` re-applies the flag and is
      idempotent.
- [x] Settings: quality `low` persists and is read by the four VFX guards; the
      locale switches live (tab labels retranslate); music volume reaches the
      Music bus immediately; haptics and locale persist.
- [x] Menu shell: all six tabs open, are cached (six screens after a tour), keep
      their scroll containers, close a modal on back, return to Home from another
      tab, and leave zero orphan nodes (`TestMenu`).
- [x] Localization: 305 CSV keys, no empty EN/UK cells; `TestMenu` checks EN and
      UK strings resolve. All 12 menu captures have full labels, including
      `ÐŸÐžÐšÐ ÐÐ©Ð•ÐÐÐ¯`, `ÐšÐ ÐÐœÐÐ˜Ð¦Ð¯` and `ÐÐÐ›ÐÐ¨Ð¢Ð£Ð’ÐÐÐÐ¯`.
- [x] Windowed menu holds 60 FPS (vsync-limited) on this desktop; no layout
      warnings or repeated errors in the capture log.
- [x] Screenshots `user://screenshot_menu_{home,upgrades,cards,missions,shop,settings}_{en,uk}.png`
      reviewed at 540x960. `MenuCapture` backs up and restores the real save.
- [ ] Android device pass: back button, notched safe areas, 720x1280 layout,
      touch feel. Deferred to stages 6-7 (no device available).
- [ ] Force-close during a purchase, device clock moved backwards, and a real
      billing sandbox. The fake provider and the date guard were tested headless
      only.
- [ ] Reset-progress end-to-end (two dialogs -> wipe -> Boot) and the reward-fly
      animation. Code-reviewed; not executed automatically because the reset
      swaps the running test scene.
- [ ] Real 60 FPS on mid-range Android and 22 ms on 720x1280. Desktop 60 FPS is
      not evidence for either.

## Stage 6 â€” monetization

- [x] Schema v2: a real v1 fixture loads through `SaveMigrations` and
      `SaveManager`, keeps Gold/Gems/upgrades/cards/products/unknown keys and
      gains `ads` defaults. Migration is idempotent (`TestMigrations`, 25 checks).
- [x] Rewarded fake outcomes: success, fail, close and timeout each resolve the
      callback exactly once; a timeout (0.1 s in the test) frees the ad slot; a
      second request while busy is refused while the first still completes
      (`TestMonetization`).
- [x] Consent: a forced deny blocks rewarded ads and purchases; the gate is
      checked before every request and can be toggled from the debug panel.
- [x] Speed trial: the pre-battle ad sets a pending 1.5x trial, a second request
      reports `active`, `Battle.start_run()` consumes it, and `run_ended` clears
      both the pending flag and the run trial. A permanent `speed_15` unlock
      returns `owned` without an ad.
- [x] Double Gold: grants exactly the base reward once, hides the button after
      success, re-enables it after a failed ad, and survives a language change
      without re-granting (`TestProgression`).
- [x] Free Gems: first claim pays 5 Gems and persists the timestamp; an immediate
      second claim is refused by the 4 h cooldown; an elapsed cooldown pays up to
      3 claims; the fourth is refused by the daily cap; a date rollover resets
      the count; a failed ad grants nothing and consumes no claim.
- [x] Interstitial: `AdPolicy` matrix plus integration checks â€” no ad in runs
      1-3, counter held at zero, first eligible show on run 6, reset after a
      successful show, no ad with `remove_ads`, refused while paused.
- [x] Revive: defeat opens the prompt, pauses the tree and offers REVIVE/GIVE UP;
      a successful ad restores 50% HP, clears and pays enemies within 250 px,
      grants the 3 s shield, resumes at the previous speed and marks the revive
      used; a second death goes to results; a failed ad goes to results with no
      penalty (`TestMonetization`).
- [x] Purchases: a gem pack is repeatable, remove_ads and the starter bundle are
      one-time, a double tap grants once, cancel/fail grant nothing, the
      provider reports `PurchaseStatus` and the shop re-enables the card.
- [x] Restore: the fake backend returns owned products, re-applies the
      remove-ads unlock without paying currency and is idempotent; a failing
      backend surfaces an error toast path.
- [x] Debug panel: five taps on the Home version label open it in a debug build;
      force next rewarded success, reset counters and toggle consent were
      exercised; provider, consent, phase, interstitial, free-Gems and run
      counters are shown.
- [x] Real-target fallback: `initialize_providers(true, true)` without plugins
      selects the fake providers and logs warnings, never crashing.
- [x] Localization: 370 keys, EN + UK; the two pre-existing UK rows with a comma
      are now quoted so Godot's CSV parser keeps the full text.
- [x] All headless suites pass on Godot 4.7.2: `TestSave` 46, `TestMigrations` 25,
      `TestMonetization` 136, `TestMenu` 112, `TestProgression` 120,
      `TestBattle` 42, `TestTowers` 74, `TestFlow`, `TestSoak` 5.
- [x] Background/resume during a live rewarded ad resolves `false`, grants
      nothing and releases the ad slot (`TestMonetization` propagates the real
      application notifications through the tree).
- [ ] Android device pass for ads, billing, revive, background/resume and the
      720x1280 layout. No device or store sandbox is available here.
- [ ] Real AdMob and Play Billing sandbox: the adapters compile and are
      reflection-guarded, but no plugin is installed and `USE_REAL_*` stays
      `false`.
- [ ] Kill the app during a fake ad and during a purchase, then relaunch. The
      grant path is synchronous and saved before the UI callback, but the kill
      itself was not executed.
- [x] Windowed screenshot review at 540x960: Home pre-battle panel (EN + UK),
      Shop free-Gems card (EN + UK), revive prompt and debug panel. The long UK
      labels were shortened after the first capture overflowed the Shop width;
      the second pass fits.
- [ ] Results double-Gold spinner and the every-third-run interstitial were not
      captured as screenshots; they are covered by `TestProgression` and
      `TestMonetization` and were code-reviewed.

## Known environment quirks
- **Cold headless import exit code.** After deleting `.godot/`, the first
  `--headless --editor --quit` / `--import` run on this machine finishes the
  import and then dies with an access violation (`0xC0000005`) during editor
  teardown. The import does complete (the save test passes on the next command)
  and every warm run exits 0. It reproduces with the git plugin folder removed
  and with the D3D12 driver override removed, so it is not caused by project
  code. Ignore the exit code of a cold run, or open the project in the editor
  once instead.

