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
3. Press `BATTLE` for a run: 10 s preparation, then orc waves with two elf
   archers. Tap one of the eight stone pads to build an Archer Tower, Frost
   Spire or Ballista; tap a built tower to upgrade, retarget or sell it.
   `UPGRADES` opens the in-run panel (Tree / Archers / Towers). Every tenth
   wave is a boss, wave modifiers start at wave 8, and the run ends on
   `Results` with Gold and Gems. `F3` toggles the debug overlay; `Esc` /
   Android back opens pause.

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
godot --headless --path . --fixed-fps 60 res://tests/TestBattle.tscn
godot --headless --path . --fixed-fps 60 res://tests/TestSoak.tscn
godot --headless --path . --fixed-fps 60 res://tests/TestTowers.tscn
godot --headless --path . --fixed-fps 60 res://tests/TestProgression.tscn
```

`TestBattle` exercises spawning, steering, arrows, armor, Coins, wave clear,
contact damage, pause, quit confirmation and defeat (42 checks). `TestSoak`
simulates ten minutes at fixed 60 FPS and checks orphan/node growth.
`TestTowers` covers pads, build/upgrade/sell maths, tower combat, frost slow,
ballista armor piercing, steering obstacles and sheet pause handling (74 checks).
`TestProgression` covers upgrade costs/effects, boss thresholds and enrage, wave
modifiers, results maths, persistence and the speed matrix (120 checks).
`TestFlow` drives the menu → battle → quit → results → menu route.

Optional visual check (dev-only tool, excluded from export):

```
godot --path . res://tools/CaptureTool.tscn
```

writes menu (EN/UK), battle (prep, wave, stress, sheets, pause), the upgrade
panel (EN/UK, both tabs), a modifier banner, the boss bar and the results screen
(EN/UK) to `user://`.

## Layout

```
autoload/            ten singletons (EventBus, SaveManager, GameState, ...)
resources/           typed data classes (EnemyData, WaveEntry, WaveTable,
                     TowerData, TowerLevel, UpgradeTrack, CardData)
scripts/core/        save migrations, defaults, spatial hash, ad/IAP providers
scripts/battle/      battle, run_modifiers, run_stats, wave_rules, wave_manager,
                     boss, arena, core, enemy, pools, archers, towers,
                     tower_manager, sheets, results, range indicator, HUD
scripts/meta/        mission hooks (stage-4 bridge, full missions in stage 5)
scripts/ui/          screen controllers (Boot, MainMenu, Toast, SpeedButton,
                     BossBar, WaveBanner, RewardCounter)
scenes/              Boot.tscn, MainMenu.tscn, battle/*.tscn
ui/                  theme.tres, Toast.tscn, TowerCard.tscn, stage-4 widgets
data/                .tres balance data (enemies, waves, towers, upgrades)
localization/        strings.csv (EN + UK, UTF-8 with BOM)
tests/               headless smoke, tower, progression and soak tests
tools/               dev-only helpers, excluded from export
docs/                decisions, QA checklist, architecture
```

## Status

Stage 4 complete: `RunModifiers`/`RunStats`, six in-run upgrade tracks, bosses on
every tenth wave with summons and enrage, deterministic wave modifiers, the
results screen with Gold/Gems payout and the double-Gold ad hook, persisted
stats/best wave/milestone, Elf Level, and 1x/1.5x/2x speed control. Stage 5
adds the full meta menu (upgrades, cards, missions, shop, settings); see
`docs/ARCHITECTURE.md`.
