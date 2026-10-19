# The Tree — ITD

Wave-based tower defense for Android. The Life Tree stands at the center of an
ancient grove; orc hordes pour in from every direction and there is no road, only
open ground.

- Engine: **Godot 4.7** (`mobile` renderer), GDScript only — no C#, no .NET.
- Orientation: **portrait**, reference resolution **1080 x 1920**.
- Target: Android 8.0+ (API 26), ARM64.

## Run it

1. Open the project folder in Godot 4.7.
2. Press `F5`. Boot shows for ~0.8 s, then the placeholder main menu.

On desktop the window opens at 540x960 (half-scale of the reference resolution).

## Test it

Headless save-system test (needs no editor, but does need one import pass the
first time: `godot --headless --import --path .`):

```
godot --headless --path . res://tests/TestSave.tscn
```

Success prints `ALL SAVE TESTS PASSED` and exits with code 0.

Optional visual check (dev-only tool, excluded from export):

```
godot --path . res://tools/CaptureTool.tscn
```

writes `user://screenshot_menu_en.png` and `user://screenshot_menu_uk.png`.

## Layout

```
autoload/            ten singletons (EventBus, SaveManager, GameState, ...)
scripts/core/        save migrations, defaults, ad/IAP provider interfaces
scripts/ui/          screen controllers (Boot, MainMenu, Toast)
scenes/              Boot.tscn, MainMenu.tscn, reserved battle/ui folders
ui/                  theme.tres, Toast.tscn
data/                .tres balance data (empty until stage 2)
localization/        strings.csv (EN + UK, UTF-8 with BOM)
tests/               headless smoke tests
tools/               dev-only helpers, excluded from export
docs/                decisions, QA checklist, architecture
```

## Status

Stage 1 complete: project settings, autoloads, save system, localization
scaffolding, Boot → placeholder menu. Gameplay starts in stage 2
(see `docs/ARCHITECTURE.md`).
