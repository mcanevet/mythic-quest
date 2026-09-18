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

## Property values (common gotchas)

- **Label font sizing**: `Label` nodes do NOT have a `font_size` property. Use
  `theme_override_font_sizes/font_size` instead. Example:
  `{ "property": "theme_override_font_sizes/font_size", "value": 16 }`
- **Button pressed state**: use `button_pressed` (not `pressed`) when setting
  the initial state programmatically.

**Sanctioned-paths-only**: mutate scene files exclusively through MCP tools; direct `.tscn` edits are not permitted — report `⛔ BLOCKED: tool cannot express <operation>` if a needed operation is unavailable. See create-entity SKILL.md for the full rule.

## Done when

Scene loads cleanly via `scripts/validate.sh <scene>` (in this skill — wraps
`godot --headless`) without errors, and buttons respond to
`pressed` in the runtime bridge (input simulation or a smoke-script call).
