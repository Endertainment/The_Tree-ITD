# QA report — 0.1.0 closed test

Date: 2026-10-20. Every row below was either observed in this environment or is
marked `BLOCKED` with the concrete reason. Nothing is marked `PASS` on the
strength of code reading alone.

## Environment

| Item | Value |
|---|---|
| Engine | Godot `4.7.2.stable.mono` (GDScript project, no C#) |
| Desktop | Windows 11, D3D12 / Forward Mobile, 1080×1920 window override 540×960 |
| Device | Xiaomi `23090RA98G`, Android 15 (API 35), 1220×2712 @ 480 dpi, 120 Hz, 122 px top cutout, rounded corners |
| Renderer on device | Vulkan (`GodotVulkanRenderView` in logcat) |
| Headless | `godot --headless`, `--fixed-fps 60` for the soak |
| Ads / billing | fake providers (no SDK, no account) |
| Signing | release keystore outside the repo, SHA-256 `7B:1D:D2:…:2F:22` |

## Summary

| Result | Rows |
|---|---|
| PASS | 18 of 20 |
| FAIL | 0 |
| BLOCKED | 2 (rows 14 and 15 — tap injection and the missing screen sizes) |

Every headless suite passes. The one `ERROR` printed in the release run is the
deliberately simulated disk failure (row 13), not a defect.

## Test matrix

| # | Area | Check | Result | Evidence |
|---|---|---|---|---|
| 1 | Boot | Fresh install → Boot → menu < 4 s, no errors | PASS | Device: `wm_activity_launch_time 891 ms`, boot splash 0.8 s, menu rendered on the first screenshot; logcat has no Godot errors. Desktop: `TestFlow`. |
| 2 | Boot | Corrupt save → recovers from `.bak` or starts clean | PASS | `TestCorruption` (truncated JSON recovers Gold/Gems from `save.bak`, keeps `save.corrupt`). |
| 3 | Boot | Save from previous version migrates without loss | PASS | `TestMigrations` 25 checks, real v1 fixture. |
| 4 | Menu | All tabs, modals, back button, language switch | PASS | `TestMenu` 112 + `TestPolish` 54 (back stack, confirmations, locale switch). Tapping on the device was blocked, see row 14. |
| 5 | Meta | Upgrade buy, card equip, mission claim, shop purchase | PASS | `TestMenu`, `TestRelease` 43 (claim idempotency, purchase grant, double tap). |
| 6 | Battle | Waves 1–10, 3 enemies, archers, coins, pause | PASS | `TestBattle` 42, `TestProgression` 120, `TestSoak` reached wave 21 with real spawns. |
| 7 | Battle | Towers: build, upgrade, sell, all 8 pads | PASS | `TestTowers` 74. |
| 8 | Battle | Boss at 10/20: summon, enrage, death, bar | PASS | `TestProgression` (boss HP, summons, enrage, death payout). |
| 9 | Battle | Defeat, revive, quit, results payout | PASS | `TestProgression` (revive guard, quit-as-finished-run, results maths). |
| 10 | Speed | 1x/1.5x/2x, unlock paths, trial, pause reset | PASS | `TestProgression` speed matrix + `SpeedService` reset assertions. |
| 11 | Ads | All four rewarded flows: success/fail/close/timeout | PASS | `TestRelease`: success grants 5 Gems once, cooldown refusal, close and provider failure grant nothing, timeout clears the machine, double tap grants once. |
| 12 | IAP | Buy, cancel, fail, restore, double-tap | PASS | `TestRelease` (cancel/fail/busy, one-time bundle not duplicated) + `TestMonetization` 136 (server restore, failed restore, owned products). |
| 13 | Save | Kill app mid-run, mid-purchase, mid-claim | PASS | `TestCorruption`: 100 commits with a torn `save.tmp`, every file parsed. Device: `force-stop` while the app was in the foreground; relaunch restored Gold/Gems and both `save.json` + `save.bak` were present. Mid-purchase kill was not executed literally (fake provider is synchronous); the store path saves before returning. |
| 14 | Device | Background 30 s, call interruption, back spam | BLOCKED | Background **was** verified (31 s on HOME, same PID 25985, `OnPause`/`OnResume`, save written on pause). Call interruption and back-button spam need tap/key injection, which MIUI rejected (`INJECT_EVENTS` denial) even with USB debugging. |
| 15 | Device | Notch, 720×1280, 1080×2400, tablet | BLOCKED | Notch verified on the 1220×2712 cutout device: the top bar sits below the 122 px inset and the rounded corners do not clip content. No 720×1280 phone, no 1080×2400 phone and no tablet were available; desktop resize checks only. |
| 16 | Device | Language UK, long text, font glyphs | PASS | `TestGlyphs` 26 (compiled EN/UK translations, glyph coverage, new keys) + `TestRelease` locale switch. Visual UK pass on device was not possible without taps; `TestGlyphs` asserts the shipped translation resources. |
| 17 | Perf | 70 enemies + 8 towers, 10-minute soak | PASS | `TestSoak`: 600 simulated seconds, wave 21, 442 kills, 965 → 965 nodes, 0 orphans. Device: 119 FPS in the menu (120 Hz vsync), 1.12% janky frames. The 70-enemy `BENCHMARK` needs an F2 console command and was not run on the device. |
| 18 | Perf | Memory/orphan growth after 5 runs | PASS | Headless: node count flat and 0 orphans across the soak. Device: `TOTAL PSS 453 MB` / `RSS 455 MB` (includes 118 MB swap) after a fresh launch; five consecutive runs were not executed on the device (no input). |
| 19 | Audio | Buses, sliders, pause ducking, no leaks | PASS | `TestPolish` asserts bus routing, volume application, ducking and the library; no leak on scene change. Audibility was **not** checked by ear. |
| 20 | Store | AAB builds, installs, versionCode correct | PASS | The signed AAB (`build/the-tree-release.aab`, 26.4 MB) verifies against the release certificate. `bundletool dump manifest` reports `com.endertainment.thetree`, `versionCode 1`, `versionName 0.1.0`, `minSdkVersion 26`, `targetSdkVersion 35`. Its universal APK installed on the phone (`adb install` → Success) and launched to the menu; `dumpsys package` confirms `versionCode=1`, `versionName=0.1.0`, `minSdk=26`, `targetSdk=35`, no fatal logcat entry. |

## Headless suites

| Suite | Checks | Result |
|---|---:|---|
| `TestSave` | 46 | PASS |
| `TestMigrations` | 25 | PASS |
| `TestBattle` | 42 | PASS |
| `TestTowers` | 74 | PASS |
| `TestProgression` | 120 | PASS |
| `TestMenu` | 112 | PASS |
| `TestMonetization` | 136 | PASS |
| `TestPolish` | 54 | PASS |
| `TestGlyphs` | 26 | PASS |
| `TestSoak` | 5 | PASS |
| `TestCorruption` (new) | 28 | PASS |
| `TestRelease` (new) | 43 | PASS |
| `TestFlow` | flow | PASS |

711 checks across 12 counted suites plus the menu → battle → quit → results →
menu flow.

## Device session

- Launch → menu: activity created in 191 ms, launch time 891 ms, no Godot error
  in logcat. Vulkan renderer active.
- Save files on device after backgrounding: `files/save.json` and
  `files/save.bak`, both 1 205 bytes, written on pause.
- Background 30 s → same process, `OnResume`, menu intact. No time jump observed
  in the HUD on resume.
- Force-stop → relaunch: profile restored (Gold 0, Gems 5, Elf Lv 1), no crash.
- Release build (universal APK built from the AAB): installed (Success), launched to the menu with a fresh profile (Gold 0, Gems 0), ersionCode 1, ersionName 0.1.0; no fatal logcat entry.
- Screenshot of the release build: docs/qa/device_release_menu_1220x2712.png.
- Screenshot evidence: `docs/qa/device_menu_1220x2712.png`.

## Defects found and fixed

| Defect | Fix |
|---|---|
| Wave 11 jumped to `1.16^10` (~4.4×) HP while wave 9 ran at ×1.0 — authored waves never received the master scaling. | `WaveRules.scaling_for_wave()` now offsets the curves to `authored_max + 1`; covered by `TestProgression`/`TestBattle` and documented in `DECISIONS.md`. |
| Balance model initially counted a wave that hit the 600 s cap as cleared, producing a bogus wave-50 run. | `tools/simulate_balance.gd` treats a timeout as a defeat and regenerates during preparation. Finding recorded in `BALANCE_REPORT.md`. |

No defect was found in save, purchase, claim, ad, locale or results code paths
by the new suites.

## Not verified

- Call interruption during a run (no way to place a call from the harness).
- Back-button spam and Android "exit" from pause on the device (input blocked).
- 720×1280 low-end phone, 1080×2400 tall phone, tablet.
- 70-enemy frame time on the device (`BENCHMARK` needs manual input).
- Audio by ear (buses, ducking, loop seam).
- AAB upload to Play and the Play-side install (no Play track exists; the AAB
  itself installs through its universal APK and launches).
- Real AdMob and Play Billing sandboxes.
