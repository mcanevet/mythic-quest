---
name: init-project
description: Scaffold a Godot project. Use when starting a new Godot game.
---

## What I do

Creates the minimal Godot 4 project structure:
- `project.godot` — project config (config_version=5, app name, viewport)
- `icon.svg` — placeholder icon
- `.gitignore` — standard Godot ignores (`.godot/`, `*.import`)

## Done when

`godot --headless --quit` runs inside the project without errors.
