---
name: apply-animation
description: Animate entities (movement, spawn, hit, idle, transitions). Use when adding motion/life to existing entities.
---

## What I do

Adds animation to existing entities:
- `AnimationPlayer` nodes with tracks (property, method call, audio)
- Tween-based procedural animation (`create_tween()`) for one-shots (hit flash, pickup bob, death)
- Sprite frame animation via `AnimatedSprite2D` + `SpriteFrames` for cycles (idle, walk, attack)
- Scene transitions (fade in/out) via `CanvasLayer` + tween

## Conventions

- Tweens for one-shot effects; AnimationPlayer for authored, reusable clips
- Frame animation via procedurally-built `SpriteFrames` (sub-image slicing or color-rect frames) — no binary asset imports
- Animate groups-referenced nodes, never `.name`
- Timing values live in exported constants (`@export var duration: float = 0.3`) for tunability
- Verify animation actually plays via MCP `run_project` + `simulate_input` + `take_screenshot` sequence

## Done when

Observed via MCP runtime: the animated behavior fires at the right trigger with no script errors.
