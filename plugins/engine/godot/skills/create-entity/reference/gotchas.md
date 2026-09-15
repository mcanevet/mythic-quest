# Gotchas — Annotated Failure Catalog

> Every entry records an observed real-build failure. Read fully when a triggered gotcha
> blocks you, or when authoring "on hit" effects (re-fire gotcha). This file is
> failure-knowledge, not a to-do list — the SKILL.md checklist links here.

## Instanced node identification
Never identify instanced nodes by `.name` — only the first PackedScene instance keeps its root name. Use groups (`add_to_group("collectibles")`) or type checks instead.

## Unconnected emitted signals
A signal defined and emitted but never connected silently does nothing. Verify every emitted signal has a connection (see SKILL.md Step 5b).

## AudioStreamPlayer ordering
Call `play()` before `get_stream_playback()`, not after.

## Input action names
Use Input action names (`Input.is_action_pressed("move_left")`), never raw key codes.

## Test/QA infrastructure cleanup
Clean up test/QA infrastructure (e.g. `TestPlayer` autoload) before shipping.

## Continuous-contact re-fire (critical)
A collision handler that emits signals or mutates state fires *every physics tick the contact persists* — `move_and_collide` keeps reporting the same contact until the bodies actually separate. A positional "nudge out of penetration" alone often does NOT separate (the next `move_and_collide` still finds the collider).

Guard every "on hit" effect (score, damage, pickups, spawn-on-contact) with a re-fire condition:
- minimum time since last hit on this collider, or
- a separation check (`!move_and_collide` no longer hits the same collider), or
- a state flag cleared on separation

**Verification:** simulate a stationary perfect-contact situation (actor held on the collider for ≥1s) and confirm the effect fires once, not per-tick.

*Rationale:* a paddle-hit score handler re-fired ~68×/sec during contact — a scripted perfect player won the game on one catch (score 0→15 in 0.22s). Caught only by human play; motivated the `max_delta_per_sec` invariant rule in `setup-project/reference/testing-patterns.md`.

## Integration is not optional
An entity that exists as a script/scene but is not added to its parent/main scene is dead code. Verify it in the running scene tree before declaring done (SKILL.md Step 4b).

## Discrete input events
(key press, click) belong in `_input`/`_unhandled_input` or a connected signal — polling `Input.is_key_pressed` in `_process` for a one-shot event (e.g. ESC pause) silently misses it. See [godot-best-practices.md](godot-best-practices.md) §7.

## Never save scene files during a live run
A live engine session serializes runtime node state (positions, velocities) into the scene file. Stop the project first; if entities were mutated during testing, reset them to default values before any save.

## Generated tooling scripts live in `tools/`
Generated asset/tooling scripts belong in the game project's `tools/` directory, never in `.opencode/skills/**` or `skills/**` — those paths are harness code (write-denied anyway). A task needing a throwaway generator (asset importer, SFX synthesizer, format converter) writes it to `tools/` inside the consumer project.

*Observed:* an SFX task wrote 7 helper scripts into a skill directory and burned ~5 minutes writing cleanup scripts to remove them.

## Script edits under a running engine serve stale bytecode
A running Godot process caches compiled script bytecode. Editing a `.gd` file while the engine runs means the live process keeps reporting the OLD errors at OLD line numbers — including parse errors already fixed. Symptom: you edit a file, the reported error still points at the pre-edit line contents or names an identifier you already renamed (an agent can burn 5+ steps hunting a nonexistent second bug before guessing "cached bytecode"). Fix: `stop_project()` → relaunch → re-register autoload → re-validate. If the reported error doesn't match current file contents, do not debug the file — restart the engine first.

## .tscn section order: ext_resource must precede sub_resource
In a Godot scene file, `[ext_resource]` blocks must come BEFORE `[sub_resource]` blocks. This matters only if a direct `.tscn` hand-edit ever happens off-harness (resource-typed properties go through the MCP tools now — see SKILL.md Step 5a; direct .tscn edit is denied, ⛔ BLOCKED): appending a sub_resource above an existing ext_resource or splicing blocks out of order makes the scene fail to load with `Unknown tag 'ext_resource' in file` even though every individual block is well-formed. Canonical order: `[gd_scene]` header → all `[ext_resource]` → all `[sub_resource]` → `[node]` blocks. *Case:* paddle integration into main.tscn once put ext_resource after sub_resource; validate caught it; fix was a pure reordering, no content change. When this exact error appears after a manual sub_resource edit, check block ORDER first, not block contents.

## run_script node paths: root is the autoload container, your scene is one level down
`run_script` code executes against the SceneTree. The tree root (`/root`) contains autoloads (GameManager, McpBridge, TestPlayer) and your main scene's root node as a CHILD — a main scene whose root node is named `root` yields `/root/root/<Entity>`. Two recurring mistakes (each burns several probe round-trips): (1) calling `get_node_or_null` on the SceneTree itself — it is a Node method, call it on a node (e.g. `get_tree().get_root()`); (2) assuming the entity is a direct child of the tree root. Verify the actual path with `get_scene_tree` once, then hard-code the verified path in probes.

## End-of-round transitions: snapshot + edge-triggered restart + always-sample input (one recipe)
End screens (game-over/win) are a three-part compound trap; each part alone seems fine and ships, then QA discovers the missing third at the worst time. From run 12 (benchmarks/results/2026-09-09-rallywall-lumo-max-medium-shipped-run12.md, bugfix plans 15/17/18 — three separate rework cycles on one end-screen flow):
1. **Snapshot the score at transition time.** If an end screen renders the live mutable counter, a restart (or throttled idle frame) zeroes it before paint — "Final score: 0". Store `final_score` immutably inside `game_over()`/`win()` before ANY state reset; screens render the snapshot, never the live counter.
2. **Edge-trigger + grace the restart key.** Polling `Input.is_key_pressed` with no edge detection restarts on keys held ACROSS the death frame — instant reset, invisible loss screen. Require a rising edge (fresh press) AND a short post-transition grace (~0.25s) before restart is honored.
3. **Sample the key every frame even while gated.** If the edge detector itself sits behind the grace gate, a press landing during grace is never sampled; when grace expires, the still-held key reads as a fresh edge (fabricated restart). Structure it as: always run the sampler, gate only the emit:
   ```gdscript
   var edge := _sample_restart_edge()   # ALWAYS — keeps _restart_held tracking reality
   if visible and not manager.is_restart_gated() and edge:
       restart_requested.emit()
   ```
Also: decide win/loss in the AUTHORITATIVE event path (e.g. on the score-updated signal, in the same physics callback chain), never in a `_process` poll — physics callbacks run before `_process`, so a ball-out signal on the win frame can preempt the win poll and paint GAME OVER at the winning score (run 12 bugfix 17).
