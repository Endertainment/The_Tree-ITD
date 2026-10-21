# The Tree â€” ITD

Wave-based tower defense for Android. The Life Tree stands at the center of an
ancient grove; orc hordes pour in from every direction and there is no road, only
open ground.

- Engine: **Godot 4.7** (`mobile` renderer), GDScript only â€” no C#, no .NET.
- Orientation: **portrait**, reference resolution **1080 x 1920**.
- Target: Android 8.0+ (API 26), ARM64.

## Run it

1. Open the project folder in Godot 4.7.
2. Press `F5`. Boot shows for ~0.8 s, then the main menu.
3. The menu has six tabs: **Home**, **Upgrades**, **Cards**, **Missions**, **Shop**
   and **Settings**. Home holds the pre-battle panel (best wave, difficulty,
   equipped cards, `SPEED TRIAL` ad and `BATTLE`), the Elf Level, the daily
   summary and the version label. Upgrades spends Gold on eight permanent
   tracks, Cards unlocks six Gem cards (equip two), Missions shows three daily
   missions plus eight achievements, Shop is a fake-IAP grid with restore and a
   free-Gems ad, and Settings covers audio, haptics, language, quality and reset.
4. Press `BATTLE` for a run: 10 s preparation, then orc waves with two elf
   archers. Tap one of the eight stone pads to build an Archer Tower, Spirit
   Tower or Ballista; tap a built tower to upgrade, retarget or sell it.
   `UPGRADES` opens the in-run panel (Tree / Archers / Towers). Every tenth
   wave is a boss (Warlord and airship alternate), wave modifiers start at wave 8, and the run ends on
   `Results` with Gold and Gems (the optional double-Gold ad is there). A defeat
   first offers one rewarded revive. `F3` toggles the debug overlay; `Esc` /
   Android back closes a sheet, then returns Home, then asks before exiting.

On desktop the window opens at 540x960 (half-scale of the reference resolution).

Debug-only shortcut straight into the battle:

```
godot --path . --debug-battle
```

## Test it

Headless suites (one import pass first: `godot --headless --import --path .`):

```
godot --headless --path . res://tests/TestSave.tscn
godot --headless --path . res://tests/TestFlow.tscn
godot --headless --path . res://tests/TestMenu.tscn
godot --headless --path . --fixed-fps 60 res://tests/TestBattle.tscn
godot --headless --path . --fixed-fps 60 res://tests/TestSoak.tscn
godot --headless --path . --fixed-fps 60 res://tests/TestTowers.tscn
godot --headless --path . --fixed-fps 60 res://tests/TestProgression.tscn
godot --headless --path . res://tests/TestMigrations.tscn
godot --headless --path . res://tests/TestMonetization.tscn
godot --headless --path . res://tests/TestGlyphs.tscn
godot --headless --path . --fixed-fps 60 res://tests/TestPolish.tscn
```

`TestMenu` covers the meta layer: data counts, permanent upgrades reaching
`RunStats` (tree_hp level 3 -> 1 150 HP), card unlock/equip/replace and
persistence, all eight daily metrics, claim idempotency, date rollover,
achievement derivation, all eight shop grants, restore, settings persistence,
and the six-tab shell including modal/back behaviour and the debug 5-tap
(112 checks).

`TestBattle` exercises spawning, steering, arrows, armor, Coins, wave clear,
contact damage, pause, quit confirmation and defeat (42 checks). `TestSoak`
simulates ten minutes at fixed 60 FPS and checks orphan/node growth.
`TestTowers` covers pads, build/upgrade/sell maths, tower combat, spirit root,
ballista armor piercing, steering obstacles and sheet pause handling (74 checks).
`TestProgression` covers upgrade costs/effects, boss thresholds and enrage, wave
modifiers, results maths, persistence and the speed matrix (120 checks).
`TestMigrations` loads a real v1 fixture, migrates it to v2 and checks that
currencies, upgrades, cards, products and unknown keys survive (25 checks).
`TestMonetization` covers every fake ad outcome, the 15 s timeout, busy
handling, the speed-trial hand-off, free-Gems cooldowns and caps, the
interstitial cadence, revive, purchase idempotency, restore, consent and the
debug panel (136 checks).
`TestFlow` drives the menu → battle → quit → results → menu route.

`TestGlyphs` renders the Ukrainian alphabet plus every character used in the
`uk` column of `strings.csv` and fails if the theme font cannot draw one
(16 checks). `TestPolish` covers safe-area inset maths for notched 1080x1920 and
720x1280 profiles, the camera trauma decay and its low-quality gate, the
120-particle cap, the sound library and aliases, -6 dB pause ducking, Ukrainian
plural rules (1 / 2 / 5 / 11 / 21 / 22 / 25), localized percent and duration
formatting, and the tutorial state machine (54 checks).

