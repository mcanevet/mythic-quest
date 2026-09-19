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

- **Entity scene path**: create entity scenes at `entities/<name>.tscn` — NOT
  `scenes/` (that directory holds levels/composite scenes: `scenes/main.tscn`,
  `scenes/levels/<name>.tscn`, `ui/<name>.tscn` for Control roots). Scaffolding
  an entity into the wrong directory strands a stale file that cleanup
  permissions cannot remove (observed once: an orphaned `scenes/ball.tscn` required a
  separate cleanup bead). If an entity
  scene already exists at a wrong path, report it to the orchestrator with the
  correct target path — do not attempt file moves or deletions.

- Player/AI movement → CharacterBody2D
- Physics objects → RigidBody2D
- Triggers/pickups → Area2D
- Identify instanced nodes by groups, not names
- Connect signals explicitly; discrete input in `_input`, not polled

**Sanctioned-paths-only rule**: Scene files are **only** mutated through MCP tools (`create_scene`, `add_node`, `set_node_properties`, `batch_scene_operations`). Direct `.tscn` edits (shell heredocs, text editors, shell scripts) are **not permitted** — if an operation the tools cannot express is required (ext_resource reordering, scene metadata repair), report `⛔ BLOCKED: tool cannot express <operation>` to the orchestrator. Never improvise file-system workarounds. This rule prevents silent corruption and permission-profile violations (observed: heredoc bypasses edit deny).

**Reference files (read the one matching your entity before Step 3):**
- Physics node selection decision tree → [reference/physics-nodes.md](reference/physics-nodes.md)
- Worked examples (player, pickup, projectile — node hierarchies + script skeletons) → [reference/examples.md](reference/examples.md)
- MCP tool usage, error recovery, engine-unresponsive procedures → [reference/mcp-patterns.md](reference/mcp-patterns.md)
- Godot architecture best practices (hierarchy, coupling, autoloads) → [reference/godot-best-practices.md](reference/godot-best-practices.md)
- **Test hooks**: every interactive entity joins `test_exposed` in `_ready()` and exposes `get_test_state() -> Dictionary` — the full contract and scenario schema are in [../init-project/reference/testing-patterns.md](../init-project/reference/testing-patterns.md) § Test Hooks for Entities

## Gotchas

Empirically observed godot-mcp-runtime schema quirks. The full annotated failure list with evidence citations lives in [reference/gotchas.md](reference/gotchas.md). Verify each before closing a task:

- **Colors**: pass `{r, g, b, a}` objects with floats 0–1, not hex strings. `"#1b2a41"` fails; use `{r: 27/255, g: 42/255, b: 65/255, a: 1}`.
- **Scripts**: pass plain `res://` path strings (e.g. `"res://scripts/station.gd"`), not nested objects.
- **Scene root name**: verify the root node name via `godot_get_scene_tree` before writing scripts that reference node paths like `/root/Main/Lamp` — the root name may differ from the scene filename.
- **Polygon2D**: the `polygon` property takes an array of `{x, y}` points.
- **Overlap queries**: `Area2D.get_overlapping_bodies()` won't detect non-physics placeholder nodes; iterate children instead when entities are `Node2D` placeholders.
- **Batch scene operations**: malformed or loosely-formatted JSON payloads fail; keep JSON compact and canonical.
- **Running engine overwrites scene files**: a live `run_project`/playtest serializes runtime state back into `.tscn` files, clobbering concurrent edits. MANDATORY: call `godot_stop_project` BEFORE any scene-file edit (create/edit/save), and only restart the engine after the edit round completes.
- **`:=` type inference in run_script**: `var x := dict.get("k", d)` fails with "cannot infer the type" — use untyped `var x = ...` or explicit `var x: int = ...` in dynamically submitted scripts (also the largest compile-error class observed in a full run: 14 occurrences).
- **Batch-validation economics**: when verifying multiple entities, run one
  `validate.sh` per logical unit (not per file). Godot's headless boot
  caches imports; repeated boots waste 15–30s each with zero added value.
  Group validations by scene dependency (observed: 14 type-inference parse
  errors concentrated in one batch-validation run).

**Signal wiring**: use `verify_node_connections` instead of manual 4-point
checks (upstream status: released on the pinned combo branch
`combo/mythic-quest-integration`, PRs #45–#47; retire the manual procedure
when a tagged upstream release ships the tool). See
[reference/signals.md](reference/signals.md) for the manual path.

## Test scenario contract (creator-authored)

You wrote the entity — you write its test contract, not QA. For every
interactive entity, author `tests/scenarios/<entity_name>.json` using the
canonical schema in [../init-project/reference/testing-patterns.md](../init-project/reference/testing-patterns.md):

- Start from the canonical scenario schema; add a `custom` invariant per
  game-specific behavior (requires `get_test_state()` on the entity)
- **Never invent a `rule` name** — an unknown rule is silently ignored by the
  harness (passes while checking nothing). Use only the canonical invariant
  rules list in testing-patterns.md
- This file is a functional contract: `playtest`'s `functional` mode globs
  `tests/scenarios/*.json` and merges these invariants into the final QA
  scenario — entity-specific correctness gets checked at final QA because
  you declared it here, at creation time. QA verifies against this contract;
  the creator authors it.

## Done when

`scripts/validate.sh <res://scenes/....tscn>` (in this skill) runs without
errors — it wraps `godot --headless <scene> --quit-after 1` — AND test hooks
respond AND the entity is integrated into its parent scene (an entity not
in the scene tree is dead code — integrate via `add_node` under the
project's Main scene at the plan-specified node path, then confirm via
`get_scene_tree()` that it appears under its parent). Before runtime
verification, also run `scripts/validate.sh` with **no argument** — the
headless project-boot mode (legacy `headless_check.sh` equivalent) catches
script parse errors across the whole project that single-scene loading
misses. AND `tests/scenarios/<entity_name>.json` exists for interactive
entities (see _Test scenario contract_ above).
