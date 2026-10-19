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
   `F3` toggles the debug overlay; `Esc` / Android back opens pause.

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
```

`TestBattle` exercises spawning, steering, arrows, armor, Coins, wave clear,
contact damage, pause, quit confirmation and defeat (42 checks). `TestSoak`
simulates ten minutes at fixed 60 FPS and checks orphan/node growth.
`TestTowers` covers pads, build/upgrade/sell maths, tower combat, frost slow,
ballista armor piercing, steering obstacles and sheet pause handling (74 checks).
`TestFlow` drives the menu → battle → quit → menu route.

Optional visual check (dev-only tool, excluded from export):

```
godot --path . res://tools/CaptureTool.tscn
```

writes menu (EN/UK) and battle (prep, wave, 70-enemy stress, pause, defeat)
screenshots to `user://`.

## Layout

```
autoload/            ten singletons (EventBus, SaveManager, GameState, ...)
resources/           typed data classes (EnemyData, WaveEntry, WaveTable,
                     TowerData, TowerLevel)
scripts/core/        save migrations, defaults, spatial hash, ad/IAP providers
scripts/battle/      battle, arena, core, enemy, pools, waves, archers, towers,
                     tower_manager, build/tower sheets, range indicator, HUD
scripts/ui/          screen controllers (Boot, MainMenu, Toast)
scenes/              Boot.tscn, MainMenu.tscn, battle/*.tscn
ui/                  theme.tres, Toast.tscn, TowerCard.tscn, tower_icon.gd
data/                .tres balance data (enemies, waves, towers; more later)
localization/        strings.csv (EN + UK, UTF-8 with BOM)
tests/               headless smoke, tower and soak tests
tools/               dev-only helpers, excluded from export
docs/                decisions, QA checklist, architecture
```

## Status

Stage 3 complete: eight build pads, three tower types with three levels each,
targeting modes, frost slow, armor-piercing ballista bolts, selling, and towers
as steering obstacles. Stage 4 adds the in-run upgrade panel, bosses, wave
modifiers, results and rewards (see `docs/ARCHITECTURE.md`).
