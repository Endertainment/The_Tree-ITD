# The Tree — ITD

Wave-based tower defense for Android. The Life Tree stands at the center of an
ancient grove; orc hordes pour in from every direction and there is no road, only
open ground.

- Engine: **Godot 4.7** (`mobile` renderer), GDScript only — no C#, no .NET.
- Orientation: **portrait**, reference resolution **1080 x 1920**.
- Target: Android 8.0+ (API 26), ARM64.

## Run it

1. Open the project folder in Godot 4.7.
2. Press `F5`. Boot shows for ~0.8 s, then the main menu.
3. The menu has six tabs: **Home**, **Upgrades**, **Cards**, **Missions**, **Shop**
   and **Settings**. Home holds the `BATTLE` button, best wave, Elf Level, the
   daily summary and the equipped cards. Upgrades spends Gold on eight permanent
   tracks, Cards unlocks six Gem cards (equip two), Missions shows three daily
   missions plus eight achievements, Shop is a fake-IAP grid with restore, and
   Settings covers audio, haptics, language, quality and reset.
4. Press `BATTLE` for a run: 10 s preparation, then orc waves with two elf
   archers. Tap one of the eight stone pads to build an Archer Tower, Frost
   Spire or Ballista; tap a built tower to upgrade, retarget or sell it.
   `UPGRADES` opens the in-run panel (Tree / Archers / Towers). Every tenth
   wave is a boss, wave modifiers start at wave 8, and the run ends on
   `Results` with Gold and Gems. `F3` toggles the debug overlay; `Esc` /
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
```

`TestMenu` covers the meta layer: data counts, permanent upgrades reaching
`RunStats` (tree_hp level 3 -> 1 150 HP), card unlock/equip/replace and
persistence, all eight daily metrics, claim idempotency, date rollover,
achievement derivation, all eight shop grants, restore, settings persistence,
and the six-tab shell including modal/back behaviour (110 checks).

`TestBattle` exercises spawning, steering, arrows, armor, Coins, wave clear,
contact damage, pause, quit confirmation and defeat (42 checks). `TestSoak`
simulates ten minutes at fixed 60 FPS and checks orphan/node growth.
`TestTowers` covers pads, build/upgrade/sell maths, tower combat, frost slow,
ballista armor piercing, steering obstacles and sheet pause handling (74 checks).
`TestProgression` covers upgrade costs/effects, boss thresholds and enrage, wave
modifiers, results maths, persistence and the speed matrix (120 checks).
`TestFlow` drives the menu → battle → quit → results → menu route.

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
                     StatModifier, MetaUpgradeData, MissionData, ShopProduct)
scripts/core/        save migrations, defaults, spatial hash, ad/IAP providers
scripts/battle/      battle, run_modifiers, run_stats, wave_rules, wave_manager,
                     boss, arena, core, enemy, pools, archers, towers,
                     tower_manager, sheets, results, range indicator, HUD
scripts/meta/        mission tracker, shop grants, stat text
scripts/ui/          screen controllers (Boot, MainMenu, Toast, SpeedButton,
                     BossBar, WaveBanner, RewardCounter)
scripts/ui/menu/     Home, Upgrades, Cards, Missions, Shop, Settings, widgets,
                     modal sheet
scenes/              Boot.tscn, menu/*.tscn, battle/*.tscn, ui/ModalSheet.tscn
ui/                  theme.tres, Toast.tscn, TowerCard.tscn, stage-4 widgets
data/                .tres balance data (enemies, waves, towers, upgrades,
                     meta_upgrades, cards, missions, shop)
localization/        strings.csv (EN + UK, UTF-8 with BOM)
tests/               headless save, flow, menu, battle, tower, progression and
                     soak tests
tools/               dev-only helpers, excluded from export
docs/                decisions, QA checklist, architecture, economy
```

## Status

Stage 5 complete: the six-tab meta menu (Home, Upgrades, Cards, Missions, Shop,
Settings), eight permanent Gold tracks feeding `RunModifiers`, six Gem cards
with equip/replace, three deterministic daily missions plus eight achievements,
a fake-IAP shop with exactly-once grants and restore, persisted settings with a
two-step reset, full EN/UK strings and `docs/ECONOMY.md`. Stage 6 adds real ad
and billing adapters on top of the existing facade; see `docs/ARCHITECTURE.md`.
