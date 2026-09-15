# Godot Best Practices — Curated Reference

> **Attribution:** Distilled and synthesized from the official Godot Engine documentation
> (Best Practices series), https://docs.godotengine.org/en/stable/tutorials/best_practices/ —
> © Juan Linietsky, Ariel Manzur and contributors, licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
> This file is a paraphrase for agent use, not a copy. Source pages: `scene_organization`,
> `godot_interfaces`, `godot_notifications`, `logic_preferences`, `scenes_versus_scripts`,
> `autoloads_versus_regular_nodes`, `node_alternatives`, `project_organization`.
>
> **This is Godot-fork content.** Engine-agnostic decisions belong in the agents; everything
> here is the Godot implementation layer.

## 1. Scene Organization & Hierarchy

Design hierarchies relationally, not spatially. A node should be a child of another only if
it *is a part of* that parent — removing the parent must conceptually remove the child.
Trees built around visual grouping (e.g. everything at `(0,0)`) break when a node moves.

- Use a canonical top-level split per level/UI screen:
  - `Main` — persistent orchestration (level lifecycle, state)
  - `World` — instanced and swapped when the level changes
  - `GUI` — overlays/HUD, independent of the World
- Keep one scene self-contained (own visuals + logic + UI). Split only when the plan
  requires it (e.g. a pause screen that must persist, a reusable in-world object).
- Instantiate (`PackedScene.instantiate()`) rather than duplicate node trees by hand.
  One instanced scene is the single source of truth; a hand-copied tree is a new source of truth.
- Nodes that must outlive a swapped World (player stats, camera) live in `Main`, not `World`.
- For worlds that swap content in/out: instance the new world under `Main`, queue-free the old.
- `top_level` or `RemoteTransform` only for effects that visually trail a parent without
  inheriting its transform (VFX/particles attached to a moving character).

## 2. Loose Coupling (Dependency Injection Ladder)

When `A` must trigger/notify `B`, pick the weakest link that works — in this order:

1. **Signal** — `B` emits (past-tense verb: `item_collected`), `A` connects. Best when one
   thing happened and several listeners respond.
2. **Method call** — direct call for behavior the target owns (`start_jump()`).
3. **`Callable` property** — inject a callback; target stays unaware of the caller's identity.
4. **Node reference** — `@export var` or set via `get_node()`. Only after signals/offsets fail.
5. **NodePath** — textual, weakest; resolve at runtime.

Validation is done by the *consumer* (`A`), not the provider: assert the injected dependency
exists in `_ready()` (`assert(target != null)` or log a clear error) so a broken wiring fails
loudly at scene load instead of silently later.

Groups are a convention layer, not a coupling free-pass — only use when several nodes share
a behavior with no single owner (e.g. `add_to_group("collectibles")`), never to reach *one*
specific node.

## 3. Referencing Nodes Correctly

Preference order for acquiring a node reference:

1. `@onready var label: Label = $Label` — use this by default.
2. `@export var target: Node` — for cross-scene wiring assigned in the editor/scene.
3. `get_node("Path")` / `get_node_or_null(...)` — dynamic paths, handle null.
4. Autoload by name — global singleton access (see §5).

Rules:
- `$Path` syntax and scene paths are relative to the current node.
- Store references in `@onready` once at load; do not re-query every frame.
- Never resolve the same path repeatedly in `_process`/`_physics_process`.
- Use groups for multi-target fan-out, not for reaching a named singleton.

## 4. Scenes vs Scripts

- **Scene** (`.tscn`): game-specific concepts with a visible/solvable structure — entities,
  levels, UI panels. Root node + `class_name`/`extends` gives it type identity too.
- **Script-only** (`class_name`, no node): reusable computation/tools with no scene needs —
  math helpers, data tables, RNG wrappers. No Node overhead.
- Reuse: a concept reused in many builds belongs in its own scene/script (`class_name`)
  rather than being re-authored per use. `preload()` the reused resource once.
- Performance: instancing a `PackedScene` beats hand-allocating its node tree; prefer scene
  instances when the plan shows repeated use.

