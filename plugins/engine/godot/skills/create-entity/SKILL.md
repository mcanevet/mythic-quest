---
name: create-entity
description: Create Godot entity scenes with scripts (CharacterBody2D, RigidBody2D, Area2D). Use when implementing game entities (player, enemies, pickups, obstacles).
---

## What I do

Creates complete Godot entity scenes:
- `.tscn` scene file with proper node hierarchy
- `.gd` script with architecture patterns
- Supporting resources (collision shapes, placeholder art)

## Execution

### Step 1: Context Discovery

Read the claimed bead's description to extract:
- Entity type (Player, Enemy, Pickup, Obstacle)
- Root node type (CharacterBody2D, RigidBody2D, Area2D)
- Required child nodes and signals
- Definition of Done

### Step 2: Plan the scene

Document the node hierarchy before creating files.

### Step 3: Create scene file (.tscn)

Write the scene with:
- Proper node types and inheritance
- Collision shapes (CollisionShape2D for physics nodes)
- Groups for identification (never rely on `.name`)
- Script attachment

### Step 4: Create script (.gd)

Write the script with:
- Proper extends clause
- Signals as declared in the scene
- Test hooks (`_on_test_verify()`, `_on_test_get_state()`)
- Architecture patterns from project docs

### Step 5: Validate

Run validation checks (collision shapes present, signals connected, groups set).
