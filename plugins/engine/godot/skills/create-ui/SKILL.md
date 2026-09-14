---
name: create-ui
description: Create Godot UI scenes (Control nodes, menus, HUD). Use when implementing UI screens (main menu, pause menu, HUD, dialogs).
---

## What I do

Creates UI scenes with Control-node hierarchy and a script:

- Root `Control` node (full-rect anchors) with script attached
- `VBoxContainer`/`HBoxContainer` for layout; `Label`, `Button`, `Panel` for content
- Buttons connect `pressed` signals explicitly
- Theme-able: use `theme_override` sparingly; prefer a shared `Theme` resource later

## Conventions

- Menus/dialogs → standalone `.tscn` under `scenes/ui/`
- HUD → composes into the game level scene later (see create-level)
- Every interactive node reachable by focus (keyboard navigable by default)
- Text via `Label`, never baked into textures
- Identify nodes by groups or exported NodePaths, not `.name` lookups

## Done when

Scene loads in `godot --headless` without errors, and buttons respond to
`pressed` in the runtime bridge (input simulation or a smoke-script call).
