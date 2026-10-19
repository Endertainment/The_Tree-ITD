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
   archers. `F3` toggles the debug overlay; `Esc` / Android back opens pause.

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
```

`TestBattle` exercises spawning, steering, arrows, armor, Coins, wave clear,
contact damage, pause, quit confirmation and defeat (42 checks). `TestSoak`
simulates ten minutes at fixed 60 FPS and checks orphan/node growth. `TestFlow`
drives the menu → battle → quit → menu route.

Optional visual check (dev-only tool, excluded from export):

```
godot --path . res://tools/CaptureTool.tscn
```

writes menu (EN/UK) and battle (prep, wave, 70-enemy stress, pause, defeat)
screenshots to `user://`.

## Layout

```
autoload/            ten singletons (EventBus, SaveManager, GameState, ...)
resources/           typed data classes (EnemyData, WaveEntry, WaveTable)
scripts/core/        save migrations, defaults, spatial hash, ad/IAP providers
scripts/battle/      battle, arena, core, enemy, pools, waves, archers, HUD
scripts/ui/          screen controllers (Boot, MainMenu, Toast)
scenes/              Boot.tscn, MainMenu.tscn, battle/*.tscn
ui/                  theme.tres, Toast.tscn
data/                .tres balance data (enemies, waves; more in later stages)
localization/        strings.csv (EN + UK, UTF-8 with BOM)
tests/               headless smoke and soak tests
tools/               dev-only helpers, excluded from export
docs/                decisions, QA checklist, architecture
```

## Status

Stage 2 complete: playable, losable battle loop with data-driven orc waves,
steering and separation, elf archers and homing arrows, Coins, pause, defeat and
a results stub. Towers and build pads start in stage 3
(see `docs/ARCHITECTURE.md`).
