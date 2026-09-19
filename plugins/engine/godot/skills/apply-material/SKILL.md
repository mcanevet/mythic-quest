---
name: apply-material
description: Apply visual materials to entities (colors, sprites, shaders, palettes). Use when dressing entities/scenes visually per the VISION.md art style.
---

## What I do

Applies visual materials to existing entities:
- Flat colors / gradients via `modulate`, `self_modulate`, `color` properties
- Procedural art via `GradientTexture2D`, `NoiseTexture2D` for placeholder-quality visuals
- Simple shaders (`shader_type canvas_item`) for effects (outline, glow, dissolve, palette swap)
- Palettes consistent with VISION.md art style direction

## Conventions

- Prefer property-based coloring over file-based textures when possible (fewer assets, faster iteration)
- Place custom shaders in `shaders/` with descriptive names (`entity_outline.gdshader`)
- Encode art-style palette constants in one autoload (`res://scripts/palette.gd`) so all materials share the same vocabulary
- Never break physics/collision while dressing visuals (materials are cosmetic layers)
- Verify visuals render via MCP `take_screenshot` — not just "property set"

## Gotchas

- **Geometry props are unwritable via `batch_scene_operations`** — the batch
  tool serializes array-typed properties (e.g. `Polygon2D.polygon`,
  `PackedVector2Array`) as all-zero arrays while reporting
  `success: true` (mythic-quest-9aw). Two sanctioned escapes: set geometry
  at creation time via the create-scene definitions, or report
  `⛔ BLOCKED: batch tool cannot faithfully write <prop>` and route the
  geometry change to poppy. NEVER improvise `godot_create_scene`
  replacement scenes — that strands cruft files (observed:
  `entities/paddle_fixed.tscn` in wt11).
- **Read back after touching geometry-adjacent props** — zeroed polygons
  are the tell (`get_node_properties` shows all-zero arrays). A successful
  batch write is not evidence the geometry survived.

## Done when

MCP screenshot shows the entity visibly styled per the bead's description, with no script errors in `get_debug_output`.
