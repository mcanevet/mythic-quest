---
name: create-entity
description: Create Godot entity scenes with scripts. Use when implementing game entities (player, enemies, pickups).
---

## What I do

Creates entity scenes and scripts:
- `.tscn` scene with proper node hierarchy (root + collision shape + script)
- `.gd` script with test hooks (`_on_test_verify()`, `_on_test_get_state()`)
- Groups for identification (never rely on `.name`)

## Conventions

- Player/AI movement → CharacterBody2D
- Physics objects → RigidBody2D
- Triggers/pickups → Area2D
- Identify instanced nodes by groups, not names
- Connect signals explicitly; discrete input in `_input`, not polled

## Gotchas

Empirically observed godot-mcp-runtime schema quirks (walkthrough6, 2026-09-15):

- **Colors**: pass `{r, g, b, a}` objects with floats 0–1, not hex strings. `"#1b2a41"` fails; use `{r: 27/255, g: 42/255, b: 65/255, a: 1}`.
- **Scripts**: pass plain `res://` path strings (e.g. `"res://scripts/station.gd"`), not nested objects.
- **Scene root name**: verify the root node name via `godot_get_scene_tree` before writing scripts that reference node paths like `/root/Main/Lamp` — the root name may differ from the scene filename.
- **Polygon2D**: the `polygon` property takes an array of `{x, y}` points.
- **Overlap queries**: `Area2D.get_overlapping_bodies()` won't detect non-physics placeholder nodes; iterate children instead when entities are `Node2D` placeholders.
- **Batch scene operations**: malformed or loosely-formatted JSON payloads fail; keep JSON compact and canonical.
- **Running engine overwrites scene files**: a live `run_project`/playtest serializes runtime state back into `.tscn` files, clobbering concurrent edits. MANDATORY: call `godot_stop_project` BEFORE any scene-file edit (create/edit/save), and only restart the engine after the edit round completes. Evidence: walkthrough6, 2026-09-15.

## Done when

`scripts/validate.sh <res://scenes/....tscn>` (in this skill) runs without
errors — it wraps `godot --headless <scene> --quit-after 1` — and test hooks
respond.
