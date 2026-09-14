---
name: init-project
description: Scaffold a Godot project. Use when starting a new Godot game.
---

## What I do

Creates the minimal Godot 4 project structure:
- `project.godot` — config (config_version=5, app name, viewport) with:
  - `run/main_scene` set (empty placeholder scene or first real scene)
  - input map: `move_left`, `move_right`, `jump` (keyboard defaults)
- `icon.svg` — placeholder icon
- `.gitignore` — standard Godot ignores (`.godot/`, `*.import`)

## Done when

`godot --headless --quit` runs without errors AND every input action
referenced by game scripts exists in the input map.
