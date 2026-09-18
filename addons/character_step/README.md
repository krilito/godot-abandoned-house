# Character Step (runtime library)

Not an editor plugin. There is no `plugin.cfg` on purpose.

This folder holds the single reusable static class used by `res://player.gd`:

- `character_step.gd` — `class_name CharacterStep3D`
- License: MIT, PantheraDigital

## Source

- Official demo / docs: https://github.com/PantheraDigital/GodotCharacterStep
- Isolated full demo (do not import into this Godot project):
  `D:\游戏教学\Godot_Reference_Library\GodotCharacterStep`

## Usage

Call `step_up()` **before** `move_and_slide()`, `step_down()` **after**.
Do not attach the third-person demo player. Our first-person `player.gd` already wraps this class.

## Why it lives in `addons/`

It is third-party runtime code. It must not live in `res://scripts/` (our code) and must not include the author's demo `project.godot` / scenes.