Optional visual check (dev-only tools, excluded from export):

```
godot --path . res://tools/CaptureTool.tscn
godot --path . res://tools/MenuCapture.tscn
```

`CaptureTool` writes menu, battle, sheets, pause, upgrade panel, boss bar and
results screenshots to `user://`. `MenuCapture` writes the six menu tabs in EN
and UK (`user://screenshot_menu_<tab>_<locale>.png`), then restores your real
save files from its temporary backup.

## Layout

```
autoload/            ten singletons (EventBus, SaveManager, GameState, ...)
resources/           typed data classes (EnemyData, WaveEntry, WaveTable,
					 TowerData, TowerLevel, UpgradeTrack, CardData,
					 StatModifier, MetaUpgradeData, MissionData, ShopProduct,
					 StoreConfig)
scripts/core/        save migrations, defaults, spatial hash, ad/IAP providers,
					 AdPolicy, AdsFlow, PurchaseFlow, ConsentManager
scripts/battle/      battle, run_modifiers, run_stats, wave_rules, wave_manager,
					 boss, arena, core, enemy, pools, archers, towers,
					 tower_manager, sheets, results, revive prompt,
					 range indicator, HUD
scripts/meta/        mission tracker, shop grants, stat text
scripts/ui/          screen controllers (Boot, MainMenu, Toast, SpeedButton,
					 AdSpinner, BossBar, WaveBanner, RewardCounter)
scripts/ui/menu/     Home, PreBattle, Upgrades, Cards, Missions, Shop, Settings,
					 widgets, modal sheet
scenes/              Boot.tscn, menu/*.tscn, battle/*.tscn, ui/ModalSheet.tscn,
					 ui/AdSpinner.tscn, ui/debug/MonetizationDebug.tscn
ui/                  theme.tres, Toast.tscn, TowerCard.tscn, stage-4 widgets,
					 AdSpinner.tscn, debug panel
data/                .tres balance data (enemies, waves, towers, upgrades,
					 meta_upgrades, cards, missions, shop, monetization)
localization/        strings.csv (EN + UK, UTF-8)
tests/               headless save, flow, menu, battle, tower, progression,
					 migration, monetization and soak tests
tools/               dev-only helpers, excluded from export
docs/                decisions, QA checklist, architecture, economy
```

## Status

Stage 7 complete. Presentation layer and Android build:

- **Localization** — every scene string is a translation key, ~390 keys in
  `strings.csv` for `en`/`uk`, Ukrainian glyph coverage proven by
  `TestGlyphs`, thin-space number grouping, localized percent and duration,
  and `Loc.plural()` with Ukrainian 1 / 2-4 / 5+ rules.
- **Audio** — `default_bus_layout.tres` (Master → Music / SFX / UI), 12
  synthesized SFX plus a 30 s loop generated by
  `tools/gen_placeholder_sfx.gd`, -6 dB pause ducking, and every pooled voice
  stopped on scene change. Slots and replacement steps: `docs/ASSET_SLOTS.md`.
- **Combat feedback** — pooled particle bursts (hit sparks, death puffs, coin
  sparkles, leaf bursts, summon rings) capped at 120 alive, trauma-decay camera
  shake, damage numbers behind a setting, red damage vignette, and a
  `quality = low` path that drops shake, sparkles and damage numbers.
- **Tutorial** — three non-blocking steps (build, upgrade, call wave) with 20 s
  fallbacks, SKIP, boss-wave suppression and Settings → Replay tutorial.
- **Device behaviour** — safe-area insets on menu, results and HUD, portrait
  immersive, focus-loss muting and pausing, gated haptics (15 ms UI / 30 ms Tree
  hit / 60 ms boss), and a debug console on `F2`
  (`LOCALE en|uk`, `BENCHMARK`, `HELP`).
- **Android** — `export_presets.cfg`, generated adaptive icons and splash, and a
  verified debug APK: `com.endertainment.thetree`, minSdk 24, arm64 + armv7,
  signed, 56.2 MB. Build steps: `docs/BUILD_ANDROID.md`.

Stage 6 delivered one `Monetization` facade over fake AdMob/Billing providers,
rewarded speed-trial, double-Gold and revive flows, free Gems with a persisted
4 h / 3-per-day policy, the every-third-run results interstitial, a v2 save
schema with a v1 migration, a consent gate and a debug panel behind five taps on
the version label. Real SDK adapters are written but disabled until accounts and
IDs exist.
