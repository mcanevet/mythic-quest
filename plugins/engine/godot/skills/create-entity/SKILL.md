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

## Done when

Scene loads in `godot --headless` without errors and test hooks respond.
