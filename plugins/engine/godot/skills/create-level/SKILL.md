---
name: create-level
description: Create full Godot level scenes composing entities and UI. Use when assembling a playable game level.
---

## What I do

Assembles a complete game level by composing entity scenes, UI elements, and layout:

- Root `Node2D` (level) with exported NodePaths or groups for player spawner, checkpoints, win/fail triggers
- Instanced entity scenes (player, enemies, pickups) with proper transforms
- TileMap layer(s) for terrain/background
- Camera node (follows player via script or tween)
- HUD instance (from create-ui) anchored to viewport
- Optional: ambient audio, particle emitters, light sources

## Conventions

- Levels live under `scenes/levels/` (e.g., `level_01.tscn`)
- Player spawner → instanced player scene with transform override
- Win/fail conditions → Area2D triggers with scripts that emit signals
- Camera follow logic in a dedicated `CameraController.gd` (tween or direct follow)
- Exported NodePaths for critical references (player, goal, hazards)

**Sanctioned-paths-only**: mutate scene files exclusively through MCP tools; direct `.tscn` edits are not permitted — report `⛔ BLOCKED: tool cannot express <operation>` if a needed operation is unavailable. See create-entity SKILL.md for the full rule.

## Done when

Level loads cleanly via `.agents/plugins/engine/godot/skills/create-level/scripts/validate.sh <scene>` (wraps
`godot --headless`), camera follows player, win/fail triggers fire,
HUD updates, and the runtime bridge can screenshot/verify state transitions.