## 5. Autoloads vs Regular Nodes

Autoloads are global singletons — convenient but a reflex that fights the node tree:

- Prefer scene-local nodes (e.g. a `Music` node child of an in-scene root) over an
  autoload for anything that only the scene needs.
- Prefer `class_name` + static functions for pure helper logic
  (`class_name WaveUtils`, `static func sine(...)`) — no autoload needed.
- **Autoloads are only justified when:** the system is genuinely global *and* manages its
  own data/state (e.g. a quest/dialogue database, the test harness `TestPlayer`), and almost
  every scene needs it.
- An autoload instantiated once is not a singleton by nature — guard against accidental
  duplication when designing.
- Keep autoload nodes lean; push processing into normal scenes where possible.

## 6. Node Alternatives (Don't Optimize Nodes Prematurely)

`Node` is the heaviest object. If a concept is pure data or computation, don't force a node:

- `Resource` — config/datasets (dict-accessible, shared between scenes).
- `RefCounted` — self-managed ephemeral objects (commands, one-shot tasks).
- `Object` — bare signal emitter (camera reactions, game-state announcements).
- Plain `Array`/`Dictionary` — local data.

Rule of thumb: if it has no scene position, no children, and needs no `_process`, it belongs
in a plain object, not in the tree. Measure before over-refactoring; do not pre-emptively
replace nodes when a scene count stays small.

## 7. Lifecycle & Process Logic

Call-order matters — placing logic in the wrong callback is a latent bug:

- `_init()` — member setup only, runs on `instantiate()`/`new()`, tree not ready.
- `_enter_tree()` → `_ready()` — one-shot setup; children exist, export vars assigned.
  Do network/physics-dependent setup in `_ready()`, and `call_deferred` heavy work that must
  run after siblings (`_await_ready` patterns) when order is uncertain.
- Set node properties *before* `add_child` where possible — the parent triggers `_enter_tree`
  immediately, and a node whose later-added sibling dependencies aren't set yet breaks.
- `NOTIFICATION_PARENTED` — for dynamically spawned child logic that must run immediately at
  `add_child` (data nodes being parented mid-frame), hook it here rather than polling.

Frame callbacks:

- `_process(delta)` — visual/input-derived logic and anything that must tick every rendered
  frame (UI animation, camera smoothing). Ties to render rate.
- `_physics_process(delta)` — physics, `move_and_slide`, and anything the physics engine
  needs to see in fixed steps. The harness invariants read these — keep test-relevant state
  mutations here.
- Input callbacks (`_input`, `_unhandled_input`) — separate from process loops; don't poll
  `Input.is_action_pressed` when an event callback fits.

Choose *one* based on what the logic depends on; do not duplicate logic in both.

## 8. Resource & Project Organization

- `preload()` vs `load()`: `preload` for resources referenced in the same script (checked at
  parse time, loaded eagerly); `load` for paths chosen at runtime (optional/lazy). Don't
  preload what may not exist.
- File/dir names: `snake_case` for files and directories; node names `PascalCase`; class names
  `PascalCase`. Consistent — the skills' validators and the plan's DoD check these.
- Third-party code goes under `addons/` (an import-reserved folder), not scattered.
- Hidden/scratch folders that Godot should not import: add a `.gdignore` file inside them.
- `.gitignore` must exclude `.godot/` (see setup-project Step 3) — never commit the cache.
- Keep the `Main` scene minimal and let levels/UI be instances off it, so a broken component
  fails in isolation and `run/main_scene` boot stays fast.

---

## Quick Decision Help

| Want … | Use |
|---|---|
| One-shot event, many listeners | Signal |
| Have one node act on another | Method call → Callable → ref → NodePath |
| Reused computation, no scene | `class_name` + static func |
| Global data every scene needs | Autoload (only then) |
| Global-ish helper that needs no instance | `class_name` static |
| Pure data/state | Resource / RefCounted |
| Per-frame visual | `_process` |
| Fixed-step physics/test-relevant | `_physics_process` |
| Something owned by one scene only | Scene-local node, not autoload |